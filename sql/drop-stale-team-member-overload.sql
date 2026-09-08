-- Real bug found while verifying staff seat-limit enforcement tonight:
-- two overloaded versions of owner_upsert_ungani_team_member coexist
-- live - a 7-param version (pre-multi-branch) and the real 9-param
-- version (p_branch_id, p_can_access_all_branches) that the actual
-- production UI (my-team-access.html) always calls. Confirmed live:
-- any call that omits the two branch params - which the 7-param
-- signature never had - fails outright with "Could not choose the best
-- candidate function", since both overloads have every param after
-- p_full_name optional (default-valued), making them ambiguous to
-- Postgres for such a call. Production traffic isn't affected today
-- (my-team-access.html always sends all 9 params), but this is a live
-- landmine for any other caller.
--
-- Fix: drop the stale 7-param overload by its exact type signature.
-- The 9-param version (confirmed via source read to already contain
-- the correct limit-check, extended role validation, and branch-aware
-- logic) is left completely untouched - this is a pure removal, not a
-- redefinition.

drop function if exists public.owner_upsert_ungani_team_member(
  text, text, text, text, text, numeric, text
);

-- ============================================================
-- VERIFICATION - run this and paste back the output.
-- ============================================================

-- Should return exactly ONE row now (the 9-param version).
select
  p.oid::regprocedure as signature,
  pg_get_function_arguments(p.oid) as arguments
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'owner_upsert_ungani_team_member';
