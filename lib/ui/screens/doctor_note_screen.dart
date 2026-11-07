import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/content.dart';
import '../../core/dates.dart';
import '../../core/note_share.dart';
import '../../data/remote.dart';
import '../theme.dart';
import '../widgets.dart';

/// Doctor's Note: a short clinical summary in SBAR order (Situation, Background, Assessment
/// history, Recommendations and actions), made on the phone from her own records, for her to
/// show a clinician. She chooses what goes in, and nothing is shown until she agrees to share.
/// It never contains a diagnosis. Sharing by QR encrypts the note on the phone; the key is only
/// in the QR, so the server cannot read it, and only a health worker who scans it can open it.
class DoctorNoteScreen extends StatefulWidget {
  const DoctorNoteScreen({super.key});
  @override
  State<DoctorNoteScreen> createState() => _DoctorNoteScreenState();
}

class _DoctorNoteScreenState extends State<DoctorNoteScreen> {
  bool consent = false;
  final include = {'symptoms': true, 'pregnancy': true, 'alerts': true, 'questions': true};

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final tt = Theme.of(context).textTheme;
    final labels = {
      'symptoms': context.t('Symptom history (last 14 days)', 'Historia ya dalili (siku 14)'),
      'pregnancy': s.pregnant
          ? context.t('Pregnancy information', 'Taarifa za ujauzito')
          : context.t('Birth and baby information', 'Taarifa za kujifungua na mtoto'),
      'alerts': context.t('Warning history (amber and red)', 'Historia ya tahadhari (njano na nyekundu)'),
      'questions': context.t('My questions for the visit', 'Maswali yangu ya kliniki'),
    };
    return AppScaffold(
      title: context.t("Doctor's Note", 'Taarifa kwa daktari'),
      children: [
        Text(
          context.t(
            'A short summary of your own records to show your nurse or doctor. It is made on this phone and is not a diagnosis.',
            'Muhtasari mfupi wa kumbukumbu zako wa kumwonyesha muuguzi au daktari. Unatengenezwa kwenye simu hii na si utambuzi.',
          ),
          style: tt.bodyLarge,
        ),
        SectionTitle(context.t('What to include', 'Cha kujumuisha')),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.xs),
          child: Column(
            children: [
              for (final k in include.keys)
                CheckboxListTile(
                  key: Key('note-inc-$k'),
                  value: include[k],
                  onChanged: (v) => setState(() => include[k] = v ?? false),
                  title: Text(labels[k]!, style: tt.titleMedium),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
            ],
          ),
        ),
        const Gap(Sp.smd),
        AppCard(
          color: C.primarySoft,
          border: C.primary.withValues(alpha: .25),
          padding: const EdgeInsets.fromLTRB(Sp.md, Sp.xs, Sp.xs, Sp.xs),
          child: SwitchListTile(
            key: const Key('note-consent'),
            contentPadding: EdgeInsets.zero,
            value: consent,
            onChanged: (v) => setState(() => consent = v),
            title: Text(context.t('I agree to show this summary to my clinician', 'Nakubali kumwonyesha mhudumu wangu muhtasari huu'), style: tt.titleMedium),
            subtitle: Text(context.t('You can turn this off at any time.', 'Unaweza kuzima wakati wowote.')),
          ),
        ),
        if (!consent) ...[
          const Gap(Sp.md),
          EmptyState(Icons.lock_outline, context.t('Turn on sharing above to see the summary.', 'Washa kushiriki hapo juu kuona muhtasari.')),
        ] else ...[
          SectionTitle(context.t('Summary', 'Muhtasari')),
          _Sbar(include: include),
          const Gap(Sp.md),
          _ShareByQr(include: include),
        ],
        const Gap(Sp.md),
        const OfflineIndicator(),
      ],
    );
  }
}

