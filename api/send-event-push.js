import webpush from "web-push";
import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = process.env.SUPABASE_URL || "https://ctmtjwklltnsmfdtvqhl.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_jkZaWWep-cObTEv_F_kN6g_Ic85BxD9";
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const VAPID_PUBLIC_KEY = process.env.UNGANI_VAPID_PUBLIC_KEY;
const VAPID_PRIVATE_KEY = process.env.UNGANI_VAPID_PRIVATE_KEY;
const VAPID_SUBJECT = process.env.UNGANI_VAPID_SUBJECT;

const SUBSCRIPTIONS_TABLE = "ungani_push_subscriptions";
const SENT_LOG_TABLE = "ungani_push_sent_log";

// Anonymous registrants can trigger the new_registration branch below -
// this window caps how long after a registration's real created_at that
// trigger remains usable, so a leaked/guessed registration id can't be
// replayed indefinitely to resurrect an old, already-handled signup.
// Combined with the sent-log dedup below (which blocks it from firing
// more than once ever, for any single registration), this makes the
// anonymous-safe path replay-resistant without needing to authenticate
// the caller at all.
const REGISTRATION_RECENCY_WINDOW_MS = 30 * 60 * 1000;

function json(res, status, body) {
  res.status(status).json(body);
}

async function alreadySent(supabaseAdmin, eventType, relatedId, recipientScope) {
  const { data } = await supabaseAdmin
    .from(SENT_LOG_TABLE)
    .select("id")
    .eq("event_type", eventType)
    .eq("related_id", relatedId)
    .eq("recipient_scope", recipientScope)
    .maybeSingle();

  return Boolean(data);
}

async function markSent(supabaseAdmin, eventType, relatedId, recipientScope) {
  await supabaseAdmin.from(SENT_LOG_TABLE).insert({
    event_type: eventType,
    related_id: relatedId,
    recipient_scope: recipientScope
  });
}

async function sendToSubscriptions(supabaseAdmin, subscriptions, payload) {
  const results = [];

  for (const sub of subscriptions) {
    try {
      await webpush.sendNotification(
        { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth_key } },
        payload
      );

      results.push({ id: sub.id, ok: true });
    } catch (sendError) {
      const statusCode = sendError.statusCode;

      if (statusCode === 404 || statusCode === 410) {
        await supabaseAdmin.from(SUBSCRIPTIONS_TABLE).delete().eq("id", sub.id);
        results.push({ id: sub.id, ok: false, message: "Subscription expired - removed.", pruned: true });
      } else {
        results.push({ id: sub.id, ok: false, message: sendError.message });
      }
    }
  }

  return results;
}

function getBearerToken(req) {
  const authHeader = req.headers["authorization"] || "";
  return authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : null;
}

// Mirrors the exact pattern already proven in api/send-email-queue.js's
// getRequestingTenantId - a user-scoped client (their own JWT, not
// service role) so get_my_ungani_staff_access() evaluates auth.uid()
// correctly, then reads the resolved tenant_id back out of its result.
async function resolveCallerTenantId(bearerToken) {
  if (!bearerToken) return null;

  try {
    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: "Bearer " + bearerToken } },
      auth: { persistSession: false, autoRefreshToken: false }
    });

    const { data, error } = await userClient.rpc("get_my_ungani_staff_access");

    if (error || !data || data.can_access !== true) return null;

    return data.tenant_id || null;
  } catch {
    return null;
  }
}

