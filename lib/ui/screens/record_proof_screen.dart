import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/content.dart';
import '../../core/dates.dart';
import '../../core/record_proof.dart';
import '../theme.dart';
import '../widgets.dart';

/// "My verifiable record": a QR with the fingerprint of her vaccine and clinic-visit record, which
/// the server writes to the Safari ya Mama ledger (stamped daily on the Bitcoin blockchain). Only the
/// fingerprint leaves the server; no name or personal data goes on the blockchain. Needs sign-in and
/// a connection; nothing here gives or changes health advice.
class RecordProofScreen extends StatefulWidget {
  const RecordProofScreen({super.key});
  @override
  State<RecordProofScreen> createState() => _RecordProofScreenState();
}

class _RecordProofScreenState extends State<RecordProofScreen> {
  RecordProof? proof;
  bool busy = false;
  bool failed = false;

  Future<void> _create() async {
    setState(() {
      busy = true;
      failed = false;
    });
    RecordProof? p;
    try {
      p = await context.appRead.createRecordProof();
    } catch (_) {
      p = null; // offline, rate limit or server error: nothing personal is logged
    }
    if (!mounted) return;
    setState(() {
      busy = false;
      proof = p ?? proof;
      failed = p == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final ready = s.hasRemote && s.signedIn;
    final p = proof;
    final lang = s.lang;
    String day(String? iso) => iso == null || iso.isEmpty ? '—' : fmtDayYear(parseDay(iso.substring(0, 10)), lang);
    final vaccineLabel = {for (final d in vaccineDoses) d.key: d.label};
    String visitLabel(ProofVisit v) {
      final n = v.contactNo == null ? '' : ' ${v.contactNo}';
      return switch (v.kind) {
            'anc' => context.t('Pregnancy clinic visit', 'Kliniki ya ujauzito'),
            'pnc' => context.t('After-birth visit', 'Kliniki baada ya kujifungua'),
            'immunisation' => context.t('Vaccine visit', 'Kliniki ya chanjo'),
            _ => context.t('Clinic visit', 'Kliniki'),
          } +
          n;
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.t('My verifiable record', 'Kumbukumbu yangu inayothibitishwa'))),
      body: Pad(
        children: [
          AppCard(
            child: Text(
              context.t(
                'This creates a tamper-proof fingerprint of your vaccine and clinic-visit record. The fingerprint is recorded in the Safari ya Mama ledger and stamped every day on the Bitcoin blockchain, so any clinic can check that your record was not changed. Your name and personal details never go on the blockchain: only the fingerprint does.',
                'Hii inatengeneza alama ya kidijitali isiyoweza kughushiwa ya kumbukumbu zako za chanjo na mahudhurio ya kliniki. Alama hii inahifadhiwa kwenye daftari la Safari ya Mama na kugongwa muhuri kila siku kwenye blockchain ya Bitcoin, ili kliniki yoyote iweze kuhakiki kwamba kumbukumbu yako haijabadilishwa. Jina lako na taarifa zako binafsi haziwekwi kwenye blockchain: ni alama tu.',
              ),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          const Gap(12),
          if (!ready)
            AppCard(
              key: const Key('proof-needs-signin'),
              color: C.amberSoft,
              child: Text(
                context.t(
                  'To create your record QR you need to sign in and be online. Your records stay on this phone in the meantime.',
                  'Ili kutengeneza QR ya kumbukumbu yako unahitaji kuingia na kuwa na mtandao. Kumbukumbu zako zinabaki kwenye simu hii kwa sasa.',
                ),
              ),
            )
          else ...[
            FilledButton.icon(
              key: const Key('proof-create'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: busy ? null : _create,
              icon: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.qr_code_2),
              label: Text(context.t('Create my record QR', 'Tengeneza QR ya kumbukumbu yangu')),
            ),
            if (failed) ...[
              const Gap(8),
              Text(
                key: const Key('proof-failed'),
                context.t(
                  'Could not create it now. Check that you are online and try again later.',
                  'Imeshindikana kutengeneza sasa. Hakikisha una mtandao kisha jaribu tena baadaye.',
                ),
                style: const TextStyle(color: C.amber, fontWeight: FontWeight.w700),
              ),
            ],
          ],
          if (p != null) ...[
            const Gap(16),
            AppCard(
              child: Column(
                children: [
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(8),
                    child: QrImageView(
                      key: const Key('proof-qr'),
                      data: p.qrPayload,
                      size: 240,
                      backgroundColor: Colors.white,
                      semanticsLabel: context.t('Record QR code', 'Msimbo wa QR wa kumbukumbu'),
                    ),
                  ),
                  const Gap(8),
                  Text('${context.t('Proof', 'Uthibitisho')} ${p.shortId}', style: Theme.of(context).textTheme.titleMedium),
                  if (p.issuedAt != null)
                    Text(
                      '${context.t('Created', 'Imetengenezwa')} ${fmtDayYear(p.issuedAt!, lang)} ${fmtTime(p.issuedAt!)}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  const Gap(4),
                  Text(
                    context.t(
                      'Show this QR at the clinic. The blockchain stamp is added within a day.',
                      'Onyesha QR hii kliniki. Muhuri wa blockchain unaongezwa ndani ya siku moja.',
                    ),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            SectionTitle(context.t('Vaccines in this record', 'Chanjo kwenye kumbukumbu hii')),
            AppCard(
              child: p.vaccines.isEmpty
                  ? Text(context.t('No vaccines recorded yet.', 'Bado hakuna chanjo zilizoandikwa.'))
                  : Column(
                      children: [
                        for (final v in p.vaccines)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(vaccineLabel[v.key] ?? v.key),
                            subtitle: Text(
                              v.givenOn != null ? '${context.t('Given', 'Imetolewa')} ${day(v.givenOn)}' : '${context.t('Due', 'Inatarajiwa')} ${day(v.dueOn)}',
                            ),
                          ),
                      ],
                    ),
            ),
            SectionTitle(context.t('Clinic visits in this record', 'Mahudhurio ya kliniki kwenye kumbukumbu hii')),
            AppCard(
              child: p.visits.isEmpty
                  ? Text(context.t('No clinic visits recorded yet.', 'Bado hakuna mahudhurio yaliyoandikwa.'))
                  : Column(
                      children: [
                        for (final v in p.visits)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(visitLabel(v)),
                            subtitle: Text(
                              v.attendedOn != null
                                  ? '${context.t('Attended', 'Alihudhuria')} ${day(v.attendedOn)}'
                                  : '${context.t('Due', 'Inatarajiwa')} ${day(v.dueOn)}',
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
