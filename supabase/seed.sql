-- DOUM / Porori MVP demo seed data.
-- This seeds workflow records and non-login demo profiles.
-- For real login testing, sign up through the app and promote those profiles.

insert into public.profiles (
  id,
  auth_user_id,
  role,
  name,
  phone,
  village,
  address_public,
  address_detail
)
values
  (
    '00000000-0000-4000-8000-000000000001',
    null,
    'admin',
    'Demo Admin',
    '010-9000-0001',
    '다로리',
    '다로리 마을회관',
    '다로리 마을회관 사무실'
  ),
  (
    '00000000-0000-4000-8000-000000000002',
    null,
    'helper',
    'Demo Helper',
    '010-9000-0002',
    '다로리',
    '다로리 청년회',
    '다로리 청년회 사무실'
  ),
  (
    '00000000-0000-4000-8000-000000000101',
    null,
    'requester',
    '김점순 어르신',
    '010-9000-0101',
    '다로리',
    '다로리 동쪽',
    '다로리 12번지'
  ),
  (
    '00000000-0000-4000-8000-000000000102',
    null,
    'requester',
    '박말례 어르신',
    '010-9000-0102',
    '다로리',
    '다로리 서쪽',
    '다로리 34번지'
  ),
  (
    '00000000-0000-4000-8000-000000000103',
    null,
    'requester',
    '이순자 어르신',
    '010-9000-0103',
    '다로리',
    '다로리 회관 근처',
    '회관 뒤 흰 대문집'
  ),
  (
    '00000000-0000-4000-8000-000000000104',
    null,
    'requester',
    '최복례 어르신',
    '010-9000-0104',
    '다로리',
    '다로리 남쪽',
    '버스정류장 옆집'
  ),
  (
    '00000000-0000-4000-8000-000000000105',
    null,
    'requester',
    '정옥분 어르신',
    '010-9000-0105',
    '다로리',
    '다로리 북쪽',
    '감나무 밭 옆집'
  )
on conflict (id) do update
set role = excluded.role,
    name = excluded.name,
    phone = excluded.phone,
    village = excluded.village,
    address_public = excluded.address_public,
    address_detail = excluded.address_detail;

insert into public.help_requests (
  id,
  requester_id,
  approved_by,
  source,
  status,
  category,
  title,
  content,
  items_provided,
  items_needed_details,
  appointment_time,
  location_public,
  location_detail,
  credit_reward,
  ai_extracted_payload,
  admin_notes,
  approved_at,
  published_at
)
values
  (
    '00000000-0000-4000-8000-000000001001',
    '00000000-0000-4000-8000-000000000101',
    null,
    'voice',
    'pending_review',
    'labor',
    '마당 화분 옮기기',
    '큰 화분 5개를 마당에서 하우스로 옮기는 일손 요청입니다.',
    true,
    '장갑과 손수레는 어르신 댁에 있습니다.',
    now() + interval '2 days',
    '다로리 동쪽',
    '다로리 12번지',
    20,
    '{"confirmed_by_requester": true, "confidence": 0.92}'::jsonb,
    'Seed demo pending voice request.',
    null,
    null
  ),
  (
    '00000000-0000-4000-8000-000000001002',
    '00000000-0000-4000-8000-000000000102',
    '00000000-0000-4000-8000-000000000001',
    'admin_manual',
    'published',
    'daily_life',
    '형광등 갈기',
    '부엌 형광등을 새 전구로 갈아 끼워달라는 요청입니다.',
    true,
    '새 형광등은 싱크대 옆에 준비되어 있습니다.',
    now() + interval '3 days',
    '다로리 서쪽',
    '다로리 34번지',
    10,
    null,
    'Seed demo published request.',
    now() - interval '2 hours',
    now() - interval '2 hours'
  ),
  (
    '00000000-0000-4000-8000-000000001003',
    '00000000-0000-4000-8000-000000000103',
    '00000000-0000-4000-8000-000000000001',
    'admin_manual',
    'accepted',
    'mobility_care',
    '병원 동행',
    '보건소 방문길에 동행이 필요합니다.',
    false,
    '청년이 우산을 챙겨오면 좋습니다.',
    now() + interval '1 day',
    '다로리 회관 근처',
    '회관 뒤 흰 대문집',
    15,
    null,
    'Seed demo accepted request.',
    now() - interval '4 hours',
    now() - interval '4 hours'
  ),
  (
    '00000000-0000-4000-8000-000000001004',
    '00000000-0000-4000-8000-000000000104',
    '00000000-0000-4000-8000-000000000001',
    'admin_manual',
    'completed_submitted',
    'household',
    '마당 정리',
    '마당에 쌓인 빈 박스와 폐비닐을 정리하는 요청입니다.',
    true,
    '끈과 장갑은 준비되어 있습니다.',
    now() - interval '1 day',
    '다로리 남쪽',
    '버스정류장 옆집',
    25,
    null,
    'Seed demo completion waiting for admin confirmation.',
    now() - interval '2 days',
    now() - interval '2 days'
  ),
  (
    '00000000-0000-4000-8000-000000001005',
    '00000000-0000-4000-8000-000000000105',
    '00000000-0000-4000-8000-000000000001',
    'admin_manual',
    'credited',
    'electronics',
    '리모컨 설정',
    'TV 리모컨과 셋톱박스 연결을 다시 설정한 완료 요청입니다.',
    true,
    '리모컨과 셋톱박스는 거실에 있습니다.',
    now() - interval '3 days',
    '다로리 북쪽',
    '감나무 밭 옆집',
    10,
    null,
    'Seed demo credited request.',
    now() - interval '5 days',
    now() - interval '5 days'
  )
