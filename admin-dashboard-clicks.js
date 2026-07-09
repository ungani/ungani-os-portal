(function () {
  const adminRoutes = [
    {
      keywords: ["pending registration", "registrations", "new registration", "approve", "reject"],
      href: "admin.html"
    },
    {
      keywords: ["approved clients", "clients", "client status", "active clients", "trial clients"],
      href: "admin.html"
    },
    {
      keywords: ["support", "issue", "urgent issue", "client support"],
      href: "support.html"
    },
    {
      keywords: ["billing", "payment", "invoice", "paid", "unpaid", "proof"],
      href: "admin-billing.html"
    },
    {
      keywords: ["payment proof", "proofs", "upload proof"],
      href: "admin-payment-proofs.html"
    },
    {
      keywords: ["report", "reports", "insight", "overview", "activity"],
      href: "admin-reports.html"
    },
    {
      keywords: ["subscription", "package", "plan"],
      href: "admin-subscriptions.html"
    },
    {
      keywords: ["upgrade", "upgrade request"],
      href: "admin-upgrade-requests.html"
    },
    {
      keywords: ["onboarding", "setup progress", "checklist"],
      href: "admin-onboarding.html"
    },
    {
      keywords: ["branch", "branches", "multi branch"],
      href: "admin-branches.html"
    },
    {
      keywords: ["health", "system health", "error", "warning"],
      href: "admin-health.html"
    },
    {
      keywords: ["email", "email queue", "queued email"],
      href: "admin-email-queue.html"
    }
  ];

  window.addEventListener("load", function () {
    setTimeout(makeAdminCardsClickable, 300);
    setTimeout(makeAdminCardsClickable, 1200);
    setTimeout(makeAdminCardsClickable, 2500);
  });

  function makeAdminCardsClickable() {
    const candidates = getCardCandidates();

    candidates.forEach(function (el) {
      if (!el || el.dataset.adminClickReady === "true") return;

      const text = normalizeText(el.innerText || el.textContent || "");
      if (!text) return;

      const route = findRoute(text);
      if (!route) return;

      el.dataset.adminClickReady = "true";
      el.dataset.adminTarget = route.href;

      el.style.cursor = "pointer";
      el.style.transition = "0.2s ease";

      el.addEventListener("click", function (event) {
        if (event.target.closest("a, button, input, select, textarea, label")) {
          return;
        }

        window.location.href = route.href;
      });

      el.addEventListener("mouseenter", function () {
        el.style.transform = "translateY(-2px)";
        el.style.borderColor = "rgba(212,166,58,0.35)";
      });

      el.addEventListener("mouseleave", function () {
        el.style.transform = "";
        el.style.borderColor = "";
      });

      el.title = "Open " + route.href;
    });
  }

  function getCardCandidates() {
    const selectors = [
      ".card",
      ".kpi-card",
      ".quick-action",
      ".summary-card",
      ".stat-card",
      ".metric-card",
      ".dashboard-card",
      ".tile",
      ".box",
      ".panel",
      "[class*='card']",
      "[class*='stat']",
      "[class*='metric']",
      "[class*='summary']"
    ];

    const nodes = [];

    selectors.forEach(function (selector) {
      document.querySelectorAll(selector).forEach(function (el) {
        if (!nodes.includes(el)) nodes.push(el);
      });
    });

    return nodes.filter(function (el) {
      const rect = el.getBoundingClientRect();

      if (rect.width < 120 || rect.height < 60) return false;
      if (el.closest("#unganiAdminQuickMenu")) return false;
      if (el.closest("#unganiAdminModeBadge")) return false;

      return true;
    });
  }

  function findRoute(text) {
    for (let i = 0; i < adminRoutes.length; i++) {
      const route = adminRoutes[i];

      for (let j = 0; j < route.keywords.length; j++) {
        if (text.includes(route.keywords[j])) {
          return route;
        }
      }
    }

    return null;
  }

  function normalizeText(value) {
    return String(value || "")
      .toLowerCase()
      .replace(/\s+/g, " ")
      .trim();
  }
})();
