-- P0 behavior: requester registration, admin review/audit, application approval,
-- helper exploration feed, and 2026 credit calculation.

drop index if exists public.assignments_one_active_per_request_idx;

create unique index if not exists assignments_one_open_per_helper_request_idx
on public.assignments(help_request_id, helper_id)
where status in ('applied', 'accepted', 'completed_submitted', 'confirmed', 'disputed');

create index if not exists assignments_review_queue_idx
on public.assignments(status, applied_at desc)
where status = 'applied';

create or replace function public.straight_line_distance_meters(
  p_lat1 numeric,
  p_lon1 numeric,
  p_lat2 numeric,
  p_lon2 numeric
)
returns numeric
language sql
immutable
as $$
  select case
    when p_lat1 is null or p_lon1 is null or p_lat2 is null or p_lon2 is null
      then null
    else round((
      6371000.0 * 2.0 * asin(sqrt(
        power(sin(radians(((p_lat2 - p_lat1)::double precision) / 2.0)), 2)
        + cos(radians(p_lat1::double precision))
        * cos(radians(p_lat2::double precision))
        * power(sin(radians(((p_lon2 - p_lon1)::double precision) / 2.0)), 2)
      ))
    )::numeric, 0)
  end
$$;

create or replace function public.calculate_help_credit(
  p_category public.help_category,
  p_duration_minutes integer,
  p_distance_meters numeric default 0,
  p_review_bonus boolean default false
)
returns integer
language plpgsql
immutable
as $$
declare
  v_base_hourly constant numeric := 15480;
  v_multiplier numeric := 1.0;
  v_duration_minutes integer := greatest(coalesce(p_duration_minutes, 60), 15);
  v_distance numeric := greatest(coalesce(p_distance_meters, 0), 0);
  v_travel_bonus integer := 0;
  v_review_bonus integer := case when coalesce(p_review_bonus, false) then 10 else 0 end;
begin
  v_multiplier := case p_category
    when 'labor' then 1.5
    when 'daily_life' then 1.2
    when 'household' then 1.2
    else 1.0
  end;

  v_travel_bonus := case
    when v_distance >= 3000 then 5000
    when v_distance >= 1000 then 2000
    else 0
  end;

  return round(v_base_hourly * (v_duration_minutes::numeric / 60.0) * v_multiplier)::integer
    + v_travel_bonus
    + v_review_bonus;
end;
$$;

