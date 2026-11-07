// Appointments: book a clinic visit or a video call in 3 steps, join the call, reminders, cancel.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:safari_ya_mama/app/app.dart';
import 'package:safari_ya_mama/app/providers.dart';
import 'package:safari_ya_mama/core/dates.dart';
import 'package:safari_ya_mama/data/local_store.dart';
import 'package:safari_ya_mama/data/reminders.dart';
import 'package:safari_ya_mama/data/remote.dart';
import 'package:safari_ya_mama/state/app_state.dart';

import 'fakes.dart';

void main() {
  late LocalStore store;
  late FakeRemote remote;
  late List<Map<String, dynamic>> booked;
  final tomorrow10 = addDays(sod(DateTime.now()), 1).add(const Duration(hours: 10));

  Map<String, dynamic> slot(String id, DateTime at, String mode) => {
    'id': id,
    'starts_at': at.toUtc().toIso8601String(),
    'minutes': 20,
    'mode': mode,
    'staff_name': 'Nurse Asha',
  };

  setUp(() async {
    store = LocalStore();
    await store.open(inMemory: true);
    remote = FakeRemote();
    booked = [];
    remote.rpcHandlers['open_slots'] = (p) => [
      slot('s1', tomorrow10, p['p_mode'] as String),
      slot('s2', tomorrow10.add(const Duration(minutes: 20)), p['p_mode'] as String),
    ];
    remote.rpcHandlers['book_slot'] = (p) {
      final b = {
        'id': 'b${booked.length + 1}',
        'facility_id': 'f1',
        'starts_at': tomorrow10.toUtc().toIso8601String(),
        'minutes': 20,
        'mode': 'video',
        'reason': p['p_reason'],
        'status': 'booked',
        'facility_name': 'Sample Health Centre 1',
        'facility_phone': '+255700000001',
        'staff_name': 'Nurse Asha',
      };
      booked.add(b);
      return b;
    };
    remote.rpcHandlers['my_bookings'] = (_) => booked;
  });
  tearDown(() => Hive.close());

  Future<AppState> pump(WidgetTester t, {DateTime Function()? clock}) async {
    final s = AppState(store, remote: remote, clock: clock);
    await s.setLang('en');
    await s.completeOnboarding(name: 'Amina', stage: 'pregnant', lmp: addDays(sod(DateTime.now()), -150));
    await s.refreshFacilities();
    await s.setFacility({'id': 'f1', 'name': 'Sample Health Centre 1', 'phone': '+255700000001'});
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.75;
    addTearDown(t.view.reset);
    await t.pumpWidget(ProviderScope(overrides: [appStateProvider.overrideWith((ref) => s)], child: const SafariYaMamaApp()));
    await t.pumpAndSettle();
    return s;
  }

  Future<void> tap(WidgetTester t, String key) async {
    if (find.byKey(Key(key)).evaluate().isEmpty) {
      await t.scrollUntilVisible(find.byKey(Key(key)), 300, scrollable: find.byType(Scrollable).first);
    }
    await t.ensureVisible(find.byKey(Key(key)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(Key(key)));
    await t.pumpAndSettle();
  }

  testWidgets('from Home: video call in 3 steps, then it shows on Home', (t) async {
    final s = await pump(t);
    await tap(t, 'need-doctor');
    expect(find.text('See a health worker'), findsOneWidget);
    await tap(t, 'book-start');
    expect(find.text('Step 1 of 3'), findsOneWidget);
    await tap(t, 'mode-video');
    expect(find.text('Step 2 of 3'), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget);
    await tap(t, 'slot-s1');
    await tap(t, 'book-next');
    await t.enterText(find.byKey(const Key('book-reason')), 'Swollen feet');
    await t.pumpAndSettle();
    await tap(t, 'book-confirm');
    expect(find.textContaining('You are booked'), findsOneWidget);
    expect(find.byKey(const Key('join-call')), findsOneWidget);
    expect(booked.single['reason'], 'Swollen feet');
    expect(s.bookings.next?.id, 'b1');

    // back on Home: the next appointment is there
    await t.pageBack();
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Your next appointment'), findsOneWidget);
  });

  testWidgets('back inside the booking steps goes to the previous step, not out', (t) async {
    await pump(t);
    await tap(t, 'need-doctor');
    await tap(t, 'book-start');
    await tap(t, 'mode-clinic');
    expect(find.text('Step 2 of 3'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Step 1 of 3'), findsOneWidget);
  });

  testWidgets('someone took the time first: she is told and sees fresh times', (t) async {
    remote.rpcHandlers['book_slot'] = (_) => throw RemoteError('P0001: this time is no longer free');
    await pump(t);
    await tap(t, 'need-doctor');
    await tap(t, 'book-start');
    await tap(t, 'mode-clinic');
    await tap(t, 'slot-s2');
    await tap(t, 'book-next');
    await tap(t, 'book-confirm');
    expect(find.textContaining('Someone just took this time'), findsOneWidget);
    expect(find.text('Step 2 of 3'), findsOneWidget);
  });

  testWidgets('the call button works only from 15 minutes before', (t) async {
    remote.invokeHandlers['telemed-join'] = (_) => {'url': 'https://example.daily.co/room?t=x'};
    final s = await pump(t);
    await s.bookings.book(await s.bookings.openSlots('f1', 'video').then((l) => l.first));
    final b = s.bookings.next!;
    expect(b.canJoin(tomorrow10.subtract(const Duration(minutes: 20))), isFalse);
    expect(b.canJoin(tomorrow10.subtract(const Duration(minutes: 15))), isTrue);
    expect(b.canJoin(tomorrow10.add(const Duration(minutes: 49))), isTrue);
    expect(b.canJoin(tomorrow10.add(const Duration(minutes: 51))), isFalse);
    expect(await s.bookings.joinUrl(b.id), startsWith('https://'));
    expect(remote.invokeBodies.last, {'booking_id': 'b1'});
  });

  testWidgets('reminders: the evening before, and 30 minutes before a video call', (t) async {
    final s = await pump(t);
    await s.setFlag('phone_reminders', true);
    await s.bookings.book(await s.bookings.openSlots('f1', 'video').then((l) => l.first));
    final r = plannedReminders(s).where((x) => x.id >= 300).toList();
    expect(r.map((x) => x.en), ['Video call tomorrow at 10:00', 'Video call in 30 minutes. Find a quiet place.']);
    expect((r.first.on, r.first.hour), (sod(DateTime.now()), 18));
    expect((r.last.hour, r.last.minute), (9, 30));
  });

  testWidgets('cancel an appointment', (t) async {
    remote.rpcHandlers['cancel_booking'] = (p) {
      booked.firstWhere((b) => b['id'] == p['p_booking'])['status'] = 'cancelled';
      return null;
    };
    final s = await pump(t);
    await s.bookings.book(await s.bookings.openSlots('f1', 'video').then((l) => l.first));
    await t.pumpAndSettle();
    await tap(t, 'booking-b1');
    await tap(t, 'cancel-booking');
    await tap(t, 'confirm-cancel');
    expect(remote.calls, contains('rpc cancel_booking'));
    expect(s.bookings.next, isNull);
    expect(find.text('Your next appointment'), findsNothing);
  });

  testWidgets("after the visit she sees the health worker's advice", (t) async {
    final s = await pump(t);
    await s.bookings.book(await s.bookings.openSlots('f1', 'video').then((l) => l.first));
    booked.single
      ..['status'] = 'done'
      ..['starts_at'] = DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String()
      ..['outcome_note'] = 'Rest with your feet up. Come to the clinic on Monday for a BP check.';
    await s.bookings.refresh();
    await t.pumpAndSettle();
    await tap(t, 'need-doctor');
    await tap(t, 'booking-b1');
    expect(find.text("Health worker's advice"), findsOneWidget);
    expect(find.textContaining('Rest with your feet up'), findsOneWidget);
  });
}
