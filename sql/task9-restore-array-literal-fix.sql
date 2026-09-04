-- ============================================================
-- Fix: restore_my_ungani_deleted_record_v2() failed on every call
-- with "malformed array literal: 'restored_at = now()'" (and
-- similarly for the other 3 dynamic SET fragments).
--
-- Root cause: `v_set_parts := v_set_parts || 'some text';` is
-- ambiguous to Postgres between text[] || text[] (cast the string to
-- an array literal) and text[] || text (append as a single element).
-- Postgres picked the array-literal-cast interpretation, and a plain
-- string like 'restored_at = now()' is not valid array literal
-- syntax (no curly braces), so it failed at runtime on every restore
-- attempt, for every table.
--
-- ONLY CHANGE: the 4 lines appending a plain string to v_set_parts
-- now wrap that string in ARRAY[...], forcing unambiguous
-- array-to-array concatenation. Every other line is unchanged from
-- the source provided.
-- ============================================================

CREATE OR REPLACE FUNCTION public.restore_my_ungani_deleted_record_v2(p_table_name text, p_record_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tenant_id uuid := null;
  v_table text := lower(trim(coalesce(p_table_name, '')));
  v_allowed_tables text[] := array[
    'transactions',
    'tasks',
    'business_items',
    'business_records',
    'documents',
    'support_issues',
    'client_people',
    'business_events'
  ];

  v_table_exists boolean := false;
  v_has_id boolean := false;
  v_has_tenant_id boolean := false;
  v_has_deleted_at boolean := false;
  v_has_restored_at boolean := false;
  v_has_restored_by boolean := false;
  v_has_delete_reason boolean := false;
  v_has_updated_at boolean := false;

  v_can_write boolean := false;
  v_set_parts text[] := array['deleted_at = null'];
  v_set_sql text;
  v_sql text;
  v_restored_id text := null;
  v_log_result jsonb := null;
begin
  v_tenant_id := public.get_my_ungani_current_tenant_id_v16();

  if v_tenant_id is null then
    return jsonb_build_object(
      'ok', false,
      'message', 'No tenant found for this user.'
    );
  end if;

  if v_table is null or v_table = '' or not (v_table = any(v_allowed_tables)) then
    return jsonb_build_object(
      'ok', false,
      'message', 'This table is not allowed for restore.',
      'table_name', v_table
    );
  end if;

  begin
    v_can_write := coalesce(public.can_write_ungani_client_data(), false);
  exception
    when others then
      v_can_write := false;
  end;

  if v_can_write is not true then
    return jsonb_build_object(
      'ok', false,
      'message', 'Restore is blocked because this account is currently read-only or does not have write access.'
    );
  end if;

  select exists (
    select 1
    from information_schema.tables
    where table_schema = 'public'
      and table_name = v_table
  )
  into v_table_exists;

  if not v_table_exists then
    return jsonb_build_object(
      'ok', false,
      'message', 'Table does not exist.',
      'table_name', v_table
    );
  end if;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = v_table
      and column_name = 'id'
  )
  into v_has_id;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = v_table
      and column_name = 'tenant_id'
  )
  into v_has_tenant_id;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = v_table
      and column_name = 'deleted_at'
  )
  into v_has_deleted_at;

  if not (v_has_id and v_has_tenant_id and v_has_deleted_at) then
    return jsonb_build_object(
      'ok', false,
      'message', 'This table is not restore-ready.',
      'table_name', v_table,
      'has_id', v_has_id,
      'has_tenant_id', v_has_tenant_id,
      'has_deleted_at', v_has_deleted_at
    );
  end if;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = v_table
      and column_name = 'restored_at'
  )
  into v_has_restored_at;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = v_table
      and column_name = 'restored_by'
  )
  into v_has_restored_by;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = v_table
      and column_name = 'delete_reason'
  )
  into v_has_delete_reason;

  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = v_table
      and column_name = 'updated_at'
  )
  into v_has_updated_at;

  if v_has_restored_at then
    v_set_parts := v_set_parts || ARRAY['restored_at = now()'];
  end if;

  if v_has_restored_by then
    v_set_parts := v_set_parts || ARRAY['restored_by = auth.uid()'];
  end if;

  if v_has_delete_reason then
    v_set_parts := v_set_parts || ARRAY['delete_reason = null'];
  end if;

  if v_has_updated_at then
    v_set_parts := v_set_parts || ARRAY['updated_at = now()'];
  end if;

  v_set_sql := array_to_string(v_set_parts, ', ');

  v_sql := format(
    'update public.%I
     set %s
     where id::text = $1
       and tenant_id = $2
       and deleted_at is not null
     returning id::text',
    v_table,
    v_set_sql
  );

  execute v_sql
  using p_record_id, v_tenant_id
  into v_restored_id;

  if v_restored_id is null then
    return jsonb_build_object(
      'ok', false,
      'message', 'Record was not found, does not belong to this tenant, or is already restored.',
      'table_name', v_table,
      'record_id', p_record_id
    );
  end if;

  begin
    v_log_result := public.log_ungani_smart_action(
      v_tenant_id,
      'recently_deleted_restore_v2',
      'Recently deleted record restored',
      'A deleted record was restored from the Recently Deleted v2 workflow.',
      v_table,
      v_restored_id,
      'completed',
      jsonb_build_object(
        'table_name', v_table,
        'record_id', v_restored_id,
        'restored_at', now()
      )
    );
  exception
    when others then
      v_log_result := jsonb_build_object(
        'ok', false,
        'message', sqlerrm
      );
  end;

  return jsonb_build_object(
    'ok', true,
    'message', 'Record restored successfully.',
    'table_name', v_table,
    'record_id', v_restored_id,
    'log_result', v_log_result,
    'restored_at', now()
  );
exception
  when others then
    return jsonb_build_object(
      'ok', false,
      'message', sqlerrm
    );
end;
$function$;

-- ============================================================
-- VERIFICATION - run and paste back the output.
-- ============================================================

select pg_get_functiondef(p.oid) like '%ARRAY[''restored_at = now()'']%'
    and pg_get_functiondef(p.oid) like '%ARRAY[''restored_by = auth.uid()'']%'
    and pg_get_functiondef(p.oid) like '%ARRAY[''delete_reason = null'']%'
    and pg_get_functiondef(p.oid) like '%ARRAY[''updated_at = now()'']%'
  as array_literal_fix_applied
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'restore_my_ungani_deleted_record_v2';
