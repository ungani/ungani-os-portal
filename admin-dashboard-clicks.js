(function () {
  const routes = [
    {
      href: "admin-health.html",
      keywords: ["system health", "business health", "health", "errors", "warnings", "system status"]
    },
    {
      href: "support.html",
      keywords: ["support issues", "client support", "support", "urgent issue", "issues"]
    },
    {
      href: "admin-billing.html",
      keywords: ["billing", "payments", "payment", "invoices", "unpaid", "paid"]
    },
    {
      href: "admin-payment-proofs.html",
      keywords: ["payment proofs", "proofs", "proof upload", "uploaded proof"]
    },
    {
      href: "admin-reports.html",
      keywords: ["reports", "reporting", "insights", "overview", "activity"]
    },
    {
      href: "admin-onboarding.html",
      keywords: ["onboarding", "setup progress", "checklist"]
    },
    {
      href: "admin-branches.html",
      keywords: ["branches", "branch", "multi branch", "locations"]
    },
    {
      href: "admin-subscriptions.html",
      keywords: ["subscriptions", "subscription", "packages", "package", "plans", "plan"]
    },
    {
      href: "admin-upgrade-requests.html",
      keywords: ["upgrade requests", "upgrade request", "upgrades", "upgrade"]
    },
    {
      href: "admin-email-queue.html",
      keywords: ["email queue", "emails", "queued email", "mail queue"]
    },
    {
      href: "admin.html",
      keywords: ["pending registrations", "pending registration", "registrations", "registration approval", "approved clients", "clients"]
    }
  ];

  const cardSelectors = [
    ".kpi-card",
    ".summary-card",
    ".stat-card",
    ".metric-card",
    ".dashboard-card",
    ".quick-action",
    ".tile",
    ".panel",
    ".card",
    "[class*='kpi']",
    "[class*='summary']",
    "[class*='stat']",
    "[class*='metric']",
    "[class*='dashboard-card']"
  ];

  window.addEventListener("load", function () {
    runSoon();
  });

  function runSoon() {
    setTimeout(makeAdminCardsClickable, 300);
    setTimeout(makeAdminCardsClickable, 1200);
    setTimeout(makeAdminCardsClickable, 2500);
  }

  function makeAdminCardsClickable() {
    const candidates = getSafeCardCandidates();

    candidates.forEach(function (el) {
      if (!el || el.dataset.adminClickReady === "true") return;

      const text = getCleanText(el);

      if (!text) return;

      const route = findBestRoute(text);

      if (!route) return;

      el.dataset.adminClickReady = "true";
      el.dataset.adminTarget = route.href;

      el.style.cursor = "pointer";
      el.style.transition = "0.2s ease";

      el.addEventListener("click", function (event) {
        if (event.target.closest("a, button, input, select, textarea, label")) {
          return;
        }

        event.preventDefault();
        event.stopPropagation();

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

  function getSafeCardCandidates() {
    const all = [];

    cardSelectors.forEach(function (selector) {
      document.querySelectorAll(selector).forEach(function (el) {
        if (!all.includes(el)) {
          all.push(el);
        }
      });
    });

    return all.filter(function (el) {
      if (!isVisibleBox(el)) return false;
      if (el.closest("#unganiAdminQuickMenu")) return false;
      if (el.closest("#unganiAdminModeBadge")) return false;

      /*
        Important:
        Skip large parent cards/containers that contain smaller cards.
        This prevents one big parent area from sending every click to admin.html.
      */
      if (containsAnotherCard(el)) return false;

      const text = getCleanText(el);

      if (!text) return false;

      /*
        Skip very large text containers because they usually contain the whole dashboard.
      */
      if (text.length > 420) return false;

      return !!findBestRoute(text);
    });
  }

  function containsAnotherCard(el) {
    for (let i = 0; i < cardSelectors.length; i++) {
      const selector = cardSelectors[i];
      const children = el.querySelectorAll(selector);

      for (let j = 0; j < children.length; j++) {
        if (children[j] !== el && isVisibleBox(children[j])) {
          return true;
        }
      }
    }

    return false;
  }

  function isVisibleBox(el) {
    const rect = el.getBoundingClientRect();

    if (rect.width < 100 || rect.height < 50) return false;

    const style = window.getComputedStyle(el);

    if (style.display === "none" || style.visibility === "hidden" || style.opacity === "0") {
      return false;
    }

    return true;
  }

  function findBestRoute(text) {
    const clean = normalizeText(text);
    let best = null;
    let bestScore = 0;

    routes.forEach(function (route) {
      let score = 0;

      route.keywords.forEach(function (keyword) {
        const key = normalizeText(keyword);

        if (clean === key) {
          score += 100;
        } else if (clean.includes(key)) {
          score += 20 + key.length;
        }
      });

      if (score > bestScore) {
        bestScore = score;
        best = route;
      }
    });

    if (bestScore <= 0) return null;

    return best;
  }

  function getCleanText(el) {
    return normalizeText(el.innerText || el.textContent || "");
  }

  function normalizeText(value) {
    return String(value || "")
      .toLowerCase()
      .replace(/[^\w\s/-]/g, " ")
      .replace(/\s+/g, " ")
      .trim();
  }
})();
