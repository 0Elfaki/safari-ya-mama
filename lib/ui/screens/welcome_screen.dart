import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';

import '../content_widgets.dart';
import '../theme.dart';
import '../widgets.dart';

/// First screen before onboarding: brand, promise, language, Get started.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.lg),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - Sp.lg * 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Image.asset('assets/brand/mark.png', width: 36, height: 36),
                      const SizedBox(width: Sp.sm),
                      Expanded(
                        child: Text('Safari ya Mama', style: AppTypography.h3, overflow: TextOverflow.ellipsis),
                      ),
                      const EmergencyShortcut(),
                    ],
                  ),
                  const Gap(Sp.xl),
                  // HERO-WELCOME when delivered (app-picture-prompts.md), else the logo on a soft circle
                  ContentPicture(
                    'HERO-WELCOME',
                    height: 260,
                    radius: R.xlarge,
                    semanticLabel: context.t('A mother at home with her phone', 'Mama nyumbani na simu yake'),
                    fallback: Center(
                      child: Container(
                        width: 240,
                        height: 240,
                        decoration: const BoxDecoration(color: C.primarySoft, shape: BoxShape.circle),
                        padding: const EdgeInsets.all(Sp.lg),
                        child: Image.asset('assets/brand/mark.png', semanticLabel: context.t('Mother holding her baby', 'Mama amembeba mtoto wake')),
                      ),
                    ),
                  ),
                  const Gap(Sp.xl),
                  Text(context.t('A safer journey into motherhood', 'Safari salama kuelekea uzazi'), style: tt.headlineMedium, textAlign: TextAlign.center),
                  const Gap(Sp.sm),
                  Text(
                    context.t('Recognize. Prepare. Seek care.', 'Tambua. Jiandae. Tafuta huduma.'),
                    style: tt.bodyLarge!.copyWith(color: C.ink2),
                    textAlign: TextAlign.center,
                  ),
                  const Gap(Sp.xl),
                  Text(context.t('Language', 'Lugha'), style: AppTypography.label, textAlign: TextAlign.center),
                  const Gap(Sp.sm),
                  SegmentedButton<String>(
                    key: const Key('welcome-lang'),
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: 'sw',
                        label: Text('Kiswahili', key: Key('lang-sw')),
                      ),
                      ButtonSegment(
                        value: 'en',
                        label: Text('English', key: Key('lang-en')),
                      ),
                    ],
                    selected: {s.lang},
                    onSelectionChanged: (v) => s.setLang(v.first),
                  ),
                  const Gap(Sp.lg),
                  PrimaryButton(
                    key: const Key('get-started'),
                    context.t('Get started', 'Anza'),
                    onPressed: () => context.push(s.hasRemote ? Routes.signin : Routes.onboarding),
                  ),
                  if (s.hasRemote) ...[
                    const Gap(Sp.sm),
                    OutlineButton(
                      key: const Key('have-account'),
                      context.t('I already use Safari ya Mama', 'Tayari natumia Safari ya Mama'),
                      onPressed: () => context.push(Routes.signin),
                    ),
                  ],
                  const Gap(Sp.sm),
                  TextButton.icon(
                    key: const Key('i-help-a-mother'),
                    onPressed: () => context.push(Routes.caregiverJoin),
                    icon: const Icon(Icons.volunteer_activism_outlined),
                    label: Text(context.t('I help a mother (partner or family)', 'Ninamsaidia mama (mwenzi au familia)')),
                  ),
                  const Gap(Sp.md),
                  Text(
                    context.t(
                      'Safari ya Mama supports your health worker. It does not replace them and it cannot diagnose.',
                      'Safari ya Mama inamsaidia mhudumu wako wa afya. Haichukui nafasi yake na haiwezi kutoa utambuzi.',
                    ),
                    style: tt.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
