/**
 * ============================================================
 * UNGANI OS - Centralized Supabase Configuration
 * ============================================================
 * 
 * Purpose:
 * - Single source of truth for Supabase connection settings
 * - Supports environment-based configuration
 * - Fallback to hardcoded values for development
 * - Easy credential rotation by updating this file only
 * 
 * Usage:
 * Import in any page/script:
 *   <script src="config/supabase-config.js"></script>
 *   
 * Then use:
 *   window.UnganiSupabase.getClient()  // Get or create Supabase client
 *   window.UnganiSupabase.getURL()     // Get Supabase URL
 *   window.UnganiSupabase.getKey()     // Get Supabase anon key
 * 
 * TODO (SECURITY):
 * - Move to environment variables: process.env.SUPABASE_URL
 * - Create backend proxy API for client calls
 * - Enable Row Level Security on all tables
 * - Never expose service role key on client
 * ============================================================
 */

(function () {
  // Configuration sources (in priority order)
  const CONFIG = {
    // Priority 1: Environment variables (from build process)
    // These should be injected at build time by your CI/CD
    env: {
      url: typeof window !== 'undefined' && window.__UNGANI_ENV__ 
        ? window.__UNGANI_ENV__.SUPABASE_URL 
        : null,
      key: typeof window !== 'undefined' && window.__UNGANI_ENV__ 
        ? window.__UNGANI_ENV__.SUPABASE_KEY 
        : null
    },

    // Priority 2: Development fallback
    // IMPORTANT: These should be rotated immediately.
    // Use environment variables in production instead.
    development: {
      url: "https://ctmtjwklltnsmfdtvqhl.supabase.co",
      key: "sb_publishable_jkZaWWep-cObTEv_F_kN6g_Ic85BxD9"
    }
  };

  let supabaseClient = null;

  /**
   * Get the Supabase configuration
   * Tries environment variables first, falls back to development
   */
  function getConfig() {
    if (CONFIG.env.url && CONFIG.env.key) {
      return {
        url: CONFIG.env.url,
        key: CONFIG.env.key,
        source: 'environment'
      };
    }

    return {
      url: CONFIG.development.url,
      key: CONFIG.development.key,
      source: 'development'
    };
  }

  /**
   * Get Supabase URL
   */
  function getURL() {
    return getConfig().url;
  }

  /**
   * Get Supabase anon key
   */
  function getKey() {
    return getConfig().key;
  }

  /**
   * Get or create Supabase client
   * Uses window.supabase.createClient() if available
   * Returns null if supabase.js library not loaded
   */
  function getClient() {
    if (supabaseClient) {
      return supabaseClient;
    }

    if (typeof window === 'undefined' || !window.supabase || !window.supabase.createClient) {
      console.warn('Supabase client library not loaded. Include <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js"></script>');
      return null;
    }

    const config = getConfig();
    supabaseClient = window.supabase.createClient(config.url, config.key);
    
    return supabaseClient;
  }

  /**
   * Check if configuration is loaded from environment or fallback
   */
  function isUsingEnvironmentConfig() {
    return getConfig().source === 'environment';
  }

  /**
   * Clear the cached client (useful for testing or credential rotation)
   */
  function clearClient() {
    supabaseClient = null;
  }

  // Expose API globally
  window.UnganiSupabase = {
    getClient,
    getURL,
    getKey,
    getConfig,
    isUsingEnvironmentConfig,
    clearClient
  };

  // Log configuration source in development
  if (typeof window !== 'undefined' && window.location.hostname === 'localhost') {
    const configSource = getConfig();
    console.log(
      '[UnganiSupabase] Configuration source:',
      configSource.source,
      '| URL:', configSource.url
    );
  }
})();
