import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/dates.dart';
import '../theme.dart';
import '../widgets.dart';
import '../../features/telemedicine/ui/appointments_screen.dart';
import '../../features/telemedicine/ui/booking_format.dart';
import 'doctor_note_screen.dart';
import 'visits_screen.dart';

/// Side menu (☰ on every tab): everything in the app in one list, in plain words.
/// The 5 tabs first, then the things she looks for most, then help and settings.
class AppDrawer extends StatelessWidget {
  final StatefulNavigationShell shell;
  const AppDrawer({super.key, required this.shell});

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final first = s.name.trim().split(' ').first;
    final stage = s.pregnant
        ? context.t('${s.weeks} weeks pregnant', 'Mimba ya wiki ${s.weeks}')
        : s.baby == null
        ? ''
        : context.t('${s.babiesLabel}: ${s.babyMonths} months', '${s.babiesLabel}: miezi ${s.babyMonths}');
    final unread = s.unreadNotifications;
    final next = s.bookings.next;

    final tab = shell.currentIndex;
    // close the menu, then act: tabs switch, screens open inside the current tab
    void then(void Function() action) {
      Scaffold.of(context).closeDrawer();
      action();
    }

    void goTab(int i) => then(() => shell.goBranch(i, initialLocation: i == tab));
    void open(Widget w) => then(() => branchKeys[tab].currentState?.push(MaterialPageRoute(builder: (_) => w)));

    Widget item(String key, IconData icon, String label, VoidCallback onTap, {bool selected = false, String? sub, Widget? trailing}) => ListTile(
      key: Key(key),
      leading: Icon(icon, color: selected ? C.primary : C.ink2),
      title: Text(label, style: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? C.primary : C.ink)),
      subtitle: sub == null ? null : Text(sub),
      trailing: trailing,
      selected: selected,
      selectedTileColor: C.primarySoft,
      minTileHeight: 52,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.pill)),
      contentPadding: const EdgeInsets.symmetric(horizontal: Sp.md),
      onTap: onTap,
    );
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(Sp.md, Sp.md, Sp.md, Sp.xs),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge!.copyWith(color: C.ink2)),
    );

    return Drawer(
      key: const Key('app-drawer'),
      backgroundColor: C.bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // who she is and where she is in the journey
            Container(
              margin: const EdgeInsets.fromLTRB(Sp.smd, Sp.smd, Sp.smd, Sp.sm),
              padding: const EdgeInsets.all(Sp.md),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [C.primary, C.primaryDeep], begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(R.large),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: Image.asset('assets/brand/mark.png'),
                  ),
                  const SizedBox(width: Sp.smd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          first.isEmpty ? 'Safari ya Mama' : context.t('Hello, $first', 'Habari, $first'),
                          style: AppTypography.h3.copyWith(color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (stage.isNotEmpty) Text(stage, style: const TextStyle(color: C.onPrimaryMuted, fontSize: 14)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: Sp.sm),
                children: [
                  item('menu-home', Icons.home_outlined, context.t('Home', 'Nyumbani'), () => goTab(0), selected: tab == 0),
                  item('menu-care', Icons.monitor_heart_outlined, context.t('My Care', 'Huduma yangu'), () => goTab(1), selected: tab == 1),
                  item('menu-mamabot', Icons.chat_bubble_outline_rounded, context.t('Ask MamaBot', 'Muulize MamaBot'), () => goTab(2), selected: tab == 2),
                  item('menu-community', Icons.groups_outlined, context.t("Mothers' circle", 'Kikundi cha akina mama'), () => goTab(3), selected: tab == 3),
                  item('menu-learn', Icons.menu_book_outlined, context.t('Learn', 'Jifunze'), () => goTab(4), selected: tab == 4),
                  const Divider(indent: Sp.md, endIndent: Sp.md),
                  heading(context.t('My health', 'Afya yangu')),
                  item(
                    'menu-appointments',
                    Icons.medical_services_outlined,
                    context.t('Appointments', 'Miadi'),
                    () => open(const AppointmentsScreen()),
                    sub: next == null ? context.t('Clinic visit or video call', 'Kliniki au simu ya video') : fmtWhen(context, next.startsAt),
                  ),
                  item(
                    'menu-visits',
                    Icons.event_available_outlined,
                    context.t('Clinic visit schedule', 'Ratiba ya kliniki'),
                    () => open(
                      Scaffold(
                        appBar: AppBar(title: Text(context.t('Clinic visits', 'Kliniki')), actions: const [EmergencyShortcut()]),
                        body: const VisitsScreen(),
                      ),
                    ),
                  ),
                  item('menu-note', Icons.description_outlined, context.t("Doctor's Note", 'Taarifa kwa daktari'), () => open(const DoctorNoteScreen())),
                  item(
                    'menu-notifications',
                    Icons.notifications_none_rounded,
                    context.t('Notifications and reminders', 'Arifa na vikumbusho'),
                    () => then(() => context.push(Routes.notifications)),
                    trailing: unread > 0 ? Badge(backgroundColor: C.primary, label: Text('$unread')) : null,
                  ),
                  const Divider(indent: Sp.md, endIndent: Sp.md),
                  item('open-profile', Icons.account_circle_outlined, context.t('Profile and settings', 'Wasifu na mipangilio'), () => then(() => context.push(Routes.profile))),
                  item(
                    'menu-language',
                    Icons.translate,
                    s.lang == 'sw' ? 'Switch to English' : 'Badilisha kwenda Kiswahili',
                    () => s.setLang(s.lang == 'sw' ? 'en' : 'sw'),
                  ),
                ],
              ),
            ),
            // emergency help is always at the bottom of the menu, in red
            Padding(
              padding: const EdgeInsets.all(Sp.smd),
              child: DangerButton(
                key: const Key('menu-emergency'),
                context.t('Emergency help', 'Msaada wa dharura'),
                icon: Icons.emergency,
                onPressed: () => then(() => context.push(Routes.emergency)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Tomorrow, 10:00" / "Tue 12 Nov, 10:00"
String fmtWhen(BuildContext c, DateTime t) {
  final d = DateTime(t.year, t.month, t.day), now = DateTime.now(), today = DateTime(now.year, now.month, now.day);
  if (d == today) return c.t('Today, ${fmtTime(t)}', 'Leo, ${fmtTime(t)}');
  if (d == today.add(const Duration(days: 1))) return c.t('Tomorrow, ${fmtTime(t)}', 'Kesho, ${fmtTime(t)}');
  return whenLabel(t, c.appRead.lang);
}
