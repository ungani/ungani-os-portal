-- UNGANI OS: Multi-currency (KES/USD) support for the Money module.
-- Run this once in the Supabase SQL editor.
--
-- Design (agreed with user before building):
--   - KES stays the fixed home/base currency for every total, VAT/
--     withholding calculation, and report - USD is an optional ENTRY
--     currency only, not a symmetric second ledger. This is why every
--     new tax-related column below has a "_kes" twin rather than the
--     app tracking two parallel sets of totals.
--   - Scope is fixed at exactly KES/USD, opted into per-tenant via
--     tenants.multi_currency_enabled - not a general N-currency
--     framework, matching the actual ask. There is deliberately no
--     tenants.base_currency column - the base is always KES, not
--     configurable.
--   - A rate is fetched once daily (see api/fetch-exchange-rate.js) from
--     open.er-api.com (free, no key, and only updates once/24h anyway -
--     matching this table's own one-row-per-calendar-day grain) and
--     LOCKED onto each transaction at save time, not re-derived at
--     report time. This matches real accounting practice (QuickBooks/
--     Xero do the same) - a transaction's KES-equivalent must stay
--     reproducible later, not drift every time the page is reopened.
--   - transactions.exchange_rate is stored as 1 (not null) for KES-
--     currency rows - a harmless no-op multiplier that avoids scattering
--     null-guards through every read site.
--   - amount_kes/vat_amount_kes/withholding_amount_kes are computed and
--     stored by the app at save time (not generated columns), same
--     precedent as vat_amount in sql/tax-vat-withholding-tracking.sql -
--     for a KES-currency row these are always identical to their native
--     twins, so every existing tenant who never enables this feature is
--     completely unaffected (amount_kes = amount, byte for byte). This
--     is what lets the dashboard/report/CSV changes in this feature
--     switch to reading the _kes columns everywhere without a separate
--     "is this tenant multi-currency" branch at every read site.
--   - amount_kes is NOT NULL (every transaction has an amount, so it
--     always has a KES-equivalent); vat_amount_kes/withholding_amount_kes
--     stay nullable, mirroring vat_amount/withholding_amount's own
--     nullability (only set when vat_applicable/withholding_applicable).
--   - exchange_rates is a small shared (NOT tenant-scoped) lookup table -
--     one row per calendar date, since the rate is the same for every
--     tenant. Only the service-role cron writes to it; tenant users only
--     ever read it, hence a read-only RLS policy/grant for
--     `authenticated` and no insert/update grant at all.

create table if not exists public.exchange_rates (
  id uuid primary key default gen_random_uuid(),
  rate_date date not null unique,
  base_currency text not null default 'USD',
  quote_currency text not null default 'KES',
  rate numeric(12,4) not null,
  source text not null default 'open.er-api.com',
  fetched_at timestamptz not null default now()
);

alter table public.exchange_rates enable row level security;

drop policy if exists "Authenticated users can read exchange rates" on public.exchange_rates;
create policy "Authenticated users can read exchange rates"
  on public.exchange_rates for select
  to authenticated
  using (true);

grant select on public.exchange_rates to authenticated;

-- transactions: native-currency entry + locked KES-equivalent columns.
-- Additive only - existing columns/rows untouched beyond the one-time
-- backfill below.
alter table public.transactions
  add column if not exists currency text not null default 'KES',
  add column if not exists exchange_rate numeric(12,4) not null default 1,
  add column if not exists amount_kes numeric(14,2),
  add column if not exists vat_amount_kes numeric(14,2),
  add column if not exists withholding_amount_kes numeric(14,2);

alter table public.transactions
  drop constraint if exists transactions_currency_chk,
  add constraint transactions_currency_chk
    check (currency in ('KES', 'USD'));

-- Backfill: every transaction recorded before this migration is a KES
-- row by definition (currency/exchange_rate default to 'KES'/1 above),
-- so its _kes columns are simply its already-correct native values - no
-- historical data is reinterpreted or estimated.
update public.transactions
set amount_kes = amount,
    vat_amount_kes = vat_amount,
    withholding_amount_kes = withholding_amount
where amount_kes is null;

alter table public.transactions
  alter column amount_kes set not null;

-- tenants: per-tenant opt-in only.
alter table public.tenants
  add column if not exists multi_currency_enabled boolean not null default false;
