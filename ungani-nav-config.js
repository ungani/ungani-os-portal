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
  // Operations, Finance, Sales, Inventory) are the daily-use core and
  // always render fully expanded. Collapsible groups render a clickable
  // header that shows/hides its items - `defaultExpanded` is the
  // fallback state before any per-user
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
    // Split from one flat "Operations" list into four purpose-based
    // groups once enough modules existed (Quotations/Orders/Customer
    // Invoices, Stock Tracking/Price Lists, Debtors & Payables) that a
    // single list stopped being scannable. Finance is kept separate from
    // Sales deliberately - Money is bookkeeping (what actually happened),
    // Sales is customer-facing document generation (what you're
    // proposing/billing) - conflating them was the actual clarity
    // problem being fixed here. All four stay non-collapsible, matching
    // the pre-existing "daily-use core stays always visible" principle
    // Main/Operations already used.

    const operationsItems = [
      ["people", "my-people.html", "users", "People"],
      ["records", "my-records.html", "clipboard-list", "Business Records"],
      ["tasks", "my-tasks.html", "square-check-big", "Tasks / Follow-ups"],
      ["calendar", "my-calendar.html", "calendar", "Calendar"],
      ["documents", "my-documents.html", "file-text", "Documents"]
    ];

    if (isIntegrationsEligible(tenant)) {
      operationsItems.push(["integrations", "my-integrations.html", "satellite", "Integrations"]);
    }

    const financeItems = [
      ["money", "my-money.html", "wallet", "Money Records"]
    ];

    if (tenant && tenant.debtors_payables_enabled === true) {
      financeItems.push(["debtors-payables", "my-debtors-payables.html", "notebook", "Debtors & Payables"]);
    }

    const salesItems = [
      ["quotations", "my-quotations.html", "file-pen", "Quotations"],
      ["orders", "my-orders.html", "shopping-cart", "Orders"],
      ["customer-invoices", "my-customer-invoices.html", "receipt", "Customer Invoices"]
    ];

    const inventoryItems = [
      ["items", "my-items.html", "tag", "Items / Assets / Stock"]
    ];

    if (tenant && tenant.stock_tracking_enabled === true) {
      inventoryItems.push(["stock-tracking", "my-stock-tracking.html", "package", "Stock Tracking"]);
    }

    if (tenant && tenant.price_lists_enabled === true) {
      inventoryItems.push(["price-lists", "my-price-lists.html", "wallet", "Price Lists"]);
    }

    return [
      {
        key: "main",
        title: "Main",
        collapsible: false,
        items: [
          ["dashboard", "client.html", "house", "Dashboard"],
          ["overview", "my-overview.html", "pin", "Overview"],
          ["connect", "my-connect.html", "link-2", "Shared Files"],
          ["notifications", "client-notifications.html", "bell", "Notifications"],
          ["activity", "my-activity.html", "clock", "Activity Feed"],
          ["charts", "my-charts.html", "chart-column", "Charts"]
        ]
      },
      {
        key: "operations",
        title: "Operations",
        collapsible: false,
        items: operationsItems
      },
      {
        key: "finance",
        title: "Finance",
        collapsible: false,
        items: financeItems
      },
      {
        key: "sales",
        title: "Sales",
        collapsible: false,
        items: salesItems
      },
      {
        key: "inventory",
        title: "Inventory",
        collapsible: false,
        items: inventoryItems
      },
      {
        key: "support",
        title: "Support",
        collapsible: true,
        defaultExpanded: true,
        items: [
          ["support", "my-support.html", "life-buoy", "Support Issues"],
          ["notices", "my-notices.html", "megaphone", "Notices"],
          ["chat", "my-chat.html", "message-circle", "Chat with UNGANI"],
          ["team-chat", "my-team-chat.html", "users-round", "Team Chat"]
        ]
      },
      {
        key: "reports-account",
        title: "Reports",
        collapsible: true,
        defaultExpanded: false,
        items: [
          ["reports", "reports.html", "file-text", "Reports"],
          ["print-report", "print-report.html", "printer", "Print Report"]
        ]
      },
      {
        key: "security-team",
        title: "Security & Team",
        collapsible: true,
        defaultExpanded: false,
        items: [
          ["security", "my-security.html", "shield-check", "Security & Data"],
          ["team-access", "my-team-access.html", "user-cog", "Team Access"],
          ["recently-deleted", "my-recently-deleted.html", "trash", "Recently Deleted"]
        ]
      },
      {
        key: "support-access",
        title: "UNGANI Support Access",
        collapsible: true,
        defaultExpanded: false,
        items: [
          ["support-access", "my-support-access.html", "lock-open", "Support Access"]
        ]
      },
      {
        key: "billing-setup",
        title: "Billing & Setup",
        collapsible: true,
        defaultExpanded: false,
        items: [
          ["package", "my-package.html", "briefcase", "Package"],
          ["billing", "my-billing.html", "receipt", "Billing"],
          ["account-status", "my-account-status.html", "search", "Account Status"],
          ["onboarding", "my-onboarding.html", "rocket", "Onboarding"],
          ["my-tools", "my-tools.html", "toolbox", "My Tools"]
        ]
      }
    ];
  }

  window.UnganiNavConfig = {
    getSidebarGroups: getSidebarGroups,
    isIntegrationsEligible: isIntegrationsEligible
  };
})();
