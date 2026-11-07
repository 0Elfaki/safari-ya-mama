import 'package:go_router/go_router.dart';

import '../../app/router.dart';

import 'package:flutter/material.dart';

import '../../ui/widgets.dart' show Ctx;
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// Persistent one-tap Emergency help (MA-09), in the top bar of every screen.
/// Red pill with an icon and the word, so it is never colour alone. Its label grows with the
/// phone's text size up to 1.3x, so the top bar still fits on a small phone at the largest size.
class EmergencyShortcut extends StatelessWidget {
  const EmergencyShortcut({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 12),
    child: FilledButton.icon(
      key: const Key('emergency'),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.red,
        minimumSize: const Size(AppSize.touch, AppSize.touch),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w700),
      ),
      onPressed: () => context.push(Routes.emergency),
      icon: const Icon(Icons.emergency, size: 20),
      label: MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: Text(context.t('Emergency', 'Dharura'))),
    ),
  );
}

typedef EmergencyButton = EmergencyShortcut;
