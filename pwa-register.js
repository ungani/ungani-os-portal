(function () {
  const UNGANI_BUILD_VERSION = "portal-separation-14s-20260710";

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
    const portalMode = String(localStorage.getItem("ungani_portal_mode") || "").toLowerCase();

    const publicPages = [
      "index.html",
      "login.html",
      "staff-login.html"
    ];

    const adminPages = [
      "admin.html",
      "admin-home.html",
      "admin-reports.html",
      "admin-onboarding.html",
      "admin-billing.html",
      "admin-subscriptions.html",
      "admin-upgrade-requests.html",
      "admin-branches.html",
      "admin-health.html",
      "admin-email-queue.html",
      "admin-payment-proofs.html",
      "admin-invoice.html",
      "support.html"
    ];

    const clientPages = [
      "client.html",
      "my-money.html",
      "my-tasks.html",
      "my-items.html",
      "my-people.html",
      "my-records.html",
      "my-documents.html",
      "my-calendar.html",
      "my-support.html",
      "my-chat.html",
      "my-team-chat.html",
      "my-reports.html",
      "reports.html",
      "my-billing.html",
      "my-invoice.html",
      "my-package.html",
      "my-branches.html",
      "my-settings.html",
      "my-team-access.html",
      "client-notifications.html",
      "my-tools.html",
      "my-onboarding.html",
      "my-account-status.html"
    ];

    if (publicPages.includes(page)) return;

    if (adminPages.includes(page)) {
      loadScriptOnce("admin-access-guard.js");
      loadScriptOnce("admin-ui-polish.js");
      loadScriptOnce("admin-dashboard-clicks.js");
      loadScriptOnce("session-inactivity-guard.js");
      return;
    }

    if (clientPages.includes(page)) {
      loadScriptOnce("client-access-guard.js");
      loadScriptOnce("session-inactivity-guard.js");

      if (portalMode === "staff") {
        loadScriptOnce("staff-permission-guard.js");
        loadScriptOnce("staff-visibility-filter.js");
      }
    }
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
