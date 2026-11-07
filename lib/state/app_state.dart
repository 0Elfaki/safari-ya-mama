// The mother's whole record, kept on the phone and synced when online.
// Screens read from here and call its methods; every write goes to the local
// store first (works with no signal), then to the outbox.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/content.dart';
import '../core/dates.dart';
import '../core/lessons.g.dart';
import '../core/note_share.dart';
import '../core/record_proof.dart';
import '../core/rules.dart';
import '../core/tx.dart';
import '../data/local_store.dart';
import '../data/remote.dart';
import '../data/sync_service.dart';
import '../features/telemedicine/data/booking_service.dart';
import '../features/community/data/community_service.dart';

const consentTextVersion = 'consent-2026-11';

/// Consent switches shown at onboarding and in Profile. All off by default.
const consentKinds = ['share_with_facility', 'share_with_chw', 'reminders_sms', 'reminders_whatsapp', 'photo_storage', 'research'];

class Visit {
  final String kind; // anc | pnc | immunisation | other
  final int? contactNo;
  final DateTime due;
  final DateTime? attended;
  final Tx title;
  final String? id, note, source;
  const Visit(this.kind, this.contactNo, this.due, this.title, {this.attended, this.id, this.note, this.source});
}

class VaccineStatus {
  final VaccineDose dose;
  final DateTime due;
  final DateTime? givenOn;
  final String? serverId;
  const VaccineStatus(this.dose, this.due, this.givenOn, this.serverId);
  bool get given => givenOn != null;
}

/// What the mother reported for one baby in the daily check-in.
class BabyAnswers {
  final Set<String> signs;
  final String feeding; // normal | less | not
  /// What the mother wrote about this baby (signs not in the list, a description).
  final String note;
  const BabyAnswers({this.signs = const {}, this.feeding = 'normal', this.note = ''});
}

/// A baby recorded at birth (twins and triplets are recorded together).
class NewBaby {
  final String? name, sex;
  final int? weightG;
  const NewBaby({this.name, this.sex, this.weightG});
}

class Reminder {
  final String id;
  final Tx text;
  final String when;
  final String icon; // pill | baby | calendar | gauge | syringe
  const Reminder(this.id, this.text, this.when, this.icon);
}

class AppState extends ChangeNotifier {
  final LocalStore store;
  final RemoteApi? remote;
  final DateTime Function() now;
  late final SyncService? _sync = remote == null ? null : SyncService(store, remote!);
  final _uuid = const Uuid();

  AppState(this.store, {this.remote, DateTime Function()? clock}) : now = clock ?? DateTime.now;

  /// Mothers' circle and appointments (need the server; kept in their own files).
  late final community = CommunityService(this);
  late final bookings = BookingService(this);

  /// Redraw after a change made by [community] or [bookings].
  void touch() => notifyListeners();

  /// Set by the app: reschedules phone reminders when her appointments change.
  void Function()? onBookingsChanged;

  DateTime get _today => sod(now());
  String _nowIso() => now().toUtc().toIso8601String();
  String newId() => _uuid.v4();

  /// Postgres char_length counts code points; cap there so emoji never break a check constraint.
  static String _cap(String s, int n) => s.runes.length <= n ? s : String.fromCharCodes(s.runes.take(n));

  // ───────────── settings
  String get lang => store.meta<String>('lang', 'sw')!;
  String tr(Tx t) => t.of(lang);
  Future<void> setLang(String l) async {
    await store.setMeta('lang', l);
    if (signedIn) await _saveProfile();
    notifyListeners();
  }

  bool get onboarded => store.meta<bool>('onboarded', false)!;
  String get stage => store.meta<String>('stage', 'pregnant')!;
  bool get pregnant => stage == 'pregnant';
  String get name => store.meta<String>('name', '')!;
  bool get lowData => store.meta<bool>('low_data', false)!;
  bool get readAloud => store.meta<bool>('read_aloud', false)!;
  bool get hasRemote => remote != null;
  bool get signedIn => remote?.userId != null;

  Future<void> setFlag(String k, bool v) async {
    await store.setMeta(k, v);
    if (k == 'low_data' && signedIn) await _saveProfile();
    notifyListeners();
  }

  Future<void> setName(String v) async {
    await store.setMeta('name', v.trim());
    if (signedIn) await _saveProfile();
    notifyListeners();
  }

  // ───────────── shared-phone PIN (4 digits, salted hash, never leaves the phone)
  bool locked = false;
  bool get hasPin => store.meta<String>('pin_hash') != null;
  String _hash(String pin) {
    final salt = store.meta<String>('pin_salt') ?? newId();
    return sha256.convert(utf8.encode('$salt:$pin')).toString();
  }

  Future<void> setPin(String pin) async {
    if (store.meta<String>('pin_salt') == null) await store.setMeta('pin_salt', newId());
    await store.setMeta('pin_hash', _hash(pin));
    notifyListeners();
  }

  Future<void> clearPin() async {
    await store.setMeta('pin_hash', null);
    locked = false;
    notifyListeners();
  }

  bool unlock(String pin) {
    final ok = _hash(pin) == store.meta<String>('pin_hash');
    if (ok) {
      locked = false;
      notifyListeners();
    }
    return ok;
  }

  void lock() {
    if (hasPin) {
      locked = true;
      notifyListeners();
    }
  }

  // ───────────── facility
  /// {id?, name, phone}. `id` is set when chosen from the server list.
  Map<String, dynamic>? get facility => store.meta<Map<String, dynamic>>('facility');
  List<Map<String, dynamic>> get facilityList => (store.meta<List>('facilities', const []) ?? const []).map((e) => asMap(e)).toList();

  Future<void> setFacility(Map<String, dynamic> f) async {
    // moving to another clinic: the old clinic loses access (sharing is per facility)
    final old = facility?['id'];
    if (old != null && old != f['id'] && _sharedWith(old)) {
      await _insertConsent('share_with_facility', false, old);
    }
    await store.setMeta('facility', f);
    if (signedIn) await _saveProfile();
    // sharing was switched on before a clinic with an id was known: record it now
    if (store.meta<bool>('share_pref', false)! && f['id'] != null && !consent('share_with_facility')) {
      await setConsent('share_with_facility', true);
    }
    notifyListeners();
  }

  Future<void> refreshFacilities() async {
    if (remote == null) return;
    try {
      await store.setMeta('facilities', await remote!.facilities());
      notifyListeners();
    } on RemoteError {
      // offline: keep the cached list
    }
  }

