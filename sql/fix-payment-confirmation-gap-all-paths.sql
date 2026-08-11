-- Fixes the payment-confirmation gap found in the trial/subscription
-- reminder audit: only ONE of three admin actions that mark a payment
-- "paid" actually told the client (admin_accept_ungani_payment_proof_
-- and_mark_paid, via the payment-proofs page), and even that one sent a
-- generic "thank you" with no amount/package/date - not a real receipt.
-- The other two (admin_update_ungani_payment_status from billing.html,
-- mark_admin_ungani_billing_record_paid from admin-billing.html) sent
-- nothing at all.
--
-- Design: one shared helper, queue_ungani_payment_confirmation_email(),
-- called from all three instead of duplicating the email-building logic
-- three times. It reads directly off ungani_payments (amount, currency,
-- package_key, invoice_number, paid_at) - the same table all three
-- functions already write to - so the receipt is built from the exact
-- row each path just updated, not a second guess at what happened.
--
-- Idempotency is unchanged in shape from the original: keyed on
-- (email_type='payment_approved', related_table='ungani_payments',
-- related_id=payment_id), so calling the helper multiple times for the
-- same payment (e.g. an admin re-clicking an already-paid record) is a
-- safe no-op, not a duplicate email.
--
-- No grant to `authenticated` on the helper - it's an internal building
-- block only ever called from inside the three already admin-gated
-- SECURITY DEFINER functions below, never directly from client code.
-- Run this whole file once in the Supabase SQL editor.

