// Side menu: opens from every tab, switches tabs, opens screens, Emergency at the bottom.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:safari_ya_mama/app/app.dart';
import 'package:safari_ya_mama/app/providers.dart';
import 'package:safari_ya_mama/core/dates.dart';
import 'package:safari_ya_mama/data/local_store.dart';
import 'package:safari_ya_mama/state/app_state.dart';

import 'fakes.dart';

void main() {
  late LocalStore store;
  setUp(() async {
    store = LocalStore();
    await store.open(inMemory: true);
  });
  tearDown(() => Hive.close());

  Future<AppState> pump(WidgetTester t) async {
    final s = AppState(store, remote: FakeRemote()..rpcResults['community_feed'] = []);
    await s.setLang('en');
    await s.completeOnboarding(name: 'Amina Juma', stage: 'pregnant', lmp: addDays(sod(DateTime.now()), -200));
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.75;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(overrides: [appStateProvider.overrideWith((ref) => s)], child: const SafariYaMamaApp()));
    await t.pumpAndSettle();
    return s;
  }

  Future<void> tap(WidgetTester t, String key) async {
    if (find.byKey(Key(key)).evaluate().isEmpty) {
      await t.scrollUntilVisible(find.byKey(Key(key)), 200, scrollable: find.descendant(of: find.byKey(const Key('app-drawer')), matching: find.byType(Scrollable)));
    }
    await t.ensureVisible(find.byKey(Key(key)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key(key)));
    await t.pumpAndSettle();
  }

  testWidgets('menu shows who she is and switches tabs', (t) async {
    await pump(t);
    await tap(t, 'open-menu');
    expect(find.text('Hello, Amina'), findsWidgets);
    expect(find.text('28 weeks pregnant'), findsOneWidget);
    await tap(t, 'menu-community');
    expect(find.byKey(const Key('app-drawer')), findsNothing, reason: 'the menu closes');
    expect(find.text("Mothers' circle"), findsOneWidget);
    // the menu is on every tab, with the current tab highlighted
    await tap(t, 'open-menu');
    expect(t.widget<ListTile>(find.byKey(const Key('menu-community'))).selected, isTrue);
    await tap(t, 'menu-learn');
    expect(find.byKey(const Key('tab-learn')), findsOneWidget);
  });

  testWidgets('menu opens Appointments, Profile, and Emergency help', (t) async {
    await pump(t);
    await tap(t, 'open-menu');
    await tap(t, 'menu-appointments');
    expect(find.text('See a health worker'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await tap(t, 'open-menu');
    await tap(t, 'open-profile');
    expect(find.text('Profile'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await tap(t, 'open-menu');
    await tap(t, 'menu-emergency');
    expect(find.text('Need urgent help?'), findsOneWidget);
  });

  testWidgets('language switch in the menu', (t) async {
    final s = await pump(t);
    await tap(t, 'open-menu');
    await tap(t, 'menu-language');
    expect(s.lang, 'sw');
    expect(find.text('Switch to English'), findsOneWidget);
  });
}
