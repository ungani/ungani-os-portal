-- Approvals & Internal Controls v1: expense-approval-threshold.
--
-- Decisions confirmed with the user before writing this:
--   1. Flat KES threshold per tenant (not per-category).
--   2. Owner-only approver in v1.
--   3. Expense-creation-only - editing/deleting an already-approved
--      transaction is not gated.
--   4. Off by default (null threshold) - solo owners and tenants who
--      never set one see zero behavior change.
--
-- Enforced server-side (inside this RPC), not just in the UI - see the
-- "staff section-permissions enforced client-side only" finding logged
-- separately: a client-side-only gate here would be exactly as
-- bypassable as the existing create/edit permission checks.

-- ============================================================
-- PART A: approval requests table.
-- ============================================================

create table if not exists public.ungani_approval_requests (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  approval_type text not null default 'money_expense',
  requested_by uuid not null,
  payload jsonb not null,
  amount_kes numeric,
  status text not null default 'pending',
  reviewed_by uuid,
  reviewed_at timestamptz,
  review_note text,
  created_transaction_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ungani_approval_requests_status_check check (status in ('pending', 'approved', 'rejected'))
);

create index if not exists ungani_approval_requests_tenant_status_idx
  on public.ungani_approval_requests(tenant_id, status);

alter table public.ungani_approval_requests enable row level security;

drop policy if exists ungani_approval_requests_requester_select on public.ungani_approval_requests;
create policy ungani_approval_requests_requester_select on public.ungani_approval_requests
  for select
  using (tenant_id = public.get_my_ungani_tenant_id() and requested_by = auth.uid());

drop policy if exists ungani_approval_requests_owner_select on public.ungani_approval_requests;
create policy ungani_approval_requests_owner_select on public.ungani_approval_requests
  for select
  using (tenant_id = public.get_my_ungani_tenant_id() and public.is_my_ungani_tenant_owner(tenant_id));

grant select on public.ungani_approval_requests to authenticated;
-- No insert/update/delete grants - only via the security-definer RPCs below.

-- ============================================================
-- PART B: settings column. Null = feature off.
-- ============================================================

alter table public.tenants
  add column if not exists expense_approval_threshold_kes numeric;

alter table public.tenants
  drop constraint if exists tenants_expense_approval_threshold_check;

alter table public.tenants
  add constraint tenants_expense_approval_threshold_check
  check (expense_approval_threshold_kes is null or expense_approval_threshold_kes > 0);

-- ============================================================
-- PART C: request_or_create_ungani_expense() - the new single
-- entry point for creating a NEW expense transaction. p_payload
-- mirrors my-money.html's existing insert payload exactly (verified
-- against its real, current field-by-field construction).
-- ============================================================

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
      related_person_id, related_team_member_id, related_payee_id, section_label,
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
      p_payload->>'section_label',
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
    false
  );

  return jsonb_build_object('ok', true, 'mode', 'pending_approval', 'request_id', v_request_id);
end;
$function$;

grant execute on function public.request_or_create_ungani_expense(jsonb) to authenticated;

-- ============================================================
-- PART D: approve / reject - owner-only.
-- ============================================================

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
    related_person_id, related_team_member_id, related_payee_id, section_label,
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
    v_payload->>'section_label',
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
    false
  );

  return jsonb_build_object('ok', true, 'transaction_id', v_transaction_id);
end;
$function$;

grant execute on function public.owner_approve_ungani_expense_request(uuid, text) to authenticated;

create or replace function public.owner_reject_ungani_expense_request(p_request_id uuid, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_request record;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if public.is_my_ungani_tenant_owner(v_tenant_id) is not true then
    return jsonb_build_object('ok', false, 'message', 'Only the business owner can reject expense requests.');
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

  update public.ungani_approval_requests
  set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now(), review_note = p_note, updated_at = now()
  where id = p_request_id;

  perform public.create_ungani_notification(
    v_tenant_id,
    'Expense request rejected',
    'Your ' || coalesce(v_request.payload->>'category', 'expense') || ' expense request was rejected.' ||
      case when p_note is not null and p_note <> '' then ' Reason: ' || p_note else '' end,
    'approval_request',
    'ungani_approval_requests',
    p_request_id,
    'my-approvals.html',
    'normal',
    jsonb_build_object('request_id', p_request_id),
    false
  );

  return jsonb_build_object('ok', true, 'message', 'Request rejected.');
end;
$function$;

grant execute on function public.owner_reject_ungani_expense_request(uuid, text) to authenticated;
