// The server side of sync, behind a small interface so tests can use a fake.
import 'package:supabase_flutter/supabase_flutter.dart';

class RemoteError implements Exception {
  final String message;

  /// true for validation or permission errors that will fail again on retry.
  final bool permanent;

  /// HTTP status from an Edge Function, and its JSON body (e.g. {"error": "too_early", "opens_at": ...}).
  final int? status;
  final Object? details;
  RemoteError(this.message, {this.permanent = false, this.status, this.details});

  /// The `error` code from an Edge Function body, when there is one.
  String? get code => details is Map ? (details as Map)['error'] as String? : null;
  @override
  String toString() => message;
}

abstract class RemoteApi {
  String? get userId;
  String? get phone;
  Future<void> upsert(String table, List<Map<String, dynamic>> rows, {bool ignoreDuplicates = false, String? onConflict});
  Future<void> update(String table, String id, Map<String, dynamic> patch);
  Future<dynamic> rpc(String fn, Map<String, dynamic> params);
  Future<List<Map<String, dynamic>>> pullSince(String table, String column, String? since, {int limit = 1000});
  Future<List<Map<String, dynamic>>> facilities();
  Future<void> sendCode(String phone);
  Future<void> verifyCode(String phone, String code);

  /// Staff-assisted sign-in: an 8-digit code from the clinic (Edge Function mother-setup).
  Future<void> signInWithSetupCode(String code);

  /// Google: the ID token from the phone's Google account picker.
  Future<void> signInWithGoogle(String idToken);
  Future<void> signOut();

  /// Calls an Edge Function with the signed-in session; returns its JSON body.
  Future<dynamic> invoke(String fn, Map<String, dynamic> body);
}

/// Supabase implementation. The anon key is public by design; row-level
/// security in Postgres decides what this mother can read and write.
class SupabaseRemote implements RemoteApi {
  final SupabaseClient c;
  SupabaseRemote(this.c);

  @override
  String? get userId => c.auth.currentUser?.id;
  @override
  String? get phone => c.auth.currentUser?.phone;

  Future<T> _wrap<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on PostgrestException catch (e) {
      // 22xxx bad value, 23xxx constraint, 42xxx permission/RLS, PGRST1xx/2xx request errors.
      // 23503 (foreign key) is NOT permanent: the row it points to may simply not have arrived yet.
      final code = e.code ?? '';
      final permanent = code != '23503' && RegExp(r'^(22|23|42|PGRST[12])').hasMatch(code);
      throw RemoteError('${e.code}: ${e.message}', permanent: permanent);
    } on FunctionException catch (e) {
      throw RemoteError('function ${e.status}', permanent: e.status >= 400 && e.status < 500, status: e.status, details: e.details);
    } on AuthException catch (e) {
      throw RemoteError(e.message, permanent: true);
    } catch (e) {
      throw RemoteError(e.toString());
    }
  }

  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows, {bool ignoreDuplicates = false, String? onConflict}) =>
      _wrap(() => c.from(table).upsert(rows, ignoreDuplicates: ignoreDuplicates, onConflict: onConflict));

  @override
  Future<void> update(String table, String id, Map<String, dynamic> patch) => _wrap(() => c.from(table).update(patch).eq('id', id));

  @override
  Future<dynamic> rpc(String fn, Map<String, dynamic> params) => _wrap(() => c.rpc(fn, params: params));

  @override
  Future<List<Map<String, dynamic>>> pullSince(String table, String column, String? since, {int limit = 1000}) => _wrap(() async {
    var q = c.from(table).select();
    if (since != null) q = q.gt(column, since);
    final r = await q.order(column, ascending: true).limit(limit);
    return List<Map<String, dynamic>>.from(r);
  });

  @override
  Future<List<Map<String, dynamic>>> facilities() => _wrap(() async {
    final r = await c.from('facilities').select('id,name,level,phone,emergency_24h').order('name');
    return List<Map<String, dynamic>>.from(r);
  });

  @override
  Future<void> sendCode(String phone) => _wrap(() => c.auth.signInWithOtp(phone: phone));

  @override
  Future<void> verifyCode(String phone, String code) => _wrap(() => c.auth.verifyOTP(type: OtpType.sms, phone: phone, token: code));

  @override
  Future<void> signInWithSetupCode(String code) => _wrap(() async {
    final r = await c.functions.invoke('mother-setup', body: {'action': 'redeem', 'code': code});
    final data = r.data;
    final hash = data is Map ? data['token_hash'] as String? : null;
    if (hash == null) throw RemoteError('setup code refused', permanent: true);
    await c.auth.verifyOTP(type: OtpType.magiclink, tokenHash: hash);
  });

  @override
  Future<void> signInWithGoogle(String idToken) => _wrap(() => c.auth.signInWithIdToken(provider: OAuthProvider.google, idToken: idToken));

  @override
  Future<void> signOut() => _wrap(() => c.auth.signOut());

  @override
  Future<dynamic> invoke(String fn, Map<String, dynamic> body) =>
      _wrap(() async => (await c.functions.invoke(fn, body: body).timeout(const Duration(seconds: 20))).data);
}
