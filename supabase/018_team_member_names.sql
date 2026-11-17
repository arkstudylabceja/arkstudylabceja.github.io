-- ============================================================================
-- 018_team_member_names.sql
--
-- 문제: 인증방(team.html)에서 팀원 이름이 "(알 수 없음)"으로 나옴.
--       학생은 다른 학생의 profiles 행을 볼 수 없기 때문.
--       (012의 "팀원 프로필 전체 조회" 정책은 이메일·학부모 이메일까지
--        보이게 되어 적용하지 않았음)
--
-- 해결: 같은 인증방 사람들의 "이름만" 돌려주는 함수를 만듦.
--       - 그 인증방 소속 학생이거나 관리자만 호출 가능
--       - 현재 팀원 + 그 인증방에 글을 남긴 적이 있는 학생의 이름
--
-- 실행 방법: Supabase 대시보드 → SQL Editor → 전체 붙여넣기 → Run
-- 실행 전: 001, 003, 004가 먼저 실행되어 있어야 함
-- ============================================================================

create or replace function public.get_team_member_names(target_team_id uuid)
returns table (student_id uuid, name text)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.name
  from public.profiles p
  where (public.is_team_member(target_team_id, auth.uid()) or public.is_admin(auth.uid()))
    and p.id in (
      select tm.student_id from public.team_members tm where tm.team_id = target_team_id
      union
      select tp.student_id from public.team_posts tp where tp.team_id = target_team_id
    );
$$;

revoke all on function public.get_team_member_names(uuid) from public;
grant execute on function public.get_team_member_names(uuid) to authenticated;

do $$
begin
  if to_regclass('public._migrations_applied') is not null then
    insert into public._migrations_applied (filename)
    values ('018_team_member_names.sql')
    on conflict (filename) do nothing;
  end if;
end $$;
