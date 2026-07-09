(function () {
  const SUPABASE_URL = "https://ctmtjwklltnsmfdtvqhl.supabase.co";
  const SUPABASE_KEY = "sb_publishable_jkZaWWep-cObTEv_F_kN6g_Ic85BxD9";

  const POLL_INTERVAL_MS = 15000;
  const STORAGE_KEY = "ungani_last_seen_notification_alert_id";

  let supabaseClient = null;
  let alertStarted = false;
  let lastSeenId = null;
  let currentUserType = "client";
  let audioReady = false;

  function initUnganiNotificationAlerts(options = {}) {
    if (alertStarted) return;

    alertStarted = true;
    currentUserType = options.userType === "admin" ? "admin" : "client";
    lastSeenId = localStorage.getItem(STORAGE_KEY + "_" + currentUserType);

    if (!window.supabase) {
      console.warn("UNGANI notification alerts: Supabase library not found.");
      return;
    }

    supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

    createAlertStyles();
    createAlertContainer();
    enableAudioAfterUserInteraction();

    checkForNewNotifications();

    setInterval(() => {
      checkForNewNotifications();
    }, POLL_INTERVAL_MS);
  }

  async function checkForNewNotifications() {
    try {
      const sessionResponse = await supabaseClient.auth.getSession();

      if (
        !sessionResponse ||
        !sessionResponse.data ||
        !sessionResponse.data.session
      ) {
        return;
      }

      let query = supabaseClient
        .from("ungani_notifications")
        .select("*")
        .order("created_at", { ascending: false })
        .limit(1);

      query = applyUserTypeFilter(query);

      const response = await query;

      if (response.error) {
        return;
      }

      const notifications = Array.isArray(response.data) ? response.data : [];

      if (!notifications.length) {
        return;
      }

      const latest = notifications[0];
      const latestId = String(latest.id || "");

      if (!latestId) {
        return;
      }

      if (!lastSeenId) {
        lastSeenId = latestId;
        localStorage.setItem(STORAGE_KEY + "_" + currentUserType, latestId);
        return;
      }

      if (latestId !== lastSeenId) {
        lastSeenId = latestId;
        localStorage.setItem(STORAGE_KEY + "_" + currentUserType, latestId);
        showNotificationPopup(latest);
        playNotificationSound();
      }
    } catch (error) {
      console.warn("UNGANI notification alert check failed:", error);
    }
  }

  function applyUserTypeFilter(query) {
    if (currentUserType === "admin") {
      return query.or("target_type.eq.admin,target_type.is.null");
    }

    return query.or("target_type.eq.client,target_type.is.null");
  }

  function showNotificationPopup(notification) {
    const container = document.getElementById("unganiNotificationAlertContainer");

    if (!container) return;

    const title = notification.title || "New notification";
    const message =
      notification.message ||
      notification.body ||
      "You have a new UNGANI OS notification.";

    const linkUrl =
      notification.link_url ||
      (currentUserType === "admin"
        ? "admin-notifications.html"
        : "client-notifications.html");

    const popup = document.createElement("button");
    popup.className = "ungani-notification-popup";
    popup.type = "button";

    popup.innerHTML = `
      <div class="ungani-notification-icon">🔔</div>
      <div class="ungani-notification-content">
        <strong>${escapeHtml(title)}</strong>
        <span>${escapeHtml(message)}</span>
      </div>
      <div class="ungani-notification-close">×</div>
    `;

    popup.addEventListener("click", () => {
      window.location.href = linkUrl;
    });

    container.appendChild(popup);

    setTimeout(() => {
      popup.classList.add("show");
    }, 50);

    setTimeout(() => {
      popup.classList.remove("show");

      setTimeout(() => {
        popup.remove();
      }, 300);
    }, 8000);
  }

  function playNotificationSound() {
    try {
      if (!audioReady) return;

      const audioContext = new (window.AudioContext || window.webkitAudioContext)();

      const oscillator = audioContext.createOscillator();
      const gainNode = audioContext.createGain();

      oscillator.type = "sine";
      oscillator.frequency.setValueAtTime(880, audioContext.currentTime);
      oscillator.frequency.setValueAtTime(660, audioContext.currentTime + 0.12);

      gainNode.gain.setValueAtTime(0.0001, audioContext.currentTime);
      gainNode.gain.exponentialRampToValueAtTime(0.08, audioContext.currentTime + 0.02);
      gainNode.gain.exponentialRampToValueAtTime(0.0001, audioContext.currentTime + 0.35);

      oscillator.connect(gainNode);
      gainNode.connect(audioContext.destination);

      oscillator.start(audioContext.currentTime);
      oscillator.stop(audioContext.currentTime + 0.38);
    } catch (error) {
      console.warn("UNGANI notification sound failed:", error);
    }
  }

  function enableAudioAfterUserInteraction() {
    const enable = () => {
      audioReady = true;

      window.removeEventListener("click", enable);
      window.removeEventListener("touchstart", enable);
      window.removeEventListener("keydown", enable);
    };

    window.addEventListener("click", enable);
    window.addEventListener("touchstart", enable);
    window.addEventListener("keydown", enable);
  }

  function createAlertContainer() {
    if (document.getElementById("unganiNotificationAlertContainer")) return;

    const container = document.createElement("div");
    container.id = "unganiNotificationAlertContainer";
    container.className = "ungani-notification-alert-container";

    document.body.appendChild(container);
  }

  function createAlertStyles() {
    if (document.getElementById("unganiNotificationAlertStyles")) return;

    const style = document.createElement("style");
    style.id = "unganiNotificationAlertStyles";

    style.textContent = `
      .ungani-notification-alert-container {
        position: fixed;
        right: 18px;
        top: 82px;
        z-index: 99999;
        display: flex;
        flex-direction: column;
        gap: 12px;
        width: min(380px, calc(100vw - 36px));
        pointer-events: none;
      }

      .ungani-notification-popup {
        pointer-events: auto;
        border: 1px solid rgba(212, 166, 58, 0.35);
        background:
          linear-gradient(135deg, rgba(8, 38, 84, 0.98), rgba(6, 28, 61, 0.98));
        color: #FFFFFF;
        border-radius: 18px;
        box-shadow: 0 18px 45px rgba(0, 0, 0, 0.35);
        padding: 14px;
        display: grid;
        grid-template-columns: 38px 1fr 20px;
        gap: 11px;
        text-align: left;
        cursor: pointer;
        transform: translateY(-12px);
        opacity: 0;
        transition: 0.28s ease;
        font-family: Arial, Helvetica, sans-serif;
      }

      .ungani-notification-popup.show {
        transform: translateY(0);
        opacity: 1;
      }

      .ungani-notification-icon {
        width: 38px;
        height: 38px;
        border-radius: 999px;
        display: flex;
        align-items: center;
        justify-content: center;
        background: rgba(212, 166, 58, 0.18);
        color: #D4A63A;
        font-size: 18px;
      }

      .ungani-notification-content {
        display: flex;
        flex-direction: column;
        gap: 5px;
        min-width: 0;
      }

      .ungani-notification-content strong {
        color: #D4A63A;
        font-size: 14px;
        line-height: 1.25;
      }

      .ungani-notification-content span {
        color: #F5F5F3;
        font-size: 13px;
        line-height: 1.4;
      }

      .ungani-notification-close {
        color: #B8C3D6;
        font-size: 18px;
        line-height: 1;
      }

      @media (max-width: 560px) {
        .ungani-notification-alert-container {
          top: 72px;
          right: 12px;
          width: calc(100vw - 24px);
        }

        .ungani-notification-popup {
          border-radius: 16px;
          grid-template-columns: 34px 1fr 18px;
          padding: 13px;
        }

        .ungani-notification-icon {
          width: 34px;
          height: 34px;
        }
      }
    `;

    document.head.appendChild(style);
  }

  function escapeHtml(value) {
    return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  window.initUnganiNotificationAlerts = initUnganiNotificationAlerts;
})();
