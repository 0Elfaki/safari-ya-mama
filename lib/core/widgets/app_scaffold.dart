import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'emergency_shortcut.dart';

/// Every pushed screen: the same top bar (title + Emergency shortcut) and the same scrolling
/// body with 16 px side padding. Tabs live inside the Shell, which has its own bar.
class AppScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final Widget? bottom;
  final bool emergency;
  final Color? background;
  const AppScaffold({super.key, required this.title, required this.children, this.bottom, this.emergency = true, this.background});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: background,
    appBar: AppBar(title: Text(title), actions: [if (emergency) const EmergencyShortcut()]),
    body: ListView(padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, AppSpacing.xl), children: children),
    bottomNavigationBar: bottom == null
        ? null
        : SafeArea(
            child: Padding(padding: const EdgeInsets.fromLTRB(AppSpacing.screen, AppSpacing.sm, AppSpacing.screen, AppSpacing.md), child: bottom),
          ),
  );
}
