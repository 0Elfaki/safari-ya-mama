import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/content.dart';
import '../../core/dates.dart';
import '../../core/tx.dart';
import '../../data/remote.dart';
import '../theme.dart';
import '../widgets.dart';
import 'first_aid_screen.dart';
import 'learn_screen.dart';
import 'signin_screen.dart';

/// Caregiver / partner link (MA-53). A helper signs in with their own phone number and the
/// 6-digit code the mother gives them. They see what she chose to share: today's result, the
/// last 7 days, the next visit and vaccine. Never her journal, notes or questions.
class CaregiverJoinScreen extends StatefulWidget {
  const CaregiverJoinScreen({super.key});
  @override
  State<CaregiverJoinScreen> createState() => _CaregiverJoinScreenState();
}

class _CaregiverJoinScreenState extends State<CaregiverJoinScreen> {
  final code = TextEditingController(), name = TextEditingController();
  String? err;
  bool busy = false;

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('I help a mother', 'Ninamsaidia mama'))),
      body: Pad(
        children: [
          Text(
            context.t(
              'Partners, grandmothers and family can follow a mother\'s checks and be told when she or her baby needs care. Ask her for a 6-digit code: she makes it in her app under Profile → My helpers.',
              'Wenzi, bibi na familia wanaweza kufuatilia ukaguzi wa mama na kuambiwa yeye au mtoto anapohitaji huduma. Muombe namba ya tarakimu 6: anaitengeneza kwenye programu yake, Wasifu → Wasaidizi wangu.',
            ),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const Gap(16),
          if (!s.hasRemote)
            AppCard(
              color: C.amberSoft,
              border: C.amberFill,
              child: Text(
                context.t(
                  'This app is not connected to a server (offline demo), so a helper cannot join here.',
                  'Programu hii haijaunganishwa na seva (onyesho bila mtandao), kwa hiyo msaidizi hawezi kujiunga hapa.',
                ),
              ),
            )
          else if (!s.signedIn) ...[
            TextField(
              key: const Key('cg-name'),
              controller: name,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: context.t('Your first name', 'Jina lako la kwanza')),
            ),
            const Gap(12),
            FilledButton.icon(
              key: const Key('cg-signin'),
              onPressed: name.text.trim().isEmpty
                  ? null
                  : () async {
                      await s.setName(name.text);
                      if (context.mounted) await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SignInScreen()));
                      setState(() {});
                    },
              icon: const Icon(Icons.phone_android),
              label: Text(context.t('Sign in with my phone number', 'Ingia kwa namba yangu ya simu')),
            ),
          ] else ...[
            TextField(
              key: const Key('cg-code'),
              controller: code,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(labelText: context.t('Code from the mother', 'Namba kutoka kwa mama')),
            ),
            FilledButton(
              key: const Key('cg-join'),
              onPressed: busy
                  ? null
                  : () async {
                      setState(() {
                        busy = true;
                        err = null;
                      });
                      final bad = context.t('That code did not work. Check it, or ask for a new one.', 'Namba hiyo haikufanya kazi. Ihakiki, au omba mpya.');
                      try {
                        final who = await s.acceptCaregiverInvite(code.text);
                        if (who == null) {
                          err = bad;
                        } else if (context.mounted) {
                          Navigator.of(context).popUntil((r) => r.isFirst);
                        }
                      } on RemoteError catch (e) {
                        err = e.message;
                      }
                      if (mounted) setState(() => busy = false);
                    },
              child: Text(context.t('Join', 'Jiunge')),
            ),
          ],
          if (err != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(err!, style: const TextStyle(color: C.red)),
            ),
        ],
      ),
    );
  }
}

/// The caregiver's home: one card per mother they help.
class CaregiverHomeScreen extends StatefulWidget {
  const CaregiverHomeScreen({super.key});
  @override
  State<CaregiverHomeScreen> createState() => _CaregiverHomeScreenState();
}

