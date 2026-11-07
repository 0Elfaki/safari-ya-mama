-- Mothers' circle (community posts and replies) and appointments (clinic visits and video calls).
--
-- Community: posts are written only by the Edge Function "community", which runs the content
-- check (rules + AI) before a post is stored. Mothers read through the functions below, which
-- never return who wrote a post: a post shows either her community name (a username she chose,
-- unique, checked by the shared rules) or "Anonymous mother", her choice on every post.
-- Repeat misinformation: each post a health worker removes "with a strike" counts; 2 strikes put
-- all her posts through review for 30 days, 4 strikes stop her posting for 30 days.
-- Statuses: published (everyone sees it), review (only the author and staff, until a health worker
-- checks it), hidden (3 reports, waiting for a health worker), removed.
--
-- Appointments: staff open time slots at their facility (clinic visit or video call); a mother
-- books one; the video room name is random and only handed out by the Edge Function "telemed-join"
-- to the mother and the facility's staff, close to the appointment time.

-- ───────────── community
-- Her community identity. The name is set only by the Edge Function (shared username rules);
-- handle_key makes look-alike names count as the same name, so nobody can copy another mother's
-- name or pose as staff.
create table if not exists public.community_profiles (
  profile_id uuid primary key references public.profiles(id) on delete cascade,
  handle text check (handle ~ '^[A-Za-z][A-Za-z0-9._]{2,19}$'),
  handle_key text unique,
  handle_changed_at timestamptz,
  strikes int not null default 0,
  review_until timestamptz, -- all her posts wait for a health worker until then
  muted_until timestamptz, -- she cannot post until then
  created_at timestamptz not null default now()
);
alter table public.community_profiles enable row level security;

create table if not exists public.community_posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  parent_id uuid references public.community_posts(id) on delete cascade, -- set for a reply
  topic text not null default 'other' check (topic in ('pregnancy', 'birth', 'feeding', 'baby', 'feelings', 'other')),
  body text not null check (char_length(body) between 2 and 1000),
  anonymous boolean not null default true, -- false: shown with her community name
  stage_kind text check (stage_kind in ('pregnant', 'baby')),
  stage_value int check (stage_value between 0 and 60), -- weeks pregnant, or baby's age in months
  status text not null default 'review' check (status in ('published', 'review', 'hidden', 'removed')),
  urgent boolean not null default false,
  reasons text[] not null default '{}',
  facts text[] not null default '{}', -- ids of checked facts shown with the post (rules.json)
  ai jsonb, -- the AI check's label, confidence and short reason (staff only)
  staff_post boolean not null default false, -- written by a health worker
  health_note text check (char_length(health_note) <= 600), -- a health worker's note shown under the post
  checked_by uuid references public.profiles(id) on delete set null,
  checked_at timestamptz,
  helpful_count int not null default 0,
  reply_count int not null default 0,
  report_count int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists community_feed_idx on public.community_posts (created_at desc) where parent_id is null and status = 'published';
create index if not exists community_replies_idx on public.community_posts (parent_id, created_at);
create index if not exists community_author_idx on public.community_posts (author_id, created_at desc);
create index if not exists community_queue_idx on public.community_posts (urgent desc, created_at) where status in ('review', 'hidden');
alter table public.community_posts enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'community_posts' and policyname = 'community_posts_read') then
    create policy community_posts_read on public.community_posts for select
      using (author_id = auth.uid() or public.is_staff() or public.is_platform_admin());
  end if;
end $$;
-- no insert/update/delete policies: writes go through the Edge Function and the functions below

create table if not exists public.community_reports (
  post_id uuid not null references public.community_posts(id) on delete cascade,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check (reason in ('wrong', 'unkind', 'selling', 'private', 'other')),
  created_at timestamptz not null default now(),
  primary key (post_id, reporter_id)
);
alter table public.community_reports enable row level security;

