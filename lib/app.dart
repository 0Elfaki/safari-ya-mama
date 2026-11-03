import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'state/app_state.dart';
import 'ui/screens/caregiver_screen.dart';
import 'ui/screens/demo_picker_screen.dart';
import 'ui/screens/emergency_screen.dart';
import 'ui/screens/lock_screen.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/shell.dart';
import 'ui/theme.dart';

class SafariYaMamaApp extends StatefulWidget {
  const SafariYaMamaApp({super.key});
  @override
  State<SafariYaMamaApp> createState() => _SafariYaMamaAppState();
}

class _SafariYaMamaAppState extends State<SafariYaMamaApp> with WidgetsBindingObserver {
  Timer? _syncTimer;
  final _nav = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final s = context.read<AppState>();
    // sync on open and every 60 seconds while open (NF-06)
    WidgetsBinding.instance.addPostFrameCallback((_) => s.syncNow());
    _syncTimer = Timer.periodic(const Duration(seconds: 60), (_) => s.syncNow());
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState st) {
    final s = context.read<AppState>();
    if (st == AppLifecycleState.paused && s.hasPin) {
      // shared phones: close every open screen (journal, check-in…) and ask for the PIN on return
      _nav.currentState?.popUntil((r) => r.isFirst);
      s.lock();
    }
    if (st == AppLifecycleState.resumed) s.syncNow();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return MaterialApp(
      title: 'Safari ya Mama',
      debugShowCheckedModeBanner: false,
      navigatorKey: _nav,
      theme: buildTheme(),
      routes: {'/emergency': (_) => const EmergencyScreen()},
      home: s.locked
          ? const LockScreen()
          : s.isCaregiver
          ? const CaregiverHomeScreen()
          : (s.onboarded ? const Shell() : (demoPicker ? const DemoPickerScreen() : const OnboardingScreen())),
    );
  }
}
