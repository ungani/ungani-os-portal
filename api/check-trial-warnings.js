import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = process.env.SUPABASE_URL || "https://ctmtjwklltnsmfdtvqhl.supabase.co";
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const SUPABASE_ANON_KEY = "sb_publishable_jkZaWWep-cObTEv_F_kN6g_Ic85BxD9";
const CRON_SECRET = process.env.CRON_SECRET;

const APP_URL = "https://ungani-os-portal.vercel.app";

// Same window as client-shared.js/client.html's warning banner - keep the
// email and the banner triggering on the same day range.
const WARNING_WINDOW_DAYS = 3;

// Once a warning email has gone out for a tenant, don't send another one
// until this many days later - covers the whole 3-day warning window with
// one email per daily cron run, not one per day.
const WARNING_DEDUP_DAYS = 5;

// A trial only ends once. This window is generous purely so a transient
// failure (queue insert succeeds, tenant somehow still reads as "trial"
// next run) can't spam a second "your trial has ended" email.
const ENDED_DEDUP_DAYS = 60;

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

function pickField(record, names, fallback = "") {
  for (const name of names) {
    if (record[name] !== undefined && record[name] !== null && String(record[name]).trim() !== "") {
      return record[name];
    }
  }

  return fallback;
}

function daysRemaining(trialEndAt, now) {
  if (!trialEndAt) return null;
  const trialEnd = new Date(trialEndAt);
  if (isNaN(trialEnd.getTime())) return null;
  return (trialEnd.getTime() - now.getTime()) / 86400000;
}

function buildWarningEmail(businessName, daysLeft) {
  const dayWord = daysLeft === 1 ? "day" : "days";
  return {
    email_subject: `Your UNGANI OS trial ends in ${daysLeft} ${dayWord}`,
    email_body:
      `Hi ${businessName},\n\n` +
      `Your free trial of UNGANI OS ends in ${daysLeft} ${dayWord}. Choose a plan now to keep full access - nothing is blocked yet, this is just a heads-up.\n\n` +
      `Your existing data is always safe and visible, even after the trial ends.\n\n` +
      `Choose a plan: ${APP_URL}/my-package.html#requestedPackage\n\n` +
      `- UNGANI OS Team`
  };
}

function buildEndedEmail(businessName) {
  return {
    email_subject: "Your UNGANI OS trial has ended",
    email_body:
      `Hi ${businessName},\n\n` +
      `Your free trial of UNGANI OS has ended. Choose a plan to continue adding new records - your existing data is safe and visible.\n\n` +
      `Choose a plan: ${APP_URL}/my-package.html#requestedPackage\n\n` +
      `- UNGANI OS Team`
  };
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
      return json(res, 401, { ok: false, message: "Unauthorized trial-warning check request." });
    }

    if (!SUPABASE_SERVICE_ROLE_KEY) {
      return json(res, 500, { ok: false, message: "Missing required environment variable: SUPABASE_SERVICE_ROLE_KEY" });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false }
    });

    const { data: subs, error: subsError } = await supabase
      .from("ungani_subscriptions")
      .select("tenant_id, subscription_status, payment_status, trial_end_at")
      .eq("subscription_status", "trial")
      .not("trial_end_at", "is", null);

    if (subsError) {
      return json(res, 500, { ok: false, message: subsError.message });
    }

    const now = new Date();
    const candidates = [];

    for (const sub of subs || []) {
      const remaining = daysRemaining(sub.trial_end_at, now);
      if (remaining === null) continue;

      if (remaining > 0 && remaining <= WARNING_WINDOW_DAYS) {
        candidates.push({ tenantId: sub.tenant_id, kind: "trial_warning", daysLeft: Math.max(1, Math.ceil(remaining)) });
      } else if (remaining <= 0) {
        candidates.push({ tenantId: sub.tenant_id, kind: "trial_ended" });
      }
    }

    if (!candidates.length) {
      return json(res, 200, { ok: true, message: "No trials in the warning or ended window.", via, checked: (subs || []).length, queued: 0 });
    }

    const tenantIds = [...new Set(candidates.map(c => c.tenantId))];

    const { data: tenants, error: tenantsError } = await supabase
      .from("tenants")
      .select("*")
      .in("id", tenantIds);

    if (tenantsError) {
      return json(res, 500, { ok: false, message: tenantsError.message });
    }

    const tenantById = new Map((tenants || []).map(t => [String(t.id), t]));

    const { data: recentEmails, error: recentError } = await supabase
      .from("ungani_email_queue")
      .select("tenant_id, email_type, created_at")
      .in("email_type", ["trial_warning", "trial_ended"])
      .in("tenant_id", tenantIds);

    if (recentError) {
      return json(res, 500, { ok: false, message: recentError.message });
    }

    const lastSentAt = new Map();
    for (const row of recentEmails || []) {
      const key = `${row.tenant_id}:${row.email_type}`;
      const existing = lastSentAt.get(key);
      const created = new Date(row.created_at);
      if (!existing || created > existing) {
        lastSentAt.set(key, created);
      }
    }

    const toInsert = [];
    const skipped = [];

    for (const candidate of candidates) {
      const dedupDays = candidate.kind === "trial_warning" ? WARNING_DEDUP_DAYS : ENDED_DEDUP_DAYS;
      const key = `${candidate.tenantId}:${candidate.kind}`;
      const lastSent = lastSentAt.get(key);

      if (lastSent && (now.getTime() - lastSent.getTime()) / 86400000 < dedupDays) {
        skipped.push({ tenantId: candidate.tenantId, kind: candidate.kind, reason: "already sent within dedup window" });
        continue;
      }

      const tenant = tenantById.get(String(candidate.tenantId));
      if (!tenant) {
        skipped.push({ tenantId: candidate.tenantId, kind: candidate.kind, reason: "tenant record not found" });
        continue;
      }

      const recipientEmail = pickField(tenant, ["business_email", "email", "contact_email"]);
      if (!recipientEmail) {
        skipped.push({ tenantId: candidate.tenantId, kind: candidate.kind, reason: "no recipient email on tenant record" });
        continue;
      }

      const businessName = pickField(tenant, ["business_name", "company_name", "tenant_name"], "there");

      const content = candidate.kind === "trial_warning"
        ? buildWarningEmail(businessName, candidate.daysLeft)
        : buildEndedEmail(businessName);

      toInsert.push({
        tenant_id: candidate.tenantId,
        recipient_email: recipientEmail,
        recipient_name: businessName,
        email_subject: content.email_subject,
        email_body: content.email_body,
        email_type: candidate.kind,
        related_table: "ungani_subscriptions",
        related_id: candidate.tenantId,
        send_status: "pending",
        created_at: now.toISOString()
      });
    }

    if (!toInsert.length) {
      return json(res, 200, { ok: true, message: "Nothing new to queue.", via, checked: (subs || []).length, queued: 0, skipped });
    }

    const { data: inserted, error: insertError } = await supabase
      .from("ungani_email_queue")
      .insert(toInsert)
      .select("id, tenant_id, email_type");

    if (insertError) {
      return json(res, 500, { ok: false, message: insertError.message });
    }

    return json(res, 200, {
      ok: true,
      message: "Trial warning/ended emails queued.",
      via,
      checked: (subs || []).length,
      queued: inserted?.length || toInsert.length,
      skipped
    });
  } catch (error) {
    return json(res, 500, { ok: false, message: error.message });
  }
}