create table if not exists public.community_helpful (
  post_id uuid not null references public.community_posts(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  active boolean not null default true, -- toggled off instead of removing the row
  primary key (post_id, profile_id)
);
alter table public.community_helpful enable row level security;

-- reply counts follow the replies everyone can see
create or replace function public.community_reply_count() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_parent uuid := coalesce(new.parent_id, old.parent_id);
begin
  if v_parent is not null then
    update community_posts set reply_count =
      (select count(*) from community_posts r where r.parent_id = v_parent and r.status = 'published')
    where id = v_parent;
  end if;
  return null;
end $$;
-- posts are never removed (status 'removed'), so insert and status changes keep the count right
create or replace trigger community_reply_count after insert or update of status on public.community_posts
  for each row execute function public.community_reply_count();

-- One post as a mother may see it. Never includes author_id.
create or replace function public._community_row(p public.community_posts)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id, 'parent_id', p.parent_id, 'topic', p.topic, 'body', p.body, 'anonymous', p.anonymous,
    -- the name shown: a health worker's first name, her community name, or nothing (anonymous)
    'author_name', case
      when p.staff_post then (select split_part(pr.display_name, ' ', 1) from profiles pr where pr.id = p.author_id)
      when p.anonymous then null
      else (select c.handle from community_profiles c where c.profile_id = p.author_id) end,
    'stage_kind', p.stage_kind, 'stage_value', p.stage_value, 'status', p.status,
    'urgent', case when p.author_id = auth.uid() then p.urgent else false end,
    'facts', p.facts, 'staff_post', p.staff_post, 'health_note', p.health_note,
    'checked', p.checked_at is not null, 'helpful_count', p.helpful_count, 'reply_count', p.reply_count,
    'created_at', p.created_at, 'mine', p.author_id = auth.uid(),
    'helped', exists (select 1 from community_helpful h where h.post_id = p.id and h.profile_id = auth.uid() and h.active))
$$;
revoke all on function public._community_row(public.community_posts) from public, anon, authenticated;

create or replace function public.community_feed(p_topic text default null, p_before timestamptz default null, p_limit int default 30)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'sign in first' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(public._community_row(p) order by p.created_at desc)
    from (
      select * from community_posts p
      where p.parent_id is null
        and (p.status = 'published' or (p.author_id = auth.uid() and p.status <> 'removed'))
        and (p_topic is null or p.topic = p_topic)
        and (p_before is null or p.created_at < p_before)
      order by p.created_at desc
      limit least(greatest(coalesce(p_limit, 30), 1), 50)
    ) p), '[]'::jsonb);
end $$;

create or replace function public.community_thread(p_post uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v community_posts;
begin
  if auth.uid() is null then raise exception 'sign in first' using errcode = '42501'; end if;
  select * into v from community_posts where id = p_post and parent_id is null
    and (status = 'published' or (author_id = auth.uid() and status <> 'removed'));
  if v.id is null then return null; end if;
  return jsonb_build_object('post', public._community_row(v), 'replies', coalesce((
    select jsonb_agg(public._community_row(r) order by r.created_at)
    from community_posts r
    where r.parent_id = p_post and (r.status = 'published' or (r.author_id = auth.uid() and r.status <> 'removed'))), '[]'::jsonb));
end $$;

-- 3 reports from different people hide a post until a health worker looks at it
create or replace function public.report_community_post(p_post uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare v community_posts; n int;
begin
  if auth.uid() is null then raise exception 'sign in first' using errcode = '42501'; end if;
  select * into v from community_posts where id = p_post and status = 'published' for update;
  if v.id is null or v.author_id = auth.uid() then return; end if;
  insert into community_reports (post_id, reporter_id, reason) values (p_post, auth.uid(), p_reason)
    on conflict do nothing;
  select count(*) into n from community_reports where post_id = p_post;
  update community_posts set report_count = n, updated_at = now(),
    status = case when n >= 3 and not staff_post and checked_at is null then 'hidden' else status end
  where id = p_post;
end $$;

create or replace function public.toggle_community_helpful(p_post uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_on boolean;
begin
  if auth.uid() is null then raise exception 'sign in first' using errcode = '42501'; end if;
  if not exists (select 1 from community_posts where id = p_post and status = 'published') then return false; end if;
  insert into community_helpful (post_id, profile_id, active) values (p_post, auth.uid(), true)
    on conflict (post_id, profile_id) do update set active = not community_helpful.active
    returning active into v_on;
  update community_posts set helpful_count = (select count(*) from community_helpful where post_id = p_post and active) where id = p_post;
  return v_on;
end $$;

-- Her community name and standing (the app shows when she may change the name, and why posts wait).
create or replace function public.my_community_profile()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'handle', c.handle,
    'can_change_at', c.handle_changed_at + interval '30 days',
    'strikes', coalesce(c.strikes, 0),
    'review_until', case when c.review_until > now() then c.review_until end,
    'muted_until', case when c.muted_until > now() then c.muted_until end)
  from (select auth.uid() as id) me left join community_profiles c on c.profile_id = me.id
  where me.id is not null
$$;

create or replace function public.delete_my_community_post(p_post uuid)
returns void language sql security definer set search_path = public as $$
  update community_posts set status = 'removed', updated_at = now() where id = p_post and author_id = auth.uid();
$$;

-- ───────────── community moderation (health workers, facility admins, admins)
create or replace function public.community_review_queue(p_limit int default 50)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.is_staff() or public.is_platform_admin()) then
    raise exception 'staff only' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(public._community_row(p) || jsonb_build_object(
      'urgent', p.urgent, 'reasons', p.reasons, 'ai', p.ai, 'report_count', p.report_count,
      'reports', (select coalesce(jsonb_agg(r.reason), '[]'::jsonb) from community_reports r where r.post_id = p.id),
      -- the author's standing, without saying who she is
      'author_strikes', coalesce((select c.strikes from community_profiles c where c.profile_id = p.author_id), 0),
      'author_has_name', exists (select 1 from community_profiles c where c.profile_id = p.author_id and c.handle is not null),
      'parent_body', (select q.body from community_posts q where q.id = p.parent_id))
      order by p.urgent desc, p.created_at)
    from (select * from community_posts where status in ('review', 'hidden')
          order by urgent desc, created_at limit least(greatest(coalesce(p_limit, 50), 1), 200)) p), '[]'::jsonb);
