// Offline sync contract (resources/BACKEND_SCHEMA.md → "Offline sync contract").
//  1. Every save is already on the phone (LocalStore.save) with a phone-made UUID.
//  2. Push the outbox oldest first, in batches of up to 50 per table:
//       health events  → upsert, ignore duplicates (a resend does nothing)
//       editable rows  → upsert, merge; the server's *_touch trigger keeps the newer updated_at
//       vaccine doses  → update by id;  deletes → rpc delete_record
//  3. An item leaves the outbox only after success. Permanent errors (validation, permission)
//     go to the dead-letter list shown in Profile → Sync; network errors retry with backoff
//     30 s, 2 min, 10 min, then hourly.
//  4. Pull rows changed since the last cursor and keep the server's server_level.
import 'local_store.dart';
import 'remote.dart';

/// Column used as the pull cursor for each table.
const pullCursor = {
  'profiles': 'updated_at',
  'consents': 'created_at',
  'pregnancies': 'updated_at',
  'babies': 'updated_at',
  'checkins': 'created_at',
  'bp_readings': 'created_at',
  'growth_measures': 'created_at',
  'feeds': 'created_at',
  'milestones': 'updated_at',
  'vaccine_doses': 'updated_at',
  'appointments': 'updated_at',
  'medications': 'updated_at',
  'journal_entries': 'updated_at',
  'visit_questions': 'updated_at',
  'birth_plans': 'updated_at',
  'lesson_views': 'viewed_at',
};

/// Columns the server owns; never sent from the phone.
const _serverOwned = {'edd', 'server_level', 'created_at'};

const _onConflict = {'milestones': 'baby_id,milestone_key', 'lesson_views': 'mother_id,lesson_id'};

Duration backoffFor(int tries) => switch (tries) {
  0 => const Duration(seconds: 30),
  1 => const Duration(minutes: 2),
  2 => const Duration(minutes: 10),
  _ => const Duration(hours: 1),
};

class SyncResult {
  final int pushed, pulled, failed;
  final String? error;
  const SyncResult({this.pushed = 0, this.pulled = 0, this.failed = 0, this.error});
  bool get ok => error == null;
}

class SyncService {
  final LocalStore store;
  final RemoteApi remote;
  bool _running = false;
  SyncService(this.store, this.remote);

  /// [pullFirst] is used on the first sync after sign-in, so a returning mother's server
  /// record is merged before anything from this phone is sent.
  Future<SyncResult> run({DateTime? now, bool pullFirst = false}) async {
    final uid = remote.userId;
    if (uid == null) return const SyncResult(error: 'not signed in');
    if (_running) return const SyncResult(error: 'already running');
    _running = true;
    try {
      var pulled = pullFirst ? await _pull() : 0;
      final push = await _push(uid, now ?? DateTime.now());
      // a network error stops here; items waiting for backoff still let us pull fresh server levels
      if (push.error != null && push.error != waiting) return push;
      if (!pullFirst) pulled = await _pull();
      await store.setMeta('last_sync', DateTime.now().toUtc().toIso8601String());
      return SyncResult(pushed: push.pushed, failed: push.failed, pulled: pulled, error: push.error);
    } on RemoteError catch (e) {
      return SyncResult(error: e.message);
    } finally {
      _running = false;
    }
  }

  static const waiting = 'waiting to retry';

  /// Pull only (first step after sign-in on a phone that may hold a returning mother's data).
  Future<int> pullOnly() async => remote.userId == null ? 0 : _pull();

  Map<String, dynamic> _forServer(String table, Map<String, dynamic> row, String uid) {
    final r = Map<String, dynamic>.from(row)..removeWhere((k, _) => k.startsWith('_') || _serverOwned.contains(k));
    if (table == 'profiles') {
      r['id'] = uid;
      r.remove('role');
    } else {
      r['mother_id'] = uid;
    }
    return r;
  }

  Future<SyncResult> _push(String uid, DateTime now) async {
    var pushed = 0, failed = 0;
    // the profile goes first: every other row points to it
    final all = store.outbox();
    final items = [...all.where((e) => e.table == 'profiles'), ...all.where((e) => e.table != 'profiles')];
    var i = 0;
    while (i < items.length) {
      final e = items[i];
      if (e.nextAt != null && DateTime.parse(e.nextAt!).isAfter(now)) {
        // waiting for backoff: keep order, stop here
        return SyncResult(pushed: pushed, failed: failed, error: waiting);
      }
      // batch consecutive upserts of the same table and kind
      final batch = <OutboxEntry>[e];
      if (e.op == 'upsert' || e.op == 'upsert_ignore') {
        while (i + batch.length < items.length && batch.length < 50) {
          final n = items[i + batch.length];
          if (n.table != e.table || n.op != e.op || n.nextAt != null) break;
          batch.add(n);
        }
      }
      try {
        await _send(e.table, e.op, batch, uid);
        for (final b in batch) {
          await store.done(b);
        }
        pushed += batch.length;
      } on RemoteError catch (err) {
        if (!err.permanent) {
          await store.retryLater(e, backoffFor(e.tries), err.message);
          return SyncResult(pushed: pushed, failed: failed, error: err.message);
        }
        // one bad row must not take the others (e.g. a red check-in) down with it: retry singly
        for (final b in batch) {
          try {
            await _send(b.table, b.op, [b], uid);
            await store.done(b);
            pushed++;
          } on RemoteError catch (one) {
            if (!one.permanent) {
              await store.retryLater(b, backoffFor(b.tries), one.message);
              return SyncResult(pushed: pushed, failed: failed, error: one.message);
            }
            await store.moveToDead(b, one.message);
            failed++;
          }
        }
      }
      i += batch.length;
    }
    return SyncResult(pushed: pushed, failed: failed);
  }

  Future<void> _send(String table, String op, List<OutboxEntry> batch, String uid) async {
    final e = batch.first;
    switch (op) {
      case 'upsert':
      case 'upsert_ignore':
        // the latest copy of each row wins inside a batch
        final rows = <String, Map<String, dynamic>>{};
        for (final b in batch) {
          rows[b.id] = _forServer(table, b.row, uid);
        }
        await remote.upsert(
          table,
          rows.values.toList(),
          ignoreDuplicates: op == 'upsert_ignore' || eventTables.contains(table),
          onConflict: _onConflict[table],
        );
      case 'update':
        final patch = Map<String, dynamic>.from(e.row)..removeWhere((k, _) => k == 'id' || k.startsWith('_'));
        await remote.update(table, e.id, patch);
      case 'delete':
        await remote.rpc('delete_record', {'p_table': table, 'p_id': e.id});
    }
  }

  Future<int> _pull() async {
    var n = 0;
    final cursors = store.meta<Map<String, dynamic>>('cursors', {})!;
    for (final t in syncedTables) {
      final col = pullCursor[t]!;
      final rows = await remote.pullSince(t, col, cursors[t] as String?);
      for (final r in rows) {
        final key = rowKey(t, r);
        final local = store.get(t, key);
        final editable = !eventTables.contains(t);
        if (editable &&
            local != null &&
            local['updated_at'] != null &&
            r['updated_at'] != null &&
            DateTime.parse(local['updated_at'] as String).isAfter(DateTime.parse(r['updated_at'] as String))) {
          continue; // our newer copy is still waiting in the outbox
        }
        await store.putFromServer(t, {...?local, ...r});
        final v = r[col];
        if (v is String && (cursors[t] == null || v.compareTo(cursors[t] as String) > 0)) cursors[t] = v;
        n++;
      }
    }
    await store.setMeta('cursors', cursors);
    return n;
  }
}
