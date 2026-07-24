-- Fixes a confirmed missing grant on ungani_email_queue - found live via
-- sql/email-queue-permission-diagnosis.sql's query 4, which impersonated
-- the REAL service_role Postgres role and got "permission denied for
-- table ungani_email_queue" with Postgres's own suggested fix. Query 1
-- confirmed service_role only had REFERENCES/TRIGGER/TRUNCATE - the same
-- class of bug as tenant_integrations' missing grant, found and fixed
-- earlier this session. This also definitively rules out the sb_secret_
-- key concern (see the GitHub discussion referenced in the diagnosis
-- file) as the cause here - a real service_role impersonation hit the
-- exact same wall, so the key format was never the problem.
--
-- SELECT: api/send-email-queue.js reads pending rows.
-- INSERT: api/check-trial-warnings.js inserts trial_warning/trial_ended
--         rows into this same table.
-- UPDATE: api/send-email-queue.js moves rows through the send lifecycle
--         (pending -> sending -> sent/failed).
-- No DELETE - nothing in this app ever removes rows from this table.

grant select, insert, update on public.ungani_email_queue to service_role;

-- Verification - run after the above. Expect SELECT, INSERT, UPDATE now
-- present for service_role alongside the REFERENCES/TRIGGER/TRUNCATE it
-- already had.
select grantee, privilege_type
from information_schema.table_privileges
where table_schema = 'public' and table_name = 'ungani_email_queue'
order by grantee, privilege_type;
