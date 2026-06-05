-- P0 decision alignment and backend gaps from the 2026-06-04 requirements pass.
-- Decisions: 15,000 base credit, 48h NEW, pending cancellation, approve-all,
-- mandatory completion photo + text before admin credit approval,
-- day-before application cutoff, and admin underfilled-match decisions.

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
  v_base_hourly constant numeric := 15000;
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

create or replace function public.help_request_application_deadline(
  p_appointment_time timestamptz
)
returns timestamptz
language sql
stable
as $$
  select case
    when p_appointment_time is null then null
    else ((p_appointment_time at time zone 'Asia/Seoul')::date::timestamp at time zone 'Asia/Seoul')
  end;
$$;

grant execute on function public.help_request_application_deadline(timestamptz)
to authenticated;

create or replace function public.help_request_cancellation_deadline(
  p_appointment_time timestamptz
)
returns timestamptz
language sql
stable
as $$
  select case
    when p_appointment_time is null then null
    else p_appointment_time - interval '24 hours'
  end;
$$;

grant execute on function public.help_request_cancellation_deadline(timestamptz)
to authenticated;

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
      coalesce(applications.applied_count, 0)::integer as applied_count,
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
        or coalesce(applications.accepted_count, 0) >= h.required_helpers as is_full
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

drop policy if exists help_requests_select_admin_or_assigned
on public.help_requests;

drop policy if exists help_requests_select_admin_or_accepted_helper
on public.help_requests;

create policy help_requests_select_admin_or_accepted_helper
on public.help_requests for select
to authenticated
using (
  public.is_mediator()
  or requester_id = public.current_profile_id()
  or exists (
    select 1
    from public.assignments a
    where a.help_request_id = help_requests.id
      and a.helper_id = public.current_profile_id()
      and a.status in ('accepted', 'completed_submitted', 'confirmed', 'disputed')
  )
);

drop policy if exists profiles_select_assigned_requester
on public.profiles;

drop policy if exists profiles_select_accepted_requester
on public.profiles;

create policy profiles_select_accepted_requester
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
      and a.status in ('accepted', 'completed_submitted', 'confirmed', 'disputed')
  )
);

drop function if exists public.list_my_helper_assignments();

