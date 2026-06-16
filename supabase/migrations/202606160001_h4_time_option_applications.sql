-- H-4 two-time-option helper applications.
-- Existing single appointment_time requests keep working through a seeded/default option.

do $$ begin
  create type public.help_request_time_option_status as enum ('open', 'locked', 'closed');
exception when duplicate_object then null;
end $$;

create table if not exists public.help_request_time_options (
  id uuid primary key default gen_random_uuid(),
  help_request_id uuid not null references public.help_requests(id) on delete cascade,
  label text not null,
  starts_at timestamptz not null,
  timezone text not null default 'Asia/Seoul',
  status public.help_request_time_option_status not null default 'open',
  locked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint help_request_time_options_label_not_blank check (btrim(label) <> '')
);

create index if not exists help_request_time_options_request_idx
on public.help_request_time_options(help_request_id, starts_at);

create unique index if not exists help_request_time_options_one_locked_idx
on public.help_request_time_options(help_request_id)
where status = 'locked';

alter table public.assignments
  add column if not exists time_option_id uuid
  references public.help_request_time_options(id) on delete set null;

create index if not exists assignments_time_option_idx
on public.assignments(time_option_id)
where time_option_id is not null;

alter table public.help_request_time_options enable row level security;

drop policy if exists help_request_time_options_select_authenticated
on public.help_request_time_options;

create policy help_request_time_options_select_authenticated
on public.help_request_time_options for select
to authenticated
using (true);

drop policy if exists help_request_time_options_admin_write
on public.help_request_time_options;

create policy help_request_time_options_admin_write
on public.help_request_time_options for all
to authenticated
using (public.is_mediator())
with check (public.is_mediator());

create or replace function public.set_help_request_time_options_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_help_request_time_options_updated_at
on public.help_request_time_options;

create trigger set_help_request_time_options_updated_at
before update on public.help_request_time_options
for each row execute function public.set_help_request_time_options_updated_at();

insert into public.help_request_time_options (
  help_request_id,
  label,
  starts_at,
  timezone,
  status,
  locked_at
)
select
  h.id,
  '확정 시간',
  h.appointment_time,
  h.appointment_timezone,
  case when h.status = 'accepted' then 'locked'::public.help_request_time_option_status else 'open'::public.help_request_time_option_status end,
  case when h.status = 'accepted' then coalesce(h.approved_at, h.published_at, h.created_at, now()) else null end
from public.help_requests h
where h.appointment_time is not null
  and not exists (
    select 1
    from public.help_request_time_options opt
    where opt.help_request_id = h.id
  );

update public.assignments a
set time_option_id = opt.id
from public.help_request_time_options opt
where a.time_option_id is null
  and opt.help_request_id = a.help_request_id
  and not exists (
    select 1
    from public.help_request_time_options opt2
    where opt2.help_request_id = opt.help_request_id
      and (
        opt2.starts_at < opt.starts_at
        or (opt2.starts_at = opt.starts_at and opt2.id < opt.id)
      )
  );

create or replace function public.help_request_time_options_payload(
  p_help_request_id uuid,
  p_current_helper_id uuid default null
)
returns jsonb
language sql
stable
set search_path = public
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', opt.id,
        'label', opt.label,
        'starts_at', opt.starts_at,
        'timezone', opt.timezone,
        'status', opt.status,
        'locked_at', opt.locked_at,
        'applied_count', coalesce(counts.active_count, 0),
        'accepted_count', coalesce(counts.accepted_count, 0),
        'is_locked', opt.status = 'locked',
        'is_available', opt.status in ('open', 'locked') and coalesce(counts.active_count, 0) < 6,
        'current_helper_assignment_id', mine.id,
        'current_helper_assignment_status', mine.status
      )
      order by opt.starts_at asc, opt.created_at asc
    ),
    '[]'::jsonb
  )
  from public.help_request_time_options opt
  left join lateral (
    select
      count(*) filter (
        where a.status in ('applied', 'accepted', 'completed_submitted', 'confirmed', 'disputed')
      )::integer as active_count,
      count(*) filter (
        where a.status in ('accepted', 'completed_submitted', 'confirmed', 'disputed')
      )::integer as accepted_count
    from public.assignments a
    where a.time_option_id = opt.id
  ) counts on true
  left join lateral (
    select a.id, a.status
    from public.assignments a
    where a.time_option_id = opt.id
      and a.helper_id = p_current_helper_id
      and a.status in ('applied', 'accepted', 'completed_submitted', 'confirmed', 'disputed')
    order by a.created_at desc
    limit 1
  ) mine on true
  where opt.help_request_id = p_help_request_id;
