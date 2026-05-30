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

grant execute on function public.admin_update_help_request(uuid, jsonb) to authenticated;
