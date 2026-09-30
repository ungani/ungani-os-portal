-- =====================================================================
-- sql/rls-wrap-rollback-reference.sql
--
-- ROLLBACK REFERENCE for sql/rls-wrap-live-dynamic.sql. Each statement
-- below restores ONE policy's original (pre-wrap) USING/WITH CHECK text,
-- exactly as read from pg_policies before the wrap migration ran. Run
-- any single statement to revert just that one policy if a problem
-- shows up later - do not run this whole file unless reverting
-- everything.
--
-- Captured from the dry-run pass covering 220 policies (out of
-- 326 total public-schema policies at the time), plus the one policy
-- fixed separately (ungani_billing_reminder_logs_admin_all) due to its
-- to_regprocedure() string-literal argument.
-- =====================================================================

alter policy "admin_client_messages_delete_policy" on public.admin_client_messages
  using (is_ungani_admin());

alter policy "admin_client_messages_insert_own" on public.admin_client_messages
  with check (((tenant_id = get_my_ungani_tenant_id()) OR is_ungani_admin()));

alter policy "admin_client_messages_insert_policy" on public.admin_client_messages
  with check (((is_ungani_admin() OR (tenant_id = get_my_ungani_tenant_id())) AND ((sender_id = auth.uid()) OR (sender_id IS NULL))));

alter policy "admin_client_messages_select_own" on public.admin_client_messages
  using (((tenant_id = get_my_ungani_tenant_id()) OR is_ungani_admin()));

alter policy "admin_client_messages_select_policy" on public.admin_client_messages
  using ((is_ungani_admin() OR (tenant_id = get_my_ungani_tenant_id())));

alter policy "admin_client_messages_update_own" on public.admin_client_messages
  using (((tenant_id = get_my_ungani_tenant_id()) OR is_ungani_admin()))
  with check (((tenant_id = get_my_ungani_tenant_id()) OR is_ungani_admin()));

alter policy "admin_client_messages_update_policy" on public.admin_client_messages
  using ((is_ungani_admin() OR (tenant_id = get_my_ungani_tenant_id())))
  with check ((is_ungani_admin() OR (tenant_id = get_my_ungani_tenant_id())));

alter policy "Admins can read app error log" on public.app_error_log
  using (is_ungani_admin());

alter policy "ungani_admin_manage_audit_logs" on public.audit_logs
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "UNGANI admin can manage branches" on public.branches
  using ((is_ungani_admin() IS TRUE))
  with check ((is_ungani_admin() IS TRUE));

alter policy "UNGANI clients can view own branches" on public.branches
  using ((tenant_id = get_my_ungani_tenant_id()));

alter policy "UNGANI support access can insert (business_events)" on public.business_events
  with check ((is_ungani_admin() AND (EXISTS ( SELECT 1
   FROM ungani_support_access_grants g
  WHERE ((g.tenant_id = business_events.tenant_id) AND (g.status = 'active'::text) AND (g.access_level = 'full_access'::text) AND (g.expires_at IS NOT NULL) AND (g.expires_at > now()))))));

alter policy "UNGANI support access can read (business_events)" on public.business_events
  using ((is_ungani_admin() AND (EXISTS ( SELECT 1
   FROM ungani_support_access_grants g
  WHERE ((g.tenant_id = business_events.tenant_id) AND (g.status = 'active'::text) AND (g.expires_at IS NOT NULL) AND (g.expires_at > now()))))));

alter policy "UNGANI support access can update (business_events)" on public.business_events
  using ((is_ungani_admin() AND (EXISTS ( SELECT 1
   FROM ungani_support_access_grants g
  WHERE ((g.tenant_id = business_events.tenant_id) AND (g.status = 'active'::text) AND (g.access_level = 'full_access'::text) AND (g.expires_at IS NOT NULL) AND (g.expires_at > now()))))))
  with check ((is_ungani_admin() AND (EXISTS ( SELECT 1
   FROM ungani_support_access_grants g
  WHERE ((g.tenant_id = business_events.tenant_id) AND (g.status = 'active'::text) AND (g.access_level = 'full_access'::text) AND (g.expires_at IS NOT NULL) AND (g.expires_at > now()))))));

alter policy "admin_can_read_business_events" on public.business_events
  using (is_ungani_admin());

alter policy "admin_can_update_business_events" on public.business_events
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "ungani_events_admin_delete_15d" on public.business_events
  using (is_ungani_admin());

alter policy "ungani_events_admin_insert_15d" on public.business_events
  with check (is_ungani_admin());

alter policy "ungani_events_client_staff_insert_16b" on public.business_events
  with check (((tenant_id = get_my_ungani_tenant_id()) AND (deleted_at IS NULL) AND can_access_ungani_section('calendar'::text, 'create'::text)));

alter policy "ungani_events_client_staff_select_16b" on public.business_events
  using (((tenant_id = get_my_ungani_tenant_id()) AND (deleted_at IS NULL) AND can_access_ungani_section('calendar'::text, 'view'::text)));

alter policy "ungani_events_client_staff_update_16b" on public.business_events
  using (((tenant_id = get_my_ungani_tenant_id()) AND (deleted_at IS NULL) AND can_access_ungani_section('calendar'::text, 'edit'::text)))
  with check (((tenant_id = get_my_ungani_tenant_id()) AND (deleted_at IS NULL) AND can_access_ungani_section('calendar'::text, 'edit'::text)));

