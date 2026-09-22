-- Real-data autocomplete (distinct from browser autofill): suggests
-- REAL, EXISTING values already entered by this tenant as the user
-- types - vehicle plates, person names, phone numbers - reusing the
-- exact same shape as get_my_ungani_customer_name_suggestions() so the
-- new shared client-shared.js helper (wireDatalistSuggestions) can call
-- any of them interchangeably. Read-only, tenant-scoped.

-- Vehicle / asset registration numbers (Logistics Transport field set
-- stores this in business_items.custom_fields->>'registration_number' -
-- no `column` property, so it's JSONB-only; the key simply won't exist
-- for any other business type's items, so this naturally returns
-- nothing for them without needing an item_type filter).
create or replace function public.get_my_ungani_vehicle_plate_suggestions()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_plates jsonb;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  select jsonb_agg(plate order by plate)
  into v_plates
  from (
    select distinct custom_fields->>'registration_number' as plate
    from public.business_items
    where tenant_id = v_tenant_id
      and custom_fields->>'registration_number' is not null
      and trim(custom_fields->>'registration_number') <> ''
  ) distinct_plates;

  return jsonb_build_object('ok', true, 'plates', coalesce(v_plates, '[]'::jsonb));
end;
$function$;

grant execute on function public.get_my_ungani_vehicle_plate_suggestions() to authenticated;

-- Person full names already in this tenant's People records.
create or replace function public.get_my_ungani_person_name_suggestions()
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
    select distinct full_name as name
    from public.client_people
    where tenant_id = v_tenant_id
      and full_name is not null
      and trim(full_name) <> ''
  ) distinct_names;

  return jsonb_build_object('ok', true, 'names', coalesce(v_names, '[]'::jsonb));
end;
$function$;

grant execute on function public.get_my_ungani_person_name_suggestions() to authenticated;

-- Phone numbers already in this tenant's People records (also reused
-- for Money's Payer phone field, and any other phone input later).
create or replace function public.get_my_ungani_person_phone_suggestions()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_phones jsonb;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  select jsonb_agg(phone order by phone)
  into v_phones
  from (
    select distinct phone
    from public.client_people
    where tenant_id = v_tenant_id
      and phone is not null
      and trim(phone) <> ''
  ) distinct_phones;

  return jsonb_build_object('ok', true, 'phones', coalesce(v_phones, '[]'::jsonb));
end;
$function$;

grant execute on function public.get_my_ungani_person_phone_suggestions() to authenticated;