create or replace function public.list_my_helper_assignments()
returns table (
  assignment jsonb,
  help_request jsonb,
  requester jsonb,
  companion_helpers jsonb,
  completion_proofs jsonb,
  credit_ledger jsonb
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_helper_id uuid;
begin
  v_helper_id := public.current_profile_id();

  if v_helper_id is null or public.current_user_role() <> 'helper' then
    raise exception 'Only helpers can view their assignments';
  end if;

  return query
  select
    to_jsonb(a) as assignment,
    jsonb_build_object(
      'id', h.id,
      'requester_id', h.requester_id,
      'source', h.source,
      'status', h.status,
      'category', h.category,
      'title', h.title,
      'content', h.content,
      'items_provided', h.items_provided,
      'items_needed_details', h.items_needed_details,
      'appointment_time', h.appointment_time,
      'appointment_timezone', h.appointment_timezone,
      'location_public', h.location_public,
      'location_detail', case
        when a.status in ('accepted', 'completed_submitted', 'confirmed', 'disputed')
          then h.location_detail
        else null
      end,
      'location_latitude', case
        when a.status in ('accepted', 'completed_submitted', 'confirmed', 'disputed')
          then h.location_latitude
        else null
      end,
      'location_longitude', case
        when a.status in ('accepted', 'completed_submitted', 'confirmed', 'disputed')
          then h.location_longitude
        else null
      end,
      'credit_reward', h.credit_reward,
      'required_helpers', h.required_helpers,
      'safety_tier', h.safety_tier,
      'estimated_duration_minutes', h.estimated_duration_minutes,
      'created_at', h.created_at,
      'updated_at', h.updated_at,
      'published_at', h.published_at,
      'admin_notes', null,
      'ai_extracted_payload', null,
      'approved_by', h.approved_by,
      'approved_at', h.approved_at,
      'reject_reason', null,
      'rejected_at', h.rejected_at
    ) as help_request,
    jsonb_build_object(
      'id', rp.id,
      'name', rp.name,
      'phone', case
        when a.status in ('accepted', 'completed_submitted', 'confirmed', 'disputed')
          then rp.phone
        else null
      end,
      'village', rp.village,
      'address_public', rp.address_public,
      'address_detail', case
        when a.status in ('accepted', 'completed_submitted', 'confirmed', 'disputed')
          then rp.address_detail
        else null
      end,
      'personal_notes', case
        when a.status in ('accepted', 'completed_submitted', 'confirmed', 'disputed')
          then rp.personal_notes
        else null
      end
    ) as requester,
    case
      when a.status in ('accepted', 'completed_submitted', 'confirmed', 'disputed') then
        coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', hp.id,
              'name', hp.name,
              'phone', hp.phone,
              'status', companion.status
            )
            order by companion.accepted_at nulls last, companion.applied_at nulls last
          )
          from public.assignments companion
          join public.profiles hp on hp.id = companion.helper_id
          where companion.help_request_id = a.help_request_id
            and companion.status in ('accepted', 'completed_submitted', 'confirmed', 'disputed')
        ), '[]'::jsonb)
      else '[]'::jsonb
    end as companion_helpers,
    coalesce((
      select jsonb_agg(to_jsonb(cp) order by cp.submitted_at desc)
      from public.completion_proofs cp
      where cp.assignment_id = a.id
    ), '[]'::jsonb) as completion_proofs,
    coalesce((
      select jsonb_agg(to_jsonb(cl) order by cl.created_at desc)
      from public.credit_ledger cl
      where cl.assignment_id = a.id
        and cl.profile_id = v_helper_id
    ), '[]'::jsonb) as credit_ledger
  from public.assignments a
  join public.help_requests h on h.id = a.help_request_id
  join public.profiles rp on rp.id = h.requester_id
  where a.helper_id = v_helper_id
  order by coalesce(a.accepted_at, a.applied_at, a.created_at) desc;
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
  v_next_category public.help_category;
  v_next_duration integer;
begin
  if public.current_user_role() not in ('mediator', 'admin') then
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
  v_next_category := case
    when v_patch ? 'category' then (v_patch ->> 'category')::public.help_category
    else v_before.category
  end;
  v_next_duration := case
    when v_patch ? 'estimated_duration_minutes' then (v_patch ->> 'estimated_duration_minutes')::integer
    else v_before.estimated_duration_minutes
  end;

  update public.help_requests
  set
    category = v_next_category,
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
    credit_reward = public.calculate_help_credit(v_next_category, v_next_duration, 0, false),
    required_helpers = case when v_patch ? 'required_helpers' then (v_patch ->> 'required_helpers')::integer else required_helpers end,
    safety_tier = case when v_patch ? 'safety_tier' then (v_patch ->> 'safety_tier')::public.safety_tier else safety_tier end,
    estimated_duration_minutes = v_next_duration,
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

