import 'package:go_router/go_router.dart';

import '../../app/router.dart';

import 'package:flutter/material.dart';

import '../../core/content.dart';
import '../../core/lessons.g.dart';
import '../theme.dart';
import '../content_widgets.dart';
import '../widgets.dart';
import 'checkin_screen.dart';
import 'learn_screen.dart';

/// Health library (MA-26): picture-first lessons in 4 topics plus clinic-visit guides.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    Widget tile(Lesson l) => LessonTile(l);
    return Scaffold(
      appBar: AppBar(title: Text(context.t('All lessons', 'Masomo yote')), actions: const [EmergencyButton()]),
      body: Pad(
        children: [
          AppCard(
            color: C.primarySoft,
            border: C.primarySoft,
            child: Row(
              children: [
                ProgressRing(value: s.lessonsDone / lessons.length, big: '${s.lessonsDone}', small: '/ ${lessons.length}', size: 72),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    context.t(
                      'Lessons finished. Each one works without a signal once opened, and can be read aloud.',
                      'Masomo uliyomaliza. Kila somo linafanya kazi bila mtandao likishafunguliwa, na linaweza kusomwa kwa sauti.',
                    ),
                  ),
                ),
              ],
            ),
          ),
          SectionTitle(context.t('Next for you', 'Linalofuata kwako')),
          for (final l in s.lessonsForYou.take(3)) tile(l),
          for (final c in lessonCategories) ...[SectionTitle(context.tx(c.title)), for (final l in lessons.where((x) => x.category == c.key)) tile(l)],
          if (s.pregnant) ...[
            SectionTitle(context.t('What happens at each clinic visit', 'Kinachofanyika kila kliniki')),
            for (final (i, a) in ancContacts.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      '${context.t('Visit', 'Ziara')} ${i + 1} · ${context.t('week', 'wiki')} ${a.week}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    subtitle: Text(context.tx(a.title)),
                    children: [for (final it in a.items) ListTile(dense: true, leading: const Icon(Icons.check, size: 18), title: Text(context.tx(it)))],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// A lesson in a list: picture, title, length, done tick and quiz score.
class LessonTile extends StatelessWidget {
  final Lesson l;
  const LessonTile(this.l, {super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final q = s.quizScore(l.id), n = quizzes[l.id]?.length ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        key: Key('lesson-${l.id}'),
        padding: const EdgeInsets.all(10),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LessonScreen(l.id))),
        child: Row(
          children: [
            SizedBox(width: 96, child: ContentPicture('${l.asset}-P1', height: 72, radius: 12, fallback: Illus(l.steps.first.art, height: 72))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tx(l.title), style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    '${l.steps.length} ${context.t('steps', 'hatua')} · ${l.minutes} min${q == null ? '' : ' · ${context.t('quiz', 'maswali')} $q/$n'}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            if (s.lessonDone(l.id)) const Icon(Icons.check_circle, color: C.green),
          ],
        ),
      ),
    );
  }
}

/// One lesson: one big picture per step, listen button, own pace (illustrated guide / film / audio).
class LessonScreen extends StatefulWidget {
  final String id;
  const LessonScreen(this.id, {super.key});
  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  final page = PageController();
  int i = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.appRead.markLesson(widget.id, completed: false));
  }

  @override
  void dispose() {
    Speaker.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = lessonById(widget.id)!;
    final n = l.steps.length;
    final last = i == n - 1;
    return Scaffold(
      appBar: AppBar(title: Text(context.tx(l.title)), actions: const [EmergencyButton()]),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                for (var k = 0; k < n; k++)
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      height: 6,
                      decoration: BoxDecoration(color: k <= i ? C.primary : C.surface2, borderRadius: BorderRadius.circular(3)),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: page,
              itemCount: n,
              onPageChanged: (k) {
                setState(() => i = k);
                if (context.appRead.readAloud) Speaker.say(context.appRead.tr(l.steps[k].text), context.appRead.lang);
              },
              itemBuilder: (_, k) {
                final st = l.steps[k];
                return Pad(
                  children: [
                    if (k == 0 && l.facts.isNotEmpty) ...[_KeyFacts(l), const Gap(16)],
                    ContentPicture('${l.asset}-P${k + 1}', height: 220, fallback: const SizedBox.shrink()),
                    const Gap(24),
                    if (st.warn != null) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: StatusBadge(
                          st.warn == Level.red
                              ? context.t('Danger sign: go now', 'Dalili ya hatari: nenda sasa')
                              : context.t('Get help today', 'Pata msaada leo'),
                          color: levelColor(st.warn!),
                          icon: levelIcon(st.warn!),
                          background: levelSoft(st.warn!),
                        ),
                      ),
                      const Gap(Sp.smd),
                    ],
                    Text(context.tx(st.text), style: AppTypography.h3.copyWith(fontSize: 22)),
                    const Gap(16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        onPressed: () => Speaker.say(context.tx(st.text), context.appRead.lang),
                        icon: const Icon(Icons.volume_up),
                        label: Text(context.t('Listen', 'Sikiliza')),
                      ),
                    ),
                    if (k == n - 1) ...[const Gap(24), _GetHelp(l), _Related(l), const Gap(16), _Sources(l)],
                  ],
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  if (i > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => page.previousPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
                        child: Text(context.t('Back', 'Rudi')),
                      ),
                    ),
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      key: const Key('lesson-next'),
                      onPressed: () async {
                        if (!last) {
                          page.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
                        } else {
                          await context.appRead.markLesson(l.id, completed: true);
                          if (!context.mounted) return;
                          if (quizzes[l.id]?.isNotEmpty ?? false) {
                            Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => QuizScreen(l.id)));
                          } else {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text(context.appRead.lang == 'sw' ? 'Somo limekamilika' : 'Lesson finished')));
                            Navigator.pop(context);
                          }
                        }
                      },
                      child: Text(last ? context.t('Finish', 'Maliza') : context.t('Next', 'Endelea')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// MA-56: the lesson's key facts, shown first (before the step pictures).
class _KeyFacts extends StatelessWidget {
  final Lesson l;
  const _KeyFacts(this.l);
  @override
  Widget build(BuildContext context) {
    final facts = [for (final f in l.facts) context.tx(f)];
    return AppCard(
      key: const Key('lesson-facts'),
      color: C.primarySoft,
      border: C.primarySoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_outline, color: C.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(context.t('Key facts', 'Mambo muhimu'), style: Theme.of(context).textTheme.titleMedium)),
              ListenButton(facts.join(' ')),
            ],
          ),
          const Gap(8),
          for (final f in facts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: Icon(Icons.circle, size: 8, color: C.primary),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(f, style: Theme.of(context).textTheme.bodyLarge)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// MA-56: "When to get help" at the end of a lesson: the lesson's own warning steps (red first,
/// then amber) in the level colours used everywhere else, plus Emergency help and the daily check.
/// It repeats the lesson's approved words only; it never adds advice of its own.
class _GetHelp extends StatelessWidget {
  final Lesson l;
  const _GetHelp(this.l);
  @override
  Widget build(BuildContext context) {
    final w = l.warnings;
    final top = w.isEmpty ? null : w.first.warn!;
    return AppCard(
      key: const Key('lesson-gethelp'),
      color: top == null ? C.surface : levelSoft(top),
      border: top == null ? C.line : levelColor(top).withValues(alpha: .45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.t('When to get help', 'Wakati wa kutafuta msaada'), style: Theme.of(context).textTheme.titleMedium),
          const Gap(8),
          if (w.isEmpty)
            Text(
              context.t(
                'Notice a warning sign? Do the daily check, or open Emergency help.',
                'Umeona dalili ya onyo? Fanya uchunguzi wa kila siku, au fungua Msaada wa dharura.',
              ),
              key: const Key('lesson-gethelp-generic'),
              style: Theme.of(context).textTheme.bodyLarge,
            )
          else
            for (final (k, st) in w.indexed) _WarnRow(st, key: Key('lesson-warn-$k')),
          const Gap(12),
          FilledButton.icon(
            key: const Key('lesson-emergency'),
            style: FilledButton.styleFrom(backgroundColor: C.red, minimumSize: const Size(44, 48)),
            onPressed: () => context.push(Routes.emergency),
            icon: const Icon(Icons.emergency),
            label: Text(context.t('Emergency help', 'Msaada wa dharura')),
          ),
          const Gap(8),
          OutlinedButton.icon(
            key: const Key('lesson-check'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(44, 48)),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CheckinScreen())),
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(context.t('Do the daily check', 'Fanya uchunguzi wa kila siku')),
          ),
        ],
      ),
    );
  }
}

