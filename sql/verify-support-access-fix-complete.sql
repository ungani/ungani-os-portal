-- Final verification, no writes. Two checks:

-- 1) All 21 support-access policies, INSERT included this time (coalesce
-- avoids the qual/with_check NULL-comparison trap that undercounted the
-- first diagnostic). Expect exactly 21 rows, has_admin_check = true on
-- every single one, including business_events (excluded from Part B's
-- table list but NOT excluded from Part A's hardening).
select tablename, policyname, cmd,
  (coalesce(qual, '') || ' ' || coalesce(with_check, '')) ilike '%is_ungani_admin%' as has_admin_check
from pg_policies
where schemaname = 'public'
  and policyname like 'UNGANI support access can%'
order by tablename, cmd;

-- 2) Confirm the 11 old unconditional admin write policies are gone.
-- Expect ZERO rows.
select tablename, policyname, cmd, qual
from pg_policies
where schemaname = 'public'
  and policyname in (
    'ungani_admin_manage_business_items', 'admin_can_update_items_management',
    'ungani_admin_manage_business_records', 'admin_can_update_records_management',
    'admin_can_update_client_people',
    'ungani_admin_manage_documents', 'admin_can_update_documents_management',
    'ungani_admin_manage_tasks', 'admin_can_update_tasks_management',
    'ungani_admin_manage_transactions', 'admin_can_update_money_management'
  );