create or replace function public.register_requester_profile(
  p_name text,
  p_phone text,
  p_village text default '다로리',
  p_address_public text default null,
  p_address_detail text default null,
  p_latitude numeric default null,
  p_longitude numeric default null,
  p_personal_notes text default null,
  p_consent_info boolean default false,
  p_consent_voice boolean default false,
  p_consent_photo boolean default false,
  p_consent_doc_url text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid;
  v_profile public.profiles%rowtype;
begin
  if not public.is_mediator() then
    raise exception 'Only mediators/admins can register requesters';
  end if;

  if nullif(btrim(coalesce(p_name, '')), '') is null then
    raise exception 'Requester name is required';
  end if;

  if nullif(btrim(coalesce(p_phone, '')), '') is null then
    raise exception 'Requester phone is required';
  end if;

  if p_consent_info is not true or p_consent_voice is not true or p_consent_photo is not true then
    raise exception 'All required requester consents must be true';
  end if;

  v_actor_id := public.current_profile_id();

  insert into public.profiles (
    auth_user_id,
    role,
    name,
    phone,
    village,
    address_public,
    address_detail,
    latitude,
    longitude,
    personal_notes,
    consent_info,
    consent_voice,
    consent_photo,
    consent_doc_url,
    registered_by
  )
  values (
    null,
    'requester',
    btrim(p_name),
    btrim(p_phone),
    coalesce(nullif(btrim(p_village), ''), '다로리'),
    nullif(btrim(coalesce(p_address_public, '')), ''),
    nullif(btrim(coalesce(p_address_detail, '')), ''),
    p_latitude,
    p_longitude,
    nullif(btrim(coalesce(p_personal_notes, '')), ''),
    p_consent_info,
    p_consent_voice,
    p_consent_photo,
    nullif(btrim(coalesce(p_consent_doc_url, '')), ''),
    v_actor_id
  )
  returning *
  into v_profile;

  insert into public.audit_events (
    actor_profile_id,
    entity_type,
    entity_id,
    action,
    before_data,
    after_data
  )
  values (
    v_actor_id,
    'profile',
    v_profile.id,
    'requester_registered',
    null,
    to_jsonb(v_profile)
  );

  return v_profile.id;
end;
$$;

create or replace function public.admin_update_help_request(
  p_help_request_id uuid,
  p_patch jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid;
  v_patch jsonb := coalesce(p_patch, '{}'::jsonb);
  v_before public.help_requests%rowtype;
  v_after public.help_requests%rowtype;
begin
  if not public.is_mediator() then
    raise exception 'Only mediators/admins can edit help requests';
  end if;

  select *
  into v_before
  from public.help_requests
  where id = p_help_request_id
  for update;

  if not found then
    raise exception 'Help request not found';
  end if;

  if v_before.status not in ('draft', 'pending_review') then
    raise exception 'Only draft or pending_review requests can be edited in O-2';
  end if;

  if v_patch ? 'title' and nullif(btrim(coalesce(v_patch ->> 'title', '')), '') is null then
    raise exception 'Title cannot be empty';
  end if;

  if v_patch ? 'content' and nullif(btrim(coalesce(v_patch ->> 'content', '')), '') is null then
    raise exception 'Content cannot be empty';
  end if;

  v_actor_id := public.current_profile_id();

  update public.help_requests
  set
    category = case when v_patch ? 'category' then (v_patch ->> 'category')::public.help_category else category end,
    title = case when v_patch ? 'title' then btrim(v_patch ->> 'title') else title end,
    content = case when v_patch ? 'content' then btrim(v_patch ->> 'content') else content end,
    items_provided = case
      when v_patch ? 'items_provided' and v_patch ->> 'items_provided' is null then null
      when v_patch ? 'items_provided' and nullif(v_patch ->> 'items_provided', '') is null then null
      when v_patch ? 'items_provided' then (v_patch ->> 'items_provided')::boolean
      else items_provided
    end,
    items_needed_details = case when v_patch ? 'items_needed_details' then nullif(btrim(coalesce(v_patch ->> 'items_needed_details', '')), '') else items_needed_details end,
    appointment_time = case
      when v_patch ? 'appointment_time' and nullif(v_patch ->> 'appointment_time', '') is null then null
      when v_patch ? 'appointment_time' then (v_patch ->> 'appointment_time')::timestamptz
      else appointment_time
    end,
    appointment_timezone = case when v_patch ? 'appointment_timezone' then coalesce(nullif(btrim(v_patch ->> 'appointment_timezone'), ''), 'Asia/Seoul') else appointment_timezone end,
    location_public = case when v_patch ? 'location_public' then nullif(btrim(coalesce(v_patch ->> 'location_public', '')), '') else location_public end,
    location_detail = case when v_patch ? 'location_detail' then nullif(btrim(coalesce(v_patch ->> 'location_detail', '')), '') else location_detail end,
    location_latitude = case
      when v_patch ? 'location_latitude' and nullif(v_patch ->> 'location_latitude', '') is null then null
      when v_patch ? 'location_latitude' then (v_patch ->> 'location_latitude')::numeric
      else location_latitude
    end,
    location_longitude = case
      when v_patch ? 'location_longitude' and nullif(v_patch ->> 'location_longitude', '') is null then null
      when v_patch ? 'location_longitude' then (v_patch ->> 'location_longitude')::numeric
      else location_longitude
    end,
    credit_reward = case when v_patch ? 'credit_reward' then (v_patch ->> 'credit_reward')::integer else credit_reward end,
    required_helpers = case when v_patch ? 'required_helpers' then (v_patch ->> 'required_helpers')::integer else required_helpers end,
    safety_tier = case when v_patch ? 'safety_tier' then (v_patch ->> 'safety_tier')::public.safety_tier else safety_tier end,
    estimated_duration_minutes = case when v_patch ? 'estimated_duration_minutes' then (v_patch ->> 'estimated_duration_minutes')::integer else estimated_duration_minutes end,
    admin_notes = case when v_patch ? 'admin_notes' then nullif(btrim(coalesce(v_patch ->> 'admin_notes', '')), '') else admin_notes end
  where id = p_help_request_id
  returning *
  into v_after;

  insert into public.audit_events (
    actor_profile_id,
    entity_type,
    entity_id,
    action,
    before_data,
    after_data
  )
  values (
    v_actor_id,
    'help_request',
    v_after.id,
    'help_request_updated',
    to_jsonb(v_before),
    to_jsonb(v_after)
  );

  return v_after.id;
end;
$$;

drop function if exists public.review_help_request(uuid, public.help_request_status);

create or replace function public.review_help_request(
  p_help_request_id uuid,
  p_status public.help_request_status,
  p_reject_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid;
  v_before public.help_requests%rowtype;
  v_after public.help_requests%rowtype;
  v_payload jsonb;
begin
  if not public.is_mediator() then
    raise exception 'Only mediators/admins can review help requests';
  end if;

  if p_status not in ('published', 'rejected') then
    raise exception 'Review status must be published or rejected';
  end if;

  select *
  into v_before
  from public.help_requests
  where id = p_help_request_id
  for update;

  if not found then
    raise exception 'Help request not found';
  end if;

  if v_before.status not in ('draft', 'pending_review') then
    raise exception 'Request is not waiting for review';
  end if;

  v_actor_id := public.current_profile_id();

  if p_status = 'published' then
    if nullif(btrim(v_before.title), '') is null
      or nullif(btrim(v_before.content), '') is null
      or v_before.appointment_time is null
      or nullif(btrim(coalesce(v_before.location_public, '')), '') is null
      or v_before.credit_reward <= 0
      or v_before.required_helpers not between 3 and 6
      or v_before.safety_tier in ('tier_1', 'needs_review')
    then
      raise exception 'Request is missing required publish fields or has unresolved safety risk';
    end if;

    update public.help_requests
    set status = 'published',
        approved_by = v_actor_id,
        approved_at = now(),
        published_at = now(),
        reject_reason = null,
        rejected_at = null
    where id = p_help_request_id
    returning *
    into v_after;
  else
    if nullif(btrim(coalesce(p_reject_reason, '')), '') is null then
      raise exception 'Reject reason is required';
    end if;

    update public.help_requests
    set status = 'rejected',
        approved_by = null,
        approved_at = null,
        published_at = null,
        reject_reason = btrim(p_reject_reason),
        rejected_at = now()
    where id = p_help_request_id
    returning *
    into v_after;
  end if;

  insert into public.audit_events (
    actor_profile_id,
    entity_type,
    entity_id,
    action,
    before_data,
    after_data
  )
  values (
    v_actor_id,
    'help_request',
    v_after.id,
    case when p_status = 'published' then 'help_request_published' else 'help_request_rejected' end,
    to_jsonb(v_before),
    to_jsonb(v_after)
  );

  v_payload := jsonb_build_object(
    'title', v_after.title,
    'status', p_status,
    'actor_profile_id', v_actor_id,
    'appointment_time', v_after.appointment_time,
    'credit_reward', v_after.credit_reward,
    'required_helpers', v_after.required_helpers,
    'source', v_after.source,
    'reject_reason', v_after.reject_reason
  );

  insert into public.notifications (
    recipient_profile_id,
    help_request_id,
    channel,
    purpose,
    status,
    payload
  )
  values (
    null,
    v_after.id,
    'in_app',
    case when p_status = 'published' then 'request_published' else 'request_rejected' end,
    'pending',
    v_payload
  );

  if p_status = 'published' then
    insert into public.notifications (
      recipient_profile_id,
      help_request_id,
      channel,
      purpose,
      status,
      payload
    )
    select
      p.id,
      v_after.id,
      'in_app',
      'request_published',
      'pending',
      v_payload || jsonb_build_object('recipient_role', 'helper')
    from public.profiles p
    where p.role = 'helper';
  end if;

  return v_after.id;
end;
$$;

create or replace function public.apply_help_request(p_help_request_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_helper_id uuid;
  v_assignment_id uuid;
  v_existing_assignment_id uuid;
  v_request public.help_requests%rowtype;
  v_helper public.profiles%rowtype;
  v_accepted_count integer;
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

  select count(*)
  into v_accepted_count
  from public.assignments
  where help_request_id = p_help_request_id
    and status in ('accepted', 'completed_submitted', 'confirmed', 'disputed');

  if v_accepted_count >= v_request.required_helpers then
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

create or replace function public.approve_assignment(p_assignment_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid;
  v_before public.assignments%rowtype;
  v_after public.assignments%rowtype;
  v_request public.help_requests%rowtype;
  v_helper public.profiles%rowtype;
  v_accepted_count integer;
  v_payload jsonb;
begin
  if not public.is_mediator() then
    raise exception 'Only mediators/admins can approve helper applications';
  end if;

  v_actor_id := public.current_profile_id();

  select *
  into v_before
  from public.assignments
  where id = p_assignment_id
  for update;

  if not found or v_before.status <> 'applied' then
    raise exception 'Assignment is not waiting for approval';
  end if;

  select *
  into v_request
  from public.help_requests
  where id = v_before.help_request_id
  for update;

  select *
  into v_helper
  from public.profiles
  where id = v_before.helper_id;

  select count(*)
  into v_accepted_count
  from public.assignments
  where help_request_id = v_before.help_request_id
    and status in ('accepted', 'completed_submitted', 'confirmed', 'disputed');

  if v_accepted_count >= v_request.required_helpers then
    raise exception 'Request already has the required number of helpers';
  end if;

  update public.assignments
  set status = 'accepted',
      accepted_at = now()
  where id = p_assignment_id
  returning *
  into v_after;

  if v_accepted_count + 1 >= v_request.required_helpers then
    update public.help_requests
    set status = 'accepted'
    where id = v_request.id
      and status = 'published';
  end if;

  v_payload := jsonb_build_object(
    'title', v_request.title,
    'status', 'accepted',
    'helper_profile_id', v_helper.id,
    'helper_name', v_helper.name,
    'appointment_time', v_request.appointment_time,
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
    v_actor_id,
    'assignment',
    p_assignment_id,
    'assignment_approved',
    to_jsonb(v_before),
    to_jsonb(v_after)
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
      p_assignment_id,
      'in_app',
      'assignment_approved',
      'pending',
      v_payload
    ),
    (
      v_helper.id,
      v_request.id,
      p_assignment_id,
      'in_app',
      'assignment_approved',
      'pending',
      v_payload
    );

  return p_assignment_id;
end;
$$;

create or replace function public.reject_assignment(
  p_assignment_id uuid,
  p_reason text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid;
  v_before public.assignments%rowtype;
  v_after public.assignments%rowtype;
  v_request public.help_requests%rowtype;
  v_payload jsonb;
begin
  if not public.is_mediator() then
    raise exception 'Only mediators/admins can reject helper applications';
  end if;

  v_actor_id := public.current_profile_id();

  select *
  into v_before
  from public.assignments
  where id = p_assignment_id
  for update;

  if not found or v_before.status <> 'applied' then
    raise exception 'Assignment is not waiting for approval';
  end if;

  select *
  into v_request
  from public.help_requests
  where id = v_before.help_request_id;

  update public.assignments
  set status = 'rejected',
      cancelled_at = now()
  where id = p_assignment_id
  returning *
  into v_after;

  v_payload := jsonb_build_object(
    'title', v_request.title,
    'status', 'rejected',
    'reason', nullif(btrim(coalesce(p_reason, '')), '')
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
    v_actor_id,
    'assignment',
    p_assignment_id,
    'assignment_rejected',
    to_jsonb(v_before),
    to_jsonb(v_after)
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
  values (
    v_before.helper_id,
    v_request.id,
    p_assignment_id,
    'in_app',
    'assignment_rejected',
    'pending',
    v_payload
  );

  return p_assignment_id;
end;
$$;

drop function if exists public.list_published_help_requests();

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
      coalesce(h.location_latitude, p.latitude) as location_latitude,
      coalesce(h.location_longitude, p.longitude) as location_longitude,
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
      coalesce(h.published_at, h.created_at) >= now() - interval '24 hours' as is_new,
      coalesce(applications.applied_count, 0)::integer as applied_count,
      coalesce(applications.accepted_count, 0)::integer as accepted_count,
      mine.id as current_helper_assignment_id,
      mine.status as current_helper_assignment_status,
      coalesce(applications.accepted_count, 0) >= h.required_helpers as is_full
    from public.help_requests h
    join public.profiles p on p.id = h.requester_id
    left join lateral (
      select
        count(*) filter (
          where a.status in ('applied', 'accepted', 'completed_submitted', 'confirmed', 'disputed')
        ) as applied_count,
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
    where h.status = 'published'
      and (p_category is null or h.category = p_category)
      and (coalesce(p_new_only, false) is false or coalesce(h.published_at, h.created_at) >= now() - interval '24 hours')
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

create or replace function public.confirm_assignment_and_credit(
  p_assignment_id uuid,
  p_rating integer default null,
  p_review_text text default null,
  p_source public.review_source default 'admin_manual'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid;
  v_helper_id uuid;
  v_requester_id uuid;
  v_help_request_id uuid;
  v_credit_reward integer;
  v_credit_id uuid;
  v_review_bonus_id uuid;
  v_completion_note text;
begin
  if not public.is_mediator() then
    raise exception 'Only mediators/admins can confirm and credit assignments';
  end if;

  v_actor_id := public.current_profile_id();

  select
    a.helper_id,
    h.requester_id,
    h.id,
    public.calculate_help_credit(
      h.category,
      h.estimated_duration_minutes,
      public.straight_line_distance_meters(
        hp.latitude,
        hp.longitude,
        coalesce(h.location_latitude, rp.latitude),
        coalesce(h.location_longitude, rp.longitude)
      ),
      false
    ),
    cp.note
  into
    v_helper_id,
    v_requester_id,
    v_help_request_id,
    v_credit_reward,
    v_completion_note
  from public.assignments a
  join public.help_requests h on h.id = a.help_request_id
  join public.profiles hp on hp.id = a.helper_id
  join public.profiles rp on rp.id = h.requester_id
  left join lateral (
    select note
    from public.completion_proofs cp
    where cp.assignment_id = a.id
    order by cp.submitted_at desc
    limit 1
  ) cp on true
  where a.id = p_assignment_id
    and a.status = 'completed_submitted';

  if not found then
    raise exception 'Assignment is not ready for confirmation';
  end if;

  update public.assignments
  set status = 'confirmed'
  where id = p_assignment_id;

  update public.completion_proofs
  set status = 'approved',
      reviewed_by = v_actor_id,
      reviewed_at = now()
  where assignment_id = p_assignment_id
    and status = 'submitted';

  update public.help_requests
  set status = 'credited'
  where id = v_help_request_id;

  if p_rating is not null or p_review_text is not null then
    insert into public.reviews (
      assignment_id,
      requester_id,
      helper_id,
      rating,
      review_text,
      source
    )
    values (
      p_assignment_id,
      v_requester_id,
      v_helper_id,
      p_rating,
      p_review_text,
      p_source
    )
    on conflict (assignment_id) do update
    set rating = excluded.rating,
        review_text = excluded.review_text,
        source = excluded.source;
  end if;

  insert into public.credit_ledger (
    profile_id,
    assignment_id,
    amount,
    reason,
    created_by
  )
  values (
    v_helper_id,
    p_assignment_id,
    greatest(v_credit_reward, 1),
    'task_completion',
    v_actor_id
  )
  on conflict do nothing;

  select id
  into v_credit_id
  from public.credit_ledger
  where assignment_id = p_assignment_id
    and profile_id = v_helper_id
    and reason = 'task_completion'
  limit 1;

  if nullif(btrim(coalesce(v_completion_note, '')), '') is not null then
    insert into public.credit_ledger (
      profile_id,
      assignment_id,
      amount,
      reason,
      created_by
    )
    values (
      v_helper_id,
      p_assignment_id,
      10,
      'review_bonus',
      v_actor_id
    )
    on conflict do nothing;

    select id
    into v_review_bonus_id
    from public.credit_ledger
    where assignment_id = p_assignment_id
      and profile_id = v_helper_id
      and reason = 'review_bonus'
    limit 1;
  end if;

  insert into public.audit_events (
    actor_profile_id,
    entity_type,
    entity_id,
    action,
    before_data,
    after_data
  )
  values (
    v_actor_id,
    'assignment',
    p_assignment_id,
    'assignment_confirmed_and_credited',
    null,
    jsonb_build_object(
      'task_credit_id', v_credit_id,
      'review_bonus_id', v_review_bonus_id,
      'task_credit_amount', greatest(v_credit_reward, 1),
      'review_bonus_amount', case when v_review_bonus_id is not null then 10 else 0 end
    )
  );

  return v_credit_id;
end;
$$;

grant execute on function public.straight_line_distance_meters(numeric, numeric, numeric, numeric) to authenticated;
grant execute on function public.calculate_help_credit(public.help_category, integer, numeric, boolean) to authenticated;
grant execute on function public.register_requester_profile(text, text, text, text, text, numeric, numeric, text, boolean, boolean, boolean, text) to authenticated;
grant execute on function public.admin_update_help_request(uuid, jsonb) to authenticated;
grant execute on function public.review_help_request(uuid, public.help_request_status, text) to authenticated;
grant execute on function public.apply_help_request(uuid) to authenticated;
grant execute on function public.accept_help_request(uuid) to authenticated;
grant execute on function public.approve_assignment(uuid) to authenticated;
grant execute on function public.reject_assignment(uuid, text) to authenticated;
grant execute on function public.list_published_help_requests(text, public.help_category, boolean, integer, integer, numeric, numeric, text) to authenticated;
grant execute on function public.confirm_assignment_and_credit(uuid, integer, text, public.review_source) to authenticated;
