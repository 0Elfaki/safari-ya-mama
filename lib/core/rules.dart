// ================= Safari ya Mama · Layer 1 warning rules =================
// Fixed, explainable rules based on WHO danger signs (pregnancy), WHO PCPNC
// (mother after birth) and IMCI (young infant). They never diagnose and never
// say "you are fine". The database runs the same rules in rate_checkin(),
// rate_bp() and bp_rise_3wk(); test/rules_parity_test.dart checks this file
// against shared/rules_cases.json, which is generated from the same cases the
// SQL parity test uses.
//
// Only this file (on the phone) and the SQL functions may set a warning level.
// AI features may explain a result but can never raise or lower it.
import 'body_check.dart';
import 'content.dart';
import 'tx.dart';

const rulesVersion = '2026.12';

class CheckinInput {
  /// 'pregnant' or 'postnatal'
  final String stage;

  /// 'well' | 'ok' | 'unwell'
  final String feeling;
  final Set<String> signs;

  /// pregnant from 20 weeks: 'normal' | 'fewer' | 'none'
  final String? movement;
  final Set<String> babySigns;

  /// 'normal' | 'less' | 'not'
  final String? babyFeeding;
  final int? systolic, diastolic;
  final int weeks;
  final int babyDays;
  final String? babyName;

  const CheckinInput({
    required this.stage,
    this.feeling = 'well',
    this.signs = const {},
    this.movement,
    this.babySigns = const {},
    this.babyFeeding,
    this.systolic,
    this.diastolic,
    this.weeks = 0,
    this.babyDays = 0,
    this.babyName,
  });
}

class Triage {
  final Level level;

  /// Reasons for the level shown (red reasons if red, else amber reasons).
  final List<Tx> reasons;
  final String version;
  const Triage(this.level, this.reasons, [this.version = rulesVersion]);
}

/// Blood pressure band: red ≥160/110, amber ≥140/90, 'elev' ≥130/85 (watch), else green.
enum BpBand { green, elev, amber, red }

BpBand? bpBand(int? s, int? d) {
  if (s == null || d == null || s == 0 || d == 0) return null;
  if (s >= 160 || d >= 110) return BpBand.red;
  if (s >= 140 || d >= 90) return BpBand.amber;
  if (s >= 130 || d >= 85) return BpBand.elev;
  return BpBand.green;
}

/// Mirror of SQL rate_bp(): red at 160/110, or 140/90 with any warning symptom;
/// amber at 140/90 alone.
Level rateBp(int s, int d, {bool withSymptoms = false}) {
  final b = bpBand(s, d);
  if (b == BpBand.red) return Level.red;
  if (b == BpBand.amber) return withSymptoms ? Level.red : Level.amber;
  return Level.green;
}

/// Mirror of SQL bp_rise_3wk(): this systolic minus the lowest systolic logged
/// 14–28 calendar days earlier. Null when there is no earlier reading.
int? bpRise3wk(DateTime at, int systolic, Iterable<(DateTime, int)> history) {
  final day = DateTime(at.year, at.month, at.day);
  int? low;
  for (final (t, s) in history) {
    final d = day.difference(DateTime(t.year, t.month, t.day)).inDays;
    if (d >= 14 && d <= 28) low = low == null ? s : (s < low ? s : low);
  }
  return low == null ? null : systolic - low;
}

/// Weekly BP log result (bp_readings): rate_bp, raised to amber when the
/// systolic rose 20 mmHg or more over about 3 weeks (rules 2026.11).
Triage rateBpReading(int s, int d, List<String> symptoms, DateTime at, Iterable<(DateTime, int)> history) {
  var lvl = rateBp(s, d, withSymptoms: symptoms.isNotEmpty);
  final reasons = <Tx>[];
  if (lvl != Level.green) {
    reasons.add(Tx('Blood pressure $s/$d', 'Shinikizo la damu $s/$d'));
  }
  final rise = bpRise3wk(at, s, history);
  if (rise != null && rise >= 20) {
    if (lvl == Level.green) lvl = Level.amber;
    reasons.add(Tx('Top number up $rise in about 3 weeks', 'Namba ya juu imepanda $rise ndani ya wiki 3 hivi'));
  }
  return Triage(lvl, reasons);
}

