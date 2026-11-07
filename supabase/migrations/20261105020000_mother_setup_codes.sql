-- Staff-assisted sign-in. Sign-in is required in the app; a mother who cannot receive an SMS
-- code (or needs help) gets her account set up by clinic staff, who give her an 8-digit setup
-- code (24 hours, single use). Only a SHA-256 hash of each code is stored. Everything goes
-- through the Edge Function "mother-setup" (service role); app users cannot touch these tables.

create table if not exists public.mother_setup_codes (
  code_hash text primary key check (code_hash ~ '^[0-9a-f]{64}$'),
  mother_id uuid not null references public.profiles(id) on delete cascade,
  facility_id uuid references public.facilities(id) on delete set null,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '24 hours',
  used_at timestamptz
);
create index if not exists mother_setup_codes_mother_idx on public.mother_setup_codes (mother_id, created_at desc);
alter table public.mother_setup_codes enable row level security; -- Edge Function only

-- Failed redeem attempts per client, for rate limiting (no codes stored).
create table if not exists public.setup_code_attempts (
  id bigint generated always as identity primary key,
  client text not null,
  at timestamptz not null default now()
);
create index if not exists setup_code_attempts_idx on public.setup_code_attempts (client, at desc);
alter table public.setup_code_attempts enable row level security; -- Edge Function only

-- Finds an existing account by phone (auth stores numbers without "+"). Service role only.
create or replace function public.find_user_id_by_phone(p_phone text)
returns uuid
language sql stable security definer set search_path = public, auth as $$
  select u.id from auth.users u where u.phone = ltrim(p_phone, '+') or u.phone = p_phone limit 1;
$$;
revoke all on function public.find_user_id_by_phone(text) from public, anon, authenticated;
grant execute on function public.find_user_id_by_phone(text) to service_role;
