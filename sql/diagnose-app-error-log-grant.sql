-- Diagnostic only, no writes. Compares table-level GRANTs between
-- app_error_log (broken, 403 "permission denied") and ungani_audit_log
-- (working) to confirm the missing-grant theory before fixing anything.

select table_name, grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in ('app_error_log', 'ungani_audit_log')
order by table_name, grantee, privilege_type;
