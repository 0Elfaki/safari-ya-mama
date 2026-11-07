# Safari ya Mama: Product Requirements Document (PRD)

| | |
|---|---|
| Product | Safari ya Mama mother and caregiver app (Flutter), plus the server parts in `supabase/` |
| Owner | Zatii Technologies (`pubspec.yaml`) |
| Version described | App `1.0.0+1`, warning rules `2026.12`, community rules `version 1` |
| Date | 7 November 2026 |
| Related | [TRD.md](TRD.md) (how it is built) · [USER_FLOWS.md](USER_FLOWS.md) (step-by-step flows) · [BACKEND_SCHEMA.md](BACKEND_SCHEMA.md) (tables and server functions) |

This document describes what the app must do and why. Every requirement is taken from the code in this
repository. Where the code does not decide something, the text says **to be decided**.

---

## 1. Overview and problem

Safari ya Mama is a phone companion for women in Tanzania and East Africa, from pregnancy month 1 until the
baby is 9 months old. It works in Kiswahili and English.

**The problem.**
- Many mothers do not know the danger signs in pregnancy, after birth, or in a young baby. They reach care late.
- Phones are often shared, data is expensive, and the signal is often weak or missing.
- Mothers get health advice from family, neighbours and social media. Some of it is wrong and harmful
  (for example: stop iron tablets, give water to a newborn, put ash on the cord).
- Clinics have little time. Mothers travel far for short questions.

**What the app does.**
- A 1-minute daily check gives a green, amber or red result, with clear next steps, even with no signal.
- It tracks the pregnancy, clinic visits, blood pressure, baby movements, contractions, the baby's growth,
  feeds, milestones and vaccines.
- It teaches with picture lessons and answers questions (MamaBot).
- It lets mothers talk to each other safely in the **Mothers' circle**, where wrong health advice is caught.
- It lets a mother **book a clinic visit or a video call** with a health worker at her facility.
- It shares what she chooses with her clinic and with helpers (caregivers).

---

## 2. Goals and non-goals

### Goals
1. Help a mother recognise danger signs early and go to care quickly.
2. Keep working with no signal. Nothing important depends on the internet.
3. Keep her records safe and backed up (sign-in is required when a server is configured).
4. Stop wrong health advice from spreading between mothers.
5. Make it easy to see a health worker (booked visit or video call).
6. Give clinics and programme teams the numbers they need (KPIs), without exposing small groups of mothers.

### Non-goals
- The app never diagnoses, never names an illness and never says "you are fine" (`lib/core/rules.dart`).
- AI never sets, raises or lowers a warning level (`lib/core/rules.dart`, `supabase/functions/ai-gateway`).
- The app does not prescribe or change medicines.
- The app is not an emergency service. Emergency help points her to a facility and to people to call.
- The staff dashboard and the public website are **not** in this repository. They live in their own
  repositories. This document lists only what the dashboard needs from this app and server (section 7).

---

## 3. Users and personas

| User | Role in the system (`profiles.role`) | What they do |
|---|---|---|
| **Pregnant woman** | `mother` | Daily check, pregnancy tracking, visits, lessons, MamaBot, Mothers' circle, appointments |
| **Mother of a baby 0–9 months** (one baby, twins or triplets) | `mother` | Same, with baby checks, growth, feeds, milestones and vaccines |
| **Caregiver / helper** (partner, family) | `caregiver` | Sees a short summary the mother chose to share; can get alerts |
| **Health worker** | `health_worker` | Dashboard: follows mothers who share with the facility, answers alerts, moderates the circle, runs appointments and video calls |
| **Facility admin** | `facility_admin` | Health worker powers plus facility staff and settings |
| **Programme admin** ("admin") | `programme_admin` | Whole-system KPIs, facilities, content, accounts |
| **Super admin** | `super_admin` | Everything, incl. creating admins. Needs MFA |
| Website team | `editor`, `author`, `clinical_reviewer`, `viewer` | Website and blog only. Never see mothers' data (`20261107000000_website_roles.sql`) |

### Personas (short)
- **Amina, 24, first pregnancy, rural.** Shared basic Android phone, little data, reads Kiswahili slowly.
  Needs: big pictures, voice input, read-aloud, short words, works offline, private on a shared phone.
- **Neema, 31, baby of 3 months, town.** Has WhatsApp, hears conflicting advice from relatives.
  Needs: a safe place to ask other mothers, checked facts, a quick video call instead of a long trip.
- **Juma, Amina's husband.** Wants to know if she is OK and when the next visit is.
  Needs: a simple summary and an alert if something is red. Must not see her journal.
- **Sister Rehema, nurse at a health centre.** Busy. Needs: an ordered queue (urgent first), a calendar of
  bookings, one-tap video calls, and a quick way to write advice.

---

## 4. Product principles

