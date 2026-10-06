-- =====================================================================
-- sql/storage-usage-tracking.sql
--
-- Storage Usage feature (Property Readiness item 8). Scoped to what's
-- actually true today: UNGANI only hosts bytes in two Supabase Storage
-- buckets - "payment-proofs" (sized per upload via
-- ungani_payment_proofs.proof_file_size, confirmed live) and
-- "tenant-branding" (exactly one logo file per tenant, size not tracked
-- anywhere since it's a single bounded file, not a growing collection).
-- my-documents.html's "documents" table stores external URLs / Google
-- Drive links (documents.file_url), never an uploaded file, so it is
-- deliberately NOT counted here - counting it would overstate usage
-- against bytes UNGANI never stored.
--
-- No quota concept exists anywhere pre-migration (confirmed: no
-- storage_limit column on tenants or ungani_packages). Adds one flat
-- limit column on tenants rather than a new per-package tier system,
-- since real usage today is near-zero across every tenant and a tiered
-- quota would be solving a problem nobody has hit yet.
-- =====================================================================

alter table public.tenants
  add column if not exists storage_limit_mb integer not null default 500;

-- ---------------------------------------------------------------------
-- 1. admin-storage.html: one row per tenant, sorted biggest-first.
--    Admin-only (platform-wide, no tenant_id scoping), same security
--    pattern as sql/admin-money-aggregate-rpcs.sql.
-- ---------------------------------------------------------------------
create or replace function public.admin_get_ungani_storage_usage()
returns table (
  tenant_id uuid,
  business_name text,
  proof_file_count bigint,
  proof_bytes_used bigint,
  storage_limit_mb integer,
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
      coalesce(p.file_count, 0) as proof_file_count,
      coalesce(p.bytes_used, 0) as proof_bytes_used,
      t.storage_limit_mb,
      round(
        coalesce(p.bytes_used, 0)::numeric
          / nullif(t.storage_limit_mb::numeric * 1048576, 0) * 100,
        1
      ) as percent_used
    from public.tenants t
    left join (
      select
        pp.tenant_id,
        count(*) as file_count,
        sum(coalesce(pp.proof_file_size, 0)) as bytes_used
      from public.ungani_payment_proofs pp
      group by pp.tenant_id
    ) p on p.tenant_id = t.id
    where t.is_test is distinct from true
    order by coalesce(p.bytes_used, 0) desc;
end;
$$;

revoke all on function public.admin_get_ungani_storage_usage() from public, anon;
grant execute on function public.admin_get_ungani_storage_usage() to authenticated;

-- ---------------------------------------------------------------------
-- 2. my-settings.html: one tenant's own usage line.
--    Tenant-scoped to the caller via get_my_ungani_tenant_id(), the
--    same resolver every other per-tenant RPC in this codebase uses.
-- ---------------------------------------------------------------------
create or replace function public.get_my_ungani_storage_usage()
returns table (
  proof_file_count bigint,
  proof_bytes_used bigint,
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
begin
  if v_tenant_id is null then
    raise exception 'No tenant found for current user';
  end if;

  select t.storage_limit_mb into v_limit_mb
  from public.tenants t
  where t.id = v_tenant_id;

  return query
    select
      count(*) as proof_file_count,
      coalesce(sum(pp.proof_file_size), 0) as proof_bytes_used,
      v_limit_mb as storage_limit_mb,
      round(
        coalesce(sum(pp.proof_file_size), 0)::numeric
          / nullif(v_limit_mb::numeric * 1048576, 0) * 100,
        1
      ) as percent_used
    from public.ungani_payment_proofs pp
    where pp.tenant_id = v_tenant_id;
end;
$$;

revoke all on function public.get_my_ungani_storage_usage() from public, anon;
grant execute on function public.get_my_ungani_storage_usage() to authenticated;
