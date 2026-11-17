-- ============================================================================
-- 020_multi_photos.sql
--
-- 목적: 학습 기록 하나에 공부 사진을 여러 장(최대 10장) 올릴 수 있게 함.
--   - study_log_images: 기록별 사진 목록
--   - 기존 study_logs.image_path(첫 사진)는 그대로 두어 예전 기록·화면과 호환
--   - 사진 열람 권한: 학생 본인, 학부모, 관리자, 분석 계정 (기존과 동일)
--   - 자동 분석 함수가 기록의 사진 목록(image_paths)을 함께 돌려주도록 변경
--
-- 실행 방법: Supabase 대시보드 → SQL Editor → 전체 붙여넣기 → Run
-- 실행 전: 019가 먼저 실행되어 있어야 함
-- ============================================================================

create table if not exists public.study_log_images (
  id uuid primary key default gen_random_uuid(),
  log_id uuid not null references public.study_logs(id) on delete cascade,
  image_path text not null unique,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists study_log_images_log_idx
  on public.study_log_images (log_id, sort_order);

alter table public.study_log_images enable row level security;

-- 헬퍼: 이 기록의 주인(학생)인지
create or replace function public.owns_study_log(target_log_id uuid, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.study_logs where id = target_log_id and student_id = uid);
$$;

revoke all on function public.owns_study_log(uuid, uuid) from public;
grant execute on function public.owns_study_log(uuid, uuid) to authenticated;

-- 조회: 학생 본인, 학부모, 관리자, 분석 계정
drop policy if exists "study_log_images_rows_select" on public.study_log_images;
create policy "study_log_images_rows_select" on public.study_log_images
  for select using (
    public.owns_study_log(log_id, auth.uid())
    or public.is_admin(auth.uid())
    or public.is_analyst(auth.uid())
    or exists (
      select 1 from public.study_logs l
      where l.id = log_id and public.is_parent_of(auth.uid(), l.student_id)
    )
  );

-- 추가: 본인 기록에, 본인 폴더의 사진만 (정지된 계정은 불가)
drop policy if exists "study_log_images_rows_insert" on public.study_log_images;
create policy "study_log_images_rows_insert" on public.study_log_images
  for insert with check (
    public.owns_study_log(log_id, auth.uid())
    and public.is_active(auth.uid())
    and split_part(image_path, '/', 1) = auth.uid()::text
  );

-- 삭제: 본인 또는 관리자
drop policy if exists "study_log_images_rows_delete" on public.study_log_images;
create policy "study_log_images_rows_delete" on public.study_log_images
  for delete using (
    public.owns_study_log(log_id, auth.uid())
    or public.is_admin(auth.uid())
  );

grant select, insert, delete on public.study_log_images to authenticated;

-- 기록 하나에 최대 10장
create or replace function public.limit_study_log_images()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (select count(*) from public.study_log_images where log_id = new.log_id) >= 10 then
    raise exception '기록 하나에 사진은 10장까지 올릴 수 있어요';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_limit_study_log_images on public.study_log_images;
create trigger trg_limit_study_log_images
  before insert on public.study_log_images
  for each row execute function public.limit_study_log_images();

-- 사진 파일 열람 권한: study_logs.image_path 또는 study_log_images에 등록된 사진
create or replace function public.can_access_study_log_image(object_name text, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.study_logs log
    where (
        log.image_path = object_name
        or exists (select 1 from public.study_log_images i where i.log_id = log.id and i.image_path = object_name)
      )
      and (
        log.student_id = uid
        or public.is_parent_of(uid, log.student_id)
        or public.is_admin(uid)
        or public.is_analyst(uid)
      )
  );
$$;

-- 자동 분석 함수: 사진 목록(image_paths) 추가 (반환 형식이 바뀌므로 지우고 다시 만듦)
drop function if exists public.get_logs_needing_ai_draft(integer, integer);

create or replace function public.get_logs_needing_ai_draft(max_days integer default 7, max_rows integer default 30)
returns table (
  log_id uuid,
  student_name text,
  study_date date,
  subject text,
  content text,
  minutes_spent integer,
  image_path text,
  image_paths text[],
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
    coalesce(
      (select array_agg(i.image_path order by i.sort_order, i.created_at)
       from public.study_log_images i where i.log_id = l.id),
      case when l.image_path is not null then array[l.image_path] else array[]::text[] end
    ),
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

do $$
begin
  if to_regclass('public._migrations_applied') is not null then
    insert into public._migrations_applied (filename)
    values ('020_multi_photos.sql')
    on conflict (filename) do nothing;
  end if;
end $$;