| Principle | What it means in the app |
|---|---|
| **Offline first** | Every record is saved on the phone first (Hive) and sent later from an outbox. The daily check, its result, Emergency help, lessons, reminders and the scripted MamaBot work with no signal. |
| **Safety first** | Warning levels come only from fixed rules, identical on phone and server. Emergency help is reachable from every screen, before sign-in, and on the PIN lock screen. Danger words in MamaBot or in a post send her to Emergency help. |
| **Privacy** | Consent switches are all off by default. The journal is never shared. Reminders show generic text on the lock screen by default. In the Mothers' circle her real name and phone are never shown. Small groups (1–4 people) are hidden in KPIs. |
| **Simple for low literacy** | Picture tiles, one question per screen, large buttons, colour plus icon plus word (colour is never the only cue), read-aloud, voice input. |
| **Bilingual** | Every text exists in Kiswahili and English (`Tx(en, sw)`). Kiswahili is the default language (`AppState.lang` defaults to `sw`). |
| **Health workers stay in charge** | AI can only hold content back or add a labelled answer. Health workers publish, remove, and give advice. |

---

## 5. Navigation summary

- **Bottom tabs (5):** Home · My Care · MamaBot · Community · Learn (`lib/ui/screens/shell.dart`).
- **Top bar on every tab:** menu (☰), notifications bell with unread count, Emergency shortcut.
- **Side menu (☰)** (`lib/ui/screens/app_drawer.dart`): greeting and stage; the 5 tabs; "My health":
  Appointments, Clinic visit schedule, Doctor's Note, Notifications and reminders, Profile and settings;
  language switch; **Emergency help** button at the bottom.
- **Home** (`lib/ui/screens/home_screen.dart`), top to bottom: greeting; stage hero card (weeks and days,
  baby size, due date; or baby age and next vaccine); today's check; next appointment; "How can we help?"
  with 4 picture tiles (See a health worker, Ask a question, Talk to other mothers, My pregnancy / My baby);
  daily care; danger signs and emergency care plan; lessons "For you".

---

## 6. Feature requirements

Each requirement has an ID. "Must" means it is built and tested or required for release.
Status marks: **Built** (in the app code), **Server pending** (app built, server part not yet live; see section 10).

### 6.1 Account, sign-in and setup (ACC)

| ID | Requirement | Status |
|---|---|---|
| ACC-01 | When the app is built with a server (`SUPABASE_URL`, `SUPABASE_ANON_KEY`), sign-in is required before setup or use. Without a server the app runs as an offline demo and sends nothing. | Built |
| ACC-02 | Three ways to sign in, no password: (a) phone number + 6-digit SMS code; (b) 8-digit clinic setup code; (c) Google account (only in builds with Google client IDs, Android/iOS). | Built |
| ACC-03 | Clinic setup code: created by staff in the dashboard through `mother-setup`; 8 digits; valid 24 hours; single use; a new code cancels the old one; only a hash is stored; 10 failed tries per hour per client are allowed, then refused. | Server pending |
| ACC-04 | After sign-in, a returning mother (records already on the server) goes straight to Home. Her server records are merged before anything from the phone is sent, so nothing is duplicated. A new mother answers the setup questions. | Built |
| ACC-05 | Setup questions (5 steps): first name; pregnant or baby born, with dates; emergency contacts and clinic; consent (all off by default); optional 4-digit PIN. | Built |
| ACC-06 | Consent is per kind and per facility: `share_with_facility`, `share_with_chw`, `reminders_sms`, `reminders_whatsapp`, `photo_storage`, `research`. Every change is kept as history. | Built |
| ACC-07 | Optional 4-digit PIN for shared phones. When the app goes to the background, all open screens close and the PIN is asked on return. | Built |
| ACC-08 | Emergency help and emergency contacts open without sign-in and without the PIN. | Built |
| ACC-09 | She can sign out and delete all her data from Profile. | Built |

### 6.2 Daily check and warning levels (CHK)

| ID | Requirement | Status |
|---|---|---|
| CHK-01 | 1-minute daily check: how she feels, danger signs, baby movements (from 20 weeks), and for a baby: signs and feeding, in three coloured steps (green, orange, red), all always shown. | Built |
| CHK-02 | Result is green, amber or red. Amber: contact a health worker today / within 24 hours. Red: go to a facility now, with an Emergency help button. | Built |
| CHK-03 | Levels come only from `lib/core/rules.dart` on the phone and the same rules in the database (`rate_checkin`, `rate_bp`, `bp_rise_3wk`). The server may raise a level (`server_level`); the app shows the higher one. | Built |
| CHK-04 | Phone and server rules must give identical results: `test/rules_parity_test.dart` runs the shared cases (`test/fixtures/rules_cases.json`). Refresh the fixture whenever `rules_version` changes. | Built |
| CHK-05 | Blood pressure log with trend and 140/90 guidance. | Built |
| CHK-06 | Baby movements: one answer a day; fewer than usual → amber, not moving → red. No kick-count target. | Built |
| CHK-07 | Contraction timer: start/stop, shows length and gap. No number-based verdict. | Built |
| CHK-08 | Body self-check: tap where it hurts, answer yes/no, get a safe next step. Never names an illness. | Built |
| CHK-09 | Twins and triplets: each baby has its own checks; a sign in any baby counts. | Built |

