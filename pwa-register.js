(function () {
  const ALERT_SCRIPT_SRC = "notification-alerts.js";

  document.addEventListener("DOMContentLoaded", function () {
    registerUnganiServiceWorker();
    loadUnganiNotificationAlerts();
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

  function loadUnganiNotificationAlerts() {
    const pageName = getCurrentPageName();

    if (shouldSkipNotificationAlerts(pageName)) {
      return;
    }

    const userType = detectUserType(pageName);

    if (!userType) {
      return;
    }

    if (window.initUnganiNotificationAlerts) {
      window.initUnganiNotificationAlerts({
        userType: userType
      });
      return;
    }

    if (document.querySelector('script[src="' + ALERT_SCRIPT_SRC + '"]')) {
      waitForAlertScript(userType);
      return;
    }

    const script = document.createElement("script");
    script.src = ALERT_SCRIPT_SRC;
    script.defer = true;

    script.onload = function () {
      if (window.initUnganiNotificationAlerts) {
        window.initUnganiNotificationAlerts({
          userType: userType
        });
      }
    };

    script.onerror = function () {
      console.warn("UNGANI notification alert script failed to load.");
    };

    document.body.appendChild(script);
  }

  function waitForAlertScript(userType) {
    let attempts = 0;

    const timer = setInterval(function () {
      attempts += 1;

      if (window.initUnganiNotificationAlerts) {
        clearInterval(timer);
        window.initUnganiNotificationAlerts({
          userType: userType
        });
        return;
      }

      if (attempts >= 20) {
        clearInterval(timer);
      }
    }, 250);
  }

  function getCurrentPageName() {
    const path = window.location.pathname || "";
    const clean = path.split("/").pop() || "index.html";

    return clean.toLowerCase();
  }

  function detectUserType(pageName) {
    if (
      pageName.startsWith("admin") ||
      pageName === "support.html" ||
      pageName === "billing.html"
    ) {
      return "admin";
    }

    if (
      pageName.startsWith("my-") ||
      pageName.startsWith("client") ||
      pageName === "client.html" ||
      pageName === "client-notifications.html"
    ) {
      return "client";
    }

    return null;
  }

  function shouldSkipNotificationAlerts(pageName) {
    const skipPages = [
      "index.html",
      "login.html",
      "register.html",
      "forgot-password.html",
      "reset-password.html",
      "signup.html"
    ];

    return skipPages.includes(pageName);
  }
})();
