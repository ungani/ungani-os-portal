-- =====================================================================
-- Batch 2: Tenant Paybill/Till production readiness - Part A.
--
-- Rewritten from LIVE schema facts confirmed this conversation (real
-- CREATE/ALTER statements in sql/mpesa-tenant-paybill-connection-vault.sql
-- and sql/mpesa-bank-paybill-failure-status-fix.sql, cross-checked
-- against every real column read in api/mpesa-stk-push.js).
--
-- Scope of THIS file: schema additions (connection_type, store_number)
-- and a new owner-facing "payments to match" review surface. Does NOT
-- yet include BillRefNumber-to-invoice auto-matching in the C2B webhook
-- itself - that needs service_record_ungani_invoice_payment's real
-- signature first (one more discovery query, included below, not yet
-- run) so I'm not guessing at a function that posts money against an
-- invoice. Everything in this file is reviewed-before-write per your
-- rule for money-touching changes.
--
-- Covers:
--  1. connection_type ('paybill' | 'till' | 'till_with_store') and
--     store_number on ungani_tenant_mpesa_connections - lets the connect
--     UI (my-settings.html) ask the right follow-up question, and lets
--     future C2B logic know whether an account-number match even makes
--     sense (a Till has no BillRefNumber; a Till-with-Store's "store"
--     identifier arrives in a different field than a Paybill account
--     number - flagging this as something to verify against Safaricom's
--     actual go-live paperwork for the specific tenant, since Daraja's
--     documented behavior here varies by business type).
--  2. owner_get_ungani_unmatched_mpesa_payments() - the "Payments to
--     Match" list: M-Pesa transactions with no related_person_id,
--     tenant-scoped, paginated the same way every other list page in
--     this app already is.
--  3. owner_match_ungani_mpesa_payment(transaction_id, person_id) - the
--     action behind that list. This does NOT touch invoices - it's the
--     same "link this payment to a customer" action my-money.html's
--     existing "No payer match" badge already offers via manual payer-
--     phone editing, just surfaced as a dedicated, convenient screen
--     instead of requiring the owner to find it buried in the full
--     ledger.
-- =====================================================================


-- ---------------------------------------------------------------------
-- SECTION 1: Schema additions.
-- ---------------------------------------------------------------------

alter table public.ungani_tenant_mpesa_connections
  add column if not exists connection_type text not null default 'paybill'
    check (connection_type in ('paybill', 'till', 'till_with_store')),
  add column if not exists store_number text;


-- ---------------------------------------------------------------------
-- SECTION 2: owner_get_ungani_unmatched_mpesa_payments - paginated list
-- of M-Pesa transactions with no linked person, for the tenant's own
-- workspace. Mirrors the access level my-money.html's existing
-- "No payer match" badge + manual-edit flow already allows - any
-- authenticated member of the tenant, not owner-exclusive, since that's
-- the existing permission level for editing a transaction's payer link.
-- If you want this restricted to the owner only, tell me and I'll add
-- an is_my_ungani_tenant_owner() check.
-- ---------------------------------------------------------------------

create or replace function public.owner_get_ungani_unmatched_mpesa_payments(
  p_limit int default 25,
  p_offset int default 0
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_total int;
  v_rows jsonb;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  select count(*) into v_total
  from public.transactions t
  where t.tenant_id = v_tenant_id
    and t.deleted_at is null
    and t.payment_method = 'M-Pesa'
    and t.related_person_id is null;

  select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) into v_rows
  from (
    select
      t.id, t.amount, t.amount_kes, t.currency, t.transaction_date,
      t.payer_phone, t.reference_no, t.description, t.created_at
    from public.transactions t
    where t.tenant_id = v_tenant_id
      and t.deleted_at is null
      and t.payment_method = 'M-Pesa'
      and t.related_person_id is null
    order by t.created_at desc
    limit greatest(least(coalesce(p_limit, 25), 100), 1)
    offset greatest(coalesce(p_offset, 0), 0)
  ) x;

  return jsonb_build_object(
    'ok', true,
    'total', v_total,
    'payments', v_rows
  );
end;
$function$;

revoke all on function public.owner_get_ungani_unmatched_mpesa_payments(int, int) from public, anon;
grant execute on function public.owner_get_ungani_unmatched_mpesa_payments(int, int) to authenticated;


-- ---------------------------------------------------------------------
-- SECTION 3: owner_match_ungani_mpesa_payment - the action button on
-- that list. Confirms the transaction belongs to the caller's own
-- tenant before touching it (never trusts a client-supplied tenant_id).
-- ---------------------------------------------------------------------

create or replace function public.owner_match_ungani_mpesa_payment(
  p_transaction_id uuid,
  p_person_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_txn_tenant_id uuid;
  v_person_tenant_id uuid;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  select tenant_id into v_txn_tenant_id from public.transactions where id = p_transaction_id;
  if v_txn_tenant_id is null or v_txn_tenant_id <> v_tenant_id then
    return jsonb_build_object('ok', false, 'message', 'Payment record not found.');
  end if;

  select tenant_id into v_person_tenant_id from public.client_people where id = p_person_id;
  if v_person_tenant_id is null or v_person_tenant_id <> v_tenant_id then
    return jsonb_build_object('ok', false, 'message', 'Customer record not found.');
  end if;

  update public.transactions
  set related_person_id = p_person_id, updated_at = now()
  where id = p_transaction_id;

  return jsonb_build_object('ok', true);
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

revoke all on function public.owner_match_ungani_mpesa_payment(uuid, uuid) from public, anon;
grant execute on function public.owner_match_ungani_mpesa_payment(uuid, uuid) to authenticated;


-- ---------------------------------------------------------------------
-- SECTION 4: Verification.
-- ---------------------------------------------------------------------

select jsonb_build_object(
  'connection_type_column_exists', (
    select count(*) from information_schema.columns
    where table_schema = 'public' and table_name = 'ungani_tenant_mpesa_connections'
      and column_name in ('connection_type', 'store_number')
  ),
  'functions_created', (
    select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in (
      'owner_get_ungani_unmatched_mpesa_payments', 'owner_match_ungani_mpesa_payment'
    )
  ),
  'anon_or_public_exec', (
    select jsonb_agg(p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in (
      'owner_get_ungani_unmatched_mpesa_payments', 'owner_match_ungani_mpesa_payment'
    ) and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('public', p.oid, 'execute'))
  )
) as verification_result;
