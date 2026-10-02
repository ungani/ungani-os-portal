import nodemailer from "nodemailer";
import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = process.env.SUPABASE_URL || "https://ctmtjwklltnsmfdtvqhl.supabase.co";
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const SUPABASE_ANON_KEY = "sb_publishable_jkZaWWep-cObTEv_F_kN6g_Ic85BxD9";

const SMTP_HOST = process.env.UNGANI_SMTP_HOST;
const SMTP_PORT = Number(process.env.UNGANI_SMTP_PORT || 465);
const SMTP_SECURE = String(process.env.UNGANI_SMTP_SECURE || "true") === "true";

const INFO_EMAIL = process.env.UNGANI_INFO_EMAIL;
const INFO_PASSWORD = process.env.UNGANI_INFO_EMAIL_PASSWORD;

const SUPPORT_EMAIL = process.env.UNGANI_SUPPORT_EMAIL;
const SUPPORT_PASSWORD = process.env.UNGANI_SUPPORT_EMAIL_PASSWORD;

// Presence of this key alone is the "swap to Resend" switch - set it in
// Vercel once the ungani.com domain shows Verified in the Resend
// dashboard, redeploy, and every automated send from here on goes
// through Resend's API instead of the SMTP mailbox below. Nothing else
// in this file changes: same queue table, same sender routing, same
// templates, same triggers - only the transport underneath buildEmail()
// changes. The SMTP mailbox itself is untouched and keeps working for
// normal human inbox use, since this only affects app-triggered sends.
const RESEND_API_KEY = process.env.RESEND_API_KEY;

// Go-forward suppression memory for addresses that have genuinely hard-
// bounced (mailbox doesn't exist - a permanent failure), kept separate
// from fake/test addresses (detected inline below, no table needed).
const HARD_BOUNCE_TABLE = "ungani_email_hard_bounces";

// A permanent "this mailbox doesn't exist" rejection, NOT the generic
// "550 high-probability spam" reputation rejection every current
// failure actually is - conflating the two would suppress real
// addresses just because the sender's reputation was bad that day.
function isHardBounceSignature(message) {
  const text = String(message || "").toLowerCase();
  if (text.includes("spam")) return false;
  return (
    text.includes("no such user") ||
    text.includes("user unknown") ||
    text.includes("mailbox unavailable") ||
    text.includes("mailbox not found") ||
    text.includes("does not exist") ||
    text.includes("no mailbox") ||
    text.includes("recipient rejected") ||
    text.includes("550 5.1.1") ||
    text.includes("invalid recipient")
  );
}

// Fake/test recipients never go anywhere near a real mail provider -
// checked against data already on the row (recipient_email, tenant_id),
// no schema change needed. Matches the real fake domains already
// confirmed live in this queue (ungani-test.local, example.com,
// ungani-branchtest.local) plus the general patterns test fixtures use.
function isFakeRecipient(record, testTenantIds) {
  const email = String(record.recipient_email || record.to_email || record.email_to || record.email || "").toLowerCase();

  if (record.tenant_id && testTenantIds.has(record.tenant_id)) return true;
  if (!email) return false;

  return (
    /@example\.(com|org)$/.test(email) ||
    /\.local$/.test(email) ||
    /@test\./.test(email) ||
    /\btest\./.test(email) ||
    /\.test$/.test(email)
  );
}

// Legacy static-secret path, kept for backward compatibility with any
// existing external caller (e.g. a third-party scheduler configured
// before Vercel Cron / admin-triggered auth existed below).
const EMAIL_SENDER_SECRET = process.env.UNGANI_EMAIL_SENDER_SECRET;
const CRON_SECRET = process.env.CRON_SECRET;

// The real queue table/columns, confirmed from admin-email-queue.html's
// own read/write RPCs (admin_get_ungani_email_queue /
// admin_update_ungani_email_queue_status) - not guessed.
const QUEUE_TABLE = "ungani_email_queue";
const STATUS_COLUMN = "send_status";
const ERROR_COLUMN = "last_error";
const ATTEMPTS_COLUMN = "send_attempts";
const PENDING_STATUSES = ["pending", "queued", "retry"];

