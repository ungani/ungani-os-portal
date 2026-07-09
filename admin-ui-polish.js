(function () {
  const adminPages = {
    "admin-home.html": "Command Center",
    "admin.html": "Registrations",
    "admin-reports.html": "Reports",
    "admin-onboarding.html": "Onboarding",
    "admin-billing.html": "Billing",
    "admin-subscriptions.html": "Subscriptions",
    "admin-upgrade-requests.html": "Upgrade Requests",
    "admin-branches.html": "Branches",
    "admin-health.html": "System Health",
    "admin-email-queue.html": "Email Queue",
    "admin-payment-proofs.html": "Payment Proofs",
    "support.html": "Support Issues"
  };

  window.addEventListener("load", function () {
    addAdminModeBadge();
    addAdminQuickMenu();
    polishAdminLinks();
  });

  function addAdminModeBadge() {
    if (document.getElementById("unganiAdminModeBadge")) return;

    const badge = document.createElement("div");
    badge.id = "unganiAdminModeBadge";
    badge.innerHTML = `<strong>Admin Mode</strong><span>UNGANI OS</span>`;

    badge.style.position = "fixed";
    badge.style.right = "18px";
    badge.style.bottom = "18px";
    badge.style.zIndex = "9998";
    badge.style.display = "flex";
    badge.style.gap = "8px";
    badge.style.alignItems = "center";
    badge.style.padding = "10px 13px";
    badge.style.borderRadius = "999px";
    badge.style.background = "rgba(6,28,61,0.94)";
    badge.style.color = "white";
    badge.style.border = "1px solid rgba(212,166,58,0.35)";
    badge.style.boxShadow = "0 18px 44px rgba(0,0,0,0.28)";
    badge.style.fontFamily = "Inter, Arial, sans-serif";
    badge.style.fontSize = "12px";

    const span = badge.querySelector("span");
    if (span) span.style.opacity = ".72";

    document.body.appendChild(badge);
  }

  function addAdminQuickMenu() {
    if (document.getElementById("unganiAdminQuickMenu")) return;

    const wrap = document.createElement("div");
    wrap.id = "unganiAdminQuickMenu";

    wrap.innerHTML = `
      <button id="unganiAdminQuickToggle" type="button">Admin Menu</button>
      <div id="unganiAdminQuickPanel">
        ${Object.keys(adminPages).map(page => `
          <a href="${page}">${adminPages[page]}</a>
        `).join("")}
      </div>
    `;

    document.body.appendChild(wrap);

    const toggle = document.getElementById("unganiAdminQuickToggle");
    const panel = document.getElementById("unganiAdminQuickPanel");

    wrap.style.position = "fixed";
    wrap.style.right = "18px";
    wrap.style.top = "18px";
    wrap.style.zIndex = "9999";
    wrap.style.fontFamily = "Inter, Arial, sans-serif";

    toggle.style.border = "0";
    toggle.style.borderRadius = "999px";
    toggle.style.padding = "11px 15px";
    toggle.style.background = "#D4A63A";
    toggle.style.color = "#061C3D";
    toggle.style.fontWeight = "950";
    toggle.style.cursor = "pointer";
    toggle.style.boxShadow = "0 18px 44px rgba(0,0,0,0.24)";

    panel.style.display = "none";
    panel.style.marginTop = "10px";
    panel.style.width = "240px";
    panel.style.background = "rgba(6,28,61,0.97)";
    panel.style.border = "1px solid rgba(212,166,58,0.30)";
    panel.style.borderRadius = "22px";
    panel.style.padding = "10px";
    panel.style.boxShadow = "0 24px 70px rgba(0,0,0,0.35)";

    panel.querySelectorAll("a").forEach(function (a) {
      a.style.display = "block";
      a.style.color = "white";
      a.style.textDecoration = "none";
      a.style.padding = "11px 12px";
      a.style.borderRadius = "14px";
      a.style.fontWeight = "850";
      a.style.fontSize = "13px";
      a.onmouseenter = function () {
        a.style.background = "rgba(212,166,58,0.16)";
      };
      a.onmouseleave = function () {
        a.style.background = "transparent";
      };
    });

    toggle.addEventListener("click", function () {
      panel.style.display = panel.style.display === "none" ? "block" : "none";
    });
  }

  function polishAdminLinks() {
    document.querySelectorAll("a[href]").forEach(function (link) {
      const href = String(link.getAttribute("href") || "").toLowerCase();

      if (
        href.includes("admin") ||
        href.includes("support.html") ||
        href.includes("billing") ||
        href.includes("reports")
      ) {
        link.style.cursor = "pointer";
      }
    });
  }
})();
