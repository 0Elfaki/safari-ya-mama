-- Doctor's Note sharing with an encrypted, expiring QR code.
--
-- The phone encrypts the note (AES-256-GCM) with a fresh random key and uploads only the
-- ciphertext. The key never reaches the server: it travels inside the QR code the mother
-- shows (SYM2:<share id>.<key>). A clinician needs BOTH the QR (key) and a staff account
-- (to fetch the ciphertext), every open is written to audit_log, shares expire after at most
-- 7 days, and the mother can revoke them at any time.

create table if not exists public.note_shares (
  id uuid primary key default gen_random_uuid(),
  mother_id uuid not null references public.profiles(id) on delete cascade,
  ciphertext text not null check (char_length(ciphertext) between 40 and 24000),
  sections text[] not null default '{}',
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  open_count integer not null default 0,
  last_opened_at timestamptz,
  constraint note_shares_expiry check (expires_at > created_at and expires_at <= created_at + interval '7 days')
);

create index if not exists note_shares_mother_idx on public.note_shares (mother_id, created_at desc);

alter table public.note_shares enable row level security;

-- The mother sees her own shares (never the ciphertext of anyone else). No direct writes:
-- every change goes through the functions below.
drop policy if exists note_shares_own_select on public.note_shares;
create policy note_shares_own_select on public.note_shares
  for select to authenticated using (mother_id = auth.uid());

-- Create a share. Returns its id and expiry. 1 to 168 hours; at most 20 active shares.
create or replace function public.create_note_share(p_ciphertext text, p_sections text[], p_hours integer)
returns table (id uuid, expires_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
  v_exp timestamptz;
begin
  if auth.uid() is null or public.my_role() is distinct from 'mother' then
    raise exception 'only a signed-in mother can share her note' using errcode = '42501';
  end if;
  if p_hours is null or p_hours < 1 or p_hours > 168 then
    raise exception 'expiry must be 1 to 168 hours' using errcode = '22023';
  end if;
  if (select count(*) from note_shares s where s.mother_id = auth.uid() and s.revoked_at is null and s.expires_at > now()) >= 20 then
    raise exception 'too many active shares: revoke one first' using errcode = '22023';
  end if;
  v_exp := now() + make_interval(hours => p_hours);
  insert into note_shares (mother_id, ciphertext, sections, expires_at)
  values (auth.uid(), p_ciphertext, coalesce(p_sections, '{}'), v_exp)
  returning note_shares.id into v_id;
  return query select v_id, v_exp;
end $$;

-- The mother's shares, newest first (no ciphertext).
create or replace function public.my_note_shares()
returns table (id uuid, sections text[], created_at timestamptz, expires_at timestamptz, revoked_at timestamptz, open_count integer, last_opened_at timestamptz)
language sql stable security definer set search_path = public as $$
  select s.id, s.sections, s.created_at, s.expires_at, s.revoked_at, s.open_count, s.last_opened_at
  from note_shares s where s.mother_id = auth.uid() order by s.created_at desc limit 50;
$$;

-- The mother stops a share at once.
create or replace function public.revoke_note_share(p_id uuid)
returns void
language sql security definer set search_path = public as $$
  update note_shares set revoked_at = coalesce(revoked_at, now()) where id = p_id and mother_id = auth.uid();
$$;

-- A clinician opens a share: staff only, not expired or revoked, mother not deleted.
-- Returns the ciphertext (useless without the key in the QR) and logs the view.
create or replace function public.open_note_share(p_id uuid)
returns table (ciphertext text, sections text[], created_at timestamptz, expires_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  r note_shares;
begin
  if auth.uid() is null or public.my_role() not in ('health_worker', 'facility_admin', 'programme_admin') then
    raise exception 'only health workers can open a shared note' using errcode = '42501';
  end if;
  select s.* into r from note_shares s join profiles p on p.id = s.mother_id
  where s.id = p_id and p.deleted_at is null
  for update of s;
  if not found or r.revoked_at is not null or r.expires_at <= now() then
    raise exception 'this note has expired or was stopped by the mother' using errcode = 'P0002';
  end if;
  update note_shares set open_count = open_count + 1, last_opened_at = now() where note_shares.id = p_id;
  insert into audit_log (actor_id, action, mother_id, details)
  values (auth.uid(), 'open_note_share', r.mother_id, jsonb_build_object('share_id', p_id, 'sections', r.sections));
  return query select r.ciphertext, r.sections, r.created_at, r.expires_at;
end $$;

revoke all on function public.create_note_share(text, text[], integer) from public, anon;
revoke all on function public.my_note_shares() from public, anon;
revoke all on function public.revoke_note_share(uuid) from public, anon;
revoke all on function public.open_note_share(uuid) from public, anon;
grant execute on function public.create_note_share(text, text[], integer) to authenticated;
grant execute on function public.my_note_shares() to authenticated;
grant execute on function public.revoke_note_share(uuid) to authenticated;
grant execute on function public.open_note_share(uuid) to authenticated;
