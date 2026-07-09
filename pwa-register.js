(function () {
  const UNGANI_BUILD_VERSION = "admin-clicks-14o-20260710";

  loadUiPolish();
  registerServiceWorker();
  loadAccessGuards();

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
      return;
    }

    if (clientPages.includes(page)) {
      loadScriptOnce("client-access-guard.js");
      loadScriptOnce("staff-permission-guard.js");
      loadScriptOnce("staff-visibility-filter.js");
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
