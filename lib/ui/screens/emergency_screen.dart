import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/content.dart';
import '../theme.dart';
import '../widgets.dart';
import 'first_aid_screen.dart';

/// Emergency help (MA-24): what to do now, who to call, what to bring. Fully offline.
class EmergencyScreen extends StatelessWidget {
  const EmergencyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final f = s.facility;
    void call(String n) => launchUrl(Uri(scheme: 'tel', path: n.replaceAll(' ', '')));
    final steps = [
      context.t('Ask someone to go with you and call for transport now.', 'Muombe mtu akusindikize na tafuta usafiri sasa.'),
      context.t('Go to the nearest health facility that is open day and night.', 'Nenda kituo cha afya kilicho karibu kinachofanya kazi mchana na usiku.'),
      context.t('Call your clinic on the way, so they are ready.', 'Piga simu kliniki ukiwa njiani ili wajiandae.'),
      s.pregnant
          ? context.t('Lie on your left side while you travel if you can.', 'Lala kwa ubavu wa kushoto ukisafiri kama unaweza.')
          : context.t(
              'Keep the baby warm, skin to skin, and keep breastfeeding if the baby can.',
              'Mweke mtoto katika joto, ngozi kwa ngozi, na endelea kunyonyesha kama anaweza.',
            ),
    ];
    return Scaffold(
      backgroundColor: C.redSoft,
      appBar: AppBar(
        backgroundColor: C.red,
        foregroundColor: Colors.white,
        title: Text(
          context.t('Emergency help', 'Msaada wa dharura'),
          style: const TextStyle(fontFamily: display, fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ),
      body: Pad(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(context.t('What to do now', 'Nini cha kufanya sasa'), style: Theme.of(context).textTheme.headlineSmall!.copyWith(color: C.red)),
              ),
              ListenButton(steps.join(' ')),
            ],
          ),
          const Gap(12),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: C.red,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(steps[i], style: Theme.of(context).textTheme.bodyLarge)),
                ],
              ),
            ),
          if (!context.app.pregnant && context.app.baby != null) ...[
            const Gap(12),
            OutlinedButton.icon(
              key: const Key('emergency-first-aid'),
              style: OutlinedButton.styleFrom(
                foregroundColor: C.red,
                side: const BorderSide(color: C.red),
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FirstAidHubScreen())),
              icon: const Icon(Icons.health_and_safety_outlined),
              label: Text(context.t('Baby first aid: choking, not breathing, fits', 'Huduma ya kwanza: kukabwa, kutopumua, degedege')),
            ),
          ],
          SectionTitle(context.t('Who to call', 'Wa kumpigia')),
          if (f != null && '${f['phone'] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: C.red,
                  minimumSize: const Size.fromHeight(64),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: () => call('${f['phone']}'),
                child: Row(
                  children: [
                    const Icon(Icons.call),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${f['name']}', maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(
                            '${f['phone']}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
              ),
            )
          else
            AppCard(
              child: Text(
                context.t(
                  'Add your clinic\'s phone number in Profile so it is here when you need it.',
                  'Ongeza namba ya simu ya kliniki yako kwenye Wasifu ili iwe hapa ukiihitaji.',
                ),
              ),
            ),
          for (final (label, n) in emergencyNumbersTz)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: C.red, minimumSize: const Size.fromHeight(56)),
                onPressed: () => call(n),
                icon: const Icon(Icons.local_phone),
                label: Text('${context.tx(label)} · $n'),
              ),
            ),
          SectionTitle(context.t('What to bring', 'Vitu vya kubeba')),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final x in [
                  context.t('Your clinic card (and the child health card)', 'Kadi ya kliniki (na kadi ya afya ya mtoto)'),
                  context.t('This phone', 'Simu hii'),
                  context.t('Money for transport', 'Pesa ya usafiri'),
                  context.t('Clean cloths, a wrap for the baby', 'Vitambaa safi, kanga ya mtoto'),
                  context.t('Any medicines you take', 'Dawa unazotumia'),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.check, color: C.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(x)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          SectionTitle(context.t('Danger signs: go now', 'Dalili za hatari: nenda sasa')),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final sg in (s.pregnant ? pregnancySigns : [...postnatalSigns, ...babySigns]).where((x) => x.level == Level.red))
                Chip(
                  avatar: Icon(sg.icon, size: 18, color: C.red),
                  label: Text(context.tx(sg.label)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
