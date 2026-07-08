(function () {
  const APP_NAME = "UNGANI OS";
  const THEME_COLOR = "#061C3D";
  const ICON_PATH = "/ungani-logo.png";
  const MANIFEST_PATH = "/manifest.json";
  const SERVICE_WORKER_PATH = "/sw.js";

  let deferredInstallPrompt = null;

  function addOrUpdateMeta(name, content) {
    let meta = document.querySelector(`meta[name="${name}"]`);

    if (!meta) {
      meta = document.createElement("meta");
      meta.setAttribute("name", name);
      document.head.appendChild(meta);
    }

    meta.setAttribute("content", content);
  }

  function addOrUpdateLink(rel, href, type) {
    let link = document.querySelector(`link[rel="${rel}"]`);

    if (!link) {
      link = document.createElement("link");
      link.setAttribute("rel", rel);
      document.head.appendChild(link);
    }

    link.setAttribute("href", href);

    if (type) {
      link.setAttribute("type", type);
    }
  }

  function setupPwaHeadTags() {
    addOrUpdateLink("manifest", MANIFEST_PATH);
    addOrUpdateLink("apple-touch-icon", ICON_PATH);
    addOrUpdateLink("icon", ICON_PATH, "image/png");

    addOrUpdateMeta("application-name", APP_NAME);
    addOrUpdateMeta("apple-mobile-web-app-title", APP_NAME);
    addOrUpdateMeta("apple-mobile-web-app-capable", "yes");
    addOrUpdateMeta("apple-mobile-web-app-status-bar-style", "black-translucent");
    addOrUpdateMeta("mobile-web-app-capable", "yes");
    addOrUpdateMeta("theme-color", THEME_COLOR);
    addOrUpdateMeta("msapplication-TileColor", THEME_COLOR);
    addOrUpdateMeta("msapplication-TileImage", ICON_PATH);
  }

  async function registerServiceWorker() {
    if (!("serviceWorker" in navigator)) {
      return;
    }

    try {
      const registration = await navigator.serviceWorker.register(SERVICE_WORKER_PATH, {
        scope: "/"
      });

      if (registration && registration.update) {
        registration.update().catch(function () {});
      }
    } catch (error) {
      console.warn("UNGANI PWA service worker registration failed:", error.message);
    }
  }

  function setupInstallPrompt() {
    window.addEventListener("beforeinstallprompt", function (event) {
      event.preventDefault();
      deferredInstallPrompt = event;

      window.UnganiPWA.canInstall = true;

      document.dispatchEvent(
        new CustomEvent("ungani:pwa-install-ready", {
          detail: {
            canInstall: true
          }
        })
      );
    });

    window.addEventListener("appinstalled", function () {
      deferredInstallPrompt = null;
      window.UnganiPWA.canInstall = false;

      document.dispatchEvent(
        new CustomEvent("ungani:pwa-installed", {
          detail: {
            installed: true
          }
        })
      );
    });
  }

  function isStandalone() {
    return (
      window.matchMedia("(display-mode: standalone)").matches ||
      window.navigator.standalone === true
    );
  }

  function getInstallInstructions() {
    const userAgent = navigator.userAgent || "";

    if (/iphone|ipad|ipod/i.test(userAgent)) {
      return "On iPhone Safari: tap Share, then Add to Home Screen.";
    }

    if (/android/i.test(userAgent)) {
      return "On Android Chrome: tap the browser menu, then Install app or Add to Home screen.";
    }

    return "On desktop Chrome or Edge: open the browser menu, then choose Install UNGANI OS.";
  }

  async function promptInstall() {
    if (!deferredInstallPrompt) {
      return false;
    }

    deferredInstallPrompt.prompt();

    const choice = await deferredInstallPrompt.userChoice;
    const accepted = choice && choice.outcome === "accepted";

    deferredInstallPrompt = null;
    window.UnganiPWA.canInstall = false;

    return accepted;
  }

  window.UnganiPWA = window.UnganiPWA || {};
  window.UnganiPWA.canInstall = false;
  window.UnganiPWA.promptInstall = promptInstall;
  window.UnganiPWA.isStandalone = isStandalone;
  window.UnganiPWA.getInstallInstructions = getInstallInstructions;

  setupPwaHeadTags();
  setupInstallPrompt();
  registerServiceWorker();

  function injectClickableCardStyles() {
    if (document.getElementById("ungani-clickable-card-styles")) {
      return;
    }

    const style = document.createElement("style");
    style.id = "ungani-clickable-card-styles";
    style.textContent = `
      .ungani-clickable-card {
        cursor: pointer !important;
        transition: transform 0.18s ease, box-shadow 0.18s ease, border-color 0.18s ease, background 0.18s ease !important;
      }

      .ungani-clickable-card:hover {
        transform: translateY(-2px) !important;
        border-color: rgba(212, 166, 58, 0.46) !important;
      }

      .ungani-clickable-card:active {
        transform: translateY(0) !important;
      }

      .ungani-clickable-card .ungani-click-hint {
        margin-top: 10px;
        color: #D4A63A;
        font-size: 11px;
        font-weight: 950;
        letter-spacing: 0.02em;
      }

      .ungani-notification-card {
        cursor: pointer !important;
      }

      @media (max-width: 1180px) {
        .ungani-clickable-card .ungani-click-hint {
          display: none;
        }
      }
    `;

    document.head.appendChild(style);
  }

  function cleanText(value) {
    return String(value || "")
      .toLowerCase()
      .replace(/\s+/g, " ")
      .trim();
  }

  function isAdminPage() {
    const path = window.location.pathname.toLowerCase();
    return path.includes("admin-home.html");
  }

  function isClientPage() {
    const path = window.location.pathname.toLowerCase();
    return path.endsWith("/client.html") || path.includes("client.html");
  }

  function isDashboardPage() {
    return isAdminPage() || isClientPage();
  }

  function openNotificationPanel() {
    if (typeof window.toggleNotifications === "function") {
      window.toggleNotifications();
      return true;
    }

    const panel = document.getElementById("notificationPanel");
    const overlay = document.getElementById("notificationOverlay");

    if (panel) {
      panel.classList.add("open");
      if (overlay) overlay.classList.add("open");
      document.body.style.overflow = "hidden";
      return true;
    }

    return false;
  }

  function routeForAdminCard(text) {
    const value = cleanText(text);

    if (value.includes("notification") || value.includes("unread update")) {
      return "__notifications__";
    }

    if (value.includes("pending approval") || value.includes("approval") || value.includes("registration") || value.includes("pending registrations")) {
      return "admin.html";
    }

    if (value.includes("client") || value.includes("profiles") || value.includes("active clients") || value.includes("trial clients")) {
      return "admin-profiles.html";
    }

    if (value.includes("support") || value.includes("issue") || value.includes("urgent") || value.includes("high priority")) {
      return "support.html";
    }

    if (value.includes("chat") || value.includes("message")) {
      return "admin-chat.html";
    }

    if (value.includes("billing") || value.includes("payment") || value.includes("package") || value.includes("payments")) {
      return "billing.html";
    }

    if (value.includes("money") || value.includes("income") || value.includes("expense") || value.includes("client money")) {
      return "admin-money.html";
    }

    if (value.includes("task") || value.includes("overdue") || value.includes("follow")) {
      return "admin-tasks.html";
    }

    if (value.includes("document") || value.includes("file")) {
      return "admin-documents.html";
    }

    if (value.includes("calendar") || value.includes("event") || value.includes("activity")) {
      return "admin-calendar.html";
    }

    if (value.includes("record") || value.includes("business record")) {
      return "admin-records.html";
    }

    if (value.includes("item") || value.includes("asset") || value.includes("stock")) {
      return "admin-items.html";
    }

    if (value.includes("people") || value.includes("user") || value.includes("access") || value.includes("staff")) {
      return "admin-people.html";
    }

    if (value.includes("report")) {
      return "admin-reports.html";
    }

    if (value.includes("health") || value.includes("attention") || value.includes("no money") || value.includes("no tasks") || value.includes("no documents")) {
      return "admin-health.html";
    }

    if (value.includes("business type") || value.includes("industries")) {
      return "admin-profiles.html";
    }

    return "";
  }

  function routeForClientCard(text) {
    const value = cleanText(text);

    if (value.includes("notification") || value.includes("unread update")) {
      return "__notifications__";
    }

    if (value.includes("income") || value.includes("expense") || value.includes("balance") || value.includes("money") || value.includes("petty") || value.includes("recorded income") || value.includes("recorded expenses")) {
      return "my-money.html";
    }

    if (value.includes("task") || value.includes("follow") || value.includes("overdue") || value.includes("pending") || value.includes("due follow")) {
      return "my-tasks.html";
    }

    if (value.includes("record") || value.includes("business update") || value.includes("business records")) {
      return "my-records.html";
    }

    if (value.includes("support") || value.includes("issue") || value.includes("open issue")) {
      return "my-support.html";
    }

    if (value.includes("chat") || value.includes("message") || value.includes("admin chat")) {
      return "my-chat.html";
    }

    if (value.includes("team chat")) {
      return "my-team-chat.html";
    }

    if (value.includes("calendar") || value.includes("event") || value.includes("viewing") || value.includes("today")) {
      return "my-calendar.html";
    }

    if (value.includes("document") || value.includes("file")) {
      return "my-documents.html";
    }

    if (value.includes("item") || value.includes("asset") || value.includes("stock") || value.includes("property") || value.includes("properties")) {
      return "my-items.html";
    }

    if (value.includes("people") || value.includes("staff") || value.includes("supplier") || value.includes("client") || value.includes("lead") || value.includes("agents") || value.includes("tenants") || value.includes("buyers")) {
      return "my-people.html";
    }

    if (value.includes("report") || value.includes("summary")) {
      return "reports.html";
    }

    if (value.includes("attention") || value.includes("needs action")) {
      return "my-tasks.html";
    }

    return "";
  }

  function shouldIgnoreCard(card) {
    if (!card) {
      return true;
    }

    if (card.dataset.unganiClickableReady === "yes") {
      return true;
    }

    if (card.tagName && card.tagName.toLowerCase() === "a") {
      return true;
    }

    if (card.closest && card.closest(".sidebar")) {
      return true;
    }

    if (card.closest && card.closest(".notification-panel")) {
      return true;
    }

    if (card.closest && card.closest("form")) {
      return true;
    }

    return false;
  }

  function getRouteForCard(card) {
    const text = card.innerText || "";

    if (isAdminPage()) {
      return routeForAdminCard(text);
    }

    if (isClientPage()) {
      return routeForClientCard(text);
    }

    return "";
  }

  function makeCardClickable(card, href) {
    if (!card || !href) {
      return;
    }

    card.dataset.unganiClickableReady = "yes";
    card.dataset.unganiHref = href;
    card.classList.add("ungani-clickable-card");
    card.setAttribute("role", "link");
    card.setAttribute("tabindex", "0");

    if (href === "__notifications__") {
      card.classList.add("ungani-notification-card");
      card.setAttribute("title", "Open notifications");
    } else {
      card.setAttribute("title", "Open " + href.replace(".html", "").replace(/[-_]/g, " "));
    }

    const hasHint = card.querySelector(".ungani-click-hint");

    if (!hasHint && (card.classList.contains("kpi-card") || card.classList.contains("today-item"))) {
      const hint = document.createElement("div");
      hint.className = "ungani-click-hint";
      hint.textContent = href === "__notifications__" ? "Click to view" : "Click to open";
      card.appendChild(hint);
    }

    card.addEventListener("click", function (event) {
      if (event.target && event.target.closest && event.target.closest("a, button, input, select, textarea")) {
        return;
      }

      if (href === "__notifications__") {
        openNotificationPanel();
        return;
      }

      window.location.href = href;
    });

    card.addEventListener("keydown", function (event) {
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();

        if (href === "__notifications__") {
          openNotificationPanel();
          return;
        }

        window.location.href = href;
      }
    });
  }

  function enhanceClickableCards() {
    if (!isDashboardPage()) {
      return;
    }

    injectClickableCardStyles();

    const selectors = [
      ".kpi-card",
      ".today-item",
      ".summary-row",
      ".activity-item",
      ".quick-action",
      ".hero-mini",
      ".card"
    ];

    const cards = Array.from(document.querySelectorAll(selectors.join(", ")));

    cards.forEach(function (card) {
      if (shouldIgnoreCard(card)) {
        return;
      }

      const href = getRouteForCard(card);

      if (href) {
        makeCardClickable(card, href);
      }
    });
  }

  function setupClickableCardsObserver() {
    if (!isDashboardPage()) {
      return;
    }

    let timer = null;

    function scheduleEnhance() {
      window.clearTimeout(timer);
      timer = window.setTimeout(enhanceClickableCards, 180);
    }

    document.addEventListener("DOMContentLoaded", scheduleEnhance);
    window.addEventListener("load", scheduleEnhance);

    const observer = new MutationObserver(scheduleEnhance);

    observer.observe(document.body, {
      childList: true,
      subtree: true
    });

    scheduleEnhance();
  }

  setupClickableCardsObserver();
})();