  // ───────────── consent (insert-only history; the latest row for a kind counts)
  List<Map<String, dynamic>> get consentHistory => store.all('consents')..sort((a, b) => _consentKey(a).compareTo(_consentKey(b)));

  static String _consentKey(Map<String, dynamic> r) => '${r['_at'] ?? r['created_at']}|${'${r['_seq'] ?? 0}'.padLeft(8, '0')}';

  Future<int> _nextSeq() async {
    final n = store.meta<int>('consent_seq', 0)! + 1;
    await store.setMeta('consent_seq', n);
    return n;
  }

  bool consent(String kind) {
    if (kind == 'share_with_facility' && facility?['id'] == null) return store.meta<bool>('share_pref', false)!;
    final fid = facility?['id'];
    final rows = consentHistory.where((r) => r['kind'] == kind && (kind != 'share_with_facility' || r['facility_id'] == fid));
    return rows.isEmpty ? false : rows.last['granted'] == true;
  }

  Future<void> setConsent(String kind, bool granted) async {
    if (kind == 'share_with_facility') {
      await store.setMeta('share_pref', granted);
      if (facility?['id'] == null) {
        notifyListeners();
        return; // recorded as a row once she picks a clinic from the server list
      }
    }
    await _insertConsent(kind, granted, kind == 'share_with_facility' ? facility!['id'] : null);
    notifyListeners();
  }

  Future<void> _insertConsent(String kind, bool granted, Object? facilityId) async {
    await store.save('consents', {
      'id': newId(),
      'kind': kind,
      'facility_id': facilityId,
      'granted': granted,
      'text_version': consentTextVersion,
      '_at': _nowIso(),
      '_seq': await _nextSeq(),
    });
  }

  bool _sharedWith(Object facilityId) {
    final rows = consentHistory.where((r) => r['kind'] == 'share_with_facility' && r['facility_id'] == facilityId);
    return rows.isNotEmpty && rows.last['granted'] == true;
  }

  /// Sharing is really in effect only when she is signed in and has granted it for a clinic
  /// from the server list. Screens must not say "your clinic will see this" otherwise.
  bool get sharingActive => signedIn && facility?['id'] != null && _sharedWith(facility!['id'] as Object);

  // ───────────── onboarding
  Future<void> completeOnboarding({
    required String name,
    required String stage,
    DateTime? lmp,
    DateTime? dob,
    String? babyName,
    List<String>? babyNames,
    Map<String, bool> consents = const {},
  }) async {
    await store.setMeta('name', name.trim());
    await store.setMeta('stage', stage);
    if (stage == 'pregnant' && lmp != null) await startPregnancy(lmp);
    if (stage == 'postnatal' && dob != null) {
      final names = babyNames ?? [babyName ?? ''];
      for (var i = 0; i < names.length; i++) {
        await addBaby(dob: dob, name: names[i], order: i + 1);
      }
    }
    for (final e in consents.entries) {
      if (e.value) await setConsent(e.key, true);
    }
    await store.setMeta('onboarded', true);
    notifyListeners();
  }

  // ───────────── pregnancy
  Map<String, dynamic>? get pregnancy {
    final l = store.all('pregnancies').where((p) => p['status'] == 'active').toList()
      ..sort((a, b) => (b['updated_at'] as String).compareTo(a['updated_at'] as String));
    return l.isEmpty ? null : l.first;
  }

  DateTime? get lmp => pregnancy == null ? null : parseDay(pregnancy!['lmp'] as String);
  int get pregnancyDays => lmp == null ? 0 : daysBetween(_today, lmp!);
  int get weeks => pregnancyDays ~/ 7;
  DateTime? get edd => lmp == null ? null : addDays(lmp!, 280);
  int get month => (pregnancyDays / 30.44).floor().clamp(0, 8) + 1;

  Future<void> startPregnancy(DateTime lmp) async {
    await store.save('pregnancies', {'id': newId(), 'lmp': isoDay(lmp), 'status': 'active', 'updated_at': _nowIso()});
    notifyListeners();
  }

  Future<void> updatePregnancy(Map<String, dynamic> patch) async {
    final p = pregnancy;
    if (p == null) return;
    await store.save('pregnancies', {...p, ...patch, 'updated_at': _nowIso()});
    notifyListeners();
  }

  // ───────────── babies (one, twins or triplets; screens follow the selected baby)
  /// Every child she follows: youngest birth first; twins in birth order.
  List<Map<String, dynamic>> get babies => store.all('babies')
    ..sort((a, b) {
      final d = (b['dob'] as String).compareTo(a['dob'] as String);
      if (d != 0) return d;
      final o = ((a['_order'] ?? 99) as int).compareTo((b['_order'] ?? 99) as int);
      return o != 0 ? o : '${a['created_at'] ?? a['id']}'.compareTo('${b['created_at'] ?? b['id']}');
    });

  /// Babies born together with the selected baby (same date of birth).
  List<Map<String, dynamic>> get birthGroup => baby == null ? const [] : babies.where((b) => b['dob'] == baby!['dob']).toList();
  bool get multipleBirth => birthGroup.length > 1;

  /// The baby the screens are showing.
  Map<String, dynamic>? get baby {
    final l = babies;
    if (l.isEmpty) return null;
    final sel = store.meta<String>('baby_sel');
    return l.where((b) => b['id'] == sel).firstOrNull ?? l.first;
  }

  Future<void> selectBaby(String id) async {
    await store.setMeta('baby_sel', id);
    notifyListeners();
  }

  Map<String, dynamic>? babyById(String id) => store.get('babies', id);
  String nameOf(Map<String, dynamic>? b, [int? index]) {
    final n = (b?['name'] as String?)?.trim();
    if (n != null && n.isNotEmpty) return n;
    final i = index ?? (b == null ? 0 : birthGroup.indexWhere((x) => x['id'] == b['id']));
    return tr(multipleBirth && i >= 0 ? Tx('Baby ${i + 1}', 'Mtoto ${i + 1}') : const Tx('Baby', 'Mtoto'));
  }

  int ageDays(Map<String, dynamic> b) => daysBetween(_today, parseDay(b['dob'] as String));

  DateTime? get dob => baby == null ? null : parseDay(baby!['dob'] as String);
  int get babyDays => dob == null ? 0 : daysBetween(_today, dob!);
  int get babyMonths => (babyDays / 30.44).floor();
  String get babyName => nameOf(baby);

  /// "Zuri", or "Zuri & Neema" for twins.
  String get babiesLabel => birthGroup.isEmpty ? babyName : [for (final (i, b) in birthGroup.indexed) nameOf(b, i)].join(' & ');

