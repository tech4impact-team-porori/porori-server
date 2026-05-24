-- DOUM / Porori MVP Supabase schema
-- Initial schema for requester/helper/mediator request lifecycle.

create extension if not exists "pgcrypto";

-- =========================
-- Enums
-- =========================

do $$ begin
  create type public.user_role as enum ('requester', 'helper', 'mediator', 'admin');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.request_source as enum ('voice', 'admin_manual', 'requester_form', 'seed_demo');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.help_request_status as enum (
    'draft',
    'pending_review',
    'published',
    'accepted',
    'completed_submitted',
    'confirmed',
    'credited',
    'closed',
    'rejected',
    'cancelled',
    'disputed',
    'expired'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.help_category as enum (
    'electronics',
    'labor',
    'daily_life',
    'mobility_care',
    'household',
    'other'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.assignment_status as enum (
    'accepted',
    'completed_submitted',
    'confirmed',
    'cancelled',
    'disputed'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.completion_proof_status as enum ('submitted', 'approved', 'rejected');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.review_source as enum ('happy_call', 'admin_manual', 'app');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.credit_reason as enum (
    'task_completion',
    'review_bonus',
    'manual_adjustment',
    'redemption'
  );
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.call_direction as enum ('inbound', 'outbound');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.call_purpose as enum ('intake', 'match_confirmation', 'happy_call');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.notification_channel as enum ('kakao', 'sms', 'push', 'voice', 'email', 'in_app');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.notification_status as enum ('pending', 'sent', 'failed', 'skipped');
exception when duplicate_object then null;
end $$;

-- =========================
-- Utility trigger
-- =========================

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- =========================
-- Tables
-- =========================

create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users(id) on delete set null,
  role public.user_role not null default 'helper',
  name text not null,
  phone text unique,
  village text not null default '다로리',
  address_public text,
  address_detail text,
  latitude numeric(9,6),
  longitude numeric(9,6),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.help_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete restrict,
  approved_by uuid references public.profiles(id) on delete set null,
  source public.request_source not null default 'admin_manual',
  status public.help_request_status not null default 'pending_review',
  category public.help_category not null default 'other',
  title text not null,
  content text not null,
  items_provided boolean,
  items_needed_details text,
  appointment_time timestamptz,
  appointment_timezone text not null default 'Asia/Seoul',
  location_public text,
  location_detail text,
  credit_reward integer not null default 0 check (credit_reward >= 0),
  ai_extracted_payload jsonb,
  admin_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  approved_at timestamptz,
  published_at timestamptz
);

create table if not exists public.assignments (
  id uuid primary key default gen_random_uuid(),
  help_request_id uuid not null references public.help_requests(id) on delete cascade,
  helper_id uuid not null references public.profiles(id) on delete restrict,
  status public.assignment_status not null default 'accepted',
  accepted_at timestamptz not null default now(),
  completed_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.completion_proofs (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments(id) on delete cascade,
  image_path text not null,
  note text,
  status public.completion_proof_status not null default 'submitted',
  submitted_at timestamptz not null default now(),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz
);

create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null unique references public.assignments(id) on delete cascade,
  requester_id uuid not null references public.profiles(id) on delete restrict,
  helper_id uuid not null references public.profiles(id) on delete restrict,
  rating integer check (rating between 1 and 5),
  review_text text,
  source public.review_source not null default 'admin_manual',
  created_at timestamptz not null default now()
);

create table if not exists public.credit_ledger (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete restrict,
  assignment_id uuid references public.assignments(id) on delete set null,
  amount integer not null check (amount <> 0),
  reason public.credit_reason not null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.voice_calls (
  id uuid primary key default gen_random_uuid(),
  provider text,
  provider_call_id text unique,
  direction public.call_direction not null,
  phone text not null,
  requester_id uuid references public.profiles(id) on delete set null,
  help_request_id uuid references public.help_requests(id) on delete set null,
  purpose public.call_purpose not null,
  status text,
  transcript text,
  raw_payload jsonb,
  extracted_payload jsonb,
  confidence numeric(4,3) check (confidence is null or (confidence >= 0 and confidence <= 1)),
  confirmed_by_requester boolean,
  started_at timestamptz,
  ended_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_profile_id uuid references public.profiles(id) on delete set null,
  help_request_id uuid references public.help_requests(id) on delete cascade,
  assignment_id uuid references public.assignments(id) on delete cascade,
  channel public.notification_channel not null,
  purpose text not null,
  status public.notification_status not null default 'pending',
  payload jsonb,
  sent_at timestamptz,
  failed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.audit_events (
  id uuid primary key default gen_random_uuid(),
  actor_profile_id uuid references public.profiles(id) on delete set null,
  entity_type text not null,
  entity_id uuid not null,
  action text not null,
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz not null default now()
);

-- =========================
-- Triggers
-- =========================

drop trigger if exists set_profiles_updated_at on public.profiles;
create trigger set_profiles_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists set_help_requests_updated_at on public.help_requests;
create trigger set_help_requests_updated_at
before update on public.help_requests
for each row execute function public.set_updated_at();

drop trigger if exists set_assignments_updated_at on public.assignments;
create trigger set_assignments_updated_at
before update on public.assignments
for each row execute function public.set_updated_at();

-- =========================
-- Indexes
-- =========================

create index if not exists profiles_auth_user_id_idx on public.profiles(auth_user_id);
create index if not exists profiles_role_idx on public.profiles(role);
create index if not exists help_requests_status_idx on public.help_requests(status);
create index if not exists help_requests_requester_id_idx on public.help_requests(requester_id);
create index if not exists help_requests_appointment_time_idx on public.help_requests(appointment_time);
create index if not exists assignments_help_request_id_idx on public.assignments(help_request_id);
create index if not exists assignments_helper_id_idx on public.assignments(helper_id);
create index if not exists credit_ledger_profile_id_idx on public.credit_ledger(profile_id);
create index if not exists voice_calls_phone_idx on public.voice_calls(phone);

create unique index if not exists assignments_one_active_per_request_idx
on public.assignments(help_request_id)
where status in ('accepted', 'completed_submitted', 'confirmed', 'disputed');

create unique index if not exists credit_ledger_unique_assignment_reason_idx
on public.credit_ledger(assignment_id, profile_id, reason)
where assignment_id is not null;

-- =========================
-- Auth/profile helpers
-- =========================

create or replace function public.current_profile_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select id
  from public.profiles
  where auth_user_id = auth.uid()
  limit 1
$$;

create or replace function public.current_user_role()
returns public.user_role
language sql
stable
security definer
set search_path = public
as $$
  select role
  from public.profiles
  where auth_user_id = auth.uid()
  limit 1
$$;

create or replace function public.is_mediator()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_user_role() in ('mediator', 'admin'), false)
$$;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (auth_user_id, role, name, phone)
  values (
    new.id,
    'helper',
    coalesce(new.raw_user_meta_data ->> 'name', new.email, 'New user'),
    new.raw_user_meta_data ->> 'phone'
  )
  on conflict (auth_user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

-- =========================
-- Atomic app actions
-- =========================

create or replace function public.accept_help_request(p_help_request_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_helper_id uuid;
  v_assignment_id uuid;
begin
  v_helper_id := public.current_profile_id();

  if v_helper_id is null or public.current_user_role() <> 'helper' then
    raise exception 'Only helpers can accept help requests';
  end if;

  update public.help_requests
  set status = 'accepted',
      updated_at = now()
  where id = p_help_request_id
    and status = 'published';

  if not found then
    raise exception 'Request is not available for acceptance';
  end if;

  insert into public.assignments (help_request_id, helper_id, status)
  values (p_help_request_id, v_helper_id, 'accepted')
  returning id into v_assignment_id;

  return v_assignment_id;
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
  v_proof_id uuid;
begin
  v_helper_id := public.current_profile_id();

  select *
  into v_assignment
  from public.assignments
  where id = p_assignment_id
    and helper_id = v_helper_id
    and status = 'accepted';

  if not found then
    raise exception 'Assignment is not available for completion submission';
  end if;

  insert into public.completion_proofs (assignment_id, image_path, note)
  values (p_assignment_id, p_image_path, p_note)
  returning id into v_proof_id;

  update public.assignments
  set status = 'completed_submitted',
      completed_at = now()
  where id = p_assignment_id;

  update public.help_requests
  set status = 'completed_submitted'
  where id = v_assignment.help_request_id;

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
begin
  if not public.is_mediator() then
    raise exception 'Only mediators/admins can confirm and credit assignments';
  end if;

  v_actor_id := public.current_profile_id();

  select
    a.helper_id,
    h.requester_id,
    h.id,
    h.credit_reward
  into
    v_helper_id,
    v_requester_id,
    v_help_request_id,
    v_credit_reward
  from public.assignments a
  join public.help_requests h on h.id = a.help_request_id
  where a.id = p_assignment_id
    and a.status = 'completed_submitted';

  if not found then
    raise exception 'Assignment is not ready for confirmation';
  end if;

  update public.assignments
  set status = 'confirmed'
  where id = p_assignment_id;

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

  return v_credit_id;
end;
$$;

grant execute on function public.accept_help_request(uuid) to authenticated;
grant execute on function public.submit_completion(uuid, text, text) to authenticated;
grant execute on function public.confirm_assignment_and_credit(uuid, integer, text, public.review_source) to authenticated;

-- =========================
-- Row Level Security
-- =========================

alter table public.profiles enable row level security;
alter table public.help_requests enable row level security;
alter table public.assignments enable row level security;
alter table public.completion_proofs enable row level security;
alter table public.reviews enable row level security;
alter table public.credit_ledger enable row level security;
alter table public.voice_calls enable row level security;
alter table public.notifications enable row level security;
alter table public.audit_events enable row level security;

create policy profiles_select_own_or_admin
on public.profiles for select
to authenticated
using (auth_user_id = auth.uid() or public.is_mediator());

create policy profiles_insert_own
on public.profiles for insert
to authenticated
with check (auth_user_id = auth.uid());

create policy profiles_update_admin
on public.profiles for update
to authenticated
using (public.is_mediator())
with check (public.is_mediator());

create policy help_requests_select_admin_or_available_or_assigned
on public.help_requests for select
to authenticated
using (
  public.is_mediator()
  or status = 'published'
  or exists (
    select 1
    from public.assignments a
    where a.help_request_id = help_requests.id
      and a.helper_id = public.current_profile_id()
  )
);

create policy help_requests_insert_admin
on public.help_requests for insert
to authenticated
with check (public.is_mediator());

create policy help_requests_update_admin
on public.help_requests for update
to authenticated
using (public.is_mediator())
with check (public.is_mediator());

create policy assignments_select_own_or_admin
on public.assignments for select
to authenticated
using (
  public.is_mediator()
  or helper_id = public.current_profile_id()
);

create policy completion_proofs_select_own_or_admin
on public.completion_proofs for select
to authenticated
using (
  public.is_mediator()
  or exists (
    select 1
    from public.assignments a
    where a.id = completion_proofs.assignment_id
      and a.helper_id = public.current_profile_id()
  )
);

create policy reviews_select_related_or_admin
on public.reviews for select
to authenticated
using (
  public.is_mediator()
  or helper_id = public.current_profile_id()
  or requester_id = public.current_profile_id()
);

create policy credit_ledger_select_own_or_admin
on public.credit_ledger for select
to authenticated
using (
  public.is_mediator()
  or profile_id = public.current_profile_id()
);

create policy voice_calls_select_admin
on public.voice_calls for select
to authenticated
using (public.is_mediator());

create policy notifications_select_own_or_admin
on public.notifications for select
to authenticated
using (
  public.is_mediator()
  or recipient_profile_id = public.current_profile_id()
);

create policy audit_events_select_admin
on public.audit_events for select
to authenticated
using (public.is_mediator());

-- =========================
-- Storage bucket for completion images
-- =========================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'completion-proofs',
  'completion-proofs',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

create policy completion_proofs_storage_upload_authenticated
on storage.objects for insert
to authenticated
with check (bucket_id = 'completion-proofs');

create policy completion_proofs_storage_read_authenticated
on storage.objects for select
to authenticated
using (bucket_id = 'completion-proofs');
