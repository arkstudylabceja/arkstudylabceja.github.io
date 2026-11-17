-- ============================================================================
-- 019_ai_drafts.sql
--
-- 목적: 2단계 자동 분석. 매일 정해진 시간에 Claude가 새 학습 기록(사진 포함)을
--       분석해서 "학부모님께 보낼 코칭 초안"과 "선생님용 메모"를 써둠.
--       선생님은 관리자 화면에서 초안을 확인·수정한 뒤 보내기만 하면 됨.
--
-- 구조:
--   - 'analyst' 역할 추가: 분석 전용 계정. 홈페이지 가입으로는 절대 만들 수 없고
--     (handle_new_user는 parent/student만 허용), 이 SQL로만 지정 가능.
--   - study_log_ai_drafts: AI 초안 표. 관리자만 볼 수 있음. 학생·학부모는 볼 수 없음.
--   - 분석 계정이 할 수 있는 일 (함수로만):
--       get_logs_needing_ai_draft() : 초안이 필요한 기록 목록 (+ 같은 학생의 최근 기록)
--       save_ai_draft()             : 초안 저장
--       공부 사진 읽기 (can_access_study_log_image에 analyst 추가)
--
-- 실행 방법: Supabase 대시보드 → SQL Editor → 전체 붙여넣기 → Run
-- 실행 전: 001, 002, 006, 007, 015가 먼저 실행되어 있어야 함
-- ============================================================================

-- 1) 역할에 analyst 추가
alter table public.profiles drop constraint if exists profiles_role_check;
alter table public.profiles
  add constraint profiles_role_check check (role in ('parent', 'student', 'admin', 'analyst'));

create or replace function public.is_analyst(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = uid and role = 'analyst' and coalesce(account_status, 'active') = 'active'
  );
$$;

revoke all on function public.is_analyst(uuid) from public;
grant execute on function public.is_analyst(uuid) to authenticated;

-- 2) AI 초안 표 (관리자만 조회)
create table if not exists public.study_log_ai_drafts (
  log_id uuid primary key references public.study_logs(id) on delete cascade,
  draft_for_parent text not null,
  teacher_notes text,
  model text,
  created_at timestamptz not null default now()
);

alter table public.study_log_ai_drafts enable row level security;

drop policy if exists "study_log_ai_drafts_admin_select" on public.study_log_ai_drafts;
create policy "study_log_ai_drafts_admin_select" on public.study_log_ai_drafts
  for select using (public.is_admin(auth.uid()));

drop policy if exists "study_log_ai_drafts_admin_delete" on public.study_log_ai_drafts;
create policy "study_log_ai_drafts_admin_delete" on public.study_log_ai_drafts
  for delete using (public.is_admin(auth.uid()));

grant select, delete on public.study_log_ai_drafts to authenticated;

-- 3) 분석 계정: 초안이 필요한 기록 목록
--    최근 max_days일 안에 올라온 기록 중, AI 초안도 없고 선생님 코칭도 아직 안 보낸 것
create or replace function public.get_logs_needing_ai_draft(max_days integer default 7, max_rows integer default 30)
returns table (
  log_id uuid,
  student_name text,
  study_date date,
  subject text,
  content text,
  minutes_spent integer,
  image_path text,
  created_at timestamptz,
  previous_logs jsonb,
  previous_feedback jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_analyst(auth.uid()) then
    raise exception '분석 계정만 사용할 수 있습니다';
  end if;

  return query
  select
    l.id,
    p.name,
    l.study_date,
    l.subject,
    l.content,
    l.minutes_spent,
    l.image_path,
    l.created_at,
    coalesce((
      select jsonb_agg(jsonb_build_object(
               'study_date', x.study_date, 'subject', x.subject,
               'content', x.content, 'minutes_spent', x.minutes_spent)
             order by x.study_date desc)
      from (
        select pl.study_date, pl.subject, pl.content, pl.minutes_spent
        from public.study_logs pl
        where pl.student_id = l.student_id and pl.created_at < l.created_at
        order by pl.created_at desc
        limit 5
      ) x
    ), '[]'::jsonb),
    coalesce((
      select jsonb_agg(jsonb_build_object('published_at', y.published_at, 'body', y.body)
             order by y.published_at desc)
      from (
        select f.published_at, f.body
        from public.study_log_feedback f
        join public.study_logs fl on fl.id = f.log_id
        where fl.student_id = l.student_id and f.status = 'published'
        order by f.published_at desc
        limit 3
      ) y
    ), '[]'::jsonb)
  from public.study_logs l
  join public.profiles p on p.id = l.student_id
  where l.created_at > now() - make_interval(days => greatest(max_days, 1))
    and not exists (select 1 from public.study_log_ai_drafts d where d.log_id = l.id)
    and not exists (select 1 from public.study_log_feedback f where f.log_id = l.id and f.status = 'published')
  order by l.created_at asc
  limit greatest(least(max_rows, 100), 1);
end;
$$;

revoke all on function public.get_logs_needing_ai_draft(integer, integer) from public;
grant execute on function public.get_logs_needing_ai_draft(integer, integer) to authenticated;

-- 4) 분석 계정: 초안 저장
create or replace function public.save_ai_draft(
  target_log_id uuid,
  draft text,
  notes text default null,
  model_name text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_analyst(auth.uid()) then
    raise exception '분석 계정만 사용할 수 있습니다';
  end if;
  if draft is null or length(trim(draft)) = 0 then
    raise exception '초안 내용이 비어 있습니다';
  end if;

  insert into public.study_log_ai_drafts (log_id, draft_for_parent, teacher_notes, model, created_at)
  values (target_log_id, left(draft, 4000), left(notes, 4000), left(model_name, 100), now())
  on conflict (log_id) do update set
    draft_for_parent = excluded.draft_for_parent,
    teacher_notes = excluded.teacher_notes,
    model = excluded.model,
    created_at = now();
end;
$$;

revoke all on function public.save_ai_draft(uuid, text, text, text) from public;
grant execute on function public.save_ai_draft(uuid, text, text, text) to authenticated;

-- 5) 공부 사진 읽기 권한에 분석 계정 추가 (007의 함수를 그대로 두고 analyst만 추가)
create or replace function public.can_access_study_log_image(object_name text, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.study_logs log
    where log.image_path = object_name
      and (
        log.student_id = uid
        or public.is_parent_of(uid, log.student_id)
        or public.is_admin(uid)
        or public.is_analyst(uid)
      )
  );
$$;

do $$
begin
  if to_regclass('public._migrations_applied') is not null then
    insert into public._migrations_applied (filename)
    values ('019_ai_drafts.sql')
    on conflict (filename) do nothing;
  end if;
end $$;
