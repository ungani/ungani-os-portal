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

  document.addEventListener("DOMContentLoaded", function () {
    initUnganiAdminAccessGuard();
  });

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

    await protectAdminPage();
  }

  async function protectAdminPage() {
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

      const adminResponse = await supabaseClient.rpc("is_ungani_admin");

      if (adminResponse.error) {
        console.warn("UNGANI admin guard RPC failed:", adminResponse.error);

        showAdminBlockedScreen({
          title: "Admin Check Failed",
          message: "UNGANI OS could not confirm your admin access.",
          detail: "Please refresh the page. If this continues, contact UNGANI support.",
          actionText: "Back to Login",
          actionUrl: "login.html"
        });

        return;
      }

      if (adminResponse.data === true) {
        return;
      }

      showAdminBlockedScreen({
        title: "Admin Access Required",
        message: "This page is reserved for UNGANI admin users only.",
        detail: "You are logged in, but this account does not have admin permission.",
        actionText: "Go to Client Portal",
        actionUrl: "client.html"
      });
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
