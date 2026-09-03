-- Fixes a real data-loss risk found during Task 1 live testing: my-money.html's
-- "Paid To" dropdown is populated by get_my_ungani_payees(), which only
-- returns payees with status = 'active' (confirmed via its literal
-- source, sql/payee-tracking.sql). If a Money record is linked to a
-- payee who is later deactivated, reopening that record's edit form
-- finds no matching <option> for the stored related_payee_id, so the
-- dropdown silently falls back to "Not linked to anyone" - and if the
-- owner then re-saves the record without noticing, the real link gets
-- overwritten with null.
--
-- This is a pure ADD - get_my_ungani_payees() itself is untouched, so
-- my-team-access.html's existing Payees card (which also calls it) is
-- completely unaffected. The new function is a single-row, any-status
-- lookup that my-money.html's edit flow calls ONLY when the record's
-- existing related_payee_id isn't already in the active list it just
-- loaded - see paidToOptionsHtml()/ensurePayeeOptionIncluded() in
-- my-money.html.

create or replace function public.get_ungani_payee_by_id(p_payee_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_payee record;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null or p_payee_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  select id, full_name, job_title, status
  into v_payee
  from public.ungani_payees
  where id = p_payee_id
    and tenant_id = v_tenant_id;

  if v_payee.id is null then
    return jsonb_build_object('ok', false, 'message', 'Payee not found.');
  end if;

  return jsonb_build_object(
    'ok', true,
    'payee', jsonb_build_object(
      'id', v_payee.id,
      'full_name', v_payee.full_name,
      'job_title', v_payee.job_title,
      'status', v_payee.status
    )
  );
end;
$function$;

grant execute on function public.get_ungani_payee_by_id(uuid) to authenticated;

-- Verification - confirm it landed and is grantable.
select routine_name
from information_schema.routines
where routine_schema = 'public' and routine_name = 'get_ungani_payee_by_id';

select routine_name, privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public'
  and routine_name = 'get_ungani_payee_by_id'
  and grantee = 'authenticated';

-- ============================================================
-- Cleanup: remove the 3 test payee records created during Task 1
-- verification. Their linked test transactions were already voided
-- (soft-deleted) - this is a real DELETE, safe because
-- transactions.related_payee_id is "on delete set null" (see
-- sql/payee-tracking.sql), so no other row can be left dangling.
-- ============================================================

delete from public.ungani_payees
where full_name in ('DYAR-VERIFY Payee2', 'DYAR-MONEY-TEST Payee', 'BILLY-TEST Payee');

-- Verification - should return 0 rows.
select id, tenant_id, full_name, job_title, status
from public.ungani_payees
where full_name in ('DYAR-VERIFY Payee2', 'DYAR-MONEY-TEST Payee', 'BILLY-TEST Payee');
