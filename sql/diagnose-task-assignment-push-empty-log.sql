-- Diagnosing why a real task-assignment test created a real
-- ungani_notifications row (confirmed) but left ungani_push_sent_log
-- completely empty for event_type = 'task_assignment' (confirmed).
--
-- Found via code investigation, not yet confirmed against real data
-- (I have no DB access) - this query confirms which of two suspects
-- actually applies before I write a fix. Read-only. Paste back the
-- full output.
--
-- ============================================================
-- THE SETUP: notify_ungani_task_assignment() (the SQL RPC that creates
-- the notification, called from my-tasks.html) and handleTaskAssignment()
-- (the JS function in api/send-event-push.js that's supposed to send the
-- actual push, called right after) both independently re-resolve "who is
-- the assignee's auth_user_id" from the same task row - but their
-- resolution logic has DRIFTED:
--
--   1. Owner-assignment branch: the RPC was fixed on 2026-08-11
--      (sql/fix-task-assignment-owner-auth-user-id-staleness.sql) to (a)
--      match registrations by `coalesce(status, registration_status)`
--      instead of just `status`, and (b) verify the resulting
--      auth_user_id still points to a real auth.users row, falling back
--      to an email match if not. The JS endpoint's owner branch
--      (api/send-event-push.js lines 199-209) has NEITHER fix - it only
--      checks the plain `status` column and never verifies/falls back on
--      auth_user_id staleness.
--
--   2. Whichever branch actually ran, the JS endpoint's "no resolvable
--      assignee" early return (line 221-223) is the ONLY exit path in
--      the whole function that does NOT call markSent() - every other
--      exit (no push subscriptions, success) writes a row to
--      ungani_push_sent_log regardless of outcome. So a completely
--      empty log is consistent with THIS specific branch being hit,
--      whichever underlying cause put it there.
-- ============================================================
--
-- OUTCOME (2026-08-12): both suspects above were ruled out by the real
-- data this query returned. See sql/diagnose-task-assignment-push-
-- round2.sql for the round 2 diagnostic that followed, and
-- sql/diagnose-chris-settings-permission.sql for what actually turned
-- out to be the root cause (a permissions gap, not the send pipeline).

-- 1. The real task from your test - which assignment shape does it
-- actually have? (own_id blank + team_member_id set = staff assignment;
-- is_owner = true = self/owner assignment.)
select t.id, t.tenant_id, t.task_title, t.assigned_to, t.assigned_to_is_owner,
       t.assigned_to_team_member_id, t.created_at
from public.tasks t
join public.ungani_notifications n on n.source_table = 'tasks' and n.source_record_id = t.id
where n.id = '429fa4bc-8344-45ed-8cc9-ab2d3fb3aac8';

-- 2. If it was a team-member assignment: does that team member actually
-- have an auth_user_id linked? A found-but-null auth_user_id here would
-- make BOTH the RPC and the JS endpoint fail to resolve an assignee (not
-- a drift bug - a genuinely unlinked team member).
select tm.id, tm.full_name, tm.email, tm.auth_user_id, tm.tenant_id
from public.ungani_team_members tm
join public.tasks t on t.assigned_to_team_member_id = tm.id
join public.ungani_notifications n on n.source_table = 'tasks' and n.source_record_id = t.id
where n.id = '429fa4bc-8344-45ed-8cc9-ab2d3fb3aac8';

-- 3. If it was an owner assignment: what does the tenant's most recent
-- registrations row actually look like - is `status` populated, or only
-- `registration_status`? And does its auth_user_id point to a real
-- auth.users row?
select r.id, r.tenant_id, r.status, r.registration_status, r.auth_user_id,
       (select count(*) from auth.users u where u.id = r.auth_user_id) as auth_user_id_is_valid,
       r.created_at
from public.registrations r
join public.tasks t on t.tenant_id = r.tenant_id
join public.ungani_notifications n on n.source_table = 'tasks' and n.source_record_id = t.id
where n.id = '429fa4bc-8344-45ed-8cc9-ab2d3fb3aac8'
  and t.assigned_to_is_owner = true
order by r.created_at desc;

-- 4. The real notification row itself - does it have a user_id? (The
-- RPC always writes one if it resolved an assignee; NULL here would mean
-- even the RPC's resolution came up empty, which would point somewhere
-- else entirely.)
select id, tenant_id, user_id, notification_type, source_table, source_record_id, created_at
from public.ungani_notifications
where id = '429fa4bc-8344-45ed-8cc9-ab2d3fb3aac8';
