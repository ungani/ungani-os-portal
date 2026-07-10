(function () {
  const VERSION = "portal14ae";

  function injectBillingTheme() {
    const old = document.getElementById("ungani-admin-billing-theme-fix");
    if (old) old.remove();

    const style = document.createElement("style");
    style.id = "ungani-admin-billing-theme-fix";

    style.textContent = `
      body {
        background:
          radial-gradient(circle at top left, rgba(212, 166, 58, 0.16), transparent 34%),
          radial-gradient(circle at top right, rgba(255, 255, 255, 0.07), transparent 28%),
          linear-gradient(135deg, #03142E 0%, #061C3D 46%, #071B36 100%) !important;
        color: #FFFFFF !important;
      }

      body,
      main,
      .main,
      .content,
      .admin-content,
      .page-content,
      .container {
        color: #FFFFFF !important;
      }

      h1, h2, h3, h4, h5, h6,
      .title,
      .page-title,
      .card-title,
      .section-title {
        color: #FFFFFF !important;
        opacity: 1 !important;
      }

      p, span, div, label, small, td, li {
        color: rgba(255, 255, 255, 0.88) !important;
        opacity: 1 !important;
      }

      .muted,
      .hint,
      .subtitle,
      .description,
      .help-text,
      .note {
        color: rgba(255, 255, 255, 0.72) !important;
        opacity: 1 !important;
      }

      strong,
      b,
      .value,
      .number,
      .count,
      .metric-value {
        color: #FFFFFF !important;
        opacity: 1 !important;
      }

      .label,
      .metric-label,
      .stat-label,
      th {
        color: #F0C85A !important;
        opacity: 1 !important;
      }

      .card,
      .panel,
      .box,
      .admin-card,
      .admin-panel,
      .content-card,
      .table-card,
      .billing-card,
      .stat-card,
      .summary-card,
      section {
        background:
          linear-gradient(145deg, rgba(6, 28, 61, 0.96), rgba(10, 37, 79, 0.90)) !important;
        color: #FFFFFF !important;
        border-color: rgba(212, 166, 58, 0.18) !important;
        opacity: 1 !important;
      }

      header,
      .header,
      .topbar,
      .page-header,
      .hero {
        background:
          linear-gradient(135deg, rgba(6, 28, 61, 0.98), rgba(10, 37, 79, 0.94)) !important;
        color: #FFFFFF !important;
        border-color: rgba(212, 166, 58, 0.20) !important;
      }

      table,
      tbody,
      tr,
      td {
        background: rgba(6, 28, 61, 0.76) !important;
        color: rgba(255, 255, 255, 0.88) !important;
        opacity: 1 !important;
      }

      th {
        background: rgba(212, 166, 58, 0.16) !important;
        color: #F0C85A !important;
        font-weight: 900 !important;
      }

      td,
      th {
        border-bottom: 1px solid rgba(255, 255, 255, 0.10) !important;
      }

      input,
      select,
      textarea {
        background: rgba(255, 255, 255, 0.08) !important;
        color: #FFFFFF !important;
        border: 1px solid rgba(212, 166, 58, 0.28) !important;
      }

      input::placeholder,
      textarea::placeholder {
        color: rgba(255, 255, 255, 0.55) !important;
        opacity: 1 !important;
      }

      select option {
        background: #061C3D !important;
        color: #FFFFFF !important;
      }

      button,
      .btn,
      .button,
      a.button {
        opacity: 1 !important;
        border-radius: 14px !important;
        font-weight: 900 !important;
      }

      a {
        opacity: 1 !important;
      }

      a:not(.nav-link):not(.ungani-admin-side-link):not(.ungani-admin-nav-polished) {
        color: #F0C85A !important;
      }

      .primary,
      .btn-primary,
      button.primary {
        background: linear-gradient(135deg, #D4A63A, #F0C85A) !important;
        color: #061C3D !important;
      }

      .sidebar,
      .admin-sidebar,
      aside.sidebar,
      aside.admin-sidebar {
        background:
          linear-gradient(180deg, rgba(3, 20, 46, 0.99), rgba(6, 28, 61, 0.99)) !important;
        color: #FFFFFF !important;
        border-right: 1px solid rgba(212, 166, 58, 0.18) !important;
      }

      .sidebar a,
      .admin-sidebar a,
      aside.sidebar a,
      aside.admin-sidebar a {
        color: rgba(255, 255, 255, 0.86) !important;
      }

      .sidebar a:hover,
      .admin-sidebar a:hover,
      .sidebar a.active,
      .admin-sidebar a.active {
        color: #FFFFFF !important;
      }

      body[data-ungani-billing-theme-fix="${VERSION}"] .ungani-admin-floating-menu-fix {
        transition: 0.18s ease !important;
      }

      @media (min-width: 781px) {
        body[data-ungani-billing-theme-fix="${VERSION}"] .ungani-admin-floating-menu-fix {
          display: none !important;
        }
      }

      @media (max-width: 780px) {
        body[data-ungani-billing-theme-fix="${VERSION}"] .ungani-admin-floating-menu-fix {
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
    document.body.setAttribute("data-ungani-billing-theme-fix", VERSION);
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
    injectBillingTheme();
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
