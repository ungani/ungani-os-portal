-- UNGANI OS: Audit Log (Security/Performance/Data spec, §6)
-- Run this once in the Supabase SQL editor.
--
-- Design notes:
--   - Only the /api/log-audit-event serverless function (using the
--     SUPABASE_SERVICE_ROLE_KEY) ever writes to this table. No INSERT
--     policy is granted to the anon/authenticated roles on purpose -
--     that function verifies the caller's JWT and stamps actor_user_id/
--     actor_email/ip_address/created_at itself, so none of that is ever
--     trusted from client input.
--   - Reads are admin-only via is_ungani_admin(), matching the pattern
--     already used to gate cross-tenant reads elsewhere in this app
--     (admin.html, admin-profiles.html, users.html, sections.html,
--     admin-home.html).
--   - Rows are immutable: no UPDATE/DELETE policy is granted to anyone
--     via the API surface. If a correction is ever needed, do it
--     directly in the Supabase dashboard as the postgres role.

create table if not exists public.ungani_audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid,
  actor_email text,
  actor_tenant_id uuid,
  tenant_id uuid,
  action text not null,
  entity_type text,
  entity_id text,
  description text,
  metadata jsonb,
  ip_address text,
  user_agent text,
  created_at timestamptz not null default now()
);

comment on table public.ungani_audit_log is 'Immutable security audit trail: logins, logouts, deletions, permission/status changes. Written only by /api/log-audit-event (service role). Read-only to admins via RLS.';
comment on column public.ungani_audit_log.actor_tenant_id is 'Tenant of the acting user, resolved server-side from their own users-table row. Null for platform admins with no tenant scope.';
comment on column public.ungani_audit_log.tenant_id is 'Tenant the event pertains to (may differ from actor_tenant_id, e.g. an admin approving another tenant''s registration). Client-supplied context, not a security boundary - reads are already admin-gated.';

create index if not exists ungani_audit_log_created_at_idx on public.ungani_audit_log (created_at desc);
create index if not exists ungani_audit_log_actor_user_id_idx on public.ungani_audit_log (actor_user_id);
create index if not exists ungani_audit_log_tenant_id_idx on public.ungani_audit_log (tenant_id);
create index if not exists ungani_audit_log_action_idx on public.ungani_audit_log (action);

alter table public.ungani_audit_log enable row level security;

drop policy if exists "Admins can read audit log" on public.ungani_audit_log;
create policy "Admins can read audit log"
  on public.ungani_audit_log
  for select
  to authenticated
  using (is_ungani_admin());

-- Deliberately no insert/update/delete policies for anon/authenticated -
-- the service-role key used by /api/log-audit-event bypasses RLS entirely,
-- and everyone else should be denied by default.
