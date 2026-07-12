/**
 * ============================================================
 * UNGANI OS - Secure Session Storage
 * ============================================================
 * 
 * PURPOSE:
 * - Stores temporary session state safely
 * - NEVER stores sensitive user data
 * - Uses sessionStorage (cleared on browser close) instead of localStorage
 * - Only stores non-sensitive identifiers and UI state
 * - Implements safe defaults and error handling
 * 
 * SECURITY PRINCIPLES:
 * 1. sessionStorage only - cleared automatically on tab close
 * 2. No sensitive account data - no passwords, tokens, messages
 * 3. Only store IDs, not full objects
 * 4. Fail-safe defaults - silent failures, don't crash
 * 5. No sensitive data derivation - don't reconstruct sensitive data
 * 
 * WHAT TO STORE (Safe):
 * ✓ Last seen notification ID
 * ✓ UI state (theme, sidebar collapsed)
 * ✓ Session identifiers
 * ✓ Page visit timestamps
 * ✓ User preferences (non-sensitive)
 * 
 * WHAT NOT TO STORE (Unsafe):
 * ✗ Account status messages
 * ✗ Access level information
 * ✗ Account credentials
 * ✗ Authentication tokens
 * ✗ Personal information
 * ✗ Billing details
 * ✗ Account type/role (should be in session only)
 * 
 * USAGE:
 * 
 *   // Store UI state
 *   UnganiSessionStorage.set('notification_id', '12345');
 *   
 *   // Retrieve state
 *   const id = UnganiSessionStorage.get('notification_id');
 *   
 *   // Check if key exists
 *   if (UnganiSessionStorage.has('some_key')) { ... }
 *   
 *   // Remove item
 *   UnganiSessionStorage.remove('notification_id');
 *   
 *   // Clear all
 *   UnganiSessionStorage.clear();
 * 
 * ============================================================
 */

(function () {
  // Allowed keys that are safe to store
  // Add new keys here as needed - only safe, non-sensitive data
  const ALLOWED_KEYS = new Set([
    // Notification tracking
    'last_seen_notification_id_admin',
    'last_seen_notification_id_client',
    
    // UI state
    'theme_preference',
    'sidebar_collapsed',
    'modal_dismissed',
    
    // Session markers
    'session_start_time',
    'last_activity_time',
    
    // Navigation
    'last_visited_page',
    'breadcrumb_trail',
    
    // Preferences (non-sensitive)
    'language_preference',
    'currency_preference',
    'timezone_preference'
  ]);

  // Storage prefix to avoid collisions with other apps
  const STORAGE_PREFIX = 'ungani_session_';

  /**
   * Check if a key is allowed to be stored
   */
  function isAllowedKey(key) {
    if (!key || typeof key !== 'string') {
      return false;
    }
    return ALLOWED_KEYS.has(key);
  }

  /**
   * Get prefixed key
   */
  function getPrefixedKey(key) {
    return STORAGE_PREFIX + key;
  }

  /**
   * Store a value in sessionStorage
   * Only allows whitelisted keys
   */
  function set(key, value) {
    if (!isAllowedKey(key)) {
      console.warn(
        '[SessionStorage] Key not allowed:',
        key,
        '. Add to ALLOWED_KEYS if needed.'
      );
      return false;
    }

    try {
      const prefixedKey = getPrefixedKey(key);
      sessionStorage.setItem(prefixedKey, String(value || ''));
      return true;
    } catch (error) {
      // sessionStorage may fail if full or disabled
      console.warn('[SessionStorage] Failed to store key:', key, error.message);
      return false;
    }
  }

  /**
   * Retrieve a value from sessionStorage
   */
  function get(key) {
    if (!isAllowedKey(key)) {
      console.warn('[SessionStorage] Key not allowed:', key);
      return null;
    }

    try {
      const prefixedKey = getPrefixedKey(key);
      return sessionStorage.getItem(prefixedKey);
    } catch (error) {
      console.warn('[SessionStorage] Failed to retrieve key:', key, error.message);
      return null;
    }
  }

  /**
   * Check if a key exists
   */
  function has(key) {
    if (!isAllowedKey(key)) {
      return false;
    }

    try {
      const prefixedKey = getPrefixedKey(key);
      return sessionStorage.getItem(prefixedKey) !== null;
    } catch (error) {
      return false;
    }
  }

  /**
   * Remove a key
   */
  function remove(key) {
    if (!isAllowedKey(key)) {
      return false;
    }

    try {
      const prefixedKey = getPrefixedKey(key);
      sessionStorage.removeItem(prefixedKey);
      return true;
    } catch (error) {
      console.warn('[SessionStorage] Failed to remove key:', key, error.message);
      return false;
    }
  }

  /**
   * Clear all UNGANI session storage keys
   * Only removes prefixed keys, doesn't touch other data
   */
  function clear() {
    try {
      const keysToRemove = [];

      for (let i = 0; i < sessionStorage.length; i++) {
        const key = sessionStorage.key(i);
        if (key && key.startsWith(STORAGE_PREFIX)) {
          keysToRemove.push(key);
        }
      }

      keysToRemove.forEach(key => {
        sessionStorage.removeItem(key);
      });

      return true;
    } catch (error) {
      console.warn('[SessionStorage] Failed to clear:', error.message);
      return false;
    }
  }

  /**
   * Get all stored keys (for debugging)
   */
  function getAllKeys() {
    const keys = [];

    try {
      for (let i = 0; i < sessionStorage.length; i++) {
        const key = sessionStorage.key(i);
        if (key && key.startsWith(STORAGE_PREFIX)) {
          keys.push(key.replace(STORAGE_PREFIX, ''));
        }
      }
    } catch (error) {
      console.warn('[SessionStorage] Failed to enumerate keys:', error.message);
    }

    return keys;
  }

  /**
   * Register a new allowed key
   * Use with caution - only for safe, non-sensitive data
   */
  function registerKey(key, description) {
    if (!key || typeof key !== 'string') {
      console.warn('[SessionStorage] Invalid key:', key);
      return false;
    }

    if (ALLOWED_KEYS.has(key)) {
      return false; // Already exists
    }

    ALLOWED_KEYS.add(key);
    
    if (typeof window !== 'undefined' && window.location.hostname === 'localhost') {
      console.log('[SessionStorage] Registered key:', key, description || '');
    }

    return true;
  }

  /**
   * Public API
   */
  const API = {
    set,
    get,
    has,
    remove,
    clear,
    getAllKeys,
    registerKey
  };

  // Expose globally
  window.UnganiSessionStorage = API;

  // Log in development
  if (typeof window !== 'undefined' && window.location.hostname === 'localhost') {
    console.log('[UnganiSessionStorage] Initialized with', ALLOWED_KEYS.size, 'allowed keys');
  }

})();
