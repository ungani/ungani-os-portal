(function () {
  const SUPABASE_URL = "https://ctmtjwklltnsmfdtvqhl.supabase.co";
  const SUPABASE_KEY = "sb_publishable_jkZaWWep-cObTEv_F_kN6g_Ic85BxD9";

  const IDLE_TIMEOUT_MS = 30 * 60 * 1000;
  const WARNING_LEAD_MS = 5 * 60 * 1000;
  const ACTIVITY_KEY = "ungani_last_activity";
  const WRITE_THROTTLE_MS = 3000;

  const ACTIVITY_EVENTS = ["mousedown", "mousemove", "keydown", "scroll", "touchstart", "click"];

  let supabaseClient = null;
  let lastWriteAt = 0;
  let tickTimer = null;
  let warningEl = null;
  let countdownTimer = null;

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }

  async function init() {
    if (!window.supabase) return;

    supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

    const userResponse = await supabaseClient.auth.getUser();
    const user = userResponse && userResponse.data ? userResponse.data.user : null;

    if (!user) return;

    recordActivity();

    ACTIVITY_EVENTS.forEach(function (evt) {
      window.addEventListener(evt, throttledRecordActivity, { passive: true });
    });

    window.addEventListener("storage", function (event) {
      if (event.key === ACTIVITY_KEY) {
        hideWarning();
      }
    });

    supabaseClient.auth.onAuthStateChange(function (event) {
      if (event === "SIGNED_OUT") {
        redirectToLogin("signed-out");
      }
    });

    tickTimer = setInterval(checkIdle, 1000);
  }

  function throttledRecordActivity() {
    const now = Date.now();
    if (now - lastWriteAt < WRITE_THROTTLE_MS) return;
    recordActivity();
  }

  function recordActivity() {
    lastWriteAt = Date.now();

    try {
      localStorage.setItem(ACTIVITY_KEY, String(lastWriteAt));
    } catch (error) {
      // localStorage unavailable - inactivity tracking degrades to per-tab only
    }

    hideWarning();
  }

  function getLastActivity() {
    try {
      const stored = localStorage.getItem(ACTIVITY_KEY);
      return stored ? Number(stored) : Date.now();
    } catch (error) {
      return lastWriteAt || Date.now();
    }
  }

  function checkIdle() {
    const idleFor = Date.now() - getLastActivity();

    if (idleFor >= IDLE_TIMEOUT_MS) {
      doLogout("logout_idle_timeout");
      return;
    }

    if (idleFor >= IDLE_TIMEOUT_MS - WARNING_LEAD_MS) {
      showWarning(IDLE_TIMEOUT_MS - idleFor);
    }
  }

  function showWarning(msRemaining) {
    if (!warningEl) {
      warningEl = buildWarningEl();
      document.body.appendChild(warningEl);
    }

    updateCountdown(msRemaining);
  }

  function updateCountdown(msRemaining) {
    if (!warningEl) return;

    const totalSeconds = Math.max(0, Math.ceil(msRemaining / 1000));
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    const label = minutes + ":" + String(seconds).padStart(2, "0");

    const countEl = warningEl.querySelector("[data-ungani-idle-countdown]");
    if (countEl) countEl.textContent = label;
  }

  function hideWarning() {
    if (warningEl && warningEl.parentNode) {
      warningEl.parentNode.removeChild(warningEl);
    }

    warningEl = null;
  }

  function buildWarningEl() {
    const overlay = document.createElement("div");
    overlay.setAttribute("data-ungani-idle-overlay", "");
    overlay.style.cssText = [
      "position:fixed", "inset:0", "z-index:99999",
      "background:rgba(2,6,23,0.72)",
      "display:flex", "align-items:center", "justify-content:center",
      "padding:20px", "font-family:Inter, Arial, sans-serif"
    ].join(";");

    overlay.innerHTML = `
      <div style="
        width:min(420px, 100%);
        background:linear-gradient(135deg, rgba(6,28,61,0.98), rgba(9,43,88,0.96));
        border:1px solid rgba(255,255,255,0.14);
        border-radius:26px;
        padding:26px;
        box-shadow:0 30px 90px rgba(0,0,0,0.4);
        color:white;
        text-align:center;
      ">
        <div style="
          width:56px;height:56px;border-radius:16px;
          background:rgba(212,166,58,0.16);
          display:flex;align-items:center;justify-content:center;
          font-size:26px;margin:0 auto 14px;
        ">⏱️</div>

        <h2 style="margin:0 0 8px;font-size:21px;letter-spacing:-0.03em;color:white;">Still there?</h2>

        <p style="margin:0 0 4px;color:rgba(255,255,255,0.78);line-height:1.5;font-size:14px;">
          You'll be logged out due to inactivity in
        </p>

        <div data-ungani-idle-countdown style="
          font-size:32px;font-weight:950;color:#D4A63A;letter-spacing:-0.02em;margin:6px 0 18px;
        ">5:00</div>

        <div style="display:flex;gap:10px;flex-wrap:wrap;">
          <button type="button" data-ungani-idle-stay style="
            flex:1;min-width:140px;border:0;border-radius:999px;padding:13px 16px;
            background:#D4A63A;color:#061C3D;font-weight:950;font-size:14px;cursor:pointer;
          ">Stay Logged In</button>

          <button type="button" data-ungani-idle-logout style="
            flex:1;min-width:120px;border:1px solid rgba(255,255,255,0.22);border-radius:999px;padding:13px 16px;
            background:rgba(255,255,255,0.08);color:white;font-weight:950;font-size:14px;cursor:pointer;
          ">Log Out Now</button>
        </div>
      </div>
    `;

    overlay.querySelector("[data-ungani-idle-stay]").addEventListener("click", function () {
      recordActivity();
    });

    overlay.querySelector("[data-ungani-idle-logout]").addEventListener("click", function () {
      doLogout();
    });

    return overlay;
  }

  async function doLogout(reason) {
    hideWarning();

    if (tickTimer) {
      clearInterval(tickTimer);
      tickTimer = null;
    }

    try {
      const sessionRes = await supabaseClient.auth.getSession();
      const token = sessionRes?.data?.session?.access_token;
      if (token) {
        fetch("/api/log-audit-event", {
          method: "POST",
          headers: { "Content-Type": "application/json", Authorization: "Bearer " + token },
          body: JSON.stringify({ action: reason || "logout", entityType: "session" }),
          keepalive: true
        }).catch(function () {});
      }

      await supabaseClient.auth.signOut();
    } catch (error) {
      // proceed to redirect regardless
    }

    redirectToLogin("inactivity");
  }

  function redirectToLogin(reason) {
    const mode = window.location.pathname.toLowerCase().includes("admin") ? "admin" : "client";
    window.location.href = "login.html?mode=" + mode + "&reason=" + reason;
  }
})();
