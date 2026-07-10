(function () {
  const VERSION = "portal14z";

  function injectContrastStyles() {
    const old = document.getElementById("ungani-admin-dark-contrast-fix");
    if (old) old.remove();

    const style = document.createElement("style");
    style.id = "ungani-admin-dark-contrast-fix";

    style.textContent = `
      body.ungani-admin-page-polished,
      body.ungani-admin-page-polished main,
      body.ungani-admin-page-polished .main,
      body.ungani-admin-page-polished .content,
      body.ungani-admin-page-polished .admin-content,
      body.ungani-admin-page-polished .page-content {
        color: #FFFFFF !important;
      }

      body.ungani-admin-page-polished h1,
      body.ungani-admin-page-polished h2,
      body.ungani-admin-page-polished h3,
      body.ungani-admin-page-polished h4,
      body.ungani-admin-page-polished h5,
      body.ungani-admin-page-polished h6,
      body.ungani-admin-page-polished .title,
      body.ungani-admin-page-polished .page-title,
      body.ungani-admin-page-polished .card-title,
      body.ungani-admin-page-polished .section-title {
        color: #FFFFFF !important;
        opacity: 1 !important;
        text-shadow: none !important;
      }

      body.ungani-admin-page-polished p,
      body.ungani-admin-page-polished span,
      body.ungani-admin-page-polished div,
      body.ungani-admin-page-polished label,
      body.ungani-admin-page-polished small,
      body.ungani-admin-page-polished td,
      body.ungani-admin-page-polished li {
        color: rgba(255, 255, 255, 0.86) !important;
        opacity: 1 !important;
      }

      body.ungani-admin-page-polished .muted,
      body.ungani-admin-page-polished .hint,
      body.ungani-admin-page-polished .subtitle,
      body.ungani-admin-page-polished .description,
      body.ungani-admin-page-polished .safe-note,
      body.ungani-admin-page-polished .note,
      body.ungani-admin-page-polished .help-text {
        color: rgba(255, 255, 255, 0.72) !important;
        opacity: 1 !important;
      }

      body.ungani-admin-page-polished strong,
      body.ungani-admin-page-polished b,
      body.ungani-admin-page-polished .value,
      body.ungani-admin-page-polished .number,
      body.ungani-admin-page-polished .count,
      body.ungani-admin-page-polished .metric-value {
        color: #FFFFFF !important;
        opacity: 1 !important;
      }

      body.ungani-admin-page-polished .label,
      body.ungani-admin-page-polished .metric-label,
      body.ungani-admin-page-polished .stat-label,
      body.ungani-admin-page-polished th {
        color: #F0C85A !important;
        opacity: 1 !important;
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
      body.ungani-admin-page-polished .package-card,
      body.ungani-admin-page-polished .client-card {
        background:
          linear-gradient(145deg, rgba(6, 28, 61, 0.96), rgba(10, 37, 79, 0.90)) !important;
        color: #FFFFFF !important;
        border: 1px solid rgba(212, 166, 58, 0.18) !important;
        opacity: 1 !important;
      }

      body.ungani-admin-page-polished .hero,
      body.ungani-admin-page-polished .header,
      body.ungani-admin-page-polished .topbar,
      body.ungani-admin-page-polished .page-header {
        background:
          linear-gradient(135deg, rgba(6, 28, 61, 0.98), rgba(10, 37, 79, 0.94)) !important;
        color: #FFFFFF !important;
        border: 1px solid rgba(212, 166, 58, 0.18) !important;
      }

      body.ungani-admin-page-polished table,
      body.ungani-admin-page-polished tbody,
      body.ungani-admin-page-polished tr,
      body.ungani-admin-page-polished td {
        color: rgba(255, 255, 255, 0.86) !important;
        opacity: 1 !important;
      }

      body.ungani-admin-page-polished input,
      body.ungani-admin-page-polished select,
      body.ungani-admin-page-polished textarea {
        color: #FFFFFF !important;
        background: rgba(255, 255, 255, 0.08) !important;
        border: 1px solid rgba(212, 166, 58, 0.26) !important;
      }

      body.ungani-admin-page-polished input::placeholder,
      body.ungani-admin-page-polished textarea::placeholder {
        color: rgba(255, 255, 255, 0.55) !important;
        opacity: 1 !important;
      }

      body.ungani-admin-page-polished button,
      body.ungani-admin-page-polished .btn,
      body.ungani-admin-page-polished .button,
      body.ungani-admin-page-polished a.button {
        opacity: 1 !important;
        color: inherit;
      }

      body.ungani-admin-page-polished button:not(.ungani-admin-floating-menu-fix),
      body.ungani-admin-page-polished .btn,
      body.ungani-admin-page-polished .button {
        border-radius: 14px !important;
        font-weight: 900 !important;
      }

      body.ungani-admin-page-polished a {
        opacity: 1 !important;
      }

      body.ungani-admin-page-polished a:not(.ungani-admin-side-link):not(.ungani-admin-nav-polished) {
        color: #F0C85A !important;
      }

      body.ungani-admin-page-polished .filter button,
      body.ungani-admin-page-polished .filters button,
      body.ungani-admin-page-polished .tabs button,
      body.ungani-admin-page-polished .tab,
      body.ungani-admin-page-polished .pill {
        color: #061C3D !important;
        background: #FFFFFF !important;
        border: 1px solid rgba(212, 166, 58, 0.26) !important;
      }

      body.ungani-admin-page-polished .filter button.active,
      body.ungani-admin-page-polished .filters button.active,
      body.ungani-admin-page-polished .tabs button.active,
      body.ungani-admin-page-polished .tab.active,
      body.ungani-admin-page-polished .pill.active {
        color: #061C3D !important;
        background: linear-gradient(135deg, #D4A63A, #F0C85A) !important;
      }
    `;

    document.head.appendChild(style);
    document.body.setAttribute("data-ungani-dark-contrast-fix", VERSION);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", injectContrastStyles);
  } else {
    injectContrastStyles();
  }
})();
