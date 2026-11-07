import 'package:flutter/material.dart';

import '../../core/content.dart';
import '../../core/dates.dart';
import '../journey.dart';
import '../theme.dart';
import '../widgets.dart';
import 'birth_plan_screen.dart';
import 'child_profile_screen.dart';
import 'bp_screen.dart';
import 'journal_screen.dart';
import 'journey_screen.dart';
import 'library_screen.dart';
import 'nutrition_screen.dart';

/// Pregnancy tracker (MA-10..MA-13) or, after birth, the mother's own recovery.
class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key});
  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  int? month;

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    void go(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    final bp = s.bpReadings.map((r) => (parseTs(r['client_created_at'] as String), r['systolic'] as int, r['diastolic'] as int)).toList();
    final bpCard = AppCard(
      onTap: () => go(const BpScreen()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row2(
            icon: Icons.speed,
            title: context.t('Weekly blood pressure', 'Shinikizo la damu la wiki'),
            sub: bp.isEmpty
                ? context.t('No readings yet. Ask your CHW or clinic to measure it.', 'Bado hakuna vipimo. Muombe mhudumu au kliniki akupime.')
                : '${bp.last.$2}/${bp.last.$3} · ${fmtDay(bp.last.$1, s.lang)}',
          ),
          if (bp.length > 1) BpChart(bp.length > 8 ? bp.sublist(bp.length - 8) : bp),
        ],
      ),
    );
    if (!s.pregnant) {
      final b = s.baby;
      final cur = babyMonthOf(s.babyDays);
      final bm = month ?? cur;
      final g = babyMonthsGuide[bm]!;
      const arts = {1: 'breastfeed', 2: 'mother_baby', 3: 'baby_back', 4: 'talk', 5: 'baby_hat', 6: 'bowl', 7: 'plate', 8: 'hands', 9: 'calendar'};
      final contacts = b == null ? const <({ChildContact contact, DateTime due, bool done})>[] : s.childContactsFor(b['id'] as String);
      return Pad(
        children: [
          const MotherTools(),
          if (s.babies.length > 1) const BabySwitcher(),
          Text(context.t('Month by month', 'Mwezi kwa mwezi'), style: Theme.of(context).textTheme.headlineSmall),
          const Gap(12),
          MonthChips(current: cur, selected: bm, onSelected: (i) => setState(() => month = i), keyPrefix: 'baby-month'),
          const Gap(12),
          MonthCard(art: arts[bm]!, asset: 'MM-BB-$bm', babyTitle: s.babyName, baby: g.baby, you: g.you, watch: g.watch),
          SectionTitle(context.t("${s.babyName}'s 8 clinic visits", 'Kliniki 8 za ${s.babyName}')),
          AppCard(
            key: const Key('child-contacts'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                for (final (i, c) in contacts.indexed)
                  ContactTile(
                    title: '${i + 1} · ${context.tx(c.contact.title)}',
                    subtitle: '${fmtDayYear(c.due, s.lang)}${c.done ? ' · ${context.t('done', 'imefanyika')}' : ''}',
                    done: c.done,
                    past: c.due.isBefore(today()),
                    items: c.contact.items,
                  ),
              ],
            ),
          ),
          SectionTitle(context.t('Your recovery after birth', 'Kupona kwako baada ya kujifungua')),
          Text(
            context.t(
              'Your body needs care too. These signs mean go to a facility now:',
              'Mwili wako unahitaji uangalizi pia. Dalili hizi zinamaanisha nenda kituoni sasa:',
            ),
          ),
          const Gap(12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final sg in postnatalSigns.where((x) => x.level == Level.red))
                Chip(
                  avatar: Icon(sg.icon, size: 18, color: C.red),
                  label: Text(context.tx(sg.label)),
                ),
            ],
          ),
          const Gap(16),
          bpCard,
          const Gap(12),
          AppCard(
            child: Row2(
              icon: Icons.nightlight_outlined,
              title: context.t('Feeling low?', 'Unahisi huzuni?'),
              sub: context.t(
                'Many mothers do. Tap to learn what helps and when to ask for help.',
                'Akina mama wengi huhisi hivyo. Gusa ujifunze kinachosaidia.',
              ),
              onTap: () => go(const LessonScreen('mood')),
            ),
          ),
          const Gap(12),
          AppCard(
            child: Row2(
              icon: Icons.child_friendly,
              title: context.t('Spacing your next pregnancy', 'Kupanga uzazi'),
              onTap: () => go(const LessonScreen('spacing')),
            ),
          ),
          const Gap(12),
          AppCard(
            child: Row2(
              icon: Icons.restaurant,
              title: context.t('Eat well while breastfeeding', 'Lishe bora wakati wa kunyonyesha'),
              onTap: () => go(const NutritionScreen()),
            ),
          ),
          const Gap(12),
          AppCard(
            child: Row2(icon: Icons.book_outlined, title: context.t('My private journal', 'Shajara yangu binafsi'), onTap: () => go(const JournalScreen())),
          ),
        ],
      );
    }
    final m = month ?? s.month;
    final pm = pregnancyMonths[m]!;
    return Pad(
      children: [
        const MotherTools(),
        Text(context.t('Month by month', 'Mwezi kwa mwezi'), style: Theme.of(context).textTheme.headlineSmall),
        const Gap(12),
        MonthChips(current: s.month, selected: m, onSelected: (i) => setState(() => month = i)),
        const Gap(12),
        MonthCard(
          art: m <= 3
              ? 'mother_belly'
              : m <= 6
              ? 'lie_left'
              : 'bag',
          asset: 'MM-PR-$m',
          babyTitle: context.t('Your baby', 'Mtoto wako'),
          baby: pm.baby,
          you: pm.you,
        ),
        SectionTitle(context.t('Your 8 clinic visits', 'Kliniki zako 8')),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              for (final (i, v) in s.ancVisits.indexed)
                ContactTile(
                  title: context.tx(v.title),
                  subtitle:
                      '${context.t('Week', 'Wiki')} ${ancContacts[i].week} · ${fmtDayYear(v.due, s.lang)}${v.attended != null ? ' · ${context.t('attended', 'umehudhuria')}' : ''}',
                  done: v.attended != null,
                  past: v.due.isBefore(today()),
                  items: ancContacts[i].items,
                  note: v.note,
                ),
            ],
          ),
        ),
        const Gap(16),
        bpCard,
        const Gap(12),
        if (s.weeks >= 20)
          AppCard(
            child: Row2(
              icon: Icons.child_care,
              title: context.t("Know your baby's movements", 'Ifahamu mitikisiko ya mtoto'),
              sub: context.t(
                'There is no number to count. If movements are fewer, changed or stopped, contact a health worker the same day.',
                'Hakuna idadi ya kuhesabu. Mitikisiko ikipungua, ikibadilika au ikikoma, wasiliana na mhudumu wa afya siku hiyo hiyo.',
              ),
              onTap: () => go(const LessonScreen('kicks')),
            ),
          ),
        const Gap(12),
        AppCard(
          child: Row2(
            icon: Icons.luggage_outlined,
            title: context.t('My birth plan', 'Mpango wangu wa kujifungua'),
            sub: context.t(
              '${(s.birthPlan['items_ready'] as List).length} of ${birthReady.length} ready',
              '${(s.birthPlan['items_ready'] as List).length} kati ya ${birthReady.length} tayari',
            ),
            onTap: () => go(const BirthPlanScreen()),
          ),
        ),
        const Gap(12),
        AppCard(
          child: Row2(
            icon: Icons.restaurant,
            title: context.t('Eat well: Tanzanian foods', 'Lishe bora: vyakula vya nyumbani'),
            onTap: () => go(const NutritionScreen()),
          ),
        ),
        const Gap(12),
        AppCard(
          child: Row2(icon: Icons.book_outlined, title: context.t('My private journal', 'Shajara yangu binafsi'), onTap: () => go(const JournalScreen())),
        ),
      ],
    );
  }
}
