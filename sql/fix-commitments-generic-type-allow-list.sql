-- Approved fix: owner_upsert_ungani_commitment()'s own validation line
-- is the ONLY thing blocking a save for any of the 15 (of 19) business
-- types outside Real Estate/Gym/Security/Cleaning - confirmed there is
-- NO CHECK constraint on ungani_commitments.commitment_type at all (see
-- reports/invoice-stock-check.md Part C: zero rows). my-commitments.html's
-- commitmentTypeForTenant() already falls back to "generic" for every
-- unmapped business type and has a full COMMITMENT_VOCAB.generic labelset
-- ready to render - the RPC just never accepted the value.
--
-- Built from the LIVE body (pg_get_functiondef, pasted by Chris) - every
-- line is byte-identical except the one allow-list addition below. Also
-- adds an explicit revoke public/anon + grant authenticated, matching
-- this project's standing grant-hygiene pattern (same as
-- sync_ungani_invoice_stock and every RPC written this session).

CREATE OR REPLACE FUNCTION public.owner_upsert_ungani_commitment(p_commitment_id uuid DEFAULT NULL::uuid, p_commitment_type text DEFAULT NULL::text, p_person_id uuid DEFAULT NULL::uuid, p_linked_item_id uuid DEFAULT NULL::uuid, p_plan_name text DEFAULT NULL::text, p_amount numeric DEFAULT NULL::numeric, p_billing_frequency text DEFAULT 'monthly'::text, p_start_date date DEFAULT NULL::date, p_end_date date DEFAULT NULL::date, p_status text DEFAULT 'active'::text, p_auto_renew boolean DEFAULT false, p_section_label text DEFAULT NULL::text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tenant_id uuid;
  v_commitment_id uuid;
  v_clean_type text;
  v_clean_status text;
  v_person_tenant_check uuid;
  v_item_tenant_check uuid;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  v_clean_type := lower(trim(coalesce(p_commitment_type, '')));
  if v_clean_type not in ('lease', 'membership', 'service_contract', 'generic') then
    return jsonb_build_object('ok', false, 'message', 'A valid commitment type is required.');
  end if;

  v_clean_status := lower(trim(coalesce(p_status, 'active')));
  if v_clean_status not in ('active', 'terminated', 'frozen') then
    v_clean_status := 'active';
  end if;

  if p_person_id is not null then
    select id into v_person_tenant_check
    from public.client_people
    where id = p_person_id and tenant_id = v_tenant_id;

    if v_person_tenant_check is null then
      return jsonb_build_object('ok', false, 'message', 'Person not found in your workspace.');
    end if;
  end if;

  if p_linked_item_id is not null then
    select id into v_item_tenant_check
    from public.business_items
    where id = p_linked_item_id and tenant_id = v_tenant_id;

    if v_item_tenant_check is null then
      return jsonb_build_object('ok', false, 'message', 'Linked unit/site not found in your workspace.');
    end if;
  end if;

  if p_commitment_id is not null then
    update public.ungani_commitments
    set commitment_type = v_clean_type,
        person_id = p_person_id,
        linked_item_id = p_linked_item_id,
        plan_name = nullif(trim(coalesce(p_plan_name, '')), ''),
        amount = p_amount,
        billing_frequency = coalesce(nullif(trim(coalesce(p_billing_frequency, '')), ''), 'monthly'),
        start_date = p_start_date,
        end_date = p_end_date,
        status = v_clean_status,
        auto_renew = coalesce(p_auto_renew, false),
        section_label = nullif(trim(coalesce(p_section_label, '')), ''),
        notes = nullif(trim(coalesce(p_notes, '')), ''),
        updated_at = now()
    where id = p_commitment_id and tenant_id = v_tenant_id
    returning id into v_commitment_id;

    if v_commitment_id is null then
      return jsonb_build_object('ok', false, 'message', 'Commitment not found.');
    end if;
  else
    insert into public.ungani_commitments (
      tenant_id, commitment_type, person_id, linked_item_id, plan_name, amount,
      billing_frequency, start_date, end_date, status, auto_renew, section_label,
      notes, created_by
    )
    values (
      v_tenant_id, v_clean_type, p_person_id, p_linked_item_id,
      nullif(trim(coalesce(p_plan_name, '')), ''), p_amount,
      coalesce(nullif(trim(coalesce(p_billing_frequency, '')), ''), 'monthly'),
      p_start_date, p_end_date, v_clean_status, coalesce(p_auto_renew, false),
      nullif(trim(coalesce(p_section_label, '')), ''), nullif(trim(coalesce(p_notes, '')), ''),
      auth.uid()
    )
    returning id into v_commitment_id;
  end if;
return jsonb_build_object('ok', true, 'id', v_commitment_id, 'commitment_id', v_commitment_id);
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

revoke all on function public.owner_upsert_ungani_commitment(
  uuid, text, uuid, uuid, text, numeric, text, date, date, text, boolean, text, text
) from public, anon;

grant execute on function public.owner_upsert_ungani_commitment(
  uuid, text, uuid, uuid, text, numeric, text, date, date, text, boolean, text, text
) to authenticated;

-- Commits the migration above as its own transaction - see
-- sql/fix-partner-payout-functions-live-confirmed.sql's header comment
-- for why this is required when DDL and a rolled-back test are pasted
-- together as one script.
commit;
