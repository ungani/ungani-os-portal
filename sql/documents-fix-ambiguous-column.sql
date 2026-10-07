-- get_my_ungani_storage_usage() has a real bug: RETURNS TABLE implicitly
-- declares "storage_limit_mb" as an OUT variable in the function body,
-- which collides with 2 bare (unqualified) references to the
-- tenants.storage_limit_mb and ungani_packages.storage_limit_mb columns
-- inside the function - Postgres can't tell which one is meant
-- ("column reference storage_limit_mb is ambiguous"), confirmed live via
-- a direct RPC call returning HTTP 400/42702. Fixed by qualifying both
-- references with their table alias. Same signature as what's live now,
-- so CREATE OR REPLACE is correct here (no DROP needed).

create or replace function public.get_my_ungani_storage_usage()
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

  select package_key into v_package_key
  from public.ungani_subscriptions where tenant_id = v_tenant_id;

  select t.storage_limit_mb into v_override_mb from public.tenants t where t.id = v_tenant_id;

  if v_package_key is null then
    select t.package_key into v_package_key from public.tenants t where t.id = v_tenant_id;
  end if;

  select coalesce(v_override_mb, p.storage_limit_mb, 500)
  into v_limit_mb
  from public.ungani_packages p
  where p.package_key = v_package_key;

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
