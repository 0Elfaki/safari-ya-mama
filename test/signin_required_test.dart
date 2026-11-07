// Sign-in is required when the app has a server: SMS code, clinic setup code, or Google.
// A new mother answers the setup questions after signing in; a returning mother (records
// already on the server) goes straight to Home. Emergency help works before sign-in.
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
  late FakeRemote remote;
  setUp(() async {
    store = LocalStore();
    await store.open(inMemory: true);
    remote = FakeRemote()..uid = null;
  });
  tearDown(() => Hive.close());

  Future<AppState> pump(WidgetTester t, AppState s) async {
    await s.setLang('en');
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.75;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(overrides: [appStateProvider.overrideWith((ref) => s)], child: const SafariYaMamaApp()));
    await t.pumpAndSettle();
    return s;
  }

  Future<void> tap(WidgetTester t, String key) async {
    await t.tap(find.byKey(Key(key)));
    await t.pumpAndSettle();
  }

  testWidgets('a new mother cannot pass Welcome without signing in; Emergency still works', (t) async {
    await pump(t, AppState(store, remote: remote));
    expect(find.byKey(const Key('have-account')), findsOneWidget);
    await tap(t, 'get-started');
    expect(find.text('Keep your records safe'), findsOneWidget);
    expect(find.byKey(const Key('ob-name')), findsNothing, reason: 'no setup questions before sign-in');
    await tap(t, 'emergency');
    expect(find.text('Need urgent help?'), findsOneWidget);
  });

  testWidgets('SMS sign-in, new mother → setup questions', (t) async {
    final s = await pump(t, AppState(store, remote: remote));
    await tap(t, 'get-started');
    await t.enterText(find.byKey(const Key('signin-phone')), '0712 345 678');
    await t.pumpAndSettle();
    await tap(t, 'signin-send');
    expect(remote.calls, contains('otp +255712345678'));
    await t.enterText(find.byKey(const Key('signin-code')), '123456');
    await t.pumpAndSettle();
    await tap(t, 'signin-verify');
    expect(s.signedIn, isTrue);
    expect(find.byKey(const Key('ob-name')), findsOneWidget, reason: 'new mother answers the setup questions');
    expect(s.onboarded, isFalse);
  });

  testWidgets('returning mother on a new phone: records come back and she goes straight Home', (t) async {
    final lmp = isoDay(addDays(sod(DateTime.now()), -200));
    remote.pullRows['profiles'] = [
      {'id': 'mother-1', 'display_name': 'Amina', 'role': 'mother', 'updated_at': '2026-11-01T08:00:00Z'},
    ];
    remote.pullRows['pregnancies'] = [
      {'id': 'p1', 'mother_id': 'mother-1', 'lmp': lmp, 'status': 'active', 'updated_at': '2026-11-01T08:00:00Z'},
    ];
    final s = await pump(t, AppState(store, remote: remote));
    await tap(t, 'have-account');
    await t.enterText(find.byKey(const Key('signin-phone')), '0712345678');
    await t.pumpAndSettle();
    await tap(t, 'signin-send');
    await t.enterText(find.byKey(const Key('signin-code')), '123456');
    await t.pumpAndSettle();
    await tap(t, 'signin-verify');
    expect(s.onboarded, isTrue);
    expect(s.pregnant, isTrue);
    expect(find.byKey(const Key('tab-home')), findsOneWidget);
    expect(find.text('Hello, Amina'), findsOneWidget);
  });

  testWidgets('clinic setup code: a wrong code is refused, the right one works once', (t) async {
    remote.setupCodes.add('48213907');
    final s = await pump(t, AppState(store, remote: remote));
    await tap(t, 'get-started');
    await t.tap(find.text('Code from clinic'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('signin-clinic-code')), '11112222');
    await t.pumpAndSettle();
    await tap(t, 'signin-clinic');
    expect(s.signedIn, isFalse);
    expect(find.textContaining('This code did not work'), findsOneWidget);
    await t.enterText(find.byKey(const Key('signin-clinic-code')), '4821 3907');
    await t.pumpAndSettle();
    await tap(t, 'signin-clinic');
    expect(s.signedIn, isTrue);
    expect(remote.setupCodes, isEmpty, reason: 'single use');
    expect(find.byKey(const Key('ob-name')), findsOneWidget);
  });

  testWidgets('set up before sign-in was required: sent to sign in, records kept', (t) async {
    final s = AppState(store, remote: remote);
    await s.completeOnboarding(name: 'Neema', stage: 'pregnant', lmp: addDays(sod(DateTime.now()), -100));
    await pump(t, s);
    expect(find.text('Keep your records safe'), findsOneWidget);
    expect(find.byKey(const Key('tab-home')), findsNothing);
    expect(s.pregnancy, isNotNull, reason: 'nothing on the phone is lost while she signs in');
  });

  test('Google sign-in: closing the Google window changes nothing', () async {
    final s = AppState(store, remote: remote);
    expect(await s.signInWithGoogle(() async => null), isFalse);
    expect(s.signedIn, isFalse);
    expect(await s.signInWithGoogle(() async => 'id-token'), isTrue);
    expect(remote.calls, contains('google'));
    expect(s.signedIn, isTrue);
  });
}
