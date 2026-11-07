import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import 'app_button.dart';

/// EmptyState: icon, one line saying what is missing and, optionally, how to fill it.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyState(this.icon, this.text, {super.key, this.actionLabel, this.onAction});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.ink3),
            const SizedBox(width: AppSpacing.smd),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
          ],
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: AppSpacing.smd),
          OutlineButton(actionLabel!, onPressed: onAction, expand: false),
        ],
      ],
    ),
  );
}

typedef EmptyNote = EmptyState;

/// ErrorState: what went wrong in plain words, and a retry when one makes sense.
class ErrorState extends StatelessWidget {
  final String text;
  final String? retryLabel;
  final VoidCallback? onRetry;
  const ErrorState(this.text, {super.key, this.retryLabel, this.onRetry});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.redSoft,
      borderRadius: BorderRadius.circular(AppRadius.medium),
      border: Border.all(color: AppColors.red.withValues(alpha: .3)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: AppColors.red),
            const SizedBox(width: AppSpacing.smd),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
          ],
        ),
        if (onRetry != null) ...[
          const SizedBox(height: AppSpacing.smd),
          OutlineButton(retryLabel ?? 'Retry', icon: Icons.refresh, onPressed: onRetry, expand: false),
        ],
      ],
    ),
  );
}

/// LoadingState: a spinner with words (never a bare spinner).
class LoadingState extends StatelessWidget {
  final String text;
  const LoadingState(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.lg),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
        const SizedBox(width: AppSpacing.smd),
        Flexible(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
      ],
    ),
  );
}
