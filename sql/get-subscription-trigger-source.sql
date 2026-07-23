-- Read-only. Pulls the real source of both trigger functions on
-- ungani_subscriptions, now that trg_sync_ungani_subscription_from_package
-- (BEFORE INSERT OR UPDATE OF package_key) is confirmed the likely
-- culprit for "ON CONFLICT DO UPDATE command cannot affect row a second
-- time" - a BEFORE trigger that itself writes to the same row/table
-- within the same command is the classic cause of this exact error.
-- Pulling trg_sync_tenant_from_ungani_subscription's source too since it
-- fires on the same table and is worth seeing in the same pass.

select p.proname, pg_get_functiondef(p.oid) as source
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'sync_tenant_from_ungani_subscription',
    'sync_ungani_subscription_from_package'
  )
order by p.proname;
