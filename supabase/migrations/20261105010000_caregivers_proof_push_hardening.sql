-- Server functions the app calls that were missing, plus a security fix.
--   1. Hardening: maintenance and trigger functions can no longer be called by app users.
--   2. Caregivers: 6-digit invites (48 h, brute-force limited), links, and the summary a helper sees.
--   3. Verifiable record: a fingerprint (SHA-256) of her vaccine and visit dates, chained in a ledger.
--   4. Push: the phone's FCM token.

-- ───────────── 1. hardening
-- pg_cron runs these as the owner and triggers fire without EXECUTE checks, so nothing breaks.
revoke execute on function public.purge_deleted() from public, anon, authenticated;
revoke execute on function public.escalate_red_alerts() from public, anon, authenticated;
revoke execute on function public.queue_visit_reminders() from public, anon, authenticated;
revoke execute on function public.raise_alert() from public, anon, authenticated;
revoke execute on function public.schedule_anc() from public, anon, authenticated;
revoke execute on function public.schedule_baby() from public, anon, authenticated;
revoke execute on function public.create_profile_for_user() from public, anon, authenticated;
-- takes any mother's id: only the rules engine (owner) needs it
revoke execute on function public.bp_rise_3wk(uuid, timestamptz, integer) from public, anon, authenticated;
alter function public.touch_updated_at() set search_path = public;
alter function public.events_insert_only() set search_path = public;
alter function public.rate_bp(integer, integer, text[]) set search_path = public;
alter function public.local_day(timestamptz) set search_path = public;

-- ───────────── 2. caregivers
alter table public.caregiver_links add column if not exists alerts boolean not null default true;

create table if not exists public.caregiver_invites (
  code text primary key check (code ~ '^[0-9]{6}$'),
  mother_id uuid not null references public.profiles(id) on delete cascade,
  relation text not null check (relation in ('partner', 'grandmother', 'sister', 'friend', 'other')),
  alerts boolean not null default true,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '48 hours',
  used_at timestamptz,
  used_by uuid references public.profiles(id) on delete set null
);
alter table public.caregiver_invites enable row level security; -- functions only

create table if not exists public.caregiver_invite_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  at timestamptz not null default now()
);
create index if not exists caregiver_invite_attempts_idx on public.caregiver_invite_attempts (user_id, at desc);
alter table public.caregiver_invite_attempts enable row level security; -- functions only

-- Mother: make a code for a helper. At most 5 unused codes at a time.
create or replace function public.create_caregiver_invite(p_relation text, p_alerts boolean default true)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_code text;
begin
  if auth.uid() is null or public.my_role() is distinct from 'mother' then
    raise exception 'only a signed-in mother can invite a helper' using errcode = '42501';
  end if;
  if (select count(*) from caregiver_invites i where i.mother_id = auth.uid() and i.used_at is null and i.expires_at > now()) >= 5 then
    raise exception 'too many open codes: wait for one to be used or to expire' using errcode = '22023';
  end if;
  loop
    v_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
    exit when not exists (select 1 from caregiver_invites i where i.code = v_code);
  end loop;
  insert into caregiver_invites (code, mother_id, relation, alerts) values (v_code, auth.uid(), coalesce(p_relation, 'other'), coalesce(p_alerts, true));
  return v_code;
end $$;

-- Helper: redeem a code. {ok, mother_name}. 10 wrong tries an hour, then refused.
create or replace function public.accept_caregiver_invite(p_code text)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  inv caregiver_invites;
  v_name text;
begin
  if auth.uid() is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;
  if (select count(*) from caregiver_invite_attempts a where a.user_id = auth.uid() and a.at > now() - interval '1 hour') >= 10 then
    raise exception 'too many tries: wait an hour' using errcode = '22023';
  end if;
  select * into inv from caregiver_invites i where i.code = trim(p_code) and i.used_at is null and i.expires_at > now() for update;
  if not found or inv.mother_id = auth.uid() then
    insert into caregiver_invite_attempts (user_id) values (auth.uid());
    return jsonb_build_object('ok', false);
  end if;
  insert into caregiver_links (caregiver_id, mother_id, relation, alerts)
  values (auth.uid(), inv.mother_id, inv.relation, inv.alerts)
  on conflict (caregiver_id, mother_id) do update set relation = excluded.relation, alerts = excluded.alerts, revoked_at = null;
  update caregiver_invites set used_at = now(), used_by = auth.uid() where code = inv.code;
  -- a new account with no records of her own becomes a caregiver account
  update profiles p set role = 'caregiver'
  where p.id = auth.uid() and p.role = 'mother'
    and not exists (select 1 from pregnancies x where x.mother_id = auth.uid())
    and not exists (select 1 from babies x where x.mother_id = auth.uid());
  select display_name into v_name from profiles where id = inv.mother_id;
  return jsonb_build_object('ok', true, 'mother_name', coalesce(v_name, ''));
