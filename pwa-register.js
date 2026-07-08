(function () {
  const APP_NAME = "UNGANI OS";

  function addMeta(name, content) {
    if (document.querySelector(`meta[name="${name}"]`)) return;

    const meta = document.createElement("meta");
    meta.setAttribute("name", name);
    meta.setAttribute("content", content);
    document.head.appendChild(meta);
  }

  function addLink(rel, href, extra) {
    if (document.querySelector(`link[rel="${rel}"][href="${href}"]`)) return;

    const link = document.createElement("link");
    link.setAttribute("rel", rel);
    link.setAttribute("href", href);

    if (extra) {
      Object.keys(extra).forEach(function (key) {
        link.setAttribute(key, extra[key]);
      });
    }

    document.head.appendChild(link);
  }

  function preparePwaHead() {
    addLink("manifest", "/manifest.json");
    addLink("apple-touch-icon", "/ungani-logo.png");
    addLink("icon", "/ungani-logo.png", {
      type: "image/png"
    });

    addMeta("application-name", APP_NAME);
    addMeta("apple-mobile-web-app-title", APP_NAME);
    addMeta("apple-mobile-web-app-capable", "yes");
    addMeta("apple-mobile-web-app-status-bar-style", "black-translucent");
    addMeta("mobile-web-app-capable", "yes");
    addMeta("theme-color", "#061C3D");
    addMeta("msapplication-TileColor", "#061C3D");
    addMeta("msapplication-TileImage", "/ungani-logo.png");
  }

  async function registerServiceWorker() {
    if (!("serviceWorker" in navigator)) {
      console.warn("UNGANI OS PWA: Service workers are not supported in this browser.");
      return;
    }

    try {
      const registration = await navigator.serviceWorker.register("/sw.js", {
        scope: "/"
      });

      console.log("UNGANI OS PWA service worker registered:", registration.scope);
    } catch (error) {
      console.warn("UNGANI OS PWA service worker registration failed:", error);
    }
  }

  function setupInstallPrompt() {
    let deferredPrompt = null;

    window.addEventListener("beforeinstallprompt", function (event) {
      event.preventDefault();
      deferredPrompt = event;

      window.UnganiPWA = window.UnganiPWA || {};
      window.UnganiPWA.canInstall = true;
      window.UnganiPWA.promptInstall = async function () {
        if (!deferredPrompt) return false;

        deferredPrompt.prompt();

        const choiceResult = await deferredPrompt.userChoice;
        deferredPrompt = null;

        return choiceResult && choiceResult.outcome === "accepted";
      };

      document.dispatchEvent(new CustomEvent("ungani:pwa-install-ready"));
    });

    window.addEventListener("appinstalled", function () {
      deferredPrompt = null;

      window.UnganiPWA = window.UnganiPWA || {};
      window.UnganiPWA.installed = true;
      window.UnganiPWA.canInstall = false;

      console.log("UNGANI OS PWA installed.");
    });
  }

  function isStandaloneMode() {
    return (
      window.matchMedia("(display-mode: standalone)").matches ||
      window.navigator.standalone === true
    );
  }

  function exposeHelpers() {
    window.UnganiPWA = window.UnganiPWA || {};

    window.UnganiPWA.isStandalone = isStandaloneMode;

    window.UnganiPWA.getInstallInstructions = function () {
      const userAgent = navigator.userAgent || "";

      if (/iphone|ipad|ipod/i.test(userAgent)) {
        return "On iPhone Safari: tap Share, then tap Add to Home Screen.";
      }

      if (/android/i.test(userAgent)) {
        return "On Android Chrome: tap the menu, then tap Install app or Add to Home screen.";
      }

      return "Open this site in Chrome, Edge, or Safari and use the browser install option.";
    };
  }

  preparePwaHead();
  setupInstallPrompt();
  exposeHelpers();

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", registerServiceWorker);
  } else {
    registerServiceWorker();
  }
})();