class _Sbar extends StatelessWidget {
  final Map<String, bool> include;
  const _Sbar({required this.include});

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final tt = Theme.of(context).textTheme;
    final now = DateTime.now();
    Widget section(String letter, String title, List<String> rows) => Padding(
      padding: const EdgeInsets.only(bottom: Sp.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: C.primary, borderRadius: BorderRadius.circular(R.small)),
            child: Text(letter, style: AppTypography.h3.copyWith(color: Colors.white, fontSize: 16)),
          ),
          const SizedBox(width: Sp.smd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: tt.titleMedium),
                const Gap(Sp.xs),
                if (rows.isEmpty) Text(context.t('Nothing recorded.', 'Hakuna kilichoandikwa.'), style: tt.bodyMedium),
                for (final r in rows) Text(r, style: tt.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );

    final parts = sbarSections(context, include);
    return AppCard(
      key: const Key('note-summary'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${s.name.isEmpty ? '' : '${s.name} · '}${fmtDayYear(now, s.lang)}', style: tt.bodySmall),
          const Gap(Sp.smd),
          for (final (letter, title, rows) in parts) section(letter, title, rows),
          Text(
            context.t(
              'Made by Safari ya Mama from what the mother entered. Warning levels come from fixed WHO-based rules. Not a diagnosis.',
              'Imetengenezwa na Safari ya Mama kutokana na alichoandika mama. Viwango vya tahadhari vinatoka kwenye kanuni za WHO. Si utambuzi.',
            ),
            style: tt.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// The note in SBAR order: (letter, title, lines). Used on screen and inside the encrypted QR note.
List<(String, String, List<String>)> sbarSections(BuildContext context, Map<String, bool> include) {
  final s = context.appRead;
  final now = DateTime.now();
  final recent = s.checkins.where((c) => now.difference(parseTs(c['client_created_at'] as String)).inDays < 14).toList();
  final alerts = s.checkins.where((c) => s.levelOf(c) != Level.green).take(10).toList();
  final latest = s.checkins.firstOrNull;
  final bp = s.bpReadings.isEmpty ? null : s.bpReadings.last;
  final attended = s.ancVisits.where((v) => v.attended != null).length;
  final openQ = s.questions.where((q) => q['answered'] != true).toList();
  String line(Map<String, dynamic> c) =>
      '${fmtDay(parseTs(c['client_created_at'] as String), s.lang)}: ${context.tx(LevelBanner.status(s.levelOf(c)))}'
      '${s.reasonsOf(c).isEmpty ? '' : ' · ${s.reasonsOf(c).map(context.tx).join(', ')}'}';

  final situation = <String>[
    if (s.pregnant)
      context.t('Pregnant, ${s.weeks} weeks', 'Mjamzito, wiki ${s.weeks}')
    else
      context.t('Mother after birth; ${s.babiesLabel}, ${s.babyDays} days old', 'Mama baada ya kujifungua; ${s.babiesLabel}, siku ${s.babyDays}'),
    if (latest != null) context.t('Latest check: ', 'Ukaguzi wa mwisho: ') + line(latest),
  ];
  final background = <String>[
    if (include['pregnancy']! && s.pregnant && s.edd != null)
      context.t('Due date about ${fmtDayYear(s.edd!, 'en')}', 'Kujifungua takriban ${fmtDayYear(s.edd!, 'sw')}'),
    if (include['pregnancy']! && s.pregnant) context.t('ANC visits attended: $attended of 8', 'Kliniki alizohudhuria: $attended kati ya 8'),
    if (include['pregnancy']! && s.pregnant && s.pregnancyType != 'unknown')
      context.t(
        'Pregnancy: ${s.pregnancyType}',
        'Ujauzito: ${switch (s.pregnancyType) {
          'single' => 'mtoto mmoja',
          'twins' => 'pacha',
          _ => 'zaidi ya mmoja',
        }}',
      ),
    if (include['pregnancy']! && !s.pregnant && s.dob != null)
      context.t('Birth date ${fmtDayYear(s.dob!, 'en')}', 'Tarehe ya kuzaliwa ${fmtDayYear(s.dob!, 'sw')}'),
    if (bp != null) context.t('Last blood pressure ${bp['systolic']}/${bp['diastolic']}', 'Shinikizo la damu la mwisho ${bp['systolic']}/${bp['diastolic']}'),
    for (final m in s.medications)
      context.t('Medicine: ${m['name']}${m['dose'] == null ? '' : ' ${m['dose']}'}', 'Dawa: ${m['name']}${m['dose'] == null ? '' : ' ${m['dose']}'}'),
  ];
  final assessment = <String>[
    if (include['symptoms']!) ...recent.take(14).map(line),
    if (include['alerts']! && !include['symptoms']!) ...alerts.map(line),
    if (include['alerts']! && include['symptoms']!) context.t('Amber or red checks ever: ${alerts.length}', 'Ukaguzi wa njano au nyekundu: ${alerts.length}'),
  ];
  final recommend = <String>[
    if (latest != null) context.tx(LevelBanner.title(s.levelOf(latest))),
    if (include['questions']!) ...openQ.map((q) => context.t('Question: ', 'Swali: ') + (q['body'] as String)),
  ];
  return [
    ('S', context.t('Situation', 'Hali'), situation),
    ('B', context.t('Background', 'Historia'), background),
    ('A', context.t('Assessment history', 'Historia ya tathmini'), assessment),
    ('R', context.t('Recommendations and actions', 'Mapendekezo na hatua'), recommend),
  ];
}

/// Share by QR: makes an encrypted, expiring share and shows its QR; lists earlier shares
/// with how often a clinician opened them, and stops any of them at once.
class _ShareByQr extends StatefulWidget {
  final Map<String, bool> include;
  const _ShareByQr({required this.include});
  @override
  State<_ShareByQr> createState() => _ShareByQrState();
}

class _ShareByQrState extends State<_ShareByQr> {
  int hours = 24;
  bool busy = false;
  String? qr, error;
  NoteShare? current;
  List<NoteShare>? earlier;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await context.appRead.myNoteShares();
      if (mounted) setState(() => earlier = l);
    } catch (_) {
      if (mounted) setState(() => earlier = const []);
    }
  }

