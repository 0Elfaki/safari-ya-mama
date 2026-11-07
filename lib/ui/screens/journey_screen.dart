import 'package:go_router/go_router.dart';

import '../../app/router.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/content.dart';
import '../../core/dates.dart';
import '../../core/tx.dart';
import '../theme.dart';
import '../widgets.dart';
import '../../features/telemedicine/ui/appointments_screen.dart';
import 'baby_screen.dart';
import 'doctor_note_screen.dart';
import 'health_screen.dart';
import 'library_screen.dart';
import 'visits_screen.dart';

/// My Journey: one place for tracking, with a Mother | Baby switch.
/// Mother: pregnancy progress or recovery, clinic visits, symptom diary, movements, contractions.
/// Baby: feeding, growth, vaccines, development (the baby tracker).
class JourneyScreen extends StatefulWidget {
  const JourneyScreen({super.key});
  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen> {
  String? who; // null = follow the stage (baby after birth)

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final sel = who ?? (s.pregnant ? 'mother' : 'baby');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Sp.md, Sp.xs, Sp.md, Sp.sm),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              key: const Key('journey-who'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 'mother', icon: const Icon(Icons.pregnant_woman), label: Text(context.t('Mother', 'Mama'))),
                ButtonSegment(value: 'baby', icon: const Icon(Icons.child_care), label: Text(context.t('Baby', 'Mtoto'))),
              ],
              selected: {sel},
              onSelectionChanged: (v) => setState(() => who = v.first),
            ),
          ),
        ),
        Expanded(
          child: IndexedStack(index: sel == 'mother' ? 0 : 1, children: const [HealthScreen(), BabyScreen()]),
        ),
      ],
    );
  }
}

/// Tracking tools at the top of the Mother view.
class MotherTools extends StatelessWidget {
  const MotherTools({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.app;
    void go(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    final last = s.checkins.firstOrNull;
    final tiles = <Widget>[
      ActionTile(
        key: const Key('tool-diary'),
        icon: Icons.fact_check_outlined,
        label: context.t('Symptom diary', 'Shajara ya dalili'),
        sub: last == null ? context.t('No checks yet', 'Bado hakuna ukaguzi') : fmtDay(parseTs(last['client_created_at'] as String), s.lang),
        onTap: () => go(const SymptomDiaryScreen()),
      ),
      ActionTile(
        key: const Key('tool-visits'),
        icon: Icons.event_available_outlined,
        label: context.t('Clinic visits', 'Kliniki'),
        sub: s.nextVisit == null ? null : fmtDay(s.nextVisit!.due, s.lang),
        onTap: () => go(
          Scaffold(
            appBar: AppBar(title: Text(context.t('Clinic visits', 'Kliniki')), actions: const [EmergencyButton()]),
            body: const VisitsScreen(),
          ),
        ),
      ),
      ActionTile(
        key: const Key('tool-appointments'),
        icon: Icons.medical_services_outlined,
        label: context.t('Appointments', 'Miadi'),
        sub: s.bookings.next == null ? context.t('Clinic or video call', 'Kliniki au simu ya video') : fmtDay(s.bookings.next!.startsAt, s.lang),
        onTap: () => go(const AppointmentsScreen()),
      ),
      ActionTile(
        key: const Key('tool-note'),
        icon: Icons.description_outlined,
        label: context.t("Doctor's Note", 'Taarifa kwa daktari'),
        sub: context.t('Summary for your clinician', 'Muhtasari kwa mhudumu'),
        onTap: () => go(const DoctorNoteScreen()),
      ),
      if (s.pregnant && s.weeks >= 20)
        ActionTile(
          key: const Key('tool-movements'),
          icon: Icons.favorite_border,
          label: context.t("Baby's movements", 'Mtoto kucheza'),
          sub: s.movementToday == null ? context.t('Not noted today', 'Bado leo') : context.t('Noted today', 'Umeandika leo'),
          onTap: () => go(const MovementsScreen()),
        ),
      if (s.pregnant && s.weeks >= 24)
        ActionTile(
          key: const Key('tool-contractions'),
          icon: Icons.timer_outlined,
          label: context.t('Contraction timer', 'Kipima uchungu'),
          sub: context.t('Time tightenings', 'Pima mikazo'),
          onTap: () => go(const ContractionTimerScreen()),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.lg),
      child: TileGrid(children: tiles),
    );
  }
}

/// Every daily check, newest first, with its level and reasons (the symptom diary).
class SymptomDiaryScreen extends StatelessWidget {
  const SymptomDiaryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final rows = s.checkins;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('Symptom diary', 'Shajara ya dalili')), actions: const [EmergencyButton()]),
      body: Pad(
        children: [
          Text(
            context.t('Each daily check you did, newest first.', 'Kila ukaguzi wa kila siku ulioufanya, wa karibuni kwanza.'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const Gap(Sp.md),
          if (rows.isEmpty)
            AppCard(
              child: EmptyNote(
                Icons.fact_check_outlined,
                context.t(
                  'No checks yet. Do your first daily check from Home or MamaBot.',
                  'Bado hakuna ukaguzi. Fanya ukaguzi wa kwanza kutoka Nyumbani au MamaBot.',
                ),
              ),
            ),
          for (final r in rows.take(60)) ...[
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${fmtDayYear(parseTs(r['client_created_at'] as String), s.lang)} · ${fmtTime(parseTs(r['client_created_at'] as String))}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const Gap(Sp.sm),
                  StatusPill(
                    context.tx(LevelBanner.status(s.levelOf(r))),
                    color: levelColor(s.levelOf(r)),
                    icon: levelIcon(s.levelOf(r)),
                    background: levelSoft(s.levelOf(r)),
                  ),
                  for (final t in s.reasonsOf(r)) ...[const Gap(Sp.xs), Text('• ${context.tx(t)}', style: Theme.of(context).textTheme.bodyLarge)],
                ],
              ),
            ),
            const Gap(Sp.md - 4),
          ],
        ],
      ),
    );
  }
}

