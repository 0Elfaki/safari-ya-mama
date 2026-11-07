-- Role × action permission tests for the dashboard (migrations 20261106000000…20261107000300).
-- Runs in ONE transaction that is rolled back: the synthetic accounts, facilities, mothers,
-- alerts and content below never persist. Safe to run against the live project:
--   supabase db execute < supabase/tests/permissions.sql      (or paste into the SQL editor)
-- Output: one row per test with pass = true/false. Every row must be true.
begin;

create temp table t_result (n serial primary key, test text not null, pass boolean not null, detail text);

-- act as a signed-in user (aal2 = finished MFA) or as anon
create function pg_temp.act(p_user uuid, p_aal text) returns void language plpgsql as $$
begin
  if p_user is null then
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    perform set_config('role', 'anon', true);
  else
    perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated', 'aal', p_aal)::text, true);
    perform set_config('role', 'authenticated', true);
  end if;
end $$;

-- run p_sql as the user; pass when it succeeds exactly when it should
create function pg_temp.expect(p_test text, p_user uuid, p_aal text, p_sql text, p_allowed boolean) returns void language plpgsql as $$
declare v_ok boolean := true; v_err text;
begin
  perform pg_temp.act(p_user, p_aal);
  begin
    execute p_sql;
  exception when others then
    v_ok := false; v_err := sqlerrm;
  end;
  perform set_config('role', 'postgres', true);
  insert into t_result (test, pass, detail) values (p_test, v_ok = p_allowed, coalesce(v_err, 'allowed'));
end $$;

-- run a query returning one number as the user; pass when it equals p_expected
create function pg_temp.expect_n(p_test text, p_user uuid, p_aal text, p_sql text, p_expected bigint) returns void language plpgsql as $$
declare v bigint; v_err text;
begin
  perform pg_temp.act(p_user, p_aal);
  begin
    execute p_sql into v;
  exception when others then
    v_err := sqlerrm;
  end;
  perform set_config('role', 'postgres', true);
  insert into t_result (test, pass, detail) values (p_test, v_err is null and v = p_expected, coalesce(v_err, 'got ' || coalesce(v::text, 'null')));
end $$;

-- ───────── synthetic world (rolled back)
insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select ('00000000-0000-4000-b000-0000000000' || x.n)::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
       'perm-test-' || x.n || '@example.invalid', now(), '{}', '{}', now(), now()
from (values ('01'), ('02'), ('03'), ('04'), ('05'), ('06'), ('07'), ('08')) x(n);
-- 01 super admin · 02 admin · 03 facility admin T1 · 04 health worker T1 · 05 health worker T2 · 06 mother sharing T1 · 07 mother not sharing · 08 facility admin T2
update profiles set role = 'super_admin', display_name = 'Test Super' where id = '00000000-0000-4000-b000-000000000001';
update profiles set role = 'programme_admin', display_name = 'Test Admin' where id = '00000000-0000-4000-b000-000000000002';
update profiles set role = 'facility_admin', display_name = 'Test FacAdmin 1' where id = '00000000-0000-4000-b000-000000000003';
update profiles set role = 'health_worker', display_name = 'Test HW 1' where id = '00000000-0000-4000-b000-000000000004';
update profiles set role = 'health_worker', display_name = 'Test HW 2' where id = '00000000-0000-4000-b000-000000000005';
update profiles set role = 'facility_admin', display_name = 'Test FacAdmin 2' where id = '00000000-0000-4000-b000-000000000008';

insert into facilities (id, district_id, name, level, active)
select '00000000-0000-4000-b000-0000000000f1'::uuid, (select id from districts order by name limit 1), 'Perm Test Facility 1', 'health_centre', true union all
select '00000000-0000-4000-b000-0000000000f2'::uuid, (select id from districts order by name limit 1), 'Perm Test Facility 2', 'dispensary', true;

insert into staff_assignments (staff_id, facility_id, active) values
  ('00000000-0000-4000-b000-000000000003', '00000000-0000-4000-b000-0000000000f1', true),
  ('00000000-0000-4000-b000-000000000004', '00000000-0000-4000-b000-0000000000f1', true),
  ('00000000-0000-4000-b000-000000000005', '00000000-0000-4000-b000-0000000000f2', true),
  ('00000000-0000-4000-b000-000000000008', '00000000-0000-4000-b000-0000000000f2', true);

update profiles set home_facility = '00000000-0000-4000-b000-0000000000f1', display_name = 'Test Mother A'
where id in ('00000000-0000-4000-b000-000000000006', '00000000-0000-4000-b000-000000000007');
insert into consents (mother_id, kind, facility_id, granted, text_version)
values ('00000000-0000-4000-b000-000000000006', 'share_with_facility', '00000000-0000-4000-b000-0000000000f1', true, 'test');
insert into alerts (id, mother_id, facility_id, source_table, source_id, level, reasons, status)
values ('00000000-0000-4000-b000-0000000000a1', '00000000-0000-4000-b000-000000000006', '00000000-0000-4000-b000-0000000000f1',
        'checkins', gen_random_uuid(), 'red', array['bleeding'], 'open');

-- ───────── facilities: super admin only, and only with MFA
select pg_temp.expect('super admin creates a facility', '00000000-0000-4000-b000-000000000001', 'aal2',
  $q$select public.admin_save_facility(null, 'Perm Test New', 'hospital', (select id from districts limit 1), null, true, -6.8, 39.2)$q$, true);
select pg_temp.expect('super admin without MFA cannot create a facility', '00000000-0000-4000-b000-000000000001', 'aal1',
  $q$select public.admin_save_facility(null, 'Perm Test New 2', 'hospital', (select id from districts limit 1), null, true, null, null)$q$, false);
