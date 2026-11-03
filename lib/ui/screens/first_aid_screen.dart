import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/content.dart';
import '../../core/first_aid.dart';
import '../theme.dart';
import '../../core/content_assets.dart';
import '../content_widgets.dart';
import '../widgets.dart';

/// Keep baby safe (MA-50): animated first aid and a picture guide to the daily-check signs.
/// Works offline: all pictures ship with the app.
class FirstAidHubScreen extends StatelessWidget {
  /// 0 = first aid, 1 = spot the signs
  final int initialTab;
  const FirstAidHubScreen({super.key, this.initialTab = 0});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    initialIndex: initialTab,
    child: Scaffold(
      appBar: AppBar(
        title: Text(context.t('Keep baby safe', 'Mlinde mtoto')),
        actions: const [EmergencyButton()],
        bottom: TabBar(
          tabs: [
            Tab(key: const Key('tab-first-aid'), text: context.t('First aid', 'Huduma ya kwanza')),
            Tab(key: const Key('tab-signs'), text: context.t('Spot the signs', 'Tambua dalili')),
          ],
        ),
      ),
      body: const TabBarView(children: [_FirstAidList(), SignGuideList()]),
    ),
  );
}

IconData aidIcon(String k) => switch (k) {
  'choke' => Icons.no_food_outlined,
  'heart' => Icons.monitor_heart_outlined,
  'bolt' => Icons.bolt,
  'thermo' => Icons.thermostat,
  'drop' => Icons.water_drop_outlined,
  'fire' => Icons.local_fire_department_outlined,
  'fall' => Icons.airline_seat_flat_angled,
  _ => Icons.health_and_safety_outlined,
};

class _FirstAidList extends StatelessWidget {
  const _FirstAidList();
  @override
  Widget build(BuildContext context) => Pad(
    children: [
      AppCard(
        color: C.redSoft,
        border: C.red.withValues(alpha: .3),
        child: Text(
          context.t(
            'In an emergency, shout for help and call 112 first. Then follow the steps.',
            'Wakati wa dharura, piga kelele kuomba msaada na piga 112 kwanza. Kisha fuata hatua.',
          ),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      const Gap(12),
      for (final t in firstAidTopics)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AppCard(
            key: Key('aid-${t.id}'),
            child: Row2(
              icon: aidIcon(t.icon),
              tint: C.red,
              title: context.tx(t.title),
              sub: context.tx(t.when),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FirstAidTopicScreen(t))),
            ),
          ),
        ),
      const Gap(8),
      Text(
        context.t(
          'Practise these steps with a trainer or at your clinic. Reading is not the same as practice.',
          'Jifunze hatua hizi kwa vitendo na mkufunzi au kliniki. Kusoma si sawa na kufanya mazoezi.',
        ),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    ],
  );
}

