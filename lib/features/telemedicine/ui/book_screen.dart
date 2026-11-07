import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/dates.dart';
import '../data/booking_service.dart';
import '../../../ui/content_widgets.dart';
import '../../../ui/theme.dart';
import '../../../ui/widgets.dart';
import 'booking_format.dart';
import 'booking_screen.dart';

/// Booking in three steps: how to meet → day and time → check and book.
class BookScreen extends StatefulWidget {
  const BookScreen({super.key});
  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  int step = 0;
  String? mode;
  late String? facilityId = context.appRead.facility?['id'] as String?;
  List<Slot>? slots;
  DateTime? day;
  Slot? slot;
  bool loading = false, busy = false;
  String? err;
  final reason = TextEditingController();

  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _facility => context.appRead.facilityList.where((f) => f['id'] == facilityId).firstOrNull ?? context.appRead.facility;

  Future<void> _pickMode(String m) async {
    setState(() {
      mode = m;
      step = 1;
      loading = true;
      err = null;
      slots = null;
      day = null;
      slot = null;
    });
    try {
      final r = await context.appRead.bookings.openSlots(facilityId!, m);
      if (!mounted) return;
      setState(() {
        slots = r;
        day = r.isEmpty ? null : sod(r.first.startsAt);
      });
    } on Object {
      if (mounted) setState(() => err = context.t('Could not load free times. Check your internet.', 'Imeshindikana kupata nafasi. Kagua intaneti.'));
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _book() async {
    setState(() {
      busy = true;
      err = null;
    });
    try {
      final b = await context.appRead.bookings.book(slot!, reason: reason.text.trim().isEmpty ? null : reason.text.trim());
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => BookingScreen(b, justBooked: true)));
      return;
    } on BookingError catch (e) {
      // someone else took the time: show the fresh times first, then say why
      if (e.problem == BookingProblem.taken) await _pickMode(mode!);
      if (!mounted) return;
      setState(
        () => err = switch (e.problem) {
          BookingProblem.taken => context.t('Someone just took this time. Please choose another.', 'Mtu amechukua muda huu sasa hivi. Tafadhali chagua mwingine.'),
          BookingProblem.tooMany => context.t(
            'You already have 3 appointments coming up. Cancel one to book another.',
            'Tayari una miadi 3 inayokuja. Ghairi mmoja upange mwingine.',
          ),
          BookingProblem.offline => context.t('Not booked. Check your internet and try again.', 'Haijapangwa. Kagua intaneti kisha ujaribu tena.'),
        },
      );
    }
    if (mounted) setState(() => busy = false);
  }