end $$;

-- p_action: publish | hide | remove | remove_strike (removed as misinformation or abuse: counts
-- against the author) | note (adds or changes the health worker's note; publishes it) |
-- reset_name (the author's community name is not acceptable: it is cleared and she must choose
-- another; the post itself is not changed)
create or replace function public.moderate_community_post(p_post uuid, p_action text, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_author uuid; v_strikes int;
begin
  if not (public.is_staff() or public.is_platform_admin()) then
    raise exception 'staff only' using errcode = '42501';
  end if;
  if p_action not in ('publish', 'hide', 'remove', 'remove_strike', 'note', 'reset_name') then
    raise exception 'unknown action' using errcode = '22023';
  end if;
  if p_action = 'reset_name' then
    update community_profiles set handle = null, handle_key = null, handle_changed_at = null
      where profile_id = (select author_id from community_posts where id = p_post);
    insert into audit_log (actor_id, action, details)
      values (auth.uid(), 'community_reset_name', jsonb_build_object('post_id', p_post));
    return;
  end if;
  update community_posts set
    status = case p_action when 'hide' then 'hidden' when 'publish' then 'published' when 'note' then 'published' else 'removed' end,
    health_note = case when p_action = 'note' or p_note is not null then nullif(trim(p_note), '') else health_note end,
    urgent = case when p_action in ('remove', 'remove_strike') then urgent else false end,
    checked_by = auth.uid(), checked_at = now(), updated_at = now()
  where id = p_post
  returning author_id into v_author;
  if p_action = 'remove_strike' and v_author is not null then
    insert into community_profiles (profile_id, strikes) values (v_author, 1)
      on conflict (profile_id) do update set strikes = community_profiles.strikes + 1
      returning strikes into v_strikes;
    update community_profiles set
      review_until = case when v_strikes >= 2 then greatest(coalesce(review_until, now()), now() + interval '30 days') else review_until end,
      muted_until = case when v_strikes >= 4 then greatest(coalesce(muted_until, now()), now() + interval '30 days') else muted_until end
    where profile_id = v_author;
  end if;
  insert into audit_log (actor_id, action, details)
    values (auth.uid(), 'community_' || p_action, jsonb_build_object('post_id', p_post));
end $$;

-- ───────────── appointments
create table if not exists public.booking_slots (
  id uuid primary key default gen_random_uuid(),
  facility_id uuid not null references public.facilities(id) on delete cascade,
  staff_id uuid references public.profiles(id) on delete set null,
  starts_at timestamptz not null,
  minutes int not null default 20 check (minutes between 5 and 120),
  mode text not null check (mode in ('clinic', 'video')),
  status text not null default 'open' check (status in ('open', 'booked', 'cancelled')),
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);
create unique index if not exists booking_slots_unique on public.booking_slots (facility_id, coalesce(staff_id, '00000000-0000-0000-0000-000000000000'::uuid), starts_at, mode);
create index if not exists booking_slots_open_idx on public.booking_slots (facility_id, mode, starts_at) where status = 'open';
alter table public.booking_slots enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'booking_slots' and policyname = 'booking_slots_staff_read') then
    create policy booking_slots_staff_read on public.booking_slots for select
      using (public.staff_of(facility_id) or public.is_platform_admin());
  end if;
end $$;

create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  slot_id uuid not null references public.booking_slots(id) on delete restrict,
  mother_id uuid not null references public.profiles(id) on delete cascade,
  facility_id uuid not null references public.facilities(id),
  staff_id uuid references public.profiles(id) on delete set null,
  starts_at timestamptz not null,
  minutes int not null,
  mode text not null check (mode in ('clinic', 'video')),
  reason text check (char_length(reason) <= 300),
  status text not null default 'booked' check (status in ('booked', 'cancelled', 'done', 'missed')),
  room text not null default (replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '')),
  outcome_note text check (char_length(outcome_note) <= 1000), -- the health worker's advice, shown to her afterwards
  mother_joined_at timestamptz, -- first time each side opened the video call (telemed-join)
  staff_joined_at timestamptz,
  cancelled_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists bookings_one_per_slot on public.bookings (slot_id) where status <> 'cancelled';
