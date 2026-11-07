import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';
import 'assistant_screen.dart';
import 'checkin_screen.dart';

/// MamaBot: tell us how you feel.
/// Two doors, kept apart on purpose:
///  1. "Check symptoms": the guided daily check. Its questions and the warning level come only
///     from the fixed, validated rules on the phone (rules.dart), never from AI.
///  2. The chat below: questions answered from approved scripted content, with AI added only for
///     non-urgent topics when online and signed in. Urgent words always route to Emergency help.
class MamaBotScreen extends StatefulWidget {
  const MamaBotScreen({super.key});
  @override
  State<MamaBotScreen> createState() => _MamaBotScreenState();
}

class _MamaBotScreenState extends State<MamaBotScreen> {
  String? about;

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final who = about ?? (s.pregnant ? 'mother' : 'baby');
    final babyLabel = s.pregnant ? context.t('Baby', 'Mtoto') : s.babiesLabel;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.screen, Sp.xs, Sp.screen, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.t('Tell us how you feel', 'Tuambie unavyojisikia'), style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: Sp.smd),
              SegmentedButton<String>(
                key: const Key('mamabot-about'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 'mother', icon: const Icon(Icons.pregnant_woman), label: Text(context.t('Mother', 'Mama'))),
                  ButtonSegment(
                    value: 'baby',
                    icon: const Icon(Icons.child_care),
                    label: Text(babyLabel, overflow: TextOverflow.ellipsis),
                  ),
                ],
                selected: {who},
                onSelectionChanged: (v) => setState(() => about = v.first),
              ),
              const SizedBox(height: Sp.smd),
              HealthCard(
                key: const Key('mamabot-check'),
                tone: C.primary,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CheckinScreen())),
                child: Row(
                  children: [
                    const Icon(Icons.fact_check_outlined, color: C.primary, size: 28),
                    const SizedBox(width: Sp.smd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            who == 'baby'
                                ? context.t("Check my baby's symptoms", 'Kagua dalili za mtoto')
                                : context.t('Check my symptoms', 'Kagua dalili zangu'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            context.t(
                              'A few questions, about 1 minute. Tells you when to get care.',
                              'Maswali machache, dakika 1. Inakuambia wakati wa kutafuta huduma.',
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: C.ink2),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: Sp.sm),
        const Divider(),
        Expanded(
          child: AssistantScreen(key: ValueKey(who), embedded: true, about: who),
        ),
      ],
    );
  }
}
