import 'package:flutter/material.dart';

import '../../core/content.dart';
import '../../core/dates.dart';
import '../../state/app_state.dart';
import '../content_widgets.dart';
import '../journey.dart';
import '../theme.dart';
import '../widgets.dart';
import 'assistant_screen.dart';
import 'checkin_screen.dart';
import 'library_screen.dart';
import 'nutrition_screen.dart';

class HomeScreen extends StatelessWidget {
  final ValueChanged<int> onTab;
  const HomeScreen({super.key, required this.onTab});

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final tc = s.todayWorst;
    final raised = s.serverRaised;
    void go(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    return Pad(
      children: [
        Text(context.t('Hello, ${s.name}', 'Habari, ${s.name}'), style: Theme.of(context).textTheme.headlineSmall),
        const Gap(16),
        _StageCard(s),
        const Gap(16),
        // today's check (MA-06)
        AppCard(
          key: const Key('today-check'),
          color: tc == null ? C.primary : levelSoft(s.levelOf(tc)),
          border: tc == null ? C.primary : levelColor(s.levelOf(tc)).withValues(alpha: .4),
          onTap: () => go(const CheckinScreen()),
          padding: const EdgeInsets.all(20),
          child: tc == null
              ? Row(
                  children: [
                    const Icon(Icons.fact_check_outlined, color: Colors.white, size: 36),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.t("Today's check", 'Ukaguzi wa leo'),
                            style: const TextStyle(fontFamily: display, fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                          Text(
                            context.t('Not done yet. It takes about 1 minute.', 'Bado haujafanya. Inachukua dakika 1 tu.'),
                            style: const TextStyle(color: Colors.white, fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward, color: Colors.white),
                  ],
                )
              : Row(
                  children: [
                    Icon(levelIcon(s.levelOf(tc)), color: levelColor(s.levelOf(tc)), size: 36),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tx(LevelBanner.title(s.levelOf(tc))),
                            style: Theme.of(context).textTheme.titleMedium!.copyWith(color: levelColor(s.levelOf(tc))),
                          ),
                          Text(
                            context.t(
                              'Checked at ${fmtTime(parseTs(tc['client_created_at'] as String))}. Tap to check again.',
                              'Umekagua saa ${fmtTime(parseTs(tc['client_created_at'] as String))}. Gusa kukagua tena.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
        if (raised != null) ...[
          const Gap(12),
          AppCard(
            color: levelSoft(s.levelOf(raised)),
            child: Text(
              context.t(
                'Your clinic\'s copy of the rules rated a recent check higher: ${context.tx(LevelBanner.title(s.levelOf(raised)))}. Please follow this advice.',
                'Nakala ya kliniki ya kanuni imekadiria ukaguzi wako wa karibuni juu zaidi: ${context.tx(LevelBanner.title(s.levelOf(raised)))}. Tafadhali fuata ushauri huu.',
              ),
            ),
          ),
        ],
        SectionTitle(context.t("Today's reminders", 'Vikumbusho vya leo')),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: s.reminders.isEmpty
              ? EmptyNote(Icons.check, context.t('Nothing else for today.', 'Hakuna kingine kwa leo.'))
              : Column(
                  children: [
                    for (final r in s.reminders)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: s.reminderDone(r.id),
                        onChanged: (_) => s.toggleReminder(r.id),
                        secondary: Icon(_icon(r.icon), color: C.primary),
                        title: Text(
                          context.tx(r.text),
                          style: TextStyle(fontWeight: FontWeight.w700, decoration: s.reminderDone(r.id) ? TextDecoration.lineThrough : null),
                        ),
                        subtitle: r.when.isEmpty ? null : Text(r.when),
                      ),
                  ],
                ),
        ),
        if (s.nextVisit != null) ...[
          SectionTitle(context.t('Next visit', 'Kliniki ijayo')),
          AppCard(
            onTap: () => onTab(4),
            child: Row2(
              icon: Icons.event,
              title: context.tx(s.nextVisit!.title),
              sub: '${fmtDayYear(s.nextVisit!.due, s.lang)} · ${_inDays(context, daysBetween(s.nextVisit!.due, today()))}',
            ),
          ),
        ],
        SectionTitle(
          context.t('For you', 'Kwa ajili yako'),
          trailing: TextButton(onPressed: () => onTab(3), child: Text(context.t('All lessons', 'Masomo yote'))),
        ),
        SizedBox(
          height: 236,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final l in s.lessonsForYou.take(4))
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: 220,
                    child: AppCard(
                      padding: const EdgeInsets.all(10),
                      onTap: () => go(LessonScreen(l.id)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ContentPicture('${l.asset}-P1', height: 110, fallback: Illus(l.steps.first.art, height: 110)),
                          const Gap(8),
                          Text(context.tx(l.title), maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                          Text(
                            '${l.minutes} min · ${s.lessonDone(l.id) ? context.t('done', 'umemaliza') : _fmt(context, l.format)}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Gap(16),
        Row(
          children: [
            Expanded(child: _Quick(Icons.restaurant, context.t('Eat well', 'Lishe bora'), () => go(const NutritionScreen()))),
            const SizedBox(width: 12),
            Expanded(child: _Quick(Icons.forum_outlined, context.t('Ask a question', 'Uliza swali'), () => go(const AssistantScreen()))),
          ],
        ),
        const Gap(24),
        Text(
          context.t(
            'Safari ya Mama supports your health worker. It does not replace them.',
            'Safari ya Mama inamsaidia mhudumu wako wa afya. Haichukui nafasi yake.',
          ),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  static IconData _icon(String k) => switch (k) {
    'pill' => Icons.medication_outlined,
    'baby' => Icons.child_care,
    'gauge' => Icons.speed,
    'syringe' => Icons.vaccines_outlined,
    _ => Icons.event,
  };
  static String _inDays(BuildContext c, int n) => n == 0
      ? c.t('today', 'leo')
      : n == 1
      ? c.t('tomorrow', 'kesho')
      : c.t('in $n days', 'baada ya siku $n');
  static String _fmt(BuildContext c, String f) => switch (f) {
    'video' => c.t('film', 'filamu'),
    'audio' => c.t('listen', 'sikiliza'),
    _ => c.t('picture guide', 'mwongozo wa picha'),
  };
}

/// The journey card: the same ring and "Month X of 9" in pregnancy and after birth, so the
/// mother sees one journey (MA-48).
class _StageCard extends StatelessWidget {
  final AppState s;
  const _StageCard(this.s);
  @override
  Widget build(BuildContext context) {
    if (s.pregnant) {
      final w = s.weeks;
      return JourneyCard(
        value: w / 40,
        big: '$w',
        small: context.t('weeks', 'wiki'),
        title: context.t('Month ${s.month} of 9', 'Mwezi ${s.month} kati ya 9'),
        line1: context.t('Your baby is about the size of a ${sizeForWeek(w).en}.', 'Mtoto wako ana ukubwa wa ${sizeForWeek(w).sw}.'),
        line2: s.edd == null ? null : context.t('Due about ${fmtDay(s.edd!, 'en')}', 'Kujifungua takriban ${fmtDay(s.edd!, 'sw')}'),
      );
    }
    final d = s.babyDays, m = babyMonthOf(d), g = babyMonthsGuide[m]!;
    final nv = s.nextVaccine;
    return JourneyCard(
      value: d / 274,
      big: d < 63 ? '${d ~/ 7}' : '${s.babyMonths}',
      small: d < 63 ? context.t('weeks old', 'wiki') : context.t('months old', 'miezi'),
      title: context.t('Month $m of 9', 'Mwezi $m kati ya 9'),
      line1: '${s.babiesLabel}: ${context.tx(g.short)}',
      line2: nv == null
          ? null
          : context.t('Next vaccine: ${nv.dose.label}, ${fmtDay(nv.due, 'en')}', 'Chanjo ijayo: ${nv.dose.label}, ${fmtDay(nv.due, 'sw')}'),
    );
  }
}

class _Quick extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Quick(this.icon, this.label, this.onTap);
  @override
  Widget build(BuildContext context) => AppCard(
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: C.primary, size: 28),
        const Gap(8),
        Text(label, style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );
}
