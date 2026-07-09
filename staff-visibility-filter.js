(function () {
  const SUPABASE_URL = "https://ctmtjwklltnsmfdtvqhl.supabase.co";
  const SUPABASE_KEY = "sb_publishable_jkZaWWep-cObTEv_F_kN6g_Ic85BxD9";

  const hrefSectionMap = {
    "client.html": "dashboard",
    "my-money.html": "money",
    "my-tasks.html": "tasks",
    "my-items.html": "items",
    "my-people.html": "people",
    "my-records.html": "records",
    "my-documents.html": "documents",
    "my-calendar.html": "calendar",
    "my-support.html": "support",
    "my-chat.html": "support",
    "my-team-chat.html": "support",
    "my-reports.html": "reports",
    "reports.html": "reports",
    "my-billing.html": "billing",
    "my-invoice.html": "billing",
    "my-package.html": "package",
    "my-branches.html": "branches",
    "my-team-access.html": "settings",
    "client-notifications.html": "notifications",
    "my-tools.html": "tools",
    "my-onboarding.html": "tools",
    "my-account-status.html": "tools"
  };

  const alwaysVisiblePages = [
    "client.html",
    "client-notifications.html",
    "my-tools.html",
    "my-account-status.html",
    "staff-login.html",
    "login.html"
  ];

  window.addEventListener("load", function () {
    setTimeout(runStaffVisibilityFilter, 650);
    setTimeout(runStaffVisibilityFilter, 1600);
    setTimeout(runStaffVisibilityFilter, 3000);
  });

  async function runStaffVisibilityFilter() {
    try {
      if (!window.supabase) return;

      const supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

      const userResponse = await supabaseClient.auth.getUser();
      const user = userResponse && userResponse.data ? userResponse.data.user : null;

      if (!user) return;

      const response = await supabaseClient.rpc("get_my_ungani_staff_access");

      if (response.error) {
        console.warn("Staff visibility filter:", response.error.message);
        return;
      }

      const access = response.data || {};

      if (access.is_owner === true) {
        document.body.setAttribute("data-ungani-role", "owner");
        return;
      }

      document.body.setAttribute("data-ungani-role", "staff");

      const permissions = access.permissions || {};

      hideRestrictedLinks(permissions);
      hideRestrictedDashboardCards(permissions);
      addStaffModeBadge(access);
    } catch (error) {
      console.warn("Staff visibility filter:", error.message);
    }
  }

  function hideRestrictedLinks(permissions) {
    const links = Array.from(document.querySelectorAll("a[href]"));

    links.forEach(function (link) {
      const page = getPageFromHref(link.getAttribute("href"));

      if (!page) return;

      if (alwaysVisiblePages.includes(page)) return;

      const section = hrefSectionMap[page];

      if (!section) return;

      if (canView(permissions, section)) return;

      hideElementSafely(link);
    });
  }

  function hideRestrictedDashboardCards(permissions) {
    Object.keys(hrefSectionMap).forEach(function (page) {
      if (alwaysVisiblePages.includes(page)) return;

      const section = hrefSectionMap[page];

      if (!section || canView(permissions, section)) return;

      const selectors = [
        `a[href="${page}"]`,
        `a[href="./${page}"]`,
        `a[href="/${page}"]`
      ];

      selectors.forEach(function (selector) {
        document.querySelectorAll(selector).forEach(function (el) {
          hideElementSafely(el);
        });
      });
    });
  }

  function addStaffModeBadge(access) {
    if (document.getElementById("unganiStaffModeBadge")) return;

    const badge = document.createElement("div");
    badge.id = "unganiStaffModeBadge";
    badge.innerHTML = `
      <span style="font-weight:950;">Staff Mode</span>
      <span style="opacity:.72;">${escapeHtml(access.role_key || "staff")}</span>
    `;

    badge.style.position = "fixed";
    badge.style.right = "18px";
    badge.style.bottom = "18px";
    badge.style.zIndex = "9999";
    badge.style.display = "flex";
    badge.style.gap = "8px";
    badge.style.alignItems = "center";
    badge.style.padding = "10px 13px";
    badge.style.borderRadius = "999px";
    badge.style.background = "rgba(6,28,61,0.92)";
    badge.style.color = "white";
    badge.style.border = "1px solid rgba(212,166,58,0.35)";
    badge.style.boxShadow = "0 18px 44px rgba(0,0,0,0.28)";
    badge.style.fontFamily = "Inter, Arial, sans-serif";
    badge.style.fontSize = "12px";

    document.body.appendChild(badge);
  }

  function canView(permissions, section) {
    if (!section) return true;

    const permission = permissions[section] || {};

    return permission.view === true;
  }

  function getPageFromHref(href) {
    if (!href) return "";

    if (href.startsWith("#")) return "";

    try {
      const url = new URL(href, window.location.origin);
      return (url.pathname.split("/").pop() || "").toLowerCase();
    } catch (error) {
      return href.split("?")[0].split("#")[0].split("/").pop().toLowerCase();
    }
  }

  function hideElementSafely(element) {
    if (!element) return;

    element.setAttribute("data-staff-hidden", "true");
    element.style.display = "none";
  }

  function escapeHtml(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }
})();