/// One warning step: level colour and icon (as on the check-in result) plus a word label, so colour is never the only cue.
class _WarnRow extends StatelessWidget {
  final LessonStep st;
  const _WarnRow(this.st, {super.key});
  @override
  Widget build(BuildContext context) {
    final lv = st.warn!;
    final c = levelColor(lv);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: lv == Level.amber ? C.amberFill : c, shape: BoxShape.circle),
            child: Icon(levelIcon(lv), color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lv == Level.red ? context.t('Danger sign', 'Dalili ya hatari') : context.t('Warning sign', 'Dalili ya onyo'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c),
                ),
                Text(context.tx(st.text), style: Theme.of(context).textTheme.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// MA-56: related lessons, each opening that lesson.
class _Related extends StatelessWidget {
  final Lesson l;
  const _Related(this.l);
  @override
  Widget build(BuildContext context) {
    final rel = [for (final id in l.related) ?lessonById(id)];
    if (rel.isEmpty) return const SizedBox.shrink();
    return Column(
      key: const Key('lesson-related'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [SectionTitle(context.t('Related lessons', 'Masomo yanayohusiana')), for (final r in rel) LessonTile(r)],
    );
  }
}

/// MA-56: guideline sources and the clinical review status (list collapsed by default).
class _Sources extends StatelessWidget {
  final Lesson l;
  const _Sources(this.l);
  @override
  Widget build(BuildContext context) {
    final r = l.review;
    final status = r == null
        ? context.t('Clinical review pending', 'Mapitio ya kitabibu yanasubiriwa')
        : context.t('Clinically reviewed by ${r.by} on ${r.on}', 'Imepitiwa kitabibu na ${r.by} tarehe ${r.on}');
    return AppCard(
      key: const Key('lesson-sources'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        leading: const Icon(Icons.menu_book_outlined, color: C.ink2),
        title: Text(context.t('Sources and review', 'Vyanzo na mapitio'), style: Theme.of(context).textTheme.titleSmall),
        subtitle: Text(status, key: const Key('lesson-review'), style: Theme.of(context).textTheme.bodySmall),
        children: [
          if (l.sources.isEmpty)
            ListTile(dense: true, title: Text(context.t('No sources listed yet.', 'Bado hakuna vyanzo vilivyoorodheshwa.')))
          else
            for (final x in l.sources) ListTile(dense: true, leading: const Icon(Icons.description_outlined, size: 18), title: Text(x)),
        ],
      ),
    );
  }
}
