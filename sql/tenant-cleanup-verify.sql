-- Tenant cleanup - STEP 1: VERIFICATION (read-only, no deletes anywhere in
-- this file). Run this FIRST and review every result before touching
-- sql/tenant-cleanup-delete.sql.
--
-- Covers every tenant-scoped table found by grepping every .from() call in
-- the whole repo (21 tables with a direct tenant_id column, plus
-- user_preferences which is scoped indirectly via users.tenant_id) - a
-- wider check than sql/pre-launch-data-diagnostic.sql's 6-table version,
-- since this one needs to be exhaustive before an irreversible delete.
--
-- Known gap: the app also has a "recurring money reminders" feature
-- (my-money.html), but it's read/written entirely through RPCs
-- (get_my_ungani_recurring_transactions / create_my_ungani_recurring_
-- transaction) - the underlying table name is never referenced directly
-- in any client-side code, so it can't be identified or checked from this
-- repo. If any of these 12 tenants set up a recurring reminder, it won't
-- show up below and won't be touched by the delete script. Check for this
-- directly in the Supabase dashboard's table list if you want to be sure,
-- or ask before deleting if any of these tenants look like they used the
-- Money page's "Recurring Money" panel.

-- 1a. Resolve the 12 given ID prefixes to full tenant rows. This MUST
--     return exactly 12 rows, one per prefix. If it returns more or
--     fewer, STOP - a prefix is either ambiguous (matches >1 tenant) or
--     doesn't exist, and you need to resolve that before going further.
select id, business_name, company_name, business_type, email, status, created_at
from tenants
where id::text like 'e63bcaf1%'  -- Test Hotel & Bar & Restaurant
   or id::text like '431f986d%'  -- E2E Sections Test Hotel
   or id::text like '8803e0ec%'  -- Dyar Properties (old cancelled duplicate)
   or id::text like '4e763fed%'  -- Ice cold Worldwide Logistics Limited (1/6)
   or id::text like '4e836f5e%'  -- Ice cold Worldwide Logistics Limited (2/6)
   or id::text like 'db2d9efd%'  -- Ice cold Worldwide Logistics Limited (3/6)
   or id::text like '84e60682%'  -- Ice cold Worldwide Logistics Limited (4/6)
   or id::text like '1c953682%'  -- Ice cold Worldwide Logistics Limited (5/6)
   or id::text like 'c65f45ce%'  -- Ice cold Worldwide Logistics Limited (6/6)
   or id::text like 'c01549db%'  -- Test Client One
   or id::text like '2365c692%'  -- Demo Vegan Restaurant
   or id::text like '9e955992%'  -- UNGANI Demo Logistics
order by created_at desc;

-- 1b. Sanity check on 1a - must return exactly (12, 12). If match_count
--     differs from prefix_count, at least one prefix matched 0 or 2+ rows.
with prefixes(p) as (
  values ('e63bcaf1'),('431f986d'),('8803e0ec'),('4e763fed'),('4e836f5e'),
         ('db2d9efd'),('84e60682'),('1c953682'),('c65f45ce'),('c01549db'),
         ('2365c692'),('9e955992')
)
select
  (select count(*) from prefixes) as prefix_count,
  (select count(*) from tenants t, prefixes where t.id::text like prefixes.p || '%') as match_count;

