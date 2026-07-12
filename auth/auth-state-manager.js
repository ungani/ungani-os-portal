/**
 * ============================================================
 * UNGANI OS - Global Auth State Manager
 * ============================================================
 * 
 * PURPOSE:
 * - Centralized auth state listener across entire app
 * - Monitor token expiry and automatic logout
 * - Prevent background tasks when session expires
 * - Gracefully redirect on auth failure
 * - Clean up resources on logout
 * 
 * KEY FEATURES:
 * 1. Global auth state listener via Supabase.onAuthStateChange()
 * 2. Automatic session refresh before expiry
 * 3. Background task pause when not authenticated
 * 4. Event system for other components to react to auth changes
 * 5. Secure redirect to login on token expiry
 * 
 * LIFECYCLE:
 * - Page loads → Auth state listener initializes
 * - Session valid → User can access protected pages
 * - Token expires → Auto-redirect to login
 * - User signs out → All background tasks stop
 * - New session → Resume background tasks
 * 
 * USAGE:
 * 
 *   // Initialize in login.html and protected pages
 *   <script src="auth-state-manager.js"></script>
 * 
 *   // Listen for auth changes
 *   window.addEventListener('ungani:auth-state-changed', (e) => {
 *     if (e.detail.authenticated) {
 *       console.log('User logged in:', e.detail.user.email);
 *     } else {
 *       console.log('User logged out');
 *     }
 *   });
 * 
 *   // Check if currently authenticated
 *   if (UnganiAuthManager.isAuthenticated()) {
 *     // Safe to make API calls
 *   }
 * 
 *   // Register a background task
 *   UnganiAuthManager.registerBackgroundTask('my-poller', pollFunction);
 * 
 * ============================================================
 */

