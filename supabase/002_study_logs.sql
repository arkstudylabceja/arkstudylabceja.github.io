-- ============================================================================
-- 002_study_logs.sql
--
-- 목적: 학생이 매일 공부한 내용을 기록하는 "학습 포트폴리오" 테이블 생성.
--       001에서 만든 is_admin() / is_parent_of() 함수를 그대로 재사용.
--
-- 실행 방법: Supabase 대시보드 → SQL Editor → 전체 붙여넣기 → Run
-- 실행 전: 000, 001을 먼저 실행해둔 상태여야 함 (is_admin/is_parent_of 함수 필요)
-- ============================================================================

create table if not exists public.study_logs (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  study_date date not null default current_date,
  subject text,
  content text not null,
  minutes_spent integer,
  created_at timestamptz not null default now()
);

create index if not exists study_logs_student_date_idx
  on public.study_logs (student_id, study_date desc);

alter table public.study_logs enable row level security;

-- 본인 기록: 조회/작성/수정/삭제
drop policy if exists "study_logs_select_own" on public.study_logs;
create policy "study_logs_select_own" on public.study_logs
  for select using (auth.uid() = student_id);

drop policy if exists "study_logs_insert_own" on public.study_logs;
create policy "study_logs_insert_own" on public.study_logs
  for insert with check (auth.uid() = student_id);

drop policy if exists "study_logs_update_own" on public.study_logs;
create policy "study_logs_update_own" on public.study_logs
  for update using (auth.uid() = student_id);

drop policy if exists "study_logs_delete_own" on public.study_logs;
create policy "study_logs_delete_own" on public.study_logs
  for delete using (auth.uid() = student_id);

-- 부모: 본인 자녀의 기록만 조회 가능
drop policy if exists "study_logs_select_parent" on public.study_logs;
create policy "study_logs_select_parent" on public.study_logs
  for select using (public.is_parent_of(auth.uid(), student_id));

-- 관리자: 전체 조회 가능
drop policy if exists "study_logs_select_admin" on public.study_logs;
create policy "study_logs_select_admin" on public.study_logs
  for select using (public.is_admin(auth.uid()));