-- 2. Row counts per table, per tenant, for exactly these 12 tenants -
--    review every one before deciding anything is "safe to delete".
--    tenant_name is included on every row so you don't have to
--    cross-reference IDs back to query 1a while scanning this.
with target_ids as (
  select array_agg(id) as ids from tenants
  where id::text like 'e63bcaf1%' or id::text like '431f986d%' or id::text like '8803e0ec%'
     or id::text like '4e763fed%' or id::text like '4e836f5e%' or id::text like 'db2d9efd%'
     or id::text like '84e60682%' or id::text like '1c953682%' or id::text like 'c65f45ce%'
     or id::text like 'c01549db%' or id::text like '2365c692%' or id::text like '9e955992%'
),
counts as (
  select 'transactions' as table_name, tenant_id, count(*) from transactions, target_ids where tenant_id = any(target_ids.ids) group by tenant_id
  union all select 'tasks', tenant_id, count(*) from tasks, target_ids where tenant_id = any(target_ids.ids) group by tenant_id
  union all select 'documents', tenant_id, count(*) from documents, target_ids where tenant_id = any(target_ids.ids) group by tenant_id
  union all select 'client_people', tenant_id, count(*) from client_people, target_ids where tenant_id = any(target_ids.ids) group by tenant_id
  union all select 'business_records', tenant_id, count(*) from business_records, target_ids where tenant_id = any(target_ids.ids) group by tenant_id
  union all select 'business_items', tenant_id, count(*) from business_items, target_ids where tenant_id = any(target_ids.ids) group by tenant_id
  union all select 'business_events', tenant_id, count(*) from business_events, target_ids where tenant_id = any(target_ids.ids) group by tenant_id
  union all select 'admin_client_messages', tenant_id, count(*) from admin_client_messages, target_ids where tenant_id = any(target_ids.ids) group by tenant_id
  union all select 'client_notices', tenant_id, count(*) from client_notices, target_ids where tenant_id = any(target_ids.ids) group by tenant_id
  union all select 'support_issues', tenant_id, count(*) from support_issues, target_ids where tenant_id = any(target_ids.ids) group by tenant_id
  union all select 'system_notices', tenant_id, count(*) from system_notices, target_ids where tenant_id = any(target_ids.ids) group by tenant_id
  union all select 'team_chat_messages', tenant_id, count(*) from team_chat_messages, target_ids where tenant_id = any(target_ids.ids) group by tenant_id
  union all select 'tenant_sections', tenant_id, count(*) from tenant_sections, target_ids where tenant_id = any(target_ids.ids) group by tenant_id
  union all select 'ungani_audit_log', tenant_id, count(*) from ungani_audit_log, target_ids where tenant_id = any(target_ids.ids) group by tenant_id
  union all select 'ungani_notifications', tenant_id, count(*) from ungani_notifications, target_ids where tenant_id = any(target_ids.ids) group by tenant_id
  union all select 'ungani_upgrade_requests', tenant_id, count(*) from ungani_upgrade_requests, target_ids where tenant_id = any(target_ids.ids) group by tenant_id
  union all select 'upgrade_requests', tenant_id, count(*) from upgrade_requests, target_ids where tenant_id = any(target_ids.ids) group by tenant_id
  union all select 'payments', tenant_id, count(*) from payments, target_ids where tenant_id = any(target_ids.ids) group by tenant_id
  union all select 'client_settings', tenant_id, count(*) from client_settings, target_ids where tenant_id = any(target_ids.ids) group by tenant_id
  union all select 'ungani_billing_reminder_logs', tenant_id, count(*) from ungani_billing_reminder_logs, target_ids where tenant_id = any(target_ids.ids) group by tenant_id
  union all select 'users', tenant_id, count(*) from users, target_ids where tenant_id = any(target_ids.ids) group by tenant_id
  union all
  select 'user_preferences (via users)', u.tenant_id, count(*)
  from user_preferences up
  join users u on u.id = up.user_id
  , target_ids
  where u.tenant_id = any(target_ids.ids)
  group by u.tenant_id
)
select c.table_name, t.business_name, c.tenant_id, c.count
from counts c
join tenants t on t.id = c.tenant_id
order by t.business_name, c.count desc;

-- 3. Optional, lower-stakes context (not tenant_id-scoped, matched by
--    email instead - review separately, not part of the main safety
--    check above). registrations are pre-approval signup requests -
--    confirmed real via a direct .from("registrations") call in the app.
--    Not "business data" in the sense you're checking for, just
--    housekeeping that would be left dangling after a tenant delete.
with target_emails as (
  select array_agg(distinct email) as emails from tenants
  where id::text like 'e63bcaf1%' or id::text like '431f986d%' or id::text like '8803e0ec%'
     or id::text like '4e763fed%' or id::text like '4e836f5e%' or id::text like 'db2d9efd%'
     or id::text like '84e60682%' or id::text like '1c953682%' or id::text like 'c65f45ce%'
     or id::text like 'c01549db%' or id::text like '2365c692%' or id::text like '9e955992%'
)
select 'registrations' as table_name, count(*) from registrations, target_emails where email = any(target_emails.emails);

-- 3b. login_attempts (lockout tracking) - NOT run above. The app only
--     ever accesses this through RPCs (check_login_lockout/
--     record_failed_login/record_successful_login), never a direct
--     .from("login_attempts") call anywhere in the code - the table name
--     is only mentioned once, in a stale code comment, so I can't confirm
--     it's actually correct. If you want this checked/cleaned up too,
--     confirm the real table name in the Supabase dashboard's table list
--     first (it's low-stakes either way - just failed-login counters,
--     not business data).
