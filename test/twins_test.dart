// Twins and triplets: one record per baby, own vaccines/feeds/weights, own warning-sign check.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safari_ya_mama/app/app.dart';
import 'package:safari_ya_mama/app/providers.dart';
import 'package:safari_ya_mama/core/content.dart';
import 'package:safari_ya_mama/core/dates.dart';
import 'package:safari_ya_mama/data/local_store.dart';
import 'package:safari_ya_mama/state/app_state.dart';

import 'fakes.dart';

void main() {
  group('state', () {
    late Directory dir;
    late LocalStore store;
    late AppState s;
    final clock = DateTime(2026, 11, 2, 10);

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('symtwins');
      store = LocalStore();
      await store.open(path: dir.path);
      s = AppState(store, clock: () => clock);
      await s.completeOnboarding(name: 'Rehema', stage: 'pregnant', lmp: addDays(sod(clock), -265));
      await s.setLang('en');
    });
    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    Future<void> twins() => s.recordBirth(
      dob: addDays(sod(clock), -20),
      children: const [
        NewBaby(name: 'Zuri', sex: 'f', weightG: 2300),
        NewBaby(sex: 'm', weightG: 2100),
      ],
    );

    test('recording twins makes two babies from one pregnancy, with their own schedules and weights', () async {
      final pid = s.pregnancy!['id'];
      await twins();
      expect(s.babies.length, 2);
      expect(s.babies.every((b) => b['pregnancy_id'] == pid), isTrue);
      expect(s.multipleBirth, isTrue);
      expect(s.babiesLabel, 'Zuri & Baby 2');
      expect(s.babyName, 'Zuri', reason: 'the first-born is shown first');
      for (final b in s.babies) {
        expect(s.vaccinesFor(b['id'] as String).length, 16);
        expect(s.growthOf(b['id'] as String).single['weight_g'], b['sex'] == 'f' ? 2300 : 2100);
      }
    });

    test('vaccines, feeds and milestones are per baby', () async {
      await twins();
      final [a, b] = s.babies;
      await s.setVaccineGiven('bcg', true, babyId: a['id'] as String);
      expect(s.vaccinesFor(a['id'] as String).first.given, isTrue);
      expect(s.vaccinesFor(b['id'] as String).first.given, isFalse);
      await s.selectBaby(b['id'] as String);
      await s.addFeed('breast');
      await s.toggleMilestone('m1a');
      expect(s.feedsToday(), 1);
      expect(s.milestoneDone('m1a'), isTrue);
      await s.selectBaby(a['id'] as String);
      expect(s.feedsToday(), 0);
      expect(s.milestoneDone('m1a'), isFalse);
    });

    test('check-in: each twin gets its own row and rules; the result is the most urgent', () async {
      await twins();
      final [a, b] = s.babies;
      final t = await s.submitCheckin(
        s.checkinInput(feeling: 'ok', signs: {'pp_breast'}),
        babyAnswers: {
          a['id'] as String: const BabyAnswers(),
          b['id'] as String: const BabyAnswers(signs: {'b_fever'}),
        },
      );
      expect(t.level, Level.red, reason: 'fever at 20 days old is red (IMCI)');
      expect(t.reasons.single.en, 'Baby 2: Feels hot (fever)');
      final rows = s.checkins;
      expect(rows.length, 2);
      final rowA = rows.firstWhere((r) => r['baby_id'] == a['id']), rowB = rows.firstWhere((r) => r['baby_id'] == b['id']);
      expect(rowA['signs'], ['pp_breast'], reason: "the mother's answers go on the first row only");
      expect(rowA['level'], 'amber');
      expect(rowB['signs'], isEmpty);
      expect(rowB['feeling'], isNull);
      expect(rowB['level'], 'red');
      expect(s.levelOf(s.todayWorst!), Level.red);
    });

    test('the child profile can be corrected; a forgotten twin can be added later', () async {
      await s.recordBirth(dob: addDays(sod(clock), -5), name: 'Zuri');
      final id = s.baby!['id'] as String;
      await s.updateBaby(id, {'name': 'Zuri Amani', 'birth_weight_g': 2600});
      expect(s.babyName, 'Zuri Amani');
      expect(store.outbox().last.table, 'babies');
      final second = await s.addBaby(dob: addDays(sod(clock), -5), name: 'Imani', order: 2);
      expect(s.birthGroup.length, 2);
      expect(s.babiesLabel, 'Zuri Amani & Imani');
      expect(s.babyById(second)!['pregnancy_id'], isNull, reason: 'pregnancy already delivered; the twin is still linked by birth date');
    });

    test('reminders: twins due the same day share one vaccine reminder', () async {
      await s.recordBirth(
        dob: addDays(sod(clock), -40),
        children: const [
          NewBaby(name: 'Zuri'),
          NewBaby(name: 'Neema'),
        ],
      );
      for (final b in s.babies) {
        await s.setVaccineGiven('bcg', true, babyId: b['id'] as String);
        await s.setVaccineGiven('opv0', true, babyId: b['id'] as String);
      }
      final vx = s.reminders.where((r) => r.icon == 'syringe').toList();
      expect(vx.length, 1);
      expect(vx.single.text.en, startsWith('Zuri & Neema: OPV 1'));
    });
  });

  test('sign-in on a new phone matches unsynced twins to the server twins in birth order', () async {
    final dir = await Directory.systemTemp.createTemp('symtwins2');
    final store = LocalStore();
    await store.open(path: dir.path);
    final remote = FakeRemote()..uid = null;
    final clock = DateTime(2026, 11, 2, 10);
    final s = AppState(store, remote: remote, clock: () => clock);
    final born = isoDay(addDays(sod(clock), -30));
    await s.completeOnboarding(name: 'Rehema', stage: 'postnatal', dob: addDays(sod(clock), -30), babyNames: ['Zuri', 'Neema']);
    final [l1, l2] = s.babies;
    await s.addFeed('breast', babyId: l2['id'] as String);
    remote.pullRows['babies'] = [
      {'id': 'srv-1', 'name': 'Zuri', 'dob': born, 'updated_at': '2026-10-05T00:00:00Z', 'created_at': '2026-10-05T00:00:00Z'},
      {'id': 'srv-2', 'name': 'Neema', 'dob': born, 'updated_at': '2026-10-05T00:00:01Z', 'created_at': '2026-10-05T00:00:01Z'},
    ];
    await s.verifyCode('+255700000102', '123456');
    expect(s.babies.map((b) => b['id']), containsAll(['srv-1', 'srv-2']));
    expect(s.babies.length, 2);
    expect(store.get('babies', l1['id'] as String), isNull);
    expect(store.all('feeds').single['baby_id'], 'srv-2');
    expect(remote.tables['babies'], isNull, reason: 'no duplicate babies sent');
    await Hive.close();
    await dir.delete(recursive: true);
  });

  testWidgets('UI: record twins, then a fever in the second twin gives red', (t) async {
    final store = LocalStore();
    await store.open(inMemory: true);
    final s = AppState(store);
    await s.completeOnboarding(name: 'Rehema', stage: 'pregnant', lmp: DateTime.now().subtract(const Duration(days: 270)));
    await s.setLang('en');
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.75;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(overrides: [appStateProvider.overrideWith((ref) => s)], child: const SafariYaMamaApp()));
    await t.pumpAndSettle();

    Future<void> tapKey(String k) async {
      final f = find.byKey(Key(k));
      if (f.evaluate().isEmpty) {
        await t.scrollUntilVisible(
          f,
          200,
          scrollable: find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first,
        );
      }
      await t.ensureVisible(f);
      await t.pumpAndSettle();
      await t.tap(f);
      await t.pumpAndSettle();
    }

    await t.tap(find.byKey(const Key('tab-journey')));
    await t.pumpAndSettle();
    await t.tap(find.text('Baby'));
    await t.pumpAndSettle();
    await tapKey('record-birth');
    await tapKey('count-2');
    await t.enterText(find.byKey(const Key('baby-name-0')), 'Zuri');
    await t.enterText(find.byKey(const Key('baby-name-1')), 'Neema');
    await t.pumpAndSettle();
    await tapKey('birth-save');
    expect(s.babies.length, 2);
    expect(find.byType(ChoiceChip), findsNWidgets(2), reason: 'baby switcher on My baby');

    await tapKey('open-child-profile');
    expect(find.text('Zuri'), findsWidgets);
    expect(find.text('Neema'), findsWidgets);
    await t.pageBack();
    await t.pumpAndSettle();

    await t.tap(find.text('Home'));
    await t.pumpAndSettle();
    expect(find.text('Zuri & Neema: Knows your voice and smell'), findsOneWidget);
    await tapKey('today-check');
    await tapKey('feel-well');
    await tapKey('sign-b_fever-1');
    expect(find.text('Neema: everyday things'), findsOneWidget);
    await tapKey('ck-submit');
    expect(find.byKey(const Key('level-red')), findsOneWidget);
    expect(find.text('Neema: Feels hot (fever)'), findsOneWidget);
    await Hive.close();
  });
}
