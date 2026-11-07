// Child side (MA-47..MA-50): colour-coded check, step-up rule, per-baby notes, colour
// history, child clinic contacts, mirrored month-by-month, first aid.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safari_ya_mama/app/app.dart';
import 'package:safari_ya_mama/app/providers.dart';
import 'package:safari_ya_mama/core/content.dart';
import 'package:safari_ya_mama/core/dates.dart';
import 'package:safari_ya_mama/core/first_aid.dart';
import 'package:safari_ya_mama/core/rules.dart';
import 'package:safari_ya_mama/data/local_store.dart';
import 'package:safari_ya_mama/state/app_state.dart';
import 'package:safari_ya_mama/ui/screens/first_aid_screen.dart';

void main() {
  group('rules 2026.12', () {
    CheckinInput baby(Set<String> s, {int days = 100}) => CheckinInput(stage: 'postnatal', babySigns: s, babyDays: days, babyName: 'Zuri');
    test('3 everyday signs stay green; 4 together are amber, with a named reason', () {
      expect(triage(baby({'b_g_cold', 'b_g_spit', 'b_g_rash'})).level, Level.green);
      final t = triage(baby({'b_g_cold', 'b_g_spit', 'b_g_rash', 'b_g_fussy'}));
      expect(t.level, Level.amber);
      expect(t.reasons.single.en, 'Zuri: Several everyday signs together (4)');
    });
    test('green signs never hide a danger sign', () {
      final t = triage(baby({'b_g_cold', 'b_g_spit', 'b_g_rash', 'b_g_fussy', 'b_belly'}));
      expect(t.level, Level.red);
      expect(t.reasons.map((r) => r.en), ['Zuri: Swollen, hard belly or green vomit']);
    });
    test('new red signs: severe jaundice and belly danger signs at any age', () {
      expect(triage(baby({'b_yellow_severe'}, days: 2)).level, Level.red);
      expect(triage(baby({'b_belly'}, days: 250)).level, Level.red);
      expect(rulesVersion, '2026.12');
    });
    test('every sign guide explains a sign the rules know; no guide uses a word of reassurance', () {
      for (final g in signGuides) {
        expect(babySigns.any((s) => s.key == g.key), isTrue, reason: g.key);
        for (final w in ['fine', 'normal', 'safe']) {
          expect(g.how.en.toLowerCase().contains(' $w'), isFalse, reason: '${g.key} says "$w"');
        }
      }
      expect(firstAidTopics.first.steps.first.count, 5);
    });
    test('baby month on the 9-month journey', () {
      expect(babyMonthOf(0), 1);
      expect(babyMonthOf(31), 2);
      expect(babyMonthOf(270), 9);
      expect(babyMonthOf(400), 9);
      expect(babyMonthsGuide.length, 9);
      expect(childContacts.length, 8, reason: 'eight child visits, like eight antenatal contacts');
    });
  });

  group('state', () {
    late Directory dir;
    late LocalStore store;
    late AppState s;
    final clock = DateTime(2026, 11, 2, 10);

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('symchild');
      store = LocalStore();
      await store.open(path: dir.path);
      s = AppState(store, clock: () => clock);
      await s.completeOnboarding(name: 'Bahati', stage: 'postnatal', dob: addDays(sod(clock), -50), babyName: 'Zuri');
      await s.setLang('en');
    });
    tearDown(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    test('a note about the baby goes on that baby\'s check and into the questions', () async {
      final id = s.baby!['id'] as String;
      final t = await s.submitCheckin(
        s.checkinInput(feeling: 'well', signs: const {}),
        babyAnswers: {
          id: const BabyAnswers(signs: {'b_g_cold', 'b_g_spit', 'b_g_rash', 'b_g_stool'}, note: 'Coughs at night'),
        },
      );
      expect(t.level, Level.amber);
      final row = store.all('checkins').single;
      expect(row['note'], 'Coughs at night');
      expect(row['baby_signs'], hasLength(4));
      expect(s.questions.map((q) => q['body']), contains('Zuri: Coughs at night'));
    });

    test('colour history keeps the most urgent result of each day', () async {
      final id = s.baby!['id'] as String;
      Future<void> check(Set<String> signs) => s.submitCheckin(
        s.checkinInput(feeling: 'well', signs: const {}),
        babyAnswers: {id: BabyAnswers(signs: signs)},
      );
      await check({});
      await check({'b_yellow'});
      await check({});
      final h = s.checkHistory(id);
      expect(h.length, 14);
      expect(h.last.level, Level.amber);
      expect(h.first.level, isNull);
    });

    test('child clinic contacts: done when the visit\'s vaccines are ticked', () async {
      final id = s.baby!['id'] as String;
      var c = s.childContactsFor(id);
      expect(c.length, 8);
      expect(c.first.done, isFalse);
      expect(c[3].due, addDays(addDays(sod(clock), -50), 42));
      await s.setVaccineGiven('bcg', true);
      await s.setVaccineGiven('opv0', true);
      c = s.childContactsFor(id);
      expect(c.first.done, isTrue);
      expect(c[3].done, isFalse);
    });
  });

  group('UI', () {
    Future<AppState> pump(WidgetTester t) async {
      final store = LocalStore();
      await store.open(inMemory: true);
      final s = AppState(store);
      await s.completeOnboarding(name: 'Bahati', stage: 'postnatal', dob: addDays(sod(DateTime.now()), -100), babyName: 'Zuri');
      await s.setLang('en');
      t.view.physicalSize = const Size(1080, 2340);
      t.view.devicePixelRatio = 2.75;
      addTearDown(t.view.reset);
      t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await t.pumpWidget(ProviderScope(overrides: [appStateProvider.overrideWith((ref) => s)], child: const SafariYaMamaApp()));
      await t.pumpAndSettle();
      return s;
    }

    Future<void> tapKey(WidgetTester t, String k) async {
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

    testWidgets('home mirrors pregnancy: Month X of 9 with the baby highlight', (t) async {
      await pump(t);
      expect(find.byKey(const Key('journey-card')), findsOneWidget);
      expect(find.text('Month 4 of 9'), findsOneWidget);
      expect(find.text('Zuri: Laughs and holds the head steady'), findsOneWidget);
      await t.tap(find.byKey(const Key('tab-journey')));
      await t.pumpAndSettle();
      await t.tap(find.text('Mother'));
      await t.pumpAndSettle();
      expect(find.text('Month by month'), findsOneWidget);
      expect(find.byKey(const Key('baby-month-4')), findsOneWidget);
      await t.scrollUntilVisible(
        find.text("Zuri's 8 clinic visits"),
        300,
        scrollable: find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first,
      );
      expect(find.text("Zuri's 8 clinic visits"), findsOneWidget);
      await Hive.close();
    });

    testWidgets('colour-coded check: 4 everyday signs prompt the next step and give amber', (t) async {
      await pump(t);
      await tapKey(t, 'today-check');
      await tapKey(t, 'feel-well');
      for (final k in ['b_g_cold', 'b_g_spit', 'b_g_rash']) {
        await tapKey(t, 'sign-$k');
      }
      expect(find.byKey(const Key('stepup')), findsNothing);
      await tapKey(t, 'sign-b_g_fussy');
      expect(find.byKey(const Key('stepup')), findsOneWidget);
      expect(find.byKey(const Key('step-red')), findsOneWidget, reason: 'danger signs always shown');
      await t.enterText(find.byKey(const Key('baby-note')), 'Coughs at night');
      await tapKey(t, 'ck-submit');
      expect(find.byKey(const Key('level-amber')), findsOneWidget);
      expect(find.text('Zuri: Several everyday signs together (4)'), findsOneWidget);
      await Hive.close();
    });

    testWidgets('first aid: choking opens with the animated back blows and counter', (t) async {
      await pump(t);
      await t.tap(find.byKey(const Key('tab-journey')));
      await t.pumpAndSettle();
      await tapKey(t, 'open-first-aid');
      await t.tap(find.byKey(const Key('aid-choking')));
      await t.pumpAndSettle();
      expect(find.text('5 back blows'), findsOneWidget);
      expect(find.byKey(const Key('anim-count')), findsWidgets);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('tab-signs')));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byKey(const Key('guide-b_yellow')),
        300,
        scrollable: find.descendant(of: find.byType(SignGuideList), matching: find.byType(Scrollable)).first,
      );
      expect(find.byKey(const Key('guide-b_yellow')), findsOneWidget);
      await Hive.close();
    });
  });
}
