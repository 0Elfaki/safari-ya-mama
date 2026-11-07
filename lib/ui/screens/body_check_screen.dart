import 'package:go_router/go_router.dart';

import '../../app/router.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/body_check.dart';
import '../../core/content.dart';
import '../../core/rules.dart';
import '../../core/tx.dart';
import '../theme.dart';
import '../widgets.dart';

/// Body self-check (MA-43): tap where it hurts, look as shown, answer yes or no, get a safe next
/// step. Pregnant, after birth (her own body) and baby maps. Phone only; never names an illness.
class BodyCheckScreen extends StatefulWidget {
  const BodyCheckScreen({super.key});
  @override
  State<BodyCheckScreen> createState() => _BodyCheckScreenState();
}

class _BodyCheckScreenState extends State<BodyCheckScreen> {
  String? map;

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final m = map ?? (s.pregnant ? 'pregnant' : 'postnatal');
    final weeks = s.pregnant ? s.weeks : 0;
    final areas = bodyMaps[m]!.where((a) => !(m == 'pregnant' && a.id == 'baby' && weeks < 20)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(context.t('Body check', 'Jichunguze')), actions: const [EmergencyButton()]),
      body: Pad(
        children: [
          AppCard(
            key: const Key('body-go-now'),
            color: C.redSoft,
            border: C.red.withValues(alpha: .3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t(
                    'Very unwell, bleeding heavily, fitting or not breathing well? Do not do a check. Go now.',
                    'Unajisikia vibaya sana, unatoka damu nyingi, degedege au kupumua kwa shida? Usifanye ukaguzi. Nenda sasa.',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Gap(8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: C.red),
                  onPressed: () => context.push(Routes.emergency),
                  icon: const Icon(Icons.emergency),
                  label: Text(context.t('Emergency help', 'Msaada wa dharura')),
                ),
              ],
            ),
          ),
          if (!s.pregnant && s.baby != null) ...[
            const Gap(12),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'postnatal', label: Text(context.t('Me', 'Mimi')), icon: const Icon(Icons.person_outline)),
                ButtonSegment(value: 'baby', label: Text(s.babyName), icon: const Icon(Icons.child_care)),
              ],
              selected: {m},
              onSelectionChanged: (v) => setState(() => map = v.first),
            ),
          ],
          const Gap(12),
          Text(context.t('Tap where it hurts or feels wrong', 'Gusa panapouma au pasipo sawa'), style: Theme.of(context).textTheme.titleMedium),
          const Gap(8),
          AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(
              builder: (context, box) => Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _Figure(baby: m == 'baby', pregnant: m == 'pregnant'),
                    ),
                  ),
                  for (final a in areas)
                    Positioned(
                      left: a.x * box.maxWidth - 22,
                      top: a.y * box.maxHeight - 22,
                      child: Tooltip(
                        message: context.tx(a.title),
                        child: InkResponse(
                          key: Key('area-${a.id}'),
                          onTap: () => _open(context, m, a),
                          child: CircleAvatar(
                            radius: 22,
                            backgroundColor: C.primary,
                            child: Icon(a.icon, color: Colors.white, size: 22),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          SectionTitle(context.t('Or choose from the list', 'Au chagua kwenye orodha')),
          for (final a in areas)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                child: Row2(icon: a.icon, title: context.tx(a.title), onTap: () => _open(context, m, a)),
              ),
            ),
        ],
      ),
    );
  }

  void _open(BuildContext context, String map, BodyArea a) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => BodyAreaScreen(map: map, area: a),
    ),
  );
}

class BodyAreaScreen extends StatefulWidget {
  final String map;
  final BodyArea area;
  const BodyAreaScreen({super.key, required this.map, required this.area});
  @override
  State<BodyAreaScreen> createState() => _BodyAreaScreenState();
}

class _BodyAreaScreenState extends State<BodyAreaScreen> {
  final yes = <String>{};
  Triage? result;

