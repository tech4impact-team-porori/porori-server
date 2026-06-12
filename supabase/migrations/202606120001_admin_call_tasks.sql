-- R-2 MVP: admin-operated requester callback tasks after matching.
-- The system queues a real-person call task instead of placing an automated VAPI call.

do $$ begin
  create type public.admin_call_task_status as enum (
    'pending',
    'completed'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  if exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'public'
      and t.typname = 'admin_call_task_status'
      and e.enumlabel in ('no_answer', 'failed')
  ) then
    drop function if exists public.complete_admin_call_task(
      uuid,
      public.admin_call_task_status_old,
      text
    );

    drop function if exists public.complete_admin_call_task(
      uuid,
      public.admin_call_task_status,
      text
    );

    update public.admin_call_tasks
    set status = 'pending'
    where status::text in ('no_answer', 'failed');

    alter type public.admin_call_task_status rename to admin_call_task_status_old;
    create type public.admin_call_task_status as enum ('pending', 'completed');
    alter table public.admin_call_tasks
      alter column status drop default,
      alter column status type public.admin_call_task_status using status::text::public.admin_call_task_status,
      alter column status set default 'pending';
    drop type public.admin_call_task_status_old;
  end if;
end $$;

create table if not exists public.admin_call_tasks (
  id uuid primary key default gen_random_uuid(),
  help_request_id uuid not null references public.help_requests(id) on delete cascade,
  requester_id uuid not null references public.profiles(id) on delete cascade,
  purpose public.call_purpose not null default 'match_confirmation',
  status public.admin_call_task_status not null default 'pending',
  requester_name text not null,
  requester_phone text not null,
  request_title text not null,
  appointment_time timestamptz,
  appointment_timezone text not null default 'Asia/Seoul',
  accepted_helper_count integer not null default 0,
  accepted_helper_names text[] not null default '{}',
  call_script text not null,
  admin_notes text,
  no_answer_count integer not null default 0,
  last_no_answer_at timestamptz,
  completed_by uuid references public.profiles(id) on delete set null,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (help_request_id, purpose)
);

create index if not exists admin_call_tasks_status_created_at_idx
on public.admin_call_tasks(status, created_at desc);

create index if not exists admin_call_tasks_help_request_id_idx
on public.admin_call_tasks(help_request_id);

alter table public.admin_call_tasks
  add column if not exists no_answer_count integer not null default 0,
  add column if not exists last_no_answer_at timestamptz;

alter table public.admin_call_tasks enable row level security;

drop policy if exists admin_call_tasks_select_admin on public.admin_call_tasks;
create policy admin_call_tasks_select_admin
on public.admin_call_tasks for select
to authenticated
using (public.is_mediator());

drop policy if exists admin_call_tasks_update_admin on public.admin_call_tasks;
create policy admin_call_tasks_update_admin
on public.admin_call_tasks for update
to authenticated
using (public.is_mediator())
with check (public.is_mediator());

create or replace function public.set_admin_call_tasks_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_admin_call_tasks_updated_at on public.admin_call_tasks;
create trigger set_admin_call_tasks_updated_at
before update on public.admin_call_tasks
for each row execute function public.set_admin_call_tasks_updated_at();

