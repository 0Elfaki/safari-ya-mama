-- Whole-system KPIs, facility comparison, staff activity, audit viewer and system health.
-- Platform admins only (super_admin, Admin) with MFA. Any group of fewer than 5 mothers is
-- suppressed: its mother-derived figures come back as null.

-- Facilities in a country / district / facility filter (null = no filter). Internal helper.
create or replace function public.scope_facilities(p_country text, p_district uuid, p_facility uuid)
returns setof uuid language sql stable security definer set search_path = public as $$
  select f.id from facilities f join districts d on d.id = f.district_id
  where (p_country is null or d.country_code = p_country)
    and (p_district is null or f.district_id = p_district)
    and (p_facility is null or f.id = p_facility)
$$;

create or replace function public.uuid_or_null(p text)
returns uuid language sql immutable set search_path = public as $$
  select case when p ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then p::uuid end
$$;

create or replace function public.check_admin_range(p_from date, p_to date)
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 400 then
    raise exception 'choose a date range of up to 400 days' using errcode = '22023';
  end if;
end $$;

-- ───────────── KPI overview
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
    'suppressed', v_n < 5);
  if v_n < 5 then
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
  if cardinality(v_ids) < 5 then
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
    case when m.n < 5 then null else m.n end,
    case when m.n < 5 then null else (select count(distinct c.mother_id) from checkins c join profiles p on p.id = c.mother_id
      where p.home_facility = f.id and p.role = 'mother' and c.deleted_at is null and c.client_created_at > now() - interval '7 days') end,
    case when m.n < 5 then null else (select count(*) from checkins c join profiles p on p.id = c.mother_id
      where p.home_facility = f.id and p.role = 'mother' and c.deleted_at is null and c.client_created_at::date between p_from and p_to) end,
    case when m.n < 5 then null else al.red end,
    case when m.n < 5 then null else al.amber end,
    case when m.n < 5 then null else al.still_open end,
    case when m.n < 5 then null else al.ack end,
    case when m.n < 5 then null else (select round(avg(case when q.n >= 4 then 1.0 else 0 end), 2) from (
      select a.mother_id, count(*) filter (where a.attended_on is not null) n from appointments a join profiles p on p.id = a.mother_id
      where p.home_facility = f.id and a.kind = 'anc' and a.deleted_at is null group by a.mother_id) q) end,
    case when m.n < 5 then null else (select count(*) from appointments a join profiles p on p.id = a.mother_id
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

-- ───────────── staff activity
create or replace function public.admin_staff_activity(p_from date, p_to date, p_facility uuid default null)
returns table (staff_id uuid, name text, role public.user_role, facilities text, logins bigint, alerts_handled bigint,
               last_action timestamptz, last_sign_in_at timestamptz)
language plpgsql stable security definer set search_path = public, auth as $$
begin
  perform public.check_admin_range(p_from, p_to);
  return query
  select p.id, p.display_name, p.role,
    (select string_agg(f.name, ', ' order by f.name) from staff_assignments s join facilities f on f.id = s.facility_id
     where s.staff_id = p.id and s.active),
    (select count(*) from audit_log l where l.actor_id = p.id and l.action in ('staff_sign_in', 'admin_sign_in') and l.at::date between p_from and p_to),
    (select count(*) from alert_actions x where x.actor_id = p.id and x.created_at::date between p_from and p_to),
    (select max(l.at) from audit_log l where l.actor_id = p.id),
    u.last_sign_in_at
  from profiles p join auth.users u on u.id = p.id
  where p.deleted_at is null and p.role in ('health_worker', 'facility_admin', 'programme_admin', 'super_admin')
    and (p_facility is null or exists (select 1 from staff_assignments s where s.staff_id = p.id and s.facility_id = p_facility))
  order by 5 desc, p.display_name;
end $$;

-- ───────────── audit log viewer (read-only). Mothers appear only as a short pseudonym.
create or replace function public.admin_audit(p_from timestamptz default null, p_to timestamptz default null, p_actor uuid default null,
                                              p_action text default null, p_facility uuid default null,
                                              p_limit integer default 100, p_before bigint default null)
returns table (id bigint, at timestamptz, actor_id uuid, actor_name text, actor_role public.user_role, action text,
               facility_id uuid, facility_name text, subject text, details jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  return query
  select l.id, l.at, l.actor_id, a.display_name, a.role, l.action, q.fid, f.name,
    case when l.mother_id is not null then 'Mother ' || left(md5(l.mother_id::text), 6)
         when public.uuid_or_null(l.details ->> 'target') is not null
           then coalesce((select t.display_name from profiles t where t.id = public.uuid_or_null(l.details ->> 'target')), 'Account')
         end,
    l.details - array['note', 'text', 'email', 'password', 'phone', 'name']
  from audit_log l
  left join profiles a on a.id = l.actor_id
  cross join lateral (select coalesce(public.uuid_or_null(l.details ->> 'facility_id'), public.uuid_or_null(l.details ->> 'facility'),
                                      (select m.home_facility from profiles m where m.id = l.mother_id)) fid) q
  left join facilities f on f.id = q.fid
  where (p_from is null or l.at >= p_from) and (p_to is null or l.at < p_to)
    and (p_actor is null or l.actor_id = p_actor) and (p_action is null or l.action = p_action)
    and (p_facility is null or q.fid = p_facility) and (p_before is null or l.id < p_before)
  order by l.id desc
  limit least(greatest(coalesce(p_limit, 100), 1), 500);
end $$;

create or replace function public.admin_audit_actions()
returns table (action text, n bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_platform_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  return query select l.action, count(*) from audit_log l group by l.action order by l.action;
end $$;

-- ───────────── system health (cron, notification queue, AI usage, data freshness)
create or replace function public.admin_system()
returns jsonb language plpgsql stable security definer set search_path = public, cron as $$
begin
  if not public.is_platform_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'checked_at', now(),
    'cron', (select coalesce(jsonb_agg(jsonb_build_object(
               'job', j.jobname, 'schedule', j.schedule, 'active', j.active,
               'last', (select jsonb_build_object('status', d.status, 'start', d.start_time, 'end', d.end_time, 'message', left(d.return_message, 200))
                        from cron.job_run_details d where d.jobid = j.jobid order by d.start_time desc limit 1),
               'failures_24h', (select count(*) from cron.job_run_details d where d.jobid = j.jobid and d.status = 'failed'
                                  and d.start_time > now() - interval '24 hours')) order by j.jobname), '[]'::jsonb)
             from cron.job j),
    'queue', (select jsonb_build_object(
                'queued', count(*) filter (where q.status = 'queued'),
                'due', count(*) filter (where q.status = 'queued' and q.send_after <= now()),
                'oldest_due', min(q.send_after) filter (where q.status = 'queued' and q.send_after <= now()),
                'sent_24h', count(*) filter (where q.status = 'sent' and q.sent_at > now() - interval '24 hours'),
                'failed_24h', count(*) filter (where q.status = 'failed' and q.send_after > now() - interval '24 hours'),
                'failed_7d', count(*) filter (where q.status = 'failed' and q.send_after > now() - interval '7 days'),
                'by_channel', (select coalesce(jsonb_object_agg(channel, n), '{}'::jsonb) from
                                 (select channel, count(*) n from notification_queue where status = 'queued' group by channel) c))
              from notification_queue q),
    'failed_recent', (select coalesce(jsonb_agg(jsonb_build_object('template', x.template_key, 'channel', x.channel, 'at', x.send_after)), '[]'::jsonb)
                      from (select template_key, channel, send_after from notification_queue where status = 'failed'
                            order by send_after desc limit 10) x),
    'push_devices', (select count(*) from push_subscriptions),
    'ai', jsonb_build_object(
      'last_24h', (select count(*) from ai_usage where at > now() - interval '24 hours'),
      'last_7d', (select count(*) from ai_usage where at > now() - interval '7 days'),
      'per_day', (select coalesce(jsonb_agg(jsonb_build_object('day', d.day, 'n', coalesce(u.n, 0)) order by d.day), '[]'::jsonb)
                  from (select generate_series(current_date - 13, current_date, interval '1 day')::date as day) d
                  left join (select at::date as day, count(*) n from ai_usage where at > current_date - 14 group by 1) u on u.day = d.day)),
    'data', jsonb_build_object(
      'last_checkin', (select max(created_at) from checkins),
      'last_mother_signup', (select max(created_at) from profiles where role = 'mother'),
      'last_staff_sign_in', (select max(at) from audit_log where action in ('staff_sign_in', 'admin_sign_in')),
      'mothers', (select count(*) from profiles where role = 'mother' and deleted_at is null),
      'caregivers', (select count(*) from profiles where role = 'caregiver' and deleted_at is null),
      'staff', (select count(*) from profiles where role in ('health_worker', 'facility_admin') and deleted_at is null),
      'admins', (select count(*) from profiles where role in ('programme_admin', 'super_admin') and deleted_at is null),
      'pending_deletions', (select count(*) from profiles where deleted_at is not null)),
    'db_size_mb', round(pg_database_size(current_database()) / 1048576.0, 1));
end $$;

-- ───────────── facility level additions for facility admins and staff
-- Child daily checks (the staff dashboard's colour-coded card).
create or replace function public.child_check_kpis(p_facility uuid, p_from date, p_to date)
returns table (checks bigint, children bigint, green bigint, amber bigint, red bigint, top_signs jsonb)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.staff_of(p_facility) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  return query
  with ck as (
    select c.baby_id, c.baby_signs, greatest(c.level, coalesce(c.server_level, c.level)) lvl
    from checkins c join profiles p on p.id = c.mother_id
    where p.home_facility = p_facility and p.deleted_at is null and sharing_on(p.id, p_facility)
      and c.baby_id is not null and c.deleted_at is null and c.client_created_at::date between p_from and p_to)
  select count(*), count(distinct ck.baby_id),
    count(*) filter (where ck.lvl = 'green'), count(*) filter (where ck.lvl = 'amber'), count(*) filter (where ck.lvl = 'red'),
    coalesce((select jsonb_agg(jsonb_build_object('sign', s.sign, 'n', s.n) order by s.n desc, s.sign)
              from (select x.sign, count(*) n from ck, unnest(ck.baby_signs) x(sign) group by x.sign order by 2 desc, 1 limit 8) s), '[]'::jsonb)
  from ck;
end $$;

-- Check-ins per day at one facility (mothers who share).
create or replace function public.facility_daily(p_facility uuid, p_from date, p_to date)
returns table (day date, checks bigint, red bigint, amber bigint)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.staff_of(p_facility) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if p_to < p_from or p_to - p_from > 400 then
    raise exception 'choose a date range of up to 400 days' using errcode = '22023';
  end if;
  return query
  with days as (select generate_series(p_from, p_to, interval '1 day')::date d),
  ck as (select c.client_created_at::date d, count(*) n,
                count(*) filter (where greatest(c.level, coalesce(c.server_level, c.level)) = 'red') r,
                count(*) filter (where greatest(c.level, coalesce(c.server_level, c.level)) = 'amber') a
         from checkins c join profiles p on p.id = c.mother_id
         where p.home_facility = p_facility and p.deleted_at is null and sharing_on(p.id, p_facility)
           and c.deleted_at is null and c.client_created_at::date between p_from and p_to group by 1)
  select days.d, coalesce(ck.n, 0), coalesce(ck.r, 0), coalesce(ck.a, 0) from days left join ck on ck.d = days.d order by days.d;
end $$;

-- ───────────── grants
revoke execute on function public.scope_facilities(text, uuid, uuid) from public, anon, authenticated;
revoke execute on function public.check_admin_range(date, date) from public, anon, authenticated;
do $$
declare f text;
begin
  foreach f in array array[
    'public.uuid_or_null(text)',
    'public.admin_kpis(date, date, text, uuid, uuid)', 'public.admin_daily(date, date, text, uuid, uuid)',
    'public.admin_facility_table(date, date, text, uuid)', 'public.admin_staff_activity(date, date, uuid)',
    'public.admin_audit(timestamptz, timestamptz, uuid, text, uuid, integer, bigint)', 'public.admin_audit_actions()',
    'public.admin_system()', 'public.child_check_kpis(uuid, date, date)', 'public.facility_daily(uuid, date, date)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
