(function () {
  const SUPABASE_URL = "https://ctmtjwklltnsmfdtvqhl.supabase.co";
  const SUPABASE_KEY = "sb_publishable_jkZaWWep-cObTEv_F_kN6g_Ic85BxD9";

  const allowedWithoutFullAccess = [
    "login.html",
    "staff-login.html",
    "index.html",
    "my-account-status.html",
    "client-notifications.html"
  ];

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", runClientAccessGuard);
  } else {
    runClientAccessGuard();
  }

  async function runClientAccessGuard() {
    try {
      const page = getCurrentPage();

      if (allowedWithoutFullAccess.includes(page)) return;
      if (!window.supabase) return;

      const supabaseClient = window.getUnganiSupabaseClient ? window.getUnganiSupabaseClient() : window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
      if (!supabaseClient) return;

      const userResponse = await supabaseClient.auth.getUser();
      const user = userResponse && userResponse.data ? userResponse.data.user : null;

      if (!user) {
        window.location.href = "login.html?mode=client";
        return;
      }

      const staffResponse = await supabaseClient.rpc("get_my_ungani_staff_access");

      if (!staffResponse.error && staffResponse.data && staffResponse.data.account_type === "staff") {
        if (staffResponse.data.can_access === true) {
          return;
        }
      }

      const approvalResponse = await supabaseClient.rpc("get_my_ungani_approval_status");

      if (approvalResponse.error) {
        console.warn("Approval check:", approvalResponse.error.message);
        return;
      }

      const approval = approvalResponse.data || {};

      if (approval.account_type === "staff" && approval.can_access === true) {
        return;
      }

      if (approval.can_access !== true) {
        showBlockedPage(
          "Approval Required",
          approval.message || "Your UNGANI OS workspace is not open yet because your account is still waiting for approval.",
          "login.html?mode=client",
          "Back to Login"
        );
        return;
      }

      const accessResponse = await supabaseClient.rpc("get_my_ungani_access_status");

      if (accessResponse.error) {
        console.warn("Access check:", accessResponse.error.message);
        return;
      }

      const access = accessResponse.data || {};
      const status = String(access.access_status || access.status || "").toLowerCase();

      const allowedStatuses = [
        "trial",
        "active",
        "approved",
        "enabled",
        "payment_warning",
        "trial_expired_warning",
        "warning",
        "allowed"
      ];

      const blockedStatuses = [
        "suspended",
        "cancelled",
        "canceled",
        "blocked",
        "restricted",
        "no_tenant"
      ];

      if (access.can_access === true || allowedStatuses.includes(status)) {
        // Reaching this point (rather than returning earlier via one of
        // the two staff-account_type checks above) means this is an owner
        // account - 2FA is scoped to owners only, by explicit decision, so
        // this is the one correct place to check it. Same
        // getAuthenticatorAssuranceLevel() pattern as admin-access-guard.js:
        // nextLevel only ever comes back "aal2" for an account that has a
        // verified TOTP factor enrolled, so this never blocks an owner who
        // hasn't opted in, and fails OPEN on an API error rather than
        // blocking access over a transient hiccup.
        const mfaRedirect = await checkMfaRequirement(supabaseClient, page);

        if (mfaRedirect) {
          window.location.href = mfaRedirect;
          return;
        }

        return;
      }

      if (blockedStatuses.includes(status) || access.can_access === false) {
        showBlockedPage(
          "Workspace Access Restricted",
          access.message || "Your UNGANI OS workspace cannot be opened because the account status is currently restricted.",
          "my-account-status.html",
          "View Account Status"
        );
      }
    } catch (error) {
      console.warn("Client access guard:", error.message);
    }
  }

  // Opt-in TOTP MFA (supabase.auth.mfa), owners only - mirrors
  // admin-access-guard.js's checkMfaRequirement() exactly.
  async function checkMfaRequirement(supabaseClient, page) {
    try {
      const aalResponse = await supabaseClient.auth.mfa.getAuthenticatorAssuranceLevel();

      if (aalResponse.error || !aalResponse.data) {
        return null;
      }

      const currentLevel = aalResponse.data.currentLevel;
      const nextLevel = aalResponse.data.nextLevel;

      if (nextLevel === "aal2" && currentLevel !== "aal2") {
        return "mfa-challenge.html?redirect=" + encodeURIComponent(page) + "&surface=client";
      }

      return null;
    } catch (error) {
      console.warn("UNGANI client MFA check failed:", error);
      return null;
    }
  }

  function getCurrentPage() {
    const path = window.location.pathname || "";
    return (path.split("/").pop() || "client.html").toLowerCase();
  }

  function showBlockedPage(title, message, buttonHref, buttonText) {
    const existing = document.getElementById("clientAccessBlockedOverlay");
    if (existing) existing.remove();

    const overlay = document.createElement("div");
    overlay.id = "clientAccessBlockedOverlay";
    overlay.style.cssText = "position:fixed;inset:0;z-index:999999;";

    overlay.innerHTML = `
      <div style="
        min-height:100vh;
        display:flex;
        align-items:center;
        justify-content:center;
        padding:24px;
        background:
          radial-gradient(circle at top right, rgba(212,166,58,0.18), transparent 32%),
          linear-gradient(135deg, #061C3D 0%, #092B58 55%, #0F172A 100%);
        font-family:Inter, Arial, sans-serif;
        color:white;
      ">
        <div style="
          width:min(620px, 100%);
          background:rgba(255,255,255,0.10);
          border:1px solid rgba(255,255,255,0.16);
          border-radius:28px;
          padding:28px;
          box-shadow:0 30px 90px rgba(0,0,0,0.35);
          text-align:center;
        ">
          <img src="ungani-logo.png" alt="UNGANI" style="
            width:76px;
            height:76px;
            object-fit:contain;
            background:white;
            border-radius:20px;
            padding:10px;
            margin-bottom:18px;
          " />

          <h1 style="margin:0;color:#D4A63A;font-size:30px;letter-spacing:-0.04em;">
            ${escapeHtml(title)}
          </h1>

          <p style="color:rgba(255,255,255,0.82);line-height:1.55;margin:14px auto 0;max-width:460px;">
            ${escapeHtml(message)}
          </p>

          <div style="display:flex;flex-wrap:wrap;gap:10px;justify-content:center;margin-top:24px;">
            <a href="${escapeHtml(buttonHref)}" style="
              display:inline-flex;
              align-items:center;
              justify-content:center;
              border-radius:999px;
              padding:12px 16px;
              background:#D4A63A;
              color:#061C3D;
              text-decoration:none;
              font-weight:950;
            ">${escapeHtml(buttonText)}</a>

            <a href="staff-login.html" style="
              display:inline-flex;
              align-items:center;
              justify-content:center;
              border-radius:999px;
              padding:12px 16px;
              background:rgba(255,255,255,0.12);
              color:white;
              border:1px solid rgba(255,255,255,0.16);
              text-decoration:none;
              font-weight:950;
            ">Staff Login</a>
          </div>

          <p style="color:rgba(255,255,255,0.62);font-size:12px;margin-top:24px;">
            UNGANI OS · ungani.com · info@ungani.com
          </p>
        </div>
      </div>
    `;

    document.body.appendChild(overlay);
  }

  function escapeHtml(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }
})();
