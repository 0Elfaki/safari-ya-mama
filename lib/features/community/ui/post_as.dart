import 'package:flutter/material.dart';

import '../../../ui/theme.dart';
import '../../../ui/widgets.dart';
import 'community_name_screen.dart';

/// "Who should other mothers see?" on every post and reply: "Anonymous mother" (nobody sees a
/// name), or her community name. Choosing a name she does not have yet opens the name screen.
/// Her last choice is remembered on the phone.
class PostAsChoice extends StatelessWidget {
  final bool anonymous;
  final ValueChanged<bool> onChanged;
  final bool compact;
  const PostAsChoice({super.key, required this.anonymous, required this.onChanged, this.compact = false});

  static bool remembered(BuildContext context) => context.appRead.store.meta<bool>('community_anonymous', true)!;

  Future<void> _pick(BuildContext context, bool anon) async {
    final s = context.appRead;
    if (!anon && s.community.handle == null) {
      final saved = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const CommunityNameScreen()));
      if (saved == null) return;
    }
    await s.store.setMeta('community_anonymous', anon);
    onChanged(anon);
  }

  @override
  Widget build(BuildContext context) {
    final handle = context.app.community.handle;
    final tt = Theme.of(context).textTheme;
    if (compact) {
      // replies: one line, tap to switch
      return InkWell(
        key: const Key('reply-as'),
        onTap: () => _pick(context, !anonymous),
        borderRadius: BorderRadius.circular(R.small),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Icon(anonymous ? Icons.visibility_off_outlined : Icons.alternate_email, size: 18, color: C.ink2),
              const SizedBox(width: Sp.xs),
              Expanded(
                child: Text(
                  anonymous ? context.t('Replying as Anonymous mother · change', 'Unajibu kama Mama asiyejulikana · badilisha') : context.t('Replying as @$handle · change', 'Unajibu kama @$handle · badilisha'),
                  style: tt.bodySmall,
                ),
              ),
            ],
          ),
        ),
      );
    }
    Widget option(String key, bool value, IconData icon, String title, String sub) {
      final on = anonymous == value;
      return Expanded(
        child: InkWell(
          key: Key(key),
          onTap: () => _pick(context, value),
          borderRadius: BorderRadius.circular(R.large),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(Sp.smd),
            decoration: BoxDecoration(
              color: on ? C.primarySoft : C.surface,
              borderRadius: BorderRadius.circular(R.large),
              border: Border.all(color: on ? C.primary : C.line, width: on ? 2 : 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: on ? C.primary : C.ink2),
                const Gap(Sp.xs),
                Text(title, style: tt.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(sub, style: tt.bodySmall, maxLines: 2),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.t('Who should other mothers see?', 'Akina mama wengine waone nani?'), style: tt.titleMedium),
        const Gap(Sp.sm),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              option('post-as-anon', true, Icons.visibility_off_outlined, context.t('Anonymous mother', 'Mama asiyejulikana'), context.t('No name shown', 'Bila jina')),
              const SizedBox(width: Sp.sm),
              option(
                'post-as-name',
                false,
                Icons.alternate_email,
                handle == null ? context.t('A community name', 'Jina la jamii') : '@$handle',
                handle == null ? context.t('Choose any name you like', 'Chagua jina lolote upendalo') : context.t('Your community name', 'Jina lako la jamii'),
              ),
            ],
          ),
        ),
        if (!anonymous && handle != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const Key('change-name'),
              onPressed: () => Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const CommunityNameScreen())),
              child: Text(context.t('Change my community name', 'Badilisha jina langu la jamii')),
            ),
          ),
      ],
    );
  }
}
