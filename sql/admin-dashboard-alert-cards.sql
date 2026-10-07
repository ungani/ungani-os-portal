-- Admin dashboard alert cards: one combined RPC, 6 live counts, each
-- excluding is_test tenants. Real columns confirmed from existing live
-- code, not guessed: registrations.status ('pending'/null = waiting),
-- ungani_subscriptions.trial_end_at/subscription_ends_at/
-- subscription_status, ungani_payment_proofs.proof_status
-- ('submitted'/'reviewing' = to confirm, via admin_get_ungani_payment_proofs'
-- own filter logic), ungani_email_queue.send_status/resolved_at (the
-- resolved_at column just added this session), partner_commissions.status
-- ('owed' = payout due, from sql/partner-referral-system.sql).

create or replace function public.admin_get_ungani_dashboard_alerts()
returns table (
  registrations_waiting integer,
  trials_ending_this_week integer,
  payments_to_confirm integer,
  subscriptions_overdue integer,
  storage_over_80pct integer,
  failed_emails_unresolved integer,
  partner_payouts_due integer
)
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_ungani_admin() then
    raise exception 'Access denied: admin only';
  end if;

  return query
    select
      (
        select count(*)::integer
        from public.registrations r
        left join public.tenants t on t.id = r.tenant_id
        where (r.status = 'pending' or r.status is null)
          and coalesce(t.is_test, false) = false
      ) as registrations_waiting,

      (
        select count(*)::integer
        from public.ungani_subscriptions s
        join public.tenants t on t.id = s.tenant_id
        where s.subscription_status = 'trial'
          and s.trial_end_at is not null
          and s.trial_end_at between now() and now() + interval '7 days'
          and coalesce(t.is_test, false) = false
      ) as trials_ending_this_week,

      (
        select count(*)::integer
        from public.ungani_payment_proofs pp
        join public.tenants t on t.id = pp.tenant_id
        where pp.proof_status in ('submitted', 'reviewing')
          and coalesce(t.is_test, false) = false
      ) as payments_to_confirm,

      (
        select count(*)::integer
        from public.ungani_subscriptions s
        join public.tenants t on t.id = s.tenant_id
        where s.subscription_status = 'active'
          and s.subscription_ends_at is not null
          and s.subscription_ends_at < now()
          and coalesce(t.is_test, false) = false
      ) as subscriptions_overdue,

      (
        select count(*)::integer
        from public.admin_get_ungani_storage_usage() su
        where su.percent_used >= 80
      ) as storage_over_80pct,

      (
        select count(*)::integer
        from public.ungani_email_queue eq
        left join public.tenants t on t.id = eq.tenant_id
        where eq.send_status = 'failed'
          and eq.resolved_at is null
          and coalesce(t.is_test, false) = false
      ) as failed_emails_unresolved,

      (
        select count(distinct pc.partner_id)::integer
        from public.partner_commissions pc
        left join public.tenants t on t.id = pc.tenant_id
        where pc.status = 'owed'
          and coalesce(t.is_test, false) = false
      ) as partner_payouts_due;
end;
$function$;

revoke all on function public.admin_get_ungani_dashboard_alerts() from public, anon;
grant execute on function public.admin_get_ungani_dashboard_alerts() to authenticated;

-- VERIFICATION
select
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'admin_get_ungani_dashboard_alerts') as overload_count,
  has_function_privilege('public', 'public.admin_get_ungani_dashboard_alerts()', 'execute') as public_can_execute,
  has_function_privilege('anon', 'public.admin_get_ungani_dashboard_alerts()', 'execute') as anon_can_execute,
  has_function_privilege('authenticated', 'public.admin_get_ungani_dashboard_alerts()', 'execute') as authenticated_can_execute;

select * from public.admin_get_ungani_dashboard_alerts();
