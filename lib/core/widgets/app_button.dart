import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// The app's buttons. All are 52 high, radius 12, Inter 16 semibold, show a spinner and
/// ignore taps while [loading], and show the disabled style when [onPressed] is null.
enum _Kind { primary, secondary, outline, danger }

class _AppButton extends StatelessWidget {
  final _Kind kind;
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading, expand;
  const _AppButton(this.kind, this.label, {super.key, this.icon, this.onPressed, this.loading = false, this.expand = true});

  @override
  Widget build(BuildContext context) {
    final fg = switch (kind) {
      _Kind.primary || _Kind.danger => Colors.white,
      _ => AppColors.primary,
    };
    final child = loading
        ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: fg))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
              Flexible(
                child: Text(label, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, maxLines: 2),
              ),
            ],
          );
    final tap = loading ? () {} : onPressed;
    final min = Size(expand ? double.infinity : AppSize.button, AppSize.button);
    final b = switch (kind) {
      _Kind.primary => FilledButton(
        style: FilledButton.styleFrom(minimumSize: min),
        onPressed: tap,
        child: child,
      ),
      _Kind.danger => FilledButton(
        style: FilledButton.styleFrom(minimumSize: min, backgroundColor: AppColors.red),
        onPressed: tap,
        child: child,
      ),
      _Kind.secondary => FilledButton(
        style: FilledButton.styleFrom(minimumSize: min, backgroundColor: AppColors.primarySoft, foregroundColor: AppColors.primary),
        onPressed: tap,
        child: child,
      ),
      _Kind.outline => OutlinedButton(
        style: OutlinedButton.styleFrom(minimumSize: min),
        onPressed: tap,
        child: child,
      ),
    };
    return Semantics(button: true, enabled: onPressed != null, label: loading ? '$label…' : null, child: b);
  }
}

class PrimaryButton extends _AppButton {
  const PrimaryButton(String label, {super.key, super.icon, super.onPressed, super.loading, super.expand}) : super(_Kind.primary, label);
}

class SecondaryButton extends _AppButton {
  const SecondaryButton(String label, {super.key, super.icon, super.onPressed, super.loading, super.expand}) : super(_Kind.secondary, label);
}

class OutlineButton extends _AppButton {
  const OutlineButton(String label, {super.key, super.icon, super.onPressed, super.loading, super.expand}) : super(_Kind.outline, label);
}

class DangerButton extends _AppButton {
  const DangerButton(String label, {super.key, super.icon, super.onPressed, super.loading, super.expand}) : super(_Kind.danger, label);
}

/// A primary button that shows its own spinner while [onPressed] runs.
class LoadingButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final Future<void> Function()? onPressed;
  const LoadingButton(this.label, {super.key, this.icon, this.onPressed});
  @override
  State<LoadingButton> createState() => _LoadingButtonState();
}

class _LoadingButtonState extends State<LoadingButton> {
  bool busy = false;
  @override
  Widget build(BuildContext context) => PrimaryButton(
    widget.label,
    icon: widget.icon,
    loading: busy,
    onPressed: widget.onPressed == null
        ? null
        : () async {
            setState(() => busy = true);
            try {
              await widget.onPressed!();
            } finally {
              if (mounted) setState(() => busy = false);
            }
          },
  );
}

/// Icon button with a required label for screen readers (no icon without words).
class AppIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool filled;
  const AppIconButton(this.icon, {super.key, required this.tooltip, this.onPressed, this.filled = false});
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    style: IconButton.styleFrom(
      minimumSize: const Size(AppSize.touch, AppSize.touch),
      foregroundColor: AppColors.primary,
      backgroundColor: filled ? AppColors.primarySoft : null,
    ),
    icon: Icon(icon),
  );
}