select pg_temp.expect('admin cannot create a facility', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.admin_save_facility(null, 'Perm Test New 3', 'hospital', (select id from districts limit 1), null, true, null, null)$q$, false);
select pg_temp.expect('facility admin cannot create a facility', '00000000-0000-4000-b000-000000000003', 'aal1',
  $q$select public.admin_save_facility(null, 'Perm Test New 4', 'hospital', (select id from districts limit 1), null, true, null, null)$q$, false);
select pg_temp.expect('health worker cannot create a facility', '00000000-0000-4000-b000-000000000004', 'aal1',
  $q$select public.admin_save_facility(null, 'Perm Test New 5', 'hospital', (select id from districts limit 1), null, true, null, null)$q$, false);
select pg_temp.expect('admin cannot deactivate a facility', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.admin_set_facility_active('00000000-0000-4000-b000-0000000000f2', false)$q$, false);
select pg_temp.expect('super admin deactivates a facility', '00000000-0000-4000-b000-000000000001', 'aal2',
  $q$select public.admin_set_facility_active('00000000-0000-4000-b000-0000000000f2', false)$q$, true);
select pg_temp.expect('super admin reactivates a facility', '00000000-0000-4000-b000-000000000001', 'aal2',
  $q$select public.admin_set_facility_active('00000000-0000-4000-b000-0000000000f2', true)$q$, true);
select pg_temp.expect('anon cannot list admin facilities', null, null, $q$select * from public.admin_facilities()$q$, false);
select pg_temp.expect_n('anon sees active facility names for sign-in', null, null,
  $q$select count(*) from public.sign_in_facilities() where name like 'Perm Test Facility%'$q$, 2);

-- ───────── accounts: who may create / manage whom (the admin-users Edge Function asks these)
select pg_temp.expect_n('super admin may create an admin', '00000000-0000-4000-b000-000000000001', 'aal2',
  $q$select public.can_manage_account('programme_admin', null)::int$q$, 1);
select pg_temp.expect_n('super admin may create a facility admin', '00000000-0000-4000-b000-000000000001', 'aal2',
  $q$select public.can_manage_account('facility_admin', '00000000-0000-4000-b000-0000000000f1')::int$q$, 1);
select pg_temp.expect_n('admin may not create an admin', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.can_manage_account('programme_admin', null)::int$q$, 0);
select pg_temp.expect_n('admin may not create a super admin', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.can_manage_account('super_admin', null)::int$q$, 0);
select pg_temp.expect_n('admin may not create a facility admin', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.can_manage_account('facility_admin', '00000000-0000-4000-b000-0000000000f1')::int$q$, 0);
select pg_temp.expect_n('admin may create a health worker', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.can_manage_account('health_worker', '00000000-0000-4000-b000-0000000000f2')::int$q$, 1);
select pg_temp.expect_n('admin without MFA may not create a health worker', '00000000-0000-4000-b000-000000000002', 'aal1',
  $q$select public.can_manage_account('health_worker', '00000000-0000-4000-b000-0000000000f2')::int$q$, 0);
select pg_temp.expect_n('facility admin may create a health worker for own facility', '00000000-0000-4000-b000-000000000003', 'aal1',
  $q$select public.can_manage_account('health_worker', '00000000-0000-4000-b000-0000000000f1')::int$q$, 1);
select pg_temp.expect_n('facility admin may not create a health worker elsewhere', '00000000-0000-4000-b000-000000000003', 'aal1',
  $q$select public.can_manage_account('health_worker', '00000000-0000-4000-b000-0000000000f2')::int$q$, 0);
select pg_temp.expect_n('health worker may not create accounts', '00000000-0000-4000-b000-000000000004', 'aal1',
  $q$select public.can_manage_account('health_worker', '00000000-0000-4000-b000-0000000000f1')::int$q$, 0);
select pg_temp.expect_n('facility admin may manage own health worker', '00000000-0000-4000-b000-000000000003', 'aal1',
  $q$select public.can_manage_user('00000000-0000-4000-b000-000000000004')::int$q$, 1);
select pg_temp.expect_n('facility admin may not manage another facility''s health worker', '00000000-0000-4000-b000-000000000003', 'aal1',
  $q$select public.can_manage_user('00000000-0000-4000-b000-000000000005')::int$q$, 0);
select pg_temp.expect_n('facility admin may not manage another facility admin', '00000000-0000-4000-b000-000000000003', 'aal1',
  $q$select public.can_manage_user('00000000-0000-4000-b000-000000000008')::int$q$, 0);
select pg_temp.expect_n('admin may manage any health worker', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.can_manage_user('00000000-0000-4000-b000-000000000005')::int$q$, 1);
select pg_temp.expect_n('admin may not manage a facility admin', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.can_manage_user('00000000-0000-4000-b000-000000000003')::int$q$, 0);
select pg_temp.expect_n('admin may not manage the super admin', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.can_manage_user('00000000-0000-4000-b000-000000000001')::int$q$, 0);
select pg_temp.expect_n('super admin may manage an admin', '00000000-0000-4000-b000-000000000001', 'aal2',
  $q$select public.can_manage_user('00000000-0000-4000-b000-000000000002')::int$q$, 1);
select pg_temp.expect_n('nobody may manage their own account', '00000000-0000-4000-b000-000000000001', 'aal2',
  $q$select public.can_manage_user('00000000-0000-4000-b000-000000000001')::int$q$, 0);
select pg_temp.expect_n('mothers are never managed from the dashboard', '00000000-0000-4000-b000-000000000001', 'aal2',
  $q$select public.can_manage_user('00000000-0000-4000-b000-000000000006')::int$q$, 0);