### 6.3 My Care: tracking and records (CARE)

| ID | Requirement | Status |
|---|---|---|
| CARE-01 | Pregnancy progress (weeks, days, trimester, due date) or her recovery after birth. | Built |
| CARE-02 | Clinic visit schedule (ANC and PNC) plus her own visits; mark attended. | Built |
| CARE-03 | Vaccines for each baby: given / due / coming. | Built |
| CARE-04 | Baby growth, feeds and milestones; child profile per baby. | Built |
| CARE-05 | Medicines prescribed by a clinician, and questions for the next visit. | Built |
| CARE-06 | Birth plan and preparation checklist. | Built |
| CARE-07 | Private journal. Never shown to staff or caregivers (database policy: owner only). | Built |
| CARE-08 | Local meal tracker (Tanzanian foods), kept on the phone only. | Built |

### 6.4 MamaBot (BOT)

| ID | Requirement | Status |
|---|---|---|
| BOT-01 | Two doors: "Check symptoms" opens the daily check (rules only); the chat answers questions. | Built |
| BOT-02 | Scripted answers from approved content always work, offline. | Built |
| BOT-03 | When online and signed in, a non-urgent question may also go to the AI gateway (Groq). Only the question text and her stage are sent, never her name, phone or records. | Built (needs `GROQ_API_KEY`) |
| BOT-04 | Urgent words (bleeding, fits, baby not moving, self-harm, and Kiswahili equivalents) never reach the AI. Both app and server return a fixed safety message and an Emergency button. | Built |
| BOT-05 | AI answers carry the label "AI answer · not medical advice". If the AI is slow (>12 s), busy, empty or cut off, the scripted answer is shown. | Built |
| BOT-06 | Limit: 30 AI questions per person per 24 hours; 600 characters per question. Questions are not stored; only who and when is counted. | Built |
| BOT-07 | Voice input: the phone's own speech recogniser fills the text box; nothing is sent until she presses Send; the microphone is asked for only on first tap. | Built |

### 6.5 Learn (LRN)

| ID | Requirement | Status |
|---|---|---|
| LRN-01 | Picture-first lessons with steps, key facts, "When to get help", quizzes, related lessons, sources and clinical review status. | Built |
| LRN-02 | Read-aloud (text to speech) option. | Built |
| LRN-03 | First aid ("Keep baby safe") with animations; works offline. | Built |
| LRN-04 | Lessons "For you" picked by stage. | Built |
| LRN-05 | Download lessons and content published in the dashboard (`app_content_manifest()`), cache them offline, refresh only when `content_version` changes. | **Not built** (section 10) |

### 6.6 Sharing, records and helpers (SHR)

| ID | Requirement | Status |
|---|---|---|
| SHR-01 | Doctor's Note: a short SBAR summary made on the phone; she chooses the sections. Shown on screen, or shared by QR. | Built |
| SHR-02 | Doctor's Note QR is encrypted on the phone (AES-256-GCM, new key per share). The key is only in the QR. Only health workers and admins can open it, and every opening is logged. Shares last 1, 3 or 7 days and she can stop one at any time. | Built |
| SHR-03 | Verifiable record QR (`SYM1:` + SHA-256 of her dated vaccine and visit record). Staff verify with `verify_record_proof`; proofs are chained so edits are detectable; every check is logged. | Built |
| SHR-04 | Caregivers: she makes a 6-digit code (48 hours, at most 5 open codes); the helper signs in with their own phone and enters it. 10 wrong codes in an hour are refused. | Built |
| SHR-05 | A caregiver sees only: today's level and signs, the last 7 days, the next visit and vaccine, and (if she allowed) open alerts. Never her journal, notes, questions or phone. She can stop a link at once. | Built |

### 6.7 Reminders and notifications (NOT)

| ID | Requirement | Status |
|---|---|---|
| NOT-01 | Phone reminders scheduled on the phone (no signal, no SMS cost): daily check, iron/folic or medicine, baby movements from 20 weeks, the evening before visits and vaccines, and booked appointments. | Built |
| NOT-02 | By default the lock screen shows only a generic text ("Safari ya Mama: you have a reminder"). She can turn on "Show details". | Built |
| NOT-03 | Push notifications (FCM) carry no health data, only a template key. | Built in app; sender **not deployed** |
| NOT-04 | Notifications screen: today's reminders, what is coming, anything the clinic raised, reminder settings. | Built |

### 6.8 Emergency (EMR)

