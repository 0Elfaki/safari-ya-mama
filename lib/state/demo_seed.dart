// Synthetic demo records (made-up people) for the offline demo, usability sessions and
// screenshots. Opened with ?demo=pregnant or ?demo=baby on the web build, or from
// "Try the demo" during development. Never used when a backend is configured.
import '../core/dates.dart';
import '../core/rules.dart';
import 'app_state.dart';

extension DemoSeed on AppState {
  Future<void> seedDemo(String which) async {
    await store.wipe();
    final now = this.now();
    String ago(int days, [int h = 9]) => DateTime(now.year, now.month, now.day - days, h).toUtc().toIso8601String();
    await store.setMeta('lang', 'en');
    await setFacility({'id': null, 'name': 'Sample Health Centre 1', 'phone': '+255 700 000 001'});
    if (which == 'caregiver') {
      // A partner who follows Bahati and baby Zuri (simulated summary, same shape as caregiver_summary()).
      String day(int d) => isoDay(addDays(sod(now), -d));
      await store.setMeta('caregiver', true);
      await store.setMeta('cg_updated', now.toUtc().toIso8601String());
      await store.setMeta('cg_summary', [
        {
          'mother_id': 'demo-bahati',
          'name': 'Bahati',
          'relation': 'partner',
          'pregnant_weeks': null,
          'babies': [
            {'name': 'Zuri', 'days': 92},
          ],
          'today': {
            'level': 'amber',
            'signs': ['b_g_cold', 'b_g_rash', 'b_g_fussy', 'b_g_stool'],
          },
          'last7': [
            for (final (d, l) in [(6, 'green'), (5, 'green'), (4, 'green'), (2, 'green'), (1, 'green'), (0, 'amber')]) {'day': day(d), 'level': l},
          ],
          'next_visit': {'kind': 'child', 'contact': 6, 'due': day(-6)},
          'next_vaccine': {'key': 'opv3', 'due': day(-6)},
          'open_alert': {'level': 'amber', 'at': now.toUtc().toIso8601String()},
        },
      ]);
      await store.setMeta('demo', which);
      await setName('Juma');
      return;
    }
    if (which == 'twins') {
      await completeOnboarding(
        name: 'Rehema',
        stage: 'postnatal',
        dob: addDays(sod(now), -21),
        babyNames: ['Hope', 'Faith'],
        consents: {'share_with_facility': true},
      );
      final [h, f] = babies;
      await updateBaby(h['id'] as String, {'sex': 'f', 'birth_weight_g': 2400});
      await updateBaby(f['id'] as String, {'sex': 'f', 'birth_weight_g': 2150});
      for (final (b, g) in [(h, 2400), (f, 2150)]) {
        await addGrowth(weightG: g, on: addDays(sod(now), -21), source: 'clinic', babyId: b['id'] as String);
        await addGrowth(weightG: g + 450, on: addDays(sod(now), -3), source: 'clinic', babyId: b['id'] as String);
        for (final k in ['bcg', 'opv0']) {
          await setVaccineGiven(k, true, babyId: b['id'] as String);
        }
      }
      await toggleMilestone('m1b', babyId: h['id'] as String);
      for (final (d, hs, fs) in [
        (5, <String>[], <String>['b_g_spit']),
        (3, <String>['b_g_rash'], <String>[]),
        (2, <String>[], <String>[]),
        (1, <String>[], <String>['b_yellow']),
      ]) {
        for (final (b, signs) in [(h, hs), (f, fs)]) {
          await store.save('checkins', {
            'id': newId(),
            'stage': 'postnatal',
            'baby_id': b['id'],
            'feeling': 'well',
            'signs': <String>[],
            'baby_signs': signs,
            'baby_feeding': 'normal',
            'level': signs.contains('b_yellow') ? 'amber' : 'green',
            'rules_version': rulesVersion,
            'client_created_at': ago(d),
          });
        }
      }
    } else if (which == 'baby') {
      await completeOnboarding(
        name: 'Bahati',
        stage: 'postnatal',
        dob: addDays(sod(now), -96),
        babyName: 'Zuri',
        consents: {'share_with_facility': true, 'reminders_sms': true},
      );
      final b = baby!['id'];
      for (final (d, g) in [(96, 3100), (93, 3050), (86, 3200), (54, 4500), (26, 5400)]) {
        await store.save('growth_measures', {
          'id': newId(),
          'baby_id': b,
          'weight_g': g,
          'source': 'clinic',
          'measured_on': isoDay(addDays(sod(now), -d)),
          'client_created_at': ago(d),
        });
      }
      for (final k in ['bcg', 'opv0', 'opv1', 'penta1', 'pcv1', 'rota1', 'opv2', 'penta2', 'pcv2', 'rota2']) {
        await setVaccineGiven(k, true);
      }
      for (final k in ['m1a', 'm1b', 'm1c', 'm2a', 'm2b', 'm2c']) {
        await toggleMilestone(k);
      }
      for (var i = 0; i < 5; i++) {
        await addFeed('breast');
      }
      // two weeks of colour-coded child checks: mostly green, one day with 4 everyday signs (amber)
      for (final (d, signs, lvl) in [
        (13, <String>[], 'green'),
        (12, <String>['b_g_rash'], 'green'),
        (10, <String>[], 'green'),
        (9, <String>['b_g_cold', 'b_g_spit', 'b_g_fussy', 'b_g_stool'], 'amber'),
        (8, <String>['b_g_cold'], 'green'),
        (6, <String>[], 'green'),
        (4, <String>[], 'green'),
        (3, <String>['b_g_spit'], 'green'),
        (1, <String>[], 'green'),
      ]) {
        await store.save('checkins', {
          'id': newId(),
          'stage': 'postnatal',
          'baby_id': b,
          'feeling': 'well',
          'signs': <String>[],
          'baby_signs': signs,
          'baby_feeding': 'normal',
          'level': lvl,
          'rules_version': rulesVersion,
          'note': d == 9 ? 'Zuri was coughing at night and cried a lot.' : null,
          'client_created_at': ago(d),
        });
      }
      await addQuestion('When should Zuri start porridge?');
    } else {
      await completeOnboarding(name: 'Amina', stage: 'pregnant', lmp: addDays(sod(now), -198), consents: {'share_with_facility': true});
      await updatePregnancy({'gravida': 2, 'parity': 1, 'mother_age': 27});
      for (final (d, s, di) in [(35, 115, 74), (28, 118, 76), (21, 122, 80), (14, 128, 84), (7, 134, 88)]) {
        await store.save('bp_readings', {
          'id': newId(),
          'pregnancy_id': pregnancy!['id'],
          'systolic': s,
          'diastolic': di,
          'symptoms': <String>[],
          'level': 'green',
          'taken_by': 'chw',
          'client_created_at': ago(d, 10),
        });
      }
      for (final d in [6, 5, 3, 2, 1]) {
        await store.save('checkins', {
          'id': newId(),
          'stage': 'pregnant',
          'pregnancy_id': pregnancy!['id'],
          'feeling': 'well',
          'signs': <String>[],
          'movement': 'normal',
          'baby_signs': <String>[],
          'level': 'green',
          'rules_version': rulesVersion,
          'client_created_at': ago(d, 19),
        });
      }
      await saveBirthPlan({
        'items_ready': ['facility', 'card'],
        'transport': 'Bajaji with neighbour Juma',
      });
      await addQuestion('Is it safe to keep working at the market?');
      await addQuestion('Where do I go if labour starts at night?');
      await markLesson('danger-preg', completed: true);
      await markLesson('eat-well', completed: true);
    }
    await store.setMeta('demo', which);
  }
}
