import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/content.dart';
import '../theme.dart';
import '../widgets.dart';
import 'first_aid_screen.dart';

/// Emergency care plan (MA-24): what to do now, where to go, who to call, what to bring.
/// Fully offline. Calling uses the phone's dialler, so it works without data.
class EmergencyScreen extends StatelessWidget {
  const EmergencyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final plan = s.carePlan;
    final f = s.facility;
    final tt = Theme.of(context).textTheme;
    void call(String n) => launchUrl(Uri(scheme: 'tel', path: n.replaceAll(' ', '')));
    final hospital = (plan['hospital_name'] ?? '').isNotEmpty ? plan['hospital_name']! : '${f?['name'] ?? ''}';
    final hospitalPhone = (plan['hospital_phone'] ?? '').isNotEmpty ? plan['hospital_phone']! : '${f?['phone'] ?? ''}';
    final steps = [
      context.t('Ask someone to go with you and call for transport now.', 'Muombe mtu akusindikize na tafuta usafiri sasa.'),
      context.t('Go to the nearest health facility that is open day and night.', 'Nenda kituo cha afya kilicho karibu kinachofanya kazi mchana na usiku.'),
      context.t('Call the facility on the way, so they are ready.', 'Piga simu kituoni ukiwa njiani ili wajiandae.'),
      s.pregnant
          ? context.t('Lie on your left side while you travel if you can.', 'Lala kwa ubavu wa kushoto ukisafiri kama unaweza.')
          : context.t(
              'Keep the baby warm, skin to skin, and keep breastfeeding if the baby can.',
              'Mweke mtoto katika joto, ngozi kwa ngozi, na endelea kunyonyesha kama anaweza.',
            ),
    ];

    Widget callRow({required IconData icon, required String title, required String sub, required String number, required Key key, bool primary = false}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: Sp.sm),
          child: Material(
            color: primary ? C.red : C.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(R.card),
              side: BorderSide(color: primary ? C.red : C.red.withValues(alpha: .35)),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: key,
              onTap: () => call(number),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 64),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.md, vertical: Sp.smd),
                  child: Row(
                    children: [
                      Icon(icon, color: primary ? Colors.white : C.red),
                      const SizedBox(width: Sp.smd),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: tt.titleMedium!.copyWith(color: primary ? Colors.white : C.ink)),
                            Text(sub, style: tt.bodyMedium!.copyWith(color: primary ? Colors.white : C.ink2)),
                          ],
                        ),
                      ),
                      Icon(Icons.call, color: primary ? Colors.white : C.red),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

    return Scaffold(
      backgroundColor: C.redSoft,
      appBar: AppBar(
        backgroundColor: C.red,
        foregroundColor: Colors.white,
        title: Text(context.t('Emergency care plan', 'Mpango wa dharura'), style: AppTypography.h3.copyWith(color: Colors.white)),
      ),
      body: Pad(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(context.t('Need urgent help?', 'Unahitaji msaada wa haraka?'), style: tt.headlineSmall!.copyWith(color: C.red)),
              ),
              ListenButton(steps.join(' ')),
            ],
          ),
          const Gap(Sp.xs),
          Text(
            context.t('Never wait because of this app. If you are worried, go now.', 'Usichelewe kwa sababu ya programu hii. Ukiwa na wasiwasi, nenda sasa.'),
            style: tt.bodyLarge,
          ),
          const Gap(Sp.md),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.smd),
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
                  const SizedBox(width: Sp.smd),
                  Expanded(child: Text(steps[i], style: tt.bodyLarge)),
                ],
              ),
            ),
          if (!s.pregnant && s.baby != null) ...[
            const Gap(Sp.sm),
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
          SectionTitle(
            context.t('Where to go and who to call', 'Wapi pa kwenda na nani wa kumpigia'),
            trailing: TextButton(
              key: const Key('edit-care-plan'),
              style: TextButton.styleFrom(foregroundColor: C.red),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EmergencyContactsScreen())),
              child: Text(context.t('Edit', 'Hariri')),
            ),
          ),
          if (hospital.isNotEmpty && hospitalPhone.isNotEmpty)
            callRow(
              key: const Key('call-hospital'),
              icon: Icons.local_hospital_outlined,
              title: hospital,
              sub: [if ((plan['hospital_address'] ?? '').isNotEmpty) plan['hospital_address']!, hospitalPhone].join(' · '),
              number: hospitalPhone,
              primary: true,
            ),
          if ((plan['contact_phone'] ?? '').isNotEmpty)
            callRow(
              key: const Key('call-contact'),
              icon: Icons.person_outline,
              title: context.t(
                'Call ${plan['contact_name']?.isNotEmpty == true ? plan['contact_name'] : 'my emergency contact'}',
                'Mpigie ${plan['contact_name']?.isNotEmpty == true ? plan['contact_name'] : 'mtu wa dharura'}',
              ),
              sub: plan['contact_phone']!,
              number: plan['contact_phone']!,
            ),
          if ((plan['transport_phone'] ?? '').isNotEmpty)
            callRow(
              key: const Key('call-transport'),
              icon: Icons.local_taxi_outlined,
              title: context.t(
                'Call transport${plan['transport_name']?.isNotEmpty == true ? ': ${plan['transport_name']}' : ''}',
                'Piga usafiri${plan['transport_name']?.isNotEmpty == true ? ': ${plan['transport_name']}' : ''}',
              ),
              sub: plan['transport_phone']!,
              number: plan['transport_phone']!,
            ),
          if (hospitalPhone.isEmpty || (plan['contact_phone'] ?? '').isEmpty || (plan['transport_phone'] ?? '').isEmpty)
            AppCard(
              child: EmptyState(
                Icons.add_call,
                context.t(
                  'Add ${[if (hospitalPhone.isEmpty) 'your facility', if ((plan['contact_phone'] ?? '').isEmpty) 'a person to call', if ((plan['transport_phone'] ?? '').isEmpty) 'transport'].join(', ')} now, so they are here when you need them.',
                  'Ongeza ${[if (hospitalPhone.isEmpty) 'kituo chako', if ((plan['contact_phone'] ?? '').isEmpty) 'mtu wa kumpigia', if ((plan['transport_phone'] ?? '').isEmpty) 'usafiri'].join(', ')} sasa, ili viwe hapa ukivihitaji.',
                ),
                actionLabel: context.t('Add contacts', 'Ongeza namba'),
                onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EmergencyContactsScreen())),
              ),
            ),
          const Gap(Sp.sm),
          for (final (label, n) in emergencyNumbersTz)
            callRow(key: Key('call-$n'), icon: Icons.local_phone_outlined, title: context.tx(label), sub: n, number: n),
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
                    padding: const EdgeInsets.symmetric(vertical: Sp.xs),
                    child: Row(
                      children: [
                        const Icon(Icons.check, color: C.red, size: 20),
                        const SizedBox(width: Sp.sm),
                        Expanded(child: Text(x, style: tt.bodyLarge)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          SectionTitle(context.t('Danger signs: go now', 'Dalili za hatari: nenda sasa')),
          Wrap(
            spacing: Sp.sm,
            runSpacing: Sp.sm,
            children: [
              for (final sg in (s.pregnant ? pregnancySigns : [...postnatalSigns, ...babySigns]).where((x) => x.level == Level.red))
                Chip(
                  avatar: Icon(sg.icon, size: 18, color: C.red),
                  label: Text(context.tx(sg.label)),
                ),
            ],
          ),
          const Gap(Sp.lg),
          const OfflineIndicator(),
        ],
      ),
    );
  }
}

