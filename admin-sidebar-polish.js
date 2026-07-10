(function () {
  const VERSION = "portal14w";

  const ICON_RULES = [
    { keys: ["admin-home", "home"], icon: "🏠", label: "Admin Home" },
    { keys: ["admin-launch", "launch"], icon: "🚀", label: "Launch Readiness" },
    { keys: ["admin-health", "health"], icon: "🛡️", label: "System Health" },
    { keys: ["admin-smart", "smart"], icon: "🧠", label: "Smart Checks" },

    { keys: ["admin.html", "client admin"], icon: "👥", label: "Client Admin" },
    { keys: ["client profiles", "profiles"], icon: "🏢", label: "Client Profiles" },
    { keys: ["users", "access", "team"], icon: "🔐", label: "Users & Access" },

    { keys: ["money", "income", "expense"], icon: "💰", label: "Money Records" },
    { keys: ["items", "assets", "stock"], icon: "📦", label: "Items / Assets" },
    { keys: ["people", "leads", "contacts"], icon: "👤", label: "People" },
    { keys: ["business records", "records"], icon: "🗂️", label: "Business Records" },
    { keys: ["tasks", "follow"], icon: "✅", label: "Tasks" },
    { keys: ["documents", "files"], icon: "📄", label: "Documents" },
    { keys: ["calendar", "events"], icon: "📅", label: "Calendar" },

    { keys: ["support"], icon: "💬", label: "Support" },
    { keys: ["registrations", "approvals"], icon: "📝", label: "Approvals" },
    { keys: ["notifications"], icon: "🔔", label: "Notifications" },

    { keys: ["subscriptions", "packages"], icon: "📦", label: "Subscriptions" },
    { keys: ["upgrade"], icon: "⬆️", label: "Upgrade Requests" },
    { keys: ["billing", "payments"], icon: "💳", label: "Billing" },
    { keys: ["proof"], icon: "🧾", label: "Payment Proofs" },

    { keys: ["email"], icon: "✉️", label: "Email Queue" },
    { keys: ["branches"], icon: "🏬", label: "Branches" },
    { keys: ["reports", "analytics"], icon: "📊", label: "Reports" },
    { keys: ["onboarding"], icon: "🧭", label: "Onboarding" },
    { keys: ["settings"], icon: "⚙️", label: "Settings" },

    { keys: ["login"], icon: "🚪", label: "Login" },
    { keys: ["logout"], icon: "🚪", label: "Logout" },
    { keys: ["index", "registration"], icon: "📝", label: "Registration" }
  ];

  function injectStyles() {
    const old = document.getElementById("ungani-admin-sidebar-polish-style");
    if (old) old.remove();

    const style = document.createElement("style");
    style.id = "ungani-admin-sidebar-polish-style";

    style.textContent = `
      body .sidebar,
      body .admin-sidebar,
      body aside.sidebar,
      body aside.admin-sidebar {
        background:
          linear-gradient(180deg, rgba(3, 20, 46, 0.99), rgba(6, 28, 61, 0.99)) !important;
        border-right: 1px solid rgba(212, 166, 58, 0.18) !important;
        box-shadow: 12px 0 36px rgba(0, 0, 0, 0.30) !important;
      }

      body .sidebar .brand,
      body .admin-sidebar .brand {
        border-bottom: 1px solid rgba(212, 166, 58, 0.18) !important;
      }

      body .sidebar .nav-section-title,
      body .admin-sidebar .nav-section-title,
      body .sidebar .section-title,
      body .admin-sidebar .section-title,
      body .sidebar .menu-title,
      body .admin-sidebar .menu-title {
        color: rgba(212, 166, 58, 0.90) !important;
        font-size: 11px !important;
        text-transform: uppercase !important;
        letter-spacing: 0.13em !important;
        font-weight: 900 !important;
      }

      body .sidebar a.ungani-admin-nav-polished,
      body .admin-sidebar a.ungani-admin-nav-polished {
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

      body .sidebar a.ungani-admin-nav-polished:hover,
      body .admin-sidebar a.ungani-admin-nav-polished:hover,
      body .sidebar a.ungani-admin-nav-polished.active,
      body .admin-sidebar a.ungani-admin-nav-polished.active,
      body .sidebar a.ungani-admin-nav-polished[aria-current="page"],
      body .admin-sidebar a.ungani-admin-nav-polished[aria-current="page"] {
        color: #FFFFFF !important;
        background: rgba(212, 166, 58, 0.16) !important;
        border-color: rgba(212, 166, 58, 0.36) !important;
        transform: translateX(2px) !important;
      }

      .ungani-admin-nav-icon {
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
        line-height: 1 !important;
        margin: 0 !important;
        padding: 0 !important;
      }

      .ungani-admin-nav-text {
        display: inline-flex !important;
        align-items: center !important;
        justify-content: flex-start !important;
        flex: 0 1 auto !important;
        margin: 0 !important;
        padding: 0 !important;
        min-width: 0 !important;
        text-align: left !important;
        white-space: normal !important;
      }

      body .sidebar a.ungani-admin-nav-polished:hover .ungani-admin-nav-icon,
      body .admin-sidebar a.ungani-admin-nav-polished:hover .ungani-admin-nav-icon,
      body .sidebar a.ungani-admin-nav-polished.active .ungani-admin-nav-icon,
      body .admin-sidebar a.ungani-admin-nav-polished.active .ungani-admin-nav-icon {
        background: rgba(212, 166, 58, 0.24) !important;
        border-color: rgba(212, 166, 58, 0.48) !important;
      }

      /*
        Admin Menu button fix:
        Desktop: hide it because the sidebar is already visible.
        Mobile/tablet: move it to bottom-right so it does not block notification bell or menu dots.
      */
      .ungani-admin-floating-menu-fix {
        transition: 0.18s ease !important;
      }

      @media (min-width: 781px) {
        .ungani-admin-floating-menu-fix {
          display: none !important;
        }
      }

      @media (max-width: 780px) {
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

        .ungani-admin-floating-menu-fix:hover {
          transform: translateY(-2px) !important;
        }
      }
    `;

    document.head.appendChild(style);
  }

  function cleanLabel(value) {
    return String(value || "")
      .replace(/[🏠🚀🛡️🧠👥🏢🔐💰📦👤🗂️✅📄📅💬📝🔔⬆️💳🧾✉️🏬📊🧭⚙️🚪•·]/g, "")
      .replace(/\s+/g, " ")
      .trim();
  }

  function getExistingLabel(anchor) {
    const existingText = anchor.querySelector(".ungani-admin-nav-text, .ungani-nav-text");
    if (existingText) return cleanLabel(existingText.textContent);
    return cleanLabel(anchor.textContent);
  }

  function getMeta(anchor) {
    const href = String(anchor.getAttribute("href") || "").toLowerCase();
    const label = getExistingLabel(anchor);
    const text = label.toLowerCase();
    const combined = `${href} ${text}`;

    for (const rule of ICON_RULES) {
      if (rule.keys.some((key) => combined.includes(key))) {
        return {
          icon: rule.icon,
          label: label || rule.label
        };
      }
    }

    return {
      icon: "📌",
      label: label || "Admin Link"
    };
  }

  function polishSidebar() {
    injectStyles();

    const sidebar =
      document.querySelector(".sidebar") ||
      document.querySelector(".admin-sidebar") ||
      document.querySelector("aside");

    if (!sidebar) return;

    sidebar.setAttribute("data-ungani-sidebar-polish", VERSION);

    const currentPath = window.location.pathname.split("/").pop().split("?")[0];

    sidebar.querySelectorAll("a[href]").forEach((anchor) => {
      const href = anchor.getAttribute("href") || "";

      if (
        href.startsWith("#") ||
        href.startsWith("mailto:") ||
        href.startsWith("tel:")
      ) {
        return;
      }

      const meta = getMeta(anchor);
      const hrefPath = href.split("?")[0].split("/").pop();

      anchor.classList.remove("ungani-polished-nav-link");
      anchor.classList.add("ungani-admin-nav-polished");

      if (hrefPath && currentPath && hrefPath === currentPath) {
        anchor.classList.add("active");
        anchor.setAttribute("aria-current", "page");
      }

      anchor.innerHTML = `
        <span class="ungani-admin-nav-icon">${meta.icon}</span>
        <span class="ungani-admin-nav-text">${meta.label}</span>
      `;
    });
  }

  function fixAdminMenuButton() {
    const candidates = Array.from(document.querySelectorAll("button, a"));

    candidates.forEach((el) => {
      const text = String(el.textContent || "").replace(/\s+/g, " ").trim().toLowerCase();

      if (text === "admin menu" || text.includes("admin menu")) {
        const insideSidebar = el.closest(".sidebar, .admin-sidebar, aside");
        if (insideSidebar) return;

        el.classList.add("ungani-admin-floating-menu-fix");
        el.setAttribute("data-ungani-admin-menu-fixed", VERSION);
      }
    });
  }

  function run() {
    polishSidebar();
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
