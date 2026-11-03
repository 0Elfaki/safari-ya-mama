// "My verifiable record": the reply of the my_record_proof() RPC and the QR text built from it.
// The QR holds only the record's fingerprint (a SHA-256 hash), never a name or health details.

final _hex64 = RegExp(r'^[0-9a-fA-F]{64}$');

/// QR content for a record proof: exactly `SYM1:` + the 64-character hash in lowercase hex.
/// Throws [FormatException] when the hash is not 64 hex characters.
String recordQrPayload(String recordHash) {
  final h = recordHash.trim();
  if (!_hex64.hasMatch(h)) throw const FormatException('record_hash must be 64 hex characters');
  return 'SYM1:${h.toLowerCase()}';
}

class ProofVaccine {
  final String key;
  final String? dueOn, givenOn;
  const ProofVaccine(this.key, this.dueOn, this.givenOn);
}

class ProofVisit {
  final String kind;
  final int? contactNo;
  final String? dueOn, attendedOn;
  const ProofVisit(this.kind, this.contactNo, this.dueOn, this.attendedOn);
}

class RecordProof {
  final String proofId;
  final String recordHash;
  final int? ledgerSeq;
  final DateTime? issuedAt;
  final List<ProofVaccine> vaccines;
  final List<ProofVisit> visits;
  const RecordProof({required this.proofId, required this.recordHash, this.ledgerSeq, this.issuedAt, this.vaccines = const [], this.visits = const []});

  String get qrPayload => recordQrPayload(recordHash);

  /// First 8 characters of the proof id, for reading out at the clinic.
  String get shortId => proofId.length > 8 ? proofId.substring(0, 8) : proofId;

  /// Accepts what the RPC returns through PostgREST: a list with one row, or the row itself.
  static RecordProof fromRpc(Object? r) {
    final row = r is List ? (r.isEmpty ? null : r.first) : r;
    if (row is! Map) throw const FormatException('no proof returned');
    final doc = row['record_doc'] is Map ? row['record_doc'] as Map : const {};
    String? s(Object? v) => v == null ? null : '$v';
    final hash = '${row['record_hash'] ?? ''}';
    recordQrPayload(hash); // validates
    return RecordProof(
      proofId: '${row['proof_id'] ?? doc['proof_id'] ?? ''}',
      recordHash: hash.toLowerCase(),
      ledgerSeq: row['ledger_seq'] is num ? (row['ledger_seq'] as num).toInt() : int.tryParse('${row['ledger_seq']}'),
      issuedAt: DateTime.tryParse('${row['issued_at'] ?? doc['issued_at'] ?? ''}')?.toLocal(),
      vaccines: [
        for (final v in (doc['vaccines'] is List ? doc['vaccines'] as List : const []))
          if (v is Map) ProofVaccine('${v['vaccine_key'] ?? ''}', s(v['due_on']), s(v['given_on'])),
      ],
      visits: [
        for (final v in (doc['visits'] is List ? doc['visits'] as List : const []))
          if (v is Map) ProofVisit('${v['kind'] ?? ''}', v['contact_no'] is num ? (v['contact_no'] as num).toInt() : null, s(v['due_on']), s(v['attended_on'])),
      ],
    );
  }
}
