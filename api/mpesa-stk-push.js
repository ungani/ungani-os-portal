import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = process.env.SUPABASE_URL || "https://ctmtjwklltnsmfdtvqhl.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_jkZaWWep-cObTEv_F_kN6g_Ic85BxD9";
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

// Daraja Sandbox by default - swapping to production is purely a Vercel
// env-var change (MPESA_ENV=production + real Consumer Key/Secret/
// Passkey/Shortcode), no code change needed. Sandbox shortcode/passkey
// below are Safaricom's own published, non-secret test values, used only
// as a fallback if the real env vars aren't set yet.
const MPESA_ENV = process.env.MPESA_ENV || "sandbox";
const MPESA_BASE_URL = MPESA_ENV === "production"
  ? "https://api.safaricom.co.ke"
  : "https://sandbox.safaricom.co.ke";

const MPESA_CONSUMER_KEY = process.env.MPESA_CONSUMER_KEY;
const MPESA_CONSUMER_SECRET = process.env.MPESA_CONSUMER_SECRET;
const MPESA_PASSKEY = process.env.MPESA_PASSKEY || "bfb279f9aa9bdbcf158e97dd71a467cd2e0c893059b10f78e6b72ada1ed2c919";
const MPESA_SHORTCODE = process.env.MPESA_SHORTCODE || "174379";

const APP_URL = process.env.APP_URL || "https://ungani-os-portal.vercel.app";

function json(res, status, body) {
  res.status(status).json(body);
}

function getBearerToken(req) {
  const authHeader = req.headers["authorization"] || "";
  return authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : null;
}

// Mirrors api/send-event-push.js's resolveCallerTenantId exactly - a
// user-scoped client (their own JWT) so get_my_ungani_staff_access()
// evaluates auth.uid() correctly.
async function resolveCaller(bearerToken) {
  if (!bearerToken) return null;

  try {
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: "Bearer " + bearerToken } },
      auth: { persistSession: false, autoRefreshToken: false }
    });

    const { data: staffAccess, error } = await userClient.rpc("get_my_ungani_staff_access");
    if (error || !staffAccess || staffAccess.can_access !== true) return null;

    const { data: userData } = await userClient.auth.getUser();

    return {
      tenantId: staffAccess.tenant_id || null,
      authUserId: userData && userData.user ? userData.user.id : null
    };
  } catch {
    return null;
  }
}

function formatTimestamp(date) {
  const pad = (n) => String(n).padStart(2, "0");
  return (
    date.getFullYear().toString() +
    pad(date.getMonth() + 1) +
    pad(date.getDate()) +
    pad(date.getHours()) +
    pad(date.getMinutes()) +
    pad(date.getSeconds())
  );
}

// Accepts 07XXXXXXXX, 7XXXXXXXX, 2547XXXXXXXX, or +2547XXXXXXXX and
// normalizes to Daraja's required 2547XXXXXXXX / 2541XXXXXXXX format.
function normalizePhoneNumber(raw) {
  const digits = String(raw || "").replace(/\D/g, "");

  if (digits.startsWith("254") && digits.length === 12) return digits;
  if (digits.startsWith("0") && digits.length === 10) return "254" + digits.slice(1);
  if ((digits.startsWith("7") || digits.startsWith("1")) && digits.length === 9) return "254" + digits;

  return null;
}

async function getDarajaAccessToken() {
  const credentials = Buffer.from(MPESA_CONSUMER_KEY + ":" + MPESA_CONSUMER_SECRET).toString("base64");

  const response = await fetch(MPESA_BASE_URL + "/oauth/v1/generate?grant_type=client_credentials", {
    method: "GET",
    headers: { Authorization: "Basic " + credentials }
  });

  if (!response.ok) {
    const text = await response.text().catch(() => "");
    throw new Error("Daraja OAuth failed (" + response.status + "): " + text);
  }

  const data = await response.json();
  return data.access_token;
}