on conflict (id) do update
set status = excluded.status,
    title = excluded.title,
    content = excluded.content,
    appointment_time = excluded.appointment_time,
    location_public = excluded.location_public,
    location_detail = excluded.location_detail,
    credit_reward = excluded.credit_reward,
    admin_notes = excluded.admin_notes,
    approved_at = excluded.approved_at,
    published_at = excluded.published_at;

insert into public.assignments (
  id,
  help_request_id,
  helper_id,
  status,
  accepted_at,
  completed_at
)
values
  (
    '00000000-0000-4000-8000-000000002003',
    '00000000-0000-4000-8000-000000001003',
    '00000000-0000-4000-8000-000000000002',
    'accepted',
    now() - interval '3 hours',
    null
  ),
  (
    '00000000-0000-4000-8000-000000002004',
    '00000000-0000-4000-8000-000000001004',
    '00000000-0000-4000-8000-000000000002',
    'completed_submitted',
    now() - interval '2 days',
    now() - interval '1 hour'
  ),
  (
    '00000000-0000-4000-8000-000000002005',
    '00000000-0000-4000-8000-000000001005',
    '00000000-0000-4000-8000-000000000002',
    'confirmed',
    now() - interval '5 days',
    now() - interval '4 days'
  )
on conflict (id) do update
set status = excluded.status,
    accepted_at = excluded.accepted_at,
    completed_at = excluded.completed_at;

insert into public.completion_proofs (
  id,
  assignment_id,
  image_path,
  note,
  status,
  submitted_at
)
values
  (
    '00000000-0000-4000-8000-000000003004',
    '00000000-0000-4000-8000-000000002004',
    'demo/completed-submitted.jpg',
    '박스와 폐비닐 정리 완료했습니다.',
    'submitted',
    now() - interval '1 hour'
  ),
  (
    '00000000-0000-4000-8000-000000003005',
    '00000000-0000-4000-8000-000000002005',
    'demo/credited.jpg',
    'TV 리모컨 설정 완료했습니다.',
    'approved',
    now() - interval '4 days'
  )
on conflict (id) do update
set image_path = excluded.image_path,
    note = excluded.note,
    status = excluded.status,
    submitted_at = excluded.submitted_at;

insert into public.credit_ledger (
  id,
  profile_id,
  assignment_id,
  amount,
  reason,
  created_by,
  created_at
)
values (
  '00000000-0000-4000-8000-000000004005',
  '00000000-0000-4000-8000-000000000002',
  '00000000-0000-4000-8000-000000002005',
  10,
  'task_completion',
  '00000000-0000-4000-8000-000000000001',
  now() - interval '4 days'
)
on conflict (id) do update
set amount = excluded.amount,
    reason = excluded.reason,
    created_by = excluded.created_by,
    created_at = excluded.created_at;

insert into public.reviews (
  id,
  assignment_id,
  requester_id,
  helper_id,
  rating,
  review_text,
  source,
  created_at
)
values (
  '00000000-0000-4000-8000-000000005005',
  '00000000-0000-4000-8000-000000002005',
  '00000000-0000-4000-8000-000000000105',
  '00000000-0000-4000-8000-000000000002',
  5,
  '싹싹하게 잘 도와주었습니다.',
  'admin_manual',
  now() - interval '4 days'
)
on conflict (assignment_id) do update
set rating = excluded.rating,
    review_text = excluded.review_text,
    source = excluded.source,
    created_at = excluded.created_at;

insert into public.voice_calls (
  id,
  provider,
  provider_call_id,
  direction,
  phone,
  requester_id,
  help_request_id,
  purpose,
  status,
  transcript,
  extracted_payload,
  confidence,
  confirmed_by_requester,
  ended_at
)
values (
  '00000000-0000-4000-8000-000000006001',
  'vapi',
  'seed-demo-call-001',
  'inbound',
  '010-9000-0101',
  '00000000-0000-4000-8000-000000000101',
  '00000000-0000-4000-8000-000000001001',
  'intake',
  'assistant-ended-call',
  '어르신께서 큰 화분 5개를 하우스로 옮겨달라고 요청하셨습니다.',
  '{"category": "일손", "title": "마당 화분 옮기기", "confirmed_by_requester": true}'::jsonb,
  0.92,
  true,
  now() - interval '30 minutes'
)
on conflict (provider_call_id) do update
set transcript = excluded.transcript,
    extracted_payload = excluded.extracted_payload,
    confidence = excluded.confidence,
    confirmed_by_requester = excluded.confirmed_by_requester,
    ended_at = excluded.ended_at;

insert into public.notifications (
  id,
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
    '00000000-0000-4000-8000-000000007001',
    null,
    '00000000-0000-4000-8000-000000001001',
    null,
    'in_app',
    'voice_request_created',
    'pending',
    '{"title": "마당 화분 옮기기", "source": "seed_demo"}'::jsonb
  ),
  (
    '00000000-0000-4000-8000-000000007002',
    '00000000-0000-4000-8000-000000000002',
    '00000000-0000-4000-8000-000000001002',
    null,
    'in_app',
    'request_published',
    'pending',
    '{"title": "형광등 갈기", "source": "seed_demo"}'::jsonb
  ),
  (
    '00000000-0000-4000-8000-000000007003',
    null,
    '00000000-0000-4000-8000-000000001003',
    '00000000-0000-4000-8000-000000002003',
    'in_app',
    'request_accepted',
    'pending',
    '{"title": "병원 동행", "helper_name": "Demo Helper", "source": "seed_demo"}'::jsonb
  )
on conflict (id) do update
set purpose = excluded.purpose,
    payload = excluded.payload;
