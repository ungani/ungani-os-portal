select check_name, result, pass
from (
  select
    'owner_upsert_ungani_commitment: overload count (expect 1)' as check_name,
    count(*)::text as result,
    (count(*) = 1) as pass
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'owner_upsert_ungani_commitment'

  union all

  select
    'owner_upsert_ungani_commitment: PUBLIC can execute (expect false)',
    has_function_privilege('public', 'public.owner_upsert_ungani_commitment(uuid, text, uuid, uuid, text, numeric, text, date, date, text, boolean, text, text, numeric)', 'execute')::text,
    not has_function_privilege('public', 'public.owner_upsert_ungani_commitment(uuid, text, uuid, uuid, text, numeric, text, date, date, text, boolean, text, text, numeric)', 'execute')

  union all

  select
    'owner_upsert_ungani_commitment: anon can execute (expect false)',
    has_function_privilege('anon', 'public.owner_upsert_ungani_commitment(uuid, text, uuid, uuid, text, numeric, text, date, date, text, boolean, text, text, numeric)', 'execute')::text,
    not has_function_privilege('anon', 'public.owner_upsert_ungani_commitment(uuid, text, uuid, uuid, text, numeric, text, date, date, text, boolean, text, text, numeric)', 'execute')

  union all

  select
    'owner_upsert_ungani_commitment: authenticated can execute (expect true)',
    has_function_privilege('authenticated', 'public.owner_upsert_ungani_commitment(uuid, text, uuid, uuid, text, numeric, text, date, date, text, boolean, text, text, numeric)', 'execute')::text,
    has_function_privilege('authenticated', 'public.owner_upsert_ungani_commitment(uuid, text, uuid, uuid, text, numeric, text, date, date, text, boolean, text, text, numeric)', 'execute')

  union all

  select
    'owner_settle_ungani_commitment_deposit: PUBLIC can execute (expect false)',
    has_function_privilege('public', 'public.owner_settle_ungani_commitment_deposit(uuid, numeric, numeric, text, text, text)', 'execute')::text,
    not has_function_privilege('public', 'public.owner_settle_ungani_commitment_deposit(uuid, numeric, numeric, text, text, text)', 'execute')

  union all

  select
    'owner_settle_ungani_commitment_deposit: anon can execute (expect false)',
    has_function_privilege('anon', 'public.owner_settle_ungani_commitment_deposit(uuid, numeric, numeric, text, text, text)', 'execute')::text,
    not has_function_privilege('anon', 'public.owner_settle_ungani_commitment_deposit(uuid, numeric, numeric, text, text, text)', 'execute')

  union all

  select
    'owner_settle_ungani_commitment_deposit: authenticated can execute (expect true)',
    has_function_privilege('authenticated', 'public.owner_settle_ungani_commitment_deposit(uuid, numeric, numeric, text, text, text)', 'execute')::text,
    has_function_privilege('authenticated', 'public.owner_settle_ungani_commitment_deposit(uuid, numeric, numeric, text, text, text)', 'execute')
) checks
order by check_name;
