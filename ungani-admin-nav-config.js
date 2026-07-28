(function () {
  // Single source of truth for the admin sidebar's groups/items, shared
  // between admin-shared.js (renderSidebar(), used by 33 admin pages via
  // requireAdmin()/renderShell()) and admin-home.html (which has its own
  // much richer bespoke shell - search/notifications/chat bell/quick-create/
  // profile panel - and deliberately does NOT move onto admin-shared.js's
  // renderShell(), the same reasoning that kept client.html on its own
  // shell during the client-side sidebar unification). Loading THIS file
  // has zero side effects - it only exposes plain data - so both pages can
  // render the identical group/item list in their own existing markup/CSS
  // without drifting apart again, which is exactly the bug (7+ different
  // admin sidebar architectures found across 29 pages) this file exists to
  // prevent a recurrence of.
  //
  // Each item's `key` doubles as admin-shared.js's translation-lookup key
  // (see its `translations.en/sw` dict) - admin-home.html and any other
  // non-i18n-aware renderer should use `label` (always English) instead.
  // `activeKey` is kept distinct from `key` for a few legacy items (e.g.
  // registrations -> "admin-main", not "registrations") purely to avoid
  // breaking existing pages' `renderSidebar({ activeKey: ... })` calls -
  // admin-shared.js's active-link check already matches EITHER field.
  //
  // Each group has a `collapsible` flag, mirroring the client-side
  // ungani-nav-config.js pattern exactly. Main/Operations stay always-
  // expanded (core, frequent); Business defaults expanded too (still very
  // frequently used) while Support/Account/System default collapsed.

  function getSidebarGroups() {
    return [
      {
        key: "main",
        titleKey: "navMain",
        title: "Main",
        collapsible: false,
        items: [
          { key: "adminHome", href: "admin-home.html", icon: "🏠", label: "Dashboard", activeKey: "admin-home" }
        ]
      },
      {
        key: "operations",
        titleKey: "navOperations",
        title: "Operations",
        collapsible: false,
        items: [
          { key: "registrations", href: "admin.html", icon: "📝", label: "Client Registrations", activeKey: "admin-main" },
          { key: "clientProfiles", href: "admin-profiles.html", icon: "🏢", label: "Client Profiles", activeKey: "admin-profiles" },
          { key: "onboarding", href: "admin-onboarding.html", icon: "🧭", label: "Client Onboarding", activeKey: "admin-onboarding" },
          { key: "sections", href: "sections.html", icon: "🧩", label: "Business Types & Sections", activeKey: "admin-sections" },
          { key: "users", href: "users.html", icon: "🔐", label: "Users & Permissions", activeKey: "admin-users" },
          { key: "tasks", href: "admin-tasks.html", icon: "✅", label: "Tasks", activeKey: "admin-tasks" },
          { key: "calendar", href: "admin-calendar.html", icon: "📅", label: "Calendar", activeKey: "admin-calendar" }
        ]
      },
      {
        key: "business",
        titleKey: "navBusiness",
        title: "Business",
        collapsible: true,
        defaultExpanded: true,
        items: [
          { key: "money", href: "admin-money.html", icon: "💰", label: "Money Records", activeKey: "admin-money" },
          { key: "itemsAssets", href: "admin-items.html", icon: "📦", label: "Assets", activeKey: "admin-items" },
          { key: "peopleStaff", href: "admin-people.html", icon: "🧑‍💼", label: "People", activeKey: "admin-people" },
          { key: "branches", href: "admin-branches.html", icon: "🏬", label: "Branches", activeKey: "admin-branches" },
          { key: "records", href: "admin-records.html", icon: "📋", label: "Business Records", activeKey: "admin-records" },
          { key: "documents", href: "admin-documents.html", icon: "📁", label: "Documents", activeKey: "admin-documents" },
          { key: "reports", href: "admin-reports.html", icon: "📄", label: "Reports", activeKey: "admin-reports" },
          { key: "charts", href: "admin-charts.html", icon: "📊", label: "System Analytics", activeKey: "admin-charts" }
        ]
      },
      {
        key: "support",
        titleKey: "navSupport",
        title: "Support",
        collapsible: true,
        defaultExpanded: false,
        items: [
          { key: "support", href: "support.html", icon: "🛟", label: "Support Desk", activeKey: "admin-support" },
          { key: "adminChat", href: "admin-chat.html", icon: "💬", label: "Client Chat", activeKey: "admin-chat" },
          { key: "notifications", href: "admin-notifications.html", icon: "🔔", label: "Notifications", activeKey: "admin-notifications" },
          { key: "notices", href: "notices.html", icon: "📢", label: "Notices", activeKey: "admin-notices" }
        ]
      },
      {
        key: "account",
        titleKey: "navAccount",
        title: "Account",
        collapsible: true,
        defaultExpanded: false,
        items: [
          { key: "billing", href: "admin-billing.html", icon: "💳", label: "Billing", activeKey: "admin-billing" },
          { key: "packages", href: "admin-subscriptions.html", icon: "🗃️", label: "Packages", activeKey: "admin-subscriptions" },
          { key: "paymentProofs", href: "admin-payment-proofs.html", icon: "🧾", label: "Payment Proofs", activeKey: "admin-payment-proofs" },
          { key: "upgradeRequests", href: "admin-upgrade-requests.html", icon: "⬆️", label: "Upgrade Requests", activeKey: "admin-upgrade-requests" },
          { key: "billingAutomation", href: "admin-billing-automation.html", icon: "⚡", label: "Billing Automation", activeKey: "admin-billing-automation" },
          { key: "billingReminders", href: "admin-billing-reminders.html", icon: "⏰", label: "Billing Reminders", activeKey: "admin-billing-reminders" },
          { key: "adminSettings", href: "admin-settings.html", icon: "⚙️", label: "Settings", activeKey: "admin-settings" }
        ]
      },
      {
        key: "system",
        titleKey: "navSystem",
        title: "System",
        collapsible: true,
        defaultExpanded: false,
        items: [
          { key: "healthCheck", href: "admin-health.html", icon: "❤️", label: "System Health", activeKey: "admin-health" },
          { key: "auditLogs", href: "admin-audit-logs.html", icon: "📜", label: "Audit Logs", activeKey: "admin-audit-logs" },
          { key: "emailQueue", href: "admin-email-queue.html", icon: "✉️", label: "Email Queue", activeKey: "admin-email-queue" },
          { key: "smartChecks", href: "admin-smart-checks.html", icon: "🧠", label: "Smart Checks", activeKey: "admin-smart-checks" },
          { key: "launchReadiness", href: "admin-launch.html", icon: "🚀", label: "Launch Readiness", activeKey: "admin-launch" },
          { key: "portal", href: "portal.html", icon: "🌐", label: "Portal", activeKey: "portal" }
        ]
      }
    ];
  }

  window.UnganiAdminNavConfig = {
    getSidebarGroups: getSidebarGroups
  };
})();
