-- H-6 completion proof update: photo required, review optional, 1000 review bonus,
-- and admin-managed no-show review candidates.

alter type public.assignment_status add value if not exists 'no_show';

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
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  v_helper_id := public.current_profile_id();

  if nullif(btrim(coalesce(p_image_path, '')), '') is null then
    raise exception 'Completion photo is required';
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

  if v_request.appointment_time is not null and now() < v_request.appointment_time then
    raise exception 'Completion can be submitted after the appointment time';
  end if;

  select *
  into v_requester
  from public.profiles
  where id = v_request.requester_id;

  if v_requester.consent_photo is not true then
    raise exception 'Requester has not consented to completion photo storage';
  end if;

  insert into public.completion_proofs (assignment_id, image_path, note)
  values (p_assignment_id, btrim(p_image_path), v_note)
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
    jsonb_build_object('completion_proof_id', v_proof_id, 'review_bonus_eligible', v_note is not null)
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
  v_review_bonus_amount constant integer := 1000;
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
      v_review_bonus_amount,
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
      'review_bonus_amount', case when v_review_bonus_id is not null then v_review_bonus_amount else 0 end
    )
  );

  return v_credit_id;
end;
$$;

create or replace function public.list_unsubmitted_completion_candidates()
returns table (
  assignment_id uuid,
  help_request_id uuid,
  helper_id uuid,
  helper_name text,
  helper_phone text,
  requester_id uuid,
  requester_name text,
  requester_phone text,
  request_title text,
  appointment_time timestamptz,
  appointment_timezone text,
  hours_overdue numeric
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_mediator() then
    raise exception 'Only mediators/admins can view completion candidates';
  end if;

  return query
  select
    a.id,
    h.id,
    hp.id,
    hp.name,
    hp.phone,
    rp.id,
    rp.name,
    rp.phone,
    h.title,
    h.appointment_time,
    h.appointment_timezone,
    round((extract(epoch from (now() - h.appointment_time)) / 3600.0)::numeric, 1)
  from public.assignments a
  join public.help_requests h on h.id = a.help_request_id
  join public.profiles hp on hp.id = a.helper_id
  join public.profiles rp on rp.id = h.requester_id
  where a.status = 'accepted'
    and h.appointment_time is not null
    and now() >= h.appointment_time
    and not exists (
      select 1
      from public.completion_proofs cp
      where cp.assignment_id = a.id
    )
  order by h.appointment_time asc, a.accepted_at asc nulls last, a.created_at asc;
end;
$$;

create or replace function public.resolve_unsubmitted_completion(
  p_assignment_id uuid,
  p_elder_confirmed_visit boolean,
  p_admin_notes text default null
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
  v_helper public.profiles%rowtype;
  v_requester public.profiles%rowtype;
  v_credit_reward integer;
  v_credit_id uuid;
begin
  if not public.is_mediator() then
    raise exception 'Only mediators/admins can resolve completion candidates';
  end if;

  v_actor_id := public.current_profile_id();

  select *
  into v_before
  from public.assignments
  where id = p_assignment_id
  for update;

  if not found or v_before.status <> 'accepted' then
    raise exception 'Only accepted assignments without completion can be resolved';
  end if;

  if exists (
    select 1
    from public.completion_proofs cp
    where cp.assignment_id = p_assignment_id
  ) then
    raise exception 'Assignment already has a completion proof';
  end if;

  select *
  into v_request
  from public.help_requests
  where id = v_before.help_request_id
  for update;

  if v_request.appointment_time is not null and now() < v_request.appointment_time then
    raise exception 'Completion candidate can be resolved after the appointment time';
  end if;

  select * into v_helper from public.profiles where id = v_before.helper_id;
  select * into v_requester from public.profiles where id = v_request.requester_id;

  if coalesce(p_elder_confirmed_visit, false) then
    v_credit_reward := public.calculate_help_credit(
      v_request.category,
      v_request.estimated_duration_minutes,
      public.straight_line_distance_meters(
        v_helper.latitude,
        v_helper.longitude,
        coalesce(v_request.location_latitude, v_requester.latitude),
        coalesce(v_request.location_longitude, v_requester.longitude)
      ),
      false
    );

    update public.assignments
    set status = 'confirmed',
        completed_at = coalesce(completed_at, now())
    where id = p_assignment_id
    returning * into v_after;

    insert into public.credit_ledger (
      profile_id,
      assignment_id,
      amount,
      reason,
      created_by
    )
    values (
      v_before.helper_id,
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
      and profile_id = v_before.helper_id
      and reason = 'task_completion'
    limit 1;

    update public.help_requests
    set status = 'credited'
    where id = v_before.help_request_id
      and not exists (
        select 1
        from public.assignments a
        where a.help_request_id = v_before.help_request_id
          and a.id <> p_assignment_id
          and a.status in ('accepted', 'completed_submitted')
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
      'completion_rescued_by_elder_call',
      to_jsonb(v_before),
      jsonb_build_object(
        'assignment', to_jsonb(v_after),
        'admin_notes', nullif(btrim(coalesce(p_admin_notes, '')), ''),
        'task_credit_id', v_credit_id,
        'task_credit_amount', greatest(v_credit_reward, 1)
      )
    );
  else
    update public.assignments
    set status = 'no_show',
        cancelled_at = coalesce(cancelled_at, now())
    where id = p_assignment_id
    returning * into v_after;

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
      'assignment_no_show_confirmed',
      to_jsonb(v_before),
      jsonb_build_object(
        'assignment', to_jsonb(v_after),
        'admin_notes', nullif(btrim(coalesce(p_admin_notes, '')), ''),
        'repost_followup_required', true
      )
    );
  end if;

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
    v_before.help_request_id,
    p_assignment_id,
    'in_app',
    case when coalesce(p_elder_confirmed_visit, false) then 'completion_rescued' else 'no_show_confirmed' end,
    'pending',
    jsonb_build_object(
      'title', v_request.title,
      'status', case when coalesce(p_elder_confirmed_visit, false) then 'confirmed' else 'no_show' end
    )
  );

  if not coalesce(p_elder_confirmed_visit, false) then
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
      v_before.help_request_id,
      p_assignment_id,
      'in_app',
      'no_show_repost_followup',
      'pending',
      jsonb_build_object(
        'title', v_request.title,
        'requester_name', v_requester.name,
        'requester_phone', v_requester.phone,
        'helper_name', v_helper.name
      )
    );
  end if;

  return p_assignment_id;
end;
$$;

-- Restore accepted-helper private fields after H-4 time-option override and include no_show
-- in the helper history without treating it as an active/private state.
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
    and a.status in ('applied', 'accepted', 'completed_submitted', 'confirmed', 'disputed', 'no_show')
  order by a.created_at desc;
end;
$$;

grant execute on function public.submit_completion(uuid, text, text) to authenticated;
grant execute on function public.confirm_assignment_and_credit(uuid, integer, text, public.review_source) to authenticated;
grant execute on function public.list_unsubmitted_completion_candidates() to authenticated;
grant execute on function public.resolve_unsubmitted_completion(uuid, boolean, text) to authenticated;
grant execute on function public.list_my_helper_assignments() to authenticated;
