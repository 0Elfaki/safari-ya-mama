import 'package:flutter/material.dart';

import '../../../core/dates.dart';
import '../../../ui/widgets.dart';

const _daysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _daysSw = ['Jumatatu', 'Jumanne', 'Jumatano', 'Alhamisi', 'Ijumaa', 'Jumamosi', 'Jumapili'];

/// "Tue 12 Nov, 10:30" / "Jumanne 12 Nov, 10:30"
String whenLabel(DateTime t, String lang) => '${(lang == 'sw' ? _daysSw : _daysEn)[t.weekday - 1]} ${fmtDay(t, lang)}, ${fmtTime(t)}';

/// "Today", "Tomorrow", or "Tue 12 Nov".
String dayLabel(BuildContext c, DateTime d) {
  final t = sod(DateTime.now());
  if (sod(d) == t) return c.t('Today', 'Leo');
  if (sod(d) == addDays(t, 1)) return c.t('Tomorrow', 'Kesho');
  return '${(c.appRead.lang == 'sw' ? _daysSw : _daysEn)[d.weekday - 1]} ${fmtDay(d, c.appRead.lang)}';
}
