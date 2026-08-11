-- Deletes the "UNGANI QA Test - DELETE ME" tenant and every row tied to
-- it, in dependency-safe order. Safety-checked: re-derives the tenant id
-- by name and asserts it matches the confirmed id from the verify pass
-- (sql/qa-test-tenant-cleanup-verify.sql), then asserts every table's
-- row count matches exactly what was confirmed before deleting anything
-- - if the live data had drifted since the verify query ran (e.g. a
-- stray row appeared), this aborts with an exception and deletes
-- nothing, rather than silently removing more than was reviewed. All
-- deletes are inside one DO block, so it's fully atomic - either
-- everything below is removed, or (on any mismatch/error) nothing is.
--
-- Order: billing_reminder_logs and payment_proofs first (both carry a
-- payment_id pointing at ungani_payments), then payments, then every
-- other tenant-scoped child table, then users (references both tenants
-- and auth.users), then tenants itself last among tenant-scoped tables,
-- then the registrations row (linked by id, not tenant_id).
--
-- auth.users is deliberately NOT touched by this script - deleted
-- separately via the Supabase Dashboard (Authentication > Users), per
-- Supabase's own guidance that raw SQL against auth.users isn't the
-- guaranteed-clean path (identities/sessions/refresh tokens/MFA
-- factors all need to be handled consistently with Supabase's own
-- internals).
--
-- Confirmed run 2026-08-12: all 12 tables verified at count=0 afterward.

do $$
declare
  v_tenant_id uuid;
  v_expected_tenant_id uuid := '123b3687-02f7-45fb-a059-32ec49c3e55e';
  v_registration_id uuid := 'f41adb4f-a6f3-4297-9e74-5d9f613b8c79';
  v_count bigint;
begin
  select id into v_tenant_id from public.tenants where business_name = 'UNGANI QA Test — DELETE ME';

  if v_tenant_id is null then
    raise exception 'Tenant not found by name - aborting, nothing deleted.';
  end if;

  if v_tenant_id <> v_expected_tenant_id then
    raise exception 'Tenant id mismatch (found %, expected %) - aborting, nothing deleted.', v_tenant_id, v_expected_tenant_id;
  end if;

  -- Assert every table's count still matches what was confirmed.
  select count(*) into v_count from public.team_chat_messages where tenant_id = v_tenant_id;
  if v_count <> 1 then raise exception 'team_chat_messages count changed (now %, expected 1) - aborting.', v_count; end if;

  select count(*) into v_count from public.tenant_sections where tenant_id = v_tenant_id;
  if v_count <> 4 then raise exception 'tenant_sections count changed (now %, expected 4) - aborting.', v_count; end if;

  select count(*) into v_count from public.ungani_billing_records where tenant_id = v_tenant_id;
  if v_count <> 2 then raise exception 'ungani_billing_records count changed (now %, expected 2) - aborting.', v_count; end if;

  select count(*) into v_count from public.ungani_billing_reminder_logs where tenant_id = v_tenant_id;
  if v_count <> 2 then raise exception 'ungani_billing_reminder_logs count changed (now %, expected 2) - aborting.', v_count; end if;

  select count(*) into v_count from public.ungani_email_queue where tenant_id = v_tenant_id;
  if v_count <> 5 then raise exception 'ungani_email_queue count changed (now %, expected 5) - aborting.', v_count; end if;

  select count(*) into v_count from public.ungani_notifications where tenant_id = v_tenant_id;
  if v_count <> 10 then raise exception 'ungani_notifications count changed (now %, expected 10) - aborting.', v_count; end if;

  select count(*) into v_count from public.ungani_payment_proofs where tenant_id = v_tenant_id;
  if v_count <> 1 then raise exception 'ungani_payment_proofs count changed (now %, expected 1) - aborting.', v_count; end if;

  select count(*) into v_count from public.ungani_payments where tenant_id = v_tenant_id;
  if v_count <> 3 then raise exception 'ungani_payments count changed (now %, expected 3) - aborting.', v_count; end if;

  select count(*) into v_count from public.ungani_subscriptions where tenant_id = v_tenant_id;
  if v_count <> 1 then raise exception 'ungani_subscriptions count changed (now %, expected 1) - aborting.', v_count; end if;

  select count(*) into v_count from public.users where tenant_id = v_tenant_id;
  if v_count <> 1 then raise exception 'users count changed (now %, expected 1) - aborting.', v_count; end if;

  select count(*) into v_count from public.registrations where id = v_registration_id;
  if v_count <> 1 then raise exception 'registrations row not found by confirmed id - aborting.'; end if;

  -- All checks passed - delete in dependency-safe order.

  delete from public.ungani_billing_reminder_logs where tenant_id = v_tenant_id;
  delete from public.ungani_payment_proofs where tenant_id = v_tenant_id;
  delete from public.ungani_payments where tenant_id = v_tenant_id;
  delete from public.ungani_billing_records where tenant_id = v_tenant_id;
  delete from public.ungani_subscriptions where tenant_id = v_tenant_id;
  delete from public.ungani_email_queue where tenant_id = v_tenant_id;
  delete from public.ungani_notifications where tenant_id = v_tenant_id;
  delete from public.team_chat_messages where tenant_id = v_tenant_id;
  delete from public.tenant_sections where tenant_id = v_tenant_id;
  delete from public.users where tenant_id = v_tenant_id;
  delete from public.tenants where id = v_tenant_id;
  delete from public.registrations where id = v_registration_id;

  raise notice 'Deleted tenant % and all related rows successfully.', v_tenant_id;
end $$;

-- Verification - every one of these should return 0 rows. Confirmed 2026-08-12.
select 'tenants' as tbl, count(*) from public.tenants where id = '123b3687-02f7-45fb-a059-32ec49c3e55e'
union all select 'registrations', count(*) from public.registrations where id = 'f41adb4f-a6f3-4297-9e74-5d9f613b8c79'
union all select 'users', count(*) from public.users where tenant_id = '123b3687-02f7-45fb-a059-32ec49c3e55e'
union all select 'ungani_subscriptions', count(*) from public.ungani_subscriptions where tenant_id = '123b3687-02f7-45fb-a059-32ec49c3e55e'
union all select 'ungani_payments', count(*) from public.ungani_payments where tenant_id = '123b3687-02f7-45fb-a059-32ec49c3e55e'
union all select 'ungani_payment_proofs', count(*) from public.ungani_payment_proofs where tenant_id = '123b3687-02f7-45fb-a059-32ec49c3e55e'
union all select 'ungani_billing_records', count(*) from public.ungani_billing_records where tenant_id = '123b3687-02f7-45fb-a059-32ec49c3e55e'
union all select 'ungani_billing_reminder_logs', count(*) from public.ungani_billing_reminder_logs where tenant_id = '123b3687-02f7-45fb-a059-32ec49c3e55e'
union all select 'ungani_email_queue', count(*) from public.ungani_email_queue where tenant_id = '123b3687-02f7-45fb-a059-32ec49c3e55e'
union all select 'ungani_notifications', count(*) from public.ungani_notifications where tenant_id = '123b3687-02f7-45fb-a059-32ec49c3e55e'
union all select 'team_chat_messages', count(*) from public.team_chat_messages where tenant_id = '123b3687-02f7-45fb-a059-32ec49c3e55e'
union all select 'tenant_sections', count(*) from public.tenant_sections where tenant_id = '123b3687-02f7-45fb-a059-32ec49c3e55e';
