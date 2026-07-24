-- Read-only. Three checks, one per part of task #11's investigation.
-- Each is explained in the report alongside this file.

-- ============================================================
-- 1. DUPLICATE-SUBMISSION: does check_ungani_duplicate_registration
--    actually exist? index.html has called this RPC since commit
--    d0371a1 (2026-07-13), but that commit's own message says "the SQL
--    to create it needs to be run in Supabase separately" - and no
--    commit anywhere in this repo's history ever defines it. If it
--    doesn't exist, every call silently degrades to {duplicate: false}
--    (the client-side code catches the "function does not exist" error
--    and treats it as "not a duplicate"), meaning server-side duplicate
--    protection has likely been a no-op this entire time.
-- ============================================================
select p.proname, has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_can_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'check_ungani_duplicate_registration';

-- ============================================================
-- 2. SMTP: any evidence of a real, successfully delivered email? Every
--    test of api/send-email-queue.js this session (and per its own
--    commit history) was against a mocked SMTP layer - this checks
--    real production queue history for actual outcomes.
-- ============================================================
select send_status, count(*) as row_count, min(created_at) as earliest, max(created_at) as latest
from ungani_email_queue
group by send_status
order by row_count desc;

-- Most recent 10 rows regardless of status, for direct inspection
-- (including last_error text for any failures).
select id, recipient_email, email_type, send_status, send_attempts, last_error, created_at, sent_at
from ungani_email_queue
order by created_at desc
limit 10;

-- ============================================================
-- 3. STUCK APPROVAL: the one concretely-documented edge case on record
--    (from the Option A registration flow work) is that if
--    auth.signUp() succeeds but the registrations insert fails, the
--    resulting Auth user has NO registrations row - invisible to admin,
--    can never be approved, permanently "stuck". This checks for
--    exactly that: Auth users with no matching registrations row AND no
--    matching tenants/users row (i.e. never became a real account
--    either).
-- ============================================================
select au.id, au.email, au.created_at
from auth.users au
where not exists (select 1 from registrations r where r.auth_user_id = au.id)
  and not exists (select 1 from users u where u.id = au.id)
order by au.created_at desc;

-- Separately - registrations stuck in 'pending' for a long time (a
-- different flavor of "stuck": these DO show up for admin, so if
-- they're old, it's more likely a review backlog than a bug, but worth
-- seeing the real picture rather than assuming).
select id, business_name, email, status, created_at,
       now() - created_at as age
from registrations
where status = 'pending'
order by created_at asc;

-- The real source of approve_ungani_registration - assesses whether
-- it's atomic (wrapped in a way that can't partially succeed) or has a
-- multi-step gap where a status update could fail after a tenant/user
-- was already created.
select pg_get_functiondef(p.oid) as source
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'approve_ungani_registration';
