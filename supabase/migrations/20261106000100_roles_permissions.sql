-- Dashboard roles and permissions.
--   super_admin       full control: facilities, admin accounts, everything below
--   programme_admin   shown as "Admin": the whole platform except facilities and admin accounts
--   facility_admin    one facility: its mothers, KPIs and health workers
--   health_worker     the facilities in staff_assignments
-- Every rule lives here, in Postgres. The dashboard only hides what these functions refuse.
-- Admins (super_admin, programme_admin) must sign in with MFA (aal2) for any admin power.

-- ───────────── 1. one helper per permission
create or replace function public.mfa_ok()
returns boolean language sql stable set search_path = public as $$
  select coalesce(auth.jwt() ->> 'aal', '') = 'aal2'
$$;

create or replace function public.is_super_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.my_role() = 'super_admin', false) and public.mfa_ok()
$$;

-- super_admin or Admin (programme_admin)
create or replace function public.is_platform_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.my_role() in ('super_admin', 'programme_admin'), false) and public.mfa_ok()
$$;

create or replace function public.is_staff()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.my_role() in ('health_worker', 'facility_admin'), false)
$$;

-- signed-in health worker or facility admin with an active assignment at an active facility
create or replace function public.staff_of(p_facility uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_staff() and exists (
    select 1 from staff_assignments s join facilities f on f.id = s.facility_id
    where s.staff_id = auth.uid() and s.facility_id = p_facility and s.active and f.active)
$$;

create or replace function public.facility_admin_of(p_facility uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.my_role() = 'facility_admin', false) and public.staff_of(p_facility)
$$;

-- May the caller create (or manage) an account with this role at this facility?
--   admin roles (super_admin, programme_admin, facility_admin): super_admin only
--   health_worker: super_admin, Admin, or the facility admin of that facility
create or replace function public.can_manage_account(p_role public.user_role, p_facility uuid default null)
returns boolean language sql stable security definer set search_path = public as $$
  select case
    when p_role in ('super_admin', 'programme_admin', 'facility_admin') then public.is_super_admin()
    when p_role = 'health_worker' then public.is_platform_admin()
      or (p_facility is not null and public.facility_admin_of(p_facility))
    else false end
$$;

-- May the caller deactivate, reset or re-invite this existing account? Never yourself.
create or replace function public.can_manage_user(p_target uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select p_target is distinct from auth.uid() and exists (
    select 1 from profiles t where t.id = p_target and t.deleted_at is null and case
      when t.role in ('super_admin', 'programme_admin', 'facility_admin') then public.is_super_admin()
      when t.role = 'health_worker' then public.is_platform_admin()
        or exists (select 1 from staff_assignments s where s.staff_id = t.id and public.facility_admin_of(s.facility_id))
      else false end)
$$;

-- ───────────── 2. super admin bootstrap
-- The owner's address is the only one promoted, and only once it is confirmed, so nobody can
-- claim it by signing up first. It lives only here, never in the dashboard.
create or replace function public.bootstrap_super_admin()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if lower(coalesce(new.email, '')) = 'megdad.elfaki@gmail.com' and new.email_confirmed_at is not null then
    insert into public.profiles (id, display_name, role) values (new.id, 'Super admin', 'super_admin')
    on conflict (id) do update set role = 'super_admin';
  end if;
  return new;
end $$;

create or replace trigger zz_bootstrap_super_admin
  after insert or update of email_confirmed_at on auth.users
  for each row execute function public.bootstrap_super_admin();

update public.profiles p set role = 'super_admin'
from auth.users u
where u.id = p.id and lower(u.email) = 'megdad.elfaki@gmail.com' and u.email_confirmed_at is not null;

-- ───────────── 3. sign-in
-- Names of active facilities for the sign-in dropdown (public information, nothing else).
create or replace function public.sign_in_facilities()
returns table (id uuid, name text)
language sql stable security definer set search_path = public as $$
  select f.id, f.name from facilities f where f.active order by f.name
$$;

-- Medical staff: confirm the chosen facility. A refusal returns ok=false instead of raising,
-- so the refused attempt stays in audit_log; the dashboard then signs the user out at once.
create or replace function public.staff_session(p_facility uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_role public.user_role := public.my_role();
begin
  if auth.uid() is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;
  if v_role in ('super_admin', 'programme_admin') then
    insert into audit_log (actor_id, action, details)
    values (auth.uid(), 'staff_sign_in_refused', jsonb_build_object('facility_id', p_facility, 'reason', 'admin'));
    return jsonb_build_object('ok', false, 'message', 'Administrators sign in under Administration');
  end if;
  if not public.staff_of(p_facility) then
    insert into audit_log (actor_id, action, details)
    values (auth.uid(), 'staff_sign_in_refused', jsonb_build_object('facility_id', p_facility));
    return jsonb_build_object('ok', false, 'message', 'You are not registered at this facility');
  end if;
  insert into audit_log (actor_id, action, details)
  values (auth.uid(), 'staff_sign_in', jsonb_build_object('facility_id', p_facility));
  return jsonb_build_object(
    'ok', true,
    'role', v_role,
    'name', (select display_name from profiles where id = auth.uid()),
    'facility', (select jsonb_build_object('id', f.id, 'name', f.name, 'level', f.level, 'phone', f.phone)
                 from facilities f where f.id = p_facility),
    'facilities', (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'name', f.name) order by f.name), '[]'::jsonb)
                   from staff_assignments s join facilities f on f.id = s.facility_id
                   where s.staff_id = auth.uid() and s.active and f.active));
