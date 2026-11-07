// Doctor's Note sharing: end-to-end encryption on the phone.
//
// The note is encrypted with AES-256-GCM using a fresh random key for every share. Only the
// ciphertext goes to the server (create_note_share). The key travels only inside the QR code:
//   SYM2:<share id>.<key, base64url>
// A clinician needs the QR (the key) AND a health-worker account (open_note_share returns the
// ciphertext and logs the view). The server can never read the note.
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

final _aes = AesGcm.with256bits();

class SealedNote {
  /// base64(nonce | ciphertext | mac): what the server stores.
  final String ciphertext;

  /// base64url(32-byte key) without padding: goes only into the QR.
  final String key;
  const SealedNote(this.ciphertext, this.key);
}

Future<SealedNote> sealNote(Map<String, dynamic> note) async {
  final key = await _aes.newSecretKey();
  final box = await _aes.encrypt(utf8.encode(jsonEncode(note)), secretKey: key);
  final raw = await key.extractBytes();
  return SealedNote(base64.encode(box.concatenation()), base64Url.encode(raw).replaceAll('=', ''));
}

Future<Map<String, dynamic>> openNote(String ciphertext, String key) async {
  final k = SecretKey(base64Url.decode(base64Url.normalize(key)));
  final box = SecretBox.fromConcatenation(base64.decode(ciphertext), nonceLength: _aes.nonceLength, macLength: _aes.macAlgorithm.macLength);
  final clear = await _aes.decrypt(box, secretKey: k);
  return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
}

final _qr = RegExp(r'^SYM2:([0-9a-fA-F-]{36})\.([A-Za-z0-9_-]{43})$');

/// QR text for a share.
String shareQrPayload(String shareId, String key) {
  final p = 'SYM2:$shareId.$key';
  if (!_qr.hasMatch(p)) throw const FormatException('bad share id or key');
  return p;
}

/// Reads a scanned QR back into (share id, key); null when it is not a Doctor's Note QR.
(String id, String key)? parseShareQr(String text) {
  final m = _qr.firstMatch(text.trim());
  return m == null ? null : (m.group(1)!.toLowerCase(), m.group(2)!);
}

/// One share as the mother sees it in her list.
class NoteShare {
  final String id;
  final List<String> sections;
  final DateTime createdAt, expiresAt;
  final DateTime? revokedAt, lastOpenedAt;
  final int openCount;
  const NoteShare({
    required this.id,
    required this.sections,
    required this.createdAt,
    required this.expiresAt,
    this.revokedAt,
    this.lastOpenedAt,
    this.openCount = 0,
  });

  bool get active => revokedAt == null && expiresAt.isAfter(DateTime.now());

  static NoteShare fromRow(Map row) => NoteShare(
    id: '${row['id']}',
    sections: [for (final x in (row['sections'] as List? ?? const [])) '$x'],
    createdAt: DateTime.parse('${row['created_at']}').toLocal(),
    expiresAt: DateTime.parse('${row['expires_at']}').toLocal(),
    revokedAt: row['revoked_at'] == null ? null : DateTime.parse('${row['revoked_at']}').toLocal(),
    lastOpenedAt: row['last_opened_at'] == null ? null : DateTime.parse('${row['last_opened_at']}').toLocal(),
    openCount: (row['open_count'] as num?)?.toInt() ?? 0,
  );
}
