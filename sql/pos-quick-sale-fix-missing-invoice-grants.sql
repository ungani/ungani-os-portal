-- Real gap found live-testing the M-Pesa POS path: api/mpesa-stk-push.js
-- now reads/writes ungani_customer_invoices and ungani_customer_invoice_items
-- directly via the service-role client (to look up the sale amount before
-- STK push, and to read line items + flag stock shortfalls in the
-- callback) - this needs an actual table-level GRANT, since service_role
-- bypassing RLS is NOT the same as having a GRANT on the table. These 3
-- tables were only ever granted to `authenticated` (sql/task2-branding-
-- and-customer-invoicing.sql:161,186,214) - every existing read/write
-- path went through SECURITY DEFINER RPCs instead, which never needed
-- the caller's own grants. This is the same missing-grant bug class
-- already found and fixed elsewhere in this project multiple times.
--
-- Matches the exact pattern already used for ungani_mpesa_transactions
-- (sql/task11-mpesa-stk-push.sql:73: `grant all ... to service_role`).

grant all on public.ungani_customer_invoices to service_role;
grant all on public.ungani_customer_invoice_items to service_role;
grant all on public.ungani_customer_invoice_payments to service_role;

-- ============================================================
-- VERIFICATION - run this and paste back the output.
-- ============================================================

select table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in ('ungani_customer_invoices', 'ungani_customer_invoice_items', 'ungani_customer_invoice_payments')
  and grantee = 'service_role'
order by table_name, privilege_type;
