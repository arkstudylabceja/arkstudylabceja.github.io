-- ============================================================================
-- 012_profile_visibility_for_relations.sql
--
-- 문제: profiles 테이블의 select 정책은 "본인 행" 또는 "관리자"만 허용했음.
--       그래서 team.html/admin-teams.html이 팀원 이름을 가져오려고
--       team_members.select('student_id, profiles(name)') 같은 조인을 해도,
--       본인 행이 아닌 팀원의 profiles는 RLS에 막혀 null로 돌아옴 →
--       화면에 "(알 수 없음)"으로 표시됨. parent.html의 자녀 학습기록
--       목록에서도 같은 이유로 자녀 이름이 안 나옴(자녀가 여러 명일 때 구분 불가).
--
-- 해결: "같은 인증방 소속(팀원)" 관계와 "학부모-자녀" 관계에 한해 서로의 프로필을
--       조회할 수 있는 select 정책을 추가함. is_parent_of()는 001에서 이미 만든
--       함수를 재사용하고, "같은 팀 소속인지"를 확인하는 are_teammates() 함수를
--       새로 추가함(무한 재귀 방지를 위해 security definer로 team_members를 직접 조회).
--
-- 참고(트레이드오프): 이 정책은 이름뿐 아니라 profiles 행 전체(이메일, 계정 상태 등)를
--       열람 가능하게 함. 화면에서는 이름만 쓰고 있지만, 팀원이 직접 API를 호출하면
--       팀원의 이메일 등도 볼 수 있게 된다는 점은 참고해두세요. 더 좁게 제한하려면
--       (이름만 반환하는 전용 RPC로 교체) 나중에 별도로 강화할 수 있습니다.
--
-- 실행 방법: Supabase 대시보드 → SQL Editor → 전체 붙여넣기 → Run
-- 실행 전: 001, 004가 먼저 실행되어 있어야 함
-- ============================================================================

create or replace function public.are_teammates(uid1 uuid, uid2 uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.team_members me
    join public.team_members them on me.team_id = them.team_id
    where me.student_id = uid1 and them.student_id = uid2
  );
$$;

revoke all on function public.are_teammates(uuid, uuid) from public;
grant execute on function public.are_teammates(uuid, uuid) to authenticated;

drop policy if exists "select teammate profile" on public.profiles;
create policy "select teammate profile" on public.profiles
  for select using (public.are_teammates(auth.uid(), id));

drop policy if exists "select child profile for parent" on public.profiles;
create policy "select child profile for parent" on public.profiles
  for select using (public.is_parent_of(auth.uid(), id));
