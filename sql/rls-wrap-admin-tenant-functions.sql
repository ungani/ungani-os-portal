-- =====================================================================
-- SUPERSEDED - DO NOT RUN.
-- This file was reconstructed from sql/*.sql migration source, which
-- Chris correctly flagged as unsafe: live policies can drift from the
-- tracked migration text (confirmed already for partner_commissions
-- and other functions). Use sql/rls-wrap-live-dynamic.sql instead,
-- which reads pg_policies LIVE and wraps only what's actually still
-- unwrapped in the real database - no drift risk. Kept here only for
-- the file-provenance/supersession comments it contains.
-- =====================================================================

-- =====================================================================
-- sql/rls-wrap-admin-tenant-functions.sql
--
-- PURPOSE
-- -------
-- Every RLS policy in this project that calls public.is_ungani_admin()
-- or public.get_my_ungani_tenant_id() does so as a bare, unwrapped
-- function call inside USING/WITH CHECK. Postgres re-evaluates an
-- unwrapped (volatile-by-default, since neither function is marked
-- STABLE) function call once PER ROW scanned, instead of once per
-- query - a well-known RLS performance anti-pattern on any table with
-- meaningful row counts.
--
-- This migration rewrites every one of those policies, wrapping ONLY
-- the two calls as a scalar subquery - `(select is_ungani_admin())` /
-- `(select public.get_my_ungani_tenant_id())` - which lets the planner
-- evaluate/cache the result once instead of per row. Both functions
-- have been confirmed (separately from this migration) to only SELECT
-- from other tables and read auth.uid()/auth.jwt() - no side effects,
-- so wrapping changes nothing about behavior, only how often the value
-- gets computed. Pair this with marking both functions STABLE.
--
-- This migration touches NOTHING else: every other clause, operator,
-- table, command, role, and permissive/restrictive setting is
-- reproduced verbatim from the live, currently-effective policy text.
-- Where a table's policy was superseded by a later drop+recreate
-- migration, only the LATEST live version is rewritten here (the
-- superseded file is noted in a comment for traceability, not
-- reproduced).
--
-- SAFETY: additive-safe. Every statement is `drop policy if exists`
-- followed by `create policy` recreating the IDENTICAL logic (same
-- table, command, role, using/check expressions) with only the two
-- calls wrapped. No RLS behavior changes. Idempotent - safe to re-run.
--
-- Two functions NOT touched by this migration (mentioned only because
-- they appear alongside the two in-scope functions in some policies):
--   - public.is_my_ungani_tenant_owner(uuid)   (approvals policy)
--   - public.get_my_ungani_staff_access()      (support-access-grants policy)
--   - public.can_access_ungani_chat_message(...)  (read-receipts policy)
-- These are out of scope for this task and are left exactly as-is.
--
-- 64 policies total. Spot-checked by hand against live source files
-- before delivery (not just agent self-report): the jsonb owner-check
-- logic, the 21-policy support-access exists() template,
-- ungani_favorites_select, the 3 partner _admin_all policies, and the
-- channel-validation insert check all matched exactly.
--
-- NOT YET RUN against the live database.
-- =====================================================================


-- =====================================================================
-- from sql/approvals-internal-controls-v1.sql
-- =====================================================================

drop policy if exists ungani_approval_requests_requester_select on public.ungani_approval_requests;
create policy ungani_approval_requests_requester_select on public.ungani_approval_requests
  for select
  using (tenant_id = (select public.get_my_ungani_tenant_id()) and requested_by = auth.uid());

drop policy if exists ungani_approval_requests_owner_select on public.ungani_approval_requests;
create policy ungani_approval_requests_owner_select on public.ungani_approval_requests
  for select
  using (tenant_id = (select public.get_my_ungani_tenant_id()) and public.is_my_ungani_tenant_owner(tenant_id));


-- =====================================================================
-- from sql/audit-log-setup.sql
-- =====================================================================

drop policy if exists "Admins can read audit log" on public.ungani_audit_log;
create policy "Admins can read audit log"
  on public.ungani_audit_log
  for select
  to authenticated
  using ((select is_ungani_admin()));


-- =====================================================================
-- from sql/ungani-support-access.sql
-- NOTE: this file's own "Tenant owner can create/update their own
-- support access grant" policies are superseded by
-- sql/fix-support-access-owner-check-v2.sql (see below) - not
-- reproduced here. Only the still-live select/admin-read-all/audit-log
-- policies from this file are rewritten.
-- =====================================================================

drop policy if exists "Tenant members can read their own support access grant" on public.ungani_support_access_grants;
create policy "Tenant members can read their own support access grant"
  on public.ungani_support_access_grants
  for select
  to authenticated
  using (tenant_id = (select public.get_my_ungani_tenant_id()));

drop policy if exists "Admins can read all support access grants" on public.ungani_support_access_grants;
create policy "Admins can read all support access grants"
  on public.ungani_support_access_grants
  for select
  to authenticated
  using ((select is_ungani_admin()));

drop policy if exists "Tenant owner can read their tenant's support access audit trail" on public.ungani_audit_log;
create policy "Tenant owner can read their tenant's support access audit trail"
  on public.ungani_audit_log
  for select
  to authenticated
  using (
    action like 'support_access_%'
    and tenant_id = (select public.get_my_ungani_tenant_id())
  );


-- =====================================================================
-- from sql/fix-support-access-owner-check-v2.sql
-- (supersedes sql/fix-support-access-owner-check.sql and the original
-- "Tenant owner can create/update their own support access grant"
-- policies in sql/ungani-support-access.sql - confirmed via explicit
-- `drop policy if exists <same name>` in this later file, and both v1
-- and v2 land in the same commit e60072f, with v2 being the documented
-- follow-up fix to v1's incomplete owner-detection check.)
-- =====================================================================

drop policy if exists "Tenant owner can create their own support access grant" on public.ungani_support_access_grants;
create policy "Tenant owner can create their own support access grant"
  on public.ungani_support_access_grants
  for insert
  to authenticated
  with check (
    tenant_id = (select public.get_my_ungani_tenant_id())
    and exists (
      select 1
      from (select public.get_my_ungani_staff_access() as access) s
      where (s.access->>'is_owner')::boolean is true
         or coalesce(lower(s.access->>'role_key'), '') in ('', 'guest')
    )
  );

drop policy if exists "Tenant owner can update their own support access grant" on public.ungani_support_access_grants;
create policy "Tenant owner can update their own support access grant"
  on public.ungani_support_access_grants
  for update
  to authenticated
  using (tenant_id = (select public.get_my_ungani_tenant_id()))
  with check (
    tenant_id = (select public.get_my_ungani_tenant_id())
    and exists (
      select 1
      from (select public.get_my_ungani_staff_access() as access) s
      where (s.access->>'is_owner')::boolean is true
         or coalesce(lower(s.access->>'role_key'), '') in ('', 'guest')
    )
  );


-- =====================================================================
-- from sql/branch-billing-phase4-live-wiring.sql
-- =====================================================================

drop policy if exists "Admins can read billing mismatches" on public.ungani_billing_amount_mismatches;
create policy "Admins can read billing mismatches"
  on public.ungani_billing_amount_mismatches
  for select
  to authenticated
  using ((select is_ungani_admin()));


-- =====================================================================
-- from sql/cluster4-commitments.sql
-- =====================================================================

drop policy if exists ungani_commitments_tenant_select on public.ungani_commitments;
create policy ungani_commitments_tenant_select on public.ungani_commitments
  for select
  using (tenant_id = (select public.get_my_ungani_tenant_id()));


-- =====================================================================
-- from sql/education-vertical-phase1.sql
-- =====================================================================

drop policy if exists ungani_class_enrollments_tenant_select on public.ungani_class_enrollments;
create policy ungani_class_enrollments_tenant_select on public.ungani_class_enrollments
  for select
  using (tenant_id = (select public.get_my_ungani_tenant_id()));


-- =====================================================================
-- from sql/favorites-v1.sql
-- =====================================================================

drop policy if exists ungani_favorites_select on public.ungani_favorites;
create policy ungani_favorites_select
  on public.ungani_favorites for select to authenticated
  using ((select public.is_ungani_admin()) or user_id = auth.uid());


-- =====================================================================
-- from sql/fix-support-access-admin-scoping-and-gate-writes.sql
-- (supersedes the original 21 "UNGANI support access can read/update/
-- insert (<table>)" policies defined in sql/ungani-support-access.sql -
-- confirmed via explicit `drop policy if exists <same name>` for all
-- 21 names in this later file, dated after the original.)
-- =====================================================================

drop policy if exists "UNGANI support access can read (business_items)" on public.business_items;
create policy "UNGANI support access can read (business_items)"
  on public.business_items
  for select
  to authenticated
  using (
    (select is_ungani_admin())
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
    (select is_ungani_admin())
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
    (select is_ungani_admin())
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
    (select is_ungani_admin())
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = business_items.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can read (transactions)" on public.transactions;
create policy "UNGANI support access can read (transactions)"
  on public.transactions
  for select
  to authenticated
  using (
    (select is_ungani_admin())
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
    (select is_ungani_admin())
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
    (select is_ungani_admin())
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
    (select is_ungani_admin())
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = transactions.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can read (tasks)" on public.tasks;
create policy "UNGANI support access can read (tasks)"
  on public.tasks
  for select
  to authenticated
  using (
    (select is_ungani_admin())
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
    (select is_ungani_admin())
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
    (select is_ungani_admin())
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
    (select is_ungani_admin())
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = tasks.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can read (business_records)" on public.business_records;
create policy "UNGANI support access can read (business_records)"
  on public.business_records
  for select
  to authenticated
  using (
    (select is_ungani_admin())
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
    (select is_ungani_admin())
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
    (select is_ungani_admin())
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
    (select is_ungani_admin())
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = business_records.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can read (documents)" on public.documents;
create policy "UNGANI support access can read (documents)"
  on public.documents
  for select
  to authenticated
  using (
    (select is_ungani_admin())
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
    (select is_ungani_admin())
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
    (select is_ungani_admin())
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
    (select is_ungani_admin())
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = documents.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can read (client_people)" on public.client_people;
create policy "UNGANI support access can read (client_people)"
  on public.client_people
  for select
  to authenticated
  using (
    (select is_ungani_admin())
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
    (select is_ungani_admin())
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
    (select is_ungani_admin())
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
    (select is_ungani_admin())
    and exists (
      select 1 from public.ungani_support_access_grants g
      where g.tenant_id = client_people.tenant_id
        and g.status = 'active'
        and g.access_level = 'full_access'
        and g.expires_at is not null
        and g.expires_at > now()
    )
  );

drop policy if exists "UNGANI support access can read (business_events)" on public.business_events;
create policy "UNGANI support access can read (business_events)"
  on public.business_events
  for select
  to authenticated
  using (
    (select is_ungani_admin())
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
    (select is_ungani_admin())
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
    (select is_ungani_admin())
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
    (select is_ungani_admin())
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
-- from sql/partner-referral-system.sql
-- =====================================================================

drop policy if exists partners_admin_all on public.partners;
create policy partners_admin_all on public.partners
  for all using ((select public.is_ungani_admin())) with check ((select public.is_ungani_admin()));

drop policy if exists partner_commissions_admin_all on public.partner_commissions;
create policy partner_commissions_admin_all on public.partner_commissions
  for all using ((select public.is_ungani_admin())) with check ((select public.is_ungani_admin()));

drop policy if exists partner_payouts_admin_all on public.partner_payouts;
create policy partner_payouts_admin_all on public.partner_payouts
  for all using ((select public.is_ungani_admin())) with check ((select public.is_ungani_admin()));


-- =====================================================================
-- from sql/payee-tracking.sql
-- =====================================================================

drop policy if exists ungani_payees_tenant_select on public.ungani_payees;
create policy ungani_payees_tenant_select on public.ungani_payees
  for select
  using (tenant_id = (select public.get_my_ungani_tenant_id()));

drop policy if exists ungani_payees_tenant_insert on public.ungani_payees;
create policy ungani_payees_tenant_insert on public.ungani_payees
  for insert
  with check (tenant_id = (select public.get_my_ungani_tenant_id()));

drop policy if exists ungani_payees_tenant_update on public.ungani_payees;
create policy ungani_payees_tenant_update on public.ungani_payees
  for update
  using (tenant_id = (select public.get_my_ungani_tenant_id()))
  with check (tenant_id = (select public.get_my_ungani_tenant_id()));


-- =====================================================================
-- from sql/stock-atomicity-and-idempotency-fix.sql
-- =====================================================================

drop policy if exists ungani_pos_sale_events_tenant_select on public.ungani_pos_sale_events;
create policy ungani_pos_sale_events_tenant_select on public.ungani_pos_sale_events
  for select
  using (tenant_id = (select public.get_my_ungani_tenant_id()));

drop policy if exists ungani_order_fulfillment_events_tenant_select on public.ungani_order_fulfillment_events;
create policy ungani_order_fulfillment_events_tenant_select on public.ungani_order_fulfillment_events
  for select
  using (tenant_id = (select public.get_my_ungani_tenant_id()));


-- =====================================================================
-- from sql/task-app-error-log.sql
-- =====================================================================

drop policy if exists "Admins can read app error log" on public.app_error_log;
create policy "Admins can read app error log"
  on public.app_error_log
  for select
  to authenticated
  using ((select is_ungani_admin()));


-- =====================================================================
-- from sql/task2-branding-and-customer-invoicing.sql
-- =====================================================================

drop policy if exists tenant_branding_select on storage.objects;
create policy tenant_branding_select on storage.objects
  for select
  using (
    bucket_id = 'tenant-branding'
    and (storage.foldername(name))[1] = (select public.get_my_ungani_tenant_id())::text
  );

drop policy if exists tenant_branding_insert on storage.objects;
create policy tenant_branding_insert on storage.objects
  for insert
  with check (
    bucket_id = 'tenant-branding'
    and (storage.foldername(name))[1] = (select public.get_my_ungani_tenant_id())::text
  );

drop policy if exists tenant_branding_update on storage.objects;
create policy tenant_branding_update on storage.objects
  for update
  using (
    bucket_id = 'tenant-branding'
    and (storage.foldername(name))[1] = (select public.get_my_ungani_tenant_id())::text
  );

drop policy if exists tenant_branding_delete on storage.objects;
create policy tenant_branding_delete on storage.objects
  for delete
  using (
    bucket_id = 'tenant-branding'
    and (storage.foldername(name))[1] = (select public.get_my_ungani_tenant_id())::text
  );

drop policy if exists ungani_customer_invoices_tenant_select on public.ungani_customer_invoices;
create policy ungani_customer_invoices_tenant_select on public.ungani_customer_invoices
  for select
  using (tenant_id = (select public.get_my_ungani_tenant_id()));

drop policy if exists ungani_customer_invoice_items_tenant_select on public.ungani_customer_invoice_items;
create policy ungani_customer_invoice_items_tenant_select on public.ungani_customer_invoice_items
  for select
  using (tenant_id = (select public.get_my_ungani_tenant_id()));

drop policy if exists ungani_customer_invoice_payments_tenant_select on public.ungani_customer_invoice_payments;
create policy ungani_customer_invoice_payments_tenant_select on public.ungani_customer_invoice_payments
  for select
  using (tenant_id = (select public.get_my_ungani_tenant_id()));


-- =====================================================================
-- from sql/task3-stock-tracking.sql
-- =====================================================================

drop policy if exists "ungani_stock_movements_select_own_tenant" on public.ungani_stock_movements;
create policy "ungani_stock_movements_select_own_tenant" on public.ungani_stock_movements
  for select
  using (tenant_id = (select public.get_my_ungani_tenant_id()));


-- =====================================================================
-- from sql/task5-quotations.sql
-- =====================================================================

drop policy if exists ungani_quotations_tenant_select on public.ungani_quotations;
create policy ungani_quotations_tenant_select on public.ungani_quotations
  for select
  using (tenant_id = (select public.get_my_ungani_tenant_id()));

drop policy if exists ungani_quotation_items_tenant_select on public.ungani_quotation_items;
create policy ungani_quotation_items_tenant_select on public.ungani_quotation_items
  for select
  using (tenant_id = (select public.get_my_ungani_tenant_id()));


-- =====================================================================
-- from sql/task6-orders.sql
-- =====================================================================

drop policy if exists ungani_orders_tenant_select on public.ungani_orders;
create policy ungani_orders_tenant_select on public.ungani_orders
  for select
  using (tenant_id = (select public.get_my_ungani_tenant_id()));

drop policy if exists ungani_order_items_tenant_select on public.ungani_order_items;
create policy ungani_order_items_tenant_select on public.ungani_order_items
  for select
  using (tenant_id = (select public.get_my_ungani_tenant_id()));


-- =====================================================================
-- from sql/task7-price-lists.sql
-- =====================================================================

drop policy if exists ungani_price_lists_tenant_select on public.ungani_price_lists;
create policy ungani_price_lists_tenant_select on public.ungani_price_lists
  for select
  using (tenant_id = (select public.get_my_ungani_tenant_id()));

drop policy if exists ungani_price_list_items_tenant_select on public.ungani_price_list_items;
create policy ungani_price_list_items_tenant_select on public.ungani_price_list_items
  for select
  using (tenant_id = (select public.get_my_ungani_tenant_id()));


-- =====================================================================
-- from sql/team-chat-presence-phase5.sql
-- =====================================================================

drop policy if exists "tenant members can read their tenant's presence" on public.ungani_user_presence;
create policy "tenant members can read their tenant's presence"
  on public.ungani_user_presence for select
  using (tenant_id = (select public.get_my_ungani_tenant_id()));


-- =====================================================================
-- from sql/team-chat-read-receipts.sql
-- =====================================================================

drop policy if exists team_chat_message_reads_select on public.team_chat_message_reads;
create policy team_chat_message_reads_select
  on public.team_chat_message_reads
  for select
  to authenticated
  using (
    (select public.is_ungani_admin())
    or exists (
      select 1 from public.team_chat_messages m
      where m.id = message_id
        and public.can_access_ungani_chat_message(m.tenant_id, m.sender_user_id, m.recipient_team_member_id, m.recipient_is_owner)
    )
  );


-- =====================================================================
-- from sql/tenant-integrations-setup.sql
-- =====================================================================

drop policy if exists "Tenant members can read their own integrations" on public.tenant_integrations;
create policy "Tenant members can read their own integrations"
  on public.tenant_integrations
  for select
  to authenticated
  using (tenant_id = (select public.get_my_ungani_tenant_id()));

drop policy if exists "Tenant members can connect their own integrations" on public.tenant_integrations;
create policy "Tenant members can connect their own integrations"
  on public.tenant_integrations
  for insert
  to authenticated
  with check (tenant_id = (select public.get_my_ungani_tenant_id()));

drop policy if exists "Tenant members can update their own integrations" on public.tenant_integrations;
create policy "Tenant members can update their own integrations"
  on public.tenant_integrations
  for update
  to authenticated
  using (tenant_id = (select public.get_my_ungani_tenant_id()))
  with check (tenant_id = (select public.get_my_ungani_tenant_id()));

drop policy if exists "Admins can read all integrations" on public.tenant_integrations;
create policy "Admins can read all integrations"
  on public.tenant_integrations
  for select
  to authenticated
  using ((select is_ungani_admin()));


-- =====================================================================
-- from sql/ungani-connect-phase1-channels.sql
-- NOTE: team_chat_insert_own_tenant_and_identity also has an earlier
-- version in sql/team-chat-direct-messages.sql (2026-07-31). This file
-- (2026-08-05) contains an explicit `drop policy if exists
-- team_chat_insert_own_tenant_and_identity` immediately before its own
-- `create policy` of the same name, confirming it is the later,
-- live-effective version (it adds channel_id validation on top of the
-- original tenant/identity check) - not ambiguous, so only this
-- version is reproduced below.
-- =====================================================================

drop policy if exists "Tenant members can read their channels" on public.ungani_chat_channels;
create policy "Tenant members can read their channels"
  on public.ungani_chat_channels
  for select
  to authenticated
  using (
    (select public.is_ungani_admin())
    or tenant_id = (select public.get_my_ungani_tenant_id())
  );

drop policy if exists team_chat_insert_own_tenant_and_identity on public.team_chat_messages;
create policy team_chat_insert_own_tenant_and_identity
  on public.team_chat_messages
  for insert
  with check (
    (select public.is_ungani_admin())
    or (
      tenant_id = (select public.get_my_ungani_tenant_id())
      and sender_user_id = auth.uid()
      and (
        channel_id is null
        or exists (
          select 1 from public.ungani_chat_channels c
          where c.id = channel_id
            and c.tenant_id = tenant_id
            and c.is_archived = false
        )
      )
    )
  );
