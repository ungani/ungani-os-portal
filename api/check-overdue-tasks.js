import webpush from "web-push";
import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = process.env.SUPABASE_URL || "https://ctmtjwklltnsmfdtvqhl.supabase.co";
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const SUPABASE_ANON_KEY = "sb_publishable_jkZaWWep-cObTEv_F_kN6g_Ic85BxD9";
const CRON_SECRET = process.env.CRON_SECRET;

const VAPID_PUBLIC_KEY = process.env.UNGANI_VAPID_PUBLIC_KEY;
const VAPID_PRIVATE_KEY = process.env.UNGANI_VAPID_PRIVATE_KEY;
const VAPID_SUBJECT = process.env.UNGANI_VAPID_SUBJECT;

const SUBSCRIPTIONS_TABLE = "ungani_push_subscriptions";
const SENT_LOG_TABLE = "ungani_push_sent_log";

// Once-daily cron (Vercel Hobby-plan limit, same constraint as the other
// crons in this app) - NOT real-time. A task that goes overdue at 9am
// won't push until the next scheduled run. The permanent dedup log below
// means each task only ever triggers this push once, ever, the first
// time a run notices it overdue - not a daily nag for the same task.

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

function todayISO() {
  return new Date().toISOString().slice(0, 10);
}

// Mirrors client.html's findOverdueTasksForSection() status check exactly
// (due date strictly before today, status text doesn't contain
// "completed"/"cancelled") - same semantics, just re-run here server-side
// against every tenant instead of one tenant's already-loaded dashboard data.
function isOverdueAndOpen(task, todayStr) {
  const due = String(task.due_date || "").slice(0, 10);
  if (!due || due >= todayStr) return false;

  const status = String(task.status || "").toLowerCase();
  return !status.includes("completed") && !status.includes("cancelled");
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
        results.push({ id: sub.id, ok: false, pruned: true });
      } else {
        results.push({ id: sub.id, ok: false, message: sendError.message });
      }
    }
  }

  return results;
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
      return json(res, 401, { ok: false, message: "Unauthorized overdue-task check request." });
    }

    if (!SUPABASE_SERVICE_ROLE_KEY || !VAPID_PUBLIC_KEY || !VAPID_PRIVATE_KEY || !VAPID_SUBJECT) {
      return json(res, 500, {
        ok: false,
        message: "Server misconfigured: missing Supabase service role or VAPID environment variables."
      });
    }

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false }
    });

    webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

    const todayStr = todayISO();

    // Scalability fix: this used to be an unordered .limit(1000), so which
    // 1000 rows got processed (and which got silently dropped past the cap)
    // was arbitrary. Ordering oldest-due-first makes the cap deterministic -
    // the most overdue tasks are always processed first, and anything
    // pushed past the cap is picked up on tomorrow's run instead of being
    // permanently skipped.
    const { data: candidateTasks, error: tasksError } = await supabaseAdmin
      .from("tasks")
      .select("id, tenant_id, task_title, due_date, status, assigned_to_team_member_id, assigned_to_is_owner")
      .lt("due_date", todayStr)
      .not("due_date", "is", null)
      .order("due_date", { ascending: true })
      .limit(1000);

    if (tasksError) {
      return json(res, 500, { ok: false, message: tasksError.message });
    }

    const overdueTasks = (candidateTasks || []).filter((task) => isOverdueAndOpen(task, todayStr));
    const eligibleTasks = overdueTasks.filter((task) => task.assigned_to_is_owner || task.assigned_to_team_member_id);

    // Scalability fix: this whole block used to do up to 4 sequential DB
    // round-trips PER overdue task (owner lookup or team-member lookup,
    // alreadySent check, subscriptions fetch, markSent insert) - at
    // thousands of tenants with hundreds of overdue tasks, that's
    // thousands of awaited queries in one serverless invocation, risking a
    // function timeout that silently leaves the remainder unprocessed
    // until tomorrow. Replaced with a handful of bulk queries keyed by the
    // distinct tenant/team-member/task/user ids actually involved.

    const ownerTenantIds = [...new Set(eligibleTasks.filter((t) => t.assigned_to_is_owner).map((t) => t.tenant_id))];
    const teamMemberIds = [...new Set(eligibleTasks.filter((t) => !t.assigned_to_is_owner && t.assigned_to_team_member_id).map((t) => t.assigned_to_team_member_id))];

    const ownerAuthByTenant = {};
    if (ownerTenantIds.length > 0) {
      const { data: ownerRegs } = await supabaseAdmin
        .from("registrations")
        .select("tenant_id, auth_user_id, created_at")
        .in("tenant_id", ownerTenantIds)
        .in("status", ["approved", "active", "trial"])
        .order("created_at", { ascending: false });

      for (const reg of ownerRegs || []) {
        if (!ownerAuthByTenant[reg.tenant_id] && reg.auth_user_id) {
          ownerAuthByTenant[reg.tenant_id] = reg.auth_user_id;
        }
      }
    }

    const teamMembersById = {};
    if (teamMemberIds.length > 0) {
      const { data: teamMembers } = await supabaseAdmin
        .from("ungani_team_members")
        .select("id, tenant_id, auth_user_id")
        .in("id", teamMemberIds);

      for (const tm of teamMembers || []) teamMembersById[tm.id] = tm;
    }

    const resolvedTasks = [];
    for (const task of eligibleTasks) {
      let assigneeUserId = null;

      if (task.assigned_to_is_owner) {
        assigneeUserId = ownerAuthByTenant[task.tenant_id] || null;
      } else if (task.assigned_to_team_member_id) {
        const tm = teamMembersById[task.assigned_to_team_member_id];
        assigneeUserId = (tm && tm.tenant_id === task.tenant_id) ? tm.auth_user_id : null;
      }

      if (assigneeUserId) resolvedTasks.push({ task, assigneeUserId });
    }

    let alreadySentSet = new Set();
    if (resolvedTasks.length > 0) {
      const taskIds = [...new Set(resolvedTasks.map((r) => r.task.id))];
      const { data: sentRows } = await supabaseAdmin
        .from(SENT_LOG_TABLE)
        .select("related_id, recipient_scope")
        .eq("event_type", "task_overdue")
        .in("related_id", taskIds);

      alreadySentSet = new Set((sentRows || []).map((r) => r.related_id + "::" + r.recipient_scope));
    }

    const toNotify = resolvedTasks.filter((r) => !alreadySentSet.has(r.task.id + "::" + r.assigneeUserId));

    const subsByUser = {};
    const assigneeIds = [...new Set(toNotify.map((r) => r.assigneeUserId))];
    if (assigneeIds.length > 0) {
      const { data: allSubs } = await supabaseAdmin
        .from(SUBSCRIPTIONS_TABLE)
        .select("id, endpoint, p256dh, auth_key, auth_user_id")
        .in("auth_user_id", assigneeIds);

      for (const sub of allSubs || []) {
        (subsByUser[sub.auth_user_id] = subsByUser[sub.auth_user_id] || []).push(sub);
      }
    }

    const results = [];
    const sentLogInserts = [];

    for (const { task, assigneeUserId } of toNotify) {
      const subscriptions = subsByUser[assigneeUserId] || [];

      if (subscriptions.length === 0) {
        sentLogInserts.push({ event_type: "task_overdue", related_id: task.id, recipient_scope: assigneeUserId });
        continue;
      }

      const payload = JSON.stringify({
        title: "Task overdue",
        body: (task.task_title || "A task") + " was due " + task.due_date + " and hasn't been completed.",
        url: "/my-tasks.html?highlight=" + task.id,
        tag: "overdue-" + task.id
      });

      const sendResults = await sendToSubscriptions(supabaseAdmin, subscriptions, payload);
      sentLogInserts.push({ event_type: "task_overdue", related_id: task.id, recipient_scope: assigneeUserId });

      results.push({ taskId: task.id, sent: sendResults.filter((r) => r.ok).length });
    }

    if (sentLogInserts.length > 0) {
      await supabaseAdmin.from(SENT_LOG_TABLE).insert(sentLogInserts);
    }

    return json(res, 200, {
      ok: true,
      via,
      candidatesChecked: overdueTasks.length,
      pushed: results.length,
      results
    });
  } catch (error) {
    return json(res, 500, { ok: false, message: error.message });
  }
}