create index if not exists bookings_mother_idx on public.bookings (mother_id, starts_at desc);
create index if not exists bookings_facility_idx on public.bookings (facility_id, starts_at);
alter table public.bookings enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'bookings' and policyname = 'bookings_read') then
    create policy bookings_read on public.bookings for select
      using (mother_id = auth.uid() or public.staff_of(facility_id) or public.is_platform_admin());
  end if;
end $$;
-- No direct table access from the app or the dashboard: they use the functions below, which never
-- return the video room name (only telemed-join hands it out, close to the time) or who wrote a post.
revoke all on public.bookings, public.booking_slots, public.community_posts, public.community_reports,
  public.community_helpful, public.community_profiles from anon, authenticated;

-- One booking as the app shows it (no room name).
create or replace function public._booking_row(b public.bookings)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', b.id, 'facility_id', b.facility_id, 'starts_at', b.starts_at, 'minutes', b.minutes, 'mode', b.mode,
    'reason', b.reason, 'status', b.status, 'created_at', b.created_at, 'outcome_note', b.outcome_note,
    'facility_name', f.name, 'facility_phone', f.phone,
    'staff_name', (select p.display_name from profiles p where p.id = b.staff_id))
  from facilities f where f.id = b.facility_id
$$;
revoke all on function public._booking_row(public.bookings) from public, anon, authenticated;

-- Free times at a facility, from 30 minutes from now, for the next p_days days.
create or replace function public.open_slots(p_facility uuid, p_mode text, p_days int default 14)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'sign in first' using errcode = '42501'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', s.id, 'starts_at', s.starts_at, 'minutes', s.minutes, 'mode', s.mode,
      'staff_name', (select p.display_name from profiles p where p.id = s.staff_id)) order by s.starts_at)
    from booking_slots s join facilities f on f.id = s.facility_id and f.active
    where s.facility_id = p_facility and s.mode = p_mode and s.status = 'open'
      and s.starts_at > now() + interval '30 minutes'
      and s.starts_at < now() + make_interval(days => least(greatest(coalesce(p_days, 14), 1), 60))), '[]'::jsonb);
end $$;

create or replace function public.book_slot(p_slot uuid, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s booking_slots; b bookings;
begin
  if auth.uid() is null or public.my_role() is distinct from 'mother' then
    raise exception 'only a mother can book' using errcode = '42501';
  end if;
  if (select count(*) from bookings where mother_id = auth.uid() and status = 'booked' and starts_at > now()) >= 3 then
    raise exception 'you already have 3 upcoming appointments' using errcode = 'P0001', hint = 'too_many';
  end if;
  select * into s from booking_slots where id = p_slot for update;
  if s.id is null or s.status <> 'open' or s.starts_at <= now() + interval '15 minutes' then
    raise exception 'this time is no longer free' using errcode = 'P0001', hint = 'taken';
  end if;
  update booking_slots set status = 'booked' where id = s.id;
  insert into bookings (slot_id, mother_id, facility_id, staff_id, starts_at, minutes, mode, reason)
    values (s.id, auth.uid(), s.facility_id, s.staff_id, s.starts_at, s.minutes, s.mode, nullif(left(trim(p_reason), 300), ''))
    returning * into b;
  return public._booking_row(b);
end $$;

create or replace function public.cancel_booking(p_booking uuid)
returns void language plpgsql security definer set search_path = public as $$
declare b bookings;
begin
  select * into b from bookings where id = p_booking for update;
  if b.id is null or not (b.mother_id = auth.uid() or public.staff_of(b.facility_id)) then
    raise exception 'not your appointment' using errcode = '42501';
  end if;
  if b.status <> 'booked' then return; end if;
  update bookings set status = 'cancelled', cancelled_by = auth.uid(), updated_at = now() where id = b.id;
  -- the time opens again for someone else, if it is still ahead
  update booking_slots set status = case when starts_at > now() + interval '30 minutes' then 'open' else 'cancelled' end
    where id = b.slot_id;
end $$;

create or replace function public.my_bookings()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(public._booking_row(b) order by b.starts_at desc), '[]'::jsonb)
  from (select * from bookings where mother_id = auth.uid() order by starts_at desc limit 50) b
