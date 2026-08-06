-- Notification Unification: makes ungani_notifications the single real
-- source for every client page's bell, retiring the older tasks/
-- support_issues/client_notices heuristic (getNotificationItems() in
-- client-shared.js) that had drifted completely apart from it (zero
-- event-type overlap, confirmed via investigation - not a guess).
--
-- Real sources confirmed before writing this:
--   - support_issues: status in ('open','in progress','resolved',
--     'closed'), no assignee column - tenant-wide, from my-support.html's
--     real <select> options and getValue() field reads.
--   - client_notices: notice_title, notice_type, message, status
--     ('unread'/'read'), read_at - a SINGLE tenant-wide status per
--     notice (not per-user), from my-notices.html's real insert/update
--     payloads.
--   - admin_client_messages: sender_role, is_read (boolean) - confirmed
--     via my-chat.html's markAdminMessagesRead() and client-shared.js's
--     own existing getNotificationItems() query. This is a 4th signal
--     the old heuristic covers that wasn't in the original 3-item ask -
--     included here since "retire the heuristic entirely" requires it
--     too, or client users would silently lose "UNGANI replied" badges.
--   - get_my_ungani_notifications()'s real, current body (reproduced
--     verbatim below except the new sync call/target_type filter/
--     resolved_at column) is from sql/task-assignment-linking-my-tasks-
--     notifications.sql, the latest confirmed-live version. Real bug
--     found while reading it: it never filtered by target_type, so a
--     client-surface caller could see admin-targeted rows mixed in -
--     fixed here as part of this same migration since this RPC becomes
--     the canonical client read path.
--   - create_ungani_notification()'s real column list (unchanged, still
--     the one from Phase 4's fix - target_type/status/is_read all set
--     together at insert).
--
-- State-based semantics design (task_overdue, support_issue_open):
-- these represent "a condition is currently true", not "an event that
-- happened" - the exact bug being fixed is that marking one read
-- shouldn't make the badge stop reflecting reality while the task is
-- still overdue. New nullable resolved_at column: sync_my_ungani_
-- notifications() creates a row the first time the condition becomes
-- true, resolves it (resolved_at = now()) the moment it becomes false,
-- and NEVER re-creates a duplicate for the same still-true condition.
-- is_read stays fully user-controlled for list display (so "mark read"
-- still visibly does something - dims/acknowledges it), but the UNREAD
-- COUNT for these two types is "unresolved", not "unread" - i.e. it
-- keeps counting toward the badge until the real task/issue is actually
-- resolved, regardless of whether the user dismissed the notification.
-- notice_posted and admin_reply_unread are ordinary one-shot events
-- (mirrored once, then behave exactly like existing Connect
-- notifications - read means gone).
--
-- No triggers, no new cron - matches this app's existing "app-level
-- computation, not a rebuilt trigger" convention (see sql/fix-user-
-- limit-enforcement.sql's own reasoning). sync_my_ungani_notifications()
-- runs at the top of every get_my_ungani_notifications() call so it's
-- always fresh on read, tenant-scoped, cheap (each tenant has a small
-- number of tasks/issues/notices/messages, not thousands).

-- ============================================================
-- PART A: schema - one additive nullable column.
-- ============================================================

alter table public.ungani_notifications add column if not exists resolved_at timestamptz;

comment on column public.ungani_notifications.resolved_at is 'State-based notifications only (task_overdue, support_issue_open) - set when the underlying condition becomes false. NULL means still true/unresolved. Event-type notifications never set this.';

-- ============================================================
-- PART B: backfill - the previously-flagged, still-pending target_type
-- gap. Verified via the user's own diagnostic query that Dyar Property
-- specifically has zero null rows (its real issue was the coverage gap,
-- not stale data) - running anyway since other tenants with activity
-- before the Phase 4 target_type fix may still have nulls, and this is
-- a safe, idempotent no-op for tenants that don't.
-- ============================================================

update public.ungani_notifications
set target_type = 'client', updated_at = now()
where target_type is null;

