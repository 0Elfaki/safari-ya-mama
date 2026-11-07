import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Text input. Same look as every field in the app: the label always shown at the top edge
/// (never only a placeholder), an optional hint, and an inline error under it.
class AppTextField extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final String? hint, error, helper;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final int maxLines;
  final bool required;
  final Key? fieldKey;
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.error,
    this.helper,
    this.keyboardType,
    this.onChanged,
    this.maxLines = 1,
    this.required = false,
    this.fieldKey,
  });
  @override
  Widget build(BuildContext context) => TextField(
    key: fieldKey,
    controller: controller,
    keyboardType: keyboardType,
    onChanged: onChanged,
    maxLines: maxLines,
    decoration: InputDecoration(
      label: Text.rich(
        TextSpan(
          text: label,
          children: [
            if (required)
              const TextSpan(
                text: ' *',
                style: TextStyle(color: AppColors.red),
              ),
          ],
        ),
      ),
      hintText: hint,
      errorText: error,
      helperText: helper,
      helperMaxLines: 2,
    ),
  );
}

/// Search box: pill-free rounded field with a search icon and a clear button.
class AppSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final Key? fieldKey;
  const AppSearchField({super.key, required this.controller, required this.hint, required this.onChanged, this.fieldKey});
  @override
  Widget build(BuildContext context) => TextField(
    key: fieldKey,
    controller: controller,
    onChanged: onChanged,
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      hintText: hint,
      floatingLabelBehavior: FloatingLabelBehavior.never,
      prefixIcon: const Icon(Icons.search, color: AppColors.ink2),
      suffixIcon: controller.text.isEmpty
          ? null
          : IconButton(
              tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
              icon: const Icon(Icons.close),
              onPressed: () {
                controller.clear();
                onChanged('');
              },
            ),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
    ),
  );
}
