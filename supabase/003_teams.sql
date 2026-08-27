-- ============================================================================
-- 003_teams.sql
--
-- 목적: 학생들을 팀으로 묶어 함께 공부 인증을 나누는 "팀방" 기능.
--       팀 배정은 관리자만 할 수 있음 (학생 자율 개설 아님).
--       001에서 만든 is_admin() / is_parent_of() 함수를 재사용.
--
-- 실행 방법: Supabase 대시보드 → SQL Editor → 전체 붙여넣기 → Run
-- 실행 전: 000, 001이 먼저 실행되어 있어야 함
-- ============================================================================

create table if not exists public.teams (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.team_members (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  unique (team_id, student_id)
);

create table if not exists public.team_posts (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  content text not null,
  created_at timestamptz not null default now()
);

alter table public.teams enable row level security;
alter table public.team_members enable row level security;
alter table public.team_posts enable row level security;

-- teams: 소속된 팀만 조회 가능, 관리 전권은 admin
drop policy if exists "teams_select_member" on public.teams;
create policy "teams_select_member" on public.teams
  for select using (
    exists (
      select 1 from public.team_members tm
      where tm.team_id = teams.id and tm.student_id = auth.uid()
    )
  );

drop policy if exists "teams_all_admin" on public.teams;
create policy "teams_all_admin" on public.teams
  for all using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));

-- team_members: 같은 팀 소속끼리만 서로 조회 가능, 배정/제외는 admin만
drop policy if exists "team_members_select_teammate" on public.team_members;
create policy "team_members_select_teammate" on public.team_members
  for select using (
    exists (
      select 1 from public.team_members me
      where me.team_id = team_members.team_id and me.student_id = auth.uid()
    )
  );

drop policy if exists "team_members_all_admin" on public.team_members;
create policy "team_members_all_admin" on public.team_members
  for all using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));

-- team_posts: 같은 팀원끼리 열람, 본인 글만 작성/삭제, 부모는 자녀 글 열람, admin 전권
drop policy if exists "team_posts_select_teammate" on public.team_posts;
create policy "team_posts_select_teammate" on public.team_posts
  for select using (
    exists (
      select 1 from public.team_members tm
      where tm.team_id = team_posts.team_id and tm.student_id = auth.uid()
    )
  );

drop policy if exists "team_posts_insert_own" on public.team_posts;
create policy "team_posts_insert_own" on public.team_posts
  for insert with check (
    auth.uid() = student_id
    and exists (
      select 1 from public.team_members tm
      where tm.team_id = team_posts.team_id and tm.student_id = auth.uid()
    )
  );

drop policy if exists "team_posts_delete_own" on public.team_posts;
create policy "team_posts_delete_own" on public.team_posts
  for delete using (auth.uid() = student_id);

drop policy if exists "team_posts_select_parent" on public.team_posts;
create policy "team_posts_select_parent" on public.team_posts
  for select using (public.is_parent_of(auth.uid(), student_id));

drop policy if exists "team_posts_all_admin" on public.team_posts;
create policy "team_posts_all_admin" on public.team_posts
  for all using (public.is_admin(auth.uid())) with check (public.is_admin(auth.uid()));
