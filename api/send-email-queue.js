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

function buildEmail(record) {
  const to = pickField(record, ["recipient_email", "to_email", "email_to", "email"]);
  const subject = pickField(record, ["email_subject", "subject"], "UNGANI OS Notification");
  const html = pickField(record, ["email_html", "html_body"]);
  const text = pickField(record, ["email_body", "email_text", "text_body"], "You have a new UNGANI OS notification.");

  return {
    to,
    subject,
    html: html || undefined,
    text
  };
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

async function getPendingEmails(supabase, limit) {
  const { data, error } = await supabase
    .from(QUEUE_TABLE)
    .select("*")
    .in(STATUS_COLUMN, PENDING_STATUSES)
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

    const via = isCronRequest(bearerToken)
      ? "cron"
      : (await isAdminRequest(bearerToken))
        ? "admin"
        : isLegacySecretRequest(req)
          ? "legacy_secret"
          : null;

    if (!via) {
      return json(res, 401, { ok: false, message: "Unauthorized email sender request." });
    }

    const requiredEnv = {
      SUPABASE_SERVICE_ROLE_KEY,
      UNGANI_SMTP_HOST: SMTP_HOST,
      UNGANI_INFO_EMAIL: INFO_EMAIL,
      UNGANI_INFO_EMAIL_PASSWORD: INFO_PASSWORD,
      UNGANI_SUPPORT_EMAIL: SUPPORT_EMAIL,
      UNGANI_SUPPORT_EMAIL_PASSWORD: SUPPORT_PASSWORD
    };

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

    const limit = Math.max(1, Math.min(Number(req.body?.limit || req.query?.limit || 15), 25));
    const pendingResult = await getPendingEmails(supabase, limit);

    if (!pendingResult.ok) {
      return json(res, 500, { ok: false, message: pendingResult.message });
    }

    const rows = pendingResult.rows;
    const results = [];

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

      const sender = getSenderForQueueRecord(record);

      if (!sender.email || !sender.password) {
        results.push({ id: record.id, ok: false, message: "Sender email credentials missing." });
        continue;
      }

      const transporter = nodemailer.createTransport({
        host: SMTP_HOST,
        port: SMTP_PORT,
        secure: SMTP_SECURE,
        auth: { user: sender.email, pass: sender.password }
      });

      try {
        await updateQueueRecord(supabase, record.id, {
          [STATUS_COLUMN]: "sending",
          [ATTEMPTS_COLUMN]: attempts,
          updated_at: new Date().toISOString()
        });

        const sent = await transporter.sendMail({
          from: `"${sender.label}" <${sender.email}>`,
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

        results.push({ id: record.id, ok: false, to: email.to, message: sendError.message });
      }
    }

    return json(res, 200, {
      ok: true,
      message: "Email queue processing completed.",
      via,
      table: QUEUE_TABLE,
      processed: results.length,
      results
    });
  } catch (error) {
    return json(res, 500, { ok: false, message: error.message });
  }
}