end $$;

-- Mother: who helps her.
create or replace function public.my_caregivers()
returns table (caregiver_id uuid, name text, relation text, alerts boolean, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select l.caregiver_id, coalesce(p.display_name, ''), l.relation, l.alerts, l.created_at
  from caregiver_links l join profiles p on p.id = l.caregiver_id
  where l.mother_id = auth.uid() and l.revoked_at is null
  order by l.created_at;
$$;

-- Mother: stop a helper at once.
create or replace function public.stop_caregiver(p_caregiver uuid)
returns void
language sql security definer set search_path = public as $$
  update caregiver_links set revoked_at = now() where mother_id = auth.uid() and caregiver_id = p_caregiver and revoked_at is null;
$$;

-- Helper: what each linked mother shares. Never her journal, notes, questions or phone.
create or replace function public.caregiver_summary()
returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(x order by x->>'name'), '[]'::jsonb) from (
    select jsonb_build_object(
      'mother_id', m.id,
      'name', coalesce(m.display_name, ''),
      'relation', l.relation,
      'pregnant_weeks', (select ((current_date - pr.lmp) / 7)::int from pregnancies pr
                         where pr.mother_id = m.id and pr.status = 'active' and pr.deleted_at is null order by pr.updated_at desc limit 1),
      'babies', coalesce((select jsonb_agg(jsonb_build_object('name', coalesce(b.name, ''), 'days', current_date - b.dob) order by b.dob)
                          from babies b where b.mother_id = m.id and b.deleted_at is null and current_date - b.dob <= 300), '[]'::jsonb),
      'today', (select jsonb_build_object('level', greatest(c.level, coalesce(c.server_level, c.level)), 'signs', to_jsonb(c.signs || c.baby_signs))
                from checkins c where c.mother_id = m.id and c.deleted_at is null and public.local_day(c.client_created_at) = public.local_day(now())
                order by greatest(c.level, coalesce(c.server_level, c.level)) desc, c.client_created_at desc limit 1),
      'last7', coalesce((select jsonb_agg(jsonb_build_object('day', d.day, 'level', d.level) order by d.day)
                         from (select public.local_day(c.client_created_at) as day, max(greatest(c.level, coalesce(c.server_level, c.level))) as level
                               from checkins c where c.mother_id = m.id and c.deleted_at is null and c.client_created_at > now() - interval '7 days'
                               group by 1) d), '[]'::jsonb),
      'next_visit', (select jsonb_build_object('kind', case when a.baby_id is null then a.kind::text else 'child' end, 'contact', a.contact_no, 'due', a.due_on)
                     from appointments a where a.mother_id = m.id and a.deleted_at is null and a.attended_on is null and a.due_on >= current_date
                     order by a.due_on limit 1),
      'next_vaccine', (select jsonb_build_object('key', v.vaccine_key, 'due', v.due_on)
                       from vaccine_doses v where v.mother_id = m.id and v.given_on is null and v.due_on >= current_date - 30
                       order by v.due_on limit 1),
      'open_alert', case when l.alerts then (select jsonb_build_object('level', al.level, 'at', al.created_at)
                         from alerts al where al.mother_id = m.id and al.status not in ('closed') order by al.level desc, al.created_at desc limit 1) end
    ) as x
    from caregiver_links l join profiles m on m.id = l.mother_id
    where l.caregiver_id = auth.uid() and l.revoked_at is null and m.deleted_at is null
  ) t;
$$;

-- ───────────── 3. verifiable record (hash-chained ledger)
create table if not exists public.record_proofs (
  ledger_seq bigint generated always as identity primary key,
  proof_id uuid not null unique default gen_random_uuid(),
  mother_id uuid not null references public.profiles(id) on delete cascade,
  record_hash text not null check (record_hash ~ '^[0-9a-f]{64}$'),
  prev_chain text,
  chain_hash text not null,
  record_doc jsonb not null,
  issued_at timestamptz not null default now()
);
create index if not exists record_proofs_hash_idx on public.record_proofs (record_hash);
alter table public.record_proofs enable row level security; -- functions only

