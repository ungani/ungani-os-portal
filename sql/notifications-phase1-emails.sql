-- UNGANI OS: Notification System Phase 1 - expanded email notifications.
-- Run this once in the Supabase SQL editor.
--
-- Five events, using the exact same ungani_email_queue -> api/send-email-
-- queue.js pipeline already proven for registration/approval/trial-
-- warning emails. Real current sources for the two extended RPCs were
-- pulled first (sql/diagnose-notifications-phase1-sources.sql) and are
-- reproduced verbatim below except for the blocks marked "-- NEW:".
--
-- Correction from the diagnostic: the payment-proofs table is actually
-- named ungani_payment_proofs (confirmed from query 1's own function
-- body), not "payment-proofs" - used correctly throughout below.
--
-- Design notes common to all five:
--   - Every email queue insert is wrapped in its own BEGIN/EXCEPTION
--     sub-block (an implicit savepoint in plpgsql) so a queueing failure
--     can NEVER roll back the real action (payment marked paid, task
--     assigned, support response saved, staff member saved, money
--     record saved). RAISE WARNING on failure, visible in Postgres logs.
--   - Every insert is idempotency-guarded against ungani_email_queue
--     before inserting, using whatever key makes sense per event (see
--     each function's own comment) - never a blanket "one email per
--     row ever" rule where that would block a legitimate repeat action
--     (e.g. a second, different support reply on the same ticket).
--   - Recipient email/name are resolved from real, already-confirmed
--     columns only (tenants.business_email/contact_person/business_name,
--     ungani_team_members.email/full_name, support_issues.email/
--     reported_by, registrations.email/contact_email/contact_person) -
--     nothing guessed.
--   - The "Label: https://..." single-line paragraph pattern (matching
--     api/send-email-queue.js's buildHtmlFromText CTA-button detection)
--     is used everywhere a link is included.

-- ============================================================
-- 1. Payment approved - extends admin_accept_ungani_payment_proof_and_
-- mark_paid(). Recipient is the tenant's own business_email.
-- ============================================================

create or replace function public.admin_accept_ungani_payment_proof_and_mark_paid(p_proof_id uuid, p_admin_note text DEFAULT NULL::text, p_payment_method text DEFAULT NULL::text, p_payment_reference text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_payment_id uuid;
  v_tenant_id uuid;
  v_invoice_number text;
  v_existing_method text;
  v_existing_reference text;
  v_clean_note text;
  v_clean_method text;
  v_clean_reference text;
  v_recipient_email text; -- NEW
  v_recipient_name text; -- NEW
begin
  if public.is_ungani_admin() is not true then
    raise exception 'Access denied';
  end if;
  select
    pp.payment_id,
    pp.tenant_id,
    pp.invoice_number
  into
    v_payment_id,
    v_tenant_id,
    v_invoice_number
  from public.ungani_payment_proofs pp
  where pp.id = p_proof_id
  limit 1;
  if v_payment_id is null then
    raise exception 'Payment proof not found';
  end if;
  select
    p.payment_method,
    p.payment_reference
  into
    v_existing_method,
    v_existing_reference
  from public.ungani_payments p
  where p.id = v_payment_id
  limit 1;
  if not found then
    raise exception 'Related payment record not found';
  end if;
  v_clean_note := nullif(trim(coalesce(p_admin_note, '')), '');
  v_clean_method := nullif(trim(coalesce(p_payment_method, '')), '');
  v_clean_reference := nullif(trim(coalesce(p_payment_reference, '')), '');
  update public.ungani_payment_proofs
  set
    proof_status = 'accepted',
    admin_note = coalesce(
      v_clean_note,
      admin_note,
      'Payment proof accepted and payment marked as paid by UNGANI admin.'
    ),
    reviewed_by = auth.uid(),
    reviewed_at = now()
  where id = p_proof_id;
  update public.ungani_payments
  set
    payment_status = 'paid',
    paid_at = coalesce(paid_at, now()),
    payment_method = coalesce(
      v_clean_method,
      nullif(trim(coalesce(v_existing_method, '')), ''),
      'Payment proof'
    ),
    payment_reference = coalesce(
      v_clean_reference,
      nullif(trim(coalesce(v_existing_reference, '')), ''),
      v_invoice_number,
      'Proof accepted'
    ),
    notes = case
      when v_clean_note is not null and length(v_clean_note) > 0 then
        case
          when notes is null or length(trim(notes)) = 0 then
            'Admin accepted payment proof: ' || v_clean_note
          else
            notes || E'\nAdmin accepted payment proof: ' || v_clean_note
        end
      else
        case
          when notes is null or length(trim(notes)) = 0 then
            'Payment proof accepted and payment marked as paid by UNGANI admin.'
          else
            notes || E'\nPayment proof accepted and payment marked as paid by UNGANI admin.'
        end
    end,
    updated_at = now()
  where id = v_payment_id;
  if not found then
    raise exception 'Unable to update payment record';
  end if;

  -- NEW: queue a "payment approved" email to the tenant. Idempotency key
  -- is the payment_id - a given payment only ever gets marked paid once
  -- in the normal flow, so one email per payment is correct here (unlike
  -- support responses/task assignments, which can legitimately recur).
  begin
    select coalesce(t.business_email, ''), coalesce(t.contact_person, t.business_name, 'there')
    into v_recipient_email, v_recipient_name
    from public.tenants t
    where t.id = v_tenant_id;

    v_recipient_email := nullif(trim(coalesce(v_recipient_email, '')), '');

    if v_recipient_email is not null then
      if not exists (
        select 1 from public.ungani_email_queue
        where email_type = 'payment_approved'
          and related_table = 'ungani_payments'
          and related_id = v_payment_id
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
          v_recipient_email,
          v_recipient_name,
          'Your UNGANI OS payment has been confirmed',
          'Hi ' || v_recipient_name || E',\n\n' ||
          'Your payment' || (case when v_invoice_number is not null then ' for invoice ' || v_invoice_number else '' end) || ' has been reviewed and confirmed.' || E'\n\n' ||
          'Thank you for your payment.' || E'\n\n' ||
          'Regards,' || E'\n' ||
          'UNGANI' || E'\n' ||
          'info@ungani.com',
          'payment_approved',
          'ungani_payments',
          v_payment_id,
          'pending',
          now()
        );
      end if;
    end if;
  exception
    when others then
      raise warning 'Could not queue payment-approved email for payment %: %', v_payment_id, sqlerrm;
  end;

  return true;
end;
$function$;

-- ============================================================
-- 2. Task assigned - extends notify_ungani_task_assignment(). Recipient
-- is resolved exactly the way this function already resolves the in-app
-- notification's target user (owner via registrations, team member via
-- ungani_team_members) - just also carrying email/name through.
-- ============================================================

create or replace function public.notify_ungani_task_assignment(p_task_id uuid, p_assignee_team_member_id uuid DEFAULT NULL::uuid, p_assignee_is_owner boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_access jsonb;
  v_caller_tenant_id uuid;
  v_task record;
  v_assignee_user_id uuid;
  v_assignee_email text; -- NEW
  v_assignee_name text; -- NEW
  v_tenant_name text; -- NEW
  v_result jsonb; -- NEW
begin
  v_access := public.get_my_ungani_staff_access();
  if coalesce((v_access->>'can_access')::boolean, false) is not true then
    return jsonb_build_object('ok', false, 'message', 'No active account found for this login.');
  end if;
  v_caller_tenant_id := nullif(v_access->>'tenant_id', '')::uuid;
  select id, tenant_id, task_title, due_date -- NEW: due_date
  into v_task
  from public.tasks
  where id = p_task_id;
  if v_task.id is null then
    return jsonb_build_object('ok', false, 'message', 'Task not found.');
  end if;
  if v_caller_tenant_id is null or v_caller_tenant_id != v_task.tenant_id then
    return jsonb_build_object('ok', false, 'message', 'Task does not belong to your account.');
  end if;
  if coalesce(p_assignee_is_owner, false) then
    select r.auth_user_id, coalesce(r.email, r.contact_email), coalesce(r.contact_person, r.contact_name, r.full_name, 'there') -- NEW: email/name
    into v_assignee_user_id, v_assignee_email, v_assignee_name
    from public.registrations r
    where r.tenant_id = v_task.tenant_id
      and lower(coalesce(r.status, r.registration_status, 'pending')) in ('approved', 'active', 'trial')
    order by r.created_at desc
    limit 1;
  elsif p_assignee_team_member_id is not null then
    select tm.auth_user_id, tm.email, coalesce(tm.full_name, 'there') -- NEW: email/name
    into v_assignee_user_id, v_assignee_email, v_assignee_name
    from public.ungani_team_members tm
    where tm.id = p_assignee_team_member_id
      and tm.tenant_id = v_task.tenant_id;
    if not found then
      return jsonb_build_object('ok', false, 'message', 'Assignee not found for this account.');
    end if;
  else
    return jsonb_build_object('ok', true, 'message', 'No assignee - nothing to notify.');
  end if;

  v_result := public.create_ungani_notification(
    v_task.tenant_id,
    'New task assigned',
    'You''ve been assigned: ' || coalesce(v_task.task_title, 'a task'),
    'task_assignment',
    'tasks',
    v_task.id,
    '/my-tasks.html?highlight=' || v_task.id::text,
    'normal',
    jsonb_build_object(
      'task_id', v_task.id,
      'assignee_team_member_id', p_assignee_team_member_id,
      'assignee_is_owner', coalesce(p_assignee_is_owner, false)
    ),
    false,
    v_assignee_user_id
  );

  -- NEW: best-effort email, never allowed to affect the in-app
  -- notification result captured above. Idempotency key includes
  -- recipient_email (not just task_id) so reassigning the same task to a
  -- DIFFERENT person still emails them, but re-notifying the same person
  -- for the same task doesn't double-send.
  begin
    v_assignee_email := nullif(trim(coalesce(v_assignee_email, '')), '');

    if v_assignee_email is not null then
      select business_name into v_tenant_name from public.tenants where id = v_task.tenant_id;

      if not exists (
        select 1 from public.ungani_email_queue
        where email_type = 'task_assignment'
          and related_table = 'tasks'
          and related_id = v_task.id
          and recipient_email = v_assignee_email
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
          v_task.tenant_id,
          v_assignee_email,
          coalesce(v_assignee_name, 'there'),
          'New task assigned: ' || coalesce(v_task.task_title, 'a task'),
          'Hi ' || coalesce(v_assignee_name, 'there') || E',\n\n' ||
          'You''ve been assigned a new task' || (case when v_tenant_name is not null then ' at ' || v_tenant_name else '' end) || ':' || E'\n\n' ||
          coalesce(v_task.task_title, 'Task') ||
          (case when v_task.due_date is not null then E'\nDue: ' || to_char(v_task.due_date, 'DD Mon YYYY') else '' end) || E'\n\n' ||
          'View it here: https://ungani-os-portal.vercel.app/my-tasks.html?highlight=' || v_task.id::text || E'\n\n' ||
          'Regards,' || E'\n' ||
          'UNGANI' || E'\n' ||
          'info@ungani.com',
          'task_assignment',
          'tasks',
          v_task.id,
          'pending',
          now()
        );
      end if;
    end if;
  exception
    when others then
      raise warning 'Could not queue task-assignment email for task %: %', v_task.id, sqlerrm;
  end;

  return v_result;
end;
$function$;

-- ============================================================
-- 3. Support response - brand new RPC (support.html's saveSelectedIssue()
-- currently does a raw client-side .update(), no RPC exists to extend).
-- Called AFTER that real update already succeeded, same "queue after the
-- real write" pattern as the registration confirmation email. Admin-only,
-- matching support.html's own admin-only nature.
-- ============================================================

create or replace function public.queue_ungani_support_response_email(p_issue_id uuid, p_admin_response text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  i public.support_issues;
  v_recipient_email text;
  v_recipient_name text;
  v_clean_response text;
  v_body text;
begin
  if public.is_ungani_admin() is not true then
    return jsonb_build_object('ok', false, 'message', 'Only UNGANI admin can send support responses.');
  end if;

  select * into i from public.support_issues where id = p_issue_id;

  if i.id is null then
    return jsonb_build_object('ok', false, 'message', 'Support issue not found.');
  end if;

  v_clean_response := nullif(trim(coalesce(p_admin_response, '')), '');

  if v_clean_response is null then
    return jsonb_build_object('ok', false, 'message', 'No response text provided.');
  end if;

  v_recipient_email := nullif(trim(coalesce(i.email, '')), '');

  if v_recipient_email is null then
    return jsonb_build_object('ok', false, 'message', 'This ticket has no email on file.');
  end if;

  v_recipient_name := coalesce(nullif(trim(i.reported_by), ''), nullif(trim(i.company_name), ''), 'there');

  v_body :=
    'Hi ' || v_recipient_name || E',\n\n' ||
    'You have a new reply on your support ticket' || (case when i.issue_title is not null then ' "' || i.issue_title || '"' else '' end) || ':' || E'\n\n' ||
    v_clean_response || E'\n\n' ||
    'If you need anything else, just reply to this email or open a new message from your Chat with UNGANI page.' || E'\n\n' ||
    'Regards,' || E'\n' ||
    'UNGANI' || E'\n' ||
    'info@ungani.com';

  -- Idempotency: dedupe on the exact built body, not just the issue id -
  -- a ticket can legitimately get several distinct admin replies over
  -- its life, each of which should email the client; only an exact-text
  -- resubmit (e.g. a double-click on Save) is blocked.
  if exists (
    select 1 from public.ungani_email_queue
    where email_type = 'support_response'
      and related_table = 'support_issues'
      and related_id = p_issue_id
      and email_body = v_body
  ) then
    return jsonb_build_object('ok', true, 'message', 'This exact response was already queued.');
  end if;

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
    i.tenant_id,
    v_recipient_email,
    v_recipient_name,
    'UNGANI Support: reply to your ticket' || (case when i.issue_title is not null then ' - ' || i.issue_title else '' end),
    v_body,
    'support_response',
    'support_issues',
    p_issue_id,
    'pending',
    now()
  );

  return jsonb_build_object('ok', true);
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

grant execute on function public.queue_ungani_support_response_email(uuid, text) to authenticated;

-- ============================================================
-- 4. Payroll payment recorded - brand new RPC. Called from my-money.html
-- right after a successful transaction insert that carries a
-- related_team_member_id, using plain params rather than a transaction
-- id (the client-side insert path is left completely untouched - no
-- .select() chained onto it, avoiding the exact RLS/RETURNING gotcha
-- that broke registration confirmation emails earlier this session).
-- Tenant-scoped via get_my_ungani_staff_access(), same pattern as
-- notify_ungani_task_assignment - verifies the team member actually
-- belongs to the CALLER's own tenant before doing anything.
-- ============================================================

create or replace function public.queue_ungani_payroll_payment_email(
  p_team_member_id uuid,
  p_amount numeric,
  p_currency text default 'KES',
  p_transaction_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_access jsonb;
  v_tenant_id uuid;
  v_tenant_name text;
  tm public.ungani_team_members;
  v_recipient_email text;
  v_body text;
begin
  v_access := public.get_my_ungani_staff_access();

  if coalesce((v_access->>'can_access')::boolean, false) is not true then
    return jsonb_build_object('ok', false, 'message', 'No active account found for this login.');
  end if;

  v_tenant_id := nullif(v_access->>'tenant_id', '')::uuid;

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant found for this login.');
  end if;

  select * into tm from public.ungani_team_members where id = p_team_member_id;

  if tm.id is null or tm.tenant_id != v_tenant_id then
    return jsonb_build_object('ok', false, 'message', 'Staff member not found for this account.');
  end if;

  v_recipient_email := nullif(trim(coalesce(tm.email, '')), '');

  if v_recipient_email is null then
    return jsonb_build_object('ok', true, 'message', 'No email on file for this staff member - nothing to send.');
  end if;

  select business_name into v_tenant_name from public.tenants where id = v_tenant_id;

  v_body :=
    'Hi ' || coalesce(nullif(trim(tm.full_name), ''), 'there') || E',\n\n' ||
    'A payment has been recorded for you' || (case when v_tenant_name is not null then ' by ' || v_tenant_name else '' end) || ':' || E'\n\n' ||
    upper(coalesce(p_currency, 'KES')) || ' ' || to_char(coalesce(p_amount, 0), 'FM999,999,999.00') || ' on ' || to_char(coalesce(p_transaction_date, current_date), 'DD Mon YYYY') || E'\n\n' ||
    'This is a record of a payment already made to you - no action is needed.' || E'\n\n' ||
    'Regards,' || E'\n' ||
    'UNGANI' || E'\n' ||
    'info@ungani.com';

  -- Idempotency: dedupe on exact body text (amount+date baked in), so a
  -- genuinely new/different payment always queues its own email, but a
  -- retried/duplicate call for the identical payment doesn't double-send.
  if exists (
    select 1 from public.ungani_email_queue
    where email_type = 'payroll_payment'
      and related_table = 'ungani_team_members'
      and related_id = p_team_member_id
      and email_body = v_body
  ) then
    return jsonb_build_object('ok', true, 'message', 'This exact payment record was already queued.');
  end if;

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
    v_recipient_email,
    coalesce(nullif(trim(tm.full_name), ''), 'there'),
    'A payment has been recorded for you',
    v_body,
    'payroll_payment',
    'ungani_team_members',
    p_team_member_id,
    'pending',
    now()
  );

  return jsonb_build_object('ok', true);
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

grant execute on function public.queue_ungani_payroll_payment_email(uuid, numeric, text, date) to authenticated;

-- ============================================================
-- 5. Team invitation - extends owner_upsert_ungani_team_member() (the
-- version already shipped earlier tonight for payroll tracking, real
-- source reused directly from sql/payroll-staff-payment-tracking.sql,
-- not re-diagnosed). Fires ONLY on a genuine brand-new staff member -
-- v_is_new_member is captured immediately after the INSERT, before the
-- fallback "find existing by email + update" branch below can reassign
-- v_member_id, so an edit/permission change to an EXISTING member never
-- re-sends the invitation.
-- ============================================================

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
  v_is_new_member boolean := false; -- NEW
  v_clean_email text; -- NEW
  v_tenant_name text; -- NEW
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

  v_is_new_member := (v_member_id is not null); -- NEW - captured before the fallback branch below can reassign v_member_id

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

  -- NEW: one-time invitation email, brand-new members only.
  if v_is_new_member then
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
        raise warning 'Could not queue team-invitation email for member %: %', v_member_id, sqlerrm;
    end;
  end if;

  return jsonb_build_object(
    'ok', true,
    'team_member_id', v_member_id,
    'message', 'Staff member saved.'
  );
end;
$function$;

-- ============================================================
-- STEP 6: verification queries (read-only)
-- ============================================================

select
  p.proname,
  pg_get_function_arguments(p.oid) as arguments
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'admin_accept_ungani_payment_proof_and_mark_paid',
    'notify_ungani_task_assignment',
    'queue_ungani_support_response_email',
    'queue_ungani_payroll_payment_email',
    'owner_upsert_ungani_team_member'
  )
order by p.proname;
