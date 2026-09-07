-- ============================================================================
-- 010_guardian_consent_hardening.sql
--
-- 문제: guardian_consent_at / guardian_consent_by 컬럼(008_guardian_consent.sql)에는
--       role이나 account_status(001, 009)와 달리 "본인이 직접 못 바꾸게" 막는
--       트리거가 없었음. profiles 테이블의 기본 update 정책은 "본인 행이면 수정 가능"
--       이라서, 학생이 개발자 도구로 아래처럼 실행하면 보호자 승인 없이도
--       스스로 승인 처리를 할 수 있었음:
--         sb.from('profiles').update({ guardian_consent_at: new Date() }).eq('id', myId)
--
-- 해결: role/account_status와 동일한 패턴의 트리거를 추가하되, 정상적인 승인 경로인
--       approve_child_consent() RPC(부모가 호출)는 계속 동작해야 하므로
--       "관리자 또는 연결된 학부모"인 경우는 허용하도록 함.
--
-- 실행 방법: Supabase 대시보드 → SQL Editor → 전체 붙여넣기 → Run
-- 실행 전: 001, 008, 009가 먼저 실행되어 있어야 함 (is_admin, is_parent_of, 관련 컬럼 필요)
-- ============================================================================

create or replace function public.prevent_guardian_consent_self_change()
returns trigger
language plpgsql
as $$
begin
  if (new.guardian_consent_at is distinct from old.guardian_consent_at
      or new.guardian_consent_by is distinct from old.guardian_consent_by)
     and auth.uid() is not null
     and not public.is_admin(auth.uid())
     and not public.is_parent_of(auth.uid(), new.id) then
    raise exception '보호자 동의 상태 변경은 연결된 학부모 또는 관리자만 할 수 있습니다';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_guardian_consent_self_change on public.profiles;
create trigger trg_prevent_guardian_consent_self_change
  before update on public.profiles
  for each row
  execute function public.prevent_guardian_consent_self_change();
