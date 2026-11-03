import 'package:flutter_test/flutter_test.dart';
import 'package:safari_ya_mama/core/content.dart';
import 'package:safari_ya_mama/core/rules.dart';
import 'package:safari_ya_mama/ui/widgets.dart';

void main() {
  group('clinical guardrails', () {
    test('combinations: headache + blurred vision is red, each alone is amber', () {
      expect(triage(const CheckinInput(stage: 'pregnant', signs: {'headache'})).level, Level.amber);
      expect(triage(const CheckinInput(stage: 'pregnant', signs: {'vision'})).level, Level.amber);
      expect(triage(const CheckinInput(stage: 'pregnant', signs: {'headache', 'vision'})).level, Level.red);
    });

    test('baby not moving counts only from 20 weeks', () {
      expect(triage(const CheckinInput(stage: 'pregnant', movement: 'none', weeks: 16)).level, Level.green);
      expect(triage(const CheckinInput(stage: 'pregnant', movement: 'none', weeks: 28)).level, Level.red);
      expect(triage(const CheckinInput(stage: 'pregnant', movement: 'fewer', weeks: 28)).level, Level.amber);
    });

    test('IMCI: baby fever is red under 60 days, amber after', () {
      expect(triage(const CheckinInput(stage: 'postnatal', babySigns: {'b_fever'}, babyDays: 59)).level, Level.red);
      expect(triage(const CheckinInput(stage: 'postnatal', babySigns: {'b_fever'}, babyDays: 60)).level, Level.amber);
    });

    test('safeguarding: thoughts of self-harm are red', () {
      expect(triage(const CheckinInput(stage: 'postnatal', signs: {'pp_harm'})).level, Level.red);
    });

    test('blood pressure thresholds', () {
      expect(rateBp(160, 80), Level.red);
      expect(rateBp(150, 95), Level.amber);
      expect(rateBp(150, 95, withSymptoms: true), Level.red);
      expect(rateBp(135, 88), Level.green);
      expect(triage(const CheckinInput(stage: 'pregnant', signs: {'swelling'}, systolic: 142, diastolic: 92)).level, Level.red);
    });

    test('feeling unwell alone is amber, never green', () {
      expect(triage(const CheckinInput(stage: 'pregnant', feeling: 'unwell')).level, Level.amber);
    });

    test('green results never say "you are fine"', () {
      for (final lang in ['en', 'sw']) {
        final text = '${LevelBanner.title(Level.green).of(lang)} ${LevelBanner.sub(Level.green).of(lang)}'.toLowerCase();
        expect(text.contains('fine'), isFalse);
        expect(text.contains('salama'), isFalse);
        expect(text, contains(lang == 'en' ? 'cannot rule out' : 'hauwezi kuondoa'));
      }
    });
  });

  group('3-week BP rise (rules 2026.11, mirror of SQL bp_rise_3wk)', () {
    final now = DateTime(2026, 11, 20, 9);
    List<(DateTime, int)> weekly(List<int> sys) => [for (var i = 0; i < sys.length; i++) (now.subtract(Duration(days: 7 * (sys.length - i))), sys[i])];

    test('the Amina case: 118 → 142 over 4 weeks is amber, rise reported', () {
      final h = weekly([115, 118, 122, 128, 134]);
      expect(bpRise3wk(now, 142, h), 142 - 118);
      final t = rateBpReading(142, 92, const [], now, h);
      expect(t.level, Level.amber);
      expect(t.reasons.any((r) => r.en.contains('up 24')), isTrue);
    });

    test('139/88 after a rise of 21 is amber even below 140/90', () {
      final h = weekly([115, 118, 122, 128, 134]);
      expect(rateBpReading(139, 88, const [], now, h).level, Level.amber);
    });

    test('a rise under 20 stays green; no history means no trend', () {
      expect(rateBpReading(134, 88, const [], now, weekly([118, 120, 122])).level, Level.green);
      expect(rateBpReading(138, 80, const [], now, const []).level, Level.green);
    });

    test('readings in the last 13 days or older than 28 days are ignored', () {
      final h = [(now.subtract(const Duration(days: 10)), 100), (now.subtract(const Duration(days: 35)), 100)];
      expect(bpRise3wk(now, 135, h), isNull);
    });
  });
}
