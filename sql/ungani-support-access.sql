-- UNGANI OS: UNGANI Support Access, Phase 1 storage layer.
-- Run this once in the Supabase SQL editor.
--
-- What this feature is: a client-controlled, time-limited, revocable
-- permission grant letting UNGANI support staff view (and, if the client
-- chooses, edit) their workspace data for troubleshooting - without ever
-- needing the client's password, and without a separate admin
-- credential. An admin who wants to use an active grant simply uses
-- their own existing login; the grant is a permission overlay checked
-- live by RLS, not a new identity.
--
-- Design notes:
--   - ONE row per tenant (tenant_id is unique), mutated in place through
--     a status machine: none -> pending -> active -> (revoked | expired)
--     -> pending/active again on the next invite/grant. This mirrors
--     tenant_integrations' "one row, status flip, never delete" pattern
--     (see sql/tenant-integrations-setup.sql) rather than a
--     multi-row history table - the full history already lives in
--     ungani_audit_log (support_access_invited/granted/revoked entries),
--     so this table only needs to represent CURRENT state.
--   - "Invite UNGANI Support" -> status='pending', access_level defaults
--     to view_only, no expiry yet - this is a request/flag, not access.
--   - "Grant Temporary Access" -> client sets access_level + duration
--     and the app sets status='active', granted_at=now(),
--     expires_at=granted_at+duration. Can be called directly without a
--     prior invite (upserts the same row).
--   - "Revoke Access at Any Time" -> status='revoked', revoked_at=now().
--     Because every RLS predicate below checks status='active' AND
--     expires_at > now() live (not a cached/derived flag), revoking
--     takes effect immediately on the next query - no cron job needed
--     to "close" a grant, and none is added for expiry either (a grant
--     past its expires_at is simply no longer active_now(), the stored
--     status='active' value is kept as an honest historical record of
--     what was granted rather than silently rewritten).
--   - access_level/status are plain text (app-validated), matching this
--     app's existing convention (see tenant_integrations' identical
--     choice) - no DB enum, so new values never need a migration.
--   - Write access to this table is OWNER-ONLY (see the role check in
--     the insert/update policies) - this is a deliberately
--     higher-privilege control than the Owner/Manager/Accountant/Staff
--     permission system in my-team-access.html/team_members, per the
--     spec's explicit requirement that Support Access be a separate
--     section, not part of normal staff management. Any authenticated
--     tenant member can SELECT (see it's on/off), matching this app's
--     general "transparency within a tenant" convention, but only the
--     owner can flip it.
--   - Admins get read-only access to every tenant's grant row (so the
--     new admin-support-access.html can list "who has granted us
--     access"), same shape as sql/audit-log-setup.sql's two-policy
--     pattern. Admins never get INSERT/UPDATE/DELETE on this table -
--     the full lifecycle (invite/grant/revoke) stays entirely in the
--     client's hands, matching the spec's four client-controlled verbs.
--   - No delete policy anywhere, on purpose - same soft-delete
--     convention as tenant_integrations.
--
-- UNGANI Support access to a tenant's own operational data (Money,
-- Tasks, Documents, People, Items, Records) is granted further down in
-- this file via new, PURELY ADDITIVE policies on those 7 tables - the
-- exact same table list already used as the tenant-wide audit-visibility
-- allowlist in sql/audit-log-tenant-business-record-read-policy.sql, so
-- table/column names here are known-correct against that precedent.
-- Nothing below modifies, drops, or narrows any existing policy on those
-- tables - it only adds a new way IN, conditioned on an active grant.
-- view_only grants get read (select); full_access grants additionally
-- get insert/update - deliberately NOT delete, matching this app's
-- existing safe-deletion (recycle bin / status flip) convention, so a
-- support session can fix records but never permanently remove one.

