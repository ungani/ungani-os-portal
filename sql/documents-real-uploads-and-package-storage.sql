-- DOCUMENTS: real file uploads + per-package Storage limits
-- CORRECTED, idempotent, transaction-wrapped version.
--
-- Approved storage tiers (Chris): Starter 1 GB, Growth 5 GB, Business
-- 20 GB, Custom 100 GB, admin can override per tenant.
--
-- FIX FOR THE FAILED RUN: the first version had no `begin`, only a
-- trailing `commit`, so STEP 1-4 below already landed and committed
-- independently before STEP 5 errored ("cannot change return type of
-- existing function... Use DROP FUNCTION first" - CREATE OR REPLACE
-- cannot change a function's OUTPUT columns, only CREATE FUNCTION after
-- an explicit DROP can). Fixed by:
--   (a) wrapping the whole file in begin/commit so a failure anywhere
--       rolls back everything, not just the one statement;
--   (b) explicit DROP FUNCTION before both get_my_ungani_storage_usage()
--       and admin_get_ungani_storage_usage() (both changed their output
--       columns from the live version);
--   (c) every other statement was already idempotent (ADD COLUMN IF NOT
--       EXISTS / ON CONFLICT DO NOTHING / DROP POLICY IF EXISTS / plain
--       UPDATEs) so re-running STEP 1-4 on top of what already landed is
--       harmless.
--
-- ALSO CLOSES A GAP caught before this ran again: the storage.objects
-- RLS policies in the first version only checked tenant_id (any member
-- of the business, regardless of their own Documents permission, could
-- enumerate/open any file in their tenant's folder via a direct Storage
-- API call, bypassing the app's own UI-level gating in
-- staff-visibility-filter.js). Fixed by adding the same
-- can_access_ungani_section('documents', <action>) check the documents
-- TABLE's own RLS already uses (confirmed live via 2 independent files:
-- my-team-access.html's permission grid row ["documents", "Documents"]
-- and staff-visibility-filter.js's "my-documents.html": "documents" page
-- map - so 'documents' is confirmed the real section_key, not guessed).
--
-- Real package_key values confirmed live via REST:
-- starter(2 users)/growth(5)/business(10)/custom(null).

begin;

