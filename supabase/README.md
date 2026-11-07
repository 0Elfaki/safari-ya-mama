# Supabase (server) for the Safari ya Mama app

Project: `qrkzzptfpcotirbvvmke` (eu-west-3). Apply new files in `migrations/` in name order
(`supabase db push`, or the SQL editor).

> The tables that existed before November 2026 were created without migration files. Run
> `supabase db pull` once against the project to bring that baseline into this folder.

## Status (7 Nov 2026)

| File | What it adds | On the live project |
|---|---|---|
| `migrations/20261105000000_note_shares.sql` | Doctor's Note encrypted QR sharing | **Applied** |
| `migrations/20261105010000_caregivers_proof_push_hardening.sql` | Caregiver invites, links and summary; verifiable-record ledger; push-token registration; AI usage counter; locks maintenance functions away from app users | **Applied** (5 Nov 2026) |
| `functions/ai-gateway` | MamaBot AI answers (Groq) | **Deployed**; answers start once the `GROQ_API_KEY` secret is set |
| `migrations/20261106000000_super_admin_role.sql` | `super_admin` role | **Applied** (5 Nov 2026) |
| `migrations/20261106000100_roles_permissions.sql` | Dashboard roles, permission helpers, super admin bootstrap, staff/admin sign-in checks, facilities, people, alert assignment, append-only audit log | **Applied** (5 Nov 2026) |
| `migrations/20261106000200_admin_kpis_monitoring.sql` | Whole-system KPIs (groups under 5 hidden), facility comparison, staff activity, audit viewer, system health | **Applied** (5 Nov 2026) |
| `migrations/20261106000300_content_management.sql` | Lesson channels/versions/sign-off, website pages, app content, media buckets, `app_content_manifest()` | **Applied** (5 Nov 2026) |
| `migrations/20261106000400_staff_caregivers.sql` | Caregiver names for the patient page | **Applied** (5 Nov 2026) |
| `functions/admin-users` | Staff and admin accounts for the dashboard (invite, temporary password, reset, deactivate) | **Deployed** |
| `tests/permissions.sql` | 168 role × action checks (staff, admins, website team, appointments, Mothers' circle, MamaBot library); runs in one transaction and rolls back | Passing (7 Nov 2026) |
| `functions/send-notifications` | Push notifications from `notification_queue` | Not deployed |
| `migrations/20261105020000_mother_setup_codes.sql` + `functions/mother-setup` | Clinic setup codes: staff set up a mother's account, she signs in with an 8-digit code (admins need their two-step code) | **Applied / deployed** (7 Nov 2026, `verify_jwt` off) |
| `migrations/20261106010000_community_bookings.sql` | Mothers' circle (community names, anonymous posts, reports, strikes, review queue) and appointments (slots, bookings, advice notes, join tracking), plus `community_kpis` and `booking_kpis` | **Applied** (7 Nov 2026). Changed before applying: "helpful" marks are switched off (`active`) instead of deleted, the reply-count trigger runs on insert/status change, and the KPI privacy rule hides 1 to 4 (0 shows 0) |
| `functions/community` | Stores posts after the content check (rules + AI) | **Deployed** (7 Nov 2026); AI layer starts once `GROQ_API_KEY` is set |
| `functions/telemed-join` | Video call link for a booked appointment (also super admins and Admins with their two-step code) | **Deployed** (7 Nov 2026); set `DAILY_API_KEY` + `DAILY_DOMAIN` for real calls (Jitsi until then) |
| `migrations/20261107000000…000600` | Website team roles; platform admins at any facility; KPI privacy 1–4 hidden; website CMS (pages, blog workflow, media, partners, impact, inbox, SEO, settings, revisions, previews); platform and extra KPIs; MamaBot answer library and safety phrases; `staff_slots` | **Applied** (7 Nov 2026) |
| `functions/site-files`, `functions/link-check`, `functions/contact-submit` | Website sitemap.xml and robots.txt; blog link checker; contact form with an email alert (`RESEND_API_KEY`, `CONTACT_NOTIFY_TO`, `CONTACT_NOTIFY_FROM`, optional) | **Deployed** (7 Nov 2026) |
| `tests/community_check.test.ts` | 31 content-check cases + 25 community-name checks, shared with the app (`node supabase/tests/community_check.test.ts`) | Passing (6 Nov 2026) |


## Deploying

```bash
# 0. once: install the Supabase CLI, then
supabase login
supabase link --project-ref qrkzzptfpcotirbvvmke

# 1. database
supabase db push            # applies migrations/ not yet on the project

# 2. MamaBot AI answers
supabase secrets set GROQ_API_KEY=...                # paste in your terminal, never in chat or git
# optional: supabase secrets set GROQ_MODEL=...      # default llama-3.3-70b-versatile
supabase functions deploy ai-gateway

# 3. push notifications (optional; the app's own phone reminders work without this)
supabase secrets set FCM_SERVICE_ACCOUNT="$(cat firebase-service-account.json)" CRON_SECRET="$(openssl rand -hex 32)"
supabase functions deploy send-notifications --no-verify-jwt
```

Then schedule the push sender in the SQL editor. Enable the `pg_net` extension first, and store the same
`CRON_SECRET` in Vault under the name `cron_secret`:

```sql
select cron.schedule('send-notifications', '*/5 * * * *', $$
  select net.http_post(
    url := 'https://qrkzzptfpcotirbvvmke.supabase.co/functions/v1/send-notifications',
    headers := jsonb_build_object('Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret'))
  );
$$);
```

Build the app with the Firebase dart-defines (`FCM_API_KEY`, `FCM_APP_ID`, `FCM_SENDER_ID`, `FCM_PROJECT_ID`) for push to register.

**The AI model.** `ai-gateway` calls Groq's chat completions API.
- **Model.** The default is `llama-3.3-70b-versatile`; set `GROQ_MODEL` to change it. Groq's model list changes, so check that the model is still offered in the Groq console.
- **Test Kiswahili first.** Before switching it on for mothers, ask about 20 real questions in Kiswahili and check the answers are correct, plain, and send danger signs to a facility. Open models are weaker in Kiswahili than in English.
- **Safety.** Urgent questions never reach the model, and questions are never stored.
- **Failures.** If Groq is slow (more than 12 seconds), busy, or returns an empty or cut-off answer, the app shows its scripted answer.

**Free plan.** The project pauses after about a week without use. Resume it in the dashboard, or upgrade the plan.

## Doctor's Note QR (`20261105000000_note_shares.sql`)

How it works:

1. **The phone encrypts the note.** It uses AES-256-GCM with a fresh random key for every share.
2. **Only the scrambled text goes to the server.** The phone uploads it with `create_note_share`, and the server can never read the note.
3. **The key travels only in the QR code.** The QR text is `SYM2:<share id>.<key in base64url>`.
4. **The clinician needs both** the QR (which holds the key) and a health-worker account. `open_note_share` gives out the scrambled text only to the roles `health_worker`, `facility_admin` and `programme_admin`, and writes every opening to `audit_log`.
5. **Shares end.** A share lasts at most 7 days, and the mother can stop it at any time with `revoke_note_share`.

### Opening a note in the staff dashboard (browser)

Paste this into the dashboard. `supabase` is the signed-in staff client. QR text can come from a camera
scanner or be typed. It has been checked against the app's encryption.

```js
// Returns { v, lang, name, made_at, sections: [{ letter, title, rows: [..] }], footer }
async function openDoctorNote(supabase, qrText) {
  const m = /^SYM2:([0-9a-f-]{36})\.([A-Za-z0-9_-]{43})$/i.exec(qrText.trim());
  if (!m) throw new Error('This is not a Safari ya Mama Doctor\'s Note QR code.');
  const { data, error } = await supabase.rpc('open_note_share', { p_id: m[1] });
  if (error) throw new Error(error.message); // expired, stopped by the mother, or not a health worker
  const row = Array.isArray(data) ? data[0] : data;
  const keyBytes = Uint8Array.from(atob(m[2].replace(/-/g, '+').replace(/_/g, '/') + '='), (c) => c.charCodeAt(0));
  const all = Uint8Array.from(atob(row.ciphertext), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('raw', keyBytes, 'AES-GCM', false, ['decrypt']);
  const clear = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: all.slice(0, 12) }, key, all.slice(12));
  return JSON.parse(new TextDecoder().decode(clear));
}
```

Show the sections in order (S, B, A, R) with the footer. Never store the decrypted note or the key.

## Verifiable record QR (`my_record_proof` / `verify_record_proof`)

The mother's QR text is `SYM1:<64 hex>`: the SHA-256 fingerprint of her dated vaccine and visit record.

- **Checking it.** A health worker calls `verify_record_proof(p_hash)`. It returns the dated record, the issue time, and `chain_ok`.
- **Tamper evidence.** Every proof is chained to the one before it, so editing any stored proof breaks the chain.
- **Audit.** Every check is written to `audit_log`.

## Caregivers

- **Invites.** `create_caregiver_invite` makes a 6-digit code that lasts 48 hours. A mother can have at most 5 open codes.
- **Accepting.** `accept_caregiver_invite` links the helper. After 10 wrong codes in an hour, further tries are refused.
- **What helpers see.** `caregiver_summary` returns only today's level and signs, the last 7 days, the next visit and vaccine, and (if she allowed alerts) any open alert. It never includes her journal, notes, questions or phone.
- **Stopping.** `stop_caregiver` ends a link at once.


## Dashboard (migrations 20261106…)

The dashboard repo (`../Safari-ya-mam-dashboard`) has no SQL of its own: everything is here.

- **Applied in parts.** The tool used to apply them refuses statements that contain DROP or DELETE,
  so the files avoid them (`create or replace trigger`, `alter policy`, archive instead of delete).
  Each file is safe to run again.
- **Super admin.** The owner email in `20261106000100` is promoted only once it is confirmed, and
  admin powers need MFA (`aal2`). Turn on "Leaked password protection" under Auth settings.
- **Permission tests.** Run `tests/permissions.sql` in the SQL editor. Every row must be `true`.
  Nothing persists.
- **admin-users.** Optional secret `DASHBOARD_URL` (the dashboard's address, for invite and reset
  links). Add the same address to Auth → URL Configuration → Redirect URLs.

## App content manifest (contract for the app)

`select public.app_content_manifest();` (anon or signed in). Stable shape, `schema: 1`:

```json
{
  "schema": 1,
  "content_version": 7,
  "generated_at": "2026-11-05T09:00:00Z",
  "media": { "bucket": "app-media", "path": "<PICTURE-ID>.webp" },
  "lessons": [{ "id": "danger-preg", "category": "preg", "format": "guide", "minutes": 3, "stage": "pregnant",
                "sort": 1, "version": 2, "art_keys": [], "step_pictures": ["PR-DANGER-P1", ""],
                "tr": { "en": { "title": "…", "steps": ["…"], "reviewed_by": "…", "reviewed_on": "2026-11-01" },
                        "sw": { "title": "…", "steps": ["…"], "reviewed_by": "…", "reviewed_on": "2026-11-01" } } }],
  "content": { "emergency.tz": { "kind": "emergency_numbers", "version": 1, "country_code": "TZ",
                                 "starts_on": null, "ends_on": null, "en": "…", "sw": "…" } }
}
```

- **When to download.** `content_version` goes up on every publish, unpublish or restore. Download the
  manifest only when it has changed, and cache it for offline use.
- **Lessons.** Only published lessons whose channels include `app`. `step_pictures[i]` belongs to step `i`;
  an empty string means that step has no picture. Each picture is at
  `<SUPABASE_URL>/storage/v1/object/public/app-media/<ID>.webp` (WebP, 1200×900, under 150 KB).
- **Content.** Only published, unexpired items. `kind` is one of `announcement`, `emergency_numbers`,
  `learn_cover` or `other`. Announcements that mention symptoms are published only with clinical sign-off.


## Mothers' circle (`20261106010000_community_bookings.sql`, `functions/community`)
Mothers share questions and experiences; wrong or unsafe health advice must not spread. A post goes
through these layers before other mothers see it:

1. **Rules** (`functions/community/check.ts` + `rules.json`; the app runs the same file while she types,
   `lib/features/community/domain/community_check.dart`). Plain, explainable matching in English and Kiswahili, word by word,
   sentence by sentence:
   - *insults* → refused (`block`); *phone numbers, emails* → she removes them (`fix`), the server also redacts;
   - *danger signs* → flagged `urgent`, she is sent to Emergency help at once, and the post goes to the top of the review queue;
   - *11 known myths* (stopping iron or ARVs, skipping clinic, herbs for labour, water before 6 months, things on the cord,
     throwing away colostrum, vaccine fears, alcohol for milk, honey for babies, eating less): a myth **stated as fact**
     waits for a health worker; the same myth **asked as a question** ("is it true…?") is published with the checked
     fact attached, because asking is how a mother finds the truth. "Don't stop taking iron" does not match (exceptions per rule);
   - *selling, links, miracle cures* → wait for a health worker.
2. **New members**: the first 2 posts wait for a health worker.
3. **AI second opinion** (Groq, same key as MamaBot) on whatever the rules would publish. It can only hold a post
   back (misinformation, harmful, spam, abuse with confidence ≥ 0.6), never publish something the rules held.
   The text goes to Groq without her name; nothing is logged.
4. **No AI available**: a post about medicines waits.
5. **After publishing**: 3 reports from different mothers hide a post; health workers publish, add a note, hide
   or remove from the dashboard (`community_review_queue`, `moderate_community_post`, audited).

Privacy: nobody sees who wrote a post (the read functions never return `author_id`). On every post she
chooses "Anonymous mother" or her community name: a username she picks (3–20 letters/numbers/`_`/`.`, at
most 4 numbers, no staff or app look-alikes, unique even against look-alikes, changed at most once in 30
days; rules in `rules.json` → `handle`). Repeat misinformation: "remove with strike" by a health worker;
2 strikes → her posts are reviewed for 30 days, 4 strikes → no posting for 30 days. The tables are closed to the app and the dashboard;
everything goes through the functions. Limits: 10 posts an hour per person, 1,000 characters.

Change the rules in `functions/community/rules.json`, copy it to `assets/content/community_rules.json`
(a test checks they are identical), add cases to `test/fixtures/community_cases.json`, and run both tests.

## Appointments and video calls (`20261106010000_community_bookings.sql`, `functions/telemed-join`)
- Staff open times with `staff_add_slots` (clinic visit or video call). A mother sees free times from 30 minutes
  ahead for 14 days (`open_slots`), books one (`book_slot`: locked, so two mothers can't take the same time;
  at most 3 upcoming), and can cancel (`cancel_booking`, frees the time again).
- Video: `telemed-join` hands out the link only to that mother and her facility's staff, from 15 minutes before
  until 30 minutes after the end. The room name is random and never returned by any other function.
- Provider: with `DAILY_API_KEY` and `DAILY_DOMAIN` set, private Daily.co rooms that expire, one token per person
  (staff join as owner). Without them it falls back to Jitsi (`JITSI_BASE`, default meet.jit.si) with a random
  64-character room name: good for testing, but use Daily or your own Jitsi server for real consultations.

```bash
supabase db push                                      # applies the migrations above
supabase functions deploy community
supabase functions deploy telemed-join
supabase functions deploy mother-setup --no-verify-jwt
supabase secrets set DAILY_API_KEY=... DAILY_DOMAIN=yourteam   # from the Daily.co dashboard; never in git or chat
```
