-- Real task-assignment test (Chris, Property section, self-assigned) -
-- manual test push worked moments earlier, but this real event-triggered
-- push did not arrive. Investigating whether the send attempt reached
-- ungani_push_sent_log at all, and if so, why the actual push still
-- didn't land despite a confirmed-working subscription.
--
-- Read-only. Paste back the full output.

-- 1. The most recent task_assignment notification (confirms the RPC/
-- notification-creation half fired for this specific real test).
select id, tenant_id, user_id, notification_type, source_table,
       source_record_id, created_at
from public.ungani_notifications
where notification_type = 'task_assignment'
order by created_at desc
limit 3;

-- 2. Did THIS attempt reach ungani_push_sent_log at all? (Your question 1
-- - a fresh row here means the send code ran to completion; no fresh row
-- means it's failing/throwing before markSent(), same class of gap as
-- the very first investigation.)
select event_type, related_id, recipient_scope, created_at
from public.ungani_push_sent_log
where event_type = 'task_assignment'
order by created_at desc
limit 5;

-- 3. Chris's current, real push subscription(s) - confirms which
-- auth_user_id his actual working subscription (the one the manual test
-- push just succeeded against) is registered under.
select id, auth_user_id, endpoint, created_at
from public.ungani_push_subscriptions
where auth_user_id = 'a358312c-4670-486f-a106-555d8ca067ee';

-- 4. The real task from this test - which assignment shape, and does it
-- match Chris's team-member row exactly (re-checking in case anything
-- drifted since the first round of this investigation).
select t.id, t.tenant_id, t.task_title, t.assigned_to, t.assigned_to_is_owner,
       t.assigned_to_team_member_id, t.created_at
from public.tasks t
order by t.created_at desc
limit 5;

-- 5. Chris's team-member row's auth_user_id right now - must exactly
-- match query 3's auth_user_id for handleTaskAssignment() to find his
-- subscription at all.
select id, full_name, auth_user_id, tenant_id
from public.ungani_team_members
where id = 'b6330098-281b-4760-9ea7-526e78d29acf';
