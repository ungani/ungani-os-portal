-- POS "Quick Sale" Phase 1: schema + tier gating + the core
-- record_ungani_pos_sale RPC. Cash and M-Pesa both create a REAL
-- ungani_customer_invoices row (never a parallel "sale" table) per
-- explicit decision - avoids the same "island" problem already found
-- and fixed for Customer Invoicing earlier this session.
--
-- All changes below are additive to existing shared objects
-- (owner_upsert_ungani_customer_invoice, ungani_customer_invoice_items,
-- ungani_mpesa_transactions) - verified against each object's real,
-- currently-live source before writing this, not guessed. Every other
-- existing caller of these objects is unaffected (new columns default
-- to null/false, and no existing behavior branch changes).

-- ============================================================
-- PART A: Opt-in toggle (mirrors enable/disable_ungani_stock_tracking
-- exactly).
-- ============================================================

alter table public.tenants
  add column if not exists pos_enabled boolean not null default false;

create or replace function public.enable_ungani_pos()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if not public.can_write_ungani_client_data() then
    return jsonb_build_object('ok', false, 'message', 'This account is currently read-only.');
  end if;

  update public.tenants
  set pos_enabled = true
  where id = v_tenant_id;

  return jsonb_build_object('ok', true, 'message', 'Point of Sale enabled.');
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

grant execute on function public.enable_ungani_pos() to authenticated;

create or replace function public.disable_ungani_pos()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if not public.can_write_ungani_client_data() then
    return jsonb_build_object('ok', false, 'message', 'This account is currently read-only.');
  end if;

  update public.tenants
  set pos_enabled = false
  where id = v_tenant_id;

  return jsonb_build_object('ok', true, 'message', 'Point of Sale disabled.');
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

grant execute on function public.disable_ungani_pos() to authenticated;

-- ============================================================
-- PART B: Tier gating - declarative column mirroring the one real
-- precedent (ungani_packages.multi_branch_included), not a hardcoded
-- 'business' string comparison in code.
-- ============================================================

alter table public.ungani_packages
  add column if not exists pos_included boolean not null default false;

update public.ungani_packages
set pos_included = true
where package_key in ('business', 'custom');

-- Client-facing eligibility check (used for nav-hiding UX only - the
-- real enforcement is server-side inside record_ungani_pos_sale below).
-- Correctly reads ungani_subscriptions.package_key (the live value),
-- never tenants.package_key (confirmed stale after upgrades, same bug
-- already fixed elsewhere tonight).
create or replace function public.get_my_ungani_pos_eligibility()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_pos_enabled boolean;
  v_package_key text;
  v_pos_included boolean;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  select pos_enabled into v_pos_enabled
  from public.tenants
  where id = v_tenant_id;

  select package_key into v_package_key
  from public.ungani_subscriptions
  where tenant_id = v_tenant_id;

  select coalesce(p.pos_included, false) into v_pos_included
  from public.ungani_packages p
  where p.package_key = v_package_key;

  return jsonb_build_object(
    'ok', true,
    'pos_enabled', coalesce(v_pos_enabled, false),
    'package_included', coalesce(v_pos_included, false),
    'eligible', coalesce(v_pos_enabled, false) and coalesce(v_pos_included, false)
  );
end;
$function$;

grant execute on function public.get_my_ungani_pos_eligibility() to authenticated;

-- ============================================================
-- PART C: item_id on invoice line items (mirrors the column Orders
-- already has on ungani_order_items). Needed so the M-Pesa callback -
-- a separate, later request with no memory of the original cart - can
-- still find which business_items rows to deduct once payment confirms.
-- Nullable and additive: every existing caller (manual invoice
-- creation, Quotation-to-Invoice conversion) simply never sends it, so
-- it stays null exactly as today.
-- ============================================================

alter table public.ungani_customer_invoice_items
  add column if not exists item_id uuid references public.business_items(id) on delete set null;

-- ============================================================
-- PART D: M-Pesa transaction discriminator columns. Default keeps
-- every existing row, and the entire subscription STK-push flow,
-- byte-identical - this is purely additive.
-- ============================================================

alter table public.ungani_mpesa_transactions
  add column if not exists transaction_type text not null default 'subscription',
  add column if not exists related_table text,
  add column if not exists related_id uuid;

-- ============================================================
-- VERIFICATION - run this and paste back the output.
-- ============================================================

select table_name, column_name, data_type, column_default
from information_schema.columns
where table_schema = 'public'
  and (
    (table_name = 'tenants' and column_name = 'pos_enabled')
    or (table_name = 'ungani_packages' and column_name = 'pos_included')
    or (table_name = 'ungani_customer_invoice_items' and column_name = 'item_id')
    or (table_name = 'ungani_mpesa_transactions' and column_name in ('transaction_type', 'related_table', 'related_id'))
  )
order by table_name, column_name;

select package_key, pos_included from public.ungani_packages order by package_key;
