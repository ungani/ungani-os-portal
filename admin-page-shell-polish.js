(function () {
  const VERSION = "portal14y";

  const ADMIN_LINKS = [
    { section: "COMMAND", label: "Admin Home", icon: "🏠", href: "admin-home.html?v=portal14y" },
    { section: "COMMAND", label: "Launch Readiness", icon: "🚀", href: "admin-launch.html?v=portal14y" },
    { section: "COMMAND", label: "System Health", icon: "🛡️", href: "admin-health.html?v=portal14y" },
    { section: "COMMAND", label: "Smart Checks", icon: "🧠", href: "admin-smart-checks.html?v=portal14y" },

    { section: "CLIENTS", label: "Client Admin", icon: "👥", href: "admin.html?v=portal14y" },
    { section: "CLIENTS", label: "Subscriptions", icon: "📦", href: "admin-subscriptions.html?v=portal14y" },
    { section: "CLIENTS", label: "Upgrade Requests", icon: "⬆️", href: "admin-upgrade-requests.html?v=portal14y" },
    { section: "CLIENTS", label: "Billing", icon: "💳", href: "admin-billing.html?v=portal14y" },
    { section: "CLIENTS", label: "Payment Proofs", icon: "🧾", href: "admin-payment-proofs.html?v=portal14y" },

    { section: "SYSTEM", label: "Email Queue", icon: "✉️", href: "admin-email-queue.html?v=portal14y" },
    { section: "SYSTEM", label: "Branches", icon: "🏬", href: "admin-branches.html?v=portal14y" },
    { section: "SYSTEM", label: "Reports", icon: "📊", href: "admin-reports.html?v=portal14y" },
    { section: "SYSTEM", label: "Onboarding", icon: "🧭", href: "admin-onboarding.html?v=portal14y" },
    { section: "SYSTEM", label: "Settings", icon: "⚙️", href: "admin-settings.html?v=portal14y" }
  ];

  function pageName() {
    return window.location.pathname.split("/").pop().split("?")[0].toLowerCase();
  }

  function existingSidebar() {
    return (
      document.querySelector(".sidebar") ||
      document.querySelector(".admin-sidebar") ||
      document.querySelector("aside.sidebar") ||
      document.querySelector("aside.admin-sidebar")
    );
  }

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

      body.ungani-admin-page-polished .sidebar,
      body.ungani-admin-page-polished .admin-sidebar,
      body.ungani-admin-page-polished aside.sidebar,
      body.ungani-admin-page-polished aside.admin-sidebar,
      body.ungani-admin-page-polished .ungani-admin-standard-sidebar {
        background:
          linear-gradient(180deg, rgba(3, 20, 46, 0.99), rgba(6, 28, 61, 0.99)) !important;
        color: #FFFFFF !important;
        border-right: 1px solid rgba(212, 166, 58, 0.18) !important;
        box-shadow: 12px 0 36px rgba(0, 0, 0, 0.30) !important;
      }

      /*
        Only pages where this script CREATES a sidebar get forced margin-left.
        Existing-sidebar pages like admin-subscriptions must keep their own layout.
      */
      body.ungani-admin-created-sidebar .ungani-admin-main-content {
        margin-left: 278px !important;
        width: calc(100% - 278px) !important;
        min-height: 100vh !important;
        padding: 24px !important;
      }

      .ungani-admin-standard-sidebar {
        width: 278px !important;
        padding: 24px 18px !important;
        position: fixed !important;
        top: 0 !important;
        bottom: 0 !important;
        left: 0 !important;
        overflow-y: auto !important;
        z-index: 20 !important;
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
        gap: 12px !important;
        color: rgba(255, 255, 255, 0.86) !important;
        text-decoration: none !important;
        padding: 12px 13px !important;
        border-radius: 14px !important;
        margin: 4px 0 !important;
        font-size: 14px !important;
        font-weight: 800 !important;
        border: 1px solid transparent !important;
        background: transparent !important;
      }

      .ungani-admin-side-link:hover,
      .ungani-admin-side-link.active {
        color: #FFFFFF !important;
        background: rgba(212, 166, 58, 0.16) !important;
        border-color: rgba(212, 166, 58, 0.36) !important;
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
      }

      body.ungani-admin-page-polished h1,
      body.ungani-admin-page-polished h2,
      body.ungani-admin-page-polished h3,
      body.ungani-admin-page-polished h4 {
        color: #FFFFFF !important;
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
      body.ungani-admin-page-polished .summary-card,
      body.ungani-admin-page-polished section {
        background-color: rgba(6, 28, 61, 0.72);
        color: #FFFFFF;
      }

      body.ungani-admin-page-polished table {
        background: rgba(6, 28, 61, 0.74) !important;
        color: #FFFFFF !important;
        border: 1px solid rgba(212, 166, 58, 0.14) !important;
        border-radius: 16px !important;
      }

      body.ungani-admin-page-polished th {
        background: rgba(212, 166, 58, 0.16) !important;
        color: #F0C85A !important;
      }

      body.ungani-admin-page-polished td,
      body.ungani-admin-page-polished th {
        border-bottom: 1px solid rgba(255, 255, 255, 0.10) !important;
      }

      body.ungani-admin-page-polished input,
      body.ungani-admin-page-polished select,
      body.ungani-admin-page-polished textarea {
        background: rgba(255, 255, 255, 0.08) !important;
        color: #FFFFFF !important;
        border: 1px solid rgba(212, 166, 58, 0.22) !important;
      }

      body.ungani-admin-page-polished button,
      body.ungani-admin-page-polished .btn,
      body.ungani-admin-page-polished a.button,
      body.ungani-admin-page-polished .button {
        border-radius: 14px !important;
        font-weight: 900 !important;
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
        body.ungani-admin-created-sidebar .ungani-admin-standard-sidebar {
          position: relative !important;
          width: 100% !important;
          min-height: auto !important;
          bottom: auto !important;
        }

        body.ungani-admin-created-sidebar .ungani-admin-main-content {
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
    const currentPage = pageName();

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
          <span>${link.label}</span>
        </a>
      `;
    });

    aside.innerHTML = html;
    document.body.insertBefore(aside, document.body.firstChild);
    return aside;
  }

  function wrapOnlyWhenSidebarWasCreated(sidebar) {
    const main = document.createElement("main");
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
  }

  function fixAdminMenuButton() {
    Array.from(document.querySelectorAll("button, a")).forEach((el) => {
      const text = String(el.textContent || "").replace(/\s+/g, " ").trim().toLowerCase();

      if (text === "admin menu" || text.includes("admin menu")) {
        if (el.closest(".sidebar, .admin-sidebar, aside")) return;
        el.classList.add("ungani-admin-floating-menu-fix");
      }
    });
  }

  function run() {
    const page = pageName();
    if (!page.startsWith("admin")) return;

    document.body.classList.add("ungani-admin-page-polished");
    injectStyles();

    const sidebar = existingSidebar();

    if (!sidebar) {
      const created = createSidebar();
      document.body.classList.add("ungani-admin-created-sidebar");
      wrapOnlyWhenSidebarWasCreated(created);
    } else {
      document.body.classList.add("ungani-admin-existing-sidebar");
      sidebar.setAttribute("data-ungani-existing-sidebar", VERSION);
    }

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
