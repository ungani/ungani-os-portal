(function () {
  const SUPABASE_URL = "https://ctmtjwklltnsmfdtvqhl.supabase.co";
  const SUPABASE_KEY = "sb_publishable_jkZaWWep-cObTEv_F_kN6g_Ic85BxD9";

  const pageSectionMap = {
    "client.html": "dashboard",
    "my-money.html": "money",
    "my-tasks.html": "tasks",
    "my-items.html": "items",
    "my-people.html": "people",
    "my-records.html": "records",
    "my-documents.html": "documents",
    "my-calendar.html": "calendar",
    "my-support.html": "support",
    "my-chat.html": "support",
    "my-team-chat.html": "support",
    "my-reports.html": "reports",
    "reports.html": "reports",
    "my-billing.html": "billing",
    "my-invoice.html": "billing",
    "my-package.html": "package",
    "my-branches.html": "branches",
    "my-settings.html": "settings",
    "my-team-access.html": "settings",
    "client-notifications.html": "notifications",
    "my-tools.html": "tools",
    "my-onboarding.html": "tools",
    "my-account-status.html": "tools"
  };

  const exemptPages = [
    "login.html",
    "index.html",
    "staff-login.html"
  ];

  // Previously fired via runSoon() registered three times (immediately,
  // on DOMContentLoaded, and on window.load), each scheduling two more
  // setTimeouts (20ms/300ms) - up to 6 concurrent invocations of this
  // guard per page load, each creating its OWN Supabase client. Multiple
  // GoTrueClient instances racing against the same session is exactly the
  // kind of thing that produces intermittent "got logged out" symptoms -
  // collapsed to the same single-invocation pattern the other guards use.
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", runStaffPermissionGuard);
  } else {
    runStaffPermissionGuard();
  }

  async function runStaffPermissionGuard() {
    try {
      const page = getCurrentPage();

      if (exemptPages.includes(page)) return;

      const sectionKey = pageSectionMap[page];

      if (!sectionKey) return;

      if (!window.supabase) return;

      const supabaseClient = window.getUnganiSupabaseClient ? window.getUnganiSupabaseClient() : window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
      if (!supabaseClient) return;

      const userResponse = await supabaseClient.auth.getUser();
      const user = userResponse && userResponse.data ? userResponse.data.user : null;

      if (!user) return;

      const response = await supabaseClient.rpc("get_my_ungani_staff_access");

      if (response.error) {
        console.warn("Staff permission guard:", response.error.message);
        return;
      }

      const access = response.data || {};

      if (access.is_owner === true) return;

      // get_my_ungani_staff_access was originally only ever called from
      // staff-login.html, where every caller already has a team_members
      // row. Now that this guard runs unconditionally for every client
      // session (closing the ?mode=client bypass), a genuine owner who
      // never went through Team Access has no team_members row at all -
      // the RPC returns data: null (or an object with neither is_owner
      // nor role_key set), which must NOT be treated as "not owner, so
      // restrict." Only restrict when there's positive evidence this is
      // a real, provisioned staff record (a real role_key), matching the
      // same check staff-login.html already uses to decide "not listed
      // as active staff."
      const roleKey = String(access.role_key || "").toLowerCase();
      const isConfirmedStaffRecord = roleKey !== "" && roleKey !== "guest";

      if (!isConfirmedStaffRecord) return;

      const permissions = access.permissions || {};
      const sectionPermission = permissions[sectionKey] || {};

      if (sectionPermission.view === true) return;

      blockPage(sectionKey);
    } catch (error) {
      console.warn("Staff permission guard:", error.message);
    }
  }

  function getCurrentPage() {
    const path = window.location.pathname || "";
    const page = path.split("/").pop() || "client.html";
    return page.toLowerCase();
  }

  function blockPage(sectionKey) {
    document.body.innerHTML = `
      <div style="
        min-height:100vh;
        display:flex;
        align-items:center;
        justify-content:center;
        padding:24px;
        background:
          radial-gradient(circle at top right, rgba(212,166,58,0.18), transparent 32%),
          linear-gradient(135deg, #061C3D 0%, #092B58 55%, #0F172A 100%);
        font-family:Inter, Arial, sans-serif;
        color:white;
      ">
        <div style="
          width:min(620px, 100%);
          background:rgba(255,255,255,0.10);
          border:1px solid rgba(255,255,255,0.16);
          border-radius:28px;
          padding:28px;
          box-shadow:0 30px 90px rgba(0,0,0,0.35);
        ">
          <div style="
            width:62px;
            height:62px;
            border-radius:20px;
            background:rgba(212,166,58,0.18);
            display:flex;
            align-items:center;
            justify-content:center;
            font-size:30px;
            margin-bottom:16px;
          ">🔐</div>

          <h1 style="margin:0;font-size:34px;letter-spacing:-0.05em;">Staff Access Restricted</h1>

          <p style="color:rgba(255,255,255,0.72);line-height:1.55;margin:12px 0 0;">
            This section is not assigned to your staff account.
            Please ask the business owner to update your access if you need this section.
          </p>

          <p style="color:#FFE8A3;font-weight:900;margin:16px 0 0;">
            Restricted section: ${escapeHtml(sectionKey)}
          </p>

          <div style="display:flex;flex-wrap:wrap;gap:10px;margin-top:22px;">
            <a href="client.html?mode=staff" style="
              display:inline-flex;
              align-items:center;
              justify-content:center;
              border-radius:999px;
              padding:12px 16px;
              background:#D4A63A;
              color:#061C3D;
              text-decoration:none;
              font-weight:950;
            ">Back to Staff Dashboard</a>

            <a href="staff-login.html" style="
              display:inline-flex;
              align-items:center;
              justify-content:center;
              border-radius:999px;
              padding:12px 16px;
              background:rgba(255,255,255,0.12);
              color:white;
              border:1px solid rgba(255,255,255,0.16);
              text-decoration:none;
              font-weight:950;
            ">Staff Login</a>
          </div>
        </div>
      </div>
    `;
  }

  function escapeHtml(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }
})();