-- ───────── staff assignments and roles
select pg_temp.expect('facility admin adds a health worker to own facility', '00000000-0000-4000-b000-000000000003', 'aal1',
  $q$select public.admin_assign_staff('00000000-0000-4000-b000-000000000005', '00000000-0000-4000-b000-0000000000f1', true)$q$, true);
select pg_temp.expect('facility admin cannot assign to another facility', '00000000-0000-4000-b000-000000000003', 'aal1',
  $q$select public.admin_assign_staff('00000000-0000-4000-b000-000000000004', '00000000-0000-4000-b000-0000000000f2', true)$q$, false);
select pg_temp.expect('facility admin cannot change own access', '00000000-0000-4000-b000-000000000003', 'aal1',
  $q$select public.admin_assign_staff('00000000-0000-4000-b000-000000000003', '00000000-0000-4000-b000-0000000000f1', false)$q$, false);
select pg_temp.expect('admin cannot assign a facility admin', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.admin_assign_staff('00000000-0000-4000-b000-000000000008', '00000000-0000-4000-b000-0000000000f1', true)$q$, false);
select pg_temp.expect('health worker cannot write staff_assignments directly', '00000000-0000-4000-b000-000000000004', 'aal1',
  $q$insert into staff_assignments (staff_id, facility_id) values ('00000000-0000-4000-b000-000000000004', '00000000-0000-4000-b000-0000000000f2')$q$, false);
select pg_temp.expect('facility admin cannot write staff_assignments directly', '00000000-0000-4000-b000-000000000003', 'aal1',
  $q$insert into staff_assignments (staff_id, facility_id) values ('00000000-0000-4000-b000-000000000007', '00000000-0000-4000-b000-0000000000f1')$q$, false);
select pg_temp.expect('admin cannot change roles', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.admin_set_role('00000000-0000-4000-b000-000000000004', 'programme_admin')$q$, false);
select pg_temp.expect('a user cannot raise their own role', '00000000-0000-4000-b000-000000000004', 'aal1',
  $q$update profiles set role = 'super_admin' where id = '00000000-0000-4000-b000-000000000004'$q$, false);
select pg_temp.expect('super admin changes a role', '00000000-0000-4000-b000-000000000001', 'aal2',
  $q$select public.admin_set_role('00000000-0000-4000-b000-000000000008', 'health_worker')$q$, true);

-- ───────── sign-in: facility check
select pg_temp.expect_n('health worker signs in at own facility', '00000000-0000-4000-b000-000000000004', 'aal1',
  $q$select (public.staff_session('00000000-0000-4000-b000-0000000000f1') ->> 'ok')::boolean::int$q$, 1);
select pg_temp.expect_n('health worker refused at a facility they are not registered at', '00000000-0000-4000-b000-000000000004', 'aal1',
  $q$select (public.staff_session('00000000-0000-4000-b000-0000000000f2') ->> 'ok')::boolean::int$q$, 0);
select pg_temp.expect_n('admin refused at the medical staff entrance', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select (public.staff_session('00000000-0000-4000-b000-0000000000f1') ->> 'ok')::boolean::int$q$, 0);
select pg_temp.expect_n('mother refused at the medical staff entrance', '00000000-0000-4000-b000-000000000006', 'aal1',
  $q$select (public.staff_session('00000000-0000-4000-b000-0000000000f1') ->> 'ok')::boolean::int$q$, 0);
select pg_temp.expect('health worker refused at the administration entrance', '00000000-0000-4000-b000-000000000004', 'aal1',
  $q$select public.admin_session()$q$, false);
select pg_temp.expect_n('wrong-facility attempt is written to audit_log', null, null,
  $q$select 1$q$, 1);
update t_result set pass = exists (select 1 from audit_log where action = 'staff_sign_in_refused'
  and actor_id = '00000000-0000-4000-b000-000000000004') where test = 'wrong-facility attempt is written to audit_log';

-- ───────── consent: staff see a mother only while she shares with their facility
select pg_temp.expect_n('health worker sees the sharing mother', '00000000-0000-4000-b000-000000000004', 'aal1',
  $q$select count(*) from profiles where id = '00000000-0000-4000-b000-000000000006'$q$, 1);
select pg_temp.expect_n('health worker does not see a mother who does not share', '00000000-0000-4000-b000-000000000004', 'aal1',
  $q$select count(*) from profiles where id = '00000000-0000-4000-b000-000000000007'$q$, 0);
select pg_temp.expect_n('admin does not see mothers (aggregates only)', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select count(*) from profiles where id = '00000000-0000-4000-b000-000000000006'$q$, 0);
select pg_temp.expect('health worker logs a record view', '00000000-0000-4000-b000-000000000004', 'aal1',
  $q$select public.log_view('00000000-0000-4000-b000-000000000006', 'record')$q$, true);
select pg_temp.expect_n('record view is in audit_log', null, null, $q$select 1$q$, 1);
update t_result set pass = exists (select 1 from audit_log where action = 'view_mother' and actor_id = '00000000-0000-4000-b000-000000000004'
  and mother_id = '00000000-0000-4000-b000-000000000006') where test = 'record view is in audit_log';
select pg_temp.expect('health worker cannot log a view of a mother who does not share', '00000000-0000-4000-b000-000000000004', 'aal1',
  $q$select public.log_view('00000000-0000-4000-b000-000000000007', 'record')$q$, false);
select pg_temp.expect_n('nobody reads journals but the mother', '00000000-0000-4000-b000-000000000004', 'aal1',
  $q$select count(*) from journal_entries where mother_id = '00000000-0000-4000-b000-000000000006'$q$, 0);

