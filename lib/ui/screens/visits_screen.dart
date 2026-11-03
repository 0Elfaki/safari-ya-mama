import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Visits, clinician-prescribed medicines and questions for the next visit (MA-32..MA-34).
class VisitsScreen extends StatelessWidget {
  const VisitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    final visits = s.allVisits;
    final upcoming = visits.where((v) => v.attended == null && !v.due.isBefore(today())).toList();
    final past = visits.where((v) => v.attended != null || v.due.isBefore(today())).toList().reversed.toList();
    return Pad(
      children: [
        SectionTitle(
          context.t('Questions for my next visit', 'Maswali ya kliniki ijayo'),
          trailing: IconButton.filledTonal(key: const Key('add-question'), onPressed: () => _addQuestion(context), icon: const Icon(Icons.add)),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: s.questions.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: EmptyNote(
                    Icons.help_outline,
                    context.t(
                      'Write down anything you want to ask, so you do not forget at the clinic.',
                      'Andika chochote unachotaka kuuliza, usisahau ukiwa kliniki.',
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (final q in s.questions)
                      CheckboxListTile(
                        value: q['answered'] == true,
                        onChanged: (_) => s.toggleQuestion(q['id'] as String),
                        title: Text(q['body'] as String, style: TextStyle(decoration: q['answered'] == true ? TextDecoration.lineThrough : null)),
                        secondary: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: context.t('Delete', 'Futa'),
                          onPressed: () => s.deleteRecord('visit_questions', q['id'] as String),
                        ),
                      ),
                  ],
                ),
        ),
        if (s.sharingActive)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              context.t('Your clinic can see these questions.', 'Kliniki yako inaweza kuona maswali haya.'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        SectionTitle(
          context.t('Coming up', 'Zinazokuja'),
          trailing: TextButton.icon(onPressed: () => _addVisit(context), icon: const Icon(Icons.add), label: Text(context.t('Add', 'Ongeza'))),
        ),
        if (upcoming.isEmpty) EmptyNote(Icons.event_available, context.t('No visits planned.', 'Hakuna ziara zilizopangwa.')),
        for (final v in upcoming)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(child: _visitRow(context, s, v)),
          ),
        if (!s.pregnant && s.nextVaccine != null) ...[
          SectionTitle(context.t('Next vaccines', 'Chanjo zijazo')),
          AppCard(
            child: Row2(
              icon: Icons.vaccines_outlined,
              title: s.vaccines.where((x) => !x.given && x.due == s.nextVaccine!.due).map((x) => x.dose.label).join(', '),
              sub: fmtDayYear(s.nextVaccine!.due, s.lang),
            ),
          ),
        ],
        SectionTitle(
          context.t('My medicines', 'Dawa zangu'),
          trailing: TextButton.icon(onPressed: () => _addMed(context), icon: const Icon(Icons.add), label: Text(context.t('Add', 'Ongeza'))),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: s.medications.isEmpty
              ? EmptyNote(
                  Icons.medication_outlined,
                  context.t('Only add medicines a health worker prescribed for you.', 'Ongeza dawa ulizoandikiwa na mhudumu wa afya tu.'),
                )
              : Column(
                  children: [
                    for (final m in s.medications)
                      Row2(
                        icon: Icons.medication_outlined,
                        title: '${m['name']} ${m['dose'] ?? ''}',
                        sub: (m['times'] as List).join(', '),
                        trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => s.deleteRecord('medications', m['id'] as String)),
                      ),
                  ],
                ),
        ),
        if (past.isNotEmpty) ...[
          SectionTitle(context.t('Past visits', 'Ziara zilizopita')),
          for (final v in past)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(child: _visitRow(context, s, v)),
            ),
        ],
      ],
    );
  }

  Widget _visitRow(BuildContext context, AppState s, Visit v) => Row2(
    icon: v.kind == 'anc'
        ? Icons.pregnant_woman
        : v.kind == 'pnc'
        ? Icons.child_care
        : Icons.event,
    tint: v.attended != null ? C.green : C.primary,
    title: context.tx(v.title),
    sub:
        '${fmtDayYear(v.due, s.lang)}${v.attended != null
            ? ' · ${context.t('attended', 'umehudhuria')}'
            : v.due.isBefore(today())
            ? ' · ${context.t('not recorded yet', 'bado haijaandikwa')}'
            : ''}${v.note != null && v.kind != 'other' ? ' · ${v.note}' : ''}',
    trailing: v.kind == 'other' && v.id != null ? Checkbox(value: v.attended != null, onChanged: (x) => s.markOwnVisit(v.id!, x == true)) : null,
  );

  Future<void> _addQuestion(BuildContext context) async {
    final c = TextEditingController();
    final s = context.appRead;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dc) => AlertDialog(
        title: Text(s.lang == 'sw' ? 'Swali jipya' : 'New question'),
        content: TextField(key: const Key('question-field'), controller: c, maxLength: 500, maxLines: 3, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dc, false), child: Text(s.lang == 'sw' ? 'Ghairi' : 'Cancel')),
          FilledButton(key: const Key('question-save'), onPressed: () => Navigator.pop(dc, true), child: Text(s.lang == 'sw' ? 'Hifadhi' : 'Save')),
        ],
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) await s.addQuestion(c.text.trim());
  }

  Future<void> _addVisit(BuildContext context) async {
    final s = context.appRead;
    final d = await showDatePicker(context: context, firstDate: today(), lastDate: addDays(today(), 365), initialDate: addDays(today(), 7));
    if (d == null || !context.mounted) return;
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dc) => AlertDialog(
        title: Text(s.lang == 'sw' ? 'Ziara ni ya nini?' : 'What is the visit for?'),
        content: TextField(controller: c, autofocus: true),
        actions: [FilledButton(onPressed: () => Navigator.pop(dc, true), child: Text(s.lang == 'sw' ? 'Hifadhi' : 'Save'))],
      ),
    );
    if (ok == true) await s.addAppointment(d, c.text.trim().isEmpty ? (s.lang == 'sw' ? 'Ziara ya kliniki' : 'Clinic visit') : c.text.trim());
  }

  Future<void> _addMed(BuildContext context) async {
    final s = context.appRead;
    final name = TextEditingController(), dose = TextEditingController();
    var prescribed = false;
    final times = <String>{'08:00'};
    await showDialog(
      context: context,
      builder: (dc) => StatefulBuilder(
        builder: (dc, set) => AlertDialog(
          title: Text(s.lang == 'sw' ? 'Dawa uliyoandikiwa' : 'Prescribed medicine'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: InputDecoration(labelText: s.lang == 'sw' ? 'Jina la dawa' : 'Medicine name'),
                ),
                const Gap(8),
                TextField(
                  controller: dose,
                  decoration: InputDecoration(labelText: s.lang == 'sw' ? 'Kiasi (mf. kidonge 1)' : 'Dose (e.g. 1 tablet)'),
                ),
                const Gap(8),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final t in ['08:00', '13:00', '20:00'])
                      FilterChip(label: Text(t), selected: times.contains(t), onSelected: (v) => set(() => v ? times.add(t) : times.remove(t))),
                  ],
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: prescribed,
                  onChanged: (v) => set(() => prescribed = v == true),
                  title: Text(s.lang == 'sw' ? 'Mhudumu wa afya aliniandikia dawa hii' : 'A health worker prescribed this for me'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dc), child: Text(s.lang == 'sw' ? 'Ghairi' : 'Cancel')),
            FilledButton(
              onPressed: !prescribed || name.text.trim().isEmpty || times.isEmpty
                  ? null
                  : () {
                      s.addMedication(name: name.text, dose: dose.text, times: times.toList()..sort());
                      Navigator.pop(dc);
                    },
              child: Text(s.lang == 'sw' ? 'Hifadhi' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}
