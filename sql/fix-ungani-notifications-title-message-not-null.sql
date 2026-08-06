-- Root cause of tonight's notification-unification bell bug, confirmed
-- via a live rollback-wrapped test insert: public.ungani_notifications
-- has two legacy columns, "title" and "message", both NOT NULL with NO
-- DEFAULT. Neither create_ungani_notification() (the function used by
-- Ungani Connect Phase 4's mentions/comments/status-changes/attachments
-- and by notify_ungani_task_assignment()) nor sync_my_ungani_
-- notifications() (tonight's notification-unification work) has ever
-- written to either column - both only ever wrote notification_title/
-- notification_message, the newer pair. Every insert from either
-- function has been failing with a 23502 not-null-violation, silently -
-- create_ungani_notification() has its own `exception when others`
-- handler that catches this and returns {ok:false, message:sqlerrm}
-- instead of raising, so callers (task assignment, Phase 4 Connect
-- notifications) correctly skipped downstream email/push, but the
-- in-app notification itself was never created.
--
-- Confirmed via the real column list (information_schema.columns) this
-- isn't a regression from tonight - the earliest version of create_
-- ungani_notification() on file (2026-07-31) already omitted title/
-- message, so this has been broken for every caller of that function
-- since at least then. Historical rows that DO have real content
-- (notification_type 'general'/'support'/'support_update' for Demo Dyar
-- Properties, dated back to 2026-07-08) were not created by this
-- function - some other, older/legacy insert path must still write
-- title/message directly. That path is untouched by this fix.
--
-- Fix: both functions now write BOTH column pairs with the same values,
-- so any future code that reads either title/message OR notification_
-- title/notification_message sees real content.
--
-- *** RUN THIS FILE AS THREE SEPARATE EXECUTIONS, NOT ONE PASTE. ***
-- STEP 1 (PART A + PART B below) redefines both functions - run this
-- block ALONE first. STEP 2 and STEP 3 (under VERIFICATION) each run
-- ALONE afterward, in their own separate "Run" action. Do not run all
-- three in a single paste: STEP 3 contains an explicit begin/rollback
-- for its safe test insert, and if the SQL editor executes a pasted
-- script as one continuous session, that rollback silently undoes
-- everything run earlier in the SAME paste - including STEP 1's
-- function redefinitions. That is exactly what happened on the first
-- attempt: no errors were shown, but the rollback reverted the fix.

-- ============================================================
-- STEP 1, PART A: create_ungani_notification() - adds title/message to
-- the INSERT, identical values to notification_title/notification_
-- message. Everything else reproduced verbatim from the current live
-- version (sql/ungani-connect-phase4-smart-notifications.sql). Return
-- type is unchanged (jsonb), so CREATE OR REPLACE works without a DROP
-- first. Run PART A and PART B together, alone, nothing else.
-- ============================================================

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
    return jsonb_build_object('ok', false, 'message', 'Tenant ID is required.');
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
    tenant_id, user_id, title, message, notification_title, notification_message, notification_type,
    source_table, source_record_id, link_url, priority, status, is_read,
    email_enabled, email_queued, metadata, target_type, created_at, updated_at
  )
  values (
    p_tenant_id, p_user_id, v_title, v_message, v_title, v_message, v_type,
    p_source_table, p_source_record_id, p_link_url, v_priority, 'unread', false,
    coalesce(p_email_enabled, false), false, coalesce(p_metadata, '{}'::jsonb), 'client', now(), now()
  )
  returning id into v_notification_id;

  return jsonb_build_object('ok', true, 'message', 'Notification created.', 'notification_id', v_notification_id);
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

-- ============================================================
-- STEP 1, PART C: create_ungani_notification() - the OLDER 10-arg
-- overload (no p_user_id), a genuinely separate function from PART A's
-- 11-arg version, not previously fixed. Confirmed real and live: Nia's
-- daily briefing (persistDailyBriefingNotification() in nia-assistant.js)
-- calls it via the safe create_my_ungani_notification() wrapper (sql/
-- fix-notification-cross-tenant-vulnerability.sql), so it has been
-- silently failing the same way. Source reproduced verbatim from the
-- real pg_get_functiondef() output pulled just now, plus title/message
-- added to the INSERT. Everything else - including the lack of
-- target_type/user_id columns in the INSERT, which this overload never
-- set - left exactly as-is; target_type still gets its table default
-- ('client') either way. Still part of STEP 1 - run together with PART
-- A and PART B above, in the same execution as each other.
-- ============================================================

