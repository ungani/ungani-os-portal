-- Pull the real, current source of soft_delete_ungani_record() so the
-- allowlist fix can be written as a precise one-line addition, not a
-- guess. Paste the full output back.

select pg_get_functiondef(p.oid) as function_source
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'soft_delete_ungani_record';