alter policy "UNGANI support access can insert (business_items)" on public.business_items
  with check ((is_ungani_admin() AND (EXISTS ( SELECT 1
   FROM ungani_support_access_grants g
  WHERE ((g.tenant_id = business_items.tenant_id) AND (g.status = 'active'::text) AND (g.access_level = 'full_access'::text) AND (g.expires_at IS NOT NULL) AND (g.expires_at > now()))))));

alter policy "UNGANI support access can read (business_items)" on public.business_items
  using ((is_ungani_admin() AND (EXISTS ( SELECT 1
   FROM ungani_support_access_grants g
  WHERE ((g.tenant_id = business_items.tenant_id) AND (g.status = 'active'::text) AND (g.expires_at IS NOT NULL) AND (g.expires_at > now()))))));

alter policy "UNGANI support access can update (business_items)" on public.business_items
  using ((is_ungani_admin() AND (EXISTS ( SELECT 1
   FROM ungani_support_access_grants g
  WHERE ((g.tenant_id = business_items.tenant_id) AND (g.status = 'active'::text) AND (g.access_level = 'full_access'::text) AND (g.expires_at IS NOT NULL) AND (g.expires_at > now()))))))
  with check ((is_ungani_admin() AND (EXISTS ( SELECT 1
   FROM ungani_support_access_grants g
  WHERE ((g.tenant_id = business_items.tenant_id) AND (g.status = 'active'::text) AND (g.access_level = 'full_access'::text) AND (g.expires_at IS NOT NULL) AND (g.expires_at > now()))))));

alter policy "admin_can_read_items_admin_home" on public.business_items
  using (is_ungani_admin());

alter policy "admin_can_read_items_for_reports" on public.business_items
  using (is_ungani_admin());

alter policy "admin_can_read_items_health" on public.business_items
  using (is_ungani_admin());

alter policy "admin_can_read_items_management" on public.business_items
  using (is_ungani_admin());

alter policy "ungani_items_client_staff_insert_16b" on public.business_items
  with check (((tenant_id = get_my_ungani_tenant_id()) AND (deleted_at IS NULL) AND can_access_ungani_section('items'::text, 'create'::text)));

alter policy "ungani_items_client_staff_select_16b" on public.business_items
  using (((tenant_id = get_my_ungani_tenant_id()) AND (deleted_at IS NULL) AND can_access_ungani_section('items'::text, 'view'::text)));

alter policy "ungani_items_client_staff_update_16b" on public.business_items
  using (((tenant_id = get_my_ungani_tenant_id()) AND (deleted_at IS NULL) AND can_access_ungani_section('items'::text, 'edit'::text)))
  with check (((tenant_id = get_my_ungani_tenant_id()) AND (deleted_at IS NULL) AND can_access_ungani_section('items'::text, 'edit'::text)));

alter policy "UNGANI support access can insert (business_records)" on public.business_records
  with check ((is_ungani_admin() AND (EXISTS ( SELECT 1
   FROM ungani_support_access_grants g
  WHERE ((g.tenant_id = business_records.tenant_id) AND (g.status = 'active'::text) AND (g.access_level = 'full_access'::text) AND (g.expires_at IS NOT NULL) AND (g.expires_at > now()))))));

alter policy "UNGANI support access can read (business_records)" on public.business_records
  using ((is_ungani_admin() AND (EXISTS ( SELECT 1
   FROM ungani_support_access_grants g
  WHERE ((g.tenant_id = business_records.tenant_id) AND (g.status = 'active'::text) AND (g.expires_at IS NOT NULL) AND (g.expires_at > now()))))));

alter policy "UNGANI support access can update (business_records)" on public.business_records
  using ((is_ungani_admin() AND (EXISTS ( SELECT 1
   FROM ungani_support_access_grants g
  WHERE ((g.tenant_id = business_records.tenant_id) AND (g.status = 'active'::text) AND (g.access_level = 'full_access'::text) AND (g.expires_at IS NOT NULL) AND (g.expires_at > now()))))))
  with check ((is_ungani_admin() AND (EXISTS ( SELECT 1
   FROM ungani_support_access_grants g
  WHERE ((g.tenant_id = business_records.tenant_id) AND (g.status = 'active'::text) AND (g.access_level = 'full_access'::text) AND (g.expires_at IS NOT NULL) AND (g.expires_at > now()))))));

alter policy "ungani_admin_manage_business_sections" on public.business_sections
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "ungani_admin_manage_business_types" on public.business_types
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "ungani_admin_manage_categories" on public.categories
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "admin_can_manage_client_notices" on public.client_notices
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "admin_can_read_client_notices_charts" on public.client_notices
  using (is_ungani_admin());

alter policy "client_notices_admin_insert" on public.client_notices
  with check (is_ungani_admin());

alter policy "client_notices_admin_select_all" on public.client_notices
  using (is_ungani_admin());

alter policy "client_notices_admin_update" on public.client_notices
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "client_notices_client_select_own" on public.client_notices
  using ((tenant_id = get_my_ungani_tenant_id()));

alter policy "client_notices_client_update_own" on public.client_notices
  using ((tenant_id = get_my_ungani_tenant_id()))
  with check ((tenant_id = get_my_ungani_tenant_id()));

alter policy "client_notices_insert_own" on public.client_notices
  with check (((tenant_id = get_my_ungani_tenant_id()) OR is_ungani_admin()));

