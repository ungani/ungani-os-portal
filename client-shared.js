(function () {
  const SUPABASE_URL = "https://ctmtjwklltnsmfdtvqhl.supabase.co";
  const SUPABASE_KEY = "sb_publishable_jkZaWWep-cObTEv_F_kN6g_Ic85BxD9";

  const BRAND = {
    navy: "#061C3D",
    navy2: "#082852",
    gold: "#D4A63A",
    offWhite: "#F5F5F3",
    white: "#FFFFFF",
    gray: "#E5E7EB",
    green: "#15803D",
    orange: "#C77700",
    red: "#B91C1C"
  };

  const state = {
    supabaseClient: null,
    authUser: null,
    userProfile: null,
    tenant: null,
    tenantId: null,
    contentEl: null,
    shellEl: null,
    currentPageKey: "",
    currentPageTitle: "UNGANI OS",
    currentPageSubtitle: "",
    currentTheme: localStorage.getItem("ungani_theme") || localStorage.getItem("ungani_client_theme") || "light"
  };

  injectEarlyBranding();
  injectSharedStyles();
  exposeGlobals();

  function injectEarlyBranding() {
    document.documentElement.style.background = BRAND.navy;
    document.documentElement.style.minHeight = "100%";
    document.documentElement.dataset.unganiTheme = state.currentTheme;

    const earlyStyle = document.createElement("style");
    earlyStyle.id = "ungani-early-style";
    earlyStyle.textContent = `
      html,
      body {
        min-height: 100%;
        margin: 0;
        background: ${BRAND.navy};
      }

      body {
        opacity: 1;
      }
    `;

    if (document.head) {
      document.head.appendChild(earlyStyle);
    }
  }

  function injectSharedStyles() {
    if (document.getElementById("ungani-client-shared-styles")) {
      return;
    }

    const style = document.createElement("style");
    style.id = "ungani-client-shared-styles";

    style.textContent = `
      :root {
        --ungani-navy: ${BRAND.navy};
        --ungani-navy-2: ${BRAND.navy2};
        --ungani-gold: ${BRAND.gold};
        --ungani-offwhite: ${BRAND.offWhite};
        --ungani-white: ${BRAND.white};
        --ungani-gray: ${BRAND.gray};
        --ungani-green: ${BRAND.green};
        --ungani-orange: ${BRAND.orange};
        --ungani-red: ${BRAND.red};

        --ungani-bg: #F5F5F3;
        --ungani-card: #FFFFFF;
        --ungani-text: #061C3D;
        --ungani-muted: #64748B;
        --ungani-border: rgba(6, 28, 61, 0.12);
        --ungani-soft: rgba(6, 28, 61, 0.045);
        --ungani-shadow: 0 18px 45px rgba(6, 28, 61, 0.10);
        --ungani-shadow-hover: 0 24px 60px rgba(6, 28, 61, 0.18);
      }

      html[data-ungani-theme="dark"] {
        --ungani-bg: #061426;
        --ungani-card: #0B2346;
        --ungani-text: #FFFFFF;
        --ungani-muted: #CBD5E1;
        --ungani-border: rgba(255, 255, 255, 0.12);
        --ungani-soft: rgba(255, 255, 255, 0.06);
        --ungani-shadow: 0 18px 45px rgba(0, 0, 0, 0.28);
        --ungani-shadow-hover: 0 24px 70px rgba(0, 0, 0, 0.38);
      }

      * {
        box-sizing: border-box;
      }

      html {
        min-height: 100%;
        background: var(--ungani-bg);
        scroll-behavior: smooth;
      }

      body {
        min-height: 100%;
        margin: 0;
        background:
          radial-gradient(circle at top left, rgba(212,166,58,0.14), transparent 32%),
          radial-gradient(circle at top right, rgba(6,28,61,0.10), transparent 30%),
          var(--ungani-bg);
        color: var(--ungani-text);
        font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
        transition: background 0.25s ease, color 0.25s ease;
      }

      a {
        color: inherit;
        text-decoration: none;
      }

      button,
      input,
      select,
      textarea {
        font: inherit;
      }

      .ungani-preloader,
      .ungani-login-wrap {
        min-height: 100vh;
        width: 100%;
        background:
          radial-gradient(circle at 20% 20%, rgba(212,166,58,0.30), transparent 28%),
          radial-gradient(circle at 80% 10%, rgba(255,255,255,0.10), transparent 22%),
          linear-gradient(135deg, #061C3D 0%, #082852 52%, #061C3D 100%);
        color: white;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 24px;
      }

      .ungani-loader-card,
      .ungani-login-card {
        width: min(460px, 100%);
        background: rgba(255,255,255,0.10);
        border: 1px solid rgba(255,255,255,0.18);
        border-radius: 28px;
        padding: 32px;
        box-shadow: 0 30px 90px rgba(0,0,0,0.28);
        backdrop-filter: blur(16px);
        animation: unganiFadeUp 0.42s ease both;
      }

      .ungani-loader-logo,
      .ungani-login-logo {
        display: flex;
        align-items: center;
        gap: 14px;
        margin-bottom: 18px;
      }

      .ungani-loader-logo img,
      .ungani-login-logo img {
        width: 58px;
        height: 58px;
        object-fit: contain;
        border-radius: 18px;
        background: white;
        padding: 8px;
      }

      .ungani-loader-logo strong,
      .ungani-login-logo strong {
        display: block;
        font-size: 23px;
        letter-spacing: 0.08em;
      }

      .ungani-loader-logo span,
      .ungani-login-logo span {
        color: rgba(255,255,255,0.75);
        font-size: 13px;
      }

      .ungani-loading-bar {
        height: 8px;
        width: 100%;
        overflow: hidden;
        border-radius: 999px;
        background: rgba(255,255,255,0.16);
        margin-top: 22px;
      }

      .ungani-loading-bar div {
        height: 100%;
        width: 45%;
        border-radius: 999px;
        background: linear-gradient(90deg, transparent, var(--ungani-gold), transparent);
        animation: unganiLoadingSlide 1.15s ease-in-out infinite;
      }

      .ungani-login-card label {
        display: block;
        margin: 14px 0 7px;
        color: rgba(255,255,255,0.86);
        font-size: 13px;
        font-weight: 700;
      }

      .ungani-login-card input {
        width: 100%;
        border: 1px solid rgba(255,255,255,0.22);
        background: rgba(255,255,255,0.12);
        color: white;
        border-radius: 14px;
        padding: 13px 14px;
        outline: none;
      }

      .ungani-login-card input::placeholder {
        color: rgba(255,255,255,0.58);
      }

      .ungani-app-shell {
        min-height: 100vh;
        display: grid;
        grid-template-columns: 292px minmax(0, 1fr);
        background: var(--ungani-bg);
        color: var(--ungani-text);
      }

      .ungani-sidebar {
        position: sticky;
        top: 0;
        height: 100vh;
        overflow: auto;
        padding: 20px 16px;
        background:
          radial-gradient(circle at 20% 0%, rgba(212,166,58,0.22), transparent 30%),
          linear-gradient(180deg, #061C3D 0%, #082852 58%, #061C3D 100%);
        color: white;
        box-shadow: 18px 0 50px rgba(6, 28, 61, 0.16);
        z-index: 30;
      }

      .ungani-sidebar::-webkit-scrollbar {
        width: 7px;
      }

      .ungani-sidebar::-webkit-scrollbar-thumb {
        background: rgba(255,255,255,0.22);
        border-radius: 999px;
      }

      .ungani-brand {
        display: flex;
        align-items: center;
        gap: 12px;
        padding: 10px 10px 18px;
        border-bottom: 1px solid rgba(255,255,255,0.13);
        margin-bottom: 16px;
      }

      .ungani-brand img {
        width: 54px;
        height: 54px;
        object-fit: contain;
        border-radius: 16px;
        background: #FFFFFF;
        padding: 7px;
        box-shadow: 0 12px 28px rgba(0,0,0,0.20);
      }

      .ungani-brand strong {
        display: block;
        font-size: 18px;
        letter-spacing: 0.08em;
      }

      .ungani-brand span {
        display: block;
        color: rgba(255,255,255,0.72);
        font-size: 12px;
        margin-top: 3px;
      }

      .ungani-nav-group {
        margin: 18px 0;
      }

      .ungani-nav-title {
        padding: 0 11px 8px;
        color: rgba(255,255,255,0.52);
        font-size: 11px;
        font-weight: 800;
        letter-spacing: 0.11em;
        text-transform: uppercase;
      }

      .ungani-nav-link {
        position: relative;
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 11px 12px;
        border-radius: 15px;
        color: rgba(255,255,255,0.80);
        margin-bottom: 5px;
        transition: transform 0.18s ease, background 0.18s ease, color 0.18s ease, box-shadow 0.18s ease;
      }

      .ungani-nav-link:hover {
        transform: translateX(4px);
        background: rgba(255,255,255,0.10);
        color: #FFFFFF;
      }

      .ungani-nav-link.active {
        color: #061C3D;
        background: linear-gradient(135deg, #FFFFFF, #F8E7B5);
        box-shadow: 0 16px 34px rgba(212,166,58,0.26);
      }

      .ungani-nav-icon {
        width: 27px;
        height: 27px;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        border-radius: 11px;
        background: rgba(255,255,255,0.12);
        font-size: 14px;
      }

      .ungani-nav-link.active .ungani-nav-icon {
        background: rgba(6,28,61,0.08);
      }

      .ungani-sidebar-footer {
        border-top: 1px solid rgba(255,255,255,0.13);
        padding: 16px 10px 8px;
        margin-top: 18px;
      }

      .ungani-tenant-chip {
        display: flex;
        gap: 10px;
        align-items: center;
        padding: 12px;
        border-radius: 18px;
        background: rgba(255,255,255,0.09);
        border: 1px solid rgba(255,255,255,0.13);
        margin-bottom: 12px;
      }

      .ungani-avatar {
        width: 38px;
        height: 38px;
        border-radius: 14px;
        background: var(--ungani-gold);
        color: #061C3D;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        font-weight: 900;
      }

      .ungani-tenant-chip strong {
        display: block;
        font-size: 13px;
      }

      .ungani-tenant-chip span {
        display: block;
        font-size: 11px;
        color: rgba(255,255,255,0.65);
        margin-top: 2px;
      }

      .ungani-main {
        min-width: 0;
        padding: 22px;
      }

      .ungani-topbar {
        position: sticky;
        top: 0;
        z-index: 20;
        background: rgba(245,245,243,0.82);
        border: 1px solid var(--ungani-border);
        border-radius: 24px;
        padding: 18px 20px;
        margin-bottom: 22px;
        backdrop-filter: blur(18px);
        box-shadow: 0 12px 34px rgba(6,28,61,0.08);
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 16px;
      }

      html[data-ungani-theme="dark"] .ungani-topbar {
        background: rgba(6,20,38,0.84);
      }

      .ungani-topbar h2 {
        margin: 0;
        font-size: clamp(22px, 2.4vw, 34px);
        line-height: 1.1;
      }

      .ungani-topbar p {
        margin: 6px 0 0;
        color: var(--ungani-muted);
        font-size: 14px;
      }

      .ungani-top-actions {
        display: flex;
        align-items: center;
        gap: 10px;
        flex-wrap: wrap;
        justify-content: flex-end;
      }

      .ungani-mobile-menu {
        display: none;
      }

      .ungani-content {
        animation: unganiFadeUp 0.28s ease both;
      }

      .ungani-card {
        background:
          linear-gradient(180deg, rgba(255,255,255,0.04), transparent),
          var(--ungani-card);
        border: 1px solid var(--ungani-border);
        border-radius: 24px;
        padding: 20px;
        box-shadow: var(--ungani-shadow);
        margin-bottom: 18px;
        transition: transform 0.20s ease, box-shadow 0.20s ease, border-color 0.20s ease, background 0.20s ease;
      }

      .ungani-card:hover {
        transform: translateY(-3px);
        box-shadow: var(--ungani-shadow-hover);
        border-color: rgba(212,166,58,0.38);
      }

      .ungani-hero {
        overflow: hidden;
        position: relative;
        background:
          radial-gradient(circle at top right, rgba(212,166,58,0.20), transparent 28%),
          linear-gradient(135deg, var(--ungani-navy) 0%, var(--ungani-navy-2) 58%, var(--ungani-navy) 100%);
        color: white;
        border: 1px solid rgba(255,255,255,0.12);
      }

      .ungani-hero::after {
        content: "";
        position: absolute;
        right: -90px;
        top: -90px;
        width: 230px;
        height: 230px;
        border-radius: 50%;
        border: 42px solid rgba(212,166,58,0.12);
        pointer-events: none;
      }

      .ungani-hero h2,
      .ungani-hero h3 {
        margin-top: 0;
        color: white;
      }

      .ungani-hero p {
        color: rgba(255,255,255,0.78);
        max-width: 920px;
      }

      .ungani-grid {
        display: grid;
        grid-template-columns: repeat(4, minmax(0, 1fr));
        gap: 16px;
        margin-bottom: 18px;
      }

      .ungani-two-col {
        display: grid;
        grid-template-columns: minmax(0, 1.2fr) minmax(320px, 0.8fr);
        gap: 18px;
        align-items: start;
        margin-bottom: 18px;
      }

      .ungani-metric {
        position: relative;
        overflow: hidden;
        min-height: 142px;
        cursor: default;
      }

      .ungani-metric::before {
        content: "";
        position: absolute;
        inset: auto -40px -55px auto;
        width: 130px;
        height: 130px;
        border-radius: 50%;
        background: rgba(212,166,58,0.13);
        transition: transform 0.22s ease, opacity 0.22s ease;
      }

      .ungani-metric:hover::before {
        transform: scale(1.18);
        opacity: 0.95;
      }

      .ungani-metric.clickable {
        cursor: pointer;
      }

      .ungani-metric.clickable:hover {
        transform: translateY(-6px);
      }

      .ungani-metric-top {
        position: relative;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 12px;
        margin-bottom: 18px;
      }

      .ungani-metric-label {
        color: var(--ungani-muted);
        font-size: 13px;
        font-weight: 800;
        letter-spacing: 0.04em;
        text-transform: uppercase;
      }

      .ungani-metric-icon {
        width: 42px;
        height: 42px;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        border-radius: 16px;
        color: white;
        font-size: 18px;
        background: var(--ungani-navy);
        box-shadow: 0 12px 24px rgba(6,28,61,0.20);
      }

      .ungani-metric-value {
        position: relative;
        font-size: clamp(24px, 3vw, 36px);
        line-height: 1;
        margin: 0 0 10px;
        font-weight: 900;
        letter-spacing: -0.04em;
      }

      .ungani-metric-subtitle {
        position: relative;
        margin: 0;
        color: var(--ungani-muted);
        font-size: 13px;
      }

      .ungani-metric.green .ungani-metric-icon { background: var(--ungani-green); }
      .ungani-metric.gold .ungani-metric-icon { background: var(--ungani-gold); color: var(--ungani-navy); }
      .ungani-metric.orange .ungani-metric-icon { background: var(--ungani-orange); }
      .ungani-metric.red .ungani-metric-icon { background: var(--ungani-red); }
      .ungani-metric.blue .ungani-metric-icon { background: var(--ungani-navy); }

      .ungani-section-title {
        display: flex;
        align-items: flex-start;
        justify-content: space-between;
        gap: 14px;
        margin-bottom: 16px;
      }

      .ungani-section-title h3 {
        margin: 0;
        font-size: 20px;
      }

      .ungani-section-title p {
        margin: 5px 0 0;
      }

      .ungani-small {
        color: var(--ungani-muted);
        font-size: 13px;
        line-height: 1.55;
      }

      .ungani-form-grid {
        display: grid;
        grid-template-columns: repeat(2, minmax(0, 1fr));
        gap: 14px;
      }

      label {
        display: block;
        margin: 12px 0 7px;
        color: var(--ungani-muted);
        font-size: 13px;
        font-weight: 800;
      }

      input,
      select,
      textarea {
        width: 100%;
        border: 1px solid var(--ungani-border);
        background: var(--ungani-card);
        color: var(--ungani-text);
        border-radius: 15px;
        padding: 12px 13px;
        outline: none;
        transition: border-color 0.18s ease, box-shadow 0.18s ease, transform 0.18s ease;
      }

      input:focus,
      select:focus,
      textarea:focus {
        border-color: var(--ungani-gold);
        box-shadow: 0 0 0 4px rgba(212,166,58,0.15);
      }

      textarea {
        min-height: 120px;
        resize: vertical;
      }

      .ungani-button-row {
        display: flex;
        flex-wrap: wrap;
        align-items: center;
        gap: 10px;
        margin-top: 14px;
      }

      .ungani-btn {
        border: 0;
        border-radius: 14px;
        padding: 11px 15px;
        background: var(--ungani-navy);
        color: #FFFFFF;
        font-weight: 850;
        cursor: pointer;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 8px;
        box-shadow: 0 12px 24px rgba(6,28,61,0.15);
        transition: transform 0.18s ease, box-shadow 0.18s ease, filter 0.18s ease;
      }

      .ungani-btn:hover {
        transform: translateY(-2px);
        box-shadow: 0 18px 34px rgba(6,28,61,0.22);
        filter: brightness(1.04);
      }

      .ungani-btn.green { background: var(--ungani-green); }
      .ungani-btn.gold { background: var(--ungani-gold); color: var(--ungani-navy); }
      .ungani-btn.orange { background: var(--ungani-orange); }
      .ungani-btn.red { background: var(--ungani-red); }
      .ungani-btn.dark { background: #0F172A; color: #FFFFFF; }
      .ungani-btn.light { background: rgba(255,255,255,0.12); color: #FFFFFF; border: 1px solid rgba(255,255,255,0.16); }

      .ungani-badge {
        display: inline-flex;
        align-items: center;
        justify-content: center;
        gap: 6px;
        padding: 7px 10px;
        border-radius: 999px;
        font-size: 12px;
        font-weight: 850;
        text-transform: capitalize;
        background: rgba(6,28,61,0.08);
        color: var(--ungani-navy);
        margin: 2px;
      }

      html[data-ungani-theme="dark"] .ungani-badge {
        color: white;
      }

      .ungani-badge.blue { background: rgba(6,28,61,0.12); color: var(--ungani-navy); }
      .ungani-badge.gold { background: rgba(212,166,58,0.18); color: #7A5200; }
      .ungani-badge.green { background: rgba(21,128,61,0.15); color: var(--ungani-green); }
      .ungani-badge.orange { background: rgba(199,119,0,0.16); color: var(--ungani-orange); }
      .ungani-badge.red { background: rgba(185,28,28,0.15); color: var(--ungani-red); }

      html[data-ungani-theme="dark"] .ungani-badge.blue,
      html[data-ungani-theme="dark"] .ungani-badge.gold,
      html[data-ungani-theme="dark"] .ungani-badge.green,
      html[data-ungani-theme="dark"] .ungani-badge.orange,
      html[data-ungani-theme="dark"] .ungani-badge.red {
        color: white;
      }

      .ungani-empty {
        border: 1px dashed var(--ungani-border);
        border-radius: 20px;
        padding: 26px;
        text-align: center;
        background: var(--ungani-soft);
      }

      .ungani-empty h3 {
        margin: 0 0 8px;
      }

      .ungani-toast {
        position: fixed;
        right: 20px;
        bottom: 20px;
        z-index: 9999;
        max-width: 360px;
        background: var(--ungani-navy);
        color: white;
        border: 1px solid rgba(255,255,255,0.15);
        border-radius: 18px;
        padding: 14px 16px;
        box-shadow: 0 18px 50px rgba(0,0,0,0.24);
        animation: unganiToastIn 0.24s ease both;
      }

      .ungani-top-mini {
        display: flex;
        align-items: center;
        gap: 9px;
        color: var(--ungani-muted);
        font-size: 12px;
        font-weight: 750;
      }

      .ungani-pulse-dot {
        width: 9px;
        height: 9px;
        border-radius: 50%;
        background: var(--ungani-green);
        box-shadow: 0 0 0 0 rgba(21,128,61,0.50);
        animation: unganiPulse 1.7s infinite;
      }

      .ungani-shell-fade {
        animation: unganiFadeUp 0.28s ease both;
      }

      @keyframes unganiFadeUp {
        from {
          opacity: 0;
          transform: translateY(10px);
        }

        to {
          opacity: 1;
          transform: translateY(0);
        }
      }

      @keyframes unganiLoadingSlide {
        0% {
          transform: translateX(-110%);
        }

        100% {
          transform: translateX(260%);
        }
      }

      @keyframes unganiToastIn {
        from {
          opacity: 0;
          transform: translateY(12px);
        }

        to {
          opacity: 1;
          transform: translateY(0);
        }
      }

      @keyframes unganiPulse {
        0% {
          box-shadow: 0 0 0 0 rgba(21,128,61,0.50);
        }

        70% {
          box-shadow: 0 0 0 10px rgba(21,128,61,0);
        }

        100% {
          box-shadow: 0 0 0 0 rgba(21,128,61,0);
        }
      }

      @media (max-width: 1180px) {
        .ungani-grid {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }

        .ungani-two-col {
          grid-template-columns: 1fr;
        }
      }

      @media (max-width: 860px) {
        .ungani-app-shell {
          grid-template-columns: 1fr;
        }

        .ungani-sidebar {
          position: fixed;
          left: 0;
          top: 0;
          bottom: 0;
          width: min(315px, 86vw);
          transform: translateX(-104%);
          transition: transform 0.24s ease;
        }

        body.ungani-sidebar-open .ungani-sidebar {
          transform: translateX(0);
        }

        .ungani-mobile-menu {
          display: inline-flex;
        }

        .ungani-main {
          padding: 14px;
        }

        .ungani-topbar {
          position: relative;
          border-radius: 20px;
          align-items: flex-start;
        }

        .ungani-grid,
        .ungani-form-grid {
          grid-template-columns: 1fr;
        }
      }

      @media (max-width: 560px) {
        .ungani-topbar {
          flex-direction: column;
        }

        .ungani-top-actions {
          justify-content: flex-start;
        }

        .ungani-card {
          padding: 16px;
          border-radius: 20px;
        }

        .ungani-section-title {
          flex-direction: column;
        }
      }
    `;

    document.head.appendChild(style);
  }

  async function initPage(config) {
    state.currentPageKey = config.pageKey || "";
    state.currentPageTitle = config.pageTitle || "UNGANI OS";
    state.currentPageSubtitle = config.pageSubtitle || "";

    applyTheme(state.currentTheme);
    showPreloader("Loading UNGANI OS...");

    try {
      if (!window.supabase || !window.supabase.createClient) {
        showFatalError("Supabase could not load", "Please refresh the page and check your internet connection.");
        return;
      }

      state.supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

      const sessionResponse = await state.supabaseClient.auth.getSession();
      const session = sessionResponse && sessionResponse.data ? sessionResponse.data.session : null;

      if (!session || !session.user) {
        renderLoginScreen();
        return;
      }

      state.authUser = session.user;
      state.userProfile = await loadUserProfile(session.user);
      state.tenantId = await resolveTenantId(session.user, state.userProfile);

      if (!state.tenantId) {
        renderLoginProblem(
          "Your account is signed in, but no business workspace was found.",
          "Please contact UNGANI so your user can be connected to the correct business."
        );
        return;
      }

      state.tenant = await loadTenant(state.tenantId);

      if (!state.tenant) {
        renderLoginProblem(
          "Business workspace not found.",
          "Please contact UNGANI support to confirm your client account."
        );
        return;
      }

      await loadSavedSettings();

      renderShell(config);
      const context = makeContext();

      if (typeof config.onReady === "function") {
        await config.onReady(context);
      }
    } catch (error) {
      showFatalError("Could not open this page", error.message || "Unknown error");
    }
  }

  function showPreloader(message) {
    document.body.className = "";
    document.body.innerHTML = `
      <div class="ungani-preloader">
        <div class="ungani-loader-card">
          <div class="ungani-loader-logo">
            <img src="ungani-logo.png" alt="UNGANI Logo" />
            <div>
              <strong>UNGANI</strong>
              <span>Business operations workspace</span>
            </div>
          </div>

          <h2 style="margin:0 0 8px;">${safe(message || "Loading...")}</h2>
          <p style="margin:0;color:rgba(255,255,255,0.72);line-height:1.6;">
            Preparing your business dashboard, records, tasks, reports, and support workspace.
          </p>

          <div class="ungani-loading-bar"><div></div></div>
        </div>
      </div>
    `;
  }

  function renderLoginScreen() {
    document.body.className = "";
    document.body.innerHTML = `
      <div class="ungani-login-wrap">
        <div class="ungani-login-card">
          <div class="ungani-login-logo">
            <img src="ungani-logo.png" alt="UNGANI Logo" />
            <div>
              <strong>UNGANI</strong>
              <span>Client Portal</span>
            </div>
          </div>

          <h2 style="margin:0 0 8px;">Sign in to your workspace</h2>
          <p style="margin:0 0 18px;color:rgba(255,255,255,0.72);line-height:1.6;">
            Access your business dashboard, records, tasks, documents, calendar, reports, and support tools.
          </p>

          <form onsubmit="UnganiClientShared.signInFromForm(event)">
            <label for="unganiLoginEmail">Email Address</label>
            <input id="unganiLoginEmail" type="email" required placeholder="you@example.com" />

            <label for="unganiLoginPassword">Password</label>
            <input id="unganiLoginPassword" type="password" required placeholder="Enter your password" />

            <div id="unganiLoginError" style="display:none;margin-top:14px;color:#FCA5A5;font-weight:700;"></div>

            <div class="ungani-button-row">
              <button class="ungani-btn gold" type="submit">Sign In</button>
              <a class="ungani-btn light" href="index.html">Register Business</a>
            </div>
          </form>

          <p style="margin:18px 0 0;color:rgba(255,255,255,0.60);font-size:12px;">
            ungani.com · info@ungani.com
          </p>
        </div>
      </div>
    `;
  }

  async function signInFromForm(event) {
    event.preventDefault();

    const email = value("unganiLoginEmail");
    const password = value("unganiLoginPassword");
    const errorEl = document.getElementById("unganiLoginError");

    if (errorEl) {
      errorEl.style.display = "none";
      errorEl.textContent = "";
    }

    if (!state.supabaseClient) {
      state.supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
    }

    const response = await state.supabaseClient.auth.signInWithPassword({
      email,
      password
    });

    if (response.error) {
      if (errorEl) {
        errorEl.style.display = "block";
        errorEl.textContent = response.error.message;
      }

      return;
    }

    showPreloader("Opening your workspace...");
    window.location.reload();
  }

  function renderLoginProblem(title, message) {
    document.body.className = "";
    document.body.innerHTML = `
      <div class="ungani-login-wrap">
        <div class="ungani-login-card">
          <div class="ungani-login-logo">
            <img src="ungani-logo.png" alt="UNGANI Logo" />
            <div>
              <strong>UNGANI</strong>
              <span>Client Portal</span>
            </div>
          </div>

          <h2 style="margin:0 0 8px;">${safe(title)}</h2>
          <p style="margin:0 0 18px;color:rgba(255,255,255,0.72);line-height:1.6;">
            ${safe(message)}
          </p>

          <div class="ungani-button-row">
            <button class="ungani-btn gold" onclick="UnganiClientShared.logout()">Sign Out</button>
            <a class="ungani-btn light" href="mailto:info@ungani.com">Contact UNGANI</a>
          </div>
        </div>
      </div>
    `;
  }

  function renderShell(config) {
    const tenantName = getTenantName(state.tenant);
    const initials = makeInitials(tenantName);
    const pageTitle = config.pageTitle || "UNGANI OS";
    const pageSubtitle = config.pageSubtitle || "";

    document.body.className = "ungani-shell-fade";
    document.body.innerHTML = `
      <div class="ungani-app-shell" id="unganiAppShell">
        <aside class="ungani-sidebar">
          <a class="ungani-brand" href="client.html">
            <img src="ungani-logo.png" alt="UNGANI Logo" />
            <div>
              <strong>UNGANI</strong>
              <span>Connecting • Moving • Helping</span>
            </div>
          </a>

          ${renderSidebarNav()}

          <div class="ungani-sidebar-footer">
            <div class="ungani-tenant-chip">
              <div class="ungani-avatar">${safe(initials)}</div>
              <div>
                <strong>${safe(tenantName)}</strong>
                <span>${safe(getBusinessTypeLabel(state.tenant))}</span>
              </div>
            </div>

            <div class="ungani-button-row" style="margin-top:10px;">
              <button class="ungani-btn gold" type="button" onclick="UnganiClientShared.toggleTheme()">Theme</button>
              <button class="ungani-btn light" type="button" onclick="UnganiClientShared.logout()">Logout</button>
            </div>

            <p style="font-size:11px;color:rgba(255,255,255,0.52);line-height:1.5;margin:14px 2px 0;">
              Client Shared Version: Step 308A Premium Styling
            </p>
          </div>
        </aside>

        <main class="ungani-main">
          <header class="ungani-topbar">
            <div>
              <h2>${safe(pageTitle)}</h2>
              <p>${safe(pageSubtitle)}</p>
            </div>

            <div class="ungani-top-actions">
              <div class="ungani-top-mini">
                <span class="ungani-pulse-dot"></span>
                Live workspace
              </div>
              <button class="ungani-btn dark ungani-mobile-menu" type="button" onclick="UnganiClientShared.toggleSidebar()">Menu</button>
              <a class="ungani-btn" href="client.html">Dashboard</a>
              <a class="ungani-btn green" href="reports.html">Reports</a>
            </div>
          </header>

          <div class="ungani-content" id="unganiContent">
            ${loadingCard("Loading page content...")}
          </div>
        </main>
      </div>
    `;

    state.shellEl = document.getElementById("unganiAppShell");
    state.contentEl = document.getElementById("unganiContent");
  }

  function renderSidebarNav() {
    const groups = [
      {
        title: "Main",
        items: [
          ["dashboard", "client.html", "🏠", "Dashboard"],
          ["overview", "my-overview.html", "📌", "Overview"],
          ["activity", "my-activity.html", "🕒", "Activity Feed"],
          ["charts", "my-charts.html", "📊", "Charts"]
        ]
      },
      {
        title: "Operations",
        items: [
          ["money", "my-money.html", "💰", "Money Records"],
          ["records", "my-records.html", "🗂️", "Business Records"],
          ["items", "my-items.html", "🏷️", "Items / Assets / Stock"],
          ["people", "my-people.html", "👥", "People"],
          ["tasks", "my-tasks.html", "✅", "Tasks / Follow-ups"],
          ["calendar", "my-calendar.html", "📅", "Calendar"],
          ["documents", "my-documents.html", "📄", "Documents"]
        ]
      },
      {
        title: "Support",
        items: [
          ["support", "my-support.html", "🛟", "Support Issues"],
          ["notices", "my-notices.html", "🔔", "Notices"],
          ["chat", "my-chat.html", "💬", "Chat with UNGANI"],
          ["team-chat", "my-team-chat.html", "👨‍👩‍👧‍👦", "Team Chat"]
        ]
      },
      {
        title: "Reports & Account",
        items: [
          ["reports", "reports.html", "📑", "Reports"],
          ["print-report", "print-report.html", "🖨️", "Print Report"],
          ["profile", "my-profile.html", "🏢", "Business Profile"],
          ["account", "account.html", "⚙️", "Account Settings"]
        ]
      }
    ];

    return groups.map(function (group) {
      return `
        <div class="ungani-nav-group">
          <div class="ungani-nav-title">${safe(group.title)}</div>
          ${group.items.map(function (item) {
            const active = item[0] === state.currentPageKey ? "active" : "";

            return `
              <a class="ungani-nav-link ${active}" href="${attr(item[1])}">
                <span class="ungani-nav-icon">${safe(item[2])}</span>
                <span>${safe(item[3])}</span>
              </a>
            `;
          }).join("")}
        </div>
      `;
    }).join("");
  }

  async function loadUserProfile(authUser) {
    const attempts = [
      { column: "auth_user_id", value: authUser.id },
      { column: "user_id", value: authUser.id },
      { column: "id", value: authUser.id },
      { column: "email", value: authUser.email }
    ];

    for (const attempt of attempts) {
      try {
        const response = await state.supabaseClient
          .from("users")
          .select("*")
          .eq(attempt.column, attempt.value)
          .limit(1)
          .maybeSingle();

        if (!response.error && response.data) {
          return response.data;
        }
      } catch (error) {
        console.warn("User profile lookup skipped:", attempt.column, error.message);
      }
    }

    return {
      email: authUser.email,
      auth_user_id: authUser.id
    };
  }

  async function resolveTenantId(authUser, profile) {
    const possible = [
      getValue(profile, ["tenant_id"], null),
      getValue(profile, ["client_id"], null),
      getValue(authUser, ["user_metadata", "tenant_id"], null),
      getValue(authUser, ["app_metadata", "tenant_id"], null)
    ].filter(Boolean);

    if (possible.length > 0) {
      return possible[0];
    }

    try {
      const response = await state.supabaseClient.rpc("get_my_ungani_tenant_id");

      if (!response.error && response.data) {
        return response.data;
      }
    } catch (error) {
      console.warn("Tenant RPC skipped:", error.message);
    }

    return null;
  }

  async function loadTenant(tenantId) {
    try {
      const response = await state.supabaseClient
        .from("tenants")
        .select("*")
        .eq("id", tenantId)
        .limit(1)
        .maybeSingle();

      if (response.error) {
        console.warn("Tenant lookup error:", response.error.message);
        return null;
      }

      return response.data;
    } catch (error) {
      console.warn("Tenant lookup failed:", error.message);
      return null;
    }
  }

  async function loadSavedSettings() {
    const localTheme = localStorage.getItem("ungani_theme") || localStorage.getItem("ungani_client_theme");

    if (localTheme) {
      applyTheme(localTheme);
    }

    try {
      const response = await state.supabaseClient
        .from("client_settings")
        .select("*")
        .eq("tenant_id", state.tenantId)
        .limit(1)
        .maybeSingle();

      if (!response.error && response.data) {
        const theme = getValue(response.data, ["theme", "appearance", "selected_theme"], null);

        if (theme) {
          applyTheme(theme);
        }
      }
    } catch (error) {
      console.warn("Client settings skipped:", error.message);
    }
  }

  function makeContext() {
    return {
      supabaseClient: state.supabaseClient,
      authUser: state.authUser,
      userProfile: state.userProfile,
      tenant: state.tenant,
      tenantId: state.tenantId,
      contentEl: state.contentEl,
      shellEl: state.shellEl
    };
  }

  function setContent(html) {
    if (!state.contentEl) {
      state.contentEl = document.getElementById("unganiContent");
    }

    if (state.contentEl) {
      state.contentEl.innerHTML = html;
      state.contentEl.classList.remove("ungani-content");
      void state.contentEl.offsetWidth;
      state.contentEl.classList.add("ungani-content");
    }
  }

  function loadingCard(message) {
    return `
      <section class="ungani-card">
        <div class="ungani-section-title">
          <div>
            <h3>${safe(message || "Loading...")}</h3>
            <p class="ungani-small">Please wait while UNGANI prepares this section.</p>
          </div>
          <span class="ungani-badge gold">Loading</span>
        </div>
        <div class="ungani-loading-bar" style="background:rgba(6,28,61,0.08);"><div></div></div>
      </section>
    `;
  }

  function errorCard(title, message) {
    return `
      <section class="ungani-card">
        <div class="ungani-section-title">
          <div>
            <h3>${safe(title || "Something went wrong")}</h3>
            <p class="ungani-small">${safe(message || "Please refresh the page and try again.")}</p>
          </div>
          <span class="ungani-badge red">Error</span>
        </div>
        <button class="ungani-btn" onclick="window.location.reload()">Refresh Page</button>
      </section>
    `;
  }

  function showFatalError(title, message) {
    document.body.innerHTML = `
      <div class="ungani-preloader">
        <div class="ungani-loader-card">
          <div class="ungani-loader-logo">
            <img src="ungani-logo.png" alt="UNGANI Logo" />
            <div>
              <strong>UNGANI</strong>
              <span>Client Portal</span>
            </div>
          </div>

          <h2 style="margin:0 0 8px;">${safe(title)}</h2>
          <p style="margin:0 0 18px;color:rgba(255,255,255,0.72);line-height:1.6;">
            ${safe(message)}
          </p>

          <button class="ungani-btn gold" onclick="window.location.reload()">Refresh Page</button>
        </div>
      </div>
    `;
  }

  function metricCard(title, valueText, subtitle, color, href) {
    const selectedColor = color || "blue";
    const icon = metricIcon(title);
    const card = `
      <div class="ungani-card ungani-metric ${attr(selectedColor)} ${href ? "clickable" : ""}">
        <div class="ungani-metric-top">
          <div class="ungani-metric-label">${safe(title)}</div>
          <div class="ungani-metric-icon">${safe(icon)}</div>
        </div>

        <h3 class="ungani-metric-value">${safe(valueText)}</h3>
        <p class="ungani-metric-subtitle">${safe(subtitle || "")}</p>
      </div>
    `;

    if (href) {
      return `<a href="${attr(href)}">${card}</a>`;
    }

    return card;
  }

  function metricIcon(title) {
    const lower = String(title || "").toLowerCase();

    if (lower.includes("money") || lower.includes("income") || lower.includes("expense") || lower.includes("balance")) return "💰";
    if (lower.includes("task") || lower.includes("pending")) return "✅";
    if (lower.includes("people") || lower.includes("agent") || lower.includes("lead")) return "👥";
    if (lower.includes("document")) return "📄";
    if (lower.includes("calendar") || lower.includes("event")) return "📅";
    if (lower.includes("support")) return "🛟";
    if (lower.includes("message") || lower.includes("chat")) return "💬";
    if (lower.includes("property") || lower.includes("item") || lower.includes("asset")) return "🏷️";
    if (lower.includes("report")) return "📑";

    return "◆";
  }

  function applyTheme(theme) {
    const cleanTheme = String(theme || "light").toLowerCase().includes("dark") ? "dark" : "light";

    state.currentTheme = cleanTheme;
    localStorage.setItem("ungani_theme", cleanTheme);
    localStorage.setItem("ungani_client_theme", cleanTheme);

    document.documentElement.dataset.unganiTheme = cleanTheme;

    if (document.body) {
      document.body.dataset.unganiTheme = cleanTheme;
    }
  }

  function toggleTheme() {
    const nextTheme = state.currentTheme === "dark" ? "light" : "dark";
    applyTheme(nextTheme);
    showToast(nextTheme === "dark" ? "Dark mode enabled" : "Light mode enabled");
  }

  function toggleSidebar() {
    document.body.classList.toggle("ungani-sidebar-open");
  }

  async function logout() {
    try {
      if (!state.supabaseClient && window.supabase) {
        state.supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
      }

      if (state.supabaseClient) {
        await state.supabaseClient.auth.signOut();
      }
    } catch (error) {
      console.warn("Logout warning:", error.message);
    }

    window.location.href = "client.html";
  }

  function showToast(message) {
    const existing = document.querySelector(".ungani-toast");

    if (existing) {
      existing.remove();
    }

    const toast = document.createElement("div");
    toast.className = "ungani-toast";
    toast.textContent = message || "Done";

    document.body.appendChild(toast);

    setTimeout(function () {
      toast.style.opacity = "0";
      toast.style.transform = "translateY(12px)";

      setTimeout(function () {
        toast.remove();
      }, 220);
    }, 2600);
  }

  function getTenantName(tenant) {
    return getValue(tenant, ["business_name", "name", "company_name", "tenant_name"], "Business Workspace");
  }

  function getBusinessTypeLabel(tenant) {
    return getValue(tenant, ["business_type", "business_type_key"], "Business Operations");
  }

  function makeInitials(valueText) {
    const parts = String(valueText || "U")
      .trim()
      .split(/\s+/)
      .filter(Boolean);

    if (parts.length === 0) return "U";

    if (parts.length === 1) {
      return parts[0].slice(0, 2).toUpperCase();
    }

    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  function value(id) {
    const el = document.getElementById(id);

    if (!el) return "";

    return String(el.value || "").trim();
  }

  function getValue(object, keys, fallback) {
    if (!object) {
      return fallback === undefined ? "" : fallback;
    }

    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];

      if (
        Object.prototype.hasOwnProperty.call(object, key) &&
        object[key] !== null &&
        object[key] !== undefined &&
        object[key] !== ""
      ) {
        return object[key];
      }
    }

    return fallback === undefined ? "" : fallback;
  }

  function formatKES(value) {
    const amount = Number(value || 0);

    try {
      return new Intl.NumberFormat("en-KE", {
        style: "currency",
        currency: "KES",
        maximumFractionDigits: 0
      }).format(amount);
    } catch (error) {
      return "KES " + amount.toLocaleString();
    }
  }

  function formatNumber(value) {
    const amount = Number(value || 0);

    try {
      return new Intl.NumberFormat("en-KE").format(amount);
    } catch (error) {
      return String(amount);
    }
  }

  function formatDate(valueText) {
    if (!valueText) return "—";

    const date = new Date(valueText);

    if (isNaN(date.getTime())) {
      return String(valueText);
    }

    try {
      return new Intl.DateTimeFormat("en-KE", {
        day: "2-digit",
        month: "short",
        year: "numeric"
      }).format(date);
    } catch (error) {
      return date.toISOString().slice(0, 10);
    }
  }

  function formatDateTime(valueText) {
    if (!valueText) return "—";

    const date = new Date(valueText);

    if (isNaN(date.getTime())) {
      return String(valueText);
    }

    try {
      return new Intl.DateTimeFormat("en-KE", {
        day: "2-digit",
        month: "short",
        year: "numeric",
        hour: "2-digit",
        minute: "2-digit"
      }).format(date);
    } catch (error) {
      return date.toISOString();
    }
  }

  function todayISO() {
    return new Date().toISOString().slice(0, 10);
  }

  function safe(valueText) {
    return String(valueText === null || valueText === undefined ? "" : valueText)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  function attr(valueText) {
    return safe(valueText);
  }

  function exposeGlobals() {
    window.UnganiClientShared = {
      initPage,
      setContent,
      loadingCard,
      errorCard,
      metricCard,
      safe,
      attr,
      value,
      getValue,
      formatKES,
      formatCurrency: formatKES,
      formatNumber,
      formatDate,
      formatDateTime,
      todayISO,
      showToast,
      toggleTheme,
      toggleSidebar,
      logout,
      signInFromForm,
      getTenantName,
      getBusinessTypeLabel,
      getCurrentUserId: function () {
        return state.authUser ? state.authUser.id : null;
      },
      getCurrentTenantId: function () {
        return state.tenantId;
      },
      getState: function () {
        return state;
      }
    };
  }
})();
