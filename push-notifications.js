(function () {
  // Public VAPID key - safe to ship in client code (only the private key,
  // held server-side in api/send-push.js, is secret). Generated once
  // tonight; if it's ever rotated, this and the Vercel env vars must be
  // updated together or existing subscriptions silently stop matching.
  const VAPID_PUBLIC_KEY = "BFJ-HuWHjH1OHim313PV12E7yiVaxSqw_RfwHBrgIJ8OA5JI61HWKfrD_b6zhXV46f0cUIBkigfDwH3SkYUh0dI";
  const BANNER_DISMISSED_KEY = "ungani_push_banner_dismissed";
  const SW_READY_TIMEOUT_MS = 8000;

  function isSupported() {
    return "serviceWorker" in navigator && "PushManager" in window && typeof Notification !== "undefined";
  }

  // The Badging API is a separate, much less consistently supported
  // browser capability from push itself - notably absent on Android
  // Chrome entirely (no navigator.setAppBadge at all, on any Chrome
  // version, as of this writing), present on iOS 16.4+ but ONLY for a
  // PWA actually installed to the Home Screen (an open Safari tab has no
  // access to it, same install requirement as push), and present on some
  // desktop browsers (Chrome/Edge, taskbar/dock icon). Always feature-
  // detected - silently does nothing where unsupported, which is the
  // correct behavior (not a bug) rather than something to warn about.
  function isBadgingSupported() {
    return "setAppBadge" in navigator && "clearAppBadge" in navigator;
  }

  async function setAppBadgeCount(total) {
    if (!isBadgingSupported()) return;

    try {
      const count = Math.max(0, Number(total) || 0);

      if (count > 0) {
        await navigator.setAppBadge(count);
      } else {
        await navigator.clearAppBadge();
      }
    } catch (error) {
      console.warn("UNGANI app badge update skipped:", error.message);
    }
  }

  async function clearAppBadgeNow() {
    if (!isBadgingSupported()) return;

    try {
      await navigator.clearAppBadge();
    } catch (error) {
      console.warn("UNGANI app badge clear skipped:", error.message);
    }
  }

  function urlBase64ToUint8Array(base64String) {
    const padding = "=".repeat((4 - (base64String.length % 4)) % 4);
    const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/");
    const rawData = atob(base64);
    const outputArray = new Uint8Array(rawData.length);

    for (let i = 0; i < rawData.length; i++) {
      outputArray[i] = rawData.charCodeAt(i);
    }

    return outputArray;
  }

  function getClient() {
    return typeof window.getUnganiSupabaseClient === "function" ? window.getUnganiSupabaseClient() : null;
  }

  function serviceWorkerReady() {
    return Promise.race([
      navigator.serviceWorker.ready,
      new Promise(function (_, reject) {
        setTimeout(function () { reject(new Error("Service worker took too long to become ready.")); }, SW_READY_TIMEOUT_MS);
      })
    ]);
  }

  async function getExistingSubscription() {
    if (!isSupported()) return null;

    try {
      const registration = await serviceWorkerReady();
      return await registration.pushManager.getSubscription();
    } catch (error) {
      console.warn("UNGANI push: could not read existing subscription:", error.message);
      return null;
    }
  }

  // Must call Notification.requestPermission() as the very first thing
  // this function does (before any await) - it has to run inside the
  // synchronous portion of the click handler that invoked it, or Chrome
  // silently suppresses the prompt and iOS Safari requires it outright.
  async function subscribe() {
    if (!isSupported()) {
      return { ok: false, message: "Push notifications aren't supported on this browser/device." };
    }

    try {
      const permission = await Notification.requestPermission();

      if (permission !== "granted") {
        return {
          ok: false,
          message: permission === "denied"
            ? "Notifications were blocked. You can re-enable them from your browser's site settings."
            : "Notification permission was not granted."
        };
      }

      const registration = await serviceWorkerReady();
      let subscription = await registration.pushManager.getSubscription();

      if (!subscription) {
        subscription = await registration.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY)
        });
      }

      const subJson = subscription.toJSON();
      const client = getClient();

      if (!client) {
        return { ok: false, message: "Could not reach the UNGANI session." };
      }

      const { data, error } = await client.rpc("save_ungani_push_subscription", {
        p_endpoint: subJson.endpoint,
        p_p256dh: subJson.keys.p256dh,
        p_auth_key: subJson.keys.auth,
        p_user_agent: navigator.userAgent
      });

      if (error || !data || data.ok !== true) {
        return { ok: false, message: (error && error.message) || (data && data.message) || "Could not save push subscription." };
      }

      localStorage.setItem(BANNER_DISMISSED_KEY, "1");
      return { ok: true, message: "Notifications enabled on this device." };
    } catch (error) {
      return { ok: false, message: error.message };
    }
  }

  async function unsubscribe() {
    try {
      const subscription = await getExistingSubscription();

      if (!subscription) {
        return { ok: true, message: "Notifications were already off on this device." };
      }

      const endpoint = subscription.endpoint;
      const client = getClient();

      await subscription.unsubscribe();

      if (client) {
        await client.rpc("remove_ungani_push_subscription", { p_endpoint: endpoint });
      }

      return { ok: true, message: "Notifications turned off on this device." };
    } catch (error) {
      return { ok: false, message: error.message };
    }
  }

  async function sendTestPush() {
    const client = getClient();
    if (!client) return { ok: false, message: "Could not reach the UNGANI session." };

    try {
      const sessionRes = await client.auth.getSession();
      const token = sessionRes?.data?.session?.access_token;

      if (!token) return { ok: false, message: "Not signed in." };

      const response = await fetch("/api/send-push", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: "Bearer " + token },
        body: JSON.stringify({
          title: "UNGANI OS test push",
          body: "If you can see this, push notifications are working on this device.",
          url: "/"
        })
      });

      const body = await response.json().catch(function () { return {}; });

      if (!response.ok || body.ok !== true) {
        return { ok: false, message: body.message || "Could not send test push." };
      }

      if (body.sent === 0) {
        return { ok: false, message: body.message || "No active push subscription found - enable notifications first." };
      }

      return { ok: true, message: "Test push sent - check your device." };
    } catch (error) {
      return { ok: false, message: error.message };
    }
  }

  // "unsupported" | "blocked" | "enabled" | "not_enabled"
  async function getStatus() {
    if (!isSupported()) return "unsupported";
    if (Notification.permission === "denied") return "blocked";

    const subscription = await getExistingSubscription();
    return subscription ? "enabled" : "not_enabled";
  }

  function isBannerDismissed() {
    return localStorage.getItem(BANNER_DISMISSED_KEY) === "1";
  }

  function dismissBanner() {
    localStorage.setItem(BANNER_DISMISSED_KEY, "1");
    const el = document.getElementById("unganiPushBanner");
    if (el) el.remove();
  }

  function injectBannerStyles() {
    if (document.getElementById("unganiPushBannerStyles")) return;

    const style = document.createElement("style");
    style.id = "unganiPushBannerStyles";
    style.textContent = `
      .ungani-push-banner {
        position: fixed;
        left: 18px;
        bottom: 18px;
        z-index: 99998;
        display: grid;
        grid-template-columns: 40px 1fr;
        gap: 12px;
        width: min(380px, calc(100vw - 36px));
        border: 1px solid rgba(212, 166, 58, 0.35);
        background: linear-gradient(135deg, rgba(8, 38, 84, 0.98), rgba(6, 28, 61, 0.98));
        color: #FFFFFF;
        border-radius: 18px;
        box-shadow: 0 18px 45px rgba(0, 0, 0, 0.35);
        padding: 16px;
        font-family: Arial, Helvetica, sans-serif;
        transform: translateY(16px);
        opacity: 0;
        transition: 0.28s ease;
      }
      .ungani-push-banner.show { transform: translateY(0); opacity: 1; }
      .ungani-push-banner-icon {
        width: 40px; height: 40px; border-radius: 999px;
        display: flex; align-items: center; justify-content: center;
        background: rgba(212, 166, 58, 0.18); color: #D4A63A; font-size: 19px;
      }
      .ungani-push-banner-content { display: flex; flex-direction: column; gap: 4px; min-width: 0; }
      .ungani-push-banner-content strong { color: #D4A63A; font-size: 14px; }
      .ungani-push-banner-content span { color: #F5F5F3; font-size: 13px; line-height: 1.4; }
      .ungani-push-banner-actions { grid-column: 1 / -1; display: flex; gap: 10px; margin-top: 10px; }
      .ungani-push-banner-actions button {
        flex: 1; border-radius: 10px; border: none; padding: 9px 12px;
        font-weight: 700; font-size: 13px; cursor: pointer; font-family: inherit;
      }
      .ungani-push-banner-enable { background: #D4A63A; color: #061C3D; }
      .ungani-push-banner-dismiss { background: rgba(255, 255, 255, 0.12); color: #F5F5F3; }
      @media (max-width: 560px) {
        .ungani-push-banner { left: 12px; right: 12px; bottom: 12px; width: auto; }
      }
    `;
    document.head.appendChild(style);
  }

  async function maybeShowBanner() {
    if (isBannerDismissed()) return;
    if (!isSupported()) return;
    if (Notification.permission !== "default") return;
    if (document.getElementById("unganiPushBanner")) return;

    injectBannerStyles();

    const banner = document.createElement("div");
    banner.id = "unganiPushBanner";
    banner.className = "ungani-push-banner";
    banner.innerHTML =
      '<div class="ungani-push-banner-icon">🔔</div>' +
      '<div class="ungani-push-banner-content">' +
      "<strong>Turn on notifications?</strong>" +
      "<span>Get notified instantly for important updates - even when this tab isn't open.</span>" +
      "</div>" +
      '<div class="ungani-push-banner-actions">' +
      '<button type="button" class="ungani-push-banner-enable">Enable</button>' +
      '<button type="button" class="ungani-push-banner-dismiss">Not now</button>' +
      "</div>";

    banner.querySelector(".ungani-push-banner-enable").addEventListener("click", async function () {
      const result = await subscribe();
      dismissBanner();
      if (!result.ok) console.warn("UNGANI push subscribe:", result.message);
    });

    banner.querySelector(".ungani-push-banner-dismiss").addEventListener("click", dismissBanner);

    document.body.appendChild(banner);
    setTimeout(function () { banner.classList.add("show"); }, 50);
  }

  window.UnganiPush = {
    isSupported,
    subscribe,
    unsubscribe,
    sendTestPush,
    getStatus,
    maybeShowBanner,
    isBadgingSupported,
    setAppBadgeCount,
    clearAppBadgeNow
  };

  // Auto-offer the banner once there's a real session - only on pages
  // that load this file at all (pwa-register.js decides that, skipping
  // public/unauthenticated pages).
  window.addEventListener("load", function () {
    setTimeout(async function () {
      const client = getClient();
      if (!client) return;

      const sessionRes = await client.auth.getSession();
      if (!sessionRes?.data?.session) return;

      maybeShowBanner();
    }, 1500);
  });
})();