alter policy "client_notices_select_own" on public.client_notices
  using (((tenant_id = get_my_ungani_tenant_id()) OR is_ungani_admin()));

alter policy "client_notices_update_own" on public.client_notices
  using (((tenant_id = get_my_ungani_tenant_id()) OR is_ungani_admin()))
  with check (((tenant_id = get_my_ungani_tenant_id()) OR is_ungani_admin()));

alter policy "UNGANI support access can insert (client_people)" on public.client_people
  with check ((is_ungani_admin() AND (EXISTS ( SELECT 1
   FROM ungani_support_access_grants g
  WHERE ((g.tenant_id = client_people.tenant_id) AND (g.status = 'active'::text) AND (g.access_level = 'full_access'::text) AND (g.expires_at IS NOT NULL) AND (g.expires_at > now()))))));

alter policy "UNGANI support access can read (client_people)" on public.client_people
  using ((is_ungani_admin() AND (EXISTS ( SELECT 1
   FROM ungani_support_access_grants g
  WHERE ((g.tenant_id = client_people.tenant_id) AND (g.status = 'active'::text) AND (g.expires_at IS NOT NULL) AND (g.expires_at > now()))))));

alter policy "UNGANI support access can update (client_people)" on public.client_people
  using ((is_ungani_admin() AND (EXISTS ( SELECT 1
   FROM ungani_support_access_grants g
  WHERE ((g.tenant_id = client_people.tenant_id) AND (g.status = 'active'::text) AND (g.access_level = 'full_access'::text) AND (g.expires_at IS NOT NULL) AND (g.expires_at > now()))))))
  with check ((is_ungani_admin() AND (EXISTS ( SELECT 1
   FROM ungani_support_access_grants g
  WHERE ((g.tenant_id = client_people.tenant_id) AND (g.status = 'active'::text) AND (g.access_level = 'full_access'::text) AND (g.expires_at IS NOT NULL) AND (g.expires_at > now()))))));

alter policy "admin_can_read_client_people" on public.client_people
  using (is_ungani_admin());

alter policy "admin_can_read_client_people_charts" on public.client_people
  using (is_ungani_admin());

alter policy "ungani_people_client_staff_insert_16b" on public.client_people
  with check (((tenant_id = get_my_ungani_tenant_id()) AND (deleted_at IS NULL) AND can_access_ungani_section('people'::text, 'create'::text)));

alter policy "ungani_people_client_staff_select_16b" on public.client_people
  using (((tenant_id = get_my_ungani_tenant_id()) AND (deleted_at IS NULL) AND can_access_ungani_section('people'::text, 'view'::text)));

alter policy "ungani_people_client_staff_update_16b" on public.client_people
  using (((tenant_id = get_my_ungani_tenant_id()) AND (deleted_at IS NULL) AND can_access_ungani_section('people'::text, 'edit'::text)))
  with check (((tenant_id = get_my_ungani_tenant_id()) AND (deleted_at IS NULL) AND can_access_ungani_section('people'::text, 'edit'::text)));

alter policy "ungani_admin_manage_client_settings" on public.client_settings
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "UNGANI support access can insert (documents)" on public.documents
  with check ((is_ungani_admin() AND (EXISTS ( SELECT 1
   FROM ungani_support_access_grants g
  WHERE ((g.tenant_id = documents.tenant_id) AND (g.status = 'active'::text) AND (g.access_level = 'full_access'::text) AND (g.expires_at IS NOT NULL) AND (g.expires_at > now()))))));

alter policy "UNGANI support access can read (documents)" on public.documents
  using ((is_ungani_admin() AND (EXISTS ( SELECT 1
   FROM ungani_support_access_grants g
  WHERE ((g.tenant_id = documents.tenant_id) AND (g.status = 'active'::text) AND (g.expires_at IS NOT NULL) AND (g.expires_at > now()))))));

alter policy "UNGANI support access can update (documents)" on public.documents
  using ((is_ungani_admin() AND (EXISTS ( SELECT 1
   FROM ungani_support_access_grants g
  WHERE ((g.tenant_id = documents.tenant_id) AND (g.status = 'active'::text) AND (g.access_level = 'full_access'::text) AND (g.expires_at IS NOT NULL) AND (g.expires_at > now()))))))
  with check ((is_ungani_admin() AND (EXISTS ( SELECT 1
   FROM ungani_support_access_grants g
  WHERE ((g.tenant_id = documents.tenant_id) AND (g.status = 'active'::text) AND (g.access_level = 'full_access'::text) AND (g.expires_at IS NOT NULL) AND (g.expires_at > now()))))));

alter policy "admin_can_read_documents_management" on public.documents
  using (is_ungani_admin());

alter policy "ungani_admin_manage_packages" on public.packages
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "partner_commissions_admin_all" on public.partner_commissions
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "partner_commissions_select_own" on public.partner_commissions
  using (((EXISTS ( SELECT 1
   FROM partners p
  WHERE ((p.id = partner_commissions.partner_id) AND (p.auth_user_id = auth.uid())))) OR is_ungani_admin()));

alter policy "partner_payouts_admin_all" on public.partner_payouts
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "partner_payouts_select_own" on public.partner_payouts
  using (((EXISTS ( SELECT 1
   FROM partners p
  WHERE ((p.id = partner_payouts.partner_id) AND (p.auth_user_id = auth.uid())))) OR is_ungani_admin()));

