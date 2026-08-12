-- Round 3 of the task-assignment push investigation. The owner-resolver
-- fix (resolve_ungani_tenant_owner_auth_user_id, sql/add-resolve-tenant-
-- owner-auth-user-id.sql) is confirmed live and deployed, but a fresh
-- real test still produced zero rows in ungani_push_sent_log for
-- task_assignment. handleTaskAssignment() in api/send-event-push.js has
-- 4 distinct early-return branches before it ever calls markSent() -
-- this narrows down which one is firing.
--
-- Read-only except query 1, which is the actual fix-verification call.
-- Paste back the full output of all 5 queries.

-- 1. Direct test of the new resolver against the real tenant - if this
-- doesn't return Chris's auth_user_id (c05d6fda-dcbe-4b01-8037-
-- 42693ea620de), the resolver itself is still the problem (branch 3
-- above - "no resolvable assignee").
select public.resolve_ungani_tenant_owner_auth_user_id('a29af055-e4f0-48cf-af97-f99081a9106b'::uuid) as resolved_owner_auth_user_id;

-- 2. The raw registrations row(s) the resolver is reading from - shows
-- exactly what status/auth_user_id/email values it's working with, so we
-- can see WHY query 1 returned what it did.
select id, tenant_id, auth_user_id, email, contact_email, status,
       registration_status, created_at
from public.registrations
where tenant_id = 'a29af055-e4f0-48cf-af97-f99081a9106b'
order by created_at desc;

-- 3. Confirms whether the auth_user_id on those registrations rows
-- actually still exists in auth.users (the staleness check the resolver
-- performs) - a mismatch here would explain a null result in query 1
-- even with a seemingly valid-looking registrations row.
select r.id as registration_id, r.auth_user_id, u.id as matched_auth_user
from public.registrations r
left join auth.users u on u.id = r.auth_user_id
where r.tenant_id = 'a29af055-e4f0-48cf-af97-f99081a9106b';

-- 4. The real source of get_my_ungani_staff_access() - this is what
-- resolveCallerTenantId() in api/send-event-push.js calls FIRST, before
-- ever reaching the resolver. If this doesn't resolve Chris's tenant
-- correctly, the whole request 401s immediately (branch 1 above) and the
-- resolver fix is never even reached.
select pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'get_my_ungani_staff_access';

-- 5. The real, most recent task row for this tenant - confirms the
-- assignment shape (assigned_to_is_owner / tenant_id) matches what's
-- expected, in case the task itself saved with an unexpected tenant_id
-- or assignment shape (branch 2 above - tenant mismatch).
select id, tenant_id, task_title, assigned_to_is_owner,
       assigned_to_team_member_id, created_at
from public.tasks
where tenant_id = 'a29af055-e4f0-48cf-af97-f99081a9106b'
order by created_at desc
limit 5;
