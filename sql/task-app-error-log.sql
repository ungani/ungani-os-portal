-- UNGANI OS: Passive App Error Log (self-monitoring, Phase 1)
-- Run this once in the Supabase SQL editor.
--
-- Design notes (mirrors sql/audit-log-setup.sql deliberately - same
-- shape, same reasoning):
--   - Only /api/log-app-error (using SUPABASE_SERVICE_ROLE_KEY) ever
--     writes to this table. No INSERT policy is granted to anon/
--     authenticated - that endpoint verifies the caller's JWT and
--     resolves actor_user_id/actor_email/tenant_id itself, so none of
--     that is ever trusted from client input.
--   - Reads are admin-only via is_ungani_admin(), matching every other
--     cross-tenant admin surface in this app.
--   - Unlike the audit log (fully immutable), a "mark resolved" workflow
--     is genuinely useful here - an admin needs to be able to triage and
--     dismiss entries. Rather than grant a raw UPDATE policy, that's done
--     through a narrow RPC (admin_mark_ungani_error_resolved), matching
--     how every other admin write in this app goes through an RPC
--     instead of a direct table grant.

create table if not exists public.app_error_log (
  id uuid primary key default gen_random_uuid(),
  occurred_at timestamptz not null default now(),
  surface text not null,
  tenant_id uuid,
  actor_user_id uuid,
  actor_email text,
  page text,
  error_type text not null,
  message text not null,
  context jsonb,
  resolved boolean not null default false,
  resolved_at timestamptz,
  resolved_by uuid
);

comment on table public.app_error_log is 'Passive error log: failures from client-shared.js/admin-shared.js try/catch blocks, written only by /api/log-app-error (service role). Read-only to admins via RLS; resolution is via admin_mark_ungani_error_resolved().';
comment on column public.app_error_log.surface is 'Which shell logged the error: client or admin.';
comment on column public.app_error_log.tenant_id is 'Tenant the acting user belonged to at the time, resolved server-side. Null for platform admins.';
comment on column public.app_error_log.page is 'window.location.pathname at the time of the error, e.g. /client.html.';
comment on column public.app_error_log.error_type is 'Short, stable category tag chosen at the call site, e.g. tenant_lookup_failed, sidebar_badge_payment_proofs.';

create index if not exists app_error_log_occurred_at_idx on public.app_error_log (occurred_at desc);
create index if not exists app_error_log_surface_idx on public.app_error_log (surface);
create index if not exists app_error_log_tenant_id_idx on public.app_error_log (tenant_id);
create index if not exists app_error_log_error_type_idx on public.app_error_log (error_type);
create index if not exists app_error_log_resolved_idx on public.app_error_log (resolved);

alter table public.app_error_log enable row level security;

-- Table-level grant, distinct from the RLS policy below - without this,
-- PostgREST returns "permission denied for table app_error_log" (a plain
-- GRANT failure) regardless of RLS, since the original run of this script
-- didn't include it and (unlike ungani_audit_log) it wasn't picked up from
-- elsewhere. Found live via admin-error-log.html returning 403.
grant select on public.app_error_log to authenticated;

drop policy if exists "Admins can read app error log" on public.app_error_log;
create policy "Admins can read app error log"
  on public.app_error_log
  for select
  to authenticated
  using (is_ungani_admin());

-- Deliberately no insert/update/delete policies for anon/authenticated -
-- the service-role key used by /api/log-app-error bypasses RLS entirely,
-- and resolution goes through the RPC below (SECURITY DEFINER), not a
-- direct table grant.

create or replace function public.admin_mark_ungani_error_resolved(p_error_id uuid)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not coalesce(public.is_ungani_admin(), false) then
    raise exception 'Only UNGANI admins can resolve error log entries.';
  end if;

  update public.app_error_log
  set resolved = true,
      resolved_at = now(),
      resolved_by = auth.uid()
  where id = p_error_id;

  return found;
end;
$function$;

grant execute on function public.admin_mark_ungani_error_resolved(uuid) to authenticated;

-- ============================================================
-- VERIFICATION - run and paste back the output.
-- ============================================================

select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'app_error_log'
order by ordinal_position;

select policyname, cmd, roles
from pg_policies
where schemaname = 'public' and tablename = 'app_error_log';

select proname, prosecdef
from pg_proc
where proname = 'admin_mark_ungani_error_resolved';
