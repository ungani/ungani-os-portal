import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = process.env.SUPABASE_URL || "https://ctmtjwklltnsmfdtvqhl.supabase.co";
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const SUPABASE_ANON_KEY = "sb_publishable_jkZaWWep-cObTEv_F_kN6g_Ic85BxD9";
const CRON_SECRET = process.env.CRON_SECRET;

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
      return json(res, 401, { ok: false, message: "Unauthorized purge request." });
    }

    if (!SUPABASE_SERVICE_ROLE_KEY) {
      return json(res, 500, { ok: false, message: "Missing required environment variable: SUPABASE_SERVICE_ROLE_KEY" });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false }
    });

    const [{ data: recordResult, error: recordError }, { data: tenantResult, error: tenantError }] = await Promise.all([
      supabase.rpc("purge_ungani_expired_records"),
      supabase.rpc("purge_ungani_closed_tenants")
    ]);

    if (recordError) return json(res, 500, { ok: false, message: "purge_ungani_expired_records failed: " + recordError.message });
    if (tenantError) return json(res, 500, { ok: false, message: "purge_ungani_closed_tenants failed: " + tenantError.message });

    return json(res, 200, {
      ok: true,
      via,
      records: recordResult,
      tenants: tenantResult
    });
  } catch (err) {
    return json(res, 500, { ok: false, message: err && err.message ? err.message : "Unexpected error." });
  }
}