end $$;

-- Administration: who the caller is and whether MFA is complete. Logged once MFA is done.
create or replace function public.admin_session()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_role public.user_role := public.my_role();
begin
  if auth.uid() is null or v_role is null or v_role not in ('super_admin', 'programme_admin') then
    raise exception 'This entrance is for administrators' using errcode = '42501';
  end if;
  if public.mfa_ok() then
    insert into audit_log (actor_id, action) values (auth.uid(), 'admin_sign_in');
  end if;
  return jsonb_build_object('role', v_role, 'mfa', public.mfa_ok(),
    'name', (select display_name from profiles where id = auth.uid()));
end $$;

-- ───────────── 4. facilities (super admin creates, edits and deactivates)
create or replace function public.admin_save_district(p_country text, p_name text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_super_admin() then
    raise exception 'only the super admin can add districts' using errcode = '42501';
  end if;
  if char_length(trim(coalesce(p_name, ''))) < 2 or not exists (select 1 from countries where code = p_country) then
    raise exception 'choose a country and give the district a name' using errcode = '22023';
  end if;
  insert into districts (id, country_code, name) values (gen_random_uuid(), p_country, trim(p_name))
  on conflict (country_code, name) do update set name = excluded.name
  returning id into v_id;
  insert into audit_log (actor_id, action, details) values (auth.uid(), 'district_save', jsonb_build_object('district_id', v_id));
  return v_id;
end $$;

create or replace function public.admin_save_facility(
  p_id uuid, p_name text, p_level text, p_district uuid, p_phone text,
  p_emergency_24h boolean, p_lat numeric, p_lng numeric)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  if not public.is_super_admin() then
    raise exception 'only the super admin can create or edit facilities' using errcode = '42501';
  end if;
  if char_length(trim(coalesce(p_name, ''))) < 3 or char_length(p_name) > 120 then
    raise exception 'give the facility a name (3 to 120 letters)' using errcode = '22023';
  end if;
  if p_level not in ('dispensary', 'health_centre', 'hospital') then
    raise exception 'choose the facility level' using errcode = '22023';
  end if;
  if not exists (select 1 from districts where id = p_district) then
    raise exception 'choose a district' using errcode = '22023';
  end if;
  if (p_lat is null) <> (p_lng is null) or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'location needs both latitude (-90 to 90) and longitude (-180 to 180)' using errcode = '22023';
  end if;
  if p_phone is not null and p_phone !~ '^\+?[0-9 ]{6,20}$' then
    raise exception 'phone: digits and spaces, optionally starting with +' using errcode = '22023';
  end if;
  if p_id is null then
    insert into facilities (id, district_id, name, level, phone, emergency_24h, lat, lng, active)
    values (gen_random_uuid(), p_district, trim(p_name), p_level, nullif(trim(p_phone), ''), coalesce(p_emergency_24h, false), p_lat, p_lng, true)
    returning id into v_id;
    insert into audit_log (actor_id, action, details) values (auth.uid(), 'facility_create', jsonb_build_object('facility_id', v_id));
  else
    update facilities set district_id = p_district, name = trim(p_name), level = p_level, phone = nullif(trim(p_phone), ''),
      emergency_24h = coalesce(p_emergency_24h, false), lat = p_lat, lng = p_lng
    where id = p_id returning id into v_id;
    if v_id is null then
      raise exception 'facility not found' using errcode = 'P0002';
    end if;
    insert into audit_log (actor_id, action, details) values (auth.uid(), 'facility_update', jsonb_build_object('facility_id', v_id));
  end if;
  return v_id;
end $$;

create or replace function public.admin_set_facility_active(p_id uuid, p_active boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_super_admin() then
    raise exception 'only the super admin can deactivate facilities' using errcode = '42501';
  end if;
  update facilities set active = p_active where id = p_id;
  if not found then
    raise exception 'facility not found' using errcode = 'P0002';
  end if;
  insert into audit_log (actor_id, action, details)
  values (auth.uid(), case when p_active then 'facility_reactivate' else 'facility_deactivate' end, jsonb_build_object('facility_id', p_id));
end $$;

-- Every facility (active or not) for admins; a staff member's own facilities otherwise.
create or replace function public.admin_facilities()
returns table (id uuid, name text, level text, district_id uuid, district text, country_code text, country text,
               phone text, emergency_24h boolean, lat numeric, lng numeric, active boolean, staff_count bigint)
language sql stable security definer set search_path = public as $$
  select f.id, f.name, f.level, f.district_id, d.name, d.country_code::text, c.name, f.phone, f.emergency_24h, f.lat, f.lng, f.active,
    (select count(*) from staff_assignments s where s.facility_id = f.id and s.active)
  from facilities f join districts d on d.id = f.district_id join countries c on c.code = d.country_code
  where public.is_platform_admin() or public.staff_of(f.id)
  order by f.active desc, f.name
$$;

-- ───────────── 5. people (staff and admin accounts)
create or replace function public.admin_people(p_facility uuid default null)
returns table (id uuid, display_name text, email text, role public.user_role, facilities jsonb, created_at timestamptz,
               last_sign_in_at timestamptz, confirmed boolean, banned boolean, mfa boolean)
language sql stable security definer set search_path = public, auth as $$
  select p.id, p.display_name, u.email::text, p.role,
    coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'name', f.name, 'active', s.active) order by f.name)
              from staff_assignments s join facilities f on f.id = s.facility_id where s.staff_id = p.id), '[]'::jsonb),
    u.created_at, u.last_sign_in_at, u.email_confirmed_at is not null, coalesce(u.banned_until > now(), false),
    exists (select 1 from auth.mfa_factors m where m.user_id = u.id and m.status = 'verified')
  from profiles p join auth.users u on u.id = p.id
  where p.deleted_at is null
    and p.role in ('health_worker', 'facility_admin', 'programme_admin', 'super_admin')
    and (p_facility is null or exists (select 1 from staff_assignments s where s.staff_id = p.id and s.facility_id = p_facility))
    and (public.is_platform_admin()
         or (p.role in ('health_worker', 'facility_admin')
             and exists (select 1 from staff_assignments s where s.staff_id = p.id and public.facility_admin_of(s.facility_id))))
  order by p.role, p.display_name
