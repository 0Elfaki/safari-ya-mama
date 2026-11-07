import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/reminders.dart';
import '../state/app_scope.dart';
import '../ui/theme.dart';
import 'providers.dart';
import 'router.dart';

/// App root. Riverpod owns the state and the router; [AppScope] hands the state to every screen.
class SafariYaMamaApp extends ConsumerStatefulWidget {
  const SafariYaMamaApp({super.key});
  @override
  ConsumerState<SafariYaMamaApp> createState() => _SafariYaMamaAppState();
}

class _SafariYaMamaAppState extends ConsumerState<SafariYaMamaApp> with WidgetsBindingObserver {
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final s = ref.read(appStateProvider);
    // sync on open and every 60 seconds while open (NF-06); phone reminders follow her settings
    s.onBookingsChanged = () => Reminders.sync(s);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      s.syncNow();
      Reminders.sync(s);
      s.bookings.refresh();
    });
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
    final s = ref.read(appStateProvider);
    if (st == AppLifecycleState.paused && s.hasPin) {
      // shared phones: close every open screen (journal, check-in…) and ask for the PIN on return
      closeAllTabScreens();
      s.lock();
    }
    if (st == AppLifecycleState.resumed) {
      s.syncNow();
      Reminders.sync(s);
      s.bookings.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final router = ref.watch(routerProvider);
    return AppScope(
      state: s,
      child: MaterialApp.router(title: 'Safari ya Mama', debugShowCheckedModeBanner: false, theme: buildTheme(), routerConfig: router),
    );
  }
}
