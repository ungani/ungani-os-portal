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
    red: "#B91C1C",
    blue: "#2563EB"
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
    currentTheme: localStorage.getItem("ungani_theme") || localStorage.getItem("ungani_client_theme") || "light",
    searchTimer: null,
    subscriptionAccess: null,
    readOnlyNotice: null
  };

  injectEarlyBranding();
  injectSharedStyles();
  injectPwaMetaLinks();
  exposeGlobals();

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
        --ungani-blue: ${BRAND.blue};

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
        --ungani-text: #F5F5F3;
        --ungani-muted: #B8C3D6;
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
        border-left: 3px solid transparent;
        transition: transform 0.18s ease, background 0.18s ease, color 0.18s ease, box-shadow 0.18s ease, border-color 0.18s ease;
      }

      .ungani-nav-link:hover {
        transform: translateX(4px);
        background: rgba(255,255,255,0.10);
        color: #FFFFFF;
      }

      .ungani-nav-link.active {
        color: #FFFFFF;
        background: rgba(212,166,58,0.14);
        border-left-color: var(--ungani-gold);
        box-shadow: inset 0 0 0 1px rgba(212,166,58,0.12);
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
        background: rgba(212,166,58,0.22);
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
        background: rgba(245,245,243,0.86);
        border: 1px solid var(--ungani-border);
        border-radius: 24px;
        padding: 16px 18px;
        margin-bottom: 22px;
        backdrop-filter: blur(18px);
        box-shadow: 0 12px 34px rgba(6,28,61,0.08);
        display: grid;
        grid-template-columns: minmax(260px, 1fr) minmax(320px, 0.95fr) auto;
        align-items: center;
        gap: 14px;
      }

      html[data-ungani-theme="dark"] .ungani-topbar {
        background: rgba(6,20,38,0.86);
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
        flex-wrap: wrap;
        justify-content: flex-end;
      }

      .ungani-top-actions > * {
        margin: 4px 0 4px 14px;
      }

      @supports (gap: 1px) {
        .ungani-top-actions {
          gap: 14px;
        }

        .ungani-top-actions > * {
          margin: 0;
        }
      }

      .ungani-mobile-menu {
        display: none;
      }

      .ungani-global-search-wrap {
        position: relative;
        width: 100%;
      }

      .ungani-global-search {
        padding-left: 42px;
        height: 45px;
        background: var(--ungani-card);
        box-shadow: inset 0 0 0 1px rgba(212,166,58,0.04);
      }

      .ungani-search-icon {
        position: absolute;
        left: 14px;
        top: 50%;
        transform: translateY(-50%);
        color: var(--ungani-muted);
        pointer-events: none;
      }

      .ungani-global-results,
      .ungani-notification-panel,
      .ungani-quickadd-panel {
        position: absolute;
        top: calc(100% + 10px);
        right: 0;
        width: min(520px, 92vw);
        background: var(--ungani-card);
        border: 1px solid var(--ungani-border);
        border-radius: 22px;
        box-shadow: 0 26px 70px rgba(6,28,61,0.24);
        overflow: hidden;
        z-index: 80;
        animation: unganiFadeUp 0.18s ease both;
      }

      .ungani-teamchat-panel {
        display: flex;
        flex-direction: column;
        height: min(500px, 72vh);
        width: min(400px, 92vw);
      }

      .ungani-teamchat-messages {
        flex: 1;
        overflow-y: auto;
        padding: 14px;
        display: flex;
        flex-direction: column;
        gap: 10px;
      }

      .ungani-teamchat-bubble {
        max-width: 82%;
        padding: 10px 14px;
        border-radius: 16px;
        font-size: 13px;
        line-height: 1.45;
      }

      .ungani-teamchat-bubble .ungani-teamchat-sender {
        display: block;
        font-size: 11px;
        font-weight: 900;
        text-transform: uppercase;
        letter-spacing: 0.04em;
        margin-bottom: 3px;
        opacity: 0.7;
      }

      .ungani-teamchat-bubble .ungani-teamchat-time {
        display: block;
        font-size: 10px;
        margin-top: 4px;
        opacity: 0.6;
      }

      .ungani-teamchat-bubble.mine {
        align-self: flex-end;
        background: var(--ungani-gold);
        color: var(--ungani-navy);
        border-bottom-right-radius: 4px;
      }

      .ungani-teamchat-bubble.theirs {
        align-self: flex-start;
        background: var(--ungani-soft);
        color: var(--ungani-text);
        border: 1px solid var(--ungani-border);
        border-bottom-left-radius: 4px;
      }

      .ungani-teamchat-input-row {
        display: flex;
        gap: 8px;
        padding: 12px;
        border-top: 1px solid var(--ungani-border);
        background: var(--ungani-soft);
      }

      .ungani-teamchat-input-row input {
        flex: 1;
        border-radius: 999px;
        border: 1px solid var(--ungani-border);
        background: var(--ungani-card);
        color: var(--ungani-text);
        padding: 10px 16px;
        font-size: 13px;
        outline: none;
      }

      .ungani-teamchat-input-row input:focus {
        border-color: var(--ungani-gold);
      }

      .ungani-teamchat-send {
        width: 40px;
        height: 40px;
        border-radius: 999px;
        border: 0;
        background: var(--ungani-gold);
        color: var(--ungani-navy);
        font-weight: 900;
        cursor: pointer;
        flex: 0 0 auto;
      }

      .ungani-teamchat-toast {
        position: fixed;
        right: 18px;
        bottom: 18px;
        z-index: 99999;
        max-width: min(340px, calc(100vw - 32px));
        background: linear-gradient(135deg, rgba(8,38,84,0.98), rgba(6,28,61,0.98));
        color: #FFFFFF;
        border: 1px solid rgba(212,166,58,0.35);
        border-radius: 18px;
        box-shadow: 0 18px 45px rgba(0,0,0,0.35);
        padding: 14px;
        display: flex;
        gap: 11px;
        align-items: flex-start;
        cursor: pointer;
        transform: translateY(14px);
        opacity: 0;
        transition: 0.28s ease;
      }

      .ungani-teamchat-toast.show {
        transform: translateY(0);
        opacity: 1;
      }

      .ungani-teamchat-toast strong {
        display: block;
        color: #D4A63A;
        font-size: 13px;
        margin-bottom: 3px;
      }

      .ungani-teamchat-toast p {
        margin: 0;
        font-size: 13px;
        color: #F5F5F3;
        line-height: 1.4;
      }

      @media (max-width: 640px) {
        .ungani-teamchat-panel {
          position: fixed;
          top: auto;
          bottom: 0;
          left: 0;
          right: 0;
          width: 100%;
          height: min(78vh, 560px);
          border-radius: 22px 22px 0 0;
        }
      }

      .ungani-global-results {
        left: 0;
        right: auto;
      }

      .ungani-panel-head {
        padding: 14px 16px;
        background: var(--ungani-soft);
        border-bottom: 1px solid var(--ungani-border);
        display: flex;
        justify-content: space-between;
        gap: 12px;
        align-items: center;
      }

      .ungani-panel-body {
        max-height: 430px;
        overflow: auto;
        padding: 10px;
      }

      .ungani-search-result,
      .ungani-alert-row {
        display: block;
        padding: 12px;
        border-radius: 16px;
        border: 1px solid transparent;
        transition: background 0.18s ease, border-color 0.18s ease, transform 0.18s ease;
      }

      .ungani-search-result:hover,
      .ungani-alert-row:hover {
        background: var(--ungani-soft);
        border-color: var(--ungani-border);
        transform: translateY(-1px);
      }

      .ungani-icon-button {
        position: relative;
        width: 44px;
        height: 44px;
        border: 0;
        border-radius: 15px;
        background: var(--ungani-card);
        color: var(--ungani-text);
        border: 1px solid var(--ungani-border);
        cursor: pointer;
        box-shadow: 0 10px 24px rgba(6,28,61,0.08);
        transition: transform 0.18s ease, box-shadow 0.18s ease;
      }

      .ungani-icon-button:hover {
        transform: translateY(-2px);
        box-shadow: 0 14px 32px rgba(6,28,61,0.15);
      }

      .ungani-bell-count {
        position: absolute;
        top: -6px;
        right: -4px;
        min-width: 20px;
        height: 20px;
        border-radius: 999px;
        background: var(--ungani-red);
        color: white;
        font-size: 11px;
        font-weight: 900;
        display: none;
        align-items: center;
        justify-content: center;
        padding: 0 6px;
      }

      .ungani-quickadd-holder,
      .ungani-bell-holder {
        position: relative;
      }

      .ungani-quickadd-overlay {
        position: fixed;
        inset: 0;
        z-index: 70;
        display: none;
      }

      body.ungani-quickadd-open .ungani-quickadd-overlay {
        display: block;
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

      /* .ungani-hero has overflow:hidden above and inherits .ungani-card:hover's
         transform via the shared "ungani-card ungani-hero" class combo - that's
         the exact combination that caused the dashboard flicker bug. Neutralize
         the inherited movement here; a large banner shouldn't shift under the
         cursor anyway. */
      .ungani-hero.ungani-hero:hover {
        transform: none;
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
        --accent: #64748B;
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

      .ungani-metric::after {
        content: "";
        position: absolute;
        left: 0;
        top: 18px;
        bottom: 18px;
        width: 4px;
        border-radius: 0 999px 999px 0;
        background: var(--accent);
      }

      .ungani-metric:hover::before {
        transform: scale(1.18);
        opacity: 0.95;
      }

      .ungani-metric.green { --accent: var(--ungani-green); }
      .ungani-metric.gold, .ungani-metric.orange { --accent: var(--ungani-gold); }
      .ungani-metric.red { --accent: var(--ungani-red); }
      .ungani-metric.blue { --accent: var(--ungani-blue); }

      .ungani-metric.clickable {
        cursor: pointer;
      }

      /* .ungani-metric has overflow:hidden above - a hover transform on this same
         element is the exact combo that caused the dashboard flicker bug (the box
         shifts out from under the cursor, un-hovers, reverts, re-hovers). Color/
         glow only here, never movement. */
      .ungani-metric.clickable:hover {
        box-shadow: 0 20px 50px rgba(0,0,0,0.18);
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
        font-size: 12px;
        font-weight: 900;
        letter-spacing: 0.04em;
        text-transform: uppercase;
        line-height: 1.25;
      }

      .ungani-metric-icon {
        width: 42px;
        height: 42px;
        flex: 0 0 42px;
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
        max-width: 100%;
        font-size: clamp(21px, 2vw, 31px);
        line-height: 1.05;
        margin: 0 0 10px;
        font-weight: 950;
        letter-spacing: -0.045em;
        white-space: normal;
        overflow-wrap: anywhere;
        word-break: break-word;
      }

      .ungani-metric-value.compact {
        font-size: clamp(25px, 2.4vw, 34px);
      }

      .ungani-metric-full {
        display: inline-flex;
        margin-top: 4px;
        font-size: 11px;
        color: var(--ungani-muted);
        font-weight: 750;
      }

      .ungani-metric-subtitle {
        position: relative;
        margin: 0;
        color: var(--ungani-muted);
        font-size: 13px;
        line-height: 1.45;
      }

      .ungani-metric.green .ungani-metric-icon { background: var(--ungani-green); }
      .ungani-metric.gold .ungani-metric-icon { background: var(--ungani-gold); color: var(--ungani-navy); }
      .ungani-metric.orange .ungani-metric-icon { background: var(--ungani-gold); color: var(--ungani-navy); }
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

      /* Secondary, adapted for permanently-dark surfaces (e.g. the sidebar) */
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

      .ungani-badge.blue { background: rgba(6,28,61,0.12); color: var(--ungani-navy); }
      .ungani-badge.gold { background: rgba(212,166,58,0.18); color: #7A5200; }
      .ungani-badge.green { background: rgba(21,128,61,0.15); color: var(--ungani-green); }
      .ungani-badge.orange { background: rgba(212,166,58,0.20); color: #7A5200; }
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

      .ungani-bottom-nav {
        display: none;
      }

      @keyframes unganiFadeUp {
        from { opacity: 0; }
        to { opacity: 1; }
      }

      @keyframes unganiLoadingSlide {
        0% { transform: translateX(-110%); }
        100% { transform: translateX(260%); }
      }

      @keyframes unganiToastIn {
        from { opacity: 0; transform: translateY(12px); }
        to { opacity: 1; transform: translateY(0); }
      }

      @keyframes unganiPulse {
        0% { box-shadow: 0 0 0 0 rgba(21,128,61,0.50); }
        70% { box-shadow: 0 0 0 10px rgba(21,128,61,0); }
        100% { box-shadow: 0 0 0 0 rgba(21,128,61,0); }
      }

      @media (max-width: 1180px) {
        .ungani-grid {
          grid-template-columns: repeat(2, minmax(0, 1fr));
        }

        .ungani-two-col {
          grid-template-columns: 1fr;
        }

        .ungani-topbar {
          grid-template-columns: 1fr;
        }

        .ungani-top-actions {
          justify-content: flex-start;
        }
      }

      @media (max-width: 860px) {
        body {
          padding-bottom: 74px;
        }

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

        body.ungani-sidebar-open::after {
          content: "";
          position: fixed;
          inset: 0;
          background: rgba(0,0,0,0.38);
          z-index: 25;
        }

        .ungani-mobile-menu {
          display: inline-flex;
        }

        .ungani-main {
          padding: 14px;
          padding-bottom: 90px;
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

        .ungani-global-results,
        .ungani-notification-panel,
        .ungani-quickadd-panel {
          position: fixed;
          left: 12px;
          right: 12px;
          top: 90px;
          width: auto;
          max-height: calc(100vh - 130px);
        }

        .ungani-bottom-nav {
          position: fixed;
          left: 10px;
          right: 10px;
          bottom: 10px;
          height: 62px;
          display: grid;
          grid-template-columns: repeat(5, 1fr);
          gap: 6px;
          padding: 7px;
          border-radius: 22px;
          background: rgba(6,28,61,0.95);
          border: 1px solid rgba(255,255,255,0.13);
          box-shadow: 0 20px 60px rgba(0,0,0,0.28);
          backdrop-filter: blur(18px);
          z-index: 60;
        }

        .ungani-bottom-nav a,
        .ungani-bottom-nav button {
          border: 0;
          background: transparent;
          color: rgba(255,255,255,0.72);
          border-radius: 16px;
          display: flex;
          align-items: center;
          justify-content: center;
          flex-direction: column;
          gap: 2px;
          font-size: 11px;
          font-weight: 800;
        }

        .ungani-bottom-nav a.active {
          background: rgba(212,166,58,0.18);
          color: white;
        }

        .ungani-bottom-nav span {
          font-size: 18px;
          line-height: 1;
        }
      }

      @media (max-width: 560px) {
        .ungani-card {
          padding: 16px;
          border-radius: 20px;
        }

        .ungani-section-title {
          flex-direction: column;
        }

        .ungani-metric {
          min-height: 128px;
        }

        .ungani-metric-value {
          font-size: clamp(21px, 7vw, 29px);
        }

        .ungani-btn {
          width: auto;
        }
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
    `;

    document.head.appendChild(style);
  }

  let modalEscapeListenerAttached = false;

  function ensureModal() {
    injectSharedStyles();

    let backdrop = document.getElementById("unganiModalBackdrop");

    if (backdrop) return backdrop;

    backdrop = document.createElement("div");
    backdrop.id = "unganiModalBackdrop";
    backdrop.className = "ungani-modal-backdrop";
    backdrop.innerHTML = `
      <div class="ungani-modal" role="dialog" aria-modal="true" aria-labelledby="unganiModalTitle">
        <div class="ungani-modal-head">
          <h3 id="unganiModalTitle"></h3>
          <button type="button" class="ungani-modal-close" onclick="UnganiClientShared.closeModal()" aria-label="Close">✕</button>
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

  function cleanText(value) {
    return String(value || "N/A").replaceAll("_", " ");
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
      loadNotificationBadge();
      startTeamChatPolling();

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
      <div class="ungani-quickadd-overlay" onclick="UnganiClientShared.closeQuickAdd()"></div>

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
              Client Shared Version: Step 308A-2 Global UX Fix
            </p>
          </div>
        </aside>

        <main class="ungani-main">
          <header class="ungani-topbar">
            <div>
              <h2>${safe(pageTitle)}</h2>
              <p>${safe(pageSubtitle)}</p>
            </div>

            <div class="ungani-global-search-wrap">
              <span class="ungani-search-icon">⌕</span>
              <input
                id="unganiGlobalSearch"
                class="ungani-global-search"
                placeholder="Search properties, tasks, leads, documents..."
                autocomplete="off"
                oninput="UnganiClientShared.handleGlobalSearchInput()"
                onfocus="UnganiClientShared.handleGlobalSearchInput()"
              />
              <div id="unganiGlobalResults" class="ungani-global-results" style="display:none;"></div>
            </div>

            <div class="ungani-top-actions">
              <button class="ungani-btn dark ungani-mobile-menu" type="button" onclick="UnganiClientShared.toggleSidebar()">Menu</button>

              <div class="ungani-bell-holder">
                <button id="unganiBellBtn" class="ungani-icon-button" type="button" onclick="UnganiClientShared.toggleNotifications()" title="Notifications">
                  🔔
                  <span id="unganiBellCount" class="ungani-bell-count">0</span>
                </button>
                <div id="unganiNotificationPanel" class="ungani-notification-panel" style="display:none;"></div>
              </div>

              <div class="ungani-bell-holder">
                <button id="unganiChatBtn" class="ungani-icon-button" type="button" onclick="UnganiClientShared.toggleTeamChat()" title="Team Chat">
                  💬
                  <span id="unganiChatCount" class="ungani-bell-count">0</span>
                </button>
                <div id="unganiTeamChatPanel" class="ungani-notification-panel ungani-teamchat-panel" style="display:none;"></div>
              </div>

              <div class="ungani-quickadd-holder">
                <button class="ungani-btn gold" type="button" onclick="UnganiClientShared.openQuickAdd()">＋ Quick Add</button>
                <div id="unganiQuickAddPanel" class="ungani-quickadd-panel" style="display:none;"></div>
              </div>
            </div>
          </header>

          <div class="ungani-content" id="unganiContent">
            ${loadingCard("Loading page content...")}
          </div>
        </main>
      </div>

      ${renderBottomNav()}
    `;

    state.shellEl = document.getElementById("unganiAppShell");
    state.contentEl = document.getElementById("unganiContent");
  }

  function buildSectionNavGroup() {
    if (
      !window.UnganiBusinessConfig ||
      typeof UnganiBusinessConfig.resolveWithSections !== "function" ||
      typeof UnganiBusinessConfig.mergeWithGeneral !== "function"
    ) {
      return null;
    }

    const resolved = UnganiBusinessConfig.resolveWithSections(state.tenant);
    const merged = UnganiBusinessConfig.mergeWithGeneral(resolved);
    const labels = (merged && merged.selectedSectionLabels) || [];

    if (labels.length <= 1) return null;

    const items = [["dashboard", "client.html", "📊", "Overview"]];

    labels.forEach(function (label) {
      items.push([
        "section-" + label.toLowerCase(),
        "client.html?section=" + encodeURIComponent(label),
        "🏷️",
        label
      ]);
    });

    return { title: "Sections", items: items };
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
      }
    ];

    const sectionGroup = buildSectionNavGroup();
    if (sectionGroup) groups.push(sectionGroup);

    groups.push(
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
    );

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

  function renderBottomNav() {
    const items = [
      ["dashboard", "client.html", "🏠", "Home"],
      ["items", "my-items.html", "🏷️", "Items"],
      ["money", "my-money.html", "💰", "Money"],
      ["tasks", "my-tasks.html", "✅", "Tasks"],
      ["menu", "#", "☰", "Menu"]
    ];

    return `
      <nav class="ungani-bottom-nav">
        ${items.map(function (item) {
          if (item[0] === "menu") {
            return `<button type="button" onclick="UnganiClientShared.toggleSidebar()"><span>${safe(item[2])}</span>${safe(item[3])}</button>`;
          }

          const active = item[0] === state.currentPageKey ? "active" : "";

          return `<a class="${active}" href="${attr(item[1])}"><span>${safe(item[2])}</span>${safe(item[3])}</a>`;
        }).join("")}
      </nav>
    `;
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
      authUser && authUser.user_metadata ? authUser.user_metadata.tenant_id : null,
      authUser && authUser.app_metadata ? authUser.app_metadata.tenant_id : null
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
    const selectedColor = normalizeMetricColor(title, color || "blue");
    const icon = metricIcon(title, selectedColor);
    const display = compactMetricValue(title, valueText);
    const cardTitle = display.fullValue && display.fullValue !== display.displayValue
      ? "Full value: " + display.fullValue
      : String(valueText || "");

    const card = `
      <div class="ungani-card ungani-metric ${attr(selectedColor)} ${href ? "clickable" : ""}" title="${attr(cardTitle)}">
        <div class="ungani-metric-top">
          <div class="ungani-metric-label">${safe(title)}</div>
          <div class="ungani-metric-icon">${safe(icon)}</div>
        </div>

        <h3 class="ungani-metric-value ${display.isCompact ? "compact" : ""}">${safe(display.displayValue)}</h3>
        ${display.isCompact ? `<span class="ungani-metric-full">${safe(display.fullValue)}</span>` : ""}
        <p class="ungani-metric-subtitle">${safe(subtitle || "")}</p>
      </div>
    `;

    if (href) {
      return `<a href="${attr(href)}">${card}</a>`;
    }

    return card;
  }

  function normalizeMetricColor(title, color) {
    const lower = String(title || "").toLowerCase();

    if (lower.includes("urgent") || lower.includes("overdue") || lower.includes("failed") || lower.includes("high")) return "red";
    if (lower.includes("income") || lower.includes("balance") || lower.includes("resolved") || lower.includes("completed")) return "green";
    if (lower.includes("expense") || lower.includes("pending") || lower.includes("open")) return "gold";

    if (color === "orange") return "gold";

    return color || "blue";
  }

  function compactMetricValue(title, valueText) {
    const original = String(valueText === null || valueText === undefined ? "" : valueText);
    const lower = String(title + " " + original).toLowerCase();
    const isMoney = lower.includes("ksh") || lower.includes("kes") || lower.includes("money") || lower.includes("income") || lower.includes("expense") || lower.includes("balance") || lower.includes("amount");

    if (!isMoney) {
      return {
        displayValue: original,
        fullValue: original,
        isCompact: false
      };
    }

    const amount = parseMoneyNumber(original);

    if (!isNaN(amount) && Math.abs(amount) >= 100000) {
      return {
        displayValue: "Ksh " + compactNumber(amount),
        fullValue: formatKES(amount),
        isCompact: true
      };
    }

    if (original.length > 15 && !isNaN(amount)) {
      return {
        displayValue: formatKES(amount),
        fullValue: formatKES(amount),
        isCompact: false
      };
    }

    return {
      displayValue: original,
      fullValue: original,
      isCompact: false
    };
  }

  function parseMoneyNumber(valueText) {
    const cleaned = String(valueText || "")
      .replace(/[^\d.-]/g, "")
      .trim();

    if (!cleaned) return NaN;

    return Number(cleaned);
  }

  function compactNumber(amount) {
    const sign = amount < 0 ? "-" : "";
    const absolute = Math.abs(Number(amount || 0));

    if (absolute >= 1000000000) {
      return sign + trimDecimal(absolute / 1000000000) + "B";
    }

    if (absolute >= 1000000) {
      return sign + trimDecimal(absolute / 1000000) + "M";
    }

    if (absolute >= 1000) {
      return sign + trimDecimal(absolute / 1000) + "K";
    }

    return sign + absolute.toLocaleString("en-KE");
  }

  function trimDecimal(valueNumber) {
    const rounded = Math.round(valueNumber * 10) / 10;

    if (Number.isInteger(rounded)) {
      return String(rounded);
    }

    return String(rounded);
  }

  function metricIcon(title, color) {
    const lower = String(title || "").toLowerCase();

    if (lower.includes("money") || lower.includes("income") || lower.includes("expense") || lower.includes("balance")) return "💰";
    if (lower.includes("task") || lower.includes("pending")) return color === "red" ? "⚠️" : "✅";
    if (lower.includes("people") || lower.includes("agent") || lower.includes("lead")) return "👥";
    if (lower.includes("document")) return "📄";
    if (lower.includes("calendar") || lower.includes("event")) return "📅";
    if (lower.includes("support")) return "🛟";
    if (lower.includes("message") || lower.includes("chat")) return "💬";
    if (lower.includes("property") || lower.includes("item") || lower.includes("asset")) return "🏷️";
    if (lower.includes("report")) return "📑";

    return "◆";
  }

  async function handleGlobalSearchInput() {
    const input = document.getElementById("unganiGlobalSearch");
    const panel = document.getElementById("unganiGlobalResults");

    if (!input || !panel) return;

    const query = String(input.value || "").trim();

    clearTimeout(state.searchTimer);

    if (query.length < 2) {
      panel.style.display = "none";
      panel.innerHTML = "";
      return;
    }

    closeTeamChat();
    closeQuickAdd();

    panel.style.display = "block";
    panel.innerHTML = `
      <div class="ungani-panel-head">
        <strong>Search</strong>
        <span class="ungani-small">Searching...</span>
      </div>
      <div class="ungani-panel-body">
        ${loadingCard("Searching workspace...")}
      </div>
    `;

    state.searchTimer = setTimeout(async function () {
      const results = await runGlobalSearch(query);
      renderGlobalSearchResults(query, results);
    }, 260);
  }

  async function runGlobalSearch(query) {
    const tables = [
      {
        table: "business_items",
        label: "Property / Item",
        href: "my-items.html",
        titleFields: ["property_name", "item_name", "name", "title"],
        detailFields: ["property_status", "item_status", "status", "project_name", "property_location"]
      },
      {
        table: "tasks",
        label: "Task",
        href: "my-tasks.html",
        titleFields: ["task_title", "title", "name"],
        detailFields: ["status", "priority", "property_name", "project_name", "lead_name"]
      },
      {
        table: "client_people",
        label: "Person / Lead",
        href: "my-people.html",
        titleFields: ["full_name", "name"],
        detailFields: ["person_type", "relationship_status", "lead_status", "property_of_interest"]
      },
      {
        table: "documents",
        label: "Document",
        href: "my-documents.html",
        titleFields: ["document_title", "title", "file_name"],
        detailFields: ["document_type", "status", "property_name", "project_name"]
      },
      {
        table: "business_records",
        label: "Record",
        href: "my-records.html",
        titleFields: ["record_title", "title", "name"],
        detailFields: ["record_type", "status", "property_name", "project_name", "assigned_agent"]
      },
      {
        table: "transactions",
        label: "Money Record",
        href: "my-money.html",
        titleFields: ["category_name", "category", "description"],
        detailFields: ["transaction_type", "type", "payment_method", "status"]
      }
    ];

    const results = [];
    const queryLower = query.toLowerCase();

    for (const config of tables) {
      try {
        const response = await state.supabaseClient
          .from(config.table)
          .select("*")
          .eq("tenant_id", state.tenantId)
          .order("created_at", { ascending: false })
          .limit(50);

        if (response.error) continue;

        (response.data || []).forEach(function (row) {
          const haystack = JSON.stringify(row || {}).toLowerCase();

          if (haystack.includes(queryLower)) {
            results.push({
              label: config.label,
              href: config.href,
              title: getValue(row, config.titleFields, config.label),
              detail: config.detailFields.map(function (field) {
                return getValue(row, [field], "");
              }).filter(Boolean).slice(0, 3).join(" · ")
            });
          }
        });
      } catch (error) {
        console.warn("Search skipped:", config.table, error.message);
      }
    }

    return results.slice(0, 12);
  }

  function renderGlobalSearchResults(query, results) {
    const panel = document.getElementById("unganiGlobalResults");

    if (!panel) return;

    if (!results.length) {
      panel.innerHTML = `
        <div class="ungani-panel-head">
          <strong>Search Results</strong>
          <button class="ungani-btn dark" type="button" onclick="UnganiClientShared.closeGlobalSearch()">Close</button>
        </div>
        <div class="ungani-panel-body">
          <div class="ungani-empty">
            <h3>No results found</h3>
            <p>No matching properties, tasks, leads, documents, or records for "${safe(query)}".</p>
          </div>
        </div>
      `;
      return;
    }

    panel.innerHTML = `
      <div class="ungani-panel-head">
        <strong>Search Results</strong>
        <button class="ungani-btn dark" type="button" onclick="UnganiClientShared.closeGlobalSearch()">Close</button>
      </div>

      <div class="ungani-panel-body">
        ${results.map(function (item) {
          return `
            <a class="ungani-search-result" href="${attr(item.href)}">
              <span class="ungani-badge gold">${safe(item.label)}</span>
              <h3 style="font-size:15px;margin:8px 0 4px;">${safe(item.title)}</h3>
              <p class="ungani-small" style="margin:0;">${safe(item.detail || "Open section")}</p>
            </a>
          `;
        }).join("")}
      </div>
    `;
  }

  function closeGlobalSearch() {
    const panel = document.getElementById("unganiGlobalResults");

    if (panel) {
      panel.style.display = "none";
      panel.innerHTML = "";
    }
  }

  async function loadNotificationBadge() {
    const countEl = document.getElementById("unganiBellCount");

    if (!countEl || !state.supabaseClient || !state.tenantId) return;

    const items = await getNotificationItems();
    const count = items.length;

    countEl.textContent = String(count);
    countEl.style.display = count > 0 ? "inline-flex" : "none";
  }

  let teamChatState = {
    messages: [],
    isOpen: false,
    pollTimer: null,
    firstLoadDone: false
  };

  async function loadTeamChatMessages(silent) {
    if (!state.supabaseClient || !state.tenantId) return;

    try {
      const response = await state.supabaseClient
        .from("team_chat_messages")
        .select("*")
        .eq("tenant_id", state.tenantId)
        .order("created_at", { ascending: true })
        .limit(100);

      if (response.error) {
        console.warn("Team chat load skipped:", response.error.message);
        return;
      }

      const previousMessages = teamChatState.messages;
      teamChatState.messages = response.data || [];

      if (teamChatState.firstLoadDone) {
        checkForNewTeamChatMessages(previousMessages, teamChatState.messages);
      }

      teamChatState.firstLoadDone = true;
      updateTeamChatBadge();

      if (teamChatState.isOpen) {
        renderTeamChatMessages();

        if (!silent) {
          scrollTeamChatToBottom();
        }
      }
    } catch (error) {
      console.warn("Team chat load skipped:", error.message);
    }
  }

  function checkForNewTeamChatMessages(previousMessages, newMessages) {
    const previousIds = new Set(previousMessages.map(function (m) { return m.id; }));
    const myUserId = state.authUser ? state.authUser.id : null;

    const freshOnes = newMessages.filter(function (m) {
      return !previousIds.has(m.id) && m.sender_user_id !== myUserId;
    });

    if (freshOnes.length > 0 && !teamChatState.isOpen) {
      showTeamChatToast(freshOnes[freshOnes.length - 1]);
    }
  }

  function updateTeamChatBadge() {
    const countEl = document.getElementById("unganiChatCount");
    if (!countEl) return;

    const myUserId = state.authUser ? state.authUser.id : null;
    const unread = teamChatState.messages.filter(function (m) {
      return m.sender_user_id !== myUserId && !m.is_read;
    }).length;

    countEl.textContent = String(unread);
    countEl.style.display = unread > 0 ? "inline-flex" : "none";
  }

  function showTeamChatToast(message) {
    const existing = document.getElementById("unganiTeamChatToast");
    if (existing) existing.remove();

    const toast = document.createElement("div");
    toast.id = "unganiTeamChatToast";
    toast.className = "ungani-teamchat-toast";

    const senderName = getValue(message, ["sender_name"], "Team Member");
    const rawBody = String(getValue(message, ["message_body", "message", "body"], "New team message"));
    const body = rawBody.length > 90 ? rawBody.slice(0, 90) + "..." : rawBody;

    toast.innerHTML = `
      <div style="font-size:20px;">💬</div>
      <div>
        <strong>${safe(senderName)}</strong>
        <p>${safe(body)}</p>
      </div>
    `;

    toast.addEventListener("click", function () {
      toast.remove();
      toggleTeamChat();
    });

    document.body.appendChild(toast);

    setTimeout(function () { toast.classList.add("show"); }, 30);
    setTimeout(function () {
      toast.classList.remove("show");
      setTimeout(function () { toast.remove(); }, 300);
    }, 7000);
  }

  async function toggleTeamChat() {
    const panel = document.getElementById("unganiTeamChatPanel");
    if (!panel) return;

    closeGlobalSearch();
    closeQuickAdd();

    const notificationPanel = document.getElementById("unganiNotificationPanel");
    if (notificationPanel) notificationPanel.style.display = "none";

    if (teamChatState.isOpen) {
      closeTeamChat();
      return;
    }

    teamChatState.isOpen = true;
    panel.style.display = "flex";
    panel.innerHTML = renderTeamChatShell();

    await markTeamChatRead();
    renderTeamChatMessages();
    scrollTeamChatToBottom();

    const input = document.getElementById("unganiTeamChatInput");
    if (input) input.focus();
  }

  function closeTeamChat() {
    const panel = document.getElementById("unganiTeamChatPanel");
    teamChatState.isOpen = false;

    if (panel) {
      panel.style.display = "none";
    }
  }

  function renderTeamChatShell() {
    return `
      <div class="ungani-panel-head">
        <strong>Team Chat</strong>
        <button class="ungani-btn dark" type="button" onclick="UnganiClientShared.closeTeamChat()">Close</button>
      </div>
      <div id="unganiTeamChatMessages" class="ungani-teamchat-messages"></div>
      <form class="ungani-teamchat-input-row" onsubmit="UnganiClientShared.sendTeamChatMessage(event); return false;">
        <input id="unganiTeamChatInput" type="text" placeholder="Message your team..." autocomplete="off" />
        <button class="ungani-teamchat-send" type="submit" title="Send">➤</button>
      </form>
    `;
  }

  function renderTeamChatMessages() {
    const box = document.getElementById("unganiTeamChatMessages");
    if (!box) return;

    if (!teamChatState.messages.length) {
      box.innerHTML = `
        <div class="ungani-empty" style="margin:auto;">
          <h3>No messages yet</h3>
          <p>Send a quick note to your team to get started.</p>
        </div>
      `;
      return;
    }

    const myUserId = state.authUser ? state.authUser.id : null;

    box.innerHTML = teamChatState.messages.map(function (row) {
      const isMine = row.sender_user_id === myUserId;
      const senderName = getValue(row, ["sender_name"], isMine ? "You" : "Team Member");
      const body = getValue(row, ["message_body", "message", "body"], "");
      const time = formatDateTime(getValue(row, ["created_at"], ""));

      return `
        <div class="ungani-teamchat-bubble ${isMine ? "mine" : "theirs"}">
          ${isMine ? "" : `<span class="ungani-teamchat-sender">${safe(senderName)}</span>`}
          <span>${safe(body)}</span>
          <span class="ungani-teamchat-time">${safe(time)}</span>
        </div>
      `;
    }).join("");
  }

  function scrollTeamChatToBottom() {
    const box = document.getElementById("unganiTeamChatMessages");
    if (box) box.scrollTop = box.scrollHeight;
  }

  async function markTeamChatRead() {
    if (!state.supabaseClient || !state.tenantId || !state.authUser) return;

    try {
      await state.supabaseClient
        .from("team_chat_messages")
        .update({ is_read: true, updated_at: new Date().toISOString() })
        .eq("tenant_id", state.tenantId)
        .neq("sender_user_id", state.authUser.id)
        .eq("is_read", false);

      teamChatState.messages.forEach(function (m) {
        if (m.sender_user_id !== state.authUser.id) m.is_read = true;
      });

      updateTeamChatBadge();
    } catch (error) {
      console.warn("Could not mark team chat read:", error.message);
    }
  }

  async function sendTeamChatMessage(event) {
    if (event && event.preventDefault) event.preventDefault();

    const input = document.getElementById("unganiTeamChatInput");
    const body = input ? String(input.value || "").trim() : "";

    if (!body || !state.authUser) return;

    const senderName = getValue(state.userProfile, ["full_name", "name"], "") ||
      getValue(state.authUser, ["email"], "Team Member");

    const payload = {
      tenant_id: state.tenantId,
      sender_user_id: state.authUser.id,
      sender_name: senderName,
      sender_role: "team",
      message_type: "message",
      message_body: body,
      message: body,
      body: body,
      is_read: false,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    };

    if (input) input.value = "";

    try {
      const response = await state.supabaseClient.from("team_chat_messages").insert(payload);

      if (response.error) {
        showToast("Could not send message: " + response.error.message);
        return;
      }

      await loadTeamChatMessages(true);
    } catch (error) {
      showToast("Could not send message: " + error.message);
    }
  }

  function startTeamChatPolling() {
    if (teamChatState.pollTimer) clearInterval(teamChatState.pollTimer);

    loadTeamChatMessages(true);

    teamChatState.pollTimer = setInterval(function () {
      loadTeamChatMessages(true);
    }, 12000);
  }

  async function toggleNotifications() {
    const panel = document.getElementById("unganiNotificationPanel");

    if (!panel) return;

    closeGlobalSearch();
    closeQuickAdd();
    closeTeamChat();

    if (panel.style.display === "block") {
      panel.style.display = "none";
      return;
    }

    panel.style.display = "block";
    panel.innerHTML = `
      <div class="ungani-panel-head">
        <strong>Notifications</strong>
        <button class="ungani-btn dark" type="button" onclick="UnganiClientShared.toggleNotifications()">Close</button>
      </div>
      <div class="ungani-panel-body">${loadingCard("Loading notifications...")}</div>
    `;

    const items = await getNotificationItems();

    panel.innerHTML = `
      <div class="ungani-panel-head">
        <strong>Notifications</strong>
        <button class="ungani-btn dark" type="button" onclick="UnganiClientShared.toggleNotifications()">Close</button>
      </div>

      <div class="ungani-panel-body">
        ${items.length === 0 ? `
          <div class="ungani-empty">
            <h3>No urgent alerts</h3>
            <p>Task reminders, unread notices, support items, and UNGANI replies will appear here.</p>
          </div>
        ` : items.map(function (item) {
          return `
            <a class="ungani-alert-row" href="${attr(item.href)}">
              <span class="ungani-badge ${attr(item.color)}">${safe(item.type)}</span>
              <h3 style="font-size:15px;margin:8px 0 4px;">${safe(item.title)}</h3>
              <p class="ungani-small" style="margin:0;">${safe(item.detail)}</p>
            </a>
          `;
        }).join("")}
      </div>
    `;
  }

  async function getNotificationItems() {
    const items = [];
    const today = todayISO();

    try {
      const tasks = await state.supabaseClient
        .from("tasks")
        .select("*")
        .eq("tenant_id", state.tenantId)
        .lte("due_date", today)
        .limit(10);

      if (!tasks.error) {
        (tasks.data || []).forEach(function (row) {
          const status = String(getValue(row, ["status"], "")).toLowerCase();

          if (!status.includes("completed") && !status.includes("cancelled")) {
            items.push({
              type: "Task Due",
              color: "red",
              title: getValue(row, ["task_title", "title", "name"], "Task due"),
              detail: "Due " + formatDate(getValue(row, ["due_date"], "")),
              href: "my-tasks.html"
            });
          }
        });
      }
    } catch (error) {
      console.warn("Task notifications skipped:", error.message);
    }

    try {
      const support = await state.supabaseClient
        .from("support_issues")
        .select("*")
        .eq("tenant_id", state.tenantId)
        .in("status", ["open", "in progress"])
        .limit(10);

      if (!support.error) {
        (support.data || []).forEach(function (row) {
          items.push({
            type: "Support",
            color: "gold",
            title: getValue(row, ["issue_title", "subject"], "Open support issue"),
            detail: getValue(row, ["priority"], "normal") + " priority",
            href: "my-support.html"
          });
        });
      }
    } catch (error) {
      console.warn("Support notifications skipped:", error.message);
    }

    try {
      const notices = await state.supabaseClient
        .from("client_notices")
        .select("*")
        .eq("tenant_id", state.tenantId)
        .eq("status", "unread")
        .limit(10);

      if (!notices.error) {
        (notices.data || []).forEach(function (row) {
          items.push({
            type: "Notice",
            color: "gold",
            title: getValue(row, ["notice_title", "title"], "Unread notice"),
            detail: getValue(row, ["message", "description"], "Unread client notice"),
            href: "my-notices.html"
          });
        });
      }
    } catch (error) {
      console.warn("Notice notifications skipped:", error.message);
    }

    try {
      const chat = await state.supabaseClient
        .from("admin_client_messages")
        .select("*")
        .eq("tenant_id", state.tenantId)
        .neq("sender_role", "client")
        .eq("is_read", false)
        .limit(10);

      if (!chat.error) {
        (chat.data || []).forEach(function (row) {
          items.push({
            type: "UNGANI Reply",
            color: "green",
            title: "New message from UNGANI",
            detail: shortText(getValue(row, ["message_body", "message", "body"], ""), 80),
            href: "my-chat.html"
          });
        });
      }
    } catch (error) {
      console.warn("Chat notifications skipped:", error.message);
    }

    return items.slice(0, 20);
  }

  function openQuickAdd() {
    const panel = document.getElementById("unganiQuickAddPanel");

    if (!panel) return;

    closeGlobalSearch();
    closeTeamChat();

    const notificationPanel = document.getElementById("unganiNotificationPanel");

    if (notificationPanel) {
      notificationPanel.style.display = "none";
    }

    document.body.classList.add("ungani-quickadd-open");
    panel.style.display = "block";
    panel.innerHTML = renderQuickAddPanel("income");
  }

  function closeQuickAdd() {
    const panel = document.getElementById("unganiQuickAddPanel");

    document.body.classList.remove("ungani-quickadd-open");

    if (panel) {
      panel.style.display = "none";
      panel.innerHTML = "";
    }
  }

  function changeQuickAddType() {
    const selectedType = value("unganiQuickAddType") || "income";
    const panel = document.getElementById("unganiQuickAddPanel");

    if (panel) {
      panel.innerHTML = renderQuickAddPanel(selectedType);
    }
  }

  function renderQuickAddPanel(selectedType) {
    return `
      <div class="ungani-panel-head">
        <strong>Quick Add</strong>
        <button class="ungani-btn dark" type="button" onclick="UnganiClientShared.closeQuickAdd()">Close</button>
      </div>

      <div class="ungani-panel-body">
        <form onsubmit="UnganiClientShared.saveQuickAdd(event)">
          <label for="unganiQuickAddType">Add Type</label>
          <select id="unganiQuickAddType" onchange="UnganiClientShared.changeQuickAddType()">
            <option value="income" ${selectedType === "income" ? "selected" : ""}>Sale / Income</option>
            <option value="expense" ${selectedType === "expense" ? "selected" : ""}>Expense</option>
            <option value="task" ${selectedType === "task" ? "selected" : ""}>Task / Follow-up</option>
            <option value="property" ${selectedType === "property" ? "selected" : ""}>Property / Item</option>
          </select>

          ${renderQuickAddFields(selectedType)}

          <div class="ungani-button-row">
            <button class="ungani-btn green" type="submit">Save</button>
            <button class="ungani-btn dark" type="button" onclick="UnganiClientShared.closeQuickAdd()">Cancel</button>
          </div>
        </form>
      </div>
    `;
  }

  function renderQuickAddFields(type) {
    if (type === "income" || type === "expense") {
      return `
        <label for="unganiQuickTitle">Category / Title</label>
        <input id="unganiQuickTitle" required placeholder="${type === "income" ? "Property Sale / Rental Income" : "Agent Commission / Maintenance"}" />

        <label for="unganiQuickAmount">Amount</label>
        <input id="unganiQuickAmount" type="number" min="0" step="1" required placeholder="Amount in Ksh" />

        <label for="unganiQuickRelated">Related Property / Person</label>
        <input id="unganiQuickRelated" placeholder="Optional property, client, agent, or supplier" />

        <label for="unganiQuickDescription">Description</label>
        <textarea id="unganiQuickDescription" placeholder="Short note..."></textarea>
      `;
    }

    if (type === "task") {
      return `
        <label for="unganiQuickTitle">Task Title</label>
        <input id="unganiQuickTitle" required placeholder="Follow up with client after viewing" />

        <label for="unganiQuickDueDate">Due Date</label>
        <input id="unganiQuickDueDate" type="date" />

        <label for="unganiQuickPriority">Priority</label>
        <select id="unganiQuickPriority">
          <option value="normal">Normal</option>
          <option value="high">High</option>
          <option value="urgent">Urgent</option>
          <option value="low">Low</option>
        </select>

        <label for="unganiQuickDescription">Description</label>
        <textarea id="unganiQuickDescription" placeholder="Short task details..."></textarea>
      `;
    }

    return `
      <label for="unganiQuickTitle">Property / Item Name</label>
      <input id="unganiQuickTitle" required placeholder="Clove Garden A12" />

      <label for="unganiQuickAmount">Price / Value</label>
      <input id="unganiQuickAmount" type="number" min="0" step="1" placeholder="Amount in Ksh" />

      <label for="unganiQuickRelated">Location / Project</label>
      <input id="unganiQuickRelated" placeholder="Nyali, Mombasa / Clove Garden" />

      <label for="unganiQuickStatus">Status</label>
      <select id="unganiQuickStatus">
        <option value="available">Available</option>
        <option value="reserved">Reserved</option>
        <option value="under negotiation">Under Negotiation</option>
        <option value="sold">Sold</option>
        <option value="rented">Rented</option>
      </select>

      <label for="unganiQuickDescription">Notes</label>
      <textarea id="unganiQuickDescription" placeholder="Short property/item note..."></textarea>
    `;
  }

  async function saveQuickAdd(event) {
    event.preventDefault();

    const type = value("unganiQuickAddType") || "income";
    const title = value("unganiQuickTitle");
    const amount = Number(value("unganiQuickAmount") || 0);
    const related = value("unganiQuickRelated");
    const description = value("unganiQuickDescription");

    if (!title) {
      alert("Please enter a title.");
      return;
    }

    let response;

    if (type === "income" || type === "expense") {
      response = await state.supabaseClient
        .from("transactions")
        .insert({
          tenant_id: state.tenantId,
          business_type_key: getValue(state.tenant, ["business_type_key"], null),
          section_key: "money_records",
          transaction_type: type,
          type: type,
          category: title,
          category_name: title,
          amount: amount,
          transaction_date: todayISO(),
          related_person: related || null,
          property_name: related || null,
          description: description || null,
          status: "completed",
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        });
    } else if (type === "task") {
      response = await state.supabaseClient
        .from("tasks")
        .insert({
          tenant_id: state.tenantId,
          business_type_key: getValue(state.tenant, ["business_type_key"], null),
          section_key: "tasks_followups",
          task_title: title,
          title: title,
          name: title,
          task_type: "follow up",
          priority: value("unganiQuickPriority") || "normal",
          status: "pending",
          due_date: value("unganiQuickDueDate") || null,
          description: description || null,
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        });
    } else {
      response = await state.supabaseClient
        .from("business_items")
        .insert({
          tenant_id: state.tenantId,
          business_type_key: getValue(state.tenant, ["business_type_key"], null),
          section_key: "properties_listings",
          item_name: title,
          name: title,
          title: title,
          property_name: title,
          item_type: "property",
          type: "property",
          item_category: "property",
          category: "property",
          property_price: amount || null,
          property_location: related || null,
          project_name: related || null,
          listing_type: "sale",
          item_status: value("unganiQuickStatus") || "available",
          status: value("unganiQuickStatus") || "available",
          property_status: value("unganiQuickStatus") || "available",
          notes: description || null,
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString()
        });
    }

    if (response.error) {
      alert(response.error.message);
      return;
    }

    closeQuickAdd();
    showToast("Quick add saved ✓");
    loadNotificationBadge();

    setTimeout(function () {
      window.location.reload();
    }, 450);
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
      return "Ksh " + new Intl.NumberFormat("en-KE", {
        maximumFractionDigits: 0
      }).format(amount);
    } catch (error) {
      return "Ksh " + amount.toLocaleString();
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

  function shortText(valueText, limit) {
    const text = String(valueText || "");
    const max = Number(limit || 80);

    if (text.length <= max) return text;

    return text.slice(0, max) + "...";
  }

  function exposeGlobals() {
    window.UnganiClientShared = {
      initPage,
      setContent,
      loadingCard,
      errorCard,
      metricCard,
      safe,
      cleanText,
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
      withButtonLoading,
      toggleTheme,
      toggleSidebar,
      logout,
      signInFromForm,
      getTenantName,
      getBusinessTypeLabel,
      handleGlobalSearchInput,
      closeGlobalSearch,
      toggleNotifications,
      toggleTeamChat,
      closeTeamChat,
      sendTeamChatMessage,
      openQuickAdd,
      closeQuickAdd,
      changeQuickAddType,
      saveQuickAdd,
      openModal,
      closeModal,
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
(function () {
  let readOnlyState = {
    loaded: false,
    isReadOnly: false,
    message: "This account is currently in read-only mode. Please contact UNGANI or update payment to continue editing."
  };

  function waitForSharedState(callback) {
    let tries = 0;

    const timer = setInterval(function () {
      tries++;

      if (
        window.UnganiClientShared &&
        typeof window.UnganiClientShared.getState === "function"
      ) {
        clearInterval(timer);
        callback(window.UnganiClientShared.getState());
        return;
      }

      if (tries > 80) {
        clearInterval(timer);
      }
    }, 250);
  }

  async function loadReadOnlyAccess() {
    waitForSharedState(async function (state) {
      if (!state || !state.supabaseClient || !state.tenantId) {
        setTimeout(loadReadOnlyAccess, 800);
        return;
      }

      try {
        const accessResponse = await state.supabaseClient.rpc("get_my_ungani_subscription_access");

        if (!accessResponse.error && accessResponse.data) {
          const access = accessResponse.data;
          readOnlyState.isReadOnly = access.can_write === false || access.can_write === "false";

          if (access.reason) {
            readOnlyState.message = access.reason;
          }
        }
      } catch (error) {
        console.warn("UNGANI read-only access check skipped:", error.message);
      }

      try {
        const noticeResponse = await state.supabaseClient.rpc("get_my_ungani_read_only_notice");

        if (!noticeResponse.error && noticeResponse.data) {
          if (noticeResponse.data.message) {
            readOnlyState.message = noticeResponse.data.message;
          }

          if (noticeResponse.data.read_only === true || noticeResponse.data.read_only === "true") {
            readOnlyState.isReadOnly = true;
          }
        }
      } catch (error) {
        console.warn("UNGANI read-only notice check skipped:", error.message);
      }

      readOnlyState.loaded = true;

      renderReadOnlyBanner();
      installReadOnlyGuard();
      exposeReadOnlyHelpers();
    });
  }

  function renderReadOnlyBanner() {
    if (!readOnlyState.isReadOnly) {
      return;
    }

    if (document.getElementById("unganiReadOnlyBanner")) {
      return;
    }

    const topbar = document.querySelector(".ungani-topbar");

    if (!topbar) {
      setTimeout(renderReadOnlyBanner, 800);
      return;
    }

    injectReadOnlyStyles();

    const banner = document.createElement("div");
    banner.id = "unganiReadOnlyBanner";
    banner.className = "ungani-readonly-banner";
    banner.innerHTML = `
      <div>
        <strong>Read-only mode active</strong>
        <p>${safe(readOnlyState.message)}</p>
      </div>
      <a class="ungani-btn gold" href="my-billing.html">Open Billing</a>
    `;

    topbar.insertAdjacentElement("afterend", banner);
  }

  function injectReadOnlyStyles() {
    if (document.getElementById("ungani-readonly-style")) {
      return;
    }

    const style = document.createElement("style");
    style.id = "ungani-readonly-style";
    style.textContent = `
      .ungani-readonly-banner {
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 14px;
        margin: -8px 0 18px;
        padding: 15px 16px;
        border-radius: 20px;
        border: 1px solid rgba(212,166,58,0.45);
        background:
          radial-gradient(circle at top right, rgba(212,166,58,0.22), transparent 30%),
          rgba(212,166,58,0.12);
        color: var(--ungani-text);
        box-shadow: var(--ungani-shadow);
      }

      .ungani-readonly-banner strong {
        display: block;
        margin-bottom: 4px;
        color: var(--ungani-text);
      }

      .ungani-readonly-banner p {
        margin: 0;
        color: var(--ungani-muted);
        font-size: 13px;
        line-height: 1.5;
      }

      @media (max-width: 720px) {
        .ungani-readonly-banner {
          flex-direction: column;
          align-items: flex-start;
        }
      }
    `;

    document.head.appendChild(style);
  }

  function installReadOnlyGuard() {
    if (document.body.dataset.unganiReadOnlyGuardInstalled === "true") {
      return;
    }

    document.body.dataset.unganiReadOnlyGuardInstalled = "true";

    document.addEventListener("submit", function (event) {
      if (!readOnlyState.isReadOnly) {
        return;
      }

      const form = event.target;

      if (form && form.closest(".ungani-login-card")) {
        return;
      }

      event.preventDefault();
      event.stopImmediatePropagation();
      showReadOnlyMessage();
    }, true);

    document.addEventListener("click", function (event) {
      if (!readOnlyState.isReadOnly) {
        return;
      }

      const target = event.target.closest("button");

      if (!target) {
        return;
      }

      const text = String(target.textContent || "").toLowerCase();

      const writeWords = [
        "save",
        "submit",
        "update",
        "delete",
        "restore",
        "complete",
        "done",
        "resolved",
        "closed",
        "in progress",
        "available",
        "reserved",
        "sold",
        "add",
        "quick add"
      ];

      const isWriteButton = writeWords.some(function (word) {
        return text.includes(word);
      });

      if (!isWriteButton) {
        return;
      }

      event.preventDefault();
      event.stopImmediatePropagation();
      showReadOnlyMessage();
    }, true);
  }

  function showReadOnlyMessage() {
    if (
      window.UnganiClientShared &&
      typeof window.UnganiClientShared.showToast === "function"
    ) {
      window.UnganiClientShared.showToast(readOnlyState.message);
      return;
    }

    alert(readOnlyState.message);
  }

  function exposeReadOnlyHelpers() {
    if (!window.UnganiClientShared) {
      return;
    }

    window.UnganiClientShared.isReadOnlyMode = function () {
      return readOnlyState.isReadOnly;
    };

    window.UnganiClientShared.getReadOnlyMessage = function () {
      return readOnlyState.message;
    };

    window.UnganiClientShared.ensureCanWrite = function () {
      if (!readOnlyState.isReadOnly) {
        return true;
      }

      showReadOnlyMessage();
      return false;
    };

    window.UnganiClientShared.reloadReadOnlyAccess = function () {
      return loadReadOnlyAccess();
    };
  }

  function safe(valueText) {
    return String(valueText === null || valueText === undefined ? "" : valueText)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", loadReadOnlyAccess);
  } else {
    loadReadOnlyAccess();
  }
})();
(function () {
  function waitForUnganiShared(callback) {
    let tries = 0;

    const timer = setInterval(function () {
      tries++;

      if (
        window.UnganiClientShared &&
        typeof window.UnganiClientShared.getState === "function"
      ) {
        clearInterval(timer);
        callback(window.UnganiClientShared.getState());
        return;
      }

      if (tries > 80) {
        clearInterval(timer);
      }
    }, 250);
  }

  async function getEngineNotifications() {
    const shared = window.UnganiClientShared;

    if (!shared || typeof shared.getState !== "function") {
      return [];
    }

    const state = shared.getState();

    if (!state || !state.supabaseClient || !state.tenantId) {
      return [];
    }

    try {
      const response = await state.supabaseClient.rpc("get_my_ungani_notifications", {
        p_limit: 30
      });

      if (response.error) {
        console.warn("UNGANI notification engine error:", response.error.message);
        return [];
      }

      return response.data || [];
    } catch (error) {
      console.warn("UNGANI notification engine skipped:", error.message);
      return [];
    }
  }

  async function refreshEngineNotificationBadge() {
    const countEl = document.getElementById("unganiBellCount");

    if (!countEl) {
      return;
    }

    const items = await getEngineNotifications();
    const unread = items.filter(function (item) {
      return item.is_read === false || item.status === "unread";
    });

    countEl.textContent = String(unread.length);
    countEl.style.display = unread.length > 0 ? "inline-flex" : "none";
  }

  async function toggleEngineNotifications() {
    const panel = document.getElementById("unganiNotificationPanel");

    if (!panel) {
      return;
    }

    if (
      window.UnganiClientShared &&
      typeof window.UnganiClientShared.closeGlobalSearch === "function"
    ) {
      window.UnganiClientShared.closeGlobalSearch();
    }

    if (
      window.UnganiClientShared &&
      typeof window.UnganiClientShared.closeQuickAdd === "function"
    ) {
      window.UnganiClientShared.closeQuickAdd();
    }

    if (panel.style.display === "block") {
      panel.style.display = "none";
      return;
    }

    panel.style.display = "block";
    panel.innerHTML = `
      <div class="ungani-panel-head">
        <strong>Notifications</strong>
        <button class="ungani-btn dark" type="button" onclick="UnganiClientShared.toggleNotifications()">Close</button>
      </div>
      <div class="ungani-panel-body">
        <section class="ungani-card">
          <div class="ungani-section-title">
            <div>
              <h3>Loading notifications...</h3>
              <p class="ungani-small">Checking your latest UNGANI updates.</p>
            </div>
            <span class="ungani-badge gold">Loading</span>
          </div>
        </section>
      </div>
    `;

    const items = await getEngineNotifications();

    panel.innerHTML = `
      <div class="ungani-panel-head">
        <strong>Notifications</strong>
        <button class="ungani-btn dark" type="button" onclick="UnganiClientShared.toggleNotifications()">Close</button>
      </div>

      <div class="ungani-panel-body">
        ${items.length === 0 ? `
          <div class="ungani-empty">
            <h3>No notifications yet</h3>
            <p>Support updates, task reminders, payment updates, stock alerts, and system messages will appear here.</p>
          </div>
        ` : items.map(function (item) {
          const color = getNotificationColor(item);
          const title = item.notification_title || "UNGANI Notification";
          const message = item.notification_message || "";
          const type = item.notification_type || "system";
          const href = item.link_url || "#";
          const created = formatNotificationDate(item.created_at);
          const readClass = item.is_read ? "read" : "unread";

          return `
            <a class="ungani-alert-row ungani-engine-notification ${readClass}" href="${safeAttr(href)}" onclick="UnganiNotificationEngine.markRead('${safeAttr(item.id)}')">
              <span class="ungani-badge ${safeAttr(color)}">${safe(type)}</span>
              ${item.is_read ? "" : `<span class="ungani-badge red">New</span>`}
              <h3 style="font-size:15px;margin:8px 0 4px;">${safe(title)}</h3>
              <p class="ungani-small" style="margin:0;">${safe(message)}</p>
              <p class="ungani-small" style="margin:6px 0 0;">${safe(created)}</p>
            </a>
          `;
        }).join("")}
      </div>
    `;
  }

  async function markRead(notificationId) {
    const shared = window.UnganiClientShared;

    if (!shared || typeof shared.getState !== "function") {
      return;
    }

    const state = shared.getState();

    if (!state || !state.supabaseClient || !notificationId) {
      return;
    }

    try {
      await state.supabaseClient.rpc("mark_my_ungani_notification_read", {
        p_notification_id: notificationId
      });

      setTimeout(refreshEngineNotificationBadge, 400);
    } catch (error) {
      console.warn("UNGANI mark notification read skipped:", error.message);
    }
  }

  function getNotificationColor(item) {
    const priority = String(item.priority || "").toLowerCase();
    const type = String(item.notification_type || "").toLowerCase();

    if (priority === "urgent" || priority === "high") return "red";
    if (type.includes("support")) return "gold";
    if (type.includes("task")) return "blue";
    if (type.includes("payment") || type.includes("billing")) return "green";
    if (type.includes("stock")) return "red";
    if (type.includes("lead") || type.includes("people")) return "blue";
    if (type.includes("property") || type.includes("item")) return "gold";

    return "blue";
  }

  function formatNotificationDate(valueText) {
    if (!valueText) {
      return "Just now";
    }

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

  function safe(valueText) {
    return String(valueText === null || valueText === undefined ? "" : valueText)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  function safeAttr(valueText) {
    return safe(valueText);
  }

  function installNotificationEngine() {
    if (!window.UnganiClientShared) {
      return;
    }

    window.UnganiClientShared.toggleNotifications = toggleEngineNotifications;
    window.UnganiClientShared.refreshNotificationBadge = refreshEngineNotificationBadge;

    window.UnganiNotificationEngine = {
      refreshBadge: refreshEngineNotificationBadge,
      toggle: toggleEngineNotifications,
      markRead: markRead
    };

    refreshEngineNotificationBadge();

    setInterval(function () {
      refreshEngineNotificationBadge();
    }, 60000);
  }

  waitForUnganiShared(function () {
    installNotificationEngine();
  });
})();
