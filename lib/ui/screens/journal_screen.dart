import 'package:flutter/material.dart';

import '../../core/dates.dart';
import '../theme.dart';
import '../widgets.dart';

/// Private journal (MA-35). Never shown to staff (database policy: owner only).
class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});
  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final c = TextEditingController();
  int? mood;

  @override
  Widget build(BuildContext context) {
    final s = context.app;
    const faces = [
      Icons.sentiment_very_dissatisfied,
      Icons.sentiment_dissatisfied,
      Icons.sentiment_neutral,
      Icons.sentiment_satisfied,
      Icons.sentiment_very_satisfied,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(context.t('My journal', 'Shajara yangu')), actions: const [EmergencyButton()]),
      body: Pad(
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline, color: C.ink3, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  context.t('Private: only you can read this. Health workers never see it.', 'Binafsi: wewe tu unaweza kusoma. Wahudumu wa afya hawaioni.'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const Gap(12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 5; i++)
                IconButton(
                  iconSize: 36,
                  isSelected: mood == i + 1,
                  color: mood == i + 1 ? C.primary : C.ink3,
                  onPressed: () => setState(() => mood = i + 1),
                  icon: Icon(faces[i]),
                ),
            ],
          ),
          TextField(
            controller: c,
            maxLines: 4,
            decoration: InputDecoration(hintText: context.t('How was today? Symptoms, feeding, feelings…', 'Leo ilikuwaje? Dalili, kunyonyesha, hisia…')),
          ),
          const Gap(12),
          FilledButton(
            onPressed: () {
              if (c.text.trim().isEmpty && mood == null) return;
              s.addJournal(c.text, mood: mood);
              setState(() {
                c.clear();
                mood = null;
              });
            },
            child: Text(context.t('Save', 'Hifadhi')),
          ),
          const Gap(16),
          for (final j in s.journal)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(j['mood'] == null ? Icons.notes : faces[(j['mood'] as int) - 1], color: C.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(fmtDayYear(parseDay(j['entry_on'] as String), s.lang), style: Theme.of(context).textTheme.titleMedium),
                          if ((j['body'] as String?)?.isNotEmpty == true) Text(j['body'] as String),
                        ],
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => s.deleteRecord('journal_entries', j['id'] as String)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