$$;

create or replace function public.lock_help_request_time_option_if_ready(
  p_help_request_id uuid,
  p_time_option_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_option public.help_request_time_options%rowtype;
  v_request public.help_requests%rowtype;
  v_active_count integer := 0;
  v_locked_exists boolean := false;
begin
  select *
  into v_request
  from public.help_requests
  where id = p_help_request_id
  for update;

  if not found then
    raise exception 'Help request not found';
  end if;

  perform 1
  from public.help_request_time_options
  where help_request_id = p_help_request_id
  order by starts_at asc, created_at asc
  for update;

  select exists (
    select 1
    from public.help_request_time_options
    where help_request_id = p_help_request_id
      and status = 'locked'
  )
  into v_locked_exists;

  if v_locked_exists then
    return false;
  end if;

  select *
  into v_option
  from public.help_request_time_options
  where id = p_time_option_id
    and help_request_id = p_help_request_id;

  if not found then
    raise exception 'Time option not found';
  end if;

  select count(*)::integer
  into v_active_count
  from public.assignments
  where time_option_id = p_time_option_id
    and status in ('applied', 'accepted', 'completed_submitted', 'confirmed', 'disputed');

  if v_active_count < 3 then
    return false;
  end if;

  update public.help_request_time_options
  set status = case when id = p_time_option_id then 'locked' else 'closed' end,
      locked_at = case when id = p_time_option_id then now() else locked_at end
  where help_request_id = p_help_request_id;

  update public.help_requests
  set appointment_time = v_option.starts_at,
      appointment_timezone = v_option.timezone
  where id = p_help_request_id;

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
    p_help_request_id,
    null,
    'in_app',
    'time_option_locked',
    'pending',
    jsonb_build_object(
      'title', v_request.title,
      'time_option_id', p_time_option_id,
      'appointment_time', v_option.starts_at,
      'active_count', v_active_count
    )
  )
  on conflict do nothing;

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
    case when a.time_option_id = p_time_option_id then 'time_option_locked' else 'time_option_move_needed' end,
    'pending',
    jsonb_build_object(
      'title', v_request.title,
      'status', case when a.time_option_id = p_time_option_id then 'locked' else 'move_needed' end,
      'locked_time_option_id', p_time_option_id,
      'appointment_time', v_option.starts_at
    )
  from public.assignments a
  where a.help_request_id = p_help_request_id
    and a.status = 'applied';

  return true;
end;
$$;

drop function if exists public.apply_help_request(uuid);

