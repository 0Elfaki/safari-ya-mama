// Mothers' circle: posts and replies from other mothers, checked before others see them.
// Reading needs a signal once; the last feed is kept on the phone to read offline.
// Writing goes through the Edge Function "community" (rules + AI check); see community_check.dart.
// Nobody sees who wrote a post: on each post she chooses "Anonymous mother" or her community name (a username), plus her stage.
import '../../../core/tx.dart';
import '../../../data/local_store.dart';
import '../../../data/remote.dart';
import '../../../state/app_state.dart';

const communityTopics = <(String, Tx)>[
  ('pregnancy', Tx('Pregnancy', 'Ujauzito')),
  ('birth', Tx('Birth', 'Kujifungua')),
  ('feeding', Tx('Breastfeeding', 'Kunyonyesha')),
  ('baby', Tx('Baby care', 'Malezi ya mtoto')),
  ('feelings', Tx('Feelings', 'Hisia')),
  ('other', Tx('Other', 'Mengineyo')),
];

Tx topicLabel(String id) => communityTopics.firstWhere((t) => t.$1 == id, orElse: () => communityTopics.last).$2;

class CommunityPost {
  final String id, body, topic, status;
  final String? parentId, authorName, stageKind, healthNote;
  final int? stageValue;
  final List<String> facts;
  final bool anonymous, urgent, staffPost, checked, mine, helped;
  final int helpfulCount, replyCount;
  final DateTime createdAt;

  const CommunityPost({
    required this.id,
    required this.body,
    required this.topic,
    required this.status,
    required this.createdAt,
    this.parentId,
    this.authorName,
    this.anonymous = true,
    this.stageKind,
    this.stageValue,
    this.healthNote,
    this.facts = const [],
    this.urgent = false,
    this.staffPost = false,
    this.checked = false,
    this.mine = false,
    this.helped = false,
    this.helpfulCount = 0,
    this.replyCount = 0,
  });

  factory CommunityPost.fromJson(Map<String, dynamic> j) => CommunityPost(
    id: j['id'] as String,
    body: j['body'] as String? ?? '',
    topic: j['topic'] as String? ?? 'other',
    status: j['status'] as String? ?? 'published',
    createdAt: DateTime.tryParse('${j['created_at']}')?.toLocal() ?? DateTime.now(),
    parentId: j['parent_id'] as String?,
    authorName: j['author_name'] as String?,
    anonymous: j['anonymous'] != false,
    stageKind: j['stage_kind'] as String?,
    stageValue: (j['stage_value'] as num?)?.toInt(),
    healthNote: j['health_note'] as String?,
    facts: [for (final f in (j['facts'] as List? ?? const [])) '$f'],
    urgent: j['urgent'] == true,
    staffPost: j['staff_post'] == true,
    checked: j['checked'] == true,
    mine: j['mine'] == true,
    helped: j['helped'] == true,
    helpfulCount: (j['helpful_count'] as num?)?.toInt() ?? 0,
    replyCount: (j['reply_count'] as num?)?.toInt() ?? 0,
  );

  bool get waiting => status == 'review' || status == 'hidden';

  /// "@MamaJasiri · 28 weeks pregnant", "Anonymous mother · baby 3 months", "Asha · Health worker".
  Tx get byline {
    if (staffPost) return Tx('${authorName ?? 'Health worker'} · Health worker', '${authorName ?? 'Mhudumu wa afya'} · Mhudumu wa afya');
    final who = authorName == null ? const Tx('Anonymous mother', 'Mama asiyejulikana') : Tx('@$authorName', '@$authorName');
    final v = stageValue;
    if (stageKind == 'pregnant' && v != null) return Tx('${who.en} · $v weeks pregnant', '${who.sw} · mimba ya wiki $v');
    if (stageKind == 'baby' && v != null) {
      return v == 0 ? Tx('${who.en} · new baby', '${who.sw} · mtoto mchanga') : Tx('${who.en} · baby $v months', '${who.sw} · mtoto miezi $v');
    }
    return who;
  }
}

