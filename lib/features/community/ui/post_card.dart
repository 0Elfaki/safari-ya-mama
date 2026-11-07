import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../domain/community_check.dart';
import '../../../core/tx.dart';
import '../../../data/remote.dart';
import '../data/community_service.dart';
import '../../../ui/theme.dart';
import '../../../ui/widgets.dart';

/// What happens to her post, in plain words.
void showOutcome(BuildContext context, PostOutcome r, {required bool reply}) {
  final text = switch (r.status) {
    'published' => reply ? context.t('Reply shared. Thank you!', 'Jibu limeshirikiwa. Asante!') : context.t('Shared. Thank you!', 'Imeshirikiwa. Asante!'),
    'blocked' => context.t(
      'Not shared. Please write kindly to other mothers.',
      'Haijashirikiwa. Tafadhali andika kwa upole kwa akina mama wengine.',
    ),
    _ => context.t(
      'Thank you. A health worker will check it soon. Until then only you can see it.',
      'Asante. Mhudumu wa afya ataikagua hivi karibuni. Hadi hapo ni wewe tu unayeiona.',
    ),
  };
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

void showCircleRules(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (c) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.t('How we keep the circle safe', 'Tunavyoweka kikundi salama'), style: AppTypography.h3),
          const Gap(Sp.smd),
          for (final (icon, en, sw) in [
            (Icons.fact_check_outlined, 'Every post is checked for wrong health advice before others see it.', 'Kila chapisho hukaguliwa kama lina ushauri mbaya wa afya kabla wengine hawajaliona.'),
            (Icons.health_and_safety_outlined, 'Health workers read posts, add notes and remove unsafe advice.', 'Wahudumu wa afya husoma machapisho, huongeza maelezo na kuondoa ushauri usio salama.'),
            (Icons.flag_outlined, 'If something looks wrong, tap ⋮ and report it. Three reports hide a post.', 'Ukiona kitu si sawa, gusa ⋮ uripoti. Ripoti tatu huficha chapisho.'),
            (Icons.lock_outline, 'Others see only your first name if you choose. Never share phone numbers.', 'Wengine wanaona jina lako la kwanza tu ukichagua. Usishiriki namba za simu.'),
            (Icons.emergency_outlined, 'In an emergency do not wait for answers here: open Emergency help.', 'Wakati wa dharura usisubiri majibu hapa: fungua Msaada wa dharura.'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.smd),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: C.primary),
                  const SizedBox(width: Sp.smd),
                  Expanded(child: Text(c.t(en, sw), style: AppTypography.bodyText)),
                ],
              ),
            ),
        ],
      ),
    ),
  ),
);

String _ago(BuildContext c, DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return c.t('just now', 'sasa hivi');
  if (d.inMinutes < 60) return c.t('${d.inMinutes} min ago', 'dakika ${d.inMinutes} zilizopita');
  if (d.inHours < 24) return c.t('${d.inHours} h ago', 'saa ${d.inHours} zilizopita');
  return c.t('${d.inDays} d ago', 'siku ${d.inDays} zilizopita');
}

/// One post or reply, with its checks: waiting for a health worker, checked facts, a health
/// worker's note, and the "danger sign" card for her own urgent post.
class PostCard extends StatelessWidget {
  final CommunityPost p;
  final VoidCallback? onTap, onChanged;
  final bool full, reply;
  const PostCard(this.p, {super.key, this.onTap, this.onChanged, this.full = false, this.reply = false});

