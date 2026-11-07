// Mothers' circle content check, layer 1: rules. The Dart twin of
// supabase/functions/community/check.ts; both pass test/fixtures/community_cases.json.
// The rules come from assets/content/community_rules.json, a copy of the server's rules.json.
//
// On the phone it runs while she writes, so she hears straight away that a phone number must
// come out, that a danger sign needs help now, or which checked fact goes with her post.
// The server runs the same rules again (plus the AI check); the phone never decides alone.
import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../core/tx.dart';

enum Verdict { publish, review, block, fix }

class CommunityCheck {
  final Verdict verdict;
  final bool urgent, medical;

  /// `urgent`, `privacy`, `abuse`, `selling`, `miracle`, `myth:ID` or `fact:ID`
  final List<String> reasons;

  /// Ids of checked facts that go with the post.
  final List<String> facts;
  const CommunityCheck(this.verdict, {this.urgent = false, this.medical = false, this.reasons = const [], this.facts = const []});
}

class Myth {
  final String id;
  final List<List<String>> all;
  final List<String> unless;
  final Tx fact;
  const Myth(this.id, this.all, this.unless, this.fact);
}

/// Community name (username) rules; see rules.json "handle".
class HandleRules {
  final int min, max, maxDigits;
  final List<String> reservedContains, reservedPrefix, offensive;
  const HandleRules({
    required this.min,
    required this.max,
    required this.maxDigits,
    required this.reservedContains,
    required this.reservedPrefix,
    required this.offensive,
  });
}

class CommunityRules {
  final HandleRules handle;
  final List<String> urgent, abuse, selling, miracle, medical, questionStarts;
  final List<Myth> myths;
  const CommunityRules({
    required this.handle,
    required this.urgent,
    required this.abuse,
    required this.selling,
    required this.miracle,
    required this.medical,
    required this.questionStarts,
    required this.myths,
  });

  static CommunityRules? _loaded;
  static CommunityRules? get loaded => _loaded;

  static Future<CommunityRules> load({AssetBundle? bundle}) async =>
      _loaded ??= parse(await (bundle ?? rootBundle).loadString('assets/content/community_rules.json'));

  static CommunityRules parse(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    List<String> ls(Object? v) => [for (final e in (v as List? ?? const [])) '$e'];
    final h = j['handle'] as Map<String, dynamic>;
    return CommunityRules(
      handle: HandleRules(
        min: h['min'] as int,
        max: h['max'] as int,
        maxDigits: h['max_digits'] as int,
        reservedContains: ls(h['reserved_contains']),
        reservedPrefix: ls(h['reserved_prefix']),
        offensive: ls(h['offensive']),
      ),
      urgent: ls(j['urgent']),
      abuse: ls(j['abuse']),
      selling: ls(j['selling']),
      miracle: ls(j['miracle']),
      medical: ls(j['medical_terms']),
      questionStarts: ls(j['question_starts']),
      myths: [
        for (final m in (j['myths'] as List).cast<Map<String, dynamic>>())
          Myth(
            m['id'] as String,
            [for (final g in m['all'] as List) ls(g)],
            ls(m['unless']),
            Tx((m['fact'] as Map)['en'] as String, (m['fact'] as Map)['sw'] as String),
          ),
      ],
    );
  }

  Myth? myth(String id) => myths.where((m) => m.id == id).firstOrNull;
}

final _phone = RegExp(r'\+?\d[\d\s\-]{7,}\d');
final _email = RegExp(r'[^\s@]+@[^\s@]+\.[a-z]{2,}', caseSensitive: false);
final _link = RegExp(r'(https?://|www\.)\S+', caseSensitive: false);

