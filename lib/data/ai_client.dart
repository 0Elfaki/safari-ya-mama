// Client for the AI gateway Edge Function (resources/AI_GATEWAY.md, task "assistant").
// The scripted offline assistant stays the base: this only adds an answer when the gateway
// gives one. It never sets or changes a warning level, and it never sees her name or phone.
import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// One reply from the gateway that the screen can show. `null` from a gateway call means
/// "use the scripted answer" (unavailable, error, timeout, offline or a reply we cannot read).
class AiReply {
  /// Shown verbatim: the server already ends it with its own "AI answer · not medical advice" line.
  final String text;

  /// Small badge text from the server, e.g. "AI answer" or "Safety message · not AI".
  final String label;

  /// true when the server matched an urgent topic: the screen shows the Emergency help button.
  final bool urgent;

  const AiReply({required this.text, required this.label, required this.urgent});

  /// Reads a 200 response body. Returns null for `unavailable` or anything malformed.
  static AiReply? fromJson(Object? body) {
    if (body is! Map) return null;
    if (body['unavailable'] == true) return null;
    final text = body['text'];
    if (text is! String || text.trim().isEmpty) return null;
    final urgent = body['urgent'] == true || body['action'] == 'emergency';
    final label = body['label'] is String && (body['label'] as String).trim().isNotEmpty
        ? body['label'] as String
        : (urgent ? 'Safety message · not AI' : 'AI answer · not medical advice');
    return AiReply(text: text, label: label, urgent: urgent);
  }
}

/// Seam for the assistant screen and tests: question text, app language ('sw'|'en') and the
/// gateway stage ('pregnant'|'postpartum'|'baby'). Nothing else about her is sent.
typedef AssistantGateway = Future<AiReply?> Function(String question, String lang, String stage);

class AiClient {
  static const timeout = Duration(seconds: 15);

  /// Calls `ai-gateway` through the signed-in Supabase client (the session token and the public
  /// anon key are attached by supabase_flutter). Every failure returns null; nothing is logged.
  static Future<AiReply?> askSupabase(String question, String lang, String stage) async {
    try {
      final c = Supabase.instance.client;
      if (c.auth.currentSession == null) return null;
      final r = await c.functions
          .invoke(
            'ai-gateway',
            body: {
              'task': 'assistant',
              'lang': lang == 'sw' ? 'sw' : 'en',
              'input': question,
              'context': {'stage': stage},
            },
          )
          .timeout(timeout);
      if (r.status != 200) return null;
      return AiReply.fromJson(r.data);
    } catch (_) {
      // 401/403/429/500 (FunctionException), no signal, timeout: the scripted answer is used.
      return null;
    }
  }
}

/// App stage ('pregnant' | 'postnatal') → gateway stage. The first 6 weeks after birth are
/// "postpartum" (the mother's own recovery), after that questions are mostly about the baby.
String gatewayStage({required bool pregnant, required int babyDays}) => pregnant ? 'pregnant' : (babyDays <= 42 ? 'postpartum' : 'baby');