$$;

-- ───────────── appointments, staff side (dashboard)
-- Opens p_count back-to-back slots of p_minutes from p_first. Existing slots are kept.
create or replace function public.staff_add_slots(p_facility uuid, p_mode text, p_first timestamptz,
  p_count int default 1, p_minutes int default 20, p_staff uuid default null)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not (public.staff_of(p_facility) or public.is_platform_admin()) then
    raise exception 'not staff at this facility' using errcode = '42501';
  end if;
  if p_count not between 1 and 48 or p_first < now() then
    raise exception 'choose 1 to 48 times, in the future' using errcode = '22023';
  end if;
  insert into booking_slots (facility_id, staff_id, starts_at, minutes, mode)
    select p_facility, coalesce(p_staff, auth.uid()), p_first + make_interval(mins => i * p_minutes), p_minutes, p_mode
    from generate_series(0, p_count - 1) i
  on conflict do nothing;
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.staff_cancel_slot(p_slot uuid)
returns void language plpgsql security definer set search_path = public as $$
declare s booking_slots;
begin
  select * into s from booking_slots where id = p_slot;
  if s.id is null or not (public.staff_of(s.facility_id) or public.is_platform_admin()) then
    raise exception 'not staff at this facility' using errcode = '42501';
  end if;
  if s.status = 'open' then update booking_slots set status = 'cancelled' where id = p_slot; end if;
end $$;

create or replace function public.staff_bookings(p_facility uuid, p_from timestamptz, p_to timestamptz)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.staff_of(p_facility) or public.is_platform_admin()) then
    raise exception 'not staff at this facility' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(public._booking_row(b) || jsonb_build_object(
      'mother_id', b.mother_id, 'mother_name', p.display_name, 'mother_phone', p.phone) order by b.starts_at)
    from bookings b join profiles p on p.id = b.mother_id
    where b.facility_id = p_facility and b.starts_at >= p_from and b.starts_at < p_to), '[]'::jsonb);
end $$;

