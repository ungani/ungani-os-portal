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
  // Operations, Finance, Sales, Inventory, Insights & Activity) always
  // render fully expanded, ordered by real usage frequency (see the
  // reorder note above getSidebarGroups()) rather than department
  // taxonomy. Collapsible groups render a clickable
  // header that shows/hides its items - `defaultExpanded` is the
  // fallback state before any per-user
  // localStorage preference or "I'm currently on a page inside this
  // group" override is applied (both handled by each page's own render
  // code, not here - this file only supplies the data and the flag).

  const INTEGRATIONS_ELIGIBLE_BUSINESS_TYPE_KEYS = ["logistics", "real_estate", "warehouse"];

  // Sidebar Show/Hide (2026-09-10): businesses can hide items they never
  // use via a Settings panel (tenants.hidden_nav_items) - this list is
  // what's exempt from that, so a business can't accidentally hide its
  // way into a corner of core account management or lose the "quick
  // access" Favorites feature. Mirrors the server-side allow-list of
  // HIDEABLE keys in set_ungani_hidden_nav_items() (sql/sidebar-show-
  // hide.sql) - the two lists are complements of each other and must be
  // kept in sync if the sidebar structure changes. Used both to filter
  // hidden items below and by my-settings.html to decide which items get
  // a checkbox at all.
  const PROTECTED_NAV_ITEM_KEYS = [
    "dashboard", "notifications", "favorites",
    "security", "team-access",
    "package", "billing", "account-status", "onboarding", "my-tools",
    "support", "notices", "chat"
  ];

  function isIntegrationsEligible(tenant) {
    if (!window.UnganiBusinessConfig || typeof UnganiBusinessConfig.resolve !== "function") {
      return false;
    }

    const resolved = UnganiBusinessConfig.resolve(tenant);
    return !!(resolved && INTEGRATIONS_ELIGIBLE_BUSINESS_TYPE_KEYS.indexOf(resolved.key) !== -1);
  }

  function getSidebarGroups(tenant) {
    // Priority reorder (2026-09-09): items are now grouped by how often a
    // business owner actually touches them, not by department taxonomy -
    // Main is the real daily-use core (Dashboard/Team Chat/Tasks/Money/
    // People/Documents/Notifications, evidenced by which modules got CSV
    // export + duplicate-detection + the heaviest Nia FAQ coverage this
    // session), Operations/Finance/Sales/Inventory below it are regular-
    // but-less-frequent, and Insights & Activity is occasional/analytical.
    // The old flat "Operations" list was split into four purpose-based
    // groups once enough modules existed (Quotations/Orders/Customer
    // Invoices, Stock Tracking/Price Lists, Debtors & Payables) that a
    // single list stopped being scannable - that split is kept, just
    // reordered and partly emptied into Main above. All non-collapsible
    // groups can end up with zero items for a given tenant (e.g. Finance
    // now holds only the two opt-in items) - filtered out at the bottom
    // of this function rather than rendering an empty section header.

    const operationsItems = [
      ["records", "my-records.html", "clipboard-list", "Business Records"],
      ["calendar", "my-calendar.html", "calendar", "Calendar"]
    ];

    const financeItems = [];

    if (tenant && tenant.debtors_payables_enabled === true) {
      financeItems.push(["debtors-payables", "my-debtors-payables.html", "notebook", "Debtors & Payables"]);
    }

    if (tenant && tenant.expense_approval_threshold_kes != null) {
      financeItems.push(["approvals", "my-approvals.html", "shield-check", "Approvals"]);
    }

    const salesItems = [
      ["quotations", "my-quotations.html", "file-pen", "Quotations"],
      ["orders", "my-orders.html", "shopping-cart", "Orders"],
      ["customer-invoices", "my-customer-invoices.html", "banknote", "Customer Invoices"]
    ];

    // POS is opt-in (tenant.pos_enabled) same as Stock Tracking/Price
    // Lists/Debtors above - this is nav-visibility UX only, not the
    // real enforcement. The real, server-side tier gate lives inside
    // record_ungani_pos_sale()/enable_ungani_pos() - a tenant whose
    // package no longer includes POS still gets a clear rejection
    // there even if this link is still visible for a moment.
    if (tenant && tenant.pos_enabled === true) {
      salesItems.push(["quick-sale", "my-quick-sale.html", "shopping-bag", "Quick Sale"]);
    }

    const inventoryItems = [
      ["items", "my-items.html", "tag", "Items / Assets / Stock"]
    ];

    if (tenant && tenant.stock_tracking_enabled === true) {
      inventoryItems.push(["stock-tracking", "my-stock-tracking.html", "package", "Stock Tracking"]);
    }

    if (tenant && tenant.price_lists_enabled === true) {
      inventoryItems.push(["price-lists", "my-price-lists.html", "wallet", "Price Lists"]);
    }

    const insightsItems = [
      ["overview", "my-overview.html", "pin", "Overview"],
      ["charts", "my-charts.html", "chart-column", "Charts"],
      ["activity", "my-activity.html", "clock", "Activity Feed"],
      ["connect", "my-connect.html", "link-2", "Shared Files"]
    ];

    if (isIntegrationsEligible(tenant)) {
      insightsItems.push(["integrations", "my-integrations.html", "satellite", "Integrations"]);
    }

    const allGroups = [
      {
        key: "main",
        title: "Main",
        collapsible: false,
        items: [
          ["dashboard", "client.html", "house", "Dashboard"],
          ["team-chat", "my-team-chat.html", "users-round", "Team Chat"],
          ["favorites", "my-favorites.html", "star", "Favorites"],
          ["tasks", "my-tasks.html", "square-check-big", "Tasks / Follow-ups"],
          ["money", "my-money.html", "wallet", "Money Records"],
          ["people", "my-people.html", "users", "People"],
          ["documents", "my-documents.html", "file-text", "Documents"],
          ["notifications", "client-notifications.html", "bell", "Notifications"]
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
        key: "insights",
        title: "Insights & Activity",
        collapsible: false,
        items: insightsItems
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
          ["billing", "my-billing.html", "banknote", "Billing"],
          ["account-status", "my-account-status.html", "search", "Account Status"],
          ["onboarding", "my-onboarding.html", "rocket", "Onboarding"],
          ["my-tools", "my-tools.html", "toolbox", "My Tools"]
        ]
      },
      // Moved to the very bottom (2026-09-09) - previously sandwiched
      // right after the daily-use groups, ahead of Reports/Security/
      // Billing, which put a rarely-needed contact-support group above
      // genuinely more page views. defaultExpanded stays true - only its
      // position changed, not its default open/closed behavior.
      {
        key: "support",
        title: "Support",
        collapsible: true,
        defaultExpanded: true,
        items: [
          ["support", "my-support.html", "life-buoy", "Support Issues"],
          ["notices", "my-notices.html", "megaphone", "Notices"],
          ["chat", "my-chat.html", "message-circle", "Chat with UNGANI"]
        ]
      }
    ];

    // Sidebar Show/Hide - a second, independent filter applied after
    // everything above has already decided which items are candidates
    // for this tenant (feature toggles, business-type eligibility, etc).
    // Hiding an item is a user preference layered on top of whatever's
    // already available to them - it never interacts with why an item
    // was a candidate in the first place. hidden_nav_items is validated
    // server-side against the same protected list on save (see
    // set_ungani_hidden_nav_items()), so it should never actually contain
    // a protected key - this only filters, it doesn't re-check protection.
    const hiddenItems = (tenant && Array.isArray(tenant.hidden_nav_items)) ? tenant.hidden_nav_items : [];
    const visibleGroups = hiddenItems.length
      ? allGroups.map(function (group) {
          return {
            key: group.key,
            title: group.title,
            collapsible: group.collapsible,
            defaultExpanded: group.defaultExpanded,
            items: group.items.filter(function (item) { return hiddenItems.indexOf(item[0]) === -1; })
          };
        })
      : allGroups;

    // Non-collapsible groups can end up empty for a given tenant (Finance
    // now holds only the two opt-in items) - drop them rather than
    // rendering a bare section header with nothing underneath it. A
    // group can also now end up empty purely from hiding, same handling.
    return visibleGroups.filter(function (group) { return group.items && group.items.length > 0; });
  }

  window.UnganiNavConfig = {
    getSidebarGroups: getSidebarGroups,
    isIntegrationsEligible: isIntegrationsEligible,
    PROTECTED_NAV_ITEM_KEYS: PROTECTED_NAV_ITEM_KEYS
  };
})();
