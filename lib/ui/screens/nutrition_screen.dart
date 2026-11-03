import 'package:flutter/material.dart';

import '../../core/content.dart';
import '../theme.dart';
import '../widgets.dart';

/// Local meal tracker: protein, iron, folate and calcium from Tanzanian foods. Kept on the phone only.
class NutritionScreen extends StatelessWidget {
  const NutritionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final picked = s.foodsToday;
    double sum(double Function(Food) f) => foodsTz.where((x) => picked.contains(x.key)).fold(0.0, (a, x) => a + f(x));
    final bars = [
      (context.t('Protein', 'Protini'), sum((f) => f.protein), dailyNeeds.protein, 'g'),
      (context.t('Iron', 'Madini ya chuma'), sum((f) => f.iron), dailyNeeds.iron, 'mg'),
      (context.t('Folate', 'Foliki'), sum((f) => f.folate), dailyNeeds.folate, 'µg'),
      (context.t('Calcium', 'Kalsiamu'), sum((f) => f.calcium), dailyNeeds.calcium, 'mg'),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(context.t('Eat well', 'Lishe bora')), actions: const [EmergencyButton()]),
      body: Pad(
        children: [
          Text(context.t('Tap what you ate today', 'Gusa ulichokula leo'), style: Theme.of(context).textTheme.titleLarge),
          const Gap(8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in foodsTz)
                FilterChip(
                  label: Text(context.tx(f.name)),
                  tooltip: context.tx(f.serving),
                  selected: picked.contains(f.key),
                  onSelected: (_) => s.toggleFood(f.key),
                ),
            ],
          ),
          const Gap(16),
          AppCard(
            child: Column(
              children: [
                for (final (label, have, need, unit) in bars)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
                            Text('${have.round()} / ${need.round()} $unit'),
                          ],
                        ),
                        const Gap(4),
                        LinearProgressIndicator(
                          value: (have / need).clamp(0, 1),
                          minHeight: 10,
                          borderRadius: BorderRadius.circular(5),
                          color: C.primary,
                          backgroundColor: C.surface2,
                        ),
                      ],
                    ),
                  ),
                Text(
                  context.t(
                    'Daily needs in pregnancy, approximate. Take the iron + folic acid tablet as prescribed.',
                    'Mahitaji ya kila siku wakati wa ujauzito, takriban. Meza kidonge cha IFA kama ulivyoandikiwa.',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          SectionTitle(context.t('Recipes', 'Mapishi')),
          for (final (title, steps) in recipesTz)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  leading: const Icon(Icons.restaurant_menu, color: C.primary),
                  title: Text(context.tx(title), style: Theme.of(context).textTheme.titleMedium),
                  children: [for (final (i, st) in steps.indexed) ListTile(dense: true, leading: Text('${i + 1}'), title: Text(context.tx(st)))],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
