import webpush from "web-push";
import { createClient } from "@supabase/supabase-js";

const SUPABASE_URL = process.env.SUPABASE_URL || "https://ctmtjwklltnsmfdtvqhl.supabase.co";
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const VAPID_PUBLIC_KEY = process.env.UNGANI_VAPID_PUBLIC_KEY;
const VAPID_PRIVATE_KEY = process.env.UNGANI_VAPID_PRIVATE_KEY;
const VAPID_SUBJECT = process.env.UNGANI_VAPID_SUBJECT;

const TABLE = "ungani_push_subscriptions";

function json(res, status, body) {
  res.status(status).json(body);
}

// Step 1 scope, deliberately narrow: an authenticated user can only ever
// send a push to THEIR OWN subscriptions - there is no cross-user
// targeting yet. That's intentional for the "send yourself a test push"
// button this endpoint exists for right now. Event-triggered pushes to
// OTHER users (admin gets notified of a new registration, a staff member
// gets notified of a task) are Step 2/3 work, not built here - adding
// that later needs its own auth design per event (mirroring how Phase 1's
// email work split into admin-gated vs tenant-scoped vs a public/anon-
// safe path for the unauthenticated registration case).
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

    const authHeader = req.headers["authorization"] || "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7).trim() : null;

    if (!token) {
      return json(res, 401, { ok: false, message: "Missing bearer token." });
    }

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false }
    });

    const { data: userData, error: userError } = await supabaseAdmin.auth.getUser(token);

    if (userError || !userData?.user) {
      return json(res, 401, { ok: false, message: "Invalid or expired session." });
    }

    const callerId = userData.user.id;

    const { data: subscriptions, error: subsError } = await supabaseAdmin
      .from(TABLE)
      .select("id, endpoint, p256dh, auth_key")
      .eq("auth_user_id", callerId);

    if (subsError) {
      return json(res, 500, { ok: false, message: subsError.message });
    }

    if (!subscriptions || subscriptions.length === 0) {
      return json(res, 200, {
        ok: true,
        message: "No push subscriptions found for this account. Enable notifications first, then try again.",
        sent: 0
      });
    }

    webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

    // Same real unread count the automatic event pushes now carry (see
    // api/send-event-push.js's computeUnreadBadgeCount) - kept in sync so
    // the test-push button also exercises the app-icon badge, not just
    // the notification pop-up.
    let badgeCount = 0;

    try {
      const { count } = await supabaseAdmin
        .from("ungani_notifications")
        .select("id", { count: "exact", head: true })
        .eq("user_id", callerId)
        .neq("status", "read");

      badgeCount = count || 0;
    } catch (badgeError) {
      badgeCount = 0;
    }

    const payload = JSON.stringify({
      title: req.body?.title || "UNGANI OS test push",
      body: req.body?.body || "If you can see this, push notifications are working on this device.",
      url: req.body?.url || "/",
      badgeCount: badgeCount
    });

    const results = [];

    for (const sub of subscriptions) {
      try {
        await webpush.sendNotification(
          {
            endpoint: sub.endpoint,
            keys: { p256dh: sub.p256dh, auth: sub.auth_key }
          },
          payload
        );

        results.push({ id: sub.id, ok: true });
      } catch (sendError) {
        const statusCode = sendError.statusCode;

        // 404/410 mean the browser has invalidated this subscription
        // (uninstalled, permission revoked, endpoint expired) - prune it
        // so future sends don't keep retrying a dead endpoint.
        if (statusCode === 404 || statusCode === 410) {
          await supabaseAdmin.from(TABLE).delete().eq("id", sub.id);
          results.push({ id: sub.id, ok: false, message: "Subscription expired - removed.", pruned: true });
        } else {
          results.push({ id: sub.id, ok: false, message: sendError.message });
        }
      }
    }

    return json(res, 200, {
      ok: true,
      sent: results.filter((r) => r.ok).length,
      results
    });
  } catch (error) {
    return json(res, 500, { ok: false, message: error.message });
  }
}
