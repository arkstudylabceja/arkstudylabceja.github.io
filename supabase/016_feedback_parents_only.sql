-- ============================================================================
-- 016_feedback_parents_only.sql
--
-- 목적: 선생님 코칭 피드백을 "학생"이 아니라 "학부모"만 볼 수 있게 바꿈.
--   - 학생: 피드백을 볼 수 없음
--   - 학부모: 자녀 기록에 대해 '보낸(published)' 피드백만 조회
--   - 관리자: 기존과 같음 (전체 권한)
--
-- 실행 방법: Supabase 대시보드 → SQL Editor → 전체 붙여넣기 → Run
-- 실행 전: 015가 먼저 실행되어 있어야 함
-- ============================================================================

-- 헬퍼: uid가 이 기록 학생의 학부모인지
create or replace function public.is_parent_of_study_log(target_log_id uuid, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.study_logs log
    where log.id = target_log_id
      and public.is_parent_of(uid, log.student_id)
  );
$$;

revoke all on function public.is_parent_of_study_log(uuid, uuid) from public;
grant execute on function public.is_parent_of_study_log(uuid, uuid) to authenticated;

-- 기존 "학생·학부모 조회" 정책을 "학부모만 조회"로 교체
drop policy if exists "study_log_feedback_select_published" on public.study_log_feedback;
drop policy if exists "study_log_feedback_select_parent" on public.study_log_feedback;
create policy "study_log_feedback_select_parent" on public.study_log_feedback
  for select using (
    status = 'published'
    and public.is_parent_of_study_log(log_id, auth.uid())
  );

do $$
begin
  if to_regclass('public._migrations_applied') is not null then
    insert into public._migrations_applied (filename)
    values ('016_feedback_parents_only.sql')
    on conflict (filename) do nothing;
  end if;
end $$;
