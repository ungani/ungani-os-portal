-- Fixes a real gap found via sql/verify-ungani-support-access.sql's
-- PART 1 query 4: sql/ungani-support-access.sql created RLS policies but
-- never explicitly granted base table-level privileges to the
-- `authenticated` role. RLS policies only restrict WHICH rows a role can
-- touch - they don't grant baseline access to the table itself. Without
-- this grant, every request from a real logged-in owner/client fails
-- before RLS is even evaluated (authenticated had only REFERENCES/
-- TRIGGER/TRUNCATE - default privileges that don't cover normal app
-- usage at all).
--
-- This is the THIRD table this exact bug class has hit this session,
-- after tenant_integrations (sql/fix-tenant-integrations-missing-grants.sql)
-- and ungani_email_queue (sql/fix-email-queue-missing-grants.sql). See
-- sql/check-all-tables-missing-grants.sql for a systematic sweep of every
-- other table for the same pattern.
--
-- Only SELECT/INSERT/UPDATE - matching the RLS policies already in
-- place. No DELETE, matching that no delete policy was granted either
-- (revoking/expiring is a status update, not a row delete).

grant select, insert, update on public.ungani_support_access_grants to authenticated;

-- Verification - run after the above. Expect SELECT, INSERT, UPDATE now
-- present for 'authenticated' alongside the REFERENCES/TRIGGER/TRUNCATE
-- it already had.
select grantee, privilege_type
from information_schema.table_privileges
where table_schema = 'public' and table_name = 'ungani_support_access_grants'
order by grantee, privilege_type;
