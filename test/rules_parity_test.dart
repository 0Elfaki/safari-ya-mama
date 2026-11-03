// The phone's rules (lib/core/rules.dart) must give the same level as the
// reference rules and the database's rate_checkin() for every case in
// shared/rules_cases.json (423 cases; the same file drives tools/parity_sql.mjs).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:safari_ya_mama/core/content.dart';
import 'package:safari_ya_mama/core/rules.dart';

void main() {
  // In the monorepo the generated file lives in ../shared; the standalone app repo carries a copy in test/fixtures.
  final shared = File('../shared/rules_cases.json');
  final cases = shared.existsSync() ? shared : File('test/fixtures/rules_cases.json');
  final data = jsonDecode(cases.readAsStringSync()) as Map<String, dynamic>;

  test('rules version matches the shared cases', () {
    expect(rulesVersion, data['rules_version']);
  });

  test('sign keys and single-sign levels match the content pack', () {
    final signs = data['signs'] as Map<String, dynamic>;
    String lv(Sign s) => s.ageDependent ? 'age' : s.level.db;
    expect([for (final s in pregnancySigns) '${s.key}:${lv(s)}'], [for (final s in signs['pregnant']) '${s['key']}:${s['level']}']);
    expect([for (final s in postnatalSigns) '${s.key}:${lv(s)}'], [for (final s in signs['postnatal']) '${s['key']}:${s['level']}']);
    expect([for (final s in babySigns) '${s.key}:${lv(s)}'], [for (final s in signs['baby']) '${s['key']}:${s['level']}']);
  });

  test('every shared case gives the expected level', () {
    final cases = (data['cases'] as List).cast<Map<String, dynamic>>();
    expect(cases.length, greaterThanOrEqualTo(400));
    var bad = 0;
    for (final c in cases) {
      final t = triage(
        CheckinInput(
          stage: c['stage'] as String,
          feeling: c['feeling'] as String,
          signs: {...(c['signs'] as List).cast<String>()},
          movement: c['movement'] as String?,
          babySigns: {...(c['baby_signs'] as List).cast<String>()},
          babyFeeding: c['baby_feeding'] as String?,
          systolic: c['systolic'] as int?,
          diastolic: c['diastolic'] as int?,
          weeks: c['weeks'] as int,
          babyDays: c['baby_days'] as int,
        ),
      );
      if (t.level.db != c['expected']) {
        bad++;
        if (bad < 5) printOnFailure('MISMATCH $c → ${t.level.db}');
      }
    }
    expect(bad, 0, reason: '$bad of ${cases.length} cases disagree');
  });
}
