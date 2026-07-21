// =========================================================
// UNGANI OS - subscription-guard.js
// Step SaaS-6B
//
// Purpose:
// Shared client-side account access guard for UNGANI OS.
//
// Rules:
// - active = allowed
// - trial = allowed until trial_end_at
// - suspended = blocked
// - cancelled/canceled = blocked
// - overdue = warning only for now
// - pending = warning only for now
//
// Important:
// - This file does not redesign any page.
// - This file does not touch dashboard cards/buttons/colors.
// - This file does not open admin pages.
// - This file is for client workspace pages only.
// - Admin pages should not load this file.
// =========================================================

(function () {
  const SUPABASE_URL = "https://ctmtjwklltnsmfdtvqhl.supabase.co";
  const SUPABASE_KEY = "sb_publishable_jkZaWWep-cObTEv_F_kN6g_Ic85BxD9";

  const CLIENT_ALLOWED_WITHOUT_BLOCK = [
    "login.html",
    "index.html",
    "my-package.html",
    "my-support.html",
    "client-notifications.html"
  ];

  const ADMIN_PAGE_PREFIXES = [
    "admin",
    "support.html",
    "billing.html",
    "admin-health.html"
  ];

  // accessStatus.redirect_url (from get_my_ungani_access_status) is a
  // free-text database string - not guaranteed to match a real client page
  // filename. safeClientRedirect() below only ever checked it wasn't an
  // admin page, so any other wrong/stale value would pass straight through
  // to window.location.href and 404. Validate against the real client page
  // list too now (same pages client-notifications.html's own
  // normalizeActionUrl() already trusts).
  const SAFE_CLIENT_PAGES = [
    "client.html", "client-notifications.html", "my-money.html", "my-tasks.html",
    "my-records.html", "my-items.html", "my-people.html", "my-documents.html",
    "my-calendar.html", "my-support.html", "my-chat.html", "my-team-chat.html",
    "my-notices.html", "my-charts.html", "reports.html", "my-profile.html",
    "my-package.html", "my-account-status.html"
  ];

  const BLOCKED_REDIRECT_URL = "my-package.html";

  let guardAlreadyRunning = false;

  document.addEventListener("DOMContentLoaded", function () {
    runUnganiSubscriptionGuard();
  });

  async function runUnganiSubscriptionGuard() {
    if (guardAlreadyRunning) return;
    guardAlreadyRunning = true;

    const pageName = getCurrentPageName();

    if (isAdminPage(pageName)) {
      return;
    }

    if (CLIENT_ALLOWED_WITHOUT_BLOCK.includes(pageName)) {
      await showWarningOnlyIfNeeded();
      return;
    }

    try {
      const supabaseClient = getSupabaseClient();

      if (!supabaseClient) {
        showGuardBanner(
          "warning",
          "Unable to check your account status right now. Please refresh or contact UNGANI support if this continues."
        );
        return;
      }

      const { data, error } = await supabaseClient.rpc("get_my_ungani_access_status");

      if (error) {
        showGuardBanner(
          "warning",
          "Unable to confirm your account access right now. Please refresh or contact UNGANI support if this continues."
        );
        return;
      }

      const accessStatus = extractFirstRow(data);

      if (!accessStatus) {
        showGuardBanner(
          "warning",
          "Your account status could not be confirmed. Please contact UNGANI support if this continues."
        );
        return;
      }

      handleAccessStatus(accessStatus, pageName);
    } catch (error) {
      showGuardBanner(
        "warning",
        "Unable to verify your account status right now. Please refresh or contact UNGANI support if this continues."
      );
    }
  }

  async function showWarningOnlyIfNeeded() {
    try {
      const supabaseClient = getSupabaseClient();

      if (!supabaseClient) {
        return;
      }

      const { data, error } = await supabaseClient.rpc("get_my_ungani_access_status");

      if (error) {
        return;
      }

      const accessStatus = extractFirstRow(data);

      if (!accessStatus) {
        return;
      }

      const accessLevel = normalize(accessStatus.access_level);
      const accessAllowed = accessStatus.access_allowed === true;
      const message = accessStatus.access_message || "";

      if (accessAllowed && accessLevel === "warning" && message) {
        showGuardBanner("warning", message);
      }

      if (!accessAllowed && message) {
        showGuardBanner("blocked", message);
      }
    } catch (error) {
      return;
    }
  }

  function handleAccessStatus(accessStatus, pageName) {
    const accessAllowed = accessStatus.access_allowed === true;
    const accessLevel = normalize(accessStatus.access_level);
    const message = accessStatus.access_message || "";
    const redirectUrl = accessStatus.redirect_url || BLOCKED_REDIRECT_URL;

    if (!accessAllowed) {
      saveBlockedMessage(message);

      if (pageName !== "my-package.html") {
        window.location.href = safeClientRedirect(redirectUrl);
        return;
      }

      showGuardBanner("blocked", message);
      return;
    }

    if (accessLevel === "warning" && message) {
      showGuardBanner("warning", message);
    }
  }

  function getSupabaseClient() {
    if (window.unganiSubscriptionGuardClient) {
      return window.unganiSubscriptionGuardClient;
    }

    if (typeof window.supabase === "undefined" || !window.supabase.createClient) {
      return null;
    }

    window.unganiSubscriptionGuardClient = window.supabase.createClient(
      SUPABASE_URL,
      SUPABASE_KEY
    );

    return window.unganiSubscriptionGuardClient;
  }

  function extractFirstRow(data) {
    if (!data) return null;

    if (Array.isArray(data)) {
      return data.length ? data[0] : null;
    }

    return data;
  }

  function getCurrentPageName() {
    const path = window.location.pathname || "";
    const clean = path.split("/").filter(Boolean).pop() || "index.html";

    if (!clean.includes(".")) {
      return clean + ".html";
    }

    return clean;
  }

  function isAdminPage(pageName) {
    const clean = normalize(pageName);

    if (clean.startsWith("admin")) {
      return true;
    }

    return ADMIN_PAGE_PREFIXES.some(function (prefix) {
      return clean === normalize(prefix) || clean.startsWith(normalize(prefix));
    });
  }

  function safeClientRedirect(redirectUrl) {
    const clean = String(redirectUrl || BLOCKED_REDIRECT_URL).trim();

    if (!clean) {
      return BLOCKED_REDIRECT_URL;
    }

    const lower = clean.toLowerCase();

    if (lower.startsWith("admin")) {
      return BLOCKED_REDIRECT_URL;
    }

    if (lower.includes("admin-home.html")) {
      return BLOCKED_REDIRECT_URL;
    }

    if (lower.includes("admin.html")) {
      return BLOCKED_REDIRECT_URL;
    }

    const base = clean.split("?")[0].split("#")[0];
    if (!SAFE_CLIENT_PAGES.includes(base)) {
      return BLOCKED_REDIRECT_URL;
    }

    return clean;
  }

  function saveBlockedMessage(message) {
    try {
      localStorage.setItem(
        "ungani_account_access_message",
        message || "Your account access needs attention. Please contact UNGANI support."
      );
    } catch (error) {
      return;
    }
  }

  function showGuardBanner(type, message) {
    if (!message) return;

    removeExistingGuardBanner();

    const banner = document.createElement("div");
    banner.id = "unganiSubscriptionGuardBanner";

    const isBlocked = type === "blocked";

    banner.style.position = "fixed";
    banner.style.left = "16px";
    banner.style.right = "16px";
    banner.style.bottom = "16px";
    banner.style.zIndex = "99999";
    banner.style.background = isBlocked ? "#7F1D1D" : "#FFFBEB";
    banner.style.color = isBlocked ? "#FFFFFF" : "#061C3D";
    banner.style.border = isBlocked ? "1px solid #FECACA" : "1px solid #FDE68A";
    banner.style.borderRadius = "16px";
    banner.style.padding = "14px 16px";
    banner.style.boxShadow = "0 14px 35px rgba(6, 28, 61, 0.18)";
    banner.style.fontFamily = "Arial, Helvetica, sans-serif";
    banner.style.fontSize = "14px";
    banner.style.lineHeight = "1.5";
    banner.style.display = "flex";
    banner.style.alignItems = "center";
    banner.style.justifyContent = "space-between";
    banner.style.gap = "12px";
    banner.style.maxWidth = "980px";
    banner.style.margin = "0 auto";

    const text = document.createElement("div");
    text.style.fontWeight = "700";
    text.textContent = message;

    const actions = document.createElement("div");
    actions.style.display = "flex";
    actions.style.alignItems = "center";
    actions.style.gap = "8px";
    actions.style.flexWrap = "wrap";
    actions.style.justifyContent = "flex-end";

    const packageLink = document.createElement("a");
    packageLink.href = "my-package.html";
    packageLink.textContent = "View Package";
    packageLink.style.textDecoration = "none";
    packageLink.style.borderRadius = "999px";
    packageLink.style.padding = "9px 12px";
    packageLink.style.fontWeight = "900";
    packageLink.style.fontSize = "12px";
    packageLink.style.background = "#D4A63A";
    packageLink.style.color = "#061C3D";
    packageLink.style.whiteSpace = "nowrap";

    const supportLink = document.createElement("a");
    supportLink.href = "my-support.html";
    supportLink.textContent = "Contact Support";
    supportLink.style.textDecoration = "none";
    supportLink.style.borderRadius = "999px";
    supportLink.style.padding = "9px 12px";
    supportLink.style.fontWeight = "900";
    supportLink.style.fontSize = "12px";
    supportLink.style.background = isBlocked ? "#FFFFFF" : "#061C3D";
    supportLink.style.color = isBlocked ? "#061C3D" : "#FFFFFF";
    supportLink.style.whiteSpace = "nowrap";

    const closeButton = document.createElement("button");
    closeButton.type = "button";
    closeButton.textContent = "Close";
    closeButton.style.border = "none";
    closeButton.style.borderRadius = "999px";
    closeButton.style.padding = "9px 12px";
    closeButton.style.fontWeight = "900";
    closeButton.style.fontSize = "12px";
    closeButton.style.cursor = "pointer";
    closeButton.style.background = "rgba(255,255,255,0.18)";
    closeButton.style.color = isBlocked ? "#FFFFFF" : "#061C3D";
    closeButton.style.whiteSpace = "nowrap";

    closeButton.addEventListener("click", function () {
      removeExistingGuardBanner();
    });

    actions.appendChild(packageLink);
    actions.appendChild(supportLink);

    if (!isBlocked) {
      actions.appendChild(closeButton);
    }

    banner.appendChild(text);
    banner.appendChild(actions);

    document.body.appendChild(banner);
  }

  function removeExistingGuardBanner() {
    const existing = document.getElementById("unganiSubscriptionGuardBanner");

    if (existing && existing.parentNode) {
      existing.parentNode.removeChild(existing);
    }
  }

  function normalize(value) {
    return String(value || "").trim().toLowerCase();
  }
})();
