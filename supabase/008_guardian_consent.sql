-- 만 14세 미만 학생을 포함한 학부모 승인 흐름
alter table public.profiles
  add column if not exists guardian_consent_at timestamptz,
  add column if not exists guardian_consent_by uuid references public.profiles(id);

-- 기능 도입 전부터 사용하던 학생은 서비스가 갑자기 잠기지 않도록 승인 상태로 이관
update public.profiles
set guardian_consent_at = coalesce(guardian_consent_at, now())
where role = 'student';

create or replace function public.get_my_children_consent()
returns table(child_id uuid, child_name text, child_email text, guardian_consent_at timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  select s.id, s.name, s.email, s.guardian_consent_at
  from public.profiles s
  join public.profiles p on p.email = s.parent_email and p.role = 'parent'
  where p.id = auth.uid() and s.role = 'student'
  order by s.created_at;
$$;

create or replace function public.approve_child_consent(target_child_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare approved_at timestamptz := now();
begin
  if not public.is_parent_of(auth.uid(), target_child_id) then
    raise exception '연결된 학부모만 승인할 수 있습니다';
  end if;

  update public.profiles
  set guardian_consent_at = approved_at,
      guardian_consent_by = auth.uid(),
      updated_at = approved_at
  where id = target_child_id and role = 'student';

  return approved_at;
end;
$$;

revoke all on function public.get_my_children_consent() from public;
revoke all on function public.approve_child_consent(uuid) from public;
grant execute on function public.get_my_children_consent() to authenticated;
grant execute on function public.approve_child_consent(uuid) to authenticated;
