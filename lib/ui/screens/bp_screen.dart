import 'package:go_router/go_router.dart';

import '../../app/router.dart';

import 'package:flutter/material.dart';

import '../../core/content.dart';
import '../../core/dates.dart';
import '../../core/rules.dart';
import '../theme.dart';
import '../widgets.dart';

/// Weekly blood pressure log with trend and 140/90 guidance (MA-12).
class BpScreen extends StatefulWidget {
  const BpScreen({super.key});
  @override
  State<BpScreen> createState() => _BpScreenState();
}

class _BpScreenState extends State<BpScreen> {
  final sys = TextEditingController(), dia = TextEditingController();
  final symptoms = <String>{};
  String by = 'chw';
  Triage? result;

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final rows = s.bpReadings;
    final pts = rows.map((r) => (parseTs(r['client_created_at'] as String), r['systolic'] as int, r['diastolic'] as int)).toList();
    final a = int.tryParse(sys.text), b = int.tryParse(dia.text);
    final valid = a != null && b != null && a >= 60 && a <= 260 && b >= 30 && b <= 180;
    final sym = {
      'headache': context.t('Severe headache', 'Kichwa kuuma sana'),
      'vision': context.t('Blurred vision', 'Kuona ukungu'),
      'pain_upper': context.t('Pain high in the belly', 'Maumivu juu ya tumbo'),
      'swelling': context.t('Swollen face or hands', 'Uso au mikono kuvimba'),
    };
    return Scaffold(
      appBar: AppBar(title: Text(context.t('Blood pressure', 'Shinikizo la damu')), actions: const [EmergencyButton()]),
      body: Pad(
        children: [
          if (pts.isNotEmpty) AppCard(child: BpChart(pts)),
          const Gap(8),
          Text(
            context.t(
              '140/90 or higher needs a health worker within 24 hours. 160/110 or higher, or 140/90 with headache, blurred vision, belly pain or swelling, means go now.',
              '140/90 au zaidi inahitaji mhudumu wa afya ndani ya saa 24. 160/110 au zaidi, au 140/90 pamoja na kichwa, kuona ukungu, maumivu ya tumbo au kuvimba, nenda sasa.',
            ),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          SectionTitle(context.t('Add a reading', 'Ongeza kipimo')),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('bp-sys'),
                  controller: sys,
                  onChanged: (_) => setState(() => result = null),
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
                  key: const Key('bp-dia'),
                  controller: dia,
                  onChanged: (_) => setState(() => result = null),
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: context.t('Bottom number', 'Namba ya chini')),
                ),
              ),
            ],
          ),
          const Gap(12),
          Text(context.t('Do you have any of these now?', 'Una mojawapo ya hizi sasa?'), style: Theme.of(context).textTheme.titleMedium),
          const Gap(8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in sym.entries)
                FilterChip(
                  label: Text(e.value),
                  selected: symptoms.contains(e.key),
                  onSelected: (v) => setState(() => v ? symptoms.add(e.key) : symptoms.remove(e.key)),
                ),
            ],
          ),
          const Gap(12),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'self', label: Text(context.t('Me', 'Mimi'))),
              ButtonSegment(value: 'chw', label: Text(context.t('CHW', 'Mhudumu'))),
              ButtonSegment(value: 'clinic', label: Text(context.t('Clinic', 'Kliniki'))),
            ],
            selected: {by},
            onSelectionChanged: (v) => setState(() => by = v.first),
          ),
          const Gap(16),
          FilledButton(
            key: const Key('bp-save'),
            onPressed: !valid
                ? null
                : () async {
                    final t = await context.appRead.addBp(a, b, symptoms.toList(), takenBy: by);
                    setState(() {
                      result = t;
                      sys.clear();
                      dia.clear();
                      symptoms.clear();
                    });
                  },
            child: Text(context.t('Save reading', 'Hifadhi kipimo')),
          ),
          if (result != null) ...[
            const Gap(16),
            LevelBanner(result!.level, reasons: result!.reasons.map(context.tx).toList()),
            if (result!.level == Level.red) ...[
              const Gap(8),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: C.red),
                onPressed: () => context.push(Routes.emergency),
                icon: const Icon(Icons.emergency),
                label: Text(context.t('What to do now', 'Nini cha kufanya sasa')),
              ),
            ],
          ],
          SectionTitle(context.t('History', 'Historia')),
          if (rows.isEmpty) EmptyNote(Icons.speed, context.t('No readings yet.', 'Bado hakuna vipimo.')),
          for (final r in rows.reversed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.circle, size: 14, color: levelColor(s.levelOf(r))),
              title: Text('${r['systolic']}/${r['diastolic']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              subtitle: Text(fmtDayYear(parseTs(r['client_created_at'] as String), s.lang)),
            ),
        ],
      ),
    );
  }
}
