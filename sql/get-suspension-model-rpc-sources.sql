-- Read-only. Pulls the real, current source of the 3 RPCs that together
-- drive both the hard-lockout screen (client-access-guard.js) and the
-- softer read-only banner (client-shared.js's loadReadOnlyAccess()) -
-- needed before writing the actual suspension-model change, per this
-- project's standing rule to never guess/reconstruct SQL from memory.
--
-- get_my_ungani_access_status: feeds access_status/status in
--   client-access-guard.js - 'suspended' (among others) currently
--   triggers a full-page "Workspace Access Restricted" block.
-- get_my_ungani_subscription_access: sets can_write, checked first by
--   the read-only banner.
-- get_my_ungani_read_only_notice: checked second, can independently
--   force isReadOnly = true and override the banner message.

select p.proname, pg_get_functiondef(p.oid) as source
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'get_my_ungani_access_status',
    'get_my_ungani_subscription_access',
    'get_my_ungani_read_only_notice'
  )
order by p.proname;