-- ───────── alerts
select pg_temp.expect('health worker acknowledges an alert at own facility', '00000000-0000-4000-b000-000000000004', 'aal1',
  $q$select public.set_alert_status('00000000-0000-4000-b000-0000000000a1', 'acknowledged', 'test')$q$, true);
select pg_temp.expect('facility admin assigns an alert to own staff', '00000000-0000-4000-b000-000000000003', 'aal1',
  $q$select public.assign_alert('00000000-0000-4000-b000-0000000000a1', '00000000-0000-4000-b000-000000000004')$q$, true);
select pg_temp.expect('health worker cannot assign alerts', '00000000-0000-4000-b000-000000000004', 'aal1',
  $q$select public.assign_alert('00000000-0000-4000-b000-0000000000a1', '00000000-0000-4000-b000-000000000004')$q$, false);
select pg_temp.expect('facility admin cannot assign an alert to an outsider', '00000000-0000-4000-b000-000000000003', 'aal1',
  $q$select public.assign_alert('00000000-0000-4000-b000-0000000000a1', '00000000-0000-4000-b000-000000000002')$q$, false);
select pg_temp.expect('health worker closes the alert', '00000000-0000-4000-b000-000000000004', 'aal1',
  $q$select public.set_alert_status('00000000-0000-4000-b000-0000000000a1', 'closed', 'test')$q$, true);
select pg_temp.expect('admin cannot act on alerts', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.set_alert_status('00000000-0000-4000-b000-0000000000a1', 'closed', null)$q$, false);

-- ───────── KPIs, audit and system health: admins with MFA only
select pg_temp.expect('admin reads KPIs', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.admin_kpis(current_date - 30, current_date)$q$, true);
select pg_temp.expect('admin without MFA cannot read KPIs', '00000000-0000-4000-b000-000000000002', 'aal1',
  $q$select public.admin_kpis(current_date - 30, current_date)$q$, false);
select pg_temp.expect('facility admin cannot read system KPIs', '00000000-0000-4000-b000-000000000003', 'aal1',
  $q$select public.admin_kpis(current_date - 30, current_date)$q$, false);
select pg_temp.expect_n('a facility with fewer than 5 mothers is suppressed', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select (public.admin_kpis(current_date - 30, current_date, null, null, '00000000-0000-4000-b000-0000000000f1') ->> 'suppressed')::boolean::int$q$, 1);
select pg_temp.expect_n('facility table hides mother counts under 5', '00000000-0000-4000-b000-000000000001', 'aal2',
  $q$select count(*) from public.admin_facility_table(current_date - 30, current_date) where facility_id = '00000000-0000-4000-b000-0000000000f1' and mothers is null$q$, 1);
select pg_temp.expect('admin reads the audit log', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select * from public.admin_audit(null, null, null, null, null, 10, null)$q$, true);
select pg_temp.expect('health worker cannot read the audit log', '00000000-0000-4000-b000-000000000004', 'aal1',
  $q$select * from public.admin_audit(null, null, null, null, null, 10, null)$q$, false);
select pg_temp.expect_n('audit viewer shows mothers only as a pseudonym', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select count(*) from public.admin_audit(null, null, null, null, null, 500, null) where subject like '%Test Mother%'$q$, 0);
select pg_temp.expect('admin reads system health', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.admin_system()$q$, true);
select pg_temp.expect_n('no signed-in user can edit the audit log', '00000000-0000-4000-b000-000000000001', 'aal2',
  $q$with u as (update audit_log set action = 'x' where true returning 1) select count(*) from u$q$, 0);
select pg_temp.expect_n('the database owner cannot edit the audit log either', null, null, $q$select 1$q$, 1);
do $$ begin
  begin
    update audit_log set action = action where id = (select max(id) from audit_log);
    update t_result set pass = false, detail = 'owner update allowed' where test = 'the database owner cannot edit the audit log either';
  exception when others then null;
  end;
end $$;
select pg_temp.expect('anon cannot read KPIs', null, null, $q$select public.admin_kpis(current_date - 30, current_date)$q$, false);

-- ───────── content: both languages, clinical sign-off, live lock, public read
insert into lessons (id, category, format, minutes, stage, sort) values ('perm-test-lesson', 'preg', 'guide', 2, 'pregnant', 999);
select pg_temp.expect('admin writes a draft lesson', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$insert into lesson_translations (lesson_id, lang, title, steps) values ('perm-test-lesson', 'en', 'Test lesson', array['One', 'Two'])$q$, true);
select pg_temp.expect('publish blocked until Kiswahili exists', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.lesson_publish('perm-test-lesson', 'Registered midwife', current_date)$q$, false);
select pg_temp.expect('admin adds Kiswahili', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$insert into lesson_translations (lesson_id, lang, title, steps) values ('perm-test-lesson', 'sw', 'Somo la jaribio', array['Moja', 'Mbili'])$q$, true);
select pg_temp.expect('publish blocked without clinical sign-off', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.lesson_publish('perm-test-lesson')$q$, false);
select pg_temp.expect('health worker cannot publish', '00000000-0000-4000-b000-000000000004', 'aal1',
  $q$select public.lesson_publish('perm-test-lesson', 'Registered midwife', current_date)$q$, false);
select pg_temp.expect('admin publishes with sign-off', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.lesson_publish('perm-test-lesson', 'Registered midwife', current_date)$q$, true);
select pg_temp.expect('a live lesson cannot be edited', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$update lesson_translations set title = 'Changed' where lesson_id = 'perm-test-lesson' and lang = 'en'$q$, false);
select pg_temp.expect('publishing is only through lesson_publish', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$insert into lessons (id, category, format, minutes, stage, status) values ('perm-test-2', 'preg', 'guide', 2, 'pregnant', 'published')$q$, false);
select pg_temp.expect_n('anon reads the published web lesson', null, null,
  $q$select count(*) from lessons where id = 'perm-test-lesson'$q$, 1);
