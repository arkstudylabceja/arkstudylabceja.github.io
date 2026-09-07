-- ============================================================================
-- 013_prevent_duplicate_team_assignment.sql
--
-- 문제: admin-teams.html에서 학생을 인증방에 배정할 때, 새 team_members 행을
--       먼저 insert하고 나서 이전 인증방 소속 행을 별도로 delete하는 2단계로
--       처리하고 있었음. 중간에 delete가 실패하면(네트워크 문제 등) 학생이
--       두 인증방에 동시에 남게 되는데, team.html/student.html은 학생이
--       인증방 하나에만 속한다고 가정(.maybeSingle())하고 있어서 이 경우
--       에러가 나고, 화면에는 "배정된 인증방이 없어요"로 잘못 표시됨.
--
-- 해결: "이전 인증방에서 빼고 새 인증방에 넣기"를 하나의 트랜잭션(함수)으로
--       묶어서, 중간에 실패해도 부분 반영되지 않게 함. 추가로 student_id에
--       유니크 제약을 걸어 어떤 경로로든 한 학생이 동시에 두 인증방에
--       들어가는 것 자체를 DB가 막도록 함.
--
-- 실행 방법: Supabase 대시보드 → SQL Editor → 전체 붙여넣기 → Run
-- 실행 전: 001, 003이 먼저 실행되어 있어야 함
-- 참고: 만약 지금 이미 두 인증방에 동시 배정된 학생이 있다면, 아래 유니크
--       제약 추가 단계에서 에러가 날 수 있습니다. 에러가 나면 알려주세요 —
--       어느 학생이 중복 배정됐는지 먼저 확인하고 정리하는 쿼리를 드릴게요.
-- ============================================================================

alter table public.team_members
  add constraint team_members_student_id_key unique (student_id);

create or replace function public.admin_assign_student_to_team(
  target_student_id uuid,
  target_team_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin(auth.uid()) then
    raise exception '관리자만 인증방을 배정할 수 있습니다';
  end if;

  delete from public.team_members
  where student_id = target_student_id and team_id <> target_team_id;

  insert into public.team_members (team_id, student_id)
  values (target_team_id, target_student_id)
  on conflict (student_id) do update set team_id = excluded.team_id;
end;
$$;

revoke all on function public.admin_assign_student_to_team(uuid, uuid) from public;
grant execute on function public.admin_assign_student_to_team(uuid, uuid) to authenticated;
