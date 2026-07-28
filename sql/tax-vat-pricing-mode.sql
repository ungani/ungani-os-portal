-- UNGANI OS: VAT pricing-mode correction (Money module).
-- Additive only - existing columns/rows untouched. Companion to
-- sql/tax-vat-withholding-tracking.sql, which shipped VAT-inclusive-only
-- pricing (amount * rate / (100 + rate)). This adds support for
-- VAT-exclusive quoting ("Ksh 150,000 PLUS VAT") without changing what
-- transactions.amount means anywhere else in the app.
--
-- Design (agreed with user before building):
--   - transactions.amount ALWAYS represents the actual gross cash that
--     moved, regardless of which pricing convention was used to arrive
--     at that figure. This is non-negotiable for correctness: every
--     Income/Expense/Balance total and every report reads amount
--     directly, for VAT-tagged and untagged rows alike, and letting
--     amount mean "net" for some rows and "gross" for others would
--     silently corrupt those totals in a way that's very hard to catch
--     later (a mismatch against the real bank/M-Pesa balance, discovered
--     months after the fact).
--   - Inclusive mode (unchanged from the original migration): the
--     bookkeeper types the total that moved; vat_amount is EXTRACTED via
--     amount * rate / (100 + rate).
--   - Exclusive mode (new): the bookkeeper types the pre-VAT base price;
--     the app computes vat_amount = base * rate / 100 and grosses up
--     amount = base * (1 + rate / 100) before saving - the base price
--     itself is never stored as a separate column (it's always trivially
--     recoverable as amount - vat_amount whenever needed, e.g. when
--     re-opening the record for editing).
--   - vat_pricing_mode is stored per-transaction purely so the Edit form
--     can correctly redisplay what the bookkeeper originally typed
--     (the base price, in exclusive mode) rather than showing the
--     grossed-up amount in a field they never actually entered a number
--     into - a real edit-mode confusion risk without this.
--   - default_vat_pricing_mode lives on tenants (same home as
--     default_vat_rate) so a business that always quotes exclusive (the
--     user's own example: logistics/transport, "Ksh 150,000 plus VAT")
--     doesn't have to flip the toggle on every transaction.

alter table public.transactions
  add column if not exists vat_pricing_mode text not null default 'inclusive';

alter table public.transactions
  drop constraint if exists transactions_vat_pricing_mode_chk,
  add constraint transactions_vat_pricing_mode_chk
    check (vat_pricing_mode in ('inclusive', 'exclusive'));

alter table public.tenants
  add column if not exists default_vat_pricing_mode text not null default 'inclusive';

alter table public.tenants
  drop constraint if exists tenants_default_vat_pricing_mode_chk,
  add constraint tenants_default_vat_pricing_mode_chk
    check (default_vat_pricing_mode in ('inclusive', 'exclusive'));