select pg_temp.expect_n('the app manifest has the lesson', null, null,
  $q$select count(*) from jsonb_array_elements(public.app_content_manifest() -> 'lessons') x where x ->> 'id' = 'perm-test-lesson'$q$, 1);
select pg_temp.expect('admin unpublishes to edit', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.lesson_set_status('perm-test-lesson', 'draft')$q$, true);
select pg_temp.expect_n('editing the text clears the sign-off', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$with u as (update lesson_translations set title = 'Changed lesson' where lesson_id = 'perm-test-lesson' and lang = 'en' returning reviewed_by) select count(*) from u where reviewed_by is null$q$, 1);
select pg_temp.expect('admin restores version 1', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.lesson_restore('perm-test-lesson', 1)$q$, true);
select pg_temp.expect_n('the restored version keeps its sign-off', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select count(*) from lesson_translations where lesson_id = 'perm-test-lesson' and title = 'Test lesson' and reviewed_by = 'Registered midwife'$q$, 1);
select pg_temp.expect_n('admin without MFA cannot edit lessons (RLS)', '00000000-0000-4000-b000-000000000002', 'aal1',
  $q$with u as (update lessons set sort = 998 where id = 'perm-test-lesson' returning 1) select count(*) from u$q$, 0);

select pg_temp.expect('admin saves a website page draft', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.site_content_save('faq.perm-test', 'faq', 1, null, 'Question?', 'Answer.', '', '')$q$, true);
select pg_temp.expect('website publish blocked until both languages have text', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.site_content_publish('faq.perm-test')$q$, false);
select pg_temp.expect('admin completes the Kiswahili text', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.site_content_save('faq.perm-test', 'faq', 1, null, 'Question?', 'Answer.', 'Swali?', 'Jibu.')$q$, true);
select pg_temp.expect('admin publishes the page in both languages', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.site_content_publish('faq.perm-test')$q$, true);
select pg_temp.expect_n('anon reads the published page', null, null,
  $q$select count(*) from public.site_content_public() where key = 'faq.perm-test'$q$, 2);
select pg_temp.expect('admin saves a new draft of the live page', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.site_content_save('faq.perm-test', 'faq', 1, null, 'Draft?', 'Draft.', 'Rasimu?', 'Rasimu.')$q$, true);
select pg_temp.expect_n('a new draft does not change the live page', null, null,
  $q$select count(*) from public.site_content_public('en') where key = 'faq.perm-test' and title = 'Question?'$q$, 1);
select pg_temp.expect_n('anon cannot read drafts', null, null, $q$select count(*) from site_content$q$, 0);
select pg_temp.expect('health worker cannot edit website pages', '00000000-0000-4000-b000-000000000004', 'aal1',
  $q$select public.site_content_save('faq.perm-test', 'faq', 1, null, 'x', 'x', 'x', 'x')$q$, false);

select pg_temp.expect('admin saves an announcement that mentions symptoms', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.app_content_save('home.perm-test', 'announcement', 'TZ', null, null, 'If you have heavy bleeding, go now.', 'Ukitokwa na damu nyingi, nenda sasa.', false)$q$, true);
select pg_temp.expect('announcement with symptoms needs clinical sign-off', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.app_content_publish('home.perm-test')$q$, false);
select pg_temp.expect('announcement publishes with sign-off', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.app_content_publish('home.perm-test', 'Registered midwife', current_date)$q$, true);
select pg_temp.expect_n('the manifest carries the announcement', null, null,
  $q$select count(*) from jsonb_object_keys(public.app_content_manifest() -> 'content') k where k = 'home.perm-test'$q$, 1);

-- ───────── 20261107: platform admins at any facility (with MFA), consent still applies
select pg_temp.expect_n('super admin with MFA can open any facility (staff view)', '00000000-0000-4000-b000-000000000001', 'aal2',
  $q$select (public.staff_session('00000000-0000-4000-b000-0000000000f2') ->> 'ok')::boolean::int$q$, 1);
select pg_temp.expect_n('super admin without MFA cannot open a facility', '00000000-0000-4000-b000-000000000001', 'aal1',
  $q$select (public.staff_session('00000000-0000-4000-b000-0000000000f1') ->> 'ok')::boolean::int$q$, 0);
select pg_temp.expect_n('admin with MFA reads a mother who shares with an active facility', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.can_read_mother('00000000-0000-4000-b000-000000000006')::int$q$, 1);
select pg_temp.expect_n('admin cannot read a mother who does not share', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.can_read_mother('00000000-0000-4000-b000-000000000007')::int$q$, 0);
select pg_temp.expect('super admin opening a record is logged', '00000000-0000-4000-b000-000000000001', 'aal2',
  $q$select public.log_view('00000000-0000-4000-b000-000000000006', 'record')$q$, true);
select pg_temp.expect_n('health worker at another facility still cannot read her', '00000000-0000-4000-b000-000000000005', 'aal1',
  $q$select public.can_read_mother('00000000-0000-4000-b000-000000000006')::int$q$, 0);

