-- 비공개 학습 사진을 역할과 관계에 따라 안전하게 열람하도록 보완
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
      )
  );
$$;

create or replace function public.can_access_team_post_image(object_name text, uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.team_posts post
    where post.image_path = object_name
      and (
        public.is_team_member(post.team_id, uid)
        or public.is_parent_of(uid, post.student_id)
        or public.is_admin(uid)
      )
  );
$$;

revoke all on function public.can_access_study_log_image(text, uuid) from public;
revoke all on function public.can_access_team_post_image(text, uuid) from public;
grant execute on function public.can_access_study_log_image(text, uuid) to authenticated;
grant execute on function public.can_access_team_post_image(text, uuid) to authenticated;

drop policy if exists "study_log_images_select_allowed" on storage.objects;
create policy "study_log_images_select_allowed" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'study-log-images'
    and public.can_access_study_log_image(name, auth.uid())
  );

drop policy if exists "team_post_images_select_allowed" on storage.objects;
create policy "team_post_images_select_allowed" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'team-post-images'
    and public.can_access_team_post_image(name, auth.uid())
  );
