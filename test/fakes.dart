import 'package:safari_ya_mama/data/remote.dart';

/// In-memory stand-in for Supabase that copies the behaviours the sync contract relies on.
class FakeRemote implements RemoteApi {
  String? uid = 'mother-1';
  final calls = <String>[];
  final tables = <String, Map<String, Map<String, dynamic>>>{};
  RemoteError? failNext;
  int failTimes = 0;

  @override
  String? get userId => uid;
  @override
  String? get phone => '+255700000101';

  void _maybeFail() {
    if (failTimes > 0 && failNext != null) {
      failTimes--;
      throw failNext!;
    }
  }

  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows, {bool ignoreDuplicates = false, String? onConflict}) async {
    calls.add('upsert $table ${rows.length}${ignoreDuplicates ? ' ignore' : ''}');
    _maybeFail();
    final t = tables.putIfAbsent(table, () => {});
    for (final r in rows) {
      final k = '${r['id'] ?? '${r['baby_id']}:${r['milestone_key']}'}';
      if (ignoreDuplicates && t.containsKey(k)) continue;
      t[k] = {...?t[k], ...r, 'created_at': DateTime.now().toUtc().toIso8601String()};
    }
  }

  @override
  Future<void> update(String table, String id, Map<String, dynamic> patch) async {
    calls.add('update $table $id');
    _maybeFail();
    tables[table]?[id]?.addAll(patch);
  }

  /// Canned RPC replies by function name (null when absent).
  final rpcResults = <String, dynamic>{};

  /// Live RPC replies by function name: they see the parameters (and may throw).
  final rpcHandlers = <String, dynamic Function(Map<String, dynamic>)>{};

  @override
  Future<dynamic> rpc(String fn, Map<String, dynamic> params) async {
    calls.add('rpc $fn');
    _maybeFail();
    final h = rpcHandlers[fn];
    return h != null ? h(params) : rpcResults[fn];
  }

  /// Edge Function replies by name; a handler sees the body (and may throw).
  final invokeHandlers = <String, dynamic Function(Map<String, dynamic>)>{};
  final invokeBodies = <Map<String, dynamic>>[];

  @override
  Future<dynamic> invoke(String fn, Map<String, dynamic> body) async {
    calls.add('invoke $fn');
    invokeBodies.add(body);
    _maybeFail();
    return invokeHandlers[fn]?.call(body);
  }

  /// Rows the server will return on the next pull, per table.
  final pullRows = <String, List<Map<String, dynamic>>>{};

  @override
  Future<List<Map<String, dynamic>>> pullSince(String table, String column, String? since, {int limit = 1000}) async {
    final rows = pullRows.remove(table) ?? const [];
    return rows.where((r) => since == null || '${r[column]}'.compareTo(since) > 0).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> facilities() async => [
    {'id': 'f1', 'name': 'Sample Health Centre 1', 'phone': '+255700000001', 'emergency_24h': true},
  ];
  @override
  Future<void> sendCode(String phone) async => calls.add('otp $phone');
  @override
  Future<void> verifyCode(String phone, String code) async {
    calls.add('verify $phone $code');
    uid = 'mother-1';
  }

  /// Codes the fake clinic has issued; a redeemed code is removed.
  final setupCodes = <String>{};

  @override
  Future<void> signInWithSetupCode(String code) async {
    calls.add('setup $code');
    if (!setupCodes.remove(code)) throw RemoteError('setup code refused', permanent: true);
    uid = 'mother-1';
  }

  @override
  Future<void> signInWithGoogle(String idToken) async {
    calls.add('google');
    uid = 'mother-1';
  }

  @override
  Future<void> signOut() async => uid = null;
}