  Future<void> _make() async {
    final s = context.appRead;
    setState(() {
      busy = true;
      error = null;
    });
    final sections = [
      for (final e in widget.include.entries)
        if (e.value) e.key,
    ];
    final note = {
      'v': 1,
      'lang': s.lang,
      'name': s.name,
      'made_at': DateTime.now().toUtc().toIso8601String(),
      'sections': [
        for (final (letter, title, rows) in sbarSections(context, widget.include)) {'letter': letter, 'title': title, 'rows': rows},
      ],
      'footer': context.t(
        'Made by Safari ya Mama from what the mother entered. Warning levels come from fixed WHO-based rules. Not a diagnosis.',
        'Imetengenezwa na Safari ya Mama kutokana na alichoandika mama. Viwango vya tahadhari vinatoka kwenye kanuni za WHO. Si utambuzi.',
      ),
    };
    try {
      final r = await s.createNoteShare(note, sections, hours: hours);
      if (!mounted) return;
      setState(() {
        qr = r.qr;
        current = r.share;
      });
      _load();
    } on RemoteError catch (e) {
      if (mounted) {
        setState(
          () => error = e.permanent
              ? context.t('Sharing was refused: ${e.message}', 'Kushiriki kumekataliwa: ${e.message}')
              : context.t(
                  'No connection. Making a QR needs internet; the summary above works without it.',
                  'Hakuna mtandao. Kutengeneza QR kunahitaji intaneti; muhtasari hapo juu unafanya kazi bila hiyo.',
                ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => error = context.t('Could not make the QR. Please try again.', 'Imeshindikana kutengeneza QR. Jaribu tena.'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _stop(String id) async {
    try {
      await context.appRead.revokeNoteShare(id);
      if (!mounted) return;
      if (current?.id == id) {
        setState(() {
          qr = null;
          current = null;
        });
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('Sharing stopped.', 'Kushiriki kumesimamishwa.'))));
      _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(context.t('No connection. Try again to stop sharing.', 'Hakuna mtandao. Jaribu tena kusimamisha.'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final tt = Theme.of(context).textTheme;
    if (!s.signedIn) {
      return Text(
        context.t(
          'To share by QR code, sign in from Profile. You can always show the summary above on your screen.',
          'Kushiriki kwa msimbo wa QR, ingia kupitia Wasifu. Unaweza kuonyesha muhtasari hapo juu kwenye skrini yako wakati wowote.',
        ),
        style: tt.bodyMedium,
      );
    }
    String when(DateTime d) => '${fmtDay(d, s.lang)} ${fmtTime(d)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(context.t('Share by QR code', 'Shiriki kwa msimbo wa QR')),
        Text(
          context.t(
            'The note is locked on this phone. Only a health worker who scans this QR can open it, and each opening is recorded.',
            'Taarifa inafungwa kwenye simu hii. Ni mhudumu wa afya tu atakayeskani QR hii anayeweza kuifungua, na kila ufunguzi unarekodiwa.',
          ),
          style: tt.bodyMedium,
        ),
        const Gap(Sp.smd),
        if (qr == null) ...[
          Text(context.t('Stop sharing after', 'Acha kushiriki baada ya'), style: AppTypography.label),
          const Gap(Sp.sm),
          Wrap(
            spacing: Sp.sm,
            children: [
              for (final (h, l) in [(24, context.t('1 day', 'Siku 1')), (72, context.t('3 days', 'Siku 3')), (168, context.t('7 days', 'Siku 7'))])
                ChoiceChip(key: Key('note-hours-$h'), label: Text(l), selected: hours == h, onSelected: (_) => setState(() => hours = h)),
            ],
          ),
          const Gap(Sp.smd),
          PrimaryButton(
            key: const Key('note-make-qr'),
            context.t('Make QR code', 'Tengeneza msimbo wa QR'),
            icon: Icons.qr_code_2,
            loading: busy,
            onPressed: _make,
          ),
          if (error != null) ...[const Gap(Sp.smd), ErrorState(error!, retryLabel: context.t('Try again', 'Jaribu tena'), onRetry: _make)],
        ] else ...[
          AppCard(
            key: const Key('note-qr'),
            child: Column(
              children: [
                QrImageView(
                  data: qr!,
                  size: 240,
                  backgroundColor: Colors.white,
                  semanticsLabel: context.t('QR code for your clinician', 'Msimbo wa QR kwa mhudumu'),
                ),
                const Gap(Sp.sm),
                Text(context.t('Show this to your nurse or doctor', 'Mwonyeshe muuguzi au daktari wako'), style: tt.titleMedium, textAlign: TextAlign.center),
                Text(context.t('Works until ${when(current!.expiresAt)}', 'Inafanya kazi hadi ${when(current!.expiresAt)}'), style: tt.bodySmall),
              ],
            ),
          ),
          const Gap(Sp.smd),
          OutlineButton(context.t('Stop sharing now', 'Acha kushiriki sasa'), icon: Icons.block, onPressed: () => _stop(current!.id)),
        ],
        if (earlier != null && earlier!.where((e) => e.id != current?.id).isNotEmpty) ...[
          SectionTitle(context.t('Earlier shares', 'Ulishiriki awali')),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.xs),
            child: Column(
              children: [
                for (final e in earlier!.where((e) => e.id != current?.id).take(10))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(when(e.createdAt), style: tt.titleMedium),
                    subtitle: Text(
                      [
                        e.revokedAt != null
                            ? context.t('Stopped', 'Imesimamishwa')
                            : e.active
                            ? context.t('Active until ${when(e.expiresAt)}', 'Hai hadi ${when(e.expiresAt)}')
                            : context.t('Expired', 'Imeisha'),
                        context.t('opened ${e.openCount} times', 'imefunguliwa mara ${e.openCount}'),
                      ].join(' · '),
                    ),
                    trailing: e.active ? TextButton(onPressed: () => _stop(e.id), child: Text(context.t('Stop', 'Acha'))) : null,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
