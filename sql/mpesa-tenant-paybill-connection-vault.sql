-- ============================================================
-- UNGANI OS: Per-tenant M-Pesa Paybill/Till connection storage
-- (foundation piece for "connect your own Paybill" - real client
-- meeting feedback, M-Pesa auto-matching Phase 2)
--
-- Distinct from api/mpesa-stk-push.js, which only handles UNGANI's
-- OWN single Paybill (env-var Shortcode/Consumer Key/Secret) for
-- subscription/POS payments via STK Push. This is the opposite
-- direction: a client's OWN Paybill/Till, receiving payments FROM
-- their own tenants, via Daraja's C2B API (not built yet - this
-- migration is only the credential-storage foundation everything
-- else depends on).
--
-- SECURITY MODEL: Consumer Key/Secret + Initiator Name/Password are
-- real financial credentials capable of moving money and re-pointing
-- a client's own Paybill's callback URLs - never stored as plaintext.
-- Confirmed live on this project (2026-09-17): Supabase Vault
-- (vault.create_secret / vault.decrypted_secrets) works end-to-end
-- despite pgsodium not showing in pg_extension - Supabase manages it
-- outside the standard extension registry on this project. The 4
-- credential fields are bundled into one JSON blob and stored via
-- vault.create_secret(); the root encryption key lives in Supabase's
-- own infrastructure, never in this database or in application code.
-- Only the resulting vault_secret_id (a plain reference, useless
-- without vault access) is stored in our own table.
--
-- Shortcode is kept as its OWN PLAIN column, not inside the vault
-- blob - it must stay queryable, since a future inbound Daraja C2B
-- webhook will need "where shortcode = <incoming shortcode>" to
-- resolve which tenant a payment belongs to, and a shortcode is not
-- itself secret (it's the number a business publishes to its own
-- customers).
--
-- Two RPCs, matching this codebase's existing owner_*/service_*
-- naming and grant conventions:
--   owner_connect_ungani_mpesa_paybill() - tenant owner only, called
--     from a future Settings wizard. Upserts: creates a new vault
--     secret + connection row on first connect, or updates the
--     existing vault secret in place (same vault_secret_id) if the
--     owner reconnects/rotates credentials later.
--   service_get_ungani_mpesa_credentials() - service_role ONLY,
--     never grantable to authenticated - called exclusively from a
--     trusted serverless function immediately before a real Daraja
--     call. Plaintext credentials are never returned to any browser
--     session, matching how supabaseAdmin is used in
--     api/mpesa-stk-push.js.
-- ============================================================

