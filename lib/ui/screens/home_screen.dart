import 'package:go_router/go_router.dart';

import '../../app/router.dart';

import 'package:flutter/material.dart';

import '../../core/content.dart';
import '../../core/dates.dart';
import '../../state/app_state.dart';
import '../content_widgets.dart';
import '../theme.dart';
import '../widgets.dart';
import '../../features/telemedicine/ui/appointments_screen.dart';
import '../../features/telemedicine/ui/booking_screen.dart';
import 'checkin_screen.dart';
import 'library_screen.dart';

/// Home, top to bottom in the order she needs it: greeting, where she is in the journey,
/// today's check, her next appointment, four big "How can we help?" tiles (health worker,
/// MamaBot, other mothers, her records), daily care, danger signs and the emergency plan,
/// then lessons picked for her stage.
class HomeScreen extends StatelessWidget {
  final ValueChanged<int> onTab;
  const HomeScreen({super.key, required this.onTab});

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final tc = s.todayWorst;
    final raised = s.serverRaised;
    void go(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    final first = s.name.trim().split(' ').first;
    return Pad(
      children: [
        AppHeader(
          first.isEmpty ? context.t('Hello', 'Habari') : context.t('Hello, $first', 'Habari, $first'),
          subtitle: context.t('Your health journey, one step at a time', 'Safari yako ya afya, hatua moja baada ya nyingine'),
        ),
        _StageCard(s),
        const Gap(Sp.smd),
        // today's check (MA-06)
        if (tc == null)
          AppCard(
            key: const Key('today-check'),
            color: C.primarySoft,
            border: C.primary.withValues(alpha: .18),
            onTap: () => go(const CheckinScreen()),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: C.surface, borderRadius: BorderRadius.circular(R.medium)),
                  child: const Icon(Icons.fact_check_outlined, color: C.primary, size: 26),
                ),
                const SizedBox(width: Sp.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.t("Today's check", 'Ukaguzi wa leo'), style: AppTypography.h3),
                      Text(context.t('Not done yet. It takes about 1 minute.', 'Bado haujafanya. Inachukua dakika 1 tu.'), style: AppTypography.bodyText),
                    ],
                  ),
                ),
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(color: C.primary, shape: BoxShape.circle),
                  child: const Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                ),
              ],
            ),
          )
        else
          HealthCard(
            key: const Key('today-check'),
            tone: levelColor(s.levelOf(tc)),
            background: levelSoft(s.levelOf(tc)),
            onTap: () => go(const CheckinScreen()),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusBadge(context.tx(LevelBanner.status(s.levelOf(tc))), color: levelColor(s.levelOf(tc)), icon: levelIcon(s.levelOf(tc))),
                const Gap(Sp.sm),
                Text(context.tx(LevelBanner.title(s.levelOf(tc))), style: Theme.of(context).textTheme.titleMedium!.copyWith(color: levelColor(s.levelOf(tc)))),
                Text(
                  context.t(
                    'Checked at ${fmtTime(parseTs(tc['client_created_at'] as String))}. Tap to check again.',
                    'Umekagua saa ${fmtTime(parseTs(tc['client_created_at'] as String))}. Gusa kukagua tena.',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        if (raised != null) ...[
          const Gap(Sp.smd),
          HealthCard(
            tone: levelColor(s.levelOf(raised)),
            background: levelSoft(s.levelOf(raised)),
            child: Text(
              context.t(
                'Your clinic\'s copy of the rules rated a recent check higher: ${context.tx(LevelBanner.title(s.levelOf(raised)))}. Please follow this advice.',
                'Nakala ya kliniki ya kanuni imekadiria ukaguzi wako wa karibuni juu zaidi: ${context.tx(LevelBanner.title(s.levelOf(raised)))}. Tafadhali fuata ushauri huu.',
              ),
            ),
          ),
        ],
        if (s.bookings.next case final b?) ...[
          SectionTitle(context.t('Your next appointment', 'Miadi yako ijayo')),
          BookingTile(b, onTap: () => go(BookingScreen(b))),
        ],
        // what she most often needs, in big picture tiles (pictures HOME-*, icons until delivered)
        SectionTitle(context.t('How can we help?', 'Tukusaidie nini?')),
        TileGrid(
          children: [
            PictureTile(
              key: const Key('need-doctor'),
              picture: 'HOME-DOCTOR',
              icon: Icons.medical_services_outlined,
              label: context.t('See a health worker', 'Muone mhudumu wa afya'),
              sub: context.t('Clinic visit or video call', 'Kliniki au simu ya video'),
              onTap: () => go(const AppointmentsScreen()),
            ),
            PictureTile(
              key: const Key('need-ask'),
              picture: 'HOME-ASK',
              icon: Icons.chat_bubble_outline_rounded,
              label: context.t('Ask a question', 'Uliza swali'),
              sub: context.t('MamaBot answers any time', 'MamaBot hujibu wakati wowote'),
              onTap: () => onTab(2),
            ),
            PictureTile(
              key: const Key('need-circle'),
              picture: 'HOME-CIRCLE',
              icon: Icons.groups_outlined,
              label: context.t('Talk to other mothers', 'Ongea na akina mama'),
              sub: context.t('Share and learn, safely', 'Shiriki na ujifunze, kwa usalama'),
              onTap: () => onTab(3),
            ),
            PictureTile(
              key: const Key('need-care'),
              picture: 'HOME-CARE',
              icon: Icons.monitor_heart_outlined,
              label: s.pregnant ? context.t('My pregnancy', 'Ujauzito wangu') : context.t('My baby', 'Mtoto wangu'),
              sub: context.t('Visits, checks and records', 'Kliniki, ukaguzi na kumbukumbu'),
              onTap: () => onTab(1),
            ),
          ],
        ),
        SectionTitle(context.t('Daily care', 'Huduma ya kila siku')),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: Sp.smd, vertical: Sp.xs),
          child: s.reminders.isEmpty
              ? EmptyState(Icons.check, context.t('Nothing else for today.', 'Hakuna kingine kwa leo.'))
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
                          style: Theme.of(context).textTheme.titleMedium!
                              .copyWith(decoration: s.reminderDone(r.id) ? TextDecoration.lineThrough : null, color: s.reminderDone(r.id) ? C.ink2 : C.ink),
                        ),
                        subtitle: r.when.isEmpty ? null : Text(r.when),
                      ),
                  ],
                ),
        ),
        const Gap(Sp.md),
        HealthCard(
          key: const Key('danger-banner'),
          tone: C.amber,
          background: C.amberSoft,
          onTap: () => go(LessonScreen(s.pregnant ? 'danger-preg' : 'danger-baby')),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: C.amber, size: 28),
              const SizedBox(width: Sp.smd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.t('Know the danger signs', 'Zijue dalili za hatari'), style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      context.t('When to go to a facility straight away', 'Wakati wa kwenda kituoni mara moja'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: C.ink2),
            ],
          ),
        ),
        const Gap(Sp.smd),
        DangerButton(
          key: const Key('home-emergency-plan'),
          context.t('Emergency care plan', 'Mpango wa dharura'),
          icon: Icons.emergency,
          onPressed: () => context.push(Routes.emergency),
        ),
        SectionTitle(
          context.t('For you', 'Kwa ajili yako'),
          trailing: TextButton(onPressed: () => onTab(4), child: Text(context.t('All lessons', 'Masomo yote'))),
        ),
        SizedBox(
          height: 236,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final l in s.lessonsForYou.take(4))
                Padding(
                  padding: const EdgeInsets.only(right: Sp.smd),
                  child: SizedBox(
                    width: 220,
                    child: AppCard(
                      padding: const EdgeInsets.all(Sp.smd - 2),
                      onTap: () => go(LessonScreen(l.id)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ContentPicture('${l.asset}-P1', height: 110, radius: R.medium, fallback: Illus(l.steps.first.art, height: 110)),
                          const Gap(Sp.sm),
                          Text(context.tx(l.title), maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                          Text(
                            '${l.minutes} min · ${s.lessonDone(l.id) ? context.t('done', 'umemaliza') : _fmt(context, l.format)}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Gap(Sp.lg),
        Text(
          context.t(
            'Safari ya Mama supports your health worker. It does not replace them.',
            'Safari ya Mama inamsaidia mhudumu wako wa afya. Haichukui nafasi yake.',
          ),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
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
  static String _fmt(BuildContext c, String f) => switch (f) {
    'video' => c.t('film', 'filamu'),
    'audio' => c.t('listen', 'sikiliza'),
    _ => c.t('picture guide', 'mwongozo wa picha'),
  };
}

/// Home's hero card, deep green (HeroCard).
/// Pregnancy: gestational age, the baby's size this stage (picture `SZ-<stage>` when delivered),
/// progress to 40 weeks, trimester and due date.
/// After birth: the baby's age on a ring, the month guide and the next vaccine (one journey, MA-48).
class _StageCard extends StatelessWidget {
  final AppState s;
  const _StageCard(this.s);

  static const _muted = TextStyle(color: C.onPrimaryMuted, fontSize: 13, height: 1.35);

  @override
  Widget build(BuildContext context) {
    if (s.pregnant) {
      final w = s.weeks, d = s.pregnancyDays % 7;
      final tri = w < 14 ? 1 : (w < 28 ? 2 : 3);
      final size = sizeForWeek(w);
      final stage = sizeStageWeek(w).toString().padLeft(2, '0');
      return HeroCard(
        key: const Key('journey-card'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.t('Gestational age', 'Umri wa mimba'), style: _muted),
                      const SizedBox(height: Sp.xs),
                      Text(
                        context.t('$w weeks, $d days', 'Wiki $w, siku $d'),
                        style: AppTypography.h2.copyWith(color: Colors.white, fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                      const SizedBox(height: Sp.sm),
                      Text(
                        context.t('About the size of a ${size.en}', 'Ukubwa wa ${size.sw}'),
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600, height: 1.35),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Sp.smd),
                Container(
                  width: 100,
                  height: 100,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: .28), width: 2),
                  ),
                  child: ContentPicture(
                    key: Key('size-SZ-$stage'),
                    'SZ-$stage',
                    height: 92,
                    radius: 46,
                    semanticLabel: context.t('Picture of a ${size.en}', 'Picha ya ${size.sw}'),
                    fallback: Container(
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: .10), shape: BoxShape.circle),
                      child: const Icon(Icons.pregnant_woman, size: 48, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Sp.mdl),
            Semantics(
              label: context.t('Week $w of 40', 'Wiki $w kati ya 40'),
              child: LinearProgressIndicator(
                value: (w / 40).clamp(0, 1),
                minHeight: 8,
                color: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: .18),
                borderRadius: BorderRadius.circular(R.pill),
              ),
            ),
            const SizedBox(height: Sp.smd),
            Row(
              children: [
                Expanded(child: _Fact(context.t('Trimester', 'Kipindi'), context.t('$tri of 3', '$tri kati ya 3'))),
                Expanded(child: _Fact(context.t('Due date', 'Tarehe ya kujifungua'), s.edd == null ? '–' : fmtDayYear(s.edd!, s.lang))),
              ],
            ),
          ],
        ),
      );
    }
    final d = s.babyDays, m = babyMonthOf(d), g = babyMonthsGuide[m]!;
    final nv = s.nextVaccine;
    return HeroCard(
      key: const Key('journey-card'),
      child: Row(
        children: [
          ProgressRing(
            value: (d / 274).clamp(0, 1),
            big: d < 63 ? '${d ~/ 7}' : '${s.babyMonths}',
            small: d < 63 ? context.t('weeks old', 'wiki') : context.t('months old', 'miezi'),
            onDark: true,
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.t('Month $m of 9', 'Mwezi $m kati ya 9'), style: AppTypography.h3.copyWith(color: Colors.white)),
                const SizedBox(height: Sp.xs),
                Text('${s.babiesLabel}: ${context.tx(g.short)}', style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4)),
                if (nv != null) ...[
                  const SizedBox(height: Sp.xs),
                  Text(
                    context.t('Next vaccine: ${nv.dose.label}, ${fmtDay(nv.due, 'en')}', 'Chanjo ijayo: ${nv.dose.label}, ${fmtDay(nv.due, 'sw')}'),
                    style: _muted,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  final String label, value;
  const _Fact(this.label, this.value);
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: _StageCard._muted),
      Text(
        value,
        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ],
  );
}
