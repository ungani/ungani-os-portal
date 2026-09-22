-- Diagnostic only. Any row returned here means that tenant's data is
-- CURRENTLY exploitable by any authenticated user who knows its
-- tenant_id, not just a UNGANI admin, until the fix below is run.
select tenant_id, status, access_level, granted_at, expires_at
from public.ungani_support_access_grants
where status = 'active' and expires_at > now();