/// Edit the emergency care plan: facility, one person to call, and transport.
/// Kept on this phone only. Nothing here is invented: every field is what she types.
class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});
  @override
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  static const keys = ['hospital_name', 'hospital_address', 'hospital_phone', 'contact_name', 'contact_phone', 'transport_name', 'transport_phone'];
  late final c = {for (final k in keys) k: TextEditingController()};
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final s = context.appRead;
    final p = s.carePlan;
    for (final k in keys) {
      c[k]!.text = p[k] ?? '';
    }
    if (c['hospital_name']!.text.isEmpty && s.facility != null) {
      c['hospital_name']!.text = '${s.facility!['name'] ?? ''}';
      c['hospital_phone']!.text = '${s.facility!['phone'] ?? ''}';
    }
  }

  @override
  void dispose() {
    for (final x in c.values) {
      x.dispose();
    }
    super.dispose();
  }

  String? _phoneError(String k) {
    final v = c[k]!.text.trim();
    if (v.isEmpty) return null;
    return RegExp(r'^[+0-9 ()-]{6,20}$').hasMatch(v) ? null : context.t('Use numbers only, for example 0712 345 678', 'Tumia namba tu, kwa mfano 0712 345 678');
  }

  @override
  Widget build(BuildContext context) {
    final valid = _phoneError('hospital_phone') == null && _phoneError('contact_phone') == null && _phoneError('transport_phone') == null;
    Widget field(String k, String label, {bool phone = false, String? hint}) => Padding(
      padding: const EdgeInsets.only(bottom: Sp.mdl),
      child: AppTextField(
        fieldKey: Key('cp-$k'),
        label: label,
        hint: hint,
        controller: c[k],
        keyboardType: phone ? TextInputType.phone : null,
        error: phone ? _phoneError(k) : null,
        onChanged: (_) => setState(() {}),
      ),
    );
    return AppScaffold(
      title: context.t('My contacts', 'Namba zangu'),
      bottom: PrimaryButton(
        key: const Key('cp-save'),
        context.t('Save', 'Hifadhi'),
        onPressed: !valid
            ? null
            : () async {
                await context.appRead.saveCarePlan({for (final k in keys) k: c[k]!.text});
                if (context.mounted) Navigator.of(context).pop();
              },
      ),
      children: [
        Text(
          context.t('Saved on this phone only. You can change it at any time.', 'Inahifadhiwa kwenye simu hii tu. Unaweza kubadilisha wakati wowote.'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        SectionTitle(context.t('Health facility', 'Kituo cha afya')),
        field('hospital_name', context.t('Facility name', 'Jina la kituo')),
        field('hospital_address', context.t('Where it is', 'Mahali kilipo'), hint: context.t('Village, road or landmark', 'Kijiji, barabara au alama')),
        field('hospital_phone', context.t('Facility phone', 'Simu ya kituo'), phone: true),
        SectionTitle(context.t('Person to call', 'Mtu wa kumpigia')),
        field('contact_name', context.t('Name', 'Jina'), hint: context.t('Partner, mother, neighbour…', 'Mwenzi, mama, jirani…')),
        field('contact_phone', context.t('Phone', 'Simu'), phone: true),
        SectionTitle(context.t('Transport', 'Usafiri')),
        field('transport_name', context.t('Driver or taxi', 'Dereva au teksi'), hint: context.t('Bajaji, boda boda, car…', 'Bajaji, boda boda, gari…')),
        field('transport_phone', context.t('Phone', 'Simu'), phone: true),
      ],
    );
  }
}
