-- admin_get_ungani_email_queue() previously returned every column of
-- every row, unbounded (no limit) - confirmed live via its real
-- definition (pasted back): all 17 ungani_email_queue columns including
-- the full email_body text, no resolved_at/resolution_note (added this
-- session, sql/email-queue-resolved-tracking.sql), no limit/offset.
-- Return type changes (2 new columns), so DROP FUNCTION first - CREATE
-- OR REPLACE cannot alter output columns (confirmed earlier this
-- session on a different function, same Postgres rule).

begin;

drop function if exists public.admin_get_ungani_email_queue();

create function public.admin_get_ungani_email_queue(
  p_limit integer default 100,
  p_offset integer default 0
)
returns table (
  id uuid,
  tenant_id uuid,
  user_id uuid,
  recipient_email text,
  recipient_name text,
  email_type text,
  email_subject text,
  email_body text,
  related_table text,
  related_id uuid,
  send_status text,
  send_attempts integer,
  last_error text,
  scheduled_at timestamptz,
  sent_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  resolved_at timestamptz,
  resolution_note text
)
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_ungani_admin() then
    raise exception 'Access denied: admin only';
  end if;

  return query
    select
      eq.id, eq.tenant_id, eq.user_id, eq.recipient_email, eq.recipient_name,
      eq.email_type, eq.email_subject, eq.email_body, eq.related_table, eq.related_id,
      eq.send_status, eq.send_attempts, eq.last_error, eq.scheduled_at, eq.sent_at,
      eq.created_at, eq.updated_at, eq.resolved_at, eq.resolution_note
    from public.ungani_email_queue eq
    order by eq.created_at desc
    limit greatest(p_limit, 1)
    offset greatest(p_offset, 0);
end;
$function$;

revoke all on function public.admin_get_ungani_email_queue(integer, integer) from public, anon;
grant execute on function public.admin_get_ungani_email_queue(integer, integer) to authenticated;

-- VERIFICATION
select
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'admin_get_ungani_email_queue') as overload_count,
  has_function_privilege('public', 'public.admin_get_ungani_email_queue(integer, integer)', 'execute') as public_can_execute,
  has_function_privilege('anon', 'public.admin_get_ungani_email_queue(integer, integer)', 'execute') as anon_can_execute,
  has_function_privilege('authenticated', 'public.admin_get_ungani_email_queue(integer, integer)', 'execute') as authenticated_can_execute;

commit;