create or replace function public.queue_match_confirmation_call_task(
  p_help_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.help_requests%rowtype;
  v_requester public.profiles%rowtype;
  v_task_id uuid;
  v_helper_count integer;
  v_helper_names text[];
  v_appointment_label text;
  v_script text;
begin
  select *
  into v_request
  from public.help_requests
  where id = p_help_request_id;

  if not found then
    raise exception 'Help request not found';
  end if;

  if v_request.status <> 'accepted' then
    raise exception 'Match confirmation call can only be queued for accepted requests';
  end if;

  select *
  into v_requester
  from public.profiles
  where id = v_request.requester_id;

  if not found then
    raise exception 'Requester profile not found';
  end if;

  if nullif(btrim(coalesce(v_requester.phone, '')), '') is null then
    raise exception 'Requester phone is required for match confirmation call';
  end if;

  select
    count(*)::integer,
    coalesce(array_agg(p.name order by a.accepted_at asc, a.created_at asc), '{}')
  into v_helper_count, v_helper_names
  from public.assignments a
  join public.profiles p on p.id = a.helper_id
  where a.help_request_id = p_help_request_id
    and a.status in ('accepted', 'completed_submitted', 'confirmed', 'disputed');

  v_appointment_label := case
    when v_request.appointment_time is null then '확정된 방문 시간'
    else to_char(
      v_request.appointment_time at time zone v_request.appointment_timezone,
      'YYYY. FMMM. FMDD. HH24:MI'
    )
  end;

  v_script := format(
    '안녕하세요, 다로리 도움입니다. 요청하신 “%s”은(는) %s에 청년 %s명이 방문하는 것으로 확정되었습니다. 변경이 필요하시면 다로리 직원에게 말씀해주세요.',
    v_request.title,
    v_appointment_label,
    v_helper_count
  );

  insert into public.admin_call_tasks (
    help_request_id,
    requester_id,
    purpose,
    status,
    requester_name,
    requester_phone,
    request_title,
    appointment_time,
    appointment_timezone,
    accepted_helper_count,
    accepted_helper_names,
    call_script
  )
  values (
    p_help_request_id,
    v_requester.id,
    'match_confirmation',
    'pending',
    v_requester.name,
    v_requester.phone,
    v_request.title,
    v_request.appointment_time,
    v_request.appointment_timezone,
    v_helper_count,
    v_helper_names,
    v_script
  )
  on conflict (help_request_id, purpose)
  do update set
    requester_name = excluded.requester_name,
    requester_phone = excluded.requester_phone,
    request_title = excluded.request_title,
    appointment_time = excluded.appointment_time,
    appointment_timezone = excluded.appointment_timezone,
    accepted_helper_count = excluded.accepted_helper_count,
    accepted_helper_names = excluded.accepted_helper_names,
    call_script = excluded.call_script
  returning id into v_task_id;

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
    null,
    p_help_request_id,
    null,
    'in_app',
    'admin_call_task_created',
    'pending',
    jsonb_build_object(
      'title', v_request.title,
      'requester_name', v_requester.name,
      'requester_phone', v_requester.phone,
      'appointment_time', v_request.appointment_time,
      'accepted_helper_count', v_helper_count,
      'call_task_id', v_task_id
    )
  where not exists (
    select 1
    from public.notifications n
    where n.help_request_id = p_help_request_id
      and n.purpose = 'admin_call_task_created'
  );

  return v_task_id;
end;
$$;

create or replace function public.handle_match_confirmation_call_task()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'accepted'
    and (tg_op = 'INSERT' or old.status is distinct from new.status)
  then
    perform public.queue_match_confirmation_call_task(new.id);
  end if;

  return new;
end;
$$;

drop trigger if exists queue_match_confirmation_call_task_on_accept on public.help_requests;
create trigger queue_match_confirmation_call_task_on_accept
after insert or update of status on public.help_requests
for each row execute function public.handle_match_confirmation_call_task();

create or replace function public.complete_admin_call_task(
  p_task_id uuid,
  p_admin_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid;
  v_before public.admin_call_tasks%rowtype;
  v_after public.admin_call_tasks%rowtype;
begin
  if not public.is_mediator() then
    raise exception 'Only mediators/admins can update admin call tasks';
  end if;

  v_actor_id := public.current_profile_id();

  select *
  into v_before
  from public.admin_call_tasks
  where id = p_task_id
  for update;

  if not found then
    raise exception 'Admin call task not found';
  end if;

  update public.admin_call_tasks
  set status = 'completed',
      admin_notes = nullif(btrim(coalesce(p_admin_notes, '')), ''),
      completed_by = v_actor_id,
      completed_at = now()
  where id = p_task_id
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
    'admin_call_task',
    p_task_id,
    'admin_call_task_completed',
    to_jsonb(v_before),
    to_jsonb(v_after)
  );

  return p_task_id;
end;
$$;

create or replace function public.log_admin_call_no_answer(
  p_task_id uuid,
  p_admin_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid;
  v_before public.admin_call_tasks%rowtype;
  v_after public.admin_call_tasks%rowtype;
begin
  if not public.is_mediator() then
    raise exception 'Only mediators/admins can update admin call tasks';
  end if;

  v_actor_id := public.current_profile_id();

  select *
  into v_before
  from public.admin_call_tasks
  where id = p_task_id
  for update;

  if not found then
    raise exception 'Admin call task not found';
  end if;

  if v_before.status <> 'pending' then
    raise exception 'Only pending call tasks can record no-answer attempts';
  end if;

  update public.admin_call_tasks
  set no_answer_count = no_answer_count + 1,
      last_no_answer_at = now(),
      admin_notes = nullif(btrim(coalesce(p_admin_notes, '')), '')
  where id = p_task_id
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
    'admin_call_task',
    p_task_id,
    'admin_call_task_no_answer_logged',
    to_jsonb(v_before),
    to_jsonb(v_after)
  );

  return p_task_id;
end;
$$;

revoke all on function public.queue_match_confirmation_call_task(uuid) from public;
revoke all on function public.queue_match_confirmation_call_task(uuid) from authenticated;
grant select, update on public.admin_call_tasks to authenticated;
grant execute on function public.complete_admin_call_task(uuid, text) to authenticated;
grant execute on function public.log_admin_call_no_answer(uuid, text) to authenticated;
