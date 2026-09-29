-- ============================================================
-- UNGANI OS: M-Pesa Paybill Connect - correct status lifecycle,
-- drop unused Initiator credentials, and close two real gaps:
-- shortcode collisions (Issue A) and silently-ACKed processing
-- failures in the C2B callback (Issue A, deeper problem).
-- (2026-09-29, combined per Chris's review of the first draft)
--
-- Confirmed live facts this migration is built on (Chris pulled and
-- pasted these back - not guessed):
--   - status check constraint currently allows only ('active','disabled'),
--     default 'active'.
--   - the ONLY unique constraint on ungani_tenant_mpesa_connections is on
--     tenant_id. There is no uniqueness on shortcode at all.
--   - zero rows currently have status = 'active' - no existing tenant's
--     connection status changes as a result of this migration.
--   - owner_connect_ungani_mpesa_paybill currently takes 6 parameters
--     (shortcode, consumer_key, consumer_secret, initiator_name,
--     initiator_password, environment). Grep across api/mpesa-stk-push.js
--     and every sql/mpesa*.sql file found initiator_name/
--     initiator_password referenced ONLY inside this function's own vault
--     payload - no Transaction Status check, reversal, or B2C call exists
--     anywhere that would consume them. C2B (this feature) only needs the
--     consumer key/secret. Removed entirely below, not just left unused.
--
-- ISSUE A, the deeper problem: handleC2BConfirmation
-- (api/mpesa-stk-push.js) always ACKs Safaricom with 200, even when our
-- own processing throws - Safaricom is told "received" and the payment
-- is gone with no trace. Fixed by writing every callback to a raw log
-- table FIRST, before any tenant lookup, and only ACKing 200 once that
-- write has actually succeeded. From that point on, nothing is ever
-- lost even if matching/processing fails afterward - it just sits in
-- the raw log as 'unmatched' or 'error' for an admin to resolve,
-- instead of vanishing. Only a failure of the raw write itself now
-- returns non-2xx so Safaricom retries.
--
-- Status lifecycle after this migration (unchanged from the first
-- draft):
--   'pending'  - credentials saved, Daraja registration not yet confirmed.
--   'active'   - Daraja confirmed the registration.
--   'failed'   - Daraja rejected the registration, the HTTP call timed
--                out, or the API route hit any other exception.
--   'disabled' - reserved for a future explicit disconnect action.
-- ============================================================


-- ============================================================
-- PART 1 - connection status lifecycle + shortcode uniqueness
-- ============================================================

alter table public.ungani_tenant_mpesa_connections
  add column if not exists last_error text;

alter table public.ungani_tenant_mpesa_connections
  drop constraint if exists ungani_tenant_mpesa_connections_status_check;

alter table public.ungani_tenant_mpesa_connections
  add constraint ungani_tenant_mpesa_connections_status_check
  check (status in ('pending', 'active', 'failed', 'disabled'));

alter table public.ungani_tenant_mpesa_connections
  alter column status set default 'pending';

-- Shortcode uniqueness (Issue A, first part) - production only. Sandbox
-- shares Safaricom's shared test shortcodes across every developer on
-- the platform, so it must stay non-unique. Run the check below FIRST -
-- if it returns any rows, resolve those duplicates before the CREATE
-- UNIQUE INDEX statement, or it will fail.
select shortcode, count(*), array_agg(tenant_id) as tenant_ids
from public.ungani_tenant_mpesa_connections
where environment = 'production'
group by shortcode
having count(*) > 1;

-- Replaces the original status='active'-scoped index (wrong semantics -
-- a real paybill shortcode is only ever ownable by one business
-- regardless of that business's current connection status here).
drop index if exists public.ungani_tenant_mpesa_connections_shortcode_active_idx;

create unique index if not exists ungani_tenant_mpesa_connections_shortcode_production_idx
  on public.ungani_tenant_mpesa_connections (shortcode)
  where environment = 'production';


-- ============================================================
-- PART 2 - drop the old 6-param owner_connect_ungani_mpesa_paybill and
-- replace it with a 4-param version that no longer touches Initiator
-- credentials at all. Dropping the old signature explicitly so the two
-- overloads never coexist - PostgREST would otherwise have to guess
-- which one a plain positional RPC call means.
-- ============================================================

drop function if exists public.owner_connect_ungani_mpesa_paybill(text, text, text, text, text, text);

create or replace function public.owner_connect_ungani_mpesa_paybill(
  p_shortcode text,
  p_consumer_key text,
  p_consumer_secret text,
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
  v_environment := case when lower(trim(coalesce(p_environment, ''))) = 'production' then 'production' else 'sandbox' end;

  if v_shortcode is null or v_consumer_key is null or v_consumer_secret is null then
    return jsonb_build_object('ok', false, 'message', 'Shortcode, Consumer Key and Consumer Secret are all required.');
  end if;

  v_payload := jsonb_build_object(
    'consumer_key', v_consumer_key,
    'consumer_secret', v_consumer_secret
  )::text;

  select id, vault_secret_id into v_existing_id, v_existing_secret_id
  from public.ungani_tenant_mpesa_connections
  where tenant_id = v_tenant_id;

  if v_existing_id is not null then
    -- Reconnect/rotate: update the SAME vault secret in place rather
    -- than creating a new one, so the vault_secret_id reference on our
    -- own row never has to change.
    perform vault.update_secret(v_existing_secret_id, v_payload);

    update public.ungani_tenant_mpesa_connections
    set shortcode = v_shortcode,
        environment = v_environment,
        status = 'pending',
        last_error = null,
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
    v_tenant_id, v_shortcode, v_environment, v_secret_id, 'pending', auth.uid()
  );

  return jsonb_build_object('ok', true, 'mode', 'connected', 'shortcode', v_shortcode, 'environment', v_environment);
exception
  when unique_violation then
    return jsonb_build_object('ok', false, 'message', 'This Paybill/Till Shortcode is already connected to another account on this platform.');
end;
$function$;

revoke all on function public.owner_connect_ungani_mpesa_paybill(text, text, text, text) from public, anon, authenticated;
grant execute on function public.owner_connect_ungani_mpesa_paybill(text, text, text, text) to authenticated;


-- ============================================================
-- PART 3 - service-role-only registration outcome RPCs (unchanged
-- from the first draft) - the credential-save RPC above never marks a
-- connection 'active' itself, only these two do, and only from the
-- trusted serverless function, never from the browser.
-- ============================================================

create or replace function public.service_mark_ungani_mpesa_registration_succeeded(
  p_tenant_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  update public.ungani_tenant_mpesa_connections
  set status = 'active',
      last_error = null,
      updated_at = now()
  where tenant_id = p_tenant_id;

  return jsonb_build_object('ok', true);
end;
$function$;

revoke all on function public.service_mark_ungani_mpesa_registration_succeeded(uuid) from public, anon, authenticated;
grant execute on function public.service_mark_ungani_mpesa_registration_succeeded(uuid) to service_role;

create or replace function public.service_mark_ungani_mpesa_registration_failed(
  p_tenant_id uuid,
  p_error text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  update public.ungani_tenant_mpesa_connections
  set status = 'failed',
      last_error = nullif(trim(coalesce(p_error, '')), ''),
      updated_at = now()
  where tenant_id = p_tenant_id;

  return jsonb_build_object('ok', true);
end;
$function$;

revoke all on function public.service_mark_ungani_mpesa_registration_failed(uuid, text) from public, anon, authenticated;
grant execute on function public.service_mark_ungani_mpesa_registration_failed(uuid, text) to service_role;


-- ============================================================
-- PART 4 - owner_get_ungani_mpesa_connection_status - adds last_error,
-- uses "if not found" instead of "if v_row is null" after the select
-- into. Unchanged from the first draft.
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

  select shortcode, environment, status, last_error, created_at, updated_at
  into v_row
  from public.ungani_tenant_mpesa_connections
  where tenant_id = v_tenant_id;

  if not found then
    return jsonb_build_object('ok', true, 'connected', false);
  end if;

  return jsonb_build_object(
    'ok', true,
    'connected', v_row.status = 'active',
    'shortcode', v_row.shortcode,
    'environment', v_row.environment,
    'status', v_row.status,
    'last_error', v_row.last_error,
    'connected_at', v_row.created_at,
    'updated_at', v_row.updated_at
  );
end;
$function$;

revoke all on function public.owner_get_ungani_mpesa_connection_status() from public, anon, authenticated;
grant execute on function public.owner_get_ungani_mpesa_connection_status() to authenticated;


-- ============================================================
-- PART 5 - Issue A, the deeper problem: raw C2B callback log.
-- Every callback lands here FIRST, before any tenant lookup or
-- processing. Only api/mpesa-stk-push.js (service role) ever writes
-- to this table - no insert/update/select policy is granted to
-- anon/authenticated at all, matching the "service_role only, no
-- client access" requirement literally: RLS is enabled but carries no
-- permissive policies, so even a stray grant would still be blocked.
-- The admin view below reads it exclusively through a SECURITY
-- DEFINER RPC gated by is_ungani_admin(), never a direct table grant.
-- ============================================================

create table if not exists public.ungani_mpesa_c2b_callback_log (
  id uuid primary key default gen_random_uuid(),
  received_at timestamptz not null default now(),
  raw_payload jsonb not null,
  shortcode text,
  trans_id text,
  status text not null default 'received' check (status in ('received', 'matched', 'unmatched', 'error')),
  tenant_id uuid,
  transaction_id uuid,
  error_reason text,
  resolved boolean not null default false,
  resolved_at timestamptz,
  resolved_by uuid,
  updated_at timestamptz not null default now()
);

comment on table public.ungani_mpesa_c2b_callback_log is 'Raw log of every Daraja C2B confirmation, written before any tenant lookup - so a matching/processing failure never silently loses a real payment. service_role only; admin access is via admin_list_ungani_mpesa_unmatched_callbacks()/admin_mark_ungani_mpesa_callback_resolved(), never a direct grant.';
comment on column public.ungani_mpesa_c2b_callback_log.status is 'received = just logged, about to be processed. matched = successfully tied to a tenant/transaction (or a harmless duplicate delivery). unmatched = no active connection for this shortcode. error = an exception during processing.';

create index if not exists ungani_mpesa_c2b_callback_log_received_at_idx on public.ungani_mpesa_c2b_callback_log (received_at desc);
create index if not exists ungani_mpesa_c2b_callback_log_status_idx on public.ungani_mpesa_c2b_callback_log (status);
create index if not exists ungani_mpesa_c2b_callback_log_shortcode_idx on public.ungani_mpesa_c2b_callback_log (shortcode);
create index if not exists ungani_mpesa_c2b_callback_log_tenant_id_idx on public.ungani_mpesa_c2b_callback_log (tenant_id);

alter table public.ungani_mpesa_c2b_callback_log enable row level security;

-- Deliberately no grants and no policies for anon/authenticated - the
-- service-role key used by api/mpesa-stk-push.js bypasses RLS entirely,
-- and every admin read/write goes through the two SECURITY DEFINER
-- RPCs below instead.
revoke all on public.ungani_mpesa_c2b_callback_log from public, anon, authenticated;

create or replace function public.admin_list_ungani_mpesa_unmatched_callbacks(
  p_include_resolved boolean default false
)
returns table (
  id uuid,
  received_at timestamptz,
  raw_payload jsonb,
  shortcode text,
  trans_id text,
  status text,
  tenant_id uuid,
  transaction_id uuid,
  error_reason text,
  resolved boolean,
  resolved_at timestamptz
)
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not coalesce(public.is_ungani_admin(), false) then
    raise exception 'Only UNGANI admins can view M-Pesa callback logs.';
  end if;

  return query
  select
    l.id, l.received_at, l.raw_payload, l.shortcode, l.trans_id, l.status,
    l.tenant_id, l.transaction_id, l.error_reason, l.resolved, l.resolved_at
  from public.ungani_mpesa_c2b_callback_log l
  where l.status in ('unmatched', 'error')
    and (p_include_resolved or l.resolved = false)
  order by l.received_at desc
  limit 200;
end;
$function$;

revoke all on function public.admin_list_ungani_mpesa_unmatched_callbacks(boolean) from public, anon, authenticated;
grant execute on function public.admin_list_ungani_mpesa_unmatched_callbacks(boolean) to authenticated;

create or replace function public.admin_mark_ungani_mpesa_callback_resolved(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not coalesce(public.is_ungani_admin(), false) then
    raise exception 'Only UNGANI admins can resolve M-Pesa callback log entries.';
  end if;

  update public.ungani_mpesa_c2b_callback_log
  set resolved = true,
      resolved_at = now(),
      resolved_by = auth.uid()
  where id = p_id;

  return found;
end;
$function$;

revoke all on function public.admin_mark_ungani_mpesa_callback_resolved(uuid) from public, anon, authenticated;
grant execute on function public.admin_mark_ungani_mpesa_callback_resolved(uuid) to authenticated;


-- ============================================================
-- VERIFICATION - run and paste back the output.
-- ============================================================

-- Status check + default landed correctly
select conname, pg_get_constraintdef(oid)
from pg_constraint
where conrelid = 'public.ungani_tenant_mpesa_connections'::regclass
  and conname = 'ungani_tenant_mpesa_connections_status_check';

select column_name, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'ungani_tenant_mpesa_connections'
  and column_name in ('status', 'last_error');

-- New shortcode index exists, old status-based one is gone
select indexname, indexdef
from pg_indexes
where tablename = 'ungani_tenant_mpesa_connections'
  and schemaname = 'public';

-- Only ONE owner_connect_ungani_mpesa_paybill signature exists (4 args) -
-- confirms the old 6-param overload is really gone, not just shadowed
select p.proname, pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'owner_connect_ungani_mpesa_paybill';

-- Grants on all connection-lifecycle functions - confirms no PUBLIC/anon
-- leftover and the service-only pair really is service_role-only
select routine_name, grantee, privilege_type
from information_schema.routine_privileges
where routine_name in (
  'owner_connect_ungani_mpesa_paybill',
  'owner_get_ungani_mpesa_connection_status',
  'service_mark_ungani_mpesa_registration_succeeded',
  'service_mark_ungani_mpesa_registration_failed',
  'admin_list_ungani_mpesa_unmatched_callbacks',
  'admin_mark_ungani_mpesa_callback_resolved'
)
order by routine_name, grantee;

-- Raw callback log table: confirm RLS is on and there are zero grants
-- for anon/authenticated (service_role bypasses RLS and isn't listed
-- by this query, which is expected)
select relrowsecurity, relforcerowsecurity
from pg_class
where oid = 'public.ungani_mpesa_c2b_callback_log'::regclass;

select grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public' and table_name = 'ungani_mpesa_c2b_callback_log';

-- Confirms nothing existing is left in a stale state
select tenant_id, shortcode, environment, status, last_error
from public.ungani_tenant_mpesa_connections
order by updated_at desc;
