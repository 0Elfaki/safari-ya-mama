import 'package:flutter/material.dart';

import '../../core/content.dart';
import '../../core/dates.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'child_check.dart';

const _avatarColors = [Color(0xFF22372D), Color(0xFF8D3F2D), Color(0xFF7A5C10)];

/// Round initial avatar (no photos: baby photos never leave the phone without consent).
class BabyAvatar extends StatelessWidget {
  final String name;
  final int index;
  final double size;
  const BabyAvatar(this.name, {super.key, this.index = 0, this.size = 48});
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: size / 2,
    backgroundColor: _avatarColors[index % _avatarColors.length],
    child: Text(
      name.isEmpty ? '?' : name.characters.first.toUpperCase(),
      style: TextStyle(fontFamily: display, fontWeight: FontWeight.w800, color: Colors.white, fontSize: size * .42),
    ),
  );
}

/// Chips to switch between babies (twins/triplets). Hidden when there is one baby.
class BabySwitcher extends StatelessWidget {
  const BabySwitcher({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final all = s.babies;
    if (all.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (i, b) in all.indexed)
            ChoiceChip(
              key: Key('baby-${b['id']}'),
              avatar: BabyAvatar(s.nameOf(b), index: i, size: 24),
              label: Text(s.nameOf(b)),
              selected: s.baby?['id'] == b['id'],
              onSelected: (_) => s.selectBaby(b['id'] as String),
            ),
        ],
      ),
    );
  }
}

