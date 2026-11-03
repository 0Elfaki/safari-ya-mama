import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';
import 'baby_screen.dart';
import 'health_screen.dart';
import 'home_screen.dart';
import 'learn_screen.dart';
import 'profile_screen.dart';
import 'visits_screen.dart';

/// Five low-effort tabs, with Emergency help always one tap away.
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final titles = [
      'Safari ya Mama',
      context.t('Health', 'Afya'),
      context.t('My baby', 'Mtoto wangu'),
      context.t('Learn', 'Jifunze'),
      context.t('Visits', 'Kliniki'),
    ];
    final pages = [HomeScreen(onTab: (i) => setState(() => tab = i)), const HealthScreen(), const BabyScreen(), const LearnScreen(), const VisitsScreen()];
    return Scaffold(
      appBar: AppBar(
        title: tab == 0
            ? FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [Image.asset('assets/brand/mark.png', width: 28, height: 28), const SizedBox(width: 8), Text(titles[0])],
                ),
              )
            : Text(titles[tab]),
        actions: [
          IconButton(
            key: const Key('open-profile'),
            tooltip: context.t('Profile', 'Wasifu'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: Text(context.t('Profile', 'Wasifu')), actions: const [EmergencyButton()]),
                  body: const ProfileScreen(),
                ),
              ),
            ),
            icon: const Icon(Icons.account_circle_outlined, size: 30),
          ),
          const EmergencyButton(),
        ],
      ),
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: C.line)),
        ),
        child: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: [
            NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: context.t('Home', 'Nyumbani')),
            NavigationDestination(icon: const Icon(Icons.favorite_border), selectedIcon: const Icon(Icons.favorite), label: context.t('Health', 'Afya')),
            NavigationDestination(
              icon: const Icon(Icons.child_care_outlined),
              selectedIcon: const Icon(Icons.child_care),
              label: context.t('My baby', 'Mtoto'),
            ),
            NavigationDestination(
              key: const Key('tab-learn'),
              icon: const Icon(Icons.menu_book_outlined),
              selectedIcon: const Icon(Icons.menu_book),
              label: context.t('Learn', 'Jifunze'),
            ),
            NavigationDestination(icon: const Icon(Icons.event_outlined), selectedIcon: const Icon(Icons.event), label: context.t('Visits', 'Kliniki')),
          ],
        ),
      ),
    );
  }
}
