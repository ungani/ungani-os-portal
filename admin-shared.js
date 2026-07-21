(function () {
  const UNGANI_CONFIG = {
    supabaseUrl: "https://ctmtjwklltnsmfdtvqhl.supabase.co",
    supabaseAnonKey: "sb_publishable_jkZaWWep-cObTEv_F_kN6g_Ic85BxD9"
  };

  let supabaseClient = null;
  let currentAdmin = null;
  let currentAdminId = null;
  let currentTheme = localStorage.getItem("ungani_theme") || localStorage.getItem("ungani_client_theme") || "light";
  let currentLanguage = "en";

  document.documentElement.dataset.unganiTheme = currentTheme;

  const translations = {
    en: {
      navMain: "Main",
      adminHome: "Dashboard",
      mainAdmin: "Main Admin",
      portal: "Portal",
      healthCheck: "System Health",
      navOperations: "Operations",
      registrations: "Client Registrations",
      clientProfiles: "Client Profiles",
      sections: "Business Types & Sections",
      users: "Users & Permissions",
      tasks: "Tasks",
      calendar: "Calendar",
      navBusiness: "Business",
      money: "Money Records",
      itemsAssets: "Assets",
      peopleStaff: "People",
      records: "Business Records",
      documents: "Documents",
      reports: "Reports",
      charts: "System Analytics",
      navSupport: "Support",
      support: "Support Desk",
      adminChat: "Client Chat",
      notifications: "Notifications",
      notices: "Notices",
      navAccount: "Account",
      billing: "Billing",
      packages: "Packages",
      adminSettings: "Settings",
      navSystem: "System",
      auditLogs: "Audit Logs",
      refresh: "Refresh",
      logout: "Logout",
      menu: "Menu",
      loadingAdmin: "Loading UNGANI Admin...",
      checkingSession: "Please wait while we check your session.",
      adminLogin: "Admin workspace login",
      email: "Email",
      password: "Password",
      login: "Login",
      loginSuccess: "Login successful.",
      accessBlocked: "Admin Access Blocked",
      backToAdminHome: "Back to Admin Home",
      signedInAs: "Signed in as:",
      theme: "Theme",
      language: "Language",
      lightMode: "light mode",
      darkMode: "dark mode"
    },
    sw: {
      navMain: "Kuu",
      adminHome: "Dashibodi",
      mainAdmin: "Admin Kuu",
      portal: "Portal",
      healthCheck: "Afya ya Mfumo",
      navOperations: "Uendeshaji",
      registrations: "Usajili wa Wateja",
      clientProfiles: "Wasifu wa Wateja",
      sections: "Aina za Biashara na Sehemu",
      users: "Watumiaji na Ruhusa",
      tasks: "Kazi",
      calendar: "Kalenda",
      navBusiness: "Biashara",
      money: "Kumbukumbu za Fedha",
      itemsAssets: "Mali",
      peopleStaff: "Watu",
      records: "Kumbukumbu za Biashara",
      documents: "Nyaraka",
      reports: "Ripoti",
      charts: "Uchambuzi wa Mfumo",
      navSupport: "Msaada",
      support: "Dawati la Msaada",
      adminChat: "Gumzo la Mteja",
      notifications: "Arifa",
      notices: "Matangazo",
      navAccount: "Akaunti",
      billing: "Malipo",
      packages: "Vifurushi",
      adminSettings: "Mipangilio",
      navSystem: "Mfumo",
      auditLogs: "Kumbukumbu za Ukaguzi",
      refresh: "Sasisha",
      logout: "Toka",
      menu: "Menyu",
      loadingAdmin: "Inapakia Admin ya UNGANI...",
      checkingSession: "Tafadhali subiri tunapokagua session yako.",
      adminLogin: "Ingia kwenye eneo la admin",
      email: "Barua pepe",
      password: "Nenosiri",
      login: "Ingia",
      loginSuccess: "Umeingia kikamilifu.",
      accessBlocked: "Ufikiaji wa Admin Umezuiwa",
      backToAdminHome: "Rudi Admin Home",
      signedInAs: "Umeingia kama:",
      theme: "Muonekano",
      language: "Lugha",
      lightMode: "muonekano mweupe",
      darkMode: "muonekano mweusi"
    }
  };

  // Restructured 2026-07-21 to match UI-UX-MASTER-SPEC.md's 6-group admin
  // sidebar (MAIN/OPERATIONS/BUSINESS/SUPPORT/ACCOUNT/SYSTEM). "portal.html"
  // and "sections.html" aren't named in the spec's example list but are
  // real, working pages that were already linked pre-restructure - kept
  // rather than silently dropped. "Business Health"/"Today's Activity" as
  // standalone destinations and the whole "Global Controls"/"Automation
  // Rules"/"AI Settings" system-group trio are spec items with no page
  // built yet - intentionally omitted rather than linking to something
  // that 404s; add them here once those pages exist.
  //
  // Dropped "teamChat" (my-team-chat.html) - that page loads client-shared.js
  // and resolves a CLIENT tenant, not an admin destination; it had no
  // business being in the admin nav at all. Also dropped the duplicate
  // "Main Admin" link that pointed at the same admin.html href as
  // "Client Registrations" under a different label.
  const adminNavSections = [
    {
      titleKey: "navMain",
      links: [
        { key: "adminHome", href: "admin-home.html", icon: "🏠", activeKey: "admin-home" }
      ]
    },
    {
      titleKey: "navOperations",
      links: [
        { key: "registrations", href: "admin.html", icon: "📝", activeKey: "admin-main" },
        { key: "clientProfiles", href: "admin-profiles.html", icon: "🏢", activeKey: "admin-profiles" },
        { key: "sections", href: "sections.html", icon: "🧩", activeKey: "admin-sections" },
        { key: "users", href: "users.html", icon: "🔐", activeKey: "admin-users" },
        { key: "tasks", href: "admin-tasks.html", icon: "✅", activeKey: "admin-tasks" },
        { key: "calendar", href: "admin-calendar.html", icon: "📅", activeKey: "admin-calendar" }
      ]
    },
    {
      titleKey: "navBusiness",
      links: [
        { key: "money", href: "admin-money.html", icon: "💰", activeKey: "admin-money" },
        { key: "itemsAssets", href: "admin-items.html", icon: "📦", activeKey: "admin-items" },
        { key: "peopleStaff", href: "admin-people.html", icon: "🧑‍💼", activeKey: "admin-people" },
        { key: "records", href: "admin-records.html", icon: "📋", activeKey: "admin-records" },
        { key: "documents", href: "admin-documents.html", icon: "📁", activeKey: "admin-documents" },
        { key: "reports", href: "admin-reports.html", icon: "📄", activeKey: "admin-reports" },
        { key: "charts", href: "admin-charts.html", icon: "📊", activeKey: "admin-charts" }
      ]
    },
    {
      titleKey: "navSupport",
      links: [
        { key: "support", href: "support.html", icon: "🛟", activeKey: "admin-support" },
        { key: "adminChat", href: "admin-chat.html", icon: "💬", activeKey: "admin-chat" },
        { key: "notifications", href: "admin-notifications.html", icon: "🔔", activeKey: "admin-notifications" },
        { key: "notices", href: "notices.html", icon: "📢", activeKey: "admin-notices" }
      ]
    },
    {
      titleKey: "navAccount",
      links: [
        { key: "billing", href: "billing.html", icon: "💳", activeKey: "admin-billing" },
        { key: "packages", href: "admin-subscriptions.html", icon: "🗃️", activeKey: "admin-subscriptions" },
        { key: "adminSettings", href: "admin-settings.html", icon: "⚙️", activeKey: "admin-settings" }
      ]
    },
    {
      titleKey: "navSystem",
      links: [
        { key: "healthCheck", href: "admin-health.html", icon: "❤️", activeKey: "admin-health" },
        { key: "auditLogs", href: "admin-audit-logs.html", icon: "📜", activeKey: "admin-audit-logs" },
        { key: "portal", href: "portal.html", icon: "🌐", activeKey: "portal" }
      ]
    }
  ];

  function safe(value) {
    return String(value ?? "")
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;");
  }

  function cleanText(value) {
    return String(value || "N/A").replaceAll("_", " ");
  }

  function t(key) {
    return translations[currentLanguage]?.[key] || translations.en[key] || key;
  }

  function getSupabaseClient() {
    if (supabaseClient) return supabaseClient;

    if (window.getUnganiSupabaseClient) {
      supabaseClient = window.getUnganiSupabaseClient();
      if (supabaseClient) return supabaseClient;
    }

    if (!window.supabase || typeof window.supabase.createClient !== "function") {
      throw new Error("Supabase JS is not loaded. Add the Supabase CDN script before admin-shared.js.");
    }

    // persistSession/autoRefreshToken/detectSessionInUrl below are already
    // the SDK's own defaults - kept explicit only as the fallback path for
    // pages that somehow load admin-shared.js without pwa-register.js.
    supabaseClient = window.supabase.createClient(
      UNGANI_CONFIG.supabaseUrl,
      UNGANI_CONFIG.supabaseAnonKey,
      {
        auth: {
          persistSession: true,
          autoRefreshToken: true,
          detectSessionInUrl: true
        }
      }
    );

    return supabaseClient;
  }

  function injectBaseStyles() {
    if (document.getElementById("ungani-admin-shared-styles")) return;

    const style = document.createElement("style");
    style.id = "ungani-admin-shared-styles";
    style.innerHTML = `
      :root {
        --ungani-navy: #061C3D;
        --ungani-gold: #D4A63A;
        --ungani-green: #15803D;
        --ungani-red: #B91C1C;
        --ungani-orange: #C77700;
        --ungani-blue: #2563EB;

        --ungani-bg: #F5F5F3;
        --ungani-card: #FFFFFF;
        --ungani-text: #061C3D;
        --ungani-muted: #64748B;
        --ungani-border: rgba(6, 28, 61, 0.12);
        --ungani-shadow: 0 18px 45px rgba(6, 28, 61, 0.10);
      }

      html[data-ungani-theme="dark"] {
        --ungani-bg: #061426;
        --ungani-card: #0B2346;
        --ungani-text: #F5F5F3;
        --ungani-muted: #B8C3D6;
        --ungani-border: rgba(255, 255, 255, 0.12);
        --ungani-shadow: 0 18px 45px rgba(0, 0, 0, 0.28);
      }

      * {
        box-sizing: border-box;
      }

      body {
        margin: 0;
        font-family: Arial, sans-serif;
        background: var(--ungani-bg);
        color: var(--ungani-text);
      }

      .hidden {
        display: none !important;
      }

      .ungani-admin-app {
        min-height: 100vh;
        display: grid;
        grid-template-columns: 290px 1fr;
        background: var(--ungani-bg);
      }

      .ungani-admin-sidebar {
        background: var(--ungani-navy);
        color: #FFFFFF;
        padding: 22px 16px;
        position: sticky;
        top: 0;
        height: 100vh;
        overflow-y: auto;
        border-right: 1px solid rgba(255,255,255,0.08);
      }

      .ungani-brand-box {
        text-align: center;
        padding-bottom: 18px;
        border-bottom: 1px solid rgba(255,255,255,0.12);
        margin-bottom: 16px;
      }

      .ungani-brand-logo {
        width: 130px;
        max-width: 75%;
        height: auto;
        margin-bottom: 10px;
        filter: drop-shadow(0 10px 20px rgba(0,0,0,0.22));
      }

      .ungani-brand-box h2 {
        margin: 4px 0 2px;
        font-size: 20px;
      }

      .ungani-brand-box p {
        margin: 0;
        font-size: 12px;
        opacity: 0.78;
      }

      .ungani-sidebar-section-title {
        font-size: 11px;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        opacity: 0.65;
        margin: 18px 10px 8px;
      }

      .ungani-side-link {
        display: flex;
        align-items: center;
        gap: 10px;
        color: #FFFFFF;
        text-decoration: none;
        padding: 11px 12px;
        min-height: 44px;
        border-radius: 14px;
        margin-bottom: 5px;
        transition: 0.2s ease;
        font-weight: bold;
        font-size: 14px;
      }

      .ungani-side-link:hover,
      .ungani-side-link.active {
        background: rgba(212,166,58,0.18);
        color: var(--ungani-gold);
        transform: translateX(3px);
      }

      .ungani-sidebar-footer {
        margin-top: 18px;
        padding: 14px;
        border-radius: 18px;
        background: rgba(255,255,255,0.08);
        font-size: 12px;
        line-height: 1.45;
      }

      .ungani-admin-main {
        min-width: 0;
        padding: 24px;
      }

      .ungani-topbar {
        background: var(--ungani-card);
        border: 1px solid var(--ungani-border);
        border-radius: 22px;
        padding: 16px;
        display: grid;
        grid-template-columns: 1fr auto;
        gap: 14px;
        align-items: center;
        box-shadow: var(--ungani-shadow);
        margin-bottom: 18px;
        position: sticky;
        top: 16px;
        z-index: 20;
      }

      .ungani-topbar h1 {
        margin: 0 0 5px;
        font-size: 24px;
        color: var(--ungani-text);
      }

      .ungani-topbar p {
        margin: 0;
        color: var(--ungani-muted);
        font-size: 14px;
      }

      .ungani-topbar-actions {
        display: flex;
        align-items: center;
        gap: 10px;
        flex-wrap: wrap;
        justify-content: flex-end;
      }

      .ungani-admin-menu-btn {
        display: none;
        align-items: center;
        justify-content: center;
        width: 44px;
        height: 44px;
        border-radius: 12px;
        border: 1px solid var(--ungani-border);
        background: var(--ungani-card);
        color: var(--ungani-text);
        font-size: 19px;
        cursor: pointer;
        margin-bottom: 10px;
      }

      .ungani-admin-sidebar-overlay {
        display: none;
      }

      .ungani-card {
        background: var(--ungani-card);
        color: var(--ungani-text);
        border: 1px solid var(--ungani-border);
        border-radius: 22px;
        padding: 22px;
        margin-bottom: 18px;
        box-shadow: var(--ungani-shadow);
      }

      .ungani-hero-card {
        background: linear-gradient(135deg, #061C3D, #0b2b59);
        color: #FFFFFF;
        border: none;
        overflow: hidden;
        position: relative;
      }

      html[data-ungani-theme="dark"] .ungani-hero-card {
        background: linear-gradient(135deg, #0B1220, #111C33);
        border: 1px solid rgba(212,166,58,0.22);
      }

      .ungani-btn {
        position: relative;
        border: 1.5px solid transparent;
        border-radius: 12px;
        min-height: 44px;
        padding: 0 18px;
        background: var(--ungani-navy);
        color: #FFFFFF;
        font-weight: 800;
        font-size: 14px;
        font-family: inherit;
        cursor: pointer;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 8px;
        white-space: nowrap;
        text-decoration: none;
        margin: 4px 5px 4px 0;
        box-shadow: 0 10px 22px rgba(6,28,61,0.15);
        transition: transform 0.16s ease, box-shadow 0.16s ease, filter 0.16s ease, opacity 0.16s ease;
      }

      .ungani-btn:hover {
        transform: translateY(-2px);
        box-shadow: 0 16px 30px rgba(6,28,61,0.22);
        filter: brightness(1.04);
      }

      .ungani-btn:active {
        transform: translateY(0);
        box-shadow: 0 6px 14px rgba(6,28,61,0.18);
        filter: brightness(0.98);
      }

      .ungani-btn:focus-visible {
        outline: 2px solid var(--ungani-gold);
        outline-offset: 2px;
      }

      .ungani-btn:disabled,
      .ungani-btn.is-loading {
        cursor: not-allowed;
        opacity: 0.65;
        transform: none !important;
        filter: none !important;
        box-shadow: none !important;
      }

      /* Primary: Save / Approve / Confirm / Submit */
      .ungani-btn.gold,
      .ungani-btn.primary {
        background: var(--ungani-gold);
        color: var(--ungani-navy);
      }

      /* Secondary: Cancel / Back / Close - outline, on light surfaces */
      .ungani-btn.dark,
      .ungani-btn.secondary {
        background: #FFFFFF;
        color: var(--ungani-navy);
        border-color: var(--ungani-navy);
        box-shadow: none;
      }

      html[data-ungani-theme="dark"] .ungani-btn.dark,
      html[data-ungani-theme="dark"] .ungani-btn.secondary {
        background: transparent;
        color: #FFFFFF;
        border-color: rgba(255,255,255,0.42);
      }

      .ungani-btn.light {
        background: transparent;
        color: #FFFFFF;
        border-color: rgba(255,255,255,0.45);
        box-shadow: none;
      }

      /* Destructive: Delete / Reject / Remove */
      .ungani-btn.red,
      .ungani-btn.destructive {
        background: var(--ungani-red);
        color: #FFFFFF;
      }

      .ungani-btn.green { background: var(--ungani-green); color: #FFFFFF; }
      .ungani-btn.orange { background: var(--ungani-orange); color: #FFFFFF; }
      .ungani-btn.blue { background: var(--ungani-blue); color: #FFFFFF; }

      .ungani-btn.small {
        min-height: 36px;
        padding: 0 13px;
        font-size: 12.5px;
        border-radius: 10px;
      }

      .ungani-btn-spinner {
        display: inline-block;
        width: 15px;
        height: 15px;
        border-radius: 50%;
        border: 2px solid rgba(0,0,0,0.2);
        border-top-color: currentColor;
        animation: unganiBtnSpin 0.65s linear infinite;
      }

      @keyframes unganiBtnSpin {
        to { transform: rotate(360deg); }
      }

      .ungani-loading-shell,
      .ungani-login-shell,
      .ungani-blocked-shell {
        min-height: 100vh;
        background: linear-gradient(135deg, #061C3D, #0b2b59);
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 24px;
      }

      html[data-ungani-theme="dark"] .ungani-loading-shell,
      html[data-ungani-theme="dark"] .ungani-login-shell,
      html[data-ungani-theme="dark"] .ungani-blocked-shell {
        background: linear-gradient(135deg, #0B1220, #111C33);
      }

      .ungani-login-card,
      .ungani-loading-card {
        width: 100%;
        max-width: 460px;
        background: var(--ungani-card);
        color: var(--ungani-text);
        border-radius: 22px;
        padding: 28px;
        box-shadow: 0 20px 50px rgba(0,0,0,0.25);
        text-align: center;
        border: 1px solid var(--ungani-border);
      }

      .ungani-login-card input {
        width: 100%;
        padding: 12px;
        margin: 8px 0 12px;
        border-radius: 12px;
        border: 1px solid var(--ungani-border);
        font-size: 15px;
        background: var(--ungani-card);
        color: var(--ungani-text);
      }

      .ungani-login-card label {
        display: block;
        text-align: left;
        font-weight: bold;
        margin-top: 12px;
        font-size: 14px;
      }

      .ungani-logo {
        width: 145px;
        max-width: 65%;
        height: auto;
        margin-bottom: 12px;
      }

      .ungani-toast {
        position: fixed;
        right: 18px;
        bottom: 24px;
        background: #061C3D;
        color: #FFFFFF;
        border: 1px solid var(--ungani-gold);
        padding: 14px 16px;
        border-radius: 14px;
        box-shadow: 0 12px 24px rgba(0,0,0,0.25);
        opacity: 0;
        transform: translateY(12px);
        pointer-events: none;
        transition: 0.25s ease;
        z-index: 9999;
        max-width: 330px;
      }

      html[data-ungani-theme="dark"] .ungani-toast {
        background: #111C33;
      }

      .ungani-toast.show {
        opacity: 1;
        transform: translateY(0);
      }

      .ungani-modal-backdrop {
        position: fixed;
        inset: 0;
        background: rgba(2,6,23,0.72);
        display: none;
        align-items: center;
        justify-content: center;
        z-index: 9999;
        padding: 40px 18px;
      }

      .ungani-modal-backdrop.open {
        display: flex;
      }

      .ungani-modal {
        width: min(720px, 100%);
        background: var(--ungani-card);
        color: var(--ungani-text);
        border: 1px solid var(--ungani-border);
        border-radius: 24px;
        box-shadow: 0 30px 90px rgba(0,0,0,0.4);
        overflow: hidden;
        max-height: calc(100vh - 80px);
        display: flex;
        flex-direction: column;
      }

      .ungani-modal-head {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        padding: 18px 22px;
        border-bottom: 1px solid var(--ungani-border);
        flex: none;
      }

      .ungani-modal-head h3 {
        margin: 0;
        font-size: 19px;
      }

      .ungani-modal-close {
        border: none;
        background: rgba(148,163,184,0.18);
        color: var(--ungani-text);
        width: 34px;
        height: 34px;
        border-radius: 999px;
        cursor: pointer;
        font-size: 16px;
        flex: none;
        line-height: 1;
      }

      .ungani-modal-body {
        padding: 22px;
        overflow-y: auto;
      }

      @media (max-width: 640px) {
        .ungani-modal-backdrop {
          padding: 0;
          align-items: flex-end;
        }

        .ungani-modal {
          border-radius: 24px 24px 0 0;
          max-height: 92vh;
          width: 100%;
        }
      }

      @media (max-width: 1100px) {
        .ungani-admin-app {
          grid-template-columns: 1fr;
        }

        .ungani-admin-sidebar {
          position: fixed;
          left: -320px;
          top: 0;
          width: 300px;
          z-index: 100;
          transition: 0.25s ease;
        }

        .ungani-admin-sidebar.open {
          left: 0;
        }

        .ungani-admin-main {
          padding: 16px;
        }

        .ungani-topbar {
          position: static;
          grid-template-columns: 1fr;
        }

        .ungani-topbar-actions {
          justify-content: flex-start;
        }

        .ungani-admin-menu-btn {
          display: inline-flex;
        }

        body.ungani-admin-sidebar-open .ungani-admin-sidebar-overlay {
          display: block;
          position: fixed;
          inset: 0;
          background: rgba(0,0,0,0.42);
          z-index: 95;
        }
      }
    `;

    document.head.appendChild(style);
  }

  function applyTheme(theme) {
    currentTheme = theme === "dark" ? "dark" : "light";
    document.documentElement.dataset.unganiTheme = currentTheme;

    // client-shared.js's applyTheme() sets this on both <html> and <body> -
    // mirrored here so any inline page CSS written against the client-side
    // convention (body[data-ungani-theme]) doesn't silently never fire on
    // the admin side.
    if (document.body) {
      document.body.dataset.unganiTheme = currentTheme;
    }

    localStorage.setItem("ungani_theme", currentTheme);
    localStorage.setItem("ungani_client_theme", currentTheme);
  }

  function toggleTheme() {
    const nextTheme = currentTheme === "dark" ? "light" : "dark";
    applyTheme(nextTheme);
    showToast(nextTheme === "dark" ? "Dark mode enabled" : "Light mode enabled");
  }

  function applyLanguage(rootElement) {
    document.documentElement.lang = currentLanguage === "sw" ? "sw" : "en";

    const root = rootElement || document;

    root.querySelectorAll("[data-i18n]").forEach(el => {
      const key = el.getAttribute("data-i18n");
      el.innerText = t(key);
    });
  }

  function withButtonLoading(button, asyncFn) {
    if (!button || button.disabled || button.classList.contains("is-loading")) {
      return Promise.resolve(typeof asyncFn === "function" ? asyncFn() : undefined);
    }

    const originalHtml = button.innerHTML;
    const originalMinWidth = button.style.minWidth;

    button.style.minWidth = button.offsetWidth + "px";
    button.disabled = true;
    button.classList.add("is-loading");
    button.innerHTML = '<span class="ungani-btn-spinner"></span>';

    const restore = function () {
      button.disabled = false;
      button.classList.remove("is-loading");
      button.innerHTML = originalHtml;
      button.style.minWidth = originalMinWidth;
    };

    return Promise.resolve()
      .then(function () {
        return typeof asyncFn === "function" ? asyncFn() : undefined;
      })
      .then(function (result) {
        restore();
        return result;
      })
      .catch(function (error) {
        restore();
        throw error;
      });
  }

  function showToast(message) {
    let toast = document.getElementById("unganiToast");

    if (!toast) {
      toast = document.createElement("div");
      toast.id = "unganiToast";
      toast.className = "ungani-toast";
      document.body.appendChild(toast);
    }

    toast.innerText = message;
    toast.classList.add("show");

    setTimeout(() => {
      toast.classList.remove("show");
    }, 2500);
  }

  let modalEscapeListenerAttached = false;

  function ensureModal() {
    injectBaseStyles();

    let backdrop = document.getElementById("unganiModalBackdrop");

    if (backdrop) return backdrop;

    backdrop = document.createElement("div");
    backdrop.id = "unganiModalBackdrop";
    backdrop.className = "ungani-modal-backdrop";
    backdrop.innerHTML = `
      <div class="ungani-modal" role="dialog" aria-modal="true" aria-labelledby="unganiModalTitle">
        <div class="ungani-modal-head">
          <h3 id="unganiModalTitle"></h3>
          <button type="button" class="ungani-modal-close" onclick="UnganiAdminShared.closeModal()" aria-label="Close">✕</button>
        </div>
        <div class="ungani-modal-body" id="unganiModalBody"></div>
      </div>
    `;

    document.body.appendChild(backdrop);

    backdrop.addEventListener("click", function (event) {
      if (event.target === backdrop) closeModal();
    });

    if (!modalEscapeListenerAttached) {
      modalEscapeListenerAttached = true;

      document.addEventListener("keydown", function (event) {
        const openBackdrop = document.getElementById("unganiModalBackdrop");
        if (event.key === "Escape" && openBackdrop && openBackdrop.classList.contains("open")) {
          closeModal();
        }
      });
    }

    return backdrop;
  }

  function openModal(options) {
    const settings = options || {};
    const backdrop = ensureModal();

    document.getElementById("unganiModalTitle").innerText = settings.title || "";
    document.getElementById("unganiModalBody").innerHTML = settings.bodyHtml || "";

    backdrop.classList.add("open");
    document.body.style.overflow = "hidden";

    if (typeof settings.onOpen === "function") {
      settings.onOpen();
    }
  }

  function closeModal() {
    const backdrop = document.getElementById("unganiModalBackdrop");
    if (backdrop) backdrop.classList.remove("open");
    document.body.style.overflow = "";
  }

  function renderSidebar(targetId, options) {
    injectBaseStyles();

    const target = document.getElementById(targetId || "adminSidebar");
    if (!target) return;

    const activeKey = options?.activeKey || "";
    const adminName = options?.adminName || currentAdmin?.full_name || "Admin Workspace";
    const footerTitle = options?.footerTitle || "Admin Dashboard";
    const footerVersion = options?.footerVersion || "Shared Sidebar Version: Step 279";

    const sectionsHtml = adminNavSections.map(section => {
      const linksHtml = section.links.map(link => {
        const isActive = activeKey === link.activeKey || activeKey === link.key;
        return `
          <a class="ungani-side-link ${isActive ? "active" : ""}" href="${safe(link.href)}">
            ${safe(link.icon)} <span data-i18n="${safe(link.key)}">${safe(t(link.key))}</span>
          </a>
        `;
      }).join("");

      return `
        <div class="ungani-sidebar-section-title" data-i18n="${safe(section.titleKey)}">${safe(t(section.titleKey))}</div>
        ${linksHtml}
      `;
    }).join("");

    target.className = "ungani-admin-sidebar";
    target.innerHTML = `
      <div class="ungani-brand-box">
        <img src="ungani-logo.png" alt="UNGANI Logo" class="ungani-brand-logo" />
        <h2>UNGANI Admin</h2>
        <p>${safe(adminName)}</p>
      </div>

      ${sectionsHtml}

      <div class="ungani-sidebar-footer">
        <strong>${safe(footerTitle)}</strong><br />
        ${safe(footerVersion)}<br />
        ungani.com

        <div style="margin-top:12px;">
          <button class="ungani-btn" id="unganiAdminThemeBtn" type="button" data-i18n="theme">${safe(t("theme"))}</button>
        </div>
      </div>
    `;

    document.getElementById("unganiAdminThemeBtn")?.addEventListener("click", toggleTheme);

    applyLanguage(target);
  }

  function renderShell(targetId, options) {
    injectBaseStyles();

    const target = document.getElementById(targetId || "adminRoot");

    if (!target) return;

    const activeKey = options?.activeKey || "admin-home";
    const pageTitle = options?.pageTitle || "UNGANI Admin";
    const pageSubtitle = options?.pageSubtitle || "Admin workspace";
    const mainHtml = options?.mainHtml || "";

    target.innerHTML = `
      <div id="unganiLoadingShell" class="ungani-loading-shell">
        <div class="ungani-loading-card">
          <img src="ungani-logo.png" alt="UNGANI Logo" class="ungani-logo" />
          <h2 data-i18n="loadingAdmin">${safe(t("loadingAdmin"))}</h2>
          <p data-i18n="checkingSession">${safe(t("checkingSession"))}</p>
        </div>
      </div>

      <div id="unganiLoginShell" class="ungani-login-shell hidden">
        <div class="ungani-login-card">
          <img src="ungani-logo.png" alt="UNGANI Logo" class="ungani-logo" />
          <h1>UNGANI <span style="color: var(--ungani-gold);">Admin</span></h1>
          <p data-i18n="adminLogin">${safe(t("adminLogin"))}</p>

          <label data-i18n="email">${safe(t("email"))}</label>
          <input id="unganiAdminEmail" placeholder="admin@example.com" />

          <label data-i18n="password">${safe(t("password"))}</label>
          <input id="unganiAdminPassword" type="password" placeholder="Enter password" />

          <button class="ungani-btn gold" id="unganiAdminLoginButton" data-i18n="login">${safe(t("login"))}</button>

          <div id="unganiLoginMessage"></div>

          <p style="font-size: 12px; color: var(--ungani-muted); margin-top: 18px;">
            ungani.com | info@ungani.com
          </p>
        </div>
      </div>

      <div id="unganiBlockedShell" class="ungani-blocked-shell hidden">
        <div class="ungani-login-card">
          <img src="ungani-logo.png" alt="UNGANI Logo" class="ungani-logo" />
          <h2 style="color: var(--ungani-red);" data-i18n="accessBlocked">${safe(t("accessBlocked"))}</h2>
          <p id="unganiBlockedReason"></p>
          <button class="ungani-btn dark" id="unganiBlockedLogoutButton" data-i18n="logout">${safe(t("logout"))}</button>
        </div>
      </div>

      <div id="unganiAppShell" class="ungani-admin-app hidden">
        <div class="ungani-admin-sidebar-overlay" id="unganiAdminSidebarOverlay"></div>

        <aside id="adminSidebar"></aside>

        <main class="ungani-admin-main">
          <div class="ungani-topbar">
            <div>
              <button class="ungani-admin-menu-btn" type="button" id="unganiAdminMenuBtn" aria-label="Toggle menu">☰</button>
              <h1>${safe(pageTitle)}</h1>
              <p>${safe(pageSubtitle)}</p>
            </div>

            <div class="ungani-topbar-actions">
              <a href="admin-settings.html" class="ungani-btn dark" data-i18n="adminSettings">${safe(t("adminSettings"))}</a>
              <button class="ungani-btn dark" id="unganiAdminLogoutButton" data-i18n="logout">${safe(t("logout"))}</button>
            </div>
          </div>

          <div id="unganiPageContent">
            ${mainHtml}
          </div>
        </main>
      </div>
    `;

    document.getElementById("unganiAdminLoginButton")?.addEventListener("click", loginFromShell);
    document.getElementById("unganiAdminLogoutButton")?.addEventListener("click", logoutAdmin);
    document.getElementById("unganiBlockedLogoutButton")?.addEventListener("click", logoutAdmin);
    document.getElementById("unganiAdminMenuBtn")?.addEventListener("click", toggleAdminSidebar);
    document.getElementById("unganiAdminSidebarOverlay")?.addEventListener("click", closeAdminSidebar);

    renderSidebar("adminSidebar", {
      activeKey,
      footerTitle: options?.footerTitle || pageTitle,
      footerVersion: options?.footerVersion || "Shared Admin Shell Version: Step 279"
    });

    applyLanguage(target);
  }

  function toggleAdminSidebar() {
    const sidebar = document.getElementById("adminSidebar");
    const btn = document.getElementById("unganiAdminMenuBtn");
    if (!sidebar) return;

    const isOpen = sidebar.classList.toggle("open");
    document.body.classList.toggle("ungani-admin-sidebar-open", isOpen);
    if (btn) btn.textContent = isOpen ? "✕" : "☰";
  }

  function closeAdminSidebar() {
    const sidebar = document.getElementById("adminSidebar");
    const btn = document.getElementById("unganiAdminMenuBtn");
    if (sidebar) sidebar.classList.remove("open");
    document.body.classList.remove("ungani-admin-sidebar-open");
    if (btn) btn.textContent = "☰";
  }

  function showShell(shellId) {
    ["unganiLoadingShell", "unganiLoginShell", "unganiBlockedShell", "unganiAppShell"].forEach(id => {
      const el = document.getElementById(id);
      if (el) el.classList.toggle("hidden", id !== shellId);
    });
  }

  function showBlocked(reason) {
    const reasonEl = document.getElementById("unganiBlockedReason");
    if (reasonEl) reasonEl.innerText = reason;
    showShell("unganiBlockedShell");
  }

  async function getSession() {
    const client = getSupabaseClient();
    const { data, error } = await client.auth.getSession();

    if (error) {
      console.log("Session error:", error.message);
      return null;
    }

    return data?.session || null;
  }

  async function isAdminByRpc() {
    try {
      const client = getSupabaseClient();
      const { data, error } = await client.rpc("is_ungani_admin");

      if (error) return false;

      return data === true;
    } catch (error) {
      return false;
    }
  }

  async function loadAdminProfile() {
    const client = getSupabaseClient();

    if (!currentAdminId) {
      const session = await getSession();
      currentAdminId = session?.user?.id || null;
    }

    if (!currentAdminId) return null;

    const rpcAdmin = await isAdminByRpc();

    const { data: userData, error } = await client
      .from("users")
      .select("id, full_name, email, role, status, preferred_theme, preferred_language")
      .eq("id", currentAdminId)
      .maybeSingle();

    if (error) {
      throw new Error(error.message);
    }

    if (!userData) {
      throw new Error("Your login exists, but your UNGANI admin profile was not found.");
    }

    const role = String(userData.role || "").toLowerCase();
    const isAdminRole = ["admin", "super_admin", "owner"].includes(role);

    if (!rpcAdmin && !isAdminRole) {
      throw new Error("This login is not allowed to access the Admin Dashboard.");
    }

    if (userData.status && userData.status !== "active") {
      throw new Error("Your admin user access is not active.");
    }

    currentAdmin = userData;
    currentTheme = userData.preferred_theme || localStorage.getItem("ungani_theme") || "light";
    currentLanguage = userData.preferred_language || "en";

    applyTheme(currentTheme);
    applyLanguage();

    return currentAdmin;
  }

  async function requireAdmin(options) {
    injectBaseStyles();

    const savedTheme = localStorage.getItem("ungani_theme");

    if (savedTheme) {
      applyTheme(savedTheme);
    }

    applyLanguage();

    const session = await getSession();

    if (!session || !session.user) {
      if (typeof options?.onNoSession === "function") {
        options.onNoSession();
      } else {
        showShell("unganiLoginShell");
      }

      return null;
    }

    currentAdminId = session.user.id;

    try {
      const admin = await loadAdminProfile();

      if (typeof options?.onReady === "function") {
        options.onReady(admin, getSupabaseClient());
      }

      return admin;
    } catch (error) {
      if (typeof options?.onBlocked === "function") {
        options.onBlocked(error.message);
      } else {
        showBlocked(error.message);
      }

      return null;
    }
  }

  async function loginFromShell() {
    const email = document.getElementById("unganiAdminEmail")?.value?.trim() || "";
    const password = document.getElementById("unganiAdminPassword")?.value || "";
    const msg = document.getElementById("unganiLoginMessage");
    const client = getSupabaseClient();

    if (msg) msg.innerHTML = "";

    const { data, error } = await client.auth.signInWithPassword({
      email,
      password
    });

    if (error) {
      if (msg) msg.innerHTML = `<p style="color: var(--ungani-red); font-weight: bold;">${safe(error.message)}</p>`;
      return;
    }

    currentAdminId = data?.session?.user?.id || null;

    if (msg) msg.innerHTML = `<p style="color: var(--ungani-green); font-weight: bold;">${safe(t("loginSuccess"))}</p>`;

    await logAuditEvent("login", { entityType: "session" });
    await loadAdminProfile();
    window.location.reload();
  }

  async function logAuditEvent(action, details) {
    try {
      const client = getSupabaseClient();
      const sessionRes = await client.auth.getSession();
      const token = sessionRes?.data?.session?.access_token;

      if (!token) return;

      await fetch("/api/log-audit-event", {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: "Bearer " + token },
        body: JSON.stringify(Object.assign({ action: action }, details || {})),
        keepalive: true
      });
    } catch (error) {
      console.warn("Audit log warning:", error.message);
    }
  }

  async function logoutAdmin() {
    const client = getSupabaseClient();
    await logAuditEvent("logout", { entityType: "session" });
    await client.auth.signOut();
    window.location.href = "admin-home.html";
  }

  async function updateAdminPreferences(values) {
    if (!currentAdminId) {
      const session = await getSession();
      currentAdminId = session?.user?.id || null;
    }

    if (!currentAdminId) {
      throw new Error("No active admin session found.");
    }

    const client = getSupabaseClient();

    const { error } = await client
      .from("users")
      .update(values)
      .eq("id", currentAdminId);

    if (error) {
      throw new Error(error.message);
    }

    if (values.preferred_theme) {
      applyTheme(values.preferred_theme);
    }

    if (values.preferred_language) {
      currentLanguage = values.preferred_language;
      applyLanguage();
    }

    return true;
  }

  function injectPwaMetaLinks() {
    const links = [
      { rel: "manifest", href: "/manifest.json" },
      { rel: "icon", href: "/ungani-icon-32.png", type: "image/png" },
      { rel: "icon", href: "/ungani-icon-192.png", type: "image/png", sizes: "192x192" },
      { rel: "apple-touch-icon", href: "/ungani-icon-180.png" }
    ];

    links.forEach(function (linkInfo) {
      const existing = document.querySelector(
        `link[rel="${linkInfo.rel}"]` + (linkInfo.sizes ? `[sizes="${linkInfo.sizes}"]` : "")
      );

      if (existing) {
        return;
      }

      const link = document.createElement("link");
      Object.keys(linkInfo).forEach(function (key) {
        link.setAttribute(key, linkInfo[key]);
      });

      if (document.head) {
        document.head.appendChild(link);
      }
    });
  }

  injectPwaMetaLinks();

  function getCurrentAdmin() {
    return currentAdmin;
  }

  function getCurrentAdminId() {
    return currentAdminId;
  }

  function getCurrentTheme() {
    return currentTheme;
  }

  function getCurrentLanguage() {
    return currentLanguage;
  }

  function setCurrentLanguage(language) {
    currentLanguage = language === "sw" ? "sw" : "en";
    applyLanguage();
  }

  window.UnganiAdminShared = {
    config: UNGANI_CONFIG,
    getSupabaseClient,
    injectBaseStyles,
    renderSidebar,
    renderShell,
    toggleAdminSidebar,
    closeAdminSidebar,
    requireAdmin,
    loadAdminProfile,
    getSession,
    isAdminByRpc,
    applyTheme,
    toggleTheme,
    applyLanguage,
    updateAdminPreferences,
    logoutAdmin,
    logAuditEvent,
    showToast,
    openModal,
    closeModal,
    withButtonLoading,
    safe,
    cleanText,
    t,
    getCurrentAdmin,
    getCurrentAdminId,
    getCurrentTheme,
    getCurrentLanguage,
    setCurrentLanguage
  };
})();
