-- =====================================================================
-- Item 1 discovery, single-result version. Your SQL client only shows
-- the last statement's result when a script has many separate SELECTs -
-- this rewrites the whole thing as ONE query returning ONE row/column
-- (a big jsonb object), so there is exactly one result set to paste back
-- no matter what the client does. Read-only - no writes.
-- =====================================================================
select jsonb_build_object(

  'functions', (
    select jsonb_agg(jsonb_build_object('name', p.proname, 'definition', pg_get_functiondef(p.oid)))
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'set_ungani_subscription_period_from_payment',
        'calculate_ungani_subscription_amount',
        'admin_accept_ungani_payment_proof_and_mark_paid',
        'admin_update_ungani_payment_status',
        'mark_admin_ungani_billing_record_paid',
        'admin_update_ungani_subscription',
        'queue_ungani_payment_confirmation_email',
        'get_admin_ungani_package_catalog',
        'get_ungani_active_packages',
        'admin_get_ungani_partners_overview',
        'admin_create_ungani_partner',
        'client_submit_ungani_payment_proof',
        'admin_update_ungani_payment_proof',
        'get_admin_ungani_billing_page_data',
        'create_admin_ungani_billing_record',
        'get_admin_ungani_launch_dashboard_snapshot_fast'
      )
  ),

  'commission_related_functions', (
    select jsonb_agg(jsonb_build_object('name', p.proname, 'definition', pg_get_functiondef(p.oid)))
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (p.proname ilike '%commission%' or pg_get_functiondef(p.oid) ilike '%commission%')
  ),

  'other_callers_of_set_subscription_period', (
    select jsonb_agg(p.proname)
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and pg_get_functiondef(p.oid) ilike '%set_ungani_subscription_period_from_payment%'
      and p.proname <> 'set_ungani_subscription_period_from_payment'
  ),

  'table_columns', (
    select jsonb_agg(jsonb_build_object(
      'table', table_name, 'column', column_name, 'type', data_type,
      'nullable', is_nullable, 'default', column_default
    ) order by table_name, ordinal_position)
    from information_schema.columns
    where table_schema = 'public'
      and table_name in (
        'ungani_payments', 'ungani_subscriptions', 'ungani_mpesa_transactions',
        'tenants', 'partner_commissions', 'ungani_payment_proofs',
        'ungani_billing_records', 'ungani_smart_action_logs'
      )
  ),

  'package_table_columns', (
    select jsonb_agg(jsonb_build_object(
      'table', table_name, 'column', column_name, 'type', data_type,
      'nullable', is_nullable, 'default', column_default
    ) order by table_name, ordinal_position)
    from information_schema.columns
    where table_schema = 'public'
      and table_name ilike '%package%'
  ),

  'constraints', (
    select jsonb_agg(jsonb_build_object(
      'table', t.table_name, 'constraint', t.constraint_name, 'type', t.constraint_type,
      'columns', t.cols
    ))
    from (
      select tc.table_name, tc.constraint_name, tc.constraint_type,
        string_agg(kcu.column_name, ', ' order by kcu.ordinal_position) as cols
      from information_schema.table_constraints tc
      join information_schema.key_column_usage kcu
        on kcu.constraint_name = tc.constraint_name and kcu.table_schema = tc.table_schema
      where tc.table_schema = 'public'
        and tc.table_name in ('ungani_payments', 'ungani_subscriptions', 'ungani_mpesa_transactions', 'partner_commissions')
      group by tc.table_name, tc.constraint_name, tc.constraint_type
    ) t
  ),

  'indexes', (
    select jsonb_agg(jsonb_build_object('table', tablename, 'index', indexname, 'def', indexdef))
    from pg_indexes
    where schemaname = 'public'
      and tablename in ('ungani_payments', 'ungani_subscriptions', 'ungani_mpesa_transactions', 'partner_commissions')
  ),

  'rls_policies', (
    select jsonb_agg(jsonb_build_object(
      'table', tablename, 'policy', policyname, 'cmd', cmd, 'qual', qual, 'with_check', with_check
    ))
    from pg_policies
    where schemaname = 'public'
      and tablename in ('ungani_payments', 'ungani_subscriptions', 'ungani_mpesa_transactions', 'partner_commissions', 'tenants')
  ),

  'function_grants', (
    select jsonb_agg(jsonb_build_object(
      'name', p.proname,
      'anon_can_execute', has_function_privilege('anon', p.oid, 'execute'),
      'authenticated_can_execute', has_function_privilege('authenticated', p.oid, 'execute'),
      'public_can_execute', has_function_privilege('public', p.oid, 'execute')
    ))
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'set_ungani_subscription_period_from_payment',
        'calculate_ungani_subscription_amount',
        'admin_accept_ungani_payment_proof_and_mark_paid',
        'admin_update_ungani_payment_status',
        'mark_admin_ungani_billing_record_paid'
      )
  ),

  'payments_with_null_package_key_count', (
    select count(*) from public.ungani_payments where package_key is null
  ),

  'payments_with_null_package_key_sample', (
    select jsonb_agg(to_jsonb(x)) from (
      select id, tenant_id, package_key, amount, payment_status, paid_at, notes
      from public.ungani_payments
      where package_key is null
      order by paid_at desc nulls last
      limit 10
    ) x
  ),

  'duplicate_payment_references', (
    select jsonb_agg(to_jsonb(x)) from (
      select payment_reference, count(*) as occurrences
      from public.ungani_payments
      where payment_reference is not null
      group by payment_reference
      having count(*) > 1
      order by count(*) desc
      limit 20
    ) x
  ),

  'subscription_sample', (
    select jsonb_agg(to_jsonb(x)) from (
      select * from public.ungani_subscriptions
      order by updated_at desc nulls last
      limit 5
    ) x
  ),

  'partner_commissions_sample', (
    select jsonb_agg(to_jsonb(x)) from (
      select * from public.partner_commissions limit 10
    ) x
  ),

  'partner_commissions_row_count', (
    select count(*) from public.partner_commissions
  )

) as discovery_result;
