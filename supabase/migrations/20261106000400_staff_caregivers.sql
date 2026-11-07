-- Patient page: the helpers linked to a mother, names and relation only (no phone, nothing else).
-- Staff only, and only for a mother who shares with one of their facilities.
create or replace function public.staff_caregivers(p_mother uuid)
returns table (name text, relation text, since timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff() or not public.can_read_mother(p_mother) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  return query
  select coalesce(p.display_name, ''), l.relation, l.created_at
  from caregiver_links l join profiles p on p.id = l.caregiver_id
  where l.mother_id = p_mother and l.revoked_at is null
  order by l.created_at;
end $$;

revoke all on function public.staff_caregivers(uuid) from public, anon;
grant execute on function public.staff_caregivers(uuid) to authenticated;
