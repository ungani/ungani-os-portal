import { createClient } from "@supabase/supabase-js";

// File name is now narrower than its actual scope - originally trial-
// only, this now also covers paying-tenant subscription-renewal
// reminders and the grace-period/suspension mechanism. Left unrenamed
// to avoid a vercel.json cron-path change; the cadence below applies
// uniformly to both tracks (see WARNING_FAR_DAYS etc.).

const SUPABASE_URL = process.env.SUPABASE_URL || "https://ctmtjwklltnsmfdtvqhl.supabase.co";
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const SUPABASE_ANON_KEY = "sb_publishable_jkZaWWep-cObTEv_F_kN6g_Ic85BxD9";
const CRON_SECRET = process.env.CRON_SECRET;

const APP_URL = "https://ungani-os-portal.vercel.app";

// The full requested cadence: ~1 week out, a closer 2-3 day reminder,
// an ended notice, then a grace period before auto-suspension. Applied
// identically to trial accounts (against trial_end_at) and paying
// accounts (against subscription_ends_at) - see gatherCandidates().
export const WARNING_FAR_DAYS = 7;
export const WARNING_NEAR_DAYS = 3;
export const GRACE_PERIOD_DAYS = 7;

// Dedup windows - each covers its own trigger window with exactly one
// email per daily cron run, not one per day. WARNING_NEAR_DEDUP_DAYS
// deliberately stays the original 5 (matches the pre-existing
// 'trial_warning' email_type's stale-cleanup assumption in
// sql/email-queue-stale-cleanup.sql - do not change without updating
// that script too). WARNING_FAR_DEDUP_DAYS is shorter (4) so the near
// window can still fire on its own schedule afterward, not get
// suppressed by the far one's dedup.
const WARNING_FAR_DEDUP_DAYS = 4;
const WARNING_NEAR_DEDUP_DAYS = 5;
const ENDED_DEDUP_DAYS = 60;
const SUSPENDED_DEDUP_DAYS = 3650; // effectively once-ever per tenant

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

export function daysRemaining(endAt, now) {
  if (!endAt) return null;
  const end = new Date(endAt);
  if (isNaN(end.getTime())) return null;
  return (end.getTime() - now.getTime()) / 86400000;
}

const TRACK_COPY = {
  trial: { noun: "free trial", article: "your free trial" },
  subscription: { noun: "subscription", article: "your current subscription period" }
};

function buildWarningEmail(businessName, daysLeft, track) {
  const dayWord = daysLeft === 1 ? "day" : "days";
  const copy = TRACK_COPY[track];
  return {
    email_subject: `Your UNGANI OS ${copy.noun} ends in ${daysLeft} ${dayWord}`,
    email_body:
      `Hi ${businessName},\n\n` +
      `${copy.article[0].toUpperCase() + copy.article.slice(1)} ends in ${daysLeft} ${dayWord}. ` +
      (track === "trial"
        ? `You can choose a plan to keep full access - nothing is blocked yet, this is just a heads-up.\n\n`
        : `Renew to avoid any interruption - nothing is blocked yet, this is just a heads-up.\n\n`) +
      `Your existing data is always safe and visible, even after this date passes.\n\n` +
      `${track === "trial" ? "Choose a plan" : "Renew now"}: ${APP_URL}/my-package.html#requestedPackage\n\n` +
      `- UNGANI OS Team`
  };
}

function buildEndedEmail(businessName, track) {
  const copy = TRACK_COPY[track];
  return {
    email_subject: `Your UNGANI OS ${copy.noun} has ended`,
    email_body:
      `Hi ${businessName},\n\n` +
      `${copy.article[0].toUpperCase() + copy.article.slice(1)} has ended. Choose a plan to continue adding new records - your existing data is safe and visible.\n\n` +
      `You have ${GRACE_PERIOD_DAYS} days before your account is suspended, so there's time to sort this out without losing access to what you've already built.\n\n` +
      `Choose a plan: ${APP_URL}/my-package.html#requestedPackage\n\n` +
      `- UNGANI OS Team`
  };
}

function buildSuspendedEmail(businessName) {
  return {
    email_subject: "Your UNGANI OS account has been suspended",
    email_body:
      `Hi ${businessName},\n\n` +
      `Your UNGANI OS account has been suspended after ${GRACE_PERIOD_DAYS} days without an active plan. Your data has not been deleted - it's safe and will be there as soon as your account is reactivated.\n\n` +
      `Choose a plan to reactivate: ${APP_URL}/my-package.html#requestedPackage\n\n` +
      `If you believe this is a mistake, please contact info@ungani.com.\n\n` +
      `- UNGANI OS Team`
  };
}

