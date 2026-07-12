/**
 * ============================================================
 * UNGANI OS - Secure Redirect Utility
 * ============================================================
 * 
 * PURPOSE:
 * - Centralized, whitelist-based redirect validation
 * - Prevent open redirect vulnerabilities
 * - Block attempts to redirect to external domains
 * - Sanitize and validate all redirect URLs
 * 
 * SECURITY FEATURES:
 * 1. Strict whitelist of allowed internal pages
 * 2. Protocol validation (http/https only, no javascript:, data:, etc)
 * 3. Domain validation (must be current domain or relative path)
 * 4. Blocks redirect chains (URL parameters with redirects)
 * 5. Rejects URLs with suspicious patterns
 * 
 * USAGE:
 * 
 *   // Validate and redirect
 *   const safeUrl = UnganiRedirectValidator.validate(userProvidedUrl);
 *   if (safeUrl) {
 *     window.location.href = safeUrl;
 *   } else {
 *     // Redirect to default safe page
 *     window.location.href = UnganiRedirectValidator.getDefaultPage();
 *   }
 * 
 *   // Check if URL is valid without redirecting
 *   if (UnganiRedirectValidator.isValid(someUrl)) {
 *     // Safe to use
 *   }
 * 
 *   // Get the list of whitelisted pages
 *   const allowedPages = UnganiRedirectValidator.getWhitelistedPages();
 * 
 * ============================================================
 */

