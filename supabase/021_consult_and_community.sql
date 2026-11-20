-- ============================================================================
-- 021_consult_and_community.sql
--
-- 목적: 두 가지 대화 공간을 추가함.
--   1) 1:1 상담 (consult_threads / consult_messages)
--      - 학부모·학생이 선생님에게만 질문을 남기고, 선생님(관리자)이 답함.
--      - 작성자 본인과 관리자만 볼 수 있음. 다른 학부모·학생에게는 보이지 않음.
--   2) 학부모 이야기방 (community_posts / community_comments)
--      - 학부모끼리 글과 댓글로 이야기하는 게시판.
--      - 학부모와 관리자만 볼 수 있음 (학생은 볼 수 없음).
--      - 이름은 "김OO"처럼 가려서 저장함 (학부모끼리 이메일·전체 이름이 보이지 않게).
--      - 관리자는 글·댓글을 숨기거나 지울 수 있음.
--
-- 실행 방법: Supabase 대시보드 → SQL Editor → 전체 붙여넣기 → Run
-- 실행 전: 001, 008, 011(is_active)이 먼저 실행되어 있어야 함
-- 다시 실행해도 안전하도록 작성함.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 공통 헬퍼
-- ---------------------------------------------------------------------------

-- 상담을 쓸 수 있는 사람: 정지되지 않은 학부모·관리자, 또는 학부모 승인을 받은 학생
create or replace function public.can_use_consult(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = uid
      and p.account_status = 'active'
      and (
        p.role in ('parent', 'admin')
        or (p.role = 'student' and p.guardian_consent_at is not null)
      )
  );
$$;

-- 이야기방을 쓸 수 있는 사람: 정지되지 않은 학부모·관리자
create or replace function public.can_use_community(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = uid
      and p.account_status = 'active'
      and p.role in ('parent', 'admin')
  );
$$;

revoke all on function public.can_use_consult(uuid) from public;
revoke all on function public.can_use_community(uuid) from public;
grant execute on function public.can_use_consult(uuid) to authenticated;
grant execute on function public.can_use_community(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 1) 1:1 상담
-- ---------------------------------------------------------------------------

create table if not exists public.consult_threads (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  subject text not null check (char_length(subject) between 1 and 100),
  status text not null default 'waiting'
    check (status in ('waiting', 'answered', 'closed')),
  created_at timestamptz not null default now(),
  last_message_at timestamptz not null default now()
);

create table if not exists public.consult_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.consult_threads(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  from_teacher boolean not null default false,
  body text not null check (char_length(body) between 1 and 3000),
  created_at timestamptz not null default now()
);

create index if not exists consult_threads_author_idx
  on public.consult_threads (author_id, last_message_at desc);
create index if not exists consult_threads_status_idx
  on public.consult_threads (status, last_message_at desc);
create index if not exists consult_messages_thread_idx
  on public.consult_messages (thread_id, created_at);

alter table public.consult_threads enable row level security;
alter table public.consult_messages enable row level security;

create or replace function public.is_consult_author(target_thread_id uuid, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.consult_threads t
    where t.id = target_thread_id and t.author_id = uid
  );
$$;

revoke all on function public.is_consult_author(uuid, uuid) from public;
grant execute on function public.is_consult_author(uuid, uuid) to authenticated;

-- 메시지가 들어오면: 보낸 사람이 선생님인지 표시하고, 상담 상태와 최근 시각을 갱신
create or replace function public.consult_message_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.sender_id := auth.uid();
  new.from_teacher := public.is_admin(auth.uid());
  new.created_at := now();
  return new;
end;
$$;

create or replace function public.consult_message_after_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.consult_threads
  set last_message_at = new.created_at,
      status = case when new.from_teacher then 'answered' else 'waiting' end
  where id = new.thread_id;
  return new;
end;
$$;

drop trigger if exists trg_consult_message_before_insert on public.consult_messages;
create trigger trg_consult_message_before_insert
  before insert on public.consult_messages
  for each row execute function public.consult_message_before_insert();

drop trigger if exists trg_consult_message_after_insert on public.consult_messages;
create trigger trg_consult_message_after_insert
  after insert on public.consult_messages
  for each row execute function public.consult_message_after_insert();

-- 상담 시작 시 작성자를 본인으로 고정
create or replace function public.consult_thread_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.author_id := auth.uid();
  new.status := 'waiting';
  new.created_at := now();
  new.last_message_at := now();
  return new;
end;
$$;

drop trigger if exists trg_consult_thread_before_insert on public.consult_threads;
create trigger trg_consult_thread_before_insert
  before insert on public.consult_threads
  for each row execute function public.consult_thread_before_insert();

-- consult_threads 정책
drop policy if exists "consult_threads_select_own" on public.consult_threads;
create policy "consult_threads_select_own" on public.consult_threads
  for select using (author_id = auth.uid());

drop policy if exists "consult_threads_insert_own" on public.consult_threads;
create policy "consult_threads_insert_own" on public.consult_threads
  for insert with check (
    author_id = auth.uid()
    and public.can_use_consult(auth.uid())
    and not public.is_admin(auth.uid())
  );

drop policy if exists "consult_threads_admin_all" on public.consult_threads;
create policy "consult_threads_admin_all" on public.consult_threads
  for all using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

-- consult_messages 정책
drop policy if exists "consult_messages_select_own" on public.consult_messages;
create policy "consult_messages_select_own" on public.consult_messages
  for select using (public.is_consult_author(thread_id, auth.uid()));

