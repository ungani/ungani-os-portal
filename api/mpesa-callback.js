import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = process.env.SUPABASE_URL || "https://ctmtjwklltnsmfdtvqhl.supabase.co";
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

function json(res, status, body) {
  res.status(status).json(body);
}

// Standard Daraja STK callback shape (documented, unchanged between
// Sandbox and production):
//   { Body: { stkCallback: { MerchantRequestID, CheckoutRequestID,
//     ResultCode, ResultDesc, CallbackMetadata: { Item: [
//       { Name: "Amount", Value }, { Name: "MpesaReceiptNumber", Value },
//       { Name: "TransactionDate", Value }, { Name: "PhoneNumber", Value }
//     ] } } } }
// CallbackMetadata is only present on success (ResultCode 0) - a
// cancelled/failed push has no Item array at all.
function extractMetadataValue(items, name) {
  if (!Array.isArray(items)) return null;
  const match = items.find((item) => item.Name === name);
  return match ? match.Value : null;
}

// Daraja's TransactionDate arrives as a number like 20240315142530
// (yyyyMMddHHmmss), not an ISO string.
function parseDarajaTimestamp(value) {
  const str = String(value || "");
  if (str.length !== 14) return null;

  const year = str.slice(0, 4);
  const month = str.slice(4, 6);
  const day = str.slice(6, 8);
  const hour = str.slice(8, 10);
  const minute = str.slice(10, 12);
  const second = str.slice(12, 14);

  const iso = `${year}-${month}-${day}T${hour}:${minute}:${second}`;
  const parsed = new Date(iso);
  return isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

export default async function handler(req, res) {
  try {
    if (req.method !== "POST") {
      return json(res, 405, { ResultCode: 1, ResultDesc: "Method not allowed." });
    }

    if (!SUPABASE_SERVICE_ROLE_KEY) {
      return json(res, 500, { ResultCode: 1, ResultDesc: "Missing SUPABASE_SERVICE_ROLE_KEY." });
    }

    const stkCallback = req.body && req.body.Body && req.body.Body.stkCallback;

    if (!stkCallback || !stkCallback.CheckoutRequestID) {
      // Not a recognizable Daraja callback shape - acknowledge with 200
      // anyway (Safaricom retries on non-2xx) but do nothing.
      return json(res, 200, { ResultCode: 0, ResultDesc: "Accepted." });
    }

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false }
    });

    // Security model: this endpoint is necessarily public (Safaricom
    // calls it directly, no user session to authenticate), so integrity
    // comes from requiring the CheckoutRequestID to match a transaction
    // WE initiated and is still pending - not from a bearer token. A
    // forged callback with a random/unknown CheckoutRequestID matches
    // nothing and is silently ignored below.
    const { data: transaction, error: lookupError } = await supabaseAdmin
      .from("ungani_mpesa_transactions")
      .select("id, tenant_id, amount, package_key, phone_number, status")
      .eq("checkout_request_id", stkCallback.CheckoutRequestID)
      .maybeSingle();

    if (lookupError || !transaction) {
      return json(res, 200, { ResultCode: 0, ResultDesc: "Accepted." });
    }

    if (transaction.status !== "pending") {
      // Already processed (Safaricom can call back more than once for
      // the same CheckoutRequestID) - acknowledge without reprocessing.
      return json(res, 200, { ResultCode: 0, ResultDesc: "Accepted." });
    }

    const resultCode = Number(stkCallback.ResultCode);
    const resultDesc = stkCallback.ResultDesc || null;
    const items = stkCallback.CallbackMetadata && stkCallback.CallbackMetadata.Item;

    if (resultCode === 0) {
      const mpesaReceiptNumber = extractMetadataValue(items, "MpesaReceiptNumber");
      const transactionDateRaw = extractMetadataValue(items, "TransactionDate");
      const paidAt = parseDarajaTimestamp(transactionDateRaw) || new Date().toISOString();
      const amountPaid = extractMetadataValue(items, "Amount") || transaction.amount;

      const { data: payment, error: paymentError } = await supabaseAdmin
        .from("ungani_payments")
        .insert({
          tenant_id: transaction.tenant_id,
          package_key: transaction.package_key,
          amount: amountPaid,
          currency: "KES",
          paid_at: paidAt,
          payment_status: "paid",
          payment_method: "mpesa",
          payment_reference: mpesaReceiptNumber,
          notes: "M-Pesa STK Push - " + transaction.phone_number
        })
        .select("id")
        .single();

      if (paymentError) {
        await supabaseAdmin
          .from("ungani_mpesa_transactions")
          .update({
            status: "failed",
            result_code: resultCode,
            result_desc: "Payment recorded by M-Pesa but could not be saved: " + paymentError.message,
            mpesa_receipt_number: mpesaReceiptNumber,
            transaction_date: paidAt,
            raw_callback: req.body,
            updated_at: new Date().toISOString()
          })
          .eq("id", transaction.id);

        return json(res, 200, { ResultCode: 0, ResultDesc: "Accepted." });
      }

      // Reuses the exact same confirmation function every existing
      // manual mark-paid admin path already calls - this is the one and
      // only place subscription_ends_at/subscription_status get set from
      // a payment, so an M-Pesa payment behaves identically to an
      // admin-approved payment proof.
      await supabaseAdmin.rpc("set_ungani_subscription_period_from_payment", {
        p_payment_id: payment.id
      });

      await supabaseAdmin
        .from("ungani_mpesa_transactions")
        .update({
          status: "success",
          result_code: resultCode,
          result_desc: resultDesc,
          mpesa_receipt_number: mpesaReceiptNumber,
          transaction_date: paidAt,
          payment_id: payment.id,
          raw_callback: req.body,
          updated_at: new Date().toISOString()
        })
        .eq("id", transaction.id);

      return json(res, 200, { ResultCode: 0, ResultDesc: "Accepted." });
    }

    // Non-zero ResultCode: user cancelled (1032), insufficient funds,
    // timeout, etc. - just record the outcome, nothing to unlock.
    await supabaseAdmin
      .from("ungani_mpesa_transactions")
      .update({
        status: resultCode === 1032 ? "cancelled" : "failed",
        result_code: resultCode,
        result_desc: resultDesc,
        raw_callback: req.body,
        updated_at: new Date().toISOString()
      })
      .eq("id", transaction.id);

    return json(res, 200, { ResultCode: 0, ResultDesc: "Accepted." });
  } catch (error) {
    // Always acknowledge with 200 even on our own internal error -
    // Safaricom will otherwise retry the callback repeatedly, and a
    // genuine internal error here won't be fixed by a retry anyway.
    return json(res, 200, { ResultCode: 0, ResultDesc: "Accepted." });
  }
}