  /// Add a baby, e.g. the second twin recorded later or a child she cares for.
  Future<String> addBaby({required DateTime dob, String? name, String? sex, int? weightG, String? pregnancyId, int? order}) async {
    final id = newId();
    await store.save('babies', {
      'id': id,
      'pregnancy_id': pregnancyId ?? pregnancy?['id'],
      'name': (name == null || name.trim().isEmpty) ? null : name.trim(),
      'sex': sex,
      'dob': isoDay(dob),
      'birth_weight_g': weightG,
      'updated_at': _nowIso(),
      '_order': order,
    });
    if (weightG != null) await addGrowth(weightG: weightG, on: dob, source: 'clinic', babyId: id);
    notifyListeners();
    return id;
  }

  /// Switch from pregnancy mode to baby mode. Twins/triplets: one entry per baby in [children].
  /// Journal, questions and visit history carry over.
  Future<void> recordBirth({required DateTime dob, String? name, String? sex, int? weightG, List<NewBaby>? children}) async {
    final p = pregnancy;
    if (p != null) {
      await store.save('pregnancies', {...p, 'status': 'delivered', 'ended_on': isoDay(dob), 'updated_at': _nowIso()});
    }
    final kids = children ?? [NewBaby(name: name, sex: sex, weightG: weightG)];
    String? first;
    for (var i = 0; i < kids.length; i++) {
      final id = await addBaby(dob: dob, name: kids[i].name, sex: kids[i].sex, weightG: kids[i].weightG, pregnancyId: p?['id'] as String?, order: i + 1);
      first ??= id;
    }
    await store.setMeta('baby_sel', first);
    await store.setMeta('stage', 'postnatal');
    notifyListeners();
  }

  /// Child profile edits (name, sex, date of birth, birth weight). Last write wins on the server.
  Future<void> updateBaby(String id, Map<String, dynamic> patch) async {
    final b = store.get('babies', id);
    if (b == null) return;
    await store.save('babies', {...b, ...patch, 'updated_at': _nowIso()});
    notifyListeners();
  }

  // ───────────── daily check-in
  List<Map<String, dynamic>> get checkins =>
      store.all('checkins')..sort((a, b) => (b['client_created_at'] as String).compareTo(a['client_created_at'] as String));

  Map<String, dynamic>? get todayCheckin {
    for (final c in checkins) {
      if (sod(parseTs(c['client_created_at'] as String)) == _today) return c;
    }
    return null;
  }

  /// The most urgent check-in today: a later check without signs never hides an earlier red.
  Map<String, dynamic>? get todayWorst {
    Map<String, dynamic>? w;
    for (final c in checkins) {
      if (sod(parseTs(c['client_created_at'] as String)) != _today) continue;
      if (w == null || levelOf(c).index > levelOf(w).index) w = c;
    }
    return w;
  }

  /// Level shown for a stored check-in: the higher of the phone's and the server's.
  /// One baby's daily checks, newest first.
  List<Map<String, dynamic>> checkinsFor(String babyId) => checkins.where((c) => c['baby_id'] == babyId).toList();

  /// The most urgent level per day for one baby, oldest day first; null = no check that day
  /// (MA-47: the colour history on My baby and the child profile).
  List<({DateTime day, Level? level})> checkHistory(String babyId, {int days = 14}) {
    final worst = <DateTime, Level>{};
    for (final c in checkinsFor(babyId)) {
      final d = sod(parseTs(c['client_created_at'] as String));
      final l = levelOf(c);
      worst[d] = worst[d] == null ? l : worst[d]!.max(l);
    }
    return [
      for (var i = days - 1; i >= 0; i--)
        () {
          final d = addDays(_today, -i);
          return (day: d, level: worst[d]);
        }(),
    ];
  }

  Level levelOf(Map<String, dynamic> row) => LevelX.parse(row['level'] as String?).max(LevelX.parse(row['server_level'] as String?));

  /// True when the server's re-check of a check-in was higher than what the phone showed.
  Map<String, dynamic>? get serverRaised {
    for (final c in checkins.take(7)) {
      if (LevelX.parse(c['server_level'] as String?).index > LevelX.parse(c['level'] as String?).index) return c;
    }
    return null;
  }

  CheckinInput checkinInput({
    String feeling = 'well',
    Set<String> signs = const {},
    String? movement,
    Set<String> babySigns = const {},
    String? babyFeeding,
    int? systolic,
    int? diastolic,
  }) => CheckinInput(
    stage: pregnant ? 'pregnant' : 'postnatal',
    feeling: feeling,
    signs: signs,
    movement: pregnant ? movement : null,
    babySigns: pregnant ? const {} : babySigns,
    babyFeeding: pregnant ? null : babyFeeding,
    systolic: systolic,
    diastolic: diastolic,
    weeks: weeks,
    babyDays: babyDays,
    babyName: baby == null ? null : babyName,
  );

  /// Decide the level on the phone (≤300 ms, no network) and store the check-in.
  /// After birth, [babyAnswers] holds one entry per baby (twins, triplets): each baby gets its
  /// own row, so its own age-based rules and its own clinic alert; her answers go on the first row.
  Future<Triage> submitCheckin(CheckinInput input, {String? note, bool? ifa, bool? net, Map<String, BabyAnswers>? babyAnswers}) async {
    final hasBp = input.systolic != null && input.diastolic != null;
    final rows = <(CheckinInput, String?)>[];
    final babyNotes = <String, String>{};
    if (pregnant || babyAnswers == null || babyAnswers.isEmpty) {
      rows.add((input, pregnant ? null : baby?['id'] as String?));
    } else {
      var i = 0;
      for (final e in babyAnswers.entries) {
        final b = babyById(e.key);
        if (b == null) continue;
        final first = i++ == 0;
        if (e.value.note.trim().isNotEmpty) babyNotes[e.key] = e.value.note.trim();
        rows.add((
          CheckinInput(
            stage: 'postnatal',
            feeling: first ? input.feeling : 'well',
            signs: first ? input.signs : const {},
            babySigns: e.value.signs,
            babyFeeding: e.value.feeding,
            systolic: first ? input.systolic : null,
            diastolic: first ? input.diastolic : null,
            babyDays: ageDays(b),
            babyName: nameOf(b),
          ),
          e.key,
        ));
      }
    }
    final results = <Triage>[];
    for (final (i, (inp, babyId)) in rows.indexed) {
      final t = triage(inp);
      results.add(t);
      final first = i == 0;
      await store.save('checkins', {
        'id': newId(),
        'stage': inp.stage,
        'pregnancy_id': pregnant ? (pregnancy?['id']) : null,
        'baby_id': babyId,
        'feeling': first ? inp.feeling : null,
        'signs': inp.signs.toList(),
        'movement': inp.movement,
        'baby_signs': inp.babySigns.toList(),
        'baby_feeding': inp.babyFeeding,
        'systolic': first && hasBp ? inp.systolic : null,
        'diastolic': first && hasBp ? inp.diastolic : null,
        'level': t.level.db,
        'rules_version': t.version,
        'note': _rowNote(first ? note : null, babyId == null ? null : babyNotes[babyId]),
        'client_created_at': _nowIso(),
        '_ifa': first ? ifa : null,
        '_net': first ? net : null,
        '_reasons': t.reasons.map((r) => {'en': r.en, 'sw': r.sw}).toList(),
      });
    }
    if (note != null && note.trim().isNotEmpty) await addQuestion(note.trim());
    for (final e in babyNotes.entries) {
      await addQuestion('${nameOf(babyById(e.key)!)}: ${e.value}');
    }
    notifyListeners();
    // the result she sees: the most urgent level, with every reason at that level
    final worst = results.map((t) => t.level).reduce((a, b) => a.max(b));
    return Triage(worst, [
      for (final t in results)
        if (t.level == worst) ...t.reasons,
    ]);
  }