create or replace function public.apply_help_request(
  p_help_request_id uuid,
  p_time_option_id uuid default null
)
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
  v_active_count integer := 0;
  v_option_count integer := 0;
  v_chosen_option public.help_request_time_options%rowtype;
  v_locked_option public.help_request_time_options%rowtype;
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

  if not exists (
    select 1
    from public.help_request_time_options
    where help_request_id = p_help_request_id
  ) and v_request.appointment_time is not null then
    insert into public.help_request_time_options (
      help_request_id,
      label,
      starts_at,
      timezone
    )
    values (
      p_help_request_id,
      '확정 시간',
      v_request.appointment_time,
      v_request.appointment_timezone
    );
  end if;

  perform 1
  from public.help_request_time_options
  where help_request_id = p_help_request_id
  order by starts_at asc, created_at asc
  for update;

  select count(*)::integer
  into v_option_count
  from public.help_request_time_options
  where help_request_id = p_help_request_id;

  select *
  into v_locked_option
  from public.help_request_time_options
  where help_request_id = p_help_request_id
    and status = 'locked'
  order by locked_at asc
  limit 1;

  if v_locked_option.id is not null then
    if p_time_option_id is not null and p_time_option_id <> v_locked_option.id then
      raise exception 'This time option is no longer available';
    end if;

    v_chosen_option := v_locked_option;
  elsif p_time_option_id is not null then
    select *
    into v_chosen_option
    from public.help_request_time_options
    where id = p_time_option_id
      and help_request_id = p_help_request_id
      and status = 'open';
  elsif v_option_count = 1 then
    select *
    into v_chosen_option
    from public.help_request_time_options
    where help_request_id = p_help_request_id
      and status = 'open'
    order by starts_at asc, created_at asc
    limit 1;
  else
    raise exception 'Time option is required';
  end if;

  if v_chosen_option.id is null then
    raise exception 'Time option is not available';
  end if;

  select count(*)::integer
  into v_active_count
  from public.assignments
  where time_option_id = v_chosen_option.id
    and status in ('applied', 'accepted', 'completed_submitted', 'confirmed', 'disputed');

  if v_active_count >= 6 then
    raise exception 'Request is already full';
  end if;

  insert into public.assignments (
    help_request_id,
    helper_id,
    time_option_id,
    status,
    applied_at,
    accepted_at
  )
  values (
    p_help_request_id,
    v_helper_id,
    v_chosen_option.id,
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
    'time_option_id', v_chosen_option.id,
    'appointment_time', v_chosen_option.starts_at,
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
      'request_accepted',
      'pending',
      v_payload
    );

  perform public.lock_help_request_time_option_if_ready(p_help_request_id, v_chosen_option.id);

  return v_assignment_id;
end;
$$;

grant execute on function public.apply_help_request(uuid, uuid) to authenticated;

create or replace function public.move_help_application_to_locked_option(
  p_assignment_id uuid
)
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
  v_locked_option public.help_request_time_options%rowtype;
  v_active_count integer := 0;
begin
  v_helper_id := public.current_profile_id();

  if v_helper_id is null or public.current_user_role() <> 'helper' then
    raise exception 'Only helpers can move their applications';
  end if;

  select *
  into v_before
  from public.assignments
  where id = p_assignment_id
    and helper_id = v_helper_id
  for update;

  if not found or v_before.status <> 'applied' then
    raise exception 'Only pending applications can be moved';
  end if;

  select *
  into v_request
  from public.help_requests
  where id = v_before.help_request_id
  for update;

  if not found or v_request.status <> 'published' then
    raise exception 'Application can no longer be moved';
  end if;

  select *
  into v_locked_option
  from public.help_request_time_options
  where help_request_id = v_request.id
    and status = 'locked'
  limit 1;

  if not found then
    raise exception 'No confirmed time option is available yet';
  end if;

  if v_before.time_option_id = v_locked_option.id then
    return p_assignment_id;
  end if;

  select count(*)::integer
  into v_active_count
  from public.assignments
  where time_option_id = v_locked_option.id
    and status in ('applied', 'accepted', 'completed_submitted', 'confirmed', 'disputed');

  if v_active_count >= 6 then
    raise exception 'Confirmed time option is already full';
  end if;

  update public.assignments
  set time_option_id = v_locked_option.id
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
    'assignment_time_option_moved',
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
    v_helper_id,
    v_request.id,
    p_assignment_id,
    'in_app',
    'time_option_moved',
    'pending',
    jsonb_build_object(
      'title', v_request.title,
      'time_option_id', v_locked_option.id,
      'appointment_time', v_locked_option.starts_at
    )
  );

  return p_assignment_id;