| ID | Requirement | Status |
|---|---|---|
| EMR-01 | Emergency care plan: what to do now, where to go, who to call, what to bring. Fully offline; calls use the phone dialler. | Built |
| EMR-02 | Reachable from every tab's top bar, the side menu, red results, urgent MamaBot answers, urgent posts, and the booking screens. Open before sign-in and on the lock screen. | Built |
| EMR-03 | She edits her own plan (facility, one person to call, transport). Kept on the phone only. | Built |

### 6.9 Mothers' circle (Community) (COM)

Purpose: a safe space where mothers ask and share, and where wrong or unsafe health advice does not spread.
Code: `lib/features/community/`, `supabase/functions/community/`, migration `20261106010000_community_bookings.sql`.

#### Requirements

| ID | Requirement |
|---|---|
| COM-01 | The circle needs sign-in and internet. Without internet she sees the last feed saved on the phone, with a "No internet" note. |
| COM-02 | Feed of posts, newest first, 30 at a time (server maximum 50), filter by topic: Pregnancy, Birth, Breastfeeding, Baby care, Feelings, Other. |
| COM-03 | She can write a post (2–1,000 characters), choose a topic, type or speak. She can reply to a published post (one level of replies). |
| COM-04 | **Who others see**, chosen on every post and reply: "Anonymous mother" (default) or her **community name**. Her last choice is remembered on the phone. Her real name and phone are never shown. Other mothers also see her stage ("28 weeks pregnant", "baby 3 months"). Health workers post with their first name and a "Health worker" badge. |
| COM-05 | **Community name rules** (`rules.json` → `handle`, same check on phone and server): 3–20 characters; only letters, numbers, `_` and `.`; starts with a letter; no `__`, `..`, `_.` and does not end with `_` or `.`; at most 4 digits; must not look like staff or the app (contains admin, moderator, safari, official, support, doctor, daktari, nurse, muuguzi, mhudumu, midwife, mkunga, clinic, kliniki, hospital, hospitali, staff, mamabot, ministry, wizara, govt, serikali; or starts with dr, mod, team, dkt); no offensive words. |
| COM-06 | Names must be unique after look-alike normalisation: lower case, remove `_` and `.`, read 0→o, 3→e, 4→a, 5→s, 7→t, 8→b, and 1, i, l as one letter. "Mama_Amina", "mama.amina" and "mamaam1na" are the same name. |
| COM-07 | She can change her name once every 30 days. The app shows when the next change is allowed. The app suggests 4 name ideas (e.g. "MamaJasiri42"). |
| COM-08 | **Layer 1, shared rules** (phone while typing and server again): insults → blocked, nothing stored; phone numbers (9+ digits) or emails → she must remove them (Share button disabled), and the server redacts them anyway; danger signs → post marked urgent, held for a health worker, top of the queue, and she sees "Get help now" at once; selling, links, miracle cures → held for a health worker. |
| COM-09 | **Myths** (11): stopping iron/folic, stopping ARVs, skipping clinic, herbs for labour, water or other drinks before 6 months, things on the cord, throwing away colostrum, vaccine fears, alcohol for milk or pregnancy, honey for babies, eating less in pregnancy. A myth **stated as fact** is held for a health worker. The same myth **asked as a question** ("is it true…?", or a question mark) is published with a "Checked fact" card. Negations like "Don't stop taking iron" do not match. |
| COM-10 | **Layer 2, new members:** her first 2 posts wait for a health worker. |
| COM-11 | **Layer 2b, strikes:** a health worker can "remove with strike". 2 strikes → all her posts wait for review for 30 days. 4 strikes → she cannot post for 30 days (she can still read and mark helpful). The app explains this on the tab and when she tries to post. |
| COM-12 | **Layer 3, AI second opinion** (Groq) on posts the rules would publish. Labels: ok, misinformation, harmful, spam, abuse. A non-ok label with confidence ≥ 0.6 holds the post. AI can only hold back, never publish. The text goes without her name; nothing is logged. |
| COM-13 | **Layer 4, no AI available:** a post that mentions medicines waits for a health worker. |
| COM-14 | **Layer 5, after publishing:** any mother can report a post (wrong, unkind, selling, private, other). 3 reports from different mothers hide it until a health worker looks, unless a health worker already checked it or wrote it. |
| COM-15 | Health workers (dashboard) can publish, add or change a note (shown under the post as "Health worker note"; this also publishes), hide, remove, or remove with strike. Every action is written to `audit_log`. |
| COM-16 | Her own held post is visible to her with "Waiting for a health worker to check · only you can see it". She can delete her own post. |
| COM-17 | "Helpful" button (toggle) and reply count on each post. "Checked by a health worker" badge once checked. |
| COM-18 | Limits: 10 posts per hour per person; 1,000 characters per post; health worker note up to 600 characters. |
| COM-19 | The read functions never return who wrote a post (`author_id`). The tables are closed to the app and dashboard; all access goes through server functions. |
| COM-20 | "How we keep it safe" sheet explains the layers in plain words. |