alter policy "partners_admin_all" on public.partners
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "partners_select_own" on public.partners
  using (((auth_user_id = auth.uid()) OR is_ungani_admin()));

alter policy "admin_can_read_payments_charts" on public.payments
  using (is_ungani_admin());

alter policy "ungani_admin_can_manage_payments" on public.payments
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "ungani_admin_manage_payments" on public.payments
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "registrations_delete_admin_only" on public.registrations
  using (is_ungani_admin());

alter policy "registrations_select_admin_only" on public.registrations
  using (is_ungani_admin());

alter policy "registrations_update_admin_only" on public.registrations
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "ungani_admin_manage_roles" on public.roles
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "admin_can_read_support_admin_home" on public.support_issues
  using (is_ungani_admin());

alter policy "admin_can_read_support_for_reports" on public.support_issues
  using (is_ungani_admin());

alter policy "admin_can_read_support_health" on public.support_issues
  using (is_ungani_admin());

alter policy "ungani_admin_manage_support_issues" on public.support_issues
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "ungani_support_client_staff_insert_16b" on public.support_issues
  with check (((tenant_id = get_my_ungani_tenant_id()) AND (deleted_at IS NULL) AND can_access_ungani_section('support'::text, 'create'::text)));

alter policy "ungani_support_client_staff_select_16b" on public.support_issues
  using (((tenant_id = get_my_ungani_tenant_id()) AND (deleted_at IS NULL) AND can_access_ungani_section('support'::text, 'view'::text)));

alter policy "ungani_support_client_staff_update_16b" on public.support_issues
  using (((tenant_id = get_my_ungani_tenant_id()) AND (deleted_at IS NULL) AND can_access_ungani_section('support'::text, 'edit'::text)))
  with check (((tenant_id = get_my_ungani_tenant_id()) AND (deleted_at IS NULL) AND can_access_ungani_section('support'::text, 'edit'::text)));

alter policy "system_notices_admin_all" on public.system_notices
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "system_notices_admin_insert" on public.system_notices
  with check (is_ungani_admin());

alter policy "system_notices_admin_select_all" on public.system_notices
  using (is_ungani_admin());

alter policy "system_notices_admin_update" on public.system_notices
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "system_notices_select_active" on public.system_notices
  using (((status = ANY (ARRAY['active'::text, 'published'::text, 'open'::text])) AND ((tenant_id IS NULL) OR (tenant_id = get_my_ungani_tenant_id()))));

alter policy "ungani_admin_manage_system_notices" on public.system_notices
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "UNGANI support access can insert (tasks)" on public.tasks
  with check ((is_ungani_admin() AND (EXISTS ( SELECT 1
   FROM ungani_support_access_grants g
  WHERE ((g.tenant_id = tasks.tenant_id) AND (g.status = 'active'::text) AND (g.access_level = 'full_access'::text) AND (g.expires_at IS NOT NULL) AND (g.expires_at > now()))))));

alter policy "UNGANI support access can read (tasks)" on public.tasks
  using ((is_ungani_admin() AND (EXISTS ( SELECT 1
   FROM ungani_support_access_grants g
  WHERE ((g.tenant_id = tasks.tenant_id) AND (g.status = 'active'::text) AND (g.expires_at IS NOT NULL) AND (g.expires_at > now()))))));

alter policy "UNGANI support access can update (tasks)" on public.tasks
  using ((is_ungani_admin() AND (EXISTS ( SELECT 1
   FROM ungani_support_access_grants g
  WHERE ((g.tenant_id = tasks.tenant_id) AND (g.status = 'active'::text) AND (g.access_level = 'full_access'::text) AND (g.expires_at IS NOT NULL) AND (g.expires_at > now()))))))
  with check ((is_ungani_admin() AND (EXISTS ( SELECT 1
   FROM ungani_support_access_grants g
  WHERE ((g.tenant_id = tasks.tenant_id) AND (g.status = 'active'::text) AND (g.access_level = 'full_access'::text) AND (g.expires_at IS NOT NULL) AND (g.expires_at > now()))))));

alter policy "admin_can_read_tasks_admin_home" on public.tasks
  using (is_ungani_admin());

alter policy "admin_can_read_tasks_for_reports" on public.tasks
  using (is_ungani_admin());

alter policy "admin_can_read_tasks_health" on public.tasks
  using (is_ungani_admin());

alter policy "admin_can_read_tasks_management" on public.tasks
  using (is_ungani_admin());

alter policy "team_chat_message_reads_select" on public.team_chat_message_reads
  using ((is_ungani_admin() OR (EXISTS ( SELECT 1
   FROM team_chat_messages m
  WHERE ((m.id = team_chat_message_reads.message_id) AND can_access_ungani_chat_message(m.tenant_id, m.sender_user_id, m.recipient_team_member_id, m.recipient_is_owner))))));

alter policy "team_chat_delete_admin_only" on public.team_chat_messages
  using (is_ungani_admin());

alter policy "team_chat_insert_own_tenant_and_identity" on public.team_chat_messages
  with check ((is_ungani_admin() OR ((tenant_id = get_my_ungani_tenant_id()) AND (sender_user_id = auth.uid()) AND ((channel_id IS NULL) OR (EXISTS ( SELECT 1
   FROM ungani_chat_channels c
  WHERE ((c.id = team_chat_messages.channel_id) AND (c.tenant_id = c.tenant_id) AND (c.is_archived = false))))))));