end;
$$;

grant execute on function public.move_help_application_to_locked_option(uuid)
to authenticated;

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

  if v_request.status <> 'published' then
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
  current_helper_time_option_id uuid,
  locked_time_option_id uuid,
  time_options jsonb,
  application_deadline timestamptz,
  applications_locked boolean,
  is_full boolean,
  can_apply boolean,
  apply_block_reason text,
  application_state text
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
      mine.time_option_id as current_helper_time_option_id,
      locked.id as locked_time_option_id,
      public.help_request_time_options_payload(h.id, v_profile_id) as time_options,
      public.help_request_application_deadline(coalesce(locked.starts_at, h.appointment_time)) as application_deadline
    from public.help_requests h
    join public.profiles rp on rp.id = h.requester_id
    left join public.help_request_time_options locked
      on locked.help_request_id = h.id
      and locked.status = 'locked'
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
        and (
          locked.id is null
          or a.time_option_id = locked.id
          or a.status in ('accepted', 'completed_submitted', 'confirmed', 'disputed')
        )
    ) counts on true
    left join lateral (
      select a.id, a.status, a.time_option_id
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
    d.current_helper_time_option_id,
    d.locked_time_option_id,
    d.time_options,
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
    end as apply_block_reason,
    case
      when d.current_helper_assignment_status is null then 'not_applied'
      when d.current_helper_assignment_status <> 'applied' then d.current_helper_assignment_status::text
      when d.locked_time_option_id is null then 'pending'
      when d.current_helper_time_option_id = d.locked_time_option_id then 'locked_my_time'
      else 'move_needed'
    end as application_state
  from decisions d;
end;
$$;

grant execute on function public.get_help_request_detail(uuid, numeric, numeric)
to authenticated;

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
      'rejected_at', h.rejected_at,
      'time_options', public.help_request_time_options_payload(h.id, v_helper_id),
      'locked_time_option_id', locked.id,
      'application_state', case
        when a.status <> 'applied' then a.status::text
        when locked.id is null then 'pending'
        when a.time_option_id = locked.id then 'locked_my_time'
        else 'move_needed'
      end
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
    coalesce(companions.helpers, '[]'::jsonb) as companion_helpers,
    coalesce(proofs.items, '[]'::jsonb) as completion_proofs,
    coalesce(credits.items, '[]'::jsonb) as credit_ledger
  from public.assignments a
  join public.help_requests h on h.id = a.help_request_id
  join public.profiles rp on rp.id = h.requester_id
  left join public.help_request_time_options locked
    on locked.help_request_id = h.id
    and locked.status = 'locked'
  left join lateral (
    select jsonb_agg(
      jsonb_build_object(
        'id', hp.id,
        'name', hp.name,
        'phone', hp.phone,
        'status', ca.status
      )
      order by hp.name
    ) as helpers
    from public.assignments ca
    join public.profiles hp on hp.id = ca.helper_id
    where ca.help_request_id = a.help_request_id
      and ca.id <> a.id
      and ca.status in ('accepted', 'completed_submitted', 'confirmed', 'disputed')
      and a.status in ('accepted', 'completed_submitted', 'confirmed', 'disputed')
  ) companions on true
  left join lateral (
    select jsonb_agg(to_jsonb(cp) order by cp.submitted_at desc) as items
    from public.completion_proofs cp
    where cp.assignment_id = a.id
  ) proofs on true
  left join lateral (
    select jsonb_agg(to_jsonb(cl) order by cl.created_at desc) as items
    from public.credit_ledger cl
    where cl.assignment_id = a.id
  ) credits on true
  where a.helper_id = v_helper_id
    and a.status in ('applied', 'accepted', 'completed_submitted', 'confirmed', 'disputed')
  order by a.created_at desc;
end;
$$;

grant execute on function public.list_my_helper_assignments() to authenticated;
