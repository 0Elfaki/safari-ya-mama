import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/dates.dart';
import '../../../data/remote.dart';
import '../../../ui/theme.dart';
import '../../../ui/widgets.dart';
import '../data/community_service.dart';
import '../domain/community_check.dart';

/// Words for the name ideas: kind Kiswahili words mothers use.
const _ideaWords = ['Jasiri', 'Imara', 'Furaha', 'Tumaini', 'Baraka', 'Upendo', 'Amani', 'Nuru', 'Zawadi', 'Faraja'];

/// Plain words for each reason a name is refused (shared rules, plus `taken` and `too_soon`).
String handleProblemText(BuildContext c, String problem, {DateTime? canChangeAt}) => switch (problem) {
  'length' => c.t('Use 3 to 20 characters.', 'Tumia herufi 3 hadi 20.'),
  'chars' => c.t('Use only letters, numbers, _ or . (no spaces).', 'Tumia herufi, namba, _ au . tu (bila nafasi).'),
  'start' => c.t(
    'Start with a letter. Do not end with _ or . or put two of them together.',
    'Anza na herufi. Usimalizie na _ au . wala usiweke mbili pamoja.',
  ),
  'digits' => c.t('Use at most 4 numbers, so it does not look like a phone number.', 'Tumia namba 4 au chache, isionekane kama namba ya simu.'),
  'reserved' => c.t('This name looks like a health worker or the app. Please choose another.', 'Jina hili linafanana na mhudumu wa afya au programu. Chagua jingine.'),
  'offensive' => c.t('Please choose a kind name.', 'Tafadhali chagua jina la heshima.'),
  'taken' => c.t('Someone already has this name, or one that looks the same. Try another.', 'Mtu tayari ana jina hili, au linalofanana nalo. Jaribu jingine.'),
  'too_soon' => c.t(
    'You can change your name once every 30 days${canChangeAt == null ? '' : '. Next change: ${fmtDay(canChangeAt, 'en')}'}.',
    'Unaweza kubadilisha jina mara moja kila siku 30${canChangeAt == null ? '' : '. Badiliko lijalo: ${fmtDay(canChangeAt, 'sw')}'}.',
  ),
  _ => c.t('Not saved. Check your internet and try again.', 'Haijahifadhiwa. Kagua intaneti kisha ujaribu tena.'),
};

/// Her community name: the name other mothers see when she does not post anonymously.
/// Any name she likes, within the rules: unique, no phone numbers, not posing as staff.
/// Returns the saved name (pop result).
class CommunityNameScreen extends StatefulWidget {
  const CommunityNameScreen({super.key});
  @override
  State<CommunityNameScreen> createState() => _CommunityNameScreenState();
}

class _CommunityNameScreenState extends State<CommunityNameScreen> {
  late final name = TextEditingController(text: context.appRead.community.handle ?? '');
  Timer? _debounce;
  String? problem; // a rule or 'taken'
  bool checking = false, free = false, busy = false;
  DateTime? canChangeAt;
  late final List<String> ideas = _makeIdeas();

