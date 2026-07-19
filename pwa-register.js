(function () {
  const UNGANI_BUILD_VERSION = "portal-separation-14s-20260710";
  const SUPABASE_URL = "https://ctmtjwklltnsmfdtvqhl.supabase.co";
  const SUPABASE_KEY = "sb_publishable_jkZaWWep-cObTEv_F_kN6g_Ic85BxD9";

  // Every authenticated page used to call window.supabase.createClient()
  // independently in its own inline script AND in each guard script it
  // loaded (client-access-guard.js, session-inactivity-guard.js,
  // staff-permission-guard.js, staff-visibility-filter.js) - up to 9+
  // separate GoTrueClient instances per page load, all racing against the
  // same localStorage-persisted session. Supabase JS explicitly documents
  // this as producing "undefined behavior" - multiple instances each run
  // their own auto-refresh timer, and if two race to refresh the same
  // (single-use, rotating) refresh token, the loser can get an
  // invalid-token error and conclude the user is signed out, sometimes
  // corrupting the shared session for every other instance on the page too.
  // This is the most likely cause of intermittent "got logged out" reports
  // on section navigation (a full page reload, so a fresh burst of
  // near-simultaneous client creation every time). pwa-register.js loads
  // first on every authenticated page (non-deferred, before any guard
  // script it injects), so this is the one safe place to hand out a single
  // shared instance that every script on the page reuses instead.
  window.getUnganiSupabaseClient = function () {
    if (window.__unganiSupabaseClient) return window.__unganiSupabaseClient;
    if (!window.supabase || typeof window.supabase.createClient !== "function") return null;

    window.__unganiSupabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
    return window.__unganiSupabaseClient;
  };

  setPortalModeFromUrl();
  loadUiPolish();
  registerServiceWorker();
  loadAccessGuards();

  function setPortalModeFromUrl() {
    const page = getCurrentPage();
    const params = new URLSearchParams(window.location.search || "");
    const mode = String(params.get("mode") || "").toLowerCase();

    if (mode === "staff") {
      localStorage.setItem("ungani_portal_mode", "staff");
      return;
    }

    if (mode === "client" || mode === "owner") {
      localStorage.setItem("ungani_portal_mode", "client");
      return;
    }

    if (mode === "admin") {
      localStorage.setItem("ungani_portal_mode", "admin");
      return;
    }

    if (page === "staff-login.html") {
      localStorage.setItem("ungani_portal_mode", "staff");
      return;
    }

    if (page === "login.html") {
      if (!localStorage.getItem("ungani_portal_mode")) {
        localStorage.setItem("ungani_portal_mode", "client");
      }
      return;
    }

    if (page.startsWith("admin") || page === "support.html") {
      localStorage.setItem("ungani_portal_mode", "admin");
    }
  }

  function loadUiPolish() {
    if (document.querySelector('link[href^="ungani-ui-polish.css"]')) return;

    const link = document.createElement("link");
    link.rel = "stylesheet";
    link.href = "ungani-ui-polish.css?v=" + UNGANI_BUILD_VERSION;
    document.head.appendChild(link);
  }

  function registerServiceWorker() {
    if (!("serviceWorker" in navigator)) return;

    window.addEventListener("load", function () {
      navigator.serviceWorker.register("/sw.js").catch(function (error) {
        console.warn("UNGANI OS service worker registration failed:", error.message);
      });
    });
  }

  function loadAccessGuards() {
    const page = getCurrentPage();

    // Pages with no authenticated session and nothing sensitive to guard.
    // Everything else authenticated falls through to the admin/client
    // classification below, by filename pattern rather than a hand-maintained
    // allow-list - the previous exhaustive arrays silently missed new pages
    // (they covered ~30 of ~90 pages), leaving most of the app with no
    // idle-session timeout at all.
    const publicPages = [
      "index.html",
      "login.html",
      "staff-login.html",
      "portal.html"
    ];

    if (publicPages.includes(page)) return;

    const isAdminPage = page.startsWith("admin") || page === "support.html" || page === "users.html" ||
      page === "sections.html" || page === "billing.html" || page === "notices.html";

    if (isAdminPage) {
      loadScriptOnce("admin-access-guard.js");
      loadScriptOnce("session-inactivity-guard.js");
      return;
    }

    loadScriptOnce("client-access-guard.js");
    loadScriptOnce("session-inactivity-guard.js");

    // Always run the real, server-verified permission check (it calls
    // get_my_ungani_staff_access and safely no-ops for genuine owners) -
    // this used to be gated behind a "portalMode === staff" flag read from
    // localStorage, which is trivially overwritten by a client-supplied
    // ?mode=client URL param, letting a restricted staff account skip the
    // check entirely. The check itself decides what to enforce; loading it
    // must not be optional.
    loadScriptOnce("staff-permission-guard.js");
    loadScriptOnce("staff-visibility-filter.js");
  }

  function getCurrentPage() {
    const path = window.location.pathname || "";
    const page = path.split("/").pop() || "index.html";
    return page.toLowerCase();
  }

  function loadScriptOnce(src) {
    if (!src) return;

    const baseSrc = src.split("?")[0];

    if (document.querySelector('script[src^="' + baseSrc + '"]')) {
      return;
    }

    const script = document.createElement("script");
    script.src = baseSrc + "?v=" + UNGANI_BUILD_VERSION;
    script.defer = true;
    document.head.appendChild(script);
  }
})();
