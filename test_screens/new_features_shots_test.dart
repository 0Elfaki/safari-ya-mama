// Review screenshots of the Mothers' circle, appointments and the new Home (made-up data). Run:
//   flutter test test_screens/new_features_shots_test.dart --update-goldens
// Output: test_screens/review/*.png
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:safari_ya_mama/app/app.dart';
import 'package:safari_ya_mama/app/providers.dart';
import 'package:safari_ya_mama/features/community/domain/community_check.dart';
import 'package:safari_ya_mama/core/content_assets.dart';
import 'package:safari_ya_mama/core/dates.dart';
import 'package:safari_ya_mama/data/local_store.dart';
import 'package:safari_ya_mama/state/app_state.dart';
import 'package:safari_ya_mama/state/demo_seed.dart';
import 'package:safari_ya_mama/features/telemedicine/ui/appointments_screen.dart';
import 'package:safari_ya_mama/features/telemedicine/ui/book_screen.dart';
import 'package:safari_ya_mama/features/community/ui/community_name_screen.dart';
import 'package:safari_ya_mama/features/community/ui/compose_post_screen.dart';

import '../test/fakes.dart';

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
    await CommunityRules.load();
  });

  final tomorrow10 = addDays(sod(DateTime.now()), 1).add(const Duration(hours: 10));
  final now = DateTime.now().toUtc();
  Map<String, dynamic> post(String id, String body, {String topic = 'pregnancy', List<String> facts = const [], String? name, String? note, int weeks = 28, bool mine = false, String status = 'published', int h = 2}) => {
    'id': id,
    'topic': topic,
    'body': body,
    'show_name': name,
    'stage_kind': 'pregnant',
    'stage_value': weeks,
    'status': status,
    'facts': facts,
    'staff_post': false,
    'health_note': note,
    'checked': note != null,
    'helpful_count': 4,
    'reply_count': 2,
    'created_at': now.subtract(Duration(hours: h)).toIso8601String(),
    'mine': mine,
    'helped': false,
  };

  Future<AppState> start(WidgetTester t) async {
    final store = LocalStore();
    await store.open(inMemory: true);
    final remote = FakeRemote();
    remote.rpcResults['community_feed'] = [
      post('p1', 'Is it true I should stop the iron tablets in the last month? My neighbour says they make the baby too big.', facts: ['stop-iron'], weeks: 34, h: 1),
      post('p2', 'Walking every evening helped my back pain a lot. 20 minutes after supper.', name: 'Neema', note: 'Good advice. Walk on flat ground and stop if you feel dizzy.', weeks: 26, h: 5),
      post('p3', 'My first post here. Hello mothers!', status: 'review', mine: true, name: 'Amina', h: 0),
    ];
    remote.rpcHandlers['open_slots'] = (p) => [
      for (var d = 1; d <= 3; d++)
        for (var i = 0; i < 5; i++)
          {
            'id': 's$d$i',
            'starts_at': addDays(sod(DateTime.now()), d).add(Duration(hours: 9, minutes: 20 * i)).toUtc().toIso8601String(),
            'minutes': 20,
            'mode': p['p_mode'],
            'staff_name': 'Nurse Asha',
          },
    ];
    final s = AppState(store, remote: remote);
    await s.seedDemo('pregnant');
    await s.refreshFacilities();
    await s.setFacility({'id': 'f1', 'name': 'Mwananyamala Health Centre', 'phone': '+255700000001'});
    await s.setLang('en');
    final mine = [
      {
        'id': 'b1',
        'starts_at': tomorrow10.toUtc().toIso8601String(),
        'minutes': 20,
        'mode': 'video',
        'reason': 'Swollen feet in the evening',
        'status': 'booked',
        'facility_name': 'Mwananyamala Health Centre',
        'facility_phone': '+255700000001',
        'staff_name': 'Nurse Asha',
      },
    ];
    await store.setMeta('bookings', mine);
    remote.rpcResults['my_bookings'] = mine;
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
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('review/$name.png'));
  }

  Future<void> push(WidgetTester t, Widget w) async {
    t.state<NavigatorState>(find.byType(Navigator).first).push(MaterialPageRoute(builder: (_) => w));
    await t.pumpAndSettle();
  }

  testWidgets('new feature screens', (t) async {
    await start(t);
    await shot(t, '01_home_top');
    await t.tap(find.byKey(const Key('open-menu')));
    await shot(t, '00_side_menu');
    await t.tap(find.byKey(const Key('menu-home')));
    await t.pumpAndSettle();
    await t.drag(find.byType(Scrollable).first, const Offset(0, -700));
    await shot(t, '02_home_help_tiles');
    await t.tap(find.byKey(const Key('tab-community')));
    await t.pumpAndSettle();
    await shot(t, '03_community_feed');
    await t.drag(find.byKey(const Key('community-feed')), const Offset(0, -900));
    await shot(t, '04_community_feed_more');
    await push(t, const ComposePostScreen());
    await t.enterText(find.byKey(const Key('compose-body')), 'My aunt says give the baby water from 2 months when it is hot.');
    await shot(t, '05_compose_myth');
    await t.enterText(find.byKey(const Key('compose-body')), 'I have heavy bleeding since this morning');
    await shot(t, '06_compose_danger');
    await t.pageBack();
    await t.pumpAndSettle();
    await push(t, const AppointmentsScreen());
    await shot(t, '07_appointments');
    await push(t, const BookScreen());
    await shot(t, '08_book_step1');
    await t.tap(find.byKey(const Key('mode-video')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('slot-s11')));
    await shot(t, '09_book_step2');
    await t.tap(find.byKey(const Key('book-next')));
    await shot(t, '10_book_step3');
    await t.pageBack();
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('booking-b1')));
    await shot(t, '11_booking_video');
  });

  testWidgets('community name and post-as choice', (t) async {
    await start(t);
    await push(t, const CommunityNameScreen());
    await t.enterText(find.byKey(const Key('handle-field')), 'DrAmina');
    await shot(t, '12_name_reserved');
    await t.pageBack();
    await t.pumpAndSettle();
    await push(t, const ComposePostScreen());
    await t.enterText(find.byKey(const Key('compose-body')), 'Walking after supper helps my back a lot. Does anyone else do this?');
    await t.drag(find.byType(Scrollable).last, const Offset(0, -500));
    await shot(t, '13_compose_post_as');
  });

  testWidgets('welcome and sign-in pictures', (t) async {
    await Hive.close(); // a fresh phone: nobody signed in yet
    final store = LocalStore();
    await store.open(inMemory: true);
    final s = AppState(store, remote: FakeRemote()..uid = null);
    await s.setLang('en');
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(overrides: [appStateProvider.overrideWith((ref) => s)], child: const SafariYaMamaApp()));
    await t.pumpAndSettle();
    await shot(t, '14_welcome');
    await t.tap(find.byKey(const Key('get-started')));
    await t.pumpAndSettle();
    await shot(t, '15_signin');
  });
}
