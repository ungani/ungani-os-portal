import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const MAX_ACTION_LENGTH = 100;
const MAX_TEXT_LENGTH = 2000;
const MAX_METADATA_BYTES = 8000;

function json(res, status, body) {
  res.status(status).json(body);
}

function getClientIp(req) {
  const forwarded = req.headers["x-forwarded-for"];
  if (forwarded) {
    return String(forwarded).split(",")[0].trim();
  }
  return req.socket?.remoteAddress || null;
}

function clampText(value, maxLength) {
  if (value === undefined || value === null) return null;
  const text = String(value);
  return text.length > maxLength ? text.slice(0, maxLength) : text;
}

function sanitizeMetadata(metadata) {
  if (metadata === undefined || metadata === null) return null;
  if (typeof metadata !== "object" || Array.isArray(metadata)) return null;
  try {
    const serialized = JSON.stringify(metadata);
    if (serialized.length > MAX_METADATA_BYTES) return null;
    return metadata;
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

    const action = clampText(req.body?.action, MAX_ACTION_LENGTH);

    if (!action) {
      return json(res, 400, { ok: false, message: "Missing required field: action." });
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
      actor_user_id: actor.id,
      actor_email: actor.email || null,
      actor_tenant_id: profile?.tenant_id || null,
      tenant_id: clampText(req.body?.tenantId, 100) || profile?.tenant_id || null,
      action,
      entity_type: clampText(req.body?.entityType, MAX_ACTION_LENGTH),
      entity_id: clampText(req.body?.entityId, MAX_ACTION_LENGTH),
      description: clampText(req.body?.description, MAX_TEXT_LENGTH),
      metadata: sanitizeMetadata(req.body?.metadata),
      ip_address: getClientIp(req),
      user_agent: clampText(req.headers["user-agent"], MAX_TEXT_LENGTH)
    };

    const { error: insertError } = await supabaseAdmin.from("ungani_audit_log").insert(entry);

    if (insertError) {
      return json(res, 500, { ok: false, message: insertError.message });
    }

    return json(res, 200, { ok: true });
  } catch (error) {
    return json(res, 500, { ok: false, message: error.message });
  }
}
