import 'package:flutter/material.dart';

import '../data/booking_service.dart';
import '../../../ui/theme.dart';
import '../../../ui/widgets.dart';
import 'book_screen.dart';
import 'booking_format.dart';
import 'booking_screen.dart';

/// Appointments: her upcoming clinic visits and video calls with a health worker, and booking a new one.
class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key});
  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.appRead.bookings.refresh());
  }

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final up = s.bookings.upcoming;
    final past = s.bookings.all.where((b) => !b.upcoming(s.now())).take(5).toList();
    void open(Booking b) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookingScreen(b)));
    return AppScaffold(
      title: context.t('Appointments', 'Miadi'),
      children: [
        AppHeader(
          context.t('See a health worker', 'Muone mhudumu wa afya'),
          subtitle: context.t('Book a visit at your clinic, or talk on a video call from home.', 'Panga kwenda kliniki, au ongea kwa simu ya video ukiwa nyumbani.'),
        ),
        if (!s.signedIn)
          EmptyState(Icons.event_busy_outlined, context.t('Booking needs you to be signed in, with internet.', 'Kupanga miadi kunahitaji uwe umeingia, na uwe na intaneti.'))
        else ...[
          PrimaryButton(
            key: const Key('book-start'),
            context.t('Book an appointment', 'Panga miadi'),
            icon: Icons.add,
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BookScreen())),
          ),
          SectionTitle(context.t('Coming up', 'Inayokuja')),
          if (up.isEmpty)
            EmptyState(Icons.event_available_outlined, context.t('No appointments booked.', 'Hakuna miadi iliyopangwa.'))
          else
            for (final b in up) ...[BookingTile(b, onTap: () => open(b)), const Gap(Sp.sm)],
          if (past.isNotEmpty) ...[
            SectionTitle(context.t('Earlier', 'Zilizopita')),
            for (final b in past) ...[BookingTile(b, onTap: () => open(b)), const Gap(Sp.sm)],
          ],
        ],
      ],
    );
  }
}

/// One appointment in a list (also used on Home).
class BookingTile extends StatelessWidget {
  final Booking b;
  final VoidCallback onTap;
  const BookingTile(this.b, {super.key, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final status = switch (b.status) {
      'cancelled' => context.t('Cancelled', 'Imeghairiwa'),
      'done' => context.t('Done', 'Imefanyika'),
      'missed' => context.t('Missed', 'Hukuhudhuria'),
      _ => null,
    };
    return AppCard(
      key: Key('booking-${b.id}'),
      onTap: onTap,
      padding: const EdgeInsets.all(Sp.md),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: C.primarySoft, borderRadius: BorderRadius.circular(R.medium)),
            child: Icon(b.video ? Icons.videocam_outlined : Icons.local_hospital_outlined, color: C.primary),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(whenLabel(b.startsAt, s.lang), style: Theme.of(context).textTheme.titleMedium),
                Text(
                  '${b.video ? context.t('Video call', 'Simu ya video') : context.t('Clinic visit', 'Kliniki')}${b.facilityName == null ? '' : ' · ${b.facilityName}'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (status != null) Text(status, style: Theme.of(context).textTheme.bodySmall!.copyWith(color: C.ink2, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (b.canJoin(s.now())) StatusBadge(context.t('Join now', 'Ingia sasa'), color: C.green, icon: Icons.videocam) else const Icon(Icons.chevron_right, color: C.ink2),
        ],
      ),
    );
  }
}
