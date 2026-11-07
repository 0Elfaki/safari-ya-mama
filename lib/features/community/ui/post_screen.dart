import 'package:flutter/material.dart';

import '../domain/community_check.dart';
import '../../../data/remote.dart';
import '../data/community_service.dart';
import '../../../ui/theme.dart';
import '../../../ui/widgets.dart';
import 'post_as.dart';
import 'post_card.dart';

/// One post with its replies, and a box to reply.
class PostScreen extends StatefulWidget {
  final String id;
  final CommunityPost? first;
  const PostScreen(this.id, {super.key, this.first});
  @override
  State<PostScreen> createState() => _PostScreenState();
}

class _PostScreenState extends State<PostScreen> {
  final reply = TextEditingController();
  late CommunityPost? post = widget.first;
  List<CommunityPost>? replies;
  late bool anonymous = PostAsChoice.remembered(context);
  bool busy = false, gone = false, offline = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    reply.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final t = await context.appRead.community.thread(widget.id);
      if (!mounted) return;
      setState(() {
        offline = false;
        if (t == null) {
          gone = true;
        } else {
          post = t.$1;
          replies = t.$2;
        }
      });
    } on RemoteError {
      if (mounted) setState(() => offline = true);
    }
  }

  Future<void> _send() async {
    setState(() => busy = true);
    try {
      final r = await context.appRead.community.share(reply.text, topic: post?.topic ?? 'other', parentId: widget.id, anonymous: anonymous);
      if (!mounted) return;
      reply.clear();
      showOutcome(context, r, reply: true);
      await _load();
    } on PostRefused catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.reason == 'muted'
                  ? context.t('You cannot post right now. You can still read and mark posts helpful.', 'Huwezi kuandika sasa. Bado unaweza kusoma na kuweka "imesaidia".')
                  : context.t('Choose a community name first, or reply anonymously.', 'Chagua jina la jamii kwanza, au jibu bila jina.'),
            ),
          ),
        );
      }
    } on RemoteError {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('Not sent. Check your internet.', 'Haijatumwa. Kagua intaneti.'))));
      }
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final rules = CommunityRules.loaded;
    final text = reply.text.trim();
    final check = rules == null || text.length < 3 ? null : checkText(text, rules);
    final canSend = text.length >= 2 && check?.verdict != Verdict.block && check?.verdict != Verdict.fix && !busy;
    final hint = check == null ? null : checkHint(context, check);
    final open = post != null && !post!.waiting && !gone;
    return AppScaffold(
      title: context.t('Post', 'Chapisho'),
      bottom: !open
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ?hint,
                PostAsChoice(anonymous: anonymous, compact: true, onChanged: (v) => setState(() => anonymous = v)),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('reply-body'),
                        controller: reply,
                        onChanged: (_) => setState(() {}),
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 1000,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(hintText: context.t('Write a kind reply…', 'Andika jibu la upole…'), counterText: ''),
                      ),
                    ),
                    const SizedBox(width: Sp.sm),
                    IconButton.filled(
                      key: const Key('reply-send'),
                      tooltip: context.t('Send', 'Tuma'),
                      onPressed: canSend ? _send : null,
                      icon: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
                    ),
                  ],
                ),
              ],
            ),
      children: [
        if (gone)
          EmptyState(Icons.visibility_off_outlined, context.t('This post is no longer available.', 'Chapisho hili halipatikani tena.'))
        else if (post != null) ...[
          PostCard(post!, full: true, onChanged: _load),
          const Gap(Sp.md),
          if (offline) OfflineIndicator(text: context.t('No internet. Replies will show when you are back online.', 'Hakuna intaneti. Majibu yataonekana ukirudi mtandaoni.')),
          if (replies == null && !offline)
            LoadingState(context.t('Loading replies…', 'Inapakia majibu…'))
          else if (replies != null && replies!.isEmpty)
            Text(context.t('No replies yet.', 'Bado hakuna majibu.'), style: Theme.of(context).textTheme.bodyMedium)
          else
            for (final r in replies ?? const <CommunityPost>[]) ...[PostCard(r, reply: true, full: true, onChanged: _load), const Gap(Sp.sm)],
        ] else
          LoadingState(context.t('Loading…', 'Inapakia…')),
      ],
    );
  }
}
