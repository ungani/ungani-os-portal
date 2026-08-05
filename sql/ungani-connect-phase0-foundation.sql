-- Ungani Connect - Phase 0: foundation schema only. No UI in this pass
-- (Phase 2 mounts the first real discussion+timeline panel on Tasks).
--
-- Real sources pulled/confirmed before writing this, not guessed:
--   - get_my_ungani_staff_access()'s exact live return shape (re-read in
--     full this session: ok/can_access/tenant_id/is_owner/permissions,
--     permissions keyed by lowercase section name with view/create/
--     edit/delete booleans).
--   - public.users' real columns (id, full_name, email, role, status,
--     tenant_id) - confirmed via sql/pre-launch-data-diagnostic.sql's own
--     real query. Critically: public.users.id IS auth.uid() directly (a
--     1:1 extension table), NOT a separate auth_user_id column -
--     confirmed via sql/check-orphaned-auth-users.sql's join pattern
--     (pu.id = au.id). My first draft assumed a wrong column name here;
--     caught before writing this file, not after.
--   - The real permission section keys from my-team-access.html's own
--     SECTION_LIST (dashboard/money/tasks/items/people/records/
--     documents/calendar/support/reports/billing/package/branches/
--     settings/notifications/tools) - there is NO section for
--     "employees"/"team" at all. Staff management is owner-only today
--     (owner_upsert_ungani_team_member itself gates on
--     is_my_ungani_tenant_owner). That's carried through faithfully
--     below: staff get NO access to Employee-record comments/activity
--     until a real "team" section permission exists - not silently
--     invented here.
--
-- Design, per the confirmed answers to the 4 scoping questions:
--   1. Department channels - separate future work, not part of this file.
--   2. Nia summarization - separate future work, not part of this file.
--   3. Comment permission rule - "if you can see the record, you can
--      comment on it." Implemented as ONE canonical function,
--      can_access_ungani_record(), that reuses get_my_ungani_staff_access()
--      rather than inventing a second permission system. Owners always
--      see everything in their tenant; staff need 'view' on the
--      record's corresponding section - the EXACT same check that
--      already gates whether they can see the record's own page.
--   4. Tasks first for the real Phase 2 rollout - this file is generic
--      across all 7 known record tables so that rollout is just "mount
--      the UI," not "design the schema again."
--
-- Two new tables, both team-visible (NOT the security audit log -
-- ungani_audit_log is a separate, admin-only, immutable compliance
-- trail; this is a different concept with different RLS):
--   ungani_record_comments  - the discussion thread on a record.
--   ungani_record_activity  - the auto-maintained timeline ("09:10
--                              Manager Approved").
-- Both are polymorphic (record_table + record_id) so every record type
-- shares one engine instead of five bespoke tables.

-- ============================================================
-- STEP 1: can_access_ungani_record() - the single canonical permission
-- check both new tables' RLS (and their write RPCs) are built on.
-- Never trusts a caller-supplied tenant_id - resolves the record's real
-- tenant_id directly from its own table, which also doubles as an
-- existence check (a bogus/foreign record_id resolves to null and is
-- correctly denied).
-- ============================================================

create or replace function public.can_access_ungani_record(
  p_record_table text,
  p_record_id uuid
)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_access jsonb;
  v_caller_tenant_id uuid;
  v_record_tenant_id uuid;
  v_section text;
begin
  v_access := public.get_my_ungani_staff_access();

  if coalesce((v_access->>'can_access')::boolean, false) is not true then
    return false;
  end if;

  v_caller_tenant_id := nullif(v_access->>'tenant_id', '')::uuid;
  if v_caller_tenant_id is null then
    return false;
  end if;

  case p_record_table
    when 'tasks' then
      select tenant_id into v_record_tenant_id from public.tasks where id = p_record_id;
    when 'transactions' then
      select tenant_id into v_record_tenant_id from public.transactions where id = p_record_id;
    when 'documents' then
      select tenant_id into v_record_tenant_id from public.documents where id = p_record_id;
    when 'client_people' then
      select tenant_id into v_record_tenant_id from public.client_people where id = p_record_id;
    when 'business_items' then
      select tenant_id into v_record_tenant_id from public.business_items where id = p_record_id;
    when 'business_records' then
      select tenant_id into v_record_tenant_id from public.business_records where id = p_record_id;
    when 'ungani_team_members' then
      select tenant_id into v_record_tenant_id from public.ungani_team_members where id = p_record_id;
    else
      return false;
  end case;

  if v_record_tenant_id is null or v_record_tenant_id != v_caller_tenant_id then
    return false;
  end if;

  if coalesce((v_access->>'is_owner')::boolean, false) then
    return true;
  end if;

  -- Staff: map the record's table to its real, existing permission
  -- section - the same one that already gates the record's own page.
  -- 'ungani_team_members' (Employees) has no staff-facing section at
  -- all today, so this correctly returns false for any non-owner -
  -- owner-only until a real permission for it exists.
  v_section := case p_record_table
    when 'tasks' then 'tasks'
    when 'transactions' then 'money'
    when 'documents' then 'documents'
    when 'client_people' then 'people'
    when 'business_items' then 'items'
    when 'business_records' then 'records'
    else null
  end;

  if v_section is null then
    return false;
  end if;

  return coalesce(((v_access->'permissions'->v_section)->>'view')::boolean, false);
end;
$function$;

grant execute on function public.can_access_ungani_record(text, uuid) to authenticated;

-- ============================================================
-- STEP 2: the two tables.
-- ============================================================

create table if not exists public.ungani_record_comments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  record_table text not null check (record_table in (
    'tasks', 'transactions', 'documents', 'client_people',
    'business_items', 'business_records', 'ungani_team_members'
  )),
  record_id uuid not null,
  author_user_id uuid not null,
  author_name text not null,
  body text not null,
  mentioned_user_ids uuid[] not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz -- soft delete, matches this app's established convention - no hard DELETE anywhere
);

