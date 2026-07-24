-- Fixes a real gap found via sql/verify-tenant-integrations-setup.sql's
-- query 4: sql/tenant-integrations-setup.sql created RLS policies but
-- never explicitly granted base table-level privileges to the
-- `authenticated` role. RLS policies only restrict WHICH rows a role can
-- touch - they don't grant baseline access to the table itself. Without
-- this grant, every request from a real logged-in client fails before
-- RLS is even evaluated (authenticated had only REFERENCES/TRIGGER/
-- TRUNCATE - default privileges that don't cover normal app usage at
-- all). This confirms the assumption in the original setup script's
-- comments (that new public-schema tables get the same default grants as
-- business_items/tasks) was wrong for this table.
--
-- Only SELECT/INSERT/UPDATE - matching the RLS policies already in
-- place. No DELETE, matching that no delete policy was granted either
-- (disconnecting is a status update, not a row delete).

grant select, insert, update on public.tenant_integrations to authenticated;

-- Verification - run after the above. Expect SELECT, INSERT, UPDATE now
-- present for 'authenticated' alongside the REFERENCES/TRIGGER/TRUNCATE
-- it already had.
select grantee, privilege_type
from information_schema.table_privileges
where table_schema = 'public' and table_name = 'tenant_integrations'
order by grantee, privilege_type;
