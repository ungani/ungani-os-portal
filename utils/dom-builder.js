/**
 * ============================================================
 * UNGANI OS - Secure DOM Builder Utility
 * ============================================================
 * 
 * PURPOSE:
 * - Build DOM elements safely without innerHTML injection risks
 * - Prevent XSS attacks through template literals
 * - Provide reusable patterns for guard screens
 * - Centralize styling and security logic
 * 
 * SECURITY FEATURES:
 * 1. No innerHTML - uses createElement and appendChild
 * 2. textContent only - for text nodes (not HTML)
 * 3. setAttribute for attributes - with validation
 * 4. No inline event handlers in HTML strings
 * 5. Event listeners only via addEventListener()
 * 6. Style application via cssText only when necessary
 * 
 * USAGE:
 * 
 *   const builder = UnganiDOMBuilder;
 *   
 *   // Create a blocking screen
 *   const screen = builder.createBlockedScreen({
 *     title: "Access Denied",
 *     message: "You don't have permission",
 *     detail: "Contact support",
 *     actionText: "Go Back",
 *     actionUrl: "index.html"
 *   });
 *   
 *   document.body.innerHTML = '';
 *   document.body.appendChild(screen);
 * 
 * ============================================================
 */

(function () {
  /**
   * Safe style presets to avoid repeated inline styling
   */
  const STYLES = {
    // Main container for full-screen blocked views
    mainContainer: {
      minHeight: '100vh',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      padding: '24px',
      background: 'linear-gradient(135deg, #031227 0%, #061C3D 48%, #092A59 100%)',
      fontFamily: 'Arial, Helvetica, sans-serif',
      color: '#FFFFFF',
      margin: '0',
      width: '100%'
    },

    // Card/section styling
    card: {
      width: '100%',
      maxWidth: '620px',
      background: 'rgba(8, 38, 84, 0.95)',
      border: '1px solid rgba(255, 255, 255, 0.14)',
      borderRadius: '24px',
      boxShadow: '0 18px 45px rgba(0, 0, 0, 0.28)',
      padding: '40px 32px',
      textAlign: 'center'
    },

    // Logo styling
    logo: {
      width: '72px',
      height: '72px',
      margin: '0 auto 20px',
      background: '#FFFFFF',
      borderRadius: '18px',
      padding: '8px',
      objectFit: 'contain',
      boxShadow: '0 12px 28px rgba(0, 0, 0, 0.20)',
      display: 'block'
    },

    // Title
    title: {
      margin: '0 0 16px',
      fontSize: '28px',
      fontWeight: '700',
      color: '#D4A63A',
      letterSpacing: '-0.02em'
    },

    // Message text
    message: {
      margin: '0 0 12px',
      color: '#F5F5F3',
      lineHeight: '1.6',
      fontSize: '16px'
    },

    // Detail/support text
    detail: {
      margin: '0 0 24px',
      color: '#B8C3D6',
      lineHeight: '1.6',
      fontSize: '14px'
    },

    // Primary action button
    primaryButton: {
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      textDecoration: 'none',
      background: '#D4A63A',
      color: '#061C3D',
      borderRadius: '999px',
      padding: '13px 24px',
      fontWeight: '900',
      fontSize: '14px',
      border: 'none',
      cursor: 'pointer',
      transition: 'all 0.2s ease'
    },

    // Secondary button
    secondaryButton: {
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      textDecoration: 'none',
      borderRadius: '999px',
      padding: '13px 24px',
      fontWeight: '900',
      fontSize: '14px',
      border: '1px solid rgba(255, 255, 255, 0.16)',
      background: 'rgba(255, 255, 255, 0.12)',
      color: '#FFFFFF',
      cursor: 'pointer',
      transition: 'all 0.2s ease'
    },

    // Button container
    buttonGroup: {
      display: 'flex',
      flexWrap: 'wrap',
      gap: '12px',
      justifyContent: 'center',
      marginTop: '24px'
    },

    // Footer text
    footer: {
      marginTop: '28px',
      paddingTop: '20px',
      borderTop: '1px solid rgba(255, 255, 255, 0.08)',
      color: '#B8C3D6',
      fontSize: '12px',
      lineHeight: '1.5'
    }
  };

  /**
   * Apply styles to an element safely
   */
  function applyStyles(element, styleObj) {
    if (!element || !styleObj || typeof styleObj !== 'object') {
      return;
    }

    Object.entries(styleObj).forEach(([key, value]) => {
      try {
        element.style[camelCase(key)] = value;
      } catch (error) {
        console.warn('[DOMBuilder] Failed to apply style:', key, error.message);
      }
    });
  }

  /**
   * Convert CSS property names to camelCase
   */
  function camelCase(str) {
    return str.replace(/-([a-z])/g, (g) => g[1].toUpperCase());
  }

  /**
   * Create a logo image element
   */
  function createLogo() {
    const img = document.createElement('img');
    img.src = 'ungani-logo.png';
    img.alt = 'UNGANI Logo';
    applyStyles(img, STYLES.logo);
    return img;
  }

  /**
   * Create a title element
   */
  function createTitle(text) {
    const h1 = document.createElement('h1');
    h1.textContent = text; // textContent prevents HTML injection
    applyStyles(h1, STYLES.title);
    return h1;
  }

  /**
   * Create a message/paragraph element
   */
  function createMessage(text) {
    const p = document.createElement('p');
    p.textContent = text; // textContent prevents HTML injection
    applyStyles(p, STYLES.message);
    return p;
  }

  /**
   * Create a detail/support text element
   */
  function createDetail(text) {
    const p = document.createElement('p');
    p.textContent = text; // textContent prevents HTML injection
    applyStyles(p, STYLES.detail);
    return p;
  }

  /**
   * Create a button element
   */
  function createButton(options) {
    const {
      text = 'Button',
      href = null,
      onClick = null,
      isPrimary = false,
      isSecondary = false
    } = options;

    const element = href ? document.createElement('a') : document.createElement('button');
    
    element.type = href ? undefined : 'button';
    element.textContent = text; // textContent prevents HTML injection

    // Set href safely if it's a link
    if (href) {
      // Validate URL to prevent javascript: or data: attacks
      if (isSafeUrl(href)) {
        element.href = href;
      } else {
        element.href = '#';
        element.style.cursor = 'not-allowed';
        element.style.opacity = '0.5';
      }
    }

    // Apply appropriate styles
    const styles = isPrimary 
      ? STYLES.primaryButton 
      : (isSecondary ? STYLES.secondaryButton : STYLES.secondaryButton);
    
    applyStyles(element, styles);

    // Add hover effect via event listeners (not inline)
    element.addEventListener('mouseenter', function() {
      this.style.filter = 'brightness(1.1)';
    });

    element.addEventListener('mouseleave', function() {
      this.style.filter = 'brightness(1)';
    });

    // Add click handler if provided
    if (onClick && typeof onClick === 'function') {
      element.addEventListener('click', onClick);
    }

    return element;
  }

  /**
   * Validate URL to prevent XSS
   */
  function isSafeUrl(url) {
    if (!url || typeof url !== 'string') {
      return false;
    }

    const lowercased = url.toLowerCase().trim();

    // Block dangerous protocols
    if (
      lowercased.startsWith('javascript:') ||
      lowercased.startsWith('data:') ||
      lowercased.startsWith('vbscript:') ||
      lowercased.startsWith('file:')
    ) {
      return false;
    }

    // Block encoded versions
    if (lowercased.includes('%3a') || lowercased.includes('%2f')) {
      return false;
    }

    return true;
  }

  /**
   * Create a complete blocked screen
   */
  function createBlockedScreen(options) {
    const {
      title = 'Access Denied',
      message = 'Your access is restricted.',
      detail = '',
      actionText = 'Go Back',
      actionUrl = 'index.html',
      secondaryText = null,
      secondaryUrl = null,
      onActionClick = null
    } = options;

    // Validate inputs
    if (!title || typeof title !== 'string') {
      console.warn('[DOMBuilder] Invalid title');
      return null;
    }

    // Create main container
    const main = document.createElement('main');
    applyStyles(main, STYLES.mainContainer);

    // Create card
    const section = document.createElement('section');
    applyStyles(section, STYLES.card);

    // Add logo
    const logo = createLogo();
    section.appendChild(logo);

    // Add title
    const titleEl = createTitle(title);
    section.appendChild(titleEl);

    // Add message
    const messageEl = createMessage(message);
    section.appendChild(messageEl);

    // Add detail if provided
    if (detail && typeof detail === 'string') {
      const detailEl = createDetail(detail);
      section.appendChild(detailEl);
    }

    // Create button group
    const buttonGroup = document.createElement('div');
    applyStyles(buttonGroup, STYLES.buttonGroup);

    // Add primary action button
    const primaryBtn = createButton({
      text: actionText,
      href: actionUrl,
      onClick: onActionClick,
      isPrimary: true
    });
    buttonGroup.appendChild(primaryBtn);

    // Add secondary button if provided
    if (secondaryText && secondaryUrl) {
      const secondaryBtn = createButton({
        text: secondaryText,
        href: secondaryUrl,
        isSecondary: true
      });
      buttonGroup.appendChild(secondaryBtn);
    }

    section.appendChild(buttonGroup);

    // Add footer
    const footer = document.createElement('div');
    applyStyles(footer, STYLES.footer);
    footer.textContent = 'UNGANI OS • ungani.com • info@ungani.com';
    section.appendChild(footer);

    main.appendChild(section);

    return main;
  }

  /**
   * Create a loading/checking screen
   */
  function createCheckingScreen(title = 'Verifying Access', message = 'Please wait...') {
    const main = document.createElement('main');
    applyStyles(main, STYLES.mainContainer);

    const section = document.createElement('section');
    applyStyles(section, STYLES.card);

    // Spinner
    const spinner = document.createElement('div');
    spinner.style.cssText = `
      width: 60px;
      height: 60px;
      margin: 0 auto 20px;
      border: 4px solid rgba(255, 255, 255, 0.2);
      border-top-color: #D4A63A;
      border-radius: 50%;
      animation: spin 0.8s linear infinite;
    `;

    // Add animation
    if (!document.getElementById('ungani-spinner-animation')) {
      const style = document.createElement('style');
      style.id = 'ungani-spinner-animation';
      style.textContent = '@keyframes spin { to { transform: rotate(360deg); } }';
      document.head.appendChild(style);
    }

    section.appendChild(spinner);

    // Title
    const titleEl = document.createElement('h2');
    titleEl.textContent = title;
    titleEl.style.cssText = 'margin: 0 0 12px; font-size: 18px;';
    section.appendChild(titleEl);

    // Message
    const messageEl = document.createElement('p');
    messageEl.textContent = message;
    messageEl.style.cssText = `
      margin: 0;
      color: rgba(255, 255, 255, 0.72);
      font-size: 14px;
      line-height: 1.5;
    `;
    section.appendChild(messageEl);

    main.appendChild(section);

    return main;
  }

  /**
   * Clear page safely
   */
  function clearPage() {
    try {
      // Remove all children of body
      while (document.body.firstChild) {
        document.body.removeChild(document.body.firstChild);
      }
      document.body.style.overflow = 'auto';
    } catch (error) {
      console.warn('[DOMBuilder] Failed to clear page:', error.message);
    }
  }

  /**
   * Replace page content with new element
   */
  function replacePage(element) {
    if (!element) {
      return;
    }

    clearPage();
    document.body.appendChild(element);
  }

  /**
   * Public API
   */
  const API = {
    createBlockedScreen,
    createCheckingScreen,
    createButton,
    createTitle,
    createMessage,
    createDetail,
    createLogo,
    clearPage,
    replacePage,
    applyStyles,
    isSafeUrl
  };

  // Expose globally
  window.UnganiDOMBuilder = API;

})();
