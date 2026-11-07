// Voice input for MamaBot, using the phone's own speech recogniser.
// The microphone is asked for only when she first taps the mic, never on opening the screen.
// Her words go into the text box for her to check and send; nothing is recorded or kept,
// and nothing is sent without her pressing Send.
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum VoiceStart { listening, unavailable, noKiswahili }

class VoiceInput {
  VoiceInput._();
  static final instance = VoiceInput._();

  final _stt = SpeechToText();
  bool? _ready;
  String? _sw, _en;

  /// Shown only where the phone could have a recogniser (Android, iOS).
  bool get supported => !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
  bool get listening => _stt.isListening;

  Future<bool> _init() async {
    if (_ready != null) return _ready!;
    try {
      _ready = await _stt.initialize(onError: (_) {});
      if (_ready!) {
        final all = await _stt.locales();
        String? pick(List<String> prefer, String lang) {
          for (final p in prefer) {
            final hit = all.where((l) => l.localeId.replaceAll('-', '_').toLowerCase() == p).firstOrNull;
            if (hit != null) return hit.localeId;
          }
          return all.where((l) => l.localeId.toLowerCase().startsWith(lang)).firstOrNull?.localeId;
        }

        _sw = pick(['sw_tz', 'sw_ke', 'sw'], 'sw');
        _en = pick(['en_gb', 'en_ke', 'en_us'], 'en');
      }
    } catch (_) {
      _ready = false;
    }
    return _ready!;
  }

  /// Starts listening in the app language. [onWords] gets the words so far, [onDone] when she stops.
  /// When Kiswahili is not installed on the phone it listens with the phone's own language and
  /// says so ([VoiceStart.noKiswahili]).
  Future<VoiceStart> start(String lang, {required void Function(String words) onWords, required void Function() onDone}) async {
    if (!supported || !await _init()) return VoiceStart.unavailable;
    final locale = lang == 'sw' ? _sw : _en;
    try {
      await _stt.listen(
        onResult: (r) {
          onWords(r.recognizedWords);
          if (r.finalResult) onDone();
        },
        listenOptions: SpeechListenOptions(
          localeId: locale,
          partialResults: true,
          cancelOnError: true,
          listenFor: const Duration(seconds: 45),
          pauseFor: const Duration(seconds: 4),
        ),
      );
    } catch (_) {
      return VoiceStart.unavailable;
    }
    return lang == 'sw' && _sw == null ? VoiceStart.noKiswahili : VoiceStart.listening;
  }

  Future<void> stop() async {
    try {
      await _stt.stop();
    } catch (_) {}
  }
}