$$;

create or replace function public.admin_assign_staff(p_staff uuid, p_facility uuid, p_active boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_role public.user_role;
begin
  select role into v_role from profiles where id = p_staff and deleted_at is null;
  if v_role is null or v_role not in ('health_worker', 'facility_admin') then
    raise exception 'only health workers and facility admins work at a facility' using errcode = '22023';
  end if;
  if p_staff = auth.uid() then
    raise exception 'you cannot change your own access' using errcode = '42501';
  end if;
  if not public.can_manage_account(v_role, p_facility) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_active and not exists (select 1 from facilities where id = p_facility and active) then
    raise exception 'that facility is not active' using errcode = '22023';
  end if;
  insert into staff_assignments (staff_id, facility_id, active, assigned_by)
  values (p_staff, p_facility, p_active, auth.uid())
  on conflict (staff_id, facility_id) do update set active = excluded.active, assigned_by = excluded.assigned_by;
  insert into audit_log (actor_id, action, details)
  values (auth.uid(), case when p_active then 'staff_assign' else 'staff_unassign' end,
          jsonb_build_object('target', p_staff, 'facility_id', p_facility));
end $$;

-- Change an account's role (staff and admin roles only). Super admin only, never yourself.
create or replace function public.admin_set_role(p_user uuid, p_role public.user_role)
returns void language plpgsql security definer set search_path = public as $$
declare v_old public.user_role;
begin
  if not public.is_super_admin() then
    raise exception 'only the super admin can change roles' using errcode = '42501';
  end if;
  if p_user = auth.uid() then
    raise exception 'you cannot change your own role' using errcode = '42501';
  end if;
  select role into v_old from profiles where id = p_user and deleted_at is null;
  if v_old is null or v_old not in ('health_worker', 'facility_admin', 'programme_admin', 'super_admin')
     or p_role not in ('health_worker', 'facility_admin', 'programme_admin', 'super_admin') then
    raise exception 'only staff and admin roles can be changed here' using errcode = '22023';
  end if;
  update profiles set role = p_role where id = p_user;
  -- admins work across facilities, not at one
  if p_role in ('programme_admin', 'super_admin') then
    update staff_assignments set active = false where staff_id = p_user;
  end if;
  insert into audit_log (actor_id, action, details)
  values (auth.uid(), 'role_change', jsonb_build_object('target', p_user, 'from', v_old, 'to', p_role));
end $$;

-- Direct writes to staff_assignments are replaced by admin_assign_staff (which checks roles).
do $$
begin
  if exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'staff_assignments' and policyname = 'staff_admin') then
    alter policy staff_admin on public.staff_assignments using (false) with check (false);
  end if;