-- ============================================================
-- STEP 1: per-package storage tier, tenant column becomes an ADMIN
-- OVERRIDE (null = no override, use the package's tier).
-- ============================================================
alter table public.ungani_packages
  add column if not exists storage_limit_mb integer;

update public.ungani_packages set storage_limit_mb = 1024 where package_key = 'starter';
update public.ungani_packages set storage_limit_mb = 5120 where package_key = 'growth';
update public.ungani_packages set storage_limit_mb = 20480 where package_key = 'business';
update public.ungani_packages set storage_limit_mb = 102400 where package_key = 'custom';

alter table public.tenants
  alter column storage_limit_mb drop not null,
  alter column storage_limit_mb drop default;

update public.tenants set storage_limit_mb = null where storage_limit_mb = 500;

-- ============================================================
-- STEP 2: real file bytes on documents.
-- ============================================================
alter table public.documents
  add column if not exists file_size_bytes bigint;

-- ============================================================
-- STEP 3: private Storage bucket for real document uploads. SELECT is
-- gated by BOTH tenant-folder match AND the same per-staff Documents
-- permission the documents table itself enforces - closes the
-- enumerate-via-raw-Storage-API gap. INSERT/UPDATE/DELETE require
-- 'edit' on the same section.
-- ============================================================
insert into storage.buckets (id, name, public)
values ('documents', 'documents', false)
on conflict (id) do nothing;

drop policy if exists documents_bucket_select on storage.objects;
create policy documents_bucket_select on storage.objects
  for select
  using (
    bucket_id = 'documents'
    and (storage.foldername(name))[1] = public.get_my_ungani_tenant_id()::text
    and public.can_access_ungani_section('documents', 'view')
  );

drop policy if exists documents_bucket_insert on storage.objects;
create policy documents_bucket_insert on storage.objects
  for insert
  with check (
    bucket_id = 'documents'
    and (storage.foldername(name))[1] = public.get_my_ungani_tenant_id()::text
    and public.can_access_ungani_section('documents', 'edit')
  );

drop policy if exists documents_bucket_update on storage.objects;
create policy documents_bucket_update on storage.objects
  for update
  using (
    bucket_id = 'documents'
    and (storage.foldername(name))[1] = public.get_my_ungani_tenant_id()::text
    and public.can_access_ungani_section('documents', 'edit')
  );

drop policy if exists documents_bucket_delete on storage.objects;
create policy documents_bucket_delete on storage.objects
  for delete
  using (
    bucket_id = 'documents'
    and (storage.foldername(name))[1] = public.get_my_ungani_tenant_id()::text
    and public.can_access_ungani_section('documents', 'edit')
  );

-- ============================================================
-- STEP 4: admin override RPC.
-- ============================================================
create or replace function public.admin_set_ungani_storage_override(
  p_tenant_id uuid,
  p_override_mb integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (select public.is_ungani_admin()) then
    return jsonb_build_object('ok', false, 'message', 'Access denied: admin only.');
  end if;

  if p_override_mb is not null and p_override_mb <= 0 then
    return jsonb_build_object('ok', false, 'message', 'Override must be a positive number of MB, or null to clear it.');
  end if;

  update public.tenants
  set storage_limit_mb = p_override_mb
  where id = p_tenant_id;

  if not found then
    return jsonb_build_object('ok', false, 'message', 'Tenant not found.');
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.admin_set_ungani_storage_override(uuid, integer) from public, anon;
grant execute on function public.admin_set_ungani_storage_override(uuid, integer) to authenticated;

-- ============================================================
-- STEP 5: get_my_ungani_storage_usage() - explicit DROP first since the
-- output columns change (proof_file_count/proof_bytes_used ->
-- file_count/bytes_used). Fixed bigint/numeric bug, counts BOTH
-- payment proofs and uploaded documents, resolves the effective limit
-- as coalesce(tenant override, package tier, 500 fallback).
-- ============================================================
drop function if exists public.get_my_ungani_storage_usage();

create function public.get_my_ungani_storage_usage()
returns table (
  file_count bigint,
  bytes_used bigint,
  storage_limit_mb integer,
  percent_used numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tenant_id uuid := public.get_my_ungani_tenant_id();
  v_limit_mb integer;
  v_override_mb integer;
  v_package_key text;
begin
  if v_tenant_id is null then
    raise exception 'No tenant found for current user';
  end if;

  -- Same package_key resolution order as owner_upsert_ungani_team_member
  -- (ungani_subscriptions first, tenants fallback) - using tenants alone
  -- re-introduces the exact drift bug that function was fixed for.
  select package_key into v_package_key
  from public.ungani_subscriptions where tenant_id = v_tenant_id;

  select storage_limit_mb into v_override_mb from public.tenants where id = v_tenant_id;

  if v_package_key is null then
    select package_key into v_package_key from public.tenants where id = v_tenant_id;
  end if;

  select coalesce(v_override_mb, storage_limit_mb, 500)
  into v_limit_mb
  from public.ungani_packages
  where package_key = v_package_key;

  if v_limit_mb is null then
    v_limit_mb := coalesce(v_override_mb, 500);
  end if;

  return query
    select
      (coalesce((select count(*) from public.ungani_payment_proofs pp where pp.tenant_id = v_tenant_id), 0)
        + coalesce((select count(*) from public.documents d where d.tenant_id = v_tenant_id and d.document_source = 'upload' and d.deleted_at is null), 0))::bigint as file_count,
      (coalesce((select sum(pp.proof_file_size) from public.ungani_payment_proofs pp where pp.tenant_id = v_tenant_id), 0)
        + coalesce((select sum(d.file_size_bytes) from public.documents d where d.tenant_id = v_tenant_id and d.document_source = 'upload' and d.deleted_at is null), 0))::bigint as bytes_used,
      v_limit_mb as storage_limit_mb,
      round(
        (coalesce((select sum(pp.proof_file_size) from public.ungani_payment_proofs pp where pp.tenant_id = v_tenant_id), 0)
          + coalesce((select sum(d.file_size_bytes) from public.documents d where d.tenant_id = v_tenant_id and d.document_source = 'upload' and d.deleted_at is null), 0))::numeric
          / nullif(v_limit_mb::numeric * 1048576, 0) * 100,
        1
      ) as percent_used;
end;
$$;

revoke all on function public.get_my_ungani_storage_usage() from public, anon;
grant execute on function public.get_my_ungani_storage_usage() to authenticated;

-- ============================================================
-- STEP 6: admin_get_ungani_storage_usage() - explicit DROP first (added
-- the is_override output column + renamed the other two).
-- ============================================================
drop function if exists public.admin_get_ungani_storage_usage();

create function public.admin_get_ungani_storage_usage()
returns table (
  tenant_id uuid,
  business_name text,
  file_count bigint,
  bytes_used bigint,
  storage_limit_mb integer,
  is_override boolean,
  percent_used numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not (select public.is_ungani_admin()) then
    raise exception 'Access denied: admin only';
  end if;

  return query
    select
      t.id as tenant_id,
      coalesce(t.business_name, t.company_name, t.name, 'Unnamed business') as business_name,
      (coalesce(pr.file_count, 0) + coalesce(doc.file_count, 0))::bigint as file_count,
      (coalesce(pr.bytes_used, 0) + coalesce(doc.bytes_used, 0))::bigint as bytes_used,
      coalesce(t.storage_limit_mb, pk.storage_limit_mb, 500) as storage_limit_mb,
      (t.storage_limit_mb is not null) as is_override,
      round(
        (coalesce(pr.bytes_used, 0) + coalesce(doc.bytes_used, 0))::numeric
          / nullif(coalesce(t.storage_limit_mb, pk.storage_limit_mb, 500)::numeric * 1048576, 0) * 100,
        1
      ) as percent_used
    from public.tenants t
    left join public.ungani_subscriptions sub on sub.tenant_id = t.id
    left join public.ungani_packages pk on pk.package_key = coalesce(sub.package_key, t.package_key)
    left join (
      select pp.tenant_id, count(*) as file_count, sum(coalesce(pp.proof_file_size, 0)) as bytes_used
      from public.ungani_payment_proofs pp
      group by pp.tenant_id
    ) pr on pr.tenant_id = t.id
    left join (
      select d.tenant_id, count(*) as file_count, sum(coalesce(d.file_size_bytes, 0)) as bytes_used
      from public.documents d
      where d.document_source = 'upload' and d.deleted_at is null
      group by d.tenant_id
    ) doc on doc.tenant_id = t.id
    where t.is_test is distinct from true
    order by (coalesce(pr.bytes_used, 0) + coalesce(doc.bytes_used, 0)) desc;
end;
$$;

revoke all on function public.admin_get_ungani_storage_usage() from public, anon;
grant execute on function public.admin_get_ungani_storage_usage() to authenticated;

-- ============================================================
-- VERIFICATION (inside the same transaction - if anything above failed,
-- we never reach here and the whole thing rolls back).
-- ============================================================
select package_key, storage_limit_mb from public.ungani_packages order by sort_order;

select id, name, public from storage.buckets where id = 'documents';

select policyname, cmd from pg_policies
where schemaname = 'storage' and tablename = 'objects' and policyname like 'documents_bucket_%'
order by policyname;

select column_name from information_schema.columns
where table_schema = 'public' and table_name = 'documents' and column_name = 'file_size_bytes';

select p.proname, pg_get_function_identity_arguments(p.oid) as args
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('get_my_ungani_storage_usage', 'admin_get_ungani_storage_usage', 'admin_set_ungani_storage_override');

select p.proname, count(*) as overload_count
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('get_my_ungani_storage_usage', 'admin_get_ungani_storage_usage', 'admin_set_ungani_storage_override')
group by p.proname
order by p.proname;

commit;
