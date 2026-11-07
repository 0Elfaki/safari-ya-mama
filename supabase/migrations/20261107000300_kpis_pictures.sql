-- More KPIs for the dashboard, and app picture names beyond lesson steps.
--
-- 1. platform_kpis(): the state of the whole system that does not depend on mothers' data
--    (accounts, facilities, content, website, app usage). Platform admins only. Mother and
--    caregiver totals follow the privacy rule (1 to 4 → hidden).
-- 2. admin_kpis_extra(): pregnancy care, baby care and engagement for the same country / district /
--    facility / period filter as admin_kpis(), with the same privacy rule. Definitions are listed on
--    the dashboard's "About the numbers" page.
-- 3. app-media accepts every picture ID the app uses (HERO-WELCOME, MM-PR-1, SZ-28, HOME-DOCTOR,
--    NB-SLEEP-P1 …), not only lesson step pictures. Lesson step pictures still need the -P<n> form.

create or replace function public.platform_kpis()
returns jsonb language plpgsql stable security definer set search_path = public, auth as $$
declare
  v_m bigint := (select count(*) from profiles where role = 'mother' and deleted_at is null);
  v_c bigint := (select count(*) from profiles where role = 'caregiver' and deleted_at is null);
begin
  if not public.is_platform_admin() then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'checked_at', now(),
    'accounts', (select coalesce(jsonb_object_agg(role, n), '{}'::jsonb) from (
                   select p.role::text role, count(*) n from profiles p
                   where p.deleted_at is null and p.role not in ('mother', 'caregiver') group by 1) q),
    'accounts_unconfirmed', (select count(*) from profiles p join auth.users u on u.id = p.id
                             where p.deleted_at is null and p.role not in ('mother', 'caregiver') and u.email_confirmed_at is null),
    'accounts_without_mfa', (select count(*) from profiles p
                             where p.deleted_at is null
                               and p.role in ('super_admin', 'programme_admin', 'editor', 'author', 'clinical_reviewer', 'viewer')
                               and not exists (select 1 from auth.mfa_factors m where m.user_id = p.id and m.status = 'verified')),
    'facilities', jsonb_build_object(
      'active', (select count(*) from facilities where active),
      'inactive', (select count(*) from facilities where not active),
      'without_staff', (select count(*) from facilities f where f.active
                          and not exists (select 1 from staff_assignments s join profiles p on p.id = s.staff_id
                                          where s.facility_id = f.id and s.active and p.deleted_at is null)),
      'emergency_24h', (select count(*) from facilities where active and emergency_24h),
      'by_level', (select coalesce(jsonb_object_agg(level, n), '{}'::jsonb) from (select level, count(*) n from facilities where active group by 1) q)),
    'content', jsonb_build_object(
      'content_version', (select content_version from content_meta where id = 1),
      'lessons_published', (select count(*) from lessons where status = 'published'),
      'lessons_draft', (select count(*) from lessons where status = 'draft'),
      'lessons_retired', (select count(*) from lessons where status = 'retired'),
      'lessons_app', (select count(*) from lessons where status = 'published' and 'app' = any(channels)),
      'lessons_web', (select count(*) from lessons where status = 'published' and 'web' = any(channels)),
      'lessons_unreviewed', (select count(distinct t.lesson_id) from lesson_translations t join lessons l on l.id = t.lesson_id
                             where l.status <> 'retired' and t.reviewed_by is null),
      'app_items_live', (select count(distinct key) from app_content where published and not archived),
      'app_items_pending_review', (select count(distinct key) from app_content
                                   where not archived and mentions_symptoms and reviewed_by is null),
      'app_pictures', (select count(*) from storage.objects where bucket_id = 'app-media'),
      'site_pictures', (select count(*) from media where not archived)),
    'website', jsonb_build_object(
      'posts_live', (select count(*) from blog_posts where published and not archived and published_at <= now()),
      'posts_scheduled', (select count(*) from blog_posts where published and not archived and published_at > now()),
      'posts_draft', (select count(*) from blog_posts where not archived and status = 'draft'),
      'posts_in_review', (select count(*) from blog_posts where not archived and status = 'in_review'),
      'posts_awaiting_clinical', (select count(*) from blog_posts where not archived and health_review = 'requested'),
      'posts_unpublished_changes', (select count(*) from blog_posts where not archived and published and has_draft_changes),
      'sections_live', (select count(*) from site_sections where published and not archived),
      'sections_total', (select count(*) from site_sections where not archived),
      'sections_changed', (select count(*) from site_sections where has_changes and not archived),
      'partners_live', (select count(*) from partners where published and not archived),
      'partners_proposed', (select count(*) from partners where status = 'proposed' and not archived),
      'impact_live', (select count(*) from impact_kpis where published and not archived),
      'impact_demo_live', (select count(*) from impact_kpis where published and is_demo and not archived),
      'messages_new', (select count(*) from contact_messages where status = 'new'),
      'messages_30d', (select count(*) from contact_messages where created_at > now() - interval '30 days')),
    'usage', jsonb_build_object(
      'mothers', case when v_m between 1 and 4 then null else v_m end,
      'caregivers', case when v_c between 1 and 4 then null else v_c end,
      'mothers_new_30d', (select case when n between 1 and 4 then null else n end from
                           (select count(*) n from profiles where role = 'mother' and deleted_at is null and created_at > now() - interval '30 days') q),
      'push_devices', (select count(*) from push_subscriptions),
      'ai_24h', (select count(*) from ai_usage where at > now() - interval '24 hours'),
      'ai_7d', (select count(*) from ai_usage where at > now() - interval '7 days'),
      'staff_sign_ins_7d', (select count(*) from audit_log where action in ('staff_sign_in', 'admin_sign_in') and at > now() - interval '7 days'),
      'records_opened_7d', (select count(*) from audit_log where action = 'view_mother' and at > now() - interval '7 days'),
      'last_checkin', (select max(created_at) from checkins),
      'notifications_failed_7d', (select count(*) from notification_queue where status = 'failed' and send_after > now() - interval '7 days')));