-- ───────── 20261107: privacy rule 1 to 4 hidden, 0 shown
select pg_temp.expect_n('2 mothers at a facility: hidden', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select (public.admin_kpis(current_date - 29, current_date, null, null, '00000000-0000-4000-b000-0000000000f1') ->> 'suppressed')::boolean::int$q$, 1);
select pg_temp.expect_n('0 mothers at a facility: shown as 0', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select (public.admin_kpis(current_date - 29, current_date, null, null, '00000000-0000-4000-b000-0000000000f2') ->> 'mothers')::int$q$, 0);
select pg_temp.expect_n('extra KPIs follow the same rule', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select (public.admin_kpis_extra(current_date - 29, current_date, null, null, '00000000-0000-4000-b000-0000000000f1') ->> 'suppressed')::boolean::int$q$, 1);
select pg_temp.expect('platform KPIs: admin with MFA', '00000000-0000-4000-b000-000000000002', 'aal2', $q$select public.platform_kpis()$q$, true);
select pg_temp.expect('platform KPIs: not health workers', '00000000-0000-4000-b000-000000000004', 'aal1', $q$select public.platform_kpis()$q$, false);

-- ───────── 20261107: website team
insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
select ('00000000-0000-4000-b000-0000000000' || x.n)::uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
       'perm-test-' || x.n || '@example.invalid', now(), '{}', '{}', now(), now()
from (values ('09'), ('10'), ('11'), ('12')) x(n);
-- 09 editor · 10 author · 11 clinical reviewer · 12 viewer
update profiles set role = 'editor', display_name = 'Test Editor' where id = '00000000-0000-4000-b000-000000000009';
update profiles set role = 'author', display_name = 'Test Author' where id = '00000000-0000-4000-b000-000000000010';
update profiles set role = 'clinical_reviewer', display_name = 'Test Reviewer' where id = '00000000-0000-4000-b000-000000000011';
update profiles set role = 'viewer', display_name = 'Test Viewer' where id = '00000000-0000-4000-b000-000000000012';

select pg_temp.expect_n('admin may create a website editor', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.can_manage_account('editor')::int$q$, 1);
select pg_temp.expect_n('facility admin may not create a website editor', '00000000-0000-4000-b000-000000000003', 'aal1',
  $q$select public.can_manage_account('editor')::int$q$, 0);
select pg_temp.expect('admin moves a viewer to author', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.admin_set_role('00000000-0000-4000-b000-000000000012', 'author')$q$, true);
select pg_temp.expect('admin cannot make a website user an Admin', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.admin_set_role('00000000-0000-4000-b000-000000000012', 'programme_admin')$q$, false);
update profiles set role = 'viewer' where id = '00000000-0000-4000-b000-000000000012';
select pg_temp.expect_n('website roles never read mothers', '00000000-0000-4000-b000-000000000009', 'aal2',
  $q$select public.can_read_mother('00000000-0000-4000-b000-000000000006')::int$q$, 0);
select pg_temp.expect('website roles cannot see KPIs about mothers', '00000000-0000-4000-b000-000000000009', 'aal2',
  $q$select public.admin_kpis(current_date - 29, current_date)$q$, false);

select pg_temp.expect('editor without MFA cannot write', '00000000-0000-4000-b000-000000000009', 'aal1',
  $q$select public.blog_save(null, '{"slug":"perm-test-x","title":"X"}'::jsonb)$q$, false);
select pg_temp.expect('editor writes a post', '00000000-0000-4000-b000-000000000009', 'aal2',
  $q$select public.blog_save(null, '{"slug":"perm-test-post","title":"Danger signs","excerpt":"What to watch for in pregnancy, and when to go to the clinic at once.","category":"Maternal Health","author_id":"content","body":[{"type":"p","text":"If you have **heavy bleeding**, go now."}]}'::jsonb)$q$, true);
select pg_temp.expect('viewer cannot write', '00000000-0000-4000-b000-000000000012', 'aal2',
  $q$select public.blog_save(null, '{"slug":"perm-test-v","title":"V"}'::jsonb)$q$, false);
select pg_temp.expect('health worker cannot write the blog', '00000000-0000-4000-b000-000000000004', 'aal1',
  $q$select public.blog_save(null, '{"slug":"perm-test-h","title":"H"}'::jsonb)$q$, false);
select pg_temp.expect('author writes an own draft', '00000000-0000-4000-b000-000000000010', 'aal2',
  $q$select public.blog_save(null, '{"slug":"perm-test-author","title":"Mine","author_id":"content"}'::jsonb)$q$, true);
select pg_temp.expect('author cannot edit a post by someone else', '00000000-0000-4000-b000-000000000010', 'aal2',
  $q$select public.blog_save((select id from blog_posts where slug = 'perm-test-post'), '{"slug":"perm-test-post","title":"Mine now"}'::jsonb)$q$, false);
select pg_temp.expect('author cannot publish', '00000000-0000-4000-b000-000000000010', 'aal2',
  $q$select public.blog_publish((select id from blog_posts where slug = 'perm-test-author'))$q$, false);
select pg_temp.expect('a post mentioning bleeding cannot be published before clinical review', '00000000-0000-4000-b000-000000000009', 'aal2',
  $q$select public.blog_publish((select id from blog_posts where slug = 'perm-test-post'))$q$, false);
select pg_temp.expect('editor cannot approve clinically', '00000000-0000-4000-b000-000000000009', 'aal2',
  $q$select public.blog_review((select id from blog_posts where slug = 'perm-test-post'), 'approved', null, 'Midwife')$q$, false);
select pg_temp.expect('clinical reviewer approves', '00000000-0000-4000-b000-000000000011', 'aal2',
  $q$select public.blog_review((select id from blog_posts where slug = 'perm-test-post'), 'approved', 'ok')$q$, true);
select pg_temp.expect('editor publishes the approved version', '00000000-0000-4000-b000-000000000009', 'aal2',
  $q$select public.blog_publish((select id from blog_posts where slug = 'perm-test-post'))$q$, true);
