// Visual audit: renders every screen with the real fonts and icons and writes a PNG per screen
// to test_screens/shots/. Run:
//   flutter test test_screens/audit_test.dart --update-goldens
// Not part of `flutter test` (it lives outside test/); the PNGs are for review, not comparison.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safari_ya_mama/app/app.dart';
import 'package:safari_ya_mama/app/providers.dart';
import 'package:safari_ya_mama/core/content.dart';
import 'package:safari_ya_mama/core/content_assets.dart';
import 'package:safari_ya_mama/data/local_store.dart';
import 'package:safari_ya_mama/state/app_state.dart';
import 'package:safari_ya_mama/state/demo_seed.dart';
import 'package:safari_ya_mama/ui/screens/birth_plan_screen.dart';
import 'package:safari_ya_mama/ui/screens/body_check_screen.dart';
import 'package:safari_ya_mama/ui/screens/bp_screen.dart';
import 'package:safari_ya_mama/ui/screens/checkin_screen.dart';
import 'package:safari_ya_mama/ui/screens/child_profile_screen.dart';
import 'package:safari_ya_mama/ui/screens/doctor_note_screen.dart';
import 'package:safari_ya_mama/ui/screens/emergency_screen.dart';
import 'package:safari_ya_mama/ui/screens/first_aid_screen.dart';
import 'package:safari_ya_mama/ui/screens/journal_screen.dart';
import 'package:safari_ya_mama/ui/screens/journey_screen.dart';
import 'package:safari_ya_mama/ui/screens/library_screen.dart';
import 'package:safari_ya_mama/ui/screens/notifications_screen.dart';
import 'package:safari_ya_mama/ui/screens/nutrition_screen.dart';
import 'package:safari_ya_mama/ui/screens/visits_screen.dart';

const _size = Size(400, 1400); // phone width, tall so one shot shows most of a screen

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
  final icons = FontLoader('MaterialIcons')..addFont(file('$root/bin/cache/artifacts/material_fonts/materialicons-regular.otf'));
  await icons.load();
}

