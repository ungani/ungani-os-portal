-- Read-only. Prep for fixing the ungani_billing_records / ungani_payments
-- table-split bug: admin-billing.html's create/mark-paid/list functions
-- write and read ungani_billing_records, an orphaned table nothing else
-- in the app touches, while every other payment/invoice/proof surface
-- (client Billing, client Invoice, admin Invoice, the entire payment-proof
-- submit/review/accept chain) reads and writes ungani_payments instead.
-- Fix direction: redirect the admin-billing.html-side functions to target
-- ungani_payments. This pulls exactly what's needed to write that fix
-- precisely instead of guessing column names.

-- Part A: the two admin-billing.html functions not yet pulled
-- (create_admin_ungani_billing_record's source was already retrieved in
-- billing-tenant-linkage-check.sql - re-included here for convenience).
select p.proname, pg_get_functiondef(p.oid) as source
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'create_admin_ungani_billing_record',
    'mark_admin_ungani_billing_record_paid',
    'get_admin_ungani_billing_page_data'
  )
order by p.proname;

-- Part B: full column schema of the real, load-bearing table, so the
-- rewritten INSERT/UPDATE maps every field correctly.
select column_name, data_type, udt_name, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'ungani_payments'
order by ordinal_position;

-- Part C: same, for ungani_billing_records - to confirm which fields on
-- admin-billing.html's form (amount, currency, billing_start/end, due_date,
-- paid_date, payment_status, payment_method, payment_reference,
-- invoice_number, notes, client_id, client_email) have a real equivalent
-- column on ungani_payments, and which don't (so the rewritten function
-- knows what it can safely carry over vs. what it must drop or rename).
select column_name, data_type, udt_name, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'ungani_billing_records'
order by ordinal_position;

-- Part D: is anything OTHER than admin-billing.html's own two functions
-- referencing ungani_billing_records anywhere in the database itself
-- (a view, another function, a trigger, an RLS policy)? The app-code grep
-- already showed zero JS/HTML references elsewhere, but a DB-side
-- dependency wouldn't show up there.
select
  'function' as object_type, p.proname as object_name
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prosrc ilike '%ungani_billing_records%'
  and p.proname not in ('create_admin_ungani_billing_record', 'mark_admin_ungani_billing_record_paid', 'get_admin_ungani_billing_page_data')
union all
select 'view', viewname
from pg_views
where schemaname = 'public'
  and definition ilike '%ungani_billing_records%';
