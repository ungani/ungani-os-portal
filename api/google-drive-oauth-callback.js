import { createClient } from "@supabase/supabase-js";
import crypto from "crypto";

const SUPABASE_URL = process.env.SUPABASE_URL || "https://ctmtjwklltnsmfdtvqhl.supabase.co";
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const STATE_SIGNING_KEY = process.env.CRON_SECRET;
const REDIRECT_URI = "https://ungani-os-portal.vercel.app/api/google-drive-oauth-callback";
const SETTINGS_PAGE = "https://ungani-os-portal.vercel.app/my-settings.html";
// State tokens are single-use in spirit (this callback only ever runs
// once per real connect attempt) and short-lived - 10 minutes is
// generous for a user to actually click through Google's consent screen
// while still closing the window for a stale/replayed state value.
const STATE_MAX_AGE_MS = 10 * 60 * 1000;

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

export default async function handler(req, res) {
  try {
    if (req.method !== "GET") {
      return redirectWithStatus(res, "error", "Invalid request method.");
    }

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
