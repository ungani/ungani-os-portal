-- Pre-launch data diagnostic (READ-ONLY - no INSERT/UPDATE/DELETE anywhere
-- in this file). Run each section in the Supabase SQL editor and review
-- the results yourself; nothing here modifies data. Written because this
-- repo has no live database access (no service-role key, no Supabase CLI
-- configured) - static code review alone can't tell you what data
-- actually exists, only what the app's queries expect to find.

-- 1. Every tenant, newest first - eyeball this for anything that looks
--    like test/demo data (names like "Test", "Demo", "Acme", obviously
--    placeholder emails, etc.) rather than a real business.
select id, business_name, company_name, business_type, email, status, created_at
from tenants
order by created_at desc;

-- 2. Every admin/staff user account, newest first - same idea: check for
--    leftover test logins that shouldn't be able to sign in once a real
--    client is live.
select id, full_name, email, role, status, tenant_id, created_at
from users
order by created_at desc;

-- 3. Possible duplicate transactions - same tenant, amount, date, and
--    category appearing more than once. The app already guards against
--    this going forward (check_my_ungani_duplicate_transaction warns on
--    save, doesn't hard-block), so this only surfaces pre-existing/seed
--    data, not anything the app would let happen silently today.
select tenant_id, amount, transaction_date, category, count(*) as duplicate_count,
       array_agg(id) as transaction_ids
from transactions
group by tenant_id, amount, transaction_date, category
having count(*) > 1
order by duplicate_count desc;

-- 4. Documents whose linked_item_id points at an item that no longer
--    exists (e.g. the item was hard-deleted some other way, or the link
--    was set before the item was created and never resolved). Should
--    normally be empty - the app never hard-deletes items (soft-delete
--    via soft_delete_ungani_record), so any rows here are worth a look.
select d.id as document_id, d.document_title, d.linked_item_id, d.tenant_id
from documents d
left join business_items bi on bi.id = d.linked_item_id
where d.linked_item_id is not null and bi.id is null;

-- 5. Same check for client_people.linked_item_id (Real Estate/Hospitality
--    tenant-to-unit links).
select cp.id as person_id, cp.full_name, cp.linked_item_id, cp.tenant_id
from client_people cp
left join business_items bi on bi.id = cp.linked_item_id
where cp.linked_item_id is not null and bi.id is null;

-- 6. Row counts per core table, per tenant - quick sanity check for a
--    tenant with an unexpectedly huge row count (could indicate a loop/
--    bug that kept inserting, or genuinely just a long-lived test
--    account with a lot of accumulated data worth clearing before a
--    real client is confused by leftover records on a shared view, if
--    any tenant scoping were ever found to be imperfect).
select t.business_name, t.id as tenant_id,
  (select count(*) from transactions where tenant_id = t.id) as transactions,
  (select count(*) from tasks where tenant_id = t.id) as tasks,
  (select count(*) from documents where tenant_id = t.id) as documents,
  (select count(*) from client_people where tenant_id = t.id) as people,
  (select count(*) from business_records where tenant_id = t.id) as records,
  (select count(*) from business_items where tenant_id = t.id) as items
from tenants t
order by transactions + tasks + documents + people + records + items desc;
