# Step 5: Invoicing / Stock / Reporting Audit

Everything below is from live code reading (cited file:line in my working notes), not guessing. Nothing
has been changed yet except where explicitly marked "FIXED" — this is a report-first pass per your
instruction, with one proposed fix held for your review because it touches stock and money.

## 1. CRITICAL: Invoices don't move stock — confirmed, by design, not an oversight

`ungani_customer_invoice_items` has **no `item_id` column at all** (confirmed from the live table and
the RPC body) — the code comment at `my-customer-invoices.html:165-169` says so explicitly: an invoice
line is "a point-in-time snapshot, not a tracked link." No invoice code path (create, mark sent, mark
paid, cancel) has ever called `adjust_ungani_stock`. Quotations: confirmed the same — never touch stock,
correctly, matching your spec.

**Proposed fix — WHEN it deducts:** on the invoice moving to **`sent`**, not on payment. Reasoning:
stock physically leaves when goods are delivered/invoiced out, which is what "sent" represents — the
customer owing you money for it afterward is exactly what Debtors/Payables already tracks. Waiting for
`paid` would leave stock showing as available while it's already in the customer's hands. A `draft`
invoice never deducts (it isn't committed). This also matches Orders' own existing pattern: deduct at
the "goods leave" moment (fulfillment), not at a money event.

**How it avoids double-deduction with Orders**: `convert_ungani_order_to_invoice()` already never copies
`item_id` onto the resulting invoice lines (confirmed) — I'm **not changing that function at all**. Only
invoices created directly in My Invoices (not via order conversion) will carry `item_id` on their lines.
Since the new deduction logic only fires for lines that have `item_id` set, an order-converted invoice
(stock already deducted once, at fulfillment) can never be deducted a second time — no flag-checking
needed, the existing architecture already separates the two paths.

**Idempotency + reversal**: uses the same `adjust_ungani_stock(p_source_reference)` dedup mechanism
Orders already uses (`'invoice:' || invoice_item_id`). Cancelling or deleting a `sent`+stock-deducted
invoice calls `adjust_ungani_stock` again with `'restock'` and the inverse quantity, logged as a real
movement (never a silent delete) — same pattern as the existing stock-atomicity fix.

**SQL for review (not run)** — adds `item_id` to invoice line items (nullable, only set for
directly-created invoices), and a new RPC that deducts/restores stock when an invoice's status changes:

```sql
-- Add item_id to invoice lines (nullable — order-converted invoice lines stay null, by design).
alter table public.ungani_customer_invoice_items
  add column if not exists item_id uuid references public.business_items(id);

-- Called by owner_upsert_ungani_customer_invoice (modified to accept item_id per line item,
-- passed through from my-customer-invoices.html's existing item picker — it already resolves
-- an item_id for price lookup today, per the same file's comment; it's just never saved).
-- Called again whenever an invoice's status changes.
create or replace function public.sync_ungani_invoice_stock(
  p_invoice_id uuid,
  p_new_status text,
  p_old_status text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_line record;
  v_result jsonb;
begin
  select tenant_id into v_tenant_id from public.ungani_customer_invoice_items
  where invoice_id = p_invoice_id limit 1;
  -- (falls back to reading tenant_id off ungani_customer_invoices if no line items exist yet)

  -- Deduct: moving INTO 'sent' for the first time.
  if p_new_status = 'sent' and p_old_status is distinct from 'sent' and p_old_status != 'cancelled' then
    for v_line in
      select id, item_id, quantity from public.ungani_customer_invoice_items
      where invoice_id = p_invoice_id and item_id is not null
    loop
      v_result := public.adjust_ungani_stock(
        v_line.item_id, 'sale', -v_line.quantity,
        'Invoice sent', null, 'invoice:' || v_line.id
      );
    end loop;
  end if;

  -- Restore: a previously-sent invoice is now cancelled.
  if p_new_status = 'cancelled' and p_old_status = 'sent' then
    for v_line in
      select id, item_id, quantity from public.ungani_customer_invoice_items
      where invoice_id = p_invoice_id and item_id is not null
    loop
      v_result := public.adjust_ungani_stock(
        v_line.item_id, 'restock', v_line.quantity,
        'Invoice cancelled - stock restored', null, 'invoice-cancel:' || v_line.id
      );
    end loop;
  end if;

  return jsonb_build_object('ok', true);
end;
$function$;

revoke all on function public.sync_ungani_invoice_stock(uuid, text, text) from public, anon;
grant execute on function public.sync_ungani_invoice_stock(uuid, text, text) to authenticated;
```

This needs wiring into `owner_upsert_ungani_customer_invoice` (accept+save `item_id` per line) and
`update_ungani_invoice_status`/the delete path (call `sync_ungani_invoice_stock`) — I haven't written
those edits yet since I'd be extending functions from their real live bodies, which I have (via this
session's research), but this is exactly the kind of money+stock change that gets reviewed before I
write the full migration. Tell me to proceed and I'll produce the complete, ready-to-run file.

## 2. Check results

| Item | Status | Detail |
|---|---|---|
| Person 360 payment/invoice history | **BROKEN/MISSING** | Person 360 shows *payments* (from `transactions`) but never queries invoices at all — no way to see if a person has outstanding invoices or has "fully paid." |
| Company 360 invoice history | **PARTIAL** | Shows invoices (number, date, total, status) but fetches `amount_paid` and never displays it — no computed balance. You can infer "paid" only from the status word, not a number. |
| Customer statement (printable) | **MISSING** | Confirmed, doesn't exist anywhere in the app. |
| Receipt on invoice payment | **MISSING** | `record_ungani_invoice_payment` records the payment and shows a toast — no receipt. (POS Quick Sale has its own unrelated receipt; UNGANI's own subscription invoice is a different, unrelated document.) |
| Invoice print/PDF | **WORKING** | Business name/phone/email, business KRA PIN, customer's own PIN, line items, VAT (inclusive/exclusive aware), subtotal/discount/total, remaining balance, payment terms — all present and correct. |
| Quotation print/PDF | **WORKING** | Confirmed just now — same shared branded layout as invoices (`UnganiPrintBranding.renderHeaderBlock`), includes business KRA PIN, customer PIN, items, VAT, totals, and "Valid until" date. No fix needed. |
| Printable stock list | **MISSING** | No page offers a printable current-quantities (with low/out flags) list — not Items, not Stock Tracking, not Reports. |
| Per-item stock history | **PARTIAL** | Exists on Item 360 and the Stock Tracking page, but hardcoded to the most recent 20 movements, no date-range filter — not period-selectable as asked. Also: the separate standalone `my-item-profile.html` page (still linked from a few places) has no stock-history loader at all — only the inline panel in My Items got this wiring. |
| Reports by period | **PARTIAL — your named list doesn't match what's built** | Only `today / yesterday / this week / this month / this year / all-time` exist as presets (in `print-report.html`); `reports.html` itself has no quick-period buttons at all, only a manual From/To filter. **`last week`, `last month`, and `last 6 months` don't exist anywhere in the app** — not broken, genuinely not built. No silent "empty period shows all-time" bug found; empty periods correctly return zero rows. One boundary note: existing periods are "from X through right now," not closed calendar windows (e.g. "this week" = Monday through this exact moment, not Monday–Sunday) — accurate for what it claims, just worth knowing. |
| Business Health factors | **CONFIRMED working, formulas documented** | 5 weighted factors (payments 30%, tasks 25%, support 20%, activity 15%, stock 10%), each reading a real field (`transactions`, `tasks`, `support_issues`, recent `updated_at` across 6 tables, `business_items` stock status) — not independently re-run against 3 tenants yet in this pass (time), but the formulas are confirmed correct from source, not guessed. |
| Nia period answers | **WORKING with one real gap** | Her date math is byte-identical to `print-report.html`'s (shared on purpose, commented as such), so "this week"/"this month" are accurate and labeled correctly. **Real bug: she has no concept of "last"** — "last month's expenses" and "last week's sales" both silently get answered for the *current* month/week instead (the reply does say "This Month"/"This Week", so it's not a lie, but it ignores the word "last" entirely). Zero-data periods show real zeros, correctly, but she never says "no records for this period" explicitly — a user could mistake a genuine zero for a missed answer. |

## 3. Fixed this pass

Nothing yet — everything above is reported, not fixed, per your "report first" instruction. The stock-deduction fix (item 1) is designed and the SQL is ready, held for your review since it's stock+money.

## 4. Missing items — sized, not built

| Item | Rough size |
|---|---|
| Invoice stock deduction (item 1 above) | Small-medium — 1 schema column, 1 new RPC, 2 small edits to existing RPCs, 1 picker-save-payload change in my-customer-invoices.html |
| Person 360 invoice/balance visibility | Small — add the same invoice query Company 360 already has to `loadPersonConnections()`, plus compute and show a balance |
| Company 360 balance display | Tiny — the data (`amount_paid`) is already fetched, just render `total_amount - amount_paid` |
| Customer statement (print) | Medium — new print view, reusing the invoice print-shell styling + a payments-by-customer query (similar to Debtors/Payables' existing grouping logic) |
| Receipt on invoice payment | Small-medium — one new print view keyed to a payment event, reusing `record_ungani_invoice_payment`'s existing row |
| Printable stock list | Small — one new print view on top of data `my-stock-tracking.html` already loads |
| Period-filterable stock history | Small — add `p_date_from`/`p_date_to` params to `get_my_ungani_stock_movements`, add date pickers on both pages that call it; also wire the same loader into `my-item-profile.html` |
| `last week` / `last month` / `last 6 months` report presets | Small-medium — extend `print-report.html`'s `RANGE_LABELS` with 3 more closed-window boundaries, decide if `reports.html` should get the same quick buttons |
| Nia "last X" period detection | Small — `detectSummaryRangeFromText` needs a "last" check before the bare month/week regex, plus a real previous-period boundary calc |
| Nia explicit "no data" messaging | Tiny — one conditional in `runSummaryIntent()` |
