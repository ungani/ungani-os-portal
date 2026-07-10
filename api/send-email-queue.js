import nodemailer from "nodemailer";
import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const SMTP_HOST = process.env.UNGANI_SMTP_HOST;
const SMTP_PORT = Number(process.env.UNGANI_SMTP_PORT || 465);
const SMTP_SECURE = String(process.env.UNGANI_SMTP_SECURE || "true") === "true";

const INFO_EMAIL = process.env.UNGANI_INFO_EMAIL;
const INFO_PASSWORD = process.env.UNGANI_INFO_EMAIL_PASSWORD;

const SUPPORT_EMAIL = process.env.UNGANI_SUPPORT_EMAIL;
const SUPPORT_PASSWORD = process.env.UNGANI_SUPPORT_EMAIL_PASSWORD;

const EMAIL_SENDER_SECRET = process.env.UNGANI_EMAIL_SENDER_SECRET;

function json(res, status, body) {
  res.status(status).json(body);
}

function getSenderForQueueRecord(record) {
  const typeText = [
    record.email_type,
    record.notification_type,
    record.queue_type,
    record.category,
    record.source_table
  ]
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
  const to = pickField(record, [
    "recipient_email",
    "to_email",
    "email_to",
    "client_email",
    "email"
  ]);

  const subject = pickField(record, [
    "email_subject",
    "subject",
    "notification_title",
    "title"
  ], "UNGANI OS Notification");

  const html = pickField(record, [
    "email_html",
    "html_body",
    "body_html",
    "message_html"
  ]);

  const text = pickField(record, [
    "email_text",
    "text_body",
    "body_text",
    "message",
    "notification_message",
    "email_body"
  ], "You have a new UNGANI OS notification.");

  return {
    to,
    subject,
    html: html || undefined,
    text
  };
}

async function updateQueueRecord(supabase, tableName, id, patch) {
  const { error } = await supabase
    .from(tableName)
    .update(patch)
    .eq("id", id);

  if (error) {
    return {
      ok: false,
      message: error.message
    };
  }

  return {
    ok: true
  };
}

async function findQueueTable(supabase) {
  const candidates = [
    "ungani_email_queue",
    "email_queue",
    "ungani_email_logs"
  ];

  for (const tableName of candidates) {
    const { data, error } = await supabase
      .from(tableName)
      .select("*")
      .limit(1);

    if (!error) {
      return tableName;
    }
  }

  return null;
}

async function getPendingEmails(supabase, tableName, limit) {
  const statusColumns = ["status", "email_status", "send_status"];

  for (const statusColumn of statusColumns) {
    const { data, error } = await supabase
      .from(tableName)
      .select("*")
      .in(statusColumn, ["pending", "queued", "retry"])
      .order("created_at", { ascending: true })
      .limit(limit);

    if (!error) {
      return {
        ok: true,
        statusColumn,
        rows: data || []
      };
    }
  }

  const { data, error } = await supabase
    .from(tableName)
    .select("*")
    .order("created_at", { ascending: true })
    .limit(limit);

  if (error) {
    return {
      ok: false,
      message: error.message,
      rows: []
    };
  }

  return {
    ok: true,
    statusColumn: "status",
    rows: data || []
  };
}

export default async function handler(req, res) {
  try {
    if (req.method !== "POST") {
      return json(res, 405, {
        ok: false,
        message: "Method not allowed. Use POST."
      });
    }

    const providedSecret =
      req.headers["x-ungani-email-secret"] ||
      req.body?.secret ||
      req.query?.secret;

    if (!EMAIL_SENDER_SECRET || providedSecret !== EMAIL_SENDER_SECRET) {
      return json(res, 401, {
        ok: false,
        message: "Unauthorized email sender request."
      });
    }

    const requiredEnv = {
      SUPABASE_URL,
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
      auth: {
        persistSession: false,
        autoRefreshToken: false
      }
    });

    const tableName = await findQueueTable(supabase);

    if (!tableName) {
      return json(res, 500, {
        ok: false,
        message: "No email queue table found. Expected ungani_email_queue, email_queue, or ungani_email_logs."
      });
    }

    const limit = Math.max(1, Math.min(Number(req.body?.limit || 10), 25));
    const pendingResult = await getPendingEmails(supabase, tableName, limit);

    if (!pendingResult.ok) {
      return json(res, 500, {
        ok: false,
        message: pendingResult.message
      });
    }

    const rows = pendingResult.rows;
    const statusColumn = pendingResult.statusColumn;
    const results = [];

    for (const record of rows) {
      const email = buildEmail(record);

      if (!email.to) {
        const failedPatch = {
          [statusColumn]: "failed",
          error_message: "Missing recipient email.",
          updated_at: new Date().toISOString()
        };

        await updateQueueRecord(supabase, tableName, record.id, failedPatch);

        results.push({
          id: record.id,
          ok: false,
          message: "Missing recipient email."
        });

        continue;
      }

      const sender = getSenderForQueueRecord(record);

      if (!sender.email || !sender.password) {
        results.push({
          id: record.id,
          ok: false,
          message: "Sender email credentials missing."
        });

        continue;
      }

      const transporter = nodemailer.createTransport({
        host: SMTP_HOST,
        port: SMTP_PORT,
        secure: SMTP_SECURE,
        auth: {
          user: sender.email,
          pass: sender.password
        }
      });

      try {
        await updateQueueRecord(supabase, tableName, record.id, {
          [statusColumn]: "sending",
          updated_at: new Date().toISOString()
        });

        const sent = await transporter.sendMail({
          from: `"${sender.label}" <${sender.email}>`,
          to: email.to,
          subject: email.subject,
          text: email.text,
          html: email.html
        });

        const sentPatch = {
          [statusColumn]: "sent",
          sent_at: new Date().toISOString(),
          error_message: null,
          updated_at: new Date().toISOString()
        };

        if ("provider_message_id" in record) {
          sentPatch.provider_message_id = sent.messageId || null;
        }

        await updateQueueRecord(supabase, tableName, record.id, sentPatch);

        results.push({
          id: record.id,
          ok: true,
          to: email.to,
          from: sender.email,
          messageId: sent.messageId
        });
      } catch (sendError) {
        await updateQueueRecord(supabase, tableName, record.id, {
          [statusColumn]: "failed",
          error_message: sendError.message,
          updated_at: new Date().toISOString()
        });

        results.push({
          id: record.id,
          ok: false,
          to: email.to,
          message: sendError.message
        });
      }
    }

    return json(res, 200, {
      ok: true,
      message: "Email queue processing completed.",
      table: tableName,
      processed: results.length,
      results
    });
  } catch (error) {
    return json(res, 500, {
      ok: false,
      message: error.message
    });
  }
}
