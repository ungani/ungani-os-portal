-- Gap found while building the Settings panel: enable_ungani_pos()
-- only flipped the toggle - it never checked package eligibility, so a
-- Starter-tier tenant could turn it on in Settings and only discover
-- they're blocked later at checkout (record_ungani_pos_sale already
-- enforces the real check, but failing early at Settings is much
-- clearer UX than failing at the point of an actual sale attempt).

create or replace function public.enable_ungani_pos()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_package_key text;
  v_pos_included boolean;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if not public.can_write_ungani_client_data() then
    return jsonb_build_object('ok', false, 'message', 'This account is currently read-only.');
  end if;

  select package_key into v_package_key
  from public.ungani_subscriptions
  where tenant_id = v_tenant_id;

  select coalesce(p.pos_included, false) into v_pos_included
  from public.ungani_packages p
  where p.package_key = v_package_key;

  if coalesce(v_pos_included, false) is not true then
    return jsonb_build_object('ok', false, 'message', 'Your package does not include Point of Sale. Upgrade to Business or Custom to turn this on.');
  end if;

  update public.tenants
  set pos_enabled = true
  where id = v_tenant_id;

  return jsonb_build_object('ok', true, 'message', 'Point of Sale enabled.');
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

grant execute on function public.enable_ungani_pos() to authenticated;

select proname, pg_get_function_identity_arguments(oid) as args
from pg_proc
where proname = 'enable_ungani_pos'
  and pronamespace = 'public'::regnamespace;
