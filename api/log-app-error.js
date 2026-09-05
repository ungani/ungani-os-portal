import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const MAX_SHORT_LENGTH = 200;
const MAX_TEXT_LENGTH = 2000;
const MAX_CONTEXT_BYTES = 8000;

function json(res, status, body) {
  res.status(status).json(body);
}

function clampText(value, maxLength) {
  if (value === undefined || value === null) return null;
  const text = String(value);
  return text.length > maxLength ? text.slice(0, maxLength) : text;
}

function sanitizeContext(context) {
  if (context === undefined || context === null) return null;
  if (typeof context !== "object" || Array.isArray(context)) return null;
  try {
    const serialized = JSON.stringify(context);
    if (serialized.length > MAX_CONTEXT_BYTES) return null;
    return context;
  } catch {
    return null;
  }
}

export default async function handler(req, res) {
  try {
    if (req.method !== "POST") {
      return json(res, 405, { ok: false, message: "Method not allowed. Use POST." });
    }

    if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
      return json(res, 500, { ok: false, message: "Server misconfigured: missing Supabase service credentials." });
    }

    const authHeader = req.headers["authorization"] || "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : null;

    if (!token) {
      return json(res, 401, { ok: false, message: "Missing bearer token." });
    }

    const surface = clampText(req.body?.surface, 20);
    const errorType = clampText(req.body?.errorType, MAX_SHORT_LENGTH);
    const message = clampText(req.body?.message, MAX_TEXT_LENGTH);

    if (surface !== "client" && surface !== "admin") {
      return json(res, 400, { ok: false, message: "Missing or invalid required field: surface (must be 'client' or 'admin')." });
    }

    if (!errorType) {
      return json(res, 400, { ok: false, message: "Missing required field: errorType." });
    }

    if (!message) {
      return json(res, 400, { ok: false, message: "Missing required field: message." });
    }

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false }
    });

    const { data: userData, error: userError } = await supabaseAdmin.auth.getUser(token);

    if (userError || !userData?.user) {
      return json(res, 401, { ok: false, message: "Invalid or expired session." });
    }

    const actor = userData.user;

    const { data: profile } = await supabaseAdmin
      .from("users")
      .select("tenant_id")
      .eq("id", actor.id)
      .maybeSingle();

    const entry = {
      surface,
      tenant_id: profile?.tenant_id || null,
      actor_user_id: actor.id,
      actor_email: actor.email || null,
      page: clampText(req.body?.page, MAX_SHORT_LENGTH),
      error_type: errorType,
      message,
      context: sanitizeContext(req.body?.context)
    };

    const { error: insertError } = await supabaseAdmin.from("app_error_log").insert(entry);

    if (insertError) {
      return json(res, 500, { ok: false, message: insertError.message });
    }

    return json(res, 200, { ok: true });
  } catch (error) {
    return json(res, 500, { ok: false, message: error.message });
  }
}
