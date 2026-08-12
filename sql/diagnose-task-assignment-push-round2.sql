-- Round 2: assignee-resolution is now confirmed correct end-to-end (both
-- suspects from round 1 ruled out by real data - see
-- sql/diagnose-task-assignment-push-empty-log.sql). This checks the next
-- two things upstream of any code bug: (1) does Chris even have a push
-- subscription registered at all, and (2) is there any OTHER
-- task_assignment push that ever successfully logged, to confirm the
-- pipeline has ever worked for this event type even once.
--
-- Read-only. Paste back the full output.
--
-- OUTCOME (2026-08-12): query 1 came back empty (Chris has never
-- subscribed to push on any device) and query 3 came back empty (the
-- ENTIRE table has never logged a single row, for any event type, ever).
-- This ruled out the send pipeline entirely and pointed at the opt-in
-- flow itself - see sql/diagnose-chris-settings-permission.sql for the
-- permissions-gap root cause that was found next.

-- 1. Does Chris (auth_user_id a358312c-4670-486f-a106-555d8ca067ee) have
-- any push subscription registered at all? Zero rows here means no push
-- could ever have been sent to him, full stop, regardless of any bug in
-- the send pipeline - the simplest possible explanation.
select id, auth_user_id, endpoint, created_at
from public.ungani_push_subscriptions
where auth_user_id = 'a358312c-4670-486f-a106-555d8ca067ee';

-- 2. Has task_assignment EVER produced a row in ungani_push_sent_log, for
-- ANY task, ever - or is the log genuinely empty for this event type
-- across all time (not just this one test)?
select count(*) as total_task_assignment_log_rows
from public.ungani_push_sent_log
where event_type = 'task_assignment';

-- 3. For comparison - has ANY event type ever logged successfully? If
-- this is also empty, the whole pipeline (not just task_assignment) has
-- never once written to this table, which points at something structural
-- (grants/RLS on ungani_push_sent_log itself) rather than anything
-- specific to task assignment.
select event_type, count(*) as rows_logged
from public.ungani_push_sent_log
group by event_type
order by event_type;

-- 4. Explicit self-test of the exact insert markSent() performs, run as
-- YOU (via the SQL editor, which uses your own role, not service_role -
-- so this won't prove service_role's grants specifically, but WILL
-- immediately reveal any schema mismatch, e.g. a column type issue) -
-- confirms the table itself accepts a row shaped exactly like what the
-- code sends. Safe to run - it deletes what it inserts immediately after.
do $$
declare
  v_test_id uuid := gen_random_uuid();
begin
  insert into public.ungani_push_sent_log (event_type, related_id, recipient_scope)
  values ('diagnostic_test', v_test_id, 'test-scope');

  raise notice 'Test insert succeeded.';

  delete from public.ungani_push_sent_log where related_id = v_test_id and event_type = 'diagnostic_test';

  raise notice 'Test row cleaned up.';
end $$;

-- 5. service_role's actual current grants on this table - confirms the
-- GRANT from sql/push-notifications-step2.sql is still in place and
-- wasn't reverted/never applied.
select grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name = 'ungani_push_sent_log'
order by grantee, privilege_type;