async function resolveCallerIsAdmin(bearerToken) {
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

// Anonymous-safe by design: the registrant who just submitted the form
// isn't authenticated, so this branch takes no bearer token at all. It
// never trusts anything from the caller except the registration id - all
// notification content is re-derived server-side from the real
// registrations row, and only ever sent to admin-type subscriptions.
async function handleNewRegistration(supabaseAdmin, registrationId, res) {
  const { data: registration } = await supabaseAdmin
    .from("registrations")
    .select("id, business_name, business_type, created_at")
    .eq("id", registrationId)
    .maybeSingle();

  if (!registration) {
    return json(res, 200, { ok: true, sent: 0, message: "Registration not found." });
  }

  const ageMs = Date.now() - new Date(registration.created_at).getTime();

  if (ageMs > REGISTRATION_RECENCY_WINDOW_MS) {
    return json(res, 200, { ok: true, sent: 0, message: "Registration too old for a push trigger." });
  }

  const recipientScope = "admin";

  if (await alreadySent(supabaseAdmin, "new_registration", registrationId, recipientScope)) {
    return json(res, 200, { ok: true, sent: 0, message: "Already notified." });
  }

  const { data: subscriptions } = await supabaseAdmin
    .from(SUBSCRIPTIONS_TABLE)
    .select("id, endpoint, p256dh, auth_key")
    .eq("user_type", "admin");

  if (!subscriptions || subscriptions.length === 0) {
    await markSent(supabaseAdmin, "new_registration", registrationId, recipientScope);
    return json(res, 200, { ok: true, sent: 0, message: "No admin push subscriptions yet." });
  }

  const payload = JSON.stringify({
    title: "New business registration",
    body: (registration.business_name || "A business") +
      " (" + (registration.business_type || "unknown type") + ") just registered - review in Admin.",
    url: "/admin.html",
    tag: "new-registration"
  });

  const results = await sendToSubscriptions(supabaseAdmin, subscriptions, payload);
  await markSent(supabaseAdmin, "new_registration", registrationId, recipientScope);

  return json(res, 200, { ok: true, sent: results.filter((r) => r.ok).length, results });
}

// Authenticated (any tenant member). Never trusts a client-supplied
// recipient - the real assignee is independently re-resolved here from
// the task row itself, the same two lookups (owner via registrations /
// team member via ungani_team_members) notify_ungani_task_assignment's
// real SQL source already does, so there's nothing for a caller to spoof.
async function handleTaskAssignment(req, supabaseAdmin, taskId, res) {
  const callerTenantId = await resolveCallerTenantId(getBearerToken(req));

  if (!callerTenantId) {
    return json(res, 401, { ok: false, message: "Not authenticated or no active tenant access." });
  }

  const { data: task } = await supabaseAdmin
    .from("tasks")
    .select("id, tenant_id, task_title, due_date, assigned_to_team_member_id, assigned_to_is_owner")
    .eq("id", taskId)
    .maybeSingle();

  if (!task) {
    return json(res, 200, { ok: true, sent: 0, message: "Task not found." });
  }

  if (task.tenant_id !== callerTenantId) {
    return json(res, 403, { ok: false, message: "Task does not belong to your account." });
  }

  let assigneeUserId = null;

  if (task.assigned_to_is_owner) {
    const { data: reg } = await supabaseAdmin
      .from("registrations")
      .select("auth_user_id")
      .eq("tenant_id", task.tenant_id)
      .in("status", ["approved", "active", "trial"])
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    assigneeUserId = reg?.auth_user_id || null;
  } else if (task.assigned_to_team_member_id) {
    const { data: tm } = await supabaseAdmin
      .from("ungani_team_members")
      .select("auth_user_id")
      .eq("id", task.assigned_to_team_member_id)
      .eq("tenant_id", task.tenant_id)
      .maybeSingle();

    assigneeUserId = tm?.auth_user_id || null;
  }

  if (!assigneeUserId) {
    return json(res, 200, { ok: true, sent: 0, message: "No resolvable assignee for this task." });
  }

  const recipientScope = assigneeUserId;

  if (await alreadySent(supabaseAdmin, "task_assignment", taskId, recipientScope)) {
    return json(res, 200, { ok: true, sent: 0, message: "Already notified." });
  }

  const { data: subscriptions } = await supabaseAdmin
    .from(SUBSCRIPTIONS_TABLE)
    .select("id, endpoint, p256dh, auth_key")
    .eq("auth_user_id", assigneeUserId);

  if (!subscriptions || subscriptions.length === 0) {
    await markSent(supabaseAdmin, "task_assignment", taskId, recipientScope);
    return json(res, 200, { ok: true, sent: 0, message: "Assignee has no push subscriptions." });
  }

  const payload = JSON.stringify({
    title: "New task assigned",
    body: "You've been assigned: " + (task.task_title || "a task") +
      (task.due_date ? " (due " + task.due_date + ")" : ""),
    url: "/my-tasks.html?highlight=" + task.id,
    tag: "task-" + task.id
  });

  const results = await sendToSubscriptions(supabaseAdmin, subscriptions, payload);
  await markSent(supabaseAdmin, "task_assignment", taskId, recipientScope);

  return json(res, 200, { ok: true, sent: results.filter((r) => r.ok).length, results });
}

// Admin-gated (mirrors queue_ungani_support_response_email's own
// is_ungani_admin() check). Recipient is every client-type push
// subscription on the ticket's tenant, not a single person - matches
// how the tenant-scoped email instant-send already treats "the tenant"
// as the addressable unit for this kind of update.
async function handleSupportResponse(req, supabaseAdmin, issueId, res) {
  const isAdmin = await resolveCallerIsAdmin(getBearerToken(req));

  if (!isAdmin) {
    return json(res, 401, { ok: false, message: "Only UNGANI admin can trigger this." });
  }

  const { data: issue } = await supabaseAdmin
    .from("support_issues")
    .select("id, tenant_id, issue_title, admin_response")
    .eq("id", issueId)
    .maybeSingle();

  if (!issue) {
    return json(res, 200, { ok: true, sent: 0, message: "Support issue not found." });
  }

  const cleanResponse = (issue.admin_response || "").trim();
  const recipientScope = "tenant:" + issue.tenant_id + ":" + cleanResponse.slice(0, 500);

  if (await alreadySent(supabaseAdmin, "support_response", issueId, recipientScope)) {
    return json(res, 200, { ok: true, sent: 0, message: "Already notified for this response." });
  }

  const { data: subscriptions } = await supabaseAdmin
    .from(SUBSCRIPTIONS_TABLE)
    .select("id, endpoint, p256dh, auth_key")
    .eq("tenant_id", issue.tenant_id)
    .eq("user_type", "client");

  if (!subscriptions || subscriptions.length === 0) {
    await markSent(supabaseAdmin, "support_response", issueId, recipientScope);
    return json(res, 200, { ok: true, sent: 0, message: "No client push subscriptions for this tenant." });
  }

  const payload = JSON.stringify({
    title: "UNGANI Support replied",
    body: "New reply on your ticket" + (issue.issue_title ? ' "' + issue.issue_title + '"' : "") + ".",
    url: "/my-support.html",
    tag: "support-" + issue.id
  });

  const results = await sendToSubscriptions(supabaseAdmin, subscriptions, payload);
  await markSent(supabaseAdmin, "support_response", issueId, recipientScope);

  return json(res, 200, { ok: true, sent: results.filter((r) => r.ok).length, results });
}

// Authenticated (any tenant member), tenant-verified. team_chat_messages
// is DM-style (recipient_is_owner OR recipient_team_member_id, set by the
// sender's active conversation) - same shape as tasks' assignee columns,
// so this reuses the exact same two-lookup resolution as
// handleTaskAssignment above, independently re-deriving the real
// recipient rather than trusting one from the caller. relatedId is a
// client-generated uuid (team-chat-shared.js sets it on insert, same
// "generate id up front, no .select() RETURNING" pattern already used
// for registrations) - dedup is a clean (event_type, related_id) pair
// since every send genuinely has its own id, no content-hash needed.
async function handleTeamChatMessage(req, supabaseAdmin, messageId, res) {
  const callerTenantId = await resolveCallerTenantId(getBearerToken(req));

  if (!callerTenantId) {
    return json(res, 401, { ok: false, message: "Not authenticated or no active tenant access." });
  }

  const { data: message } = await supabaseAdmin
    .from("team_chat_messages")
    .select("id, tenant_id, sender_user_id, sender_name, message_body, recipient_is_owner, recipient_team_member_id")
    .eq("id", messageId)
    .maybeSingle();

  if (!message) {
    return json(res, 200, { ok: true, sent: 0, message: "Message not found." });
  }

  if (message.tenant_id !== callerTenantId) {
    return json(res, 403, { ok: false, message: "Message does not belong to your account." });
  }

  let recipientUserId = null;

  if (message.recipient_is_owner) {
    const { data: reg } = await supabaseAdmin
      .from("registrations")
      .select("auth_user_id")
      .eq("tenant_id", message.tenant_id)
      .in("status", ["approved", "active", "trial"])
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    recipientUserId = reg?.auth_user_id || null;
  } else if (message.recipient_team_member_id) {
    const { data: tm } = await supabaseAdmin
      .from("ungani_team_members")
      .select("auth_user_id")
      .eq("id", message.recipient_team_member_id)
      .eq("tenant_id", message.tenant_id)
      .maybeSingle();

    recipientUserId = tm?.auth_user_id || null;
  }

  if (!recipientUserId || recipientUserId === message.sender_user_id) {
    return json(res, 200, { ok: true, sent: 0, message: "No resolvable recipient for this message." });
  }

  if (await alreadySent(supabaseAdmin, "team_chat_message", messageId, "broadcast")) {
    return json(res, 200, { ok: true, sent: 0, message: "Already notified." });
  }

  const { data: subscriptions } = await supabaseAdmin
    .from(SUBSCRIPTIONS_TABLE)
    .select("id, endpoint, p256dh, auth_key")
    .eq("auth_user_id", recipientUserId);

  if (!subscriptions || subscriptions.length === 0) {
    await markSent(supabaseAdmin, "team_chat_message", messageId, "broadcast");
    return json(res, 200, { ok: true, sent: 0, message: "Recipient has no push subscriptions." });
  }

  const bodyText = String(message.message_body || "").slice(0, 140);

  const payload = JSON.stringify({
    title: "New message from " + (message.sender_name || "a team member"),
    body: bodyText,
    url: "/client.html",
    tag: "team-chat-" + message.id
  });

  const results = await sendToSubscriptions(supabaseAdmin, subscriptions, payload);
  await markSent(supabaseAdmin, "team_chat_message", messageId, "broadcast");

  return json(res, 200, { ok: true, sent: results.filter((r) => r.ok).length, results });
}

// Admin-gated, same shape as handleSupportResponse - broadcasts to every
// client-type subscription on the message's tenant. relatedId is a
// client-generated uuid (admin.html/admin-home.html's sendChatThreadReply()
// sets it on insert), so dedup is a clean (event_type, related_id) pair.
async function handleAdminClientMessage(req, supabaseAdmin, messageId, res) {
  const isAdmin = await resolveCallerIsAdmin(getBearerToken(req));

  if (!isAdmin) {
    return json(res, 401, { ok: false, message: "Only UNGANI admin can trigger this." });
  }

  const { data: message } = await supabaseAdmin
    .from("admin_client_messages")
    .select("id, tenant_id, sender_name, message_body")
    .eq("id", messageId)
    .maybeSingle();

  if (!message) {
    return json(res, 200, { ok: true, sent: 0, message: "Message not found." });
  }

  if (await alreadySent(supabaseAdmin, "admin_client_message", messageId, "broadcast")) {
    return json(res, 200, { ok: true, sent: 0, message: "Already notified." });
  }

  const { data: subscriptions } = await supabaseAdmin
    .from(SUBSCRIPTIONS_TABLE)
    .select("id, endpoint, p256dh, auth_key")
    .eq("tenant_id", message.tenant_id)
    .eq("user_type", "client");

  if (!subscriptions || subscriptions.length === 0) {
    await markSent(supabaseAdmin, "admin_client_message", messageId, "broadcast");
    return json(res, 200, { ok: true, sent: 0, message: "No client push subscriptions for this tenant." });
  }

  const bodyText = String(message.message_body || "").slice(0, 140);

  const payload = JSON.stringify({
    title: "New message from UNGANI",
    body: bodyText,
    url: "/my-chat.html",
    tag: "admin-chat-" + message.id
  });

  const results = await sendToSubscriptions(supabaseAdmin, subscriptions, payload);
  await markSent(supabaseAdmin, "admin_client_message", messageId, "broadcast");

  return json(res, 200, { ok: true, sent: results.filter((r) => r.ok).length, results });
}

export default async function handler(req, res) {
  try {
    if (req.method !== "POST") {
      return json(res, 405, { ok: false, message: "Method not allowed. Use POST." });
    }

    if (!SUPABASE_SERVICE_ROLE_KEY || !VAPID_PUBLIC_KEY || !VAPID_PRIVATE_KEY || !VAPID_SUBJECT) {
      return json(res, 500, {
        ok: false,
        message: "Server misconfigured: missing Supabase service role or VAPID environment variables."
      });
    }

    const eventType = req.body?.eventType;
    const relatedId = req.body?.relatedId;

    if (!relatedId || typeof relatedId !== "string") {
      return json(res, 400, { ok: false, message: "Missing relatedId." });
    }

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false }
    });

    webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

    if (eventType === "new_registration") {
      return await handleNewRegistration(supabaseAdmin, relatedId, res);
    }

    if (eventType === "task_assignment") {
      return await handleTaskAssignment(req, supabaseAdmin, relatedId, res);
    }

    if (eventType === "support_response") {
      return await handleSupportResponse(req, supabaseAdmin, relatedId, res);
    }

    if (eventType === "team_chat_message") {
      return await handleTeamChatMessage(req, supabaseAdmin, relatedId, res);
    }

    if (eventType === "admin_client_message") {
      return await handleAdminClientMessage(req, supabaseAdmin, relatedId, res);
    }

    return json(res, 400, { ok: false, message: "Unknown eventType." });
  } catch (error) {
    return json(res, 500, { ok: false, message: error.message });
  }
}
