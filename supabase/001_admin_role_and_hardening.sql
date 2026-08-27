-- ============================================================================
-- 001_admin_role_and_hardening.sql
--
-- 목적:
--   1) profiles.role에 'admin'을 추가 (Phase 2 관리자 대시보드의 전제조건)
--   2) 이후 모든 Phase의 RLS 정책이 재사용할 헬퍼 함수 2개 생성
--   3) role 셀프 승격(학생이 자기를 admin으로 바꾸는 것) 방지
--   4) profiles 테이블 RLS를 "본인만 조회/수정, admin은 전체" 로 정비
--   5) student.html이 부모의 수강 상태를 안전하게 조회할 수 있는 RPC 제공
--      (RLS를 좁히면 student.html의 기존 "부모 profiles 직접 select" 코드가
--       더 이상 통과하지 못하므로, 이 RPC로 교체해야 함 — login.html/student.html도 같이 수정)
--
-- 실행 방법: Supabase 대시보드 → SQL Editor → New query → 전체 붙여넣기 → Run
-- 실행 순서: 000_existing_schema_baseline.sql로 현재 상태를 먼저 확인한 뒤 실행 권장
-- ============================================================================

-- 1) role 체크 제약에 'admin' 추가
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check check (role in ('parent', 'student', 'admin'));

-- 2) 헬퍼 함수: 이 uid가 admin인지
create or replace function public.is_admin(uid uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles where id = uid and role = 'admin'
  );
$$;

-- 3) 헬퍼 함수: parent_uid가 student_uid의 부모가 맞는지
--    (student.parent_email == parent.email 로 연결되는 기존 구조 그대로 사용)
create or replace function public.is_parent_of(parent_uid uuid, student_uid uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles s
    join public.profiles p on p.email = s.parent_email and p.role = 'parent'
    where s.id = student_uid and p.id = parent_uid
  );
$$;

-- 4) role 셀프 승격 방지: 웹사이트를 통해 로그인한 사람이 자기 role을 바꾸는 것만 차단.
--    SQL Editor(대시보드)에서 직접 실행할 때는 auth.uid()가 없으므로 통과시킴
--    (관리자 계정을 처음 만들 때는 SQL Editor를 쓸 수밖에 없기 때문)
create or replace function public.prevent_role_self_escalation()
returns trigger
language plpgsql
as $$
begin
  if new.role <> old.role and auth.uid() is not null and not public.is_admin(auth.uid()) then
    raise exception 'role 변경은 관리자만 할 수 있습니다';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_role_escalation on public.profiles;
create trigger trg_prevent_role_escalation
  before update on public.profiles
  for each row
  execute function public.prevent_role_self_escalation();

-- 5) profiles RLS 켜기 (이미 켜져 있어도 안전 — 재실행 가능)
alter table public.profiles enable row level security;

-- 기존 정책이 있다면 이름을 몰라 정리 못 할 수 있으니, 아래 정책 이름으로 재정의
drop policy if exists "select own profile" on public.profiles;
create policy "select own profile" on public.profiles
  for select
  using (auth.uid() = id);

drop policy if exists "admin select all profiles" on public.profiles;
create policy "admin select all profiles" on public.profiles
  for select
  using (public.is_admin(auth.uid()));

drop policy if exists "update own profile" on public.profiles;
create policy "update own profile" on public.profiles
  for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

drop policy if exists "admin update any profile" on public.profiles;
create policy "admin update any profile" on public.profiles
  for update
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

-- insert 정책: 회원가입 트리거(또는 signup 흐름)가 본인 id로 행을 만들 수 있게 허용
drop policy if exists "insert own profile" on public.profiles;
create policy "insert own profile" on public.profiles
  for insert
  with check (auth.uid() = id);

-- 6) student.html에서 쓸 RPC: 내 부모의 이름/수강완료 여부만 딱 반환
create or replace function public.get_my_parent_status()
returns table(parent_name text, course_completed boolean)
language sql
security definer
set search_path = public
as $$
  select p.name, p.course_completed
  from public.profiles p
  join public.profiles s on s.parent_email = p.email and p.role = 'parent'
  where s.id = auth.uid();
$$;

-- ============================================================================
-- 관리자 계정 만들기 (아래 UPDATE는 자동 실행되지 않음 — 본인 이메일로 바꿔서 직접 실행)
-- 먼저 signup.html에서 일반 계정으로 가입한 뒤, 그 계정을 admin으로 승격시키는 방식
-- ============================================================================
-- update public.profiles set role = 'admin' where email = '본인이메일@example.com';
