select check_name, result
from (
  select 'STEP1: ungani_packages.storage_limit_mb values' as check_name,
    string_agg(package_key || '=' || coalesce(storage_limit_mb::text, 'NULL'), ', ' order by sort_order) as result
  from public.ungani_packages

  union all

  select 'STEP1: tenants.storage_limit_mb is nullable (NOT NULL dropped)?',
    (not attnotnull)::text
  from pg_attribute
  where attrelid = 'public.tenants'::regclass and attname = 'storage_limit_mb'

  union all

  select 'STEP2: documents.file_size_bytes column exists?',
    (count(*) > 0)::text
  from information_schema.columns
  where table_schema = 'public' and table_name = 'documents' and column_name = 'file_size_bytes'

  union all

  select 'STEP3: documents bucket exists, public flag',
    coalesce((select public::text from storage.buckets where id = 'documents'), 'MISSING')

  union all

  select 'STEP3: documents_bucket_* policy count (expect 4)',
    (select count(*)::text from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname like 'documents_bucket_%')

  union all

  select 'STEP4: admin_set_ungani_storage_override exists?',
    (count(*) > 0)::text
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'admin_set_ungani_storage_override'

  union all

  select 'STEP5: get_my_ungani_storage_usage current return columns (old=proof_*, new=file_count/bytes_used)',
    pg_get_function_result(p.oid)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'get_my_ungani_storage_usage'

  union all

  select 'STEP6: admin_get_ungani_storage_usage current return columns',
    pg_get_function_result(p.oid)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'admin_get_ungani_storage_usage'
) checks;