function json(res, status, body) {
  res.status(status).json(body);
}

// Vercel Cron sends `Authorization: Bearer $CRON_SECRET` automatically
// once CRON_SECRET is set as a project env var and a cron job targeting
// this route exists in vercel.json - this is Vercel's own documented
// pattern for authenticating scheduled invocations.
function isCronRequest(bearerToken) {
  return Boolean(bearerToken && CRON_SECRET && bearerToken === CRON_SECRET);
}

// For the admin-triggered "Send Now" button: verify the caller's own
// Supabase session by creating a client scoped to their JWT (not the
// service role) so is_ungani_admin() evaluates auth.uid() exactly as it
// does for every other admin-gated call in this app, rather than
// re-implementing the admin check server-side against a guessed column.
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

// For tenant-triggered instant delivery (task assignment, team
// invitation, payroll payment - all owner/staff actions, not UNGANI
// admin actions, so isAdminRequest() above never applies to them).
// Verifies the caller's own session the same way as isAdminRequest()
// above (their own JWT, not service role), then reuses the already-
// existing get_my_ungani_tenant_id() RPC (used everywhere else in this
// app for the same purpose) to resolve their real tenant_id - the
// caller can never claim to be any tenant other than their own. The
// returned tenant_id is used below to scope getPendingEmails() to ONLY
// that tenant's rows, so this can never be used to trigger delivery of
// another tenant's queued email.
async function getRequestingTenantId(bearerToken) {
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

function isLegacySecretRequest(req) {
  const providedSecret =
    req.headers["x-ungani-email-secret"] ||
    req.body?.secret ||
    req.query?.secret;

  return Boolean(EMAIL_SENDER_SECRET && providedSecret === EMAIL_SENDER_SECRET);
}

function getSenderForQueueRecord(record) {
  const typeText = [record.email_type, record.related_table]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();

  const shouldUseSupport =
    typeText.includes("support") ||
    typeText.includes("issue") ||
    typeText.includes("ticket");

  if (shouldUseSupport) {
    return {
      email: SUPPORT_EMAIL,
      password: SUPPORT_PASSWORD,
      label: "UNGANI Support"
    };
  }

  return {
    email: INFO_EMAIL,
    password: INFO_PASSWORD,
    label: "UNGANI"
  };
}

function pickField(record, names, fallback = "") {
  for (const name of names) {
    if (record[name] !== undefined && record[name] !== null && String(record[name]).trim() !== "") {
      return record[name];
    }
  }

  return fallback;
}

function escapeHtml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

// Auto-builds a branded HTML part from the plain text when no explicit
// email_html/html_body was provided - every email this system has ever
// sent was plain-text-only (nothing writes to those columns), which is
// itself a spam-scoring signal on top of everything else. A paragraph
// that's exactly "Label: https://..." (the CTA pattern every current
// email producer already uses, e.g. "Choose a plan: https://...")
// renders as a styled button instead of a bare link.
function buildHtmlFromText(text) {
  const paragraphs = String(text || "")
    .split(/\n\s*\n/)
    .map(function (p) { return p.trim(); })
    .filter(Boolean);

  const bodyHtml = paragraphs.map(function (paragraph) {
    const linkMatch = paragraph.match(/^(.*):\s*(https?:\/\/\S+)\s*$/);

    if (linkMatch) {
      return (
        '<p style="margin:0 0 20px;text-align:center;">' +
        '<a href="' + escapeHtml(linkMatch[2]) + '" style="display:inline-block;background:#D4A63A;color:#061C3D;font-weight:700;text-decoration:none;padding:12px 28px;border-radius:10px;font-family:Arial,Helvetica,sans-serif;">' +
        escapeHtml(linkMatch[1]) + '</a></p>'
      );
    }

    return (
      '<p style="margin:0 0 16px;color:#1F2937;font-size:15px;line-height:1.6;font-family:Arial,Helvetica,sans-serif;">' +
      escapeHtml(paragraph).replace(/\n/g, "<br>") + '</p>'
    );
  }).join("");

  return (
    '<div style="background:#F5F5F3;padding:32px 16px;font-family:Arial,Helvetica,sans-serif;">' +
    '<div style="max-width:520px;margin:0 auto;background:#FFFFFF;border-radius:16px;overflow:hidden;border:1px solid #E5E7EB;">' +
    '<div style="background:#061C3D;padding:20px 28px;">' +
    '<span style="color:#F5F5F3;font-weight:800;font-size:16px;letter-spacing:0.3px;">UNGANI OS</span>' +
    '</div>' +
    '<div style="padding:28px;">' + bodyHtml + '</div>' +
    '<div style="padding:18px 28px;background:#F8FAFC;border-top:1px solid #E5E7EB;">' +
    '<p style="margin:0;color:#6B7280;font-size:12.5px;line-height:1.6;font-family:Arial,Helvetica,sans-serif;">' +
    "You're receiving this because you have an account with UNGANI OS. " +
    'Questions? Contact <a href="mailto:info@ungani.com" style="color:#061C3D;">info@ungani.com</a>.' +
    '</p></div></div></div>'
  );
}

function buildEmail(record) {
  const to = pickField(record, ["recipient_email", "to_email", "email_to", "email"]);
  const subject = pickField(record, ["email_subject", "subject"], "UNGANI OS Notification");
  const explicitHtml = pickField(record, ["email_html", "html_body"]);
  const text = pickField(record, ["email_body", "email_text", "text_body"], "You have a new UNGANI OS notification.");

  return {
    to,
    subject,
    html: explicitHtml || buildHtmlFromText(text),
    text
  };
}

// Same email shape (to/subject/html/text), same sender identity - only
// the transport differs from the nodemailer/SMTP path below. Resend
// returns its own id as messageId so the rest of the file (queue update,
// results array) doesn't need to know which transport was used.
async function sendViaResend(email, sender) {
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: "Bearer " + RESEND_API_KEY
    },
    body: JSON.stringify({
      from: `${sender.label} <${sender.email}>`,
      reply_to: sender.email,
      to: email.to,
      subject: email.subject,
      text: email.text,
      html: email.html
    })
  });

  const result = await response.json().catch(() => null);

  if (!response.ok) {
    throw new Error((result && (result.message || result.name)) || "Resend send failed with status " + response.status);
  }

  return { messageId: result && result.id };
}

