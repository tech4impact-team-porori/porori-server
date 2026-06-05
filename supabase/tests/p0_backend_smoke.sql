\set ON_ERROR_STOP on

-- P0 backend smoke tests for local Supabase.
-- Run from porori-server with:
-- psql postgresql://postgres:postgres@127.0.0.1:54322/postgres -f supabase/tests/p0_backend_smoke.sql

begin;

delete from public.notifications where help_request_id in (
  '10000000-0000-4000-8000-000000000101',
  '10000000-0000-4000-8000-000000000102',
  '10000000-0000-4000-8000-000000000103',
  '10000000-0000-4000-8000-000000000104',
  '10000000-0000-4000-8000-000000000105',
  '10000000-0000-4000-8000-000000000106'
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
  '10000000-0000-4000-8000-000000000204'
);
delete from public.completion_proofs where assignment_id in (
  '10000000-0000-4000-8000-000000000201',
  '10000000-0000-4000-8000-000000000202',
  '10000000-0000-4000-8000-000000000203',
  '10000000-0000-4000-8000-000000000204'
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
  '10000000-0000-4000-8000-000000000106'
);
delete from public.profiles where id in (
  '10000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000004',
  '10000000-0000-4000-8000-000000000011'
);
delete from auth.users where id in (
  '10000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000003',
  '10000000-0000-4000-8000-000000000004'
);

insert into auth.users (id, aud, role, email, encrypted_password, email_confirmed_at, raw_user_meta_data)
values
  ('10000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'p0-admin@example.test', 'test', now(), '{"name":"P0 Admin"}'),
  ('10000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'p0-helper-a@example.test', 'test', now(), '{"name":"P0 Helper A"}'),
  ('10000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'p0-helper-b@example.test', 'test', now(), '{"name":"P0 Helper B"}'),
  ('10000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'p0-helper-c@example.test', 'test', now(), '{"name":"P0 Helper C"}');

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
  ('10000000-0000-4000-8000-000000000101', '10000000-0000-4000-8000-000000000011', '10000000-0000-4000-8000-000000000001', 'admin_manual', 'published', 'daily_life', 'P0 Published New', 'new request', now() + interval '2 days', '테스트 공개 주소', '테스트 상세 주소', 0, 3, 'tier_3', 36.413000, 127.385000, 60, now(), now() - interval '47 hours'),
  ('10000000-0000-4000-8000-000000000102', '10000000-0000-4000-8000-000000000011', '10000000-0000-4000-8000-000000000001', 'admin_manual', 'published', 'daily_life', 'P0 Published Old', 'old request', now() + interval '2 days', '테스트 공개 주소', '테스트 상세 주소', 0, 3, 'tier_3', 36.413000, 127.385000, 60, now(), now() - interval '49 hours'),
  ('10000000-0000-4000-8000-000000000103', '10000000-0000-4000-8000-000000000011', null, 'admin_manual', 'pending_review', 'labor', 'P0 Pending', 'pending request', now() + interval '2 days', '테스트 공개 주소', '테스트 상세 주소', 0, 3, 'needs_review', 36.413000, 127.385000, 60, null, null),
  ('10000000-0000-4000-8000-000000000104', '10000000-0000-4000-8000-000000000011', '10000000-0000-4000-8000-000000000001', 'admin_manual', 'published', 'labor', 'P0 Batch Approval', 'batch request', now() + interval '2 days', '테스트 공개 주소', '테스트 상세 주소', 0, 3, 'tier_3', 36.413000, 127.385000, 60, now(), now()),
  ('10000000-0000-4000-8000-000000000105', '10000000-0000-4000-8000-000000000011', '10000000-0000-4000-8000-000000000001', 'admin_manual', 'accepted', 'electronics', 'P0 Completion', 'completion request', now() + interval '2 days', '테스트 공개 주소', '테스트 상세 주소', 0, 3, 'tier_3', 36.413000, 127.385000, 60, now(), now()),
  ('10000000-0000-4000-8000-000000000106', '10000000-0000-4000-8000-000000000011', '10000000-0000-4000-8000-000000000001', 'admin_manual', 'published', 'daily_life', 'P0 Locked Application', 'locked request', now(), '테스트 공개 주소', '테스트 상세 주소', 0, 3, 'tier_3', 36.413000, 127.385000, 60, now(), now());

insert into public.assignments (id, help_request_id, helper_id, status, applied_at, accepted_at)
values
  ('10000000-0000-4000-8000-000000000201', '10000000-0000-4000-8000-000000000101', '10000000-0000-4000-8000-000000000002', 'applied', now(), null),
  ('10000000-0000-4000-8000-000000000202', '10000000-0000-4000-8000-000000000104', '10000000-0000-4000-8000-000000000002', 'applied', now(), null),
  ('10000000-0000-4000-8000-000000000203', '10000000-0000-4000-8000-000000000104', '10000000-0000-4000-8000-000000000003', 'applied', now(), null),
  ('10000000-0000-4000-8000-000000000204', '10000000-0000-4000-8000-000000000105', '10000000-0000-4000-8000-000000000002', 'accepted', now(), now());

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
  v_approved integer;
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
