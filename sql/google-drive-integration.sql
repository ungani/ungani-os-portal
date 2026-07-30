-- UNGANI OS: Google Drive integration (Option B - Connect + Picker).
-- Run this once in the Supabase SQL editor.
--
-- Design notes:
--   - Deliberately NOT reusing the existing tenant_integrations table
--     (GPS/CCTV, see sql/tenant-integrations-setup.sql). That table's RLS
--     grants direct client SELECT on its config jsonb column - correct
--     for self-reported provider info, wrong for a real Google refresh
--     token, which must never be readable by client-side JS or a direct
--     REST call. This table has NO client-facing grants at all - every
--     read/write goes through either a SECURITY DEFINER RPC (which never
--     returns the token itself) or the service-role key, used only
--     inside Vercel serverless functions, never in browser code.
--   - One row per tenant (primary key), matching the "connect once, pick
--     files as needed" Option B design - not one row per connected file.
--   - refresh_token is long-lived (Google only expires it if the user
--     revokes access or it's unused for 6 months) - access_token/
--     token_expires_at are refreshed on demand by
--     api/google-drive-get-access-token.js and cached here so most
--     Picker opens don't need a fresh Google round-trip.

create table if not exists public.tenant_google_drive_connections (
  tenant_id uuid primary key references public.tenants(id) on delete cascade,
  refresh_token text not null,
  access_token text,
  token_expires_at timestamptz,
  connected_email text,
  scope text,
  connected_by_user_id uuid,
  connected_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.tenant_google_drive_connections is 'Google Drive OAuth connection per tenant (Option B: Connect + Picker). Token columns are never exposed to client-side code - read/written only via service-role serverless functions and SECURITY DEFINER RPCs that withhold the token itself.';
comment on column public.tenant_google_drive_connections.refresh_token is 'Long-lived Google OAuth refresh token. NEVER return this from any RPC or endpoint response.';
comment on column public.tenant_google_drive_connections.connected_by_user_id is 'auth.uid() of whoever ran the connect flow. Informational only, no FK - matches ungani_audit_log.actor_user_id''s loose-reference convention.';

alter table public.tenant_google_drive_connections enable row level security;

-- No policies granted to `authenticated` on purpose - this table is
-- intentionally unreachable via the client SDK. All access is via
-- SECURITY DEFINER functions (which run as the table owner, bypassing
-- RLS) or the service-role key used only in api/*.js.
grant select, insert, update, delete on public.tenant_google_drive_connections to service_role;

-- Status check - returns whether this tenant has a Drive connection and
-- (safe, non-sensitive) metadata about it. Never returns any token.
create or replace function public.get_my_ungani_google_drive_status()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_row public.tenant_google_drive_connections;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('connected', false);
  end if;

  select * into v_row
  from public.tenant_google_drive_connections
  where tenant_id = v_tenant_id;

  if v_row.tenant_id is null then
    return jsonb_build_object('connected', false);
  end if;

  return jsonb_build_object(
    'connected', true,
    'connected_email', v_row.connected_email,
    'connected_at', v_row.connected_at
  );
exception
  when others then
    return jsonb_build_object('connected', false, 'error', sqlerrm);
end;
$function$;

grant execute on function public.get_my_ungani_google_drive_status() to authenticated;

-- Disconnect - deletes this tenant's connection row. A later Picker open
-- will show "Connect Google Drive" again; nothing else in the app
-- (documents already linked) is affected, since we only ever stored a
-- file's URL/id/name on the document record itself, not a live
-- dependency on the connection.
create or replace function public.disconnect_my_ungani_google_drive()
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
    return jsonb_build_object('ok', false, 'message', 'Could not resolve your tenant.');
  end if;

  delete from public.tenant_google_drive_connections where tenant_id = v_tenant_id;

  return jsonb_build_object('ok', true);
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

grant execute on function public.disconnect_my_ungani_google_drive() to authenticated;
