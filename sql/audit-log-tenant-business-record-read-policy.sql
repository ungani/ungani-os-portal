-- UNGANI OS: audit log tenant-wide read policy for business-record activity
-- (fixes an RLS gap found while building the Asset Management module's
-- Phase 2 per-asset Activity Timeline). Run this once in the Supabase
-- SQL editor.
--
-- The problem: ungani_audit_log's only two SELECT policies (see
-- audit-log-setup.sql) are "admins can read everything" and "a user can
-- read rows where THEY were the actor" (actor_user_id = auth.uid()).
-- There is no policy letting a user read a co-worker's entries for the
-- same tenant. A per-item timeline that filters by entity_id/tenant_id
-- (not actor_user_id) therefore silently returns an INCOMPLETE history
-- for any multi-staff tenant - e.g. Jane sees her own edits to an item
-- but not Bob's, even though they work at the same business.
--
-- The fix is deliberately narrow, not a blanket "see everything for your
-- tenant" policy: it only opens up business-record activity (the kind a
-- record-scoped timeline actually needs), scoped to a fixed allowlist of
-- entity_type values. Session/HR-type events - login, logout,
-- access_denied, role_changed, staff_added, staff_permission_changed,
-- staff_disabled, tenant_status_changed, tenant_profile_updated,
-- subscription_updated - are deliberately NOT in the allowlist, so they
-- stay restricted to the acting user themselves or admins. Postgres OR's
-- multiple SELECT policies together, so this is purely additive - it
-- cannot narrow anyone's existing access, only expand it for the
-- specific rows listed below.
--
-- If a future phase needs a new entity_type's audit trail visible
-- tenant-wide (e.g. "client_people" changes), add it to the allowlist
-- below rather than writing a new policy - keeps the "what's tenant-wide
-- visible" decision in one place.

drop policy if exists "Users can read their tenant's business-record audit trail" on public.ungani_audit_log;

create policy "Users can read their tenant's business-record audit trail"
  on public.ungani_audit_log
  for select
  to authenticated
  using (
    entity_type in ('business_items', 'transactions', 'tasks', 'business_records', 'documents', 'client_people', 'business_events')
    and tenant_id = (select tenant_id from public.users where id = auth.uid())
  );
