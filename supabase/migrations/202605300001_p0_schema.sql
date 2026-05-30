-- P0 requirements schema additions.
-- O-1 requester consent fields, O-2 review fields, H-2 feed metadata,
-- application statuses, and credit-calculation inputs.

do $$ begin
  create type public.safety_tier as enum ('tier_1', 'tier_2', 'tier_3', 'needs_review');
exception when duplicate_object then null;
end $$;

alter type public.assignment_status add value if not exists 'applied';
alter type public.assignment_status add value if not exists 'rejected';

alter table public.profiles
  add column if not exists personal_notes text,
  add column if not exists consent_info boolean,
  add column if not exists consent_voice boolean,
  add column if not exists consent_photo boolean,
  add column if not exists consent_doc_url text,
  add column if not exists registered_by uuid;

do $$ begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_registered_by_fkey'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_registered_by_fkey
      foreign key (registered_by)
      references public.profiles(id)
      on delete set null;
  end if;
end $$;

alter table public.help_requests
  add column if not exists required_helpers integer not null default 3,
  add column if not exists safety_tier public.safety_tier not null default 'needs_review',
  add column if not exists reject_reason text,
  add column if not exists rejected_at timestamptz,
  add column if not exists location_latitude numeric(9,6),
  add column if not exists location_longitude numeric(9,6),
  add column if not exists estimated_duration_minutes integer not null default 60;

alter table public.assignments
  add column if not exists applied_at timestamptz not null default now();

alter table public.assignments
  alter column accepted_at drop not null;

alter table public.assignments
  alter column accepted_at drop default;

update public.assignments
set applied_at = coalesce(accepted_at, created_at, now())
where applied_at is null;

update public.help_requests
set required_helpers = least(greatest(coalesce(required_helpers, 3), 3), 6),
    estimated_duration_minutes = greatest(coalesce(estimated_duration_minutes, 60), 15);

do $$ begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'help_requests_required_helpers_range'
      and conrelid = 'public.help_requests'::regclass
  ) then
    alter table public.help_requests
      add constraint help_requests_required_helpers_range
      check (required_helpers between 3 and 6);
  end if;
end $$;

do $$ begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'help_requests_estimated_duration_positive'
      and conrelid = 'public.help_requests'::regclass
  ) then
    alter table public.help_requests
      add constraint help_requests_estimated_duration_positive
      check (estimated_duration_minutes > 0);
  end if;
end $$;

create index if not exists help_requests_published_at_idx
on public.help_requests(published_at desc)
where status = 'published';

create index if not exists help_requests_location_idx
on public.help_requests(location_latitude, location_longitude);

create index if not exists profiles_requester_phone_idx
on public.profiles(phone)
where role = 'requester';

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'consent-documents',
  'consent-documents',
  false,
  10485760,
  array['application/pdf', 'image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

drop policy if exists consent_documents_storage_admin_upload on storage.objects;
create policy consent_documents_storage_admin_upload
on storage.objects for insert
to authenticated
with check (bucket_id = 'consent-documents' and public.is_mediator());

drop policy if exists consent_documents_storage_admin_read on storage.objects;
create policy consent_documents_storage_admin_read
on storage.objects for select
to authenticated
using (bucket_id = 'consent-documents' and public.is_mediator());
