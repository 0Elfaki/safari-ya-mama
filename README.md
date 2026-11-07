# Safari ya Mama · Mother & caregiver app (Flutter)

Offline-first companion from pregnancy month 1 to baby month 9, in Kiswahili and English.

```bash
flutter pub get
flutter run                                   # offline demo (no backend configured: nothing leaves the phone)
flutter run --dart-define=SUPABASE_URL=https://<ref>.supabase.co --dart-define=SUPABASE_ANON_KEY=<anon key>
flutter analyze && flutter test               # app tests incl. 423 rule-parity cases
node supabase/tests/community_check.test.ts   # server community rules (same cases as the app)
flutter build appbundle --release --dart-define=...   # Play Store / internal testing
```

Web demo: `flutter build web` then open with `?demo=pregnant` or `?demo=baby` (`&lang=sw`, `&a11y=1`).

Structure: `lib/app` (app root, GoRouter routes and guards, Riverpod providers), `lib/core` (rules, content, design tokens in `core/theme`, shared widgets in `core/widgets`, encrypted Doctor's Note), `lib/data` (Hive store, outbox, Supabase sync, phone reminders, voice input), `lib/state` (AppState, owned by Riverpod and read with `context.app`), `lib/ui` (screens), `lib/features/<feature>/{domain,data,ui}` (feature-first folders for new features: `community` = Mothers' circle, `telemedicine` = appointments and video calls; put new features here). Server functions this app adds are in `supabase/migrations`. Visual audit: `flutter test test_screens/audit_test.dart --update-goldens` writes a screenshot of every screen to `test_screens/shots/`. Do not edit `*.g.dart`.

## Standalone repo

This repository holds the app only. The staff dashboard and the public website live in their own repositories.
`test/fixtures/rules_cases.json` is a copy of the shared rule cases (generated from the reference rules by `node tools/gen_rules_cases.mjs`);
refresh it whenever `rules_version` changes so `rules_parity_test.dart` keeps the phone's warning levels identical to the server's.

Product and technical docs: [docs/PRD.md](docs/PRD.md), [docs/TRD.md](docs/TRD.md), [docs/BACKEND_SCHEMA.md](docs/BACKEND_SCHEMA.md), [docs/USER_FLOWS.md](docs/USER_FLOWS.md).