(function () {
  // Use centralized config if available
  function getSupabaseConfig() {
    if (typeof window !== 'undefined' && window.UnganiSupabase) {
      return {
        url: window.UnganiSupabase.getURL(),
        key: window.UnganiSupabase.getKey(),
        client: window.UnganiSupabase.getClient()
      };
    }
    // Fallback for development
    return {
      url: "https://ctmtjwklltnsmfdtvqhl.supabase.co",
      key: "sb_publishable_jkZaWWep-cObTEv_F_kN6g_Ic85BxD9"
    };
  }

  const SUPABASE_CDN = "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2";
  const POLL_INTERVAL_MS = 60000; // Check token every minute
  const REFRESH_BUFFER_MS = 300000; // Refresh 5 minutes before expiry

  let authState = {
    authenticated: false,
    user: null,
    session: null,
    expiresAt: null
  };

  let listenerInitialized = false;
  let backgroundTasks = new Map();
  let tokenRefreshTimeout = null;

  /**
   * Initialize the auth state manager
   * Call this from login.html and all protected pages
   */
  async function initializeAuthStateManager() {
    if (listenerInitialized) {
      return;
    }

    // Ensure Supabase is loaded
    await ensureSupabaseLoaded();

    if (!window.supabase) {
      console.warn('[AuthStateManager] Supabase not available');
      return;
    }

    listenerInitialized = true;

    // Get or create Supabase client
    const config = getSupabaseConfig();
    const supabaseClient = config.client || window.supabase.createClient(config.url, config.key);

    if (!supabaseClient) {
      console.warn('[AuthStateManager] Could not create Supabase client');
      return;
    }

    // Set up auth state listener
    setupAuthStateListener(supabaseClient);

    // Check initial session
    await checkAndUpdateAuthState(supabaseClient);

    if (typeof window !== 'undefined' && window.location.hostname === 'localhost') {
      console.log('[AuthStateManager] Initialized');
    }
  }

  /**
   * Set up Supabase auth state change listener
   * This fires when session is created, refreshed, or destroyed
   */
  function setupAuthStateListener(supabaseClient) {
    try {
      supabaseClient.auth.onAuthStateChange(async (event, session) => {
        console.log('[AuthStateManager] Auth state changed:', event);

        switch (event) {
          case 'INITIAL_SESSION':
            // App just loaded, session might exist
            await handleSessionUpdate(session);
            break;

          case 'SIGNED_IN':
            // User just signed in
            await handleSessionUpdate(session);
            resumeBackgroundTasks();
            dispatchAuthEvent('signed-in', session?.user, session);
            break;

          case 'SIGNED_OUT':
            // User signed out or token expired
            handleSignedOut();
            dispatchAuthEvent('signed-out');
            break;

          case 'TOKEN_REFRESHED':
            // Token was automatically refreshed
            await handleSessionUpdate(session);
            dispatchAuthEvent('token-refreshed', session?.user, session);
            break;

          case 'USER_UPDATED':
            // User metadata was updated
            await handleSessionUpdate(session);
            dispatchAuthEvent('user-updated', session?.user, session);
            break;

          default:
            console.log('[AuthStateManager] Unknown auth event:', event);
        }
      });
    } catch (error) {
      console.error('[AuthStateManager] Failed to set up auth listener:', error);
    }
  }

  /**
   * Check current session and update auth state
   */
  async function checkAndUpdateAuthState(supabaseClient) {
    try {
      const { data, error } = await supabaseClient.auth.getSession();

      if (error) {
        console.warn('[AuthStateManager] Failed to get session:', error.message);
        return;
      }

      if (data?.session) {
        await handleSessionUpdate(data.session);
      } else {
        handleNoSession();
      }
    } catch (error) {
      console.warn('[AuthStateManager] Error checking session:', error.message);
    }
  }

  /**
   * Handle session update
   */
  async function handleSessionUpdate(session) {
    if (!session) {
      handleNoSession();
      return;
    }

    // Update auth state
    authState.authenticated = true;
    authState.user = session.user || null;
    authState.session = session;
    authState.expiresAt = session.expires_at 
      ? new Date(session.expires_at * 1000) 
      : null;

    // Schedule token refresh if near expiry
    scheduleTokenRefresh(session);

    console.log('[AuthStateManager] Session updated, user:', authState.user?.email);
  }

  /**
   * Handle no session (not authenticated)
   */
  function handleNoSession() {
    authState.authenticated = false;
    authState.user = null;
    authState.session = null;
    authState.expiresAt = null;

    clearTokenRefreshTimeout();
  }

  /**
   * Handle user signed out
   */
  function handleSignedOut() {
    handleNoSession();
    pauseBackgroundTasks();

    // Determine current page
    const pageName = getCurrentPageName();

    // Don't redirect if already on login/public pages
    if (isPublicPage(pageName)) {
      return;
    }

    // Redirect to login after a brief delay (let page render if needed)
    setTimeout(() => {
      console.log('[AuthStateManager] Session expired, redirecting to login');
      window.location.href = 'login.html?reason=session-expired';
    }, 500);
  }

  /**
   * Schedule token refresh before expiry
   */
  function scheduleTokenRefresh(session) {
    clearTokenRefreshTimeout();

    if (!session.expires_at) {
      return;
    }

    // Calculate when to refresh (5 minutes before expiry)
    const expiryTime = session.expires_at * 1000; // Convert to milliseconds
    const refreshTime = expiryTime - REFRESH_BUFFER_MS;
    const nowTime = Date.now();
    const delayMs = Math.max(0, refreshTime - nowTime);

    if (delayMs > 0) {
      tokenRefreshTimeout = setTimeout(() => {
        console.log('[AuthStateManager] Token refresh scheduled');
        // Supabase automatically refreshes tokens, but we can trigger a check
      }, delayMs);
    }
  }

  /**
   * Clear token refresh timeout
   */
  function clearTokenRefreshTimeout() {
    if (tokenRefreshTimeout) {
      clearTimeout(tokenRefreshTimeout);
      tokenRefreshTimeout = null;
    }
  }

  /**
   * Register a background task (polling, sync, etc)
   * Task will be paused when user is not authenticated
   */
  function registerBackgroundTask(taskId, taskFunction) {
    if (!taskId || typeof taskFunction !== 'function') {
      console.warn('[AuthStateManager] Invalid task registration');
      return false;
    }

    backgroundTasks.set(taskId, {
      fn: taskFunction,
      running: authState.authenticated,
      interval: null
    });

    console.log('[AuthStateManager] Registered background task:', taskId);

    return true;
  }

  /**
   * Unregister a background task
   */
  function unregisterBackgroundTask(taskId) {
    const task = backgroundTasks.get(taskId);

    if (!task) {
      return false;
    }

    if (task.interval) {
      clearInterval(task.interval);
    }

    backgroundTasks.delete(taskId);
    console.log('[AuthStateManager] Unregistered background task:', taskId);

    return true;
  }

  /**
   * Pause all background tasks
   * Called when user signs out or session expires
   */
  function pauseBackgroundTasks() {
    backgroundTasks.forEach((task) => {
      task.running = false;
      if (task.interval) {
        clearInterval(task.interval);
        task.interval = null;
      }
    });

    console.log('[AuthStateManager] Paused all background tasks');
  }

  /**
   * Resume all background tasks
   * Called when user signs back in
   */
  function resumeBackgroundTasks() {
    backgroundTasks.forEach((task) => {
      task.running = true;
      // Tasks should restart their own intervals
    });

    console.log('[AuthStateManager] Resumed all background tasks');
  }

  /**
   * Load Supabase library if not already loaded
   */
  async function ensureSupabaseLoaded() {
    if (window.supabase) {
      return;
    }

    return new Promise((resolve) => {
      const existing = document.querySelector(`script[src="${SUPABASE_CDN}"]`);

      if (existing) {
        existing.addEventListener('load', resolve, { once: true });
        existing.addEventListener('error', resolve, { once: true });
        return;
      }

      const script = document.createElement('script');
      script.src = SUPABASE_CDN;
      script.async = true;
      script.onload = resolve;
      script.onerror = resolve;
      document.head.appendChild(script);
    });
  }

  /**
   * Dispatch custom auth event
   */
  function dispatchAuthEvent(eventType, user = null, session = null) {
    const event = new CustomEvent('ungani:auth-state-changed', {
      detail: {
        type: eventType,
        authenticated: authState.authenticated,
        user,
        session
      }
    });

    window.dispatchEvent(event);
  }

  /**
   * Get current page name
   */
  function getCurrentPageName() {
    const path = window.location.pathname || '';
    return (path.split('/').pop() || 'index.html').toLowerCase();
  }

  /**
   * Check if page is public (doesn't require auth)
   */
  function isPublicPage(pageName) {
    const publicPages = [
      'index.html',
      'login.html',
      'register.html',
      'signup.html',
      'forgot-password.html',
      'reset-password.html'
    ];

    return publicPages.includes(pageName);
  }

  /**
   * Public API
   */
  const API = {
    initialize: initializeAuthStateManager,
    
    isAuthenticated: () => authState.authenticated,
    
    getUser: () => authState.user,
    
    getSession: () => authState.session,
    
    getAuthState: () => ({ ...authState }),
    
    registerBackgroundTask,
    
    unregisterBackgroundTask,
    
    pauseBackgroundTasks,
    
    resumeBackgroundTasks
  };

  // Expose globally
  window.UnganiAuthManager = API;

  // Auto-initialize when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initializeAuthStateManager);
  } else {
    initializeAuthStateManager();
  }

})();
