import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:go_router/go_router.dart';

import '../state/app_state.dart';
import 'router.dart';

/// The mother's whole record (offline-first). Created in main() and passed in with
/// `appStateProvider.overrideWith((ref) => state)`; tests do the same with an in-memory store.
final appStateProvider = ChangeNotifierProvider<AppState>((ref) => throw UnimplementedError('appStateProvider must be overridden'));

/// One router for the app's lifetime. It listens to AppState for its guards (PIN lock,
/// caregiver mode, onboarding).
final routerProvider = Provider<GoRouter>((ref) {
  final r = buildRouter(ref.read(appStateProvider));
  ref.onDispose(r.dispose);
  return r;
});
