-- Real evidence from sql/diagnose-team-invitation-email.sql's output:
--   Query 1: the email-queueing code IS live in the function.
--   Query 2: ZERO team_invitation rows ever queued, for anyone, ever.
--   Query 3: real staff (james kahindi, GRIFFINS OTIENO) exist,
--            auth_user_id null, consistent with never having received
--            an invite to log in with.
--
-- The two operations actually INSIDE the exception-wrapped block (the
-- tenants.business_name lookup, and the INSERT into
-- ungani_email_queue) are structurally IDENTICAL to the equivalent
-- lines in notify_ungani_task_assignment()'s own email-queueing block -
-- same table, same columns, same query shape - and that one is
-- CONFIRMED working (a real row was queued and observed earlier
-- tonight). That makes it very unlikely those specific lines are what's
-- failing here.
--
-- The much more likely culprit: the block never runs at all, because
-- its outer gate - `if v_is_new_member then` - is false every time.
-- v_is_new_member is only set true when the very first INSERT attempt
-- returns a real id; if `on conflict do nothing` fires instead (this
-- tenant+email combination already had a row - very plausible if a
-- real tester tried saving the same invite more than once, e.g. after
-- not seeing anything happen the first time), v_member_id comes back
-- null from the primary insert, the function falls into its "find
-- existing member by email + update" fallback branch instead, and
-- v_is_new_member stays false - permanently skipping the email block
-- for that person, even on every future save, since nothing ever
-- resets it.
--
-- Fix, two parts:
--   1. Stop gating the email attempt on "was this literally the first-
--      ever insert." Gate it on "do we have a resolved v_member_id",
--      full stop - whether that came from the fresh insert OR the
--      existing-member fallback. The idempotency check already inside
--      the block (only queue if nothing's been queued for this
--      member_id + email_type yet) is what actually prevents duplicate
--      emails, not v_is_new_member - so this is strictly more robust,
--      not looser. It also means a retried/edited save on someone who
--      never got their first email (for whatever reason) gets a real
--      second chance, instead of being locked out forever.
--   2. Per the explicit request: stop swallowing the real error
--      invisibly. The exception handler still raises a warning (for
--      Postgres server logs), but now ALSO returns the real error text
--      in the response as email_queue_error - so if something GENUINELY
--      throws in there, the very next real test will show it directly,
--      without needing another SQL diagnostic round-trip.

