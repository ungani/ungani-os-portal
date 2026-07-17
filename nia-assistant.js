(function () {
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

  // Photographic avatar (replaces the earlier flat-illustration SVG draft).
  // Square, pre-cropped to center the face for a circular crop at any size.
  const NIA_AVATAR_IMG = '<img class="nia-avatar-img" src="nia-avatar.jpg" alt="Nia" draggable="false" />';

  const SEEN_KEY = "ungani_nia_seen";

  const NAV_ITEMS = [
    { key: "dashboard", href: "client.html", icon: "🏠", label: "Dashboard", aliases: ["home", "dashboard", "main page"] },
    { key: "money", href: "my-money.html", icon: "💰", label: "Money", aliases: ["money", "finance", "finances", "transactions", "expenses", "expense", "income", "payments", "payment", "invoices", "invoice", "petty cash"] },
    { key: "documents", href: "my-documents.html", icon: "📄", label: "Documents", aliases: ["documents", "document", "docs", "files", "uploads"] },
    { key: "reports", href: "reports.html", icon: "📑", label: "Reports", aliases: ["reports", "report", "export", "exports"] },
    { key: "people", href: "my-people.html", icon: "👥", label: "People", aliases: ["people", "customers", "customer", "clients", "client", "leads", "lead", "staff", "employees", "employee", "contacts", "drivers", "driver", "suppliers", "supplier"] },
    { key: "tasks", href: "my-tasks.html", icon: "✅", label: "Tasks", aliases: ["tasks", "task", "follow-ups", "follow ups", "to-do", "todo", "reminders", "reminder"] },
    { key: "items", href: "my-items.html", icon: "🏷️", label: "Items / Assets", aliases: ["items", "assets", "inventory", "stock", "properties", "property", "units", "listings"] },
    { key: "records", href: "my-records.html", icon: "🗂️", label: "Records", aliases: ["records", "record"] },
    { key: "calendar", href: "my-calendar.html", icon: "📅", label: "Calendar", aliases: ["calendar", "schedule", "trips", "trip", "bookings", "booking"] },
    { key: "charts", href: "my-charts.html", icon: "📊", label: "Charts", aliases: ["charts", "chart", "analytics", "graphs"] },
    { key: "overview", href: "my-overview.html", icon: "📌", label: "Overview", aliases: ["overview"] },
    { key: "activity", href: "my-activity.html", icon: "🕒", label: "Activity Feed", aliases: ["activity", "activity feed", "history"] },
    { key: "notices", href: "my-notices.html", icon: "🔔", label: "Notices", aliases: ["notices", "notifications", "notice"] },
    { key: "team-chat", href: "my-team-chat.html", icon: "👨‍👩‍👧‍👦", label: "Team Chat", aliases: ["team chat", "chat with my team"] },
    { key: "profile", href: "my-profile.html", icon: "🏢", label: "Business Profile", aliases: ["business profile", "company profile"] },
    { key: "account", href: "account.html", icon: "⚙️", label: "Settings", aliases: ["settings", "account", "account settings", "preferences"] },
    { key: "support", href: "my-support.html", icon: "🛟", label: "Contact Support", aliases: ["support", "contact support", "help desk", "get help"] }
  ];

  const NAV_BY_KEY = {};
  NAV_ITEMS.forEach(function (item) { NAV_BY_KEY[item.key] = item; });

  const SEARCH_TABLES = [
    { table: "business_items", label: "Property / Item", href: "my-items.html", titleFields: ["property_name", "item_name", "name", "title"], detailFields: ["property_status", "item_status", "status", "property_location"] },
    { table: "tasks", label: "Task", href: "my-tasks.html", titleFields: ["task_title", "title", "name"], detailFields: ["status", "priority", "due_date"] },
    { table: "client_people", label: "Person / Lead", href: "my-people.html", titleFields: ["full_name", "name"], detailFields: ["person_type", "status", "phone", "email"] },
    { table: "documents", label: "Document", href: "my-documents.html", titleFields: ["document_title", "title", "file_name"], detailFields: ["document_type", "status"] },
    { table: "business_records", label: "Record", href: "my-records.html", titleFields: ["record_title", "title", "name"], detailFields: ["record_type", "status"] },
    { table: "transactions", label: "Money Record", href: "my-money.html", titleFields: ["category_name", "category", "description"], detailFields: ["transaction_type", "type", "status", "amount"] }
  ];

  const HELP_TOPICS = [
    {
      key: "password",
      match: ["password", "reset password", "forgot password", "login"],
      question: "How do I reset my password?",
      answer: "On the login screen, select \"Forgot password\" and follow the emailed reset link. If you're already signed in, you can also set a new password from Account Settings.",
      href: "login.html",
      linkLabel: "Open Login"
    },
    {
      key: "invite",
      match: ["invite", "invite staff", "add staff", "add team member", "add user"],
      question: "How do I invite staff?",
      answer: "Go to Team Access, then use \"Invite\" to send a staff member an email invitation with the right role.",
      href: "my-team-access.html",
      linkLabel: "Open Team Access"
    },
    {
      key: "subscription",
      match: ["subscription", "billing", "plan", "upgrade", "change my plan"],
      question: "How do I change my subscription?",
      answer: "Open Account Settings and look for the Subscription section, where you can review your current plan and request a change.",
      href: "my-settings.html",
      linkLabel: "Open Settings"
    },
    {
      key: "export",
      match: ["export", "export report", "export reports", "download report"],
      question: "How do I export reports?",
      answer: "Open Reports, choose the report you need, then use the export/print option to download or print it.",
      href: "reports.html",
      linkLabel: "Open Reports"
    },
    {
      key: "restore",
      match: ["restore", "deleted", "recover", "recently deleted", "recycle bin"],
      question: "How do I restore deleted records?",
      answer: "Open Recently Deleted, find the record, and select Restore. Deleted records are kept there for a limited time before permanent removal.",
      href: "my-recently-deleted.html",
      linkLabel: "Open Recently Deleted"
    },
    {
      key: "contact",
      match: ["contact support", "talk to someone", "human", "get help", "support ticket"],
      question: "How do I contact support?",
      answer: "Open Support Issues and submit your question — the UNGANI team will follow up from there.",
      href: "my-support.html",
      linkLabel: "Open Support"
    }
  ];

  const HOW_TO_TOPICS = [
    {
      key: "add-customer",
      match: ["add a customer", "add customer", "create a customer", "new customer", "add a client", "add client"],
      pageKey: "people",
      steps: ["Open People.", "Select \"+ Add Person\".", "Fill in the name, type (customer, client, lead, etc.), and contact details.", "Select Save."]
    },
    {
      key: "upload-document",
      match: ["upload a document", "upload document", "add a document", "add document", "upload file"],
      pageKey: "documents",
      steps: ["Open Documents.", "Select \"+ Add Document\".", "Choose the document type and paste in a file link (Google Drive, Dropbox, etc.).", "Select Save."]
    },
    {
      key: "generate-report",
      match: ["generate a report", "generate report", "create a report", "make a report", "run a report"],
      pageKey: "reports",
      steps: ["Open Reports.", "Choose the report type and date range you need.", "Select Generate, then export or print if you need a copy."]
    },
    {
      key: "add-expense",
      match: ["add an expense", "add expense", "record an expense", "log an expense", "new expense"],
      pageKey: "money",
      steps: ["Open Money.", "Select \"+ Add Money Record\".", "Set Type to Expense, fill in the amount, category, and date.", "Select Save."]
    },
    {
      key: "add-income",
      match: ["add income", "record income", "log a sale", "add a sale", "new income"],
      pageKey: "money",
      steps: ["Open Money.", "Select \"+ Add Money Record\".", "Set Type to Income, fill in the amount, category, and date.", "Select Save."]
    },
    {
      key: "add-task",
      match: ["add a task", "add task", "create a task", "new task", "add a reminder", "add a follow-up"],
      pageKey: "tasks",
      steps: ["Open Tasks.", "Select \"+ Add Task\".", "Fill in the title, type, due date, and who it's assigned to.", "Select Save."]
    },
    {
      key: "add-property",
      match: ["add a property", "add property", "create a property", "new property", "add an item", "add item", "new item"],
      pageKey: "items",
      steps: ["Open Items.", "Select \"Add Property\".", "Fill in the name, listing type, location, and price.", "Select Save."]
    },
    {
      key: "add-record",
      match: ["add a record", "add record", "create a record", "new record", "log a record"],
      pageKey: "records",
      steps: ["Open Records.", "Select \"+ Add Record\".", "Fill in the title, record type, and status.", "Select Save."]
    }
  ];

  // Quick "show me around" overview — a lightweight stand-in for a real
  // guided tour (see memory: a proper step-by-step spotlight tour is a
  // separate, bigger feature for later). This just gives a useful,
  // linked summary of the main sections instead of a dead-end button.
  const OVERVIEW_SECTIONS = [
    { key: "money", blurb: "Track your income and expenses." },
    { key: "documents", blurb: "Store and organize your files." },
    { key: "tasks", blurb: "Your to-do list and follow-ups." },
    { key: "people", blurb: "Manage customers, staff, and contacts." },
    { key: "items", blurb: "Track properties, assets, and stock." },
    { key: "records", blurb: "Operational notes and updates." },
    { key: "calendar", blurb: "See your schedule and activities." },
    { key: "reports", blurb: "Generate and export reports." }
  ];

  const QUICK_SUGGESTIONS = [
    { label: "Dashboard", type: "nav", key: "dashboard" },
    { label: "Money", type: "nav", key: "money" },
    { label: "Documents", type: "nav", key: "documents" },
    { label: "Reports", type: "nav", key: "reports" },
    { label: "Customers", type: "nav", key: "people" },
    { label: "Staff", type: "nav", key: "people" },
    { label: "Tasks", type: "nav", key: "tasks" },
    { label: "Settings", type: "nav", key: "account" },
    { label: "Help", type: "help" },
    { label: "Contact Support", type: "nav", key: "support" }
  ];

  const CREATE_ACTIONS = [
    { key: "income", match: ["create income", "add income", "log income", "record income", "new income", "log a sale"], href: "my-money.html", params: { action: "add", type: "income" }, confirm: "Opening Money with a new Income record ready to fill in." },
    { key: "expense", match: ["create expense", "add expense", "log expense", "record expense", "new expense"], href: "my-money.html", params: { action: "add", type: "expense" }, confirm: "Opening Money with a new Expense record ready to fill in." },
    { key: "pettyCash", match: ["create petty cash", "add petty cash", "log petty cash", "new petty cash"], href: "my-money.html", params: { action: "add", type: "petty_cash" }, confirm: "Opening Money with a new Petty Cash record ready to fill in." },
    { key: "createTask", match: ["create task", "add task", "new task", "create a follow-up", "add a follow-up"], href: "my-tasks.html", params: { action: "add" }, confirm: "Opening Tasks with a new task ready to fill in." },
    { key: "createCustomer", match: ["create customer", "add customer", "new customer", "create client", "add client"], href: "my-people.html", params: { action: "add" }, confirm: "Opening People with a new person ready to fill in." },
    { key: "createEmployee", match: ["create employee", "add employee", "new employee", "add staff", "create staff"], href: "my-people.html", params: { action: "add" }, confirm: "Opening People with a new person ready to fill in." },
    { key: "createProperty", match: ["create property", "add property", "new property", "add item", "create item", "new item"], href: "my-items.html", params: { action: "add" }, confirm: "Opening Items with a new property ready to fill in." },
    { key: "createRecord", match: ["create record", "add record", "new record", "log a record"], href: "my-records.html", params: { action: "add" }, confirm: "Opening Records with a new record ready to fill in." },
    { key: "uploadDocument", match: ["upload document", "upload a document", "add document"], href: "my-documents.html", params: { action: "add" }, confirm: "Opening Documents with a new document ready to fill in." },
    { key: "openCalendar", match: ["open calendar"], href: "my-calendar.html", params: {}, confirm: "Opening Calendar." },
    { key: "openReports", match: ["open reports"], href: "reports.html", params: {}, confirm: "Opening Reports." },
    { key: "openNotifications", match: ["open notifications", "open notices"], href: "my-notices.html", params: {}, confirm: "Opening Notices." }
  ];

  const CREATE_ACTIONS_BY_KEY = {};
  CREATE_ACTIONS.forEach(function (item) { CREATE_ACTIONS_BY_KEY[item.key] = item; });

  // Per-page quick-action chips. Dashboard keeps the broad entry-point menu;
  // every other configured page gets chips specific to what you'd actually
  // do there. Pages without an entry here fall back to QUICK_SUGGESTIONS.
  const PAGE_CONFIGS = {
    dashboard: {
      greeting: "Welcome back! What would you like to do?",
      chips: QUICK_SUGGESTIONS
    },
    money: {
      greeting: "Welcome back! Here's what I can help with on Money.",
      chips: [
        { label: "Add Income", type: "create", actionKey: "income" },
        { label: "Add Expense", type: "create", actionKey: "expense" },
        { label: "Add Petty Cash", type: "create", actionKey: "pettyCash" },
        { label: "Insights & Tools", type: "insights" },
        { label: "Find a Record", type: "search-prompt" },
        { label: "How do I add an expense?", type: "howto", key: "add-expense" },
        { label: "Dashboard", type: "nav", key: "dashboard" },
        { label: "Help", type: "help" }
      ]
    },
    documents: {
      greeting: "Welcome back! Here's what I can help with on Documents.",
      chips: [
        { label: "Upload Document", type: "create", actionKey: "uploadDocument" },
        { label: "Find a Document", type: "search-prompt" },
        { label: "Insights & Tools", type: "insights" },
        { label: "How do I upload a document?", type: "howto", key: "upload-document" },
        { label: "Dashboard", type: "nav", key: "dashboard" },
        { label: "Help", type: "help" }
      ]
    },
    people: {
      greeting: "Welcome back! Here's what I can help with on People.",
      chips: [
        { label: "Add Customer", type: "create", actionKey: "createCustomer" },
        { label: "Add Employee", type: "create", actionKey: "createEmployee" },
        { label: "Find a Person", type: "search-prompt" },
        { label: "Insights & Tools", type: "insights" },
        { label: "How do I add a customer?", type: "howto", key: "add-customer" },
        { label: "Dashboard", type: "nav", key: "dashboard" },
        { label: "Help", type: "help" }
      ]
    },
    tasks: {
      greeting: "Welcome back! Here's what I can help with on Tasks.",
      chips: [
        { label: "Add Task", type: "create", actionKey: "createTask" },
        { label: "Find a Task", type: "search-prompt" },
        { label: "Insights & Tools", type: "insights" },
        { label: "How do I add a task?", type: "howto", key: "add-task" },
        { label: "Dashboard", type: "nav", key: "dashboard" },
        { label: "Help", type: "help" }
      ]
    },
    items: {
      greeting: "Welcome back! Here's what I can help with on Items.",
      chips: [
        { label: "Add Property", type: "create", actionKey: "createProperty" },
        { label: "Find a Property", type: "search-prompt" },
        { label: "How do I add a property?", type: "howto", key: "add-property" },
        { label: "Dashboard", type: "nav", key: "dashboard" },
        { label: "Help", type: "help" }
      ]
    },
    records: {
      greeting: "Welcome back! Here's what I can help with on Records.",
      chips: [
        { label: "Add Record", type: "create", actionKey: "createRecord" },
        { label: "Find a Record", type: "search-prompt" },
        { label: "How do I add a record?", type: "howto", key: "add-record" },
        { label: "Dashboard", type: "nav", key: "dashboard" },
        { label: "Help", type: "help" }
      ]
    },
    calendar: {
      greeting: "Welcome back! Here's what I can help with on Calendar.",
      chips: [
        { label: "Add Calendar Activity", type: "call", fnName: "scrollToEventForm", confirm: "Scrolling to the Add Calendar Activity form for you." },
        { label: "Find an Event", type: "search-prompt" },
        { label: "How do I add a task?", type: "howto", key: "add-task" },
        { label: "Dashboard", type: "nav", key: "dashboard" },
        { label: "Help", type: "help" }
      ]
    }
  };

  function getPageConfig() {
    return PAGE_CONFIGS[state.pageKey] || PAGE_CONFIGS.dashboard;
  }

  const state = {
    open: false,
    surface: "unknown",
    pageKey: "",
    supabaseClient: null,
    tenantId: null,
    tenant: null,
    userId: null,
    preferredLanguage: "en",
    ready: false,
    messages: [],
    listening: false,
    lastReplyText: ""
  };

  function safe(value) {
    return String(value === null || value === undefined ? "" : value).replace(/[&<>"']/g, function (ch) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" }[ch];
    });
  }

  function attr(value) {
    return safe(value);
  }

  function isDarkMode() {
    const htmlTheme = document.documentElement.getAttribute("data-ungani-theme");
    if (htmlTheme === "dark") return true;
    if (htmlTheme === "light") return false;

    const bodyTheme = document.body && document.body.getAttribute("data-theme");
    if (bodyTheme === "dark") return true;
    if (bodyTheme === "light") return false;

    return !!(window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches);
  }

  function injectStyles() {
    if (document.getElementById("niaStyles")) return;

    const style = document.createElement("style");
    style.id = "niaStyles";
    style.textContent = `
      .nia-fab {
        position: fixed;
        right: 20px;
        bottom: 20px;
        z-index: 99998;
        width: 58px;
        height: 58px;
        border-radius: 50%;
        border: none;
        cursor: pointer;
        padding: 0;
        overflow: hidden;
        display: flex;
        align-items: center;
        justify-content: center;
        box-shadow: 0 14px 34px rgba(6,28,61,0.35);
        transition: transform 0.18s ease, box-shadow 0.18s ease;
      }

      .nia-avatar-graphic {
        display: block;
        width: 100%;
        height: 100%;
        line-height: 0;
        border-radius: 50%;
      }

      .nia-avatar-img {
        display: block;
        width: 100%;
        height: 100%;
        object-fit: cover;
        border-radius: 50%;
      }

      .nia-avatar-graphic {
        animation: niaIdlePulse 3.2s ease-in-out infinite;
      }

      @keyframes niaIdlePulse {
        0%, 100% { transform: scale(1); }
        50% { transform: scale(1.035); }
      }

      .nia-avatar-thinking {
        animation: niaThinkingRing 0.9s ease-in-out infinite;
      }

      @keyframes niaThinkingRing {
        0%, 100% { box-shadow: 0 0 0 0 rgba(212,166,58,0.55); }
        50% { box-shadow: 0 0 0 5px rgba(212,166,58,0); }
      }

      @media (prefers-reduced-motion: reduce) {
        .nia-avatar-graphic,
        .nia-avatar-thinking {
          animation: none;
        }
      }

      .nia-fab:hover {
        transform: translateY(-3px);
        box-shadow: 0 18px 42px rgba(6,28,61,0.42);
      }

      .nia-fab-dot {
        position: absolute;
        top: 4px;
        right: 4px;
        width: 12px;
        height: 12px;
        border-radius: 50%;
        background: ${BRAND.red};
        border: 2px solid ${BRAND.white};
      }

      .nia-tagline {
        position: fixed;
        right: 88px;
        bottom: 34px;
        z-index: 99997;
        background: ${BRAND.white};
        color: ${BRAND.navy};
        border: none;
        font-size: 12.5px;
        font-weight: 800;
        font-family: inherit;
        padding: 9px 15px;
        border-radius: 999px;
        box-shadow: 0 10px 24px rgba(6,28,61,0.22);
        white-space: nowrap;
        cursor: pointer;
      }

      .nia-tagline::after {
        content: "";
        position: absolute;
        top: 50%;
        right: -5px;
        width: 10px;
        height: 10px;
        background: ${BRAND.white};
        transform: translateY(-50%) rotate(45deg);
        border-radius: 2px;
      }

      @media (max-width: 640px) {
        .nia-tagline {
          display: none;
        }
      }

      .nia-panel {
        position: fixed;
        right: 20px;
        bottom: 90px;
        z-index: 99999;
        width: min(380px, calc(100vw - 32px));
        height: min(560px, calc(100vh - 120px));
        background: ${BRAND.white};
        color: ${BRAND.navy};
        border-radius: 22px;
        box-shadow: 0 24px 60px rgba(6,28,61,0.30);
        display: none;
        flex-direction: column;
        overflow: hidden;
        border: 1px solid rgba(6,28,61,0.08);
      }

      .nia-panel.open {
        display: flex;
      }

      .nia-panel[data-theme="dark"] {
        background: #0B2346;
        color: #F5F5F3;
        border-color: rgba(255,255,255,0.12);
      }

      .nia-panel-head {
        flex: none;
        display: flex;
        align-items: center;
        justify-content: space-between;
        gap: 10px;
        padding: 14px 16px;
        background: linear-gradient(135deg, ${BRAND.navy}, ${BRAND.navy2});
        color: ${BRAND.white};
      }

      .nia-panel-head .nia-title {
        display: flex;
        align-items: center;
        gap: 10px;
      }

      .nia-panel-head .nia-avatar {
        width: 34px;
        height: 34px;
        border-radius: 50%;
        overflow: hidden;
        display: flex;
        align-items: center;
        justify-content: center;
        flex: none;
      }

      .nia-panel-head strong {
        display: block;
        font-size: 14px;
      }

      .nia-panel-head span {
        display: block;
        font-size: 11px;
        color: rgba(255,255,255,0.72);
      }

      .nia-panel-close {
        background: rgba(255,255,255,0.14);
        border: none;
        color: ${BRAND.white};
        width: 28px;
        height: 28px;
        border-radius: 50%;
        cursor: pointer;
        font-size: 14px;
        flex: none;
      }

      .nia-messages {
        flex: 1;
        overflow-y: auto;
        padding: 14px;
        display: flex;
        flex-direction: column;
        gap: 10px;
        background: ${BRAND.offWhite};
      }

      .nia-panel[data-theme="dark"] .nia-messages {
        background: #071B3B;
      }

      .nia-bubble {
        max-width: 86%;
        padding: 10px 13px;
        border-radius: 15px;
        font-size: 13px;
        line-height: 1.5;
      }

      .nia-bubble.nia {
        align-self: flex-start;
        background: ${BRAND.white};
        color: ${BRAND.navy};
        border: 1px solid rgba(6,28,61,0.08);
        border-bottom-left-radius: 4px;
      }

      .nia-panel[data-theme="dark"] .nia-bubble.nia {
        background: #133769;
        color: #F5F5F3;
        border-color: rgba(255,255,255,0.10);
      }

      .nia-bubble.user {
        align-self: flex-end;
        background: ${BRAND.navy};
        color: ${BRAND.white};
        border-bottom-right-radius: 4px;
      }

      .nia-bubble p {
        margin: 0 0 6px;
      }

      .nia-bubble p:last-child {
        margin-bottom: 0;
      }

      .nia-bubble ol, .nia-bubble ul {
        margin: 6px 0 0;
        padding-left: 18px;
      }

      .nia-bubble a.nia-link-btn {
        display: inline-block;
        margin-top: 8px;
        padding: 6px 12px;
        border-radius: 999px;
        background: ${BRAND.gold};
        color: ${BRAND.navy};
        font-weight: 800;
        font-size: 12px;
        text-decoration: none;
      }

      .nia-typing {
        align-self: flex-start;
        display: flex;
        gap: 4px;
        padding: 10px 13px;
        background: ${BRAND.white};
        border-radius: 15px;
        border: 1px solid rgba(6,28,61,0.08);
      }

      .nia-panel[data-theme="dark"] .nia-typing {
        background: #133769;
        border-color: rgba(255,255,255,0.10);
      }

      .nia-typing span {
        width: 6px;
        height: 6px;
        border-radius: 50%;
        background: #64748B;
        opacity: 0.5;
        animation: niaTypingBounce 1s infinite ease-in-out;
      }

      .nia-typing span:nth-child(2) { animation-delay: 0.15s; }
      .nia-typing span:nth-child(3) { animation-delay: 0.3s; }

      @keyframes niaTypingBounce {
        0%, 60%, 100% { transform: translateY(0); opacity: 0.4; }
        30% { transform: translateY(-4px); opacity: 0.9; }
      }

      .nia-quick-actions {
        flex: none;
        display: flex;
        flex-wrap: wrap;
        gap: 7px;
        padding: 0 14px 12px;
        background: ${BRAND.offWhite};
      }

      .nia-panel[data-theme="dark"] .nia-quick-actions {
        background: #071B3B;
      }

      .nia-chip {
        border: 1px solid rgba(6,28,61,0.14);
        background: ${BRAND.white};
        color: ${BRAND.navy};
        border-radius: 999px;
        padding: 6px 12px;
        font-size: 12px;
        font-weight: 750;
        cursor: pointer;
      }

      .nia-panel[data-theme="dark"] .nia-chip {
        background: #133769;
        color: #F5F5F3;
        border-color: rgba(255,255,255,0.14);
      }

      .nia-chip:hover {
        border-color: ${BRAND.gold};
      }

      .nia-input-row {
        flex: none;
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 10px 12px;
        border-top: 1px solid rgba(6,28,61,0.08);
        background: ${BRAND.white};
      }

      .nia-panel[data-theme="dark"] .nia-input-row {
        background: #0B2346;
        border-color: rgba(255,255,255,0.10);
      }

      .nia-text-input {
        flex: 1;
        border: 1px solid rgba(6,28,61,0.16);
        border-radius: 999px;
        padding: 9px 14px;
        font-size: 13px;
        background: ${BRAND.offWhite};
        color: ${BRAND.navy};
      }

      .nia-panel[data-theme="dark"] .nia-text-input {
        background: #071B3B;
        color: #F5F5F3;
        border-color: rgba(255,255,255,0.16);
      }

      .nia-round-btn {
        flex: none;
        width: 34px;
        height: 34px;
        border-radius: 50%;
        border: none;
        cursor: pointer;
        font-size: 14px;
        display: flex;
        align-items: center;
        justify-content: center;
      }

      .nia-mic-btn {
        background: rgba(6,28,61,0.08);
        color: ${BRAND.navy};
      }

      .nia-panel[data-theme="dark"] .nia-mic-btn {
        background: rgba(255,255,255,0.12);
        color: #F5F5F3;
      }

      .nia-mic-btn.listening {
        background: ${BRAND.red};
        color: ${BRAND.white};
      }

      .nia-send-btn {
        background: ${BRAND.gold};
        color: ${BRAND.navy};
      }

      @media (max-width: 640px) {
        .nia-panel {
          right: 10px;
          left: 10px;
          bottom: 84px;
          width: auto;
          height: min(70vh, 560px);
        }

        .nia-fab {
          right: 16px;
          bottom: 16px;
        }
      }
    `;

    document.head.appendChild(style);
  }

  function renderFab() {
    if (document.getElementById("niaFabBtn")) return;

    const btn = document.createElement("button");
    btn.id = "niaFabBtn";
    btn.className = "nia-fab";
    btn.type = "button";
    btn.title = "Nia — Your UNGANI Business Assistant";
    btn.innerHTML = '<span class="nia-avatar-graphic nia-fab-avatar">' + NIA_AVATAR_IMG + '</span>' + (hasSeenNia() ? "" : '<span class="nia-fab-dot"></span>');
    btn.addEventListener("click", toggleNia);
    document.body.appendChild(btn);

    const tagline = document.createElement("button");
    tagline.id = "niaTagline";
    tagline.className = "nia-tagline";
    tagline.type = "button";
    tagline.textContent = "Ask Nia anything!";
    tagline.addEventListener("click", toggleNia);
    document.body.appendChild(tagline);

    const panel = document.createElement("div");
    panel.id = "niaPanel";
    panel.className = "nia-panel";
    document.body.appendChild(panel);
  }

  function hasSeenNia() {
    try {
      return localStorage.getItem(SEEN_KEY) === "1";
    } catch (error) {
      return false;
    }
  }

  function markSeenNia() {
    try {
      localStorage.setItem(SEEN_KEY, "1");
    } catch (error) {
      // Ignore storage failures (private browsing, quota, etc.)
    }
  }

  function toggleNia() {
    if (state.open) {
      closeNia();
    } else {
      openNia();
    }
  }

  function openNia() {
    const panel = document.getElementById("niaPanel");
    if (!panel) return;

    state.open = true;
    panel.classList.add("open");
    panel.setAttribute("data-theme", isDarkMode() ? "dark" : "light");

    const dot = document.querySelector(".nia-fab-dot");
    if (dot) dot.remove();

    const tagline = document.getElementById("niaTagline");
    if (tagline) tagline.style.display = "none";

    if (!state.messages.length) {
      renderShell();

      if (!hasSeenNia()) {
        addNiaMessage(
          "Hello 👋<br>I'm <strong>Nia</strong>, your UNGANI Business Assistant.<br><br>I can help you:<br>• Navigate the system<br>• Find records<br>• Explain features<br>• Open pages<br>• Help you complete tasks<br><br>What would you like to do today?"
        );
        markSeenNia();
      } else {
        addNiaMessage(getPageConfig().greeting);
      }

      showQuickActions();
    }

    const input = document.getElementById("niaTextInput");
    if (input) setTimeout(function () { input.focus(); }, 80);
  }

  function closeNia() {
    const panel = document.getElementById("niaPanel");
    if (panel) panel.classList.remove("open");
    state.open = false;

    const tagline = document.getElementById("niaTagline");
    if (tagline) tagline.style.display = "";
  }

  function renderShell() {
    const panel = document.getElementById("niaPanel");
    if (!panel) return;

    panel.innerHTML = `
      <div class="nia-panel-head">
        <div class="nia-title">
          <div class="nia-avatar nia-avatar-graphic" id="niaHeaderAvatar">${NIA_AVATAR_IMG}</div>
          <div>
            <strong>Nia</strong>
            <span>Your UNGANI Business Assistant</span>
          </div>
        </div>
        <button type="button" class="nia-panel-close" id="niaCloseBtn" aria-label="Close">✕</button>
      </div>
      <div class="nia-messages" id="niaMessages"></div>
      <div class="nia-quick-actions" id="niaQuickActions"></div>
      <div class="nia-input-row">
        <button type="button" class="nia-round-btn nia-mic-btn" id="niaMicBtn" title="Speak to Nia">🎤</button>
        <input type="text" class="nia-text-input" id="niaTextInput" placeholder="Ask Nia anything..." autocomplete="off" />
        <button type="button" class="nia-round-btn nia-send-btn" id="niaSendBtn" title="Send">➤</button>
      </div>
    `;

    document.getElementById("niaCloseBtn").addEventListener("click", closeNia);
    document.getElementById("niaSendBtn").addEventListener("click", handleSendClick);
    document.getElementById("niaMicBtn").addEventListener("click", handleMicClick);

    const input = document.getElementById("niaTextInput");
    input.addEventListener("keydown", function (event) {
      if (event.key === "Enter") {
        event.preventDefault();
        handleSendClick();
      }
    });

    if (!isVoiceSupported()) {
      document.getElementById("niaMicBtn").style.display = "none";
    }
  }

  function scrollMessagesToBottom() {
    const box = document.getElementById("niaMessages");
    if (box) box.scrollTop = box.scrollHeight;
  }

  function addUserMessage(text) {
    const box = document.getElementById("niaMessages");
    if (!box) return;

    const bubble = document.createElement("div");
    bubble.className = "nia-bubble user";
    bubble.textContent = text;
    box.appendChild(bubble);
    scrollMessagesToBottom();
  }

  function addNiaMessage(html) {
    const box = document.getElementById("niaMessages");
    if (!box) return;

    const bubble = document.createElement("div");
    bubble.className = "nia-bubble nia";
    bubble.innerHTML = "<p>" + html + "</p>";
    box.appendChild(bubble);
    scrollMessagesToBottom();

    state.lastReplyText = bubble.textContent || "";
  }

  function showTypingIndicator() {
    const box = document.getElementById("niaMessages");
    if (!box) return null;

    const headerAvatar = document.getElementById("niaHeaderAvatar");
    if (headerAvatar) headerAvatar.classList.add("nia-avatar-thinking");

    const el = document.createElement("div");
    el.className = "nia-typing";
    el.id = "niaTypingIndicator";
    el.innerHTML = "<span></span><span></span><span></span>";
    box.appendChild(el);
    scrollMessagesToBottom();
    return el;
  }

  function removeTypingIndicator() {
    const el = document.getElementById("niaTypingIndicator");
    if (el) el.remove();

    const headerAvatar = document.getElementById("niaHeaderAvatar");
    if (headerAvatar) headerAvatar.classList.remove("nia-avatar-thinking");
  }

  function replyWithDelay(fn) {
    showTypingIndicator();
    setTimeout(function () {
      removeTypingIndicator();
      fn();
    }, 320);
  }

  function showQuickActions() {
    const wrap = document.getElementById("niaQuickActions");
    if (!wrap) return;

    const chips = getPageConfig().chips;

    wrap.innerHTML = chips.map(function (item, index) {
      return `<button type="button" class="nia-chip" data-suggest-index="${index}">${safe(item.label)}</button>`;
    }).join("");

    Array.from(wrap.querySelectorAll(".nia-chip")).forEach(function (chip) {
      chip.addEventListener("click", function () {
        const item = chips[Number(chip.getAttribute("data-suggest-index"))];
        handleQuickSuggestion(item);
      });
    });
  }

  function handleQuickSuggestion(item) {
    if (item.type === "help") {
      addUserMessage(item.label);
      replyWithDelay(function () { showHelpMenu(); });
      return;
    }

    if (item.type === "create") {
      const action = CREATE_ACTIONS_BY_KEY[item.actionKey];
      if (!action) { addUserMessage(item.label); replyWithDelay(showFallback); return; }
      addUserMessage(item.label);
      replyWithDelay(function () {
        addNiaMessage(safe(action.confirm));
        navigateWithParams(action.href, action.params);
      });
      return;
    }

    if (item.type === "insights") {
      addUserMessage(item.label);
      replyWithDelay(function () {
        if (typeof window.openInsightsModal === "function") {
          addNiaMessage("Opening Insights & Tools for you.");
          window.openInsightsModal();
        } else {
          addNiaMessage("This page doesn't have an Insights & Tools panel yet.");
        }
      });
      return;
    }

    if (item.type === "search-prompt") {
      addUserMessage(item.label);
      replyWithDelay(function () {
        addNiaMessage("Sure — what would you like me to find? Type a name or keyword below.");
        const input = document.getElementById("niaTextInput");
        if (input) {
          input.value = "find ";
          input.focus();
          input.setSelectionRange(input.value.length, input.value.length);
        }
      });
      return;
    }

    if (item.type === "howto") {
      const topic = HOW_TO_TOPICS.find(function (entry) { return entry.key === item.key; });
      addUserMessage(item.label);
      replyWithDelay(function () {
        if (topic) answerHowTo(topic); else showFallback();
      });
      return;
    }

    if (item.type === "call") {
      addUserMessage(item.label);
      replyWithDelay(function () {
        if (typeof window[item.fnName] === "function") {
          addNiaMessage(safe(item.confirm || "Done."));
          window[item.fnName]();
        } else {
          addNiaMessage("That's not available on this page right now.");
        }
      });
      return;
    }

    addUserMessage("Open " + item.label);
    replyWithDelay(function () { navigateTo(item.key); });
  }

  function showHelpMenu() {
    const lines = HELP_TOPICS.map(function (topic) {
      return "• " + safe(topic.question);
    }).join("<br>");

    addNiaMessage("Here are common questions I can help with:<br><br>" + lines + "<br><br>Type your question, or tap Contact Support if you'd like a person.");
  }

  function showOverview() {
    const lines = OVERVIEW_SECTIONS.map(function (section) {
      const navItem = NAV_BY_KEY[section.key];
      if (!navItem) return "";

      return `<div style="margin-top:7px;">${safe(navItem.icon)} <strong>${safe(navItem.label)}</strong> — ${safe(section.blurb)} ` +
        `<a href="${attr(navItem.href)}" style="color:${BRAND.gold};font-weight:800;text-decoration:none;">Open →</a></div>`;
    }).join("");

    addNiaMessage("Here's a quick overview of UNGANI OS:" + lines);
  }

  function isVoiceSupported() {
    return !!(window.SpeechRecognition || window.webkitSpeechRecognition);
  }

  function handleMicClick() {
    if (!isVoiceSupported()) return;

    const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    const micBtn = document.getElementById("niaMicBtn");

    if (state.listening) {
      if (state.recognizer) state.recognizer.stop();
      return;
    }

    const recognizer = new Recognition();
    recognizer.lang = "en-US";
    recognizer.interimResults = false;
    recognizer.maxAlternatives = 1;

    state.recognizer = recognizer;
    state.listening = true;
    micBtn.classList.add("listening");

    recognizer.onresult = function (event) {
      const transcript = event.results[0][0].transcript;
      const input = document.getElementById("niaTextInput");
      if (input) input.value = transcript;
      submitMessage(transcript, true);
    };

    recognizer.onerror = function () {
      state.listening = false;
      micBtn.classList.remove("listening");
    };

    recognizer.onend = function () {
      state.listening = false;
      micBtn.classList.remove("listening");
    };

    try {
      recognizer.start();
    } catch (error) {
      state.listening = false;
      micBtn.classList.remove("listening");
    }
  }

  // Web Speech API voices have no gender field, so matching is by name —
  // these substrings cover the common female voices shipped by Apple
  // (Samantha, Moira, Tessa, Karen...), Microsoft (Zira, Jenny, Aria...),
  // and Google/Android TTS ("Google ... Female", explicit "female" labels).
  const FEMALE_VOICE_HINTS = [
    "female", "samantha", "victoria", "karen", "moira", "tessa", "fiona", "kate",
    "serena", "susan", "zira", "hazel", "aria", "jenny", "michelle", "ana", "linda",
    "heera", "catherine", "kathy", "nicky", "martha", "allison", "ava", "emma",
    "joanna", "kimberly", "salli", "kendra", "amelia", "libby", "olivia", "flo", "grandma", "sandy", "shelley", "reed", "eddy"
  ];

  let cachedVoices = [];

  function loadVoicesOnce() {
    if (!window.speechSynthesis) return;

    const existing = window.speechSynthesis.getVoices();
    if (existing.length) cachedVoices = existing;

    window.speechSynthesis.onvoiceschanged = function () {
      cachedVoices = window.speechSynthesis.getVoices();
    };
  }

  function pickVoice(langPrefix) {
    const voices = cachedVoices.length ? cachedVoices : (window.speechSynthesis ? window.speechSynthesis.getVoices() : []);
    if (!voices.length) return null;

    const matchesLang = function (voice) {
      return voice.lang && voice.lang.toLowerCase().indexOf(langPrefix) === 0;
    };

    const isFemaleNamed = function (voice) {
      const name = voice.name.toLowerCase();
      return FEMALE_VOICE_HINTS.some(function (hint) { return name.indexOf(hint) !== -1; });
    };

    const inLang = voices.filter(matchesLang);
    const femaleInLang = inLang.filter(isFemaleNamed);

    if (femaleInLang.length) return femaleInLang[0];
    if (inLang.length) return inLang[0];

    return null;
  }

  function speakReply(text) {
    if (!window.speechSynthesis || !text) return;

    try {
      const langPrefix = state.preferredLanguage === "sw" ? "sw" : "en";
      let voice = pickVoice(langPrefix);

      // Swahili voices are rare outside Android/Google TTS — fall back to a
      // female English voice rather than staying silent or using a male one.
      if (!voice && langPrefix !== "en") voice = pickVoice("en");

      const utterance = new SpeechSynthesisUtterance(text);
      utterance.rate = 1.02;

      if (voice) {
        utterance.voice = voice;
        utterance.lang = voice.lang;
      }

      window.speechSynthesis.cancel();
      window.speechSynthesis.speak(utterance);
    } catch (error) {
      // Voice playback is optional; fail silently.
    }
  }

  function handleSendClick() {
    const input = document.getElementById("niaTextInput");
    if (!input) return;

    const text = input.value.trim();
    if (!text) return;

    input.value = "";
    submitMessage(text, false);
  }

  function submitMessage(text, isVoiceInput) {
    addUserMessage(text);

    replyWithDelay(function () {
      const outcome = interpretMessage(text);

      if (isVoiceInput && outcome && outcome.spoken) {
        speakReply(outcome.spoken);
      }
    });
  }

  function findNavMatch(text) {
    const lower = text.toLowerCase();

    for (const item of NAV_ITEMS) {
      if (lower.indexOf(item.label.toLowerCase()) !== -1) return item;

      for (const alias of item.aliases) {
        if (lower.indexOf(alias) !== -1) return item;
      }
    }

    return null;
  }

  function findHelpTopic(text) {
    const lower = text.toLowerCase();

    for (const topic of HELP_TOPICS) {
      for (const phrase of topic.match) {
        if (lower.indexOf(phrase) !== -1) return topic;
      }
    }

    return null;
  }

  function findHowTo(text) {
    const lower = text.toLowerCase();

    for (const topic of HOW_TO_TOPICS) {
      for (const phrase of topic.match) {
        if (lower.indexOf(phrase) !== -1) return topic;
      }
    }

    return null;
  }

  function findCreateAction(text) {
    const lower = text.toLowerCase();

    for (const action of CREATE_ACTIONS) {
      for (const phrase of action.match) {
        if (lower.indexOf(phrase) !== -1) return action;
      }
    }

    return null;
  }

  function isGreeting(text) {
    const lower = text.trim().toLowerCase();
    return ["hi", "hello", "hey", "hiya", "howdy", "good morning", "good afternoon", "good evening"].indexOf(lower) !== -1;
  }

  function isSearchPhrase(text) {
    return /^(find|search|search for|look up|where is|where's)\b/i.test(text.trim());
  }

  function interpretMessage(text) {
    try {
      if (isGreeting(text)) {
        addNiaMessage("Hi there! What would you like to do — navigate somewhere, find a record, or get help with a task?");
        showQuickActions();
        return { spoken: "Hi there! What would you like to do?" };
      }

      const createAction = findCreateAction(text);
      if (createAction) {
        addNiaMessage(safe(createAction.confirm));
        navigateWithParams(createAction.href, createAction.params);
        return { spoken: createAction.confirm };
      }

      if (isSearchPhrase(text)) {
        return runSearchIntent(text.replace(/^(find|search for|search|look up|where is|where's)\b/i, "").trim());
      }

      const howTo = findHowTo(text);
      if (howTo) {
        return answerHowTo(howTo);
      }

      const helpTopic = findHelpTopic(text);
      if (helpTopic) {
        return answerHelpTopic(helpTopic);
      }

      const navMatch = findNavMatch(text);
      if (navMatch) {
        return navigateTo(navMatch.key);
      }

      return showFallback();
    } catch (error) {
      return showFallback();
    }
  }

  function answerHowTo(topic) {
    const onThisPage = state.pageKey && state.pageKey === topic.pageKey;
    const stepsHtml = "<ol>" + topic.steps.map(function (step) { return "<li>" + safe(step) + "</li>"; }).join("") + "</ol>";

    if (onThisPage) {
      addNiaMessage("You're already on the right page for this. Here's how:" + stepsHtml);
    } else {
      const navItem = NAV_BY_KEY[topic.pageKey];
      const linkHtml = navItem ? `<a class="nia-link-btn" href="${attr(navItem.href)}">Open ${safe(navItem.label)}</a>` : "";
      addNiaMessage("Here's how:" + stepsHtml + linkHtml);
    }

    return { spoken: "Here's how to do that. I've listed the steps for you." };
  }

  function answerHelpTopic(topic) {
    addNiaMessage(
      "<strong>" + safe(topic.question) + "</strong><br>" + safe(topic.answer) +
      `<br><a class="nia-link-btn" href="${attr(topic.href)}">${safe(topic.linkLabel)}</a>`
    );

    return { spoken: topic.answer };
  }

  function navigateTo(key) {
    const item = NAV_BY_KEY[key];

    if (!item) {
      return showFallback();
    }

    if (state.pageKey && state.pageKey === key) {
      addNiaMessage("You're already on " + safe(item.label) + ".");
      return { spoken: "You're already on this page." };
    }

    addNiaMessage("Opening " + safe(item.label) + "...");

    setTimeout(function () {
      window.location.href = item.href;
    }, 500);

    return { spoken: "Opening " + item.label };
  }

  function navigateWithParams(href, params) {
    const query = Object.keys(params || {})
      .filter(function (key) { return params[key]; })
      .map(function (key) { return encodeURIComponent(key) + "=" + encodeURIComponent(params[key]); })
      .join("&");

    const url = href + (query ? "?" + query : "");

    setTimeout(function () {
      window.location.href = url;
    }, 500);
  }

  async function runSearchIntent(query) {
    if (!query) {
      addNiaMessage("What would you like me to find? Try something like \"find John Mwangi\" or \"find invoice 202\".");
      return { spoken: "What would you like me to find?" };
    }

    if (!state.supabaseClient || !state.tenantId) {
      addNiaMessage("I'm still loading your workspace — please try that search again in a moment.");
      return { spoken: "I'm still loading your workspace." };
    }

    addNiaMessage("Searching for \"" + safe(query) + "\"...");

    const results = await runGlobalSearch(query);

    if (!results.length) {
      addNiaMessage("I couldn't find anything matching \"" + safe(query) + "\". Try a different name or keyword.");
      return { spoken: "I couldn't find anything matching that." };
    }

    const listHtml = results.slice(0, 6).map(function (item) {
      const url = item.id ? item.href + "?highlight=" + encodeURIComponent(item.id) : item.href;
      return `<div style="margin-top:6px;"><a class="nia-link-btn" style="margin-top:0;" href="${attr(url)}">${safe(item.label)}: ${safe(item.title)}</a></div>`;
    }).join("");

    addNiaMessage("I found " + results.length + " match" + (results.length === 1 ? "" : "es") + ":" + listHtml);
    return { spoken: "I found " + results.length + " matching results." };
  }

  async function runGlobalSearch(query) {
    const results = [];
    const queryLower = query.toLowerCase();

    for (const config of SEARCH_TABLES) {
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
          if (!haystack.includes(queryLower)) return;

          results.push({
            id: row.id,
            label: config.label,
            href: config.href,
            title: pickField(row, config.titleFields, config.label),
            detail: config.detailFields.map(function (field) { return pickField(row, [field], ""); }).filter(Boolean).slice(0, 3).join(" · ")
          });
        });
      } catch (error) {
        // Skip tables the current tenant can't read.
      }
    }

    return results.slice(0, 12);
  }

  function pickField(row, fields, fallback) {
    for (const field of fields) {
      if (row && row[field] !== undefined && row[field] !== null && row[field] !== "") {
        return row[field];
      }
    }
    return fallback;
  }

  function showFallback() {
    addNiaMessage(
      "I couldn't complete that request.<br>Would you like me to open the correct page or connect you with support?" +
      `<div style="margin-top:8px;display:flex;gap:8px;flex-wrap:wrap;">` +
      `<a class="nia-link-btn" style="margin-top:0;" href="#" id="niaFallbackQuick">Show me around</a>` +
      `<a class="nia-link-btn" style="margin-top:0;" href="my-support.html">Contact Support</a>` +
      `</div>`
    );

    setTimeout(function () {
      const el = document.getElementById("niaFallbackQuick");
      if (el) {
        el.addEventListener("click", function (event) {
          event.preventDefault();
          showOverview();
        });
      }
    }, 0);

    return { spoken: "I couldn't complete that request. Would you like me to open the correct page, or connect you with support?" };
  }

  function detectPageKeyFallback() {
    const file = (window.location.pathname.split("/").pop() || "client.html").toLowerCase();
    const found = NAV_ITEMS.find(function (item) { return item.href.toLowerCase() === file; });
    return found ? found.key : "";
  }

  function waitForClientShared(callback) {
    let tries = 0;

    const timer = setInterval(function () {
      tries++;

      if (window.UnganiClientShared && typeof window.UnganiClientShared.getState === "function") {
        const shared = window.UnganiClientShared.getState();

        // shared.contentEl only exists once renderShell() has replaced
        // document.body wholesale — appending the FAB any earlier means
        // that later replacement silently wipes it back out.
        if (shared && shared.tenantId && shared.contentEl) {
          clearInterval(timer);
          callback(shared);
          return;
        }
      }

      if (tries > 100) {
        clearInterval(timer);
      }
    }, 250);
  }

  async function loadPreferredLanguage() {
    if (!state.supabaseClient || !state.userId) return;

    try {
      const response = await state.supabaseClient
        .from("user_preferences")
        .select("language")
        .eq("user_id", state.userId)
        .maybeSingle();

      if (response && response.data && response.data.language) {
        state.preferredLanguage = response.data.language === "sw" ? "sw" : "en";
      }
    } catch (error) {
      // Preference is a nice-to-have for voice selection; default to English on failure.
    }
  }

  function boot() {
    injectStyles();
    loadVoicesOnce();

    state.pageKey = detectPageKeyFallback();
    state.surface = "client";

    if (window.UnganiClientShared) {
      waitForClientShared(function (shared) {
        state.supabaseClient = shared.supabaseClient;
        state.tenantId = shared.tenantId;
        state.tenant = shared.tenant;
        state.userId = shared.authUser ? shared.authUser.id : null;
        state.pageKey = shared.currentPageKey || state.pageKey;
        state.ready = true;
        renderFab();
        loadPreferredLanguage();
      });
    } else {
      renderFab();
    }
  }

  function init(config) {
    const settings = config || {};

    if (settings.supabaseClient) state.supabaseClient = settings.supabaseClient;
    if (settings.tenantId) state.tenantId = settings.tenantId;
    if (settings.tenant) state.tenant = settings.tenant;
    if (settings.userId) state.userId = settings.userId;
    if (settings.pageKey) state.pageKey = settings.pageKey;
    if (settings.surface) state.surface = settings.surface;

    state.ready = !!(state.supabaseClient && state.tenantId);
    loadPreferredLanguage();
  }

  function debugVoiceInfo() {
    const voices = cachedVoices.length ? cachedVoices : (window.speechSynthesis ? window.speechSynthesis.getVoices() : []);
    const englishVoice = pickVoice("en");
    const swahiliVoice = pickVoice("sw");

    return {
      voiceApiSupported: !!window.speechSynthesis,
      totalVoicesAvailable: voices.length,
      preferredLanguage: state.preferredLanguage,
      englishVoice: englishVoice ? { name: englishVoice.name, lang: englishVoice.lang } : null,
      swahiliVoice: swahiliVoice ? { name: swahiliVoice.name, lang: swahiliVoice.lang } : null,
      swahiliVoiceAvailableOnThisDevice: !!swahiliVoice
    };
  }

  window.NiaAssistant = {
    init: init,
    open: openNia,
    close: closeNia,
    toggle: toggleNia,
    debugVoiceInfo: debugVoiceInfo
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
