-- Diagnoses "permission denied for table ungani_email_queue" from
-- api/send-email-queue.js. That exact error text is Postgres's specific
-- signal for a missing table-level GRANT - RLS violations produce a
-- different message ("new row violates row-level security policy..."),
-- so this is a grant problem, not an RLS problem, regardless of which
-- role is hitting it. Same class of bug as sql/tenant-integrations-
-- setup.sql's missing grant, found and fixed earlier this session.
--
-- Two live possibilities, both checked below:
--   A. The code IS genuinely running as service_role, and this specific
--      table never got the grants service_role normally has by default
--      on every Supabase project (rare, but exactly what happened to
--      tenant_integrations, so not out of the question here either).
--   B. The SUPABASE_SERVICE_ROLE_KEY currently in Vercel isn't actually
--      authenticating as service_role at all - e.g. if it's the newer
--      sb_secret_... format and that key isn't mapping to service_role
--      correctly (there's an open, unresolved Supabase GitHub report of
--      exactly this: https://github.com/orgs/supabase/discussions/43187).
--      If so, the request is probably landing as anon or authenticated,
--      neither of which should have any access to this admin-only,
--      service-role-only table.

-- 1. Table-level grants across every role, for ungani_email_queue.
select grantee, privilege_type
from information_schema.table_privileges
where table_schema = 'public' and table_name = 'ungani_email_queue'
order by grantee, privilege_type;

-- 2. RLS status + any policies (checked for completeness, even though
--    the error signature already points at grants, not RLS).
select relrowsecurity as rls_enabled
from pg_class
where relname = 'ungani_email_queue';

select policyname, cmd, roles
from pg_policies
where tablename = 'ungani_email_queue'
order by policyname;

-- 3. Confirms service_role itself has BYPASSRLS at the Postgres role
--    level in this project (standard on every Supabase project -
--    checking rather than assuming, given the live uncertainty above).
select rolname, rolbypassrls, rolsuper
from pg_roles
where rolname in ('service_role', 'authenticated', 'anon');

-- 4. THE DEFINITIVE TEST - impersonates the REAL service_role Postgres
--    role (not a JWT claim, the actual role) and runs the exact
--    select/insert/update shapes api/send-email-queue.js performs,
--    wrapped in a transaction that rolls back so nothing is kept.
--
--    If this succeeds: the table and service_role are both fine at the
--    database level - the real problem is that the key Vercel is using
--    isn't actually authenticating as service_role (points at the
--    sb_secret_ key format, per the GitHub report above - worth trying
--    the legacy service_role JWT key instead, as already suggested).
--
--    If this ALSO fails with "permission denied": ungani_email_queue
--    itself is missing grants for service_role, same fix needed as
--    tenant_integrations (a one-line GRANT), and I'll provide the exact
--    statement once you confirm this result.

begin;

set local role service_role;

select id, send_status from ungani_email_queue limit 1;

update ungani_email_queue
set send_status = send_status
where false
returning id;

rollback;
