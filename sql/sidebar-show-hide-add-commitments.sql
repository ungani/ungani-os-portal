-- Sidebar Show/Hide: add the missing 'commitments' key to the server-side
-- allow-list. Found during the sidebar/nav architecture audit (2026-09-22):
-- 'commitments' (Cluster 4 - Leases/Memberships/Contracts, opt-in) was
-- added to ungani-nav-config.js after sidebar-show-hide.sql was written,
-- and was never added to either list. It's correctly absent from
-- PROTECTED_NAV_ITEM_KEYS (it's an opt-in item, not core account
-- management, so it SHOULD be hideable) - the bug is purely that it was
-- also missing here, so a tenant unchecking it in My Settings got a
-- "Sidebar preferences saved" success message while the key was silently
-- dropped by the foreach/allow-list check below, and the item never
-- actually hid. Full audit cross-check confirmed this is the ONLY key
-- missing from the two lists (13 protected + 25 previously-allowed + this
-- 1 = the full current sidebar key count).
--
-- Re-running create-or-replace of the exact same function from
-- sql/sidebar-show-hide.sql, with 'commitments' added to v_allowed_keys.
-- Everything else in the function is byte-identical to the live version.

create or replace function public.set_ungani_hidden_nav_items(p_hidden_items text[])
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_allowed_keys text[] := array[
    'team-chat', 'tasks', 'money', 'people', 'documents',
    'records', 'calendar', 'commitments',
    'debtors-payables', 'approvals',
    'quotations', 'orders', 'customer-invoices', 'quick-sale',
    'items', 'stock-tracking', 'price-lists',
    'overview', 'charts', 'activity', 'connect', 'integrations',
    'reports', 'print-report',
    'recently-deleted',
    'support-access'
  ];
  v_validated text[] := '{}';
  v_key text;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if not public.can_write_ungani_client_data() then
    return jsonb_build_object('ok', false, 'message', 'This account is currently read-only.');
  end if;

  foreach v_key in array coalesce(p_hidden_items, '{}') loop
    if v_key = any(v_allowed_keys) and not (v_key = any(v_validated)) then
      v_validated := array_append(v_validated, v_key);
    end if;
  end loop;

  update public.tenants
  set hidden_nav_items = v_validated
  where id = v_tenant_id;

  return jsonb_build_object('ok', true, 'message', 'Sidebar preferences saved.', 'hidden_nav_items', v_validated);
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

-- ============================================================
-- VERIFICATION - run this and confirm 'commitments' is now present.
-- ============================================================

select pg_get_functiondef(oid) as function_body
from pg_proc
where proname = 'set_ungani_hidden_nav_items' and pronamespace = 'public'::regnamespace;