end $$;

-- ───────────── 6. alerts: the facility admin assigns them to a colleague (kept in the alert history as a note)

create or replace function public.assign_alert(p_alert uuid, p_staff uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  a alerts;
  v_name text;
begin
  select * into a from alerts where id = p_alert;
  if a.id is null or not public.facility_admin_of(a.facility_id) then
    raise exception 'only the facility admin can assign this alert' using errcode = '42501';
  end if;
  if p_staff is not null then
    select p.display_name into v_name from staff_assignments s join profiles p on p.id = s.staff_id
    where s.staff_id = p_staff and s.facility_id = a.facility_id and s.active
      and p.role in ('health_worker', 'facility_admin') and p.deleted_at is null;
    if not found then
      raise exception 'that person does not work at this facility' using errcode = '22023';
    end if;
  end if;
  update alerts set assigned_to = p_staff where id = p_alert;
  insert into alert_actions (alert_id, actor_id, action, note)
  values (p_alert, auth.uid(), 'note', case when v_name is null then 'Unassigned' else 'Assigned to ' || v_name end);
  insert into audit_log (actor_id, action, mother_id, details)
  values (auth.uid(), 'alert_assign', a.mother_id, jsonb_build_object('alert', p_alert, 'target', p_staff, 'facility_id', a.facility_id));
end $$;

-- ───────────── 7. existing admin checks now use the helpers (super_admin included, MFA required)
alter policy lessons_admin on public.lessons using (public.is_platform_admin()) with check (public.is_platform_admin());
alter policy lessons_admin on public.lesson_translations using (public.is_platform_admin()) with check (public.is_platform_admin());

create or replace function public.programme_kpis(p_from date, p_to date)
returns table (district text, facility text, mothers bigint, red_alerts bigint, amber_alerts bigint, pct_red_ack_2h numeric, lesson_views bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return query
  select d.name, f.name,
         case when m.n < 5 then null else m.n end,
         case when ra.n < 5 then null else ra.n end,
         case when aa.n < 5 then null else aa.n end,
         case when ra.n < 5 then null else ra.pct end,
         lv.n
    from facilities f join districts d on d.id = f.district_id
    left join lateral (select count(*) n from profiles p
                        where p.home_facility = f.id and p.role = 'mother' and p.deleted_at is null) m on true
    left join lateral (select count(*) n,
                              round(avg(case when acknowledged_at - created_at <= interval '2 hours' then 1.0 else 0 end), 2) pct
                         from alerts where facility_id = f.id and level = 'red'
                          and created_at::date between p_from and p_to) ra on true
    left join lateral (select count(*) n from alerts where facility_id = f.id and level = 'amber'
                          and created_at::date between p_from and p_to) aa on true
    left join lateral (select count(*) n from lesson_views v join profiles p on p.id = v.mother_id
                        where p.home_facility = f.id and v.viewed_at::date between p_from and p_to) lv on true
   where f.active;
end $$;

create or replace function public.programme_weekly(p_from date, p_to date)
returns table (week_start date, active_mothers bigint, checkins bigint, red_alerts bigint, amber_alerts bigint, pct_followed_24h numeric)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then raise exception 'not allowed' using errcode = '42501'; end if;
  return query
  with weeks as (
    select generate_series(date_trunc('week', p_from)::date, p_to, interval '7 days')::date w),
  ck as (select date_trunc('week', client_created_at)::date w, count(distinct mother_id) am, count(*) n
           from checkins where deleted_at is null and client_created_at::date between p_from and p_to group by 1),
  al as (select date_trunc('week', a.created_at)::date w,
                count(*) filter (where a.level = 'red') r, count(*) filter (where a.level = 'amber') am,
                count(*) n,
                avg(case when exists (select 1 from alert_actions x where x.alert_id = a.id
                                        and x.created_at <= a.created_at + interval '24 hours') then 1.0 else 0 end) f
           from alerts a where a.created_at::date between p_from and p_to group by 1)
  select weeks.w,
         case when ck.am < 5 then null else ck.am end,
         case when ck.n < 5 then null else ck.n end,
         case when al.r < 5 then null else al.r end,
         case when al.am < 5 then null else al.am end,
         case when al.n < 5 then null else round(al.f, 2) end
    from weeks left join ck on ck.w = weeks.w left join al on al.w = weeks.w
   order by weeks.w;
end $$;

-- ───────────── 8. audit log: append-only, fast to filter
create or replace function public.audit_log_append_only()
returns trigger language plpgsql set search_path = public as $$
begin
  raise exception 'audit_log is append-only' using errcode = '42501';
end $$;
create or replace trigger audit_log_append_only before update or delete on public.audit_log
  for each row execute function public.audit_log_append_only();
create index if not exists audit_log_at_idx on public.audit_log (at desc);
create index if not exists audit_log_actor_idx on public.audit_log (actor_id, at desc);
create index if not exists audit_log_action_idx on public.audit_log (action, at desc);

-- ───────────── 9. grants
revoke execute on function public.bootstrap_super_admin() from public, anon, authenticated;
revoke execute on function public.audit_log_append_only() from public, anon, authenticated;
do $$
declare f text;
begin
  foreach f in array array[
    'public.mfa_ok()', 'public.is_super_admin()', 'public.is_platform_admin()', 'public.is_staff()',
    'public.staff_of(uuid)', 'public.facility_admin_of(uuid)',
    'public.can_manage_account(public.user_role, uuid)', 'public.can_manage_user(uuid)',
    'public.staff_session(uuid)', 'public.admin_session()',
    'public.admin_save_district(text, text)', 'public.admin_save_facility(uuid, text, text, uuid, text, boolean, numeric, numeric)',
    'public.admin_set_facility_active(uuid, boolean)', 'public.admin_facilities()', 'public.admin_people(uuid)',
    'public.admin_assign_staff(uuid, uuid, boolean)', 'public.admin_set_role(uuid, public.user_role)',
    'public.assign_alert(uuid, uuid)', 'public.programme_kpis(date, date)', 'public.programme_weekly(date, date)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
revoke all on function public.sign_in_facilities() from public;
grant execute on function public.sign_in_facilities() to anon, authenticated;
