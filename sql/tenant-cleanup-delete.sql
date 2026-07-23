-- Tenant cleanup - STEP 2: DELETE (irreversible). Only run this after
-- reviewing sql/tenant-cleanup-verify.sql's output and confirming all 12
-- tenants are safe to remove.
--
-- Wrapped in a single transaction - if anything fails partway through
-- (an unexpected FK constraint, a table that no longer exists, etc.),
-- Postgres rolls back everything above the failure point too. Nothing
-- commits unless every statement succeeds.
--
-- Order: tables that reference OTHER same-tenant tables are deleted
-- first (documents/client_people reference business_items via
-- linked_item_id; ungani_billing_reminder_logs references payments via
-- payment_id; audit/chat tables reference users), then the tables they
-- point to, then user_preferences, then users, then the tenants row
-- itself last. Confirmed via sql/documents-linked-item-id.sql that the
-- documents->business_items link is ON DELETE SET NULL (so that one
-- specific pairing wouldn't actually fail either order), but the rest
-- weren't independently confirmed the same way, so this order is kept
-- conservative throughout rather than assuming.

begin;

-- Resolves the 12 confirmed tenant IDs once - single source of truth for
-- every delete below, instead of repeating (and risking a typo in) the
-- same 12 LIKE clauses in 24 different places.
create temporary table _cleanup_targets on commit drop as
select id, email
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
   or id::text like '9e955992%'; -- UNGANI Demo Logistics

-- Hard safety check - aborts (rolling back everything in this
-- transaction) if this doesn't resolve to exactly 12 tenants, e.g.
-- because the underlying data changed since you last verified.
do $$
begin
  if (select count(*) from _cleanup_targets) <> 12 then
    raise exception 'Expected exactly 12 tenants to match, found %. Aborting - re-run the verification query.', (select count(*) from _cleanup_targets);
  end if;
end $$;

-- Tables that reference other same-tenant tables - deleted first.
delete from documents where tenant_id in (select id from _cleanup_targets);
delete from client_people where tenant_id in (select id from _cleanup_targets);
delete from ungani_billing_reminder_logs where tenant_id in (select id from _cleanup_targets);
delete from ungani_audit_log where tenant_id in (select id from _cleanup_targets);
delete from admin_client_messages where tenant_id in (select id from _cleanup_targets);
delete from team_chat_messages where tenant_id in (select id from _cleanup_targets);

-- Remaining tenant_id-scoped tables with no known cross-references.
delete from transactions where tenant_id in (select id from _cleanup_targets);
delete from tasks where tenant_id in (select id from _cleanup_targets);
delete from business_records where tenant_id in (select id from _cleanup_targets);
delete from business_events where tenant_id in (select id from _cleanup_targets);
delete from client_notices where tenant_id in (select id from _cleanup_targets);
delete from support_issues where tenant_id in (select id from _cleanup_targets);
delete from system_notices where tenant_id in (select id from _cleanup_targets);
delete from tenant_sections where tenant_id in (select id from _cleanup_targets);
delete from ungani_notifications where tenant_id in (select id from _cleanup_targets);
delete from ungani_upgrade_requests where tenant_id in (select id from _cleanup_targets);
delete from upgrade_requests where tenant_id in (select id from _cleanup_targets);
delete from client_settings where tenant_id in (select id from _cleanup_targets);
delete from payments where tenant_id in (select id from _cleanup_targets);

-- The table documents/client_people referenced above - deleted after them.
delete from business_items where tenant_id in (select id from _cleanup_targets);

-- user_preferences - scoped by user_id, not tenant_id directly. Must run
-- before deleting users (user_preferences.user_id references users.id).
delete from user_preferences
where user_id in (select id from users where tenant_id in (select id from _cleanup_targets));

-- users - after user_preferences, before tenants.
delete from users where tenant_id in (select id from _cleanup_targets);

-- registrations - not tenant_id-scoped (pre-tenant signup requests),
-- matched by the email captured in _cleanup_targets above.
delete from registrations where email in (select email from _cleanup_targets where email is not null);

-- tenants - LAST. Every table that could reference it has already been
-- cleared above.
delete from tenants where id in (select id from _cleanup_targets);

-- Final safety check before commit - confirms nothing survived.
do $$
begin
  if exists (select 1 from tenants where id in (select id from _cleanup_targets)) then
    raise exception 'Tenant rows still exist after delete - aborting commit.';
  end if;
end $$;

commit;
