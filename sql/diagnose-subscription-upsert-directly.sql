-- Diagnostic only - wrapped in a transaction that rolls back, so nothing
-- is actually changed by running this. Replicates
-- admin_update_ungani_subscription's core INSERT ... ON CONFLICT exactly,
-- using the real values from the live console log, but run directly as
-- the SQL editor's own role - bypassing is_ungani_admin() and the
-- package-active check entirely (both already confirmed to pass), which
-- lets us see whatever raw Postgres error the data layer itself produces.
--
-- Also lists any triggers on ungani_subscriptions - a trigger could fail
-- invisibly from just reading admin_update_ungani_subscription's own body.

begin;

insert into public.ungani_subscriptions (
  tenant_id,
  package_key,
  subscription_status,
  payment_status,
  trial_end_at,
  notes
)
values (
  'a29af055-e4f0-48cf-af97-f99081a9106b'::uuid,
  'starter',
  coalesce('suspended', 'trial'),
  coalesce('paid', 'trial'),
  coalesce('2026-07-15T20:04:38.214704+00:00'::timestamptz, now() + interval '14 days'),
  null
)
on conflict (tenant_id)
do update set
  package_key = excluded.package_key,
  subscription_status = coalesce('suspended', public.ungani_subscriptions.subscription_status),
  payment_status = coalesce('paid', public.ungani_subscriptions.payment_status),
  trial_end_at = coalesce('2026-07-15T20:04:38.214704+00:00'::timestamptz, public.ungani_subscriptions.trial_end_at),
  notes = coalesce(null, public.ungani_subscriptions.notes),
  updated_at = now()
returning *;

rollback;

-- Separately (not part of the transaction above): any triggers on this
-- table, and the function each one runs.
select
  t.tgname as trigger_name,
  t.tgtype,
  p.proname as function_name,
  pg_get_triggerdef(t.oid) as definition
from pg_trigger t
join pg_proc p on p.oid = t.tgfoid
where t.tgrelid = 'public.ungani_subscriptions'::regclass
  and not t.tgisinternal;