alter policy "ungani_admin_manage_team_messages" on public.team_messages
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "Admins can read all integrations" on public.tenant_integrations
  using (is_ungani_admin());

alter policy "Tenant members can connect their own integrations" on public.tenant_integrations
  with check ((tenant_id = get_my_ungani_tenant_id()));

alter policy "Tenant members can read their own integrations" on public.tenant_integrations
  using ((tenant_id = get_my_ungani_tenant_id()));

alter policy "Tenant members can update their own integrations" on public.tenant_integrations
  using ((tenant_id = get_my_ungani_tenant_id()))
  with check ((tenant_id = get_my_ungani_tenant_id()));

alter policy "tenant_sections_insert_admin" on public.tenant_sections
  with check (is_ungani_admin());

alter policy "tenant_sections_select_own_or_admin" on public.tenant_sections
  using (((tenant_id = get_my_ungani_tenant_id()) OR is_ungani_admin()));

alter policy "tenant_sections_update_admin" on public.tenant_sections
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "ungani_admin_can_manage_tenant_sections" on public.tenant_sections
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "ungani_admin_manage_tenant_sections" on public.tenant_sections
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "admin_can_read_business_profiles" on public.tenants
  using (is_ungani_admin());

alter policy "admin_can_read_clients_admin_home" on public.tenants
  using (is_ungani_admin());

alter policy "admin_can_read_clients_for_reports" on public.tenants
  using (is_ungani_admin());

alter policy "admin_can_read_clients_health" on public.tenants
  using (is_ungani_admin());

alter policy "admin_can_update_business_profiles" on public.tenants
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "tenants_insert_admin" on public.tenants
  with check (is_ungani_admin());

alter policy "tenants_select_own_or_admin" on public.tenants
  using (((id = get_my_ungani_tenant_id()) OR is_ungani_admin()));

alter policy "tenants_update_admin" on public.tenants
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "ungani_admin_can_manage_tenants_billing" on public.tenants
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "ungani_admin_manage_tenants" on public.tenants
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "ungani_admin_manage_testing_feedback" on public.testing_feedback
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "UNGANI support access can insert (transactions)" on public.transactions
  with check ((is_ungani_admin() AND (EXISTS ( SELECT 1
   FROM ungani_support_access_grants g
  WHERE ((g.tenant_id = transactions.tenant_id) AND (g.status = 'active'::text) AND (g.access_level = 'full_access'::text) AND (g.expires_at IS NOT NULL) AND (g.expires_at > now()))))));

alter policy "UNGANI support access can read (transactions)" on public.transactions
  using ((is_ungani_admin() AND (EXISTS ( SELECT 1
   FROM ungani_support_access_grants g
  WHERE ((g.tenant_id = transactions.tenant_id) AND (g.status = 'active'::text) AND (g.expires_at IS NOT NULL) AND (g.expires_at > now()))))));

alter policy "UNGANI support access can update (transactions)" on public.transactions
  using ((is_ungani_admin() AND (EXISTS ( SELECT 1
   FROM ungani_support_access_grants g
  WHERE ((g.tenant_id = transactions.tenant_id) AND (g.status = 'active'::text) AND (g.access_level = 'full_access'::text) AND (g.expires_at IS NOT NULL) AND (g.expires_at > now()))))))
  with check ((is_ungani_admin() AND (EXISTS ( SELECT 1
   FROM ungani_support_access_grants g
  WHERE ((g.tenant_id = transactions.tenant_id) AND (g.status = 'active'::text) AND (g.access_level = 'full_access'::text) AND (g.expires_at IS NOT NULL) AND (g.expires_at > now()))))));

alter policy "admin_can_read_money_admin_home" on public.transactions
  using (is_ungani_admin());

alter policy "admin_can_read_money_for_reports" on public.transactions
  using (is_ungani_admin());

alter policy "admin_can_read_money_health" on public.transactions
  using (is_ungani_admin());

alter policy "admin_can_read_money_management" on public.transactions
  using (is_ungani_admin());

alter policy "ungani transactions insert own tenant" on public.transactions
  with check (((deleted_at IS NULL) AND can_write_ungani_client_data() AND ((tenant_id = get_my_ungani_current_tenant_id_v16()) OR (tenant_id = get_my_ungani_tenant_id()))));

alter policy "ungani transactions read own tenant active only" on public.transactions
  using (((deleted_at IS NULL) AND ((tenant_id = get_my_ungani_current_tenant_id_v16()) OR (tenant_id = get_my_ungani_tenant_id()) OR is_ungani_admin())));

alter policy "ungani transactions update own tenant active only" on public.transactions
  using (((deleted_at IS NULL) AND can_write_ungani_client_data() AND ((tenant_id = get_my_ungani_current_tenant_id_v16()) OR (tenant_id = get_my_ungani_tenant_id()))))
  with check ((can_write_ungani_client_data() AND ((tenant_id = get_my_ungani_current_tenant_id_v16()) OR (tenant_id = get_my_ungani_tenant_id()))));

alter policy "Admin can view activity logs" on public.ungani_activity_logs
  using ((is_ungani_admin() IS TRUE));

alter policy "Clients can insert own activity logs" on public.ungani_activity_logs
  with check ((tenant_id = get_my_ungani_tenant_id()));

