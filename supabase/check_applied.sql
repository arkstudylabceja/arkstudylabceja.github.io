-- ============================================================================
-- check_applied.sql  (점검용 · 아무것도 바꾸지 않고 확인만 함)
--
-- 001~016 SQL 파일이 데이터베이스에 적용되어 있는지,
-- 각 파일이 만드는 대표 항목이 있는지로 확인함.
-- 실행 방법: Supabase 대시보드 → SQL Editor → 전체 붙여넣기 → Run
-- ============================================================================

select 파일,
       case when 적용 then '✅ 적용됨' else '❌ 빠짐' end as 상태
from (values
  ('001_admin_role_and_hardening',
     exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'is_admin')
     and exists (select 1 from pg_trigger where tgname = 'trg_prevent_role_escalation')),
  ('002_study_logs',
     to_regclass('public.study_logs') is not null),
  ('003_teams',
     to_regclass('public.teams') is not null),
  ('004_fix_team_membership_rls',
     exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'is_team_member')),
  ('005_team_post_images',
     exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'team_posts' and column_name = 'image_path')),
  ('006_study_log_images',
     exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'study_logs' and column_name = 'image_path')),
  ('007_private_image_access_helpers',
     exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'can_access_study_log_image')),
  ('008_guardian_consent',
     exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'approve_child_consent')),
  ('009_account_management',
     to_regclass('public.account_deletion_requests') is not null),
  ('010_guardian_consent_hardening',
     exists (select 1 from pg_trigger where tgname = 'trg_prevent_guardian_consent_self_change')),
  ('011_account_status_write_enforcement',
     exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'study_logs'
             and policyname = 'study_logs_insert_own' and with_check ilike '%is_active%')),
  ('012_profile_visibility_for_relations',
     exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'are_teammates')),
  ('013_prevent_duplicate_team_assignment',
     exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'admin_assign_student_to_team')),
  ('014_migration_tracking',
     to_regclass('public._migrations_applied') is not null),
  ('015_study_log_feedback',
     to_regclass('public.study_log_feedback') is not null),
  ('016_feedback_parents_only',
     exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'study_log_feedback'
             and policyname = 'study_log_feedback_select_parent'))
) as t(파일, 적용)
order by 파일;
