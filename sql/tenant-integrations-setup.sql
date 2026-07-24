-- UNGANI OS: GPS/CCTV Integrations module, Phase 1 storage layer.
-- Run this once in the Supabase SQL editor.
--
-- Design notes:
--   - Phase 1 has no live provider API to verify against (clients connect
--     their OWN existing GPS/CCTV providers - we don't have credentials
--     for any of them yet). This mirrors the existing
--     tenants.google_drive_folder_url pattern: presence of client-entered
--     data means "connected", nothing is live-verified. A later phase can
--     add real "Test Connection" calls once a specific provider is chosen
--     to integrate with first - this table's shape doesn't need to
--     change for that, only the wizard/page logic would.
--   - One row per (tenant_id, integration_type) - a business connects at
--     most one GPS provider and one CCTV provider at a time, matching
--     the two-card Integrations Hub UI (GPS card, CCTV card). Switching
--     providers or reconnecting after a disconnect updates the existing
--     row rather than inserting a new one, so integration history for a
--     given type isn't fragmented across multiple rows.
--   - Disconnecting sets status='disconnected' rather than deleting the
--     row, so the prior configuration and connection history survive for
--     support purposes - same soft-delete preference used elsewhere in
--     this app. No delete policy is granted below on purpose.
--   - integration_type/status are plain text, not a DB check constraint
--     or enum - matches this app's existing convention (see e.g. the
--     many synonymous subscription_status values) of validating these at
--     the application layer so a new integration_type or status value
--     never needs a migration.
--   - RLS: any authenticated user belonging to the tenant can read/write
--     their own tenant's rows (same baseline as other operational tables
--     like business_items/tasks - no separate owner-vs-staff split at
--     the RLS layer, matching what's already in place for those).
--     Admins get read-only access for support visibility, same shape as
--     sql/audit-log-setup.sql's two-policy pattern.

create table if not exists public.tenant_integrations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  integration_type text not null,
  provider_name text not null,
  status text not null default 'connected',
  config jsonb not null default '{}'::jsonb,
  connected_by_user_id uuid,
  connected_at timestamptz not null default now(),
  disconnected_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (tenant_id, integration_type)
);

comment on table public.tenant_integrations is 'Phase 1 GPS/CCTV Integrations module: client-entered connection info for their own external providers. Self-reported, not live-verified against any provider API yet.';
comment on column public.tenant_integrations.integration_type is 'Application-validated, not DB-enforced. Phase 1 values: gps, cctv.';
comment on column public.tenant_integrations.status is 'Application-validated, not DB-enforced. Phase 1 values: connected, disconnected.';
comment on column public.tenant_integrations.config is 'Free-form wizard fields beyond provider_name (e.g. account reference, contact, notes) - jsonb so the wizard can evolve without a schema migration.';
comment on column public.tenant_integrations.connected_by_user_id is 'auth.uid() of whoever ran the connect/reconnect wizard. Informational only, no FK - matches ungani_audit_log.actor_user_id''s loose-reference convention.';

create index if not exists tenant_integrations_tenant_id_idx on public.tenant_integrations (tenant_id);

alter table public.tenant_integrations enable row level security;

drop policy if exists "Tenant members can read their own integrations" on public.tenant_integrations;
create policy "Tenant members can read their own integrations"
  on public.tenant_integrations
  for select
  to authenticated
  using (tenant_id = public.get_my_ungani_tenant_id());

drop policy if exists "Tenant members can connect their own integrations" on public.tenant_integrations;
create policy "Tenant members can connect their own integrations"
  on public.tenant_integrations
  for insert
  to authenticated
  with check (tenant_id = public.get_my_ungani_tenant_id());

drop policy if exists "Tenant members can update their own integrations" on public.tenant_integrations;
create policy "Tenant members can update their own integrations"
  on public.tenant_integrations
  for update
  to authenticated
  using (tenant_id = public.get_my_ungani_tenant_id())
  with check (tenant_id = public.get_my_ungani_tenant_id());

drop policy if exists "Admins can read all integrations" on public.tenant_integrations;
create policy "Admins can read all integrations"
  on public.tenant_integrations
  for select
  to authenticated
  using (is_ungani_admin());

-- Deliberately no delete policy - disconnecting is a status update
-- (status='disconnected', disconnected_at=now()), not a row delete, so
-- connection history survives for support purposes.
