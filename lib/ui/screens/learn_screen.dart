import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../core/content_assets.dart';
import '../../core/lessons.g.dart';
import '../../core/tx.dart';
import '../theme.dart';
import '../widgets.dart';
import 'body_check_screen.dart';
import 'first_aid_screen.dart';
import 'library_screen.dart';

/// Learn tab (MA-51): lessons with pictures, quizzes, first aid, the body self-check and videos.
/// Pictures and videos from the content kit appear here as soon as they are imported.
class LearnScreen extends StatefulWidget {
  const LearnScreen({super.key});
  @override
  State<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends State<LearnScreen> {
  final search = TextEditingController();
  String q = '';
  String? cat;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  bool _matches(Lesson l) {
    final t = q.trim().toLowerCase();
    if (t.isEmpty) return true;
    final hay = [
      l.title.en,
      l.title.sw,
      for (final st in l.steps) ...[st.text.en, st.text.sw],
    ].join(' ').toLowerCase();
    return t.split(RegExp(r'\s+')).every(hay.contains);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    void go(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    final videos = ContentAssets.ofType('video');
    final quizDone = lessons.where((l) => s.quizScore(l.id) != null).length;
    final filtering = q.trim().isNotEmpty || cat != null;
    final found = lessons.where((l) => (cat == null || l.category == cat) && _matches(l)).toList();
    final header = <Widget>[
      AppSearchField(
        fieldKey: const Key('learn-search'),
        controller: search,
        hint: context.t('Search health topics', 'Tafuta mada za afya'),
        onChanged: (v) => setState(() => q = v),
      ),
      const Gap(Sp.smd),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: Sp.sm),
              child: ChoiceChip(label: Text(context.t('All', 'Yote')), selected: cat == null, onSelected: (_) => setState(() => cat = null)),
            ),
            for (final c in lessonCategories)
              Padding(
                padding: const EdgeInsets.only(right: Sp.sm),
                child: ChoiceChip(
                  key: Key('learn-cat-${c.key}'),
                  label: Text(context.tx(c.title)),
                  selected: cat == c.key,
                  onSelected: (on) => setState(() => cat = on ? c.key : null),
                ),
              ),
          ],
        ),
      ),
      const Gap(Sp.md),
    ];
    if (filtering) {
      return Pad(
        children: [
          ...header,
          Text(context.t('${found.length} lessons', 'Masomo ${found.length}'), style: Theme.of(context).textTheme.labelSmall),
          const Gap(Sp.sm),
          if (found.isEmpty)
            EmptyState(
              Icons.search_off,
              context.t('No lesson matches. Try another word, or ask MamaBot.', 'Hakuna somo linalolingana. Jaribu neno jingine, au uliza MamaBot.'),
            ),
          for (final l in found) LessonTile(l),
        ],
      );
    }
    return Pad(
      children: [
        ...header,
        AppCard(
          key: const Key('learn-cover'),
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.asset('assets/learn/cover.jpg', height: 170, fit: BoxFit.cover),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    ProgressRing(value: s.lessonsDone / lessons.length, big: '${s.lessonsDone}', small: '/ ${lessons.length}', size: 72),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.t('Short lessons for you and your baby', 'Masomo mafupi kwako na kwa mtoto'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const Gap(4),
                          Text(
                            context.t(
                              'Lessons finished · $quizDone quizzes done. Works without a signal.',
                              'Masomo uliyomaliza · maswali $quizDone. Inafanya kazi bila mtandao.',
                            ),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Gap(12),
        TileGrid(
          children: [
            ActionTile(
              key: const Key('learn-first-aid'),
              icon: Icons.health_and_safety_outlined,
              tint: C.red,
              label: context.t('First aid', 'Huduma ya kwanza'),
              sub: context.t('Choking, CPR, fits, burns', 'Kukabwa, CPR, degedege, kuungua'),
              onTap: () => go(const FirstAidHubScreen()),
            ),
            ActionTile(
              key: const Key('learn-body-check'),
              icon: Icons.accessibility_new,
              label: context.t('Body check', 'Jichunguze'),
              sub: context.t('Tap where it hurts', 'Gusa panapouma'),
              onTap: () => go(const BodyCheckScreen()),
            ),
          ],
        ),
        if (!s.pregnant) ...[
          const Gap(12),
          AppCard(
            child: Row2(
              icon: Icons.visibility_outlined,
              tint: C.amber,
              title: context.t('Spot the signs', 'Tambua dalili'),
              sub: context.t('How to look for each sign in the daily check', 'Jinsi ya kutambua kila dalili ya ukaguzi'),
              onTap: () => go(const FirstAidHubScreen(initialTab: 1)),
            ),
          ),
        ],
        SectionTitle(context.t('Next for you', 'Linalofuata kwako')),
        for (final l in s.lessonsForYou.take(3)) LessonTile(l),
        SectionTitle(context.t('Videos', 'Video')),
        if (videos.isEmpty)
          EmptyNote(
            Icons.ondemand_video_outlined,
            context.t(
              'Short videos are being made with health workers and will appear here.',
              'Video fupi zinatengenezwa pamoja na wahudumu wa afya na zitaonekana hapa.',
            ),
          )
        else
          for (final v in videos)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                key: Key('video-${v.id}'),
                child: Row2(
                  icon: Icons.play_circle_outline,
                  title: context.tx(videoTitles[v.id] ?? Tx(v.id, v.id)),
                  sub: context.t('Needs a signal to play', 'Inahitaji mtandao kucheza'),
                  onTap: () => go(VideoScreen(v)),
                ),
              ),
            ),
        for (final c in lessonCategories) ...[SectionTitle(context.tx(c.title)), for (final l in lessons.where((x) => x.category == c.key)) LessonTile(l)],
      ],
    );
  }
}

