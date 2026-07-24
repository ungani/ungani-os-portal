-- Read-only. Verifies sql/tenant-integrations-setup.sql landed exactly as
-- written - table shape, RLS, policies, and (the one thing that setup
-- script didn't explicitly handle) whether the `authenticated` role
-- actually has base table-level privileges. RLS policies only restrict
-- WHICH rows a role can see/touch - they don't grant baseline access to
-- the table itself. That setup script had no explicit `grant` statements
-- (matching sql/audit-log-setup.sql's precedent, which also has none and
-- works correctly elsewhere in this app), on the assumption Supabase's
-- default privilege setup already covers new public-schema tables the
-- same way it does for every other tenant-scoped table (business_items,
-- tasks, etc.). This query confirms that assumption rather than trusting
-- it blind.

-- 1. Table + column shape.
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'tenant_integrations'
order by ordinal_position;

-- 2. RLS is actually enabled (not just policies existing - a table can
--    have policies defined while RLS itself is off, which would make
--    every policy a no-op and expose every tenant's rows to every user).
select relrowsecurity as rls_enabled
from pg_class
where relname = 'tenant_integrations';

-- 3. The 4 policies - names, command, and roles should match exactly:
--    2x authenticated select (tenant-scoped + admin-scoped), 1x
--    authenticated insert, 1x authenticated update. No delete policy
--    should appear (disconnect is a status update, not a row delete).
select policyname, cmd, roles, qual, with_check
from pg_policies
where tablename = 'tenant_integrations'
order by policyname;

-- 4. Base table-level grants to authenticated - the thing the setup
--    script itself couldn't confirm. Expect SELECT, INSERT, UPDATE
--    present for 'authenticated' (no DELETE, matching the RLS policies
--    above). If this comes back empty for authenticated, the RLS
--    policies above are unreachable and every client request will fail
--    with a permission error before RLS is even evaluated - the fix
--    would be a one-line `grant select, insert, update on
--    public.tenant_integrations to authenticated;`.
select grantee, privilege_type
from information_schema.table_privileges
where table_schema = 'public' and table_name = 'tenant_integrations'
order by grantee, privilege_type;

-- 5. Unique constraint on (tenant_id, integration_type) and the FK to
--    tenants(id) both exist.
select conname, contype, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = 'public.tenant_integrations'::regclass
order by conname;
