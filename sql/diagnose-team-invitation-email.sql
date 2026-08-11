-- Diagnostic ONLY - read-only, changes nothing.
--
-- Answers the exact question asked: does the staff-invitation flow
-- currently send ANY email at all? Query 1 shows the REAL, currently-
-- live source of owner_upsert_ungani_team_member() - if the email-
-- queueing block (search the output for "ungani_email_queue") isn't in
-- there, the answer is a definitive no, and this needs to be built,
-- not debugged. If it IS in there, queries 2-3 show whether it's
-- actually running for real invites.

-- 1. The real, live function body - word for word, not what any SQL
-- file in the repo claims should be live.
select pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'owner_upsert_ungani_team_member';

-- 2. Every team-invitation email ever queued, if any. Empty = never
-- queued once, for anyone, ever - points at query 1 confirming the
-- code isn't there. Rows present but stuck 'pending' = queued fine,
-- never sent - a different (delivery-side) problem.
select id, tenant_id, recipient_email, recipient_name, email_subject,
       send_status, created_at, sent_at
from public.ungani_email_queue
where email_type = 'team_invitation'
order by created_at desc
limit 10;

-- 3. The staff member you just tried to invite - confirms the real
-- email address on file (rules out a typo) and when the row was
-- created.
select id, tenant_id, full_name, email, status, auth_user_id, created_at
from public.ungani_team_members
order by created_at desc
limit 5;
