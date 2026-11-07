// Appointments with a health worker: a clinic visit or a video call, booked from the times her
// clinic has opened. Her bookings are kept on the phone so Home and reminders work offline.
// Video calls open in the phone's browser through the link from the Edge Function "telemed-join",
// from 15 minutes before the start.
import '../../../data/local_store.dart';
import '../../../data/remote.dart';
import '../../../state/app_state.dart';

class Slot {
  final String id, mode;
  final DateTime startsAt;
  final int minutes;
  final String? staffName;
  const Slot(this.id, this.startsAt, this.minutes, this.mode, {this.staffName});
  factory Slot.fromJson(Map<String, dynamic> j) => Slot(
    j['id'] as String,
    DateTime.parse(j['starts_at'] as String).toLocal(),
    (j['minutes'] as num?)?.toInt() ?? 20,
    j['mode'] as String? ?? 'clinic',
    staffName: j['staff_name'] as String?,
  );
}

class Booking {
  final String id, mode, status;
  final DateTime startsAt;
  final int minutes;
  final String? facilityName, facilityPhone, staffName, reason;

  /// The health worker's advice after the appointment (written in the dashboard).
  final String? outcomeNote;
  const Booking({
    required this.id,
    required this.startsAt,
    required this.minutes,
    required this.mode,
    required this.status,
    this.facilityName,
    this.facilityPhone,
    this.staffName,
    this.reason,
    this.outcomeNote,
  });
  factory Booking.fromJson(Map<String, dynamic> j) => Booking(
    id: j['id'] as String,
    startsAt: DateTime.parse(j['starts_at'] as String).toLocal(),
    minutes: (j['minutes'] as num?)?.toInt() ?? 20,
    mode: j['mode'] as String? ?? 'clinic',
    status: j['status'] as String? ?? 'booked',
    facilityName: j['facility_name'] as String?,
    facilityPhone: j['facility_phone'] as String?,
    staffName: j['staff_name'] as String?,
    reason: j['reason'] as String?,
    outcomeNote: j['outcome_note'] as String?,
  );

  bool get video => mode == 'video';
  DateTime get endsAt => startsAt.add(Duration(minutes: minutes));

  /// The call can be joined from 15 minutes before until 30 minutes after the planned end.
  DateTime get opensAt => startsAt.subtract(const Duration(minutes: 15));
  bool canJoin(DateTime now) => video && status == 'booked' && !now.isBefore(opensAt) && now.isBefore(endsAt.add(const Duration(minutes: 30)));
  bool upcoming(DateTime now) => status == 'booked' && now.isBefore(endsAt.add(const Duration(minutes: 30)));
}

/// Why booking did not work, in words she can act on.
enum BookingProblem { taken, tooMany, offline }

class BookingError implements Exception {
  final BookingProblem problem;
  const BookingError(this.problem);
}

class BookingService {
  final AppState s;
  BookingService(this.s);

  RemoteApi get _r {
    final r = s.remote;
    if (r == null || r.userId == null) throw const BookingError(BookingProblem.offline);
    return r;
  }

  List<Booking> get all => [for (final e in (s.store.meta<List>('bookings', const []) ?? const [])) Booking.fromJson(asMap(e))];

  /// Booked and not over yet, soonest first.
  List<Booking> get upcoming => all.where((b) => b.upcoming(s.now())).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  Booking? get next => upcoming.firstOrNull;

  Future<void> refresh() async {
    if (s.remote?.userId == null) return;
    try {
      final r = await s.remote!.rpc('my_bookings', const {});
      await s.store.setMeta('bookings', [for (final e in (r as List? ?? const [])) asMap(e)]);
      s.touch();
      s.onBookingsChanged?.call();
    } on RemoteError {
      // offline: keep what the phone has
    }
  }

  Future<List<Slot>> openSlots(String facilityId, String mode) async {
    final r = await _r.rpc('open_slots', {'p_facility': facilityId, 'p_mode': mode, 'p_days': 14});
    return [for (final e in (r as List? ?? const [])) Slot.fromJson(asMap(e))];
  }

  Future<Booking> book(Slot slot, {String? reason}) async {
    try {
      final r = await _r.rpc('book_slot', {'p_slot': slot.id, 'p_reason': reason});
      final b = Booking.fromJson(asMap(r));
      await s.store.setMeta('bookings', [asMap(r), ...(s.store.meta<List>('bookings', const []) ?? const []).map(asMap).where((e) => e['id'] != b.id)]);
      s.touch();
      s.onBookingsChanged?.call();
      return b;
    } on RemoteError catch (e) {
      if (e.message.contains('3 upcoming')) throw const BookingError(BookingProblem.tooMany);
      if (e.message.contains('no longer free')) throw const BookingError(BookingProblem.taken);
      throw const BookingError(BookingProblem.offline);
    }
  }

  Future<void> cancel(String id) async {
    await _r.rpc('cancel_booking', {'p_booking': id});
    await s.store.setMeta('bookings', [
      for (final e in (s.store.meta<List>('bookings', const []) ?? const []).map(asMap)) e['id'] == id ? {...e, 'status': 'cancelled'} : e,
    ]);
    s.touch();
    s.onBookingsChanged?.call();
  }

  /// The video call link. Throws [RemoteError] with code `too_early` / `ended` when outside the time.
  Future<String> joinUrl(String id) async {
    final r = await _r.invoke('telemed-join', {'booking_id': id});
    final url = r is Map ? r['url'] as String? : null;
    if (url == null) throw RemoteError('no link');
    return url;
  }
}
