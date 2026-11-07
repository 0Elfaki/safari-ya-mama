import 'package:flutter/material.dart';

import '../core/content_assets.dart';
import '../core/tx.dart';
import 'content_widgets.dart';
import 'theme.dart';
import 'widgets.dart';

/// Building blocks shared by the pregnancy and the baby journeys (MA-48), so the after-birth
/// screens look and work the same as the ones the mother used in pregnancy.

/// Home: the progress ring with "Month X of 9" and two short lines.
class JourneyCard extends StatelessWidget {
  final double value;
  final String big, small, title;
  final String? line1, line2;
  const JourneyCard({super.key, required this.value, required this.big, required this.small, required this.title, this.line1, this.line2});
  @override
  Widget build(BuildContext context) => AppCard(
    key: const Key('journey-card'),
    padding: const EdgeInsets.all(20),
    child: Row(
      children: [
        ProgressRing(value: value.clamp(0, 1), big: big, small: small),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const Gap(4),
              if (line1 != null) Text(line1!),
              if (line2 != null) Text(line2!, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    ),
  );
}

/// "Month 1 … Month 9" chips, the current month marked with a pin.
class MonthChips extends StatelessWidget {
  final int current, selected;
  final ValueChanged<int> onSelected;
  final String keyPrefix;
  const MonthChips({super.key, required this.current, required this.selected, required this.onSelected, this.keyPrefix = 'month'});
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: ListView(
      controller: ScrollController(initialScrollOffset: ((current - 2).clamp(0, 6)) * 100.0),
      scrollDirection: Axis.horizontal,
      children: [
        for (var i = 1; i <= 9; i++)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              key: Key('$keyPrefix-$i'),
              label: Text(context.t('Month $i', 'Mwezi $i')),
              selected: selected == i,
              avatar: i == current ? const Icon(Icons.location_on, size: 16) : null,
              onSelected: (_) => onSelected(i),
            ),
          ),
      ],
    ),
  );
}

/// One month: picture, the baby, you, and (after birth) when to talk to a health worker.
class MonthCard extends StatelessWidget {
  final String art;
  final String babyTitle;
  final Tx baby, you;
  final Tx? watch;

  /// Content-kit picture ID (MM-PR-n / MM-BB-n) shown when delivered.
  final String? asset;
  const MonthCard({super.key, required this.art, required this.babyTitle, required this.baby, required this.you, this.watch, this.asset});
  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (asset != null) ContentPicture(asset!, height: 180, fallback: const SizedBox.shrink()),
        if (asset != null && ContentAssets.has(asset!)) const Gap(12),
        Row(
          children: [
            Expanded(child: Text(babyTitle, style: Theme.of(context).textTheme.titleMedium)),
            ListenButton('${context.tx(baby)} ${context.tx(you)}${watch == null ? '' : ' ${context.tx(watch!)}'}'),
          ],
        ),
        Text(context.tx(baby), style: Theme.of(context).textTheme.bodyLarge),
        const Gap(12),
        Text(context.t('You', 'Wewe'), style: Theme.of(context).textTheme.titleMedium),
        Text(context.tx(you), style: Theme.of(context).textTheme.bodyLarge),
        if (watch != null) ...[
          const Gap(12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.amberSoft, borderRadius: BorderRadius.circular(14)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.visibility_outlined, color: C.amber),
                const SizedBox(width: 8),
                Expanded(child: Text(context.tx(watch!))),
              ],
            ),
          ),
        ],
      ],
    ),
  );
}

/// One clinic contact in the "Your 8 clinic visits" list (antenatal or child).
class ContactTile extends StatelessWidget {
  final String title, subtitle;
  final bool done, past;
  final List<Tx> items;
  final String? note;
  const ContactTile({super.key, required this.title, required this.subtitle, required this.done, required this.past, required this.items, this.note});
  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    leading: Icon(done ? Icons.check_circle : (past ? Icons.history : Icons.radio_button_unchecked), color: done ? C.green : C.primary),
    title: Text(title, style: Theme.of(context).textTheme.titleMedium),
    subtitle: Text(subtitle),
    children: [
      for (final it in items)
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 2, 0, 2),
          child: Row(
            children: [
              const Icon(Icons.circle, size: 6, color: C.ink3),
              const SizedBox(width: 8),
              Expanded(child: Text(context.tx(it))),
            ],
          ),
        ),
      if (note != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 6, 0, 0),
          child: Text(note!, style: const TextStyle(fontStyle: FontStyle.italic)),
        ),
      const Gap(8),
    ],
  );
}
