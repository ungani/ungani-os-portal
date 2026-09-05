-- Diagnostic only, no writes. Compares table-level GRANTs across all
-- relevant roles for app_error_log vs the working ungani_audit_log.
-- Round 2: the authenticated/SELECT grant fix worked (confirmed live),
-- but /api/log-app-error (service_role, bypasses RLS) now fails with the
-- SAME "permission denied for table app_error_log" error on INSERT -
-- suggesting service_role is also missing its table-level grant on this
-- one table specifically.

select table_name, grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in ('app_error_log', 'ungani_audit_log')
order by table_name, grantee, privilege_type;
