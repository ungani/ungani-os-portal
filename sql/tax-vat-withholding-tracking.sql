-- UNGANI OS: VAT / withholding tax tracking (Money module, Phase 1 of 3).
-- Additive only - existing columns/rows untouched. Run this once against
-- the live database before the app code that reads/writes these columns
-- goes live (my-money.html Phase 2, shipped in the same session).
--
-- Design (agreed with user before building):
--   - VAT is treated as INCLUSIVE of transactions.amount - i.e. `amount`
--     is what actually moved (what hit M-Pesa/the bank), and vat_amount
--     is the portion of that figure that is VAT, extracted via
--     amount * rate / (100 + rate). This matches how small Kenyan
--     businesses record cash movements and avoids needing a second
--     "gross vs net" amount field that could drift out of sync with the
--     real transaction. vat_amount is computed by the app at save time
--     and stored (not a generated column), so historical figures don't
--     silently change if the calculation logic is ever revisited.
--   - Withholding tax amount is NOT auto-derived from a formula the same
--     way - WHT conventions vary (sometimes the recorded amount is
--     already net of WHT, sometimes not), so the app auto-suggests
--     withholding_amount from withholding_rate but leaves it editable -
--     a bookkeeper's actual WHT certificate figure should win over a
--     guess.
--   - vat_registered / default_vat_rate live on tenants (business-wide
--     config, same home as business_type/selected_sections) rather than
--     client_settings (theme-only) or user_preferences (per-user, and
--     its existing currency field is already unused dead weight
--     elsewhere in the app). No business-wide default exists for
--     withholding tax - WHT rates vary too much by transaction type
--     (goods vs professional fees vs contractors) for one default to be
--     meaningful, so it's per-transaction only.
--   - The VAT section of the Add/Edit Money Record form is hidden
--     entirely unless tenants.vat_registered is true, since most small
--     businesses (under the ~5M KES annual turnover threshold) aren't
--     VAT-registered and showing them a VAT field would be actively
--     confusing. Withholding tax has no such gate - it can apply to any
--     business's B2B income regardless of VAT status.

alter table public.transactions
  add column if not exists vat_applicable boolean not null default false,
  add column if not exists vat_rate numeric(5,2),
  add column if not exists vat_amount numeric(14,2),
  add column if not exists withholding_applicable boolean not null default false,
  add column if not exists withholding_rate numeric(5,2),
  add column if not exists withholding_amount numeric(14,2);

alter table public.transactions
  drop constraint if exists transactions_vat_rate_range_chk,
  add constraint transactions_vat_rate_range_chk
    check (vat_rate is null or (vat_rate >= 0 and vat_rate <= 100));

alter table public.transactions
  drop constraint if exists transactions_withholding_rate_range_chk,
  add constraint transactions_withholding_rate_range_chk
    check (withholding_rate is null or (withholding_rate >= 0 and withholding_rate <= 100));

alter table public.transactions
  drop constraint if exists transactions_vat_amount_nonneg_chk,
  add constraint transactions_vat_amount_nonneg_chk
    check (vat_amount is null or vat_amount >= 0);

alter table public.transactions
  drop constraint if exists transactions_withholding_amount_nonneg_chk,
  add constraint transactions_withholding_amount_nonneg_chk
    check (withholding_amount is null or withholding_amount >= 0);

alter table public.tenants
  add column if not exists vat_registered boolean not null default false,
  add column if not exists default_vat_rate numeric(5,2) not null default 16.00;

alter table public.tenants
  drop constraint if exists tenants_default_vat_rate_range_chk,
  add constraint tenants_default_vat_rate_range_chk
    check (default_vat_rate >= 0 and default_vat_rate <= 100);

-- Lightweight index for the Money dashboard's "this month" VAT/WHT KPI
-- queries, which filter on tenant_id + transaction_date and only care
-- about rows where one of these flags is true.
create index if not exists transactions_tax_applicable_idx
  on public.transactions (tenant_id, transaction_date)
  where vat_applicable = true or withholding_applicable = true;