  String? _rowNote(String? mother, String? baby) {
    final parts = [?mother?.trim(), ?baby].where((x) => x.isNotEmpty).toList();
    return parts.isEmpty ? null : _cap(parts.join(' · '), 500);
  }

  List<Tx> reasonsOf(Map<String, dynamic> row) {
    final r = row['_reasons'];
    if (r is List && r.isNotEmpty) return r.map((e) => Tx(e['en'] as String, e['sw'] as String)).toList();
    return [
      for (final k in [...?(row['signs'] as List?), ...?(row['baby_signs'] as List?)])
        if (signByKey(k as String) != null) signByKey(k)!.label,
    ];
  }

  // ───────────── weekly blood pressure
  List<Map<String, dynamic>> get bpReadings =>
      store.all('bp_readings')..sort((a, b) => (a['client_created_at'] as String).compareTo(b['client_created_at'] as String));

  Future<Triage> addBp(int s, int d, List<String> symptoms, {String takenBy = 'self'}) async {
    final at = now();
    final history = bpReadings.map((r) => (parseTs(r['client_created_at'] as String), r['systolic'] as int));
    final t = rateBpReading(s, d, symptoms, at, history);
    await store.save('bp_readings', {
      'id': newId(),
      'pregnancy_id': pregnancy?['id'],
      'systolic': s,
      'diastolic': d,
      'symptoms': symptoms,
      'level': t.level.db,
      'taken_by': takenBy,
      'client_created_at': at.toUtc().toIso8601String(),
    });
    notifyListeners();
    return t;
  }

  // ───────────── baby growth, feeds, milestones
  /// Weights of the selected baby (or [babyId]), oldest first.
  List<Map<String, dynamic>> growthOf(String? babyId) =>
      store.all('growth_measures').where((g) => g['baby_id'] == babyId).toList()
        ..sort((a, b) => (a['measured_on'] as String).compareTo(b['measured_on'] as String));
  List<Map<String, dynamic>> get growth => growthOf(baby?['id'] as String?);

  Future<void> addGrowth({required int weightG, DateTime? on, int? lengthMm, String source = 'home', String? babyId}) async {
    final id = babyId ?? baby?['id'];
    if (id == null) return;
    await store.save('growth_measures', {
      'id': newId(),
      'baby_id': id,
      'weight_g': weightG,
      'length_mm': lengthMm,
      'source': source,
      'measured_on': isoDay(on ?? _today),
      'client_created_at': _nowIso(),
    });
    notifyListeners();
  }

  List<Map<String, dynamic>> get feeds =>
      store.all('feeds').where((f) => f['baby_id'] == baby?['id']).toList()
        ..sort((a, b) => (b['client_created_at'] as String).compareTo(a['client_created_at'] as String));

  int feedsToday() => feeds.where((f) => sod(parseTs(f['client_created_at'] as String)) == _today).length;

  Future<void> addFeed(String kind, {int? minutes, String? babyId}) async {
    final id = babyId ?? baby?['id'];
    if (id == null) return;
    await store.save('feeds', {'id': newId(), 'baby_id': id, 'kind': kind, 'minutes': minutes, 'client_created_at': _nowIso()});
    notifyListeners();
  }

  bool milestoneDone(String key, {String? babyId}) {
    final id = babyId ?? baby?['id'];
    if (id == null) return false;
    return store.get('milestones', '$id:$key')?['achieved_on'] != null;
  }

  int milestonesDone(String babyId) => store.all('milestones').where((m) => m['baby_id'] == babyId && m['achieved_on'] != null).length;

  Future<void> toggleMilestone(String key, {String? babyId}) async {
    final id = babyId ?? baby?['id'];
    if (id == null) return;
    final done = milestoneDone(key, babyId: id as String);
    await store.save('milestones', {'baby_id': id, 'milestone_key': key, 'achieved_on': done ? null : isoDay(_today), 'updated_at': _nowIso()});
    notifyListeners();
  }

  // ───────────── visits and vaccines (the schedule works offline; server rows win when present)
  List<Map<String, dynamic>> get appointments => store.all('appointments');

  List<Visit> get ancVisits {
    if (lmp == null) return [];
    final out = <Visit>[];
    for (var i = 0; i < ancContacts.length; i++) {
      final c = ancContacts[i];
      final server = appointments.where((a) => a['kind'] == 'anc' && a['contact_no'] == i + 1).firstOrNull;
      out.add(
        Visit(
          'anc',
          i + 1,
          server != null ? parseDay(server['due_on'] as String) : addDays(lmp!, c.week * 7),
          Tx('ANC ${i + 1} of 8 · ${c.title.en}', 'Kliniki ${i + 1} kati ya 8 · ${c.title.sw}'),
          attended: server?['attended_on'] == null ? null : parseDay(server!['attended_on'] as String),
          id: server?['id'] as String?,
          note: server?['note'] as String?,
          source: 'schedule',
        ),
      );
    }
    return out;
  }

