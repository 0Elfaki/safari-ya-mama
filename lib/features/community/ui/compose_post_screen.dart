import 'package:flutter/material.dart';

import '../domain/community_check.dart';
import '../../../data/remote.dart';
import '../../../data/voice.dart';
import '../data/community_service.dart';
import '../../../ui/theme.dart';
import '../../../ui/widgets.dart';
import '../../../core/dates.dart';
import 'community_name_screen.dart';
import 'post_as.dart';
import 'post_card.dart';

/// Share with mothers: topic, words (typed or spoken), and who others see (anonymous or her community name).
class ComposePostScreen extends StatefulWidget {
  final String? topic;
  const ComposePostScreen({super.key, this.topic});
  @override
  State<ComposePostScreen> createState() => _ComposePostScreenState();
}

class _ComposePostScreenState extends State<ComposePostScreen> {
  final body = TextEditingController();
  late String topic = widget.topic ?? (context.appRead.pregnant ? 'pregnancy' : 'baby');
  late bool anonymous = PostAsChoice.remembered(context);
  bool busy = false, listening = false;
  String? err;

  @override
  void initState() {
    super.initState();
    CommunityRules.load().then((_) => mounted ? setState(() {}) : null, onError: (_) {});
  }

  @override
  void dispose() {
    if (listening) VoiceInput.instance.stop();
    body.dispose();
    super.dispose();
  }

  Future<void> _voice() async {
    final v = VoiceInput.instance;
    if (listening) {
      await v.stop();
      if (mounted) setState(() => listening = false);
      return;
    }
    final start = body.text;
    final r = await v.start(
      context.appRead.lang,
      onWords: (w) {
        if (!mounted) return;
        body.text = start.isEmpty ? w : '$start $w';
        setState(() {});
      },
      onDone: () => mounted ? setState(() => listening = false) : null,
    );
    if (mounted) setState(() => listening = r != VoiceStart.unavailable);
  }

  Future<void> _send() async {
    setState(() {
      busy = true;
      err = null;
    });
    try {
      final r = await context.appRead.community.share(body.text, topic: topic, anonymous: anonymous);
      if (mounted) Navigator.of(context).pop(r);
    } on PostRefused catch (e) {
      if (e.reason == 'need_handle') {
        // her name was not saved on this phone yet: choose it, then she taps Share again
        if (!mounted) return;
        await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const CommunityNameScreen()));
      } else if (mounted) {
        final lang = context.appRead.lang;
        setState(
          () => err = context.t(
            'You cannot post right now because some of your posts shared wrong health information.${e.until == null ? '' : ' You can post again on ${fmtDay(e.until!, lang)}.'} You can still read and mark posts helpful.',
            'Huwezi kuandika sasa kwa sababu baadhi ya machapisho yako yalikuwa na taarifa za afya zisizo sahihi.${e.until == null ? '' : ' Utaweza kuandika tena ${fmtDay(e.until!, lang)}.'} Bado unaweza kusoma na kuweka "imesaidia".',
          ),
        );
      }
    } on RemoteError catch (e) {
      setState(
        () => err = e.status == 429
            ? context.t('You have shared a lot today. Please try again later.', 'Umeshiriki mengi leo. Tafadhali jaribu tena baadaye.')
            : context.t('Not sent. Check your internet and try again.', 'Haijatumwa. Kagua intaneti kisha ujaribu tena.'),
      );
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final rules = CommunityRules.loaded;
    final text = body.text.trim();
    final check = rules == null || text.length < 3 ? null : checkText(text, rules);
    final canSend = text.length >= 2 && check?.verdict != Verdict.block && check?.verdict != Verdict.fix;
    final hint = check == null ? null : checkHint(context, check);
    return AppScaffold(
      title: context.t('New post', 'Chapisho jipya'),
      // a refusal shows right above Share, where she is looking
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (err != null) ...[ErrorState(err!), const Gap(Sp.sm)],
          PrimaryButton(key: const Key('compose-send'), context.t('Share', 'Shiriki'), icon: Icons.send, loading: busy, onPressed: canSend && !busy ? _send : null),
        ],
      ),
      children: [
        Text(context.t('What is it about?', 'Inahusu nini?'), style: Theme.of(context).textTheme.titleMedium),
        const Gap(Sp.sm),
        Wrap(
          spacing: Sp.sm,
          runSpacing: Sp.sm,
          children: [
            for (final (id, label) in communityTopics)
              ChoiceChip(key: Key('topic-$id'), label: Text(context.tx(label)), selected: topic == id, onSelected: (_) => setState(() => topic = id)),
          ],
        ),
        const Gap(Sp.md),
        TextField(
          key: const Key('compose-body'),
          controller: body,
          onChanged: (_) => setState(() {}),
          minLines: 5,
          maxLines: 10,
          maxLength: 1000,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: context.t('Ask a question, or share what helped you…', 'Uliza swali, au shiriki kilichokusaidia…'),
            suffixIcon: VoiceInput.instance.supported
                ? IconButton(
                    tooltip: listening ? context.t('Stop listening', 'Acha kusikiliza') : context.t('Speak instead of typing', 'Ongea badala ya kuandika'),
                    onPressed: _voice,
                    icon: Icon(listening ? Icons.stop_rounded : Icons.mic_none_rounded, color: listening ? C.red : C.primary),
                  )
                : null,
          ),
        ),
        ?hint,
        const Gap(Sp.sm),
        const Gap(Sp.sm),
        PostAsChoice(anonymous: anonymous, onChanged: (v) => setState(() => anonymous = v)),
        const Gap(Sp.xs),
        Text(
          context.t('Your real name and phone number are never shown.', 'Jina lako halisi na namba ya simu hazionyeshwi kamwe.'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        TextButton(onPressed: () => showCircleRules(context), child: Text(context.t('How we keep it safe', 'Tunavyoweka usalama'))),
      ],
    );
  }
}
