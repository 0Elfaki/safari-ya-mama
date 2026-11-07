// Phone reminders: notifications scheduled on the phone itself, so they work with no signal,
// no server and no SMS cost. Nothing about her health leaves the phone.
// Shared phones: unless she turns on "Show details", every notification says only
// "Safari ya Mama: you have a reminder", so nobody learns she is pregnant from the lock screen.
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/dates.dart';
import '../state/app_state.dart';

/// One reminder the phone will show. [hour]/[minute] repeat daily when [on] is null.
class PlannedReminder {
  final int id;
  final String en, sw;
  final DateTime? on;
  final int hour, minute;
  const PlannedReminder(this.id, this.en, this.sw, {this.on, required this.hour, required this.minute});
  bool get daily => on == null;
}

/// What to schedule for her right now. Pure: tested without a phone.
List<PlannedReminder> plannedReminders(AppState s) {
  if (!s.phoneReminders || !s.onboarded) return const [];
  (int, int) hm(String v) {
    final p = v.split(':');
    return (int.tryParse(p.first) ?? 9, int.tryParse(p.length > 1 ? p[1] : '0') ?? 0);
  }

  final out = <PlannedReminder>[];
  final (ch, cm) = hm(s.reminderTime('check'));
  out.add(PlannedReminder(1, "Time for today's 1-minute check", 'Ni wakati wa ukaguzi wa leo wa dakika 1', hour: ch, minute: cm));
  if (s.pregnant || s.medications.isNotEmpty) {
    final (th, tm) = hm(s.reminderTime('tablet'));
    out.add(
      PlannedReminder(
        2,
        s.pregnant ? 'Take your iron + folic acid tablet' : 'Take your medicine',
        s.pregnant ? 'Meza kidonge cha madini chuma na folic' : 'Meza dawa yako',
        hour: th,
        minute: tm,
      ),
    );
  }
  if (s.pregnant && s.weeks >= 20) {
    final (mh, mm) = hm(s.reminderTime('movements'));
    out.add(PlannedReminder(3, "Notice your baby's movements", 'Angalia mtoto anavyocheza', hour: mh, minute: mm));
  }
  // the evening before each upcoming visit and vaccine
  final today = sod(s.now());
  var id = 100;
  for (final v in s.allVisits.where((v) => v.attended == null && v.due.isAfter(today)).take(4)) {
    out.add(PlannedReminder(id++, 'Clinic visit tomorrow: ${v.title.en}', 'Kliniki kesho: ${v.title.sw}', on: addDays(v.due, -1), hour: 18, minute: 0));
  }
  final nv = s.nextVaccine;
  if (nv != null && nv.due.isAfter(today)) {
    out.add(PlannedReminder(200, 'Vaccine tomorrow: ${nv.dose.label}', 'Chanjo kesho: ${nv.dose.label}', on: addDays(nv.due, -1), hour: 18, minute: 0));
  }
  // booked appointments: the evening before, and 30 minutes before a video call
  var bid = 300;
  for (final b in s.bookings.upcoming.take(3)) {
    final day = sod(b.startsAt), at = fmtTime(b.startsAt);
    if (day.isAfter(today)) {
      out.add(
        b.video
            ? PlannedReminder(bid++, 'Video call tomorrow at $at', 'Simu ya video kesho saa $at', on: addDays(day, -1), hour: 18, minute: 0)
            : PlannedReminder(bid++, 'Clinic appointment tomorrow at $at', 'Miadi ya kliniki kesho saa $at', on: addDays(day, -1), hour: 18, minute: 0),
      );
    }
    final soon = b.startsAt.subtract(const Duration(minutes: 30));
    if (b.video && soon.isAfter(s.now())) {
      out.add(PlannedReminder(bid++, 'Video call in 30 minutes. Find a quiet place.', 'Simu ya video baada ya dakika 30. Tafuta mahali tulivu.', on: sod(soon), hour: soon.hour, minute: soon.minute));
    }
  }
  return out;
}

class Reminders {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Reminders',
      channelDescription: 'Daily check, tablets, visits and vaccines',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    ),
    iOS: DarwinNotificationDetails(),
  );

  static Future<bool> _init() async {
    if (_ready) return true;
    if (kIsWeb) return false;
    try {
      tzdata.initializeTimeZones();
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
        ),
      );
      _ready = true;
    } catch (_) {
      // tests, desktop, or a phone without the plugin: the in-app list still works
      return false;
    }
    return true;
  }

  /// Asks the phone for permission to show notifications. false when she says no.
  static Future<bool> requestPermission() async {
    if (!await _init()) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) return await android.requestNotificationsPermission() ?? false;
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) return await ios.requestPermissions(alert: true, sound: true) ?? false;
    } catch (_) {}
    return false;
  }

  /// Replaces every scheduled reminder with what [plannedReminders] says now.
  /// Called on start, on return to the app, and when she changes a reminder setting.
  static Future<void> sync(AppState s) async {
    if (!await _init()) return;
    try {
      await _plugin.cancelAll();
      final now = tz.TZDateTime.now(tz.local);
      for (final r in plannedReminders(s)) {
        var at = r.daily
            ? tz.TZDateTime(tz.local, now.year, now.month, now.day, r.hour, r.minute)
            : tz.TZDateTime(tz.local, r.on!.year, r.on!.month, r.on!.day, r.hour, r.minute);
        if (r.daily && !at.isAfter(now)) at = at.add(const Duration(days: 1));
        if (!at.isAfter(now)) continue;
        final words = s.lang == 'sw' ? r.sw : r.en;
        await _plugin.zonedSchedule(
          id: r.id,
          scheduledDate: at,
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: 'Safari ya Mama',
          body: s.reminderDetails ? words : (s.lang == 'sw' ? 'Una kikumbusho' : 'You have a reminder'),
          matchDateTimeComponents: r.daily ? DateTimeComponents.time : null,
        );
      }
    } catch (_) {
      // never let a reminder problem break the app
    }
  }
}