#### Acceptance criteria (Community)

| # | Given | When | Then |
|---|---|---|---|
| AC-COM-1 | A signed-in mother, first time | She writes a post and does not change "Who should other mothers see?" | It is sent as "Anonymous mother". Because it is one of her first 2 posts, she sees "A health worker will check it soon. Until then only you can see it." |
| AC-COM-2 | She chooses "A community name" with no name yet | She taps it | The name screen opens. After saving she returns and the choice is set. If she backs out, the choice stays "Anonymous". |
| AC-COM-3 | Name screen | She types "Dr_Amina" | "This name looks like a health worker or the app." Save is disabled. |
| AC-COM-4 | Another mother has "MamaAmina" | She types "Mama_Am1na" | After she stops typing (0.5 s), "Someone already has this name, or one that looks the same." |
| AC-COM-5 | She changed her name 10 days ago | She tries again | Refused with "You can change your name once every 30 days. Next change: <date>." |
| AC-COM-6 | Compose | Text contains "0712 345 678" | A red card asks her to remove phone numbers and emails; Share is disabled. |
| AC-COM-7 | Compose | Text contains an insult | Red card "Please write kindly"; Share disabled. If sent anyway (e.g. old app), the server returns `blocked` and stores nothing. |
| AC-COM-8 | Compose | "Is it true I should stop iron tablets?" | Published (if she is past her first 2 posts and the AI does not object) with the "Checked fact" card. |
| AC-COM-9 | Compose | "Stop taking iron, it makes the baby big." | Amber card: a health worker will check it; status `review`, reason `myth:stop-iron`. |
| AC-COM-10 | Compose | Text contains a danger sign (e.g. heavy bleeding) | Red card "This sounds like a danger sign. Get help now" with a button to Emergency help, before she even sends. After sending, the post is `review`, `urgent`, top of the staff queue. |
| AC-COM-11 | A published post | 3 different mothers report it | Status becomes `hidden`; it leaves the feed; it appears in the staff queue with the report reasons. |
| AC-COM-12 | A mother with 4 strikes | She opens the tab | Amber card: she cannot post until <date>; she can still read and mark helpful. Posting returns `muted`. |
| AC-COM-13 | A mother with 2 strikes | She posts anything | Status `review` with reason `strikes`, until `review_until`. |
| AC-COM-14 | No `GROQ_API_KEY` | A returning member posts about a medicine (no rule hit) | Status `review`, reason `unchecked-medical`. |
| AC-COM-15 | No internet | She opens the tab | Last saved feed is shown with "No internet. Showing posts saved on this phone." |

### 6.10 Appointments and telemedicine (TEL)

Purpose: book a clinic visit or a video call with a health worker at her facility.
Code: `lib/features/telemedicine/`, `supabase/functions/telemed-join/`, migration `20261106010000_community_bookings.sql`.

#### Requirements

| ID | Requirement |
|---|---|
| TEL-01 | Entry points: Home "See a health worker" tile, Home "Your next appointment" card, side menu "Appointments". Needs sign-in and internet to book. |
| TEL-02 | Booking in **3 steps**: (1) how to meet: video call or clinic visit (and her clinic, if she has none set or several exist); (2) choose a day and time; (3) check and book, with an optional reason (up to 300 characters). Back goes to the previous step, not out. Step 1 says "In an emergency, do not book: go now or open Emergency help." |
| TEL-03 | Times come only from slots opened by facility staff. She sees free slots from 30 minutes ahead up to 14 days ahead (server allows up to 60). |
| TEL-04 | Booking is race-safe: the slot row is locked, so two mothers cannot take the same time. If someone took it first she sees "Someone just took this time. Please choose another." and fresh times. A slot starting within 15 minutes cannot be booked. |
| TEL-05 | At most 3 upcoming appointments per mother. Only a `mother` account can book. |
| TEL-06 | If there are no free times in the next 2 weeks: "Please call your clinic", with a call button. |
| TEL-07 | Cancel: by her or by the facility's staff. The slot opens again if it is still more than 30 minutes ahead; otherwise it is closed. |
| TEL-08 | Her bookings are kept on the phone so Home, the appointment screen and reminders work offline. |
| TEL-09 | Reminders on the phone: the evening before (18:00) for clinic visits and video calls, and 30 minutes before a video call ("Find a quiet place"). |
| TEL-10 | **Join window:** the video link is given only by `telemed-join`, only to that mother and active staff (health worker or facility admin) of that facility, from 15 minutes before the start until 30 minutes after the planned end. Too early → "The call opens 15 minutes before the start." After → "This call has ended or was cancelled." |
| TEL-11 | Video provider: Daily.co private rooms when `DAILY_API_KEY` + `DAILY_DOMAIN` are set (room expires at the window end, max 4 people, one token per person, staff join as owner). Otherwise Jitsi (`JITSI_BASE`, default meet.jit.si) with a random 64-character room name, for **testing only**. |
| TEL-12 | The call opens in the phone's browser. The mother is shown as "Mama" in the call; her name is not sent to the video provider. |
| TEL-13 | The appointment screen shows "Before the call" tips, "Show my Doctor's Note", "Call the clinic" (if the facility has a phone), and Cancel. |
| TEL-14 | After the visit staff mark it **done** or **missed** and may write advice (up to 1,000 characters). She sees it as "Health worker's advice" under the appointment, with "If you feel worse, do not wait: open Emergency help." |
| TEL-15 | The first time each side opens the call is recorded (`mother_joined_at`, `staff_joined_at`) for KPIs. Nothing about the call content is stored. |
| TEL-16 | Staff open slots in the dashboard: 1–48 back-to-back slots, 5–120 minutes each (default 20), in the future; existing slots are kept (no duplicates). Staff can close an open slot. |