/// Baby's movements: one answer a day. There is no number to reach (WHO; lesson "kicks").
/// Fewer than usual → contact a health worker today (amber); not moving → go now (red),
/// the same levels the daily check gives for the same answers.
class MovementsScreen extends StatelessWidget {
  const MovementsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final today = s.movementToday;
    final level = switch (today) {
      'none' => Level.red,
      'fewer' => Level.amber,
      _ => null,
    };
    final f = s.facility;
    Widget answer(String v, IconData icon, String label) => Padding(
      padding: const EdgeInsets.only(bottom: Sp.md - 4),
      child: AppCard(
        key: Key('move-$v'),
        border: today == v ? C.primary : null,
        color: today == v ? C.primarySoft : null,
        onTap: () => s.logMovement(v),
        child: Row(
          children: [
            Icon(icon, color: C.primary),
            const SizedBox(width: Sp.md - 4),
            Expanded(child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
            Icon(today == v ? Icons.radio_button_checked : Icons.radio_button_off, color: today == v ? C.primary : C.ink3),
          ],
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(context.t('Movements', 'Mtoto kucheza')), actions: const [EmergencyButton()]),
      body: Pad(
        children: [
          Row(
            children: [
              Expanded(child: Text(context.t('How is your baby moving today?', 'Mtoto anachezaje leo?'), style: Theme.of(context).textTheme.headlineSmall)),
              ListenButton(
                context.t(
                  'How is your baby moving today? There is no number to reach. Compare with what is usual for your baby.',
                  'Mtoto anachezaje leo? Hakuna idadi ya kufikia. Linganisha na kawaida ya mtoto wako.',
                ),
              ),
            ],
          ),
          const Gap(Sp.sm),
          Text(
            context.t(
              'There is no number to reach. Compare with what is usual for your baby: kicks, rolls and swishes.',
              'Hakuna idadi ya kufikia. Linganisha na kawaida ya mtoto wako: mateke, kujigeuza na mitikisiko.',
            ),
          ),
          const Gap(Sp.md),
          answer('usual', Icons.favorite, context.t('As usual', 'Kama kawaida')),
          answer('fewer', Icons.trending_down, context.t('Fewer than usual', 'Kidogo kuliko kawaida')),
          answer('none', Icons.do_not_disturb_on_outlined, context.t('I have not felt my baby move', 'Sijamhisi mtoto akicheza')),
          if (level != null) ...[
            const Gap(Sp.sm),
            LevelBanner(
              level,
              reasons: [
                context.tx(
                  level == Level.red
                      ? const Tx('Baby not moving', 'Mtoto hachezi')
                      : const Tx('Baby moving less than usual', 'Mtoto anacheza kidogo kuliko kawaida'),
                ),
              ],
            ),
            const Gap(Sp.md - 4),
            if (level == Level.red)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: C.red, minimumSize: const Size.fromHeight(52)),
                onPressed: () => context.push(Routes.emergency),
                icon: const Icon(Icons.emergency),
                label: Text(context.t('Emergency help', 'Msaada wa dharura')),
              )
            else if (f != null && '${f['phone'] ?? ''}'.isNotEmpty)
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () => launchUrl(Uri(scheme: 'tel', path: '${f['phone']}'.replaceAll(' ', ''))),
                icon: const Icon(Icons.call),
                label: Text(context.t('Call ${f['name']}', 'Piga ${f['name']}')),
              ),
          ],
          SectionTitle(context.t('Last days', 'Siku zilizopita')),
          if (s.movementLog.isEmpty)
            Text(context.t('Nothing noted yet.', 'Bado hakuna kilichoandikwa.'), style: Theme.of(context).textTheme.bodyMedium)
          else
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.xs),
              child: Column(
                children: [
                  for (final m in s.movementLog.take(14))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(fmtDay(parseDay(m['day'] as String), s.lang)),
                      trailing: Text(switch (m['answer']) {
                        'none' => context.t('Not felt', 'Hakuhisiwa'),
                        'fewer' => context.t('Fewer', 'Kidogo'),
                        _ => context.t('As usual', 'Kama kawaida'),
                      }, style: Theme.of(context).textTheme.titleMedium),
                    ),
                ],
              ),
            ),
          const Gap(Sp.md),
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LessonScreen('kicks'))),
            child: Text(context.t("Learn about your baby's movements", 'Jifunze kuhusu mtoto kucheza')),
          ),
          const OfflineNote(),
        ],
      ),
    );
  }
}