select pg_temp.expect_n('the website (anon) sees the published post', null, null,
  $q$select count(*) from blog_posts where slug = 'perm-test-post'$q$, 1);
select pg_temp.expect('the website (anon) cannot read drafts or review notes', null, null,
  $q$select draft, review_note from blog_posts limit 1$q$, false);
select pg_temp.expect_n('the website (anon) does not see unpublished posts', null, null,
  $q$select count(*) from blog_posts where slug = 'perm-test-author'$q$, 0);
select pg_temp.expect_n('changing approved text needs a new review', '00000000-0000-4000-b000-000000000009', 'aal2',
  $q$select (public.blog_save((select id from blog_posts where slug = 'perm-test-post'), '{"slug":"perm-test-post","title":"Danger signs","excerpt":"x","category":"Maternal Health","author_id":"content","body":[{"type":"p","text":"Fever and bleeding: go now."}]}'::jsonb) ->> 'health_review' = 'requested')::int$q$, 1);

insert into site_sections (page, section_key, label, draft, defaults) values ('perm-test', 'hero', 'Hero', '{"title":"Old"}', '{"title":"Old"}');
select pg_temp.expect('editor saves a section draft', '00000000-0000-4000-b000-000000000009', 'aal2',
  $q$select public.site_section_save((select id from site_sections where page = 'perm-test'), '{"title":"New"}'::jsonb, true)$q$, true);
select pg_temp.expect_n('drafts are not on the website', null, null,
  $q$select count(*) from jsonb_object_keys(public.site_public() -> 'sections') k where k = 'perm-test/hero'$q$, 0);
select pg_temp.expect('viewer cannot publish a section', '00000000-0000-4000-b000-000000000012', 'aal2',
  $q$select public.site_section_publish((select id from site_sections where page = 'perm-test'))$q$, false);
select pg_temp.expect('editor publishes the section', '00000000-0000-4000-b000-000000000009', 'aal2',
  $q$select public.site_section_publish((select id from site_sections where page = 'perm-test'))$q$, true);
select pg_temp.expect_n('the website sees the published section', null, null,
  $q$select count(*) from (select public.site_public() s) x where x.s -> 'sections' -> 'perm-test/hero' -> 'data' ->> 'title' = 'New'$q$, 1);
select pg_temp.expect('anon cannot read section drafts directly', null, null, $q$select count(*) from site_sections$q$, false);

insert into partners (id, name) values ('00000000-0000-4000-b000-0000000000c1', 'Perm Test Partner');
select pg_temp.expect('an unconfirmed partner cannot be shown', '00000000-0000-4000-b000-000000000009', 'aal2',
  $q$select public.partner_publish('00000000-0000-4000-b000-0000000000c1', true)$q$, false);
select pg_temp.expect('editor cannot confirm a partnership', '00000000-0000-4000-b000-000000000009', 'aal2',
  $q$select public.partner_confirm('00000000-0000-4000-b000-0000000000c1', true)$q$, false);
select pg_temp.expect('admin confirms the partnership', '00000000-0000-4000-b000-000000000002', 'aal2',
  $q$select public.partner_confirm('00000000-0000-4000-b000-0000000000c1', true)$q$, true);
select pg_temp.expect('then the editor shows it', '00000000-0000-4000-b000-000000000009', 'aal2',
  $q$select public.partner_publish('00000000-0000-4000-b000-0000000000c1', true)$q$, true);

select pg_temp.expect('the website contact form can send a message', null, null,
  $q$select public.submit_contact('Perm Test', null, 'perm@example.invalid', 'Other', 'This is a test message from the permission tests.')$q$, true);
select pg_temp.expect('anon cannot read messages', null, null, $q$select count(*) from contact_messages$q$, false);
select pg_temp.expect_n('website viewers cannot read messages (personal data)', '00000000-0000-4000-b000-000000000012', 'aal2',
  $q$select count(*) from contact_messages where email = 'perm@example.invalid'$q$, 0);
select pg_temp.expect_n('editors read messages', '00000000-0000-4000-b000-000000000009', 'aal2',
  $q$select count(*) from contact_messages where email = 'perm@example.invalid'$q$, 1);

-- ───────── 20261107: appointments, Mothers' circle, website MamaBot
select pg_temp.expect_n('health worker opens times at own facility', '00000000-0000-4000-b000-000000000004', 'aal1',
  $q$select public.staff_add_slots('00000000-0000-4000-b000-0000000000f1', 'clinic', now() + interval '2 days', 3, 20)$q$, 3);
select pg_temp.expect('health worker cannot open times at another facility', '00000000-0000-4000-b000-000000000005', 'aal1',
  $q$select public.staff_add_slots('00000000-0000-4000-b000-0000000000f1', 'clinic', now() + interval '3 days', 1, 20)$q$, false);
select set_config('perm.slot', (select id::text from booking_slots where facility_id = '00000000-0000-4000-b000-0000000000f1' and status = 'open' order by starts_at limit 1), true);
select pg_temp.expect('a mother books a time', '00000000-0000-4000-b000-000000000006', 'aal1',
  $q$select public.book_slot(current_setting('perm.slot')::uuid, 'Headache')$q$, true);
select pg_temp.expect_n('staff see the booking', '00000000-0000-4000-b000-000000000004', 'aal1',
  $q$select jsonb_array_length(public.staff_bookings('00000000-0000-4000-b000-0000000000f1', now(), now() + interval '7 days'))$q$, 1);
select pg_temp.expect('staff at another facility cannot list it', '00000000-0000-4000-b000-000000000005', 'aal1',
  $q$select public.staff_bookings('00000000-0000-4000-b000-0000000000f1', now(), now() + interval '7 days')$q$, false);
