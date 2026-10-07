-- Blocking dependency found while wiring the "same number everywhere"
-- rule into the frontend: client.html's dashboard, Person 360
-- (client-shared.js), reports.html's Profit per Property, and
-- my-customer-invoices.html's statement all read leases through
-- get_my_ungani_commitments() - but that RPC's jsonb payload (sql/
-- deposits-feature.sql:318-373, the live version) never included
-- balance_owed/credit_balance/opening_balance_* at all. Without this,
-- every page would read `lease.balance_owed` as undefined and silently
-- show Ksh 0 everywhere - the opposite of what was just asked for.
--
-- Also fixes a real bug in get_my_ungani_total_outstanding_rent()
-- (sql/mpesa-rent-invoice-unification-and-catchup.sql): it filtered
-- open invoices to invoice_type = 'rent' only, which would have EXCLUDED
-- Henry's water bill (invoice_type = 'general') from the dashboard
-- total - but your confirmed Part 4 total (269,500) includes it. Fixed
-- to scope by "customer currently holds an active lease" instead of by
-- invoice_type, which is what actually produces 269,500.
--
-- And adds customer_person_id to get_my_ungani_customer_invoices()'s
-- payload (sql/task2-branding-and-customer-invoicing.sql:504-545) -
-- currently absent, which is why my-debtors-payables.html's own comment
-- says it has to group by customer_name instead of person_id. Debtors
-- needs it to merge an invoice-based debtor with that same person's
-- lease balance into one row.
--
-- All three are 0-parameter functions - CREATE OR REPLACE with the
-- SAME signature, zero overload risk. Re-running this file is a no-op
-- change to anything already correct.

begin;

create or replace function public.get_my_ungani_commitments()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_rows jsonb;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', c.id,
      'commitment_type', c.commitment_type,
      'person_id', c.person_id,
      'person_name', p.full_name,
      'linked_item_id', c.linked_item_id,
      'linked_item_name', coalesce(bi.item_name, bi.name, bi.title, bi.property_name),
      'plan_name', c.plan_name,
      'amount', c.amount,
      'billing_frequency', c.billing_frequency,
      'start_date', c.start_date,
      'end_date', c.end_date,
      'status', c.status,
      'auto_renew', c.auto_renew,
      'section_label', c.section_label,
      'notes', c.notes,
      'created_at', c.created_at,
      'balance_owed', c.balance_owed,
      'credit_balance', c.credit_balance,
      'last_accrued_period', c.last_accrued_period,
      'opening_balance_amount', c.opening_balance_amount,
      'opening_balance_set_at', c.opening_balance_set_at,
      'deposit_amount_kes', c.deposit_amount_kes,
      'deposit_status', c.deposit_status,
      'deposit_refunded_kes', c.deposit_refunded_kes,
      'deposit_refund_method', c.deposit_refund_method,
      'deposit_deducted_kes', c.deposit_deducted_kes,
      'deposit_deduction_type', c.deposit_deduction_type,
      'deposit_settlement_note', c.deposit_settlement_note,
      'deposit_settled_at', c.deposit_settled_at,
      'deposit_settled_by', c.deposit_settled_by
    )
    order by c.end_date nulls last, c.created_at desc
  ), '[]'::jsonb)
  into v_rows
  from public.ungani_commitments c
  left join public.client_people p on p.id = c.person_id
  left join public.business_items bi on bi.id = c.linked_item_id
  where c.tenant_id = v_tenant_id
    and c.deleted_at is null;

  return jsonb_build_object('ok', true, 'commitments', v_rows);
end;
$function$;

revoke all on function public.get_my_ungani_commitments() from public, anon;
grant execute on function public.get_my_ungani_commitments() to authenticated;

create or replace function public.get_my_ungani_customer_invoices()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_invoices jsonb;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', i.id,
      'invoice_number', i.invoice_number,
      'customer_name', i.customer_name,
      'customer_person_id', i.customer_person_id,
      'invoice_type', i.invoice_type,
      'issue_date', i.issue_date,
      'due_date', i.due_date,
      'total_amount', i.total_amount,
      'amount_paid', i.amount_paid,
      'currency', i.currency,
      'status', i.status,
      'effective_status', case
        when i.status in ('sent', 'partially_paid') and i.due_date is not null and i.due_date < current_date
          then 'overdue'
        else i.status
      end
    )
    order by i.created_at desc
  ), '[]'::jsonb)
  into v_invoices
  from public.ungani_customer_invoices i
  where i.tenant_id = v_tenant_id
    and i.deleted_at is null;

  return jsonb_build_object('ok', true, 'invoices', v_invoices);
end;
$function$;

revoke all on function public.get_my_ungani_customer_invoices() from public, anon;
grant execute on function public.get_my_ungani_customer_invoices() to authenticated;

-- Fix: scope by "customer currently holds an active lease with this
-- tenant" instead of invoice_type = 'rent', matching the confirmed real
-- total (269,500 for Demo Properties Ltd, which includes Henry's
-- 'general'-type water bill).
create or replace function public.get_my_ungani_total_outstanding_rent()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
stable
as $function$
declare
  v_tenant_id uuid;
  v_lease_owed numeric := 0;
  v_tenant_invoice_owed numeric := 0;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  select coalesce(sum(greatest(balance_owed, 0)), 0) into v_lease_owed
  from public.ungani_commitments
  where tenant_id = v_tenant_id
    and commitment_type = 'lease'
    and status = 'active'
    and deleted_at is null;

  select coalesce(sum(greatest(i.total_amount - i.amount_paid, 0)), 0) into v_tenant_invoice_owed
  from public.ungani_customer_invoices i
  where i.tenant_id = v_tenant_id
    and i.status in ('sent', 'partially_paid')
    and i.deleted_at is null
    and i.customer_person_id in (
      select person_id from public.ungani_commitments
      where tenant_id = v_tenant_id
        and commitment_type = 'lease'
        and status = 'active'
        and deleted_at is null
    );

  return jsonb_build_object(
    'ok', true,
    'lease_owed', v_lease_owed,
    'tenant_invoice_owed', v_tenant_invoice_owed,
    'total_outstanding_rent', v_lease_owed + v_tenant_invoice_owed
  );
end;
$function$;

revoke all on function public.get_my_ungani_total_outstanding_rent() from public, anon, authenticated;
grant execute on function public.get_my_ungani_total_outstanding_rent() to authenticated;

commit;

-- ============================================================
-- VERIFICATION - confirm Demo Properties Ltd's total via the RPC's own
-- logic matches the 269,500 you already confirmed from raw SQL.
-- ============================================================

select
  t.business_name,
  (select coalesce(sum(greatest(c.balance_owed, 0)), 0)
     from public.ungani_commitments c
     where c.tenant_id = t.id and c.commitment_type = 'lease' and c.status = 'active' and c.deleted_at is null) as lease_owed,
  (select coalesce(sum(greatest(i.total_amount - i.amount_paid, 0)), 0)
     from public.ungani_customer_invoices i
     where i.tenant_id = t.id and i.status in ('sent', 'partially_paid') and i.deleted_at is null
       and i.customer_person_id in (
         select person_id from public.ungani_commitments
         where tenant_id = t.id and commitment_type = 'lease' and status = 'active' and deleted_at is null
       )) as tenant_invoice_owed
from public.tenants t
where lower(trim(t.business_name)) = lower(trim('Demo Properties Ltd'));
