import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

/// BaseCard: white, 1 px border, radius 16, padding 20. Tappable when [onTap] is set.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final VoidCallback? onTap;
  final Color? border;
  final double radius;
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.mdl),
    this.color,
    this.onTap,
    this.border,
    this.radius = AppRadius.card,
  });
  @override
  Widget build(BuildContext context) => Card(
    color: color,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: border ?? AppColors.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    ),
  );
}

typedef BaseCard = AppCard;

/// Card with a status band on the left (health results, alerts, reminders).
class HealthCard extends StatelessWidget {
  final Widget child;
  final Color tone;
  final Color? background;
  final VoidCallback? onTap;
  const HealthCard({super.key, required this.child, required this.tone, this.background, this.onTap});
  @override
  Widget build(BuildContext context) => AppCard(
    padding: EdgeInsets.zero,
    color: background,
    border: tone.withValues(alpha: .35),
    onTap: onTap,
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 6, color: tone),
          Expanded(
            child: Padding(padding: const EdgeInsets.all(AppSpacing.md), child: child),
          ),
        ],
      ),
    ),
  );
}

/// HeroCard: the one emphasised card on a screen (Home's pregnancy or baby card).
/// Deep brand green, a gentle top-to-bottom shift within the same green, white text.
class HeroCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  const HeroCard({super.key, required this.child, this.padding = const EdgeInsets.all(AppSpacing.mdl), this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: Ink(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xlarge),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.primary, AppColors.primaryDeep]),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.xlarge),
        child: Padding(
          padding: padding,
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: Colors.white),
            child: child,
          ),
        ),
      ),
    ),
  );
}