create table if not exists public.ungani_support_access_grants (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null unique references public.tenants(id) on delete cascade,
  status text not null default 'none',
  access_level text not null default 'view_only',
  duration_hours integer,
  invited_at timestamptz,
  invited_by uuid,
  granted_at timestamptz,
  granted_by uuid,
  expires_at timestamptz,
  revoked_at timestamptz,
  revoked_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.ungani_support_access_grants is 'UNGANI Support Access: one row per tenant, client-controlled status machine (none/pending/active/revoked/expired). No admin write access - full lifecycle stays with the client. Full history lives in ungani_audit_log, not here.';
comment on column public.ungani_support_access_grants.status is 'Application-validated, not DB-enforced. Values: none, pending, active, revoked, expired. A row past expires_at is treated as inactive live (status is NOT auto-rewritten to expired by a background job) - always check status=''active'' AND expires_at > now() together, never status alone.';
comment on column public.ungani_support_access_grants.access_level is 'Application-validated, not DB-enforced. Values: view_only, full_access.';
comment on column public.ungani_support_access_grants.invited_by is 'auth.uid() of the client user who invited support. Informational only, no FK - matches ungani_audit_log.actor_user_id''s loose-reference convention.';
comment on column public.ungani_support_access_grants.granted_by is 'auth.uid() of the client user who activated the grant (may differ from invited_by).';
comment on column public.ungani_support_access_grants.revoked_by is 'auth.uid() of the client user who revoked the grant.';

create index if not exists ungani_support_access_grants_status_idx on public.ungani_support_access_grants (status);

alter table public.ungani_support_access_grants enable row level security;

drop policy if exists "Tenant members can read their own support access grant" on public.ungani_support_access_grants;
create policy "Tenant members can read their own support access grant"
  on public.ungani_support_access_grants
  for select
  to authenticated
  using (tenant_id = public.get_my_ungani_tenant_id());

drop policy if exists "Tenant owner can create their own support access grant" on public.ungani_support_access_grants;
create policy "Tenant owner can create their own support access grant"
  on public.ungani_support_access_grants
  for insert
  to authenticated
  with check (
    tenant_id = public.get_my_ungani_tenant_id()
    and exists (
      select 1 from public.users u
      where u.id = auth.uid()
        and u.tenant_id = ungani_support_access_grants.tenant_id
        and lower(u.role) = 'owner'
    )
  );

drop policy if exists "Tenant owner can update their own support access grant" on public.ungani_support_access_grants;
create policy "Tenant owner can update their own support access grant"
  on public.ungani_support_access_grants
  for update
  to authenticated
  using (tenant_id = public.get_my_ungani_tenant_id())
  with check (
    tenant_id = public.get_my_ungani_tenant_id()
    and exists (
      select 1 from public.users u
      where u.id = auth.uid()
        and u.tenant_id = ungani_support_access_grants.tenant_id
        and lower(u.role) = 'owner'
    )
  );

drop policy if exists "Admins can read all support access grants" on public.ungani_support_access_grants;
create policy "Admins can read all support access grants"
  on public.ungani_support_access_grants
  for select
  to authenticated
  using (is_ungani_admin());

-- No delete policy anywhere on purpose - the row is reused/updated for
-- every invite -> grant -> revoke cycle a tenant goes through.


-- =====================================================================
-- Admin read/write access to a tenant's operational data, gated by an
-- active support access grant. Purely additive - every policy below is
-- a NEW policy alongside whatever already exists on these tables;
-- nothing here can narrow existing access, only add a new path in.
-- =====================================================================

-- business_items ------------------------------------------------------

drop policy if exists "UNGANI support access can read (business_items)" on public.business_items;
create policy "UNGANI support access can read (business_items)"
  on public.business_items
  for select
  to authenticated
  using (
    exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = business_items.tenant_id
        and g.status = 'active'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can update (business_items)" on public.business_items;
create policy "UNGANI support access can update (business_items)"
  on public.business_items
  for update
  to authenticated
  using (
    exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = business_items.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  )
  with check (
    exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = business_items.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can insert (business_items)" on public.business_items;
create policy "UNGANI support access can insert (business_items)"
  on public.business_items
  for insert
  to authenticated
  with check (
    exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = business_items.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

-- transactions ----------------------------------------------------------

drop policy if exists "UNGANI support access can read (transactions)" on public.transactions;
create policy "UNGANI support access can read (transactions)"
  on public.transactions
  for select
  to authenticated
  using (
    exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = transactions.tenant_id
        and g.status = 'active'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can update (transactions)" on public.transactions;
create policy "UNGANI support access can update (transactions)"
  on public.transactions
  for update
  to authenticated
  using (
    exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = transactions.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  )
  with check (
    exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = transactions.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can insert (transactions)" on public.transactions;
create policy "UNGANI support access can insert (transactions)"
  on public.transactions
  for insert
  to authenticated
  with check (
    exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = transactions.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

-- tasks -------------------------------------------------------------

drop policy if exists "UNGANI support access can read (tasks)" on public.tasks;
create policy "UNGANI support access can read (tasks)"
  on public.tasks
  for select
  to authenticated
  using (
    exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = tasks.tenant_id
        and g.status = 'active'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can update (tasks)" on public.tasks;
create policy "UNGANI support access can update (tasks)"
  on public.tasks
  for update
  to authenticated
  using (
    exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = tasks.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  )
  with check (
    exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = tasks.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can insert (tasks)" on public.tasks;
create policy "UNGANI support access can insert (tasks)"
  on public.tasks
  for insert
  to authenticated
  with check (
    exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = tasks.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

-- business_records -------------------------------------------------------

drop policy if exists "UNGANI support access can read (business_records)" on public.business_records;
create policy "UNGANI support access can read (business_records)"
  on public.business_records
  for select
  to authenticated
  using (
    exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = business_records.tenant_id
        and g.status = 'active'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can update (business_records)" on public.business_records;
create policy "UNGANI support access can update (business_records)"
  on public.business_records
  for update
  to authenticated
  using (
    exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = business_records.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  )
  with check (
    exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = business_records.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can insert (business_records)" on public.business_records;
create policy "UNGANI support access can insert (business_records)"
  on public.business_records
  for insert
  to authenticated
  with check (
    exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = business_records.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

-- documents ------------------------------------------------------------

drop policy if exists "UNGANI support access can read (documents)" on public.documents;
create policy "UNGANI support access can read (documents)"
  on public.documents
  for select
  to authenticated
  using (
    exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = documents.tenant_id
        and g.status = 'active'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can update (documents)" on public.documents;
create policy "UNGANI support access can update (documents)"
  on public.documents
  for update
  to authenticated
  using (
    exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = documents.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  )
  with check (
    exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = documents.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can insert (documents)" on public.documents;
create policy "UNGANI support access can insert (documents)"
  on public.documents
  for insert
  to authenticated
  with check (
    exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = documents.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

-- client_people ----------------------------------------------------------

drop policy if exists "UNGANI support access can read (client_people)" on public.client_people;
create policy "UNGANI support access can read (client_people)"
  on public.client_people
  for select
  to authenticated
  using (
    exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = client_people.tenant_id
        and g.status = 'active'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can update (client_people)" on public.client_people;
create policy "UNGANI support access can update (client_people)"
  on public.client_people
  for update
  to authenticated
  using (
    exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = client_people.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  )
  with check (
    exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = client_people.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can insert (client_people)" on public.client_people;
create policy "UNGANI support access can insert (client_people)"
  on public.client_people
  for insert
  to authenticated
  with check (
    exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = client_people.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

-- business_events ---------------------------------------------------------

drop policy if exists "UNGANI support access can read (business_events)" on public.business_events;
create policy "UNGANI support access can read (business_events)"
  on public.business_events
  for select
  to authenticated
  using (
    exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = business_events.tenant_id
        and g.status = 'active'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can update (business_events)" on public.business_events;
create policy "UNGANI support access can update (business_events)"
  on public.business_events
  for update
  to authenticated
  using (
    exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = business_events.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  )
  with check (
    exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = business_events.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can insert (business_events)" on public.business_events;
create policy "UNGANI support access can insert (business_events)"
  on public.business_events
  for insert
  to authenticated
  with check (
    exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = business_events.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

-- Deliberately no delete policy for any of the 7 tables above - a
-- support session can view and fix records under a full_access grant,
-- but never permanently delete one, matching this app's existing
-- safe-deletion (recycle bin / status flip) convention.


-- =====================================================================
-- Let the tenant owner see support-access audit events even when THEY
-- weren't the actor (e.g. support_access_session_opened, where the
-- actor is the admin who opened it). Without this, ungani_audit_log's
-- existing "actor can read their own rows" policy would only show the
-- owner their OWN invite/grant/revoke actions, silently hiding the one
-- event a client cares about most for req #4 (transparency/security):
-- knowing when UNGANI actually looked at their data. Same narrow,
-- additive allowlist pattern as
-- sql/audit-log-tenant-business-record-read-policy.sql, scoped to just
-- this feature's action prefix rather than opening up all session/HR
-- events tenant-wide.
-- =====================================================================

drop policy if exists "Tenant owner can read their tenant's support access audit trail" on public.ungani_audit_log;
create policy "Tenant owner can read their tenant's support access audit trail"
  on public.ungani_audit_log
  for select
  to authenticated
  using (
    action like 'support_access_%'
    and tenant_id = public.get_my_ungani_tenant_id()
  );


-- =====================================================================
-- New audit log action strings this feature introduces (no schema
-- change needed - ungani_audit_log.action is plain text, see
-- sql/audit-log-setup.sql). Listed here for reference only:
--   support_access_invited          - client invited UNGANI support
--   support_access_granted          - client activated a grant
--   support_access_revoked          - client revoked a grant
--   support_access_session_opened   - admin opened the scoped workspace
--   support_access_record_modified  - admin edited a record under
--                                      full_access (metadata carries
--                                      entity_type/entity_id/what changed)
-- These are also added to admin-audit-logs.html's ACTION_OPTIONS filter
-- list in the app-layer changes for this feature.
-- =====================================================================