alter policy "Clients can view own activity logs" on public.ungani_activity_logs
  using ((tenant_id = get_my_ungani_tenant_id()));

alter policy "Admins manage support access sessions" on public.ungani_admin_support_access_sessions
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "Admins can read ungani admins" on public.ungani_admins
  using (is_ungani_admin());

alter policy "ungani_approval_requests_owner_select" on public.ungani_approval_requests
  using (((tenant_id = get_my_ungani_tenant_id()) AND is_my_ungani_tenant_owner(tenant_id)));

alter policy "ungani_approval_requests_requester_select" on public.ungani_approval_requests
  using (((tenant_id = get_my_ungani_tenant_id()) AND (requested_by = auth.uid())));

alter policy "Admins can read audit log" on public.ungani_audit_log
  using (is_ungani_admin());

alter policy "Tenant owner can read their tenant's support access audit trail" on public.ungani_audit_log
  using (((action ~~ 'support_access_%'::text) AND (tenant_id = get_my_ungani_tenant_id())));

alter policy "Admins can read billing mismatches" on public.ungani_billing_amount_mismatches
  using (is_ungani_admin());

alter policy "ungani admins can insert billing records" on public.ungani_billing_records
  with check (is_ungani_admin());

alter policy "ungani admins can read billing records" on public.ungani_billing_records
  using (is_ungani_admin());

alter policy "ungani admins can update billing records" on public.ungani_billing_records
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "ungani_billing_reminder_logs_admin_all" on public.ungani_billing_reminder_logs
  using (((to_regprocedure('public.is_ungani_admin()'::text) IS NOT NULL) AND is_ungani_admin()))
  with check (((to_regprocedure('public.is_ungani_admin()'::text) IS NOT NULL) AND is_ungani_admin()));

alter policy "ungani category suggestions insert own tenant" on public.ungani_category_suggestions
  with check (((tenant_id = get_my_ungani_current_tenant_id_v16()) OR (tenant_id = get_my_ungani_tenant_id()) OR is_ungani_admin()));

alter policy "ungani category suggestions read own tenant" on public.ungani_category_suggestions
  using (((tenant_id = get_my_ungani_current_tenant_id_v16()) OR (tenant_id = get_my_ungani_tenant_id()) OR is_ungani_admin()));

alter policy "ungani category suggestions update own tenant" on public.ungani_category_suggestions
  using ((((tenant_id = get_my_ungani_current_tenant_id_v16()) OR (tenant_id = get_my_ungani_tenant_id()) OR is_ungani_admin()) AND can_write_ungani_client_data()))
  with check ((((tenant_id = get_my_ungani_current_tenant_id_v16()) OR (tenant_id = get_my_ungani_tenant_id()) OR is_ungani_admin()) AND can_write_ungani_client_data()));

alter policy "Tenant members can read their channels" on public.ungani_chat_channels
  using ((is_ungani_admin() OR (tenant_id = get_my_ungani_tenant_id())));

alter policy "ungani_class_enrollments_tenant_select" on public.ungani_class_enrollments
  using ((tenant_id = get_my_ungani_tenant_id()));

alter policy "ungani_customer_invoice_items_tenant_select" on public.ungani_customer_invoice_items
  using ((tenant_id = get_my_ungani_tenant_id()));

alter policy "ungani_customer_invoice_payments_tenant_select" on public.ungani_customer_invoice_payments
  using ((tenant_id = get_my_ungani_tenant_id()));

alter policy "ungani_customer_invoices_tenant_select" on public.ungani_customer_invoices
  using ((tenant_id = get_my_ungani_tenant_id()));

alter policy "UNGANI admin can manage email queue" on public.ungani_email_queue
  using ((is_ungani_admin() IS TRUE))
  with check ((is_ungani_admin() IS TRUE));

alter policy "UNGANI clients can view own email queue" on public.ungani_email_queue
  using (((user_id = auth.uid()) OR (tenant_id = get_my_ungani_tenant_id())));

alter policy "ungani_favorites_select" on public.ungani_favorites
  using ((is_ungani_admin() OR (user_id = auth.uid())));

alter policy "Admins can manage all notifications" on public.ungani_notifications
  using ((is_ungani_admin() = true))
  with check ((is_ungani_admin() = true));

alter policy "Admins can read all notifications" on public.ungani_notifications
  using ((is_ungani_admin() = true));

alter policy "Clients can read own notifications" on public.ungani_notifications
  using ((((tenant_id IS NOT NULL) AND (tenant_id = get_my_ungani_tenant_id())) OR ((user_id IS NOT NULL) AND (user_id = auth.uid()))));

alter policy "Clients can update own notifications" on public.ungani_notifications
  using ((((tenant_id IS NOT NULL) AND (tenant_id = get_my_ungani_tenant_id())) OR ((user_id IS NOT NULL) AND (user_id = auth.uid()))))
  with check ((((tenant_id IS NOT NULL) AND (tenant_id = get_my_ungani_tenant_id())) OR ((user_id IS NOT NULL) AND (user_id = auth.uid()))));

alter policy "ungani_notifications_delete_admin_only" on public.ungani_notifications
  using ((is_ungani_admin() = true));

alter policy "ungani_notifications_insert_admin_only" on public.ungani_notifications
  with check ((is_ungani_admin() = true));

alter policy "ungani_notifications_select_secure" on public.ungani_notifications
  using (((is_ungani_admin() = true) OR ((target_type = 'client'::text) AND ((user_id = auth.uid()) OR (tenant_id = get_my_ungani_tenant_id())))));

