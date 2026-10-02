# Step 6 Proposal: Purchase / Stock-In

Proposal only — nothing built. Below is what already exists and can be reused directly, what's
genuinely new, and the shape of the migration if you approve.

## What already exists and gets reused as-is

| Piece | Reused from |
|---|---|
| Stock increase mechanism | `adjust_ungani_stock(item_id, 'restock', +qty, reason, reorder_level, source_reference)` — the exact same function Orders already calls for fulfillment, already idempotent via `source_reference`, already atomic (no new stock logic to write). |
| Supplier selection | The existing Payee concept (shipped — a lightweight, no-login contact record) is the right fit for "supplier," not a new table. If a payee list doesn't cover every real supplier yet, `client_people` itself already works the same way Payables already uses it. |
| "Owed to supplier" recording | Debtors/Payables' Payables side is already built from pending `expense` transactions tagged with `related_person_id` — no dedicated payables table exists today, and none is needed for this either. A Purchase recorded as unpaid just inserts one pending expense transaction the same way; it shows up on the Payables page automatically, no new code there. |
| "Paid now" recording | Same `transactions` insert, `status: 'paid'` instead of `'pending'` — identical to how every other paid expense is recorded today. |
| Supplier's 360 visibility | Person 360 already shows a "Payment History" card sourced from `transactions` filtered by `related_person_id` — a Purchase's transaction row appears there automatically once it exists, no new 360 code. |
| Item's stock history | `get_my_ungani_stock_movements` already logs every `adjust_ungani_stock` call with its reason/source — a Purchase's restock movement appears there automatically. |
| Auto transaction number | Same pattern as `next_invoice_number`/`next_quotation_number`/`next_order_number` on `tenants` — add `next_purchase_number`, same increment-on-save logic. |
| Printable PDF | The exact shared `invoice-print-shell` CSS + `UnganiPrintBranding.renderHeaderBlock()` component Invoices and Quotations both already use — confirmed identical, reusable as-is, no new print styling needed. |
| Stock-holding gating | The existing `stock_tracking_enabled` toggle on `tenants` (Settings) — same flag that already gates My Stock Tracking's own visibility. |
| Reversal without deleting | Same append-only movement pattern the stock-atomicity fix already established: cancelling calls `adjust_ungani_stock` again with the inverse quantity, logged, never a row deleted. |

## What's genuinely new

- **One new table**, `ungani_purchases` (header: purchase number, date, supplier `person_id`, supplier reference, narration, posted_by, posted_at, status, payment_status) + `ungani_purchase_items` (item_id, quantity, unit_cost, line_subtotal) — same shape as `ungani_orders`/`ungani_order_items`, nothing novel architecturally.
- **One new page**, `my-purchases.html` — list + create/edit modal + print view, following the exact same structure as `my-orders.html` (which already has the closest-matching UI: a document with line items tied to real stock items).
- **One new RPC**, `owner_upsert_ungani_purchase` — on save: writes the header+lines, then loops the lines calling `adjust_ungani_stock('restock', ...)` with `source_reference = 'purchase:' || purchase_item_id` (idempotent, mirrors Orders' fulfillment call exactly), then inserts the one `transactions` row (paid or pending, per the form's "paid now?" toggle). Cancelling reverses via the same function with `'restock-reverse:' || purchase_item_id` and never touches the original row.
- **Settings/nav**: a gated sidebar entry next to Orders, visible only when `stock_tracking_enabled` is on (same pattern as Price Lists/Debtors-Payables' own gating).
- **Nia**: one new keyword-recognized intent ("record a purchase" / "stock in" / "received stock"), same shape as the existing Orders/Quotations intents.
- **Bilingual labels**: same inline English/Swahili pattern already used elsewhere (no new i18n system).

## Open decision for you

Unit cost: Price Lists today store *selling* price, not purchase cost — there's no existing "cost list"
to pull from. I'd default to manual entry per line (last-used cost pre-filled from the item's most
recent purchase, if any), rather than inventing a new cost-list feature. Say if you want something
different.

## Size estimate

Small-medium — mirrors Orders' already-proven shape almost exactly; the only genuinely new engineering
is the one new table pair and the one new RPC's stock/money wiring (which itself copies Orders'
fulfillment pattern line-for-line).

Waiting for your approval before building.
