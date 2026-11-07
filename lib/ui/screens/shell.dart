import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../theme.dart';
import '../widgets.dart';
import 'app_drawer.dart';

/// Bottom navigation for the five tabs: Home · My Care · MamaBot · Community · Learn.
/// The side menu (☰, app_drawer.dart) lists everything, including Profile and settings.
/// Tabs are peers: no slide between them, each keeps its own back stack, and tapping the
/// active tab again returns it to its first screen.
/// The outer scaffold: holds the side menu so it covers the whole screen, tab bar included.
final shellScaffoldKey = GlobalKey<ScaffoldState>(debugLabel: 'shell');

class Shell extends StatelessWidget {
  final StatefulNavigationShell shell;
  const Shell({super.key, required this.shell});

  @override
  Widget build(BuildContext context) => Scaffold(
    key: shellScaffoldKey,
    drawer: AppDrawer(shell: shell),
    body: shell,
    bottomNavigationBar: DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: C.line)),
      ),
      child: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          NavigationDestination(
            key: const Key('tab-home'),
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home_rounded),
            label: context.t('Home', 'Nyumbani'),
          ),
          NavigationDestination(
            key: const Key('tab-journey'),
            icon: const Icon(Icons.monitor_heart_outlined),
            selectedIcon: const Icon(Icons.monitor_heart),
            label: context.t('My Care', 'Huduma'),
          ),
          const NavigationDestination(
            key: Key('tab-mamabot'),
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'MamaBot',
          ),
          NavigationDestination(
            key: const Key('tab-community'),
            icon: const Icon(Icons.groups_outlined),
            selectedIcon: const Icon(Icons.groups),
            label: context.t('Community', 'Jamii'),
          ),
          NavigationDestination(
            key: const Key('tab-learn'),
            icon: const Icon(Icons.menu_book_outlined),
            selectedIcon: const Icon(Icons.menu_book),
            label: context.t('Learn', 'Jifunze'),
          ),
        ],
      ),
    ),
  );
}

/// The first screen of a tab: the same top bar on every tab (title, notifications on Home,
/// Emergency shortcut). Screens opened from a tab bring their own bar.
class TabPage extends StatelessWidget {
  final int tab;
  final Widget child;
  const TabPage({super.key, required this.tab, required this.child});

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final titles = ['Safari ya Mama', context.t('My Care', 'Huduma yangu'), 'MamaBot', context.t("Mothers' circle", 'Kikundi cha akina mama'), context.t('Learn', 'Jifunze')];
    final unread = s.unreadNotifications;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 60,
        leading: IconButton(
          key: const Key('open-menu'),
          tooltip: context.t('Menu', 'Menyu'),
          icon: Badge(isLabelVisible: unread > 0 && tab != 0, backgroundColor: C.primary, smallSize: 8, child: const Icon(Icons.menu_rounded)),
          onPressed: () => shellScaffoldKey.currentState?.openDrawer(),
        ),
        title: tab == 0
            ? FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/brand/mark.png', width: 32, height: 32),
                    const SizedBox(width: Sp.sm),
                    Text(titles[0]),
                  ],
                ),
              )
            : Text(titles[tab]),
        actions: [
          if (tab == 0)
            IconButton(
              key: const Key('open-notifications'),
              tooltip: context.t('Notifications', 'Arifa'),
              onPressed: () => context.push(Routes.notifications),
              icon: Badge(isLabelVisible: unread > 0, backgroundColor: C.primary, label: Text('$unread'), child: const Icon(Icons.notifications_none_rounded)),
            ),
          const EmergencyShortcut(),
        ],
      ),
      body: child,
    );
  }
}
