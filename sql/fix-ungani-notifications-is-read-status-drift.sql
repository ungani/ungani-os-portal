-- Real, live data (Demo Dyar Properties, tenant a29af055-e4f0-48cf-af97-
-- f99081a9106b) showed 11 historical rows where is_read=false but
-- status='read' - a legacy write path (predating every function in this
-- repo) that only ever updated one of the two read-tracking columns.
-- status is treated as authoritative everywhere now (client-shared.js's
-- Engine and client.html's dashboard bell both fixed to check status
-- only, ignoring is_read, for event-type notifications - see the
-- accompanying JS commit). This one-time backfill makes is_read agree
-- with status for every existing row, app-wide (not scoped to one
-- tenant - this is a data-drift bug class, not a tenant-specific issue),
-- so nothing reads a stale is_read value going forward either.
--
-- `is_read is distinct from (status = 'read')` catches disagreement in
-- BOTH directions (is_read=false/status=read, and the reverse
-- is_read=true/status=unread, in case that combination exists for some
-- other tenant) and is null-safe (is_read is nullable).

update public.ungani_notifications
set is_read = (status = 'read'), updated_at = now()
where is_read is distinct from (status = 'read');

-- VERIFICATION - run separately after the update above, confirms zero
-- disagreement remains anywhere in the table.
select count(*) as remaining_disagreement
from public.ungani_notifications
where is_read is distinct from (status = 'read');
