(function () {
  const CLIENT_GUARD_SCRIPT_SRC = "client-access-guard.js";
  const ADMIN_GUARD_SCRIPT_SRC = "admin-access-guard.js";

  document.addEventListener("DOMContentLoaded", function () {
    registerUnganiServiceWorker();
    loadUnganiSecurityGuards();
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

  function loadUnganiSecurityGuards() {
    const pageName = getCurrentPageName();

    if (shouldLoadAdminGuard(pageName)) {
      loadScriptOnce(ADMIN_GUARD_SCRIPT_SRC, function () {
        if (window.initUnganiAdminAccessGuard) {
          window.initUnganiAdminAccessGuard();
        }
      });

      return;
    }

    if (shouldLoadClientGuard(pageName)) {
      loadScriptOnce(CLIENT_GUARD_SCRIPT_SRC, function () {
        if (window.initUnganiClientAccessGuard) {
          window.initUnganiClientAccessGuard();
        }
      });
    }
  }

  function loadScriptOnce(src, callback) {
    const existing = document.querySelector('script[src="' + src + '"]');

    if (existing) {
      waitForScriptReady(src, callback);
      return;
    }

    const script = document.createElement("script");
    script.src = src;
    script.defer = true;

    script.onload = function () {
      callback();
    };

    script.onerror = function () {
      console.warn("UNGANI security guard script failed to load:", src);
    };

    document.body.appendChild(script);
  }

  function waitForScriptReady(src, callback) {
    let attempts = 0;

    const timer = setInterval(function () {
      attempts += 1;

      if (
        src === CLIENT_GUARD_SCRIPT_SRC &&
        window.initUnganiClientAccessGuard
      ) {
        clearInterval(timer);
        callback();
        return;
      }

      if (
        src === ADMIN_GUARD_SCRIPT_SRC &&
        window.initUnganiAdminAccessGuard
      ) {
        clearInterval(timer);
        callback();
        return;
      }

      if (attempts >= 20) {
        clearInterval(timer);
      }
    }, 250);
  }

  function shouldLoadAdminGuard(pageName) {
    if (isPublicPage(pageName)) {
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

  function shouldLoadClientGuard(pageName) {
    if (isPublicPage(pageName)) {
      return false;
    }

    if (shouldLoadAdminGuard(pageName)) {
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

  function isPublicPage(pageName) {
    const publicPages = [
      "index.html",
      "login.html",
      "register.html",
      "signup.html",
      "forgot-password.html",
      "reset-password.html"
    ];

    return publicPages.includes(pageName);
  }

  function getCurrentPageName() {
    const path = window.location.pathname || "";
    const clean = path.split("/").pop() || "index.html";

    return clean.toLowerCase();
  }
})();
