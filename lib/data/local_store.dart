// Offline-first local store (Hive: IndexedDB on web, files on Android/iOS).
//
// Every record is kept exactly as its database row (same column names), so the
// sync layer can send it as-is. Each save writes the row and an outbox entry;
// the screen updates straight away and the outbox is pushed when online.
import 'dart:typed_data';

import 'package:hive_ce/hive.dart';

/// Tables the mother app keeps on the phone.
const syncedTables = [
  'profiles',
  'consents',
  'pregnancies',
  'babies',
  'checkins',
  'bp_readings',
  'growth_measures',
  'feeds',
  'milestones',
  'vaccine_doses',
  'appointments',
  'medications',
  'journal_entries',
  'visit_questions',
  'birth_plans',
  'lesson_views',
];

/// Insert-only health events: never edited, duplicates ignored on the server.
const eventTables = {'checkins', 'bp_readings', 'growth_measures', 'feeds', 'consents'};

/// Tables kept only on the phone and never sent to the server.
const localOnlyTables = <String>{};

Map<String, dynamic> asMap(dynamic v) =>
    v == null ? <String, dynamic>{} : Map<String, dynamic>.from((v as Map).map((k, x) => MapEntry(k.toString(), _plain(x))));

dynamic _plain(dynamic x) {
  if (x is Map) return asMap(x);
  if (x is List) return x.map(_plain).toList();
  return x;
}

/// Key for a row: `id`, or the composite key for tables without one.
String rowKey(String table, Map<String, dynamic> row) => switch (table) {
  'milestones' => '${row['baby_id']}:${row['milestone_key']}',
  'lesson_views' => '${row['lesson_id']}',
  'profiles' => 'me',
  _ => '${row['id']}',
};

class OutboxEntry {
  final int key;
  final String table, op, id;
  final Map<String, dynamic> row;
  final int tries;
  final String? nextAt, error;
  OutboxEntry(this.key, Map<String, dynamic> m)
    : table = m['table'] as String,
      op = m['op'] as String,
      id = m['id'] as String,
      row = asMap(m['row']),
      tries = (m['tries'] ?? 0) as int,
      nextAt = m['next_at'] as String?,
      error = m['error'] as String?;
}

class LocalStore {
  late Box _meta, _outbox, _dead;
  final Map<String, Box> _rec = {};
  bool _open = false;

  /// [path] is used in tests and on desktop; Flutter apps call Hive.initFlutter first.
  /// [inMemory] keeps everything in memory (widget tests).
  Future<void> open({String? path, bool inMemory = false}) async {
    if (_open) return;
    if (path != null) Hive.init(path);
    Future<Box> box(String n) => inMemory ? Hive.openBox(n, bytes: Uint8List(0)) : Hive.openBox(n);
    _meta = await box('sym_meta');
    _outbox = await box('sym_outbox');
    _dead = await box('sym_dead');
    for (final t in syncedTables) {
      _rec[t] = await box('sym_$t');
    }
    _open = true;
  }

  // ---------- settings ----------
  T? meta<T>(String k, [T? fallback]) {
    final v = _meta.get(k);
    if (v == null) return fallback;
    if (v is Map) return asMap(v) as T;
    if (v is List) return v.map(_plain).toList() as T;
    return v as T;
  }

  Future<void> setMeta(String k, Object? v) => v == null ? _meta.delete(k) : _meta.put(k, v);

  // ---------- records ----------
  Map<String, dynamic>? get(String table, String key) {
    final v = _rec[table]!.get(key);
    return v == null ? null : asMap(v);
  }

  /// All rows of a table, without soft-deleted ones.
  List<Map<String, dynamic>> all(String table, {bool withDeleted = false}) =>
      _rec[table]!.values.map(asMap).where((r) => withDeleted || r['deleted_at'] == null).toList();

  /// Save locally and queue for the server. [op]: upsert | update | delete.
  /// For `update`, [push] is the patch sent (defaults to the whole row).
  Future<void> save(String table, Map<String, dynamic> row, {String op = 'upsert', Map<String, dynamic>? push}) async {
    final key = rowKey(table, row);
    await putLocal(table, row);
    if (localOnlyTables.contains(table)) return;
    await queue(table, op, key, push ?? row);
  }

  Future<void> putLocal(String table, Map<String, dynamic> row) => _rec[table]!.put(rowKey(table, row), row);

  Future<void> queue(String table, String op, String id, Map<String, dynamic> row) => _outbox.add({'table': table, 'op': op, 'id': id, 'row': row, 'tries': 0});

  /// Store a row that came from the server (no outbox entry).
  Future<void> putFromServer(String table, Map<String, dynamic> row) => putLocal(table, row);

  Future<void> removeLocal(String table, String key) => _rec[table]!.delete(key);

  // ---------- outbox ----------
  List<OutboxEntry> outbox() => _outbox.keys.map((k) => OutboxEntry(k as int, asMap(_outbox.get(k)))).toList()..sort((a, b) => a.key.compareTo(b.key));

  int get pendingCount => _outbox.length;

  /// True while a row has not reached the server yet.
  bool isPending(String table, String key) => outbox().any((e) => e.table == table && e.id == key);

  /// Forget a row that never reached the server (local copy and outbox entries).
  Future<void> dropUnsynced(String table, String key) async {
    for (final e in outbox().where((e) => e.table == table && e.id == key)) {
      await _outbox.delete(e.key);
    }
    await _rec[table]!.delete(key);
  }

  /// Point every local row and queued row from one parent id to another (e.g. this phone's
  /// unsynced pregnancy → the pregnancy already on the server).
  Future<void> remapField(String field, String from, String to) async {
    for (final b in _rec.values) {
      for (final k in b.keys.toList()) {
        final r = asMap(b.get(k));
        if (r[field] == from) await b.put(k, {...r, field: to});
      }
    }
    for (final e in outbox()) {
      if (e.row[field] == from) {
        final m = asMap(_outbox.get(e.key));
        m['row'] = {...e.row, field: to};
        await _outbox.put(e.key, m);
      }
    }
  }

  int get deadCount => _dead.length;
  List<Map<String, dynamic>> deadLetters() => _dead.values.map(asMap).toList();

  Future<void> done(OutboxEntry e) => _outbox.delete(e.key);

  Future<void> retryLater(OutboxEntry e, Duration wait, String error) {
    final m = asMap(_outbox.get(e.key));
    m['tries'] = e.tries + 1;
    m['next_at'] = DateTime.now().add(wait).toIso8601String();
    m['error'] = error;
    return _outbox.put(e.key, m);
  }

  /// A 4xx from the server: keep the item aside and show it in Profile → Sync.
  Future<void> moveToDead(OutboxEntry e, String error) async {
    final m = asMap(_outbox.get(e.key))..['error'] = error;
    await _dead.add(m);
    await _outbox.delete(e.key);
  }

  Future<void> clearDead() => _dead.clear();

  /// Everything the mother has on this phone, for "download my data".
  Map<String, dynamic> export() => {'exported_at': DateTime.now().toUtc().toIso8601String(), for (final t in syncedTables) t: all(t)};

  /// Logout or delete-my-data: wipe the phone copy.
  Future<void> wipe() async {
    await _meta.clear();
    await _outbox.clear();
    await _dead.clear();
    for (final b in _rec.values) {
      await b.clear();
    }
  }
}