/// Mirror of rate_checkin(). Same structure as triageRules() in the dashboard.
Triage triage(CheckinInput c) {
  final preg = c.stage == 'pregnant';
  final red = <Tx>[], amber = <Tx>[];
  void push(Level l, Tx r) => (l == Level.red ? red : amber).add(r);
  const you = Tx('You: ', 'Wewe: ');
  final bb = Tx('${c.babyName ?? 'Baby'}: ', '${c.babyName ?? 'Mtoto'}: ');

  if (preg) {
    bool has(String k) => c.signs.contains(k);
    final combo = <String>{};
    if (has('headache') && has('vision')) {
      push(Level.red, const Tx('Severe headache with blurred vision', 'Kichwa kuuma sana na kuona ukungu'));
      combo.addAll(['headache', 'vision']);
    }
    if (has('swelling') && (has('headache') || has('vision'))) {
      push(Level.red, const Tx('Swelling with headache or vision changes', 'Kuvimba pamoja na kichwa au macho'));
      combo.addAll(['swelling', 'headache', 'vision']);
    }
    if (has('fever') && c.feeling == 'unwell') {
      push(Level.red, const Tx('Fever and feeling very unwell', 'Homa na kujisikia vibaya sana'));
      combo.add('fever');
    }
    for (final k in c.signs) {
      if (combo.contains(k)) continue;
      final s = _find(pregnancySigns, k);
      if (s != null) push(s.level, s.label);
    }
    if (c.weeks >= 20 && c.movement == 'none') push(Level.red, const Tx('Baby not moving', 'Mtoto hachezi'));
    if (c.weeks >= 20 && c.movement == 'fewer') {
      push(Level.amber, const Tx('Baby moving less than usual', 'Mtoto anacheza kidogo kuliko kawaida'));
    }
  } else {
    for (final k in c.signs) {
      final s = _find(postnatalSigns, k);
      if (s == null) continue;
      push(k == 'pp_fever' && c.feeling == 'unwell' ? Level.red : s.level, you + s.label);
    }
    var greens = 0;
    for (final k in c.babySigns) {
      final s = _find(babySigns, k);
      if (s == null) continue;
      if (s.level == Level.green && !s.ageDependent) {
        greens++;
        continue;
      }
      final lvl = s.ageDependent ? (c.babyDays < 60 ? Level.red : Level.amber) : s.level;
      push(lvl, bb + s.label);
    }
    // rules 2026.12: several everyday signs together need a health worker's look
    if (greens >= greenStepUp) {
      push(Level.amber, bb + Tx('Several everyday signs together ($greens)', 'Dalili kadhaa za kawaida kwa pamoja ($greens)'));
    }
    if (c.babyFeeding == 'not') push(Level.red, bb + const Tx('Not feeding', 'Hanyonyi'));
    if (c.babyFeeding == 'less') push(Level.amber, bb + const Tx('Feeding less than usual', 'Ananyonya kidogo kuliko kawaida'));
  }

  final s = c.systolic, d = c.diastolic, band = bpBand(s, d);
  final warn = preg ? ['headache', 'vision', 'bellypain', 'swelling'].any(c.signs.contains) : c.signs.contains('pp_head');
  if (band == BpBand.red || (band == BpBand.amber && warn)) {
    push(Level.red, Tx('Blood pressure $s/$d', 'Shinikizo la damu $s/$d'));
  } else if (band == BpBand.amber) {
    push(Level.amber, Tx('Blood pressure $s/$d (at or above 140/90)', 'Shinikizo la damu $s/$d (140/90 au zaidi)'));
  }
  if (c.feeling == 'unwell' && red.isEmpty && amber.isEmpty) {
    push(Level.amber, preg ? const Tx('Feeling unwell', 'Kujisikia vibaya') : you + const Tx('Feeling unwell', 'Kujisikia vibaya'));
  }
  if (red.isNotEmpty) return Triage(Level.red, red);
  if (amber.isNotEmpty) return Triage(Level.amber, amber);
  return const Triage(Level.green, []);
}

Sign? _find(List<Sign> list, String k) {
  for (final s in list) {
    if (s.key == k) return s;
  }
  return null;
}

/// Body self-check (MA-43), phone only. "Yes" answers that map to daily-check signs go through
/// triage() so combinations count exactly as in the check; questions without a sign carry their
/// own level (resources/HEALTH_EDUCATION_CURRICULUM.md). The result is the higher of the two,
/// with every reason at that level. Not sent to the clinic; it suggests a check-in instead.
Triage rateSelfCheck(String map, Iterable<BodyQ> yes, {int weeks = 0, int babyDays = 0, String? babyName}) {
  final signs = <String>{}, babySigns = <String>{};
  var feeling = 'well', movement = 'normal';
  final own = <Level, List<Tx>>{Level.red: [], Level.amber: []};
  for (final q in yes) {
    switch (q.sign) {
      case '_unwell':
        feeling = 'unwell';
      case '_unwell_fever':
        feeling = 'unwell';
        signs.add('pp_fever');
      case '_move_none':
        movement = 'none';
      case '_move_fewer':
        movement = 'fewer';
      case final String k when k.startsWith('b_'):
        babySigns.add(k);
      case final String k:
        signs.add(k);
      case null:
        if (q.level != null && q.level != Level.green) own[q.level!]!.add(q.text);
    }
  }
  final t = triage(
    CheckinInput(
      stage: map == 'pregnant' ? 'pregnant' : 'postnatal',
      feeling: feeling,
      signs: signs,
      movement: movement,
      babySigns: babySigns,
      weeks: weeks,
      babyDays: babyDays,
      babyName: babyName,
    ),
  );
  var level = t.level;
  if (own[Level.red]!.isNotEmpty) level = Level.red;
  if (level == Level.green && own[Level.amber]!.isNotEmpty) level = Level.amber;
  if (level == Level.green) return const Triage(Level.green, []);
  return Triage(level, [if (t.level == level) ...t.reasons, ...own[level]!]);
}