export default async function handler(req, res) {
  try {
    if (req.method !== "POST") {
      return json(res, 405, { ok: false, message: "Method not allowed. Use POST." });
    }

    if (!MPESA_CONSUMER_KEY || !MPESA_CONSUMER_SECRET) {
      return json(res, 500, { ok: false, message: "M-Pesa is not configured yet - missing MPESA_CONSUMER_KEY/MPESA_CONSUMER_SECRET." });
    }

    if (!SUPABASE_SERVICE_ROLE_KEY) {
      return json(res, 500, { ok: false, message: "Missing required environment variable: SUPABASE_SERVICE_ROLE_KEY" });
    }

    const bearerToken = getBearerToken(req);
    const caller = await resolveCaller(bearerToken);

    if (!caller || !caller.tenantId) {
      return json(res, 401, { ok: false, message: "Unauthorized." });
    }

    const phoneNumber = normalizePhoneNumber(req.body && req.body.phone);
    if (!phoneNumber) {
      return json(res, 400, { ok: false, message: "A valid Safaricom phone number is required (e.g. 0712345678)." });
    }

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false }
    });

    // Resolve the real amount owed: current package_key (from
    // ungani_subscriptions) x billing_cycle (from tenants) x real
    // pricing (ungani_packages) - the exact same lookup
    // set_ungani_subscription_period_from_payment() already relies on,
    // so a successful payment here always lines up with what that
    // function expects.
    const { data: sub } = await supabaseAdmin
      .from("ungani_subscriptions")
      .select("package_key")
      .eq("tenant_id", caller.tenantId)
      .maybeSingle();

    const { data: tenant } = await supabaseAdmin
      .from("tenants")
      .select("billing_cycle")
      .eq("id", caller.tenantId)
      .maybeSingle();

    const packageKey = (sub && sub.package_key) || "starter";
    const billingCycle = (tenant && tenant.billing_cycle) || "monthly";

    const { data: packageRow, error: packageError } = await supabaseAdmin
      .from("ungani_packages")
      .select("package_key, monthly_price_ksh, yearly_price_ksh")
      .eq("package_key", packageKey)
      .maybeSingle();

    if (packageError || !packageRow) {
      return json(res, 500, { ok: false, message: "Could not resolve package pricing for '" + packageKey + "'." });
    }

    const amount = billingCycle === "yearly" ? packageRow.yearly_price_ksh : packageRow.monthly_price_ksh;

    if (!amount || amount <= 0) {
      return json(res, 500, { ok: false, message: "This package has no price configured yet - contact UNGANI support." });
    }

    const accessToken = await getDarajaAccessToken();

    const timestamp = formatTimestamp(new Date());
    const password = Buffer.from(MPESA_SHORTCODE + MPESA_PASSKEY + timestamp).toString("base64");

    const stkResponse = await fetch(MPESA_BASE_URL + "/mpesa/stkpush/v1/processrequest", {
      method: "POST",
      headers: {
        Authorization: "Bearer " + accessToken,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        BusinessShortCode: MPESA_SHORTCODE,
        Password: password,
        Timestamp: timestamp,
        TransactionType: "CustomerPayBillOnline",
        Amount: Math.round(amount),
        PartyA: phoneNumber,
        PartyB: MPESA_SHORTCODE,
        PhoneNumber: phoneNumber,
        CallBackURL: APP_URL + "/api/mpesa-callback",
        AccountReference: "UNGANI-" + caller.tenantId.slice(0, 8),
        TransactionDesc: "UNGANI OS " + packageKey + " package"
      })
    });

    const stkData = await stkResponse.json().catch(() => ({}));

    if (!stkResponse.ok || stkData.ResponseCode !== "0") {
      return json(res, 502, {
        ok: false,
        message: stkData.errorMessage || stkData.ResponseDescription || "M-Pesa did not accept the payment request.",
        raw: stkData
      });
    }

    const { data: transaction, error: insertError } = await supabaseAdmin
      .from("ungani_mpesa_transactions")
      .insert({
        tenant_id: caller.tenantId,
        initiated_by: caller.authUserId,
        phone_number: phoneNumber,
        amount: amount,
        package_key: packageKey,
        merchant_request_id: stkData.MerchantRequestID || null,
        checkout_request_id: stkData.CheckoutRequestID || null,
        status: "pending"
      })
      .select("id, checkout_request_id")
      .single();

    if (insertError) {
      return json(res, 500, { ok: false, message: "Payment request sent to your phone, but could not be tracked: " + insertError.message });
    }

    return json(res, 200, {
      ok: true,
      message: "Check your phone and enter your M-Pesa PIN to complete payment.",
      transactionId: transaction.id,
      checkoutRequestId: transaction.checkout_request_id
    });
  } catch (error) {
    return json(res, 500, { ok: false, message: error.message });
  }
}
