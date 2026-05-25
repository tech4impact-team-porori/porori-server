-- In-app operational notifications for the MVP workflow.

create index if not exists notifications_recipient_created_at_idx
on public.notifications(recipient_profile_id, created_at desc);

create index if not exists notifications_help_request_id_idx
on public.notifications(help_request_id);

create or replace function public.review_help_request(
  p_help_request_id uuid,
  p_status public.help_request_status
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid;
  v_request public.help_requests%rowtype;
  v_payload jsonb;
begin
  if not public.is_mediator() then
    raise exception 'Only mediators/admins can review help requests';
  end if;

  if p_status not in ('published', 'rejected') then
    raise exception 'Review status must be published or rejected';
  end if;

  v_actor_id := public.current_profile_id();

  update public.help_requests
  set status = p_status,
      approved_by = v_actor_id,
      approved_at = now(),
      published_at = case when p_status = 'published' then now() else null end,
      updated_at = now()
  where id = p_help_request_id
    and status = 'pending_review'
  returning *
  into v_request;

  if not found then
    raise exception 'Request is not waiting for review';
  end if;

  v_payload := jsonb_build_object(
    'title', v_request.title,
    'status', p_status,
    'actor_profile_id', v_actor_id,
    'appointment_time', v_request.appointment_time,
    'credit_reward', v_request.credit_reward,
    'source', v_request.source
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
    v_request.id,
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
      v_request.id,
      'in_app',
      'request_published',
      'pending',
      v_payload || jsonb_build_object('recipient_role', 'helper')
    from public.profiles p
    where p.role = 'helper';
  end if;

  return v_request.id;
end;
$$;

create or replace function public.accept_help_request(p_help_request_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_helper_id uuid;
  v_assignment_id uuid;
  v_request public.help_requests%rowtype;
  v_helper public.profiles%rowtype;
  v_payload jsonb;
begin
  v_helper_id := public.current_profile_id();

  if v_helper_id is null or public.current_user_role() <> 'helper' then
    raise exception 'Only helpers can accept help requests';
  end if;

  select *
  into v_helper
  from public.profiles
  where id = v_helper_id;

  update public.help_requests
  set status = 'accepted',
      updated_at = now()
  where id = p_help_request_id
    and status = 'published'
  returning *
  into v_request;

  if not found then
    raise exception 'Request is not available for acceptance';
  end if;

  insert into public.assignments (help_request_id, helper_id, status)
  values (p_help_request_id, v_helper_id, 'accepted')
  returning id into v_assignment_id;

  v_payload := jsonb_build_object(
    'title', v_request.title,
    'status', 'accepted',
    'helper_profile_id', v_helper_id,
    'helper_name', v_helper.name,
    'appointment_time', v_request.appointment_time,
    'credit_reward', v_request.credit_reward
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
      'request_accepted',
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

  return v_assignment_id;
end;
$$;

grant execute on function public.review_help_request(uuid, public.help_request_status) to authenticated;
grant execute on function public.accept_help_request(uuid) to authenticated;