-- Mother: issue a proof of her vaccine and visit dates (no names, no health details beyond dates).
-- The QR holds only record_hash; a clinic checks it with verify_record_proof.
create or replace function public.my_record_proof()
returns table (proof_id uuid, record_hash text, ledger_seq bigint, issued_at timestamptz, record_doc jsonb)
language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id uuid := gen_random_uuid();
  v_at timestamptz := now();
  v_doc jsonb;
  v_hash text;
  v_prev text;
  v_seq bigint;
begin
  if auth.uid() is null or public.my_role() is distinct from 'mother' then
    raise exception 'only a signed-in mother has a record' using errcode = '42501';
  end if;
  v_doc := jsonb_build_object(
    'proof_id', v_id,
    'issued_at', v_at,
    'vaccines', coalesce((select jsonb_agg(jsonb_build_object('vaccine_key', d.vaccine_key, 'due_on', d.due_on, 'given_on', d.given_on) order by d.due_on, d.vaccine_key)
                          from vaccine_doses d where d.mother_id = auth.uid()), '[]'::jsonb),
    'visits', coalesce((select jsonb_agg(jsonb_build_object('kind', a.kind, 'contact_no', a.contact_no, 'due_on', a.due_on, 'attended_on', a.attended_on) order by a.due_on)
                        from appointments a where a.mother_id = auth.uid() and a.deleted_at is null), '[]'::jsonb)
  );
  v_hash := encode(extensions.digest(v_doc::text, 'sha256'), 'hex');
  lock table record_proofs in share row exclusive mode;
  select r.chain_hash into v_prev from record_proofs r order by r.ledger_seq desc limit 1;
  insert into record_proofs (proof_id, mother_id, record_hash, prev_chain, chain_hash, record_doc, issued_at)
  values (v_id, auth.uid(), v_hash, v_prev, encode(extensions.digest(coalesce(v_prev, '') || v_hash, 'sha256'), 'hex'), v_doc, v_at)
  returning record_proofs.ledger_seq into v_seq;
  return query select v_id, v_hash, v_seq, v_at, v_doc;
end $$;

-- Staff: check a scanned fingerprint. Returns the dated record it stands for (logged).
create or replace function public.verify_record_proof(p_hash text)
returns table (proof_id uuid, ledger_seq bigint, issued_at timestamptz, record_doc jsonb, chain_ok boolean)
language plpgsql security definer set search_path = public, extensions as $$
declare
  r record_proofs;
begin
  if auth.uid() is null or public.my_role() not in ('health_worker', 'facility_admin', 'programme_admin') then
    raise exception 'only health workers can check a record' using errcode = '42501';
  end if;
  select * into r from record_proofs x where x.record_hash = lower(trim(p_hash)) order by x.ledger_seq desc limit 1;
  if not found then
    return;
  end if;
  insert into audit_log (actor_id, action, mother_id, details) values (auth.uid(), 'verify_record_proof', r.mother_id, jsonb_build_object('proof_id', r.proof_id));
  return query select r.proof_id, r.ledger_seq, r.issued_at, r.record_doc,
    r.record_hash = encode(extensions.digest(r.record_doc::text, 'sha256'), 'hex')
    and r.chain_hash = encode(extensions.digest(coalesce(r.prev_chain, '') || r.record_hash, 'sha256'), 'hex');
end $$;

-- ───────────── 4. push token (FCM); the server key never reaches the phone
create or replace function public.register_push_token(p_token text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;
  if p_token is null or char_length(p_token) < 20 or char_length(p_token) > 4096 then
    raise exception 'bad token' using errcode = '22023';
  end if;
  insert into push_subscriptions (profile_id, endpoint, kind) values (auth.uid(), p_token, 'fcm')
  on conflict (endpoint) do update set profile_id = excluded.profile_id, kind = 'fcm', created_at = now();
  -- keep the 5 newest devices per person
  delete from push_subscriptions s where s.profile_id = auth.uid() and s.id not in (
    select s2.id from push_subscriptions s2 where s2.profile_id = auth.uid() order by s2.created_at desc limit 5);
end $$;

-- ───────────── grants
do $$
declare f text;
begin
  foreach f in array array[
    'public.create_caregiver_invite(text, boolean)', 'public.accept_caregiver_invite(text)', 'public.my_caregivers()',
    'public.stop_caregiver(uuid)', 'public.caregiver_summary()', 'public.my_record_proof()', 'public.verify_record_proof(text)',
    'public.register_push_token(text)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- ───────────── 5. AI gateway daily limit (no question text is stored: only who and when)
create table if not exists public.ai_usage (
  id bigint generated always as identity primary key,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  at timestamptz not null default now()
);
create index if not exists ai_usage_idx on public.ai_usage (profile_id, at desc);
alter table public.ai_usage enable row level security; -- written by the ai-gateway function only
