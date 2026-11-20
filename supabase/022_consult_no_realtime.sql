-- ============================================================================
-- 022_consult_no_realtime.sql
--
-- 목적: 1:1 상담은 실시간 채팅이 아니라 "질문 남기기 → 선생님 답변" 방식으로 운영.
--       상담 메시지를 실시간 전송 목록에서 뺌. (이야기방 댓글은 그대로 유지)
--
-- 실행 방법: Supabase 대시보드 → SQL Editor → 전체 붙여넣기 → Run
-- 실행 전: 021이 먼저 실행되어 있어야 함
-- ============================================================================

do $$
begin
  if exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'consult_messages'
  ) then
    execute 'alter publication supabase_realtime drop table public.consult_messages';
  end if;
end $$;

do $$
begin
  if to_regclass('public._migrations_applied') is not null then
    insert into public._migrations_applied (filename)
    values ('022_consult_no_realtime.sql')
    on conflict (filename) do nothing;
  end if;
end $$;
