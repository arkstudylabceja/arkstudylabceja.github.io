-- ============================================================================
-- 000_existing_schema_baseline.sql
--
-- 목적: 지금 라이브 Supabase 프로젝트에 이미 존재하는 profiles 테이블의
--       실제 상태(컬럼/RLS 정책/트리거)를 "조회만" 해서 코드로 남겨두는 파일.
--       이 파일 자체는 아무것도 바꾸지 않는다 (전부 select문).
--
-- 사용법:
--   1) Supabase 대시보드 → SQL Editor → New query
--   2) 아래 SQL 전체를 붙여넣고 Run
--   3) 각 쿼리 결과를 이 파일 맨 아래 "실행 결과 기록" 섹션에 붙여넣고 저장/커밋
--      (Claude에게도 결과를 붙여넣어 공유하면 001 스크립트를 실제 상태에 맞게 조정할 수 있음)
-- ============================================================================

-- 1) profiles 테이블 컬럼 목록/타입 확인
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_name = 'profiles'
order by ordinal_position;

-- 2) profiles에 걸린 RLS 정책 목록 확인
select policyname, cmd, qual, with_check
from pg_policies
where tablename = 'profiles';

-- 3) profiles 테이블에 RLS가 켜져 있는지 확인 (relrowsecurity가 true여야 안전)
select relname, relrowsecurity
from pg_class
where relname = 'profiles';

-- 4) auth.users에 걸린 트리거 확인
--    (회원가입 시 auth.users -> profiles로 자동 insert해주는 트리거가 있을 것으로 추정됨)
select tgname, pg_get_triggerdef(oid)
from pg_trigger
where tgrelid = 'auth.users'::regclass
  and not tgisinternal;

-- 5) profiles.role에 걸린 체크 제약 확인 (parent/student만 허용 중인지, admin 추가 전 상태 확인용)
select conname, pg_get_constraintdef(oid)
from pg_constraint
where conrelid = 'public.profiles'::regclass
  and contype = 'c';

-- ============================================================================
-- 실행 결과 기록 (여기에 위 쿼리들 결과를 붙여넣어 두세요)
-- ============================================================================
--
-- 1) 컬럼 목록:
--   (여기에 결과 붙여넣기)
--
-- 2) RLS 정책 목록:
--   (여기에 결과 붙여넣기)
--
-- 3) RLS 활성화 여부:
--   (여기에 결과 붙여넣기)
--
-- 4) auth.users 트리거:
--   (여기에 결과 붙여넣기)
--
-- 5) role 체크 제약:
--   (여기에 결과 붙여넣기)
--