alter policy "ungani_notifications_update_secure" on public.ungani_notifications
  using (((is_ungani_admin() = true) OR ((target_type = 'client'::text) AND ((user_id = auth.uid()) OR (tenant_id = get_my_ungani_tenant_id())))))
  with check (((is_ungani_admin() = true) OR ((target_type = 'client'::text) AND ((user_id = auth.uid()) OR (tenant_id = get_my_ungani_tenant_id())))));

alter policy "Clients can manage own onboarding progress" on public.ungani_onboarding_progress
  using (((tenant_id = get_my_ungani_tenant_id()) AND (user_id = auth.uid())))
  with check (((tenant_id = get_my_ungani_tenant_id()) AND (user_id = auth.uid())));

alter policy "Clients can view own onboarding progress" on public.ungani_onboarding_progress
  using (((tenant_id = get_my_ungani_tenant_id()) AND (user_id = auth.uid())));

alter policy "ungani_order_fulfillment_events_tenant_select" on public.ungani_order_fulfillment_events
  using ((tenant_id = get_my_ungani_tenant_id()));

alter policy "ungani_order_items_tenant_select" on public.ungani_order_items
  using ((tenant_id = get_my_ungani_tenant_id()));

alter policy "ungani_orders_tenant_select" on public.ungani_orders
  using ((tenant_id = get_my_ungani_tenant_id()));

alter policy "ungani_packages_admin_manage" on public.ungani_packages
  using ((is_ungani_admin() = true))
  with check ((is_ungani_admin() = true));

alter policy "ungani_packages_select_active" on public.ungani_packages
  using (((is_active = true) OR (is_ungani_admin() = true)));

alter policy "ungani_payees_tenant_insert" on public.ungani_payees
  with check ((tenant_id = get_my_ungani_tenant_id()));

alter policy "ungani_payees_tenant_select" on public.ungani_payees
  using ((tenant_id = get_my_ungani_tenant_id()));

alter policy "ungani_payees_tenant_update" on public.ungani_payees
  using ((tenant_id = get_my_ungani_tenant_id()))
  with check ((tenant_id = get_my_ungani_tenant_id()));

alter policy "Admins can manage all ungani payment proofs" on public.ungani_payment_proofs
  using ((is_ungani_admin() IS TRUE))
  with check ((is_ungani_admin() IS TRUE));

alter policy "Clients can insert own ungani payment proofs" on public.ungani_payment_proofs
  with check ((tenant_id = get_my_ungani_tenant_id()));

alter policy "Clients can read own ungani payment proofs" on public.ungani_payment_proofs
  using ((tenant_id = get_my_ungani_tenant_id()));

alter policy "ungani_payments_admin_all" on public.ungani_payments
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "ungani_payments_client_select_own" on public.ungani_payments
  using (((auth.uid() IS NOT NULL) AND (tenant_id = get_my_ungani_tenant_id())));

alter policy "ungani_pos_sale_events_tenant_select" on public.ungani_pos_sale_events
  using ((tenant_id = get_my_ungani_tenant_id()));

alter policy "ungani_price_list_items_tenant_select" on public.ungani_price_list_items
  using ((tenant_id = get_my_ungani_tenant_id()));

alter policy "ungani_price_lists_tenant_select" on public.ungani_price_lists
  using ((tenant_id = get_my_ungani_tenant_id()));

alter policy "ungani_quotation_items_tenant_select" on public.ungani_quotation_items
  using ((tenant_id = get_my_ungani_tenant_id()));

alter policy "ungani_quotations_tenant_select" on public.ungani_quotations
  using ((tenant_id = get_my_ungani_tenant_id()));

alter policy "Admins can manage recently deleted records" on public.ungani_recently_deleted
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "Clients can view own recently deleted records" on public.ungani_recently_deleted
  using ((tenant_id = get_my_ungani_tenant_id()));

alter policy "ungani recurring admin read" on public.ungani_recurring_transactions
  using (is_ungani_admin());

alter policy "ungani recurring delete own tenant" on public.ungani_recurring_transactions
  using ((((tenant_id = get_my_ungani_current_tenant_id_v16()) OR (tenant_id = get_my_ungani_tenant_id())) AND can_write_ungani_client_data()));

alter policy "ungani recurring insert own tenant" on public.ungani_recurring_transactions
  with check ((((tenant_id = get_my_ungani_current_tenant_id_v16()) OR (tenant_id = get_my_ungani_tenant_id())) AND can_write_ungani_client_data()));

alter policy "ungani recurring read own tenant" on public.ungani_recurring_transactions
  using (((tenant_id = get_my_ungani_current_tenant_id_v16()) OR (tenant_id = get_my_ungani_tenant_id()) OR is_ungani_admin()));

alter policy "ungani recurring update own tenant" on public.ungani_recurring_transactions
  using ((((tenant_id = get_my_ungani_current_tenant_id_v16()) OR (tenant_id = get_my_ungani_tenant_id())) AND can_write_ungani_client_data()))
  with check ((((tenant_id = get_my_ungani_current_tenant_id_v16()) OR (tenant_id = get_my_ungani_tenant_id())) AND can_write_ungani_client_data()));

alter policy "ungani smart logs admin read" on public.ungani_smart_action_logs
  using (is_ungani_admin());

