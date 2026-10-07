(function () {
  const SUPABASE_URL = "https://ctmtjwklltnsmfdtvqhl.supabase.co";
  const SUPABASE_KEY = "sb_publishable_jkZaWWep-cObTEv_F_kN6g_Ic85BxD9";
  const SUPABASE_CDN = "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2";

  let supabaseClient = null;
  let guardStarted = false;

  // Registration lives on index.html and password reset lives on
  // login.html in this app - register.html/signup.html/forgot-password.html/
  // reset-password.html never existed as real pages here, removed to avoid
  // implying otherwise.
  const PUBLIC_PAGES = [
    "index.html",
    "login.html"
  ];

  // Injected dynamically (pwa-register.js's loadScriptOnce, via
  // document.createElement("script") + appendChild) - the .defer=true it
  // sets has NO effect on a script inserted this way (defer only applies
  // to parser-inserted scripts per the HTML spec); a dynamically-inserted
  // script always runs as soon as it loads, which can be before OR after
  // DOMContentLoaded depending on network timing. An unconditional
  // addEventListener("DOMContentLoaded", ...) would silently never fire -
  // and this guard never runs at all - if the fetch happens to finish
  // after the event already dispatched. Matches the readyState check
  // client-access-guard.js already uses correctly.
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      initUnganiAdminAccessGuard();
    });
  } else {
    initUnganiAdminAccessGuard();
  }

  async function initUnganiAdminAccessGuard() {
    if (guardStarted) return;

    guardStarted = true;

    const pageName = getCurrentPageName();

    if (!shouldProtectAdminPage(pageName)) {
      return;
    }

    await ensureSupabaseLoaded();

    if (!window.supabase) {
      showAdminBlockedScreen({
        title: "Security Check Failed",
        message: "UNGANI OS could not load the security library.",
        detail: "Please refresh the page. If this continues, contact UNGANI support.",
        actionText: "Back to Login",
        actionUrl: "login.html"
      });

      return;
    }

    supabaseClient = window.getUnganiSupabaseClient ? window.getUnganiSupabaseClient() : window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
    if (!supabaseClient) return;

    await protectAdminPage(pageName);
  }

  async function protectAdminPage(pageName) {
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

      // Email-candidate only (NOT the strict aal2-gated is_ungani_admin())
      // - deciding whether to even START the 2FA flow must not itself
      // require 2FA to already be satisfied. Real-world lockout this
      // caused: an admin at aal1 was told "not an admin" before ever
      // reaching the challenge, with no way to climb out.
      const candidateResponse = await supabaseClient.rpc("is_ungani_admin_candidate");

      if (candidateResponse.error) {
        console.warn("UNGANI admin candidate check failed:", candidateResponse.error);

        showAdminBlockedScreen({
          title: "Admin Check Failed",
          message: "UNGANI OS could not confirm your admin access.",
          detail: "Please refresh the page. If this continues, contact UNGANI support.",
          actionText: "Back to Login",
          actionUrl: "login.html"
        });

        return;
      }

      if (candidateResponse.data !== true) {
        showAdminBlockedScreen({
          title: "Admin Access Required",
          message: "This page is reserved for UNGANI admin users only.",
          detail: "You are logged in, but this account does not have admin permission.",
          actionText: "Go to Client Portal",
          actionUrl: "client.html"
        });

        return;
      }

      const mfaOutcome = await resolveMfaRequirement(pageName);

      if (mfaOutcome.redirect) {
        window.location.href = mfaOutcome.redirect;
        return;
      }

      if (mfaOutcome.enrollmentPending) {
        // Candidate confirmed by email, no verified TOTP factor yet, and
        // this IS admin-settings.html - let the page render so its
        // enrollment section is reachable (there's nothing to challenge
        // against yet). Every admin_* RPC this page calls still fails
        // server-side via the strict is_ungani_admin() until enrollment
        // finishes, so nothing real is exposed in the meantime.
        return;
      }

      // aal2 satisfied (or never required for this account) - final real
      // confirmation via the strict, mandatory-2FA gate.
      const adminResponse = await supabaseClient.rpc("is_ungani_admin");

      if (adminResponse.error || adminResponse.data !== true) {
        showAdminBlockedScreen({
          title: "Admin Check Failed",
          message: "UNGANI OS could not confirm your admin access.",
          detail: "Please refresh the page, or complete two-factor enrollment in Settings. If this continues, contact UNGANI support.",
          actionText: "Back to Login",
          actionUrl: "login.html"
        });
      }
    } catch (error) {
      console.warn("UNGANI admin guard failed:", error);

      showAdminBlockedScreen({
        title: "Security Check Error",
        message: "UNGANI OS could not complete the admin security check.",
        detail: "Please refresh the page. If this continues, contact UNGANI support.",
        actionText: "Back to Login",
        actionUrl: "login.html"
      });
    }
  }

  // MANDATORY TOTP for every ungani_admins account - no opt-in exception.
  // Distinguishes "never enrolled a factor" (send to admin-settings.html
  // to enroll - the only admin page a not-yet-aal2 candidate may reach,
  // since there's nothing to challenge against yet) from "a verified
  // factor exists but this session hasn't completed the challenge yet"
  // (send to mfa-challenge.html). Checked here rather than in login.html's
  // submit handler because this guard is the one thing every admin page
  // already loads (confirmed via admin-settings.html, which has its own
  // separate legacy sign-in form that bypasses login.html entirely) - a
  // login-page-only check would miss that second entry point. The real
  // security boundary stays server-side (is_ungani_admin() requires
  // aal2 unconditionally) - this only decides where to route the browser.
  async function resolveMfaRequirement(pageName) {
    try {
      const aalResponse = await supabaseClient.auth.mfa.getAuthenticatorAssuranceLevel();

      if (aalResponse.error || !aalResponse.data) {
        // Fail OPEN on this routing decision only: the final strict
        // is_ungani_admin() call right after this still enforces aal2 -
        // a transient MFA-API hiccup here just means the browser lands
        // on the real blocked screen instead of a redirect loop.
        return { redirect: null, enrollmentPending: false };
      }

      if (aalResponse.data.currentLevel === "aal2") {
        return { redirect: null, enrollmentPending: false };
      }

      const factorsResponse = await supabaseClient.auth.mfa.listFactors();
      const hasVerifiedTotp = !factorsResponse.error && factorsResponse.data &&
        (factorsResponse.data.totp || []).some(function (f) { return f.status === "verified"; });

      if (!hasVerifiedTotp) {
        if (pageName === "admin-settings.html") {
          return { redirect: null, enrollmentPending: true };
        }

        return { redirect: "admin-settings.html?mfaRequired=1", enrollmentPending: false };
      }

      return {
        redirect: "mfa-challenge.html?redirect=" + encodeURIComponent(pageName) + "&surface=admin",
        enrollmentPending: false
      };
    } catch (error) {
      console.warn("UNGANI MFA requirement check failed:", error);
      return { redirect: null, enrollmentPending: false };
    }
  }

  function shouldProtectAdminPage(pageName) {
    if (PUBLIC_PAGES.includes(pageName)) {
      return false;
    }

    if (pageName.startsWith("admin")) {
      return true;
    }

    if (
      pageName === "support.html" ||
      pageName === "billing.html" ||
      pageName === "admin-notifications.html" ||
      pageName === "admin-home.html"
    ) {
      return true;
    }

    return false;
  }

  async function ensureSupabaseLoaded() {
    if (window.supabase) return;

    await new Promise(function (resolve) {
      const existing = document.querySelector('script[src="' + SUPABASE_CDN + '"]');

      if (existing) {
        existing.addEventListener("load", resolve, { once: true });
        existing.addEventListener("error", resolve, { once: true });
        return;
      }

      const script = document.createElement("script");
      script.src = SUPABASE_CDN;
      script.onload = resolve;
      script.onerror = resolve;
      document.head.appendChild(script);
    });
  }

  function showAdminBlockedScreen(options) {
    const title = options.title || "Admin Access Restricted";
    const message = options.message || "Your admin access is currently restricted.";
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
    const current = window.location.pathname.split("/").pop() || "admin-home.html";
    window.location.href =
      "login.html?redirect=" + encodeURIComponent(current);
  }

  function getCurrentPageName() {
    const path = window.location.pathname || "";
    return (path.split("/").pop() || "index.html").toLowerCase();
  }

  function escapeHtml(value) {
    return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  window.initUnganiAdminAccessGuard = initUnganiAdminAccessGuard;
})();
