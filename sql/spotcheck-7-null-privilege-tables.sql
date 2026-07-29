-- Direct, non-buggy spot-check for the 7 tables whose rows always show
-- missing_privilege = null in sql/check-all-tables-missing-grants.sql
-- (business_sections, business_types, categories, packages,
-- registrations, system_notices, testing_feedback) - a permanent
-- artifact of that query's unnest-zip bug, not a re-evaluated gap. This
-- bypasses that query entirely and reads the real grants straight from
-- information_schema.

select table_name, grantee, privilege_type
from information_schema.table_privileges
where table_schema = 'public'
  and table_name in (
    'business_sections', 'business_types', 'categories', 'packages',
    'registrations', 'system_notices', 'testing_feedback'
  )
  and grantee = 'authenticated'
order by table_name, privilege_type;

-- Expect, per table:
--   business_sections  -> SELECT
--   business_types     -> SELECT
--   categories         -> SELECT
--   packages           -> SELECT
--   registrations      -> INSERT, DELETE   (DELETE from the earlier
--                          registrations_delete_admin_only grant, still
--                          RLS-gated to admins only)
--   system_notices     -> SELECT
--   testing_feedback   -> INSERT
--
-- If every table above shows its expected privilege_type row(s), all 7
-- are confirmed genuinely fixed and this can be closed out with
-- certainty - independent of the sweep query's known blind spot.
