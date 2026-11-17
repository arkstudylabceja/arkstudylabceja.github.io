-- ============================================================================
-- 017_apply_missing_012_014.sql
--
-- 점검(check_applied.sql) 결과 012, 013, 014가 데이터베이스에 빠져 있어서
-- 한 번에 적용하는 파일.
--
--  - 012 중 "학부모가 자녀 프로필(이름)을 볼 수 있는 정책"만 적용.
--    "같은 인증방 학생끼리 서로의 프로필 전체를 볼 수 있는 정책"은 적용하지 않음.
--    (학생끼리 이메일·학부모 이메일까지 보이게 되므로. 팀원 이름은 나중에
--     이름만 돌려주는 전용 함수로 따로 해결할 예정)
--  - 013 전체 적용 (인증방 배정 함수 + 한 학생 한 인증방 제약)
--    이미 두 인증방에 동시에 배정된 학생이 있으면 아무것도 바꾸지 않고 멈춤.
--  - 014 전체 적용 (적용 기록표)
--
-- 실행 방법: Supabase 대시보드 → SQL Editor → 전체 붙여넣기 → Run
-- ============================================================================

-- ---------- 012 (일부): 학부모 → 자녀 프로필 조회 ----------
drop policy if exists "select child profile for parent" on public.profiles;
create policy "select child profile for parent" on public.profiles
  for select using (public.is_parent_of(auth.uid(), id));

-- ---------- 013: 한 학생은 한 인증방에만 ----------
do $$
declare
  dup_count integer;
begin
  select count(*) into dup_count from (
    select student_id from public.team_members group by student_id having count(*) > 1
  ) d;
  if dup_count > 0 then
    raise exception '두 인증방에 동시에 배정된 학생이 %명 있어서 멈췄어요. 이 화면을 Claude에게 보여주세요.', dup_count;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'team_members_student_id_key'
  ) then
    alter table public.team_members
      add constraint team_members_student_id_key unique (student_id);
  end if;
end $$;

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

-- ---------- 014: 적용 기록표 ----------
create table if not exists public._migrations_applied (
  filename text primary key,
  applied_at timestamptz not null default now()
);

alter table public._migrations_applied enable row level security;

insert into public._migrations_applied (filename) values
  ('000_create_profiles.sql'),
  ('000_existing_schema_baseline.sql'),
  ('001_admin_role_and_hardening.sql'),
  ('002_study_logs.sql'),
  ('003_teams.sql'),
  ('004_fix_team_membership_rls.sql'),
  ('005_team_post_images.sql'),
  ('006_study_log_images.sql'),
  ('007_private_image_access_helpers.sql'),
  ('008_guardian_consent.sql'),
  ('009_account_management.sql'),
  ('010_guardian_consent_hardening.sql'),
  ('011_account_status_write_enforcement.sql'),
  ('013_prevent_duplicate_team_assignment.sql'),
  ('014_migration_tracking.sql'),
  ('015_study_log_feedback.sql'),
  ('016_feedback_parents_only.sql'),
  ('017_apply_missing_012_014.sql')
on conflict (filename) do nothing;
