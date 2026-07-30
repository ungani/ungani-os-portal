-- Fixes billing.html's table-split bug (same shape as tonight's earlier
-- ungani_billing_records/ungani_payments fix, confirmed via a clean
-- dependency check - the only hit was notify_admin_on_ungani_upgrade_request,
-- which already correctly targets ungani_upgrade_requests; a harmless
-- substring match, not a real dependency on the orphaned table).
--
-- billing.html reads/writes TWO orphaned, unprefixed tables that nothing
-- else in the app uses:
--   - upgrade_requests (real table: ungani_upgrade_requests)
--   - payments (real table: ungani_payments)
--
-- The read side needs no fix beyond a table-name swap in the JS - billing.html
-- already reads every field through a defensive getField(row, [candidates])
-- fallback pattern, and every real column on both tables already appears
-- in those candidate lists.
--
-- The write side needs more than a table-name swap:
--   - updateUpgradeRequestStatus() already has a safe home to redirect to -
--     admin_update_ungani_upgrade_request, the same RPC admin-upgrade-
--     requests.html (the correct, working page) already uses successfully.
--     No new SQL needed for that one.
--   - updatePaymentStatus() writes {status: status} - wrong column name too
--     (real column is payment_status) - and there is no existing RPC that
--     covers arbitrary status changes (paid/pending/failed); every existing
--     ungani_payments RPC is narrow-purpose (create, mark-paid-only, or
--     proof-acceptance). Every other write to ungani_payments anywhere in
--     this app goes through a SECURITY DEFINER RPC, never a raw client
--     update - strong signal this table has no direct client-facing UPDATE
--     grant. This new RPC covers that gap.

create or replace function public.admin_update_ungani_payment_status(p_payment_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_record public.ungani_payments;
begin
  if not public.is_ungani_admin() then
    return jsonb_build_object(
      'ok', false,
      'message', 'Admin access required.'
    );
  end if;

  update public.ungani_payments
  set
    payment_status = p_status,
    paid_at = case when p_status = 'paid' then coalesce(paid_at, now()) else paid_at end,
    updated_at = now()
  where id = p_payment_id
  returning *
  into v_record;

  if v_record.id is null then
    return jsonb_build_object(
      'ok', false,
      'message', 'Payment record not found.'
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'message', 'Payment status updated.',
    'record', to_jsonb(v_record)
  );
exception
  when others then
    return jsonb_build_object(
      'ok', false,
      'message', sqlerrm
    );
end;
$function$;

grant execute on function public.admin_update_ungani_payment_status(uuid, text) to authenticated;
