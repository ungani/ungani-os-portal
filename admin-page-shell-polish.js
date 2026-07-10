(function () {
  const VERSION = "portal14x";

  const ADMIN_LINKS = [
    { section: "COMMAND", label: "Admin Home", icon: "🏠", href: "admin-home.html?v=portal14x" },
    { section: "COMMAND", label: "Launch Readiness", icon: "🚀", href: "admin-launch.html?v=portal14x" },
    { section: "COMMAND", label: "System Health", icon: "🛡️", href: "admin-health.html?v=portal14x" },
    { section: "COMMAND", label: "Smart Checks", icon: "🧠", href: "admin-smart-checks.html?v=portal14x" },

    { section: "CLIENTS", label: "Client Admin", icon: "👥", href: "admin.html?v=portal14x" },
    { section: "CLIENTS", label: "Subscriptions", icon: "📦", href: "admin-subscriptions.html?v=portal14x" },
    { section: "CLIENTS", label: "Upgrade Requests", icon: "⬆️", href: "admin-upgrade-requests.html?v=portal14x" },
    { section: "CLIENTS", label: "Billing", icon: "💳", href: "admin-billing.html?v=portal14x" },
    { section: "CLIENTS", label: "Payment Proofs", icon: "🧾", href: "admin-payment-proofs.html?v=portal14x" },

    { section: "SYSTEM", label: "Email Queue", icon: "✉️", href: "admin-email-queue.html?v=portal14x" },
    { section: "SYSTEM", label: "Branches", icon: "🏬", href: "admin-branches.html?v=portal14x" },
    { section: "SYSTEM", label: "Reports", icon: "📊", href: "admin-reports.html?v=portal14x" },
    { section: "SYSTEM", label: "Onboarding", icon: "🧭", href: "admin-onboarding.html?v=portal14x" },
    { section: "SYSTEM", label: "Settings", icon: "⚙️", href: "admin-settings.html?v=portal14x" }
  ];

  function injectStyles() {
    const old = document.getElementById("ungani-admin-page-shell-polish-style");
    if (old) old.remove();

    const style = document.createElement("style");
    style.id = "ungani-admin-page-shell-polish-style";

    style.textContent = `
      body.ungani-admin-page-polished {
        color: #FFFFFF !important;
        background:
          radial-gradient(circle at top left, rgba(212, 166, 58, 0.18), transparent 34%),
          radial-gradient(circle at top right, rgba(255, 255, 255, 0.07), transparent 28%),
          linear-gradient(135deg, #03142E 0%, #061C3D 45%, #081A34 100%) !important;
      }

      body.ungani-admin-page-polished .ungani-admin-standard-sidebar,
      body.ungani-admin-page-polished .sidebar,
      body.ungani-admin-page-polished .admin-sidebar,
      body.ungani-admin-page-polished aside.sidebar {
        width: 278px !important;
        background:
          linear-gradient(180deg, rgba(3, 20, 46, 0.99), rgba(6, 28, 61, 0.99)) !important;
        color: #FFFFFF !important;
        padding: 24px 18px !important;
        position: fixed !important;
        top: 0 !important;
        bottom: 0 !important;
        left: 0 !important;
        overflow-y: auto !important;
        border-right: 1px solid rgba(212, 166, 58, 0.18) !important;
        box-shadow: 12px 0 36px rgba(0, 0, 0, 0.30) !important;
        z-index: 20 !important;
      }

      body.ungani-admin-page-polished.ungani-admin-has-sidebar .ungani-admin-main-content {
        margin-left: 278px !important;
        width: calc(100% - 278px) !important;
        min-height: 100vh !important;
        padding: 24px !important;
      }

      .ungani-admin-brand {
        display: flex !important;
        align-items: center !important;
        gap: 12px !important;
        margin-bottom: 24px !important;
        padding: 8px 8px 18px !important;
        border-bottom: 1px solid rgba(212, 166, 58, 0.18) !important;
      }

      .ungani-admin-brand img {
        width: 50px !important;
        height: 50px !important;
        object-fit: contain !important;
        background: #FFFFFF !important;
        border-radius: 14px !important;
        padding: 5px !important;
        box-shadow: 0 8px 20px rgba(212, 166, 58, 0.16) !important;
      }

      .ungani-admin-brand h1 {
        margin: 0 !important;
        color: #FFFFFF !important;
        font-size: 19px !important;
        letter-spacing: 0.6px !important;
      }

      .ungani-admin-brand p {
        margin: 4px 0 0 !important;
        color: rgba(255, 255, 255, 0.64) !important;
        font-size: 12px !important;
      }

      .ungani-admin-section-title {
        color: rgba(212, 166, 58, 0.90) !important;
        font-size: 11px !important;
        text-transform: uppercase !important;
        letter-spacing: 0.13em !important;
        font-weight: 900 !important;
        margin: 18px 10px 8px !important;
      }

      .ungani-admin-side-link {
        width: 100% !important;
        display: flex !important;
        align-items: center !important;
        justify-content: flex-start !important;
        gap: 12px !important;
        text-align: left !important;
        color: rgba(255, 255, 255, 0.86) !important;
        text-decoration: none !important;
        padding: 12px 13px !important;
        border-radius: 14px !important;
        margin: 4px 0 !important;
        font-size: 14px !important;
        line-height: 1.2 !important;
        font-weight: 800 !important;
        transition: 0.18s ease !important;
        border: 1px solid transparent !important;
        background: transparent !important;
        cursor: pointer !important;
      }

      .ungani-admin-side-link:hover,
      .ungani-admin-side-link.active {
        color: #FFFFFF !important;
        background: rgba(212, 166, 58, 0.16) !important;
        border-color: rgba(212, 166, 58, 0.36) !important;
        transform: translateX(2px) !important;
      }

      .ungani-admin-side-icon {
        width: 30px !important;
        min-width: 30px !important;
        height: 30px !important;
        display: inline-flex !important;
        align-items: center !important;
        justify-content: center !important;
        border-radius: 10px !important;
        background: rgba(255, 255, 255, 0.08) !important;
        border: 1px solid rgba(212, 166, 58, 0.22) !important;
        font-size: 14px !important;
      }

      .ungani-admin-side-text {
        display: inline-flex !important;
        align-items: center !important;
        text-align: left !important;
      }

      body.ungani-admin-page-polished h1,
      body.ungani-admin-page-polished h2,
      body.ungani-admin-page-polished h3,
      body.ungani-admin-page-polished h4 {
        color: #FFFFFF !important;
      }

      body.ungani-admin-page-polished p,
      body.ungani-admin-page-polished small,
      body.ungani-admin-page-polished span,
      body.ungani-admin-page-polished label {
        color: inherit;
      }

      body.ungani-admin-page-polished .card,
      body.ungani-admin-page-polished .panel,
      body.ungani-admin-page-polished .box,
      body.ungani-admin-page-polished .admin-card,
      body.ungani-admin-page-polished .admin-panel,
      body.ungani-admin-page-polished .content-card,
      body.ungani-admin-page-polished .table-card,
      body.ungani-admin-page-polished .subscription-card,
      body.ungani-admin-page-polished .billing-card,
      body.ungani-admin-page-polished .stat-card,
      body.ungani-admin-page-polished .summary-card {
        background:
          linear-gradient(145deg, rgba(6, 28, 61, 0.92), rgba(10, 37, 79, 0.84)) !important;
        color: #FFFFFF !important;
        border: 1px solid rgba(212, 166, 58, 0.16) !important;
        box-shadow: 0 22px 60px rgba(0, 0, 0, 0.30) !important;
        border-radius: 20px !important;
      }

      body.ungani-admin-page-polished table {
        width: 100% !important;
        background: rgba(6, 28, 61, 0.74) !important;
        color: #FFFFFF !important;
        border-collapse: separate !important;
        border-spacing: 0 !important;
        border: 1px solid rgba(212, 166, 58, 0.14) !important;
        border-radius: 16px !important;
        overflow: hidden !important;
      }

      body.ungani-admin-page-polished th {
        background: rgba(212, 166, 58, 0.16) !important;
        color: #F0C85A !important;
        font-weight: 900 !important;
        text-align: left !important;
      }

      body.ungani-admin-page-polished td,
      body.ungani-admin-page-polished th {
        border-bottom: 1px solid rgba(255, 255, 255, 0.10) !important;
        padding: 12px !important;
      }

      body.ungani-admin-page-polished input,
      body.ungani-admin-page-polished select,
      body.ungani-admin-page-polished textarea {
        background: rgba(255, 255, 255, 0.08) !important;
        color: #FFFFFF !important;
        border: 1px solid rgba(212, 166, 58, 0.22) !important;
        border-radius: 12px !important;
      }

      body.ungani-admin-page-polished button,
      body.ungani-admin-page-polished .btn,
      body.ungani-admin-page-polished a.button,
      body.ungani-admin-page-polished .button {
        border-radius: 14px !important;
        font-weight: 900 !important;
      }

      body.ungani-admin-page-polished .btn-primary,
      body.ungani-admin-page-polished .primary,
      body.ungani-admin-page-polished button.primary {
        background: linear-gradient(135deg, #D4A63A, #F0C85A) !important;
        color: #061C3D !important;
      }

      .ungani-admin-floating-menu-fix {
        transition: 0.18s ease !important;
      }

      @media (min-width: 781px) {
        .ungani-admin-floating-menu-fix {
          display: none !important;
        }
      }

      @media (max-width: 780px) {
        body.ungani-admin-page-polished .ungani-admin-standard-sidebar,
        body.ungani-admin-page-polished .sidebar,
        body.ungani-admin-page-polished .admin-sidebar,
        body.ungani-admin-page-polished aside.sidebar {
          position: relative !important;
          width: 100% !important;
          min-height: auto !important;
          bottom: auto !important;
        }

        body.ungani-admin-page-polished.ungani-admin-has-sidebar .ungani-admin-main-content {
          margin-left: 0 !important;
          width: 100% !important;
          padding: 16px !important;
        }

        .ungani-admin-floating-menu-fix {
          position: fixed !important;
          top: auto !important;
          right: 16px !important;
          bottom: 18px !important;
          left: auto !important;
          z-index: 9999 !important;
          border-radius: 999px !important;
          padding: 13px 16px !important;
          background: linear-gradient(135deg, #D4A63A, #F0C85A) !important;
          color: #061C3D !important;
          border: 1px solid rgba(212, 166, 58, 0.55) !important;
          box-shadow: 0 16px 34px rgba(0, 0, 0, 0.34) !important;
          font-weight: 900 !important;
          min-height: 46px !important;
        }
      }
    `;

    document.head.appendChild(style);
  }

  function createSidebar() {
    const existing =
      document.querySelector(".sidebar") ||
      document.querySelector(".admin-sidebar") ||
      document.querySelector("aside.sidebar");

    if (existing) return existing;

    const currentPage = window.location.pathname.split("/").pop().split("?")[0];

    const aside = document.createElement("aside");
    aside.className = "ungani-admin-standard-sidebar sidebar";
    aside.setAttribute("data-created-by", "admin-page-shell-polish-" + VERSION);

    let html = `
      <div class="ungani-admin-brand">
        <img src="ungani-logo.png" alt="UNGANI Logo">
        <div>
          <h1>UNGANI OS</h1>
          <p>Admin Command Center</p>
        </div>
      </div>
    `;

    let currentSection = "";

    ADMIN_LINKS.forEach((link) => {
      if (link.section !== currentSection) {
        currentSection = link.section;
        html += `<div class="ungani-admin-section-title">${currentSection}</div>`;
      }

      const linkPage = link.href.split("?")[0];
      const active = linkPage === currentPage ? " active" : "";

      html += `
        <a class="ungani-admin-side-link${active}" href="${link.href}">
          <span class="ungani-admin-side-icon">${link.icon}</span>
          <span class="ungani-admin-side-text">${link.label}</span>
        </a>
      `;
    });

    aside.innerHTML = html;
    document.body.insertBefore(aside, document.body.firstChild);

    return aside;
  }

  function findMainContent(sidebar) {
    const candidates = [
      "main",
      ".main",
      ".admin-main",
      ".main-content",
      ".content",
      ".admin-content",
      ".page",
      ".page-content",
      ".container",
      "#main",
      "#app"
    ];

    for (const selector of candidates) {
      const el = document.querySelector(selector);
      if (el && el !== sidebar && !sidebar.contains(el)) {
        return el;
      }
    }

    return null;
  }

  function wrapBodyContent(sidebar) {
    let main = findMainContent(sidebar);

    if (main) {
      main.classList.add("ungani-admin-main-content");
      return main;
    }

    main = document.createElement("main");
    main.className = "ungani-admin-main-content";

    const children = Array.from(document.body.children);

    children.forEach((child) => {
      if (
        child === sidebar ||
        child.tagName === "SCRIPT" ||
        child.tagName === "STYLE" ||
        child.id === "ungani-admin-page-shell-polish-style"
      ) {
        return;
      }

      main.appendChild(child);
    });

    document.body.insertBefore(main, sidebar.nextSibling);

    return main;
  }

  function fixAdminMenuButton() {
    const candidates = Array.from(document.querySelectorAll("button, a"));

    candidates.forEach((el) => {
      const text = String(el.textContent || "").replace(/\s+/g, " ").trim().toLowerCase();

      if (text === "admin menu" || text.includes("admin menu")) {
        const insideSidebar = el.closest(".sidebar, .admin-sidebar, aside");
        if (insideSidebar) return;

        el.classList.add("ungani-admin-floating-menu-fix");
      }
    });
  }

  function run() {
    const page = window.location.pathname.split("/").pop().toLowerCase();

    if (!page.startsWith("admin")) return;

    document.body.classList.add("ungani-admin-page-polished");
    injectStyles();

    const sidebar = createSidebar();
    document.body.classList.add("ungani-admin-has-sidebar");

    wrapBodyContent(sidebar);
    fixAdminMenuButton();

    setTimeout(fixAdminMenuButton, 500);
    setTimeout(fixAdminMenuButton, 1500);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", run);
  } else {
    run();
  }
})();
