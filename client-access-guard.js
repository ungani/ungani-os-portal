(function () {
  const SUPABASE_URL = "https://ctmtjwklltnsmfdtvqhl.supabase.co";
  const SUPABASE_KEY = "sb_publishable_jkZaWWep-cObTEv_F_kN6g_Ic85BxD9";

  let supabaseClient = null;
  let guardStarted = false;

  const PUBLIC_PAGES = [
    "index.html",
    "login.html",
    "register.html",
    "signup.html",
    "forgot-password.html",
    "reset-password.html"
  ];

  const CLIENT_STATUS_ALLOWED_PAGES = [
    "my-account-status.html",
    "my-package.html",
    "my-billing.html",
    "my-invoice.html",
    "client-notifications.html"
  ];

  document.addEventListener("DOMContentLoaded", function () {
    initUnganiClientAccessGuard();
  });

  async function initUnganiClientAccessGuard() {
    if (guardStarted) return;

    guardStarted = true;

    const pageName = getCurrentPageName();

    if (shouldSkipGuard(pageName)) {
      return;
    }

    if (!window.supabase) {
      console.warn("UNGANI access guard: Supabase library not found.");
      return;
    }

    supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

    await protectClientPage(pageName);
  }

  async function protectClientPage(pageName) {
    try {
      const sessionResponse = await supabaseClient.auth.getSession();
      const session =
        sessionResponse &&
        sessionResponse.data &&
        sessionResponse.data.session
          ? sessionResponse.data.session
          : null;

      if (!session || !session.user) {
        redirectToLogin();
        return;
      }

      const user = session.user;

      if (!isEmailConfirmed(user)) {
        showAccessBlockedScreen({
          title: "Email Verification Required",
          message:
            "Please verify your email address before using your UNGANI OS workspace.",
          detail:
            "Check your email inbox for the verification link. If you cannot find it, check spam or request a new verification email from the login page.",
          actionText: "Back to Login",
          actionUrl: "login.html"
        });

        return;
      }

      const approvalResponse = await supabaseClient.rpc("get_my_ungani_approval_status");

      if (approvalResponse.error) {
        console.warn("UNGANI approval check failed:", approvalResponse.error);

        showAccessBlockedScreen({
          title: "Approval Check Failed",
          message:
            "UNGANI OS could not confirm your registration approval status.",
          detail:
            "Please refresh the page. If this continues, contact UNGANI support.",
          actionText: "Back to Login",
          actionUrl: "login.html"
        });

        return;
      }

      const approval = normalizeApprovalResponse(approvalResponse.data);

      if (approval.approval_allowed !== true) {
        if (CLIENT_STATUS_ALLOWED_PAGES.includes(pageName)) {
          showAccessWarningBanner({
            title: "Approval Notice",
            message:
              approval.message ||
              "Your account is not fully approved yet. Some workspace features may be restricted."
          });

          return;
        }

        showAccessBlockedScreen({
          title: "Approval Required",
          message:
            "Your UNGANI OS workspace is not open yet because your account is still waiting for approval.",
          detail:
            approval.message ||
            "Please wait for UNGANI admin approval before using the workspace.",
          actionText: "Back to Login",
          actionUrl: "login.html"
        });

        return;
      }

      const accessResponse = await supabaseClient.rpc("get_my_ungani_access_status");

      if (accessResponse.error) {
        console.warn("UNGANI access guard RPC failed:", accessResponse.error);

        showAccessBlockedScreen({
          title: "Access Check Failed",
          message:
            "UNGANI OS could not confirm your account access at this moment.",
          detail:
            "Please refresh the page. If this continues, contact UNGANI support.",
          actionText: "Go to Account Status",
          actionUrl: "my-account-status.html"
        });

        return;
      }

      const access = normalizeAccessResponse(accessResponse.data);
      const allowed = access.allowed === true || access.can_access === true;

      if (allowed) {
        return;
      }

      if (CLIENT_STATUS_ALLOWED_PAGES.includes(pageName)) {
        showAccessWarningBanner({
          title: "Account Notice",
          message:
            "Your account status may restrict some workspace features. You can still view account, package, billing, and notifications."
        });

        return;
      }

      const statusText =
        access.subscription_status ||
        access.account_status ||
        access.payment_status ||
        "restricted";

      const reason =
        access.reason ||
        access.message ||
        "Your account access is currently restricted.";

      showAccessBlockedScreen({
        title: "Workspace Access Restricted",
        message:
          "Your UNGANI OS workspace cannot be opened because the account status is currently restricted.",
        detail:
          "Status: " + titleCase(statusText) + ". " + reason,
        actionText: "View Account Status",
        actionUrl: "my-account-status.html"
      });
    } catch (error) {
      console.warn("UNGANI access guard failed:", error);

      showAccessBlockedScreen({
        title: "Security Check Error",
        message:
          "UNGANI OS could not complete the account security check.",
        detail:
          "Please refresh the page. If this continues, contact UNGANI support.",
        actionText: "Back to Login",
        actionUrl: "login.html"
      });
    }
  }

  function shouldSkipGuard(pageName) {
    if (PUBLIC_PAGES.includes(pageName)) {
      return true;
    }

    if (pageName.startsWith("admin")) {
      return true;
    }

    if (
      pageName === "support.html" ||
      pageName === "billing.html" ||
      pageName === "admin-notifications.html"
    ) {
      return true;
    }

    if (
      pageName.startsWith("my-") ||
      pageName.startsWith("client") ||
      pageName === "client.html" ||
      pageName === "client-notifications.html"
    ) {
      return false;
    }

    return true;
  }

  function isEmailConfirmed(user) {
    if (!user) return false;

    if (user.email_confirmed_at) return true;
    if (user.confirmed_at) return true;

    if (
      user.user_metadata &&
      user.user_metadata.email_verified === true
    ) {
      return true;
    }

    return false;
  }

  function normalizeApprovalResponse(data) {
    if (!data) {
      return {
        approval_checked: false,
        approval_allowed: true,
        message:
          "No approval record found. Existing subscription access rules will apply."
      };
    }

    if (Array.isArray(data)) {
      return data[0] || {
        approval_checked: false,
        approval_allowed: true,
        message:
          "No approval record found. Existing subscription access rules will apply."
      };
    }

    return data;
  }

  function normalizeAccessResponse(data) {
    if (!data) {
      return {
        allowed: false,
        reason: "No access status returned."
      };
    }

    if (Array.isArray(data)) {
      return data[0] || {
        allowed: false,
        reason: "No access status returned."
      };
    }

    return data;
  }

  function showAccessWarningBanner(options) {
    if (document.getElementById("unganiAccessWarningBanner")) return;

    const title = options && options.title ? options.title : "Account Notice";
    const message =
      options && options.message
        ? options.message
        : "Some workspace features may be restricted.";

    const banner = document.createElement("div");
    banner.id = "unganiAccessWarningBanner";

    banner.innerHTML = `
      <strong>${escapeHtml(title)}:</strong>
      ${escapeHtml(message)}
    `;

    banner.style.cssText = `
      position: sticky;
      top: 0;
      z-index: 9999;
      background: #FEF3C7;
      color: #92400E;
      border-bottom: 1px solid rgba(146, 64, 14, 0.22);
      padding: 12px 16px;
      font-family: Arial, Helvetica, sans-serif;
      font-size: 14px;
      line-height: 1.5;
      text-align: center;
    `;

    document.body.prepend(banner);
  }

  function showAccessBlockedScreen(options) {
    const title = options.title || "Access Restricted";
    const message = options.message || "Your access is currently restricted.";
    const detail = options.detail || "";
    const actionText = options.actionText || "Back to Login";
    const actionUrl = options.actionUrl || "login.html";

    document.body.innerHTML = `
      <main style="
        min-height: 100vh;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 24px;
        background:
          radial-gradient(circle at top left, rgba(212, 166, 58, 0.14), transparent 32%),
          linear-gradient(135deg, #031227 0%, #061C3D 48%, #092A59 100%);
        font-family: Arial, Helvetica, sans-serif;
        color: #FFFFFF;
      ">
        <section style="
          width: 100%;
          max-width: 620px;
          background: rgba(8, 38, 84, 0.95);
          border: 1px solid rgba(255, 255, 255, 0.14);
          border-radius: 24px;
          box-shadow: 0 18px 45px rgba(0, 0, 0, 0.28);
          padding: 28px;
          text-align: center;
        ">
          <img
            src="ungani-logo.png"
            alt="UNGANI Logo"
            style="
              width: 72px;
              height: 72px;
              object-fit: contain;
              background: #FFFFFF;
              border-radius: 18px;
              padding: 7px;
              margin-bottom: 16px;
            "
          />

          <h1 style="
            margin: 0 0 10px;
            font-size: 26px;
            color: #D4A63A;
          ">
            ${escapeHtml(title)}
          </h1>

          <p style="
            margin: 0 auto 12px;
            color: #F5F5F3;
            line-height: 1.6;
            max-width: 520px;
            font-size: 15px;
          ">
            ${escapeHtml(message)}
          </p>

          <p style="
            margin: 0 auto 20px;
            color: #B8C3D6;
            line-height: 1.6;
            max-width: 520px;
            font-size: 14px;
          ">
            ${escapeHtml(detail)}
          </p>

          <a
            href="${escapeHtml(actionUrl)}"
            style="
              display: inline-flex;
              align-items: center;
              justify-content: center;
              text-decoration: none;
              background: #D4A63A;
              color: #061C3D;
              border-radius: 999px;
              padding: 12px 18px;
              font-weight: 900;
              font-size: 14px;
            "
          >
            ${escapeHtml(actionText)}
          </a>

          <div style="
            margin-top: 20px;
            color: #B8C3D6;
            font-size: 13px;
            line-height: 1.5;
          ">
            UNGANI OS · ungani.com · info@ungani.com
          </div>
        </section>
      </main>
    `;
  }

  function redirectToLogin() {
    const current = window.location.pathname.split("/").pop() || "client.html";
    window.location.href =
      "login.html?redirect=" + encodeURIComponent(current);
  }

  function getCurrentPageName() {
    const path = window.location.pathname || "";
    return (path.split("/").pop() || "index.html").toLowerCase();
  }

  function titleCase(value) {
    if (!value) return "—";

    return String(value)
      .replace(/_/g, " ")
      .replace(/\b\w/g, function (char) {
        return char.toUpperCase();
      });
  }

  function escapeHtml(value) {
    return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  window.initUnganiClientAccessGuard = initUnganiClientAccessGuard;
})();
