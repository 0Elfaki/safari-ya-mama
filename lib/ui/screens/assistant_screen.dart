import 'package:flutter/material.dart';

import '../../config.dart';
import '../../core/assistant.g.dart';
import '../../core/content.dart';
import '../../data/ai_client.dart';
import '../theme.dart';
import '../widgets.dart';

/// Assistant (MA-29). The scripted answers (SIMULATED, labelled) are the always-available base and
/// work offline. When the app has a backend and she is signed in, a question that the scripted
/// keywords do not mark as urgent or as a warning topic is also sent to the AI gateway (question text
/// and stage only); its answer is shown with the server's label. Neither path can change a warning
/// level, and urgent topics always route to Emergency help, with or without a signal.
class AssistantScreen extends StatefulWidget {
  /// Injected in tests. When null, the Supabase gateway is used if the app has a backend.
  final AssistantGateway? gateway;
  const AssistantScreen({super.key, this.gateway});
  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _Msg {
  final bool me;
  final String text;
  final String? question;

  /// Scripted intent (null for AI replies and her own messages).
  final AssistantIntent? intent;

  /// AI reply label (null for scripted answers).
  final String? aiLabel;
  final bool urgent;
  final bool pending;
  const _Msg({required this.me, required this.text, this.question, this.intent, this.aiLabel, this.urgent = false, this.pending = false});
}

class _AssistantScreenState extends State<AssistantScreen> {
  final msgs = <_Msg>[];
  final c = TextEditingController();

  AssistantGateway? get _gateway => widget.gateway ?? (AppConfig.hasBackend ? AiClient.askSupabase : null);

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Future<void> _ask(String raw) async {
    final q = raw.trim();
    if (q.isEmpty) return;
    final s = context.appRead;
    // Deterministic keyword check first, on the phone: urgent and warning topics are answered
    // from the approved scripted content (red → Emergency help) and never sent to the AI.
    final a = answerFor(q);
    final scripted = _Msg(me: false, text: s.tr(a.answer), question: q, intent: a, urgent: a.urgent == Level.red);
    final gateway = _gateway;
    final useAi = a.urgent == null && gateway != null && s.signedIn;
    setState(() {
      msgs.add(_Msg(me: true, text: q));
      msgs.add(useAi ? _Msg(me: false, text: '', question: q, pending: true) : scripted);
      c.clear();
    });
    if (!useAi) return;
    final index = msgs.length - 1;
    AiReply? r;
    try {
      r = await gateway(q, s.lang, gatewayStage(pregnant: s.pregnant, babyDays: s.babyDays));
    } catch (_) {
      r = null;
    }
    if (!mounted) return;
    setState(() {
      msgs[index] = r == null ? scripted : _Msg(me: false, text: r.text, question: q, aiLabel: r.label, urgent: r.urgent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = [
      context.t('Is a headache normal?', 'Kichwa kuuma ni kawaida?'),
      context.t('How often should my baby feed?', 'Mtoto anyonye mara ngapi?'),
      context.t('My baby feels hot', 'Mtoto ana homa'),
      context.t('I feel sad', 'Nina huzuni'),
    ];
    final s = context.app;
    final aiPossible = _gateway != null && s.signedIn;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('Ask a question', 'Uliza swali')), actions: const [EmergencyButton()]),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SimulatedBadge(text: context.t('Simulated: scripted answers', 'Mfano: majibu yaliyoandaliwa')),
                    const Spacer(),
                  ],
                ),
                if (aiPossible) ...[
                  const Gap(6),
                  Text(
                    key: const Key('ai-note'),
                    context.t(
                      'Some answers may come from AI. They are not medical advice. For anything urgent, use Emergency.',
                      'Baadhi ya majibu yanaweza kutoka kwa AI. Si ushauri wa kitabibu. Kwa jambo la dharura, tumia Dharura.',
                    ),
                    style: const TextStyle(fontSize: 13, color: C.ink2),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (msgs.isEmpty)
                  Text(
                    context.t(
                      'Ask about pregnancy, getting ready for birth, feeding or caring for your baby. For anything urgent, use Emergency.',
                      'Uliza kuhusu ujauzito, maandalizi ya kujifungua, kunyonyesha au matunzo ya mtoto. Kwa jambo la dharura, tumia Dharura.',
                    ),
                  ),
                for (final m in msgs) _bubble(context, m, aiPossible),
              ],
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final q in suggestions)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(label: Text(q), onPressed: () => _ask(q)),
                  ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: c,
                      onSubmitted: _ask,
                      decoration: InputDecoration(hintText: context.t('Type your question', 'Andika swali lako')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(onPressed: () => _ask(c.text), icon: const Icon(Icons.send)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(BuildContext context, _Msg m, bool aiPossible) {
    final me = m.me;
    final intent = m.intent;
    final ai = m.aiLabel != null;
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: me ? C.primary : C.surface,
          borderRadius: BorderRadius.circular(16),
          border: me ? null : Border.all(color: C.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (m.pending)
              Row(
                key: const Key('ai-pending'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Flexible(child: Text(context.t('Looking for an answer…', 'Natafuta jibu…'))),
                ],
              )
            else
              Text(m.text, style: TextStyle(color: me ? Colors.white : C.ink, fontSize: 15, height: 1.4)),
            if (!me && ai) ...[const Gap(8), SimulatedBadge(key: const Key('ai-label'), text: m.aiLabel)],
            if (!me && !ai && !m.pending && aiPossible) ...[
              const Gap(8),
              SimulatedBadge(text: context.t('Simulated: scripted answer', 'Mfano: jibu lililoandaliwa')),
            ],
            if (!me && m.urgent) ...[
              const Gap(8),
              FilledButton.icon(
                key: const Key('assistant-emergency'),
                style: FilledButton.styleFrom(backgroundColor: C.red),
                onPressed: () => Navigator.of(context).pushNamed('/emergency'),
                icon: const Icon(Icons.emergency),
                label: Text(context.t('Emergency help', 'Dharura')),
              ),
            ],
            if (!me && intent?.urgent == Level.amber) ...[
              const Gap(8),
              Text(
                context.t('Talk to a health worker today.', 'Ongea na mhudumu wa afya leo.'),
                style: const TextStyle(color: C.amber, fontWeight: FontWeight.w700),
              ),
            ],
            if (!me && !m.pending && !m.urgent && m.question != null && (ai || (intent != null && intent.keywords.isEmpty))) ...[
              const Gap(8),
              TextButton(
                onPressed: () => context.appRead.addQuestion(m.question!),
                child: Text(context.t('Add to my questions for the visit', 'Ongeza kwenye maswali ya kliniki')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
