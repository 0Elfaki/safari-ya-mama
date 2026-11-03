import 'package:intl/intl.dart';

/// Start of day in local time.
DateTime sod(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime today() => sod(DateTime.now());

/// Whole days from [b] to [a] (calendar days, local).
int daysBetween(DateTime a, DateTime b) => DateTime.utc(a.year, a.month, a.day).difference(DateTime.utc(b.year, b.month, b.day)).inDays;

DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// 'yyyy-MM-dd' as stored in Postgres `date` columns.
String isoDay(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

DateTime parseDay(String s) {
  final p = s.substring(0, 10).split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

/// UTC timestamp as stored in `timestamptz` columns.
String nowIso() => DateTime.now().toUtc().toIso8601String();

DateTime parseTs(String s) => DateTime.parse(s).toLocal();

const _monSw = ['Jan', 'Feb', 'Mac', 'Apr', 'Mei', 'Jun', 'Jul', 'Ago', 'Sep', 'Okt', 'Nov', 'Des'];
const _monEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "14 Nov" / "14 Nov" (sw month abbreviations).
String fmtDay(DateTime d, String lang) => '${d.day} ${(lang == 'sw' ? _monSw : _monEn)[d.month - 1]}';

String fmtDayYear(DateTime d, String lang) => '${fmtDay(d, lang)} ${d.year}';

String fmtTime(DateTime d) => DateFormat('HH:mm').format(d);
