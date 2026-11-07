import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../state/app_state.dart';
import '../ui/screens/caregiver_screen.dart';
import '../features/community/ui/community_screen.dart';
import '../ui/screens/demo_picker_screen.dart';
import '../ui/screens/doctor_note_screen.dart';
import '../ui/screens/emergency_screen.dart';
import '../ui/screens/home_screen.dart';
import '../ui/screens/journey_screen.dart';
import '../ui/screens/learn_screen.dart';
import '../ui/screens/lock_screen.dart';
import '../ui/screens/mamabot_screen.dart';
import '../ui/screens/notifications_screen.dart';
import '../ui/screens/onboarding_screen.dart';
import '../ui/screens/profile_screen.dart';
import '../ui/screens/shell.dart';
import '../ui/screens/signin_screen.dart';
import '../ui/screens/welcome_screen.dart';
import '../ui/widgets.dart';

/// Route paths, so screens never spell them out.
abstract final class Routes {
  static const welcome = '/welcome';
  static const signin = '/signin';
  static const onboarding = '/onboarding';
  static const demo = '/demo';
  static const lock = '/lock';
  static const caregiver = '/caregiver';
  static const caregiverJoin = '/caregiver/join';
  static const home = '/home';
  static const care = '/care';
  static const mamabot = '/mamabot';
  static const community = '/community';
  static const learn = '/learn';
  static const profile = '/profile';
  static const emergency = '/emergency';
  static const emergencyContacts = '/emergency/contacts';
  static const doctorNote = '/doctor-note';
  static const notifications = '/notifications';
}

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// One navigator per tab: each tab keeps its own back stack.
final branchKeys = [
  for (final n in ['home', 'care', 'mamabot', 'community', 'learn']) GlobalKey<NavigatorState>(debugLabel: n),
];

/// Closes every screen opened inside the tabs (shared phones: before the PIN screen shows).
void closeAllTabScreens() {
  for (final k in branchKeys) {
    k.currentState?.popUntil((r) => r.isFirst);
  }
}

/// Open before onboarding and on the lock screen: emergency help must never be behind a wall.
const _alwaysOpen = {Routes.emergency, Routes.emergencyContacts};
const _beforeOnboarding = {Routes.welcome, Routes.onboarding, Routes.demo, Routes.caregiverJoin};

GoRouter buildRouter(AppState s) => GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: Routes.home,
  refreshListenable: s,
  redirect: (context, state) {
    final at = state.matchedLocation;
    if (_alwaysOpen.contains(at)) return null;
    // One-way doors: once a guard passes, back can never re-enter the old state.
    if (s.locked) return at == Routes.lock ? null : Routes.lock;
    if (at == Routes.lock) return Routes.home;
    if (s.isCaregiver) return at == Routes.caregiver ? null : Routes.caregiver;
    if (at == Routes.caregiver) return Routes.home;
    // helpers join with their own flow (they sign in inside it)
    if (at == Routes.caregiverJoin && !s.onboarded) return null;
    if (!s.onboarded) {
      if (at == Routes.demo) return null;
      // sign-in is required when the app has a server: records are never only on one phone
      if (s.needsSignIn) return (at == Routes.welcome || at == Routes.signin) ? null : Routes.welcome;
      if (s.hasRemote) return at == Routes.onboarding ? null : Routes.onboarding;
      if (at == Routes.welcome || at == Routes.onboarding) return null;
      return demoPicker ? Routes.demo : Routes.welcome;
    }
    // set up before sign-in was required (or signed out elsewhere): sign in to keep the records
    if (s.needsSignIn) return at == Routes.signin ? null : Routes.signin;
    if (_beforeOnboarding.contains(at) || at == Routes.signin) return Routes.home;
    return null;
  },
  routes: [
    GoRoute(path: Routes.welcome, builder: (_, _) => const WelcomeScreen()),
    GoRoute(path: Routes.onboarding, builder: (_, _) => const OnboardingScreen()),
    GoRoute(path: Routes.signin, builder: (_, _) => const SignInScreen()),
    GoRoute(path: Routes.demo, builder: (_, _) => const DemoPickerScreen()),
    GoRoute(path: Routes.lock, builder: (_, _) => const LockScreen()),
    GoRoute(path: Routes.caregiver, builder: (_, _) => const CaregiverHomeScreen()),
    GoRoute(path: Routes.caregiverJoin, builder: (_, _) => const CaregiverJoinScreen()),
    // Full-attention screens sit above the tabs, on the root navigator.
    GoRoute(
      path: Routes.emergency,
      parentNavigatorKey: rootNavigatorKey,
      builder: (_, _) => const EmergencyScreen(),
      routes: [GoRoute(path: 'contacts', parentNavigatorKey: rootNavigatorKey, builder: (_, _) => const EmergencyContactsScreen())],
    ),
    GoRoute(path: Routes.doctorNote, parentNavigatorKey: rootNavigatorKey, builder: (_, _) => const DoctorNoteScreen()),
    GoRoute(path: Routes.notifications, parentNavigatorKey: rootNavigatorKey, builder: (_, _) => const NotificationsScreen()),
    // Profile and settings: from the person button on every tab's top bar
    GoRoute(
      path: Routes.profile,
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(context.t('Profile', 'Wasifu')), actions: const [EmergencyShortcut()]),
        body: const ProfileScreen(),
      ),
    ),
    StatefulShellRoute.indexedStack(
      builder: (_, _, shell) => Shell(shell: shell),
      branches: [
        StatefulShellBranch(
          navigatorKey: branchKeys[0],
          routes: [
            GoRoute(
              path: Routes.home,
              builder: (context, _) => TabPage(tab: 0, child: HomeScreen(onTab: (i) => StatefulNavigationShell.of(context).goBranch(i))),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: branchKeys[1],
          routes: [
            GoRoute(
              path: Routes.care,
              builder: (_, _) => const TabPage(tab: 1, child: JourneyScreen()),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: branchKeys[2],
          routes: [
            GoRoute(
              path: Routes.mamabot,
              builder: (_, _) => const TabPage(tab: 2, child: MamaBotScreen()),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: branchKeys[3],
          routes: [
            GoRoute(
              path: Routes.community,
              builder: (_, _) => const TabPage(tab: 3, child: CommunityScreen()),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: branchKeys[4],
          routes: [
            GoRoute(
              path: Routes.learn,
              builder: (_, _) => const TabPage(tab: 4, child: LearnScreen()),
            ),
          ],
        ),
      ],
    ),
  ],
);