create table if not exists public.ungani_tenant_mpesa_connections (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null unique references public.tenants(id) on delete cascade,
  shortcode text not null,
  environment text not null default 'sandbox' check (environment in ('sandbox', 'production')),
  vault_secret_id uuid not null,
  status text not null default 'active' check (status in ('active', 'disabled')),
  connected_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- A shortcode can only resolve to one ACTIVE tenant connection at a
-- time (needed later for webhook routing by shortcode) - a partial
-- index rather than a plain unique constraint so a disabled/replaced
-- connection doesn't block a shortcode from being reconnected.
create unique index if not exists ungani_tenant_mpesa_connections_shortcode_active_idx
  on public.ungani_tenant_mpesa_connections (shortcode)
  where status = 'active';

alter table public.ungani_tenant_mpesa_connections enable row level security;

-- No RLS policies for authenticated/anon at all - every access path
-- goes through the two security-definer RPCs below, same pattern as
-- every other sensitive-write table in this codebase (e.g.
-- ungani_payees, ungani_approval_requests).
revoke all on public.ungani_tenant_mpesa_connections from public, authenticated, anon;
grant select, insert, update on public.ungani_tenant_mpesa_connections to service_role;

-- ============================================================
-- owner_connect_ungani_mpesa_paybill: tenant owner only
-- ============================================================
create or replace function public.owner_connect_ungani_mpesa_paybill(
  p_shortcode text,
  p_consumer_key text,
  p_consumer_secret text,
  p_initiator_name text,
  p_initiator_password text,
  p_environment text default 'sandbox'
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_shortcode text;
  v_consumer_key text;
  v_consumer_secret text;
  v_initiator_name text;
  v_initiator_password text;
  v_environment text;
  v_payload text;
  v_existing_id uuid;
  v_existing_secret_id uuid;
  v_secret_id uuid;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if public.is_my_ungani_tenant_owner(v_tenant_id) is not true then
    return jsonb_build_object('ok', false, 'message', 'Only the business owner can connect a Paybill/Till.');
  end if;

  v_shortcode := nullif(trim(coalesce(p_shortcode, '')), '');
  v_consumer_key := nullif(trim(coalesce(p_consumer_key, '')), '');
  v_consumer_secret := nullif(trim(coalesce(p_consumer_secret, '')), '');
  v_initiator_name := nullif(trim(coalesce(p_initiator_name, '')), '');
  v_initiator_password := nullif(trim(coalesce(p_initiator_password, '')), '');
  v_environment := case when lower(trim(coalesce(p_environment, ''))) = 'production' then 'production' else 'sandbox' end;

  if v_shortcode is null or v_consumer_key is null or v_consumer_secret is null
     or v_initiator_name is null or v_initiator_password is null then
    return jsonb_build_object('ok', false, 'message', 'Shortcode, Consumer Key, Consumer Secret, Initiator Name and Initiator Password are all required.');
  end if;

  v_payload := jsonb_build_object(
    'consumer_key', v_consumer_key,
    'consumer_secret', v_consumer_secret,
    'initiator_name', v_initiator_name,
    'initiator_password', v_initiator_password
  )::text;

  select id, vault_secret_id into v_existing_id, v_existing_secret_id
  from public.ungani_tenant_mpesa_connections
  where tenant_id = v_tenant_id;

  if v_existing_id is not null then
    -- Reconnect/rotate: update the SAME vault secret in place rather
    -- than creating a new one, so the vault_secret_id reference on
    -- our own row never has to change.
    perform vault.update_secret(v_existing_secret_id, v_payload);

    update public.ungani_tenant_mpesa_connections
    set shortcode = v_shortcode,
        environment = v_environment,
        status = 'active',
        connected_by = auth.uid(),
        updated_at = now()
    where id = v_existing_id;

    return jsonb_build_object('ok', true, 'mode', 'updated', 'shortcode', v_shortcode, 'environment', v_environment);
  end if;

  select vault.create_secret(
    v_payload,
    'mpesa_conn_' || v_tenant_id::text,
    'M-Pesa Daraja credentials for tenant ' || v_tenant_id::text
  ) into v_secret_id;

  insert into public.ungani_tenant_mpesa_connections (
    tenant_id, shortcode, environment, vault_secret_id, status, connected_by
  )
  values (
    v_tenant_id, v_shortcode, v_environment, v_secret_id, 'active', auth.uid()
  );

  return jsonb_build_object('ok', true, 'mode', 'connected', 'shortcode', v_shortcode, 'environment', v_environment);
exception
  when unique_violation then
    return jsonb_build_object('ok', false, 'message', 'That Shortcode is already connected to another active account.');
end;
$function$;

-- Postgres grants EXECUTE to PUBLIC on function creation by default
-- unless explicitly revoked - explicitly locking this down to
-- authenticated only, even though get_my_ungani_tenant_id() already
-- fails closed for an unauthenticated caller (returns null tenant_id),
-- since this whole migration is about not leaving default gaps in
-- place around credential storage.
revoke all on function public.owner_connect_ungani_mpesa_paybill(text, text, text, text, text, text) from public;
grant execute on function public.owner_connect_ungani_mpesa_paybill(text, text, text, text, text, text) to authenticated;

-- ============================================================
-- service_get_ungani_mpesa_credentials: service_role ONLY
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
  select c.shortcode, c.environment, s.decrypted_secret
  into v_row
  from public.ungani_tenant_mpesa_connections c
  join vault.decrypted_secrets s on s.id = c.vault_secret_id
  where c.tenant_id = p_tenant_id
    and c.status = 'active';

  if v_row is null then
    return jsonb_build_object('ok', false, 'message', 'No active M-Pesa Paybill connection for this tenant.');
  end if;

  v_payload := v_row.decrypted_secret::jsonb;

  return jsonb_build_object(
    'ok', true,
    'shortcode', v_row.shortcode,
    'environment', v_row.environment,
    'consumer_key', v_payload->>'consumer_key',
    'consumer_secret', v_payload->>'consumer_secret',
    'initiator_name', v_payload->>'initiator_name',
    'initiator_password', v_payload->>'initiator_password'
  );
end;
$function$;

-- Never grantable to authenticated/anon - this is the one function in
-- this migration that returns plaintext credentials, so it must only
-- ever be callable by a service-role client inside a trusted
-- serverless function, matching the exact revoke+grant shape already
-- used for service_adjust_ungani_stock (sql/pos-quick-sale-fix-service-role-rpcs.sql).
revoke all on function public.service_get_ungani_mpesa_credentials(uuid) from public, authenticated;
grant execute on function public.service_get_ungani_mpesa_credentials(uuid) to service_role;

-- ============================================================
-- VERIFICATION (rowsecurity lives on pg_tables, not
-- information_schema.tables)
-- ============================================================
select tablename, rowsecurity
from pg_tables
where tablename = 'ungani_tenant_mpesa_connections';

select routine_name, security_type
from information_schema.routines
where routine_name in ('owner_connect_ungani_mpesa_paybill', 'service_get_ungani_mpesa_credentials');

select routine_name, grantee, privilege_type
from information_schema.routine_privileges
where routine_name in ('owner_connect_ungani_mpesa_paybill', 'service_get_ungani_mpesa_credentials')
order by routine_name, grantee;