  List<Visit> get pncVisits {
    if (dob == null) return [];
    return [
      for (var i = 0; i < postnatalContacts.length; i++)
        () {
          final (day, title) = postnatalContacts[i];
          final server = appointments.where((a) => a['kind'] == 'pnc' && a['contact_no'] == i + 1).firstOrNull;
          return Visit(
            'pnc',
            i + 1,
            server != null ? parseDay(server['due_on'] as String) : addDays(dob!, day),
            title,
            attended: server?['attended_on'] == null ? null : parseDay(server!['attended_on'] as String),
            id: server?['id'] as String?,
          );
        }(),
    ];
  }

  List<Visit> get ownVisits => appointments
      .where((a) => a['kind'] == 'other' || (a['source'] != 'schedule' && a['kind'] != 'anc' && a['kind'] != 'pnc'))
      .map(
        (a) => Visit(
          a['kind'] as String,
          null,
          parseDay(a['due_on'] as String),
          Tx((a['note'] as String?) ?? 'Clinic visit', (a['note'] as String?) ?? 'Ziara ya kliniki'),
          attended: a['attended_on'] == null ? null : parseDay(a['attended_on'] as String),
          id: a['id'] as String,
          note: a['note'] as String?,
          source: a['source'] as String?,
        ),
      )
      .toList();

  List<Visit> get allVisits {
    final l = [...(pregnant ? ancVisits : pncVisits), ...ownVisits]..sort((a, b) => a.due.compareTo(b.due));
    return l;
  }

  Visit? get nextVisit => allVisits.where((v) => v.attended == null && !v.due.isBefore(_today)).firstOrNull;

  Future<void> addAppointment(DateTime due, String note) async {
    await store.save('appointments', {'id': newId(), 'kind': 'other', 'due_on': isoDay(due), 'source': 'self', 'note': note.trim(), 'updated_at': _nowIso()});
    notifyListeners();
  }

  Future<void> markOwnVisit(String id, bool attended) async {
    final a = store.get('appointments', id);
    if (a == null) return;
    await store.save('appointments', {...a, 'attended_on': attended ? isoDay(_today) : null, 'updated_at': _nowIso()});
    notifyListeners();
  }

  /// Ticks made before the server schedule arrived: {babyId: {vaccine_key: date}}.
  Map<String, Map<String, dynamic>> get _marks {
    final raw = store.meta<Map<String, dynamic>>('vx_marks', {})!;
    return {
      for (final e in raw.entries)
        if (e.value is Map) e.key: asMap(e.value),
    };
  }

  List<VaccineStatus> vaccinesFor(String babyId) {
    final b = babyById(babyId);
    if (b == null) return [];
    final born = parseDay(b['dob'] as String);
    final rows = store.all('vaccine_doses').where((r) => r['baby_id'] == babyId).toList();
    final marks = _marks[babyId] ?? const {};
    return [
      for (final d in vaccineDoses)
        () {
          final s = rows.where((r) => r['vaccine_key'] == d.key).firstOrNull;
          final given = (s?['given_on'] as String?) ?? (marks[d.key] as String?);
          return VaccineStatus(
            d,
            s != null ? parseDay(s['due_on'] as String) : addDays(born, d.day),
            given == null ? null : parseDay(given),
            s?['id'] as String?,
          );
        }(),
    ];
  }

  List<VaccineStatus> get vaccines => baby == null ? [] : vaccinesFor(baby!['id'] as String);

  /// The eight child clinic contacts for one baby (MA-49), with due date and whether done:
  /// all its vaccines ticked, or (for a check with no vaccines) the postnatal visit attended.
  List<({ChildContact contact, DateTime due, bool done})> childContactsFor(String babyId) {
    final b = babyById(babyId);
    if (b == null) return [];
    final born = parseDay(b['dob'] as String);
    final vx = {for (final v in vaccinesFor(babyId)) v.dose.key: v};
    final pnc = pncVisits;
    return [
      for (final c in childContacts)
        (
          contact: c,
          due: c.vaccines.isNotEmpty ? (vx[c.vaccines.first]?.due ?? addDays(born, c.day)) : addDays(born, c.day),
          done: c.vaccines.isNotEmpty
              ? c.vaccines.every((k) => vx[k]?.given ?? false)
              : (c.pnc != null && c.pnc! <= pnc.length && pnc[c.pnc! - 1].attended != null),
        ),
    ];
  }

  VaccineStatus? get nextVaccine => vaccines.where((v) => !v.given).firstOrNull;

  /// She ticks a dose from her child health card. Server rows are updated; until the
  /// schedule arrives from the server the tick is kept on the phone and sent later.
  Future<void> setVaccineGiven(String key, bool given, {String? babyId}) async {
    final id = (babyId ?? baby?['id']) as String?;
    if (id == null) return;
    final v = vaccinesFor(id).firstWhere((x) => x.dose.key == key);
    final on = given ? isoDay(_today) : null;
    if (v.serverId != null) {
      final row = store.get('vaccine_doses', v.serverId!)!;
      final upd = _nowIso();
      await store.save('vaccine_doses', {...row, 'given_on': on, 'updated_at': upd}, op: 'update', push: {'id': v.serverId, 'given_on': on, 'updated_at': upd});
    } else {
      final all = _marks;
      final m = all[id] ?? <String, dynamic>{};
      given ? m[key] = on : m.remove(key);
      all[id] = m;
      await store.setMeta('vx_marks', all);
    }
    notifyListeners();
  }

  Future<void> _reconcileVaccineMarks() async {
    final all = _marks;
    if (all.isEmpty) return;
    for (final babyId in all.keys.toList()) {
      final marks = all[babyId]!;
      for (final v in vaccinesFor(babyId)) {
        final m = marks[v.dose.key];
        if (m == null || v.serverId == null) continue;
        final row = store.get('vaccine_doses', v.serverId!)!;
        if (row['given_on'] == null) {
          final upd = _nowIso();
          await store.save(
            'vaccine_doses',
            {...row, 'given_on': m, 'updated_at': upd},
            op: 'update',
            push: {'id': v.serverId, 'given_on': m, 'updated_at': upd},
          );
        }
        marks.remove(v.dose.key);
      }
      if (marks.isEmpty) all.remove(babyId);
    }
    await store.setMeta('vx_marks', all);
  }

  // ───────────── medicines (only those a clinician prescribed)
  List<Map<String, dynamic>> get medications => store.all('medications');

  Future<void> addMedication({required String name, String? dose, required List<String> times}) async {
    await store.save('medications', {
      'id': newId(),
      'name': name.trim(),
      'dose': dose?.trim(),
      'times': times,
      'start_on': isoDay(_today),
      'prescribed_by_clinician': true,
      'updated_at': _nowIso(),
    });
    notifyListeners();
  }

