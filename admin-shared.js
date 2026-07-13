(function () {
  const UNGANI_CONFIG = {
    supabaseUrl: "https://ctmtjwklltnsmfdtvqhl.supabase.co",
    supabaseAnonKey: "sb_publishable_jkZaWWep-cObTEv_F_kN6g_Ic85BxD9"
  };

  let supabaseClient = null;
  let currentAdmin = null;
  let currentAdminId = null;
  let currentTheme = "light";
  let currentLanguage = "en";

  const translations = {
    en: {
      main: "Main",
      adminHome: "Admin Home",
      mainAdmin: "Main Admin",
      portal: "Portal",
      healthCheck: "Health Check",
      clients: "Clients",
      registrations: "Registrations",
      clientProfiles: "Client Profiles",
      peopleStaff: "People / Staff",
      users: "Users",
      sections: "Sections",
      billing: "Billing",
      operations: "Operations",
      money: "Money",
      records: "Records",
      documents: "Documents",
      tasks: "Tasks",
      itemsAssets: "Items / Assets",
      calendar: "Calendar",
      communication: "Communication",
      adminChat: "Admin Chat",
      teamChat: "Team Chat",
      support: "Support",
      notices: "Notices",
      reports: "Reports",
      charts: "Charts",
      settings: "Settings",
      adminSettings: "Admin Settings",
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
      main: "Kuu",
      adminHome: "Nyumbani kwa Admin",
      mainAdmin: "Admin Kuu",
      portal: "Portal",
      healthCheck: "Ukaguzi wa Mfumo",
      clients: "Wateja",
      registrations: "Usajili",
      clientProfiles: "Wasifu wa Wateja",
      peopleStaff: "Watu / Wafanyakazi",
      users: "Watumiaji",
      sections: "Sehemu",
      billing: "Malipo",
      operations: "Uendeshaji",
      money: "Fedha",
      records: "Rekodi",
      documents: "Nyaraka",
      tasks: "Kazi",
      itemsAssets: "Vitu / Mali",
      calendar: "Kalenda",
      communication: "Mawasiliano",
      adminChat: "Gumzo la Admin",
      teamChat: "Gumzo la Timu",
      support: "Msaada",
      notices: "Matangazo",
      reports: "Ripoti",
      charts: "Chati",
      settings: "Mipangilio",
      adminSettings: "Mipangilio ya Admin",
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

  const adminNavSections = [
    {
      titleKey: "main",
      links: [
        { key: "adminHome", href: "admin-home.html", icon: "🏠", activeKey: "admin-home" },
        { key: "mainAdmin", href: "admin.html", icon: "🧭", activeKey: "admin-main" },
        { key: "portal", href: "portal.html", icon: "🌐", activeKey: "portal" },
        { key: "healthCheck", href: "admin-health.html", icon: "✅", activeKey: "admin-health" }
      ]
    },
    {
      titleKey: "clients",
      links: [
        { key: "registrations", href: "admin.html", icon: "📝", activeKey: "registrations" },
        { key: "clientProfiles", href: "admin-profiles.html", icon: "🏢", activeKey: "admin-profiles" },
        { key: "peopleStaff", href: "admin-people.html", icon: "👥", activeKey: "admin-people" },
        { key: "users", href: "users.html", icon: "🔐", activeKey: "admin-users" },
        { key: "sections", href: "sections.html", icon: "🧩", activeKey: "admin-sections" },
        { key: "billing", href: "billing.html", icon: "💳", activeKey: "admin-billing" }
      ]
    },
    {
      titleKey: "operations",
      links: [
        { key: "money", href: "admin-money.html", icon: "💰", activeKey: "admin-money" },
        { key: "records", href: "admin-records.html", icon: "📋", activeKey: "admin-records" },
        { key: "documents", href: "admin-documents.html", icon: "📁", activeKey: "admin-documents" },
        { key: "tasks", href: "admin-tasks.html", icon: "✅", activeKey: "admin-tasks" },
        { key: "itemsAssets", href: "admin-items.html", icon: "📦", activeKey: "admin-items" },
        { key: "calendar", href: "admin-calendar.html", icon: "📅", activeKey: "admin-calendar" }
      ]
    },
    {
      titleKey: "communication",
      links: [
        { key: "adminChat", href: "admin-chat.html", icon: "💬", activeKey: "admin-chat" },
        { key: "teamChat", href: "my-team-chat.html", icon: "👥", activeKey: "team-chat" },
        { key: "support", href: "support.html", icon: "🛟", activeKey: "admin-support" },
        { key: "notices", href: "notices.html", icon: "📢", activeKey: "admin-notices" }
      ]
    },
    {
      titleKey: "reports",
      links: [
        { key: "charts", href: "admin-charts.html", icon: "📊", activeKey: "admin-charts" },
        { key: "reports", href: "admin-reports.html", icon: "📄", activeKey: "admin-reports" }
      ]
    },
    {
      titleKey: "settings",
      links: [
        { key: "adminSettings", href: "admin-settings.html", icon: "⚙️", activeKey: "admin-settings" }
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

    if (!window.supabase || typeof window.supabase.createClient !== "function") {
      throw new Error("Supabase JS is not loaded. Add the Supabase CDN script before admin-shared.js.");
    }

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
        --navy: #061C3D;
        --gold: #D4A63A;
        --green: #15803D;
        --red: #B00020;
        --orange: #EA580C;
        --blue: #2563EB;

        --bg: #F5F5F3;
        --card: #FFFFFF;
        --text: #061C3D;
        --soft-text: #6B7280;
        --border: #E5E7EB;
        --sidebar: #061C3D;
        --input-bg: #FFFFFF;
        --shadow: rgba(6,28,61,0.08);
      }

      body.dark {
        --bg: #0B1220;
        --card: #111C33;
        --text: #F5F5F3;
        --soft-text: #AAB2C0;
        --border: rgba(255,255,255,0.10);
        --sidebar: #0B1220;
        --input-bg: #0B1220;
        --shadow: rgba(0,0,0,0.28);
      }

      * {
        box-sizing: border-box;
      }

      body {
        margin: 0;
        font-family: Arial, sans-serif;
        background: var(--bg);
        color: var(--text);
      }

      .hidden {
        display: none !important;
      }

      .ungani-admin-app {
        min-height: 100vh;
        display: grid;
        grid-template-columns: 290px 1fr;
        background: var(--bg);
      }

      .ungani-admin-sidebar {
        background: var(--sidebar);
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
        color: var(--gold);
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
        background: var(--card);
        border: 1px solid var(--border);
        border-radius: 22px;
        padding: 16px;
        display: grid;
        grid-template-columns: 1fr auto;
        gap: 14px;
        align-items: center;
        box-shadow: 0 10px 24px var(--shadow);
        margin-bottom: 18px;
        position: sticky;
        top: 16px;
        z-index: 20;
      }

      .ungani-topbar h1 {
        margin: 0 0 5px;
        font-size: 24px;
        color: var(--text);
      }

      .ungani-topbar p {
        margin: 0;
        color: var(--soft-text);
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
        border: 1px solid var(--border);
        background: var(--card);
        color: var(--text);
        font-size: 19px;
        cursor: pointer;
        margin-bottom: 10px;
      }

      .ungani-admin-sidebar-overlay {
        display: none;
      }

      .ungani-card {
        background: var(--card);
        color: var(--text);
        border: 1px solid var(--border);
        border-radius: 22px;
        padding: 22px;
        margin-bottom: 18px;
        box-shadow: 0 10px 24px var(--shadow);
      }

      .ungani-hero-card {
        background: linear-gradient(135deg, #061C3D, #0b2b59);
        color: #FFFFFF;
        border: none;
        overflow: hidden;
        position: relative;
      }

      body.dark .ungani-hero-card {
        background: linear-gradient(135deg, #0B1220, #111C33);
        border: 1px solid rgba(212,166,58,0.22);
      }

      .ungani-button {
        border: none;
        border-radius: 12px;
        padding: 10px 14px;
        min-height: 44px;
        font-weight: bold;
        cursor: pointer;
        background: var(--gold);
        color: #061C3D;
        margin: 4px 5px 4px 0;
        text-decoration: none;
        display: inline-flex;
        align-items: center;
        justify-content: center;
      }

      .ungani-button.dark {
        background: #061C3D;
        color: #FFFFFF;
      }

      body.dark .ungani-button.dark {
        background: #F5F5F3;
        color: #061C3D;
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

      body.dark .ungani-loading-shell,
      body.dark .ungani-login-shell,
      body.dark .ungani-blocked-shell {
        background: linear-gradient(135deg, #0B1220, #111C33);
      }

      .ungani-login-card,
      .ungani-loading-card {
        width: 100%;
        max-width: 460px;
        background: var(--card);
        color: var(--text);
        border-radius: 22px;
        padding: 28px;
        box-shadow: 0 20px 50px rgba(0,0,0,0.25);
        text-align: center;
        border: 1px solid var(--border);
      }

      .ungani-login-card input {
        width: 100%;
        padding: 12px;
        margin: 8px 0 12px;
        border-radius: 12px;
        border: 1px solid var(--border);
        font-size: 15px;
        background: var(--input-bg);
        color: var(--text);
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
        border: 1px solid var(--gold);
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

      body.dark .ungani-toast {
        background: #111C33;
      }

      .ungani-toast.show {
        opacity: 1;
        transform: translateY(0);
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
    document.body.classList.toggle("dark", currentTheme === "dark");
    localStorage.setItem("ungani_theme", currentTheme);
  }

  function applyLanguage(rootElement) {
    document.documentElement.lang = currentLanguage === "sw" ? "sw" : "en";

    const root = rootElement || document;

    root.querySelectorAll("[data-i18n]").forEach(el => {
      const key = el.getAttribute("data-i18n");
      el.innerText = t(key);
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
      </div>
    `;

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
          <h1>UNGANI <span style="color: var(--gold);">Admin</span></h1>
          <p data-i18n="adminLogin">${safe(t("adminLogin"))}</p>

          <label data-i18n="email">${safe(t("email"))}</label>
          <input id="unganiAdminEmail" placeholder="admin@example.com" />

          <label data-i18n="password">${safe(t("password"))}</label>
          <input id="unganiAdminPassword" type="password" placeholder="Enter password" />

          <button class="ungani-button" id="unganiAdminLoginButton" data-i18n="login">${safe(t("login"))}</button>

          <div id="unganiLoginMessage"></div>

          <p style="font-size: 12px; color: var(--soft-text); margin-top: 18px;">
            ungani.com | info@ungani.com
          </p>
        </div>
      </div>

      <div id="unganiBlockedShell" class="ungani-blocked-shell hidden">
        <div class="ungani-login-card">
          <img src="ungani-logo.png" alt="UNGANI Logo" class="ungani-logo" />
          <h2 style="color: var(--red);" data-i18n="accessBlocked">${safe(t("accessBlocked"))}</h2>
          <p id="unganiBlockedReason"></p>
          <button class="ungani-button dark" id="unganiBlockedLogoutButton" data-i18n="logout">${safe(t("logout"))}</button>
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
              <a href="admin-settings.html" class="ungani-button dark" data-i18n="adminSettings">${safe(t("adminSettings"))}</a>
              <button class="ungani-button dark" id="unganiAdminLogoutButton" data-i18n="logout">${safe(t("logout"))}</button>
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
      if (msg) msg.innerHTML = `<p style="color: var(--red); font-weight: bold;">${safe(error.message)}</p>`;
      return;
    }

    currentAdminId = data?.session?.user?.id || null;

    if (msg) msg.innerHTML = `<p style="color: var(--green); font-weight: bold;">${safe(t("loginSuccess"))}</p>`;

    await loadAdminProfile();
    window.location.reload();
  }

  async function logoutAdmin() {
    const client = getSupabaseClient();
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
    applyLanguage,
    updateAdminPreferences,
    logoutAdmin,
    showToast,
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
