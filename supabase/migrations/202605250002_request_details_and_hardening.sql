-- Detail views and published-feed hardening.

drop policy if exists help_requests_select_admin_or_available_or_assigned
on public.help_requests;

drop policy if exists help_requests_select_admin_or_assigned
on public.help_requests;

create policy help_requests_select_admin_or_assigned
on public.help_requests for select
to authenticated
using (
  public.is_mediator()
  or exists (
    select 1
    from public.assignments a
    where a.help_request_id = help_requests.id
      and a.helper_id = public.current_profile_id()
  )
);

drop policy if exists profiles_select_assigned_requester
on public.profiles;

create policy profiles_select_assigned_requester
on public.profiles for select
to authenticated
using (
  role = 'requester'
  and exists (
    select 1
    from public.help_requests h
    join public.assignments a on a.help_request_id = h.id
    where h.requester_id = profiles.id
      and a.helper_id = public.current_profile_id()
  )
);

create or replace function public.list_published_help_requests()
returns table (
  id uuid,
  requester_id uuid,
  source public.request_source,
  status public.help_request_status,
  category public.help_category,
  title text,
  content text,
  items_provided boolean,
  items_needed_details text,
  appointment_time timestamptz,
  appointment_timezone text,
  location_public text,
  credit_reward integer,
  created_at timestamptz,
  published_at timestamptz,
  requester_name text,
  requester_village text,
  requester_address_public text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.current_user_role() <> 'helper' then
    raise exception 'Only helpers can view the published helper feed';
  end if;

  return query
  select
    h.id,
    h.requester_id,
    h.source,
    h.status,
    h.category,
    h.title,
    h.content,
    h.items_provided,
    h.items_needed_details,
    h.appointment_time,
    h.appointment_timezone,
    h.location_public,
    h.credit_reward,
    h.created_at,
    h.published_at,
    p.name,
    p.village,
    p.address_public
  from public.help_requests h
  join public.profiles p on p.id = h.requester_id
  where h.status = 'published'
  order by h.published_at desc nulls last, h.created_at desc;
end;
$$;

grant execute on function public.list_published_help_requests() to authenticated;
