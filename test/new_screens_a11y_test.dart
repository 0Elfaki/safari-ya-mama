// Accessibility and small-screen checks for the Mothers' circle and telemedicine screens:
// tap targets ≥ 48dp, every tappable thing labelled, text contrast, and no overflow on a small
// phone with the largest system text, or in landscape.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:safari_ya_mama/app/app.dart';
import 'package:safari_ya_mama/app/providers.dart';
import 'package:safari_ya_mama/core/dates.dart';
import 'package:safari_ya_mama/data/local_store.dart';
import 'package:safari_ya_mama/features/community/domain/community_check.dart';
import 'package:safari_ya_mama/features/community/ui/community_name_screen.dart';
import 'package:safari_ya_mama/features/community/ui/compose_post_screen.dart';
import 'package:safari_ya_mama/features/community/ui/post_screen.dart';
import 'package:safari_ya_mama/features/telemedicine/ui/appointments_screen.dart';
import 'package:safari_ya_mama/features/telemedicine/ui/book_screen.dart';
import 'package:safari_ya_mama/state/app_state.dart';

import 'fakes.dart';

void main() {
  late LocalStore store;
  late FakeRemote remote;
  final tomorrow10 = addDays(sod(DateTime.now()), 1).add(const Duration(hours: 10));
  final now = DateTime.now().toUtc();

  Map<String, dynamic> post(String id, String body, {List<String> facts = const [], String? name, String? note, bool mine = false, String status = 'published'}) => {
    'id': id,
    'topic': 'pregnancy',
    'body': body,
    'anonymous': name == null,
    'author_name': name,
    'stage_kind': 'pregnant',
    'stage_value': 34,
    'status': status,
    'facts': facts,
    'health_note': note,
    'checked': note != null,
    'helpful_count': 12,
    'reply_count': 3,
    'created_at': now.subtract(const Duration(hours: 5)).toIso8601String(),
    'mine': mine,
  };

  setUp(() async {
    store = LocalStore();
    await store.open(inMemory: true);
    remote = FakeRemote();
    await CommunityRules.load();
    remote.rpcResults['community_feed'] = [
      post('p1', 'Is it true I should stop the iron tablets in the last month?', facts: ['stop-iron']),
      post('p2', 'Walking every evening helped my back.', name: 'MamaJasiri_2025', note: 'Good advice. Walk on flat ground.'),
      post('p3', 'My first post', mine: true, status: 'review', name: 'Neema'),
    ];
    remote.rpcResults['community_thread'] = {
      'post': post('p2', 'Walking every evening helped my back.', name: 'MamaJasiri_2025'),
      'replies': [post('r1', 'Thank you, I will try it.')],
    };
    final booking = {
      'id': 'b1',
      'starts_at': tomorrow10.toUtc().toIso8601String(),
      'minutes': 20,
      'mode': 'video',
      'reason': 'Swollen feet in the evening',
      'status': 'booked',
      'facility_name': 'Mwananyamala Regional Referral Hospital',
      'facility_phone': '+255700000001',
      'staff_name': 'Nurse Asha Mwakalinga',
      'outcome_note': null,
    };
    remote.rpcResults['my_bookings'] = [booking];
    remote.rpcHandlers['open_slots'] = (p) => [
      for (var d = 1; d <= 6; d++)
        for (var i = 0; i < 6; i++)
          {'id': 's$d$i', 'starts_at': addDays(sod(DateTime.now()), d).add(Duration(hours: 9, minutes: 20 * i)).toUtc().toIso8601String(), 'minutes': 20, 'mode': p['p_mode'], 'staff_name': 'Nurse Asha'},
    ];
  });
  tearDown(() => Hive.close());

  /// Small Android phone (360 × 640 dp) by default.
  Future<AppState> pump(WidgetTester t, {Size dp = const Size(360, 640), double text = 1.0}) async {
    final s = AppState(store, remote: remote);
    await s.setLang('en');
    await s.completeOnboarding(name: 'Amina', stage: 'pregnant', lmp: addDays(sod(DateTime.now()), -238));
    await s.refreshFacilities();
    await s.setFacility({'id': 'f1', 'name': 'Mwananyamala Regional Referral Hospital', 'phone': '+255700000001'});
    t.view.devicePixelRatio = 3;
    t.view.physicalSize = dp * 3;
    t.platformDispatcher.textScaleFactorTestValue = text;
    addTearDown(t.view.reset);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpWidget(ProviderScope(overrides: [appStateProvider.overrideWith((ref) => s)], child: const SafariYaMamaApp()));
    await t.pumpAndSettle();
    return s;
  }

  Future<void> push(WidgetTester t, Widget w) async {
    t.state<NavigatorState>(find.byType(Navigator).first).push(MaterialPageRoute(builder: (_) => w));
    await t.pumpAndSettle();
  }

  /// Scrolls the screen until [key] is built (long screens at large text sizes).
  Future<Finder> reveal(WidgetTester t, String key) async {
    final f = find.byKey(Key(key));
    if (f.evaluate().isEmpty) await t.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).last);
    return f;
  }

  // Each screen, reached the way a mother reaches it.
  final screens = <String, Future<void> Function(WidgetTester)>{
    'community feed': (t) async {
      await t.tap(find.byKey(const Key('tab-community')));
      await t.pumpAndSettle();
    },
    'new post with hints': (t) async {
      await push(t, const ComposePostScreen());
      await t.enterText(find.byKey(const Key('compose-body')), 'My aunt says give the baby water from 2 months. I have heavy bleeding too.');
      await t.pumpAndSettle();
    },
    'community name': (t) async {
      await push(t, const CommunityNameScreen());
      await t.enterText(await reveal(t, 'handle-field'), 'DrAmina');
      await t.pumpAndSettle();
    },
    'post and replies': (t) async => push(t, const PostScreen('p2')),
    'appointments': (t) async => push(t, const AppointmentsScreen()),
    'book step 1': (t) async => push(t, const BookScreen()),
    'book step 2': (t) async {
      await push(t, const BookScreen());
      await t.tap(find.byKey(const Key('mode-video')));
      await t.pumpAndSettle();
    },
    'appointment': (t) async {
      await push(t, const AppointmentsScreen());
      await t.tap(await reveal(t, 'booking-b1'));
      await t.pumpAndSettle();
    },
  };

  for (final MapEntry(key: name, value: open) in screens.entries) {
    group(name, () {
      testWidgets('tap targets, labels and contrast', (t) async {
        final h = t.ensureSemantics();
        await pump(t);
        await open(t);
        await expectLater(t, meetsGuideline(androidTapTargetGuideline));
        await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(t, meetsGuideline(textContrastGuideline));
        h.dispose();
      });

      testWidgets('small phone with the largest text: nothing overflows', (t) async {
        await pump(t, text: 2.0);
        await open(t);
        expect(t.takeException(), isNull);
      });

      testWidgets('landscape: nothing overflows', (t) async {
        await pump(t, dp: const Size(780, 360));
        await open(t);
        expect(t.takeException(), isNull);
      });
    });
  }
}