drop policy if exists "consult_messages_insert_own" on public.consult_messages;
create policy "consult_messages_insert_own" on public.consult_messages
  for insert with check (
    sender_id = auth.uid()
    and public.is_consult_author(thread_id, auth.uid())
    and public.can_use_consult(auth.uid())
    and exists (
      select 1 from public.consult_threads t
      where t.id = thread_id and t.status <> 'closed'
    )
  );

drop policy if exists "consult_messages_admin_select" on public.consult_messages;
create policy "consult_messages_admin_select" on public.consult_messages
  for select using (public.is_admin(auth.uid()));

drop policy if exists "consult_messages_admin_insert" on public.consult_messages;
create policy "consult_messages_admin_insert" on public.consult_messages
  for insert with check (
    sender_id = auth.uid()
    and public.is_admin(auth.uid())
    and public.is_active(auth.uid())
  );

drop policy if exists "consult_messages_admin_delete" on public.consult_messages;
create policy "consult_messages_admin_delete" on public.consult_messages
  for delete using (public.is_admin(auth.uid()));

grant select, insert on public.consult_threads to authenticated;
grant update, delete on public.consult_threads to authenticated;
grant select, insert, delete on public.consult_messages to authenticated;

-- ---------------------------------------------------------------------------
-- 2) 학부모 이야기방
-- ---------------------------------------------------------------------------

create table if not exists public.community_posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  author_label text not null default '',
  title text not null check (char_length(title) between 1 and 100),
  body text not null check (char_length(body) between 1 and 5000),
  is_hidden boolean not null default false,
  is_notice boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.community_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.community_posts(id) on delete cascade,
  author_id uuid not null references public.profiles(id) on delete cascade,
  author_label text not null default '',
  body text not null check (char_length(body) between 1 and 1000),
  is_hidden boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists community_posts_created_idx
  on public.community_posts (is_notice desc, created_at desc);
create index if not exists community_comments_post_idx
  on public.community_comments (post_id, created_at);

alter table public.community_posts enable row level security;
alter table public.community_comments enable row level security;

-- 글쓴이 표시 이름: 관리자는 "선생님", 학부모는 "김OO 학부모님"처럼 가림
create or replace function public.community_author_label(uid uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p.role = 'admin' then '선생님'
    else coalesce(nullif(left(trim(p.name), 1), ''), '익명') || 'OO 학부모님'
  end
  from public.profiles p
  where p.id = uid;
$$;

revoke all on function public.community_author_label(uuid) from public;

create or replace function public.community_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.author_id := auth.uid();
  new.author_label := coalesce(public.community_author_label(auth.uid()), '익명');
  new.is_hidden := false;
  new.created_at := now();
  return new;
end;
$$;

create or replace function public.community_post_notice_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- 공지 표시는 관리자만
  if new.is_notice and not public.is_admin(auth.uid()) then
    new.is_notice := false;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_community_posts_before_insert on public.community_posts;
create trigger trg_community_posts_before_insert
  before insert on public.community_posts
  for each row execute function public.community_before_insert();

drop trigger if exists trg_community_posts_notice_guard on public.community_posts;
create trigger trg_community_posts_notice_guard
  before insert on public.community_posts
  for each row execute function public.community_post_notice_guard();

drop trigger if exists trg_community_comments_before_insert on public.community_comments;
create trigger trg_community_comments_before_insert
  before insert on public.community_comments
  for each row execute function public.community_before_insert();

-- community_posts 정책
drop policy if exists "community_posts_select" on public.community_posts;
create policy "community_posts_select" on public.community_posts
  for select using (
    public.can_use_community(auth.uid())
    and (is_hidden = false or author_id = auth.uid())
  );

drop policy if exists "community_posts_insert" on public.community_posts;
create policy "community_posts_insert" on public.community_posts
  for insert with check (
    author_id = auth.uid()
    and public.can_use_community(auth.uid())
  );

drop policy if exists "community_posts_delete_own" on public.community_posts;
create policy "community_posts_delete_own" on public.community_posts
  for delete using (author_id = auth.uid());

drop policy if exists "community_posts_admin_all" on public.community_posts;
create policy "community_posts_admin_all" on public.community_posts
  for all using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

-- community_comments 정책
drop policy if exists "community_comments_select" on public.community_comments;
create policy "community_comments_select" on public.community_comments
  for select using (
    public.can_use_community(auth.uid())
    and (is_hidden = false or author_id = auth.uid())
  );

drop policy if exists "community_comments_insert" on public.community_comments;
create policy "community_comments_insert" on public.community_comments
  for insert with check (
    author_id = auth.uid()
    and public.can_use_community(auth.uid())
    and exists (
      select 1 from public.community_posts p
      where p.id = post_id and p.is_hidden = false
    )
  );

drop policy if exists "community_comments_delete_own" on public.community_comments;
create policy "community_comments_delete_own" on public.community_comments
  for delete using (author_id = auth.uid());

drop policy if exists "community_comments_admin_all" on public.community_comments;
create policy "community_comments_admin_all" on public.community_comments
  for all using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

grant select, insert, update, delete on public.community_posts to authenticated;
grant select, insert, update, delete on public.community_comments to authenticated;

-- ---------------------------------------------------------------------------
-- 실시간 업데이트 (상담 메시지·이야기방 댓글이 새로고침 없이 나타나도록)
-- 이미 등록되어 있으면 건너뜀
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'consult_messages'
    ) then
      execute 'alter publication supabase_realtime add table public.consult_messages';
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'community_comments'
    ) then
      execute 'alter publication supabase_realtime add table public.community_comments';
    end if;
  end if;
end $$;

do $$
begin
  if to_regclass('public._migrations_applied') is not null then
    insert into public._migrations_applied (filename)
    values ('021_consult_and_community.sql')
    on conflict (filename) do nothing;
  end if;
end $$;
