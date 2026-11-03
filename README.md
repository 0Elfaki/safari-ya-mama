# Safari ya Mama · Mother & caregiver app (Flutter)

Offline-first companion from pregnancy month 1 to baby month 9, in Kiswahili and English.

```bash
flutter pub get
flutter run                                   # offline demo (no backend configured: nothing leaves the phone)
flutter run --dart-define=SUPABASE_URL=https://<ref>.supabase.co --dart-define=SUPABASE_ANON_KEY=<anon key>
flutter analyze && flutter test               # 47 tests incl. 423 rule-parity cases
flutter build appbundle --release --dart-define=...   # Play Store / internal testing
```

Web demo: `flutter build web` then open with `?demo=pregnant` or `?demo=baby` (`&lang=sw`, `&a11y=1`).

Structure: `lib/core` (rules, content, generated lessons/assistant), `lib/data` (Hive store, outbox, Supabase sync), `lib/state` (AppState), `lib/ui` (theme, widgets, screens). Do not edit `*.g.dart`; regenerate with `node tools/gen_dart_content.mjs` from the repo root. See `../CLAUDE.md` for guardrails.

## Standalone repo

This repository holds the app only. The staff dashboard and the public website live in their own repositories.
`test/fixtures/rules_cases.json` is a copy of the shared rule cases (generated from the reference rules by `node tools/gen_rules_cases.mjs`);
refresh it whenever `rules_version` changes so `rules_parity_test.dart` keeps the phone's warning levels identical to the server's.
