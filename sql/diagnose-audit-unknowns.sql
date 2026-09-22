-- Diagnostic only, no writes. Run in Supabase SQL editor and paste back
-- all three result sets. Confirms the two "unknown, could not verify from
-- code alone" items flagged in the sidebar/nav audit (Section J).

-- 1) Did sql/tasks-linked-item-id.sql actually run? (expect 1 row)
select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'tasks' and column_name = 'linked_item_id';

-- 2) Did the Support Access admin-scoping fix run? Every one of the 21
-- policies should now reference is_ungani_admin() in its qual/with_check.
-- expect: policies_missing_admin_check = 0
select
  count(*) filter (where qual not like '%is_ungani_admin%' and (with_check is null or with_check not like '%is_ungani_admin%')) as policies_missing_admin_check,
  count(*) as total_support_access_policies
from pg_policies
where schemaname = 'public'
  and (qual like '%ungani_support_access_grants%' or with_check like '%ungani_support_access_grants%');

-- 3) Did the owner-check v2 fix run on the grants table's own
-- insert/update policy? expect the policy definition to NOT contain the
-- bare `lower(u.role) = 'owner'` check as its only owner test.
select policyname, cmd, qual, with_check
from pg_policies
where schemaname = 'public' and tablename = 'ungani_support_access_grants';
