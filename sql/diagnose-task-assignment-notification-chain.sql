-- Diagnostic ONLY - read-only, changes nothing. Run this after doing a
-- real task-assignment test (assign a task to yourself or a real staff
-- member), then paste back the full literal output of every query below.
--
-- Goal: find exactly which link in the chain broke -
--   1. Did the RPC even run and create the in-app notification?
--   2. Did it queue an email?
--   3. Is the recipient's auth_user_id actually resolvable (the exact
--      column the push endpoint depends on, which has a documented
--      staleness history elsewhere in this app)?
--   4. Was the push endpoint ever actually invoked (proven by a
--      sent-log row, even if it decided not to send anything)?
--
-- No placeholders to fill in - every query below is ordered by recency
-- and limited, so it surfaces your real test data without needing your
-- tenant_id typed in by hand.

-- ============================================================
-- STEP 1: did notify_ungani_task_assignment() actually run and create
-- the in-app notification? Expect at least one row with a recent
-- created_at matching when you did the test.
-- ============================================================

select id, tenant_id, user_id, notification_title, notification_message,
       notification_type, source_table, source_record_id, priority,
       created_at
from public.ungani_notifications
where notification_type = 'task_assignment'
order by created_at desc
limit 10;

-- ============================================================
-- STEP 2: did it queue an email? Expect a row with send_status =
-- 'pending' (never sent) or 'sent' (sent, but you didn't receive it -
-- a different, deliverability-side problem) or NO ROW AT ALL (the
-- email-queue insert never happened - most likely because the
-- assignee's email came back null/empty from either the registrations
-- table [owner] or ungani_team_members [staff member]).
-- ============================================================

select id, tenant_id, recipient_email, recipient_name, email_subject,
       email_type, related_table, related_id, send_status, created_at, sent_at
from public.ungani_email_queue
where email_type = 'task_assignment'
order by created_at desc
limit 10;

-- ============================================================
-- STEP 3: the exact column the push endpoint depends on for the OWNER
-- path - if auth_user_id is null here, the push endpoint silently
-- returns "no resolvable assignee" and sends nothing, with no visible
-- error anywhere.
-- ============================================================

select id, tenant_id, status, registration_status, contact_email, email,
       auth_user_id, created_at
from public.registrations
order by created_at desc
limit 15;

-- ============================================================
-- STEP 4: if you assigned to a STAFF MEMBER instead of yourself, this
-- is the equivalent check - same failure mode (auth_user_id null means
-- "never logged in via staff-login.html yet", so push has nothing to
-- target).
-- ============================================================

select id, tenant_id, full_name, email, status, auth_user_id, created_at
from public.ungani_team_members
order by created_at desc
limit 15;

-- ============================================================
-- STEP 5: was /api/send-event-push ever actually invoked for this
-- event? A row here (regardless of what it decided) proves the
-- endpoint ran. NO ROW AT ALL means the client-side fetch call
-- (triggerEventPush) never reached the server - a network/auth/client-
-- side problem, not a server-side recipient-resolution problem.
-- ============================================================

select event_type, related_id, recipient_scope, created_at
from public.ungani_push_sent_log
where event_type = 'task_assignment'
order by created_at desc
limit 10;

-- ============================================================
-- STEP 6: your real, current push subscriptions - confirms which
-- auth_user_id the manual test push actually targeted successfully,
-- to compare against whatever auth_user_id STEP 3/4 shows for the
-- assignee.
-- ============================================================

select id, auth_user_id, user_type, tenant_id, created_at
from public.ungani_push_subscriptions
order by created_at desc
limit 10;
