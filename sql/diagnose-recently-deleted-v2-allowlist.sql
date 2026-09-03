-- Pull the real, current source of get_my_ungani_recently_deleted_v2()
-- (the read side of Recently Deleted) - the invoice soft-delete succeeded
-- and wrote a row, but this RPC isn't returning it, which points to a
-- second table-name allowlist that also needs ungani_customer_invoices
-- added. Paste the full output back before any fix is written.

select pg_get_functiondef(p.oid) as function_source
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'get_my_ungani_recently_deleted_v2';
