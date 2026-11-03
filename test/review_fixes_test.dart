// Regression tests for issues found in code review (sync ordering, consent truthfulness,
// clinic switching, birth linkage, today's most urgent level, returning mothers, assistant routing).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:safari_ya_mama/core/assistant.g.dart';
import 'package:safari_ya_mama/core/content.dart';
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
    dir = await Directory.systemTemp.createTemp('symfix');
    store = LocalStore();
    await store.open(path: dir.path);
    remote = FakeRemote()..uid = null;
    s = AppState(store, remote: remote, clock: () => clock);
  });
  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('records made before sign-in sync after it, profile first', () async {
    await s.completeOnboarding(name: 'Amina', stage: 'pregnant', lmp: addDays(sod(clock), -196));
    await s.submitCheckin(s.checkinInput(signs: {'bleeding'}));
    await s.verifyCode('+255700000101', '123456');
    final ups = remote.calls.where((c) => c.startsWith('upsert')).toList();
    expect(ups.first, startsWith('upsert profiles'));
    expect(ups, containsAll(['upsert pregnancies 1', 'upsert checkins 1 ignore']));
    expect(store.pendingCount, 0);
    expect(store.deadCount, 0);
  });

  test('a foreign-key error is retried later, never dead-lettered', () async {
    remote.uid = 'mother-1';
    await s.addJournal('x');
    remote.failNext = RemoteError('23503: foreign key', permanent: false);
    remote.failTimes = 1;
    await SyncService(store, remote).run(now: clock);
    expect(store.deadCount, 0);
    expect(store.pendingCount, 1);
  });

  test('one bad row in a batch does not dead-letter the others', () async {
    remote.uid = 'mother-1';
    await s.completeOnboarding(name: 'A', stage: 'pregnant', lmp: addDays(sod(clock), -196));
    await SyncService(store, remote).run(now: clock);
    for (var i = 0; i < 3; i++) {
      await s.submitCheckin(s.checkinInput());
    }
    remote.failNext = RemoteError('23514: check violation', permanent: true);
    remote.failTimes = 2; // the batch, then the first single row
    await SyncService(store, remote).run(now: clock);
    expect(store.deadCount, 1);
    expect(remote.tables['checkins']!.length, 2);
  });

  test('"your clinic will see this" only when sharing is really in effect', () async {
    await s.completeOnboarding(name: 'A', stage: 'pregnant', lmp: addDays(sod(clock), -100), consents: {'share_with_facility': true});
    await s.setFacility({'id': null, 'name': 'Typed clinic', 'phone': '0700'});
    expect(s.consent('share_with_facility'), isTrue); // her wish is remembered
    expect(s.sharingActive, isFalse); // but nothing can reach a clinic yet
    remote.uid = 'mother-1';
    await s.setFacility({'id': 'f1', 'name': 'Sample Health Centre 1', 'phone': '0700'});
    expect(s.sharingActive, isTrue);
  });

  test('switching clinic revokes the old clinic', () async {
    remote.uid = 'mother-1';
    await s.setFacility({'id': 'f1', 'name': 'One', 'phone': ''});
    await s.setConsent('share_with_facility', true);
    await s.setFacility({'id': 'f2', 'name': 'Two', 'phone': ''});
    final f1 = s.consentHistory.where((r) => r['facility_id'] == 'f1').toList();
    expect(f1.last['granted'], isFalse);
  });

  test('the baby is linked to the pregnancy it came from', () async {
    await s.completeOnboarding(name: 'A', stage: 'pregnant', lmp: addDays(sod(clock), -275));
    final pid = s.pregnancy!['id'];
    await s.recordBirth(dob: sod(clock));
    expect(s.baby!['pregnancy_id'], pid);
  });

  test('a later sign-free check never hides an earlier red today', () async {
    await s.completeOnboarding(name: 'A', stage: 'pregnant', lmp: addDays(sod(clock), -196));
    await s.submitCheckin(s.checkinInput(signs: {'bleeding'}));
    await s.submitCheckin(s.checkinInput());
    expect(s.levelOf(s.todayWorst!), Level.red);
  });

  test('a returning mother on a new phone keeps her server pregnancy, clinic and visits', () async {
    await s.completeOnboarding(name: 'Amina', stage: 'pregnant', lmp: addDays(sod(clock), -196));
    await s.submitCheckin(s.checkinInput());
    final localPreg = s.pregnancy!['id'];
    remote.pullRows['profiles'] = [
      {'id': 'mother-1', 'display_name': 'Amina', 'home_facility': 'f1', 'lang': 'sw', 'updated_at': '2026-10-01T00:00:00Z'},
    ];
    remote.pullRows['pregnancies'] = [
      {'id': 'server-preg', 'lmp': isoDay(addDays(sod(clock), -197)), 'status': 'active', 'updated_at': '2026-10-01T00:00:00Z'},
    ];
    await s.verifyCode('+255700000101', '123456');
    expect(s.pregnancy!['id'], 'server-preg');
    expect(store.get('pregnancies', localPreg as String), isNull);
    expect(s.checkins.single['pregnancy_id'], 'server-preg');
    expect(s.facility!['id'], 'f1');
    expect(remote.tables['pregnancies'], isNull, reason: 'no duplicate pregnancy sent');
    expect(remote.tables['profiles']!.values.single['home_facility'], 'f1');
  });

  test('notes are capped by code points so emoji never break the 500 limit', () async {
    await s.completeOnboarding(name: 'A', stage: 'pregnant', lmp: addDays(sod(clock), -100));
    await s.submitCheckin(s.checkinInput(), note: '😀' * 600);
    expect((s.checkins.single['note'] as String).runes.length, 500);
  });

  test('assistant: blood pressure is not routed to bleeding; "benefit" is not "fits"', () {
    expect(answerFor('What is a normal blood pressure?').keywords, contains('blood pressure'));
    expect(answerFor('Shinikizo la damu langu ni 140/90').keywords, contains('shinikizo'));
    expect(answerFor('I am bleeding').urgent, Level.red);
    expect(answerFor('What is the benefit of breastfeeding?').urgent, isNot(Level.red));
    expect(answerFor('My baby has fits').urgent, Level.red);
  });
}
