import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = process.env.SUPABASE_URL || "https://ctmtjwklltnsmfdtvqhl.supabase.co";
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const SUPABASE_ANON_KEY = "sb_publishable_jkZaWWep-cObTEv_F_kN6g_Ic85BxD9";
const CRON_SECRET = process.env.CRON_SECRET;

// Free, no API key, no signup - confirmed live to include KES among its
// 166 currencies and to update once per 24 hours (so fetching more than
// once/day here would be pointless even if we wanted to). Attribution
// is shown to users in my-settings.html's Multi-Currency panel, not
// here, since that's the user-facing surface.
const RATE_SOURCE = "open.er-api.com";
const RATE_API_URL = "https://open.er-api.com/v6/latest/USD";

function json(res, status, body) {
  res.status(status).json(body);
}

function isCronRequest(bearerToken) {
  return Boolean(bearerToken && CRON_SECRET && bearerToken === CRON_SECRET);
}

async function isAdminRequest(bearerToken) {
  if (!bearerToken) return false;

  try {
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: "Bearer " + bearerToken } },
      auth: { persistSession: false, autoRefreshToken: false }
    });

    const { data, error } = await userClient.rpc("is_ungani_admin");
    return !error && data === true;
  } catch {
    return false;
  }
}

export default async function handler(req, res) {
  try {
    if (req.method !== "GET" && req.method !== "POST") {
      return json(res, 405, { ok: false, message: "Method not allowed. Use GET or POST." });
    }

    const authHeader = req.headers["authorization"] || "";
    const bearerToken = authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : null;

    const via = isCronRequest(bearerToken)
      ? "cron"
      : (await isAdminRequest(bearerToken))
        ? "admin"
        : null;

    if (!via) {
      return json(res, 401, { ok: false, message: "Unauthorized exchange-rate fetch request." });
    }

    if (!SUPABASE_SERVICE_ROLE_KEY) {
      return json(res, 500, { ok: false, message: "Missing required environment variable: SUPABASE_SERVICE_ROLE_KEY" });
    }

    let rate;

    try {
      const response = await fetch(RATE_API_URL);
      const body = await response.json();

      if (!response.ok || body.result !== "success" || !body.rates || typeof body.rates.KES !== "number") {
        return json(res, 502, { ok: false, message: "Exchange rate provider returned an unusable response.", via });
      }

      rate = body.rates.KES;
    } catch (fetchError) {
      return json(res, 502, { ok: false, message: "Could not reach exchange rate provider: " + (fetchError.message || "network error"), via });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false }
    });

    const todayDate = new Date().toISOString().slice(0, 10);

    const { error: upsertError } = await supabase
      .from("exchange_rates")
      .upsert(
        {
          rate_date: todayDate,
          base_currency: "USD",
          quote_currency: "KES",
          rate: rate,
          source: RATE_SOURCE,
          fetched_at: new Date().toISOString()
        },
        { onConflict: "rate_date" }
      );

    if (upsertError) {
      return json(res, 500, { ok: false, message: "Could not store exchange rate: " + upsertError.message, via });
    }

    return json(res, 200, { ok: true, via, rate_date: todayDate, rate });
  } catch (error) {
    return json(res, 500, { ok: false, message: error.message || "Unexpected error fetching exchange rate." });
  }
}