#### Acceptance criteria (Telemedicine)

| # | Given | When | Then |
|---|---|---|---|
| AC-TEL-1 | Staff opened video slots for tomorrow | She taps "See a health worker" → Video call → a time → "Book this time" | Booked. Confirmation: "You are booked. We will remind you the evening before." (or "It is on your Home screen." if phone reminders are off). Home shows the next appointment. |
| AC-TEL-2 | Two mothers pick the same slot | Both press Book | One succeeds; the other sees "Someone just took this time" and a refreshed list. |
| AC-TEL-3 | She has 3 upcoming bookings | She tries a 4th | Refused with a plain message (too many). |
| AC-TEL-4 | Video call at 10:00, 20 minutes | She opens it at 09:40 | Join button explains it works from 09:45. Server answers `too_early` (425) if called. |
| AC-TEL-5 | Same | 09:45 to 10:50 | Join opens the call link in the browser. |
| AC-TEL-6 | Same | After 10:50, or booking cancelled/done | `ended` (410): "This call has ended or was cancelled." |
| AC-TEL-7 | A staff member of another facility | Calls `telemed-join` for this booking | 403 "not your appointment". |
| AC-TEL-8 | Booking for tomorrow, reminders on | — | Phone reminders at 18:00 the day before and (video) 30 minutes before. |
| AC-TEL-9 | Staff mark done with advice | She opens the appointment | Status "Done" and "Health worker's advice" card with the text. |
| AC-TEL-10 | She cancels 2 days ahead | — | Status "Cancelled"; the slot is free again for other mothers. |

---

## 7. Staff dashboard requirements (summary)

The dashboard is a separate repository. It has no SQL of its own: everything it calls is in `supabase/`.
Details of each function: [BACKEND_SCHEMA.md](BACKEND_SCHEMA.md).

| ID | Area | What the dashboard must offer | Server functions |
|---|---|---|---|
| DSH-01 | Sign-in and roles | Staff/admin sign-in, MFA for admins, role-based views | `staff_session`, `admin_session`, `mfa_ok`, role helpers |
| DSH-02 | Accounts | Invite staff/admins, temporary password, reset, deactivate/reactivate (never delete), create facility | Edge Function `admin-users` |
| DSH-03 | Mother setup | Create a mother's account by phone and hand her an 8-digit code | Edge Function `mother-setup` (`create`) |
| DSH-04 | Monitoring | Mothers who share with the facility, alerts (red/amber), assignment, caregivers, Doctor's Note opening, record verification | `assign_alert`, `open_note_share`, `verify_record_proof`, `staff_caregivers`, `can_read_mother` |
| DSH-05 | Moderation | Review queue (urgent first, then oldest), showing post, parent post, reasons, AI label, report reasons; actions publish / note / hide / remove / remove with strike | `community_review_queue`, `moderate_community_post` |
| DSH-06 | Health worker posts | Health workers can post answers in the circle (published at once with a badge) | Edge Function `community` (`post`) |
| DSH-07 | Appointments | Open slots, close slots, calendar of bookings with mother name and phone, cancel, join video, mark done/missed, write advice | `staff_add_slots`, `staff_cancel_slot`, `staff_bookings`, `cancel_booking`, `staff_set_booking_status`, Edge Function `telemed-join` |
| DSH-08 | KPIs | Facility, programme and platform numbers (section 8), with small groups hidden | see section 8 |
| DSH-09 | Content | Lessons with versions, channels and clinical sign-off; app content (announcements, emergency numbers, Learn cover); media; website pages and blog | `lesson_*`, `app_content_*`, `media_*`, `site_*`, `blog_*` |
| DSH-10 | Audit | Append-only audit log viewer | `admin_audit`, `admin_audit_actions` |

