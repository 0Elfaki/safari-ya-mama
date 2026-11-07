// End-to-end UI flow on an in-memory store: onboarding → home → red check-in → emergency.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safari_ya_mama/app/app.dart';
import 'package:safari_ya_mama/app/providers.dart';
import 'package:safari_ya_mama/data/local_store.dart';
import 'package:safari_ya_mama/state/app_state.dart';

void main() {
  late AppState s;

  setUp(() async {
    final store = LocalStore();
    await store.open(inMemory: true);
    s = AppState(store);
  });
  tearDown(() => Hive.close());

  Future<void> pump(WidgetTester t) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.75;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(overrides: [appStateProvider.overrideWith((ref) => s)], child: const SafariYaMamaApp()));
    await t.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester t, String k) async {
    final f = find.byKey(Key(k));
    if (f.evaluate().isEmpty) {
      // lazily built list: scroll the main vertical list until the widget exists
      final list = find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first;
      await t.scrollUntilVisible(f, 200, scrollable: list);
    }
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key(k)));
    await t.pumpAndSettle();
  }

  testWidgets('onboarding in English, then a red check-in shows go-now and emergency help', (t) async {
    await pump(t);
    expect(find.text('Safari ya Mama'), findsWidgets);
    await tapKey(t, 'lang-en');
    expect(find.text('A safer journey into motherhood'), findsOneWidget);
    await tapKey(t, 'get-started');
    expect(find.text('Step 1 of 5'), findsOneWidget);
    // a name is needed before Continue
    expect(t.widget<FilledButton>(find.byKey(const Key('ob-next'))).onPressed, isNull);
    await t.enterText(find.byKey(const Key('ob-name')), 'Amina');
    await t.pumpAndSettle();
    await tapKey(t, 'ob-next');
    // 28 weeks: tap + 16 times from 12
    for (var i = 0; i < 16; i++) {
      await t.tap(find.byIcon(Icons.add).first);
    }
    await t.pumpAndSettle();
    expect(find.text('28'), findsOneWidget);
    await tapKey(t, 'ob-next');
    await tapKey(t, 'ob-next'); // emergency contacts: optional
    // consent screen: sharing off by default; the data agreement is required
    final sw = t.widget<SwitchListTile>(find.byKey(const Key('consent-share_with_facility')));
    expect(sw.value, isFalse);
    expect(t.widget<FilledButton>(find.byKey(const Key('ob-next'))).onPressed, isNull);
    await tapKey(t, 'consent-data');
    await tapKey(t, 'ob-next');
    await tapKey(t, 'ob-next'); // skip PIN
    expect(find.text('Hello, Amina'), findsOneWidget);
    expect(find.text('28 weeks, 0 days'), findsOneWidget);
    expect(find.text('3 of 3'), findsOneWidget);

    await tapKey(t, 'today-check');
    await tapKey(t, 'feel-ok');
    await tapKey(t, 'sign-headache');
    await tapKey(t, 'sign-vision');
    await tapKey(t, 'ck-submit');
    expect(find.byKey(const Key('level-red')), findsOneWidget);
    expect(find.text('Go to a health facility now'), findsOneWidget);
    expect(find.text('Severe headache with blurred vision'), findsOneWidget);
    expect(find.textContaining('fine'), findsNothing);

    await t.tap(find.text('What to do now'));
    await t.pumpAndSettle();
    expect(find.text('Emergency care plan'), findsOneWidget);
    expect(find.text('Need urgent help?'), findsOneWidget);
  });

  testWidgets('green check-in never says "fine" and explains its limits (Kiswahili)', (t) async {
    await s.completeOnboarding(name: 'Neema', stage: 'pregnant', lmp: DateTime.now().subtract(const Duration(days: 100)));
    await pump(t);
    expect(find.text('Habari, Neema'), findsOneWidget);
    await tapKey(t, 'today-check');
    await tapKey(t, 'feel-well');
    await tapKey(t, 'ck-submit');
    expect(find.byKey(const Key('level-green')), findsOneWidget);
    expect(find.text('Hakuna dalili za hatari zilizoripotiwa leo'), findsOneWidget);
    expect(find.textContaining('Ukaguzi huu hauwezi kuondoa kila tatizo'), findsOneWidget);
  });

  testWidgets('baby mode: fever in a 3-week-old is red (IMCI)', (t) async {
    await s.completeOnboarding(name: 'Bahati', stage: 'postnatal', dob: DateTime.now().subtract(const Duration(days: 21)), babyName: 'Zuri');
    await s.setLang('en');
    await pump(t);
    await tapKey(t, 'today-check');
    await tapKey(t, 'feel-well');
    await tapKey(t, 'sign-b_fever');
    await tapKey(t, 'ck-submit');
    expect(find.byKey(const Key('level-red')), findsOneWidget);
    expect(find.text('Zuri: Feels hot (fever)'), findsOneWidget);
  });
}