create or replace function public.create_ungani_notification(p_tenant_id uuid, p_title text, p_message text, p_notification_type text DEFAULT 'system'::text, p_source_table text DEFAULT NULL::text, p_source_record_id uuid DEFAULT NULL::uuid, p_link_url text DEFAULT NULL::text, p_priority text DEFAULT 'normal'::text, p_metadata jsonb DEFAULT '{}'::jsonb, p_email_enabled boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    title,
    message,
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
    created_at,
    updated_at
  )
  values (
    p_tenant_id,
    v_title,
    v_message,
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

-- ============================================================
-- STEP 1, PART B: sync_my_ungani_notifications() - same fix, all 4
-- insert blocks. Everything else reproduced verbatim from sql/
-- notification-unification.sql (the current live version). Return type
-- unchanged (void), no DROP needed. Still part of STEP 1 - run together
-- with PART A above, in the same execution as each other (but separate
-- from STEP 2 and STEP 3 below).
-- ============================================================

create or replace function public.sync_my_ungani_notifications()
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_today date := current_date;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null then
    return;
  end if;

  -- 1. task_overdue (state) - create when newly true.
  insert into public.ungani_notifications (
    tenant_id, user_id, title, message, notification_title, notification_message, notification_type,
    source_table, source_record_id, link_url, priority, status, is_read,
    email_enabled, email_queued, metadata, target_type, resolved_at, created_at, updated_at
  )
  select
    v_tenant_id, null,
    'Task overdue',
    coalesce(nullif(trim(t.task_title), ''), 'A task') || ' was due ' || to_char(t.due_date, 'DD Mon YYYY') || ' and hasn''t been completed.',
    'Task overdue',
    coalesce(nullif(trim(t.task_title), ''), 'A task') || ' was due ' || to_char(t.due_date, 'DD Mon YYYY') || ' and hasn''t been completed.',
    'task_overdue', 'tasks', t.id, '/my-tasks.html?highlight=' || t.id, 'normal', 'unread', false,
    false, false, jsonb_build_object('due_date', t.due_date), 'client', null, now(), now()
  from public.tasks t
  where t.tenant_id = v_tenant_id
    and t.due_date is not null
    and t.due_date < v_today
    and lower(coalesce(t.status, '')) not like '%completed%'
    and lower(coalesce(t.status, '')) not like '%cancelled%'
    and not exists (
      select 1 from public.ungani_notifications n
      where n.tenant_id = v_tenant_id and n.source_table = 'tasks' and n.source_record_id = t.id
        and n.notification_type = 'task_overdue' and n.resolved_at is null
    );

  -- Resolve task_overdue rows whose task is no longer overdue+open.
  update public.ungani_notifications n
  set resolved_at = now(), updated_at = now()
  where n.tenant_id = v_tenant_id
    and n.notification_type = 'task_overdue'
    and n.resolved_at is null
    and not exists (
      select 1 from public.tasks t
      where t.id = n.source_record_id
        and t.due_date is not null
        and t.due_date < v_today
        and lower(coalesce(t.status, '')) not like '%completed%'
        and lower(coalesce(t.status, '')) not like '%cancelled%'
    );

  -- 2. support_issue_open (state)
  insert into public.ungani_notifications (
    tenant_id, user_id, title, message, notification_title, notification_message, notification_type,
    source_table, source_record_id, link_url, priority, status, is_read,
    email_enabled, email_queued, metadata, target_type, resolved_at, created_at, updated_at
  )
  select
    v_tenant_id, null,
    'Support issue open',
    coalesce(nullif(trim(s.issue_title), ''), 'A support issue') || ' is ' || lower(coalesce(s.status, 'open')) || '.',
    'Support issue open',
    coalesce(nullif(trim(s.issue_title), ''), 'A support issue') || ' is ' || lower(coalesce(s.status, 'open')) || '.',
    'support_issue_open', 'support_issues', s.id, '/my-support.html', coalesce(nullif(lower(trim(s.priority)), ''), 'normal'), 'unread', false,
    false, false, jsonb_build_object('status', s.status), 'client', null, now(), now()
  from public.support_issues s
  where s.tenant_id = v_tenant_id
    and lower(coalesce(s.status, '')) in ('open', 'in progress')
    and not exists (
      select 1 from public.ungani_notifications n
      where n.tenant_id = v_tenant_id and n.source_table = 'support_issues' and n.source_record_id = s.id
        and n.notification_type = 'support_issue_open' and n.resolved_at is null
    );

  update public.ungani_notifications n
  set resolved_at = now(), updated_at = now()
  where n.tenant_id = v_tenant_id
    and n.notification_type = 'support_issue_open'
    and n.resolved_at is null
    and not exists (
      select 1 from public.support_issues s
      where s.id = n.source_record_id
        and lower(coalesce(s.status, '')) in ('open', 'in progress')
    );

  -- 3. notice_posted (event, one-shot mirror).
  insert into public.ungani_notifications (
    tenant_id, user_id, title, message, notification_title, notification_message, notification_type,
    source_table, source_record_id, link_url, priority, status, is_read,
    email_enabled, email_queued, metadata, target_type, resolved_at, created_at, updated_at
  )
  select
    v_tenant_id, null,
    coalesce(
      nullif(trim(to_jsonb(c)->>'notice_title'), ''),
      nullif(trim(to_jsonb(c)->>'title'), ''),
      'New notice'
    ),
    coalesce(
      nullif(trim(to_jsonb(c)->>'message'), ''),
      nullif(trim(to_jsonb(c)->>'notice_body'), ''),
      nullif(trim(to_jsonb(c)->>'description'), ''),
      'A new notice was posted.'
    ),
    coalesce(
      nullif(trim(to_jsonb(c)->>'notice_title'), ''),
      nullif(trim(to_jsonb(c)->>'title'), ''),
      'New notice'
    ),
    coalesce(
      nullif(trim(to_jsonb(c)->>'message'), ''),
      nullif(trim(to_jsonb(c)->>'notice_body'), ''),
      nullif(trim(to_jsonb(c)->>'description'), ''),
      'A new notice was posted.'
    ),
    'notice_posted', 'client_notices', c.id, '/my-notices.html',
    coalesce(nullif(lower(trim(to_jsonb(c)->>'priority')), ''), 'normal'),
    case when lower(coalesce(c.status, '')) = 'read' then 'read' else 'unread' end,
    case when lower(coalesce(c.status, '')) = 'read' then true else false end,
    false, false, '{}'::jsonb, 'client', null, coalesce(c.created_at, now()), now()
  from public.client_notices c
  where c.tenant_id = v_tenant_id
    and not exists (
      select 1 from public.ungani_notifications n
      where n.tenant_id = v_tenant_id and n.source_table = 'client_notices' and n.source_record_id = c.id
    );

  -- 4. admin_reply_unread (event, one-shot mirror).
  insert into public.ungani_notifications (
    tenant_id, user_id, title, message, notification_title, notification_message, notification_type,
    source_table, source_record_id, link_url, priority, status, is_read,
    email_enabled, email_queued, metadata, target_type, resolved_at, created_at, updated_at
  )
  select
    v_tenant_id, null,
    'New message from UNGANI',
    left(coalesce(nullif(trim(m.message_body), ''), 'You have a new message from UNGANI.'), 200),
    'New message from UNGANI',
    left(coalesce(nullif(trim(m.message_body), ''), 'You have a new message from UNGANI.'), 200),
    'admin_reply_unread', 'admin_client_messages', m.id, '/my-chat.html', 'normal',
    case when coalesce(m.is_read, false) then 'read' else 'unread' end,
    coalesce(m.is_read, false),
    false, false, '{}'::jsonb, 'client', null, coalesce(m.created_at, now()), now()
  from public.admin_client_messages m
  where m.tenant_id = v_tenant_id
    and m.sender_role <> 'client'
    and not exists (
      select 1 from public.ungani_notifications n
      where n.tenant_id = v_tenant_id and n.source_table = 'admin_client_messages' and n.source_record_id = m.id
    );
end;
$function$;

-- ============================================================
-- STEP 2 (run ALONE, in its own execution, after STEP 1 has run and
-- completed): confirms both function definitions actually changed.
-- No transaction, no risk - safe to run any time.
-- ============================================================

select p.proname, pg_get_functiondef(p.oid) as source
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('create_ungani_notification', 'sync_my_ungani_notifications')
order by p.proname;

-- ============================================================
-- STEP 3 (run ALONE, in its own separate execution - never combined
-- with STEP 1 in the same paste): live proof, rolled back so it writes
-- nothing permanent. The exact insert that failed before should now
-- succeed with no error.
-- ============================================================

begin;

insert into public.ungani_notifications (
  tenant_id, user_id, title, message, notification_title, notification_message, notification_type,
  source_table, source_record_id, link_url, priority, status, is_read,
  email_enabled, email_queued, metadata, target_type, resolved_at, created_at, updated_at
)
select
  'a29af055-e4f0-48cf-af97-f99081a9106b', null,
  'Task overdue',
  coalesce(nullif(trim(t.task_title), ''), 'A task') || ' was due ' || to_char(t.due_date, 'DD Mon YYYY') || ' and hasn''t been completed.',
  'Task overdue',
  coalesce(nullif(trim(t.task_title), ''), 'A task') || ' was due ' || to_char(t.due_date, 'DD Mon YYYY') || ' and hasn''t been completed.',
  'task_overdue', 'tasks', t.id, '/my-tasks.html?highlight=' || t.id, 'normal', 'unread', false,
  false, false, jsonb_build_object('due_date', t.due_date), 'client', null, now(), now()
from public.tasks t
where t.tenant_id = 'a29af055-e4f0-48cf-af97-f99081a9106b'
  and t.due_date is not null
  and t.due_date < current_date
  and lower(coalesce(t.status, '')) not like '%completed%'
  and lower(coalesce(t.status, '')) not like '%cancelled%'
limit 1;

rollback;