  // ───────────── journal (private) and questions for the next visit (shared when sharing is on)
  List<Map<String, dynamic>> get journal => store.all('journal_entries')..sort((a, b) => (b['updated_at'] as String).compareTo(a['updated_at'] as String));

  Future<void> addJournal(String body, {int? mood}) async {
    await store.save('journal_entries', {
      'id': newId(),
      'entry_on': isoDay(_today),
      'mood': mood,
      'body': body.trim(),
      'question_for_visit': false,
      'updated_at': _nowIso(),
    });
    notifyListeners();
  }

  List<Map<String, dynamic>> get questions => store.all('visit_questions')..sort((a, b) => (b['updated_at'] as String).compareTo(a['updated_at'] as String));

  Future<void> addQuestion(String body) async {
    await store.save('visit_questions', {'id': newId(), 'body': _cap(body, 500), 'answered': false, 'updated_at': _nowIso()});
    notifyListeners();
  }

  Future<void> toggleQuestion(String id) async {
    final q = store.get('visit_questions', id);
    if (q == null) return;
    await store.save('visit_questions', {...q, 'answered': q['answered'] != true, 'updated_at': _nowIso()});
    notifyListeners();
  }

  /// Soft delete: hidden at once, removed on the server after 30 days.
  Future<void> deleteRecord(String table, String id) async {
    final r = store.get(table, id);
    if (r == null) return;
    await store.putLocal(table, {...r, 'deleted_at': _nowIso()});
    await store.queue(table, 'delete', id, const {});
    notifyListeners();
  }

  // ───────────── birth plan
  Map<String, dynamic> get birthPlan {
    final p = store.all('birth_plans').where((b) => b['pregnancy_id'] == pregnancy?['id']).firstOrNull;
    return p ?? {'id': newId(), 'pregnancy_id': pregnancy?['id'], 'items_ready': <String>[], 'money_saved': false};
  }

  Future<void> saveBirthPlan(Map<String, dynamic> patch) async {
    await store.save('birth_plans', {...birthPlan, ...patch, 'updated_at': _nowIso()});
    notifyListeners();
  }

  // ───────────── lessons
  bool lessonDone(String id) => store.get('lesson_views', id)?['completed'] == true;
  int get lessonsDone => store.all('lesson_views').where((v) => v['completed'] == true).length;

  Future<void> markLesson(String id, {required bool completed}) async {
    if (!completed && store.get('lesson_views', id) != null) return;
    // opening never overwrites a "completed" already on the server (ignore duplicates)
    await store.save('lesson_views', {'lesson_id': id, 'completed': completed, 'viewed_at': _nowIso()}, op: completed ? 'upsert' : 'upsert_ignore');
    notifyListeners();
  }

  /// Right answers in the lesson's quiz (MA-52), null when not taken.
  int? quizScore(String id) => store.get('lesson_views', id)?['quiz_score'] as int?;

  Future<void> saveQuiz(String id, int right) async {
    final row = store.get('lesson_views', id) ?? {'lesson_id': id, 'viewed_at': _nowIso()};
    await store.save('lesson_views', {...row, 'lesson_id': id, 'completed': true, 'quiz_score': right});
    notifyListeners();
  }

  /// "For you": lessons for her stage, unfinished first, danger signs at the top.
  List<Lesson> get lessonsForYou {
    final st = pregnant ? 'pregnant' : 'baby';
    final l = lessons.where((x) => x.forStage(st)).toList()
      ..sort((a, b) {
        final d = (lessonDone(a.id) ? 1 : 0) - (lessonDone(b.id) ? 1 : 0);
        if (d != 0) return d;
        return (b.id.startsWith('danger') ? 1 : 0) - (a.id.startsWith('danger') ? 1 : 0);
      });
    return l;
  }

  // ───────────── nutrition (local only)
  Set<String> get foodsToday => {...(store.meta<List>('foods:${isoDay(_today)}', const []) ?? const []).cast<String>()};

  Future<void> toggleFood(String k) async {
    final s = foodsToday;
    s.contains(k) ? s.remove(k) : s.add(k);
    await store.setMeta('foods:${isoDay(_today)}', s.toList());
    notifyListeners();
  }

  // ───────────── today's reminders
  Set<String> get _doneToday => {...(store.meta<List>('done:${isoDay(_today)}', const []) ?? const []).cast<String>()};
  bool reminderDone(String id) => _doneToday.contains(id);

  Future<void> toggleReminder(String id) async {
    final s = _doneToday;
    s.contains(id) ? s.remove(id) : s.add(id);
    await store.setMeta('done:${isoDay(_today)}', s.toList());
    notifyListeners();
  }

  List<Reminder> get reminders {
    final r = <Reminder>[];
    if (pregnant) {
      r.add(const Reminder('ifa', Tx('Take your iron + folic acid tablet', 'Meza kidonge cha madini ya chuma na foliki'), '08:00', 'pill'));
      if (weeks >= 20) {
        r.add(const Reminder('moves', Tx("Notice baby's movements after supper", 'Fuatilia mateke ya mtoto baada ya chakula cha jioni'), '19:00', 'baby'));
      }
      final lastBp = bpReadings.lastOrNull;
      if (lastBp == null || daysBetween(_today, parseTs(lastBp['client_created_at'] as String)) >= 7) {
        r.add(const Reminder('bp', Tx('Weekly blood pressure check', 'Kipimo cha shinikizo la damu cha wiki'), '', 'gauge'));
      }
    } else {
      // one reminder per due date; twins due together share it
      final due = <String, (VaccineStatus, List<String>)>{};
      for (final (i, b) in babies.indexed) {
        final nv = vaccinesFor(b['id'] as String).where((v) => !v.given).firstOrNull;
        if (nv == null || daysBetween(nv.due, _today) > 7) continue;
        final k = '${isoDay(nv.due)}:${nv.dose.key}';
        due[k] = (nv, [...?due[k]?.$2, nameOf(b, i)]);
      }
      for (final e in due.entries) {
        final (nv, names) = e.value;
        final who = names.join(' & ');
        r.add(Reminder('vx:${e.key}', Tx("$who: ${nv.dose.label} vaccine", 'Chanjo ya ${nv.dose.label}: $who'), fmtDay(nv.due, lang), 'syringe'));
      }
    }
    final v = nextVisit;
    if (v != null && daysBetween(v.due, _today) <= 7) {
      r.add(Reminder('visit', v.title, fmtDay(v.due, lang), 'calendar'));
    }
    for (final m in medications) {
      for (final t in (m['times'] as List? ?? const [])) {
        final time = '$t'.length >= 5 ? '$t'.substring(0, 5) : '$t';
        r.add(Reminder('med:${m['id']}:$time', Tx('Take ${m['name']} ${m['dose'] ?? ''}', 'Meza ${m['name']} ${m['dose'] ?? ''}'), time, 'pill'));
      }
    }
    return r;
  }

