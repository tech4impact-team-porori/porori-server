-- H-3 request detail API and application decision surface.
-- appointment_time is the confirmed activity time after O-2 review.

comment on column public.help_requests.appointment_time is
  'Confirmed activity/visit time used by H-3/H-5 and O-3 deadlines after operator review.';

comment on column public.help_requests.appointment_timezone is
  'Timezone for the confirmed activity/visit time; defaults to Asia/Seoul.';

create or replace function public.apply_help_request(p_help_request_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_helper_id uuid;
  v_helper public.profiles%rowtype;
  v_request public.help_requests%rowtype;
  v_assignment_id uuid;
  v_existing_assignment_id uuid;
  v_accepted_count integer;
  v_active_count integer;
  v_application_deadline timestamptz;
  v_payload jsonb;
begin
  v_helper_id := public.current_profile_id();

  if v_helper_id is null or public.current_user_role() <> 'helper' then
    raise exception 'Only helpers can apply to help requests';
  end if;

  select *
  into v_helper
  from public.profiles
  where id = v_helper_id;

  select *
  into v_request
  from public.help_requests
  where id = p_help_request_id
  for update;

  if not found or v_request.status <> 'published' then
    raise exception 'Request is not open for applications';
  end if;

  v_application_deadline := public.help_request_application_deadline(v_request.appointment_time);

  if v_application_deadline is not null and now() >= v_application_deadline then
    raise exception 'Application period has ended';
  end if;

  select id
  into v_existing_assignment_id
  from public.assignments
  where help_request_id = p_help_request_id
    and helper_id = v_helper_id
    and status in ('applied', 'accepted', 'completed_submitted', 'confirmed', 'disputed')
  order by created_at desc
  limit 1;

  if v_existing_assignment_id is not null then
    return v_existing_assignment_id;
  end if;

  select
    count(*) filter (where status in ('accepted', 'completed_submitted', 'confirmed', 'disputed'))::integer,
    count(*) filter (where status in ('applied', 'accepted', 'completed_submitted', 'confirmed', 'disputed'))::integer
  into v_accepted_count, v_active_count
  from public.assignments
  where help_request_id = p_help_request_id;

  if coalesce(v_accepted_count, 0) >= v_request.required_helpers
    or coalesce(v_active_count, 0) >= 6 then
    raise exception 'Request is already full';
  end if;

  insert into public.assignments (
    help_request_id,
    helper_id,
    status,
    applied_at,
    accepted_at
  )
  values (
    p_help_request_id,
    v_helper_id,
    'applied',
    now(),
    null
  )
  returning id into v_assignment_id;

  v_payload := jsonb_build_object(
    'title', v_request.title,
    'status', 'applied',
    'helper_profile_id', v_helper_id,
    'helper_name', v_helper.name,
    'appointment_time', v_request.appointment_time,
    'application_deadline', v_application_deadline,
    'credit_reward', v_request.credit_reward
  );

  insert into public.audit_events (
    actor_profile_id,
    entity_type,
    entity_id,
    action,
    before_data,
    after_data
  )
  values (
    v_helper_id,
    'assignment',
    v_assignment_id,
    'assignment_applied',
    null,
    v_payload
  );

  insert into public.notifications (
    recipient_profile_id,
    help_request_id,
    assignment_id,
    channel,
    purpose,
    status,
    payload
  )
  values
    (
      null,
      v_request.id,
      v_assignment_id,
      'in_app',
      'assignment_applied',
      'pending',
      v_payload
    ),
    (
      v_helper_id,
      v_request.id,
      v_assignment_id,
      'in_app',
      'assignment_applied',
      'pending',
      v_payload
    );

  return v_assignment_id;
end;
$$;

create or replace function public.accept_help_request(p_help_request_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.apply_help_request(p_help_request_id);
end;
$$;

grant execute on function public.apply_help_request(uuid) to authenticated;
grant execute on function public.accept_help_request(uuid) to authenticated;

drop function if exists public.list_published_help_requests(
  text,
  public.help_category,
  boolean,
  integer,
  integer,
  numeric,
  numeric,
  text
);

create or replace function public.list_published_help_requests(
  p_sort text default 'latest',
  p_category public.help_category default null,
  p_new_only boolean default false,
  p_limit integer default 20,
  p_offset integer default 0,
  p_latitude numeric default null,
  p_longitude numeric default null,
  p_search text default null
)
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
  required_helpers integer,
  safety_tier public.safety_tier,
  location_latitude numeric,
  location_longitude numeric,
  estimated_duration_minutes integer,
  created_at timestamptz,
  published_at timestamptz,
  requester_name text,
  requester_village text,
  requester_address_public text,
  distance_meters numeric,
  is_new boolean,
  applied_count integer,
  accepted_count integer,
  current_helper_assignment_id uuid,
  current_helper_assignment_status public.assignment_status,
  application_deadline timestamptz,
  applications_locked boolean,
  is_full boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_helper_id uuid;
  v_latitude numeric;
  v_longitude numeric;
begin
  v_helper_id := public.current_profile_id();

  if v_helper_id is null or public.current_user_role() <> 'helper' then
    raise exception 'Only helpers can view the published helper feed';
  end if;

  select
    coalesce(p_latitude, p.latitude),
    coalesce(p_longitude, p.longitude)
  into v_latitude, v_longitude
  from public.profiles p
  where p.id = v_helper_id;

  return query
  with request_rows as (
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
      public.calculate_help_credit(
        h.category,
        h.estimated_duration_minutes,
        public.straight_line_distance_meters(
          v_latitude,
          v_longitude,
          coalesce(h.location_latitude, p.latitude),
          coalesce(h.location_longitude, p.longitude)
        ),
        false
      ) as credit_reward,
      h.required_helpers,
      h.safety_tier,
      null::numeric as location_latitude,
      null::numeric as location_longitude,
      h.estimated_duration_minutes,
      h.created_at,
      h.published_at,
      p.name as requester_name,
      p.village as requester_village,
      p.address_public as requester_address_public,
      public.straight_line_distance_meters(
        v_latitude,
        v_longitude,
        coalesce(h.location_latitude, p.latitude),
        coalesce(h.location_longitude, p.longitude)
      ) as distance_meters,
      coalesce(h.published_at, h.created_at) >= now() - interval '48 hours' as is_new,
      coalesce(applications.active_count, 0)::integer as applied_count,
      coalesce(applications.accepted_count, 0)::integer as accepted_count,
      mine.id as current_helper_assignment_id,
      mine.status as current_helper_assignment_status,
      public.help_request_application_deadline(h.appointment_time) as application_deadline,
      h.status <> 'published'
        or (
          public.help_request_application_deadline(h.appointment_time) is not null
          and now() >= public.help_request_application_deadline(h.appointment_time)
        ) as applications_locked,
      h.status <> 'published'
        or coalesce(applications.accepted_count, 0) >= h.required_helpers
        or coalesce(applications.active_count, 0) >= 6 as is_full
    from public.help_requests h
    join public.profiles p on p.id = h.requester_id
    left join lateral (
      select
        count(*) filter (
          where a.status in ('applied', 'accepted', 'completed_submitted', 'confirmed', 'disputed')
        ) as active_count,
        count(*) filter (
          where a.status in ('accepted', 'completed_submitted', 'confirmed', 'disputed')
        ) as accepted_count
      from public.assignments a
      where a.help_request_id = h.id
    ) applications on true
    left join lateral (
      select a.id, a.status
      from public.assignments a
      where a.help_request_id = h.id
        and a.helper_id = v_helper_id
        and a.status in ('applied', 'accepted', 'completed_submitted', 'confirmed', 'disputed')
      order by a.created_at desc
      limit 1
    ) mine on true
    where h.status in ('published', 'accepted')
      and (p_category is null or h.category = p_category)
      and (coalesce(p_new_only, false) is false or coalesce(h.published_at, h.created_at) >= now() - interval '48 hours')
      and (
        nullif(btrim(coalesce(p_search, '')), '') is null
        or h.title ilike '%' || btrim(p_search) || '%'
        or h.content ilike '%' || btrim(p_search) || '%'
      )
  )
  select *
  from request_rows r
  order by
    case when coalesce(p_sort, 'latest') = 'distance' then r.distance_meters end asc nulls last,
    case when coalesce(p_sort, 'latest') <> 'distance' then r.published_at end desc nulls last,
    r.created_at desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

grant execute on function public.list_published_help_requests(text, public.help_category, boolean, integer, integer, numeric, numeric, text)
to authenticated;

drop function if exists public.get_help_request_detail(uuid, numeric, numeric);

create or replace function public.get_help_request_detail(
  p_help_request_id uuid,
  p_latitude numeric default null,
  p_longitude numeric default null
)
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
  location_detail text,
  credit_reward integer,
  required_helpers integer,
  safety_tier public.safety_tier,
  location_latitude numeric,
  location_longitude numeric,
  estimated_duration_minutes integer,
  created_at timestamptz,
  published_at timestamptz,
  requester_name text,
  requester_phone text,
  requester_village text,
  requester_address_public text,
  requester_address_detail text,
  requester_personal_notes text,
  distance_meters numeric,
  is_new boolean,
  applied_count integer,
  accepted_count integer,
  current_helper_assignment_id uuid,
  current_helper_assignment_status public.assignment_status,
  application_deadline timestamptz,
  applications_locked boolean,
  is_full boolean,
  can_apply boolean,
  apply_block_reason text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id uuid;
  v_role public.user_role;
  v_latitude numeric;
  v_longitude numeric;
begin
  v_profile_id := public.current_profile_id();
  v_role := public.current_user_role();

  if v_profile_id is null or v_role not in ('helper', 'mediator', 'admin') then
    raise exception 'Only helpers or admins can view help request details';
  end if;

  select
    coalesce(p_latitude, p.latitude),
    coalesce(p_longitude, p.longitude)
  into v_latitude, v_longitude
  from public.profiles p
  where p.id = v_profile_id;

  return query
  with detail as (
    select
      h.*,
      rp.name as requester_name,
      rp.phone as requester_phone,
      rp.village as requester_village,
      rp.address_public as requester_address_public,
      rp.address_detail as requester_address_detail,
      rp.personal_notes as requester_personal_notes,
      public.straight_line_distance_meters(
        v_latitude,
        v_longitude,
        coalesce(h.location_latitude, rp.latitude),
        coalesce(h.location_longitude, rp.longitude)
      ) as distance_meters,
      coalesce(counts.active_count, 0)::integer as active_count,
      coalesce(counts.accepted_count, 0)::integer as accepted_count,
      mine.id as current_helper_assignment_id,
      mine.status as current_helper_assignment_status,
      public.help_request_application_deadline(h.appointment_time) as application_deadline
    from public.help_requests h
    join public.profiles rp on rp.id = h.requester_id
    left join lateral (
      select
        count(*) filter (
          where a.status in ('applied', 'accepted', 'completed_submitted', 'confirmed', 'disputed')
        ) as active_count,
        count(*) filter (
          where a.status in ('accepted', 'completed_submitted', 'confirmed', 'disputed')
        ) as accepted_count
      from public.assignments a
      where a.help_request_id = h.id
    ) counts on true
    left join lateral (
      select a.id, a.status
      from public.assignments a
      where a.help_request_id = h.id
        and a.helper_id = v_profile_id
        and a.status in ('applied', 'accepted', 'completed_submitted', 'confirmed', 'disputed')
      order by a.created_at desc
      limit 1
    ) mine on true
    where h.id = p_help_request_id
      and (
        v_role in ('mediator', 'admin')
        or h.status in ('published', 'accepted')
      )
  ),
  decisions as (
    select
      d.*,
      v_role in ('mediator', 'admin')
        or d.current_helper_assignment_status in ('accepted', 'completed_submitted', 'confirmed', 'disputed')
        as can_view_private,
      d.status <> 'published'
        or (
          d.application_deadline is not null
          and now() >= d.application_deadline
        ) as applications_locked,
      d.status <> 'published'
        or d.accepted_count >= d.required_helpers
        or d.active_count >= 6 as is_full
    from detail d
  )
  select
    d.id,
    d.requester_id,
    d.source,
    d.status,
    d.category,
    d.title,
    d.content,
    d.items_provided,
    d.items_needed_details,
    d.appointment_time,
    d.appointment_timezone,
    d.location_public,
    case when d.can_view_private then d.location_detail else null end,
    public.calculate_help_credit(
      d.category,
      d.estimated_duration_minutes,
      d.distance_meters,
      false
    ) as credit_reward,
    d.required_helpers,
    d.safety_tier,
    case when d.can_view_private then d.location_latitude else null end,
    case when d.can_view_private then d.location_longitude else null end,
    d.estimated_duration_minutes,
    d.created_at,
    d.published_at,
    d.requester_name,
    case when d.can_view_private then d.requester_phone else null end,
    d.requester_village,
    d.requester_address_public,
    case when d.can_view_private then d.requester_address_detail else null end,
    case when d.can_view_private then d.requester_personal_notes else null end,
    d.distance_meters,
    coalesce(d.published_at, d.created_at) >= now() - interval '48 hours',
    d.active_count,
    d.accepted_count,
    d.current_helper_assignment_id,
    d.current_helper_assignment_status,
    d.application_deadline,
    d.applications_locked,
    d.is_full,
    case
      when v_role <> 'helper' then false
      when d.current_helper_assignment_status is not null then false
      when d.is_full then false
      when d.applications_locked then false
      else true
    end as can_apply,
    case
      when v_role <> 'helper' then 'not_helper'
      when d.current_helper_assignment_status is not null then 'already_applied'
      when d.is_full then 'full'
      when d.applications_locked then 'deadline_passed'
      else null
    end as apply_block_reason
  from decisions d;
end;
$$;

grant execute on function public.get_help_request_detail(uuid, numeric, numeric)
to authenticated;
