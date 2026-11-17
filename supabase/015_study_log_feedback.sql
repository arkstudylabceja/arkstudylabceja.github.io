-- ============================================================================
-- 015_study_log_feedback.sql
--
-- 목적: 학생이 개인 자료실에 남긴 학습 기록(study_logs)에 선생님(관리자)이
--       코칭 피드백을 남기고, 학생·학부모가 그 피드백을 볼 수 있게 함.
--
-- 구조:
--   - 피드백은 study_logs와 "별도 표"에 저장함.
--     (study_logs는 학생 본인이 수정할 수 있어서, 같은 표에 두면 학생이
--      선생님 피드백을 고칠 수 있게 되기 때문)
--   - 기록 1개당 피드백 1개 (log_id가 기본키)
--   - status = 'draft'     : 선생님만 보는 임시 저장
--     status = 'published' : 학생·학부모에게 보이는 피드백
--   - 2단계(자동 분석)의 AI 초안은 학생에게 절대 보이면 안 되므로
--     이 표가 아니라 관리자 전용 표를 따로 만들 예정.
--
-- 권한:
--   - 관리자: 전체 조회/작성/수정/삭제
--   - 학생: 본인 기록에 대한 'published' 피드백만 조회
--   - 학부모: 자녀 기록에 대한 'published' 피드백만 조회
--
-- 실행 방법: Supabase 대시보드 → SQL Editor → 전체 붙여넣기 → Run
-- 실행 전: 001, 002가 먼저 실행되어 있어야 함
--          (011의 is_active() 함수는 이 파일 안에서도 똑같이 만들어 둠)
-- ============================================================================

create table if not exists public.study_log_feedback (
  log_id uuid primary key references public.study_logs(id) on delete cascade,
  body text not null default '',
  status text not null default 'draft' check (status in ('draft', 'published')),
  updated_by uuid,  -- 마지막으로 수정한 관리자 id (profiles와 직접 연결하지 않음: 기존 화면의 profiles 불러오기와 충돌 방지)
  updated_at timestamptz not null default now(),
  published_at timestamptz
);

create index if not exists study_log_feedback_status_idx
  on public.study_log_feedback (status, updated_at desc);

alter table public.study_log_feedback enable row level security;

-- 헬퍼: 정지되지 않은 계정인지 (011과 동일한 정의. 011을 아직 실행하지 않았어도 되도록)
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

-- 헬퍼: uid가 이 기록의 학생 본인 또는 학부모인지
create or replace function public.can_view_study_log(target_log_id uuid, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.study_logs log
    where log.id = target_log_id
      and (
        log.student_id = uid
        or public.is_parent_of(uid, log.student_id)
      )
  );
$$;

revoke all on function public.can_view_study_log(uuid, uuid) from public;
grant execute on function public.can_view_study_log(uuid, uuid) to authenticated;

-- 관리자: 전체 권한 (정지되지 않은 관리자만 작성/수정)
drop policy if exists "study_log_feedback_admin_select" on public.study_log_feedback;
create policy "study_log_feedback_admin_select" on public.study_log_feedback
  for select using (public.is_admin(auth.uid()));

drop policy if exists "study_log_feedback_admin_insert" on public.study_log_feedback;
create policy "study_log_feedback_admin_insert" on public.study_log_feedback
  for insert with check (
    public.is_admin(auth.uid())
    and public.is_active(auth.uid())
  );

drop policy if exists "study_log_feedback_admin_update" on public.study_log_feedback;
create policy "study_log_feedback_admin_update" on public.study_log_feedback
  for update using (
    public.is_admin(auth.uid())
    and public.is_active(auth.uid())
  ) with check (
    public.is_admin(auth.uid())
    and public.is_active(auth.uid())
  );

drop policy if exists "study_log_feedback_admin_delete" on public.study_log_feedback;
create policy "study_log_feedback_admin_delete" on public.study_log_feedback
  for delete using (public.is_admin(auth.uid()));

-- 학생·학부모: 보낸(published) 피드백만 조회
drop policy if exists "study_log_feedback_select_published" on public.study_log_feedback;
create policy "study_log_feedback_select_published" on public.study_log_feedback
  for select using (
    status = 'published'
    and public.can_view_study_log(log_id, auth.uid())
  );

grant select, insert, update, delete on public.study_log_feedback to authenticated;

-- 마이그레이션 기록표(014)가 있으면 적용 기록 남기기
do $$
begin
  if to_regclass('public._migrations_applied') is not null then
    insert into public._migrations_applied (filename)
    values ('015_study_log_feedback.sql')
    on conflict (filename) do nothing;
  end if;
end $$;
