-- The dashboard's appointment calendar needs the facility's times (open, booked, closed).
-- booking_slots stays closed to direct reads (20261106010000); staff read through this function.
create or replace function public.staff_slots(p_facility uuid, p_from timestamptz, p_to timestamptz)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not (public.staff_of(p_facility) or public.is_platform_admin()) then
    raise exception 'not staff at this facility' using errcode = '42501';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('id', s.id, 'facility_id', s.facility_id, 'staff_id', s.staff_id, 'starts_at', s.starts_at,
      'minutes', s.minutes, 'mode', s.mode, 'status', s.status) order by s.starts_at)
    from booking_slots s where s.facility_id = p_facility and s.starts_at >= p_from and s.starts_at < p_to), '[]'::jsonb);
end $$;
revoke all on function public.staff_slots(uuid, timestamptz, timestamptz) from public, anon;
grant execute on function public.staff_slots(uuid, timestamptz, timestamptz) to authenticated;

-- security advisor: fixed search_path for the KPI helper from 20261106010000
alter function public._small(bigint) set search_path = public;
