-- System status / maintenance announcements (v1).
--
-- Goal: admin posts a platform-wide message ("Scheduled maintenance
-- tonight 11pm-1am" / "New feature: Team Chat is here!") that shows as
-- a dismissible banner on client.html + shared-shell pages, AND fans out
-- into the existing bell/notification system so people who don't have
-- the dashboard open still see it.
--
-- Deliberately NOT reusing/repairing the old client_notices/system_notices
-- tables behind notices.html/my-notices.html - confirmed those are dead:
-- client_notices has 1 row ever, system_notices has 125 rows of unrelated
-- auto-generated noise ("A new transaction of KES X has been posted to
-- the global ledger"), the schema itself has two incompatible generations
-- of columns coexisting on the same rows, and neither table is wired into
-- any proactive surfacing (no badge, no banner, not read by the bell).
-- Left alone per user decision - flagged for a future separate cleanup.
--
-- ============================================================
-- PART A: drop the stale, superseded create_ungani_notification() overload.
--
-- Confirmed live via pg_get_functiondef - TWO signatures coexist:
--   - old 10-param version: never sets target_type in its INSERT at all,
--     so any row it wrote would have target_type = null - get_my_ungani_
--     notifications()'s filter (n.target_type = 'client') would silently
--     exclude it. The function still returns {ok:true}, so a caller of
--     this version would believe a notification was delivered when the
--     recipient could never actually see it.
--   - new 11-param version (adds p_user_id): explicitly sets user_id and
--     hardcodes target_type = 'client' in its INSERT - this is the one
--     actually producing the real notification rows in the table today
--     (confirmed via live sample: task_overdue/support_issue_open rows
--     both show target_type: 'client').
-- Since the 11-param version's extra param is a trailing default, this
-- isn't causing an ambiguous-call error today, but leaving both around
-- risks exactly that the moment any caller (including this migration's
-- own RPC) omits p_user_id by name rather than full positional match -
-- same overload-conflict shape as owner_upsert_ungani_team_member, fixed
-- twice already this session. Dropping the dead one now, confirmed with
-- user before applying.
-- ============================================================

drop function if exists public.create_ungani_notification(
  uuid, text, text, text, text, uuid, text, text, jsonb, boolean
);

-- ============================================================
-- PART B: platform_announcements - the master record. Global, not
-- tenant-scoped - one row is meant for every tenant.
-- ============================================================

create table if not exists public.ungani_platform_announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  message text not null,
  severity text not null default 'info',
  starts_at timestamptz,
  ends_at timestamptz,
  is_active boolean not null default true,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ungani_platform_announcements_severity_check
    check (severity in ('info', 'warning', 'critical'))
);

alter table public.ungani_platform_announcements enable row level security;
-- No policies - client access is exclusively through
-- get_my_ungani_active_announcements() below, matching how
-- ungani_notifications itself is never granted directly to authenticated.

-- ============================================================
-- PART C: per-user dismissal tracking.
-- ============================================================

create table if not exists public.ungani_announcement_dismissals (
  id uuid primary key default gen_random_uuid(),
  announcement_id uuid not null references public.ungani_platform_announcements(id) on delete cascade,
  user_id uuid not null,
  dismissed_at timestamptz not null default now(),
  constraint ungani_announcement_dismissals_unique unique (announcement_id, user_id)
);

alter table public.ungani_announcement_dismissals enable row level security;
-- No policies - written/read exclusively through the two RPCs below.

-- ============================================================
-- PART D: admin write path - create + broadcast in one call.
-- Loops every tenant (including suspended/cancelled, per user decision -
-- a suspended client can still log into a read-only view and should know
-- about downtime or a new feature) and fans out one broadcast row per
-- tenant via the real, current create_ungani_notification(), with
-- p_user_id left null so it's visible to every user of that tenant
-- (confirmed via get_my_ungani_notifications()'s own filter: a row with
-- user_id is null matches any user at that tenant_id).
-- ============================================================

create or replace function public.admin_create_ungani_platform_announcement(
  p_title text,
  p_message text,
  p_severity text default 'info',
  p_starts_at timestamptz default null,
  p_ends_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_is_admin boolean;
  v_title text;
  v_message text;
  v_severity text;
  v_announcement_id uuid;
  v_tenant record;
  v_notified_count int := 0;
begin
  select is_ungani_admin() into v_is_admin;
  if not coalesce(v_is_admin, false) then
    return jsonb_build_object('ok', false, 'message', 'Admin access required.');
  end if;

  v_title := nullif(trim(coalesce(p_title, '')), '');
  v_message := nullif(trim(coalesce(p_message, '')), '');
  v_severity := lower(coalesce(nullif(trim(p_severity), ''), 'info'));

  if v_title is null then
    return jsonb_build_object('ok', false, 'message', 'Title is required.');
  end if;
  if v_message is null then
    return jsonb_build_object('ok', false, 'message', 'Message is required.');
  end if;
  if v_severity not in ('info', 'warning', 'critical') then
    v_severity := 'info';
  end if;

  insert into public.ungani_platform_announcements (
    title, message, severity, starts_at, ends_at, is_active, created_by
  ) values (
    v_title, v_message, v_severity, p_starts_at, p_ends_at, true, auth.uid()
  )
  returning id into v_announcement_id;

  for v_tenant in select id from public.tenants loop
    perform public.create_ungani_notification(
      p_tenant_id := v_tenant.id,
      p_title := v_title,
      p_message := v_message,
      p_notification_type := 'platform_announcement',
      p_source_table := 'ungani_platform_announcements',
      p_source_record_id := v_announcement_id,
      p_link_url := null,
      p_priority := case v_severity when 'critical' then 'high' when 'warning' then 'high' else 'normal' end,
      p_metadata := jsonb_build_object('severity', v_severity),
      p_email_enabled := false,
      p_user_id := null
    );
    v_notified_count := v_notified_count + 1;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'announcement_id', v_announcement_id,
    'tenants_notified', v_notified_count
  );
end;
$function$;

-- ============================================================
-- PART E: admin write path - deactivate an announcement early
-- (e.g. maintenance finished ahead of schedule).
-- ============================================================

create or replace function public.admin_deactivate_ungani_platform_announcement(
  p_announcement_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_is_admin boolean;
begin
  select is_ungani_admin() into v_is_admin;
  if not coalesce(v_is_admin, false) then
    return jsonb_build_object('ok', false, 'message', 'Admin access required.');
  end if;

  update public.ungani_platform_announcements
  set is_active = false, updated_at = now()
  where id = p_announcement_id;

  return jsonb_build_object('ok', true);
end;
$function$;

-- ============================================================
-- PART F: client read path - active, in-window, not-yet-dismissed-by-me.
-- ============================================================

create or replace function public.get_my_ungani_active_announcements()
returns table(
  id uuid,
  title text,
  message text,
  severity text,
  starts_at timestamptz,
  ends_at timestamptz,
  created_at timestamptz
)
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    return;
  end if;

  return query
  select
    a.id, a.title, a.message, a.severity, a.starts_at, a.ends_at, a.created_at
  from public.ungani_platform_announcements a
  where a.is_active = true
    and (a.starts_at is null or a.starts_at <= now())
    and (a.ends_at is null or a.ends_at >= now())
    and not exists (
      select 1 from public.ungani_announcement_dismissals d
      where d.announcement_id = a.id and d.user_id = v_user_id
    )
  order by a.created_at desc;
end;
$function$;

-- ============================================================
-- PART G: client write path - dismiss (idempotent).
-- ============================================================

create or replace function public.dismiss_ungani_platform_announcement(
  p_announcement_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    return jsonb_build_object('ok', false, 'message', 'Not signed in.');
  end if;

  insert into public.ungani_announcement_dismissals (announcement_id, user_id)
  values (p_announcement_id, v_user_id)
  on conflict (announcement_id, user_id) do nothing;

  return jsonb_build_object('ok', true);
end;
$function$;

-- ============================================================
-- PART H: grants.
-- ============================================================

grant execute on function public.admin_create_ungani_platform_announcement(
  text, text, text, timestamptz, timestamptz
) to authenticated;

grant execute on function public.admin_deactivate_ungani_platform_announcement(uuid) to authenticated;
grant execute on function public.get_my_ungani_active_announcements() to authenticated;
grant execute on function public.dismiss_ungani_platform_announcement(uuid) to authenticated;

-- ============================================================
-- VERIFICATION - run after applying, confirm:
--   1. Exactly one create_ungani_notification signature remains (11-param).
--   2. The 4 new functions exist.
-- ============================================================

select p.oid::regprocedure as signature, pg_get_function_arguments(p.oid) as arguments
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'create_ungani_notification';

select proname
from pg_proc
where pronamespace = 'public'::regnamespace
  and proname in (
    'admin_create_ungani_platform_announcement',
    'admin_deactivate_ungani_platform_announcement',
    'get_my_ungani_active_announcements',
    'dismiss_ungani_platform_announcement'
  );