create or replace function public.cancel_help_application(p_assignment_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_helper_id uuid;
  v_before public.assignments%rowtype;
  v_after public.assignments%rowtype;
  v_request public.help_requests%rowtype;
  v_accepted_count integer;
  v_cancellation_deadline timestamptz;
begin
  v_helper_id := public.current_profile_id();

  if v_helper_id is null or public.current_user_role() <> 'helper' then
    raise exception 'Only helpers can cancel their applications';
  end if;

  select *
  into v_before
  from public.assignments
  where id = p_assignment_id
    and helper_id = v_helper_id
  for update;

  if not found or v_before.status <> 'applied' then
    raise exception 'Only pending applications can be cancelled';
  end if;

  select *
  into v_request
  from public.help_requests
  where id = v_before.help_request_id
  for update;

  select count(*)
  into v_accepted_count
  from public.assignments
  where help_request_id = v_before.help_request_id
    and status in ('accepted', 'completed_submitted', 'confirmed', 'disputed');

  if v_request.status <> 'published' or v_accepted_count >= v_request.required_helpers then
    raise exception 'Application can no longer be cancelled';
  end if;

  v_cancellation_deadline := public.help_request_cancellation_deadline(v_request.appointment_time);

  if v_cancellation_deadline is not null and now() >= v_cancellation_deadline then
    raise exception 'Cancellation period has ended';
  end if;

  update public.assignments
  set status = 'cancelled',
      cancelled_at = now()
  where id = p_assignment_id
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
    v_helper_id,
    'assignment',
    p_assignment_id,
    'assignment_cancelled_by_helper',
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
    null,
    v_request.id,
    p_assignment_id,
    'in_app',
    'assignment_cancelled',
    'pending',
    jsonb_build_object(
      'title', v_request.title,
      'status', 'cancelled',
      'helper_profile_id', v_helper_id
    )
  );

  return p_assignment_id;
end;
$$;

create or replace function public.approve_all_assignments_for_request(p_help_request_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid;
  v_request public.help_requests%rowtype;
  v_assignment public.assignments%rowtype;
  v_after public.assignments%rowtype;
  v_accepted_count integer;
  v_approved_count integer := 0;
begin
  if not public.is_mediator() then
    raise exception 'Only mediators/admins can approve helper applications';
  end if;

  v_actor_id := public.current_profile_id();

  select *
  into v_request
  from public.help_requests
  where id = p_help_request_id
  for update;

  if not found or v_request.status <> 'published' then
    raise exception 'Request is not open for assignment approval';
  end if;

  select count(*)
  into v_accepted_count
  from public.assignments
  where help_request_id = p_help_request_id
    and status in ('accepted', 'completed_submitted', 'confirmed', 'disputed');

  if v_accepted_count >= v_request.required_helpers then
    raise exception 'Request already has the required number of helpers';
  end if;

  for v_assignment in
    select *
    from public.assignments
    where help_request_id = p_help_request_id
      and status = 'applied'
    order by applied_at asc, created_at asc
    limit greatest(v_request.required_helpers - v_accepted_count, 0)
    for update
  loop
    update public.assignments
    set status = 'accepted',
        accepted_at = now()
    where id = v_assignment.id
    returning *
    into v_after;

    v_approved_count := v_approved_count + 1;
    v_accepted_count := v_accepted_count + 1;

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
      v_assignment.id,
      'assignment_approved',
      to_jsonb(v_assignment),
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
        v_assignment.id,
        'in_app',
        'assignment_approved',
        'pending',
        jsonb_build_object('title', v_request.title, 'status', 'accepted')
      ),
      (
        v_assignment.helper_id,
        v_request.id,
        v_assignment.id,
        'in_app',
        'assignment_approved',
        'pending',
        jsonb_build_object('title', v_request.title, 'status', 'accepted')
      );
  end loop;

  if v_accepted_count >= v_request.required_helpers then
    update public.help_requests
    set status = 'accepted'
    where id = v_request.id
      and status = 'published';
  end if;

  return v_approved_count;
end;
$$;