-- ============================================================
-- PART C: the sync function - 4 independent, idempotent passes.
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
    tenant_id, user_id, notification_title, notification_message, notification_type,
    source_table, source_record_id, link_url, priority, status, is_read,
    email_enabled, email_queued, metadata, target_type, resolved_at, created_at, updated_at
  )
  select
    v_tenant_id, null, 'Task overdue',
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
    tenant_id, user_id, notification_title, notification_message, notification_type,
    source_table, source_record_id, link_url, priority, status, is_read,
    email_enabled, email_queued, metadata, target_type, resolved_at, created_at, updated_at
  )
  select
    v_tenant_id, null, 'Support issue open',
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

  -- 3. notice_posted (event, one-shot mirror - client_notices already
  -- has its own tenant-wide read status, mirrored directly at creation).
  -- notices.html's own insert path tries 3 different candidate payload
  -- shapes in sequence (notice_title/notice_body, then title/message,
  -- then a minimal title/message) - genuine, app-code-confirmed
  -- uncertainty about which title/message column names are live, unlike
  -- tasks/support_issues which have real unhedged direct writes
  -- elsewhere. Using to_jsonb(c)->>'key' (returns null for a missing
  -- key rather than erroring) instead of a bare column reference, so
  -- this doesn't fail to even CREATE if the live table doesn't have one
  -- of the guessed names. id/tenant_id/status/created_at are all
  -- confirmed real (used unhedged elsewhere), kept as direct columns.
  insert into public.ungani_notifications (
    tenant_id, user_id, notification_title, notification_message, notification_type,
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
    tenant_id, user_id, notification_title, notification_message, notification_type,
    source_table, source_record_id, link_url, priority, status, is_read,
    email_enabled, email_queued, metadata, target_type, resolved_at, created_at, updated_at
  )
  select
    v_tenant_id, null, 'New message from UNGANI',
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

grant execute on function public.sync_my_ungani_notifications() to authenticated;

-- ============================================================
-- PART D: get_my_ungani_notifications - real current body (verbatim
-- from sql/task-assignment-linking-my-tasks-notifications.sql) plus the
-- sync call, the target_type filter fix, and resolved_at in the
-- returned columns. Postgres won't let CREATE OR REPLACE change an
-- existing function's return type (adding resolved_at to the table
-- shape counts as a change), so the old signature has to be dropped
-- first - safe, since it's immediately recreated in the same
-- transaction-equivalent script with the identical name/argument list.
-- ============================================================

drop function if exists public.get_my_ungani_notifications(integer);

create or replace function public.get_my_ungani_notifications(p_limit integer default 30)
returns table(
  id uuid,
  notification_title text,
  notification_message text,
  notification_type text,
  source_table text,
  source_record_id uuid,
  link_url text,
  priority text,
  status text,
  is_read boolean,
  resolved_at timestamp with time zone,
  created_at timestamp with time zone,
  metadata jsonb
)
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_user_tenant_id uuid;
  v_user_id uuid := auth.uid();
begin
  begin
    v_user_tenant_id := public.get_my_ungani_current_tenant_id_v16();
  exception
    when others then
      begin
        v_user_tenant_id := public.get_my_ungani_tenant_id();
      exception
        when others then
          v_user_tenant_id := null;
      end;
  end;

  if v_user_tenant_id is null then
    return;
  end if;

  begin
    perform public.sync_my_ungani_notifications();
  exception
    when others then
      raise warning 'sync_my_ungani_notifications skipped: %', sqlerrm;
  end;

  return query
  select
    n.id,
    n.notification_title,
    n.notification_message,
    n.notification_type,
    n.source_table,
    n.source_record_id,
    n.link_url,
    n.priority,
    n.status,
    n.is_read,
    n.resolved_at,
    n.created_at,
    n.metadata
  from public.ungani_notifications n
  where n.tenant_id = v_user_tenant_id
    and n.target_type = 'client'
    and (n.user_id is null or n.user_id = v_user_id)
  order by n.created_at desc
  limit greatest(1, least(coalesce(p_limit, 30), 100));
end;
$function$;

-- ============================================================
-- VERIFICATION - run this and paste back the output.
-- ============================================================

-- 1. resolved_at column exists.
select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'ungani_notifications' and column_name = 'resolved_at';

-- 2. No more null target_type rows anywhere.
select count(*) as remaining_null_target_type
from public.ungani_notifications
where target_type is null;

-- 3. Both functions exist with correct signatures.
select p.proname, pg_get_function_identity_arguments(p.oid) as arguments
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('sync_my_ungani_notifications', 'get_my_ungani_notifications')
order by p.proname;

-- 4. get_my_ungani_notifications now filters target_type and returns resolved_at.
select pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'get_my_ungani_notifications';

-- 5. Grants: authenticated can call sync_my_ungani_notifications directly too
-- (harmless read+idempotent-write, but mainly invoked internally).
select routine_name, privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public'
  and routine_name = 'sync_my_ungani_notifications'
  and grantee = 'authenticated';
