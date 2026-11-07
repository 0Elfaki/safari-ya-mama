import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/dates.dart';
import '../../../data/remote.dart';
import '../data/booking_service.dart';
import '../../../ui/theme.dart';
import '../../../ui/widgets.dart';
import '../../../ui/screens/doctor_note_screen.dart';
import 'booking_format.dart';

/// One appointment: when and where, joining the video call, the Doctor's Note, cancelling.
class BookingScreen extends StatefulWidget {
  final Booking booking;
  final bool justBooked;
  const BookingScreen(this.booking, {super.key, this.justBooked = false});
  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  bool joining = false;
  String? err;

  Booking get b => context.appRead.bookings.all.where((x) => x.id == widget.booking.id).firstOrNull ?? widget.booking;

  Future<void> _join() async {
    setState(() {
      joining = true;
      err = null;
    });
    try {
      final url = await context.appRead.bookings.joinUrl(b.id);
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok && mounted) setState(() => err = context.t('Could not open the call. Is a browser installed?', 'Imeshindikana kufungua simu. Je, kuna kivinjari?'));
    } on RemoteError catch (e) {
      if (mounted) {
        setState(
          () => err = switch (e.code) {
            'too_early' => context.t('The call opens 15 minutes before the start.', 'Simu inafunguka dakika 15 kabla ya kuanza.'),
            'ended' => context.t('This call has ended or was cancelled.', 'Simu hii imekwisha au imeghairiwa.'),
            _ => context.t('Could not join. Check your internet and try again.', 'Imeshindikana kuingia. Kagua intaneti kisha ujaribu tena.'),
          },
        );
      }
    } on Object {
      if (mounted) setState(() => err = context.t('Could not join. Check your internet and try again.', 'Imeshindikana kuingia. Kagua intaneti kisha ujaribu tena.'));
    }
    if (mounted) setState(() => joining = false);
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(c.t('Cancel this appointment?', 'Ghairi miadi hii?')),
        content: Text(c.t('The time will be free for another mother.', 'Muda utakuwa wazi kwa mama mwingine.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(c.t('Keep it', 'Iache'))),
          TextButton(key: const Key('confirm-cancel'), onPressed: () => Navigator.pop(c, true), child: Text(c.t('Cancel it', 'Ighairi'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.appRead.bookings.cancel(b.id);
      if (mounted) Navigator.of(context).pop();
    } on Object {
      if (mounted) setState(() => err = context.t('Not cancelled. Check your internet.', 'Haijaghairiwa. Kagua intaneti.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final b = this.b;
    final tt = Theme.of(context).textTheme;
    final booked = b.status == 'booked';
    return AppScaffold(
      title: b.video ? context.t('Video call', 'Simu ya video') : context.t('Clinic visit', 'Kliniki'),
      children: [
        if (widget.justBooked) ...[
          HealthCard(
            tone: C.green,
            background: C.greenSoft,
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: C.green, size: 32),
                const SizedBox(width: Sp.smd),
                Expanded(
                  child: Text(
                    s.phoneReminders
                        ? context.t('You are booked. We will remind you the evening before.', 'Umepangiwa. Tutakukumbusha jioni ya siku iliyotangulia.')
                        : context.t('You are booked. It is on your Home screen.', 'Umepangiwa. Iko kwenye skrini ya Nyumbani.'),
                    style: tt.titleMedium,
                  ),
                ),
              ],
            ),
          ),
          const Gap(Sp.md),
        ],
        HeroCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(b.video ? Icons.videocam_outlined : Icons.local_hospital_outlined, color: Colors.white),
                  const SizedBox(width: Sp.sm),
                  Text(b.video ? context.t('Video call', 'Simu ya video') : context.t('Clinic visit', 'Kliniki'), style: const TextStyle(color: C.onPrimaryMuted)),
                ],
              ),
              const Gap(Sp.sm),
              Text(whenLabel(b.startsAt, s.lang), style: AppTypography.h2.copyWith(color: Colors.white)),
              Text('${b.minutes} min${b.facilityName == null ? '' : ' · ${b.facilityName}'}', style: const TextStyle(color: C.onPrimaryMuted)),
              if (b.staffName != null) Text(context.t('With ${b.staffName}', 'Na ${b.staffName}'), style: const TextStyle(color: Colors.white)),
              if (!booked) ...[
                const Gap(Sp.sm),
                Text(
                  switch (b.status) {
                    'cancelled' => context.t('Cancelled', 'Imeghairiwa'),
                    'done' => context.t('Done', 'Imefanyika'),
                    _ => context.t('Missed', 'Hukuhudhuria'),
                  },
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
        ),
        if (b.outcomeNote != null) ...[
          const Gap(Sp.md),
          AppCard(
            key: const Key('booking-advice'),
            color: C.greenSoft,
            border: C.green.withValues(alpha: .25),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.medical_services_outlined, color: C.green),
                    const SizedBox(width: Sp.sm),
                    Expanded(child: Text(context.t("Health worker's advice", 'Ushauri wa mhudumu wa afya'), style: tt.titleMedium!.copyWith(color: C.green))),
                  ],
                ),
                const Gap(Sp.sm),
                Text(b.outcomeNote!, style: tt.bodyLarge),
                const Gap(Sp.sm),
                Text(
                  context.t('If you feel worse, do not wait: open Emergency help.', 'Ukijisikia vibaya zaidi, usisubiri: fungua Msaada wa dharura.'),
                  style: tt.bodySmall,
                ),
              ],
            ),
          ),
        ],
        if (b.reason != null) ...[const Gap(Sp.md), Text(context.t('You want to talk about: ${b.reason}', 'Unataka kuzungumzia: ${b.reason}'), style: tt.bodyLarge)],
        const Gap(Sp.md),
        if (b.video && booked) ...[
          PrimaryButton(
            key: const Key('join-call'),
            context.t('Join video call', 'Ingia kwenye simu ya video'),
            icon: Icons.videocam,
            loading: joining,
            onPressed: b.canJoin(s.now()) && !joining ? _join : null,
          ),
          if (!b.canJoin(s.now()))
            Padding(
              padding: const EdgeInsets.only(top: Sp.sm),
              child: Text(
                context.t('This button works from ${fmtTime(b.opensAt)} on the day, 15 minutes before the start.', 'Kitufe hiki kinafanya kazi kuanzia saa ${fmtTime(b.opensAt)} siku hiyo, dakika 15 kabla ya kuanza.'),
                style: tt.bodySmall,
              ),
            ),
          const Gap(Sp.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.t('Before the call', 'Kabla ya simu'), style: tt.titleMedium),
                const Gap(Sp.sm),
                for (final (en, sw) in [
                  ('Find a quiet, private place with a good signal.', 'Tafuta mahali tulivu na faragha, penye mtandao mzuri.'),
                  ('Charge your phone and have your clinic card ready.', 'Chaji simu yako na uwe na kadi ya kliniki.'),
                  ('The call opens in your browser. Allow the camera and microphone.', 'Simu inafunguka kwenye kivinjari. Ruhusu kamera na kipaza sauti.'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: Sp.xs),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check, size: 20, color: C.primary),
                        const SizedBox(width: Sp.sm),
                        Expanded(child: Text(context.t(en, sw), style: tt.bodyMedium)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ] else if (booked)
          AppCard(child: Text(context.t('Bring your clinic card. If you cannot come, cancel so another mother can have the time.', 'Beba kadi yako ya kliniki. Usipoweza kuja, ghairi ili mama mwingine apate muda huo.'), style: tt.bodyLarge)),
        if (err != null) ...[const Gap(Sp.sm), ErrorState(err!)],
        if (booked) ...[
          const Gap(Sp.md),
          OutlineButton(
            key: const Key('booking-note'),
            context.t("Show my Doctor's Note", 'Onyesha taarifa yangu kwa daktari'),
            icon: Icons.description_outlined,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DoctorNoteScreen())),
          ),
          if (b.facilityPhone != null) ...[
            const Gap(Sp.sm),
            OutlineButton(
              context.t('Call the clinic', 'Piga simu kliniki'),
              icon: Icons.call,
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: b.facilityPhone!.replaceAll(' ', ''))),
            ),
          ],
          const Gap(Sp.md),
          TextButton(
            key: const Key('cancel-booking'),
            style: TextButton.styleFrom(foregroundColor: C.red),
            onPressed: _cancel,
            child: Text(context.t('Cancel appointment', 'Ghairi miadi')),
          ),
        ],
      ],
    );
  }
}
