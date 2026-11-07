import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Section heading inside a screen (H3, 24 above, 8 below), with an optional action.
class AppSectionHeader extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const AppSectionHeader(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, AppSpacing.lg, 2, AppSpacing.sm),
    child: Row(
      children: [
        Expanded(
          child: Semantics(header: true, child: Text(text, style: Theme.of(context).textTheme.titleLarge)),
        ),
        ?trailing,
      ],
    ),
  );
}

typedef SectionTitle = AppSectionHeader;

/// Screen heading block: title (H2) and an optional supporting line.
class AppHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const AppHeader(this.title, {super.key, this.subtitle, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.headlineSmall)),
              if (subtitle != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium!.copyWith(color: AppColors.ink2)),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    ),
  );
}
