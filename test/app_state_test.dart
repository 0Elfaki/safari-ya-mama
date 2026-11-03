import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:safari_ya_mama/core/content.dart';
import 'package:safari_ya_mama/core/dates.dart';
import 'package:safari_ya_mama/core/rules.dart';
import 'package:safari_ya_mama/data/local_store.dart';
import 'package:safari_ya_mama/state/app_state.dart';

void main() {
  late Directory dir;
  late LocalStore store;
  late AppState s;
  final clock = DateTime(2026, 11, 2, 10);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sym');
    store = LocalStore();
    await store.open(path: dir.path);
    s = AppState(store, clock: () => clock);
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('pregnant onboarding: week, month, due date and 8 ANC contacts (offline)', () async {
    await s.completeOnboarding(name: 'Amina', stage: 'pregnant', lmp: addDays(sod(clock), -196));
    expect(s.onboarded, isTrue);
    expect(s.weeks, 28);
    expect(s.month, 7);
    expect(s.edd, addDays(sod(clock), 84));
    expect(s.ancVisits.length, 8);
    expect(s.ancVisits.first.due, addDays(s.lmp!, 84));
    expect(s.nextVisit!.contactNo, 4); // week 30
    expect(store.pendingCount, 1); // the pregnancy waits in the outbox
  });

  test('consent is off by default and kept as a history of rows', () async {
    await s.completeOnboarding(name: 'A', stage: 'pregnant', lmp: addDays(sod(clock), -70));
    for (final k in consentKinds) {
      expect(s.consent(k), isFalse, reason: k);
    }
    await s.setFacility({'id': 'f1', 'name': 'Sample Health Centre 1', 'phone': '+255700000001'});
    await s.setConsent('share_with_facility', true);
    await s.setConsent('share_with_facility', false);
    expect(s.consent('share_with_facility'), isFalse);
    expect(store.all('consents').length, 2);
  });

  test('check-in is triaged on the phone and stored with level and rules version', () async {
    await s.completeOnboarding(name: 'A', stage: 'pregnant', lmp: addDays(sod(clock), -196));
    final t = await s.submitCheckin(
      s.checkinInput(feeling: 'ok', signs: {'headache', 'vision'}),
      note: 'Headache since morning',
    );
    expect(t.level, Level.red);
    final row = s.todayCheckin!;
    expect(row['level'], 'red');
    expect(row['rules_version'], rulesVersion);
    expect(row['note'], 'Headache since morning');
    expect(s.questions.single['body'], 'Headache since morning');
  });

  test('BP log: the 3-week rise raises amber on the phone', () async {
    await s.completeOnboarding(name: 'A', stage: 'pregnant', lmp: addDays(sod(clock), -196));
    for (final (d, v) in [(28, 118), (21, 122), (14, 128), (7, 134)]) {
      await store.putLocal('bp_readings', {
        'id': 'bp$d',
        'systolic': v,
        'diastolic': 80,
        'level': 'green',
        'client_created_at': clock.subtract(Duration(days: d)).toUtc().toIso8601String(),
      });
    }
    final t = await s.addBp(139, 88, const []);
    expect(t.level, Level.amber);
  });

  test('recording the birth switches to baby mode with 16 vaccines and 4 postnatal visits', () async {
    await s.completeOnboarding(name: 'A', stage: 'pregnant', lmp: addDays(sod(clock), -275));
    await s.addQuestion('Where do I go at night?');
    await s.recordBirth(dob: addDays(sod(clock), -3), name: 'Zuri', weightG: 3100);
    expect(s.stage, 'postnatal');
    expect(s.pregnancy, isNull);
    expect(s.babyName, 'Zuri');
    expect(s.vaccines.length, 16);
    expect(s.pncVisits.length, 4);
    expect(s.growth.single['weight_g'], 3100);
    expect(s.questions.length, 1, reason: 'questions carry over');
    await s.setVaccineGiven('bcg', true);
    expect(s.vaccines.firstWhere((v) => v.dose.key == 'bcg').given, isTrue);
  });

  test('PIN is salted and hashed; wrong PIN does not unlock', () async {
    await s.setPin('1234');
    expect(store.meta<String>('pin_hash'), isNot(contains('1234')));
    s.lock();
    expect(s.locked, isTrue);
    expect(s.unlock('0000'), isFalse);
    expect(s.unlock('1234'), isTrue);
  });

  test('delete all my data wipes the phone when not signed in', () async {
    await s.completeOnboarding(name: 'A', stage: 'pregnant', lmp: addDays(sod(clock), -100));
    await s.submitCheckin(s.checkinInput());
    expect(await s.deleteAllMyData(), isTrue);
    expect(s.onboarded, isFalse);
    expect(store.all('checkins'), isEmpty);
    expect(store.pendingCount, 0);
  });

  test('soft delete hides a record at once and queues delete_record', () async {
    await s.addJournal('private');
    final id = s.journal.single['id'] as String;
    await s.deleteRecord('journal_entries', id);
    expect(s.journal, isEmpty);
    expect(store.outbox().last.op, 'delete');
  });
}
