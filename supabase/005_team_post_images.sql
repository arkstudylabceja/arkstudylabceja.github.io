-- 인증 게시물 사진 첨부
alter table public.team_posts
  add column if not exists image_path text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('team-post-images', 'team-post-images', false, 5242880, array['image/jpeg', 'image/png', 'image/webp', 'image/gif'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "team_post_images_select_allowed" on storage.objects;
create policy "team_post_images_select_allowed" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'team-post-images'
    and exists (
      select 1 from public.team_posts p
      where p.image_path = storage.objects.name
    )
  );

drop policy if exists "team_post_images_insert_own" on storage.objects;
create policy "team_post_images_insert_own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'team-post-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "team_post_images_delete_own" on storage.objects;
create policy "team_post_images_delete_own" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'team-post-images'
    and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin(auth.uid()))
  );
