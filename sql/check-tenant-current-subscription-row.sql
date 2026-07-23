-- Read-only. Direct ground truth on this tenant's actual current row,
-- post-trigger-fix, post-clicking-Active. Per the confirmed logic of
-- get_my_ungani_subscription_access(), "Trial period has ended" can ONLY
-- be reached when subscription_status = 'trial' - if this row shows
-- 'active', the RPC write genuinely worked and the banner is stale
-- (reload/re-check needed, not a real bug). If it still shows 'trial'
-- (or anything else), the Active click didn't actually take effect this
-- time and needs its own trace (check console for a repeat of the RPC
-- error pattern from before).

select
  tenant_id,
  package_key,
  subscription_status,
  payment_status,
  trial_start_at,
  trial_end_at,
  updated_at
from public.ungani_subscriptions
where tenant_id = 'a29af055-e4f0-48cf-af97-f99081a9106b';
