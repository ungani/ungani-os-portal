select check_name, result, pass
from (
  -- Bucket privacy
  select
    'documents bucket: public flag (expect false)' as check_name,
    public::text as result,
    (public = false) as pass
  from storage.buckets where id = 'documents'

  union all

  -- Storage policies scope to own tenant folder + per-staff Documents permission
  select
    'storage policy ' || policyname || ': scoped to own tenant folder (expect true)',
    (qual like '%get_my_ungani_tenant_id%' or with_check like '%get_my_ungani_tenant_id%')::text,
    (qual like '%get_my_ungani_tenant_id%' or with_check like '%get_my_ungani_tenant_id%')
  from pg_policies
  where schemaname = 'storage' and tablename = 'objects' and policyname like 'documents_bucket_%'

  union all

  select
    'storage policy ' || policyname || ': gated by can_access_ungani_section (expect true)',
    (qual like '%can_access_ungani_section%' or with_check like '%can_access_ungani_section%')::text,
    (qual like '%can_access_ungani_section%' or with_check like '%can_access_ungani_section%')
  from pg_policies
  where schemaname = 'storage' and tablename = 'objects' and policyname like 'documents_bucket_%'

  union all

  select 'storage policy count on documents bucket (expect 4)',
    count(*)::text,
    (count(*) = 4)
  from pg_policies
  where schemaname = 'storage' and tablename = 'objects' and policyname like 'documents_bucket_%'

  union all

  -- Overload counts
  select 'get_my_ungani_storage_usage: overload count (expect 1)',
    count(*)::text, (count(*) = 1)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'get_my_ungani_storage_usage'

  union all

  select 'admin_get_ungani_storage_usage: overload count (expect 1)',
    count(*)::text, (count(*) = 1)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'admin_get_ungani_storage_usage'

  union all

  select 'admin_set_ungani_storage_override: overload count (expect 1)',
    count(*)::text, (count(*) = 1)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'admin_set_ungani_storage_override'

  union all

  -- Grants: PUBLIC/anon revoked, authenticated can execute - all 3 functions
  select 'get_my_ungani_storage_usage: PUBLIC can execute (expect false)',
    has_function_privilege('public', 'public.get_my_ungani_storage_usage()', 'execute')::text,
    not has_function_privilege('public', 'public.get_my_ungani_storage_usage()', 'execute')
  union all
  select 'get_my_ungani_storage_usage: anon can execute (expect false)',
    has_function_privilege('anon', 'public.get_my_ungani_storage_usage()', 'execute')::text,
    not has_function_privilege('anon', 'public.get_my_ungani_storage_usage()', 'execute')
  union all
  select 'get_my_ungani_storage_usage: authenticated can execute (expect true)',
    has_function_privilege('authenticated', 'public.get_my_ungani_storage_usage()', 'execute')::text,
    has_function_privilege('authenticated', 'public.get_my_ungani_storage_usage()', 'execute')

  union all

  select 'admin_get_ungani_storage_usage: PUBLIC can execute (expect false)',
    has_function_privilege('public', 'public.admin_get_ungani_storage_usage()', 'execute')::text,
    not has_function_privilege('public', 'public.admin_get_ungani_storage_usage()', 'execute')
  union all
  select 'admin_get_ungani_storage_usage: anon can execute (expect false)',
    has_function_privilege('anon', 'public.admin_get_ungani_storage_usage()', 'execute')::text,
    not has_function_privilege('anon', 'public.admin_get_ungani_storage_usage()', 'execute')
  union all
  select 'admin_get_ungani_storage_usage: authenticated can execute (expect true)',
    has_function_privilege('authenticated', 'public.admin_get_ungani_storage_usage()', 'execute')::text,
    has_function_privilege('authenticated', 'public.admin_get_ungani_storage_usage()', 'execute')

  union all

  select 'admin_set_ungani_storage_override: PUBLIC can execute (expect false)',
    has_function_privilege('public', 'public.admin_set_ungani_storage_override(uuid, integer)', 'execute')::text,
    not has_function_privilege('public', 'public.admin_set_ungani_storage_override(uuid, integer)', 'execute')
  union all
  select 'admin_set_ungani_storage_override: anon can execute (expect false)',
    has_function_privilege('anon', 'public.admin_set_ungani_storage_override(uuid, integer)', 'execute')::text,
    not has_function_privilege('anon', 'public.admin_set_ungani_storage_override(uuid, integer)', 'execute')
  union all
  select 'admin_set_ungani_storage_override: authenticated can execute (expect true)',
    has_function_privilege('authenticated', 'public.admin_set_ungani_storage_override(uuid, integer)', 'execute')::text,
    has_function_privilege('authenticated', 'public.admin_set_ungani_storage_override(uuid, integer)', 'execute')

  union all

  -- Package storage limits
  select 'ungani_packages.storage_limit_mb: starter (expect 1024)',
    storage_limit_mb::text, (storage_limit_mb = 1024)
  from public.ungani_packages where package_key = 'starter'
  union all
  select 'ungani_packages.storage_limit_mb: growth (expect 5120)',
    storage_limit_mb::text, (storage_limit_mb = 5120)
  from public.ungani_packages where package_key = 'growth'
  union all
  select 'ungani_packages.storage_limit_mb: business (expect 20480)',
    storage_limit_mb::text, (storage_limit_mb = 20480)
  from public.ungani_packages where package_key = 'business'
  union all
  select 'ungani_packages.storage_limit_mb: custom (expect 102400)',
    storage_limit_mb::text, (storage_limit_mb = 102400)
  from public.ungani_packages where package_key = 'custom'
) checks
order by check_name;

-- NOTE: this query proves the POLICY DEFINITIONS reference both the
-- tenant-folder check and can_access_ungani_section('documents', ...).
-- It cannot prove the *behavior* (a real staff session with Documents
-- permission off actually gets denied, or that opening another
-- business's file fails) - that requires a live test against real
-- sessions, which is run separately and reported alongside this.