**Read-only in the dashboard.** The clinical warning rules (`lib/core/rules.dart` + SQL `rate_checkin`),
the community rules and myth list (`supabase/functions/community/rules.json`) and MamaBot's urgent safety words
(`supabase/functions/ai-gateway/index.ts` and `lib/core/assistant.g.dart`) are changed only in code, with tests,
by developers. The dashboard may show them but must not edit them.

---

## 8. Success metrics (KPIs)

All KPI functions are `security definer` and check the caller's role. Counts of people under 5 come back as
`null` ("fewer than 5") so no small group can be identified.

### 8.1 Mothers' circle: `community_kpis(p_from, p_to)` (staff and admins, whole platform)

| Field | Definition |
|---|---|
| `posts` / `replies` | Top-level posts / replies created in the period |
| `active_members` | Distinct mothers who posted (null if < 5) |
| `anonymous_share` | Share of mothers' posts sent as "Anonymous mother" |
| `held_for_review_share` | Share of mothers' posts with any reason except only a checked-fact card |
| `myth_flags` | Posts with a myth stated as fact |
| `fact_cards_shown` | Posts that got a "Checked fact" card (myth asked as a question) |
| `ai_flags` | Posts held by the AI second opinion |
| `urgent_posts` | Posts with a danger sign |
| `median_minutes_to_check` | Median minutes from post to a health worker's check (mothers' posts) |
| `median_minutes_urgent` | Same, urgent posts only |
| `waiting_now` | Posts in review or hidden right now |
| `hidden_by_reports` | Posts with 3 or more reports |
| `removed` | Posts removed |
| `staff_answers` | Posts by health workers |
| `members_with_strikes` / `muted_now` | Mothers with at least 1 strike / not allowed to post now (null if < 5) |
| `top_myths` | The 5 most frequent myth ids (stated or asked) with counts |

### 8.2 Appointments: `booking_kpis(p_facility, p_from, p_to)` (facility staff; admins for all facilities with `null`)

| Field | Definition |
|---|---|
| `slots_opened` | Slots starting in the period |
| `booked` | Bookings starting in the period (any status) |
| `fill_rate` | Booked slots ÷ slots not cancelled |
| `done` / `missed` / `cancelled` | Bookings by final status |
| `attendance_rate` | done ÷ (done + missed) |
| `video` / `clinic` | Bookings by mode |
| `video_both_joined_rate` | Video calls where both mother and staff opened the call ÷ video calls marked done or missed |
| `median_days_booking_to_visit` | Median days from booking to appointment |
| `advice_notes_written` | Bookings with health worker's advice |
| `mothers_served` | Distinct mothers with a done appointment (null if < 5) |

### 8.3 Other KPIs (already applied)

| Function | Who | What it gives |
|---|---|---|
| `admin_kpis(from, to, country?, district?, facility?)` | Admins | Facilities, staff, mothers, new mothers, active in 7 days, pregnant, postnatal, checks (total/red/amber), alerts (red/amber/open/closed, median minutes to acknowledge red, share of red acknowledged in 30 min), ANC (mean contacts, ANC4 %, ANC8 %, distribution), vaccines due/given/on time (within 14 days), overdue visits and vaccines, caregivers, Doctor's Notes shared/opened, AI questions, lesson views. Whole result suppressed if < 5 mothers. |
| `admin_daily(...)` | Admins | Daily series: checks, red, amber, active mothers, AI questions, new mothers |
| `admin_kpis_extra(...)` | Admins | Pregnancy care, high BP women, reduced movements, kick sessions, baby checks, vaccines on time %, engagement |
| `programme_kpis(from, to)` | Admins | Per facility: mothers, red and amber alerts, % red acknowledged within 2 hours, lesson views |
| `platform_kpis()` | Platform admins | Accounts by role, unconfirmed accounts, admins without MFA, facilities, content, website, app usage |
| `facility_daily(facility, from, to)` | Facility staff | Checks per day, red, amber (mothers who share) |
| `child_check_kpis(facility, from, to)` | Facility staff | Child checks, children, green/amber/red, top 8 signs |
| `facility_kpis` | Facility staff | Listed in BACKEND_SCHEMA.md; defined in the pre-migration baseline, not in this repo. Definition **to be confirmed** after `supabase db pull`. |

### 8.4 Product targets
Numeric targets (for example "median minutes to check urgent posts under X") are **to be decided** by the
founder and programme team. The functions above are the agreed way to measure them.

---

## 9. Release plan and phases

The repo does not contain a dated plan. The phases below follow the server status table and are
**proposed; to be confirmed by the founder**.

