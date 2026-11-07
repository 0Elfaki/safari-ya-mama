// Encrypted Doctor's Note sharing, phone reminders, and the router's one-way doors.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:safari_ya_mama/app/app.dart';
import 'package:safari_ya_mama/app/providers.dart';
import 'package:safari_ya_mama/core/dates.dart';
import 'package:safari_ya_mama/core/note_share.dart';
import 'package:safari_ya_mama/data/local_store.dart';
import 'package:safari_ya_mama/data/reminders.dart';
import 'package:safari_ya_mama/state/app_state.dart';

import 'fakes.dart';

void main() {
  late LocalStore store;
  setUp(() async {
    store = LocalStore();
    await store.open(inMemory: true);
  });
  tearDown(() => Hive.close());

  group('encrypted note', () {
    test('seal then open gives the same note; the server copy is unreadable', () async {
      final note = {
        'v': 1,
        'name': 'Amina',
        'sections': [
          {
            'letter': 'S',
            'rows': ['Pregnant, 28 weeks'],
          },
        ],
      };
      final sealed = await sealNote(note);
      expect(sealed.ciphertext.contains('Amina'), isFalse);
      expect(sealed.key.length, 43, reason: '32-byte key, base64url without padding');
      expect(await openNote(sealed.ciphertext, sealed.key), note);
    });

    test('a wrong key or a changed ciphertext cannot open the note', () async {
      final a = await sealNote({'x': 1});
      final b = await sealNote({'x': 1});
      expect(() => openNote(a.ciphertext, b.key), throwsA(anything));
      final bytes = a.ciphertext.codeUnits.toList();
      bytes[20] = bytes[20] == 65 ? 66 : 65;
      expect(() => openNote(String.fromCharCodes(bytes), a.key), throwsA(anything));
    });

    test('QR text round-trips and rejects anything else', () async {
      final sealed = await sealNote({'x': 1});
      const id = '3f1c8a52-1b6e-4a51-9b7e-2d1e4c0a9f10';
      final qr = shareQrPayload(id, sealed.key);
      expect(qr, startsWith('SYM2:$id.'));
      expect(parseShareQr(qr), (id, sealed.key));
      expect(parseShareQr('SYM1:abc'), isNull);
      expect(parseShareQr('https://example.com'), isNull);
    });

    test('createNoteShare uploads only ciphertext and returns a QR with the key', () async {
      final remote = FakeRemote();
      final s = AppState(store, remote: remote);
      const id = '3f1c8a52-1b6e-4a51-9b7e-2d1e4c0a9f10';
      remote.rpcResults['create_note_share'] = [
        {'id': id, 'expires_at': DateTime.now().add(const Duration(hours: 24)).toUtc().toIso8601String()},
      ];
      final r = await s.createNoteShare({'name': 'Amina', 'secret': 'headache'}, ['symptoms'], hours: 24);
      expect(remote.calls, contains('rpc create_note_share'));
      final (gotId, key) = parseShareQr(r.qr)!;
      expect(gotId, id);
      expect(key.length, 43);
      expect(r.share.active, isTrue);
    });

    test('signed out: sharing is refused before anything is sent', () async {
      final remote = FakeRemote()..uid = null;
      final s = AppState(store, remote: remote);
      expect(() => s.createNoteShare({'a': 1}, const []), throwsA(anything));
      expect(remote.calls, isEmpty);
    });
  });

  group('phone reminders', () {
    Future<AppState> pregnant(int weeks) async {
      final s = AppState(store);
      await s.completeOnboarding(name: 'Amina', stage: 'pregnant', lmp: addDays(sod(DateTime.now()), -weeks * 7));
      return s;
    }

    test('off until she turns them on', () async {
      final s = await pregnant(28);
      expect(plannedReminders(s), isEmpty);
    });

    test('pregnant at 28 weeks: daily check, tablet, movements, and the evening before visits', () async {
      final s = await pregnant(28);
      await s.setFlag('phone_reminders', true);
      await s.setReminderTime('tablet', '07:30');
      final p = plannedReminders(s);
      expect(p.where((r) => r.daily).map((r) => r.id), [1, 2, 3]);
      final tablet = p.firstWhere((r) => r.id == 2);
      expect((tablet.hour, tablet.minute), (7, 30));
      final visits = p.where((r) => r.id >= 100 && r.id < 200).toList();
      expect(visits, isNotEmpty);
      for (final v in visits) {
        expect((v.hour, v.minute), (18, 0));
        expect(v.on!.isAfter(sod(DateTime.now()).subtract(const Duration(days: 1))), isTrue);
      }
    });

    test('before 20 weeks there is no movements reminder', () async {
      final s = await pregnant(12);
      await s.setFlag('phone_reminders', true);
      expect(plannedReminders(s).map((r) => r.id), isNot(contains(3)));
    });

    test('lock-screen details are off by default', () async {
      final s = await pregnant(28);
      expect(s.reminderDetails, isFalse);
    });
  });

  group('router guards', () {
    Future<AppState> pump(WidgetTester t, AppState s) async {
      await s.setLang('en');
      t.view.physicalSize = const Size(1080, 2340);
      t.view.devicePixelRatio = 2.75;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(overrides: [appStateProvider.overrideWith((ref) => s)], child: const SafariYaMamaApp()));
      await t.pumpAndSettle();
      return s;
    }

    testWidgets('new user lands on Welcome; Emergency is reachable before onboarding', (t) async {
      await pump(t, AppState(store));
      expect(find.byKey(const Key('get-started')), findsOneWidget);
      await t.tap(find.byKey(const Key('emergency')));
      await t.pumpAndSettle();
      expect(find.text('Need urgent help?'), findsOneWidget);
    });

    testWidgets('PIN lock: the lock screen replaces everything, and unlock returns Home', (t) async {
      final s = AppState(store);
      await s.completeOnboarding(name: 'Amina', stage: 'pregnant', lmp: addDays(sod(DateTime.now()), -100));
      await s.setPin('2468');
      s.lock();
      await pump(t, s);
      expect(find.text('Enter your PIN'), findsOneWidget);
      expect(find.byKey(const Key('tab-home')), findsNothing);
      s.unlock('2468');
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tab-home')), findsOneWidget);
      expect(find.text('Hello, Amina'), findsOneWidget);
    });

    testWidgets('Home bell opens Notifications with phone reminders off', (t) async {
      final s = AppState(store);
      await s.completeOnboarding(name: 'Amina', stage: 'pregnant', lmp: addDays(sod(DateTime.now()), -200));
      await pump(t, s);
      await t.tap(find.byKey(const Key('open-notifications')));
      await t.pumpAndSettle();
      expect(find.text('Phone reminders'), findsOneWidget);
      expect(t.widget<SwitchListTile>(find.byKey(const Key('phone-reminders'))).value, isFalse);
    });
  });
}