create or replace function public.finalize_help_request_match(
  p_help_request_id uuid,
  p_underfilled_reason text default null
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
  v_accepted_count integer;
  v_pending_count integer;
  v_reason text := nullif(btrim(coalesce(p_underfilled_reason, '')), '');
begin
  if not public.is_mediator() then
    raise exception 'Only mediators/admins can finalize helper matches';
  end if;

  v_actor_id := public.current_profile_id();

  select *
  into v_before
  from public.help_requests
  where id = p_help_request_id
  for update;

  if not found or v_before.status <> 'published' then
    raise exception 'Request is not open for match finalization';
  end if;

  select
    count(*) filter (where status in ('accepted', 'completed_submitted', 'confirmed', 'disputed')),
    count(*) filter (where status = 'applied')
  into v_accepted_count, v_pending_count
  from public.assignments
  where help_request_id = p_help_request_id;

  if v_accepted_count <= 1 then
    raise exception 'Requests with one or fewer accepted helpers must be marked failed';
  end if;

  if v_accepted_count < 3 and v_reason is null then
    raise exception 'Underfilled match reason is required';
  end if;

  update public.help_requests
  set status = 'accepted',
      admin_notes = case
        when v_accepted_count < greatest(required_helpers, 3) then
          concat_ws(
            E'\n',
            admin_notes,
            '부족 인원 진행 사유: ' || v_reason
          )
        else admin_notes
      end
  where id = p_help_request_id
  returning *
  into v_after;

  update public.assignments
  set status = 'rejected',
      cancelled_at = coalesce(cancelled_at, now())
  where help_request_id = p_help_request_id
    and status = 'applied';

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
    p_help_request_id,
    case
      when v_accepted_count < v_before.required_helpers then 'help_request_underfilled_finalized'
      else 'help_request_match_finalized'
    end,
    jsonb_build_object(
      'request', to_jsonb(v_before),
      'accepted_count', v_accepted_count,
      'pending_count', v_pending_count
    ),
    jsonb_build_object(
      'request', to_jsonb(v_after),
      'accepted_count', v_accepted_count,
      'rejected_pending_count', v_pending_count,
      'underfilled_reason', v_reason
    )
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
  select
    a.helper_id,
    p_help_request_id,
    a.id,
    'in_app',
    'match_finalized',
    'pending',
    jsonb_build_object(
      'title', v_after.title,
      'status', 'accepted',
      'accepted_count', v_accepted_count,
      'required_helpers', v_after.required_helpers
    )
  from public.assignments a
  where a.help_request_id = p_help_request_id
    and a.status in ('accepted', 'completed_submitted', 'confirmed', 'disputed');

  return p_help_request_id;
end;
$$;

create or replace function public.mark_help_request_unfilled(
  p_help_request_id uuid,
  p_reason text
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
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not public.is_mediator() then
    raise exception 'Only mediators/admins can mark requests failed';
  end if;

  if v_reason is null then
    raise exception 'Failure reason is required';
  end if;

  v_actor_id := public.current_profile_id();

  select *
  into v_before
  from public.help_requests
  where id = p_help_request_id
  for update;

  if not found or v_before.status not in ('published', 'accepted') then
    raise exception 'Request cannot be marked failed from its current status';
  end if;

  update public.help_requests
  set status = 'cancelled',
      admin_notes = concat_ws(E'\n', admin_notes, '무산 사유: ' || v_reason)
  where id = p_help_request_id
  returning *
  into v_after;

  update public.assignments
  set status = case
        when status = 'applied' then 'rejected'::public.assignment_status
        else status
      end,
      cancelled_at = case
        when status in ('applied', 'accepted') then coalesce(cancelled_at, now())
        else cancelled_at
      end
  where help_request_id = p_help_request_id
    and status in ('applied', 'accepted');

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
    p_help_request_id,
    'help_request_unfilled_cancelled',
    to_jsonb(v_before),
    jsonb_build_object('request', to_jsonb(v_after), 'reason', v_reason)
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
  select
    a.helper_id,
    p_help_request_id,
    a.id,
    'in_app',
    'request_cancelled_unfilled',
    'pending',
    jsonb_build_object(
      'title', v_after.title,
      'status', 'cancelled',
      'reason', v_reason
    )
  from public.assignments a
  where a.help_request_id = p_help_request_id;

  return p_help_request_id;
end;
$$;

create or replace function public.submit_completion(
  p_assignment_id uuid,
  p_image_path text,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_helper_id uuid;
  v_assignment public.assignments%rowtype;
  v_request public.help_requests%rowtype;
  v_requester public.profiles%rowtype;
  v_proof_id uuid;
begin
  v_helper_id := public.current_profile_id();

  if nullif(btrim(coalesce(p_image_path, '')), '') is null then
    raise exception 'Completion photo is required';
  end if;

  if nullif(btrim(coalesce(p_note, '')), '') is null then
    raise exception 'Completion review text is required';
  end if;

  select *
  into v_assignment
  from public.assignments
  where id = p_assignment_id
    and helper_id = v_helper_id
    and status = 'accepted'
  for update;

  if not found then
    raise exception 'Assignment is not available for completion submission';
  end if;

  select *
  into v_request
  from public.help_requests
  where id = v_assignment.help_request_id
  for update;

  select *
  into v_requester
  from public.profiles
  where id = v_request.requester_id;

  if v_requester.consent_photo is not true then
    raise exception 'Requester has not consented to completion photo storage';
  end if;

  insert into public.completion_proofs (assignment_id, image_path, note)
  values (p_assignment_id, btrim(p_image_path), btrim(p_note))
  returning id into v_proof_id;

  update public.assignments
  set status = 'completed_submitted',
      completed_at = now()
  where id = p_assignment_id;

  if not exists (
    select 1
    from public.assignments a
    where a.help_request_id = v_assignment.help_request_id
      and a.status = 'accepted'
  ) then
    update public.help_requests
    set status = 'completed_submitted'
    where id = v_assignment.help_request_id
      and status = 'accepted';
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
    v_helper_id,
    'assignment',
    p_assignment_id,
    'completion_submitted',
    to_jsonb(v_assignment),
    jsonb_build_object('completion_proof_id', v_proof_id)
  );

  return v_proof_id;
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
  v_existing_credit_id uuid;
  v_review_bonus_id uuid;
  v_completion_note text;
begin
  if not public.is_mediator() then
    raise exception 'Only mediators/admins can confirm and credit assignments';
  end if;

  v_actor_id := public.current_profile_id();

  select cl.id
  into v_existing_credit_id
  from public.assignments a
  join public.credit_ledger cl on cl.assignment_id = a.id
    and cl.profile_id = a.helper_id
    and cl.reason = 'task_completion'
  where a.id = p_assignment_id
    and a.status = 'confirmed'
  limit 1;

  if v_existing_credit_id is not null then
    return v_existing_credit_id;
  end if;

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
  join lateral (
    select image_path, note
    from public.completion_proofs cp
    where cp.assignment_id = a.id
      and cp.status = 'submitted'
      and nullif(btrim(cp.image_path), '') is not null
      and nullif(btrim(coalesce(cp.note, '')), '') is not null
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
  where id = v_help_request_id
    and not exists (
      select 1
      from public.assignments a
      where a.help_request_id = v_help_request_id
        and a.status in ('accepted', 'completed_submitted')
    );

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

grant execute on function public.calculate_help_credit(public.help_category, integer, numeric, boolean) to authenticated;
grant execute on function public.admin_update_help_request(uuid, jsonb) to authenticated;
grant execute on function public.apply_help_request(uuid) to authenticated;
grant execute on function public.accept_help_request(uuid) to authenticated;
grant execute on function public.list_published_help_requests(text, public.help_category, boolean, integer, integer, numeric, numeric, text) to authenticated;
grant execute on function public.list_my_helper_assignments() to authenticated;
grant execute on function public.cancel_help_application(uuid) to authenticated;
grant execute on function public.approve_all_assignments_for_request(uuid) to authenticated;
grant execute on function public.finalize_help_request_match(uuid, text) to authenticated;
grant execute on function public.mark_help_request_unfilled(uuid, text) to authenticated;
grant execute on function public.submit_completion(uuid, text, text) to authenticated;
grant execute on function public.confirm_assignment_and_credit(uuid, integer, text, public.review_source) to authenticated;
