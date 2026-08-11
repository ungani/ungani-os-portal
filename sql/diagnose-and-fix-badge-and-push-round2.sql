-- Round 2: investigating the two NEW issues found after the auth_user_id
-- fix - (1) bell/badge count wildly inconsistent across pages, (2) push
-- still not reaching phone for a real task assignment.
--
-- Read the comments below for what was found via code investigation
-- (no DB access on my end) - Part A is a real, confirmed bug with a fix
-- included. Part B is a fresh diagnostic for the push issue - run it
-- after your next real test and paste back the output, same as before.

-- ============================================================
-- PART A: THE BADGE-COUNT BUG (confirmed via code, not yet verified
-- against your real data - the two queries after the fix will confirm).
-- ============================================================
--
-- There are actually TWO completely separate, disconnected "notification
-- count" systems in this app, which is why the count looks inconsistent
-- - it's not one bell showing different numbers, it's two different
-- bells with unrelated logic:
--
--   1. client.html (Dashboard) has its OWN bespoke notification panel
--      (mobileNotificationCount/desktopNotificationCount) that reads the
--      REAL ungani_notifications table directly - filtered by
--      `.eq("target_type", "client")`.
--
--   2. Every OTHER client page (my-tasks.html, my-money.html, etc, via
--      the shared client-shared.js shell) shows a DIFFERENT bell
--      (unganiBellCount) that has NOTHING to do with ungani_notifications
--      at all - it's a synthetic "things needing attention" count built
--      fresh each load from: overdue/due-today tasks + open support
--      issues + unread notices + unread admin chat replies, each capped
--      at 10 and combined. This is why it can jump around - it's
--      reacting to real task/support/notice/chat data changing, not to
--      an actual notification log.
--
-- On top of that split, client.html's system has a REAL bug: every
-- notification created via create_ungani_notification() (which is what
-- notify_ungani_task_assignment - and the Nia wrapper - actually calls)
-- never sets target_type at all, so it defaults to NULL. client.html's
-- query does a strict `.eq("target_type", "client")`, which never
-- matches NULL in Postgres/PostgREST - so EVERY notification ever
-- created through this path is invisible to the Dashboard bell, which
-- is why it showed 0 even after your test created a real row.
--
-- This explains what you saw: Tasks page showed the synthetic
-- attention-count (3, then 14 as real task data changed), Dashboard
-- showed 0 because its real notification query structurally excludes
-- every row this app's own notification functions create.
--
-- Fixing the target_type gap now (safe, minimal - every current real
-- caller of create_ungani_notification is client-facing, confirmed via
-- grep across the whole app). NOT attempting to unify the two separate
-- systems in this same pass - that's a bigger design decision (should
-- the shared-shell bell also become a real notification log, or should
-- client.html's stay a separate concept?) worth deciding deliberately
-- rather than folding into an urgent bugfix pass.

create or replace function public.create_ungani_notification(
  p_tenant_id uuid,
  p_title text,
  p_message text,
  p_notification_type text default 'system'::text,
  p_source_table text default null::text,
  p_source_record_id uuid default null::uuid,
  p_link_url text default null::text,
  p_priority text default 'normal'::text,
  p_metadata jsonb default '{}'::jsonb,
  p_email_enabled boolean default false,
  p_user_id uuid default null::uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_notification_id uuid;
  v_title text;
  v_message text;
  v_type text;
  v_priority text;
begin
  if p_tenant_id is null then
    return jsonb_build_object(
      'ok', false,
      'message', 'Tenant ID is required.'
    );
  end if;

  v_title := nullif(trim(coalesce(p_title, '')), '');
  v_message := nullif(trim(coalesce(p_message, '')), '');
  v_type := lower(coalesce(nullif(trim(p_notification_type), ''), 'system'));
  v_priority := lower(coalesce(nullif(trim(p_priority), ''), 'normal'));

  if v_title is null then
    v_title := 'UNGANI Notification';
  end if;

  if v_message is null then
    v_message := v_title;
  end if;

  insert into public.ungani_notifications (
    tenant_id,
    user_id,
    notification_title,
    notification_message,
    notification_type,
    source_table,
    source_record_id,
    link_url,
    priority,
    status,
    is_read,
    email_enabled,
    email_queued,
    metadata,
    target_type, -- NEW: every real caller of this function is
                 -- client-facing (notify_ungani_task_assignment, the Nia
                 -- wrapper create_my_ungani_notification) - hardcoding
                 -- this closes the gap that made every row this
                 -- function writes invisible to client.html's/
                 -- client-notifications.html's strict
                 -- .eq("target_type","client") queries.
    created_at,
    updated_at
  )
  values (
    p_tenant_id,
    p_user_id,
    v_title,
    v_message,
    v_type,
    p_source_table,
    p_source_record_id,
    p_link_url,
    v_priority,
    'unread',
    false,
    coalesce(p_email_enabled, false),
    false,
    coalesce(p_metadata, '{}'::jsonb),
    'client', -- NEW
    now(),
    now()
  )
  returning id into v_notification_id;

  return jsonb_build_object(
    'ok', true,
    'message', 'Notification created.',
    'notification_id', v_notification_id
  );
exception
  when others then
    return jsonb_build_object(
      'ok', false,
      'message', sqlerrm
    );
end;
$function$;

-- Verify the redefinition landed.
select pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'create_ungani_notification'
  and pg_get_function_identity_arguments(p.oid) ilike '%p_user_id%';

-- ============================================================
-- PART B: fresh push diagnostic - run this AFTER doing another real
-- task-assignment test (now that both the auth_user_id fix and the
-- target_type fix above are live), then paste back the full output.
-- ============================================================

-- B1: did the notification actually get created this time, and does it
-- now carry target_type = 'client'? Expect a real row.
select id, tenant_id, user_id, notification_title, notification_type,
       target_type, source_table, source_record_id, status, created_at
from public.ungani_notifications
where notification_type = 'task_assignment'
order by created_at desc
limit 5;

-- B2: was the push endpoint invoked THIS time (it wasn't last time -
-- STEP 5 came back empty)? A row here proves it ran, regardless of what
-- it decided.
select event_type, related_id, recipient_scope, created_at
from public.ungani_push_sent_log
where event_type = 'task_assignment'
order by created_at desc
limit 5;

-- B3: your current, real push subscriptions - which auth_user_id and
-- endpoint each device is actually registered under, and when. If your
-- phone's row is missing entirely, or has an old/different auth_user_id
-- than your current login, that's the next thing to check - the manual
-- test push earlier worked, so a subscription for your phone DOES
-- exist somewhere; this confirms whether it's under the CORRECT,
-- now-fixed auth_user_id.
select id, auth_user_id, user_type, tenant_id, endpoint, created_at
from public.ungani_push_subscriptions
order by created_at desc
limit 10;

-- B4: registrations.auth_user_id one more time, to confirm Part 1 of
-- the previous fix actually landed and stuck.
select id, tenant_id, auth_user_id
from public.registrations
where tenant_id = 'a29af055-e4f0-48cf-af97-f99081a9106b';
