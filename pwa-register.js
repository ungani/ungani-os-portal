(function () {
  const CLIENT_GUARD_SCRIPT_SRC = "client-access-guard.js";

  document.addEventListener("DOMContentLoaded", function () {
    registerUnganiServiceWorker();
    loadUnganiClientAccessGuard();
  });

  function registerUnganiServiceWorker() {
    if (!("serviceWorker" in navigator)) {
      return;
    }

    window.addEventListener("load", function () {
      navigator.serviceWorker
        .register("sw.js")
        .then(function (registration) {
          console.log("UNGANI OS service worker registered:", registration.scope);
        })
        .catch(function (error) {
          console.warn("UNGANI OS service worker registration failed:", error);
        });
    });
  }

  function loadUnganiClientAccessGuard() {
    const pageName = getCurrentPageName();

    if (!shouldLoadClientGuard(pageName)) {
      return;
    }

    if (window.initUnganiClientAccessGuard) {
      window.initUnganiClientAccessGuard();
      return;
    }

    if (document.querySelector('script[src="' + CLIENT_GUARD_SCRIPT_SRC + '"]')) {
      waitForClientGuardScript();
      return;
    }

    const script = document.createElement("script");
    script.src = CLIENT_GUARD_SCRIPT_SRC;
    script.defer = true;

    script.onload = function () {
      if (window.initUnganiClientAccessGuard) {
        window.initUnganiClientAccessGuard();
      }
    };

    script.onerror = function () {
      console.warn("UNGANI client access guard script failed to load.");
    };

    document.body.appendChild(script);
  }

  function waitForClientGuardScript() {
    let attempts = 0;

    const timer = setInterval(function () {
      attempts += 1;

      if (window.initUnganiClientAccessGuard) {
        clearInterval(timer);
        window.initUnganiClientAccessGuard();
        return;
      }

      if (attempts >= 20) {
        clearInterval(timer);
      }
    }, 250);
  }

  function shouldLoadClientGuard(pageName) {
    const publicPages = [
      "index.html",
      "login.html",
      "register.html",
      "signup.html",
      "forgot-password.html",
      "reset-password.html"
    ];

    if (publicPages.includes(pageName)) {
      return false;
    }

    if (pageName.startsWith("admin")) {
      return false;
    }

    if (
      pageName === "support.html" ||
      pageName === "billing.html" ||
      pageName === "admin-notifications.html" ||
      pageName === "admin-home.html"
    ) {
      return false;
    }

    if (
      pageName === "client.html" ||
      pageName === "client-notifications.html" ||
      pageName.startsWith("my-") ||
      pageName.startsWith("client-")
    ) {
      return true;
    }

    return false;
  }

  function getCurrentPageName() {
    const path = window.location.pathname || "";
    const clean = path.split("/").pop() || "index.html";

    return clean.toLowerCase();
  }
})();
