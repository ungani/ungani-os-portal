-- Read-only. Confirms the working theory: admin_update_ungani_subscription's
-- `insert ... on conflict (tenant_id) do update ...` requires a unique
-- constraint or unique index on tenant_id. If it's missing, this exact
-- statement fails with a genuine Postgres error every time the function
-- runs - "there is no unique or exclusion constraint matching the ON
-- CONFLICT specification" - explaining the 500 on every status change,
-- regardless of which status or tenant.

select
  conname,
  contype,  -- 'u' = unique, 'p' = primary key, 'f' = foreign key, 'c' = check
  pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = 'public.ungani_subscriptions'::regclass
order by contype, conname;

-- Also check unique INDEXES specifically (a unique index on tenant_id
-- would satisfy ON CONFLICT even without a named constraint).
select indexname, indexdef
from pg_indexes
where schemaname = 'public'
  and tablename = 'ungani_subscriptions';