| Phase | Content | Depends on |
|---|---|---|
| 1. Core (live server parts) | Sign-in by SMS/Google, setup, daily check, tracking, MamaBot (scripted + AI), lessons, Doctor's Note QR, record QR, caregivers, phone reminders, dashboard monitoring and KPIs | SMS provider, Google client IDs, `GROQ_API_KEY` |
| 2. Clinic setup codes | Staff-created 8-digit codes | Apply `20261105020000_mother_setup_codes.sql`; deploy `mother-setup --no-verify-jwt` |
| 3. Mothers' circle | Community + moderation in the dashboard | Apply `20261106010000_community_bookings.sql`; deploy `community`; dashboard moderation screens; health workers trained to clear the queue |
| 4. Appointments and video | Booking, video calls, advice | Same migration; deploy `telemed-join`; Daily.co account (`DAILY_API_KEY`, `DAILY_DOMAIN`); dashboard calendar |
| 5. Content from the dashboard | App downloads published lessons, announcements, emergency numbers | App work to read `app_content_manifest()` |
| 6. Push | Server push for reminders and staff alerts | Deploy `send-notifications`, Firebase, cron job |

---

## 10. Status and open items

### Server (from `supabase/README.md` status table, 5–6 Nov 2026)

| Item | Status |
|---|---|
| `20261106010000_community_bookings.sql` (circle + appointments) | **Not applied** |
| `functions/community` | **Not deployed** |
| `functions/telemed-join` | **Not deployed**; needs `DAILY_API_KEY` + `DAILY_DOMAIN` for real calls |
| `20261105020000_mother_setup_codes.sql` + `functions/mother-setup` | **Not applied / not deployed** |
| `functions/send-notifications` | Not deployed |
| `functions/ai-gateway` | Deployed; answers start once `GROQ_API_KEY` is set |
| Other migrations up to `20261106000400` and `admin-users` | Applied / deployed |
| Migrations dated `20261107…` (website roles, KPI privacy, website CMS, `platform_kpis`, CMS indexes) | Not in the README status table; status **to be confirmed** |
| Tables created before November 2026 | No migration files yet; run `supabase db pull` once |

### App and setup

| Open item | Notes |
|---|---|
| SMS provider not configured | SMS sign-in cannot work until an SMS provider is set in Supabase Auth. (Not visible in this repo; reported by the team.) |
| Google client IDs needed | Build with `GOOGLE_WEB_CLIENT_ID` (and `GOOGLE_IOS_CLIENT_ID` for iOS); also configure Supabase → Auth → Google. Without them the Google button is hidden. |
| Dashboard content not downloaded | The app does not yet read `app_content_manifest()`. Lessons and pictures come only from files shipped in the app. |
| Dark mode | Not built (no dark theme in `lib/core/theme`). |
| Picture assets pending | Many picture IDs fall back to built-in drawings until the content kit is delivered (`assets/content/manifest.json`). |
| Low data mode | The switch exists and is saved, and promises "Sync less often; no media downloads", but the app still syncs every 60 seconds. Behaviour **to be decided and built**. |
| Strike expiry | Strikes never go down in the current code. Whether they should expire is **to be decided**. |
| Record proof anchoring | The record-proof screen says the ledger is stamped daily on the Bitcoin blockchain. No stamping job is in this repo. **To be confirmed.** |
| Kiswahili AI quality | Test about 20 real Kiswahili questions before switching AI on for mothers (`supabase/README.md`). |
| Jitsi fallback | Public meet.jit.si is for testing only. Use Daily.co or an own Jitsi server for real consultations. |

---

## 11. Risks

| Risk | Effect | Mitigation in the product |
|---|---|---|
| Health workers do not clear the review queue fast | Mothers wait; held posts feel ignored | Urgent first ordering; `median_minutes_to_check` and `waiting_now` KPIs; first-2-posts rule limits load. Staffing plan **to be decided**. |
| Myth rules miss new wording or flag good advice | Wrong advice published, or good posts held | AI second opinion, reports, health worker notes; `unless` exceptions; shared test cases on both sides |
| AI is weak in Kiswahili | Wrong MamaBot answers or wrong holds | AI never sets levels, can only hold posts; label on every AI answer; test Kiswahili first |
| Shared phones | Others see private health information | PIN, screens close on background, generic lock-screen reminders, journal never shared |
| Low signal during a video call | Call fails | Join window up to 30 min after end; "Call the clinic" button; tips before the call. Low-bandwidth video settings **to be decided**. |
| Mothers book when they should go now | Delay in an emergency | "In an emergency, do not book" message; Emergency button on booking screens |
| Small numbers in KPIs | A mother could be identified | Counts under 5 returned as null; admin KPIs suppressed when fewer than 5 mothers |
| Server parts not applied | Features visible in the app do not work | Section 10 deployment list; app shows plain errors ("Check your internet") |
| Free Supabase plan pauses after a week without use | Sign-in and sync stop | Resume in the dashboard or upgrade (`supabase/README.md`) |
| Daily.co or Groq costs | Budget | Per-person AI limit (30/day); video only for booked slots. Budget **to be decided**. |