void main() {
  setUpAll(() async {
    await _loadFonts();
    await ContentAssets.load();
  });

  Future<AppState> start(WidgetTester t, String? demo, {String lang = 'en'}) async {
    final store = LocalStore();
    await store.open(inMemory: true);
    final s = AppState(store);
    if (demo != null) await s.seedDemo(demo);
    await s.setLang(lang);
    t.view.physicalSize = _size * 1.5;
    t.view.devicePixelRatio = 1.5;
    addTearDown(t.view.reset);
    t.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await t.pumpWidget(ProviderScope(overrides: [appStateProvider.overrideWith((ref) => s)], child: const SafariYaMamaApp()));
    await t.pumpAndSettle();
    return s;
  }

  Future<void> shot(WidgetTester t, String name) async {
    await t.pumpAndSettle();
    // decode pictures for real (widget tests do not wait for image loading)
    await t.runAsync(() async {
      for (final e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/$name.png'));
  }

  Future<void> push(WidgetTester t, Widget w) async {
    t.state<NavigatorState>(find.byType(Navigator).first).push(MaterialPageRoute(builder: (_) => w));
    await t.pumpAndSettle();
  }

  Future<void> tab(WidgetTester t, String key) async {
    await t.tap(find.byKey(Key(key)));
    await t.pumpAndSettle();
  }

  group('onboarding', () {
    testWidgets('welcome and five steps', (t) async {
      await start(t, null);
      await shot(t, '01_welcome');
      await t.tap(find.byKey(const Key('get-started')));
      await t.pumpAndSettle();
      await shot(t, '02_onboarding_1_name');
      await t.enterText(find.byKey(const Key('ob-name')), 'Amina');
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('ob-next')));
      await t.pumpAndSettle();
      await shot(t, '03_onboarding_2_pregnancy');
      await t.tap(find.byKey(const Key('ob-next')));
      await t.pumpAndSettle();
      await shot(t, '04_onboarding_3_contacts');
      await t.tap(find.byKey(const Key('ob-next')));
      await t.pumpAndSettle();
      await shot(t, '05_onboarding_4_consent');
      await t.tap(find.byKey(const Key('consent-data')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('ob-next')));
      await t.pumpAndSettle();
      await shot(t, '06_onboarding_5_pin');
    });
  });

  group('pregnant mother', () {
    testWidgets('tabs', (t) async {
      await start(t, 'pregnant');
      await shot(t, '10_home_pregnant');
      await tab(t, 'tab-journey');
      await shot(t, '11_mycare_mother_pregnant');
      await t.tap(find.text('Baby'));
      await t.pumpAndSettle();
      await shot(t, '12_mycare_baby_pregnant');
      await tab(t, 'tab-mamabot');
      await shot(t, '13_mamabot');
      await tab(t, 'tab-learn');
      await shot(t, '14_learn');
      await t.enterText(find.byKey(const Key('learn-search')), 'breast');
      await t.pumpAndSettle();
      await shot(t, '15_learn_search');
      await tab(t, 'open-menu');
      await tab(t, 'open-profile');
      await shot(t, '16_profile');
    });

    testWidgets('pushed screens', (t) async {
      final s = await start(t, 'pregnant');
      await push(t, const EmergencyScreen());
      await shot(t, '20_emergency');
      await push(t, const EmergencyContactsScreen());
      await shot(t, '21_emergency_contacts');
      await push(t, const DoctorNoteScreen());
      await t.tap(find.byKey(const Key('note-consent')));
      await shot(t, '22_doctor_note');
      await push(t, const SymptomDiaryScreen());
      await shot(t, '23_symptom_diary');
      await s.logMovement('fewer');
      await push(t, const MovementsScreen());
      await shot(t, '24_movements_fewer');
      await push(t, const ContractionTimerScreen());
      await shot(t, '25_contractions');
      await push(t, const CheckinScreen());
      await shot(t, '26_checkin');
      await push(t, const LessonScreen('danger-preg'));
      await shot(t, '27_lesson');
      await push(
        t,
        Scaffold(
          appBar: AppBar(title: const Text('Clinic visits')),
          body: const VisitsScreen(),
        ),
      );
      await shot(t, '28_visits');
      await push(t, const BirthPlanScreen());
      await shot(t, '29_birth_plan');
      await push(t, const BpScreen());
      await shot(t, '30_bp');
      await push(t, const NutritionScreen());
      await shot(t, '31_nutrition');
      await push(t, const JournalScreen());
      await shot(t, '32_journal');
      await push(t, const LibraryScreen());
      await shot(t, '33_library');
      await push(t, const BodyCheckScreen());
      await shot(t, '34_body_check');
      await s.setFlag('phone_reminders', true);
      await push(t, const NotificationsScreen());
      await shot(t, '35_notifications');
    });

    testWidgets('red result', (t) async {
      final s = await start(t, 'pregnant');
      final r = await s.submitCheckin(s.checkinInput(feeling: 'unwell', signs: {'headache', 'vision'}, movement: 'normal'));
      await push(t, CheckinResultScreen(r));
      await shot(t, '36_result_red');
      expect(r.level, Level.red);
    });
  });

  group('baby', () {
    testWidgets('tabs and baby screens', (t) async {
      await start(t, 'baby');
      await shot(t, '40_home_baby');
      await tab(t, 'tab-journey');
      await shot(t, '41_mycare_baby');
      await t.tap(find.text('Mother'));
      await t.pumpAndSettle();
      await shot(t, '42_mycare_mother_postnatal');
      await push(t, const ChildProfileScreen());
      await shot(t, '43_child_profile');
      await push(t, const FirstAidHubScreen());
      await shot(t, '44_first_aid');
      await push(t, const FirstAidHubScreen(initialTab: 1));
      await shot(t, '45_spot_the_signs');
      await push(t, const EmergencyScreen());
      await shot(t, '46_emergency_baby');
    });

    testWidgets('Kiswahili home', (t) async {
      await start(t, 'baby', lang: 'sw');
      await shot(t, '47_home_baby_sw');
    });
  });

  testWidgets('delivered pictures', (t) async {
    await start(t, 'baby');
    await push(t, const LessonScreen('safe-sleep'));
    await shot(t, '60_lesson_safe_sleep_p1');
    await push(t, const LessonScreen('solids'));
    await shot(t, '61_lesson_solids_p1');
  });

  testWidgets('caregiver', (t) async {
    await start(t, 'caregiver');
    await shot(t, '50_caregiver_home');
  });

  testWidgets('lock screen', (t) async {
    final s = await start(t, 'pregnant');
    await s.setPin('1234');
    s.lock();
    await t.pumpAndSettle();
    await shot(t, '51_lock');
  });
}
