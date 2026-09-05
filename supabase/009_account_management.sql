alter table public.profiles
  add column if not exists account_status text not null default 'active';

alter table public.profiles
  drop constraint if exists profiles_account_status_check;

alter table public.profiles
  add constraint profiles_account_status_check
  check (account_status in ('active', 'suspended'));

create or replace function public.prevent_account_status_self_change()
returns trigger
language plpgsql
as $$
begin
  if new.account_status <> old.account_status
     and auth.uid() is not null
     and not public.is_admin(auth.uid()) then
    raise exception '계정 상태 변경은 관리자만 할 수 있습니다';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_account_status_self_change on public.profiles;
create trigger trg_prevent_account_status_self_change
  before update on public.profiles
  for each row
  execute function public.prevent_account_status_self_change();

create table if not exists public.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  reason text,
  status text not null default 'pending' check (status in ('pending', 'cancelled', 'completed')),
  requested_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.profiles(id)
);

create unique index if not exists account_deletion_requests_one_pending
  on public.account_deletion_requests(user_id)
  where status = 'pending';

alter table public.account_deletion_requests enable row level security;

drop policy if exists "Users can view own deletion requests" on public.account_deletion_requests;
create policy "Users can view own deletion requests"
  on public.account_deletion_requests for select
  using (auth.uid() = user_id or public.is_admin(auth.uid()));

drop policy if exists "Users can create own deletion requests" on public.account_deletion_requests;
create policy "Users can create own deletion requests"
  on public.account_deletion_requests for insert
  with check (auth.uid() = user_id and status = 'pending');

drop policy if exists "Users can cancel own deletion requests" on public.account_deletion_requests;
drop policy if exists "Admins can update deletion requests" on public.account_deletion_requests;
create policy "Admins can update deletion requests"
  on public.account_deletion_requests for update
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));

create or replace function public.cancel_my_account_deletion_request()
returns void
language sql
security definer
set search_path = public
as $$
  update public.account_deletion_requests
  set status = 'cancelled', resolved_at = now()
  where user_id = auth.uid() and status = 'pending';
$$;

grant execute on function public.cancel_my_account_deletion_request() to authenticated;

grant select, insert, update on public.account_deletion_requests to authenticated;
