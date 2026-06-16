-- O-1 admin requester directory for read-only registered elder lookup.

create or replace function public.list_admin_requester_profiles()
returns table (
  id uuid,
  name text,
  phone text,
  village text,
  address_public text,
  address_detail text,
  latitude numeric,
  longitude numeric,
  personal_notes text,
  consent_info boolean,
  consent_voice boolean,
  consent_photo boolean,
  consent_doc_url text,
  registered_by uuid,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_mediator() then
    raise exception 'Only mediators/admins can view requester profiles';
  end if;

  return query
  select
    p.id,
    p.name,
    p.phone,
    p.village,
    p.address_public,
    p.address_detail,
    p.latitude,
    p.longitude,
    p.personal_notes,
    p.consent_info,
    p.consent_voice,
    p.consent_photo,
    p.consent_doc_url,
    p.registered_by,
    p.created_at
  from public.profiles p
  where p.role = 'requester'
  order by p.created_at desc, p.name asc;
end;
$$;

revoke all on function public.list_admin_requester_profiles() from public;
grant execute on function public.list_admin_requester_profiles() to authenticated;
