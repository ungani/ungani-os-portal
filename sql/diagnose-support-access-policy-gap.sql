-- Diagnostic only, no writes. Run in Supabase SQL editor and paste back
-- the full result set. Pulls the real, current definition of all 21
-- Support Access-related RLS policies so we can see exactly which ones
-- are missing is_ungani_admin() and what they actually check instead,
-- rather than guessing from the migration files on disk.

select
  schemaname,
  tablename,
  policyname,
  cmd,
  permissive,
  roles,
  qual,
  with_check,
  (qual like '%is_ungani_admin%' or with_check like '%is_ungani_admin%') as has_admin_check
from pg_policies
where schemaname = 'public'
  and (qual like '%ungani_support_access_grants%' or with_check like '%ungani_support_access_grants%')
order by tablename, policyname;
