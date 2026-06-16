\set ON_ERROR_STOP on

-- P0 backend smoke tests for local Supabase.
-- Run from porori-server with:
-- psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -f supabase/tests/p0_backend_smoke.sql

begin;

delete from public.admin_call_tasks where help_request_id in (
  '10000000-0000-4000-8000-000000000101',
  '10000000-0000-4000-8000-000000000102',
  '10000000-0000-4000-8000-000000000103',
  '10000000-0000-4000-8000-000000000104',
  '10000000-0000-4000-8000-000000000105',
  '10000000-0000-4000-8000-000000000106',
  '10000000-0000-4000-8000-000000000107'
);
delete from public.notifications where help_request_id in (
  '10000000-0000-4000-8000-000000000101',
  '10000000-0000-4000-8000-000000000102',
  '10000000-0000-4000-8000-000000000103',
  '10000000-0000-4000-8000-000000000104',
  '10000000-0000-4000-8000-000000000105',
  '10000000-0000-4000-8000-000000000106',
  '10000000-0000-4000-8000-000000000107'
);
delete from public.audit_events where actor_profile_id in (
  '10000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000004'
);
delete from public.credit_ledger where profile_id in (
  '10000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000004'
);
delete from public.reviews where assignment_id in (
  '10000000-0000-4000-8000-000000000201',
  '10000000-0000-4000-8000-000000000202',
  '10000000-0000-4000-8000-000000000203',
  '10000000-0000-4000-8000-000000000204',
  '10000000-0000-4000-8000-000000000205',
  '10000000-0000-4000-8000-000000000206',
  '10000000-0000-4000-8000-000000000207',
  '10000000-0000-4000-8000-000000000208',
  '10000000-0000-4000-8000-000000000209',
  '10000000-0000-4000-8000-000000000210'
);
delete from public.completion_proofs where assignment_id in (
  '10000000-0000-4000-8000-000000000201',
  '10000000-0000-4000-8000-000000000202',
  '10000000-0000-4000-8000-000000000203',
  '10000000-0000-4000-8000-000000000204',
  '10000000-0000-4000-8000-000000000205',
  '10000000-0000-4000-8000-000000000206',
  '10000000-0000-4000-8000-000000000207',
  '10000000-0000-4000-8000-000000000208',
  '10000000-0000-4000-8000-000000000209',
  '10000000-0000-4000-8000-000000000210'
);
delete from public.assignments where id in (
  '10000000-0000-4000-8000-000000000201',
  '10000000-0000-4000-8000-000000000202',
  '10000000-0000-4000-8000-000000000203',
  '10000000-0000-4000-8000-000000000204'
);
delete from public.help_requests where id in (
  '10000000-0000-4000-8000-000000000101',
  '10000000-0000-4000-8000-000000000102',
  '10000000-0000-4000-8000-000000000103',
  '10000000-0000-4000-8000-000000000104',
  '10000000-0000-4000-8000-000000000105',
  '10000000-0000-4000-8000-000000000106',
  '10000000-0000-4000-8000-000000000107'
);
delete from public.profiles where id in (
  '10000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000005',
  '10000000-0000-4000-8000-000000000006',
  '10000000-0000-4000-8000-000000000007',
  '10000000-0000-4000-8000-000000000011'
);
delete from auth.identities where user_id in (
  select id
  from auth.users
  where email in (
    'p0-admin@example.test',
    'p0-helper-a@example.test',
    'p0-helper-b@example.test',
    'p0-helper-c@example.test'
  )
);
delete from auth.users where id in (
  '10000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000004'
);
delete from auth.users where email in (
  'p0-admin@example.test',
  'p0-helper-a@example.test',
  'p0-helper-b@example.test',
  'p0-helper-c@example.test'
);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at, raw_user_meta_data)
values
  ('10000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'p0-admin@example.test', crypt('password123', gen_salt('bf')), now(), '{"name":"P0 Admin"}'),
  ('10000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'p0-helper-a@example.test', crypt('password123', gen_salt('bf')), now(), '{"name":"P0 Helper A"}'),
  ('10000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'p0-helper-b@example.test', crypt('password123', gen_salt('bf')), now(), '{"name":"P0 Helper B"}'),
  ('10000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'p0-helper-c@example.test', crypt('password123', gen_salt('bf')), now(), '{"name":"P0 Helper C"}');

update public.profiles
set id = '10000000-0000-4000-8000-000000000001',
    role = 'admin',
    name = 'P0 Admin',
    phone = '010-1000-0001',
    village = '다로리',
    address_public = '운영 사무실',
    address_detail = '운영 사무실 상세',
    latitude = 36.412000,
    longitude = 127.384000
where auth_user_id = '10000000-0000-4000-8000-000000000001';

update public.profiles
set id = '10000000-0000-4000-8000-000000000002',
    role = 'helper',
    name = 'P0 Helper A',
    phone = '010-1000-0002',
    village = '다로리',
    address_public = '청년회 A',
    address_detail = '청년회 A 상세',
    latitude = 36.412000,
    longitude = 127.384000
where auth_user_id = '10000000-0000-4000-8000-000000000002';

update public.profiles
set id = '10000000-0000-4000-8000-000000000003',
    role = 'helper',
    name = 'P0 Helper B',
    phone = '010-1000-0003',
    village = '다로리',
    address_public = '청년회 B',
    address_detail = '청년회 B 상세',
    latitude = 36.412100,
    longitude = 127.384100
where auth_user_id = '10000000-0000-4000-8000-000000000003';

update public.profiles
set id = '10000000-0000-4000-8000-000000000004',
    role = 'helper',
    name = 'P0 Helper C',
    phone = '010-1000-0004',
    village = '다로리',
    address_public = '청년회 C',
    address_detail = '청년회 C 상세',
    latitude = 36.412200,
    longitude = 127.384200
where auth_user_id = '10000000-0000-4000-8000-000000000004';

insert into public.profiles (id, auth_user_id, role, name, phone, village, address_public, address_detail, latitude, longitude)
values
  ('10000000-0000-4000-8000-000000000005', null, 'helper', 'P0 Helper D', '010-1000-0005', '다로리', '청년회 D', '청년회 D 상세', 36.412300, 127.384300),
  ('10000000-0000-4000-8000-000000000006', null, 'helper', 'P0 Helper E', '010-1000-0006', '다로리', '청년회 E', '청년회 E 상세', 36.412400, 127.384400),
  ('10000000-0000-4000-8000-000000000007', null, 'helper', 'P0 Helper F', '010-1000-0007', '다로리', '청년회 F', '청년회 F 상세', 36.412500, 127.384500);

insert into public.profiles (
  id,
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
  registered_by
)
values (
  '10000000-0000-4000-8000-000000000011',
  null,
  'requester',
  'P0 Requester',
  '010-1000-0011',
  '다로리',
  '테스트 공개 주소',
  '테스트 상세 주소',
  36.413000,
  127.385000,
  '천천히 안내 필요',
  true,
  true,
  true,
  '10000000-0000-4000-8000-000000000001'
);

insert into public.help_requests (
  id,
  requester_id,
  approved_by,
  source,
  status,
  category,
  title,
  content,
  appointment_time,
  location_public,
  location_detail,
  credit_reward,
  required_helpers,
  safety_tier,
  location_latitude,
  location_longitude,
  estimated_duration_minutes,
  approved_at,
  published_at
)
values
  ('10000000-0000-4000-8000-000000000101', '10000000-0000-4000-8000-000000000011', '10000000-0000-4000-8000-000000000001', 'admin_manual', 'published', 'daily_life', 'P0 Published New', 'new request', now() + interval '4 days', '테스트 공개 주소', '테스트 상세 주소', 0, 3, 'tier_3', 36.413000, 127.385000, 60, now(), now() - interval '47 hours'),
  ('10000000-0000-4000-8000-000000000102', '10000000-0000-4000-8000-000000000011', '10000000-0000-4000-8000-000000000001', 'admin_manual', 'published', 'daily_life', 'P0 Published Old', 'old request', now() + interval '4 days', '테스트 공개 주소', '테스트 상세 주소', 0, 3, 'tier_3', 36.413000, 127.385000, 60, now(), now() - interval '49 hours'),
  ('10000000-0000-4000-8000-000000000103', '10000000-0000-4000-8000-000000000011', null, 'admin_manual', 'pending_review', 'labor', 'P0 Pending', 'pending request', now() + interval '4 days', '테스트 공개 주소', '테스트 상세 주소', 0, 3, 'needs_review', 36.413000, 127.385000, 60, null, null),
  ('10000000-0000-4000-8000-000000000104', '10000000-0000-4000-8000-000000000011', '10000000-0000-4000-8000-000000000001', 'admin_manual', 'published', 'labor', 'P0 Batch Approval', 'batch request', now() + interval '4 days', '테스트 공개 주소', '테스트 상세 주소', 0, 3, 'tier_3', 36.413000, 127.385000, 60, now(), now()),
  ('10000000-0000-4000-8000-000000000105', '10000000-0000-4000-8000-000000000011', '10000000-0000-4000-8000-000000000001', 'admin_manual', 'accepted', 'electronics', 'P0 Completion', 'completion request', now() + interval '4 days', '테스트 공개 주소', '테스트 상세 주소', 0, 3, 'tier_3', 36.413000, 127.385000, 60, now(), now()),
  ('10000000-0000-4000-8000-000000000106', '10000000-0000-4000-8000-000000000011', '10000000-0000-4000-8000-000000000001', 'admin_manual', 'published', 'daily_life', 'P0 Locked Application', 'locked request', now() + interval '1 day', '테스트 공개 주소', '테스트 상세 주소', 0, 3, 'tier_3', 36.413000, 127.385000, 60, now(), now()),
  ('10000000-0000-4000-8000-000000000107', '10000000-0000-4000-8000-000000000011', '10000000-0000-4000-8000-000000000001', 'admin_manual', 'published', 'daily_life', 'P0 Capacity Full', 'capacity request', now() + interval '4 days', '테스트 공개 주소', '테스트 상세 주소', 0, 6, 'tier_3', 36.413000, 127.385000, 60, now(), now());

insert into public.assignments (id, help_request_id, helper_id, status, applied_at, accepted_at)
values
  ('10000000-0000-4000-8000-000000000201', '10000000-0000-4000-8000-000000000101', '10000000-0000-4000-8000-000000000002', 'applied', now(), null),
  ('10000000-0000-4000-8000-000000000202', '10000000-0000-4000-8000-000000000104', '10000000-0000-4000-8000-000000000002', 'applied', now(), null),
  ('10000000-0000-4000-8000-000000000203', '10000000-0000-4000-8000-000000000104', '10000000-0000-4000-8000-000000000003', 'applied', now(), null),
  ('10000000-0000-4000-8000-000000000204', '10000000-0000-4000-8000-000000000105', '10000000-0000-4000-8000-000000000002', 'accepted', now(), now()),
  ('10000000-0000-4000-8000-000000000205', '10000000-0000-4000-8000-000000000107', '10000000-0000-4000-8000-000000000002', 'applied', now(), null),
  ('10000000-0000-4000-8000-000000000206', '10000000-0000-4000-8000-000000000107', '10000000-0000-4000-8000-000000000003', 'applied', now(), null),
  ('10000000-0000-4000-8000-000000000207', '10000000-0000-4000-8000-000000000107', '10000000-0000-4000-8000-000000000004', 'applied', now(), null),
  ('10000000-0000-4000-8000-000000000208', '10000000-0000-4000-8000-000000000107', '10000000-0000-4000-8000-000000000005', 'applied', now(), null),
  ('10000000-0000-4000-8000-000000000209', '10000000-0000-4000-8000-000000000107', '10000000-0000-4000-8000-000000000006', 'applied', now(), null),
  ('10000000-0000-4000-8000-000000000210', '10000000-0000-4000-8000-000000000107', '10000000-0000-4000-8000-000000000007', 'applied', now(), null);

commit;

do $$
begin
  if public.calculate_help_credit('electronics', 60, 0, false) <> 15000 then
    raise exception 'Expected electronics one-hour base credit to be 15000';
  end if;

  if public.calculate_help_credit('daily_life', 60, 0, false) <> 18000 then
    raise exception 'Expected daily_life one-hour credit to be 18000';
  end if;

  if public.calculate_help_credit('labor', 180, 2000, true) <> 69510 then
    raise exception 'Expected labor credit with 2km and review bonus to be 69510';
  end if;
end $$;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
declare
  v_error text;
  v_requester_id uuid;
begin
  begin
    perform public.register_requester_profile(
      '동의누락 어르신',
      '010-1000-0098',
      '다로리',
      '공개 주소',
      '상세 주소',
      36.410000,
      127.380000,
      null,
      true,
      false,
      true,
      'consent-documents/test/missing.pdf'
    );
  exception when others then
    v_error := sqlerrm;
  end;

  if v_error is distinct from 'All required requester consents must be true' then
    raise exception 'Expected missing consent registration error, got %', v_error;
  end if;

  v_requester_id := public.register_requester_profile(
    '등록성공 어르신',
    '010-1000-0099',
    '다로리',
    '공개 주소',
    '상세 주소',
    36.410000,
    127.380000,
    '천천히 안내 필요',
    true,
    true,
    true,
    'consent-documents/test/success.pdf'
  );

  if not exists (
    select 1
    from public.profiles
    where id = v_requester_id
      and role = 'requester'
      and auth_user_id is null
      and registered_by = '10000000-0000-4000-8000-000000000001'
  ) then
    raise exception 'Expected requester profile with null auth_user_id and registered_by admin';
  end if;

  if not exists (
    select 1
    from public.audit_events
    where entity_id = v_requester_id
      and action = 'requester_registered'
  ) then
    raise exception 'Expected requester_registered audit event';
  end if;
end $$;

rollback;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
declare
  v_new_count integer;
  v_total_count integer;
  v_matched_visible boolean;
  v_matched_full boolean;
begin
  select count(*) into v_new_count
  from public.list_published_help_requests('latest', null, true, 50, 0, null, null, null)
  where id in (
    '10000000-0000-4000-8000-000000000101',
    '10000000-0000-4000-8000-000000000102'
  );

  select count(*) into v_total_count
  from public.list_published_help_requests('latest', null, false, 50, 0, null, null, null)
  where id in (
    '10000000-0000-4000-8000-000000000101',
    '10000000-0000-4000-8000-000000000102'
  );

  if v_new_count <> 1 or v_total_count <> 2 then
    raise exception 'Expected 48-hour NEW filter to include one of two requests, got new %, total %', v_new_count, v_total_count;
  end if;

  select exists (
    select 1
    from public.list_published_help_requests('latest', null, false, 50, 0, null, null, null)
    where id = '10000000-0000-4000-8000-000000000105'
  )
  into v_matched_visible;

  select is_full
  into v_matched_full
  from public.list_published_help_requests('latest', null, false, 50, 0, null, null, null)
  where id = '10000000-0000-4000-8000-000000000105';

  if v_matched_visible is not true or v_matched_full is not true then
    raise exception 'Expected accepted requests to remain visible as full/closed in helper feed';
  end if;
end $$;

do $$
declare
  v_error text;
begin
  begin
    perform public.apply_help_request('10000000-0000-4000-8000-000000000106');
  exception when others then
    v_error := sqlerrm;
  end;

  if v_error is distinct from 'Application period has ended' then
    raise exception 'Expected day-of application lock, got %', v_error;
  end if;
end $$;

do $$
declare
  v_pending_requester jsonb;
  v_pending_request jsonb;
  v_pending_companions jsonb;
  v_accepted_requester jsonb;
  v_accepted_request jsonb;
  v_accepted_companions jsonb;
  v_detail record;
begin
  select rows.requester, rows.help_request, rows.companion_helpers
  into v_pending_requester, v_pending_request, v_pending_companions
  from public.list_my_helper_assignments() rows
  where rows.assignment ->> 'id' = '10000000-0000-4000-8000-000000000201';

  if v_pending_requester ->> 'phone' is not null
    or v_pending_requester ->> 'address_detail' is not null
    or v_pending_requester ->> 'personal_notes' is not null
    or v_pending_request ->> 'location_detail' is not null
    or jsonb_array_length(v_pending_companions) <> 0 then
    raise exception 'Expected pending helper assignment to mask requester private fields';
  end if;

  select rows.requester, rows.help_request, rows.companion_helpers
  into v_accepted_requester, v_accepted_request, v_accepted_companions
  from public.list_my_helper_assignments() rows
  where rows.assignment ->> 'id' = '10000000-0000-4000-8000-000000000204';

  if v_accepted_requester ->> 'phone' is distinct from '010-1000-0011'
    or v_accepted_requester ->> 'address_detail' is distinct from '테스트 상세 주소'
    or v_accepted_requester ->> 'personal_notes' is distinct from '천천히 안내 필요'
    or v_accepted_request ->> 'location_detail' is distinct from '테스트 상세 주소'
    or jsonb_array_length(v_accepted_companions) = 0 then
    raise exception 'Expected accepted helper assignment to include requester private fields';
  end if;

  select *
  into v_detail
  from public.get_help_request_detail('10000000-0000-4000-8000-000000000101', null, null);

  if v_detail.requester_phone is not null
    or v_detail.requester_address_detail is not null
    or v_detail.requester_personal_notes is not null
    or v_detail.location_detail is not null
    or v_detail.can_apply is not false
    or v_detail.apply_block_reason is distinct from 'already_applied' then
    raise exception 'Expected pending helper detail to mask private fields and block duplicate apply, got %', row_to_json(v_detail);
  end if;

  select *
  into v_detail
  from public.get_help_request_detail('10000000-0000-4000-8000-000000000105', null, null);

  if v_detail.requester_phone is distinct from '010-1000-0011'
    or v_detail.requester_address_detail is distinct from '테스트 상세 주소'
    or v_detail.requester_personal_notes is distinct from '천천히 안내 필요'
    or v_detail.location_detail is distinct from '테스트 상세 주소'
    or v_detail.can_apply is not false
    or v_detail.apply_block_reason is distinct from 'already_applied' then
    raise exception 'Expected accepted helper detail to reveal private fields and block reapply, got %', row_to_json(v_detail);
  end if;
end $$;

select public.cancel_help_application('10000000-0000-4000-8000-000000000201');

do $$
begin
  if (
    select status
    from public.assignments
    where id = '10000000-0000-4000-8000-000000000201'
  ) <> 'cancelled' then
    raise exception 'Expected helper cancellation to mark assignment cancelled';
  end if;
end $$;

rollback;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000003', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
declare
  v_detail record;
begin
  select *
  into v_detail
  from public.get_help_request_detail('10000000-0000-4000-8000-000000000101', null, null);

  if v_detail.can_apply is not true
    or v_detail.apply_block_reason is not null
    or v_detail.requester_phone is not null
    or v_detail.requester_address_detail is not null
    or v_detail.requester_personal_notes is not null then
    raise exception 'Expected unrelated helper to be able to apply while private fields stay masked, got %', row_to_json(v_detail);
  end if;

  select *
  into v_detail
  from public.get_help_request_detail('10000000-0000-4000-8000-000000000106', null, null);

  if v_detail.can_apply is not false
    or v_detail.apply_block_reason is distinct from 'deadline_passed' then
    raise exception 'Expected locked detail to block application by deadline, got %', row_to_json(v_detail);
  end if;

  select *
  into v_detail
  from public.get_help_request_detail('10000000-0000-4000-8000-000000000107', null, null);

  if v_detail.can_apply is not false
    or v_detail.apply_block_reason is distinct from 'already_applied'
    or v_detail.applied_count <> 6 then
    raise exception 'Expected capacity request detail to expose count and current application status, got %', row_to_json(v_detail);
  end if;
end $$;

rollback;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select public.admin_update_help_request(
  '10000000-0000-4000-8000-000000000103',
  '{
    "title": "P0 Pending Updated",
    "content": "pending request updated",
    "category": "labor",
    "estimated_duration_minutes": 60,
    "required_helpers": 3,
    "safety_tier": "needs_review",
    "location_public": "테스트 공개 주소"
  }'::jsonb
);

do $$
begin
  if (
    select credit_reward
    from public.help_requests
    where id = '10000000-0000-4000-8000-000000000103'
  ) <> 22500 then
    raise exception 'Expected admin update to recalculate one-hour labor credit to 22500';
  end if;
end $$;

do $$
declare
  v_error text;
begin
  begin
    perform public.review_help_request('10000000-0000-4000-8000-000000000103', 'published', null);
  exception when others then
    v_error := sqlerrm;
  end;

  if v_error is distinct from 'Request is missing required publish fields or has unresolved safety risk' then
    raise exception 'Expected unresolved safety publish error, got %', v_error;
  end if;
end $$;

do $$
declare
  v_state record;
  v_refreshed integer;
begin
  select *
  into v_state
  from public.get_help_request_matching_state('10000000-0000-4000-8000-000000000107');

  if v_state.minimum_helpers <> 3
    or v_state.capacity_helpers <> 6
    or v_state.active_count <> 6
    or v_state.capacity_full is not true
    or v_state.approval_ready is not true then
    raise exception 'Expected capacity-full request to be approval ready, got %', row_to_json(v_state);
  end if;

  if v_state.application_deadline is distinct from (
    select appointment_time - interval '48 hours'
    from public.help_requests
    where id = '10000000-0000-4000-8000-000000000107'
  ) then
    raise exception 'Expected application deadline to be appointment minus 48 hours';
  end if;

  if (
    select count(*)
    from public.notifications
    where help_request_id = '10000000-0000-4000-8000-000000000107'
      and purpose = 'matching_capacity_full'
  ) <> 1 then
    raise exception 'Expected one idempotent capacity-full admin alert';
  end if;

  v_refreshed := public.refresh_matching_operational_alerts();

  if v_refreshed < 1 then
    raise exception 'Expected refresh to create at least one deadline alert';
  end if;

  perform public.refresh_matching_operational_alerts();

  if (
    select count(*)
    from public.notifications
    where help_request_id = '10000000-0000-4000-8000-000000000106'
      and purpose = 'matching_deadline_must_fail'
  ) <> 1 then
    raise exception 'Expected one idempotent deadline must-fail admin alert';
  end if;
end $$;

do $$
declare
  v_approved integer;
  v_task_id uuid;
begin
  v_approved := public.approve_all_assignments_for_request('10000000-0000-4000-8000-000000000104');

  if v_approved <> 2 then
    raise exception 'Expected approve-all to approve 2 assignments, got %', v_approved;
  end if;

  if (
    select count(*)
    from public.assignments
    where help_request_id = '10000000-0000-4000-8000-000000000104'
      and status = 'accepted'
  ) <> 2 then
    raise exception 'Expected two accepted assignments after approve-all';
  end if;

  perform public.finalize_help_request_match(
    '10000000-0000-4000-8000-000000000104',
    '테스트 부족 인원 진행'
  );

  if (
    select status
    from public.help_requests
    where id = '10000000-0000-4000-8000-000000000104'
  ) <> 'accepted' then
    raise exception 'Expected underfilled finalization to mark request accepted';
  end if;

  if (
    select count(*)
    from public.admin_call_tasks
    where help_request_id = '10000000-0000-4000-8000-000000000104'
      and purpose = 'match_confirmation'
  ) <> 1 then
    raise exception 'Expected exactly one admin match confirmation call task';
  end if;

  if (
    select count(*)
    from public.notifications
    where help_request_id = '10000000-0000-4000-8000-000000000104'
      and purpose = 'match_finalized'
  ) <> 2 then
    raise exception 'Expected exactly one match-finalized notification per accepted helper';
  end if;

  select id
  into v_task_id
  from public.admin_call_tasks
  where help_request_id = '10000000-0000-4000-8000-000000000104'
    and purpose = 'match_confirmation';

  if (
    select call_script
    from public.admin_call_tasks
    where id = v_task_id
  ) not like '%청년 2명이 방문하는 것으로 확정되었습니다%' then
    raise exception 'Expected admin call task script to include accepted helper count';
  end if;

  perform public.log_admin_call_no_answer(v_task_id, '1차 통화 부재중');

  if (
    select status
    from public.admin_call_tasks
    where id = v_task_id
  ) <> 'pending' then
    raise exception 'Expected no-answer attempt to keep admin call task pending';
  end if;

  if (
    select no_answer_count
    from public.admin_call_tasks
    where id = v_task_id
  ) <> 1 then
    raise exception 'Expected no-answer attempt to increment count';
  end if;

  perform public.complete_admin_call_task(v_task_id, '어르신 통화 완료');

  if (
    select status
    from public.admin_call_tasks
    where id = v_task_id
  ) <> 'completed' then
    raise exception 'Expected admin call task to be marked completed';
  end if;
end $$;

rollback;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

do $$
declare
  v_error text;
begin
  begin
    perform public.submit_completion('10000000-0000-4000-8000-000000000204', 'proofs/test.jpg', null);
  exception when others then
    v_error := sqlerrm;
  end;

  if v_error is distinct from 'Completion review text is required' then
    raise exception 'Expected mandatory completion text error, got %', v_error;
  end if;
end $$;

select public.submit_completion(
  '10000000-0000-4000-8000-000000000204',
  'proofs/test.jpg',
  '완료했습니다.'
);

commit;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claim.role', 'authenticated', true);

select public.confirm_assignment_and_credit(
  '10000000-0000-4000-8000-000000000204',
  5,
  '관리자 확인 완료',
  'admin_manual'
);

select public.confirm_assignment_and_credit(
  '10000000-0000-4000-8000-000000000204',
  5,
  '관리자 확인 완료',
  'admin_manual'
);

do $$
begin
  if (
    select coalesce(sum(amount), 0)
    from public.credit_ledger
    where assignment_id = '10000000-0000-4000-8000-000000000204'
  ) <> 15010 then
    raise exception 'Expected one 15000 task credit plus one 10 review bonus';
  end if;
end $$;

rollback;

select 'P0 backend smoke tests passed' as result;
