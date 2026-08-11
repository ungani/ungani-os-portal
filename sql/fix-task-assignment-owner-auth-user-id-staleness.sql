-- Root-caused via sql/diagnose-task-assignment-notification-chain.sql's
-- real output:
--
--   1. STEP 1 (ungani_notifications) was empty - the in-app notification
--      was never created.
--   2. STEP 2 (ungani_email_queue) had a real row, but stuck 'pending' -
--      the client never called the instant-send trigger.
--   5. STEP 5 (ungani_push_sent_log) was empty - the push endpoint was
--      never invoked.
--
-- All three point to ONE cascading failure, not three separate bugs:
-- notify_ungani_task_assignment() calls create_ungani_notification()
-- FIRST, then queues the email as an unconditional side effect
-- afterward, then returns whatever create_ungani_notification()
-- reported. create_ungani_notification() has its own `exception when
-- others` handler that silently swallows any INSERT failure and returns
-- {ok:false, message:<real error>} instead of raising - so if that
-- INSERT fails, the notification silently never exists, but the RPC's
-- overall response is {ok:false}, which is exactly what
-- my-tasks.html's notifyTaskAssignment() checks before calling
-- UnganiClientShared.triggerEmailSendNow()/triggerEventPush() - so
-- BOTH of those correctly never fire, even though the email had
-- already been queued moments earlier in the same function call.
--
-- Confirmed root cause of the INSERT failure: comparing STEP 3 and
-- STEP 6 of the diagnostic, registrations.auth_user_id for this tenant
-- (a29af055-e4f0-48cf-af97-f99081a9106b, "Demo Dyar Properties") is
-- a358312c-4670-486f-a106-555d8ca067ee - but the account's real,
-- currently-active auth_user_id (proven by its own working push
-- subscription) is c05d6fda-dcbe-4b01-8037-42693ea620de. These are
-- DIFFERENT ids. ungani_notifications.user_id is populated from
-- registrations.auth_user_id for an owner-assigned task with no
-- fallback - if that id doesn't exist in auth.users (a stale/orphaned
-- value, most likely from the auth account being reset/recreated at
-- some point without registrations.auth_user_id being kept in sync),
-- the INSERT hits a foreign-key violation, caught silently by the
-- exception handler above.
--
-- This didn't break anything ELSE in the app because
-- get_my_ungani_staff_access() (used for actual login/access checks
-- everywhere else) already has a resilient fallback: it matches EITHER
-- auth_user_id OR email, a fix applied earlier this session after the
-- same class of staleness was found (see
-- sql/fix-staff-access-status-coalesce-order.sql). This function
-- never got that same fallback - it trusts auth_user_id alone, so it's
-- the one place this particular staleness was still able to break
-- something, silently.
--
-- Fix has two parts: (1) correct the stale value for this real tenant
-- now, (2) make the function resilient to this happening again for any
-- tenant, instead of silently failing next time.

-- ============================================================
-- PART 0: direct proof, before changing anything. Confirms whether the
-- stale id is a real auth.users row at all (if this returns NO ROWS,
-- that's direct confirmation of the foreign-key-violation theory above
-- rather than just a strong inference from the cascade of symptoms).
-- ============================================================

select id, email, created_at
from auth.users
where id = 'a358312c-4670-486f-a106-555d8ca067ee';

-- For comparison - the real, currently-active account.
select id, email, created_at
from auth.users
where id = 'c05d6fda-dcbe-4b01-8037-42693ea620de';

-- ============================================================
-- PART 1: data fix - correct the stale auth_user_id for this tenant's
-- registration row now, so it matches the account's real login.
-- ============================================================

update public.registrations
set auth_user_id = 'c05d6fda-dcbe-4b01-8037-42693ea620de'
where tenant_id = 'a29af055-e4f0-48cf-af97-f99081a9106b'
  and lower(coalesce(status, registration_status, 'pending')) in ('approved', 'active', 'trial');

-- Verify - expect the corrected id.
select id, tenant_id, business_name, status, auth_user_id
from public.registrations r
join public.tenants t on t.id = r.tenant_id
where r.tenant_id = 'a29af055-e4f0-48cf-af97-f99081a9106b';

-- ============================================================
-- PART 2: code fix - notify_ungani_task_assignment()'s owner-resolution
-- branch now verifies the registration's auth_user_id still points to
-- a real auth.users row, and falls back to matching by email (the same
-- auth_user_id-OR-email pattern get_my_ungani_staff_access() already
-- uses) if it doesn't. Everything else in this function - the task
-- lookup, the team-member branch, the create_ungani_notification call,
-- the email-queueing block - is reproduced verbatim from the current
-- live version (sql/notifications-phase1-emails.sql), unchanged.
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
  v_assignee_email text;
  v_assignee_name text;
  v_tenant_name text;
  v_result jsonb;
begin
  v_access := public.get_my_ungani_staff_access();
  if coalesce((v_access->>'can_access')::boolean, false) is not true then
    return jsonb_build_object('ok', false, 'message', 'No active account found for this login.');
  end if;
  v_caller_tenant_id := nullif(v_access->>'tenant_id', '')::uuid;
  select id, tenant_id, task_title, due_date
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
    select r.auth_user_id, coalesce(r.email, r.contact_email), coalesce(r.contact_person, r.contact_name, r.full_name, 'there')
    into v_assignee_user_id, v_assignee_email, v_assignee_name
    from public.registrations r
    where r.tenant_id = v_task.tenant_id
      and lower(coalesce(r.status, r.registration_status, 'pending')) in ('approved', 'active', 'trial')
    order by r.created_at desc
    limit 1;

    -- NEW: registrations.auth_user_id can go stale (the auth account
    -- gets reset/recreated after this row was written, and nothing
    -- keeps it in sync) - verify it still points to a real auth.users
    -- row before trusting it. If not, fall back to an email match,
    -- exactly like get_my_ungani_staff_access() already does elsewhere.
    if v_assignee_user_id is not null and not exists (select 1 from auth.users where id = v_assignee_user_id) then
      v_assignee_user_id := null;
    end if;

    if v_assignee_user_id is null and v_assignee_email is not null then
      select id into v_assignee_user_id from auth.users where lower(email) = lower(v_assignee_email) limit 1;
    end if;
  elsif p_assignee_team_member_id is not null then
    select tm.auth_user_id, tm.email, coalesce(tm.full_name, 'there')
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
-- NOTE on the email already stuck 'pending' from the failed test: this
-- SQL editor can't send it directly (the actual send goes through
-- api/send-email-queue.js, which holds the SMTP credentials). It'll go
-- out on its own, either:
--   a) tomorrow's daily cron run, or
--   b) immediately, the next time ANY task gets (re)assigned once the
--      fix below is live - the client's instant-send trigger picks up
--      up to 5 pending emails per call, oldest first, so it'll catch
--      this stuck one along with the new one in the same call.
-- ============================================================

-- ============================================================
-- VERIFICATION - confirm the redefinition landed.
-- ============================================================

select pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'notify_ungani_task_assignment';
