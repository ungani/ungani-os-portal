-- Lightweight customer-name autocomplete for Quotations/Orders/Customer
-- Invoices. customer_name is deliberately free text on all three
-- (confirmed real schema: ungani_quotations, ungani_orders,
-- ungani_customer_invoices all have tenant_id + customer_name columns)
-- since sales customers are often one-off walk-ins, not tracked People
-- records - this just reduces typo-driven fragmentation (e.g. "John
-- Doe" vs "john doe") by suggesting names already used by this tenant.
-- Read-only, tenant-scoped, same shape as get_my_ungani_payees().

create or replace function public.get_my_ungani_customer_name_suggestions()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_names jsonb;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  select jsonb_agg(name order by name)
  into v_names
  from (
    select distinct customer_name as name
    from (
      select customer_name, tenant_id from public.ungani_quotations
      union all
      select customer_name, tenant_id from public.ungani_orders
      union all
      select customer_name, tenant_id from public.ungani_customer_invoices
    ) combined
    where tenant_id = v_tenant_id
      and customer_name is not null
      and trim(customer_name) <> ''
  ) distinct_names;

  return jsonb_build_object('ok', true, 'customer_names', coalesce(v_names, '[]'::jsonb));
end;
$function$;

grant execute on function public.get_my_ungani_customer_name_suggestions() to authenticated;
