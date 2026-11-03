import 'package:flutter/material.dart';

import '../../core/content.dart';
import '../theme.dart';
import '../widgets.dart';

/// The child's part of the daily check, in three coloured steps (MA-47):
///   1 green  · everyday things (4 or more together → amber, rules 2026.12)
///   2 orange · needs a health worker within 24 hours
///   3 red    · go to a health facility now
/// All three are always shown, so a danger sign is never hidden behind an earlier step.
/// The level itself is decided only by rules.dart.
class BabyColourCheck extends StatefulWidget {
  final String name;
  final int babyDays;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final String feeding;
  final ValueChanged<String> onFeeding;
  final TextEditingController note;

  /// '' for the first baby, '-1' for the second (twins), and so on.
  final String keySuffix;
  const BabyColourCheck({
    super.key,
    required this.name,
    required this.babyDays,
    required this.selected,
    required this.onToggle,
    required this.feeding,
    required this.onFeeding,
    required this.note,
    this.keySuffix = '',
  });

  /// Which coloured step a sign belongs to for a baby of this age.
  static Level stepOf(Sign s, int babyDays) => s.ageDependent ? (babyDays < 60 ? Level.red : Level.amber) : s.level;

  @override
  State<BabyColourCheck> createState() => _BabyColourCheckState();
}

class _BabyColourCheckState extends State<BabyColourCheck> {
  final _orangeKey = GlobalKey();

  int get _greens => babySigns.where((s) => s.level == Level.green && widget.selected.contains(s.key)).length;

  void _toggle(Sign s) {
    final before = _greens, adding = !widget.selected.contains(s.key);
    widget.onToggle(s.key);
    // she just reached the step-up: bring the orange step into view
    if (s.level == Level.green && adding && before == greenStepUp - 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = _orangeKey.currentContext;
        if (c != null && c.mounted) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 400), alignment: .1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget, n = w.name, sfx = w.keySuffix;
    List<Sign> step(Level l) => babySigns.where((s) => BabyColourCheck.stepOf(s, w.babyDays) == l).toList();
    final greens = _greens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(context.t('$n: feeding today', '$n: kunyonya leo')),
        Choice<String>(
          keyPrefix: 'feed$sfx',
          value: w.feeding,
          onChanged: w.onFeeding,
          options: [
            ('normal', Icons.check_circle_outline, context.t('As usual', 'Kama kawaida')),
            ('less', Icons.trending_down, context.t('Less than usual', 'Kidogo')),
            ('not', Icons.do_not_disturb_on_outlined, context.t('Not feeding', 'Hanyonyi')),
          ],
        ),
        const Gap(8),
        _StepBar(selected: w.selected, babyDays: w.babyDays),
        _Step(
          key: Key('step-green$sfx'),
          number: 1,
          level: Level.green,
          title: context.t('$n: everyday things', '$n: mambo ya kawaida'),
          hint: context.t(
            'Common and usually mild. If you tick 4 or more, a health worker should look at $n.',
            'Ni ya kawaida na mara nyingi si makali. Ukichagua 4 au zaidi, mhudumu wa afya amwangalie $n.',
          ),
          signs: step(Level.green),
          selected: w.selected,
          onTap: _toggle,
          keySuffix: sfx,
          footer: greens >= greenStepUp
              ? _Prompt(
                  key: Key('stepup$sfx'),
                  text: context.t(
                    'You ticked $greens everyday signs. Together they need a health worker within 24 hours. Now check the orange and red signs below.',
                    'Umechagua dalili $greens za kawaida. Kwa pamoja zinahitaji mhudumu wa afya ndani ya saa 24. Sasa angalia dalili za machungwa na nyekundu hapa chini.',
                  ),
                )
              : null,
        ),
        _Step(
          key: _orangeKey,
          number: 2,
          level: Level.amber,
          title: context.t('Needs a health worker within 24 hours', 'Inahitaji mhudumu wa afya ndani ya saa 24'),
          signs: step(Level.amber),
          selected: w.selected,
          onTap: _toggle,
          keySuffix: sfx,
        ),
        _Step(
          key: Key('step-red$sfx'),
          number: 3,
          level: Level.red,
          title: context.t('Danger signs: go to a facility now', 'Dalili za hatari: nenda kituoni sasa'),
          signs: step(Level.red),
          selected: w.selected,
          onTap: _toggle,
          keySuffix: sfx,
        ),
        SectionTitle(context.t('Anything else about $n? (optional)', 'Jambo lingine kuhusu $n? (si lazima)')),
        TextField(
          key: Key('baby-note$sfx'),
          controller: w.note,
          maxLength: 300,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: context.t('Describe what you see, or a sign that is not in the list.', 'Eleza unachokiona, au dalili ambayo haipo kwenye orodha.'),
          ),
        ),
      ],
    );
  }
}

/// Three coloured segments: how many signs are ticked in each step.
class _StepBar extends StatelessWidget {
  final Set<String> selected;
  final int babyDays;
  const _StepBar({required this.selected, required this.babyDays});
  @override
  Widget build(BuildContext context) {
    int count(Level l) => babySigns.where((s) => BabyColourCheck.stepOf(s, babyDays) == l && selected.contains(s.key)).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          for (final l in Level.values)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: count(l) > 0 ? (l == Level.amber ? C.amberFill : levelColor(l)) : levelSoft(l),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${l.index + 1} · ${count(l)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w800, color: count(l) > 0 ? (l == Level.amber ? C.ink : Colors.white) : levelColor(l)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final Level level;
  final String title;
  final String? hint;
  final List<Sign> signs;
  final Set<String> selected;
  final ValueChanged<Sign> onTap;
  final String keySuffix;
  final Widget? footer;
  const _Step({
    super.key,
    required this.number,
    required this.level,
    required this.title,
    this.hint,
    required this.signs,
    required this.selected,
    required this.onTap,
    required this.keySuffix,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final c = levelColor(level), fill = level == Level.amber ? C.amberFill : c;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: levelSoft(level).withValues(alpha: .55),
        borderRadius: BorderRadius.circular(20),
        border: Border(left: BorderSide(color: fill, width: 6)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: c,
                child: Text(
                  '$number',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: c)),
              ),
            ],
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(hint!, style: Theme.of(context).textTheme.bodyMedium),
            ),
          const Gap(10),
          for (final s in signs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SignTile(s, keySuffix: keySuffix, selected: selected.contains(s.key), onTap: () => onTap(s), shownAs: level),
            ),
          ?footer,
        ],
      ),
    );
  }
}

class _Prompt extends StatelessWidget {
  final String text;
  const _Prompt({super.key, required this.text});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: C.amberSoft,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: C.amberFill),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.arrow_downward, color: C.amber),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

/// One square per day, coloured by the most urgent daily-check result (grey = no check).
class CheckHistoryStrip extends StatelessWidget {
  final List<({DateTime day, Level? level})> days;
  const CheckHistoryStrip(this.days, {super.key});
  @override
  Widget build(BuildContext context) {
    final checked = days.where((d) => d.level != null).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final d in days)
              Expanded(
                child: Tooltip(
                  message: d.level == null ? context.t('No check', 'Hakuna ukaguzi') : context.tx(LevelBanner.title(d.level!)),
                  child: Container(
                    height: 26,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: d.level == null ? C.surface2 : (d.level == Level.amber ? C.amberFill : levelColor(d.level!)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const Gap(6),
        Text(
          context.t('$checked of the last ${days.length} days checked', 'Siku $checked kati ya ${days.length} zilizopita zimekaguliwa'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}