/// Child profile: every baby she follows, with details she can correct (name, sex,
/// date of birth, birth weight), growth, vaccines and milestones at a glance.
class ChildProfileScreen extends StatelessWidget {
  const ChildProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final all = s.babies;
    void go(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    final groups = <String, int>{};
    for (final b in all) {
      groups[b['dob'] as String] = (groups[b['dob'] as String] ?? 0) + 1;
    }
    return Scaffold(
      appBar: AppBar(title: Text(context.t('My children', 'Watoto wangu')), actions: const [EmergencyButton()]),
      body: Pad(
        children: [
          for (final (i, b) in all.indexed) ...[
            _ChildCard(
              b,
              index: i,
              groupSize: groups[b['dob']] ?? 1,
              onEdit: () => go(ChildEditScreen(babyId: b['id'] as String)),
            ),
            const Gap(12),
          ],
          OutlinedButton.icon(
            key: const Key('add-child'),
            onPressed: () => go(const ChildEditScreen()),
            icon: const Icon(Icons.person_add_alt),
            label: Text(context.t('Add a baby (for example, a twin)', 'Ongeza mtoto (kwa mfano, pacha)')),
          ),
          const Gap(16),
          Text(
            context.t(
              'Each baby has their own vaccines, weights, milestones and warning-sign check. Always follow the child health card.',
              'Kila mtoto ana chanjo, uzito, hatua za makuzi na ukaguzi wa dalili zake mwenyewe. Fuata kadi ya afya ya mtoto daima.',
            ),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _ChildCard extends StatelessWidget {
  final Map<String, dynamic> b;
  final int index;
  final int groupSize; // 2 = twins, 3 = triplets
  final VoidCallback onEdit;
  const _ChildCard(this.b, {required this.index, required this.groupSize, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final id = b['id'] as String;
    final name = s.nameOf(b);
    final days = s.ageDays(b);
    final born = parseDay(b['dob'] as String);
    final w = s.growthOf(id);
    final vx = s.vaccinesFor(id);
    final given = vx.where((v) => v.given).length;
    final next = vx.where((v) => !v.given).firstOrNull;
    final sex = switch (b['sex']) {
      'f' => context.t('Girl', 'Msichana'),
      'm' => context.t('Boy', 'Mvulana'),
      _ => null,
    };
    final age = days < 61 ? context.t('$days days', 'siku $days') : context.t('${(days / 30.44).floor()} months', 'miezi ${(days / 30.44).floor()}');
    Widget fact(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(fontFamily: display, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
    return AppCard(
      key: Key('child-$id'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              BabyAvatar(name, index: index, size: 56),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: Theme.of(context).textTheme.titleLarge),
                    Text(
                      [
                        ?sex,
                        if (groupSize == 2) context.t('Twin', 'Pacha') else if (groupSize > 2) context.t('Triplet', 'Mtoto wa watatu'),
                        context.t('born ${fmtDayYear(born, 'en')}', 'alizaliwa ${fmtDayYear(born, 'sw')}'),
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              IconButton(key: Key('edit-$id'), tooltip: context.t('Edit', 'Hariri'), onPressed: onEdit, icon: const Icon(Icons.edit_outlined)),
            ],
          ),
          const Gap(16),
          Row(
            children: [
              fact(context.t('age', 'umri'), age),
              fact(
                context.t('birth weight', 'uzito wa kuzaliwa'),
                b['birth_weight_g'] == null ? '—' : '${((b['birth_weight_g'] as int) / 1000).toStringAsFixed(2)} kg',
              ),
              fact(context.t('latest weight', 'uzito wa mwisho'), w.isEmpty ? '—' : '${((w.last['weight_g'] as int) / 1000).toStringAsFixed(2)} kg'),
            ],
          ),
          const Gap(12),
          Row(
            children: [
              fact(context.t('vaccines given', 'chanjo zilizotolewa'), '$given / ${vaccineDoses.length}'),
              fact(context.t('milestones', 'hatua za makuzi'), '${s.milestonesDone(id)}'),
              fact(context.t('next vaccine', 'chanjo ijayo'), next == null ? '—' : '${next.dose.label}, ${fmtDay(next.due, s.lang)}'),
            ],
          ),
          const Gap(16),
          Text(context.t('Daily checks', 'Ukaguzi wa kila siku'), style: Theme.of(context).textTheme.titleMedium),
          const Gap(6),
          CheckHistoryStrip(s.checkHistory(id), key: Key('history-$id')),
          if (s.baby?['id'] != id) ...[
            const Gap(12),
            TextButton(onPressed: () => s.selectBaby(id), child: Text(context.t('Show $name in My baby', 'Onyesha $name kwenye Mtoto wangu'))),
          ],
        ],
      ),
    );
  }
}

/// Name, sex and weight fields for one baby (used at birth, when adding and when editing).
class BabyFields extends StatelessWidget {
  final int index;
  final bool showHeading;
  final TextEditingController name, weight;
  final String? sex;
  final ValueChanged<String?> onSex;
  const BabyFields({
    super.key,
    required this.index,
    required this.name,
    required this.weight,
    required this.sex,
    required this.onSex,
    this.showHeading = false,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (showHeading)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(context.t('Baby ${index + 1}', 'Mtoto ${index + 1}'), style: Theme.of(context).textTheme.titleMedium),
        ),
      TextField(
        key: Key('baby-name-$index'),
        controller: name,
        decoration: InputDecoration(labelText: context.t("Baby's name (optional)", 'Jina la mtoto (si lazima)')),
      ),
      const Gap(12),
      SegmentedButton<String>(
        emptySelectionAllowed: true,
        segments: [
          ButtonSegment(value: 'f', label: Text(context.t('Girl', 'Msichana'))),
          ButtonSegment(value: 'm', label: Text(context.t('Boy', 'Mvulana'))),
        ],
        selected: {?sex},
        onSelectionChanged: (v) => onSex(v.isEmpty ? null : v.first),
      ),
      const Gap(12),
      TextField(
        key: Key('baby-weight-$index'),
        controller: weight,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: context.t('Birth weight in kg (optional)', 'Uzito wa kuzaliwa kwa kilo (si lazima)')),
      ),
    ],
  );
}

/// Birth weight in grams from "2.4" / "2,4" kg; null when empty or outside 0.3–7 kg.
int? parseBirthWeight(String text) {
  final kg = double.tryParse(text.replaceAll(',', '.').trim());
  if (kg == null) return null;
  final g = (kg * 1000).round();
  return g >= 300 && g <= 7000 ? g : null;
}

/// Edit a child's details, or add a baby when [babyId] is null.
class ChildEditScreen extends StatefulWidget {
  final String? babyId;
  const ChildEditScreen({super.key, this.babyId});
  @override
  State<ChildEditScreen> createState() => _ChildEditScreenState();
}

class _ChildEditScreenState extends State<ChildEditScreen> {
  final name = TextEditingController(), weight = TextEditingController();
  String? sex;
  late DateTime dob;
  String? weightError;

  @override
  void initState() {
    super.initState();
    final s = context.appRead;
    final b = widget.babyId == null ? null : s.babyById(widget.babyId!);
    dob = b != null ? parseDay(b['dob'] as String) : (s.dob ?? today()); // a new twin defaults to the same birthday
    name.text = (b?['name'] as String?) ?? '';
    sex = b?['sex'] as String?;
    if (b?['birth_weight_g'] != null) weight.text = ((b!['birth_weight_g'] as int) / 1000).toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final editing = widget.babyId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? context.t('Edit details', 'Hariri taarifa') : context.t('Add a baby', 'Ongeza mtoto')),
        actions: const [EmergencyButton()],
      ),
      body: Pad(
        children: [
          Text(context.t('Date of birth', 'Tarehe ya kuzaliwa'), style: Theme.of(context).textTheme.titleMedium),
          const Gap(8),
          OutlinedButton.icon(
            icon: const Icon(Icons.cake_outlined),
            label: Text(fmtDayYear(dob, s.lang)),
            onPressed: () async {
              final d = await showDatePicker(context: context, firstDate: addDays(today(), -300), lastDate: today(), initialDate: dob);
              if (d != null) setState(() => dob = d);
            },
          ),
          const Gap(16),
          BabyFields(index: 0, name: name, weight: weight, sex: sex, onSex: (v) => setState(() => sex = v)),
          if (weightError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(weightError!, style: const TextStyle(color: C.red)),
            ),
          if (editing && s.babyById(widget.babyId!)?['dob'] != isoDay(dob)) ...[
            const Gap(12),
            AppCard(
              color: C.amberSoft,
              border: C.amberSoft,
              child: Text(
                context.t(
                  'Changing the date of birth moves the vaccine dates shown here. Your clinic keeps the dates on the child health card.',
                  'Kubadilisha tarehe ya kuzaliwa kunasogeza tarehe za chanjo zinazoonyeshwa hapa. Kliniki inafuata tarehe za kadi ya mtoto.',
                ),
              ),
            ),
          ],
          const Gap(24),
          FilledButton(
            key: const Key('child-save'),
            onPressed: () async {
              final g = parseBirthWeight(weight.text);
              if (weight.text.trim().isNotEmpty && g == null) {
                setState(() => weightError = context.t('Birth weight must be between 0.3 and 7 kg.', 'Uzito wa kuzaliwa uwe kati ya kilo 0.3 na 7.'));
                return;
              }
              if (editing) {
                await s.updateBaby(widget.babyId!, {
                  'name': name.text.trim().isEmpty ? null : name.text.trim(),
                  'sex': sex,
                  'dob': isoDay(dob),
                  'birth_weight_g': g,
                });
              } else {
                final twinOf = s.babies.where((b) => b['dob'] == isoDay(dob)).length;
                final id = await s.addBaby(dob: dob, name: name.text, sex: sex, weightG: g, pregnancyId: s.baby?['pregnancy_id'] as String?, order: twinOf + 1);
                await s.selectBaby(id);
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(context.t('Save', 'Hifadhi')),
          ),
        ],
      ),
    );
  }
}

/// Record the birth (one baby, twins or triplets): switches the app to baby mode.
class RecordBirthScreen extends StatefulWidget {
  const RecordBirthScreen({super.key});
  @override
  State<RecordBirthScreen> createState() => _RecordBirthScreenState();
}

class _RecordBirthScreenState extends State<RecordBirthScreen> {
  DateTime dob = today();
  int count = 1;
  final names = List.generate(3, (_) => TextEditingController());
  final weights = List.generate(3, (_) => TextEditingController());
  final sexes = List<String?>.filled(3, null);

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('My baby is born', 'Mtoto amezaliwa')), actions: const [EmergencyButton()]),
      body: Pad(
        children: [
          Text(context.t('Congratulations!', 'Hongera!'), style: Theme.of(context).textTheme.headlineSmall),
          const Gap(16),
          OutlinedButton.icon(
            icon: const Icon(Icons.cake_outlined),
            label: Text(fmtDayYear(dob, s.lang)),
            onPressed: () async {
              final d = await showDatePicker(context: context, firstDate: addDays(today(), -60), lastDate: today(), initialDate: dob);
              if (d != null) setState(() => dob = d);
            },
          ),
          const Gap(16),
          Text(context.t('How many babies?', 'Watoto wangapi?'), style: Theme.of(context).textTheme.titleMedium),
          const Gap(8),
          Choice<int>(
            keyPrefix: 'count',
            value: count,
            onChanged: (v) => setState(() => count = v),
            options: [
              (1, Icons.child_care, context.t('One', 'Mmoja')),
              (2, Icons.people_outline, context.t('Twins', 'Pacha')),
              (3, Icons.groups_outlined, context.t('Triplets', 'Watatu')),
            ],
          ),
          const Gap(16),
          for (var i = 0; i < count; i++) ...[
            AppCard(
              child: BabyFields(
                index: i,
                showHeading: count > 1,
                name: names[i],
                weight: weights[i],
                sex: sexes[i],
                onSex: (v) => setState(() => sexes[i] = v),
              ),
            ),
            const Gap(12),
          ],
          if (count > 1)
            AppCard(
              color: C.amberSoft,
              border: C.amberSoft,
              child: Text(
                context.t(
                  'Twins and triplets are often small and early. Keep each baby warm, skin to skin, and breastfeed each one at least 8 times a day. Go to the clinic for every postnatal visit.',
                  'Mapacha mara nyingi ni wadogo na huzaliwa mapema. Mweke kila mtoto katika joto, ngozi kwa ngozi, na nyonyesha kila mmoja angalau mara 8 kwa siku. Hudhuria kila kliniki ya baada ya kujifungua.',
                ),
              ),
            ),
          const Gap(24),
          FilledButton(
            key: const Key('birth-save'),
            onPressed: () async {
              await s.recordBirth(
                dob: dob,
                children: [for (var i = 0; i < count; i++) NewBaby(name: names[i].text, sex: sexes[i], weightG: parseBirthWeight(weights[i].text))],
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: Text(context.t('Save and switch to baby mode', 'Hifadhi na badili kuwa hali ya mtoto')),
          ),
          const Gap(16),
          AppCard(
            color: C.redSoft,
            border: C.redSoft,
            child: Text(
              context.t(
                'Mother: one or more pads soaked in an hour, or clots bigger than an egg, means go now.',
                'Mama: pedi moja au zaidi kulowa ndani ya saa moja, au mabonge makubwa kuliko yai, nenda sasa.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
