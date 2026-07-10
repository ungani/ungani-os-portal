(function () {
  const ADMIN_SIDEBAR_VERSION = "portal14u";

  const NAV_MAP = [
    { match: "admin-home.html", icon: "🏠", label: "Admin Home" },
    { match: "admin-launch.html", icon: "🚀", label: "Launch Readiness" },
    { match: "admin-health.html", icon: "🛡️", label: "System Health" },
    { match: "admin-smart-checks.html", icon: "🧠", label: "Smart Checks" },

    { match: "admin.html", icon: "👥", label: "Client Admin" },
    { match: "admin-subscriptions.html", icon: "📦", label: "Subscriptions" },
    { match: "admin-upgrade-requests.html", icon: "⬆️", label: "Upgrade Requests" },
    { match: "admin-billing.html", icon: "💳", label: "Billing" },
    { match: "admin-payment-proofs.html", icon: "🧾", label: "Payment Proofs" },

    { match: "admin-email-queue.html", icon: "✉️", label: "Email Queue" },
    { match: "admin-branches.html", icon: "🏢", label: "Branches" },
    { match: "admin-reports.html", icon: "📊", label: "Reports" },
    { match: "admin-onboarding.html", icon: "🧭", label: "Onboarding" },
    { match: "admin-settings.html", icon: "⚙️", label: "Settings" },

    { match: "login.html", icon: "🚪", label: "Login" },
    { match: "index.html", icon: "📝", label: "Registration" }
  ];

  function injectStyles() {
    if (document.getElementById("ungani-admin-sidebar-polish-style")) return;

    const style = document.createElement("style");
    style.id = "ungani-admin-sidebar-polish-style";
    style.textContent = `
      body .sidebar,
      body .admin-sidebar,
      body aside.sidebar,
      body aside.admin-sidebar {
        background:
          linear-gradient(180deg, rgba(3, 20, 46, 0.98), rgba(6, 28, 61, 0.98)) !important;
        border-right: 1px solid rgba(212, 166, 58, 0.18) !important;
        box-shadow: 12px 0 36px rgba(0, 0, 0, 0.30) !important;
      }

      body .sidebar .brand,
      body .admin-sidebar .brand {
        border-bottom: 1px solid rgba(212, 166, 58, 0.18) !important;
      }

      body .sidebar .brand h1,
      body .admin-sidebar .brand h1,
      body .sidebar h1,
      body .admin-sidebar h1 {
        color: #FFFFFF !important;
        letter-spacing: 0.6px !important;
      }

      body .sidebar .brand p,
      body .admin-sidebar .brand p {
        color: rgba(255, 255, 255, 0.64) !important;
      }

      body .sidebar img,
      body .admin-sidebar img {
        box-shadow: 0 8px 20px rgba(212, 166, 58, 0.16);
      }

      body .sidebar .nav-section-title,
      body .admin-sidebar .nav-section-title,
      body .sidebar .section-title,
      body .admin-sidebar .section-title,
      body .sidebar .menu-title,
      body .admin-sidebar .menu-title {
        color: rgba(212, 166, 58, 0.86) !important;
        font-size: 11px !important;
        text-transform: uppercase !important;
        letter-spacing: 0.13em !important;
        font-weight: 900 !important;
      }

      body .sidebar a,
      body .admin-sidebar a {
        text-decoration: none !important;
      }

      body .sidebar a.ungani-polished-nav-link,
      body .admin-sidebar a.ungani-polished-nav-link {
        display: flex !important;
        align-items: center !important;
        gap: 11px !important;
        color: rgba(255, 255, 255, 0.84) !important;
        padding: 12px 12px !important;
        border-radius: 14px !important;
        margin: 4px 0 !important;
        font-size: 14px !important;
        line-height: 1.2 !important;
        transition: 0.18s ease !important;
        border: 1px solid transparent !important;
        background: transparent !important;
        cursor: pointer !important;
      }

      body .sidebar a.ungani-polished-nav-link:hover,
      body .admin-sidebar a.ungani-polished-nav-link:hover,
      body .sidebar a.ungani-polished-nav-link.active,
      body .admin-sidebar a.ungani-polished-nav-link.active,
      body .sidebar a.ungani-polished-nav-link[aria-current="page"],
      body .admin-sidebar a.ungani-polished-nav-link[aria-current="page"] {
        color: #FFFFFF !important;
        background: rgba(212, 166, 58, 0.16) !important;
        border-color: rgba(212, 166, 58, 0.34) !important;
        transform: translateX(2px) !important;
      }

      .ungani-nav-icon {
        width: 24px;
        min-width: 24px;
        height: 24px;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        border-radius: 9px;
        background: rgba(255, 255, 255, 0.08);
        border: 1px solid rgba(212, 166, 58, 0.18);
        font-size: 13px;
      }

      .ungani-nav-text {
        display: inline-flex;
        align-items: center;
        min-width: 0;
      }

      body .sidebar a.ungani-polished-nav-link:hover .ungani-nav-icon,
      body .admin-sidebar a.ungani-polished-nav-link:hover .ungani-nav-icon,
      body .sidebar a.ungani-polished-nav-link.active .ungani-nav-icon,
      body .admin-sidebar a.ungani-polished-nav-link.active .ungani-nav-icon {
        background: rgba(212, 166, 58, 0.22);
        border-color: rgba(212, 166, 58, 0.42);
      }
    `;

    document.head.appendChild(style);
  }

  function cleanText(value) {
    return String(value || "")
      .replace(/[🏠🚀🛡️🧠👥📦⬆️💳🧾✉️🏢📊🧭⚙️🚪📝]/g, "")
      .replace(/\s+/g, " ")
      .trim();
  }

  function getNavMeta(anchor) {
    const href = anchor.getAttribute("href") || "";
    const text = cleanText(anchor.textContent);

    const byHref = NAV_MAP.find((item) => href.includes(item.match));
    if (byHref) return byHref;

    const lower = text.toLowerCase();

    if (lower.includes("home")) return { icon: "🏠", label: text || "Admin Home" };
    if (lower.includes("launch")) return { icon: "🚀", label: text || "Launch Readiness" };
    if (lower.includes("health")) return { icon: "🛡️", label: text || "System Health" };
    if (lower.includes("smart")) return { icon: "🧠", label: text || "Smart Checks" };
    if (lower.includes("client")) return { icon: "👥", label: text || "Clients" };
    if (lower.includes("subscription") || lower.includes("package")) return { icon: "📦", label: text || "Subscriptions" };
    if (lower.includes("upgrade")) return { icon: "⬆️", label: text || "Upgrade Requests" };
    if (lower.includes("billing") || lower.includes("payment")) return { icon: "💳", label: text || "Billing" };
    if (lower.includes("email")) return { icon: "✉️", label: text || "Email Queue" };
    if (lower.includes("branch")) return { icon: "🏢", label: text || "Branches" };
    if (lower.includes("report")) return { icon: "📊", label: text || "Reports" };
    if (lower.includes("setting")) return { icon: "⚙️", label: text || "Settings" };
    if (lower.includes("login") || lower.includes("logout")) return { icon: "🚪", label: text || "Login" };

    return { icon: "•", label: text || "Admin Link" };
  }

  function polishSidebar() {
    injectStyles();

    const sidebar =
      document.querySelector(".sidebar") ||
      document.querySelector(".admin-sidebar") ||
      document.querySelector("aside");

    if (!sidebar) return;

    sidebar.setAttribute("data-ungani-sidebar-polish", ADMIN_SIDEBAR_VERSION);

    const currentPath = window.location.pathname.split("/").pop();

    const anchors = sidebar.querySelectorAll("a[href]");
    anchors.forEach((anchor) => {
      const href = anchor.getAttribute("href") || "";

      if (
        href.startsWith("mailto:") ||
        href.startsWith("tel:") ||
        href.startsWith("#") ||
        anchor.dataset.unganiPolished === "true"
      ) {
        return;
      }

      const meta = getNavMeta(anchor);

      anchor.classList.add("ungani-polished-nav-link");

      const hrefPath = href.split("?")[0].split("/").pop();
      if (hrefPath && currentPath && hrefPath === currentPath) {
        anchor.classList.add("active");
        anchor.setAttribute("aria-current", "page");
      }

      anchor.innerHTML = `
        <span class="ungani-nav-icon">${meta.icon}</span>
        <span class="ungani-nav-text">${meta.label}</span>
      `;

      anchor.dataset.unganiPolished = "true";
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", polishSidebar);
  } else {
    polishSidebar();
  }
})();
