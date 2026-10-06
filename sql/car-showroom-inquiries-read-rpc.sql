-- get_my_ungani_inquiries() - the read path for Inquiries, mirroring
-- get_my_ungani_commitments()'s exact shape (RLS select policy on
-- ungani_inquiries has no deleted_at filter, same as commitments/price
-- lists before it - the RPC filters server-side instead of trusting a
-- direct .from() read).

begin;

CREATE OR REPLACE FUNCTION public.get_my_ungani_inquiries()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tenant_id uuid;
  v_rows jsonb;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', i.id,
      'customer_name', i.customer_name,
      'customer_person_id', i.customer_person_id,
      'vehicle_item_id', i.vehicle_item_id,
      'vehicle_name', bi.item_name,
      'source', i.source,
      'follow_up_date', i.follow_up_date,
      'test_drive_at', i.test_drive_at,
      'status', i.status,
      'notes', i.notes,
      'created_at', i.created_at
    )
    order by i.follow_up_date nulls last, i.created_at desc
  ), '[]'::jsonb)
  into v_rows
  from public.ungani_inquiries i
  left join public.business_items bi on bi.id = i.vehicle_item_id
  where i.tenant_id = v_tenant_id
    and i.deleted_at is null;

  return jsonb_build_object('ok', true, 'inquiries', v_rows);
end;
$function$;

revoke all on function public.get_my_ungani_inquiries() from public, anon;
grant execute on function public.get_my_ungani_inquiries() to authenticated;

commit;
