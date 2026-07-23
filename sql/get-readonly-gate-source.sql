-- Read-only. Pulls the actual source of the two RPCs that drive the
-- client-side read-only banner (client-shared.js's loadReadOnlyAccess()):
-- get_my_ungani_subscription_access (checked first, sets can_write) and
-- get_my_ungani_read_only_notice (checked second, can independently force
-- isReadOnly = true and override the banner message even if the first
-- RPC said access was fine). Needed to answer: does clicking "Active" on
-- admin-profiles.html (which sets ungani_subscriptions.subscription_status
-- = 'active') fully clear read-only mode, or does one of these also gate
-- on trial_end_at independently, regardless of subscription_status?

select p.proname, pg_get_functiondef(p.oid) as source
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'get_my_ungani_subscription_access',
    'get_my_ungani_read_only_notice'
  )
order by p.proname;