(function () {
  /**
   * WHITELIST: All pages that are safe redirect targets
   * Add new pages here as your application grows
   * 
   * Rules:
   * - Only include pages that are publicly accessible OR
   * - Pages whose access is controlled by guard files (admin-*, my-*, etc)
   * - Keep filenames lowercase
   * - Include .html extension
   * - NO external domains
   * - NO query parameters (added separately by application)
   */
  const WHITELISTED_PAGES = new Set([
    // Authentication & Public Pages
    'index.html',
    'login.html',
    'staff-login.html',
    'register.html',
    'signup.html',
    'forgot-password.html',
    'reset-password.html',
    'verify-email.html',

    // Admin Pages (protected by admin-access-guard)
    'admin.html',
    'admin-home.html',
    'admin-clients.html',
    'admin-users.html',
    'admin-billing.html',
    'admin-settings.html',
    'admin-notifications.html',
    'admin-branches.html',
    'admin-onboarding.html',
    'admin-health.html',
    'admin-reports.html',
    'support.html',
    'billing.html',

    // Client Dashboard Pages (protected by client-access-guard)
    'client.html',
    'my-overview.html',
    'my-activity.html',
    'my-charts.html',
    'my-money.html',
    'my-records.html',
    'my-items.html',
    'my-people.html',
    'my-tasks.html',
    'my-calendar.html',
    'my-documents.html',
    'my-support.html',
    'my-notices.html',
    'my-chat.html',
    'my-team-chat.html',
    'my-reports.html',
    'my-profile.html',
    'account.html',
    'print-report.html',

    // Account & Billing Pages
    'my-account-status.html',
    'my-billing.html',
    'my-invoice.html',
    'my-package.html',
    'my-branches.html',
    'my-settings.html',
    'my-team-access.html',
    'my-tools.html',
    'my-onboarding.html',

    // Client Portal Pages
    'client-notifications.html',
    'client-notifications.html',
    'client-package.html'
  ]);

  /**
   * Default safe pages for each context
   * Used when redirect target is invalid or missing
   */
  const DEFAULT_PAGES = {
    admin: 'admin-home.html',
    client: 'client.html',
    public: 'index.html',
    login: 'login.html'
  };

  /**
   * Patterns that indicate malicious intent
   * These will always be rejected
   */
  const SUSPICIOUS_PATTERNS = [
    /javascript:/i,           // javascript: protocol
    /data:/i,                  // data: protocol
    /vbscript:/i,              // vbscript: protocol
    /file:/i,                  // file: protocol
    /%3a/i,                    // Encoded colon to bypass protocol check
    /%2f/i,                    // Encoded slash
    /\\/,                      // Backslash (path traversal)
    /\.\.\//,                  // ../ (directory traversal)
    /%\d{2}/,                  // Any percent encoding (may hide malicious intent)
  ];

  /**
   * Validate a redirect URL
   * Returns the safe URL if valid, null/empty string if invalid
   */
  function validateRedirect(urlString) {
    if (!urlString || typeof urlString !== 'string') {
      return null;
    }

    const url = urlString.trim();

    // Reject empty strings
    if (url.length === 0) {
      return null;
    }

    // STEP 1: Check for obvious malicious patterns
    if (hasSuspiciousPatterns(url)) {
      console.warn('[RedirectValidator] Rejected URL with suspicious patterns:', url);
      return null;
    }

    // STEP 2: Parse URL to extract components
    const parsed = parseUrlSafely(url);
    if (!parsed) {
      console.warn('[RedirectValidator] Could not parse URL:', url);
      return null;
    }

    // STEP 3: If absolute URL (has protocol/domain), validate it
    if (parsed.protocol !== null || parsed.domain !== null) {
      // Absolute URL - must be same domain
      if (!isCurrentDomain(parsed.domain)) {
        console.warn('[RedirectValidator] Rejected cross-domain redirect:', parsed.domain);
        return null;
      }
    }

    // STEP 4: Extract pathname/filename
    const pathname = parsed.pathname || '';
    const filename = extractFilename(pathname);

    // STEP 5: Validate against whitelist
    if (!isWhitelisted(filename)) {
      console.warn('[RedirectValidator] Filename not whitelisted:', filename);
      return null;
    }

    // STEP 6: Sanitize and return safe URL
    // Return as relative URL (safest option)
    return sanitizeUrl(filename);
  }

  /**
   * Check if URL has suspicious patterns that indicate attack
   */
  function hasSuspiciousPatterns(url) {
    for (const pattern of SUSPICIOUS_PATTERNS) {
      if (pattern.test(url)) {
        return true;
      }
    }
    return false;
  }

  /**
   * Parse a URL into components safely
   * Handles relative paths, absolute paths, and absolute URLs
   * Returns { protocol, domain, pathname } or null if invalid
   */
  function parseUrlSafely(url) {
    try {
      // Check for protocol (http://, https://, //, etc)
      const protocolMatch = url.match(/^([a-z][a-z0-9+\-.]*:)?\/\//i);
      
      if (protocolMatch) {
        // Has protocol or // - parse as absolute URL
        try {
          // For protocol-relative URLs (//example.com), add current protocol
          const fullUrl = url.startsWith('//') 
            ? window.location.protocol + url 
            : url;
          
          const urlObj = new URL(fullUrl, window.location.href);
          
          return {
            protocol: urlObj.protocol.replace(':', ''),
            domain: urlObj.hostname,
            pathname: urlObj.pathname
          };
        } catch (e) {
          return null;
        }
      }

      // No protocol - it's a relative path
      // Extract path and query separately
      const pathMatch = url.match(/^([^?#]+)(\?[^#]*)?(#.*)?$/);
      if (!pathMatch) {
        return null;
      }

      return {
        protocol: null,
        domain: null,
        pathname: pathMatch[1]
      };
    } catch (error) {
      return null;
    }
  }

  /**
   * Check if domain matches current site
   * Allows relative URLs (domain = null) and same-domain redirects
   */
  function isCurrentDomain(domain) {
    if (domain === null) {
      return true; // Relative URL is safe
    }

    const currentHost = window.location.hostname;
    const domainLower = String(domain || '').toLowerCase().trim();
    const currentHostLower = currentHost.toLowerCase();

    return domainLower === currentHostLower;
  }

  /**
   * Extract filename from pathname
   * Handles paths like:
   *   /admin-home.html → admin-home.html
   *   admin-home.html → admin-home.html
   *   /path/to/admin-home.html → admin-home.html (security: only allow root files)
   */
  function extractFilename(pathname) {
    if (!pathname || typeof pathname !== 'string') {
      return '';
    }

    // Remove leading/trailing slashes
    let path = pathname.replace(/^\/+|\/+$/g, '');

    // Reject if contains path traversal patterns
    if (path.includes('/') && !path.match(/^[a-z0-9._-]+\.html$/i)) {
      // Has subdirectories - only allow if it's a simple filename pattern
      // Extract just the filename (last component)
      const parts = path.split('/');
      path = parts[parts.length - 1];
    }

    return path.toLowerCase().trim();
  }

  /**
   * Check if filename is in whitelist
   */
  function isWhitelisted(filename) {
    if (!filename) {
      return false;
    }

    // Ensure it ends with .html
    if (!filename.endsWith('.html')) {
      return false;
    }

    // Check against whitelist
    return WHITELISTED_PAGES.has(filename);
  }

  /**
   * Sanitize URL by removing any query parameters or fragments
   * Returns clean, safe URL
   */
  function sanitizeUrl(filename) {
    if (!filename) {
      return null;
    }

    // Return as relative path (no leading slash needed, but it's ok)
    return filename;
  }

  /**
   * Get current page context (admin, client, or public)
   */
  function getCurrentContext() {
    const pageName = getCurrentPageName();

    if (pageName.startsWith('admin')) {
      return 'admin';
    }
    if (pageName.startsWith('my-') || pageName === 'client.html') {
      return 'client';
    }
    return 'public';
  }

  /**
   * Get current page filename
   */
  function getCurrentPageName() {
    const path = window.location.pathname || '';
    return (path.split('/').pop() || 'index.html').toLowerCase();
  }

  /**
   * Get default safe page for context
   */
  function getDefaultPageForContext(context) {
    return DEFAULT_PAGES[context] || DEFAULT_PAGES.public;
  }

  /**
   * Public API
   */
  const API = {
    /**
     * Validate a redirect URL and return safe version or null
     */
    validate: validateRedirect,

    /**
     * Check if URL is valid without returning it
     */
    isValid: function(url) {
      return validateRedirect(url) !== null;
    },

    /**
     * Perform a safe redirect
     * Falls back to default page if URL is invalid
     */
    safeRedirect: function(url, defaultPageOverride) {
      const safeUrl = validateRedirect(url);
      
      if (safeUrl) {
        window.location.href = safeUrl;
        return;
      }

      // Redirect to default safe page
      const context = getCurrentContext();
      const fallback = defaultPageOverride || getDefaultPageForContext(context);
      window.location.href = fallback;
    },

    /**
     * Get the default page for current context
     */
    getDefaultPage: function() {
      const context = getCurrentContext();
      return getDefaultPageForContext(context);
    },

    /**
     * Get list of whitelisted pages
     */
    getWhitelistedPages: function() {
      return Array.from(WHITELISTED_PAGES).sort();
    },

    /**
     * Add a page to whitelist (use cautiously)
     * Returns true if added, false if already present
     */
    addToWhitelist: function(pageName) {
      const normalized = String(pageName || '').toLowerCase().trim();
      if (normalized.endsWith('.html') && !WHITELISTED_PAGES.has(normalized)) {
        WHITELISTED_PAGES.add(normalized);
        return true;
      }
      return false;
    },

    /**
     * Check if page is whitelisted
     */
    isWhitelisted: function(pageName) {
      const normalized = String(pageName || '').toLowerCase().trim();
      return WHITELISTED_PAGES.has(normalized);
    }
  };

  // Expose global API
  window.UnganiRedirectValidator = API;

  // Log in development
  if (typeof window !== 'undefined' && window.location.hostname === 'localhost') {
    console.log('[UnganiRedirectValidator] Initialized with', WHITELISTED_PAGES.size, 'whitelisted pages');
  }

})();
