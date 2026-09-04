-- Task 4: Debtors/Payables toggle column.
--
-- No new tables needed - confirmed via live schema diagnostic
-- (sql/diagnose-debtors-payables-schema.sql) that both sides are fully
-- representable from existing data:
--   - Debtors ("Who Owes Me"): ungani_customer_invoices already has
--     customer_person_id/customer_name/due_date/total_amount/amount_paid/status.
--   - Payables ("Who I Owe", lean scope per user decision): transactions
--     already has related_person_id + status + transaction_type - just
--     needed the isRealEstate-only UI gate on related_person_id relaxed
--     to all business types (client-side change, no SQL).
--
-- Mirrors multi_currency_enabled's pattern exactly (plain boolean,
-- direct client-side `tenants` update, no dedicated enable/disable RPC)
-- rather than Stock Tracking's dual-RPC pattern, since there is no
-- backfill step needed here.

alter table public.tenants
  add column if not exists debtors_payables_enabled boolean not null default false;
