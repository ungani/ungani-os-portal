-- ============================================================
-- Education vertical Phase 1: sub-type registration + role presets +
-- entity plumbing (Students/Teachers/Classes), for Primary School / High
-- School / College sub-types of the EXISTING "school" business type
-- (ungani-business-config.js key "school" - NOT a new "education" key,
-- since "education" is already a match keyword on "school" and a new key
-- would collide).
--
-- Scope locked in earlier this session: extend client_people (Students/
-- Parents already generic there) and ungani_team_members+Payroll
-- (Teachers/Admin already generic there) rather than new tables for
-- those; the two genuinely new pieces of plumbing are the sub-type
-- columns on tenants and a real many-to-many Class<->Student linking
-- table (built for all 3 sub-types from day one, per confirmed decision -
-- Primary/High School just always has ~1 row per student in practice,
-- College has genuinely many per student per semester, same table shape
-- serves both).
--
-- Explicitly NOT in this migration (per the agreed phasing):
--   - Class/Subject ITEM_FIELD_SETS entries (Phase 2)
--   - Enrollment picker UI (Phase 2)
--   - Per-sub-type dashboard content (Phase 3)
--   - Fee structure + bulk invoicing + Debtors/Payables customer_person_id
--     grouping fix (Phase 4)
-- ============================================================

-- ============================================================
-- PART A: sub-type columns on tenants, mirroring business_type/
-- business_type_key exactly. Nullable/optional - every non-School
-- tenant, and any School tenant registered before this shipped, simply
-- has both null.
-- ============================================================

alter table public.tenants
  add column if not exists business_sub_type text,
  add column if not exists business_sub_type_key text;

-- Registration is a two-step flow: index.html inserts into `registrations`
-- (pending), then an admin approval copies fields across into `tenants`.
-- The sub-type choice needs to survive that same trip, so it needs the
-- same two columns on `registrations` too.
alter table public.registrations
  add column if not exists business_sub_type text,
  add column if not exists business_sub_type_key text;

-- ============================================================
-- PART B: which teacher/lecturer teaches this class - mirrors the exact
-- shape of transactions.related_team_member_id (sql/payroll-staff-payment-
-- tracking.sql:29).
-- ============================================================

alter table public.business_items
  add column if not exists assigned_team_member_id uuid references public.ungani_team_members(id);

-- ============================================================
-- PART C: ungani_class_enrollments - many-to-many Student<->Class table,
-- serving all 3 sub-types. RLS/RPC shape copied from the most recent
-- precedent for a new operational (non-credential) table,
-- ungani_commitments (sql/cluster4-commitments.sql) - tenant-scoped
-- select policy + owner-checked security-definer RPCs, NOT the Vault/
-- RLS-off pattern (that's reserved for tables storing financial
-- credentials like M-Pesa/banking connections).
-- ============================================================

create table if not exists public.ungani_class_enrollments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,

  student_person_id uuid not null references public.client_people(id) on delete cascade,
  class_item_id uuid not null references public.business_items(id) on delete cascade,

  status text not null default 'active',
  -- 'active' | 'completed' | 'dropped'

  enrolled_at timestamptz not null default now(),
  ended_at timestamptz,

  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint ungani_class_enrollments_status_check
    check (status in ('active', 'completed', 'dropped')),
  constraint ungani_class_enrollments_unique_active
    unique (student_person_id, class_item_id, status)
);

create index if not exists ungani_class_enrollments_tenant_idx
  on public.ungani_class_enrollments (tenant_id);
create index if not exists ungani_class_enrollments_student_idx
  on public.ungani_class_enrollments (student_person_id);
create index if not exists ungani_class_enrollments_class_idx
  on public.ungani_class_enrollments (class_item_id);

alter table public.ungani_class_enrollments enable row level security;

drop policy if exists ungani_class_enrollments_tenant_select on public.ungani_class_enrollments;
create policy ungani_class_enrollments_tenant_select on public.ungani_class_enrollments
  for select
  using (tenant_id = public.get_my_ungani_tenant_id());

grant select on public.ungani_class_enrollments to authenticated;