alter policy "ungani smart logs system insert" on public.ungani_smart_action_logs
  with check ((is_ungani_admin() OR (tenant_id = get_my_ungani_current_tenant_id_v16()) OR (tenant_id = get_my_ungani_tenant_id())));

alter policy "ungani smart logs tenant read" on public.ungani_smart_action_logs
  using (((tenant_id = get_my_ungani_current_tenant_id_v16()) OR (tenant_id = get_my_ungani_tenant_id())));

alter policy "Admin can manage staff permissions" on public.ungani_staff_section_permissions
  using ((is_ungani_admin() IS TRUE))
  with check ((is_ungani_admin() IS TRUE));

alter policy "Owners can view own staff permissions" on public.ungani_staff_section_permissions
  using ((tenant_id = get_my_ungani_tenant_id()));

alter policy "ungani_stock_movements_select_own_tenant" on public.ungani_stock_movements
  using ((tenant_id = get_my_ungani_tenant_id()));

alter policy "ungani_subscriptions_admin_manage" on public.ungani_subscriptions
  using ((is_ungani_admin() = true))
  with check ((is_ungani_admin() = true));

alter policy "ungani_subscriptions_select_secure" on public.ungani_subscriptions
  using (((is_ungani_admin() = true) OR (tenant_id = get_my_ungani_tenant_id())));

alter policy "Admins can read all support access grants" on public.ungani_support_access_grants
  using (is_ungani_admin());

alter policy "Tenant members can read their own support access grant" on public.ungani_support_access_grants
  using ((tenant_id = get_my_ungani_tenant_id()));

alter policy "Tenant owner can create their own support access grant" on public.ungani_support_access_grants
  with check (((tenant_id = get_my_ungani_tenant_id()) AND (EXISTS ( SELECT 1
   FROM ( SELECT get_my_ungani_staff_access() AS access) s
  WHERE ((((s.access ->> 'is_owner'::text))::boolean IS TRUE) OR (COALESCE(lower((s.access ->> 'role_key'::text)), ''::text) = ANY (ARRAY[''::text, 'guest'::text])))))));

alter policy "Tenant owner can update their own support access grant" on public.ungani_support_access_grants
  using ((tenant_id = get_my_ungani_tenant_id()))
  with check (((tenant_id = get_my_ungani_tenant_id()) AND (EXISTS ( SELECT 1
   FROM ( SELECT get_my_ungani_staff_access() AS access) s
  WHERE ((((s.access ->> 'is_owner'::text))::boolean IS TRUE) OR (COALESCE(lower((s.access ->> 'role_key'::text)), ''::text) = ANY (ARRAY[''::text, 'guest'::text])))))));

alter policy "Admin can manage team members" on public.ungani_team_members
  using ((is_ungani_admin() IS TRUE))
  with check ((is_ungani_admin() IS TRUE));

alter policy "Owners can view own team members" on public.ungani_team_members
  using ((tenant_id = get_my_ungani_tenant_id()));

alter policy "Admins can manage tenant safety settings" on public.ungani_tenant_safety_settings
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "Clients can read own tenant safety settings" on public.ungani_tenant_safety_settings
  using ((tenant_id = get_my_ungani_tenant_id()));

alter policy "ungani_upgrade_requests_admin_all" on public.ungani_upgrade_requests
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "ungani_upgrade_requests_client_insert_own" on public.ungani_upgrade_requests
  with check (((auth.uid() IS NOT NULL) AND (tenant_id = get_my_ungani_tenant_id()) AND (status = 'pending'::text)));

alter policy "ungani_upgrade_requests_client_select_own" on public.ungani_upgrade_requests
  using (((auth.uid() IS NOT NULL) AND (tenant_id = get_my_ungani_tenant_id())));

alter policy "UNGANI admin can manage user branch access" on public.ungani_user_branch_access
  using ((is_ungani_admin() IS TRUE))
  with check ((is_ungani_admin() IS TRUE));

alter policy "UNGANI clients can view own branch access" on public.ungani_user_branch_access
  using ((tenant_id = get_my_ungani_tenant_id()));

alter policy "tenant members can read their tenant's presence" on public.ungani_user_presence
  using ((tenant_id = get_my_ungani_tenant_id()));

alter policy "admin_can_read_upgrade_requests_admin_home" on public.upgrade_requests
  using (is_ungani_admin());

alter policy "admin_can_read_upgrade_requests_charts" on public.upgrade_requests
  using (is_ungani_admin());

alter policy "ungani_admin_can_manage_upgrade_requests" on public.upgrade_requests
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "ungani_admin_manage_upgrade_requests" on public.upgrade_requests
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "ungani_admin_can_manage_users" on public.users
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "ungani_admin_manage_users" on public.users
  using (is_ungani_admin())
  with check (is_ungani_admin());

alter policy "users_insert_admin" on public.users
  with check (is_ungani_admin());

alter policy "users_select_own_or_admin" on public.users
  using (((id = auth.uid()) OR is_ungani_admin()));

alter policy "users_select_self_or_admin" on public.users
  using (((id = auth.uid()) OR (lower(email) = lower(COALESCE((auth.jwt() ->> 'email'::text), ''::text))) OR is_ungani_admin()));

alter policy "users_update_own_or_admin" on public.users
  using (((id = auth.uid()) OR is_ungani_admin()))
  with check (((id = auth.uid()) OR is_ungani_admin()));