create or replace function public.owner_upsert_ungani_team_member(
  p_full_name text,
  p_email text default null::text,
  p_phone text default null::text,
  p_role_key text default 'staff'::text,
  p_status text default 'active'::text,
  p_monthly_salary numeric default null,
  p_pay_frequency text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_member_id uuid;
  v_role text;
  v_status text;
  v_monthly_salary numeric;
  v_pay_frequency text;
  v_clean_email text;
  v_tenant_name text;
  v_email_queue_error text; -- NEW: surfaced in the response instead of hidden
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;
  if public.is_my_ungani_tenant_owner(v_tenant_id) is not true then
    return jsonb_build_object('ok', false, 'message', 'Only the business owner can manage staff access.');
  end if;
  v_role := lower(trim(coalesce(p_role_key, 'staff')));
  v_status := lower(trim(coalesce(p_status, 'active')));
  if v_role not in ('owner', 'manager', 'staff', 'viewer') then
    v_role := 'staff';
  end if;
  if v_status not in ('active', 'invited', 'disabled') then
    v_status := 'active';
  end if;
  v_monthly_salary := case when p_monthly_salary is not null and p_monthly_salary >= 0 then p_monthly_salary else null end;
  v_pay_frequency := lower(trim(coalesce(p_pay_frequency, '')));
  if v_pay_frequency not in ('monthly', 'weekly', 'daily') then
    v_pay_frequency := null;
  end if;

  insert into public.ungani_team_members (
    tenant_id,
    full_name,
    email,
    phone,
    role_key,
    status,
    monthly_salary,
    pay_frequency,
    created_by
  )
  values (
    v_tenant_id,
    nullif(trim(coalesce(p_full_name, '')), ''),
    nullif(lower(trim(coalesce(p_email, ''))), ''),
    nullif(trim(coalesce(p_phone, '')), ''),
    v_role,
    v_status,
    v_monthly_salary,
    v_pay_frequency,
    auth.uid()
  )
  on conflict do nothing
  returning id into v_member_id;

  if v_member_id is null and p_email is not null then
    select id
    into v_member_id
    from public.ungani_team_members
    where tenant_id = v_tenant_id
      and lower(coalesce(email, '')) = lower(trim(p_email))
    order by created_at desc
    limit 1;

    update public.ungani_team_members
    set
      full_name = nullif(trim(coalesce(p_full_name, full_name)), ''),
      phone = nullif(trim(coalesce(p_phone, phone)), ''),
      role_key = v_role,
      status = v_status,
      monthly_salary = v_monthly_salary,
      pay_frequency = v_pay_frequency,
      updated_at = now()
    where id = v_member_id;
  end if;

  perform public.log_ungani_activity(
    'staff_saved',
    'settings',
    'ungani_team_members',
    v_member_id,
    'Staff member saved or updated.',
    jsonb_build_object('role_key', v_role, 'status', v_status)
  );

  -- CHANGED: no longer gated on "was this the literal first insert" -
  -- gated on "do we have a real member to email", full stop. The
  -- exists-check just below is what actually prevents duplicate sends.
  if v_member_id is not null then
    begin
      v_clean_email := nullif(trim(coalesce(p_email, '')), '');

      if v_clean_email is not null then
        select business_name into v_tenant_name from public.tenants where id = v_tenant_id;

        if not exists (
          select 1 from public.ungani_email_queue
          where email_type = 'team_invitation'
            and related_table = 'ungani_team_members'
            and related_id = v_member_id
        ) then
          insert into public.ungani_email_queue (
            tenant_id,
            recipient_email,
            recipient_name,
            email_subject,
            email_body,
            email_type,
            related_table,
            related_id,
            send_status,
            created_at
          ) values (
            v_tenant_id,
            v_clean_email,
            coalesce(nullif(trim(p_full_name), ''), 'there'),
            'You''ve been added to ' || coalesce(v_tenant_name, 'a UNGANI OS business') || ' on UNGANI OS',
            'Hi ' || coalesce(nullif(trim(p_full_name), ''), 'there') || E',\n\n' ||
            'You''ve been added as staff for ' || coalesce(v_tenant_name, 'a business') || ' on UNGANI OS.' || E'\n\n' ||
            'To get started, create your password here: https://ungani-os-portal.vercel.app/staff-login.html' || E'\n\n' ||
            'Use this email address (' || v_clean_email || ') when creating your password.' || E'\n\n' ||
            'Regards,' || E'\n' ||
            'UNGANI' || E'\n' ||
            'info@ungani.com',
            'team_invitation',
            'ungani_team_members',
            v_member_id,
            'pending',
            now()
          );
        end if;
      end if;
    exception
      when others then
        v_email_queue_error := sqlerrm; -- NEW: captured, not just logged
        raise warning 'Could not queue team-invitation email for member %: %', v_member_id, sqlerrm;
    end;
  end if;

  return jsonb_build_object(
    'ok', true,
    'team_member_id', v_member_id,
    'message', 'Staff member saved.',
    'email_queue_error', v_email_queue_error -- NEW: null on success, real error text if something threw
  );
end;
$function$;

-- ============================================================
-- Verification - confirm the redefinition landed.
-- ============================================================

select pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'owner_upsert_ungani_team_member';

-- ============================================================
-- Catch-up: your two existing staff (james kahindi, GRIFFINS OTIENO)
-- already exist with a resolvable member_id, but never got queued -
-- queue their invitation emails now too, using the exact same idempotent
-- check the function itself uses, so this is safe to run even if one of
-- them somehow already has a row.
-- ============================================================

insert into public.ungani_email_queue (
  tenant_id, recipient_email, recipient_name, email_subject, email_body,
  email_type, related_table, related_id, send_status, created_at
)
select
  tm.tenant_id,
  tm.email,
  coalesce(nullif(trim(tm.full_name), ''), 'there'),
  'You''ve been added to ' || coalesce(t.business_name, 'a UNGANI OS business') || ' on UNGANI OS',
  'Hi ' || coalesce(nullif(trim(tm.full_name), ''), 'there') || E',\n\n' ||
  'You''ve been added as staff for ' || coalesce(t.business_name, 'a business') || ' on UNGANI OS.' || E'\n\n' ||
  'To get started, create your password here: https://ungani-os-portal.vercel.app/staff-login.html' || E'\n\n' ||
  'Use this email address (' || tm.email || ') when creating your password.' || E'\n\n' ||
  'Regards,' || E'\n' ||
  'UNGANI' || E'\n' ||
  'info@ungani.com',
  'team_invitation',
  'ungani_team_members',
  tm.id,
  'pending',
  now()
from public.ungani_team_members tm
join public.tenants t on t.id = tm.tenant_id
where tm.email is not null
  and tm.auth_user_id is null -- don't re-invite someone already active
  and not exists (
    select 1 from public.ungani_email_queue eq
    where eq.email_type = 'team_invitation'
      and eq.related_table = 'ungani_team_members'
      and eq.related_id = tm.id
  );

-- Verify - expect real rows now, including the two catch-up ones.
select id, tenant_id, recipient_email, recipient_name, send_status, created_at
from public.ungani_email_queue
where email_type = 'team_invitation'
order by created_at desc;
