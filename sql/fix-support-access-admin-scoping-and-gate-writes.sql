-- Two real, distinct findings fixed together, both surfaced by live
-- testing against Billy Logistics:
--
-- FINDING 1 (more serious): none of the 21 original support-access
-- policies in sql/ungani-support-access.sql check is_ungani_admin().
-- Each one only checks "does THIS TENANT currently have an active,
-- unexpired, full_access grant" - with no restriction on WHO is asking.
-- During an active grant window, this let ANY authenticated user on the
-- whole platform (not just the intended UNGANI admin) read/write that
-- tenant's data, as long as they knew the tenant_id. PART A below adds
-- `and is_ungani_admin()` to all 21 policies, closing this.
--
-- FINDING 2: all 6 operational tables already had PRE-EXISTING,
-- unconditional admin policies (e.g. "ungani_admin_manage_transactions",
-- cmd=ALL, qual=is_ungani_admin(), no tenant/grant condition), backing
-- 5 actively-linked admin CRUD pages (admin-items/tasks/records/
-- documents/people.html) that predate this feature entirely. Decision
-- made: gate WRITES (insert/update/delete) behind an active grant,
-- leave READS unconditional (admins keep the visibility those 5 pages
-- and admin-home's dashboards need). PART B drops the old unconditional
-- write-granting policies so the (now-hardened) 21 grant-based policies
-- become the only path for admin writes. All "admin_can_read_*" SELECT
-- policies are left completely untouched.
--
-- No new DELETE capability is added anywhere - dropping the old ALL
-- policies removes admin's only delete path on business_items,
-- business_records, documents, tasks, transactions (client_people never
-- had one). This matches the app's existing soft-delete convention
-- (recycle bin / status flip, never hard delete) - preserved exactly,
-- not loosened.
--
-- Run this whole file in one go. Safe to re-run (every statement is
-- drop-if-exists then create).

-- =====================================================================
-- PART A: harden all 21 original support-access policies to require
-- is_ungani_admin(), not just "a grant exists for this tenant."
-- =====================================================================

-- business_items --------------------------------------------------------

drop policy if exists "UNGANI support access can read (business_items)" on public.business_items;
create policy "UNGANI support access can read (business_items)"
  on public.business_items
  for select
  to authenticated
  using (
    is_ungani_admin()
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = business_items.tenant_id
        and g.status = 'active'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can update (business_items)" on public.business_items;
create policy "UNGANI support access can update (business_items)"
  on public.business_items
  for update
  to authenticated
  using (
    is_ungani_admin()
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = business_items.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  )
  with check (
    is_ungani_admin()
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = business_items.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can insert (business_items)" on public.business_items;
create policy "UNGANI support access can insert (business_items)"
  on public.business_items
  for insert
  to authenticated
  with check (
    is_ungani_admin()
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = business_items.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

-- transactions ----------------------------------------------------------

drop policy if exists "UNGANI support access can read (transactions)" on public.transactions;
create policy "UNGANI support access can read (transactions)"
  on public.transactions
  for select
  to authenticated
  using (
    is_ungani_admin()
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = transactions.tenant_id
        and g.status = 'active'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can update (transactions)" on public.transactions;
create policy "UNGANI support access can update (transactions)"
  on public.transactions
  for update
  to authenticated
  using (
    is_ungani_admin()
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = transactions.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  )
  with check (
    is_ungani_admin()
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = transactions.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can insert (transactions)" on public.transactions;
create policy "UNGANI support access can insert (transactions)"
  on public.transactions
  for insert
  to authenticated
  with check (
    is_ungani_admin()
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = transactions.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

-- tasks -------------------------------------------------------------

drop policy if exists "UNGANI support access can read (tasks)" on public.tasks;
create policy "UNGANI support access can read (tasks)"
  on public.tasks
  for select
  to authenticated
  using (
    is_ungani_admin()
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = tasks.tenant_id
        and g.status = 'active'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can update (tasks)" on public.tasks;
create policy "UNGANI support access can update (tasks)"
  on public.tasks
  for update
  to authenticated
  using (
    is_ungani_admin()
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = tasks.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  )
  with check (
    is_ungani_admin()
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = tasks.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can insert (tasks)" on public.tasks;
create policy "UNGANI support access can insert (tasks)"
  on public.tasks
  for insert
  to authenticated
  with check (
    is_ungani_admin()
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = tasks.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

-- business_records -------------------------------------------------------

drop policy if exists "UNGANI support access can read (business_records)" on public.business_records;
create policy "UNGANI support access can read (business_records)"
  on public.business_records
  for select
  to authenticated
  using (
    is_ungani_admin()
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = business_records.tenant_id
        and g.status = 'active'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can update (business_records)" on public.business_records;
create policy "UNGANI support access can update (business_records)"
  on public.business_records
  for update
  to authenticated
  using (
    is_ungani_admin()
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = business_records.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  )
  with check (
    is_ungani_admin()
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = business_records.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can insert (business_records)" on public.business_records;
create policy "UNGANI support access can insert (business_records)"
  on public.business_records
  for insert
  to authenticated
  with check (
    is_ungani_admin()
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = business_records.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

-- documents ------------------------------------------------------------

drop policy if exists "UNGANI support access can read (documents)" on public.documents;
create policy "UNGANI support access can read (documents)"
  on public.documents
  for select
  to authenticated
  using (
    is_ungani_admin()
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = documents.tenant_id
        and g.status = 'active'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can update (documents)" on public.documents;
create policy "UNGANI support access can update (documents)"
  on public.documents
  for update
  to authenticated
  using (
    is_ungani_admin()
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = documents.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  )
  with check (
    is_ungani_admin()
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = documents.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can insert (documents)" on public.documents;
create policy "UNGANI support access can insert (documents)"
  on public.documents
  for insert
  to authenticated
  with check (
    is_ungani_admin()
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = documents.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

-- client_people ----------------------------------------------------------

drop policy if exists "UNGANI support access can read (client_people)" on public.client_people;
create policy "UNGANI support access can read (client_people)"
  on public.client_people
  for select
  to authenticated
  using (
    is_ungani_admin()
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = client_people.tenant_id
        and g.status = 'active'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can update (client_people)" on public.client_people;
create policy "UNGANI support access can update (client_people)"
  on public.client_people
  for update
  to authenticated
  using (
    is_ungani_admin()
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = client_people.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  )
  with check (
    is_ungani_admin()
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = client_people.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can insert (client_people)" on public.client_people;
create policy "UNGANI support access can insert (client_people)"
  on public.client_people
  for insert
  to authenticated
  with check (
    is_ungani_admin()
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = client_people.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

-- business_events ---------------------------------------------------------

drop policy if exists "UNGANI support access can read (business_events)" on public.business_events;
create policy "UNGANI support access can read (business_events)"
  on public.business_events
  for select
  to authenticated
  using (
    is_ungani_admin()
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = business_events.tenant_id
        and g.status = 'active'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can update (business_events)" on public.business_events;
create policy "UNGANI support access can update (business_events)"
  on public.business_events
  for update
  to authenticated
  using (
    is_ungani_admin()
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = business_events.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  )
  with check (
    is_ungani_admin()
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = business_events.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can insert (business_events)" on public.business_events;
create policy "UNGANI support access can insert (business_events)"
  on public.business_events
  for insert
  to authenticated
  with check (
    is_ungani_admin()
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = business_events.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

-- =====================================================================
-- PART B: drop the pre-existing UNCONDITIONAL admin write policies on
-- the 6 operational tables. Admin SELECT policies (admin_can_read_*)
-- are NOT touched - reads stay unconditional per the "gate writes only"
-- decision. After this, admin insert/update on these 6 tables is
-- possible ONLY via the (now is_ungani_admin()-gated) support-access
-- policies above, requiring a live full_access grant. No DELETE path is
-- restored for admins on any of the 6 - matches the existing soft-
-- delete convention.
-- =====================================================================

drop policy if exists "ungani_admin_manage_business_items" on public.business_items;
drop policy if exists "admin_can_update_items_management" on public.business_items;

drop policy if exists "ungani_admin_manage_business_records" on public.business_records;
drop policy if exists "admin_can_update_records_management" on public.business_records;

drop policy if exists "admin_can_update_client_people" on public.client_people;

drop policy if exists "ungani_admin_manage_documents" on public.documents;
drop policy if exists "admin_can_update_documents_management" on public.documents;

drop policy if exists "ungani_admin_manage_tasks" on public.tasks;
drop policy if exists "admin_can_update_tasks_management" on public.tasks;

drop policy if exists "ungani_admin_manage_transactions" on public.transactions;
drop policy if exists "admin_can_update_money_management" on public.transactions;

-- =====================================================================
-- VERIFICATION - run after the above.
-- =====================================================================

-- 1. Confirm all 21 support-access policies now include is_ungani_admin()
--    in their qual/with_check text.
select tablename, policyname, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and policyname like 'UNGANI support access can%'
order by tablename, cmd;

-- 2. Confirm the 11 unconditional admin write policies are gone, and
--    every admin_can_read_* SELECT policy is still present.
select tablename, policyname, cmd, qual
from pg_policies
where schemaname = 'public'
  and tablename in ('business_items', 'business_records', 'client_people', 'documents', 'tasks', 'transactions')
  and qual ilike '%is_ungani_admin%'
order by tablename, cmd, policyname;
