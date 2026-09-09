-- Addendum to sql/system-status-maintenance-announcements.sql - missed
-- this while wiring the admin UI. ungani_platform_announcements has no
-- direct RLS policies (by design, matching how ungani_notifications
-- itself isn't granted to authenticated), so admin-announcements.html's
-- listing/metrics view needs its own admin-only read RPC - there wasn't
-- one yet.

create or replace function public.admin_list_ungani_platform_announcements()
returns table(
  id uuid,
  title text,
  message text,
  severity text,
  starts_at timestamptz,
  ends_at timestamptz,
  is_active boolean,
  created_at timestamptz
)
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_is_admin boolean;
begin
  select is_ungani_admin() into v_is_admin;
  if not coalesce(v_is_admin, false) then
    return;
  end if;

  return query
  select a.id, a.title, a.message, a.severity, a.starts_at, a.ends_at, a.is_active, a.created_at
  from public.ungani_platform_announcements a
  order by a.created_at desc;
end;
$function$;

grant execute on function public.admin_list_ungani_platform_announcements() to authenticated;

-- VERIFICATION
select proname from pg_proc
where pronamespace = 'public'::regnamespace
  and proname = 'admin_list_ungani_platform_announcements';
