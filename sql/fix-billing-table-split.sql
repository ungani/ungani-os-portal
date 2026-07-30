-- Fixes the ungani_billing_records / ungani_payments table-split bug:
-- admin-billing.html's create/mark-paid/list/summary functions wrote to
-- and read from ungani_billing_records, a table nothing else in the app
-- ever touches. Every other payment/invoice/proof surface (client Billing,
-- client Invoice, admin Invoice, and the entire client_submit_ungani_
-- payment_proof -> admin_accept_ungani_payment_proof_and_mark_paid chain
-- that actually unlocks a client's account) reads/writes ungani_payments.
-- Confirmed via direct RPC source pulls: get_my_ungani_payments filters
-- purely by tenant_id (no subscription_id dependency), and the client-side
-- proof chain was never broken - only these four admin-side functions were
-- pointing at the wrong table.
--
-- client_id/client_email (present on ungani_billing_records, absent on
-- ungani_payments) are dropped from what's persisted going forward -
-- they were write-only fields nothing downstream ever read back.
--
-- Run Part 1 (four function replacements) and Part 2 (one-time data
-- migration) together, in order, in the Supabase SQL editor.

-- =====================================================================
-- PART 1: redirect the four admin-side functions to ungani_payments
-- =====================================================================

CREATE OR REPLACE FUNCTION public.create_admin_ungani_billing_record(p_tenant_id uuid, p_client_id uuid DEFAULT NULL::uuid, p_client_email text DEFAULT NULL::text, p_package_key text DEFAULT 'starter'::text, p_amount numeric DEFAULT 0, p_currency text DEFAULT 'KES'::text, p_billing_start date DEFAULT NULL::date, p_billing_end date DEFAULT NULL::date, p_due_date date DEFAULT NULL::date, p_paid_date date DEFAULT NULL::date, p_payment_status text DEFAULT 'pending'::text, p_payment_method text DEFAULT NULL::text, p_payment_reference text DEFAULT NULL::text, p_invoice_number text DEFAULT NULL::text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_record public.ungani_payments;
begin
  if not public.is_ungani_admin() then
    return jsonb_build_object(
      'ok', false,
      'message', 'Admin access required.'
    );
  end if;

  -- p_client_id / p_client_email are accepted (signature unchanged, so
  -- admin-billing.html needs no JS change) but not persisted - ungani_payments,
  -- the real table this now targets, has no equivalent columns, and nothing
  -- anywhere else in the app ever reads a payment row's client identity back
  -- off it. tenant_id is already the single source of truth for that.
  insert into public.ungani_payments (
    tenant_id,
    package_key,
    amount,
    currency,
    billing_period_start,
    billing_period_end,
    due_date,
    paid_at,
    payment_status,
    payment_method,
    payment_reference,
    invoice_number,
    notes,
    recorded_by
  )
  values (
    p_tenant_id,
    coalesce(p_package_key, 'starter'),
    coalesce(p_amount, 0),
    coalesce(p_currency, 'KES'),
    p_billing_start,
    p_billing_end,
    p_due_date,
    p_paid_date,
    coalesce(p_payment_status, 'pending'),
    p_payment_method,
    p_payment_reference,
    p_invoice_number,
    p_notes,
    auth.uid()
  )
  returning *
  into v_record;

  return jsonb_build_object(
    'ok', true,
    'message', 'Billing record created.',
    'record', jsonb_build_object(
      'id', v_record.id,
      'tenant_id', v_record.tenant_id,
      'client_id', p_client_id,
      'client_email', p_client_email,
      'package_key', v_record.package_key,
      'amount', v_record.amount,
      'currency', v_record.currency,
      'billing_start', v_record.billing_period_start,
      'billing_end', v_record.billing_period_end,
      'due_date', v_record.due_date,
      'paid_date', v_record.paid_at,
      'payment_status', v_record.payment_status,
      'payment_method', v_record.payment_method,
      'payment_reference', v_record.payment_reference,
      'invoice_number', v_record.invoice_number,
      'notes', v_record.notes,
      'created_by', v_record.recorded_by,
      'created_at', v_record.created_at,
      'updated_at', v_record.updated_at
    )
  );
exception
  when others then
    return jsonb_build_object(
      'ok', false,
      'message', sqlerrm
    );
end;
$function$;


CREATE OR REPLACE FUNCTION public.get_admin_ungani_billing_page_data()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_clients jsonb := '[]'::jsonb;
  v_billing_records jsonb := '[]'::jsonb;
  v_payment_proofs jsonb := '[]'::jsonb;
begin
  if not public.is_ungani_admin() then
    return jsonb_build_object(
      'ok', false,
      'message', 'Admin access required.',
      'clients', '[]'::jsonb,
      'billing_records', '[]'::jsonb,
      'payment_proofs', '[]'::jsonb
    );
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(r) order by r.created_at desc),
    '[]'::jsonb
  )
  into v_clients
  from public.registrations r;

  -- Explicitly aliased back to the OLD field names (billing_start/
  -- billing_end/paid_date) even though the real table now underneath is
  -- ungani_payments (billing_period_start/billing_period_end/paid_at) -
  -- keeps admin-billing.html's existing JS working with zero changes.
  -- client_id/client_email/updated_by have no equivalent and come back null.
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', b.id,
        'tenant_id', b.tenant_id,
        'client_id', null,
        'client_email', null,
        'package_key', b.package_key,
        'amount', b.amount,
        'currency', b.currency,
        'billing_start', b.billing_period_start,
        'billing_end', b.billing_period_end,
        'due_date', b.due_date,
        'paid_date', b.paid_at,
        'payment_status', b.payment_status,
        'payment_method', b.payment_method,
        'payment_reference', b.payment_reference,
        'invoice_number', b.invoice_number,
        'notes', b.notes,
        'created_by', b.recorded_by,
        'updated_by', null,
        'created_at', b.created_at,
        'updated_at', b.updated_at
      )
      order by b.created_at desc
    ),
    '[]'::jsonb
  )
  into v_billing_records
  from public.ungani_payments b;

  if to_regclass('public.ungani_payment_proofs') is not null then
    execute '
      select coalesce(jsonb_agg(to_jsonb(p) order by p.created_at desc), ''[]''::jsonb)
      from public.ungani_payment_proofs p
    '
    into v_payment_proofs;
  else
    v_payment_proofs := '[]'::jsonb;
  end if;

  return jsonb_build_object(
    'ok', true,
    'message', 'Admin billing page data loaded.',
    'clients', v_clients,
    'billing_records', v_billing_records,
    'payment_proofs', v_payment_proofs,
    'loaded_at', now()
  );
