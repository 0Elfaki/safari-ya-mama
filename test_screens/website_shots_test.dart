// Phone-sized screenshots for the website: 390 x 844 points at 3x (1170 x 2532 px),
// real fonts and pictures, made-up demo mothers only. Run:
//   flutter test test_screens/website_shots_test.dart --update-goldens
// Output: test_screens/website/*.png
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safari_ya_mama/app/app.dart';
import 'package:safari_ya_mama/app/providers.dart';
import 'package:safari_ya_mama/core/content_assets.dart';
import 'package:safari_ya_mama/data/local_store.dart';
import 'package:safari_ya_mama/state/app_state.dart';
import 'package:safari_ya_mama/state/demo_seed.dart';
import 'package:safari_ya_mama/ui/screens/checkin_screen.dart';
import 'package:safari_ya_mama/ui/screens/doctor_note_screen.dart';
import 'package:safari_ya_mama/ui/screens/emergency_screen.dart';
import 'package:safari_ya_mama/ui/screens/journey_screen.dart';
import 'package:safari_ya_mama/ui/screens/library_screen.dart';
import 'package:safari_ya_mama/ui/screens/notifications_screen.dart';

Future<void> _loadFonts() async {
  Future<ByteData> asset(String p) => rootBundle.load(p);
  Future<ByteData> file(String p) async => ByteData.sublistView(await File(p).readAsBytes());
  final inter = FontLoader('Inter');
  for (final w in ['400Regular', '500Medium', '600SemiBold', '700Bold']) {
    inter.addFont(asset('assets/fonts/Inter_$w.ttf'));
  }
  await inter.load();
  final manrope = FontLoader('Manrope');
  for (final w in ['600SemiBold', '700Bold', '800ExtraBold']) {
    manrope.addFont(asset('assets/fonts/Manrope_$w.ttf'));
  }
  await manrope.load();
  final root = Platform.environment['FLUTTER_ROOT'] ?? 'C:/flutter';
  await (FontLoader('MaterialIcons')..addFont(file('$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf'))).load();
}

void main() {
  setUpAll(() async {
    await _loadFonts();
    await ContentAssets.load();
  });

  Future<AppState> start(WidgetTester t, String demo, {String lang = 'en'}) async {
    final store = LocalStore();
    await store.open(inMemory: true);
    final s = AppState(store);
    await s.seedDemo(demo);
    await s.setLang(lang);
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await t.pumpWidget(ProviderScope(overrides: [appStateProvider.overrideWith((ref) => s)], child: const SafariYaMamaApp()));
    await t.pumpAndSettle();
    return s;
  }

  Future<void> shot(WidgetTester t, String name) async {
    await t.pumpAndSettle();
    await t.runAsync(() async {
      for (final e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('website/$name.png'));
  }

  Future<void> push(WidgetTester t, Widget w) async {
    t.state<NavigatorState>(find.byType(Navigator).first).push(MaterialPageRoute(builder: (_) => w));
    await t.pumpAndSettle();
  }

  Future<void> tab(WidgetTester t, String key) async {
    await t.tap(find.byKey(Key(key)));
    await t.pumpAndSettle();
  }

  testWidgets('pregnant mother', (t) async {
    final s = await start(t, 'pregnant');
    await shot(t, 'app-home-pregnant');
    await tab(t, 'tab-journey');
    await shot(t, 'app-my-care');
    await tab(t, 'tab-mamabot');
    await shot(t, 'app-mamabot');
    await tab(t, 'tab-learn');
    await shot(t, 'app-learn');
    await push(t, const CheckinScreen());
    await shot(t, 'app-check');
    final r = await s.submitCheckin(s.checkinInput(feeling: 'unwell', signs: {'headache', 'vision'}, movement: 'normal'));
    await push(t, CheckinResultScreen(r));
    await shot(t, 'app-check-result');
    await push(t, const EmergencyScreen());
    await shot(t, 'app-emergency');
    await push(t, const ContractionTimerScreen());
    await shot(t, 'app-contractions');
    await s.setFlag('phone_reminders', true);
    await push(t, const NotificationsScreen());
    await shot(t, 'app-reminders');
    await push(t, const DoctorNoteScreen());
    await t.tap(find.byKey(const Key('note-consent')));
    await shot(t, 'app-doctor-note');
  });

  testWidgets('baby', (t) async {
    await start(t, 'baby');
    await shot(t, 'app-home-baby');
    await tab(t, 'tab-journey');
    await shot(t, 'app-baby-tracker');
    await push(t, const LessonScreen('safe-sleep'));
    await shot(t, 'app-lesson');
  });

  testWidgets('Kiswahili', (t) async {
    await start(t, 'pregnant', lang: 'sw');
    await shot(t, 'app-home-pregnant-sw');
  });

  testWidgets('caregiver', (t) async {
    await start(t, 'caregiver');
    await shot(t, 'app-helper');
  });
}