  // ───────────── sign-in and sync
  String? syncError;
  bool syncing = false;
  String? get lastSync => store.meta<String>('last_sync');
  int get pendingCount => store.pendingCount;
  int get deadCount => store.deadCount;

  Future<void> sendCode(String phone) => remote!.sendCode(phone);

  /// Sign-in is required when the app has a server: every record must be backed up.
  bool get needsSignIn => hasRemote && !signedIn;

  Future<void> verifyCode(String phone, String code) async {
    await remote!.verifyCode(phone, code);
    await _afterSignIn();
  }

  /// Staff-assisted sign-in with the 8-digit code the clinic gave her.
  Future<void> redeemSetupCode(String code) async {
    await remote!.signInWithSetupCode(code.replaceAll(RegExp(r'\D'), ''));
    await _afterSignIn();
  }

  /// Google sign-in. Returns false when she closed the Google window (nothing happened).
  Future<bool> signInWithGoogle(Future<String?> Function() idToken) async {
    final token = await idToken();
    if (token == null) return false;
    await remote!.signInWithGoogle(token);
    await _afterSignIn();
    return true;
  }

  Future<void> _afterSignIn() async {
    await refreshFacilities();
    // Returning mother on a new phone: merge her server record before sending anything,
    // so this phone never overwrites her clinic or duplicates her pregnancy and visits.
    try {
      await _sync!.pullOnly();
      await _adoptServerRecord();
    } on RemoteError {
      // offline right after sign-in: the normal sync merges later
    }
    await _saveProfile();
    final f = facility;
    if (store.meta<bool>('share_pref', false)! && f?['id'] != null && !_sharedWith(f!['id'] as Object)) {
      await _insertConsent('share_with_facility', true, f['id']);
    }
    await syncNow();
    await bookings.refresh();
    // a mother who already has records on the server (new phone, or set up by her clinic
    // with records) goes straight to Home; a new one answers the setup questions
    if (!onboarded && (pregnancy != null || babies.isNotEmpty)) {
      await store.setMeta('data_consent', consentTextVersion);
      await store.setMeta('onboarded', true);
    }
    notifyListeners();
    await onSignedIn?.call();
  }

  Future<void> _adoptServerRecord() async {
    final p = store.get('profiles', 'me');
    if (p != null) {
      final fid = p['home_facility'];
      if (fid != null && facility?['id'] == null) {
        final f = facilityList.where((x) => x['id'] == fid).firstOrNull;
        if (f != null) await store.setMeta('facility', {'id': f['id'], 'name': f['name'], 'phone': f['phone']});
      }
      final dn = p['display_name'] as String?;
      if (name.isEmpty && dn != null && dn != 'Mama') await store.setMeta('name', dn);
    }
    // this phone's unsynced pregnancy → the active one already on the server
    final pregs = store.all('pregnancies');
    final serverPreg = pregs.where((r) => !store.isPending('pregnancies', r['id'] as String) && r['status'] == 'active').firstOrNull;
    if (serverPreg != null) {
      for (final l in pregs.where((r) => store.isPending('pregnancies', r['id'] as String) && r['status'] == 'active')) {
        await store.remapField('pregnancy_id', l['id'] as String, serverPreg['id'] as String);
        await store.dropUnsynced('pregnancies', l['id'] as String);
      }
    }
    // this phone's unsynced babies → server babies born the same day, twin by twin in birth order
    final all = babies;
    for (final day in all.map((b) => b['dob']).toSet()) {
      final sameDay = all.where((b) => b['dob'] == day);
      final server = sameDay.where((b) => !store.isPending('babies', b['id'] as String)).toList();
      final local = sameDay.where((b) => store.isPending('babies', b['id'] as String)).toList();
      for (var i = 0; i < local.length && i < server.length; i++) {
        await store.remapField('baby_id', local[i]['id'] as String, server[i]['id'] as String);
        await store.dropUnsynced('babies', local[i]['id'] as String);
      }
    }
    if (pregnancy == null && baby != null) await store.setMeta('stage', 'postnatal');
  }

  Future<void> _saveProfile() async {
    await store.save('profiles', {
      'display_name': name.isEmpty ? 'Mama' : name,
      'phone': remote?.phone,
      'lang': lang,
      'country_code': 'TZ',
      'home_facility': facility?['id'],
      'low_data': lowData,
      'updated_at': _nowIso(),
    });
  }

  Future<SyncResult?> syncNow() async {
    final s = _sync;
    if (s == null || !signedIn) return null;
    syncing = true;
    notifyListeners();
    final r = await s.run(now: now());
    if (r.ok) await _reconcileVaccineMarks();
    syncError = r.error;
    syncing = false;
    notifyListeners();
    return r;
  }

  /// Signing out wipes this phone's copy (shared phones). Unsynced items are lost, so
  /// the Profile screen warns first when [pendingCount] > 0.
  // ───────────── caregiver link (MA-53)
  /// This phone belongs to someone who helps a mother (partner, grandmother), not to a mother.
  bool get isCaregiver => store.meta<bool>('caregiver', false)!;

  /// What each linked mother shares with this caregiver (cached for offline viewing).
  List<Map<String, dynamic>> get caregiverSummary => [for (final m in store.meta<List>('cg_summary', const []) ?? const []) asMap(m)];
  String? get caregiverUpdatedAt => store.meta<String>('cg_updated');

  /// Called after sign-in (push notifications register here).
  Future<void> Function()? onSignedIn;

  Future<String?> refreshCaregiver() async {
    if (!signedIn) return 'offline';
    try {
      final r = await remote!.rpc('caregiver_summary', {});
      await store.setMeta('cg_summary', (r as List).map(asMap).toList());
      await store.setMeta('cg_updated', _nowIso());
      notifyListeners();
      return null;
    } on RemoteError catch (e) {
      return e.message;
    }
  }