end $$;

create or replace function public.admin_kpis_extra(p_from date, p_to date, p_country text default null,
                                                   p_district uuid default null, p_facility uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  v_all boolean := p_country is null and p_district is null and p_facility is null;
  v_ids uuid[];
  v_n bigint;
begin
  perform public.check_admin_range(p_from, p_to);
  select coalesce(array_agg(p.id), '{}') into v_ids from profiles p
  where p.role = 'mother' and p.deleted_at is null
    and (v_all or p.home_facility in (select public.scope_facilities(p_country, p_district, p_facility)));
  v_n := cardinality(v_ids);
  if v_n between 1 and 4 then
    return jsonb_build_object('suppressed', true);
  end if;
  return jsonb_build_object(
    'suppressed', false,
    'pregnancy', (select jsonb_build_object(
        'active', count(*),
        'trimester_1', count(*) filter (where w < 13),
        'trimester_2', count(*) filter (where w between 13 and 27),
        'trimester_3', count(*) filter (where w >= 28),
        'weeks_36_plus', count(*) filter (where w >= 36),
        'due_14d', count(*) filter (where x.edd between current_date and current_date + 14),
        'birth_plan_36w_pct', round(avg(case when exists (select 1 from birth_plans b where b.mother_id = x.mother_id and b.deleted_at is null)
                                             then 1.0 else 0 end) filter (where w >= 36), 2))
      from (select x.*, (current_date - x.lmp) / 7 w from pregnancies x
            where x.mother_id = any(v_ids) and x.status = 'active' and x.deleted_at is null) x),
    'anc1_before_12w_pct', (select round(avg(case when q.first_visit - q.lmp < 84 then 1.0 else 0 end), 2) from (
        select x.id, x.lmp, min(a.attended_on) first_visit from pregnancies x
        join appointments a on a.mother_id = x.mother_id and a.kind = 'anc' and a.attended_on is not null
                           and a.deleted_at is null and a.attended_on >= x.lmp
        where x.mother_id = any(v_ids) and x.deleted_at is null and (x.status = 'active' or x.ended_on >= p_from)
        group by x.id, x.lmp) q),
    'high_bp_women', (select count(distinct b.mother_id) from (
        select mother_id, systolic s, diastolic d, client_created_at t from bp_readings where deleted_at is null
        union all
        select mother_id, systolic, diastolic, client_created_at from checkins where deleted_at is null and systolic is not null) b
        where b.mother_id = any(v_ids) and b.t::date between p_from and p_to and (b.s >= 140 or b.d >= 90)),
    'reduced_movements', (select count(distinct c.mother_id) from checkins c
        where c.mother_id = any(v_ids) and c.deleted_at is null and c.client_created_at::date between p_from and p_to
          and c.movement in ('fewer', 'none')),
    'kick_sessions', (select count(*) from kick_counts k where k.mother_id = any(v_ids) and k.deleted_at is null
          and k.client_created_at::date between p_from and p_to),
    'baby', (select jsonb_build_object(
        'babies', count(*),
        'under_1_month', count(*) filter (where current_date - b.dob < 31),
        'growth_monthly_pct', round(avg(case when exists (select 1 from growth_measures g where g.baby_id = b.id and g.deleted_at is null
                                                          and g.measured_on > current_date - 31) then 1.0 else 0 end)
                                    filter (where current_date - b.dob < 730), 2))
      from babies b where b.mother_id = any(v_ids) and b.deleted_at is null),
    'baby_checks', (select jsonb_build_object('total', count(*),
                                              'with_danger_signs', count(*) filter (where cardinality(c.baby_signs) > 0))
      from checkins c where c.mother_id = any(v_ids) and c.deleted_at is null and c.baby_id is not null
        and c.client_created_at::date between p_from and p_to),
    'vaccines_on_time_pct', (select round(avg(case when v.given_on is not null and v.given_on <= v.due_on + 14 then 1.0 else 0 end), 2)
      from vaccine_doses v where v.mother_id = any(v_ids) and v.due_on between p_from and least(p_to, current_date - 14)),
    'engagement', jsonb_build_object(
      'active_30d', (select count(distinct c.mother_id) from checkins c where c.mother_id = any(v_ids) and c.deleted_at is null
                       and c.client_created_at > now() - interval '30 days'),
      'checking_mothers', (select count(distinct c.mother_id) from checkins c where c.mother_id = any(v_ids) and c.deleted_at is null
                             and c.client_created_at::date between p_from and p_to),
      'checks_per_mother', (select round(count(*)::numeric / nullif(count(distinct c.mother_id), 0), 1) from checkins c
                              where c.mother_id = any(v_ids) and c.deleted_at is null and c.client_created_at::date between p_from and p_to),
      'lessons_completed', (select count(*) from lesson_views v where v.mother_id = any(v_ids) and v.completed
                              and v.viewed_at::date between p_from and p_to),
      'top_lessons', (select coalesce(jsonb_agg(jsonb_build_object('lesson', q.lesson_id, 'views', q.n) order by q.n desc), '[]'::jsonb) from (
                        select v.lesson_id, count(*) n from lesson_views v where v.mother_id = any(v_ids)
                          and v.viewed_at::date between p_from and p_to group by 1 order by 2 desc limit 5) q),
      'birth_plans', (select count(*) from birth_plans b where b.mother_id = any(v_ids) and b.deleted_at is null),
      'visit_questions', (select count(*) from visit_questions q where q.mother_id = any(v_ids) and q.deleted_at is null
                            and q.created_at::date between p_from and p_to),
      'medication_plans', (select count(*) from medications m where m.mother_id = any(v_ids) and m.deleted_at is null)));
end $$;

revoke all on function public.platform_kpis() from public, anon;
grant execute on function public.platform_kpis() to authenticated;
revoke all on function public.admin_kpis_extra(date, date, text, uuid, uuid) from public, anon;
grant execute on function public.admin_kpis_extra(date, date, text, uuid, uuid) to authenticated;

alter policy media_admin_insert on storage.objects
  with check ((bucket_id = 'site-media' and public.web_can('edit') and name ~ '^[a-z0-9][a-z0-9/_.-]{0,199}\.(webp|png|jpe?g)$')
           or (bucket_id = 'app-media' and public.is_platform_admin() and name ~ '^[A-Z]{2,5}(-[A-Z0-9]+)+\.webp$'));
alter policy media_admin_update on storage.objects
  using ((bucket_id = 'site-media' and public.web_can('edit')) or (bucket_id = 'app-media' and public.is_platform_admin()))
  with check ((bucket_id = 'site-media' and public.web_can('edit') and name ~ '^[a-z0-9][a-z0-9/_.-]{0,199}\.(webp|png|jpe?g)$')
           or (bucket_id = 'app-media' and public.is_platform_admin() and name ~ '^[A-Z]{2,5}(-[A-Z0-9]+)+\.webp$'));
