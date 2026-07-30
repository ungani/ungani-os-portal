import { createClient } from "@supabase/supabase-js";
import crypto from "crypto";

const SUPABASE_URL = process.env.SUPABASE_URL || "https://ctmtjwklltnsmfdtvqhl.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_jkZaWWep-cObTEv_F_kN6g_Ic85BxD9";
// Reusing CRON_SECRET as the HMAC signing key for OAuth state tokens -
// it's already a private, server-only secret, and state-signing doesn't
// need its own dedicated secret (would just be one more env var to manage
// for the same "only this server can produce/verify it" property).
const STATE_SIGNING_KEY = process.env.CRON_SECRET;
const REDIRECT_URI = "https://ungani-os-portal.vercel.app/api/google-drive-oauth-callback";
const SCOPES = [
  "https://www.googleapis.com/auth/drive.file",
  "openid",
  "email"
].join(" ");

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

function signState(payload) {
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url");
  const signature = crypto.createHmac("sha256", STATE_SIGNING_KEY).update(body).digest("base64url");
  return body + "." + signature;
}

export default async function handler(req, res) {
  try {
    if (req.method !== "POST") {
      return json(res, 405, { ok: false, message: "Method not allowed. Use POST." });
    }

    if (!STATE_SIGNING_KEY) {
      return json(res, 500, { ok: false, message: "Missing required environment variable: CRON_SECRET." });
    }

    const clientId = process.env.GOOGLE_CLIENT_ID;

    if (!clientId) {
      return json(res, 500, { ok: false, message: "Missing required environment variable: GOOGLE_CLIENT_ID." });
    }

    const authHeader = req.headers["authorization"] || "";
    const bearerToken = authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : null;

    const tenantId = await resolveTenantId(bearerToken);

    if (!tenantId) {
      return json(res, 401, { ok: false, message: "Could not verify your session. Please refresh and try again." });
    }

    const state = signState({
      tenant_id: tenantId,
      nonce: crypto.randomBytes(16).toString("hex"),
      ts: Date.now()
    });

    const authorizeUrl = new URL("https://accounts.google.com/o/oauth2/v2/auth");
    authorizeUrl.searchParams.set("client_id", clientId);
    authorizeUrl.searchParams.set("redirect_uri", REDIRECT_URI);
    authorizeUrl.searchParams.set("response_type", "code");
    authorizeUrl.searchParams.set("scope", SCOPES);
    authorizeUrl.searchParams.set("access_type", "offline");
    authorizeUrl.searchParams.set("prompt", "consent");
    authorizeUrl.searchParams.set("state", state);

    return json(res, 200, { ok: true, authorizeUrl: authorizeUrl.toString() });
  } catch (error) {
    return json(res, 500, { ok: false, message: error.message || "Unexpected error starting Google Drive connection." });
  }
}