  /// Redeem a mother's 6-digit code. Returns her name, or null when the code is wrong or used.
  Future<String?> acceptCaregiverInvite(String code) async {
    final r = asMap(await remote!.rpc('accept_caregiver_invite', {'p_code': code.trim()}));
    if (r['ok'] != true) return null;
    await store.setMeta('caregiver', true);
    await refreshCaregiver();
    notifyListeners();
    return r['mother_name'] as String? ?? '';
  }

  Future<String> createCaregiverInvite(String relation, {bool alerts = true}) async =>
      '${await remote!.rpc('create_caregiver_invite', {'p_relation': relation, 'p_alerts': alerts})}';

  Future<List<Map<String, dynamic>>> myCaregivers() async => [for (final r in (await remote!.rpc('my_caregivers', {}) as List)) asMap(r)];

  Future<void> stopCaregiver(String id) async => remote!.rpc('stop_caregiver', {'p_caregiver': id});

  /// "My verifiable record": asks the server for a fingerprint of her vaccine and visit record.
  /// Needs sign-in and a connection; throws [RemoteError] or [FormatException] otherwise.
  Future<RecordProof> createRecordProof() async {
    if (!signedIn) throw RemoteError('not signed in', permanent: true);
    return RecordProof.fromRpc(await remote!.rpc('my_record_proof', {}));
  }

  /// Push notifications (MA-54): the phone's FCM token, sent straight to the server.
  Future<void> registerPushToken(String token) async {
    await store.setMeta('push_token', token);
    if (!signedIn) return;
    try {
      await remote!.rpc('register_push_token', {'p_token': token});
    } on RemoteError {
      // retried at the next sign-in or token refresh
    }
  }

  Future<void> signOut() async {
    try {
      await remote?.signOut();
    } on RemoteError {
      // offline: the session token is removed locally anyway
    }
    await store.wipe();
    notifyListeners();
  }

  /// Delete everything: soft-deleted on the server now and purged after 30 days;
  /// the phone copy is wiped at once. Needs a connection when signed in.
  Future<bool> deleteAllMyData() async {
    if (signedIn) {
      try {
        await remote!.rpc('delete_my_data', {});
      } on RemoteError {
        return false;
      }
    }
    await signOut();
    return true;
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert(store.export());

  // ───────────── Doctor's Note shares (encrypted on the phone; the key is only in the QR)

  /// Encrypts [note], uploads the ciphertext and returns the QR text and expiry.
  /// Needs her to be signed in and online.
  Future<({String qr, NoteShare share})> createNoteShare(Map<String, dynamic> note, List<String> sections, {int hours = 24}) async {
    if (!signedIn) throw RemoteError('Sign in first', permanent: true);
    final sealed = await sealNote(note);
    final r = await remote!.rpc('create_note_share', {'p_ciphertext': sealed.ciphertext, 'p_sections': sections, 'p_hours': hours});
    final row = (r is List ? r.first : r) as Map;
    final share = NoteShare(id: '${row['id']}', sections: sections, createdAt: now(), expiresAt: DateTime.parse('${row['expires_at']}').toLocal());
    return (qr: shareQrPayload(share.id, sealed.key), share: share);
  }

  Future<List<NoteShare>> myNoteShares() async {
    if (!signedIn) return const [];
    final r = await remote!.rpc('my_note_shares', {});
    return [for (final row in (r as List? ?? const [])) NoteShare.fromRow(row as Map)];
  }

  Future<void> revokeNoteShare(String id) async {
    await remote!.rpc('revoke_note_share', {'p_id': id});
    notifyListeners();
  }

  // ───────────── phone reminders and the notifications list (settings stay on this phone)

  /// Reminders shown by the phone itself. Off until she turns them on (the phone asks permission).
  bool get phoneReminders => store.meta<bool>('phone_reminders', false)!;

  /// Show what the reminder is about on the lock screen. Off by default (shared phones).
  bool get reminderDetails => store.meta<bool>('reminder_details', false)!;

  /// 'HH:mm' for 'check', 'tablet' and 'movements'.
  String reminderTime(String kind) => store.meta<String>('rt_$kind') ?? const {'check': '09:00', 'tablet': '08:00', 'movements': '19:00'}[kind] ?? '09:00';

  Future<void> setReminderTime(String kind, String hhmm) async {
    await store.setMeta('rt_$kind', hhmm);
    notifyListeners();
  }

  /// Today's reminders she has not ticked yet (the badge on the bell).
  int get unreadNotifications => reminders.where((r) => !reminderDone(r.id)).length;

  // ───────────── kept on this phone only (never synced): care plan, movement diary, onboarding extras

  /// Agreement to keep her information in the app (required to start). Versioned with the consent text.
  bool get dataConsent => store.meta<String>('data_consent') == consentTextVersion;
  Future<void> setDataConsent(bool v) async {
    await store.setMeta('data_consent', v ? consentTextVersion : null);
    notifyListeners();
  }

  /// single | twins | multiple | unknown (pregnancy only).
  String get pregnancyType => store.meta<String>('pregnancy_type', 'unknown')!;
  Future<void> setPregnancyType(String v) async {
    await store.setMeta('pregnancy_type', v);
    notifyListeners();
  }

  /// Emergency care plan: where to go and who to call. Keys: hospital_name, hospital_address,
  /// hospital_phone, contact_name, contact_phone, transport_name, transport_phone.
  Map<String, String> get carePlan {
    final m = store.meta<Map>('care_plan');
    return m == null ? {} : {for (final e in m.entries) '${e.key}': '${e.value ?? ''}'};
  }

  Future<void> saveCarePlan(Map<String, String> v) async {
    await store.setMeta('care_plan', {for (final e in v.entries) e.key: _cap(e.value.trim(), 120)});
    notifyListeners();
  }

  /// Baby's movements, one answer per day: usual | fewer | none. There is no number to reach;
  /// "fewer" or "none" always means contact a health worker today (lesson "kicks").
  List<Map<String, dynamic>> get movementLog {
    final l = [for (final m in store.meta<List>('movement_log', const []) ?? const []) asMap(m)];
    l.sort((a, b) => '${b['day']}'.compareTo('${a['day']}'));
    return l;
  }

  String? get movementToday => movementLog.where((m) => m['day'] == isoDay(_today)).firstOrNull?['answer'] as String?;

  Future<void> logMovement(String answer) async {
    final day = isoDay(_today);
    final l = movementLog.where((m) => m['day'] != day).toList()..insert(0, {'day': day, 'answer': answer});
    await store.setMeta('movement_log', l.take(60).toList());
    notifyListeners();
  }
}
