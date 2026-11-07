// Full version (MA-51..MA-54): Learn tab, quizzes, body self-check, caregiver link.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safari_ya_mama/app/app.dart';
import 'package:safari_ya_mama/app/providers.dart';
import 'package:safari_ya_mama/core/body_check.dart';
import 'package:safari_ya_mama/core/content.dart';
import 'package:safari_ya_mama/core/dates.dart';
import 'package:safari_ya_mama/core/lessons.g.dart';
import 'package:safari_ya_mama/core/rules.dart';
import 'package:safari_ya_mama/data/local_store.dart';
import 'package:safari_ya_mama/state/app_state.dart';
import 'package:safari_ya_mama/state/demo_seed.dart';

BodyQ q(String map, String id) => bodyMaps[map]!.expand((a) => a.qs).firstWhere((x) => x.id == id);
Triage self(String map, List<String> ids, {int weeks = 30, int babyDays = 60}) =>
    rateSelfCheck(map, ids.map((i) => q(map, i)), weeks: weeks, babyDays: babyDays, babyName: map == 'baby' ? 'Zuri' : null);

void main() {
  group('body self-check (MA-43) uses the same rules as the daily check', () {
    test('every question maps to a known sign, a special key, or its own amber/red level', () {
      const special = {'_unwell', '_unwell_fever', '_move_none', '_move_fewer'};
      for (final e in bodyMaps.entries) {
        for (final a in e.value) {
          expect(a.qs, isNotEmpty, reason: '${e.key}/${a.id}');
          for (final x in a.qs) {
            final ok = x.sign == null ? x.level != null && x.level != Level.green : special.contains(x.sign) || signByKey(x.sign!) != null;
            expect(ok, isTrue, reason: '${e.key}/${x.id} → ${x.sign}');
            expect(x.text.sw, isNotEmpty);
          }
        }
      }
    });
    test('nothing found is green with no reasons (never "fine")', () {
      final t = self('pregnant', []);
      expect(t.level, Level.green);
      expect(t.reasons, isEmpty);
    });
    test('a danger sign is red with the same reason as the daily check', () {
      final t = self('pregnant', ['p_bleed1']);
      expect(t.level, Level.red);
      expect(t.reasons.map((r) => r.en), triage(CheckinInput(stage: 'pregnant', signs: {'bleeding'}, weeks: 30)).reasons.map((r) => r.en));
    });
    test('own red question wins over a lower rule result; own amber lifts green', () {
      expect(self('pregnant', ['p_legs1']).level, Level.red);
      expect(self('pregnant', ['p_legs1']).reasons.single.en, 'One leg swollen, red, warm or painful?');
      expect(self('pregnant', ['p_bleed3']).level, Level.amber);
      expect(self('baby', ['b_s1']).level, Level.red);
    });
    test('no movements at 30 weeks is red; baby green vomit is red', () {
      expect(self('pregnant', ['p_baby1']).level, Level.red);
      expect(self('baby', ['b_f5']).level, Level.red);
      expect(self('baby', ['b_f5']).reasons.first.en, startsWith('Zuri: '));
    });
    test('postnatal fever with feeling very unwell is never lower than fever alone', () {
      final a = self('postnatal', ['n_fever1']).level, b = self('postnatal', ['n_breast1', 'n_breast2']).level;
      expect(b.index, greaterThanOrEqualTo(a.index));
      expect(b, isNot(Level.green));
    });
  });

  group('quizzes (MA-52)', () {
    test('every quiz belongs to a lesson, has a valid answer and both languages', () {
      expect(quizzes, isNotEmpty);
      for (final e in quizzes.entries) {
        expect(lessonById(e.key), isNotNull, reason: e.key);
        for (final x in e.value) {
          expect(x.answer, inInclusiveRange(0, x.options.length - 1));
          expect(x.q.sw, isNotEmpty);
          expect(x.why.sw, isNotEmpty);
        }
      }
    });
  });

  group('UI', () {
    Future<AppState> pump(WidgetTester t, Future<void> Function(AppState) seed) async {
      final store = LocalStore();
      await store.open(inMemory: true);
      final s = AppState(store);
      await seed(s);
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

    Future<void> mother(AppState s) => s.completeOnboarding(name: 'Bahati', stage: 'postnatal', dob: addDays(sod(DateTime.now()), -100), babyName: 'Zuri');

    Future<void> tapKey(WidgetTester t, String k) async {
      final f = find.byKey(Key(k));
      if (f.evaluate().isEmpty) {
        await t.scrollUntilVisible(
          f,
          200,
          scrollable: find.descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable)).first,
        );
      }
      await t.ensureVisible(f);
      await t.pumpAndSettle();
      await t.tap(f);
      await t.pumpAndSettle();
    }

    testWidgets('Learn tab: lessons, first aid, body check; a lesson quiz scores and is saved', (t) async {
      final s = await pump(t, mother);
      await tapKey(t, 'tab-learn');
      expect(find.byKey(const Key('learn-cover')), findsOneWidget);
      expect(find.byKey(const Key('learn-first-aid')), findsOneWidget);
      final id = quizzes.keys.firstWhere((k) => lessonById(k) != null);
      await tapKey(t, 'lesson-$id');
      // read through the lesson to the end, then the quiz opens
      for (var i = 0; i < 12 && find.byKey(const Key('quiz-opt-0')).evaluate().isEmpty; i++) {
        final next = find.byKey(const Key('lesson-next'));
        if (next.evaluate().isEmpty) break;
        await t.tap(next);
        await t.pumpAndSettle();
      }
      expect(find.byKey(const Key('quiz-opt-0')), findsOneWidget);
      for (final x in quizzes[id]!) {
        await t.tap(find.byKey(Key('quiz-opt-${x.answer}')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('quiz-next')));
        await t.pumpAndSettle();
      }
      expect(find.byKey(const Key('quiz-result')), findsOneWidget);
      expect(s.quizScore(id), quizzes[id]!.length);
      await Hive.close();
    });

    testWidgets('body check: baby green vomit shows the red banner and the emergency button', (t) async {
      await pump(t, mother);
      await tapKey(t, 'tab-learn');
      await tapKey(t, 'learn-body-check');
      expect(find.byKey(const Key('body-go-now')), findsOneWidget);
      await t.tap(find.text('Zuri'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('area-feeding')));
      await t.pumpAndSettle();
      await t.tap(find.descendant(of: find.byKey(const Key('q-b_f5')), matching: find.text('Yes')));
      await t.pumpAndSettle();
      await tapKey(t, 'body-result');
      expect(find.byKey(const Key('level-red')), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('What to do now'),
        200,
        scrollable: find.descendant(of: find.byType(ListView).last, matching: find.byType(Scrollable)).first,
      );
      expect(find.text('What to do now'), findsOneWidget);
      await Hive.close();
    });

    testWidgets('caregiver: a partner sees today, 7 days and next visit; never the journal', (t) async {
      await pump(t, (s) => s.seedDemo('caregiver'));
      expect(find.text('Hello, Juma'), findsOneWidget);
      expect(find.byKey(const Key('cg-mother-demo-bahati')), findsOneWidget);
      expect(find.text('Zuri, 92 days'), findsOneWidget);
      expect(find.text('Help her contact a health worker today.'), findsOneWidget);
      expect(find.text('Last 7 days'), findsOneWidget);
      expect(find.text('Next vaccine'), findsOneWidget);
      expect(find.textContaining('Journal'), findsNothing);
      expect(find.byKey(const Key('tab-learn')), findsNothing, reason: 'helpers do not get the mother tabs');
      await Hive.close();
    });

    testWidgets('onboarding offers "I help a mother"; offline it says honestly that joining needs a server', (t) async {
      await pump(t, (_) async {});
      await tapKey(t, 'i-help-a-mother');
      expect(find.textContaining('not connected to a server'), findsOneWidget);
      await Hive.close();
    });

    testWidgets('mother: Profile → My helpers asks her to connect first when offline', (t) async {
      await pump(t, mother);
      await t.tap(find.byKey(const Key('open-menu')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('open-profile')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('open-profile')));
      await t.pumpAndSettle();
      await tapKey(t, 'my-helpers');
      expect(find.textContaining('Connect to your clinic first'), findsOneWidget);
      expect(find.textContaining('never see your journal'), findsOneWidget);
      await Hive.close();
    });
  });
}