// Classifies one subscription row (trial or paying) into at most one
// candidate for this run - the far warning, the near warning, the
// ended notice, or a suspend-now action once past the grace period.
// Same thresholds for both tracks; only the underlying date column and
// the resulting subscription_status differ.
export function classify(remaining, track, tenantId) {
  if (remaining === null) return null;

  if (remaining > WARNING_NEAR_DAYS && remaining <= WARNING_FAR_DAYS) {
    return { tenantId, track, kind: "warning_far", daysLeft: Math.max(1, Math.ceil(remaining)) };
  }
  if (remaining > 0 && remaining <= WARNING_NEAR_DAYS) {
    return { tenantId, track, kind: "warning_near", daysLeft: Math.max(1, Math.ceil(remaining)) };
  }
  if (remaining <= 0 && remaining > -GRACE_PERIOD_DAYS) {
    return { tenantId, track, kind: "ended" };
  }
  if (remaining <= -GRACE_PERIOD_DAYS) {
    return { tenantId, track, kind: "suspend" };
  }
  return null;
}

export function emailTypeFor(track, kind) {
  const prefix = track === "trial" ? "trial" : "subscription";
  if (kind === "warning_far") return `${prefix}_warning_week`;
  if (kind === "warning_near") return track === "trial" ? "trial_warning" : "subscription_warning";
  if (kind === "ended") return `${prefix}_ended`;
  return `${prefix}_suspended`;
}

export function dedupDaysFor(kind) {
  if (kind === "warning_far") return WARNING_FAR_DEDUP_DAYS;
  if (kind === "warning_near") return WARNING_NEAR_DEDUP_DAYS;
  if (kind === "ended") return ENDED_DEDUP_DAYS;
  return SUSPENDED_DEDUP_DAYS;
}

