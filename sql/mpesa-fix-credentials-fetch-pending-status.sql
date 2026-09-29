-- ============================================================
-- UNGANI OS: Fix chicken-and-egg bug in M-Pesa credential fetch
-- (2026-09-29)
--
-- Root cause, confirmed by reading api/mpesa-stk-push.js line 610:
-- registerC2BUrls() calls service_get_ungani_mpesa_credentials()
-- immediately after owner_connect_ungani_mpesa_paybill() saves the
-- connection - but that save now always leaves status = 'pending'
-- (per the status-lifecycle fix already run today), and
-- service_get_ungani_mpesa_credentials() only ever selected rows
-- WHERE status = 'active'. Every single new connection or reconnect
-- would therefore fail at the credential-fetch step with "No active
-- M-Pesa Paybill connection for this tenant." before ever reaching
-- Daraja - status could never become 'active' in the first place,
-- because THIS is the call that's supposed to lead to it becoming
-- active. Caught before any sandbox testing, not from a live failure.
--
-- Fix: accept 'pending' or 'active' (a 'failed' or 'disabled'
-- connection still correctly returns "no connection" - only a fresh
-- save or a retry-after-failure reconnect, both of which land back on
-- 'pending', should ever be fetchable here). Also drops the two
-- initiator_name/initiator_password lines (dead since the 4-param
-- rewrite - the vault payload no longer contains those keys) and adds
-- status to the response so the caller can tell which state it fetched.
-- ============================================================

create or replace function public.service_get_ungani_mpesa_credentials(p_tenant_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_row record;
  v_payload jsonb;
begin
  select c.shortcode, c.environment, c.status, s.decrypted_secret
  into v_row
  from public.ungani_tenant_mpesa_connections c
  join vault.decrypted_secrets s on s.id = c.vault_secret_id
  where c.tenant_id = p_tenant_id
    and c.status in ('pending', 'active');

  if not found then
    return jsonb_build_object('ok', false, 'message', 'No active M-Pesa Paybill connection for this tenant.');
  end if;

  v_payload := v_row.decrypted_secret::jsonb;

  return jsonb_build_object(
    'ok', true,
    'shortcode', v_row.shortcode,
    'environment', v_row.environment,
    'status', v_row.status,
    'consumer_key', v_payload->>'consumer_key',
    'consumer_secret', v_payload->>'consumer_secret'
  );
end;
$function$;

revoke all on function public.service_get_ungani_mpesa_credentials(uuid) from public, anon, authenticated;
grant execute on function public.service_get_ungani_mpesa_credentials(uuid) to service_role;

-- ============================================================
-- VERIFICATION - run and paste back the output.
-- ============================================================

-- Confirm the function body now checks status in ('pending','active')
-- and no longer returns initiator_name/initiator_password
select pg_get_functiondef(oid)
from pg_proc
where proname = 'service_get_ungani_mpesa_credentials';

-- Confirm grants: service_role only, nothing for public/anon/authenticated
select routine_name, grantee, privilege_type
from information_schema.routine_privileges
where routine_name = 'service_get_ungani_mpesa_credentials'
order by grantee;

-- Report-only: how many existing vault secrets (from before today) still
-- contain initiator_name/initiator_password in their payload. Nothing is
-- changed by this query.
select count(*) as secrets_with_initiator_fields
from public.ungani_tenant_mpesa_connections c
join vault.decrypted_secrets s on s.id = c.vault_secret_id
where s.decrypted_secret::jsonb ? 'initiator_name'
   or s.decrypted_secret::jsonb ? 'initiator_password';
