import { createClient } from "@supabase/supabase-js";
import crypto from "crypto";

const SUPABASE_URL = process.env.SUPABASE_URL || "https://ctmtjwklltnsmfdtvqhl.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_jkZaWWep-cObTEv_F_kN6g_Ic85BxD9";
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
// Reusing CRON_SECRET as the HMAC signing key for OAuth state tokens -
// it's already a private, server-only secret, and state-signing doesn't
// need its own dedicated secret (would just be one more env var to manage
// for the same "only this server can produce/verify it" property).
const STATE_SIGNING_KEY = process.env.CRON_SECRET;
const REDIRECT_URI = "https://ungani-os-portal.vercel.app/api/google-drive-oauth-callback";
const SETTINGS_PAGE = "https://ungani-os-portal.vercel.app/my-settings.html";
const SCOPES = [
  "https://www.googleapis.com/auth/drive.file",
  "openid",
  "email"
].join(" ");
// State tokens are single-use in spirit (this callback only ever runs
// once per real connect attempt) and short-lived - 10 minutes is
// generous for a user to actually click through Google's consent screen
// while still closing the window for a stale/replayed state value.
const STATE_MAX_AGE_MS = 10 * 60 * 1000;

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

async function startOAuth(req, res) {
  try {
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

function redirectWithStatus(res, status, message) {
  const url = new URL(SETTINGS_PAGE);
  url.searchParams.set("google_drive", status);
  if (message) url.searchParams.set("google_drive_message", message);
  res.writeHead(302, { Location: url.toString() });
  res.end();
}

function verifyState(state) {
  if (!state || !STATE_SIGNING_KEY) return null;

  const parts = state.split(".");
  if (parts.length !== 2) return null;

  const [body, signature] = parts;
  const expectedSignature = crypto.createHmac("sha256", STATE_SIGNING_KEY).update(body).digest("base64url");

  if (signature.length !== expectedSignature.length) return null;
  if (!crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expectedSignature))) return null;

  try {
    const payload = JSON.parse(Buffer.from(body, "base64url").toString("utf8"));
    if (!payload.tenant_id || !payload.ts) return null;
    if (Date.now() - payload.ts > STATE_MAX_AGE_MS) return null;
    return payload;
  } catch {
    return null;
  }
}

async function finishOAuth(req, res) {
  try {
    const { code, state, error: googleError } = req.query;

    if (googleError) {
      return redirectWithStatus(res, "error", "Google sign-in was cancelled.");
    }

    if (!SUPABASE_SERVICE_ROLE_KEY) {
      return redirectWithStatus(res, "error", "Server misconfiguration: missing SUPABASE_SERVICE_ROLE_KEY.");
    }

    const clientId = process.env.GOOGLE_CLIENT_ID;
    const clientSecret = process.env.GOOGLE_CLIENT_SECRET;

    if (!clientId || !clientSecret) {
      return redirectWithStatus(res, "error", "Server misconfiguration: missing Google OAuth credentials.");
    }

    const statePayload = verifyState(state);

    if (!statePayload) {
      return redirectWithStatus(res, "error", "Your connection attempt expired or was invalid. Please try again.");
    }

    if (!code) {
      return redirectWithStatus(res, "error", "Google did not return an authorization code.");
    }

    const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        code,
        client_id: clientId,
        client_secret: clientSecret,
        redirect_uri: REDIRECT_URI,
        grant_type: "authorization_code"
      })
    });

    const tokenBody = await tokenResponse.json();

    if (!tokenResponse.ok || !tokenBody.access_token || !tokenBody.refresh_token) {
      return redirectWithStatus(res, "error", "Could not complete the Google Drive connection. Please try again.");
    }

    let connectedEmail = null;

    try {
      const userinfoResponse = await fetch("https://www.googleapis.com/oauth2/v2/userinfo", {
        headers: { Authorization: "Bearer " + tokenBody.access_token }
      });

      if (userinfoResponse.ok) {
        const userinfo = await userinfoResponse.json();
        connectedEmail = userinfo.email || null;
      }
    } catch {
      // Non-fatal - the connection still works without a displayed email.
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false }
    });

    const expiresAt = new Date(Date.now() + (tokenBody.expires_in || 3600) * 1000).toISOString();

    const { error: upsertError } = await supabase
      .from("tenant_google_drive_connections")
      .upsert(
        {
          tenant_id: statePayload.tenant_id,
          refresh_token: tokenBody.refresh_token,
          access_token: tokenBody.access_token,
          token_expires_at: expiresAt,
          connected_email: connectedEmail,
          scope: tokenBody.scope || null,
          connected_by_user_id: null,
          updated_at: new Date().toISOString()
        },
        { onConflict: "tenant_id" }
      );

    if (upsertError) {
      return redirectWithStatus(res, "error", "Could not save the Google Drive connection. Please try again.");
    }

    return redirectWithStatus(res, "success", null);
  } catch (error) {
    return redirectWithStatus(res, "error", error.message || "Unexpected error connecting Google Drive.");
  }
}

// Merged with what used to be the separate api/google-drive-oauth-start.js -
// Vercel Hobby caps a deployment at 12 Serverless Functions; this repo
// crossed that limit once the 2 M-Pesa endpoints were added, silently
// breaking every deploy from that commit onward. Unlike M-Pesa's
// CallBackURL (sent fresh on every request), Google's redirect_uri is
// registered ahead of time in Google Cloud Console as this exact URL -
// so THIS filename/path must never change. Merging the other direction
// instead: our own frontend's "start connection" POST now also lands
// here, dispatched by method (POST = our app initiating, GET = Google's
// browser redirect back with ?code=&state=).
export default async function handler(req, res) {
  if (req.method === "POST") {
    return startOAuth(req, res);
  }

  if (req.method !== "GET") {
    return redirectWithStatus(res, "error", "Invalid request method.");
  }

  return finishOAuth(req, res);
}