/// Lower case, plain apostrophes, words separated by single spaces, "soooo" -> "soo".
String cleanText(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[‘’`]'), "'")
    .replaceAll(RegExp(r"[^\p{L}\p{N}'%+\- ]", unicode: true), ' ')
    .replaceAllMapped(RegExp(r'(\p{L})\1{2,}', unicode: true), (m) => '${m[1]}${m[1]}')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Phone numbers with 9 or more digits, and email addresses.
List<String> privacyHits(String text) => [
  for (final m in _phone.allMatches(text))
    if (m[0]!.replaceAll(RegExp(r'\D'), '').length >= 9) m[0]!.trim(),
  for (final m in _email.allMatches(text)) m[0]!,
];

bool _has(String padded, String term) => padded.contains(' $term');
bool _any(String padded, List<String> terms) => terms.any((t) => _has(padded, t));

CommunityCheck checkText(String text, CommunityRules rules) {
  final whole = ' ${cleanText(text)} ';
  final reasons = <String>[], facts = <String>[];
  var myth = false;

  final urgent = _any(whole, rules.urgent);
  if (urgent) reasons.add('urgent');
  if (privacyHits(text).isNotEmpty) reasons.add('privacy');
  if (_any(whole, rules.abuse)) reasons.add('abuse');
  if (_any(whole, rules.selling) || _link.hasMatch(text)) reasons.add('selling');
  if (_any(whole, rules.miracle)) reasons.add('miracle');

  for (final m in RegExp(r'([^.!?\n]+)([.!?\n]*)').allMatches(text)) {
    final s = ' ${cleanText(m[1]!)} ';
    if (s.trim().isEmpty) continue;
    final q = m[2]!.contains('?') || rules.questionStarts.any((w) => s.startsWith(' $w '));
    for (final r in rules.myths) {
      if (facts.contains(r.id)) continue;
      if (!r.all.every((g) => _any(s, g))) continue;
      if (r.unless.isNotEmpty && _any(s, r.unless)) continue;
      facts.add(r.id);
      reasons.add('${q ? 'fact' : 'myth'}:${r.id}');
      if (!q) myth = true;
    }
  }

  final verdict = reasons.contains('abuse')
      ? Verdict.block
      : reasons.contains('privacy')
      ? Verdict.fix
      : (urgent || myth || reasons.contains('selling') || reasons.contains('miracle'))
      ? Verdict.review
      : Verdict.publish;
  return CommunityCheck(verdict, urgent: urgent, medical: _any(whole, rules.medical), reasons: reasons, facts: facts);
}

// ───────────── community names (usernames), twin of checkHandle in check.ts

/// Why a community name is not allowed.
enum HandleProblem { length, chars, start, digits, reserved, offensive }

const _leet = {'0': 'o', '1': 'i', 'l': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '8': 'b'};

/// Two names are the same name when their keys match ("Mama_Amina" = "mama.amina" = "mamaam1na").
/// 1, i and l count as the same letter, so "Ami1a" cannot copy "Amila".
String handleKey(String handle) =>
    handle.trim().toLowerCase().replaceAll(RegExp('[._]'), '').replaceAllMapped(RegExp('[01l34578]'), (m) => _leet[m[0]]!);

HandleProblem? checkHandle(String handle, HandleRules r) {
  final h = handle.trim();
  if (h.length < r.min || h.length > r.max) return HandleProblem.length;
  if (!RegExp(r'^[A-Za-z0-9._]+$').hasMatch(h)) return HandleProblem.chars;
  if (!RegExp('^[A-Za-z]').hasMatch(h) || RegExp('[._]{2}').hasMatch(h) || RegExp(r'[._]$').hasMatch(h)) return HandleProblem.start;
  if (RegExp(r'\d').allMatches(h).length > r.maxDigits) return HandleProblem.digits;
  final key = handleKey(h);
  if (r.reservedContains.any(key.contains) || r.reservedPrefix.any(key.startsWith)) return HandleProblem.reserved;
  bool bad(String w) => w.length >= 5 ? key.contains(w) : key == w || key.startsWith(w) || key.endsWith(w);
  if (r.offensive.any(bad)) return HandleProblem.offensive;
  return null;
}
