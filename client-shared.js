// UNGANI OS - Client Shared Helper
// Client Shared Version: Step 305A
// Purpose: gives all client pages one shared sidebar, session check, theme handling, and common utilities.

(function () {
  const SUPABASE_URL = "https://ctmtjwklltnsmfdtvqhl.supabase.co";
  const SUPABASE_KEY = "sb_publishable_jkZaWWep-cObTEv_F_kN6g_Ic85BxD9";

  if (!window.supabase) {
    console.error("Supabase JS library is missing. Add the Supabase CDN before client-shared.js.");
    return;
  }

  const supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

  const PAGES = [
    {
      group: "Main",
      links: [
        { key: "dashboard", label: "Dashboard", href: "client.html" },
        { key: "overview", label: "Overview", href: "my-overview.html" },
        { key: "activity", label: "Activity Feed", href: "my-activity.html" },
        { key: "charts", label: "Charts", href: "my-charts.html" }
      ]
    },
    {
      group: "Operations",
      links: [
        { key: "money", label: "Money Records", href: "my-money.html" },
        { key: "records", label: "Business Records", href: "my-records.html" },
        { key: "items", label: "Items / Assets / Stock", href: "my-items.html" },
        { key: "people", label: "People", href: "my-people.html" },
        { key: "tasks", label: "Tasks / Follow-ups", href: "my-tasks.html" },
        { key: "calendar", label: "Calendar", href: "my-calendar.html" },
        { key: "documents", label: "Documents", href: "my-documents.html" }
      ]
    },
    {
      group: "Support",
      links: [
        { key: "support", label: "Support Issues", href: "my-support.html" },
        { key: "notices", label: "Notices", href: "my-notices.html" },
        { key: "chat", label: "Chat with UNGANI", href: "my-chat.html" },
        { key: "team-chat", label: "Team Chat", href: "my-team-chat.html" }
      ]
    },
    {
      group: "Reports & Account",
      links: [
        { key: "reports", label: "Reports", href: "reports.html" },
        { key: "print-report", label: "Print Report", href: "print-report.html" },
        { key: "account", label: "Account Settings", href: "account.html" }
      ]
    }
  ];

  let currentSession = null;
  let currentAuthUser = null;
  let currentProfile = null;
  let currentTenant = null;

  function injectBaseStyles() {
    if (document.getElementById("ungani-client-shared-style")) return;

    const style = document.createElement("style");
    style.id = "ungani-client-shared-style";
    style.textContent = `
      :root {
        --ungani-navy: #061C3D;
        --ungani-gold: #D4A63A;
        --ungani-offwhite: #F5F5F3;
        --ungani-white: #FFFFFF;
        --ungani-gray: #E5E7EB;
        --ungani-text: #111827;
        --ungani-soft: #6B7280;
        --ungani-green: #16A34A;
        --ungani-red: #DC2626;
        --ungani-orange: #EA580C;
        --ungani-blue: #2563EB;
        --ungani-card: #FFFFFF;
        --ungani-bg: #F5F5F3;
        --ungani-border: #E5E7EB;
        --ungani-shadow: rgba(6, 28, 61, 0.10);
      }

      body.ungani-dark {
        --ungani-bg: #061C3D;
        --ungani-card: #0B2A55;
        --ungani-text: #FFFFFF;
        --ungani-soft: #CBD5E1;
        --ungani-border: rgba(255,255,255,0.16);
        --ungani-shadow: rgba(0,0,0,0.28);
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

      .ungani-hidden {
        display: none !important;
      }

      .ungani-screen {
        min-height: 100vh;
        display: grid;
        place-items: center;
        padding: 24px;
        background: var(--ungani-offwhite);
      }

      .ungani-screen-card {
        width: 100%;
        max-width: 520px;
        background: var(--ungani-white);
        border-radius: 24px;
        padding: 28px;
        text-align: center;
        box-shadow: 0 16px 38px rgba(6,28,61,0.12);
      }

      .ungani-screen-card img {
        width: 78px;
        margin-bottom: 14px;
      }

      .ungani-layout {
        display: grid;
        grid-template-columns: 280px 1fr;
        min-height: 100vh;
      }

      .ungani-sidebar {
        background: var(--ungani-navy);
        color: var(--ungani-white);
        padding: 22px;
        height: 100vh;
        position: sticky;
        top: 0;
        overflow-y: auto;
      }

      .ungani-brand {
        display: flex;
        align-items: center;
        gap: 12px;
        margin-bottom: 22px;
      }

      .ungani-brand img {
        width: 48px;
        height: 48px;
        object-fit: contain;
        background: var(--ungani-white);
        padding: 5px;
        border-radius: 14px;
      }

      .ungani-brand h1 {
        margin: 0;
        font-size: 18px;
        line-height: 1.2;
      }

      .ungani-brand p {
        margin: 3px 0 0;
        color: #CBD5E1;
        font-size: 12px;
      }

      .ungani-tenant-card {
        background: rgba(255,255,255,0.08);
        border: 1px solid rgba(255,255,255,0.12);
        border-radius: 16px;
        padding: 12px;
        margin-bottom: 18px;
      }

      .ungani-tenant-card strong {
        display: block;
        font-size: 14px;
        margin-bottom: 4px;
      }

      .ungani-tenant-card span {
        display: block;
        font-size: 12px;
        color: #CBD5E1;
        line-height: 1.35;
      }

      .ungani-nav-title {
        color: #CBD5E1;
        font-size: 12px;
        text-transform: uppercase;
        letter-spacing: 0.08em;
        margin: 18px 0 8px;
      }

      .ungani-nav-link {
        display: block;
        color: var(--ungani-white);
        text-decoration: none;
        padding: 11px 12px;
        border-radius: 12px;
        margin-bottom: 6px;
        font-size: 14px;
      }

      .ungani-nav-link:hover,
      .ungani-nav-link.active {
        background: rgba(212,166,58,0.18);
        color: var(--ungani-gold);
      }

      .ungani-main {
        width: 100%;
        max-width: 1500px;
        margin: 0 auto;
        padding: 24px;
      }

      .ungani-topbar {
        display: flex;
        justify-content: space-between;
        align-items: flex-start;
        gap: 14px;
        flex-wrap: wrap;
        margin-bottom: 18px;
      }

      .ungani-topbar h2 {
        margin: 0;
        font-size: 26px;
        color: var(--ungani-text);
      }

      .ungani-topbar p {
        margin: 5px 0 0;
        color: var(--ungani-soft);
        line-height: 1.45;
      }

      .ungani-card {
        background: var(--ungani-card);
        border: 1px solid var(--ungani-border);
        border-radius: 22px;
        padding: 20px;
        box-shadow: 0 12px 28px var(--ungani-shadow);
        margin-bottom: 18px;
      }

      .ungani-hero {
        background: linear-gradient(135deg, var(--ungani-navy), #0B2A55);
        color: var(--ungani-white);
        border: none;
        position: relative;
        overflow: hidden;
      }

      .ungani-hero:after {
        content: "";
        width: 220px;
        height: 220px;
        border-radius: 50%;
        background: rgba(212,166,58,0.22);
        position: absolute;
        right: -80px;
        top: -90px;
      }

      .ungani-hero h2,
      .ungani-hero p,
      .ungani-hero .ungani-button-row {
        position: relative;
        z-index: 1;
      }

      .ungani-hero h2 {
        margin: 0 0 8px;
        color: var(--ungani-white);
      }

      .ungani-hero p {
        margin: 0;
        color: #E5E7EB;
        line-height: 1.5;
        max-width: 920px;
      }

      .ungani-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(210px, 1fr));
        gap: 14px;
      }

      .ungani-two-col {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 18px;
      }

      .ungani-metric {
        background: var(--ungani-card);
        border: 1px solid var(--ungani-border);
        border-left: 6px solid var(--ungani-gold);
        border-radius: 20px;
        padding: 18px;
        box-shadow: 0 10px 24px var(--ungani-shadow);
      }

      .ungani-metric.green { border-left-color: var(--ungani-green); }
      .ungani-metric.red { border-left-color: var(--ungani-red); }
      .ungani-metric.orange { border-left-color: var(--ungani-orange); }
      .ungani-metric.blue { border-left-color: var(--ungani-blue); }

      .ungani-metric h3 {
        margin: 0 0 8px;
        color: var(--ungani-soft);
        font-size: 14px;
      }

      .ungani-metric p {
        margin: 0;
        font-size: 28px;
        font-weight: bold;
        color: var(--ungani-text);
      }

      .ungani-metric .note {
        color: var(--ungani-soft);
        margin-top: 8px;
        font-size: 12px;
        line-height: 1.4;
      }

      .ungani-section-title {
        display: flex;
        justify-content: space-between;
        align-items: center;
        gap: 12px;
        flex-wrap: wrap;
        margin-bottom: 14px;
      }

      .ungani-section-title h2,
      .ungani-section-title h3 {
        margin: 0;
        color: var(--ungani-text);
      }

      .ungani-form-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
        gap: 14px;
      }

      .ungani-button-row {
        display: flex;
        gap: 8px;
        flex-wrap: wrap;
        margin-top: 14px;
      }

      .ungani-btn {
        border: none;
        background: var(--ungani-gold);
        color: var(--ungani-navy);
        padding: 10px 14px;
        border-radius: 12px;
        font-weight: bold;
        cursor: pointer;
        text-decoration: none;
        display: inline-block;
        font-family: Arial, sans-serif;
      }

      .ungani-btn.dark {
        background: var(--ungani-navy);
        color: var(--ungani-white);
      }

      body.ungani-dark .ungani-btn.dark {
        background: var(--ungani-offwhite);
        color: var(--ungani-navy);
      }

      .ungani-btn.green { background: var(--ungani-green); color: var(--ungani-white); }
      .ungani-btn.red { background: var(--ungani-red); color: var(--ungani-white); }
      .ungani-btn.orange { background: var(--ungani-orange); color: var(--ungani-white); }
      .ungani-btn.blue { background: var(--ungani-blue); color: var(--ungani-white); }

      .ungani-btn:disabled {
        opacity: 0.65;
        cursor: not-allowed;
      }

      .ungani-small {
        color: var(--ungani-soft);
        font-size: 13px;
        line-height: 1.45;
      }

      .ungani-empty {
        text-align: center;
        border: 1px dashed var(--ungani-border);
        border-radius: 18px;
        padding: 28px;
        background: var(--ungani-bg);
      }

      .ungani-empty h3 {
        margin: 0 0 8px;
        color: var(--ungani-text);
      }

      .ungani-empty p {
        color: var(--ungani-soft);
        margin: 0;
        line-height: 1.45;
      }

      .ungani-badge {
        display: inline-block;
        background: var(--ungani-navy);
        color: var(--ungani-white);
        padding: 5px 10px;
        border-radius: 999px;
        font-size: 12px;
        margin: 4px 4px 4px 0;
        text-transform: capitalize;
      }

      .ungani-badge.green { background: var(--ungani-green); }
      .ungani-badge.red { background: var(--ungani-red); }
      .ungani-badge.orange { background: var(--ungani-orange); }
      .ungani-badge.blue { background: var(--ungani-blue); }
      .ungani-badge.gold { background: var(--ungani-gold); color: var(--ungani-navy); }

      .ungani-toast {
        position: fixed;
        right: 18px;
        bottom: 18px;
        background: var(--ungani-navy);
        color: var(--ungani-white);
        padding: 12px 14px;
        border-radius: 14px;
        display: none;
        z-index: 9999;
        box-shadow: 0 14px 32px rgba(0,0,0,0.22);
      }

      label {
        display: block;
        font-weight: bold;
        margin: 8px 0 6px;
        font-size: 14px;
        color: var(--ungani-text);
      }

      input,
      select,
      textarea {
        width: 100%;
        border: 1px solid var(--ungani-border);
        background: var(--ungani-bg);
        color: var(--ungani-text);
        padding: 12px;
        border-radius: 12px;
        font-size: 15px;
        font-family: Arial, sans-serif;
      }

      textarea {
        min-height: 110px;
        resize: vertical;
      }

      table {
        width: 100%;
        border-collapse: collapse;
      }

      th,
      td {
        text-align: left;
        padding: 12px;
        border-bottom: 1px solid var(--ungani-border);
        vertical-align: top;
      }

      th {
        color: var(--ungani-navy);
        background: rgba(212,166,58,0.14);
      }

      body.ungani-dark th {
        color: var(--ungani-white);
        background: rgba(212,166,58,0.18);
      }

      @media (max-width: 980px) {
        .ungani-layout {
          grid-template-columns: 1fr;
        }

        .ungani-sidebar {
          height: auto;
          position: relative;
        }

        .ungani-two-col {
          grid-template-columns: 1fr;
        }
      }
    `;

    document.head.appendChild(style);
  }

  function createScreen(id, title, message, buttonHtml) {
    return `
      <div id="${attr(id)}" class="ungani-screen ungani-hidden">
        <div class="ungani-screen-card">
          <img src="ungani-logo.png" alt="UNGANI Logo">
          <h2>${safe(title)}</h2>
          <p class="ungani-small">${safe(message)}</p>
          ${buttonHtml || ""}
        </div>
      </div>
    `;
  }

  function renderPageShell(options) {
    injectBaseStyles();

    const pageKey = options && options.pageKey ? options.pageKey : "dashboard";
    const pageTitle = options && options.pageTitle ? options.pageTitle : "Client Dashboard";
    const pageSubtitle = options && options.pageSubtitle ? options.pageSubtitle : "Manage your business workspace in one place.";
    const contentId = options && options.contentId ? options.contentId : "pageContent";

    document.body.innerHTML = `
      ${createScreen("unganiLoadingScreen", "Loading Workspace", "Checking your login session and loading your business workspace.", "")}

      ${createScreen(
        "unganiLoginScreen",
        "Login Required",
        "Please log in to access your UNGANI OS workspace.",
        '<div class="ungani-button-row" style="justify-content:center;"><a class="ungani-btn" href="portal.html">Go to Login</a></div>'
      )}

      ${createScreen(
        "unganiSetupScreen",
        "Account Setup Needed",
        "Your login is active, but your business workspace is not fully linked yet. Please contact UNGANI support.",
        '<div class="ungani-button-row" style="justify-content:center;"><a class="ungani-btn" href="mailto:info@ungani.com">Contact UNGANI</a><button class="ungani-btn dark" onclick="UnganiClientShared.logout()">Logout</button></div>'
      )}

      <div id="unganiAppShell" class="ungani-layout ungani-hidden">
        <aside class="ungani-sidebar">
          ${renderSidebar(pageKey)}
        </aside>

        <main class="ungani-main">
          <div class="ungani-topbar">
            <div>
              <h2>${safe(pageTitle)}</h2>
              <p>${safe(pageSubtitle)}</p>
            </div>

            <div class="ungani-button-row">
              <a class="ungani-btn dark" href="client.html">Dashboard</a>
              <button class="ungani-btn" onclick="UnganiClientShared.logout()">Logout</button>
            </div>
          </div>

          <div id="${attr(contentId)}"></div>
        </main>
      </div>

      <div id="unganiToast" class="ungani-toast"></div>
    `;
  }

  function renderSidebar(activeKey) {
    const tenantName = currentTenant ? getTenantName(currentTenant) : "Client Workspace";
    const tenantType = currentTenant ? getValue(currentTenant, ["business_type", "business_type_key"], "Business") : "Business";
    const tenantStatus = currentTenant ? getValue(currentTenant, ["account_status", "status"], "trial") : "trial";

    let html = `
      <div class="ungani-brand">
        <img src="ungani-logo.png" alt="UNGANI Logo">
        <div>
          <h1>UNGANI OS</h1>
          <p>Client Workspace</p>
        </div>
      </div>

      <div class="ungani-tenant-card">
        <strong>${safe(tenantName)}</strong>
        <span>${safe(tenantType)}</span>
        <span>Status: ${safe(tenantStatus)}</span>
      </div>
    `;

    PAGES.forEach(function (group) {
      html += `<div class="ungani-nav-title">${safe(group.group)}</div>`;

      group.links.forEach(function (link) {
        const active = link.key === activeKey ? "active" : "";

        html += `
          <a class="ungani-nav-link ${active}" href="${attr(link.href)}">
            ${safe(link.label)}
          </a>
        `;
      });
    });

    html += `
      <div class="ungani-button-row">
        <button class="ungani-btn" onclick="UnganiClientShared.logout()">Logout</button>
      </div>

      <p class="ungani-small" style="margin-top:18px;color:#CBD5E1;">
        Client Shared Version: Step 305A
      </p>
    `;

    return html;
  }

  async function initPage(options) {
    injectBaseStyles();

    const finalOptions = options || {};
    const pageKey = finalOptions.pageKey || "dashboard";

    renderPageShell(finalOptions);
    showOnly("unganiLoadingScreen");

    const sessionResponse = await supabaseClient.auth.getSession();
    currentSession = sessionResponse && sessionResponse.data ? sessionResponse.data.session : null;

    if (!currentSession || !currentSession.user) {
      showOnly("unganiLoginScreen");
      return null;
    }

    currentAuthUser = currentSession.user;

    await loadCurrentProfileAndTenant();

    if (!currentProfile || !currentTenant) {
      showOnly("unganiSetupScreen");
      return null;
    }

    await applySavedTheme();

    const shell = document.getElementById("unganiAppShell");
    const sidebar = shell ? shell.querySelector(".ungani-sidebar") : null;

    if (sidebar) {
      sidebar.innerHTML = renderSidebar(pageKey);
    }

    showOnly("unganiAppShell");

    if (typeof finalOptions.onReady === "function") {
      await finalOptions.onReady({
        supabaseClient: supabaseClient,
        session: currentSession,
        authUser: currentAuthUser,
        profile: currentProfile,
        tenant: currentTenant,
        tenantId: currentTenant.id,
        contentEl: document.getElementById(finalOptions.contentId || "pageContent")
      });
    }

    return {
      supabaseClient: supabaseClient,
      session: currentSession,
      authUser: currentAuthUser,
      profile: currentProfile,
      tenant: currentTenant,
      tenantId: currentTenant.id
    };
  }

  async function loadCurrentProfileAndTenant() {
    currentProfile = null;
    currentTenant = null;

    if (!currentAuthUser) return;

    let profileResponse = await supabaseClient
      .from("users")
      .select("*")
      .eq("id", currentAuthUser.id)
      .maybeSingle();

    if (profileResponse.error || !profileResponse.data) {
      profileResponse = await supabaseClient
        .from("users")
        .select("*")
        .eq("email", currentAuthUser.email)
        .maybeSingle();
    }

    if (profileResponse.error || !profileResponse.data) {
      return;
    }

    currentProfile = profileResponse.data;

    const tenantId = getValue(currentProfile, ["tenant_id"], "");

    if (!tenantId) {
      return;
    }

    const tenantResponse = await supabaseClient
      .from("tenants")
      .select("*")
      .eq("id", tenantId)
      .maybeSingle();

    if (!tenantResponse.error && tenantResponse.data) {
      currentTenant = tenantResponse.data;
    }
  }

  async function applySavedTheme() {
    let theme = "light";

    if (currentProfile) {
      theme = getValue(currentProfile, ["preferred_theme"], "light");
    }

    try {
      const localTheme = localStorage.getItem("ungani_client_theme");
      if (localTheme) {
        theme = localTheme;
      }
    } catch (error) {
      console.log(error.message);
    }

    document.body.classList.remove("ungani-dark");

    if (theme === "dark") {
      document.body.classList.add("ungani-dark");
    }
  }

  async function logout() {
    await supabaseClient.auth.signOut();
    window.location.href = "portal.html";
  }

  function showOnly(id) {
    const ids = [
      "unganiLoadingScreen",
      "unganiLoginScreen",
      "unganiSetupScreen",
      "unganiAppShell"
    ];

    ids.forEach(function (item) {
      const el = document.getElementById(item);
      if (el) el.classList.add("ungani-hidden");
    });

    const target = document.getElementById(id);
    if (target) target.classList.remove("ungani-hidden");
  }

  function showToast(message) {
    const toast = document.getElementById("unganiToast");

    if (!toast) {
      console.log(message);
      return;
    }

    toast.innerText = message;
    toast.style.display = "block";

    setTimeout(function () {
      toast.style.display = "none";
    }, 2400);
  }

  function setContent(html, contentId) {
    const target = document.getElementById(contentId || "pageContent");
    if (target) {
      target.innerHTML = html;
    }
  }

  function loadingCard(message) {
    return `
      <div class="ungani-card">
        <div class="ungani-empty">
          <h3>Loading...</h3>
          <p>${safe(message || "Please wait while we load your data.")}</p>
        </div>
      </div>
    `;
  }

  function emptyCard(title, message) {
    return `
      <div class="ungani-card">
        <div class="ungani-empty">
          <h3>${safe(title || "No records found")}</h3>
          <p>${safe(message || "No data has been added yet.")}</p>
        </div>
      </div>
    `;
  }

  function errorCard(title, message) {
    return `
      <div class="ungani-card">
        <div class="ungani-empty">
          <h3>${safe(title || "Something went wrong")}</h3>
          <p>${safe(message || "Please refresh and try again.")}</p>
        </div>
      </div>
    `;
  }

  function metricCard(title, value, note, colorClass) {
    return `
      <div class="ungani-metric ${attr(colorClass || "")}">
        <h3>${safe(title)}</h3>
        <p>${safe(value)}</p>
        <div class="note">${safe(note || "")}</div>
      </div>
    `;
  }

  function getTenantName(row) {
    return getValue(row, ["business_name", "company_name", "name", "tenant_name"], "Client Business");
  }

  function getProfileName(row) {
    return getValue(row, ["full_name", "contact_person", "name", "email"], "Client User");
  }

  function getValue(row, names, fallback) {
    for (let i = 0; i < names.length; i++) {
      const key = names[i];

      if (row && row[key] !== undefined && row[key] !== null && row[key] !== "") {
        return row[key];
      }
    }

    return fallback;
  }

  function formatKES(value) {
    const number = Number(value || 0);

    return "KES " + number.toLocaleString("en-KE", {
      maximumFractionDigits: 0
    });
  }

  function formatNumber(value) {
    const number = Number(value || 0);
    return number.toLocaleString("en-KE");
  }

  function formatDate(value) {
    if (!value) return "N/A";

    const date = new Date(value);
    if (isNaN(date.getTime())) return value;

    return date.toLocaleDateString("en-KE", {
      year: "numeric",
      month: "short",
      day: "numeric"
    });
  }

  function formatDateTime(value) {
    if (!value) return "N/A";

    const date = new Date(value);
    if (isNaN(date.getTime())) return value;

    return date.toLocaleString("en-KE", {
      year: "numeric",
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit"
    });
  }

  function value(id) {
    const element = document.getElementById(id);
    return element ? String(element.value || "").trim() : "";
  }

  function safe(value) {
    return String(value === null || value === undefined ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  function attr(value) {
    return safe(value)
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  function slugify(value) {
    return String(value || "")
      .toLowerCase()
      .trim()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "");
  }

  window.UnganiClientShared = {
    supabaseClient: supabaseClient,
    initPage: initPage,
    renderPageShell: renderPageShell,
    renderSidebar: renderSidebar,
    loadCurrentProfileAndTenant: loadCurrentProfileAndTenant,
    applySavedTheme: applySavedTheme,
    logout: logout,
    showOnly: showOnly,
    showToast: showToast,
    setContent: setContent,
    loadingCard: loadingCard,
    emptyCard: emptyCard,
    errorCard: errorCard,
    metricCard: metricCard,
    getTenantName: getTenantName,
    getProfileName: getProfileName,
    getValue: getValue,
    formatKES: formatKES,
    formatNumber: formatNumber,
    formatDate: formatDate,
    formatDateTime: formatDateTime,
    value: value,
    safe: safe,
    attr: attr,
    slugify: slugify,
    getCurrentSession: function () { return currentSession; },
    getCurrentAuthUser: function () { return currentAuthUser; },
    getCurrentProfile: function () { return currentProfile; },
    getCurrentTenant: function () { return currentTenant; },
    getCurrentTenantId: function () { return currentTenant ? currentTenant.id : null; }
  };
})();
