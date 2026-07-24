-- Read-only. Checking whether a tenant's own session can INSERT its own
-- notification rows (needed for Nia to proactively raise a real,
-- clearable notification - e.g. "3 tasks overdue" - reusing the existing
-- get_my_ungani_notifications / mark_my_ungani_notification_read system
-- instead of building a parallel, localStorage-only one).
--
-- Context: no .insert() into ungani_notifications exists anywhere in the
-- app code, client or admin side - only SELECT and UPDATE (marking read).
-- This suggests notifications are created by a server-side/system process
-- (trigger, cron, or an RPC not yet found), not directly by any frontend
-- role. This query settles it for real instead of guessing from absence.

select
  policyname,
  roles,
  cmd,          -- SELECT / INSERT / UPDATE / DELETE / ALL
  qual,         -- USING clause (read-side condition)
  with_check    -- WITH CHECK clause (write-side condition) - this is the
                -- one that matters for INSERT specifically
from pg_policies
where schemaname = 'public'
  and tablename = 'ungani_notifications'
order by cmd;

-- Also: does an insert trigger or RPC already exist that creates these
-- rows server-side (would explain the total absence of client insert
-- code)? If one exists, it may be reusable instead of building a new RPC.
select p.proname, pg_get_functiondef(p.oid) as source
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and (
    p.proname ilike '%notification%'
  )
order by p.proname;