select pg_temp.expect('super admin with MFA lists any facility', '00000000-0000-4000-b000-000000000001', 'aal2',
  $q$select public.staff_bookings('00000000-0000-4000-b000-0000000000f1', now(), now() + interval '7 days')$q$, true);
select pg_temp.expect('website editor cannot see appointments', '00000000-0000-4000-b000-000000000009', 'aal2',
  $q$select public.staff_bookings('00000000-0000-4000-b000-0000000000f1', now(), now() + interval '7 days')$q$, false);
select set_config('perm.booking', (select id::text from bookings where facility_id = '00000000-0000-4000-b000-0000000000f1' limit 1), true);
select pg_temp.expect('staff mark it done with advice', '00000000-0000-4000-b000-000000000004', 'aal1',
  $q$select public.staff_set_booking_status(current_setting('perm.booking')::uuid, 'done', 'Rest and drink water')$q$, true);
select pg_temp.expect_n('staff list the facility times', '00000000-0000-4000-b000-000000000004', 'aal1',
  $q$select jsonb_array_length(public.staff_slots('00000000-0000-4000-b000-0000000000f1', now(), now() + interval '7 days'))$q$, 3);
select pg_temp.expect_n('booking KPIs for the facility', '00000000-0000-4000-b000-000000000004', 'aal1',
  $q$select (public.booking_kpis('00000000-0000-4000-b000-0000000000f1', current_date, current_date + 7) ->> 'done')::int$q$, 1);

insert into community_posts (id, author_id, body, status, urgent, reasons) values
  ('00000000-0000-4000-b000-0000000000e1', '00000000-0000-4000-b000-000000000006', 'Is it true I should stop iron tablets?', 'review', false, array['new']);
select pg_temp.expect_n('health worker sees the review queue', '00000000-0000-4000-b000-000000000004', 'aal1',
  $q$select jsonb_array_length(public.community_review_queue(50))$q$, 1);
select pg_temp.expect('website editor cannot see the review queue', '00000000-0000-4000-b000-000000000009', 'aal2',
  $q$select public.community_review_queue(50)$q$, false);
select pg_temp.expect('mother cannot moderate', '00000000-0000-4000-b000-000000000006', 'aal1',
  $q$select public.moderate_community_post('00000000-0000-4000-b000-0000000000e1', 'publish')$q$, false);
select pg_temp.expect('health worker publishes with a note', '00000000-0000-4000-b000-000000000004', 'aal1',
  $q$select public.moderate_community_post('00000000-0000-4000-b000-0000000000e1', 'note', 'Keep taking them every day.')$q$, true);
select pg_temp.expect_n('the mother sees it published with the note', '00000000-0000-4000-b000-000000000006', 'aal1',
  $q$select count(*) from jsonb_array_elements(public.community_feed()) p where p ->> 'health_note' = 'Keep taking them every day.'$q$, 1);
select pg_temp.expect_n('helpful toggles on and off', '00000000-0000-4000-b000-000000000007', 'aal1',
  $q$select (public.toggle_community_helpful('00000000-0000-4000-b000-0000000000e1')::int * 10) + public.toggle_community_helpful('00000000-0000-4000-b000-0000000000e1')::int$q$, 10);

select pg_temp.expect('editor writes a MamaBot answer', '00000000-0000-4000-b000-000000000009', 'aal2',
  $q$select public.mamabot_entry_save(null, array['swollen feet'], 'Some swelling is common.', 'Kuvimba kidogo ni kawaida.', 'none', null, null)$q$, true);
select pg_temp.expect('an unreviewed answer cannot be published', '00000000-0000-4000-b000-000000000009', 'aal2',
  $q$select public.mamabot_entry_publish((select id from mamabot_entries where 'swollen feet' = any(patterns)), true)$q$, false);
select pg_temp.expect('clinical reviewer approves the answer', '00000000-0000-4000-b000-000000000011', 'aal2',
  $q$select public.mamabot_entry_review((select id from mamabot_entries where 'swollen feet' = any(patterns)))$q$, true);
select pg_temp.expect('then it can be published', '00000000-0000-4000-b000-000000000009', 'aal2',
  $q$select public.mamabot_entry_publish((select id from mamabot_entries where 'swollen feet' = any(patterns)), true)$q$, true);
select pg_temp.expect_n('the website sees the approved answer', null, null,
  $q$select jsonb_array_length(public.mamabot_public() -> 'entries')$q$, 1);
select pg_temp.expect('an editor changes the approved answer', '00000000-0000-4000-b000-000000000009', 'aal2',
  $q$select public.mamabot_entry_save((select id from mamabot_entries where 'swollen feet' = any(patterns)), array['swollen feet'], 'Changed.', 'Imebadilika.', 'none', null, null)$q$, true);
select pg_temp.expect_n('the changed answer leaves the website until reviewed again', null, null,
  $q$select jsonb_array_length(public.mamabot_public() -> 'entries')$q$, 0);
select pg_temp.expect('editor cannot change safety phrases', '00000000-0000-4000-b000-000000000009', 'aal2',
  $q$select public.safety_phrase_save(null, 'heavy bleeding', 'en', 'red')$q$, false);
select pg_temp.expect('clinical reviewer adds a safety phrase', '00000000-0000-4000-b000-000000000011', 'aal2',
  $q$select public.safety_phrase_save(null, 'heavy bleeding', 'en', 'red')$q$, true);

-- every failing test (none expected), then the total
select n, pass, test, left(detail, 160) detail from t_result where not pass
union all select 0, (select bool_and(pass) from t_result), 'TOTAL ' || (select count(*) from t_result) || ' / failed ' || (select count(*) from t_result where not pass), null
order by n;
rollback;
