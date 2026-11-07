import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';

/// Small status label: icon + words in the status colour (never colour alone).
class StatusBadge extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  final Color? background;
  const StatusBadge(this.text, {super.key, required this.color, this.icon, this.background});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: background ?? AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      border: Border.all(color: color.withValues(alpha: .35)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 16, color: color), const SizedBox(width: 6)],
        Flexible(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color, height: 1.25),
          ),
        ),
      ],
    ),
  );
}

typedef StatusPill = StatusBadge;