-- owner_upsert_ungani_class_enrollment: creates or updates (by id) an
-- enrollment row. Enrolling the same student in the same class again
-- after a 'dropped'/'completed' row exists is allowed (the unique
-- constraint is scoped to status, so a new 'active' row can coexist with
-- an old 'dropped' one - re-enrollment history is preserved, not
-- overwritten).
create or replace function public.owner_upsert_ungani_class_enrollment(
  p_enrollment_id uuid default null,
  p_student_person_id uuid default null,
  p_class_item_id uuid default null,
  p_status text default 'active'
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_enrollment_id uuid;
  v_clean_status text;
  v_student_tenant_check uuid;
  v_class_tenant_check uuid;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if public.is_my_ungani_tenant_owner(v_tenant_id) is not true then
    return jsonb_build_object('ok', false, 'message', 'Only the business owner can manage enrollments.');
  end if;

  if p_student_person_id is null or p_class_item_id is null then
    return jsonb_build_object('ok', false, 'message', 'A student and a class are both required.');
  end if;

  select tenant_id into v_student_tenant_check from public.client_people where id = p_student_person_id;
  if v_student_tenant_check is distinct from v_tenant_id then
    return jsonb_build_object('ok', false, 'message', 'That student does not belong to your business.');
  end if;

  select tenant_id into v_class_tenant_check from public.business_items where id = p_class_item_id;
  if v_class_tenant_check is distinct from v_tenant_id then
    return jsonb_build_object('ok', false, 'message', 'That class does not belong to your business.');
  end if;

  v_clean_status := lower(trim(coalesce(p_status, 'active')));
  if v_clean_status not in ('active', 'completed', 'dropped') then
    v_clean_status := 'active';
  end if;

  if p_enrollment_id is not null then
    update public.ungani_class_enrollments
    set student_person_id = p_student_person_id,
        class_item_id = p_class_item_id,
        status = v_clean_status,
        ended_at = case when v_clean_status in ('completed', 'dropped') then now() else null end,
        updated_at = now()
    where id = p_enrollment_id and tenant_id = v_tenant_id
    returning id into v_enrollment_id;

    if v_enrollment_id is null then
      return jsonb_build_object('ok', false, 'message', 'Enrollment not found.');
    end if;

    return jsonb_build_object('ok', true, 'id', v_enrollment_id, 'mode', 'updated');
  end if;

  insert into public.ungani_class_enrollments (
    tenant_id, student_person_id, class_item_id, status, created_by
  )
  values (
    v_tenant_id, p_student_person_id, p_class_item_id, v_clean_status, auth.uid()
  )
  returning id into v_enrollment_id;

  return jsonb_build_object('ok', true, 'id', v_enrollment_id, 'mode', 'created');
exception
  when unique_violation then
    return jsonb_build_object('ok', false, 'message', 'That student already has an enrollment with this exact status for this class.');
end;
$function$;

revoke all on function public.owner_upsert_ungani_class_enrollment(uuid, uuid, uuid, text) from public;
grant execute on function public.owner_upsert_ungani_class_enrollment(uuid, uuid, uuid, text) to authenticated;

-- ============================================================
-- PART D: new role-preset branches - Teacher/Lecturer and Administration.
-- Purely additive to the single-param ungani_role_preset_sections()
-- function (no signature change, so this is safe to create-or-replace
-- directly, unlike Part E below). Reproduces the real, current 5-role
-- body verbatim (from sql/staff-role-presets-accountant-frontdesk.sql,
-- the confirmed-live version with accountant/frontdesk already added)
-- and adds 'teacher' and 'administration' as two more elsif branches.
--
-- Proposed defaults (following the same "propose then confirm" step used
-- for Accountant/Front Desk - please review before running):
--   Teacher/Lecturer: view/create/edit (no delete) on Tasks/Calendar
--     (their own class schedule, follow-ups), view-only on People (their
--     students) and Items (their assigned classes). No access to
--     Money/Records/Documents/Support/Reports - a teacher manages their
--     classes and students, not the business's finances or records.
--   Administration: broader front-office role - view/create/edit (no
--     delete) on People/Tasks/Records/Documents/Calendar, view-only on
--     Items and Reports. No access to Money (deliberately - matches
--     Front Desk's precedent of keeping non-Accountant roles out of
--     Money) or Support. Same owner-only lockout on billing/package/
--     branches/settings as every other non-owner role.
-- ============================================================

create or replace function public.ungani_role_preset_sections(p_role_key text)
returns table(section_key text, can_view boolean, can_create boolean, can_edit boolean, can_delete boolean)
language plpgsql
immutable
as $function$
declare
  v_role text := lower(trim(coalesce(p_role_key, 'staff')));
begin
  if v_role = 'viewer' then
    return query select * from (values
      ('dashboard', true, false, false, false),
      ('money', true, false, false, false),
      ('tasks', true, false, false, false),
      ('items', true, false, false, false),
      ('people', true, false, false, false),
      ('records', true, false, false, false),
      ('documents', true, false, false, false),
      ('calendar', true, false, false, false),
      ('support', true, false, false, false),
      ('reports', true, false, false, false),
      ('billing', false, false, false, false),
      ('package', false, false, false, false),
      ('branches', false, false, false, false),
      ('settings', false, false, false, false),
      ('notifications', true, false, false, false),
      ('tools', true, false, false, false)
    ) as t(section_key, can_view, can_create, can_edit, can_delete);
  elsif v_role = 'manager' then
    return query select * from (values
      ('dashboard', true, false, false, false),
      ('money', true, true, true, true),
      ('tasks', true, true, true, true),
      ('items', true, true, true, true),
      ('people', true, true, true, true),
      ('records', true, true, true, true),
      ('documents', true, true, true, true),
      ('calendar', true, true, true, true),
      ('support', true, true, true, true),
      ('reports', true, false, false, false),
      ('billing', false, false, false, false),
      ('package', false, false, false, false),
      ('branches', true, false, false, false),
      ('settings', false, false, false, false),
      ('notifications', true, false, false, false),
      ('tools', true, false, false, false)
    ) as t(section_key, can_view, can_create, can_edit, can_delete);
  elsif v_role = 'accountant' then
    return query select * from (values
      ('dashboard', true, false, false, false),
      ('money', true, true, true, true),
      ('tasks', false, false, false, false),
      ('items', false, false, false, false),
      ('people', true, false, false, false),
      ('records', false, false, false, false),
      ('documents', true, false, false, false),
      ('calendar', false, false, false, false),
      ('support', false, false, false, false),
      ('reports', true, false, false, false),
      ('billing', false, false, false, false),
      ('package', false, false, false, false),
      ('branches', false, false, false, false),
      ('settings', false, false, false, false),
      ('notifications', true, false, false, false),
      ('tools', true, false, false, false)
    ) as t(section_key, can_view, can_create, can_edit, can_delete);
  elsif v_role = 'frontdesk' then
    return query select * from (values
      ('dashboard', true, false, false, false),
      ('money', false, false, false, false),
      ('tasks', true, true, true, false),
      ('items', false, false, false, false),
      ('people', true, true, true, false),
      ('records', false, false, false, false),
      ('documents', false, false, false, false),
      ('calendar', true, true, true, false),
      ('support', false, false, false, false),
      ('reports', false, false, false, false),
      ('billing', false, false, false, false),
      ('package', false, false, false, false),
      ('branches', false, false, false, false),
      ('settings', false, false, false, false),
      ('notifications', true, false, false, false),
      ('tools', true, false, false, false)
    ) as t(section_key, can_view, can_create, can_edit, can_delete);
  elsif v_role = 'teacher' then
    return query select * from (values
      ('dashboard', true, false, false, false),
      ('money', false, false, false, false),
      ('tasks', true, true, true, false),
      ('items', true, false, false, false),
      ('people', true, false, false, false),
      ('records', false, false, false, false),
      ('documents', false, false, false, false),
      ('calendar', true, true, true, false),
      ('support', false, false, false, false),
      ('reports', false, false, false, false),
      ('billing', false, false, false, false),
      ('package', false, false, false, false),
      ('branches', false, false, false, false),
      ('settings', false, false, false, false),
      ('notifications', true, false, false, false),
      ('tools', true, false, false, false)
    ) as t(section_key, can_view, can_create, can_edit, can_delete);
  elsif v_role = 'administration' then
    return query select * from (values
      ('dashboard', true, false, false, false),
      ('money', false, false, false, false),
      ('tasks', true, true, true, false),
      ('items', true, false, false, false),
      ('people', true, true, true, false),
      ('records', true, true, true, false),
      ('documents', true, true, true, false),
      ('calendar', true, true, true, false),
      ('support', false, false, false, false),
      ('reports', true, false, false, false),
      ('billing', false, false, false, false),
      ('package', false, false, false, false),
      ('branches', false, false, false, false),
      ('settings', false, false, false, false),
      ('notifications', true, false, false, false),
      ('tools', true, false, false, false)
    ) as t(section_key, can_view, can_create, can_edit, can_delete);
  else
    -- 'staff' (also the fallback for any unrecognized role_key, matching
    -- owner_upsert_ungani_team_member's own default-to-'staff' behavior).
    return query select * from (values
      ('dashboard', true, false, false, false),
      ('money', true, true, false, false),
      ('tasks', true, true, true, false),
      ('items', true, true, true, false),
      ('people', true, true, true, false),
      ('records', true, true, true, false),
      ('documents', true, true, true, false),
      ('calendar', true, true, true, false),
      ('support', true, true, true, false),
      ('reports', true, false, false, false),
      ('billing', false, false, false, false),
      ('package', false, false, false, false),
      ('branches', false, false, false, false),
      ('settings', false, false, false, false),
      ('notifications', true, false, false, false),
      ('tools', true, false, false, false)
    ) as t(section_key, can_view, can_create, can_edit, can_delete);
  end if;
end;
$function$;

-- ============================================================
-- PART E: DIAGNOSTIC ONLY - do not skip. owner_upsert_ungani_team_member
-- has been redefined many times across this project's history (11
-- separate migration files touch it) and has been recreated from a STALE
-- signature twice before (see memory: "Verify SQL Signature Before Edit",
-- "Fix + re-run corrected trial 1-user cap SQL"). Rather than guess at
-- the current live body and risk creating a THIRD stale overload, please
-- run this and paste back the output - the role allowlist inside that
-- function needs 'teacher' and 'administration' added (currently:
-- 'owner','manager','staff','viewer','accountant','frontdesk' - anything
-- else silently falls back to 'staff'), and I'll write that one-line
-- change against your actual current definition, not a guessed one.
-- ============================================================

select pg_get_functiondef(p.oid) as current_live_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'owner_upsert_ungani_team_member';

-- Second diagnostic, same reasoning: approve_ungani_registration is the
-- function that copies a registrations row's fields across into a new
-- tenants row on admin approval (11 separate migration files touch
-- owner_upsert_ungani_team_member alone, and approve_ungani_registration
-- has its own multi-file edit history too - sql/partner-referral-
-- system.sql, sql/approval-confirmation-email.sql, and others). Until I
-- have its real current body, business_sub_type/business_sub_type_key
-- will sit correctly on the registrations row but will NOT automatically
-- carry across to the resulting tenant - please paste this output back
-- so I can add that one copy-through against your actual live version.
select pg_get_functiondef(p.oid) as current_live_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'approve_ungani_registration';

-- ============================================================
-- VERIFICATION
-- ============================================================

select column_name, data_type, is_nullable
from information_schema.columns
where table_name = 'tenants' and column_name in ('business_sub_type', 'business_sub_type_key');

select column_name, data_type, is_nullable
from information_schema.columns
where table_name = 'registrations' and column_name in ('business_sub_type', 'business_sub_type_key');

select column_name, data_type
from information_schema.columns
where table_name = 'business_items' and column_name = 'assigned_team_member_id';

select tablename, rowsecurity
from pg_tables
where tablename = 'ungani_class_enrollments';

select 'teacher' as role, * from public.ungani_role_preset_sections('teacher')
union all
select 'administration' as role, * from public.ungani_role_preset_sections('administration')
order by role, section_key;
