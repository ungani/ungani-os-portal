-- Sidebar Show/Hide: lets a business declutter their own sidebar by
-- hiding items they never use, while keeping the overall structure/
-- order as the designed default (Chris's decision 2026-09-10 - hide
-- only, not full drag-and-drop reorder). Confirmed protected (never
-- hideable) list: Dashboard, Notifications, Favorites, Security &
-- Data, Team Access, the whole Billing & Setup group, and the whole
-- Support group - a business shouldn't be able to accidentally hide
-- its way into a corner of core account management or lose the
-- "quick access" Favorites feature.
--
-- Storage: a flat array of nav item keys (the same key strings used
-- as item[0] throughout ungani-nav-config.js, e.g. 'quotations',
-- 'stock-tracking') - simpler than JSON, uses native Postgres array
-- ops. Filtering happens client-side inside getSidebarGroups() itself
-- (the single source of truth already shared by client.html's
-- bespoke render and client-shared.js's renderSidebarNav(), used by
-- ~20 other my-*.html pages) - this migration only adds storage and
-- a validated write path.

alter table public.tenants
  add column if not exists hidden_nav_items text[] not null default '{}';

-- Server-side allow-list of hideable keys - mirrors the JS
-- PROTECTED_NAV_ITEM_KEYS constant that will be added to
-- ungani-nav-config.js. Keep both lists in sync if the sidebar
-- structure ever changes. Never trust the client's array blindly - a
-- buggy or malicious client must not be able to hide a protected item
-- just by including it in the array; anything not on this allow-list
-- is silently dropped rather than erroring, so a stale client sending
-- an old/renamed key degrades gracefully instead of failing the save.
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
    'records', 'calendar',
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

revoke execute on function public.set_ungani_hidden_nav_items(text[]) from public;
grant execute on function public.set_ungani_hidden_nav_items(text[]) to authenticated;

-- ============================================================
-- VERIFICATION - run this and paste back the output.
-- ============================================================

select column_name, data_type, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'tenants' and column_name = 'hidden_nav_items';

select proname, pg_get_function_identity_arguments(oid) as args
from pg_proc
where proname = 'set_ungani_hidden_nav_items' and pronamespace = 'public'::regnamespace;

select routine_name, grantee, privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public' and routine_name = 'set_ungani_hidden_nav_items'
order by grantee;