async function getTestTenantIds(supabase) {
  const { data, error } = await supabase.from("tenants").select("id").eq("is_test", true);
  if (error) return new Set();
  return new Set((data || []).map((row) => row.id));
}

async function getHardBouncedEmails(supabase) {
  const { data, error } = await supabase.from(HARD_BOUNCE_TABLE).select("email");
  if (error) return new Set();
  return new Set((data || []).map((row) => String(row.email || "").toLowerCase()));
}

async function recordHardBounce(supabase, email, reason) {
  if (!email) return;
  await supabase
    .from(HARD_BOUNCE_TABLE)
    .upsert({ email: email.toLowerCase(), reason, bounced_at: new Date().toISOString() }, { onConflict: "email" });
}

async function updateQueueRecord(supabase, id, patch) {
  const { error } = await supabase
    .from(QUEUE_TABLE)
    .update(patch)
    .eq("id", id);

  if (error) {
    return { ok: false, message: error.message };
  }

  return { ok: true };
}

async function getRegistrationAlertRow(supabase, relatedId) {
  const tenMinutesAgo = new Date(Date.now() - 10 * 60 * 1000).toISOString();

  const { data, error } = await supabase
    .from(QUEUE_TABLE)
    .select("*")
    .eq("related_table", "registrations")
    .eq("related_id", relatedId)
    .eq("email_type", "registration_received_admin")
    .in(STATUS_COLUMN, PENDING_STATUSES)
    .gte("created_at", tenMinutesAgo)
    .limit(1);

  if (error) {
    return { ok: false, message: error.message, rows: [] };
  }

  return { ok: true, rows: data || [] };
}