class _CaregiverHomeScreenState extends State<CaregiverHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.appRead.refreshCaregiver());
  }

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    void go(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    final moms = s.caregiverSummary;
    return Scaffold(
      appBar: AppBar(title: const Text('Safari ya Mama'), actions: const [EmergencyButton()]),
      body: RefreshIndicator(
        onRefresh: s.refreshCaregiver,
        child: Pad(
          children: [
            Text(context.t('Hello, ${s.name}', 'Habari, ${s.name}'), style: Theme.of(context).textTheme.headlineSmall),
            Text(
              s.caregiverUpdatedAt == null
                  ? context.t('Pull down to update.', 'Vuta chini kusasisha.')
                  : context.t(
                      'Updated ${fmtTime(parseTs(s.caregiverUpdatedAt!))}. Pull down to update.',
                      'Imesasishwa ${fmtTime(parseTs(s.caregiverUpdatedAt!))}. Vuta chini kusasisha.',
                    ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Gap(12),
            if (moms.isEmpty)
              EmptyNote(
                Icons.link_off,
                context.t('You are not linked to a mother right now. Ask her for a new code.', 'Hujaunganishwa na mama kwa sasa. Muombe namba mpya.'),
              ),
            for (final m in moms) _MotherCard(m),
            const Gap(8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => go(const FirstAidHubScreen()),
                    icon: const Icon(Icons.health_and_safety_outlined),
                    label: Text(context.t('First aid', 'Huduma ya kwanza')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => go(
                      Scaffold(
                        appBar: AppBar(title: Text(context.t('Learn', 'Jifunze')), actions: const [EmergencyButton()]),
                        body: const LearnScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.menu_book_outlined),
                    label: Text(context.t('Learn', 'Jifunze')),
                  ),
                ),
              ],
            ),
            const Gap(8),
            TextButton(
              onPressed: () => go(const CaregiverJoinScreen()),
              child: Text(context.t('Add another mother with a code', 'Ongeza mama mwingine kwa namba')),
            ),
            TextButton(onPressed: s.signOut, child: Text(context.t('Sign out', 'Toka'))),
          ],
        ),
      ),
    );
  }
}

class _MotherCard extends StatelessWidget {
  final Map<String, dynamic> m;
  const _MotherCard(this.m);
  @override
  Widget build(BuildContext context) {
    final today = m['today'] as Map?;
    final lv = today == null ? null : LevelX.parse(today['level'] as String?);
    final weeks = m['pregnant_weeks'] as int?;
    final babies = (m['babies'] as List? ?? const []).map((b) => b as Map).toList();
    final days = {for (final d in (m['last7'] as List? ?? const [])) '${(d as Map)['day']}': LevelX.parse(d['level'] as String?)};
    final open = m['open_alert'] as Map?;
    final nv = m['next_visit'] as Map?, nx = m['next_vaccine'] as Map?;
    final stage = weeks != null
        ? context.t('Pregnant, $weeks weeks', 'Mjamzito, wiki $weeks')
        : babies.map((b) => context.t('${b['name']}, ${b['days']} days', '${b['name']}, siku ${b['days']}')).join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        key: Key('cg-mother-${m['mother_id']}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${m['name']}', style: Theme.of(context).textTheme.titleLarge),
            Text(stage, style: Theme.of(context).textTheme.bodyMedium),
            const Gap(12),
            if (lv == null)
              Row(
                children: [
                  const Icon(Icons.schedule, color: C.ink3),
                  const SizedBox(width: 8),
                  Expanded(child: Text(context.t('No check yet today.', 'Bado hajafanya ukaguzi leo.'))),
                ],
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: levelSoft(lv), borderRadius: BorderRadius.circular(14)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tx(LevelBanner.title(lv)),
                      style: TextStyle(color: levelColor(lv), fontWeight: FontWeight.w800),
                    ),
                    for (final k in (today!['signs'] as List? ?? const []))
                      if (signByKey('$k') != null) Text('· ${context.tx(signByKey('$k')!.label)}'),
                    if (lv == Level.red)
                      Text(
                        context.t('Help her get to a health facility now.', 'Msaidie afike kituo cha afya sasa.'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    if (lv == Level.amber) Text(context.t('Help her contact a health worker today.', 'Msaidie awasiliane na mhudumu wa afya leo.')),
                  ],
                ),
              ),
            const Gap(12),
            Text(context.t('Last 7 days', 'Siku 7 zilizopita'), style: Theme.of(context).textTheme.labelLarge),
            const Gap(4),
            Row(
              children: [
                for (var i = 6; i >= 0; i--)
                  Expanded(
                    child: Container(
                      height: 20,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(
                        color: switch (days[isoDay(addDays(today_(), -i))]) {
                          null => C.surface2,
                          Level.amber => C.amberFill,
                          final l => levelColor(l),
                        },
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
              ],
            ),
            if (open != null) ...[
              const Gap(8),
              Text(
                context.t('The clinic has an open alert and may call her.', 'Kliniki ina tahadhari iliyo wazi na inaweza kumpigia.'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (nv != null) ...[
              const Gap(8),
              Row2(icon: Icons.event, title: context.t('Next clinic visit', 'Kliniki ijayo'), sub: fmtDayYear(parseDay('${nv['due']}'), context.appRead.lang)),
            ],
            if (nx != null)
              Row2(
                icon: Icons.vaccines_outlined,
                title: context.t('Next vaccine', 'Chanjo ijayo'),
                sub:
                    '${vaccineDoses.where((d) => d.key == nx['key']).firstOrNull?.label ?? nx['key']} · ${fmtDayYear(parseDay('${nx['due']}'), context.appRead.lang)}',
              ),
          ],
        ),
      ),
    );
  }
}

DateTime today_() => today();

/// Mother's side: Profile → My helpers. Make a code, see who helps, stop a link.
class MyHelpersScreen extends StatefulWidget {
  const MyHelpersScreen({super.key});
  @override
  State<MyHelpersScreen> createState() => _MyHelpersScreenState();
}

class _MyHelpersScreenState extends State<MyHelpersScreen> {
  Future<List<Map<String, dynamic>>>? list;
  String? code;
  String relation = 'partner';
  bool alerts = true;

