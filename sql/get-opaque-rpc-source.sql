-- Read-only. Pulls the actual source of every RPC this session has had to
-- treat as opaque (no .sql file in the repo, behavior inferred from app
-- code and response shapes only). Run as the DB owner/service role in the
-- Supabase SQL editor - pg_get_functiondef works regardless of any
-- session/RLS context, unlike calling the functions themselves.
--
-- Immediate priority: is_ungani_admin (both RLS policies on
-- ungani_subscriptions gate on this - if it's evaluating false for the
-- admin's session, that explains both the 403 on direct SELECT and,
-- if admin_update_ungani_subscription has its own internal admin check
-- that raises an exception rather than returning a clean error, the 500
-- on the RPC call too) and admin_update_ungani_subscription itself.

select p.proname, pg_get_functiondef(p.oid) as source
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'is_ungani_admin',
    'admin_update_ungani_subscription',
    'get_my_ungani_subscription_access',
    'get_my_ungani_read_only_notice',
    'get_my_ungani_access_status',
    'admin_accept_ungani_payment_proof_and_mark_paid',
    'admin_update_ungani_payment_proof',
    'mark_admin_ungani_billing_record_paid',
    'client_submit_ungani_upgrade_request',
    'get_my_ungani_tenant_id'
  )
order by p.proname;