  Future<void> _report(BuildContext context) async {
    final s = context.appRead;
    final reason = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
              child: Text(c.t('What is wrong with this post?', 'Chapisho hili lina tatizo gani?'), style: AppTypography.h3),
            ),
            for (final (id, en, sw) in [
              ('wrong', 'Wrong or unsafe health advice', 'Ushauri wa afya usio sahihi au hatari'),
              ('unkind', 'Unkind or rude', 'Si wa upole au ni matusi'),
              ('selling', 'Selling something', 'Anauza kitu'),
              ('private', 'Shares private details', 'Inaweka taarifa binafsi'),
              ('other', 'Something else', 'Kitu kingine'),
            ])
              ListTile(key: Key('report-$id'), title: Text(c.t(en, sw)), onTap: () => Navigator.pop(c, id)),
          ],
        ),
      ),
    );
    if (reason == null || !context.mounted) return;
    try {
      await s.community.report(p.id, reason);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t('Thank you. A health worker will look at it.', 'Asante. Mhudumu wa afya ataliangalia.'))),
        );
      }
    } on RemoteError {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('No internet. Try again later.', 'Hakuna intaneti. Jaribu tena baadaye.'))));
      }
    }
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(c.t('Delete this post?', 'Futa chapisho hili?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(c.t('Keep', 'Acha'))),
          TextButton(key: const Key('confirm-delete'), onPressed: () => Navigator.pop(c, true), child: Text(c.t('Delete', 'Futa'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await context.appRead.community.delete(p.id);
      onChanged?.call();
    } on RemoteError {
      // offline: nothing changed
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final tt = Theme.of(context).textTheme;
    final rules = CommunityRules.loaded;
    return AppCard(
      key: Key('post-${p.id}'),
      onTap: onTap,
      color: reply ? C.surface2 : null,
      padding: const EdgeInsets.all(Sp.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: p.staffPost ? C.primary : C.primarySoft,
                child: Icon(p.staffPost ? Icons.medical_services_outlined : Icons.person_outline, size: 20, color: p.staffPost ? Colors.white : C.primary),
              ),
              const SizedBox(width: Sp.smd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tx(p.byline), style: tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      reply ? _ago(context, p.createdAt) : '${_ago(context, p.createdAt)} · ${context.tx(topicLabel(p.topic))}',
                      style: tt.bodySmall,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                key: Key('post-menu-${p.id}'),
                tooltip: context.t('More', 'Zaidi'),
                onSelected: (v) => v == 'delete' ? _delete(context) : _report(context),
                itemBuilder: (c) => [
                  if (p.mine)
                    PopupMenuItem(value: 'delete', child: Text(c.t('Delete my post', 'Futa chapisho langu')))
                  else
                    PopupMenuItem(value: 'report', child: Text(c.t('Report', 'Ripoti'))),
                ],
              ),
            ],
          ),
          const Gap(Sp.sm),
          Text(p.body, style: tt.bodyLarge, maxLines: full ? null : 6, overflow: full ? null : TextOverflow.ellipsis),
          if (p.waiting) ...[
            const Gap(Sp.sm),
            StatusBadge(
              context.t('Waiting for a health worker to check · only you can see it', 'Inasubiri mhudumu wa afya · ni wewe tu unayeiona'),
              color: C.amber,
              icon: Icons.hourglass_top_rounded,
            ),
          ],
          if (p.urgent && p.mine) ...[
            const Gap(Sp.sm),
            HealthCard(
              tone: C.red,
              background: C.redSoft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.t('This may be a danger sign. Do not wait for answers here.', 'Hii inaweza kuwa dalili ya hatari. Usisubiri majibu hapa.'),
                    style: tt.titleSmall!.copyWith(color: C.red),
                  ),
                  const Gap(Sp.sm),
                  DangerButton(context.t('Get help now', 'Pata msaada sasa'), icon: Icons.emergency, onPressed: () => context.push(Routes.emergency)),
                ],
              ),
            ),
          ],
          if (rules != null)
            for (final id in p.facts)
              if (rules.myth(id) case final m?) ...[const Gap(Sp.sm), FactCard(m.fact)],
          if (p.healthNote != null && p.healthNote!.isNotEmpty) ...[
            const Gap(Sp.sm),
            AppCard(
              color: C.greenSoft,
              border: C.green.withValues(alpha: .25),
              padding: const EdgeInsets.all(Sp.smd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.t('Health worker note', 'Maelezo ya mhudumu wa afya'), style: tt.labelLarge!.copyWith(color: C.green)),
                  const Gap(Sp.xs),
                  Text(p.healthNote!, style: tt.bodyMedium),
                ],
              ),
            ),
          ],
          if (p.checked && !p.waiting && !p.staffPost) ...[
            const Gap(Sp.sm),
            StatusBadge(context.t('Checked by a health worker', 'Imekaguliwa na mhudumu wa afya'), color: C.green, icon: Icons.verified_outlined),
          ],
          if (!p.waiting) ...[
            const Gap(Sp.xs),
            Wrap(
              children: [
                TextButton.icon(
                  key: Key('helpful-${p.id}'),
                  onPressed: p.mine
                      ? null
                      : () async {
                          try {
                            await s.community.toggleHelpful(p.id);
                            onChanged?.call();
                          } on RemoteError {
                            // offline: nothing changed
                          }
                        },
                  icon: Icon(p.helped ? Icons.favorite : Icons.favorite_border, size: 20),
                  label: Text(context.t('Helpful · ${p.helpfulCount}', 'Imesaidia · ${p.helpfulCount}')),
                ),
                if (!reply)
                  TextButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.chat_bubble_outline, size: 20),
                    label: Text(context.t('Replies · ${p.replyCount}', 'Majibu · ${p.replyCount}')),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A checked fact attached to a post about a common myth.
class FactCard extends StatelessWidget {
  final Tx fact;
  const FactCard(this.fact, {super.key});
  @override
  Widget build(BuildContext context) => AppCard(
    key: const Key('fact-card'),
    color: C.primarySoft,
    border: C.primary.withValues(alpha: .2),
    padding: const EdgeInsets.all(Sp.smd),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.fact_check_outlined, color: C.primary),
        const SizedBox(width: Sp.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.t('Checked fact', 'Ukweli uliohakikiwa'), style: Theme.of(context).textTheme.labelLarge!.copyWith(color: C.primary)),
              const Gap(Sp.xs),
              Text(context.tx(fact), style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Hints while she writes, from the same rules the server uses. Returns null when all is fine.
Widget? checkHint(BuildContext context, CommunityCheck c) {
  final rules = CommunityRules.loaded;
  Widget card(Color tone, Color bg, IconData icon, String text, {Widget? extra}) => Padding(
    padding: const EdgeInsets.only(top: Sp.sm),
    child: HealthCard(
      tone: tone,
      background: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: tone),
              const SizedBox(width: Sp.sm),
              Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
            ],
          ),
          ?extra,
        ],
      ),
    ),
  );
  final out = <Widget>[];
  if (c.urgent) {
    out.add(
      card(
        C.red,
        C.redSoft,
        Icons.emergency,
        context.t(
          'This sounds like a danger sign. Get help now. Do not wait for answers here.',
          'Hii inaonekana kama dalili ya hatari. Pata msaada sasa. Usisubiri majibu hapa.',
        ),
        extra: Padding(
          padding: const EdgeInsets.only(top: Sp.sm),
          child: DangerButton(key: const Key('compose-emergency'), context.t('Get help now', 'Pata msaada sasa'), icon: Icons.emergency, onPressed: () => context.push(Routes.emergency)),
        ),
      ),
    );
  }
  switch (c.verdict) {
    case Verdict.block:
      out.add(card(C.red, C.redSoft, Icons.block, context.t('Please write kindly. Posts with insults are not shared.', 'Tafadhali andika kwa upole. Machapisho yenye matusi hayashirikiwi.')));
    case Verdict.fix:
      out.add(
        card(
          C.red,
          C.redSoft,
          Icons.lock_outline,
          context.t(
            'Please remove phone numbers and email addresses. Keep your contacts safe.',
            'Tafadhali ondoa namba za simu na barua pepe. Linda mawasiliano yako.',
          ),
        ),
      );
    case Verdict.review when !c.urgent:
      out.add(
        card(
          C.amber,
          C.amberSoft,
          Icons.hourglass_top_rounded,
          context.t(
            'A health worker will check this before other mothers see it.',
            'Mhudumu wa afya atakagua hili kabla akina mama wengine hawajaliona.',
          ),
        ),
      );
    default:
      break;
  }
  if (rules != null) {
    for (final id in c.facts) {
      if (rules.myth(id) case final m?) out.add(Padding(padding: const EdgeInsets.only(top: Sp.sm), child: FactCard(m.fact)));
    }
  }
  // announced by screen readers when a new warning appears while she types
  return out.isEmpty ? null : Semantics(liveRegion: true, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: out));
}
