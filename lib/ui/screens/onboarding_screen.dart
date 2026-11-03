import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'caregiver_screen.dart';
import 'lock_screen.dart';

/// Onboarding (MA-01..MA-04): language, stage and dates, consent (all off), optional PIN.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int step = 0;
  final name = TextEditingController();
  final babyNames = List.generate(3, (_) => TextEditingController());
  int babyCount = 1;
  final clinic = TextEditingController();
  final clinicPhone = TextEditingController();
  String stage = 'pregnant';
  String dateMode = 'weeks'; // weeks | lmp
  int weeksPreg = 12;
  DateTime? lmp, dob;
  final consents = {for (final k in consentKinds) k: false};
  String pin = '';

  bool get _canNext => switch (step) {
    1 => name.text.trim().isNotEmpty && (stage == 'pregnant' ? (dateMode == 'weeks' || lmp != null) : dob != null),
    _ => true,
  };

  Future<void> _finish() async {
    final s = context.appRead;
    if (clinic.text.trim().isNotEmpty) {
      await s.setFacility({'id': null, 'name': clinic.text.trim(), 'phone': clinicPhone.text.trim()});
    }
    final l = stage == 'pregnant' ? (dateMode == 'weeks' ? addDays(today(), -weeksPreg * 7) : lmp) : null;
    if (pin.length == 4) await s.setPin(pin);
    await s.completeOnboarding(
      name: name.text,
      stage: stage,
      lmp: l,
      dob: dob,
      babyNames: [for (var i = 0; i < babyCount; i++) babyNames[i].text],
      consents: consents,
    );
    // opened from the preview picker: go back to the root, which now shows the app
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<DateTime?> _pick(DateTime first, DateTime last) =>
      showDatePicker(context: context, firstDate: first, lastDate: last, initialDate: last, helpText: context.t('Choose the date', 'Chagua tarehe'));

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final steps = [_welcome(s), _about(), _consent(), _pin()];
    return Scaffold(
      appBar: AppBar(
        leading: step > 0 ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => step--)) : null,
        title: Text('${step + 1} / ${steps.length}'),
        actions: const [EmergencyButton()],
      ),
      body: SafeArea(child: steps[step]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton(
            key: const Key('ob-next'),
            onPressed: !_canNext ? null : () => step < steps.length - 1 ? setState(() => step++) : _finish(),
            child: Text(step < steps.length - 1 ? context.t('Continue', 'Endelea') : context.t('Start', 'Anza')),
          ),
        ),
      ),
    );
  }

  Widget _welcome(AppState s) => Pad(
    children: [
      const Illus('mother_belly', height: 200),
      const Gap(24),
      Text('Safari ya Mama', style: Theme.of(context).textTheme.headlineSmall),
      const Gap(8),
      Text(
        context.t(
          'Your daily companion from the first month of pregnancy until your baby is 9 months old. A 1-minute check each day tells you when to get care.',
          'Mwenzako wa kila siku kuanzia mwezi wa kwanza wa ujauzito hadi mtoto afikishe miezi 9. Ukaguzi wa dakika 1 kila siku unakuambia wakati wa kutafuta huduma.',
        ),
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      const Gap(24),
      Text(context.t('Choose your language', 'Chagua lugha yako'), style: Theme.of(context).textTheme.titleMedium),
      const Gap(8),
      Choice<String>(
        keyPrefix: 'lang',
        options: const [('sw', Icons.translate, 'Kiswahili'), ('en', Icons.translate, 'English')],
        value: s.lang,
        onChanged: s.setLang,
      ),
      const Gap(8),
      Text(
        context.t('Sudanese Arabic and Luganda are coming later.', 'Kiarabu cha Sudan na Luganda vinakuja baadaye.'),
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const Gap(16),
      AppCard(
        color: C.surface2,
        child: Text(
          context.t(
            'Safari ya Mama supports your health worker. It does not replace them and it cannot diagnose.',
            'Safari ya Mama inamsaidia mhudumu wako wa afya. Haichukui nafasi yake na haiwezi kutoa utambuzi.',
          ),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
      const Gap(12),
      TextButton.icon(
        key: const Key('i-help-a-mother'),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CaregiverJoinScreen())),
        icon: const Icon(Icons.volunteer_activism_outlined),
        label: Text(context.t('I help a mother (partner or family)', 'Ninamsaidia mama (mwenzi au familia)')),
      ),
    ],
  );

  Widget _about() => Pad(
    children: [
      Text(context.t('About you', 'Kuhusu wewe'), style: Theme.of(context).textTheme.headlineSmall),
      const Gap(16),
      TextField(
        key: const Key('ob-name'),
        controller: name,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: context.t('Your first name', 'Jina lako la kwanza')),
      ),
      const Gap(24),
      Choice<String>(
        keyPrefix: 'stage',
        options: [
          ('pregnant', Icons.pregnant_woman, context.t('I am pregnant', 'Nina ujauzito')),
          ('postnatal', Icons.child_care, context.t('My baby is born', 'Mtoto amezaliwa')),
        ],
        value: stage,
        onChanged: (v) => setState(() => stage = v),
      ),
      const Gap(24),
      if (stage == 'pregnant') ...[
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'weeks', label: Text(context.t('Weeks pregnant', 'Wiki za ujauzito'))),
            ButtonSegment(value: 'lmp', label: Text(context.t('Last period date', 'Tarehe ya hedhi'))),
          ],
          selected: {dateMode},
          onSelectionChanged: (v) => setState(() => dateMode = v.first),
        ),
        const Gap(16),
        if (dateMode == 'weeks')
          AppCard(
            child: Row(
              children: [
                IconButton.filledTonal(onPressed: weeksPreg > 4 ? () => setState(() => weeksPreg--) : null, icon: const Icon(Icons.remove)),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '$weeksPreg',
                        key: const Key('ob-weeks'),
                        style: const TextStyle(fontFamily: display, fontSize: 40, fontWeight: FontWeight.w800),
                      ),
                      Text(context.t('weeks', 'wiki'), style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ),
                IconButton.filledTonal(onPressed: weeksPreg < 42 ? () => setState(() => weeksPreg++) : null, icon: const Icon(Icons.add)),
              ],
            ),
          )
        else
          OutlinedButton.icon(
            icon: const Icon(Icons.event),
            label: Text(
              lmp == null
                  ? context.t('Choose the first day of your last period', 'Chagua siku ya kwanza ya hedhi ya mwisho')
                  : fmtDayYear(lmp!, context.appRead.lang),
            ),
            onPressed: () async {
              final d = await _pick(addDays(today(), -300), today());
              if (d != null) setState(() => lmp = d);
            },
          ),
        const Gap(8),
        Builder(
          builder: (_) {
            final l = dateMode == 'weeks' ? addDays(today(), -weeksPreg * 7) : lmp;
            if (l == null) return const SizedBox();
            return Text(
              context.t('Due date about ${fmtDayYear(addDays(l, 280), 'en')}', 'Tarehe ya kujifungua takriban ${fmtDayYear(addDays(l, 280), 'sw')}'),
              style: Theme.of(context).textTheme.titleMedium,
            );
          },
        ),
      ] else ...[
        OutlinedButton.icon(
          key: const Key('ob-dob'),
          icon: const Icon(Icons.cake_outlined),
          label: Text(dob == null ? context.t("Choose your baby's birth date", 'Chagua tarehe ya kuzaliwa ya mtoto') : fmtDayYear(dob!, context.appRead.lang)),
          onPressed: () async {
            final d = await _pick(addDays(today(), -280), today());
            if (d != null) setState(() => dob = d);
          },
        ),
        const Gap(16),
        Choice<int>(
          keyPrefix: 'ob-count',
          value: babyCount,
          onChanged: (v) => setState(() => babyCount = v),
          options: [
            (1, Icons.child_care, context.t('One baby', 'Mtoto mmoja')),
            (2, Icons.people_outline, context.t('Twins', 'Pacha')),
            (3, Icons.groups_outlined, context.t('Triplets', 'Watatu')),
          ],
        ),
        for (var i = 0; i < babyCount; i++) ...[
          const Gap(12),
          TextField(
            key: Key('ob-baby-$i'),
            controller: babyNames[i],
            decoration: InputDecoration(
              labelText: babyCount == 1
                  ? context.t("Baby's name (optional)", 'Jina la mtoto (si lazima)')
                  : context.t('Name of baby ${i + 1} (optional)', 'Jina la mtoto wa ${i + 1} (si lazima)'),
            ),
          ),
        ],
      ],
      const Gap(24),
      Text(context.t('Your clinic (for emergency calls)', 'Kliniki yako (kwa simu za dharura)'), style: Theme.of(context).textTheme.titleMedium),
      const Gap(8),
      TextField(
        controller: clinic,
        decoration: InputDecoration(labelText: context.t('Clinic name (optional)', 'Jina la kliniki (si lazima)')),
      ),
      const Gap(8),
      TextField(
        controller: clinicPhone,
        keyboardType: TextInputType.phone,
        decoration: InputDecoration(labelText: context.t('Clinic phone (optional)', 'Simu ya kliniki (si lazima)')),
      ),
    ],
  );

  Widget _consent() {
    final items = <String, (String, String)>{
      'share_with_facility': (
        context.t('Share warning signs with my clinic', 'Shiriki dalili za hatari na kliniki yangu'),
        context.t(
          'If a check shows red or amber, your clinic sees it and can call you. Needed for clinic alerts.',
          'Ukaguzi ukionyesha nyekundu au njano, kliniki yako itaona na inaweza kukupigia. Inahitajika kwa tahadhari za kliniki.',
        ),
      ),
      'share_with_chw': (
        context.t('Let my community health worker follow up', 'Mhudumu wa afya ya jamii anifuatilie'),
        context.t(
          'Your CHW can visit or call when you report a warning sign.',
          'Mhudumu wa jamii anaweza kukutembelea au kukupigia ukiripoti dalili ya hatari.',
        ),
      ),
      'reminders_sms': (
        context.t('SMS reminders', 'Vikumbusho kwa SMS'),
        context.t(
          'Visit and vaccine dates by SMS. Messages never name a sign or a result.',
          'Tarehe za kliniki na chanjo kwa SMS. Ujumbe hautaji dalili wala matokeo.',
        ),
      ),
      'reminders_whatsapp': (
        context.t('WhatsApp reminders', 'Vikumbusho kwa WhatsApp'),
        context.t('The same reminders on WhatsApp.', 'Vikumbusho hivyo hivyo kwa WhatsApp.'),
      ),
      'photo_storage': (
        context.t('Keep baby photos on the server', 'Hifadhi picha za mtoto kwenye seva'),
        context.t('Off means photos stay only on this phone.', 'Ikizimwa, picha zinabaki kwenye simu hii tu.'),
      ),
      'research': (
        context.t('Anonymous research', 'Utafiti bila majina'),
        context.t('Your records without your name help improve care. Always optional.', 'Kumbukumbu zako bila jina lako husaidia kuboresha huduma. Si lazima.'),
      ),
    };
    return Pad(
      children: [
        Text(context.t('Your information, your choice', 'Taarifa zako, uamuzi wako'), style: Theme.of(context).textTheme.headlineSmall),
        const Gap(8),
        Row(
          children: [
            Expanded(
              child: Text(
                context.t(
                  'Everything is off until you turn it on. You can change this at any time in Profile, and you can delete your data.',
                  'Kila kitu kimezimwa hadi uwashe. Unaweza kubadilisha wakati wowote kwenye Wasifu, na unaweza kufuta taarifa zako.',
                ),
              ),
            ),
            ListenButton(context.t('Everything is off until you turn it on.', 'Kila kitu kimezimwa hadi uwashe.')),
          ],
        ),
        const Gap(16),
        for (final e in items.entries) ...[
          AppCard(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            child: SwitchListTile(
              key: Key('consent-${e.key}'),
              contentPadding: EdgeInsets.zero,
              title: Text(e.value.$1, style: Theme.of(context).textTheme.titleMedium),
              subtitle: Text(e.value.$2),
              value: consents[e.key]!,
              onChanged: (v) => setState(() => consents[e.key] = v),
            ),
          ),
          const Gap(8),
        ],
      ],
    );
  }

  Widget _pin() => Pad(
    children: [
      Text(context.t('Lock the app (shared phones)', 'Funga programu (simu za pamoja)'), style: Theme.of(context).textTheme.headlineSmall),
      const Gap(8),
      Text(context.t('Choose 4 numbers. You can skip this and add a PIN later.', 'Chagua namba 4. Unaweza kuruka na kuweka PIN baadaye.')),
      const Gap(16),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 4; i++)
            Container(
              margin: const EdgeInsets.all(8),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < pin.length ? C.primary : C.surface2,
                border: Border.all(color: C.line),
              ),
            ),
        ],
      ),
      PinPad(
        onDigit: (d) => setState(() => pin = pin.length < 4 ? pin + d : pin),
        onBack: () => setState(() => pin = pin.isEmpty ? '' : pin.substring(0, pin.length - 1)),
      ),
    ],
  );
}