exception
  when others then
    return jsonb_build_object(
      'ok', false,
      'message', sqlerrm,
      'clients', '[]'::jsonb,
      'billing_records', '[]'::jsonb,
      'payment_proofs', '[]'::jsonb
    );
end;
$function$;


CREATE OR REPLACE FUNCTION public.mark_admin_ungani_billing_record_paid(p_record_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_record public.ungani_payments;
begin
  if not public.is_ungani_admin() then
    return jsonb_build_object(
      'ok', false,
      'message', 'Admin access required.'
    );
  end if;

  update public.ungani_payments
  set
    payment_status = 'paid',
    paid_at = coalesce(paid_at, current_date),
    updated_at = now()
  where id = p_record_id
  returning *
  into v_record;

  if v_record.id is null then
    return jsonb_build_object(
      'ok', false,
      'message', 'Billing record not found.'
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'message', 'Billing record marked as paid.',
    'record', jsonb_build_object(
      'id', v_record.id,
      'tenant_id', v_record.tenant_id,
      'package_key', v_record.package_key,
      'amount', v_record.amount,
      'currency', v_record.currency,
      'billing_start', v_record.billing_period_start,
      'billing_end', v_record.billing_period_end,
      'due_date', v_record.due_date,
      'paid_date', v_record.paid_at,
      'payment_status', v_record.payment_status,
      'payment_method', v_record.payment_method,
      'payment_reference', v_record.payment_reference,
      'invoice_number', v_record.invoice_number,
      'notes', v_record.notes,
      'created_by', v_record.recorded_by,
      'created_at', v_record.created_at,
      'updated_at', v_record.updated_at
    )
  );
exception
  when others then
    return jsonb_build_object(
      'ok', false,
      'message', sqlerrm
    );
end;
$function$;


CREATE OR REPLACE FUNCTION public.get_admin_ungani_billing_records_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_total_records integer := 0;
  v_paid_records integer := 0;
  v_pending_records integer := 0;
  v_overdue_records integer := 0;
  v_total_paid numeric(12,2) := 0;
  v_total_pending numeric(12,2) := 0;
begin
  if not public.is_ungani_admin() then
    return jsonb_build_object(
      'ok', false,
      'message', 'Admin access required.'
    );
  end if;
  select count(*)
  into v_total_records
  from public.ungani_payments;
  select count(*)
  into v_paid_records
  from public.ungani_payments
  where payment_status = 'paid';
  select count(*)
  into v_pending_records
  from public.ungani_payments
  where payment_status in ('pending', 'partial');
  select count(*)
  into v_overdue_records
  from public.ungani_payments
  where payment_status <> 'paid'
    and due_date is not null
    and due_date < current_date;
  select coalesce(sum(amount), 0)
  into v_total_paid
  from public.ungani_payments
  where payment_status = 'paid';
  select coalesce(sum(amount), 0)
  into v_total_pending
  from public.ungani_payments
  where payment_status in ('pending', 'partial', 'overdue');
  return jsonb_build_object(
    'ok', true,
    'message', 'Billing records summary loaded.',
    'summary', jsonb_build_object(
      'total_records', v_total_records,
      'paid_records', v_paid_records,
      'pending_records', v_pending_records,
      'overdue_records', v_overdue_records,
      'total_paid', v_total_paid,
      'total_pending', v_total_pending,
      'currency', 'KES'
    ),
    'loaded_at', now()
  );
exception
  when others then
    return jsonb_build_object(
      'ok', false,
      'message', sqlerrm
    );
end;
$function$;

-- =====================================================================
-- PART 2: one-time data migration - carry the existing QA Test record
-- (and any other rows already sitting in the orphaned table) over to
-- ungani_payments, so nothing has to be manually recreated through the
-- UI. Preserves the original id/created_at/updated_at. Idempotent - safe
-- to re-run; skips any id already present in ungani_payments.
-- =====================================================================

insert into public.ungani_payments (
  id,
  tenant_id,
  package_key,
  amount,
  currency,
  billing_period_start,
  billing_period_end,
  due_date,
  paid_at,
  payment_status,
  payment_method,
  payment_reference,
  invoice_number,
  notes,
  recorded_by,
  created_at,
  updated_at
)
select
  b.id,
  b.tenant_id,
  b.package_key,
  b.amount,
  b.currency,
  b.billing_start,
  b.billing_end,
  b.due_date,
  b.paid_date,
  b.payment_status,
  b.payment_method,
  b.payment_reference,
  b.invoice_number,
  b.notes,
  b.created_by,
  b.created_at,
  b.updated_at
from public.ungani_billing_records b
where not exists (
  select 1 from public.ungani_payments p where p.id = b.id
);

-- Sanity check: confirm the QA tenant's record migrated and lands with
-- the same amount/status it had in admin-billing.html.
select id, tenant_id, package_key, amount, currency, payment_status, invoice_number, created_at
from public.ungani_payments
where tenant_id = '123b3687-02f7-45fb-a059-32ec49c3e55e';
