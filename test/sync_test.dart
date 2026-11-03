import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:safari_ya_mama/core/dates.dart';
import 'package:safari_ya_mama/data/local_store.dart';
import 'package:safari_ya_mama/data/remote.dart';
import 'package:safari_ya_mama/data/sync_service.dart';
import 'package:safari_ya_mama/state/app_state.dart';

import 'fakes.dart';

void main() {
  late Directory dir;
  late LocalStore store;
  late FakeRemote remote;
  late AppState s;
  final clock = DateTime(2026, 11, 2, 10);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('symsync');
    store = LocalStore();
    await store.open(path: dir.path);
    remote = FakeRemote();
    s = AppState(store, remote: remote, clock: () => clock);
    await s.completeOnboarding(name: 'Amina', stage: 'pregnant', lmp: addDays(sod(clock), -196));
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('outbox pushes in order, batches events, adds mother_id and strips server-owned columns', () async {
    for (var i = 0; i < 3; i++) {
      await s.submitCheckin(s.checkinInput(feeling: 'well'));
    }
    final r = await SyncService(store, remote).run(now: clock);
    expect(r.ok, isTrue, reason: r.error);
    expect(r.pushed, 4);
    expect(remote.calls.where((c) => c.startsWith('upsert')), ['upsert pregnancies 1', 'upsert checkins 3 ignore']);
    final ck = remote.tables['checkins']!.values.first;
    expect(ck['mother_id'], 'mother-1');
    expect(ck.keys.where((k) => k.startsWith('_')), isEmpty, reason: 'local-only fields never leave the phone');
    expect(store.pendingCount, 0);
  });

  test('sending the same check-in twice makes one row (ignore duplicates)', () async {
    await s.submitCheckin(s.checkinInput());
    final row = s.checkins.single;
    await store.queue('checkins', 'upsert', row['id'] as String, row);
    await SyncService(store, remote).run(now: clock);
    expect(remote.tables['checkins']!.length, 1);
  });

  test('network error keeps the item and backs off 30 s; permanent error goes to dead letters', () async {
    await s.submitCheckin(s.checkinInput());
    remote.failNext = RemoteError('offline');
    remote.failTimes = 1;
    var r = await SyncService(store, remote).run(now: clock);
    expect(r.ok, isFalse);
    expect(store.pendingCount, 2);
    final e = store.outbox().first;
    expect(e.tries, 1);
    expect(DateTime.parse(e.nextAt!).difference(DateTime.now()).inSeconds, inInclusiveRange(25, 31));
    // later, a validation error
    remote.failNext = RemoteError('23514: check violation', permanent: true);
    remote.failTimes = 2; // the batch, then the same row on its own
    r = await SyncService(store, remote).run(now: DateTime.now().add(const Duration(minutes: 1)));
    expect(store.deadCount, 1);
    expect(store.pendingCount, 0);
  });

  test('pull keeps the server level and does not overwrite a newer local edit', () async {
    await s.submitCheckin(s.checkinInput(signs: {'headache'}));
    final ck = s.checkins.single;
    await SyncService(store, remote).run(now: clock);
    remote.pullRows['checkins'] = [
      {...ck, 'server_level': 'red', 'created_at': '2026-11-02T07:00:01Z'},
    ];
    final p = s.pregnancy!;
    remote.pullRows['pregnancies'] = [
      {...p, 'gravida': 9, 'updated_at': '2000-01-01T00:00:00Z'},
    ];
    remote.pullRows['appointments'] = [
      {
        'id': 'a1',
        'kind': 'anc',
        'contact_no': 4,
        'due_on': isoDay(addDays(sod(clock), 14)),
        'attended_on': null,
        'note': 'Bring your card',
        'updated_at': '2026-11-02T07:00:00Z',
      },
    ];
    await SyncService(store, remote).run(now: clock);
    expect(s.levelOf(s.checkins.single).name, 'red');
    expect(s.serverRaised, isNotNull);
    expect(s.pregnancy!['gravida'], isNull, reason: 'older server copy ignored');
    expect(s.ancVisits[3].note, 'Bring your card');
    expect(s.ancVisits[3].due, addDays(sod(clock), 14));
  });

  test('vaccine ticks made before the schedule synced are sent once it arrives', () async {
    await s.recordBirth(dob: addDays(sod(clock), -2), name: 'Zuri');
    await s.setVaccineGiven('bcg', true);
    await s.syncNow();
    final bid = s.baby!['id'];
    remote.pullRows['vaccine_doses'] = [
      {'id': 'vx-bcg', 'baby_id': bid, 'vaccine_key': 'bcg', 'due_on': isoDay(s.dob!), 'given_on': null, 'updated_at': '2026-11-02T07:00:00Z'},
    ];
    await s.syncNow();
    expect(store.outbox().where((e) => e.op == 'update' && e.table == 'vaccine_doses').length, 1);
    await s.syncNow();
    expect(remote.calls, contains('update vaccine_doses vx-bcg'));
  });
}
