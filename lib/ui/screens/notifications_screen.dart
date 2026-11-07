import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../data/reminders.dart';
import '../theme.dart';
import '../widgets.dart';

/// Notifications: today's reminders, what is coming up, anything the clinic raised,
/// and the phone-reminder settings (on/off, times, what the lock screen shows).
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final tt = Theme.of(context).textTheme;
    final raised = s.serverRaised;
    final nv = s.nextVisit;
    final vac = s.nextVaccine;

    Future<void> togglePhone(bool on) async {
      if (on) {
        final ok = await Reminders.requestPermission();
        if (!ok) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  context.t(
                    'The phone did not allow notifications. You can allow them in the phone settings for Safari ya Mama.',
                    'Simu haikuruhusu arifa. Unaweza kuziruhusu kwenye mipangilio ya simu kwa Safari ya Mama.',
                  ),
                ),
              ),
            );
          }
          return;
        }
      }
      await s.setFlag('phone_reminders', on);
      await Reminders.sync(s);
    }

    Future<void> pickTime(String kind) async {
      final p = s.reminderTime(kind).split(':');
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1])),
        helpText: context.t('Reminder time', 'Muda wa kikumbusho'),
      );
      if (t == null) return;
      await s.setReminderTime(kind, '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
      await Reminders.sync(s);
    }

    Widget timeRow(String kind, IconData icon, String label) => ListTile(
      key: Key('rt-$kind'),
      contentPadding: EdgeInsets.zero,
      enabled: s.phoneReminders,
      leading: Icon(icon),
      title: Text(label, style: tt.titleMedium),
      trailing: Text(s.reminderTime(kind), style: tt.titleMedium!.copyWith(color: s.phoneReminders ? C.primary : C.disabled)),
      onTap: () => pickTime(kind),
    );

    return AppScaffold(
      title: context.t('Notifications', 'Arifa'),
      children: [
        if (raised != null) ...[
          HealthCard(
            tone: levelColor(s.levelOf(raised)),
            background: levelSoft(s.levelOf(raised)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusBadge(context.t('From your clinic', 'Kutoka kliniki yako'), color: levelColor(s.levelOf(raised)), icon: Icons.local_hospital_outlined),
                const Gap(Sp.sm),
                Text(context.tx(LevelBanner.title(s.levelOf(raised))), style: tt.titleMedium),
              ],
            ),
          ),
          const Gap(Sp.sm),
        ],
        SectionTitle(context.t('Today', 'Leo')),
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
                        title: Text(context.tx(r.text), style: tt.titleMedium!.copyWith(decoration: s.reminderDone(r.id) ? TextDecoration.lineThrough : null)),
                        subtitle: r.when.isEmpty ? null : Text(r.when),
                      ),
                  ],
                ),
        ),
        SectionTitle(context.t('Coming up', 'Yanayokuja')),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.xs),
          child: nv == null && vac == null
              ? EmptyState(Icons.event_available_outlined, context.t('No visits or vaccines planned yet.', 'Bado hakuna kliniki wala chanjo iliyopangwa.'))
              : Column(
                  children: [
                    if (nv != null) Row2(icon: Icons.event, title: context.tx(nv.title), sub: fmtDayYear(nv.due, s.lang)),
                    if (vac != null)
                      Row2(
                        icon: Icons.vaccines_outlined,
                        title: context.t('Vaccine: ${vac.dose.label}', 'Chanjo: ${vac.dose.label}'),
                        sub: fmtDayYear(vac.due, s.lang),
                      ),
                  ],
                ),
        ),
        SectionTitle(context.t('Phone reminders', 'Vikumbusho kwenye simu')),
        AppCard(
          padding: const EdgeInsets.fromLTRB(Sp.md, Sp.xs, Sp.md, Sp.xs),
          child: Column(
            children: [
              SwitchListTile(
                key: const Key('phone-reminders'),
                contentPadding: EdgeInsets.zero,
                value: s.phoneReminders,
                onChanged: togglePhone,
                title: Text(context.t('Remind me on this phone', 'Nikumbushe kwenye simu hii'), style: tt.titleMedium),
                subtitle: Text(context.t('Works without internet or SMS.', 'Inafanya kazi bila intaneti wala SMS.')),
              ),
              const Divider(),
              timeRow('check', Icons.fact_check_outlined, context.t('Daily check', 'Ukaguzi wa kila siku')),
              if (s.pregnant || s.medications.isNotEmpty)
                timeRow(
                  'tablet',
                  Icons.medication_outlined,
                  s.pregnant ? context.t('Iron + folic acid', 'Madini chuma na folic') : context.t('Medicine', 'Dawa'),
                ),
              if (s.pregnant && s.weeks >= 20) timeRow('movements', Icons.favorite_border, context.t("Baby's movements", 'Mtoto kucheza')),
              ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: s.phoneReminders,
                leading: const Icon(Icons.event_note_outlined),
                title: Text(context.t('Visits and vaccines', 'Kliniki na chanjo'), style: tt.titleMedium),
                trailing: Text(context.t('Evening before, 18:00', 'Jioni kabla, 18:00'), style: tt.bodySmall),
              ),
              const Divider(),
              SwitchListTile(
                key: const Key('reminder-details'),
                contentPadding: EdgeInsets.zero,
                value: s.reminderDetails,
                onChanged: !s.phoneReminders
                    ? null
                    : (v) async {
                        await s.setFlag('reminder_details', v);
                        await Reminders.sync(s);
                      },
                title: Text(context.t('Show what the reminder is about', 'Onyesha kikumbusho kinahusu nini'), style: tt.titleMedium),
                subtitle: Text(
                  context.t(
                    'Off: the lock screen only says "You have a reminder", so others using this phone see nothing private.',
                    'Ikizimwa: skrini inasema tu "Una kikumbusho", ili wengine wanaotumia simu hii wasione jambo la siri.',
                  ),
                ),
              ),
            ],
          ),
        ),
        const Gap(Sp.md),
        const OfflineIndicator(),
      ],
    );
  }
}
