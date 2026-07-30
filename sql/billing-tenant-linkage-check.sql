-- Read-only diagnostic. Confirms the QA Test billing-record bug: admin
-- created a record in admin-billing.html for "UNGANI QA Test - DELETE ME"
-- (known tenant_id 123b3687-02f7-45fb-a059-32ec49c3e55e), but the same
-- client's my-billing.html shows 0 records via get_my_ungani_payments().
-- Run as the DB owner/service role in the Supabase SQL editor.

-- Part A: pull the actual source of both RPCs involved - definitive proof
-- of which table each one reads/writes, and how each one identifies
-- "the tenant" (a session-derived tenant id vs. a passed-in argument).
-- Cuts through guessing before looking at any data.
select p.proname, pg_get_functiondef(p.oid) as source
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'create_admin_ungani_billing_record',
    'get_my_ungani_payments',
    'get_my_ungani_tenant_id'
  )
order by p.proname;

-- Part B: the QA tenant's real, canonical id and name, straight from tenants.
select id as real_tenant_id, business_name, created_at
from tenants
where id = '123b3687-02f7-45fb-a059-32ec49c3e55e'
   or business_name ilike '%QA Test%';

-- Part C: every billing-record-shaped row that could plausibly be "the"
-- record admin just created - by matching tenant_id, and separately by
-- recency, so a row with a WRONG tenant_id still turns up.
select
  id,
  tenant_id,
  tenant_id = '123b3687-02f7-45fb-a059-32ec49c3e55e' as tenant_id_matches_qa,
  package_key,
  amount,
  currency,
  payment_status,
  invoice_number,
  created_at
from ungani_billing_records
where tenant_id = '123b3687-02f7-45fb-a059-32ec49c3e55e'
   or created_at > now() - interval '2 hours'
order by created_at desc
limit 20;

-- Part D: same recency check against the older "payments" table, in case
-- create_admin_ungani_billing_record and get_my_ungani_payments turn out
-- (per Part A) to actually target two DIFFERENT tables rather than the
-- same tenant_id column landing on two different values.
select
  id,
  tenant_id,
  tenant_id = '123b3687-02f7-45fb-a059-32ec49c3e55e' as tenant_id_matches_qa,
  package_key,
  amount,
  status,
  created_at
from payments
where tenant_id = '123b3687-02f7-45fb-a059-32ec49c3e55e'
   or created_at > now() - interval '2 hours'
order by created_at desc
limit 20;