async function getPendingEmails(supabase, limit, tenantId) {
  let query = supabase
    .from(QUEUE_TABLE)
    .select("*")
    .in(STATUS_COLUMN, PENDING_STATUSES);

  if (tenantId) {
    query = query.eq("tenant_id", tenantId);
  }

  const { data, error } = await query
    .order("created_at", { ascending: true })
    .limit(limit);

  if (error) {
    return { ok: false, message: error.message, rows: [] };
  }

  return { ok: true, rows: data || [] };
}

export default async function handler(req, res) {
  try {
    if (req.method !== "GET" && req.method !== "POST") {
      return json(res, 405, { ok: false, message: "Method not allowed. Use GET or POST." });
    }

    const authHeader = req.headers["authorization"] || "";
    const bearerToken = authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : null;

    let via = isCronRequest(bearerToken)
      ? "cron"
      : (await isAdminRequest(bearerToken))
        ? "admin"
        : isLegacySecretRequest(req)
          ? "legacy_secret"
          : null;

    // Tenant-scoped instant delivery for owner/staff-triggered events
    // (task assignment, team invitation, payroll payment) - none of
    // these are UNGANI-admin actions, so isAdminRequest() above never
    // matches them, and they'd otherwise wait for the once-daily cron.
    // Checked only after the admin/cron/legacy paths above all miss, so
    // an actual admin or cron request is never mistakenly narrowed to
    // tenant scope.
    let requestingTenantId = null;

    if (!via) {
      requestingTenantId = await getRequestingTenantId(bearerToken);
      if (requestingTenantId) {
        via = "tenant_self";
      }
    }

    // Immediate UNGANI-admin alert for a brand-new registration - the
    // person submitting the form isn't logged in (no bearer token), so
    // none of the paths above can match. Checked only after every
    // authenticated path above has already missed, and deliberately
    // narrow: the server re-derives everything from relatedId itself
    // (never trusts a subject/body/recipient from the request), and
    // getRegistrationAlertRow() below only ever matches ONE specific
    // email_type, created in the last 10 minutes, still pending - so
    // this can never be used to trigger an arbitrary send.
    let registrationAlertRelatedId = null;

    if (!via && req.method === "POST" && req.body && req.body.instantRegistrationAlert === true && req.body.relatedId) {
      registrationAlertRelatedId = String(req.body.relatedId);
      via = "registration_alert";
    }

    if (!via) {
      return json(res, 401, { ok: false, message: "Unauthorized email sender request." });
    }

    const requiredEnv = {
      SUPABASE_SERVICE_ROLE_KEY,
      UNGANI_INFO_EMAIL: INFO_EMAIL,
      UNGANI_SUPPORT_EMAIL: SUPPORT_EMAIL
    };

    // Mailbox passwords are only needed for the SMTP transport - once
    // RESEND_API_KEY is set, Resend is used instead and these become
    // irrelevant (the "from" addresses above are still required either
    // way, since Resend sends as them too).
    if (!RESEND_API_KEY) {
      requiredEnv.UNGANI_SMTP_HOST = SMTP_HOST;
      requiredEnv.UNGANI_INFO_EMAIL_PASSWORD = INFO_PASSWORD;
      requiredEnv.UNGANI_SUPPORT_EMAIL_PASSWORD = SUPPORT_PASSWORD;
    }

    const missing = Object.entries(requiredEnv)
      .filter(([, value]) => !value)
      .map(([key]) => key);

    if (missing.length) {
      return json(res, 500, {
        ok: false,
        message: "Missing required environment variables.",
        missing
      });
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false }
    });

    // Tenant-scoped requests get a lower cap (defense-in-depth on top of
    // the tenant_id scoping itself - a real tenant can only ever have a
    // handful of their own pending rows at once from these trigger
    // points, so there's no legitimate reason for them to request more).
    const requestedLimit = Number(req.body?.limit || req.query?.limit || 15);
    const limit = via === "tenant_self"
      ? Math.max(1, Math.min(requestedLimit, 5))
      : Math.max(1, Math.min(requestedLimit, 25));

    const pendingResult = via === "registration_alert"
      ? await getRegistrationAlertRow(supabase, registrationAlertRelatedId)
      : await getPendingEmails(supabase, limit, via === "tenant_self" ? requestingTenantId : null);

    if (!pendingResult.ok) {
      return json(res, 500, { ok: false, message: pendingResult.message });
    }

    const rows = pendingResult.rows;
    const results = [];

    // Fetched once per invocation (cheap, both sets stay small) rather
    // than per row - a single registration_alert row still pays this
    // cost, but that path only ever processes one row anyway.
    const [testTenantIds, hardBouncedEmails] = await Promise.all([
      getTestTenantIds(supabase),
      getHardBouncedEmails(supabase)
    ]);

    for (const record of rows) {
      const attempts = Number(record[ATTEMPTS_COLUMN] || 0) + 1;
      const email = buildEmail(record);

      if (!email.to) {
        await updateQueueRecord(supabase, record.id, {
          [STATUS_COLUMN]: "failed",
          [ERROR_COLUMN]: "Missing recipient email.",
          [ATTEMPTS_COLUMN]: attempts,
          updated_at: new Date().toISOString()
        });

        results.push({ id: record.id, ok: false, message: "Missing recipient email." });
        continue;
      }

      // Suppression: fake/test recipients and known hard-bounces never
      // reach a real mail provider - marked 'cancelled' (an existing,
      // already-used status) with a clear reason instead of 'failed', so
      // they don't get confused with a genuine delivery problem.
      if (isFakeRecipient(record, testTenantIds)) {
        await updateQueueRecord(supabase, record.id, {
          [STATUS_COLUMN]: "cancelled",
          [ERROR_COLUMN]: "Suppressed: fake/test recipient (never sent).",
          updated_at: new Date().toISOString()
        });

        results.push({ id: record.id, ok: false, suppressed: true, to: email.to, message: "Suppressed: fake/test recipient." });
        continue;
      }

      if (hardBouncedEmails.has(email.to.toLowerCase())) {
        await updateQueueRecord(supabase, record.id, {
          [STATUS_COLUMN]: "cancelled",
          [ERROR_COLUMN]: "Suppressed: address previously hard-bounced (never sent).",
          updated_at: new Date().toISOString()
        });

        results.push({ id: record.id, ok: false, suppressed: true, to: email.to, message: "Suppressed: previously hard-bounced." });
        continue;
      }

      const sender = getSenderForQueueRecord(record);

      if (!sender.email || (!RESEND_API_KEY && !sender.password)) {
        results.push({ id: record.id, ok: false, message: "Sender email credentials missing." });
        continue;
      }

      try {
        await updateQueueRecord(supabase, record.id, {
          [STATUS_COLUMN]: "sending",
          [ATTEMPTS_COLUMN]: attempts,
          updated_at: new Date().toISOString()
        });

        const sent = RESEND_API_KEY
          ? await sendViaResend(email, sender)
          : await nodemailer.createTransport({
              host: SMTP_HOST,
              port: SMTP_PORT,
              secure: SMTP_SECURE,
              auth: { user: sender.email, pass: sender.password }
            }).sendMail({
              from: `"${sender.label}" <${sender.email}>`,
              replyTo: sender.email,
              to: email.to,
              subject: email.subject,
              text: email.text,
              html: email.html
            });

        await updateQueueRecord(supabase, record.id, {
          [STATUS_COLUMN]: "sent",
          [ERROR_COLUMN]: null,
          sent_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        });

        results.push({
          id: record.id,
          ok: true,
          to: email.to,
          from: sender.email,
          messageId: sent.messageId
        });
      } catch (sendError) {
        await updateQueueRecord(supabase, record.id, {
          [STATUS_COLUMN]: "failed",
          [ERROR_COLUMN]: sendError.message,
          updated_at: new Date().toISOString()
        });

        if (isHardBounceSignature(sendError.message)) {
          await recordHardBounce(supabase, email.to, sendError.message);
        }

        results.push({ id: record.id, ok: false, to: email.to, message: sendError.message });
      }
    }

    return json(res, 200, {
      ok: true,
      message: "Email queue processing completed.",
      via,
      table: QUEUE_TABLE,
      resendConfigured: Boolean(RESEND_API_KEY),
      processed: results.length,
      results
    });
  } catch (error) {
    return json(res, 500, { ok: false, message: error.message });
  }
}
