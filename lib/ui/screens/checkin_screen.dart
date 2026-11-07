import 'package:go_router/go_router.dart';

import '../../app/router.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/content.dart';
import '../../core/rules.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'child_check.dart';

/// The 1-minute daily check (MA-14..MA-18). The level is decided on the phone by
/// rules.dart, so the result and emergency advice show with no signal.
class CheckinScreen extends StatefulWidget {
  const CheckinScreen({super.key});
  @override
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen> {
  String feeling = '';
  String movement = 'normal';
  final signs = <String>{};
  // one answer set per baby (twins, triplets)
  final feeding = <String, String>{};
  final babyS = <String, Set<String>>{};
  final babyNote = <String, TextEditingController>{};
  bool? ifa, net;
  final sys = TextEditingController(), dia = TextEditingController(), note = TextEditingController();
  bool busy = false;

  Future<void> _submit() async {
    final s = context.appRead;
    setState(() => busy = true);
    final input = s.checkinInput(feeling: feeling, signs: signs, movement: movement, systolic: int.tryParse(sys.text), diastolic: int.tryParse(dia.text));
    final answers = s.pregnant
        ? null
        : {
            for (final b in s.babies)
              b['id'] as String: BabyAnswers(signs: babyS[b['id']] ?? const {}, feeding: feeding[b['id']] ?? 'normal', note: babyNote[b['id']]?.text ?? ''),
          };
    final t = await s.submitCheckin(input, note: note.text, ifa: ifa, net: net, babyAnswers: answers);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => CheckinResultScreen(t)));
  }

  String? get _bpError {
    if (sys.text.isEmpty && dia.text.isEmpty) return null;
    final a = int.tryParse(sys.text), b = int.tryParse(dia.text);
    if (a == null || b == null) return context.t('Enter both numbers', 'Weka namba zote mbili');
    if (a < 60 || a > 260 || b < 30 || b > 180) {
      return context.t('These numbers look wrong. Check the machine.', 'Namba hizi zinaonekana si sahihi. Kagua kipimo.');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final preg = s.pregnant;
    return Scaffold(
      appBar: AppBar(title: Text(context.t("Today's check", 'Ukaguzi wa leo')), actions: const [EmergencyButton()]),
      body: Pad(
        children: [
          Text(context.t('How are you feeling today?', 'Unajisikiaje leo?'), style: Theme.of(context).textTheme.titleLarge),
          const Gap(12),
          Choice<String>(
            keyPrefix: 'feel',
            value: feeling,
            onChanged: (v) => setState(() => feeling = v),
            options: [
              ('well', Icons.sentiment_satisfied_alt, context.t('Well', 'Vizuri')),
              ('ok', Icons.sentiment_neutral, context.t('Okay', 'Kawaida')),
              ('unwell', Icons.sentiment_very_dissatisfied, context.t('Unwell', 'Mgonjwa')),
            ],
          ),
          if (preg && s.weeks >= 20) ...[
            SectionTitle(context.t("Baby's movements today", 'Mtoto anacheza leo?')),
            Choice<String>(
              keyPrefix: 'move',
              value: movement,
              onChanged: (v) => setState(() => movement = v),
              options: [
                ('normal', Icons.check_circle_outline, context.t('As usual', 'Kama kawaida')),
                ('fewer', Icons.trending_down, context.t('Less than usual', 'Kidogo kuliko kawaida')),
                ('none', Icons.do_not_disturb_on_outlined, context.t('Not moving', 'Hachezi')),
              ],
            ),
          ],
          SectionTitle(
            preg
                ? context.t('Do you have any of these now?', 'Una mojawapo ya hizi sasa?')
                : context.t('You: any of these now?', 'Wewe: una mojawapo ya hizi sasa?'),
          ),
          Text(context.t('Tap all that apply', 'Gusa zote zinazohusika'), style: Theme.of(context).textTheme.bodyMedium),
          const Gap(8),
          for (final sign in preg ? pregnancySigns : postnatalSigns)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SignTile(
                sign,
                selected: signs.contains(sign.key),
                onTap: () => setState(() => signs.contains(sign.key) ? signs.remove(sign.key) : signs.add(sign.key)),
              ),
            ),
          if (!preg)
            for (final (i, b) in s.babies.indexed)
              BabyColourCheck(
                key: ValueKey('colour-check-${b['id']}'),
                name: s.nameOf(b),
                babyDays: s.ageDays(b),
                keySuffix: i == 0 ? '' : '-$i',
                selected: babyS.putIfAbsent(b['id'] as String, () => <String>{}),
                onToggle: (k) => setState(() {
                  final set = babyS[b['id'] as String]!;
                  set.contains(k) ? set.remove(k) : set.add(k);
                }),
                feeding: feeding[b['id']] ?? 'normal',
                onFeeding: (v) => setState(() => feeding[b['id'] as String] = v),
                note: babyNote.putIfAbsent(b['id'] as String, TextEditingController.new),
              ),
          if (preg) ...[
            SectionTitle(context.t('Yesterday and today', 'Jana na leo')),
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: [
                  CheckboxListTile(
                    value: ifa == true,
                    onChanged: (v) => setState(() => ifa = v),
                    title: Text(context.t('I took my iron + folic acid tablet', 'Nimemeza kidonge cha madini ya chuma na foliki')),
                  ),
                  CheckboxListTile(
                    value: net == true,
                    onChanged: (v) => setState(() => net = v),
                    title: Text(context.t('I slept under a mosquito net', 'Nimelala ndani ya chandarua')),
                  ),
                ],
              ),
            ),
          ],
          SectionTitle(context.t('Blood pressure (if you measured it)', 'Shinikizo la damu (kama umepima)')),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('ck-sys'),
                  controller: sys,
                  onChanged: (_) => setState(() {}),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: context.t('Top number', 'Namba ya juu')),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('/', style: TextStyle(fontSize: 24)),
              ),
              Expanded(
                child: TextField(
                  key: const Key('ck-dia'),
                  controller: dia,
                  onChanged: (_) => setState(() {}),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: context.t('Bottom number', 'Namba ya chini')),
                ),
              ),
            ],
          ),
          if (_bpError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_bpError!, style: const TextStyle(color: C.red)),
            ),
          SectionTitle(
            preg
                ? context.t('A note for your health worker (optional)', 'Ujumbe kwa mhudumu wa afya (si lazima)')
                : context.t('About you: a note for your health worker (optional)', 'Kuhusu wewe: ujumbe kwa mhudumu wa afya (si lazima)'),
          ),
          TextField(
            controller: note,
            maxLength: 500,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: context.t('It is also added to your questions for the next visit.', 'Pia unaongezwa kwenye maswali ya kliniki ijayo.'),
            ),
          ),
          const Gap(8),
          FilledButton(
            key: const Key('ck-submit'),
            onPressed: busy || feeling.isEmpty || _bpError != null ? null : _submit,
            child: Text(context.t('Send my check', 'Tuma ukaguzi wangu')),
          ),
          if (feeling.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                context.t('Choose how you are feeling first.', 'Chagua kwanza unavyojisikia.'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
        ],
      ),
    );
  }
}

