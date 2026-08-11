-- Real bug found live while testing the payment-confirmation-gap fix:
-- clicking "Run Automation Now" on admin-billing-automation.html threw
-- "column reference 'payment_id' is ambiguous".
--
-- Root cause: run_ungani_billing_reminders()'s RETURNS TABLE(payment_id
-- uuid, tenant_id uuid, reminder_type text, notification_sent boolean,
-- reminder_message text) declares those 5 names as OUT parameters, which
-- are in scope as PL/pgSQL variables for the whole function body. The
-- UPDATE statement's WHERE clause read two of them unqualified -
-- payment_id and reminder_type - both of which also exist as real
-- columns on public.ungani_billing_reminder_logs, so Postgres can't
-- tell whether "payment_id = r.id" means the OUT variable or the table
-- column. Only "payment_id" surfaced in the actual runtime error
-- (Postgres reports the first ambiguity it hits), but "reminder_type"
-- in the same WHERE clause has the identical problem and would have
-- thrown next.
--
-- Everything else in the function was already safe: INSERT's column
-- list and UPDATE's SET target are resolved against the table
-- unconditionally by SQL grammar (not subject to PL/pgSQL variable
-- shadowing), and the final `payment_id := r.id; ...` block is an
-- intentional assignment TO the OUT parameters, not a table read.
--
-- Fix: qualify both ambiguous references with the table name. Confirmed
-- run live 2026-08-11 - "Run Automation Now" completed successfully
-- with no error.

CREATE OR REPLACE FUNCTION public.run_ungani_billing_reminders()
 RETURNS TABLE(payment_id uuid, tenant_id uuid, reminder_type text, notification_sent boolean, reminder_message text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r record;
  v_reminder_type text;
  v_title text;
  v_message text;
  v_amount text;
  v_package text;
  v_inserted boolean;
  v_sent boolean;
begin
  for r in
    select
      p.id,
      p.tenant_id,
      p.package_key,
      p.amount,
      p.currency,
      p.payment_status,
      p.due_date,
      p.payment_reference
    from public.ungani_payments p
    where p.tenant_id is not null
      and p.due_date is not null
      and lower(coalesce(p.payment_status, 'pending')) in ('pending', 'partial', 'overdue')
      and (
        p.due_date = current_date + interval '3 days'
        or p.due_date = current_date + interval '1 day'
        or p.due_date = current_date
        or p.due_date < current_date
      )
    order by p.due_date asc, p.created_at asc
  loop
    v_reminder_type := null;
    v_title := null;
    v_message := null;
    v_sent := false;
    v_inserted := false;

    v_amount := public.format_ungani_payment_amount(r.amount, r.currency);
    v_package := initcap(coalesce(r.package_key, 'starter'));

    if r.due_date = current_date + interval '3 days' then
      v_reminder_type := 'due_in_3_days';
      v_title := 'Payment Due Soon';
      v_message :=
        'Reminder: Your UNGANI OS '
        || v_package
        || ' payment of '
        || v_amount
        || ' is due in 3 days on '
        || to_char(r.due_date, 'DD Mon YYYY')
        || '. Please open My Billing for details.';

    elsif r.due_date = current_date + interval '1 day' then
      v_reminder_type := 'due_tomorrow';
      v_title := 'Payment Due Tomorrow';
      v_message :=
        'Reminder: Your UNGANI OS '
        || v_package
        || ' payment of '
        || v_amount
        || ' is due tomorrow on '
        || to_char(r.due_date, 'DD Mon YYYY')
        || '. Please open My Billing for details.';

    elsif r.due_date = current_date then
      v_reminder_type := 'due_today';
      v_title := 'Payment Due Today';
      v_message :=
        'Reminder: Your UNGANI OS '
        || v_package
        || ' payment of '
        || v_amount
        || ' is due today. Please open My Billing for details.';

    elsif r.due_date < current_date then
      v_reminder_type := 'overdue';
      v_title := 'Payment Overdue';
      v_message :=
        'Reminder: Your UNGANI OS '
        || v_package
        || ' payment of '
        || v_amount
        || ' was due on '
        || to_char(r.due_date, 'DD Mon YYYY')
        || '. Please open My Billing or contact UNGANI support.';
    end if;

    if v_reminder_type is null then
      continue;
    end if;

    begin
      insert into public.ungani_billing_reminder_logs (
        payment_id,
        tenant_id,
        reminder_type,
        reminder_date,
        notification_sent,
        created_at
      )
      values (
        r.id,
        r.tenant_id,
        v_reminder_type,
        current_date,
        false,
        now()
      );

      v_inserted := true;
    exception
      when unique_violation then
        v_inserted := false;
    end;

    if v_inserted then
      v_sent := public.create_ungani_billing_notification(
        r.tenant_id,
        v_title,
        v_message,
        'my-billing.html'
      );

      update public.ungani_billing_reminder_logs
      set notification_sent = coalesce(v_sent, false)
      where ungani_billing_reminder_logs.payment_id = r.id
        and ungani_billing_reminder_logs.reminder_type = v_reminder_type
        and ungani_billing_reminder_logs.reminder_date = current_date;
    end if;

    payment_id := r.id;
    tenant_id := r.tenant_id;
    reminder_type := v_reminder_type;
    notification_sent := coalesce(v_sent, false);
    reminder_message := v_message;

    return next;
  end loop;
end;
$function$;