-- Done or missed, with optional advice for the mother (shown in her app under the appointment).
create or replace function public.staff_set_booking_status(p_booking uuid, p_status text, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare b bookings;
begin
  select * into b from bookings where id = p_booking;
  if b.id is null or not (public.staff_of(b.facility_id) or public.is_platform_admin()) then
    raise exception 'not staff at this facility' using errcode = '42501';
  end if;
  if p_status not in ('done', 'missed') then raise exception 'done or missed' using errcode = '22023'; end if;
  update bookings set status = p_status, updated_at = now(),
    outcome_note = coalesce(nullif(left(trim(p_note), 1000), ''), outcome_note)
  where id = p_booking;
end $$;

-- ───────────── KPIs (dashboard). Counts of 1 to 4 people come back as null ("fewer than 5"); 0 stays 0.
create or replace function public._small(n bigint) returns bigint language sql immutable as $$
  select case when n between 1 and 4 then null else n end
$$;

-- Mothers' circle, whole platform (staff and admins).
create or replace function public.community_kpis(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare a timestamptz := p_from; b timestamptz := p_to + 1;
begin
  if not (public.is_staff() or public.is_platform_admin()) then
    raise exception 'staff only' using errcode = '42501';
  end if;
  return (
    with p as (
      select *, exists (select 1 from unnest(reasons) r where r like 'myth:%') as has_myth,
        exists (select 1 from unnest(reasons) r where r like 'fact:%') as has_fact,
        exists (select 1 from unnest(reasons) r where r like 'ai:%') as has_ai
      from community_posts where created_at >= a and created_at < b),
    checked as (select extract(epoch from (checked_at - created_at)) / 60 as mins, urgent from p where checked_at is not null and not staff_post)
    select jsonb_build_object(
      'posts', count(*) filter (where parent_id is null),
      'replies', count(*) filter (where parent_id is not null),
      'active_members', public._small(count(distinct author_id) filter (where not staff_post)),
      'anonymous_share', round(avg(case when anonymous then 1.0 else 0 end) filter (where not staff_post), 3),
      'held_for_review_share', round(avg(case when cardinality(reasons) > 0 and not (has_fact and cardinality(reasons) = 1) then 1.0 else 0 end) filter (where not staff_post), 3),
      'myth_flags', count(*) filter (where has_myth),
      'fact_cards_shown', count(*) filter (where has_fact),
      'ai_flags', count(*) filter (where has_ai),
      'urgent_posts', count(*) filter (where urgent),
      'median_minutes_to_check', (select percentile_cont(0.5) within group (order by mins) from checked),
      'median_minutes_urgent', (select percentile_cont(0.5) within group (order by mins) from checked where urgent),
      'waiting_now', (select count(*) from community_posts where status in ('review', 'hidden')),
      'hidden_by_reports', count(*) filter (where report_count >= 3),
      'removed', count(*) filter (where status = 'removed'),
      'staff_answers', count(*) filter (where staff_post),
      'members_with_strikes', public._small((select count(*) from community_profiles where strikes > 0)),
      'muted_now', public._small((select count(*) from community_profiles where muted_until > now())),
      'top_myths', coalesce((select jsonb_object_agg(id, n) from (
          select substr(r, 6) as id, count(*) as n from p, unnest(p.reasons) r
          where r like 'myth:%' or r like 'fact:%' group by 1 order by 2 desc limit 5) t), '{}'::jsonb))
    from p);
end $$;

-- Appointments and video calls for one facility (its staff), or every facility (admins, p_facility null).
create or replace function public.booking_kpis(p_facility uuid, p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare a timestamptz := p_from; b timestamptz := p_to + 1;
begin
  if not (public.is_platform_admin() or (p_facility is not null and public.staff_of(p_facility))) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  return (
    with s as (select * from booking_slots where starts_at >= a and starts_at < b and (p_facility is null or facility_id = p_facility)),
    k as (select * from bookings where starts_at >= a and starts_at < b and (p_facility is null or facility_id = p_facility))
    select jsonb_build_object(
      'slots_opened', (select count(*) from s),
      'booked', (select count(*) from k),
      'fill_rate', (select round(count(*) filter (where status = 'booked')::numeric / nullif(count(*) filter (where status <> 'cancelled'), 0), 3) from s),
      'done', (select count(*) from k where status = 'done'),
      'missed', (select count(*) from k where status = 'missed'),
      'cancelled', (select count(*) from k where status = 'cancelled'),
      'attendance_rate', (select round(count(*) filter (where status = 'done')::numeric / nullif(count(*) filter (where status in ('done', 'missed')), 0), 3) from k),
      'video', (select count(*) from k where mode = 'video'),
      'clinic', (select count(*) from k where mode = 'clinic'),
      'video_both_joined_rate', (select round(count(*) filter (where mother_joined_at is not null and staff_joined_at is not null)::numeric
                                   / nullif(count(*) filter (where status in ('done', 'missed')), 0), 3) from k where mode = 'video'),
      'median_days_booking_to_visit', (select percentile_cont(0.5) within group (order by extract(epoch from (starts_at - created_at)) / 86400) from k),
      'advice_notes_written', (select count(*) from k where outcome_note is not null),
      'mothers_served', public._small((select count(distinct mother_id) from k where status = 'done'))));
end $$;

-- ───────────── who may call what
do $$
declare f text;
begin
  foreach f in array array[
    'community_feed(text, timestamptz, int)', 'community_thread(uuid)', 'report_community_post(uuid, text)',
    'toggle_community_helpful(uuid)', 'delete_my_community_post(uuid)', 'my_community_profile()', 'community_review_queue(int)',
    'moderate_community_post(uuid, text, text)', 'open_slots(uuid, text, int)', 'book_slot(uuid, text)',
    'cancel_booking(uuid)', 'my_bookings()', 'staff_add_slots(uuid, text, timestamptz, int, int, uuid)',
    'staff_cancel_slot(uuid)', 'staff_bookings(uuid, timestamptz, timestamptz)', 'staff_set_booking_status(uuid, text, text)',
    'community_kpis(date, date)', 'booking_kpis(uuid, date, date)']
  loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;
revoke all on function public.community_reply_count() from public, anon, authenticated;
revoke all on function public._small(bigint) from public, anon, authenticated;
