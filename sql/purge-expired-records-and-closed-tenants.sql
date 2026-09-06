-- Enforces the two 30-day promises privacy.html already makes but
-- nothing previously acted on:
--   1. Soft-deleted records past their recover_until (already written by
--      soft_delete_ungani_record on every delete - no new expiry field
--      needed, just a job that reads it).
--   2. Tenants closed via delete_ungani_tenant, 30 days after deleted_at.
--
-- Both are SECURITY DEFINER, callable only by service_role (never
-- authenticated) - the /api/purge-expired-records.js cron endpoint is the
-- only intended caller. Each unit of work (one record, one tenant) runs
-- in its own begin/exception block, which PL/pgSQL implements as an
-- implicit savepoint: a failure partway through one row/tenant rolls back
-- only that row's changes (including its own audit-log insert, so a
-- failed purge never leaves a misleading "purged" log entry) and the loop
-- continues - one bad row can't abort the whole run or corrupt other
-- tenants' data.

create or replace function public.purge_ungani_expired_records()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_row record;
  v_still_deleted boolean;
  v_purged_count integer := 0;
  v_skipped_count integer := 0;
  v_error_count integer := 0;
  v_errors jsonb := '[]'::jsonb;
begin
  for v_row in
    select id, tenant_id, source_table, source_record_id, record_snapshot, deleted_at
    from public.ungani_recently_deleted
    where recover_until < now()
    order by recover_until asc
    limit 500
  loop
    begin
      -- restore_my_ungani_deleted_record_v2 clears deleted_at on the
      -- source row when a user restores it, but never touches or removes
      -- this staging row - so a stale row here does not necessarily mean
      -- the record is still deleted. Re-check the live state before
      -- destroying anything.
      execute format(
        'select exists (select 1 from public.%I where id = $1 and deleted_at is not null)',
        v_row.source_table
      )
      using v_row.source_record_id
      into v_still_deleted;

      if not v_still_deleted then
        delete from public.ungani_recently_deleted where id = v_row.id;
        v_skipped_count := v_skipped_count + 1;
        continue;
      end if;

      insert into public.ungani_audit_log (
        actor_email, tenant_id, action, entity_type, entity_id, description, metadata
      )
      values (
        'system:purge-cron',
        v_row.tenant_id,
        'record_purged',
        v_row.source_table,
        v_row.source_record_id::text,
        'Record permanently deleted after 30 days in Recently Deleted.',
        jsonb_build_object(
          'source_table', v_row.source_table,
          'record_id', v_row.source_record_id,
          'deleted_at', v_row.deleted_at,
          'record_snapshot', v_row.record_snapshot
        )
      );

      execute format('delete from public.%I where id = $1', v_row.source_table)
      using v_row.source_record_id;

      delete from public.ungani_recently_deleted where id = v_row.id;

      v_purged_count := v_purged_count + 1;
    exception
      when others then
        v_error_count := v_error_count + 1;
        v_errors := v_errors || jsonb_build_array(
          jsonb_build_object(
            'recently_deleted_id', v_row.id,
            'source_table', v_row.source_table,
            'source_record_id', v_row.source_record_id,
            'error', sqlerrm
          )
        );
    end;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'purged', v_purged_count,
    'skipped_already_restored_or_purged', v_skipped_count,
    'errors', v_error_count,
    'error_detail', v_errors
  );
end;
$function$;

grant execute on function public.purge_ungani_expired_records() to service_role;

create or replace function public.purge_ungani_closed_tenants()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant record;
  v_purged_count integer := 0;
  v_error_count integer := 0;
  v_errors jsonb := '[]'::jsonb;
  v_counts jsonb;
  v_n_chat_messages integer;
  v_n_chat_channels integer;
  v_n_mpesa integer;
  v_n_activity integer;
  v_n_comments integer;
  v_n_stock_movements integer;
begin
  for v_tenant in
    select id, business_name, company_name, deleted_at, delete_reason
    from public.tenants
    where deleted_at is not null
      and deleted_at < now() - interval '30 days'
    order by deleted_at asc
    limit 50
  loop
    begin
      -- team_chat_messages.channel_id -> ungani_chat_channels' delete
      -- rule wasn't confirmed (not one of the 7 checked NO ACTION FKs),
      -- so clear messages before channels defensively rather than assume.
      delete from public.team_chat_messages where tenant_id = v_tenant.id;
      get diagnostics v_n_chat_messages = row_count;

      -- The 5 confirmed NO ACTION FKs to tenants (plus stock_movements'
      -- second NO ACTION FK to business_items, which resolves itself once
      -- these rows are gone - business_items.tenant_id cascades cleanly).
      delete from public.ungani_chat_channels where tenant_id = v_tenant.id;
      get diagnostics v_n_chat_channels = row_count;

      delete from public.ungani_mpesa_transactions where tenant_id = v_tenant.id;
      get diagnostics v_n_mpesa = row_count;

      delete from public.ungani_record_activity where tenant_id = v_tenant.id;
      get diagnostics v_n_activity = row_count;

      delete from public.ungani_record_comments where tenant_id = v_tenant.id;
      get diagnostics v_n_comments = row_count;

      delete from public.ungani_stock_movements where tenant_id = v_tenant.id;
      get diagnostics v_n_stock_movements = row_count;

      v_counts := jsonb_build_object(
        'team_chat_messages', v_n_chat_messages,
        'ungani_chat_channels', v_n_chat_channels,
        'ungani_mpesa_transactions', v_n_mpesa,
        'ungani_record_activity', v_n_activity,
        'ungani_record_comments', v_n_comments,
        'ungani_stock_movements', v_n_stock_movements
      );

      insert into public.ungani_audit_log (
        actor_email, tenant_id, action, entity_type, entity_id, description, metadata
      )
      values (
        'system:purge-cron',
        v_tenant.id,
        'tenant_purged',
        'tenants',
        v_tenant.id::text,
        'Tenant and all owned data permanently deleted, 30 days after account closure.',
        jsonb_build_object(
          'business_name', coalesce(v_tenant.business_name, v_tenant.company_name),
          'closed_at', v_tenant.deleted_at,
          'delete_reason', v_tenant.delete_reason,
          'manually_cleared_rows', v_counts
        )
      );

      -- Every other owned table (transactions, tasks, business_items,
      -- ungani_orders/quotations/customer_invoices/price_lists, their line
      -- items, client_people, documents, business_records, business_events,
      -- support_issues, etc.) has tenant_id -> tenants(id) on delete
      -- cascade, confirmed via the live FK graph - this one delete removes
      -- everything else automatically.
      delete from public.tenants where id = v_tenant.id;

      v_purged_count := v_purged_count + 1;
    exception
      when others then
        v_error_count := v_error_count + 1;
        v_errors := v_errors || jsonb_build_array(
          jsonb_build_object(
            'tenant_id', v_tenant.id,
            'business_name', coalesce(v_tenant.business_name, v_tenant.company_name),
            'error', sqlerrm
          )
        );
    end;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'purged', v_purged_count,
    'errors', v_error_count,
    'error_detail', v_errors
  );
end;
$function$;

grant execute on function public.purge_ungani_closed_tenants() to service_role;
