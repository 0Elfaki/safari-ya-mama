import 'package:flutter/material.dart';

import '../../ui/widgets.dart' show Ctx;
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// States that a screen works without internet. Only placed on screens that do.
class OfflineIndicator extends StatelessWidget {
  final String? text;
  const OfflineIndicator({super.key, this.text});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.cloud_off_outlined, size: 18, color: AppColors.ink2),
      const SizedBox(width: AppSpacing.sm),
      Expanded(child: Text(text ?? context.t('Works without internet', 'Inafanya kazi bila intaneti'), style: Theme.of(context).textTheme.bodySmall)),
    ],
  );
}

typedef OfflineNote = OfflineIndicator;

/// Where her records stand: kept on this phone only, waiting to send, or saved to the server.
class SyncStatusIndicator extends StatelessWidget {
  const SyncStatusIndicator({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final pending = s.pendingCount;
    final (icon, color, text) = !s.hasRemote || !s.signedIn
        ? (Icons.phone_android, AppColors.ink2, context.t('Saved on this phone only', 'Imehifadhiwa kwenye simu hii tu'))
        : pending > 0
        ? (Icons.cloud_upload_outlined, AppColors.amber, context.t('$pending waiting to send', '$pending zinasubiri kutumwa'))
        : (Icons.cloud_done_outlined, AppColors.green, context.t('All saved', 'Zote zimehifadhiwa'));
    return Semantics(
      label: text,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall!.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