/// Her community name and standing (from my_community_profile).
class CommunityMe {
  final String? handle;
  final DateTime? canChangeAt, reviewUntil, mutedUntil;
  final int strikes;
  const CommunityMe({this.handle, this.canChangeAt, this.reviewUntil, this.mutedUntil, this.strikes = 0});
  factory CommunityMe.fromJson(Map<String, dynamic> j) {
    DateTime? t(String k) => DateTime.tryParse('${j[k]}')?.toLocal();
    return CommunityMe(
      handle: j['handle'] as String?,
      canChangeAt: t('can_change_at'),
      reviewUntil: t('review_until'),
      mutedUntil: t('muted_until'),
      strikes: (j['strikes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Why a community name was refused: a shared rule (see community_check.dart), or
/// `taken` (someone has it, or a look-alike), or `too_soon` (changed in the last 30 days).
class HandleRefused implements Exception {
  final String reason;
  final DateTime? canChangeAt;
  const HandleRefused(this.reason, {this.canChangeAt});
}

/// Posting was refused before the content check: `need_handle` or `muted` (with [until]).
class PostRefused implements Exception {
  final String reason;
  final DateTime? until;
  const PostRefused(this.reason, {this.until});
}

/// What happened when she shared a post.
class PostOutcome {
  /// published | review | blocked
  final String status;
  final bool urgent;
  final List<String> facts;
  const PostOutcome(this.status, {this.urgent = false, this.facts = const []});
}

class CommunityService {
  final AppState s;
  CommunityService(this.s);

  RemoteApi get _r {
    final r = s.remote;
    if (r == null || r.userId == null) throw RemoteError('sign in first', permanent: true);
    return r;
  }

  /// The feed as last seen, for offline reading.
  List<CommunityPost> get cached => [
    for (final e in (s.store.meta<List>('community_cache', const []) ?? const [])) CommunityPost.fromJson(asMap(e)),
  ];

  Future<List<CommunityPost>> feed({String? topic, DateTime? before}) async {
    final r = await _r.rpc('community_feed', {'p_topic': topic, 'p_before': before?.toUtc().toIso8601String(), 'p_limit': 30});
    final rows = [for (final e in (r as List? ?? const [])) asMap(e)];
    if (topic == null && before == null) await s.store.setMeta('community_cache', rows);
    return rows.map(CommunityPost.fromJson).toList();
  }

  Future<(CommunityPost, List<CommunityPost>)?> thread(String id) async {
    final r = await _r.rpc('community_thread', {'p_post': id});
    if (r is! Map) return null;
    final j = asMap(r);
    return (CommunityPost.fromJson(asMap(j['post'])), [for (final e in (j['replies'] as List? ?? const [])) CommunityPost.fromJson(asMap(e))]);
  }

  /// Her stage as other mothers see it: weeks pregnant, or the baby's age in months.
  Map<String, dynamic>? get _stage {
    if (!s.onboarded) return null;
    if (s.pregnant) return {'kind': 'pregnant', 'value': s.weeks};
    if (s.baby != null) return {'kind': 'baby', 'value': s.babyMonths.clamp(0, 60)};
    return null;
  }

  /// Her community name, kept on the phone after the first look-up.
  String? get handle => s.store.meta<String>('community_handle');

  Future<CommunityMe> me() async {
    final r = await _r.rpc('my_community_profile', const {});
    final m = r is Map ? CommunityMe.fromJson(asMap(r)) : const CommunityMe();
    await s.store.setMeta('community_handle', m.handle);
    s.touch();
    return m;
  }

  /// null when the name is free and allowed, otherwise the reason (a rule, or `taken`).
  Future<String?> handleProblem(String handle) async {
    final r = await _r.invoke('community', {'action': 'handle_check', 'handle': handle.trim()});
    return r is Map && r['ok'] == false ? '${r['problem']}' : null;
  }

  Future<void> setHandle(String handle) async {
    try {
      final r = await _r.invoke('community', {'action': 'handle', 'handle': handle.trim()});
      await s.store.setMeta('community_handle', r is Map ? r['handle'] as String? : handle.trim());
      s.touch();
    } on RemoteError catch (e) {
      final d = e.details;
      if (d is Map && d['error'] is String && e.status != null && e.status! < 500) {
        throw HandleRefused(d['error'] as String, canChangeAt: DateTime.tryParse('${d['can_change_at']}')?.toLocal());
      }
      rethrow;
    }
  }

  /// [anonymous]: shown as "Anonymous mother"; otherwise with her community name.
  Future<PostOutcome> share(String body, {required String topic, bool anonymous = true, String? parentId}) async {
    final Object? r;
    try {
      r = await _r.invoke('community', {
        'action': 'post',
        'body': body.trim(),
        'topic': topic,
        'parent_id': ?parentId,
        'anonymous': anonymous,
        'stage': ?_stage,
      });
    } on RemoteError catch (e) {
      final code = e.code;
      if (code == 'need_handle' || code == 'muted') {
        throw PostRefused(code!, until: DateTime.tryParse('${(e.details as Map)['until']}')?.toLocal());
      }
      rethrow;
    }
    final j = r is Map ? asMap(r) : const <String, dynamic>{};
    return PostOutcome(
      j['status'] as String? ?? 'review',
      urgent: j['urgent'] == true,
      facts: [for (final f in (j['facts'] as List? ?? const [])) '$f'],
    );
  }

  Future<void> report(String id, String reason) => _r.rpc('report_community_post', {'p_post': id, 'p_reason': reason});
  Future<bool> toggleHelpful(String id) async => await _r.rpc('toggle_community_helpful', {'p_post': id}) == true;
  Future<void> delete(String id) => _r.rpc('delete_my_community_post', {'p_post': id});
}
