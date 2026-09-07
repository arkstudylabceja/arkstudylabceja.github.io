-- ============================================================================
-- 014_migration_tracking.sql
--
-- 목적: 지금까지 SQL Editor에서 수동으로 실행해온 파일들을 "이미 적용됨"으로
--       기록해두는 표를 만듦. 이제부터는 GitHub Actions가 이 표를 보고
--       "아직 적용 안 된 새 SQL 파일"만 자동으로 실행해줌.
--
-- 이 파일은 사용자가 SQL Editor에서 직접 실행하는 "마지막 수동 실행"이 됨.
-- 010~014를 순서대로 실행한 뒤부터는, 새 SQL 파일을 만들어서 깃허브에 푸시하면
-- 자동으로 실행됨 (.github/workflows/apply-sql-migrations.yml 참고).
--
-- 실행 방법: Supabase 대시보드 → SQL Editor → 전체 붙여넣기 → Run
-- 실행 전: 010, 011, 012, 013을 먼저 실행해두세요 (순서대로)
-- ============================================================================

create table if not exists public._migrations_applied (
  filename text primary key,
  applied_at timestamptz not null default now()
);

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
  ('012_profile_visibility_for_relations.sql'),
  ('013_prevent_duplicate_team_assignment.sql'),
  ('014_migration_tracking.sql')
on conflict (filename) do nothing;
