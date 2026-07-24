-- Read-only. Checks for any Ice Cold Logistics duplicate/leftover data
-- BEYOND the 6 tenant rows already deleted via
-- sql/tenant-cleanup-delete.sql (prefixes 4e763fed, 4e836f5e, db2d9efd,
-- 84e60682, 1c953682, c65f45ce - all named "Ice cold Worldwide Logistics
-- Limited", confirmed via sql/tenant-cleanup-verify.sql's query 1a).
--
-- Three angles, since "beyond the 12 already cleaned up" could mean
-- either a 7th+ duplicate that was missed, or orphaned rows left behind
-- from an incomplete cleanup of the 6 that WERE deleted:
--   1. Broad name search across tenants - catches any Ice Cold variant
--      that doesn't match the original 6 IDs at all (different
--      spelling/spacing, or created after the cleanup ran).
--   2. Orphaned rows across every tenant-scoped table - rows whose
--      tenant_id has no matching tenants row at all. Not Ice-Cold-
--      specific, but this is exactly what "leftover after an incomplete
--      cleanup" looks like, and it's a useful general health check
--      regardless of cause.
--   3. registrations (pre-approval signups, not tenant_id-scoped) for
--      any lingering Ice Cold entries never resolved into a tenant.
--
-- Known blind spots, same as sql/tenant-cleanup-verify.sql flagged
-- originally: "recurring money reminders" (accessed only via RPC, real
-- table name never appears in any client-side code) and login_attempts
-- (same - RPC-only, table name unconfirmed) can't be checked from here.

-- 1. Broad name search - permissive pattern to catch spacing/hyphenation
--    variants, not just the exact original name.
select id, business_name, company_name, email, status, created_at
from tenants
where business_name ilike '%ice%cold%'
   or company_name ilike '%ice%cold%'
   or email ilike '%ice%cold%'
order by created_at desc;

-- 2. Orphaned rows - any tenant-scoped table with a tenant_id that
--    doesn't exist in tenants at all. Same 21-table list as
--    tenant-cleanup-verify.sql's query 2, so results are directly
--    comparable to that prior check.
with orphans as (
  select 'transactions' as table_name, tenant_id, count(*) from transactions where tenant_id not in (select id from tenants) group by tenant_id
  union all select 'tasks', tenant_id, count(*) from tasks where tenant_id not in (select id from tenants) group by tenant_id
  union all select 'documents', tenant_id, count(*) from documents where tenant_id not in (select id from tenants) group by tenant_id
  union all select 'client_people', tenant_id, count(*) from client_people where tenant_id not in (select id from tenants) group by tenant_id
  union all select 'business_records', tenant_id, count(*) from business_records where tenant_id not in (select id from tenants) group by tenant_id
  union all select 'business_items', tenant_id, count(*) from business_items where tenant_id not in (select id from tenants) group by tenant_id
  union all select 'business_events', tenant_id, count(*) from business_events where tenant_id not in (select id from tenants) group by tenant_id
  union all select 'admin_client_messages', tenant_id, count(*) from admin_client_messages where tenant_id not in (select id from tenants) group by tenant_id
  union all select 'client_notices', tenant_id, count(*) from client_notices where tenant_id not in (select id from tenants) group by tenant_id
  union all select 'support_issues', tenant_id, count(*) from support_issues where tenant_id not in (select id from tenants) group by tenant_id
  union all select 'system_notices', tenant_id, count(*) from system_notices where tenant_id not in (select id from tenants) group by tenant_id
  union all select 'team_chat_messages', tenant_id, count(*) from team_chat_messages where tenant_id not in (select id from tenants) group by tenant_id
  union all select 'tenant_sections', tenant_id, count(*) from tenant_sections where tenant_id not in (select id from tenants) group by tenant_id
  union all select 'ungani_audit_log', tenant_id, count(*) from ungani_audit_log where tenant_id not in (select id from tenants) group by tenant_id
  union all select 'ungani_notifications', tenant_id, count(*) from ungani_notifications where tenant_id not in (select id from tenants) group by tenant_id
  union all select 'ungani_upgrade_requests', tenant_id, count(*) from ungani_upgrade_requests where tenant_id not in (select id from tenants) group by tenant_id
  union all select 'upgrade_requests', tenant_id, count(*) from upgrade_requests where tenant_id not in (select id from tenants) group by tenant_id
  union all select 'payments', tenant_id, count(*) from payments where tenant_id not in (select id from tenants) group by tenant_id
  union all select 'client_settings', tenant_id, count(*) from client_settings where tenant_id not in (select id from tenants) group by tenant_id
  union all select 'ungani_billing_reminder_logs', tenant_id, count(*) from ungani_billing_reminder_logs where tenant_id not in (select id from tenants) group by tenant_id
  union all select 'users', tenant_id, count(*) from users where tenant_id not in (select id from tenants) group by tenant_id
  union all select 'tenant_integrations', tenant_id, count(*) from tenant_integrations where tenant_id not in (select id from tenants) group by tenant_id
)
select * from orphans order by table_name;

-- 3. Lingering pre-approval registrations matching Ice Cold, regardless
--    of whether they ever became a tenant.
select id, business_name, email, status, created_at
from registrations
where business_name ilike '%ice%cold%' or email ilike '%ice%cold%'
order by created_at desc;
