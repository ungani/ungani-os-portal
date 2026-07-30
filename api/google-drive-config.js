// Returns the two Google values that are safe to hand to client-side JS
// (Client ID and the Picker API key - both meant to be public per
// Google's own docs; the API key is restricted by HTTP referrer + to the
// Picker API only, set up in Google Cloud Console). GOOGLE_CLIENT_SECRET
// is never read here - it only ever touches google-drive-oauth-callback.js
// and google-drive-get-access-token.js, both server-side only.

function json(res, status, body) {
  res.status(status).json(body);
}

export default async function handler(req, res) {
  if (req.method !== "GET") {
    return json(res, 405, { ok: false, message: "Method not allowed. Use GET." });
  }

  const clientId = process.env.GOOGLE_CLIENT_ID;
  const apiKey = process.env.GOOGLE_API_KEY;

  if (!clientId || !apiKey) {
    return json(res, 500, {
      ok: false,
      message: "Google Drive integration is not configured (missing GOOGLE_CLIENT_ID or GOOGLE_API_KEY)."
    });
  }

  return json(res, 200, { ok: true, clientId, apiKey });
}