create or replace function public.queue_ungani_payment_confirmation_email(p_payment_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_payment public.ungani_payments;
  v_recipient_email text;
  v_recipient_name text;
  v_package_name text;
  v_amount_text text;
  v_date_text text;
begin
  select * into v_payment from public.ungani_payments where id = p_payment_id;

  if v_payment.id is null then
    return;
  end if;

  select coalesce(t.business_email, ''), coalesce(t.contact_person, t.business_name, 'there')
  into v_recipient_email, v_recipient_name
  from public.tenants t
  where t.id = v_payment.tenant_id;

  v_recipient_email := nullif(trim(coalesce(v_recipient_email, '')), '');

  if v_recipient_email is null then
    return;
  end if;

  if exists (
    select 1 from public.ungani_email_queue
    where email_type = 'payment_approved'
      and related_table = 'ungani_payments'
      and related_id = p_payment_id
  ) then
    return;
  end if;

  select package_name into v_package_name
  from public.ungani_packages
  where package_key = v_payment.package_key
  limit 1;

  v_amount_text := coalesce(v_payment.currency, 'KES') || ' ' || to_char(coalesce(v_payment.amount, 0), 'FM999,999,990.00');
  v_date_text := to_char(coalesce(v_payment.paid_at, now()), 'DD Mon YYYY');

  insert into public.ungani_email_queue (
    tenant_id,
    recipient_email,
    recipient_name,
    email_subject,
    email_body,
    email_type,
    related_table,
    related_id,
    send_status,
    created_at
  ) values (
    v_payment.tenant_id,
    v_recipient_email,
    v_recipient_name,
    'Your UNGANI OS payment receipt' || (case when v_payment.invoice_number is not null then ' - Invoice ' || v_payment.invoice_number else '' end),
    'Hi ' || v_recipient_name || E',\n\n' ||
    'This confirms your payment has been received and processed.' || E'\n\n' ||
    'Amount paid: ' || v_amount_text || E'\n' ||
    (case when v_package_name is not null then 'Package: ' || v_package_name || E'\n' else '' end) ||
    (case when v_payment.invoice_number is not null then 'Invoice: ' || v_payment.invoice_number || E'\n' else '' end) ||
    'Date: ' || v_date_text || E'\n\n' ||
    'Thank you for your business.' || E'\n\n' ||
    'Regards,' || E'\n' ||
    'UNGANI' || E'\n' ||
    'info@ungani.com',
    'payment_approved',
    'ungani_payments',
    p_payment_id,
    'pending',
    now()
  );
exception
  when others then
    raise warning 'Could not queue payment-confirmation email for payment %: %', p_payment_id, sqlerrm;
end;
$function$;

-- ============================================================
-- 1. admin-payment-proofs.html's "Accept & Mark Paid" - already sent an
-- email, now routed through the shared helper for a real receipt.
-- ============================================================

create or replace function public.admin_accept_ungani_payment_proof_and_mark_paid(p_proof_id uuid, p_admin_note text DEFAULT NULL::text, p_payment_method text DEFAULT NULL::text, p_payment_reference text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_payment_id uuid;
  v_tenant_id uuid;
  v_invoice_number text;
  v_existing_method text;
  v_existing_reference text;
  v_clean_note text;
  v_clean_method text;
  v_clean_reference text;
begin
  if public.is_ungani_admin() is not true then
    raise exception 'Access denied';
  end if;
  select
    pp.payment_id,
    pp.tenant_id,
    pp.invoice_number
  into
    v_payment_id,
    v_tenant_id,
    v_invoice_number
  from public.ungani_payment_proofs pp
  where pp.id = p_proof_id
  limit 1;
  if v_payment_id is null then
    raise exception 'Payment proof not found';
  end if;
  select
    p.payment_method,
    p.payment_reference
  into
    v_existing_method,
    v_existing_reference
  from public.ungani_payments p
  where p.id = v_payment_id
  limit 1;
  if not found then
    raise exception 'Related payment record not found';
  end if;
  v_clean_note := nullif(trim(coalesce(p_admin_note, '')), '');
  v_clean_method := nullif(trim(coalesce(p_payment_method, '')), '');
  v_clean_reference := nullif(trim(coalesce(p_payment_reference, '')), '');
  update public.ungani_payment_proofs
  set
    proof_status = 'accepted',
    admin_note = coalesce(
      v_clean_note,
      admin_note,
      'Payment proof accepted and payment marked as paid by UNGANI admin.'
    ),
    reviewed_by = auth.uid(),
    reviewed_at = now()
  where id = p_proof_id;
  update public.ungani_payments
  set
    payment_status = 'paid',
    paid_at = coalesce(paid_at, now()),
    payment_method = coalesce(
      v_clean_method,
      nullif(trim(coalesce(v_existing_method, '')), ''),
      'Payment proof'
    ),
    payment_reference = coalesce(
      v_clean_reference,
      nullif(trim(coalesce(v_existing_reference, '')), ''),
      v_invoice_number,
      'Proof accepted'
    ),
    notes = case
      when v_clean_note is not null and length(v_clean_note) > 0 then
        case
          when notes is null or length(trim(notes)) = 0 then
            'Admin accepted payment proof: ' || v_clean_note
          else
            notes || E'\nAdmin accepted payment proof: ' || v_clean_note
        end
      else
        case
          when notes is null or length(trim(notes)) = 0 then
            'Payment proof accepted and payment marked as paid by UNGANI admin.'
          else
            notes || E'\nPayment proof accepted and payment marked as paid by UNGANI admin.'
        end
    end,
    updated_at = now()
  where id = v_payment_id;
  if not found then
    raise exception 'Unable to update payment record';
  end if;

  begin
    perform public.queue_ungani_payment_confirmation_email(v_payment_id);
  exception
    when others then
      raise warning 'Could not queue payment-approved email for payment %: %', v_payment_id, sqlerrm;
  end;

  begin
    perform public.set_ungani_subscription_period_from_payment(v_payment_id);
  exception
    when others then
      raise warning 'Could not update subscription period for payment %: %', v_payment_id, sqlerrm;
  end;

  return true;
end;
$function$;

-- ============================================================
-- 2. billing.html's admin_update_ungani_payment_status - previously sent
-- nothing at all. Now queues a confirmation whenever a payment is set to
-- 'paid' (any other status change is silent, same as before).
-- ============================================================

create or replace function public.admin_update_ungani_payment_status(p_payment_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
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
    payment_status = p_status,
    paid_at = case when p_status = 'paid' then coalesce(paid_at, now()) else paid_at end,
    updated_at = now()
  where id = p_payment_id
  returning *
  into v_record;

  if v_record.id is null then
    return jsonb_build_object(
      'ok', false,
      'message', 'Payment record not found.'
    );
  end if;

  if p_status = 'paid' then
    begin
      perform public.queue_ungani_payment_confirmation_email(v_record.id);
    exception
      when others then
        raise warning 'Could not queue payment-approved email for payment %: %', v_record.id, sqlerrm;
    end;

    begin
      perform public.set_ungani_subscription_period_from_payment(v_record.id);
    exception
      when others then
        raise warning 'Could not update subscription period for payment %: %', v_record.id, sqlerrm;
    end;
  end if;

  return jsonb_build_object(
    'ok', true,
    'message', 'Payment status updated.',
    'record', to_jsonb(v_record)
  );
exception
  when others then
    return jsonb_build_object(
      'ok', false,
      'message', sqlerrm
    );
end;
$function$;

-- ============================================================
-- 3. admin-billing.html's mark_admin_ungani_billing_record_paid -
-- previously sent nothing at all.
-- ============================================================

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

  begin
    perform public.queue_ungani_payment_confirmation_email(v_record.id);
  exception
    when others then
      raise warning 'Could not queue payment-approved email for payment %: %', v_record.id, sqlerrm;
  end;

  begin
    perform public.set_ungani_subscription_period_from_payment(v_record.id);
  exception
    when others then
      raise warning 'Could not update subscription period for payment %: %', v_record.id, sqlerrm;
  end;

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