class CheckinResultScreen extends StatelessWidget {
  final Triage t;
  const CheckinResultScreen(this.t, {super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final f = s.facility;
    final sharing = s.sharingActive, wantsSharing = s.consent('share_with_facility');
    return Scaffold(
      appBar: AppBar(title: Text(context.t('Your result', 'Matokeo yako')), actions: const [EmergencyButton()]),
      body: Pad(
        children: [
          LevelBanner(t.level, reasons: t.reasons.map(context.tx).toList()),
          const Gap(16),
          if (t.level == Level.red) ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: C.red, minimumSize: const Size.fromHeight(60)),
              onPressed: () => context.push(Routes.emergency),
              icon: const Icon(Icons.emergency),
              label: Text(context.t('What to do now', 'Nini cha kufanya sasa')),
            ),
            const Gap(12),
          ],
          if (t.level != Level.green && f?['phone'] != null && '${f!['phone']}'.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: '${f['phone']}'.replaceAll(' ', ''))),
              icon: const Icon(Icons.call),
              label: Text(context.t('Call ${f['name']}', 'Piga ${f['name']}')),
            ),
          if (t.level != Level.green) ...[
            const Gap(12),
            AppCard(
              color: C.surface2,
              child: Text(
                sharing
                    ? context.t(
                        'You share with your clinic, so they will see this when your phone syncs and may call you. Do not wait for their call.',
                        'Unashiriki na kliniki yako, kwa hiyo wataona hili simu ikisawazisha na wanaweza kukupigia. Usisubiri simu yao.',
                      )
                    : wantsSharing
                    ? context.t(
                        'Sharing is switched on, but your clinic can only see your checks after you connect to it in Profile. Please contact them yourself now.',
                        'Kushiriki kumewashwa, lakini kliniki yako itaona ukaguzi wako tu baada ya kuiunganisha kwenye Wasifu. Tafadhali wasiliana nao mwenyewe sasa.',
                      )
                    : context.t(
                        'Your clinic cannot see this because sharing is off. Please contact them yourself.',
                        'Kliniki yako haioni hili kwa sababu kushiriki kumezimwa. Tafadhali wasiliana nao mwenyewe.',
                      ),
              ),
            ),
          ],
          const Gap(16),
          FilledButton.tonal(onPressed: () => Navigator.of(context).pop(), child: Text(context.t('Done', 'Nimemaliza'))),
          const Gap(8),
          Text('${context.t('Rules', 'Kanuni')} ${t.version} · WHO / PCPNC / IMCI', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
