import 'package:flutter/material.dart';

import '../../core/content.dart';
import '../../core/dates.dart';
import '../../core/tx.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'checkin_screen.dart';
import 'child_check.dart';
import 'child_profile_screen.dart';
import 'first_aid_screen.dart';
import 'library_screen.dart';

/// Baby tracker to 9 months (MA-19..MA-23); in pregnancy, records the birth.
class BabyScreen extends StatelessWidget {
  const BabyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    void go(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    if (s.pregnant || s.baby == null) {
      return Pad(
        key: const ValueKey('baby-before-birth'),
        children: [
          Text(context.t('When your baby is born', 'Mtoto akizaliwa'), style: Theme.of(context).textTheme.headlineSmall),
          const Gap(8),
          Text(
            context.t(
              'Record the birth and Safari ya Mama switches to baby mode: feeding, growth, milestones and the 16 routine vaccines up to 9 months. Your journal and questions carry over.',
              'Andika kuzaliwa na Safari ya Mama itabadilika kuwa hali ya mtoto: kunyonyesha, ukuaji, hatua za makuzi na chanjo 16 hadi miezi 9. Shajara na maswali yako yanaendelea.',
            ),
          ),
          const Gap(16),
          FilledButton.icon(
            key: const Key('record-birth'),
            onPressed: () => go(const RecordBirthScreen()),
            icon: const Icon(Icons.celebration_outlined),
            label: Text(context.t('My baby is born', 'Mtoto amezaliwa')),
          ),
          const Gap(16),
          AppCard(
            child: Row2(
              icon: Icons.warning_amber,
              tint: C.red,
              title: context.t('Danger signs in babies', 'Dalili za hatari kwa mtoto'),
              onTap: () => go(const LessonScreen('danger-baby')),
            ),
          ),
          const Gap(12),
          AppCard(
            child: Row2(
              icon: Icons.favorite_border,
              title: context.t('Breastfeeding from the first hour', 'Kunyonyesha tangu saa ya kwanza'),
              onTap: () => go(const LessonScreen('breastfeed')),
            ),
          ),
        ],
      );
    }
    final m = s.babyMonths;
    final under6 = s.babyDays < 183;
    return Pad(
      key: const ValueKey('baby-after-birth'),
      children: [
        const BabySwitcher(),
        AppCard(
          key: const Key('open-child-profile'),
          onTap: () => go(const ChildProfileScreen()),
          child: Row(
            children: [
              BabyAvatar(s.babyName, index: s.babies.indexWhere((b) => b['id'] == s.baby!['id'])),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.babyName, style: Theme.of(context).textTheme.headlineSmall),
                    Text(
                      context.t('${s.babyDays} days old · born ${fmtDayYear(s.dob!, 'en')}', 'Ana siku ${s.babyDays} · alizaliwa ${fmtDayYear(s.dob!, 'sw')}'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    Text(
                      context.t('Child profile', 'Wasifu wa mtoto'),
                      style: const TextStyle(color: C.primary, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: C.ink3),
            ],
          ),
        ),
        SectionTitle(context.t('Daily check', 'Ukaguzi wa kila siku')),
        _DailyCheckCard(babyId: s.baby!['id'] as String, name: s.babyName),
        const Gap(12),
        AppCard(
          key: const Key('keep-safe'),
          color: C.redSoft,
          border: C.red.withValues(alpha: .25),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.t('Keep ${s.babyName} safe', 'Mlinde ${s.babyName}'), style: Theme.of(context).textTheme.titleMedium),
              const Gap(4),
              Text(
                context.t('Animated first aid, and pictures that show each danger sign.', 'Huduma ya kwanza kwa michoro, na picha za kila dalili ya hatari.'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const Gap(10),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      key: const Key('open-first-aid'),
                      style: FilledButton.styleFrom(backgroundColor: C.red),
                      onPressed: () => go(const FirstAidHubScreen()),
                      icon: const Icon(Icons.health_and_safety_outlined),
                      label: Text(context.t('First aid', 'Huduma ya kwanza')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('open-signs'),
                      onPressed: () => go(const FirstAidHubScreen(initialTab: 1)),
                      icon: const Icon(Icons.visibility_outlined),
                      label: Text(context.t('Spot the signs', 'Tambua dalili')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SectionTitle(context.t('Feeding today', 'Kunyonya leo'), trailing: Text('${s.feedsToday()}', style: Theme.of(context).textTheme.headlineSmall)),
        if (under6)
          AppCard(
            color: C.primarySoft,
            border: C.primarySoft,
            child: Text(
              context.t(
                'Breast milk only until 6 months: no water or other food. Feed whenever baby wants, 8 or more times a day and night.',
                'Maziwa ya mama pekee hadi miezi 6: bila maji wala chakula kingine. Nyonyesha kila mtoto anapotaka, mara 8 au zaidi mchana na usiku.',
              ),
            ),
          ),
        const Gap(8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (k, icon, label) in [
              ('breast', Icons.favorite, context.t('Breastfeed', 'Kunyonyesha')),
              ('expressed', Icons.local_drink_outlined, context.t('Expressed milk', 'Maziwa yaliyokamuliwa')),
              if (!under6) ('solid', Icons.rice_bowl_outlined, context.t('Food', 'Chakula')),
              ('formula', Icons.baby_changing_station, context.t('Formula', 'Maziwa ya kopo')),
            ])
              ActionChip(
                key: Key('feed-$k'),
                avatar: Icon(icon, size: 18, color: C.primary),
                label: Text(label),
                onPressed: () {
                  s.addFeed(k);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('Feed saved', 'Imehifadhiwa'))));
                },
              ),
          ],
        ),
        SectionTitle(
          context.t('Growth', 'Ukuaji'),
          trailing: TextButton.icon(onPressed: () => _addWeight(context), icon: const Icon(Icons.add), label: Text(context.t('Weight', 'Uzito'))),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (s.growth.isEmpty)
                EmptyNote(
                  Icons.monitor_weight_outlined,
                  context.t('No weights yet. Add one after the next clinic visit.', 'Hakuna uzito bado. Ongeza baada ya kliniki ijayo.'),
                ),
              for (final g in s.growth.reversed.take(5))
                Row2(
                  icon: Icons.monitor_weight_outlined,
                  title: '${((g['weight_g'] as int) / 1000).toStringAsFixed(2)} kg',
                  sub:
                      '${fmtDayYear(parseDay(g['measured_on'] as String), s.lang)} · ${g['source'] == 'clinic' ? context.t('clinic', 'kliniki') : context.t('home', 'nyumbani')}',
                ),
              Text(
                context.t(
                  'The growth chart on the child health card is the reference. Ask your clinic if weight goes down or stays the same.',
                  'Chati ya ukuaji kwenye kadi ya mtoto ndiyo kipimo. Uliza kliniki uzito ukishuka au usipoongezeka.',
                ),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        SectionTitle(context.t('Milestones', 'Hatua za makuzi')),
        for (final e in milestonesByMonth.entries.where((e) => e.key <= m + 2))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.t('By ${e.key} month${e.key > 1 ? 's' : ''}', 'Kufikia mwezi ${e.key}'), style: Theme.of(context).textTheme.titleMedium),
                  for (final ms in e.value)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: s.milestoneDone(ms.key),
                      title: Text(context.tx(ms.label)),
                      onChanged: (_) => s.toggleMilestone(ms.key),
                    ),
                ],
              ),
            ),
          ),
        SectionTitle(context.t('Vaccine schedule', 'Ratiba ya chanjo')),
        if (s.nextVaccine != null) ...[
          () {
            final nv = s.nextVaccine!;
            final due = s.vaccines.where((x) => !x.given && x.dose.day == nv.dose.day).map((x) => x.dose.label).join(', ');
            final n = daysBetween(nv.due, today());
            final late = n < 0;
            return AppCard(
              key: const Key('next-vaccine'),
              color: late ? C.amberSoft : C.primarySoft,
              border: late ? C.amberFill : C.primarySoft,
              child: Row2(
                icon: Icons.vaccines_outlined,
                tint: late ? C.amber : C.primary,
                title: '${context.tx(vaccineGroupName(nv.dose.day))}: $due',
                sub: late
                    ? context.t(
                        'Due since ${fmtDayYear(nv.due, 'en')}. Go to the clinic soon.',
                        'Ilitakiwa tangu ${fmtDayYear(nv.due, 'sw')}. Nenda kliniki mapema.',
                      )
                    : '${fmtDayYear(nv.due, s.lang)} · ${n == 0 ? context.t('today', 'leo') : context.t('in $n days', 'baada ya siku $n')}',
              ),
            );
          }(),
          const Gap(8),
        ],
        Text(
          context.t('Tick each one from the child health card. Always follow the card.', 'Weka alama kwa kila moja kutoka kadi ya mtoto. Fuata kadi daima.'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const Gap(8),
        for (final day in vaccineDoses.map((v) => v.day).toSet())
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${context.tx(vaccineGroupName(day))} · ${fmtDay(addDays(s.dob!, day), s.lang)}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      _VxStatus(s.vaccines.where((x) => x.dose.day == day).toList()),
                    ],
                  ),
                  for (final v in s.vaccines.where((x) => x.dose.day == day))
                    CheckboxListTile(
                      key: Key('vx-${v.dose.key}'),
                      contentPadding: EdgeInsets.zero,
                      value: v.given,
                      title: Text(v.dose.label),
                      subtitle: v.given
                          ? Text(context.t('given ${fmtDay(v.givenOn!, 'en')}', 'imetolewa ${fmtDay(v.givenOn!, 'sw')}'))
                          : (v.due.isBefore(today())
                                ? Text(context.t('due, not recorded', 'imefika, haijaandikwa'), style: const TextStyle(color: C.amber))
                                : null),
                      onChanged: (x) => s.setVaccineGiven(v.dose.key, x == true),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _addWeight(BuildContext context) async {
    final c = TextEditingController();
    String src = 'clinic';
    final s = context.appRead;
    await showDialog(
      context: context,
      builder: (dc) => StatefulBuilder(
        builder: (dc, set) => AlertDialog(
          title: Text(s.tr(const Tx('Add weight', 'Ongeza uzito'))),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: c,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'kg', hintText: '4.5'),
              ),
              const Gap(12),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'clinic', label: Text(s.tr(const Tx('Clinic', 'Kliniki')))),
                  ButtonSegment(value: 'home', label: Text(s.tr(const Tx('Home', 'Nyumbani')))),
                ],
                selected: {src},
                onSelectionChanged: (v) => set(() => src = v.first),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dc), child: Text(s.tr(const Tx('Cancel', 'Ghairi')))),
            FilledButton(
              onPressed: () {
                final kg = double.tryParse(c.text.replaceAll(',', '.'));
                if (kg != null && kg >= 0.3 && kg <= 20) {
                  s.addGrowth(weightG: (kg * 1000).round(), source: src);
                  Navigator.pop(dc);
                }
              },
              child: Text(s.tr(const Tx('Save', 'Hifadhi'))),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyCheckCard extends StatelessWidget {
  final String babyId, name;
  const _DailyCheckCard({required this.babyId, required this.name});
  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final last = s.checkinsFor(babyId).firstOrNull;
    final lv = last == null ? null : s.levelOf(last);
    return AppCard(
      key: const Key('baby-daily-check'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckHistoryStrip(s.checkHistory(babyId)),
          if (last != null) ...[
            const Gap(12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(levelIcon(lv!), color: levelColor(lv)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${context.t('Last check', 'Ukaguzi wa mwisho')} · ${fmtDay(parseTs(last['client_created_at'] as String), s.lang)}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        context.tx(LevelBanner.title(lv)),
                        style: TextStyle(color: levelColor(lv), fontWeight: FontWeight.w700),
                      ),
                      for (final r in s.reasonsOf(last)) Text('· ${context.tx(r)}'),
                      if ((last['note'] as String?)?.isNotEmpty ?? false) Text('"${last['note']}"', style: const TextStyle(fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const Gap(12),
          FilledButton.icon(
            key: const Key('baby-check-now'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CheckinScreen())),
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(context.t('Check $name now', 'Mkague $name sasa')),
          ),
        ],
      ),
    );
  }
}

/// Given / due / coming for one vaccine visit.
class _VxStatus extends StatelessWidget {
  final List<VaccineStatus> doses;
  const _VxStatus(this.doses);
  @override
  Widget build(BuildContext context) {
    final all = doses.every((d) => d.given);
    final late = !all && doses.any((d) => !d.given && d.due.isBefore(today()));
    final (txt, col) = all
        ? (context.t('given', 'imetolewa'), C.green)
        : late
        ? (context.t('due', 'imefika'), C.amber)
        : (context.t('coming', 'inakuja'), C.ink3);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: col.withValues(alpha: .12), borderRadius: BorderRadius.circular(999)),
      child: Text(
        txt,
        style: TextStyle(color: col, fontWeight: FontWeight.w700, fontSize: 13),
      ),
    );
  }
}
