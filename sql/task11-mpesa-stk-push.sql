-- ============================================================
-- M-Pesa STK Push: staging table for tracking each push attempt.
--
-- Deliberately does NOT introduce a new "confirm payment" SQL
-- function - the confirmation write-path (insert into ungani_payments
-- + call set_ungani_subscription_period_from_payment()) runs directly
-- inside api/mpesa-callback.js using the service-role client, exactly
-- mirroring how api/check-trial-warnings.js already writes to
-- ungani_subscriptions directly rather than through a wrapper RPC.
-- Keeps this migration to one new table + RLS, reusing every existing
-- confirmed-real function/table rather than inventing new ones.
--
-- Real schema this reuses (confirmed via source pulls this session,
-- not guessed):
--   - ungani_payments: tenant_id, package_key, amount, currency,
--     billing_period_start, billing_period_end, due_date, paid_at,
--     payment_status, payment_method, payment_reference,
--     invoice_number, notes, recorded_by
--     (sql/fix-billing-table-split.sql)
--   - set_ungani_subscription_period_from_payment(p_payment_id uuid)
--     (sql/subscription-reminder-cadence-and-suspension.sql)
--   - ungani_packages: package_key, package_name, monthly_price_ksh,
--     yearly_price_ksh (sql/fix-package-catalog-wrong-table-and-
--     yearly-pricing.sql)
--   - tenants.billing_cycle (used identically by
--     set_ungani_subscription_period_from_payment)
--   - get_my_ungani_current_tenant_id_v16() (confirmed real, used
--     throughout this app)
-- ============================================================

create table if not exists public.ungani_mpesa_transactions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  initiated_by uuid,
  phone_number text not null,
  amount numeric not null,
  package_key text,
  merchant_request_id text,
  checkout_request_id text unique,
  status text not null default 'pending',
  result_code integer,
  result_desc text,
  mpesa_receipt_number text,
  transaction_date timestamptz,
  payment_id uuid references public.ungani_payments(id),
  raw_callback jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_ungani_mpesa_transactions_tenant_id
  on public.ungani_mpesa_transactions(tenant_id);

create index if not exists idx_ungani_mpesa_transactions_checkout_request_id
  on public.ungani_mpesa_transactions(checkout_request_id);

alter table public.ungani_mpesa_transactions enable row level security;

drop policy if exists "Owners can view their own tenant's mpesa transactions" on public.ungani_mpesa_transactions;
create policy "Owners can view their own tenant's mpesa transactions"
  on public.ungani_mpesa_transactions
  for select
  to authenticated
  using (tenant_id = public.get_my_ungani_current_tenant_id_v16());

-- No insert/update policy for `authenticated` - every write to this
-- table happens server-side via the service-role client in
-- api/mpesa-stk-push.js (initiation) and api/mpesa-callback.js
-- (Safaricom's webhook result), same as ungani_push_sent_log and
-- other service-role-only tables already in this app.

grant select on public.ungani_mpesa_transactions to authenticated;
grant all on public.ungani_mpesa_transactions to service_role;

-- ============================================================
-- VERIFICATION - run and paste back the output.
-- ============================================================

select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'ungani_mpesa_transactions'
order by ordinal_position;

select policyname, cmd, roles
from pg_policies
where schemaname = 'public' and tablename = 'ungani_mpesa_transactions';