class QuizScreen extends StatefulWidget {
  final String lessonId;
  const QuizScreen(this.lessonId, {super.key});
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  int i = 0, right = 0;
  int? picked;

  @override
  Widget build(BuildContext context) {
    final qs = quizzes[widget.lessonId] ?? const <QuizQ>[];
    final l = lessonById(widget.lessonId)!;
    final done = i >= qs.length;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('Quick questions', 'Maswali mafupi')), actions: const [EmergencyButton()]),
      body: Pad(
        children: [
          Text(context.tx(l.title), style: Theme.of(context).textTheme.bodyMedium),
          const Gap(8),
          if (done) ...[
            AppCard(
              key: const Key('quiz-result'),
              color: C.primarySoft,
              border: C.primarySoft,
              child: Column(
                children: [
                  ProgressRing(value: qs.isEmpty ? 1 : right / qs.length, big: '$right', small: '/ ${qs.length}', size: 96),
                  const Gap(12),
                  Text(
                    right == qs.length
                        ? context.t('Well done. You know the key points.', 'Hongera. Unajua mambo muhimu.')
                        : context.t('Good try. Read the lesson again any time.', 'Jaribio zuri. Soma somo tena wakati wowote.'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            const Gap(16),
            FilledButton(key: const Key('quiz-done'), onPressed: () => Navigator.pop(context), child: Text(context.t('Done', 'Nimemaliza'))),
          ] else ...[
            Text('${i + 1} / ${qs.length}', style: Theme.of(context).textTheme.labelLarge),
            const Gap(4),
            Text(context.tx(qs[i].q), style: Theme.of(context).textTheme.titleLarge),
            const Gap(16),
            for (final (k, o) in qs[i].options.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  key: Key('quiz-opt-$k'),
                  onTap: picked != null
                      ? null
                      : () => setState(() {
                          picked = k;
                          if (k == qs[i].answer) right++;
                        }),
                  color: picked == null
                      ? null
                      : k == qs[i].answer
                      ? C.greenSoft
                      : (k == picked ? C.redSoft : null),
                  child: Row(
                    children: [
                      Icon(
                        picked == null
                            ? Icons.radio_button_unchecked
                            : k == qs[i].answer
                            ? Icons.check_circle
                            : (k == picked ? Icons.cancel : Icons.radio_button_unchecked),
                        color: picked == null
                            ? C.ink3
                            : k == qs[i].answer
                            ? C.green
                            : C.red,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(context.tx(o), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ),
            if (picked != null) ...[
              const Gap(8),
              Text(context.tx(qs[i].why), style: Theme.of(context).textTheme.bodyLarge),
              const Gap(16),
              FilledButton(
                key: const Key('quiz-next'),
                onPressed: () async {
                  final last = i == qs.length - 1;
                  setState(() {
                    i++;
                    picked = null;
                  });
                  if (last) await context.appRead.saveQuiz(widget.lessonId, right);
                },
                child: Text(i == qs.length - 1 ? context.t('See my result', 'Ona matokeo') : context.t('Next', 'Endelea')),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// A content-kit video. Streams from the content store; captions are offered as files.
class VideoScreen extends StatefulWidget {
  final ContentAsset video;
  const VideoScreen(this.video, {super.key});
  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  VideoPlayerController? v;
  String? err;

  @override
  void initState() {
    super.initState();
    final url = widget.video.url;
    if (url == null || url.isEmpty) {
      err = 'no-url';
      return;
    }
    v = VideoPlayerController.networkUrl(Uri.parse(url))
      ..initialize().then((_) => setState(() {})).catchError((Object e) {
        if (mounted) setState(() => err = '$e');
      });
  }

  @override
  void dispose() {
    v?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = v;
    return Scaffold(
      appBar: AppBar(title: Text(context.tx(videoTitles[widget.video.id] ?? Tx(widget.video.id, widget.video.id))), actions: const [EmergencyButton()]),
      body: Pad(
        children: [
          if (err != null)
            EmptyNote(Icons.wifi_off, context.t('This video needs a signal. Try again later.', 'Video hii inahitaji mtandao. Jaribu tena baadaye.'))
          else if (c == null || !c.value.isInitialized)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)),
            ),
            const Gap(12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  iconSize: 36,
                  onPressed: () => setState(() => c.value.isPlaying ? c.pause() : c.play()),
                  icon: Icon(c.value.isPlaying ? Icons.pause : Icons.play_arrow),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