  @override
  void initState() {
    super.initState();
    CommunityRules.load().then((_) => mounted ? setState(() {}) : null, onError: (_) {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    name.dispose();
    super.dispose();
  }

  List<String> _makeIdeas() {
    final r = Random();
    final words = [..._ideaWords]..shuffle(r);
    return [for (final w in words.take(4)) 'Mama$w${10 + r.nextInt(89)}'];
  }

  void _changed(String v) {
    _debounce?.cancel();
    final rules = CommunityRules.loaded;
    final local = rules == null ? null : checkHandle(v, rules.handle)?.name;
    setState(() {
      problem = v.trim().isEmpty ? null : local;
      free = false;
      checking = local == null && v.trim().isNotEmpty;
    });
    if (local != null || v.trim().isEmpty) return;
    // ask the server only after she stops typing
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final p = await context.appRead.community.handleProblem(v);
        if (!mounted || name.text != v) return;
        setState(() {
          problem = p;
          free = p == null;
          checking = false;
        });
      } on RemoteError {
        if (mounted) setState(() => checking = false);
      }
    });
  }

  Future<void> _save() async {
    setState(() => busy = true);
    try {
      await context.appRead.community.setHandle(name.text);
      if (mounted) Navigator.of(context).pop(name.text.trim());
      return;
    } on HandleRefused catch (e) {
      setState(() {
        problem = e.reason;
        canChangeAt = e.canChangeAt;
        free = false;
      });
    } on RemoteError {
      setState(() => problem = 'offline');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final tt = Theme.of(context).textTheme;
    final current = s.community.handle;
    final ok = problem == null && name.text.trim().isNotEmpty && name.text.trim() != current;
    return AppScaffold(
      title: context.t('Community name', 'Jina la jamii'),
      bottom: PrimaryButton(key: const Key('handle-save'), context.t('Save this name', 'Hifadhi jina hili'), loading: busy, onPressed: ok && !busy ? _save : null),
      children: [
        AppHeader(
          context.t('Choose your community name', 'Chagua jina lako la jamii'),
          subtitle: context.t(
            'Other mothers see this name when you do not post anonymously. It does not have to be your real name.',
            'Akina mama wengine wanaona jina hili usipoandika bila jina. Halihitaji kuwa jina lako halisi.',
          ),
        ),
        TextField(
          key: const Key('handle-field'),
          controller: name,
          onChanged: _changed,
          maxLength: 20,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: context.t('Community name', 'Jina la jamii'),
            prefixText: '@',
            prefixStyle: Theme.of(context).textTheme.bodyLarge!.copyWith(color: C.ink),
            hintText: 'MamaJasiri',
            suffixIcon: checking
                ? Semantics(
                    label: context.t('Checking the name', 'Inakagua jina'),
                    child: const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
                  )
                : free
                ? const Icon(Icons.check_circle, color: C.green)
                : null,
            // the answer belongs to the field (read with it, red border) and is announced when it changes
            error: problem == null
                ? null
                : Semantics(
                    liveRegion: true,
                    child: Text(key: const Key('handle-problem'), handleProblemText(context, problem!, canChangeAt: canChangeAt), style: tt.bodyMedium!.copyWith(color: C.red)),
                  ),
            helper: free ? Semantics(liveRegion: true, child: Text(context.t('This name is free.', 'Jina hili liko wazi.'), style: tt.bodyMedium!.copyWith(color: C.green))) : null,
          ),
        ),
        const Gap(Sp.md),
        Text(context.t('Ideas', 'Mawazo'), style: tt.titleMedium),
        const Gap(Sp.sm),
        Wrap(
          spacing: Sp.sm,
          runSpacing: Sp.sm,
          children: [
            for (final i in ideas)
              ActionChip(
                label: Text('@$i'),
                onPressed: () {
                  name.text = i;
                  _changed(i);
                },
              ),
          ],
        ),
        const Gap(Sp.lg),
        AppCard(
          color: C.primarySoft,
          border: C.primary.withValues(alpha: .18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.t('Name rules', 'Kanuni za jina'), style: tt.titleMedium),
              const Gap(Sp.xs),
              for (final (en, sw) in [
                ('3 to 20 letters, numbers, _ or .', 'Herufi 3 hadi 20, namba, _ au .'),
                ('No phone numbers, no names of health workers or the app', 'Bila namba za simu, bila majina ya wahudumu au programu'),
                ('Kind words only. Each name belongs to one mother.', 'Maneno ya heshima tu. Kila jina ni la mama mmoja.'),
                ('You can change it once every 30 days.', 'Unaweza kulibadilisha mara moja kila siku 30.'),
              ])
                Padding(
                  padding: const EdgeInsets.only(top: Sp.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check, size: 18, color: C.primary),
                      const SizedBox(width: Sp.sm),
                      Expanded(child: Text(context.t(en, sw), style: tt.bodyMedium)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const Gap(Sp.md),
        Text(
          context.t(
            'You can always post as "Anonymous mother" instead: nobody sees your name or number.',
            'Unaweza pia kuandika kama "Mama asiyejulikana": hakuna anayeona jina au namba yako.',
          ),
          style: tt.bodySmall,
        ),
      ],
    );
  }
}
