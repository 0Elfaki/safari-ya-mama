-- 1. Platform admins (super admin and Admin) can work at any facility.
--    The owner asked that the super admin can sign in anywhere in the system. At the Medical staff
--    entrance a platform admin picks any active facility; after two-step sign-in (aal2) they work
--    there with a health worker's view. From Administration they can open any facility the same way.
--    Consent still applies: a mother's record opens only if she shares it with an active facility,
--    and every view is logged (log_view), exactly as for health workers.
-- 2. KPI privacy rule narrowed: a group of 1 to 4 mothers is hidden ("fewer than 5"); a group of
--    0 is shown as 0. A zero reveals nothing about any mother, and hiding it made every figure look
--    broken while the programme has no mothers yet.

-- "Acts as medical staff": health workers, facility admins, and platform admins with MFA.
create or replace function public.acts_as_staff()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.my_role() in ('health_worker', 'facility_admin'), false) or public.is_platform_admin()
$$;

create or replace function public.my_facilities()
returns setof uuid language sql stable security definer set search_path = public as $$
  select facility_id from staff_assignments where staff_id = auth.uid() and active
  union
  select f.id from facilities f where f.active and public.is_platform_admin()
$$;

create or replace function public.staff_of(p_facility uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select (public.is_staff() and exists (
            select 1 from staff_assignments s join facilities f on f.id = s.facility_id
            where s.staff_id = auth.uid() and s.facility_id = p_facility and s.active and f.active))
      or (public.is_platform_admin() and exists (select 1 from facilities f where f.id = p_facility and f.active))
$$;

-- Facility-admin powers at a facility (assign alerts, manage its health workers): also platform admins.
create or replace function public.facility_admin_of(p_facility uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select (coalesce(public.my_role() = 'facility_admin', false) and public.staff_of(p_facility))
      or (public.is_platform_admin() and exists (select 1 from facilities f where f.id = p_facility))
$$;

create or replace function public.can_read_mother(p_mother uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select p_mother = auth.uid()
      or exists (select 1 from caregiver_links
                  where caregiver_id = auth.uid() and mother_id = p_mother and revoked_at is null)
      or exists (select 1 from staff_assignments s
                  where s.staff_id = auth.uid() and s.active and sharing_on(p_mother, s.facility_id))
      or (public.is_platform_admin()
          and exists (select 1 from facilities f where f.active and sharing_on(p_mother, f.id)))
$$;

create or replace function public.log_view(p_mother uuid, p_what text default 'record')
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if not public.acts_as_staff() or not public.can_read_mother(p_mother) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  insert into audit_log (actor_id, action, mother_id, details)
  values (auth.uid(), 'view_mother', p_mother, jsonb_build_object('what', left(p_what, 40)));
  return true;
end $$;

create or replace function public.staff_caregivers(p_mother uuid)
returns table (name text, relation text, since timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.acts_as_staff() or not public.can_read_mother(p_mother) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  return query
  select coalesce(p.display_name, ''), l.relation, l.created_at
  from caregiver_links l join profiles p on p.id = l.caregiver_id
  where l.mother_id = p_mother and l.revoked_at is null
  order by l.created_at;
end $$;

create or replace function public.open_note_share(p_id uuid)
returns table (ciphertext text, sections text[], created_at timestamptz, expires_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  r note_shares;
begin
  if auth.uid() is null or not public.acts_as_staff() then
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

-- Staff updates (mark visit attended, vaccine given, visit question answered): also platform admins.
alter policy staff_upd on public.appointments
  using (public.can_read_mother(mother_id) and public.acts_as_staff()) with check (public.can_read_mother(mother_id));
alter policy staff_upd on public.vaccine_doses
  using (public.can_read_mother(mother_id) and public.acts_as_staff()) with check (public.can_read_mother(mother_id));
alter policy staff_upd on public.visit_questions
  using (public.can_read_mother(mother_id) and public.acts_as_staff()) with check (public.can_read_mother(mother_id));

-- Medical staff entrance: platform admins are accepted at any active facility once MFA is done.
create or replace function public.staff_session(p_facility uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_role public.user_role := public.my_role();
  v_admin boolean := v_role in ('super_admin', 'programme_admin');
begin
  if auth.uid() is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;
  -- A refusal returns ok=false (instead of raising) so its audit row is kept.
  if v_admin and not public.mfa_ok() then
    return jsonb_build_object('ok', false, 'mfa_required', true, 'message', 'Confirm your sign-in with your authenticator code first');
  end if;
  if not public.staff_of(p_facility) then
    insert into audit_log (actor_id, action, details)
    values (auth.uid(), 'staff_sign_in_refused', jsonb_build_object('facility_id', p_facility));
    return jsonb_build_object('ok', false, 'message', 'You are not registered at this facility');
  end if;
  insert into audit_log (actor_id, action, details)
  values (auth.uid(), 'staff_sign_in', jsonb_build_object('facility_id', p_facility, 'as_admin', v_admin));
  return jsonb_build_object(
    'ok', true,
    'role', v_role,
    'name', (select display_name from profiles where id = auth.uid()),
    'facility', (select jsonb_build_object('id', f.id, 'name', f.name, 'level', f.level, 'phone', f.phone)
                 from facilities f where f.id = p_facility),
    'facilities', (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'name', f.name) order by f.name), '[]'::jsonb)
                   from facilities f where f.id in (select public.my_facilities()) and f.active));
end $$;

revoke all on function public.acts_as_staff() from public, anon;
grant execute on function public.acts_as_staff() to authenticated;

-- ───────────── 2. privacy rule: hide 1 to 4, show 0
create or replace function public.admin_kpis(p_from date, p_to date, p_country text default null,
                                             p_district uuid default null, p_facility uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_all boolean := p_country is null and p_district is null and p_facility is null;
  v_ids uuid[];
  v_n bigint;
  v_out jsonb;
begin
  perform public.check_admin_range(p_from, p_to);
  select coalesce(array_agg(p.id), '{}') into v_ids from profiles p
  where p.role = 'mother' and p.deleted_at is null
    and (v_all or p.home_facility in (select public.scope_facilities(p_country, p_district, p_facility)));
  v_n := cardinality(v_ids);

  v_out := jsonb_build_object(
    'facilities', (select count(*) from facilities f where f.active and (v_all or f.id in (select public.scope_facilities(p_country, p_district, p_facility)))),
    'staff', (select count(distinct s.staff_id) from staff_assignments s join facilities f on f.id = s.facility_id
              where s.active and f.active and (v_all or f.id in (select public.scope_facilities(p_country, p_district, p_facility)))),
    'suppressed', v_n between 1 and 4);
  if v_n between 1 and 4 then
    return v_out;
  end if;

  return v_out || jsonb_build_object(
    'mothers', v_n,
    'new_mothers', (select count(*) from profiles p where p.id = any(v_ids) and p.created_at::date between p_from and p_to),
    'active_7d', (select count(distinct c.mother_id) from checkins c
                  where c.mother_id = any(v_ids) and c.deleted_at is null and c.client_created_at > now() - interval '7 days'),
    'pregnant', (select count(distinct x.mother_id) from pregnancies x
                 where x.mother_id = any(v_ids) and x.status = 'active' and x.deleted_at is null),
    'postnatal', (select count(distinct b.mother_id) from babies b
                  where b.mother_id = any(v_ids) and b.deleted_at is null
                    and not exists (select 1 from pregnancies x where x.mother_id = b.mother_id and x.status = 'active' and x.deleted_at is null)),
    'checks', (select jsonb_build_object(
                 'total', count(*),
                 'red', count(*) filter (where greatest(c.level, coalesce(c.server_level, c.level)) = 'red'),
                 'amber', count(*) filter (where greatest(c.level, coalesce(c.server_level, c.level)) = 'amber'))
               from checkins c where c.mother_id = any(v_ids) and c.deleted_at is null
                 and c.client_created_at::date between p_from and p_to),
    'alerts', (select jsonb_build_object(
                 'red', count(*) filter (where a.level = 'red'),
                 'amber', count(*) filter (where a.level = 'amber'),
                 'open', count(*) filter (where a.status <> 'closed'),
                 'closed', count(*) filter (where a.status = 'closed'),
                 'median_ack_red_min', round((percentile_cont(0.5) within group (order by extract(epoch from a.acknowledged_at - a.created_at) / 60)
                                              filter (where a.level = 'red' and a.acknowledged_at is not null))::numeric, 1),
                 'red_ack_30m_pct', round(avg(case when a.acknowledged_at - a.created_at <= interval '30 minutes' then 1.0 else 0 end)
                                          filter (where a.level = 'red'), 2))
               from alerts a where a.mother_id = any(v_ids) and a.created_at::date between p_from and p_to),
    'anc', (select jsonb_build_object(
              'mothers', count(*),
              'mean_completed', round(avg(n), 1),
              'anc4_pct', round(avg(case when n >= 4 then 1.0 else 0 end), 2),
              'anc8_pct', round(avg(case when n >= 8 then 1.0 else 0 end), 2),
              'distribution', (select jsonb_object_agg(k, c) from (select least(n, 8) k, count(*) c from (
                                 select x.mother_id, count(a.id) filter (where a.attended_on is not null) n
                                 from pregnancies x left join appointments a on a.mother_id = x.mother_id and a.kind = 'anc' and a.deleted_at is null
                                 where x.mother_id = any(v_ids) and x.deleted_at is null
                                   and (x.status = 'active' or x.ended_on >= p_from) group by x.mother_id) q group by 1) d))
            from (select x.mother_id, count(a.id) filter (where a.attended_on is not null) n
                  from pregnancies x left join appointments a on a.mother_id = x.mother_id and a.kind = 'anc' and a.deleted_at is null
                  where x.mother_id = any(v_ids) and x.deleted_at is null and (x.status = 'active' or x.ended_on >= p_from)
                  group by x.mother_id) t),
    'vaccines', (select coalesce(jsonb_agg(jsonb_build_object('key', vaccine_key, 'due', due, 'given', given, 'on_time', on_time) order by first_due, vaccine_key), '[]'::jsonb)
                 from (select v.vaccine_key, min(v.due_on) first_due, count(*) due,
                              count(*) filter (where v.given_on is not null) given,
                              count(*) filter (where v.given_on <= v.due_on + 14) on_time
                       from vaccine_doses v where v.mother_id = any(v_ids)
                         and v.due_on between p_from and least(p_to, current_date)
                       group by v.vaccine_key) q),
    'overdue_visits', (select count(*) from appointments a where a.mother_id = any(v_ids) and a.deleted_at is null
                         and a.attended_on is null and a.due_on between p_from and least(p_to, current_date - 1)),
    'overdue_vaccines', (select count(*) from vaccine_doses v where v.mother_id = any(v_ids) and v.given_on is null
                           and v.due_on between p_from and least(p_to, current_date - 1)),
    'caregivers', (select count(*) from caregiver_links l where l.mother_id = any(v_ids) and l.revoked_at is null),
    'notes', (select jsonb_build_object('shared', count(*), 'opened', count(*) filter (where s.open_count > 0), 'opens', coalesce(sum(s.open_count), 0))
              from note_shares s where s.mother_id = any(v_ids) and s.created_at::date between p_from and p_to),
    'ai_questions', (select count(*) from ai_usage u where u.at::date between p_from and p_to
                       and (u.profile_id = any(v_ids)
                            or (v_all and u.profile_id in (select l.caregiver_id from caregiver_links l)))),
    'lesson_views', (select count(*) from lesson_views v where v.mother_id = any(v_ids) and v.viewed_at::date between p_from and p_to));
end $$;

-- Daily series for the same filter (no rows when the group is suppressed).
create or replace function public.admin_daily(p_from date, p_to date, p_country text default null,
                                              p_district uuid default null, p_facility uuid default null)
returns table (day date, checks bigint, red bigint, amber bigint, active_mothers bigint, ai_questions bigint, new_mothers bigint)
language plpgsql stable security definer set search_path = public as $$
declare
  v_all boolean := p_country is null and p_district is null and p_facility is null;
  v_ids uuid[];
begin
  perform public.check_admin_range(p_from, p_to);
  select coalesce(array_agg(p.id), '{}') into v_ids from profiles p
  where p.role = 'mother' and p.deleted_at is null
    and (v_all or p.home_facility in (select public.scope_facilities(p_country, p_district, p_facility)));
  if cardinality(v_ids) between 1 and 4 then
    return;
  end if;
  return query
  with days as (select generate_series(p_from, p_to, interval '1 day')::date d),
  ck as (select c.client_created_at::date d, count(*) n,
                count(*) filter (where greatest(c.level, coalesce(c.server_level, c.level)) = 'red') r,
                count(*) filter (where greatest(c.level, coalesce(c.server_level, c.level)) = 'amber') a,
                count(distinct c.mother_id) m
         from checkins c where c.mother_id = any(v_ids) and c.deleted_at is null and c.client_created_at::date between p_from and p_to group by 1),
  ai as (select u.at::date d, count(*) n from ai_usage u where u.profile_id = any(v_ids) and u.at::date between p_from and p_to group by 1),
  nm as (select p.created_at::date d, count(*) n from profiles p where p.id = any(v_ids) and p.created_at::date between p_from and p_to group by 1)
  select days.d, coalesce(ck.n, 0), coalesce(ck.r, 0), coalesce(ck.a, 0), coalesce(ck.m, 0), coalesce(ai.n, 0), coalesce(nm.n, 0)
  from days left join ck on ck.d = days.d left join ai on ai.d = days.d left join nm on nm.d = days.d
  order by days.d;
end $$;

-- ───────────── facility comparison (with map coordinates and sync health)
create or replace function public.admin_facility_table(p_from date, p_to date, p_country text default null, p_district uuid default null)
returns table (facility_id uuid, name text, level text, district text, country_code text, lat numeric, lng numeric, active boolean,
               mothers bigint, active_7d bigint, checks bigint, red_alerts bigint, amber_alerts bigint, open_alerts bigint,
               median_ack_red_min numeric, anc4_pct numeric, overdue_visits bigint, last_sync date,
               staff bigint, logins bigint, alerts_handled bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.check_admin_range(p_from, p_to);
  return query
  select f.id, f.name, f.level, d.name, d.country_code::text, f.lat, f.lng, f.active,
    case when m.n between 1 and 4 then null else m.n end,
    case when m.n between 1 and 4 then null else (select count(distinct c.mother_id) from checkins c join profiles p on p.id = c.mother_id
      where p.home_facility = f.id and p.role = 'mother' and c.deleted_at is null and c.client_created_at > now() - interval '7 days') end,
    case when m.n between 1 and 4 then null else (select count(*) from checkins c join profiles p on p.id = c.mother_id
      where p.home_facility = f.id and p.role = 'mother' and c.deleted_at is null and c.client_created_at::date between p_from and p_to) end,
    case when m.n between 1 and 4 then null else al.red end,
    case when m.n between 1 and 4 then null else al.amber end,
    case when m.n between 1 and 4 then null else al.still_open end,
    case when m.n between 1 and 4 then null else al.ack end,
    case when m.n between 1 and 4 then null else (select round(avg(case when q.n >= 4 then 1.0 else 0 end), 2) from (
      select a.mother_id, count(*) filter (where a.attended_on is not null) n from appointments a join profiles p on p.id = a.mother_id
      where p.home_facility = f.id and a.kind = 'anc' and a.deleted_at is null group by a.mother_id) q) end,
    case when m.n between 1 and 4 then null else (select count(*) from appointments a join profiles p on p.id = a.mother_id
      where p.home_facility = f.id and a.deleted_at is null and a.attended_on is null
        and a.due_on between p_from and least(p_to, current_date - 1)) end,
    (select max(c.created_at)::date from checkins c join profiles p on p.id = c.mother_id where p.home_facility = f.id),
    (select count(*) from staff_assignments s where s.facility_id = f.id and s.active),
    (select count(*) from audit_log l where l.action = 'staff_sign_in' and l.details ->> 'facility_id' = f.id::text
       and l.at::date between p_from and p_to),
    (select count(*) from alert_actions x join alerts a on a.id = x.alert_id
       where a.facility_id = f.id and x.created_at::date between p_from and p_to)
  from facilities f join districts d on d.id = f.district_id
  left join lateral (select count(*) n from profiles p where p.home_facility = f.id and p.role = 'mother' and p.deleted_at is null) m on true
  left join lateral (select count(*) filter (where a.level = 'red') red, count(*) filter (where a.level = 'amber') amber,
                            count(*) filter (where a.status <> 'closed') still_open,
                            round((percentile_cont(0.5) within group (order by extract(epoch from a.acknowledged_at - a.created_at) / 60)
                                   filter (where a.level = 'red' and a.acknowledged_at is not null))::numeric, 1) ack
                     from alerts a where a.facility_id = f.id and a.created_at::date between p_from and p_to) al on true
  where (p_country is null or d.country_code = p_country) and (p_district is null or f.district_id = p_district)
  order by f.active desc, f.name;
end $$;

