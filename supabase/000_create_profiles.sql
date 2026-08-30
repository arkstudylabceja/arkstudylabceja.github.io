-- ARK STUDY LAB fresh-project profile schema

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  name text not null,
  role text not null default 'student'
    check (role in ('parent', 'student', 'admin')),
  parent_email text,
  course_completed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, name, role, parent_email)
  values (
    new.id,
    new.email,
    coalesce(nullif(new.raw_user_meta_data ->> 'name', ''), split_part(new.email, '@', 1)),
    case
      when new.raw_user_meta_data ->> 'role' in ('parent', 'student')
        then new.raw_user_meta_data ->> 'role'
      else 'student'
    end,
    nullif(new.raw_user_meta_data ->> 'parent_email', '')
  )
  on conflict (id) do update set
    email = excluded.email,
    name = excluded.name,
    parent_email = excluded.parent_email,
    updated_at = now();

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert or update of email, raw_user_meta_data on auth.users
  for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;

