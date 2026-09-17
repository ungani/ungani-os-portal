-- UNGANI OS: Fix request_or_create_ungani_expense() and
-- owner_approve_ungani_expense_request() dropping related_item_id,
-- payer_phone, and reference_no on every EXPENSE transaction.
--
-- Root cause: both functions insert into public.transactions using an
-- explicit column list that predates tonight's three new columns
-- (business_items.parent_item_id's counterpart transactions.related_item_id,
-- and transactions.payer_phone/reference_no for M-Pesa auto-matching).
-- INCOME transactions insert directly from my-money.html and already
-- carry these fields correctly - only the expense-approval-workflow path
-- (Approvals & Internal Controls v1) was missing them, since it was
-- written before these columns existed.
--
-- Full function bodies reproduced verbatim from
-- sql/approvals-internal-controls-v1.sql, with only the three new
-- columns added to each insert's column list and values list (marked
-- "-- NEW" below). Nothing else changes.

create or replace function public.request_or_create_ungani_expense(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_is_owner boolean;
  v_threshold numeric;
  v_amount_kes numeric;
  v_type text;
  v_transaction_id uuid;
  v_request_id uuid;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  v_type := p_payload->>'type';
  v_amount_kes := nullif(p_payload->>'amount_kes', '')::numeric;

  if v_type is null or v_amount_kes is null then
    return jsonb_build_object('ok', false, 'message', 'Invalid expense payload.');
  end if;

  v_is_owner := coalesce(public.is_my_ungani_tenant_owner(v_tenant_id), false);

  select expense_approval_threshold_kes into v_threshold
  from public.tenants
  where id = v_tenant_id;

  if v_is_owner or v_type <> 'expense' or v_threshold is null or v_amount_kes < v_threshold then
    insert into public.transactions (
      tenant_id, type, transaction_type, category, amount, currency, exchange_rate, amount_kes,
      transaction_date, payment_method, status, description,
      related_person_id, related_team_member_id, related_payee_id, related_item_id, section_label,
      payer_phone, reference_no,
      vat_applicable, vat_rate, vat_amount, vat_pricing_mode, vat_amount_kes,
      withholding_applicable, withholding_rate, withholding_amount, withholding_amount_kes,
      created_by, created_at, updated_at
    )
    values (
      v_tenant_id,
      v_type,
      p_payload->>'transaction_type',
      p_payload->>'category',
      (p_payload->>'amount')::numeric,
      coalesce(p_payload->>'currency', 'KES'),
      coalesce((p_payload->>'exchange_rate')::numeric, 1),
      v_amount_kes,
      (p_payload->>'transaction_date')::date,
      p_payload->>'payment_method',
      coalesce(p_payload->>'status', 'completed'),
      p_payload->>'description',
      nullif(p_payload->>'related_person_id', '')::uuid,
      nullif(p_payload->>'related_team_member_id', '')::uuid,
      nullif(p_payload->>'related_payee_id', '')::uuid,
      nullif(p_payload->>'related_item_id', '')::uuid, -- NEW
      p_payload->>'section_label',
      p_payload->>'payer_phone', -- NEW
      p_payload->>'reference_no', -- NEW
      coalesce((p_payload->>'vat_applicable')::boolean, false),
      nullif(p_payload->>'vat_rate', '')::numeric,
      nullif(p_payload->>'vat_amount', '')::numeric,
      coalesce(p_payload->>'vat_pricing_mode', 'inclusive'),
      nullif(p_payload->>'vat_amount_kes', '')::numeric,
      coalesce((p_payload->>'withholding_applicable')::boolean, false),
      nullif(p_payload->>'withholding_rate', '')::numeric,
      nullif(p_payload->>'withholding_amount', '')::numeric,
      nullif(p_payload->>'withholding_amount_kes', '')::numeric,
      auth.uid(), now(), now()
    )
    returning id into v_transaction_id;

    return jsonb_build_object('ok', true, 'mode', 'created', 'transaction_id', v_transaction_id);
  end if;

  insert into public.ungani_approval_requests (
    tenant_id, approval_type, requested_by, payload, amount_kes, status
  )
  values (
    v_tenant_id, 'money_expense', auth.uid(), p_payload, v_amount_kes, 'pending'
  )
  returning id into v_request_id;

  -- create_ungani_notification has two live overloads (10-arg, and an
  -- 11-arg version with p_user_id appended, defaulted null) - a 10-arg
  -- positional call is ambiguous between them ("not unique"). The
  -- trailing null forces resolution to the 11-arg version.
  perform public.create_ungani_notification(
    v_tenant_id,
    'Expense awaiting your approval',
    'A staff member submitted a ' || coalesce(p_payload->>'category', 'expense') || ' expense of KES ' || to_char(v_amount_kes, 'FM999,999,990.00') || ' for approval.',
    'approval_request',
    'ungani_approval_requests',
    v_request_id,
    'my-approvals.html',
    'normal',
    jsonb_build_object('request_id', v_request_id, 'amount_kes', v_amount_kes),
    false,
    null
  );

  return jsonb_build_object('ok', true, 'mode', 'pending_approval', 'request_id', v_request_id);
end;
$function$;

grant execute on function public.request_or_create_ungani_expense(jsonb) to authenticated;

create or replace function public.owner_approve_ungani_expense_request(p_request_id uuid, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_request record;
  v_transaction_id uuid;
  v_payload jsonb;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if public.is_my_ungani_tenant_owner(v_tenant_id) is not true then
    return jsonb_build_object('ok', false, 'message', 'Only the business owner can approve expense requests.');
  end if;

  select * into v_request
  from public.ungani_approval_requests
  where id = p_request_id and tenant_id = v_tenant_id;

  if v_request.id is null then
    return jsonb_build_object('ok', false, 'message', 'Approval request not found.');
  end if;

  if v_request.status <> 'pending' then
    return jsonb_build_object('ok', false, 'message', 'This request has already been ' || v_request.status || '.');
  end if;

  v_payload := v_request.payload;

  insert into public.transactions (
    tenant_id, type, transaction_type, category, amount, currency, exchange_rate, amount_kes,
    transaction_date, payment_method, status, description,
    related_person_id, related_team_member_id, related_payee_id, related_item_id, section_label,
    payer_phone, reference_no,
    vat_applicable, vat_rate, vat_amount, vat_pricing_mode, vat_amount_kes,
    withholding_applicable, withholding_rate, withholding_amount, withholding_amount_kes,
    created_by, created_at, updated_at
  )
  values (
    v_tenant_id,
    v_payload->>'type',
    v_payload->>'transaction_type',
    v_payload->>'category',
    (v_payload->>'amount')::numeric,
    coalesce(v_payload->>'currency', 'KES'),
    coalesce((v_payload->>'exchange_rate')::numeric, 1),
    (v_payload->>'amount_kes')::numeric,
    (v_payload->>'transaction_date')::date,
    v_payload->>'payment_method',
    coalesce(v_payload->>'status', 'completed'),
    v_payload->>'description',
    nullif(v_payload->>'related_person_id', '')::uuid,
    nullif(v_payload->>'related_team_member_id', '')::uuid,
    nullif(v_payload->>'related_payee_id', '')::uuid,
    nullif(v_payload->>'related_item_id', '')::uuid, -- NEW
    v_payload->>'section_label',
    v_payload->>'payer_phone', -- NEW
    v_payload->>'reference_no', -- NEW
    coalesce((v_payload->>'vat_applicable')::boolean, false),
    nullif(v_payload->>'vat_rate', '')::numeric,
    nullif(v_payload->>'vat_amount', '')::numeric,
    coalesce(v_payload->>'vat_pricing_mode', 'inclusive'),
    nullif(v_payload->>'vat_amount_kes', '')::numeric,
    coalesce((v_payload->>'withholding_applicable')::boolean, false),
    nullif(v_payload->>'withholding_rate', '')::numeric,
    nullif(v_payload->>'withholding_amount', '')::numeric,
    nullif(v_payload->>'withholding_amount_kes', '')::numeric,
    v_request.requested_by, now(), now()
  )
  returning id into v_transaction_id;

  update public.ungani_approval_requests
  set status = 'approved', reviewed_by = auth.uid(), reviewed_at = now(), review_note = p_note,
      created_transaction_id = v_transaction_id, updated_at = now()
  where id = p_request_id;

  perform public.create_ungani_notification(
    v_tenant_id,
    'Expense approved',
    'Your ' || coalesce(v_payload->>'category', 'expense') || ' expense request was approved.',
    'approval_request',
    'transactions',
    v_transaction_id,
    'my-money.html',
    'normal',
    jsonb_build_object('request_id', p_request_id),
    false,
    null
  );

  return jsonb_build_object('ok', true, 'transaction_id', v_transaction_id);
end;
$function$;

grant execute on function public.owner_approve_ungani_expense_request(uuid, text) to authenticated;

-- ============================================================
-- VERIFICATION
-- ============================================================
select proname, prosecdef, pg_get_function_identity_arguments(oid) as args
from pg_proc
where proname in ('request_or_create_ungani_expense', 'owner_approve_ungani_expense_request');