  @override
  Widget build(BuildContext context) {
    final s = context.app, a = widget.area;
    return Scaffold(
      appBar: AppBar(title: Text(context.tx(a.title)), actions: const [EmergencyButton()]),
      body: Pad(
        children: [
          AppCard(
            color: C.primarySoft,
            border: C.primarySoft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(a.icon, color: C.primary),
                const SizedBox(width: 10),
                Expanded(child: Text(context.tx(a.how), style: Theme.of(context).textTheme.bodyLarge)),
                ListenButton(context.tx(a.how)),
              ],
            ),
          ),
          SectionTitle(context.t('What did you find?', 'Umeona nini?')),
          for (final q in a.qs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(context.tx(q.text), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    SegmentedButton<bool>(
                      key: Key('q-${q.id}'),
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: true, label: Text(context.t('Yes', 'Ndiyo'))),
                        ButtonSegment(value: false, label: Text(context.t('No', 'Hapana'))),
                      ],
                      selected: {yes.contains(q.id)},
                      onSelectionChanged: (v) => setState(() {
                        v.first ? yes.add(q.id) : yes.remove(q.id);
                        result = null;
                      }),
                    ),
                  ],
                ),
              ),
            ),
          const Gap(8),
          FilledButton(
            key: const Key('body-result'),
            onPressed: () => setState(
              () => result = rateSelfCheck(
                widget.map,
                a.qs.where((q) => yes.contains(q.id)),
                weeks: s.pregnant ? s.weeks : 0,
                babyDays: s.babyDays,
                babyName: widget.map == 'baby' ? s.babyName : null,
              ),
            ),
            child: Text(context.t('What should I do?', 'Nifanye nini?')),
          ),
          if (result != null) ...[
            const Gap(16),
            if (result!.level == Level.green)
              AppCard(
                key: const Key('body-green'),
                color: C.greenSoft,
                border: C.greenSoft,
                child: Text(
                  context.t(
                    'No warning signs found in this check. This check cannot rule out every problem. If the pain gets worse, or you are worried, contact a health worker. You do not need a warning sign to ask for help.',
                    'Hakuna dalili za hatari zilizoonekana katika ukaguzi huu. Ukaguzi huu hauwezi kuondoa kila tatizo. Maumivu yakiongezeka, au ukiwa na wasiwasi, wasiliana na mhudumu wa afya. Huhitaji dalili ya hatari ili kuomba msaada.',
                  ),
                ),
              )
            else
              LevelBanner(result!.level, reasons: result!.reasons.map(context.tx).toList()),
            const Gap(12),
            if (result!.level == Level.red)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: C.red, minimumSize: const Size.fromHeight(56)),
                onPressed: () => context.push(Routes.emergency),
                icon: const Icon(Icons.emergency),
                label: Text(context.t('What to do now', 'Nini cha kufanya sasa')),
              ),
            if (result!.level == Level.amber && '${s.facility?['phone'] ?? ''}'.isNotEmpty)
              OutlinedButton.icon(
                onPressed: () => launchUrl(Uri(scheme: 'tel', path: '${s.facility!['phone']}'.replaceAll(' ', ''))),
                icon: const Icon(Icons.call),
                label: Text(context.t('Call ${s.facility!['name']}', 'Piga ${s.facility!['name']}')),
              ),
            const Gap(8),
            Text(
              context.t(
                'This check stays on your phone. To tell your clinic, do Today\'s check.',
                'Ukaguzi huu unabaki kwenye simu yako. Kuiambia kliniki, fanya Ukaguzi wa leo.',
              ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

/// A plain, friendly figure for the body map (mother, pregnant mother, or baby).
class _Figure extends CustomPainter {
  final bool baby, pregnant;
  _Figure({required this.baby, required this.pregnant});
  @override
  void paint(Canvas c, Size s) {
    final skin = Paint()..color = const Color(0xFF9A5B36);
    final cloth = Paint()..color = const Color(0xFFE4ECE6);
    final w = s.width, h = s.height;
    if (baby) {
      c.drawOval(Rect.fromCenter(center: Offset(w * .5, h * .16), width: w * .3, height: h * .26), skin);
      c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * .3, h * .28, w * .4, h * .42), Radius.circular(w * .12)), cloth);
      for (final x in [.22, .78]) {
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(w * x, h * .42), width: w * .1, height: h * .24), Radius.circular(w * .05)), skin);
      }
      for (final x in [.4, .6]) {
        c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(w * x, h * .8), width: w * .12, height: h * .26), Radius.circular(w * .06)), skin);
      }
      return;
    }
    c.drawOval(Rect.fromCenter(center: Offset(w * .5, h * .09), width: w * .16, height: h * .16), skin);
    c.drawRect(Rect.fromCenter(center: Offset(w * .5, h * .19), width: w * .07, height: h * .05), skin);
    final body = Path()
      ..moveTo(w * .36, h * .21)
      ..lineTo(w * .64, h * .21)
      ..quadraticBezierTo(w * (pregnant ? .76 : .66), h * .44, w * .64, h * .66)
      ..lineTo(w * .36, h * .66)
      ..quadraticBezierTo(w * .34, h * .44, w * .36, h * .21);
    c.drawPath(body, cloth);
    for (final (x, dx) in [(.3, -1.0), (.7, 1.0)]) {
      c.drawLine(
        Offset(w * (.5 + .14 * dx), h * .23),
        Offset(w * (x + .02 * dx), h * .52),
        skin
          ..strokeWidth = w * .06
          ..strokeCap = StrokeCap.round,
      );
    }
    for (final x in [.44, .56]) {
      c.drawLine(
        Offset(w * x, h * .66),
        Offset(w * x, h * .95),
        skin
          ..strokeWidth = w * .07
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_Figure o) => o.baby != baby || o.pregnant != pregnant;
}

/// For tests: the questions of one area by id.
BodyArea bodyArea(String map, String id) => bodyMaps[map]!.firstWhere((a) => a.id == id);
Tx bodyTitle(String map, String id) => bodyArea(map, id).title;