class FirstAidTopicScreen extends StatelessWidget {
  final AidTopic topic;
  const FirstAidTopicScreen(this.topic, {super.key});
  @override
  Widget build(BuildContext context) {
    final t = topic;
    final all = [
      context.tx(t.when),
      for (final st in t.steps) '${context.tx(st.title)}. ${context.tx(st.text)}',
      if (t.goNow != null) context.tx(t.goNow!),
    ].join(' ');
    return Scaffold(
      appBar: AppBar(title: Text(context.tx(t.title)), actions: const [EmergencyButton()]),
      body: Pad(
        children: [
          Row(
            children: [
              Expanded(child: Text(context.tx(t.when), style: Theme.of(context).textTheme.bodyLarge)),
              ListenButton(all),
            ],
          ),
          const Gap(12),
          if (aidTopAsset[t.id] != null) ...[ContentPicture(aidTopAsset[t.id]!, fallback: const SizedBox.shrink()), const Gap(12)],
          for (final (i, st) in t.steps.indexed) ...[
            AppCard(
              key: Key('aid-step-$i'),
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (st.anim != null) AnimatedLesson(st.anim!, count: st.count),
                  for (final id in (aidStepAssets[t.id] ?? const <List<String>>[]).elementAtOrNull(i) ?? const <String>[])
                    ContentPicture(id, radius: 0, fallback: const SizedBox.shrink()),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 15,
                              backgroundColor: C.primary,
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(context.tx(st.title), style: Theme.of(context).textTheme.titleLarge)),
                          ],
                        ),
                        const Gap(8),
                        Text(context.tx(st.text), style: Theme.of(context).textTheme.bodyLarge),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Gap(12),
          ],
          if (t.goNow != null && aidGoNowAsset[t.id] != null) ...[ContentPicture(aidGoNowAsset[t.id]!, fallback: const SizedBox.shrink()), const Gap(8)],
          if (t.goNow != null)
            AppCard(
              color: C.redSoft,
              border: C.red.withValues(alpha: .3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.emergency, color: C.red),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(context.tx(t.goNow!), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The daily-check signs, grouped by colour, each with how to look for it.
class SignGuideList extends StatelessWidget {
  const SignGuideList({super.key});
  @override
  Widget build(BuildContext context) {
    Level lv(SignGuide g) => g.sign.ageDependent ? Level.red : g.sign.level;
    Widget group(Level l, String title) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(title),
        for (final g in signGuides.where((g) => lv(g) == l))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              key: Key('guide-${g.key}'),
              padding: EdgeInsets.zero,
              border: levelColor(l).withValues(alpha: .35),
              child: ExpansionTile(
                initiallyExpanded: g.anim != null,
                leading: Icon(g.sign.icon, color: levelColor(l)),
                title: Text(context.tx(g.sign.label), style: Theme.of(context).textTheme.titleMedium),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (g.anim != null) ClipRRect(borderRadius: BorderRadius.circular(14), child: AnimatedLesson(g.anim!)),
                  for (final id in signGuideAssets[g.key] ?? const <String>[])
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: ContentPicture(id, fallback: const SizedBox.shrink()),
                    ),
                  const Gap(8),
                  Text(context.tx(g.how), style: Theme.of(context).textTheme.bodyLarge),
                ],
              ),
            ),
          ),
      ],
    );
    return Pad(
      children: [
        Text(
          context.t(
            'How to look for each sign in the daily check. The colour shows what to do.',
            'Jinsi ya kutambua kila dalili ya ukaguzi wa kila siku. Rangi inaonyesha cha kufanya.',
          ),
        ),
        group(Level.red, context.t('Red: go to a facility now', 'Nyekundu: nenda kituoni sasa')),
        group(Level.amber, context.t('Orange: a health worker within 24 hours', 'Machungwa: mhudumu wa afya ndani ya saa 24')),
        group(Level.green, context.t('Green: everyday things, care at home and watch', 'Kijani: mambo ya kawaida, tunza nyumbani na angalia')),
        const Gap(8),
        Text(
          context.t(
            'Fever is red under 2 months and orange from 2 months. Four or more green signs on the same day: see a health worker within 24 hours.',
            'Homa ni nyekundu chini ya miezi 2 na machungwa kuanzia miezi 2. Dalili nne au zaidi za kijani siku moja: muone mhudumu wa afya ndani ya saa 24.',
          ),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

/// A looping lesson animation made of picture layers (assets/learn/*.png, 800×600 art
/// units). Offsets are in art units and scale with the picture. Reduced motion shows the
/// key frame still.
class AnimatedLesson extends StatefulWidget {
  final LessonAnim anim;
  final int count;
  const AnimatedLesson(this.anim, {super.key, this.count = 0});
  @override
  State<AnimatedLesson> createState() => _AnimatedLessonState();
}

class _AnimatedLessonState extends State<AnimatedLesson> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(
    vsync: this,
    duration: widget.anim == LessonAnim.pressTest ? const Duration(milliseconds: 3200) : const Duration(milliseconds: 1100),
  );
  int beat = 1;
  double _last = 0;

  @override
  void initState() {
    super.initState();
    c.addListener(() {
      if (c.value < _last && widget.count > 0) setState(() => beat = beat % widget.count + 1);
      _last = c.value;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      c.stop();
      c.value = widget.anim == LessonAnim.pressTest ? .8 : .5;
    } else if (!c.isAnimating) {
      c.repeat();
    }
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  // 0 → 1 → 0 with a hold at contact
  static double _strike(double t) => t < .45
      ? Curves.easeIn.transform(t / .45)
      : t < .55
      ? 1
      : 1 - Curves.easeOut.transform((t - .55) / .45);
  static double _window(double t, double a, double b, double c2, double d) => t < a
      ? 0
      : t < b
      ? (t - a) / (b - a)
      : t < c2
      ? 1
      : t < d
      ? 1 - (t - c2) / (d - c2)
      : 0;

  @override
  Widget build(BuildContext context) {
    final (base, label) = switch (widget.anim) {
      LessonAnim.backBlows => ('choke_back', context.t('Back blows between the shoulder blades', 'Mapigo mgongoni katikati ya mabega')),
      LessonAnim.chestPushes => ('choke_chest', context.t('Two fingers push on the centre of the chest', 'Vidole viwili vinasukuma katikati ya kifua')),
      LessonAnim.pressTest => ('jaundice', context.t('Press the forehead, lift, look for yellow', 'Bonyeza paji la uso, inua, angalia njano')),
    };
    // a delivered content-kit animation replaces the built-in drawing; the counter stays
    final delivered = ContentAssets.get(animAsset[widget.anim]!);
    if (delivered != null) {
      return Semantics(
        image: true,
        label: label,
        child: Stack(
          children: [
            ContentPicture(delivered.id, radius: 0, fallback: const SizedBox.shrink()),
            if (widget.count > 0)
              Positioned(
                left: 12,
                top: 12,
                child: AnimatedBuilder(
                  animation: c,
                  builder: (_, _) => Container(
                    key: const Key('anim-count'),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(14)),
                    child: Text(
                      '$beat / ${widget.count}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return Semantics(
      image: true,
      label: label,
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: LayoutBuilder(
          builder: (context, box) {
            final k = box.maxWidth / 800;
            Widget layer(String name, {Offset off = Offset.zero, double opacity = 1}) => Positioned.fill(
              child: Opacity(
                opacity: opacity.clamp(0, 1),
                child: Transform.translate(
                  offset: off * k,
                  child: Image.asset('assets/learn/$name.png', fit: BoxFit.fill, gaplessPlayback: true),
                ),
              ),
            );
            return AnimatedBuilder(
              animation: c,
              builder: (context, _) {
                final t = c.value;
                final layers = switch (widget.anim) {
                  LessonAnim.backBlows => [
                    layer('choke_back_base'),
                    layer('choke_back_strike', off: Offset(0, -34 * (1 - _strike(t)))),
                    layer('choke_back_impact', opacity: _window(t, .44, .48, .58, .66)),
                  ],
                  LessonAnim.chestPushes => [
                    layer('choke_chest_base'),
                    layer('choke_chest_press', off: Offset(0, -22 * (.5 + .5 * math.cos(2 * math.pi * t)))),
                  ],
                  LessonAnim.pressTest => [
                    layer('jaundice_base'),
                    layer('jaundice_blanchSpot', opacity: _window(t, .62, .72, .92, 1)),
                    layer('jaundice_finger', off: const Offset(40, -24) * (1 - _window(t, .15, .3, .6, .75))),
                  ],
                };
                return Stack(
                  children: [
                    ...layers,
                    if (widget.count > 0)
                      Positioned(
                        left: 12,
                        top: 12,
                        child: Container(
                          key: const Key('anim-count'),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(14)),
                          child: Text(
                            '$beat / ${widget.count}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
