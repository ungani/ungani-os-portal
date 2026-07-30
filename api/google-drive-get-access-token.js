import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = process.env.SUPABASE_URL || "https://ctmtjwklltnsmfdtvqhl.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_jkZaWWep-cObTEv_F_kN6g_Ic85BxD9";
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
// Refresh a bit before actual expiry so a Picker session that opens right
// at the edge of the window never gets handed a token that expires mid-use.
const EXPIRY_BUFFER_MS = 2 * 60 * 1000;

function json(res, status, body) {
  res.status(status).json(body);
}

async function resolveTenantId(bearerToken) {
  if (!bearerToken) return null;

  try {
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: "Bearer " + bearerToken } },
      auth: { persistSession: false, autoRefreshToken: false }
    });

    const { data, error } = await userClient.rpc("get_my_ungani_tenant_id");
    return !error && data ? data : null;
  } catch {
    return null;
  }
}

export default async function handler(req, res) {
  try {
    if (req.method !== "GET" && req.method !== "POST") {
      return json(res, 405, { ok: false, message: "Method not allowed. Use GET or POST." });
    }

    if (!SUPABASE_SERVICE_ROLE_KEY) {
      return json(res, 500, { ok: false, message: "Server misconfiguration: missing SUPABASE_SERVICE_ROLE_KEY." });
    }

    const clientId = process.env.GOOGLE_CLIENT_ID;
    const clientSecret = process.env.GOOGLE_CLIENT_SECRET;

    if (!clientId || !clientSecret) {
      return json(res, 500, { ok: false, message: "Server misconfiguration: missing Google OAuth credentials." });
    }

    const authHeader = req.headers["authorization"] || "";
    const bearerToken = authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : null;

    const tenantId = await resolveTenantId(bearerToken);

    if (!tenantId) {
      return json(res, 401, { ok: false, message: "Could not verify your session. Please refresh and try again." });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false }
    });

    const { data: connection, error: fetchError } = await supabase
      .from("tenant_google_drive_connections")
      .select("access_token, token_expires_at, refresh_token")
      .eq("tenant_id", tenantId)
      .maybeSingle();

    if (fetchError) {
      return json(res, 500, { ok: false, message: "Could not check your Google Drive connection." });
    }

    if (!connection) {
      return json(res, 404, { ok: false, message: "Google Drive is not connected yet.", notConnected: true });
    }

    const expiresAt = connection.token_expires_at ? new Date(connection.token_expires_at).getTime() : 0;
    const stillValid = connection.access_token && expiresAt - EXPIRY_BUFFER_MS > Date.now();

    if (stillValid) {
      return json(res, 200, { ok: true, accessToken: connection.access_token, expiresAt: connection.token_expires_at });
    }

    const refreshResponse = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: clientId,
        client_secret: clientSecret,
        refresh_token: connection.refresh_token,
        grant_type: "refresh_token"
      })
    });

    const refreshBody = await refreshResponse.json();

    if (!refreshResponse.ok || !refreshBody.access_token) {
      // A refresh_token stops working if the user revoked access from
      // their Google Account settings, or it simply expired from disuse -
      // either way, the stored connection is no longer usable and the
      // client needs to reconnect from scratch.
      return json(res, 409, {
        ok: false,
        message: "Your Google Drive connection has expired. Please reconnect.",
        needsReconnect: true
      });
    }

    const newExpiresAt = new Date(Date.now() + (refreshBody.expires_in || 3600) * 1000).toISOString();

    await supabase
      .from("tenant_google_drive_connections")
      .update({
        access_token: refreshBody.access_token,
        token_expires_at: newExpiresAt,
        updated_at: new Date().toISOString()
      })
      .eq("tenant_id", tenantId);

    return json(res, 200, { ok: true, accessToken: refreshBody.access_token, expiresAt: newExpiresAt });
  } catch (error) {
    return json(res, 500, { ok: false, message: error.message || "Unexpected error getting a Google Drive access token." });
  }
}
