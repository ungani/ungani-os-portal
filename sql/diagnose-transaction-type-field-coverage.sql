-- ============================================================
-- DIAGNOSTIC ONLY - no writes. Run and paste back the output.
--
-- Answers, before isIncome()/isExpense() are cut over to reading
-- transaction_type only (dropping the category-keyword fallback):
--   1. Does every existing transaction row have transaction_type (or
--      the legacy type column) set to a real value?
--   2. If not, how many rows are missing it, broken down by tenant's
--      business type, so a backfill can be scoped and approved
--      separately - nothing here writes anything.
-- ============================================================

-- Overall picture: how many rows have a usable value in either column.
select
  count(*) as total_rows,
  count(*) filter (
    where coalesce(nullif(trim(transaction_type), ''), nullif(trim(type), '')) is not null
  ) as rows_with_direction_field,
  count(*) filter (
    where coalesce(nullif(trim(transaction_type), ''), nullif(trim(type), '')) is null
  ) as rows_missing_direction_field
from public.transactions;

-- Same, broken down per tenant's business type - the number Chris asked for.
select
  t.business_type,
  count(*) as total_rows,
  count(*) filter (
    where coalesce(nullif(trim(tx.transaction_type), ''), nullif(trim(tx.type), '')) is null
  ) as rows_missing_direction_field
from public.transactions tx
join public.tenants t on t.id = tx.tenant_id
group by t.business_type
order by rows_missing_direction_field desc, total_rows desc;

-- What values actually exist in the two columns today, so a backfill
-- (if approved later) knows what it's dealing with - e.g. confirms
-- transaction_type/type only ever hold 'income'/'expense', or reveals
-- something unexpected before any rewrite ships.
select
  nullif(trim(transaction_type), '') as transaction_type_value,
  nullif(trim(type), '') as type_value,
  count(*) as row_count
from public.transactions
group by 1, 2
order by row_count desc;
