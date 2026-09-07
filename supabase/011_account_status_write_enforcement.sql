-- ============================================================================
-- 011_account_status_write_enforcement.sql
--
-- 문제: 관리자가 계정을 정지(account_status='suspended')시켜도, 그건 화면(JS)에서만
--       막고 있었음. study_logs / team_posts에 새 글을 쓰는 insert 정책은
--       account_status를 전혀 확인하지 않아서, 이미 열려있는 브라우저 탭이나
--       API를 직접 호출하면 정지된 계정도 계속 글을 쓸 수 있었음.
--
-- 해결: "정지되지 않은 본인"인지 확인하는 is_active() 함수를 추가하고,
--       학생이 새 글을 쓰는 insert 정책에 이 조건을 추가함.
--       (조회/삭제까지 막지는 않음 — 정지된 계정이 과거 기록을 보거나 지우는 것까지
--        막을 필요는 없다고 판단, "새로 쓰는 것"만 차단)
--
-- 실행 방법: Supabase 대시보드 → SQL Editor → 전체 붙여넣기 → Run
-- 실행 전: 002, 004, 009가 먼저 실행되어 있어야 함
-- ============================================================================

create or replace function public.is_active(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select account_status = 'active' from public.profiles where id = uid),
    false
  );
$$;

revoke all on function public.is_active(uuid) from public;
grant execute on function public.is_active(uuid) to authenticated;

-- study_logs: 새 기록 작성 시 정지 여부 확인
drop policy if exists "study_logs_insert_own" on public.study_logs;
create policy "study_logs_insert_own" on public.study_logs
  for insert with check (
    auth.uid() = student_id
    and public.is_active(auth.uid())
  );

drop policy if exists "study_logs_update_own" on public.study_logs;
create policy "study_logs_update_own" on public.study_logs
  for update using (
    auth.uid() = student_id
    and public.is_active(auth.uid())
  );

-- team_posts: 새 인증 게시물 작성 시 정지 여부 확인
drop policy if exists "team_posts_insert_own" on public.team_posts;
create policy "team_posts_insert_own" on public.team_posts
  for insert with check (
    auth.uid() = student_id
    and public.is_team_member(team_id, auth.uid())
    and public.is_active(auth.uid())
  );
