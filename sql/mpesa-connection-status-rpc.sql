-- ============================================================
-- UNGANI OS: owner_get_ungani_mpesa_connection_status()
-- Read-only companion to owner_connect_ungani_mpesa_paybill() /
-- service_get_ungani_mpesa_credentials() (sql/mpesa-tenant-paybill-
-- connection-vault.sql) - lets the Settings page show "Connected to
-- Paybill 123456 (sandbox)" without ever touching the vault. Returns
-- only non-secret columns (shortcode, environment, status,
-- created_at/updated_at) - mirrors get_my_ungani_google_drive_status's
-- shape for the same kind of card in my-integrations.html.
-- ============================================================

create or replace function public.owner_get_ungani_mpesa_connection_status()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_row record;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if public.is_my_ungani_tenant_owner(v_tenant_id) is not true then
    return jsonb_build_object('ok', false, 'message', 'Only the business owner can view this.');
  end if;

  select shortcode, environment, status, created_at, updated_at
  into v_row
  from public.ungani_tenant_mpesa_connections
  where tenant_id = v_tenant_id;

  if v_row is null then
    return jsonb_build_object('ok', true, 'connected', false);
  end if;

  return jsonb_build_object(
    'ok', true,
    'connected', v_row.status = 'active',
    'shortcode', v_row.shortcode,
    'environment', v_row.environment,
    'status', v_row.status,
    'connected_at', v_row.created_at,
    'updated_at', v_row.updated_at
  );
end;
$function$;

-- Postgres grants EXECUTE to PUBLIC by default on function creation -
-- explicitly locking this down, same discipline as the rest of this
-- migration set.
revoke all on function public.owner_get_ungani_mpesa_connection_status() from public;
grant execute on function public.owner_get_ungani_mpesa_connection_status() to authenticated;

-- ============================================================
-- VERIFICATION
-- ============================================================
select routine_name, security_type
from information_schema.routines
where routine_name = 'owner_get_ungani_mpesa_connection_status';

select routine_name, grantee, privilege_type
from information_schema.routine_privileges
where routine_name = 'owner_get_ungani_mpesa_connection_status'
order by grantee;
