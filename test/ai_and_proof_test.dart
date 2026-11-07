// AI assistant gateway (scripted fallback, urgent routing) and "My verifiable record". No network:
// the gateway and the RPC are injected fakes.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:go_router/go_router.dart';
import 'package:safari_ya_mama/state/app_scope.dart';
import 'package:safari_ya_mama/core/assistant.g.dart';
import 'package:safari_ya_mama/core/record_proof.dart';
import 'package:safari_ya_mama/data/ai_client.dart';
import 'package:safari_ya_mama/data/local_store.dart';
import 'package:safari_ya_mama/state/app_state.dart';
import 'package:safari_ya_mama/ui/screens/assistant_screen.dart';
import 'package:safari_ya_mama/ui/screens/record_proof_screen.dart';

import 'fakes.dart';

const hash = 'ABCDEF0123456789abcdef0123456789ABCDEF0123456789abcdef0123456789';
const plain = 'What songs can I sing to my baby?';

void main() {
  late LocalStore store;
  setUp(() async {
    store = LocalStore();
    await store.open(inMemory: true);
  });
  tearDown(() => Hive.close());

  Future<AppState> state({bool remote = false}) async {
    final s = AppState(store, remote: remote ? FakeRemote() : null);
    await s.setLang('en');
    return s;
  }

  Future<void> pump(WidgetTester t, AppState s, Widget home) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.75;
    addTearDown(t.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => home),
        GoRoute(
          path: '/emergency',
          builder: (_, _) => const Scaffold(body: Text('EMERGENCY SCREEN')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await t.pumpWidget(
      AppScope(
        state: s,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> ask(WidgetTester t, String q) async {
    await t.enterText(find.byType(TextField), q);
    await t.tap(find.byIcon(Icons.send));
    await t.pumpAndSettle();
  }

  group('AI reply parsing and helpers', () {
    test('answer, urgent and unavailable bodies', () {
      final a = AiReply.fromJson({'text': 'Hi — AI answer · not medical advice', 'label': 'AI answer', 'urgent': false});
      expect(a!.urgent, isFalse);
      expect(a.label, 'AI answer');
      final u = AiReply.fromJson({'text': 'Go now', 'label': 'Safety message · not AI', 'urgent': true, 'action': 'emergency'});
      expect(u!.urgent, isTrue);
      expect(AiReply.fromJson({'text': null, 'unavailable': true, 'reason': 'no_key'}), isNull);
      expect(AiReply.fromJson({'error': 'rate limited'}), isNull);
      expect(AiReply.fromJson(null), isNull);
    });
    test('gateway stage', () {
      expect(gatewayStage(pregnant: true, babyDays: 0), 'pregnant');
      expect(gatewayStage(pregnant: false, babyDays: 10), 'postpartum');
      expect(gatewayStage(pregnant: false, babyDays: 90), 'baby');
    });
    test('QR content is SYM1: + lowercase hex, and rejects anything else', () {
      expect(recordQrPayload(hash), 'SYM1:${hash.toLowerCase()}');
      expect(recordQrPayload(hash), matches(RegExp(r'^SYM1:[0-9a-f]{64}$')));
      expect(() => recordQrPayload('xyz'), throwsFormatException);
      expect(() => recordQrPayload('${hash}0'), throwsFormatException);
    });
    test('proof row from the RPC', () {
      final p = RecordProof.fromRpc([
        {
          'proof_id': 'prf_1234567890',
          'record_hash': hash,
          'ledger_seq': 7,
          'issued_at': '2026-11-01T08:00:00Z',
          'record_doc': {
            'vaccines': [
              {'vaccine_key': 'bcg', 'due_on': '2026-10-01', 'given_on': '2026-10-01'},
            ],
            'visits': [
              {'kind': 'pnc', 'contact_no': 1, 'due_on': '2026-10-03', 'attended_on': null},
            ],
          },
        },
      ]);
      expect(p.qrPayload, 'SYM1:${hash.toLowerCase()}');
      expect(p.shortId, 'prf_1234');
      expect(p.ledgerSeq, 7);
      expect(p.vaccines.single.key, 'bcg');
      expect(p.visits.single.contactNo, 1);
      expect(() => RecordProof.fromRpc(const []), throwsFormatException);
    });
  });

  group('assistant', () {
    testWidgets('no backend: scripted answer with the Simulated label, no AI note', (t) async {
      final s = await state();
      await pump(t, s, const AssistantScreen());
      await ask(t, plain);
      expect(find.text(s.tr(answerFor(plain).answer)), findsOneWidget);
      expect(find.text('Simulated: scripted answers'), findsOneWidget);
      expect(find.byKey(const Key('ai-note')), findsNothing);
      expect(find.byKey(const Key('ai-label')), findsNothing);
    });

    testWidgets('urgent question routes to Emergency help offline and never reaches the gateway', (t) async {
      final s = await state(remote: true);
      var calls = 0;
      Future<AiReply?> gw(String q, String l, String st) async {
        calls++;
        return null;
      }

      await pump(t, s, AssistantScreen(gateway: gw));
      await ask(t, 'I am bleeding');
      expect(calls, 0);
      expect(find.byKey(const Key('assistant-emergency')), findsOneWidget);
      await t.tap(find.byKey(const Key('assistant-emergency')));
      await t.pumpAndSettle();
      expect(find.text('EMERGENCY SCREEN'), findsOneWidget);
    });

    testWidgets('gateway "urgent" reply shows its text, label and the Emergency button', (t) async {
      final s = await state(remote: true);
      String? sentQ, sentStage;
      Future<AiReply?> gw(String q, String l, String st) async {
        sentQ = q;
        sentStage = st;
        return AiReply.fromJson({'text': 'Please go to the facility now.', 'label': 'Safety message · not AI', 'urgent': true, 'action': 'emergency'});
      }

      await pump(t, s, AssistantScreen(gateway: gw));
      expect(find.byKey(const Key('ai-note')), findsOneWidget);
      await ask(t, plain);
      expect(sentQ, plain);
      expect(sentStage, 'pregnant');
      expect(find.text('Please go to the facility now.'), findsOneWidget);
      expect(find.text('Safety message · not AI'), findsOneWidget);
      expect(find.byKey(const Key('assistant-emergency')), findsOneWidget);
    });

    testWidgets('gateway answer shows verbatim with its label', (t) async {
      final s = await state(remote: true);
      Future<AiReply?> gw(String q, String l, String st) async =>
          AiReply.fromJson({'text': 'Singing is good. — AI answer · not medical advice', 'label': 'AI answer', 'urgent': false});
      await pump(t, s, AssistantScreen(gateway: gw));
      await ask(t, plain);
      expect(find.text('Singing is good. — AI answer · not medical advice'), findsOneWidget);
      expect(find.byKey(const Key('ai-label')), findsOneWidget);
      expect(find.byKey(const Key('assistant-emergency')), findsNothing);
    });

    testWidgets('gateway "unavailable" or an error falls back to the scripted answer', (t) async {
      final s = await state(remote: true);
      var n = 0;
      Future<AiReply?> gw(String q, String l, String st) async {
        n++;
        if (n == 2) throw Exception('500');
        return AiReply.fromJson({'text': null, 'unavailable': true, 'reason': 'not_configured'});
      }

      await pump(t, s, AssistantScreen(gateway: gw));
      await ask(t, plain);
      expect(find.text(s.tr(answerFor(plain).answer)), findsOneWidget);
      expect(find.text('Simulated: scripted answer'), findsOneWidget);
      await ask(t, plain);
      expect(n, 2);
      expect(find.byKey(const Key('ai-label')), findsNothing);
      expect(find.byKey(const Key('ai-pending')), findsNothing);
    });

    testWidgets('not signed in: the gateway is not used', (t) async {
      final s = await state();
      var calls = 0;
      Future<AiReply?> gw(String q, String l, String st) async {
        calls++;
        return null;
      }

      await pump(t, s, AssistantScreen(gateway: gw));
      await ask(t, plain);
      expect(calls, 0);
      expect(find.text(s.tr(answerFor(plain).answer)), findsOneWidget);
    });
  });

  group('my verifiable record', () {
    testWidgets('without a backend it says sign-in and a connection are needed', (t) async {
      final s = await state();
      await pump(t, s, const RecordProofScreen());
      expect(find.byKey(const Key('proof-needs-signin')), findsOneWidget);
      expect(find.byKey(const Key('proof-create')), findsNothing);
    });

    testWidgets('signed in: creates the QR and lists vaccines and visits', (t) async {
      final r = FakeRemote();
      r.rpcResults['my_record_proof'] = [
        {
          'proof_id': 'prf_abcdefgh123',
          'record_hash': hash,
          'ledger_seq': 3,
          'issued_at': '2026-11-01T08:00:00Z',
          'record_doc': {
            'vaccines': [
              {'vaccine_key': 'bcg', 'due_on': '2026-10-01', 'given_on': '2026-10-02'},
            ],
            'visits': [
              {'kind': 'anc', 'contact_no': 2, 'due_on': '2026-09-01', 'attended_on': '2026-09-01'},
            ],
          },
        },
      ];
      final s = AppState(store, remote: r);
      await s.setLang('en');
      await pump(t, s, const RecordProofScreen());
      await t.tap(find.byKey(const Key('proof-create')));
      await t.pumpAndSettle();
      expect(r.calls, contains('rpc my_record_proof'));
      expect(find.byKey(const Key('proof-qr')), findsOneWidget);
      expect(find.text('Proof prf_abcd'), findsOneWidget);
      await t.scrollUntilVisible(find.text('Pregnancy clinic visit 2'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('BCG'), findsOneWidget);
      expect(find.text('Pregnancy clinic visit 2'), findsOneWidget);
    });

    testWidgets('signed in but the RPC fails: a clear message, no crash', (t) async {
      final r = FakeRemote();
      final s = AppState(store, remote: r);
      await s.setLang('en');
      await pump(t, s, const RecordProofScreen());
      await t.tap(find.byKey(const Key('proof-create'))); // rpc returns null → no proof
      await t.pumpAndSettle();
      expect(find.byKey(const Key('proof-failed')), findsOneWidget);
      expect(find.byKey(const Key('proof-qr')), findsNothing);
    });
  });
}