/// Contraction timer: start when a tightening begins, stop when it ends. Shows how long each
/// one lasts and how far apart they are. It gives no number-based verdict; the advice is the
/// same as the "Signs of labour" lesson.
class ContractionTimerScreen extends StatefulWidget {
  const ContractionTimerScreen({super.key});
  @override
  State<ContractionTimerScreen> createState() => _ContractionTimerScreenState();
}

class _ContractionTimerScreenState extends State<ContractionTimerScreen> {
  final done = <(DateTime start, Duration length)>[];
  DateTime? running;
  Timer? tick;

  @override
  void dispose() {
    tick?.cancel();
    super.dispose();
  }

  void _toggle() {
    final now = DateTime.now();
    setState(() {
      if (running == null) {
        running = now;
        tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
      } else {
        done.insert(0, (running!, now.difference(running!)));
        running = null;
        tick?.cancel();
      }
    });
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final on = running != null;
    final elapsed = on ? DateTime.now().difference(running!) : Duration.zero;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('Contractions', 'Uchungu')), actions: const [EmergencyButton()]),
      body: Pad(
        children: [
          Text(
            context.t('Tap when a tightening starts, and again when it ends.', 'Gusa mkazo unapoanza, na tena unapoisha.'),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const Gap(Sp.lg),
          Center(
            child: Semantics(
              button: true,
              label: on ? context.t('Tightening ended', 'Mkazo umeisha') : context.t('Tightening started', 'Mkazo umeanza'),
              child: InkWell(
                key: const Key('contraction-toggle'),
                onTap: _toggle,
                customBorder: const CircleBorder(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: on ? C.primaryDeep : C.primary),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        on ? _fmt(elapsed) : context.t('Start', 'Anza'),
                        style: const TextStyle(
                          fontFamily: display,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const Gap(Sp.xs),
                      Text(
                        on ? context.t('Tap when it ends', 'Gusa ukiisha') : context.t('Tap when it starts', 'Gusa ukianza'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const Gap(Sp.lg),
          AppCard(
            color: C.amberSoft,
            border: C.amber.withValues(alpha: .35),
            child: Text(
              context.t(
                'Regular, painful tightenings that get stronger and closer together mean labour: go to your facility. If your water breaks, go even without pain. Heavy bleeding is not normal labour: go now.',
                'Mikazo ya mara kwa mara yenye maumivu inayozidi kuwa mikali na kukaribiana ni uchungu wa kujifungua: nenda kituoni. Maji yakivunjika, nenda hata bila maumivu. Kutokwa damu nyingi si uchungu wa kawaida: nenda sasa.',
              ),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          if (done.isNotEmpty) ...[
            SectionTitle(
              context.t('This session', 'Kipindi hiki'),
              trailing: TextButton(onPressed: () => setState(done.clear), child: Text(context.t('Clear', 'Futa'))),
            ),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.xs),
              child: Column(
                children: [
                  for (var i = 0; i < done.length; i++)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${fmtTime(done[i].$1)} · ${context.t('lasted', 'ilidumu')} ${_fmt(done[i].$2)}',
                        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
                      ),
                      subtitle: i + 1 < done.length ? Text('${context.t('Apart', 'Tofauti')}: ${_fmt(done[i].$1.difference(done[i + 1].$1))}') : null,
                    ),
                ],
              ),
            ),
          ],
          const Gap(Sp.md),
          const OfflineNote(),
        ],
      ),
    );
  }
}
