(function () {
  // Single source of truth for the client sidebar's groups/items, shared
  // between client-shared.js (renderSidebarNav(), used by 19+ my-*.html
  // pages via initPage()) and client.html (which has its own bespoke
  // shell and deliberately does NOT load client-shared.js - it has its
  // own separately-built search/notifications/Quick Add/team-chat, and
  // client-shared.js has auto-initializing side effects on load that
  // would risk double-firing those). Loading THIS file has zero side
  // effects - it only exposes plain data plus one pure helper - so both
  // pages can render the identical group/item list in their own existing
  // markup/CSS without the two ever drifting apart again, which is
  // exactly the bug this file exists to prevent a recurrence of.
  //
  // Each group has a `collapsible` flag. Non-collapsible groups (Main,
  // Operations) are the daily-use core and always render fully expanded.
  // Collapsible groups render a clickable header that shows/hides its
  // items - `defaultExpanded` is the fallback state before any per-user
  // localStorage preference or "I'm currently on a page inside this
  // group" override is applied (both handled by each page's own render
  // code, not here - this file only supplies the data and the flag).

  const INTEGRATIONS_ELIGIBLE_BUSINESS_TYPE_KEYS = ["logistics", "real_estate", "warehouse"];

  function isIntegrationsEligible(tenant) {
    if (!window.UnganiBusinessConfig || typeof UnganiBusinessConfig.resolve !== "function") {
      return false;
    }

    const resolved = UnganiBusinessConfig.resolve(tenant);
    return !!(resolved && INTEGRATIONS_ELIGIBLE_BUSINESS_TYPE_KEYS.indexOf(resolved.key) !== -1);
  }

  function getSidebarGroups(tenant) {
    const operationsItems = [
      ["money", "my-money.html", "💰", "Money Records"],
      ["records", "my-records.html", "🗂️", "Business Records"],
      ["items", "my-items.html", "🏷️", "Items / Assets / Stock"],
      ["people", "my-people.html", "👥", "People"],
      ["tasks", "my-tasks.html", "✅", "Tasks / Follow-ups"],
      ["calendar", "my-calendar.html", "📅", "Calendar"],
      ["documents", "my-documents.html", "📄", "Documents"]
    ];

    if (isIntegrationsEligible(tenant)) {
      operationsItems.push(["integrations", "my-integrations.html", "🛰️", "Integrations"]);
    }

    return [
      {
        key: "main",
        title: "Main",
        collapsible: false,
        items: [
          ["dashboard", "client.html", "🏠", "Dashboard"],
          ["overview", "my-overview.html", "📌", "Overview"],
          ["notifications", "client-notifications.html", "🔔", "Notifications"],
          ["activity", "my-activity.html", "🕒", "Activity Feed"],
          ["charts", "my-charts.html", "📊", "Charts"]
        ]
      },
      {
        key: "operations",
        title: "Operations",
        collapsible: false,
        items: operationsItems
      },
      {
        key: "support",
        title: "Support",
        collapsible: true,
        defaultExpanded: true,
        items: [
          ["support", "my-support.html", "🛟", "Support Issues"],
          ["notices", "my-notices.html", "🔔", "Notices"],
          ["chat", "my-chat.html", "💬", "Chat with UNGANI"],
          ["team-chat", "my-team-chat.html", "👨‍👩‍👧‍👦", "Team Chat"]
        ]
      },
      {
        key: "reports-account",
        title: "Reports & Account",
        collapsible: true,
        defaultExpanded: false,
        items: [
          ["reports", "reports.html", "📑", "Reports"],
          ["print-report", "print-report.html", "🖨️", "Print Report"],
          ["profile", "my-profile.html", "🏢", "Business Profile"],
          ["account", "account.html", "⚙️", "Account Settings"],
          ["my-settings", "my-settings.html", "🔧", "My Settings"]
        ]
      },
      {
        key: "security-team",
        title: "Security & Team",
        collapsible: true,
        defaultExpanded: false,
        items: [
          ["security", "my-security.html", "🔐", "Security & Data"],
          ["team-access", "my-team-access.html", "🧑‍🤝‍🧑", "Team Access"],
          ["recently-deleted", "my-recently-deleted.html", "🗑️", "Recently Deleted"]
        ]
      },
      {
        key: "billing-setup",
        title: "Billing & Setup",
        collapsible: true,
        defaultExpanded: false,
        items: [
          ["package", "my-package.html", "💼", "Package"],
          ["billing", "my-billing.html", "🧾", "Billing"],
          ["account-status", "my-account-status.html", "🔎", "Account Status"],
          ["onboarding", "my-onboarding.html", "🚀", "Onboarding"],
          ["my-tools", "my-tools.html", "🧰", "My Tools"]
        ]
      }
    ];
  }

  window.UnganiNavConfig = {
    getSidebarGroups: getSidebarGroups,
    isIntegrationsEligible: isIntegrationsEligible
  };
})();
