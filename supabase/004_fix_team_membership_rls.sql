-- Avoid recursive RLS checks when students read team membership.

create or replace function public.is_team_member(target_team_id uuid, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.team_members tm
    where tm.team_id = target_team_id
      and tm.student_id = uid
  );
$$;

revoke all on function public.is_team_member(uuid, uuid) from public;
grant execute on function public.is_team_member(uuid, uuid) to authenticated;

drop policy if exists "teams_select_member" on public.teams;
create policy "teams_select_member" on public.teams
  for select using (public.is_team_member(id, auth.uid()));

drop policy if exists "team_members_select_teammate" on public.team_members;
create policy "team_members_select_teammate" on public.team_members
  for select using (public.is_team_member(team_id, auth.uid()));

drop policy if exists "team_posts_select_teammate" on public.team_posts;
create policy "team_posts_select_teammate" on public.team_posts
  for select using (public.is_team_member(team_id, auth.uid()));

drop policy if exists "team_posts_insert_own" on public.team_posts;
create policy "team_posts_insert_own" on public.team_posts
  for insert with check (
    auth.uid() = student_id
    and public.is_team_member(team_id, auth.uid())
  );

