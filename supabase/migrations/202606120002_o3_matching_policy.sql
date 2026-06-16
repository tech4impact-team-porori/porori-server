-- O-3 matching policy alignment:
-- application approval deadline is appointment - 48h, helper cancellation
-- remains locked at appointment - 24h, operational alerts are idempotent,
-- and match finalization side effects are centralized on accepted transition.

create or replace function public.help_request_application_deadline(
  p_appointment_time timestamptz
)
returns timestamptz
language sql
stable
as $$
  select case
    when p_appointment_time is null then null
    else p_appointment_time - interval '48 hours'
  end;
$$;

grant execute on function public.help_request_application_deadline(timestamptz)
to authenticated;

drop function if exists public.get_help_request_matching_state(uuid);

create or replace function public.get_help_request_matching_state(
  p_help_request_id uuid
)
returns table (
  help_request_id uuid,
  status public.help_request_status,
  required_helpers integer,
  minimum_helpers integer,
  capacity_helpers integer,
  applied_count integer,
  accepted_count integer,
  active_count integer,
  application_deadline timestamptz,
  cancellation_deadline timestamptz,
  application_deadline_passed boolean,
  cancellation_locked boolean,
  minimum_met boolean,
  capacity_full boolean,
  approval_ready boolean,
  underfilled_at_deadline boolean,
  must_fail_at_deadline boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.help_requests%rowtype;
  v_minimum constant integer := 3;
  v_capacity constant integer := 6;
begin
  if not public.is_mediator() then
    raise exception 'Only mediators/admins can inspect matching state';
  end if;

  select *
  into v_request
  from public.help_requests
  where id = p_help_request_id;

  if not found then
    raise exception 'Help request not found';
  end if;

  return query
  with counts as (
    select
      count(*) filter (where a.status = 'applied')::integer as applied_count,
      count(*) filter (
        where a.status in ('accepted', 'completed_submitted', 'confirmed', 'disputed')
      )::integer as accepted_count,
      count(*) filter (
        where a.status in ('applied', 'accepted', 'completed_submitted', 'confirmed', 'disputed')
      )::integer as active_count
    from public.assignments a
    where a.help_request_id = p_help_request_id
  ),
  deadlines as (
    select
      public.help_request_application_deadline(v_request.appointment_time) as application_deadline,
      public.help_request_cancellation_deadline(v_request.appointment_time) as cancellation_deadline
  )
  select
    v_request.id,
    v_request.status,
    v_request.required_helpers,
    v_minimum,
    v_capacity,
    coalesce(c.applied_count, 0),
    coalesce(c.accepted_count, 0),
    coalesce(c.active_count, 0),
    d.application_deadline,
    d.cancellation_deadline,
    d.application_deadline is not null and now() >= d.application_deadline,
    d.cancellation_deadline is not null and now() >= d.cancellation_deadline,
    coalesce(c.active_count, 0) >= v_minimum,
    coalesce(c.active_count, 0) >= v_capacity,
    coalesce(c.active_count, 0) >= v_capacity
      or (
        d.application_deadline is not null
        and now() >= d.application_deadline
        and coalesce(c.active_count, 0) >= v_minimum
      ),
    d.application_deadline is not null
      and now() >= d.application_deadline
      and coalesce(c.active_count, 0) > 1
      and coalesce(c.active_count, 0) < v_minimum,
    d.application_deadline is not null
      and now() >= d.application_deadline
      and coalesce(c.active_count, 0) <= 1
  from counts c
  cross join deadlines d;
end;
$$;

grant execute on function public.get_help_request_matching_state(uuid)
to authenticated;

create or replace function public.create_matching_operational_alerts_for_request(
  p_help_request_id uuid,
  p_include_deadline_alerts boolean default false
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.help_requests%rowtype;
  v_applied_count integer := 0;
  v_accepted_count integer := 0;
  v_active_count integer := 0;
  v_application_deadline timestamptz;
  v_inserted integer := 0;
  v_total_inserted integer := 0;
  v_payload jsonb;
  v_minimum constant integer := 3;
  v_capacity constant integer := 6;
begin
  select *
  into v_request
  from public.help_requests
  where id = p_help_request_id;

  if not found or v_request.status <> 'published' then
    return 0;
  end if;

  select
    count(*) filter (where status = 'applied')::integer,
    count(*) filter (where status in ('accepted', 'completed_submitted', 'confirmed', 'disputed'))::integer,
    count(*) filter (where status in ('applied', 'accepted', 'completed_submitted', 'confirmed', 'disputed'))::integer
  into v_applied_count, v_accepted_count, v_active_count
  from public.assignments
  where help_request_id = p_help_request_id;

  v_application_deadline := public.help_request_application_deadline(v_request.appointment_time);
  v_payload := jsonb_build_object(
    'title', v_request.title,
    'appointment_time', v_request.appointment_time,
    'application_deadline', v_application_deadline,
    'minimum_helpers', v_minimum,
    'capacity_helpers', v_capacity,
    'required_helpers', v_request.required_helpers,
    'applied_count', coalesce(v_applied_count, 0),
    'accepted_count', coalesce(v_accepted_count, 0),
    'active_count', coalesce(v_active_count, 0)
  );

  if coalesce(v_active_count, 0) >= v_capacity then
    insert into public.notifications (
      recipient_profile_id,
      help_request_id,
      channel,
      purpose,
      status,
      payload
    )
    select
      null,
      v_request.id,
      'in_app',
      'matching_capacity_full',
      'pending',
      v_payload || jsonb_build_object('decision', 'approve_now')
    where not exists (
      select 1
      from public.notifications n
      where n.help_request_id = v_request.id
        and n.purpose = 'matching_capacity_full'
    );

    get diagnostics v_inserted = row_count;
    v_total_inserted := v_total_inserted + v_inserted;
  end if;

  if coalesce(p_include_deadline_alerts, false)
    and v_application_deadline is not null
    and now() >= v_application_deadline
  then
    insert into public.notifications (
      recipient_profile_id,
      help_request_id,
      channel,
      purpose,
      status,
      payload
    )
    select
      null,
      v_request.id,
      'in_app',
      case
        when coalesce(v_active_count, 0) >= v_minimum then 'matching_deadline_ready'
        when coalesce(v_active_count, 0) <= 1 then 'matching_deadline_must_fail'
        else 'matching_deadline_underfilled'
      end,
      'pending',
      v_payload || jsonb_build_object(
        'decision',
        case
          when coalesce(v_active_count, 0) >= v_minimum then 'approve_or_adjust'
          when coalesce(v_active_count, 0) <= 1 then 'mark_unfilled'
          else 'underfilled_decision'
        end
      )
    where not exists (
      select 1
      from public.notifications n
      where n.help_request_id = v_request.id
        and n.purpose in (
          'matching_deadline_ready',
          'matching_deadline_underfilled',
          'matching_deadline_must_fail'
        )
    );

    get diagnostics v_inserted = row_count;
    v_total_inserted := v_total_inserted + v_inserted;
  end if;

  return v_total_inserted;
end;
$$;

revoke all on function public.create_matching_operational_alerts_for_request(uuid, boolean)
from public;
revoke all on function public.create_matching_operational_alerts_for_request(uuid, boolean)
from authenticated;

create or replace function public.refresh_matching_operational_alerts()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request_id uuid;
  v_inserted integer := 0;
  v_total_inserted integer := 0;
begin
  if not public.is_mediator() then
    raise exception 'Only mediators/admins can refresh matching alerts';
  end if;

  for v_request_id in
    select h.id
    from public.help_requests h
    where h.status = 'published'
  loop
    v_inserted := public.create_matching_operational_alerts_for_request(
      v_request_id,
      true
    );
    v_total_inserted := v_total_inserted + v_inserted;
  end loop;

  return v_total_inserted;
end;
$$;

grant execute on function public.refresh_matching_operational_alerts()
to authenticated;

create or replace function public.handle_assignment_matching_alert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status in ('applied', 'accepted', 'completed_submitted', 'confirmed', 'disputed') then
    if tg_op = 'INSERT' then
      perform public.create_matching_operational_alerts_for_request(
        new.help_request_id,
        false
      );
    elsif old.status is distinct from new.status
      or old.help_request_id is distinct from new.help_request_id then
      perform public.create_matching_operational_alerts_for_request(
        new.help_request_id,
        false
      );
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists create_matching_alert_on_assignment_change on public.assignments;
create trigger create_matching_alert_on_assignment_change
after insert or update of status, help_request_id on public.assignments
for each row execute function public.handle_assignment_matching_alert();

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
    and a.status in ('accepted', 'completed_submitted', 'confirmed', 'disputed')
    and not exists (
      select 1
      from public.notifications n
      where n.assignment_id = a.id
        and n.purpose = 'match_finalized'
    );

  return p_help_request_id;
end;
$$;

grant execute on function public.finalize_help_request_match(uuid, text)
to authenticated;

create or replace function public.handle_match_finalized_side_effects()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid;
  v_accepted_count integer := 0;
  v_before_data jsonb := null;
begin
  if new.status <> 'accepted' then
    return new;
  end if;

  if tg_op = 'UPDATE' and old.status is not distinct from new.status then
    return new;
  end if;

  v_actor_id := public.current_profile_id();

  if tg_op = 'UPDATE' then
    v_before_data := to_jsonb(old);
  end if;

  select count(*)::integer
  into v_accepted_count
  from public.assignments a
  where a.help_request_id = new.id
    and a.status in ('accepted', 'completed_submitted', 'confirmed', 'disputed');

  insert into public.audit_events (
    actor_profile_id,
    entity_type,
    entity_id,
    action,
    before_data,
    after_data
  )
  select
    v_actor_id,
    'help_request',
    new.id,
    'match_finalized_side_effects',
    v_before_data,
    jsonb_build_object(
      'request', to_jsonb(new),
      'accepted_count', v_accepted_count
    )
  where not exists (
    select 1
    from public.audit_events ae
    where ae.entity_type = 'help_request'
      and ae.entity_id = new.id
      and ae.action = 'match_finalized_side_effects'
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
    new.id,
    a.id,
    'in_app',
    'match_finalized',
    'pending',
    jsonb_build_object(
      'title', new.title,
      'status', 'accepted',
      'appointment_time', new.appointment_time,
      'accepted_count', v_accepted_count,
      'required_helpers', new.required_helpers,
      'location_detail', new.location_detail,
      'requester_phone', requester.phone,
      'requester_name', requester.name,
      'personal_notes', requester.personal_notes
    )
  from public.assignments a
  join public.profiles requester on requester.id = new.requester_id
  where a.help_request_id = new.id
    and a.status in ('accepted', 'completed_submitted', 'confirmed', 'disputed')
    and not exists (
      select 1
      from public.notifications n
      where n.assignment_id = a.id
        and n.purpose = 'match_finalized'
    );

  update public.assignments a
  set status = 'rejected',
      cancelled_at = coalesce(a.cancelled_at, now())
  where a.help_request_id = new.id
    and a.status = 'applied';

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
    new.id,
    a.id,
    'in_app',
    'assignment_rejected',
    'pending',
    jsonb_build_object(
      'title', new.title,
      'status', 'rejected',
      'reason', '매칭 확정으로 신청이 마감되었습니다.'
    )
  from public.assignments a
  where a.help_request_id = new.id
    and a.status = 'rejected'
    and not exists (
      select 1
      from public.notifications n
      where n.assignment_id = a.id
        and n.purpose = 'assignment_rejected'
    );

  return new;
end;
$$;

drop trigger if exists handle_match_finalized_side_effects_on_accept on public.help_requests;
create trigger handle_match_finalized_side_effects_on_accept
after insert or update of status on public.help_requests
for each row execute function public.handle_match_finalized_side_effects();
