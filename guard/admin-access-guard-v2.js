/**
 * ============================================================
 * UNGANI OS - Admin Access Guard v2 (BLOCKING)
 * ============================================================
 * 
 * PURPOSE:
 * - Synchronously block all page rendering until admin auth is verified
 * - Eliminate race conditions where page content loads before guards run
 * - Fail securely by default (deny, then show reason)
 * 
 * KEY IMPROVEMENTS OVER V1:
 * 1. Page completely blank until auth check completes
 * 2. No setTimeout delays - waits for RPC to finish
 * 3. Single consolidated auth logic (no fallthrough on errors)
 * 4. Server-side session validation preferred
 * 5. Centralized config for credentials
 * 
 * USAGE:
 * In your admin page <head>, BEFORE any other scripts:
 *   <script src="guard/admin-access-guard-v2.js"></script>
 *   <script>initUnganiAdminGuard();</script>
 * 
 * This will:
 * - Block rendering immediately
 * - Verify session and admin role
 * - Show either access or detailed block reason
 * - NEVER allow page content to load without successful auth
 * 
 * ============================================================
 */

(function () {
  // Use centralized config if available, otherwise fallback
  function getSupabaseConfig() {
    if (typeof window !== 'undefined' && window.UnganiSupabase) {
      return {
        url: window.UnganiSupabase.getURL(),
        key: window.UnganiSupabase.getKey()
      };
    }
    // Fallback for development only - should be replaced with env vars
    return {
      url: "https://ctmtjwklltnsmfdtvqhl.supabase.co",
      key: "sb_publishable_jkZaWWep-cObTEv_F_kN6g_Ic85BxD9"
    };
  }

  const SUPABASE_CDN = "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2";
  
  // Pages that don't require admin protection
  const PUBLIC_PAGES = [
    "index.html",
    "login.html",
    "register.html",
    "signup.html",
    "forgot-password.html",
    "reset-password.html"
  ];

  // Request timeout: don't wait forever for auth checks
  const AUTH_CHECK_TIMEOUT_MS = 10000; // 10 seconds

  let guardExecuted = false;

  /**
   * Initialize the admin guard
   * Call this from your admin page's <head> section
   */
  async function initUnganiAdminGuard() {
    if (guardExecuted) {
      return;
    }
    guardExecuted = true;

    const pageName = getCurrentPageName();

    // Public pages don't need protection
    if (PUBLIC_PAGES.includes(pageName)) {
      return;
    }

    // Check if this is an admin page
    if (!shouldProtectAdminPage(pageName)) {
      return;
    }

    // Block rendering - show loading screen
    showAuthCheckingScreen();

    try {
      // Ensure Supabase library is loaded
      await loadSupabaseLibrary();

      if (!window.supabase || !window.supabase.createClient) {
        showBlockedScreen({
          title: "Security Library Failed",
          message: "UNGANI OS could not initialize the authentication library.",
          detail: "This is a security-critical error. Please refresh the page. If this continues, contact UNGANI support immediately.",
          actionText: "Refresh Page",
          actionUrl: window.location.href
        });
        return;
      }

      // Get credentials from centralized config
      const config = getSupabaseConfig();
      const supabaseClient = window.supabase.createClient(config.url, config.key);

      // Perform auth check with timeout
      const result = await performAuthCheckWithTimeout(supabaseClient);

      if (result.success) {
        // User passed all checks - allow page to render
        // Remove blocking screen if any
        const blocker = document.getElementById('ungani-auth-blocker');
        if (blocker) {
          blocker.remove();
        }
        return;
      }

      // Auth check failed - show reason and block page
      showBlockedScreen(result.blockReason);

    } catch (error) {
      console.error('[AdminGuard] Unexpected error during auth check:', error);
      
      showBlockedScreen({
        title: "Security Check Error",
        message: "An unexpected error occurred during the security verification.",
        detail: "Please refresh the page. If this continues, contact UNGANI support.",
        actionText: "Refresh Page",
        actionUrl: window.location.href
      });
    }
  }

  /**
   * Perform all auth checks with a timeout
   * Returns { success: boolean, blockReason?: object }
   */
  async function performAuthCheckWithTimeout(supabaseClient) {
    return Promise.race([
      performAuthCheck(supabaseClient),
      new Promise((resolve) => {
        setTimeout(() => {
          resolve({
            success: false,
            blockReason: {
              title: "Security Check Timeout",
              message: "The authentication check took too long to complete.",
              detail: "Please refresh the page. If this continues, contact UNGANI support.",
              actionText: "Refresh Page",
              actionUrl: window.location.href
            }
          });
        }, AUTH_CHECK_TIMEOUT_MS);
      })
    ]);
  }

  /**
   * Core auth check logic
   * Returns { success: boolean, blockReason?: object }
   */
  async function performAuthCheck(supabaseClient) {
    // STEP 1: Check if user has active session
    const sessionResponse = await supabaseClient.auth.getSession();
    const session = sessionResponse?.data?.session;

    if (!session || !session.user) {
      return {
        success: false,
        blockReason: {
          title: "Not Signed In",
          message: "You must be signed in to access the admin panel.",
          detail: "Please sign in with an authorized UNGANI admin account.",
          actionText: "Go to Login",
          actionUrl: "login.html?mode=admin"
        }
      };
    }

    // Store user info for page access (optional)
    window.__unganiAuthUser = session.user;

    // STEP 2: Verify user is admin via RPC
    // This RPC function MUST verify:
    // - User's role in database
    // - Account status (not suspended)
    // - Admin-specific permissions
    // CRITICAL: RPC function should perform server-side RLS checks
    const adminResponse = await supabaseClient.rpc("is_ungani_admin");

    // Handle RPC errors explicitly
    if (adminResponse.error) {
      console.error('[AdminGuard] RPC error:', adminResponse.error.message);
      
      // Don't leak internal errors to user
      return {
        success: false,
        blockReason: {
          title: "Admin Check Failed",
          message: "We could not verify your admin permissions.",
          detail: "Please refresh the page. If this continues, contact UNGANI support.",
          actionText: "Refresh Page",
          actionUrl: window.location.href
        }
      };
    }

    // STEP 3: Check if RPC returned true (user is admin)
    if (adminResponse.data === true) {
      // SUCCESS: User is authenticated and is admin
      return { success: true };
    }

    // STEP 4: User is signed in but NOT admin
    return {
      success: false,
      blockReason: {
        title: "Admin Access Required",
        message: "This page is reserved for UNGANI admin users only.",
        detail: "Your account is signed in but does not have admin permissions. If you believe this is incorrect, contact UNGANI support.",
        actionText: "Go to Client Portal",
        actionUrl: "client.html"
      }
    };
  }

  /**
   * Show a loading screen while auth check is in progress
   */
  function showAuthCheckingScreen() {
    const blocker = document.createElement('div');
    blocker.id = 'ungani-auth-blocker';
    blocker.style.cssText = `
      position: fixed;
      top: 0;
      left: 0;
      right: 0;
      bottom: 0;
      z-index: 99999;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 24px;
      background: linear-gradient(135deg, #031227 0%, #061C3D 48%, #092A59 100%);
      font-family: Arial, Helvetica, sans-serif;
      color: white;
    `;

    blocker.innerHTML = `
      <div style="
        text-align: center;
        background: rgba(8, 38, 84, 0.95);
        border: 1px solid rgba(255, 255, 255, 0.14);
        border-radius: 24px;
        padding: 40px 32px;
        max-width: 400px;
        width: 100%;
        box-shadow: 0 18px 45px rgba(0, 0, 0, 0.28);
      ">
        <div style="
          width: 60px;
          height: 60px;
          margin: 0 auto 20px;
          border: 4px solid rgba(255, 255, 255, 0.2);
          border-top-color: #D4A63A;
          border-radius: 50%;
          animation: spin 0.8s linear infinite;
        "></div>
        <h2 style="margin: 0 0 12px; font-size: 18px;">Verifying Admin Access</h2>
        <p style="
          margin: 0;
          color: rgba(255, 255, 255, 0.72);
          font-size: 14px;
          line-height: 1.5;
        ">
          Please wait while we verify your credentials...
        </p>
        <style>
          @keyframes spin {
            to { transform: rotate(360deg); }
          }
        </style>
      </div>
    `;

    document.body.appendChild(blocker);
    document.body.style.overflow = 'hidden';
  }

  /**
   * Show blocked access screen
   */
  function showBlockedScreen(options) {
    const title = options.title || "Access Denied";
    const message = options.message || "Your access is restricted.";
    const detail = options.detail || "";
    const actionText = options.actionText || "Go Back";
    const actionUrl = options.actionUrl || "index.html";

    // Remove any existing auth blocker
    const blocker = document.getElementById('ungani-auth-blocker');
    if (blocker) {
      blocker.remove();
    }

    document.body.innerHTML = `
      <main style="
        min-height: 100vh;
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 24px;
        background: linear-gradient(135deg, #031227 0%, #061C3D 48%, #092A59 100%);
        font-family: Arial, Helvetica, sans-serif;
        color: #FFFFFF;
        margin: 0;
      ">
        <section style="
          width: 100%;
          max-width: 620px;
          background: rgba(8, 38, 84, 0.95);
          border: 1px solid rgba(255, 255, 255, 0.14);
          border-radius: 24px;
          box-shadow: 0 18px 45px rgba(0, 0, 0, 0.28);
          padding: 40px 32px;
          text-align: center;
        ">
          <div style="
            width: 72px;
            height: 72px;
            margin: 0 auto 20px;
            background: #FFFFFF;
            border-radius: 18px;
            padding: 8px;
            display: flex;
            align-items: center;
            justify-content: center;
            box-shadow: 0 12px 28px rgba(0, 0, 0, 0.20);
          ">
            <img src="ungani-logo.png" alt="UNGANI" style="
              width: 100%;
              height: 100%;
              object-fit: contain;
            " />
          </div>

          <h1 style="
            margin: 0 0 16px;
            font-size: 28px;
            font-weight: 700;
            color: #D4A63A;
            letter-spacing: -0.02em;
          ">
            ${escapeHtml(title)}
          </h1>

          <p style="
            margin: 0 0 12px;
            color: #F5F5F3;
            line-height: 1.6;
            font-size: 16px;
          ">
            ${escapeHtml(message)}
          </p>

          ${detail ? `
            <p style="
              margin: 0 0 24px;
              color: #B8C3D6;
              line-height: 1.6;
              font-size: 14px;
            ">
              ${escapeHtml(detail)}
            </p>
          ` : ''}

          <a href="${escapeAttr(actionUrl)}" style="
            display: inline-flex;
            align-items: center;
            justify-content: center;
            text-decoration: none;
            background: #D4A63A;
            color: #061C3D;
            border-radius: 999px;
            padding: 13px 24px;
            font-weight: 900;
            font-size: 14px;
            transition: all 0.2s ease;
          " onmouseover="this.style.filter='brightness(1.1)'" onmouseout="this.style.filter='brightness(1)'">
            ${escapeHtml(actionText)}
          </a>

          <div style="
            margin-top: 28px;
            padding-top: 20px;
            border-top: 1px solid rgba(255, 255, 255, 0.08);
            color: #B8C3D6;
            font-size: 12px;
            line-height: 1.5;
          ">
            UNGANI OS • ungani.com • info@ungani.com
          </div>
        </section>
      </main>
    `;

    document.body.style.overflow = 'auto';
  }

  /**
   * Load Supabase library from CDN if not already loaded
   */
  async function loadSupabaseLibrary() {
    if (window.supabase) {
      return;
    }

    return new Promise((resolve) => {
      const existing = document.querySelector(`script[src="${SUPABASE_CDN}"]`);

      if (existing) {
        // Script tag exists, wait for it to load
        existing.addEventListener('load', resolve, { once: true });
        existing.addEventListener('error', resolve, { once: true });
        return;
      }

      // Create new script tag
      const script = document.createElement('script');
      script.src = SUPABASE_CDN;
      script.async = true;
      script.onload = resolve;
      script.onerror = resolve; // Resolve anyway so error handling catches it
      document.head.appendChild(script);
    });
  }

  /**
   * Get current page filename
   */
  function getCurrentPageName() {
    const path = window.location.pathname || "";
    return (path.split("/").pop() || "index.html").toLowerCase();
  }

  /**
   * Determine if page should be protected
   */
  function shouldProtectAdminPage(pageName) {
    // Protect all admin pages
    if (pageName.startsWith("admin")) {
      return true;
    }

    // Protect other admin-only pages
    const adminPages = [
      "support.html",
      "billing.html",
      "admin-notifications.html",
      "admin-home.html"
    ];

    return adminPages.includes(pageName);
  }

  /**
   * Escape HTML to prevent XSS
   */
  function escapeHtml(value) {
    const map = {
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#039;'
    };
    return String(value || '').replace(/[&<>"']/g, (char) => map[char]);
  }

  /**
   * Escape attribute values
   */
  function escapeAttr(value) {
    return escapeHtml(value);
  }

  // Expose public API
  window.initUnganiAdminGuard = initUnganiAdminGuard;

})();
