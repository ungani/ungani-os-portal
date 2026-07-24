-- One-time cleanup of stale ungani_email_queue rows, before the cron/
-- manual-send fix (CRON_SECRET) lets any of the 40 backlogged rows go
-- out for the first time. Marks rows `send_status = 'cancelled'` rather
-- than deleting them - keeps history visible in admin-email-queue.html,
-- and PENDING_STATUSES in api/send-email-queue.js only ever looks for
-- ('pending','queued','retry'), so 'cancelled' rows are permanently
-- skipped by both the cron and "Send Pending Now" without any code
-- change needed. Reversible: flip send_status back to 'pending' for any
-- row you disagree with after reviewing.
--
-- Deliberately does NOT use a blanket "older than N days" rule across
-- every row - different email_type/situation makes different rows
-- stale for different reasons, and a blanket age cutoff would either
-- miss real problems or falsely flag rows that are still accurate.
-- Four specific, narrow criteria instead:
--
--   1. Orphaned tenant - tenant_id no longer exists in tenants at all
--      (deleted since the row was queued). Nothing left to say -
--      correct regardless of email_type.
--   2. Known test/demo recipient - explicit list of every test/demo
--      email address identified across this session (Auth cleanup,
--      duplicate-tenant cleanup, Ice Cold Logistics investigation, RLS
--      verification), plus broader ILIKE patterns as a safety net for
--      anything not explicitly listed. These should never have reached
--      a real send in the first place.
--   3. trial_warning rows older than 5 days (WARNING_DEDUP_DAYS in
--      api/check-trial-warnings.js) - the email_body has a specific
--      "ends in X days" count BAKED IN AT INSERT TIME, not computed at
--      send time. Past the warning window, that number is guaranteed
--      wrong regardless of the tenant's current status.
--   4. trial_ended rows where the tenant's CURRENT subscription_status
--      is no longer 'trial' - they've since been upgraded/reactivated/
--      cancelled by an admin, so "your trial has ended" is now
--      factually wrong or just an odd thing to send someone who's
--      already paid. Deliberately NOT age-gating trial_ended rows in
--      general - unlike trial_warning, its message has no baked-in
--      number, so an old-but-still-accurate "your trial ended, choose a
--      plan" is still useful to a client who's been sitting unaware in
--      read-only mode this whole time (arguably more useful, given how
--      late it already is).
--
-- Anything NOT matching one of these 4 reasons is left untouched on
-- purpose, even if old - flagged for your manual review in the preview
-- below rather than guessed at.
--
-- SEPARATE finding, worth checking before you rely on the CRON_SECRET
-- fix alone: api/send-email-queue.js's updateQueueRecord() writes an
-- `updated_at` column on every status transition (pending -> sending ->
-- sent/failed) - but that code path has NEVER actually executed against
-- production (every invocation has died at the 401 auth check before
-- reaching it), so updated_at's existence on this table was never
-- verified. It does not appear anywhere in admin-email-queue.html's
-- confirmed-real column list. This cleanup script deliberately does NOT
-- write updated_at, to avoid the same risk - but once CRON_SECRET is
-- fixed and the sender finally reaches a real send attempt, if this
-- column doesn't exist, every send will fail with a column-does-not-
-- exist error on the FIRST status update (moving to "sending"), which
-- would look like a new bug but is really this same pre-existing one
-- surfacing for the first time. Quick check, run any time:
--
--   select column_name from information_schema.columns
--   where table_schema = 'public' and table_name = 'ungani_email_queue'
--   order by ordinal_position;
--
-- If updated_at isn't in the result, tell me and I'll fix
-- api/send-email-queue.js before you re-test sending.

-- STEP 1 (read-only) - preview exactly which rows would be cancelled
-- and why, plus every row that does NOT match any reason (for manual
-- review) before running anything.
with reasons as (
  select
    q.id,
    q.recipient_email,
    q.email_type,
    q.send_status,
    q.created_at,
    case
      when q.tenant_id is not null and t.id is null then 'orphaned_tenant'
      when lower(q.recipient_email) in (
        'testclient1@ungani.com', 'restaurantdemo@ungani.com', 'test@ungani.com',
        'unganisystem@gmail.com', 'billychris617@gmail.com', 'superchris643@gmail.com',
        'ungani123@gmail.com', 'testhotel@gmail.com', 'rls-verify-test@example.com'
      ) or lower(q.recipient_email) like 'test%@ungani.com'
        or lower(q.recipient_email) like '%demo%@ungani.com'
        or lower(q.recipient_email) like 'diag-%@example.com'
        or lower(q.recipient_email) like 'e2e-sections-test%' then 'known_test_account'
      when q.email_type = 'trial_warning' and q.created_at < now() - interval '5 days' then 'stale_trial_warning'
      when q.email_type = 'trial_ended' and s.subscription_status is distinct from 'trial' then 'trial_no_longer_active'
      else null
    end as cancel_reason
  from ungani_email_queue q
  left join tenants t on t.id = q.tenant_id
  left join ungani_subscriptions s on s.tenant_id = q.tenant_id
  where q.send_status in ('pending', 'queued', 'retry')
)
select id, recipient_email, email_type, send_status as current_status, created_at,
       coalesce(cancel_reason, 'NO MATCH - leave as pending, review manually') as cancel_reason
from reasons
order by (cancel_reason is null), email_type, created_at;

-- STEP 2 - run only after reviewing Step 1's output and confirming the
-- flagged rows look right. Marks matching rows cancelled; everything
-- else (including any "NO MATCH" rows) is left as pending, untouched.

begin;

with target_rows as (
  select q.id
  from ungani_email_queue q
  left join tenants t on t.id = q.tenant_id
  left join ungani_subscriptions s on s.tenant_id = q.tenant_id
  where q.send_status in ('pending', 'queued', 'retry')
    and (
      (q.tenant_id is not null and t.id is null)
      or lower(q.recipient_email) in (
        'testclient1@ungani.com', 'restaurantdemo@ungani.com', 'test@ungani.com',
        'unganisystem@gmail.com', 'billychris617@gmail.com', 'superchris643@gmail.com',
        'ungani123@gmail.com', 'testhotel@gmail.com', 'rls-verify-test@example.com'
      )
      or lower(q.recipient_email) like 'test%@ungani.com'
      or lower(q.recipient_email) like '%demo%@ungani.com'
      or lower(q.recipient_email) like 'diag-%@example.com'
      or lower(q.recipient_email) like 'e2e-sections-test%'
      or (q.email_type = 'trial_warning' and q.created_at < now() - interval '5 days')
      or (q.email_type = 'trial_ended' and s.subscription_status is distinct from 'trial')
    )
)
update ungani_email_queue
set send_status = 'cancelled',
    last_error = 'Cancelled in one-time pre-launch cleanup (' || to_char(now(), 'YYYY-MM-DD') || ') - stale/orphaned before the cron auth fix, never actually sent.'
where id in (select id from target_rows)
returning id, recipient_email, email_type, send_status;

commit;
