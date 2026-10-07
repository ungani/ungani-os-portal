-- Root cause of the lockout: every admin-page entry point (login.html's
-- checkAdmin(), admin-access-guard.js's protectAdminPage(), admin-
-- shared.js's isAdminByRpc()) called the STRICT is_ungani_admin()
-- (which now requires aal2) to decide whether to even START the MFA
-- flow - so an aal1 admin was told "not an admin" before ever reaching
-- the 2FA challenge, with no way to climb out.
--
-- Fix: a second, email-only function with NO aal requirement, used
-- ONLY for client-side routing (should this session be sent toward the
-- MFA challenge/enrollment flow at all?). The real data-access gate
-- stays exactly is_ungani_admin() (unchanged from the last migration -
-- still mandatory aal2, no opt-in). This function is never used inside
-- any RPC permission check, only inside the 3 client-side files listed
-- above, called BEFORE the aal2 check so the flow becomes: email
-- candidate? -> yes -> have aal2? -> no -> send to challenge/enroll ->
-- aal2 reached -> NOW call the real is_ungani_admin() to grant access.

create or replace function public.is_ungani_admin_candidate()
 returns boolean
 language plpgsql
 stable security definer
 set search_path to 'public', 'auth'
as $function$
declare
  current_user_id uuid;
  current_email text;
  jwt_email text;
begin
  current_user_id := auth.uid();
  jwt_email := lower(trim(coalesce(auth.jwt() ->> 'email', '')));

  if current_user_id is null and jwt_email = '' then
    return false;
  end if;

  if current_user_id is not null then
    select lower(trim(au.email))
    into current_email
    from auth.users au
    where au.id = current_user_id;
  end if;

  current_email := lower(trim(coalesce(current_email, jwt_email, '')));

  if current_email = '' then
    return false;
  end if;

  return exists (
    select 1
    from public.ungani_admins a
    where lower(trim(a.email)) = current_email
      and a.is_active = true
  );
end;
$function$;

revoke all on function public.is_ungani_admin_candidate() from public, anon;
grant execute on function public.is_ungani_admin_candidate() to authenticated;

select
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'is_ungani_admin_candidate') as overload_count,
  has_function_privilege('public', 'public.is_ungani_admin_candidate()', 'execute') as public_can_execute,
  has_function_privilege('anon', 'public.is_ungani_admin_candidate()', 'execute') as anon_can_execute,
  has_function_privilege('authenticated', 'public.is_ungani_admin_candidate()', 'execute') as authenticated_can_execute;