  Widget _modeCard(String m, String picture, IconData icon, String title, String sub) => AppCard(
    key: Key('mode-$m'),
    onTap: facilityId == null ? null : () => _pickMode(m),
    padding: const EdgeInsets.all(Sp.md),
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(R.medium),
          child: SizedBox(
            width: 88,
            height: 88,
            child: ContentPicture(
              picture,
              height: 88,
              radius: R.medium,
              fallback: Container(color: C.primarySoft, child: Icon(icon, size: 40, color: C.primary)),
            ),
          ),
        ),
        const SizedBox(width: Sp.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.h3),
              const Gap(Sp.xs),
              Text(sub, style: AppTypography.bodyText),
            ],
          ),
        ),
        const Icon(Icons.chevron_right, color: C.ink2),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final f = _facility;
    final days = <DateTime>{for (final x in slots ?? const <Slot>[]) sod(x.startsAt)}.toList()..sort();
    final times = (slots ?? const <Slot>[]).where((x) => day != null && sod(x.startsAt) == day).toList();
    return PopScope(
      canPop: step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => step--);
      },
      child: AppScaffold(
        title: context.t('Book a visit', 'Panga miadi'),
        bottom: switch (step) {
          1 => PrimaryButton(key: const Key('book-next'), context.t('Next', 'Endelea'), onPressed: slot == null ? null : () => setState(() => step = 2)),
          2 => PrimaryButton(key: const Key('book-confirm'), context.t('Book this time', 'Panga muda huu'), icon: Icons.check, loading: busy, onPressed: busy ? null : _book),
          _ => null,
        },
        children: [
          StepProgress(step: step, total: 3),
          const Gap(Sp.md),
          if (step == 0) ...[
            Text(context.t('How do you want to meet?', 'Ungependa kukutana vipi?'), style: AppTypography.h2),
            const Gap(Sp.md),
            if (s.facility?['id'] == null || s.facilityList.length > 1) ...[
              DropdownButtonFormField<String>(
                key: const Key('book-facility'),
                initialValue: facilityId,
                isExpanded: true,
                decoration: InputDecoration(labelText: context.t('Your clinic', 'Kliniki yako')),
                items: [for (final x in s.facilityList) DropdownMenuItem(value: x['id'] as String, child: Text('${x['name']}', overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => facilityId = v),
              ),
              if (s.facilityList.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: Sp.sm),
                  child: Text(
                    context.t('Connect to the internet once to see the clinics.', 'Unganisha intaneti mara moja kuona kliniki.'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const Gap(Sp.md),
            ] else if (f != null) ...[
              Text(context.t('At ${f['name']}', 'Kwenye ${f['name']}'), style: Theme.of(context).textTheme.bodyLarge),
              const Gap(Sp.md),
            ],
            _modeCard(
              'video',
              'BOOK-VIDEO',
              Icons.videocam_outlined,
              context.t('Video call', 'Simu ya video'),
              context.t('Talk to a health worker from home, on this phone.', 'Ongea na mhudumu wa afya ukiwa nyumbani, kwa simu hii.'),
            ),
            const Gap(Sp.smd),
            _modeCard(
              'clinic',
              'BOOK-CLINIC',
              Icons.local_hospital_outlined,
              context.t('Visit the clinic', 'Kwenda kliniki'),
              context.t('Book a time so you wait less.', 'Panga muda ili usubiri kidogo.'),
            ),
            const Gap(Sp.md),
            Text(
              context.t('In an emergency, do not book: go now or open Emergency help.', 'Wakati wa dharura usipange miadi: nenda sasa au fungua Msaada wa dharura.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (step == 1) ...[
            Text(context.t('Choose a day and time', 'Chagua siku na muda'), style: AppTypography.h2),
            const Gap(Sp.md),
            if (err != null && slots != null) ...[ErrorState(err!), const Gap(Sp.md)],
            if (loading)
              LoadingState(context.t('Finding free times…', 'Inatafuta nafasi…'))
            else if (err != null && slots == null)
              ErrorState(err!, retryLabel: context.t('Try again', 'Jaribu tena'), onRetry: () => _pickMode(mode!))
            else if (days.isEmpty) ...[
              EmptyState(
                Icons.event_busy_outlined,
                context.t('No free times in the next 2 weeks. Please call your clinic.', 'Hakuna nafasi katika wiki 2 zijazo. Tafadhali piga simu kliniki.'),
              ),
              if (f?['phone'] != null)
                OutlineButton(
                  context.t('Call the clinic', 'Piga simu kliniki'),
                  icon: Icons.call,
                  onPressed: () => launchUrl(Uri(scheme: 'tel', path: '${f!['phone']}'.replaceAll(' ', ''))),
                ),
            ] else ...[
              Wrap(
                spacing: Sp.sm,
                runSpacing: Sp.sm,
                children: [
                  for (final (i, d) in days.indexed)
                    ChoiceChip(
                      key: Key('day-$i'),
                      label: Text(dayLabel(context, d)),
                      selected: day == d,
                      onSelected: (_) => setState(() {
                        day = d;
                        slot = null;
                      }),
                    ),
                ],
              ),
              const Gap(Sp.lg),
              Text(context.t('Time', 'Muda'), style: Theme.of(context).textTheme.titleMedium),
              const Gap(Sp.sm),
              Wrap(
                spacing: Sp.sm,
                runSpacing: Sp.sm,
                children: [
                  for (final x in times)
                    ChoiceChip(key: Key('slot-${x.id}'), label: Text(fmtTime(x.startsAt)), selected: slot?.id == x.id, onSelected: (_) => setState(() => slot = x)),
                ],
              ),
            ],
          ],
          if (step == 2 && slot != null) ...[
            Text(context.t('Check and book', 'Hakiki na upange'), style: AppTypography.h2),
            const Gap(Sp.md),
            AppCard(
              color: C.primarySoft,
              border: C.primary.withValues(alpha: .18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(whenLabel(slot!.startsAt, s.lang), style: AppTypography.h3),
                  const Gap(Sp.xs),
                  Text(
                    '${mode == 'video' ? context.t('Video call', 'Simu ya video') : context.t('Clinic visit', 'Kliniki')} · ${slot!.minutes} min',
                    style: AppTypography.bodyText,
                  ),
                  if (f != null) Text('${f['name']}', style: AppTypography.bodyText),
                  if (slot!.staffName != null) Text(context.t('With ${slot!.staffName}', 'Na ${slot!.staffName}'), style: AppTypography.bodyText),
                ],
              ),
            ),
            const Gap(Sp.md),
            TextField(
              key: const Key('book-reason'),
              controller: reason,
              maxLength: 300,
              maxLines: 3,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: context.t('What would you like to talk about? (optional)', 'Ungependa kuzungumzia nini? (si lazima)'),
                hintText: context.t('For example: swollen feet, feeding, a question about tablets', 'Mfano: miguu kuvimba, kunyonyesha, swali kuhusu vidonge'),
              ),
            ),
            if (err != null) ErrorState(err!),
          ],
        ],
      ),
    );
  }
}
