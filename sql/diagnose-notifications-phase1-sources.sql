-- Read-only. Needed before writing Phase 1 of the notification-emails
-- migration (payment approved, task assigned, support response, team
-- invitation, payroll payment). Two of these events already have a real
-- RPC that must be EXTENDED, not rewritten from scratch -
-- admin_accept_ungani_payment_proof_and_mark_paid() and notify_ungani_
-- task_assignment(). Guessing their current body risks silently dropping
-- logic (permission checks, existing side effects) that's already there.
-- Also confirming exact column shapes for support_issues/tasks/payment-
-- proofs/ungani_team_members so the two brand-new queueing RPCs (support
-- response, payroll payment - neither currently has a wrapping RPC to
-- extend, both are raw client-side table writes today) are written
-- against real columns, not assumed ones.

-- 1. Real source of admin_accept_ungani_payment_proof_and_mark_paid()
select pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'admin_accept_ungani_payment_proof_and_mark_paid';

-- 2. Real source of notify_ungani_task_assignment()
select pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'notify_ungani_task_assignment';

-- 3. Current real columns on support_issues
select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'support_issues'
order by ordinal_position;

-- 4. Current real columns on tasks
select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'tasks'
order by ordinal_position;

-- 5. Current real columns on "payment-proofs" (hyphenated table name,
-- confirmed from admin-payment-proofs.html's own .from() call)
select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'payment-proofs'
order by ordinal_position;

-- 6. Re-confirm ungani_team_members columns (light sanity check - this
-- table was extended earlier tonight for payroll tracking, confirming
-- the live shape matches before building on it again)
select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'ungani_team_members'
order by ordinal_position;

-- 7. Function signatures for both RPCs being extended, in case the
-- functiondef output above is long/hard to scan at a glance.
select
  p.proname,
  pg_get_function_arguments(p.oid) as arguments,
  pg_get_function_result(p.oid) as return_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('admin_accept_ungani_payment_proof_and_mark_paid', 'notify_ungani_task_assignment');
