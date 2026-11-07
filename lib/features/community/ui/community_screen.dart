import 'package:flutter/material.dart';

import '../domain/community_check.dart';
import '../../../core/content_assets.dart';
import '../../../core/tx.dart';
import '../../../data/remote.dart';
import '../data/community_service.dart';
import '../../../ui/content_widgets.dart';
import '../../../ui/theme.dart';
import '../../../ui/widgets.dart';
import '../../../core/dates.dart';
import 'community_name_screen.dart';
import 'compose_post_screen.dart';
import 'post_card.dart';
import 'post_screen.dart';

/// Mothers' circle (tab): mothers share questions and experiences. Every post is checked
/// (rules on the phone and the server, an AI second opinion, health workers, and reports from
/// mothers) so wrong or unsafe advice does not spread. See community_check.dart.
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});
  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  String? topic;
  List<CommunityPost>? posts;
  bool offline = false, loading = false;
  CommunityMe? me;

  @override
  void initState() {
    super.initState();
    CommunityRules.load().then((_) => mounted ? setState(() {}) : null, onError: (_) {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final s = context.appRead;
    if (!s.signedIn) return;
    setState(() => loading = true);
    // her name and standing (strikes); not needed to read, so a failure is ignored
    s.community.me().then((m) => mounted ? setState(() => me = m) : null, onError: (_) {});
    try {
      final r = await s.community.feed(topic: topic);
      if (mounted) {
        setState(() {
          posts = r;
          offline = false;
        });
      }
    } on RemoteError {
      final saved = s.community.cached.where((p) => topic == null || p.topic == topic).toList();
      if (mounted) {
        setState(() {
          posts = saved;
          offline = true;
        });
      }
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _share() async {
    final r = await Navigator.of(context).push<PostOutcome>(MaterialPageRoute(builder: (_) => ComposePostScreen(topic: topic)));
    if (r == null || !mounted) return;
    showOutcome(context, r, reply: false);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    if (!s.signedIn) {
      return Pad(
        children: [
          EmptyState(
            Icons.forum_outlined,
            context.t(
              'The mothers\' circle needs you to be signed in, with internet.',
              'Kikundi cha akina mama kinahitaji uwe umeingia, na uwe na intaneti.',
            ),
          ),
        ],
      );
    }
    final list = posts ?? const <CommunityPost>[];
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        key: const Key('community-feed'),
        padding: const EdgeInsets.fromLTRB(Sp.screen, Sp.sm, Sp.screen, Sp.xl),
        children: [
          AppCard(
            color: C.primarySoft,
            border: C.primary.withValues(alpha: .18),
            padding: const EdgeInsets.all(Sp.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (ContentAssets.has('COMM-HERO')) ...[
                  ContentPicture(
                    'COMM-HERO',
                    height: 140,
                    radius: R.medium,
                    fallback: const SizedBox.shrink(),
                    semanticLabel: context.t('Mothers talking together', 'Akina mama wakizungumza pamoja'),
                  ),
                  const Gap(Sp.smd),
                ],
                Text(context.t('Learn from other mothers', 'Jifunze kutoka kwa akina mama wengine'), style: AppTypography.h3),
                const Gap(Sp.xs),
                Text(
                  context.t(
                    'Ask a question or share what helped you. Health workers check posts, so the advice here is safe.',
                    'Uliza swali au shiriki kilichokusaidia. Wahudumu wa afya hukagua machapisho, ili ushauri hapa uwe salama.',
                  ),
                  style: AppTypography.bodyText,
                ),
                Wrap(
                  children: [
                    TextButton(
                      key: const Key('community-rules'),
                      onPressed: () => showCircleRules(context),
                      child: Text(context.t('How we keep it safe', 'Tunavyoweka usalama')),
                    ),
                    TextButton(
                      key: const Key('community-name'),
                      onPressed: () async {
                        await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const CommunityNameScreen()));
                        if (mounted) setState(() {});
                      },
                      child: Text(
                        s.community.handle == null ? context.t('Choose a community name', 'Chagua jina la jamii') : context.t('My name: @${s.community.handle}', 'Jina langu: @${s.community.handle}'),
                      ),
                    ),
                  ],
                ),
                PrimaryButton(key: const Key('community-share'), context.t('Share with mothers', 'Shiriki na akina mama'), icon: Icons.edit_outlined, onPressed: _share),
              ],
            ),
          ),
          const Gap(Sp.md),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final (id, label) in [(null, const Tx('All', 'Yote')), ...communityTopics])
                  Padding(
                    padding: const EdgeInsets.only(right: Sp.sm),
                    child: ChoiceChip(
                      key: Key('filter-${id ?? 'all'}'),
                      label: Text(context.tx(label)),
                      selected: topic == id,
                      onSelected: (_) {
                        setState(() => topic = id);
                        _refresh();
                      },
                    ),
                  ),
              ],
            ),
          ),
          const Gap(Sp.sm),
          if (me?.mutedUntil != null || me?.reviewUntil != null) ...[
            HealthCard(
              key: const Key('community-standing'),
              tone: C.amber,
              background: C.amberSoft,
              child: Text(
                me!.mutedUntil != null
                    ? context.t(
                        'Some of your posts shared wrong health information, so you cannot post until ${fmtDay(me!.mutedUntil!, 'en')}. You can still read and mark posts helpful.',
                        'Baadhi ya machapisho yako yalikuwa na taarifa za afya zisizo sahihi, hivyo huwezi kuandika hadi ${fmtDay(me!.mutedUntil!, 'sw')}. Bado unaweza kusoma na kuweka "imesaidia".',
                      )
                    : context.t(
                        'A health worker checks your posts before others see them, until ${fmtDay(me!.reviewUntil!, 'en')}, because some shared wrong health information.',
                        'Mhudumu wa afya anakagua machapisho yako kabla wengine hawajayaona, hadi ${fmtDay(me!.reviewUntil!, 'sw')}, kwa sababu baadhi yalikuwa na taarifa zisizo sahihi.',
                      ),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const Gap(Sp.sm),
          ],
          if (offline) ...[
            OfflineIndicator(text: context.t('No internet. Showing posts saved on this phone.', 'Hakuna intaneti. Unaona machapisho yaliyohifadhiwa kwenye simu hii.')),
            const Gap(Sp.sm),
          ],
          if (posts == null && loading)
            LoadingState(context.t('Loading posts…', 'Inapakia machapisho…'))
          else if (list.isEmpty)
            EmptyState(Icons.forum_outlined, context.t('No posts here yet. Be the first to share.', 'Bado hakuna machapisho hapa. Kuwa wa kwanza kushiriki.'))
          else
            for (final p in list) ...[
              PostCard(
                p,
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostScreen(p.id, first: p)));
                  _refresh();
                },
                onChanged: _refresh,
              ),
              const Gap(Sp.smd),
            ],
        ],
      ),
    );
  }
}
