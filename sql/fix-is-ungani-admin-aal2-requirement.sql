-- SECURITY FIX (mandatory version, no opt-in): is_ungani_admin() never
-- checked the JWT's aal (MFA assurance level) claim - confirmed live by
-- calling it with a plain password-grant (aal1) token for
-- chris@ungani.com, who has 2FA enrolled: it returned true, and every
-- admin RPC gated on it executed normally. The app's own 2FA
-- (mfa-challenge.html + client-access-guard.js) is enforced ONLY
-- client-side via a browser redirect - nothing server-side ever
-- verified the challenge was completed, so a compromised admin password
-- alone was sufficient to call every admin-gated RPC directly via the
-- REST API, bypassing TOTP entirely.
--
-- Per explicit decision: NOT opt-in. Every ungani_admins account always
-- requires aal2, including accounts with no TOTP factor enrolled yet -
-- an unenrolled admin is blocked from admin access until they enroll,
-- by design. Same signature/return type as the live version, so
-- CREATE OR REPLACE is safe (no DROP needed).
--
-- Cron/webhook/service-role exposure (checked before this went in):
-- the two daily crons (check-trial-warnings, send-email-queue)
-- authenticate via a separate CRON_SECRET bearer check, never via
-- is_ungani_admin(). service_role calls bypass RLS and this function
-- entirely. Only interactive, logged-in-admin-triggered actions (the
-- admin_* RPCs, and the "admin" manual-trigger path in the two cron
-- files' own handlers) go through this function - exactly the surface
-- that should require aal2.
--
-- BREAK-GLASS RECOVERY if this ever locks out every admin (e.g. before
-- anyone has 2FA enrolled): the Supabase dashboard SQL editor runs as a
-- privileged role, never subject to this function or RLS, so recovery
-- is always possible there. Revert with the exact pre-fix version
-- (verbatim, not reconstructed):
--
-- create or replace function public.is_ungani_admin()
--  returns boolean
--  language plpgsql
--  stable security definer
--  set search_path to 'public', 'auth'
-- as $function$
-- declare
--   current_user_id uuid;
--   current_email text;
--   jwt_email text;
-- begin
--   current_user_id := auth.uid();
--   jwt_email := lower(trim(coalesce(auth.jwt() ->> 'email', '')));
--   if current_user_id is null and jwt_email = '' then
--     return false;
--   end if;
--   if current_user_id is not null then
--     select lower(trim(au.email))
--     into current_email
--     from auth.users au
--     where au.id = current_user_id;
--   end if;
--   current_email := lower(trim(coalesce(current_email, jwt_email, '')));
--   if current_email = '' then
--     return false;
--   end if;
--   return exists (
--     select 1
--     from public.ungani_admins a
--     where lower(trim(a.email)) = current_email
--       and a.is_active = true
--   );
-- end;
-- $function$;

create or replace function public.is_ungani_admin()
 returns boolean
 language plpgsql
 stable security definer
 set search_path to 'public', 'auth'
as $function$
declare
  current_user_id uuid;
  current_email text;
  jwt_email text;
  is_admin_by_email boolean;
  current_aal text;
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

  is_admin_by_email := exists (
    select 1
    from public.ungani_admins a
    where lower(trim(a.email)) = current_email
      and a.is_active = true
  );

  if not is_admin_by_email then
    return false;
  end if;

  current_aal := auth.jwt() ->> 'aal';

  if current_aal is distinct from 'aal2' then
    return false;
  end if;

  return true;
end;
$function$;

revoke all on function public.is_ungani_admin() from public, anon;
grant execute on function public.is_ungani_admin() to authenticated;

select
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'is_ungani_admin') as overload_count,
  has_function_privilege('public', 'public.is_ungani_admin()', 'execute') as public_can_execute,
  has_function_privilege('anon', 'public.is_ungani_admin()', 'execute') as anon_can_execute,
  has_function_privilege('authenticated', 'public.is_ungani_admin()', 'execute') as authenticated_can_execute;
