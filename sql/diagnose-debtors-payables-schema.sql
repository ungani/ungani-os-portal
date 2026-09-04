-- Re-run 2026-09-04 for Task 4 (Debtors/Payables) - extended from the
-- original version to also pull ungani_customer_invoices (shipped since
-- this file was first written, in Task 2) and to explicitly check
-- transactions for any due-date-like column, since transactions has no
-- tracked CREATE TABLE in this sql/ folder (it predates this engagement's
-- migrations) - only ALTER TABLE additions are tracked here, so its full
-- column list can't be trusted from code/migration search alone, per the
-- Task 3 lesson (business_items had 4 dead columns no grep could find).

select 'transactions' as table_name, column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'transactions'
order by column_name;

select 'client_people' as table_name, column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'client_people'
order by column_name;

select 'ungani_payees' as table_name, column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'ungani_payees'
order by column_name;

select 'ungani_customer_invoices' as table_name, column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'ungani_customer_invoices'
order by column_name;

-- Also confirms no table already exists for this (debtors/payables/
-- receivables/aging/credit-ledger/vendor-bill) under a name the code
-- search wouldn't have caught.
select table_name
from information_schema.tables
where table_schema = 'public'
  and (
    table_name ilike '%debtor%' or table_name ilike '%creditor%' or
    table_name ilike '%receivable%' or table_name ilike '%payable%' or
    table_name ilike '%aging%' or table_name ilike '%credit_ledger%' or
    table_name ilike '%account_balance%' or table_name ilike '%vendor%' or
    table_name ilike '%bill%'
  );