comment on table public.ungani_record_comments is 'Ungani Connect Phase 0: the discussion thread attached to any record (task, payment, document, person, item, business record, or - owner-only today - staff member). Polymorphic via record_table/record_id, one engine for every record type.';

create index if not exists ungani_record_comments_lookup_idx
  on public.ungani_record_comments (tenant_id, record_table, record_id, created_at desc);

create index if not exists ungani_record_comments_mentions_idx
  on public.ungani_record_comments using gin (mentioned_user_ids);

create table if not exists public.ungani_record_activity (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  record_table text not null check (record_table in (
    'tasks', 'transactions', 'documents', 'client_people',
    'business_items', 'business_records', 'ungani_team_members'
  )),
  record_id uuid not null,
  actor_user_id uuid, -- null for a future system/Nia-generated entry
  actor_name text, -- 'Nia' for AI-generated entries, null for pure-system events
  event_type text not null,
  description text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

comment on table public.ungani_record_activity is 'Ungani Connect Phase 0: the team-visible activity timeline on a record ("09:10 Manager Approved"). Deliberately NOT the same table as ungani_audit_log, which is an admin-only, immutable security/compliance trail with different RLS - this is a collaborative feed anyone with view access to the record can see.';

create index if not exists ungani_record_activity_lookup_idx
  on public.ungani_record_activity (tenant_id, record_table, record_id, created_at desc);

alter table public.ungani_record_comments enable row level security;
alter table public.ungani_record_activity enable row level security;

drop policy if exists "Can read comments on accessible records" on public.ungani_record_comments;
create policy "Can read comments on accessible records"
  on public.ungani_record_comments
  for select
  to authenticated
  using (public.can_access_ungani_record(record_table, record_id));

drop policy if exists "Can read activity on accessible records" on public.ungani_record_activity;
create policy "Can read activity on accessible records"
  on public.ungani_record_activity
  for select
  to authenticated
  using (public.can_access_ungani_record(record_table, record_id));

-- Deliberately no INSERT/UPDATE/DELETE policy for authenticated on
-- either table - all writes go through the two SECURITY DEFINER RPCs
-- below, matching the same "narrow wrapper only" pattern already used
-- for create_ungani_notification. Grant SELECT only (governed by the
-- RLS policies above); explicit, not assumed, per the missing-grant
-- bug class found and fixed earlier this session.
grant select on public.ungani_record_comments to authenticated;
grant select on public.ungani_record_activity to authenticated;

-- ============================================================
-- STEP 3: the write path. Both RPCs resolve the real display name
-- directly from public.users (id = auth.uid(), full_name/email both
-- live on that same row - no join needed).
-- ============================================================

create or replace function public.add_ungani_record_comment(
  p_record_table text,
  p_record_id uuid,
  p_body text,
  p_mentioned_user_ids uuid[] default '{}'::uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_access jsonb;
  v_tenant_id uuid;
  v_author_name text;
  v_body text;
  v_comment_id uuid;
begin
  if public.can_access_ungani_record(p_record_table, p_record_id) is not true then
    return jsonb_build_object('ok', false, 'message', 'You do not have access to this record.');
  end if;

  v_access := public.get_my_ungani_staff_access();
  v_tenant_id := nullif(v_access->>'tenant_id', '')::uuid;

  v_body := nullif(trim(coalesce(p_body, '')), '');
  if v_body is null then
    return jsonb_build_object('ok', false, 'message', 'Comment cannot be empty.');
  end if;

  select coalesce(nullif(trim(full_name), ''), split_part(email, '@', 1))
  into v_author_name
  from public.users
  where id = auth.uid();

  insert into public.ungani_record_comments (
    tenant_id, record_table, record_id, author_user_id, author_name, body, mentioned_user_ids
  ) values (
    v_tenant_id, p_record_table, p_record_id, auth.uid(),
    coalesce(v_author_name, 'Someone'), v_body, coalesce(p_mentioned_user_ids, '{}'::uuid[])
  )
  returning id into v_comment_id;

  -- Every comment is also a timeline entry - the same event, two views
  -- (matches the spec's own "09:40 Finance Commented" timeline example).
  -- Notification delivery for mentions/new comments is explicitly Phase
  -- 4 work, not built here - mentioned_user_ids is stored so that phase
  -- has what it needs without a schema change.
  insert into public.ungani_record_activity (
    tenant_id, record_table, record_id, actor_user_id, actor_name, event_type, description
  ) values (
    v_tenant_id, p_record_table, p_record_id, auth.uid(), coalesce(v_author_name, 'Someone'),
    'commented', coalesce(v_author_name, 'Someone') || ' commented.'
  );

  return jsonb_build_object('ok', true, 'comment_id', v_comment_id);
end;
$function$;

grant execute on function public.add_ungani_record_comment(text, uuid, text, uuid[]) to authenticated;

-- General-purpose timeline helper for FUTURE phases (Phase 2's task
-- status-change logging, Phase 3's approval/upload events, etc.) - not
-- called anywhere yet in this migration. Built now so Phase 2 only has
-- to call it, not design it.
create or replace function public.log_ungani_record_activity(
  p_record_table text,
  p_record_id uuid,
  p_event_type text,
  p_description text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_access jsonb;
  v_tenant_id uuid;
  v_author_name text;
begin
  if public.can_access_ungani_record(p_record_table, p_record_id) is not true then
    return jsonb_build_object('ok', false, 'message', 'You do not have access to this record.');
  end if;

  v_access := public.get_my_ungani_staff_access();
  v_tenant_id := nullif(v_access->>'tenant_id', '')::uuid;

  select coalesce(nullif(trim(full_name), ''), split_part(email, '@', 1))
  into v_author_name
  from public.users
  where id = auth.uid();

  insert into public.ungani_record_activity (
    tenant_id, record_table, record_id, actor_user_id, actor_name, event_type, description, metadata
  ) values (
    v_tenant_id, p_record_table, p_record_id, auth.uid(), coalesce(v_author_name, 'Someone'),
    coalesce(nullif(trim(p_event_type), ''), 'activity'),
    coalesce(nullif(trim(p_description), ''), 'Activity recorded.'),
    coalesce(p_metadata, '{}'::jsonb)
  );

  return jsonb_build_object('ok', true);
end;
$function$;

grant execute on function public.log_ungani_record_activity(text, uuid, text, text, jsonb) to authenticated;

-- ============================================================
-- VERIFICATION - confirm everything landed. Run all of these and paste
-- back the output, same as every other migration this session.
-- ============================================================

-- 1. Both tables exist with RLS enabled.
select relname, relrowsecurity
from pg_class
where relname in ('ungani_record_comments', 'ungani_record_activity')
  and relnamespace = 'public'::regnamespace;

-- 2. Real column list for both (should match the create table statements
-- above exactly).
select table_name, column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name in ('ungani_record_comments', 'ungani_record_activity')
order by table_name, ordinal_position;

-- 3. RLS policies present (expect exactly 1 select policy per table,
-- no insert/update/delete policies for authenticated at all).
select schemaname, tablename, policyname, roles, cmd
from pg_policies
where schemaname = 'public'
  and tablename in ('ungani_record_comments', 'ungani_record_activity');

-- 4. All 4 new functions exist and are owned/callable as expected.
select p.proname, pg_get_function_identity_arguments(p.oid) as arguments
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'can_access_ungani_record',
    'add_ungani_record_comment',
    'log_ungani_record_activity'
  )
order by p.proname;

-- 5. Real grants confirm authenticated has SELECT (not INSERT/UPDATE/
-- DELETE) on both tables, and EXECUTE on all 3 functions.
select table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in ('ungani_record_comments', 'ungani_record_activity')
  and grantee = 'authenticated'
order by table_name, privilege_type;

select routine_name, privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public'
  and routine_name in ('can_access_ungani_record', 'add_ungani_record_comment', 'log_ungani_record_activity')
  and grantee = 'authenticated';

-- ============================================================
-- OPTIONAL real-data sanity check - pick any real task id from your
-- account and try commenting on it as yourself (should succeed since
-- you're the owner). Replace YOUR_REAL_TASK_ID first.
-- ============================================================

-- select id, task_title from public.tasks order by created_at desc limit 5;
-- select public.add_ungani_record_comment('tasks', 'YOUR_REAL_TASK_ID'::uuid, 'Phase 0 test comment - safe to ignore/delete.');
-- select * from public.ungani_record_comments where record_table = 'tasks' order by created_at desc limit 5;
-- select * from public.ungani_record_activity where record_table = 'tasks' order by created_at desc limit 5;