// Pure planning step - given this run's candidates, a tenantId->tenant
// lookup, and a "tenantId:emailType" -> last-sent-Date map, decides what
// to actually queue/suspend this run. No Supabase calls in here, so this
// is directly unit-testable without mocking a DB client.
export function buildReminderPlan(candidates, tenantById, lastSentAt, now) {
  const toInsert = [];
  const toSuspend = [];
  const skipped = [];

  for (const candidate of candidates) {
    const emailType = emailTypeFor(candidate.track, candidate.kind);
    const dedupDays = dedupDaysFor(candidate.kind);
    const key = `${candidate.tenantId}:${emailType}`;
    const lastSent = lastSentAt.get(key);

    if (lastSent && (now.getTime() - lastSent.getTime()) / 86400000 < dedupDays) {
      skipped.push({ tenantId: candidate.tenantId, kind: candidate.kind, track: candidate.track, reason: "already sent within dedup window" });
      continue;
    }

    const tenant = tenantById.get(String(candidate.tenantId));
    if (!tenant) {
      skipped.push({ tenantId: candidate.tenantId, kind: candidate.kind, track: candidate.track, reason: "tenant record not found" });
      continue;
    }

    const recipientEmail = pickField(tenant, ["business_email", "email", "contact_email"]);
    const businessName = pickField(tenant, ["business_name", "company_name", "tenant_name"], "there");

    if (candidate.kind === "suspend") {
      toSuspend.push({ tenantId: candidate.tenantId, track: candidate.track });
    }

    if (!recipientEmail) {
      skipped.push({ tenantId: candidate.tenantId, kind: candidate.kind, track: candidate.track, reason: "no recipient email on tenant record" });
      continue;
    }

    const content =
      candidate.kind === "warning_far" || candidate.kind === "warning_near"
        ? buildWarningEmail(businessName, candidate.daysLeft, candidate.track)
        : candidate.kind === "ended"
          ? buildEndedEmail(businessName, candidate.track)
          : buildSuspendedEmail(businessName);

    toInsert.push({
      tenant_id: candidate.tenantId,
      recipient_email: recipientEmail,
      recipient_name: businessName,
      email_subject: content.email_subject,
      email_body: content.email_body,
      email_type: emailType,
      related_table: "ungani_subscriptions",
      related_id: candidate.tenantId,
      send_status: "pending",
      created_at: now.toISOString()
    });
  }

  return { toInsert, toSuspend, skipped };
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
      return json(res, 401, { ok: false, message: "Unauthorized reminder check request." });
    }

    if (!SUPABASE_SERVICE_ROLE_KEY) {
      return json(res, 500, { ok: false, message: "Missing required environment variable: SUPABASE_SERVICE_ROLE_KEY" });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false }
    });

    const now = new Date();

    const [{ data: trialSubs, error: trialError }, { data: paidSubs, error: paidError }] = await Promise.all([
      supabase
        .from("ungani_subscriptions")
        .select("tenant_id, subscription_status, trial_end_at")
        .eq("subscription_status", "trial")
        .not("trial_end_at", "is", null),
      supabase
        .from("ungani_subscriptions")
        .select("tenant_id, subscription_status, subscription_ends_at")
        .eq("subscription_status", "active")
        .not("subscription_ends_at", "is", null)
    ]);

    if (trialError) return json(res, 500, { ok: false, message: trialError.message });
    if (paidError) return json(res, 500, { ok: false, message: paidError.message });

    const candidates = [];

    for (const sub of trialSubs || []) {
      const c = classify(daysRemaining(sub.trial_end_at, now), "trial", sub.tenant_id);
      if (c) candidates.push(c);
    }

    for (const sub of paidSubs || []) {
      const c = classify(daysRemaining(sub.subscription_ends_at, now), "subscription", sub.tenant_id);
      if (c) candidates.push(c);
    }

    const checked = (trialSubs || []).length + (paidSubs || []).length;

    if (!candidates.length) {
      return json(res, 200, { ok: true, message: "Nothing in the warning, ended, or suspend window.", via, checked, queued: 0, suspended: 0 });
    }

    const tenantIds = [...new Set(candidates.map(c => c.tenantId))];

    const { data: tenants, error: tenantsError } = await supabase
      .from("tenants")
      .select("*")
      .in("id", tenantIds);

    if (tenantsError) return json(res, 500, { ok: false, message: tenantsError.message });

    const tenantById = new Map((tenants || []).map(t => [String(t.id), t]));

    const allEmailTypes = [...new Set(candidates.map(c => emailTypeFor(c.track, c.kind)))];

    const { data: recentEmails, error: recentError } = await supabase
      .from("ungani_email_queue")
      .select("tenant_id, email_type, created_at")
      .in("email_type", allEmailTypes)
      .in("tenant_id", tenantIds);

    if (recentError) return json(res, 500, { ok: false, message: recentError.message });

    const lastSentAt = new Map();
    for (const row of recentEmails || []) {
      const key = `${row.tenant_id}:${row.email_type}`;
      const existing = lastSentAt.get(key);
      const created = new Date(row.created_at);
      if (!existing || created > existing) {
        lastSentAt.set(key, created);
      }
    }

    const { toInsert, toSuspend, skipped } = buildReminderPlan(candidates, tenantById, lastSentAt, now);

    let inserted = [];
    if (toInsert.length) {
      const { data, error: insertError } = await supabase
        .from("ungani_email_queue")
        .insert(toInsert)
        .select("id, tenant_id, email_type");

      if (insertError) return json(res, 500, { ok: false, message: insertError.message });
      inserted = data || [];
    }

    // Grace period elapsed - actually suspend, reusing the exact same
    // subscription_status value ('suspended') the existing admin "Suspend"
    // button already writes, so client-access-guard.js's existing
    // blockedStatuses check locks the account out with zero new
    // access-control code needed.
    let suspendedCount = 0;
    for (const s of toSuspend) {
      const { error: suspendError } = await supabase
        .from("ungani_subscriptions")
        .update({
          subscription_status: "suspended",
          notes: `Auto-suspended by daily reminder cron: ${s.track === "trial" ? "trial" : "subscription period"} exceeded the ${GRACE_PERIOD_DAYS}-day grace period.`,
          updated_at: now.toISOString()
        })
        .eq("tenant_id", s.tenantId);

      if (!suspendError) suspendedCount += 1;
    }

    return json(res, 200, {
      ok: true,
      message: "Reminder emails queued and grace-period suspensions applied.",
      via,
      checked,
      queued: inserted.length || toInsert.length,
      suspended: suspendedCount,
      skipped
    });
  } catch (error) {
    return json(res, 500, { ok: false, message: error.message });
  }
}
