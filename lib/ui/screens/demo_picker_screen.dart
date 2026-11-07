import 'package:flutter/material.dart';

import '../../state/demo_seed.dart';
import '../theme.dart';
import '../widgets.dart';
import 'onboarding_screen.dart';

/// Preview builds only (`--dart-define=DEMO_PICKER=true`): choose a made-up mother to explore,
/// or set up a new one. Never shown in a real build.
const demoPicker = bool.fromEnvironment('DEMO_PICKER');

class DemoPickerScreen extends StatefulWidget {
  const DemoPickerScreen({super.key});
  @override
  State<DemoPickerScreen> createState() => _DemoPickerScreenState();
}

class _DemoPickerScreenState extends State<DemoPickerScreen> {
  bool busy = false;

  Future<void> _load(String which) async {
    setState(() => busy = true);
    await context.appRead.seedDemo(which);
  }

  @override
  Widget build(BuildContext context) {
    final options = [
      (
        'pregnant',
        Icons.pregnant_woman,
        'Amina · pregnant, 28 weeks',
        'Amina · mjamzito, wiki 28',
        'BP rising over 3 weeks, birth plan, visits',
        'Shinikizo linapanda, mpango wa kujifungua, mahudhurio',
      ),
      (
        'baby',
        Icons.child_care,
        'Bahati · baby Zuri, 3 months',
        'Bahati · mtoto Zuri, miezi 3',
        'Vaccines, growth, milestones, feeds',
        'Chanjo, ukuaji, hatua za makuzi, unyonyeshaji',
      ),
      (
        'twins',
        Icons.people,
        'Rehema · twins Hope & Faith, 3 weeks',
        'Rehema · mapacha Hope na Faith, wiki 3',
        'Two babies, each with their own records',
        'Watoto wawili, kila mmoja na kumbukumbu zake',
      ),
      (
        'caregiver',
        Icons.volunteer_activism_outlined,
        'Juma · Bahati\'s partner (helper)',
        'Juma · mwenzi wa Bahati (msaidizi)',
        'What a partner or grandmother sees',
        'Anachoona mwenzi au bibi',
      ),
    ];
    return Scaffold(
      body: SafeArea(
        child: Pad(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
          children: [
            Text('Safari ya Mama', style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: C.primary)),
            const Gap(4),
            Text(context.t('Mother app preview', 'Onyesho la programu ya mama'), style: Theme.of(context).textTheme.titleMedium),
            const Gap(8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: C.amberSoft, borderRadius: BorderRadius.circular(8)),
              child: Text(
                context.t(
                  'Simulated: made-up mothers. Nothing you type leaves this browser.',
                  'Mfano: wamama wa kubuni. Hakuna unachoandika kinachotoka kwenye kivinjari hiki.',
                ),
              ),
            ),
            const Gap(20),
            for (final (k, icon, en, sw, den, dsw) in options)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  key: Key('demo-$k'),
                  onTap: busy ? null : () => _load(k),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: C.primarySoft,
                        child: Icon(icon, color: C.primary),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(context.t(en, sw), style: Theme.of(context).textTheme.titleMedium),
                            Text(context.t(den, dsw), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: C.ink2)),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            const Gap(8),
            OutlinedButton.icon(
              key: const Key('demo-fresh'),
              onPressed: busy ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OnboardingScreen())),
              icon: const Icon(Icons.person_add_alt),
              label: Text(context.t('Set up as a new mother', 'Jisajili kama mama mpya')),
            ),
            const Gap(12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(onPressed: () => context.appRead.setLang('en'), child: const Text('English')),
                TextButton(onPressed: () => context.appRead.setLang('sw'), child: const Text('Kiswahili')),
              ],
            ),
            if (busy) const Center(child: CircularProgressIndicator()),
          ],
        ),
      ),
    );
  }
}