  @override
  void initState() {
    super.initState();
    final s = context.appRead;
    if (s.signedIn) list = s.myCaregivers();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final rel = <(String, Tx)>[
      ('partner', const Tx('Partner or husband', 'Mwenzi au mume')),
      ('grandmother', const Tx('Mother or grandmother', 'Mama au bibi')),
      ('sister', const Tx('Sister', 'Dada')),
      ('friend', const Tx('Friend', 'Rafiki')),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(context.t('My helpers', 'Wasaidizi wangu')), actions: const [EmergencyButton()]),
      body: Pad(
        children: [
          Text(
            context.t(
              'A helper sees your daily check results, the next visit and vaccine, and can be told when you or your baby need care. They never see your journal, notes or questions. You can stop it at any time.',
              'Msaidizi anaona matokeo ya ukaguzi wako, kliniki ijayo na chanjo, na anaweza kuambiwa wewe au mtoto mnapohitaji huduma. Haoni shajara, maelezo wala maswali yako. Unaweza kusitisha wakati wowote.',
            ),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const Gap(16),
          if (!s.signedIn)
            AppCard(
              color: C.amberSoft,
              border: C.amberFill,
              child: Text(
                context.t(
                  'Connect to your clinic first (Profile → Connect), so your helper can see your checks.',
                  'Unganisha na kliniki kwanza (Wasifu → Unganisha), ili msaidizi aone ukaguzi wako.',
                ),
              ),
            )
          else ...[
            SectionTitle(context.t('Invite a helper', 'Mwalike msaidizi')),
            Wrap(
              spacing: 8,
              children: [
                for (final (k, t) in rel) ChoiceChip(label: Text(context.tx(t)), selected: relation == k, onSelected: (_) => setState(() => relation = k)),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: alerts,
              onChanged: (v) => setState(() => alerts = v),
              title: Text(context.t('Tell them when my check is red or orange', 'Waambie ukaguzi wangu ukiwa mwekundu au wa machungwa')),
            ),
            FilledButton.icon(
              key: const Key('make-code'),
              onPressed: () async {
                try {
                  final c = await s.createCaregiverInvite(relation, alerts: alerts);
                  setState(() => code = c);
                } on RemoteError catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                }
              },
              icon: const Icon(Icons.key),
              label: Text(context.t('Make a code', 'Tengeneza namba')),
            ),
            if (code != null) ...[
              const Gap(12),
              AppCard(
                color: C.primarySoft,
                border: C.primarySoft,
                child: Column(
                  children: [
                    SelectableText(
                      code!,
                      key: const Key('invite-code'),
                      style: const TextStyle(fontFamily: display, fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: 6),
                    ),
                    Text(context.t('Valid for 48 hours, once.', 'Inafanya kazi saa 48, mara moja.')),
                    const Gap(8),
                    TextButton.icon(
                      onPressed: () => Clipboard.setData(
                        ClipboardData(
                          text: context.t(
                            'Install Safari ya Mama, choose "I help a mother" and enter this code: $code',
                            'Sakinisha Safari ya Mama, chagua "Ninamsaidia mama" na uweke namba hii: $code',
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.copy),
                      label: Text(context.t('Copy a message to send', 'Nakili ujumbe wa kutuma')),
                    ),
                  ],
                ),
              ),
            ],
            SectionTitle(context.t('Who helps me', 'Wanaonisaidia')),
            FutureBuilder(
              future: list,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                if (snap.hasError) return EmptyNote(Icons.wifi_off, context.t('Needs a connection.', 'Inahitaji mtandao.'));
                final rows = snap.data ?? const [];
                if (rows.isEmpty) return EmptyNote(Icons.people_outline, context.t('Nobody yet.', 'Bado hakuna.'));
                return Column(
                  children: [
                    for (final r in rows)
                      AppCard(
                        child: Row2(
                          icon: Icons.person,
                          title: '${r['name']}',
                          sub: r['alerts'] == true ? context.t('Gets alerts', 'Anapata tahadhari') : context.t('No alerts', 'Hapati tahadhari'),
                          trailing: TextButton(
                            onPressed: () async {
                              await s.stopCaregiver('${r['caregiver_id']}');
                              setState(() => list = s.myCaregivers());
                            },
                            child: Text(context.t('Stop', 'Sitisha')),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
