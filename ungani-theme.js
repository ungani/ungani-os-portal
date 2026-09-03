// Single source of truth for dark/light theme logic, shared by client.html,
// client-shared.js's 22 initPage() pages, and the two standalone pages
// (my-profile.html, my-settings.html) that load neither of those.
//
// Deliberately zero-dependency and side-effect-free beyond what a caller
// explicitly asks for (get/apply/toggle/init) - no auto-init on load, no
// event listeners registered - safe for client.html to load even though it
// otherwise avoids client-shared.js specifically because that file has
// auto-initializing side effects.
//
// Before this file existed, four different pages each had their own
// toggle/apply implementation, disagreeing on which DOM attribute to set
// (data-theme vs data-ungani-theme) and which element to set it on
// (<html> vs <body>) - each page's own CSS only ever matched its own
// convention. Rather than picking one convention and rewriting three
// pages' CSS to match (a much bigger, separate job - see the backlogged
// full theme-consistency audit), this writes every attribute any existing
// stylesheet in the app has been found to read, so no CSS needed to
// change at all.
(function () {
  var CANONICAL_KEY = "ungani_theme";
  var LEGACY_READ_KEYS = ["ungani_client_theme", "ungani_appearance", "unganiTheme", "theme"];

  function readStoredTheme() {
    try {
      var value = localStorage.getItem(CANONICAL_KEY);
      if (value) return value;

      for (var i = 0; i < LEGACY_READ_KEYS.length; i++) {
        value = localStorage.getItem(LEGACY_READ_KEYS[i]);
        if (value) return value;
      }
    } catch (e) {
      // localStorage unavailable (private browsing etc.) - fall through.
    }

    return null;
  }

  function systemPrefersDark() {
    return !!(window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches);
  }

  function get() {
    var stored = readStoredTheme();
    if (stored) return String(stored).toLowerCase().indexOf("dark") !== -1 ? "dark" : "light";
    return systemPrefersDark() ? "dark" : "light";
  }

  // Sets every attribute/element combination any current stylesheet in the
  // app reads (data-theme and data-ungani-theme, on both <html> and
  // <body>), and persists to the canonical key plus the one legacy key
  // still read elsewhere as a fallback (ungani_client_theme).
  function apply(theme) {
    var clean = String(theme || "light").toLowerCase().indexOf("dark") !== -1 ? "dark" : "light";

    document.documentElement.setAttribute("data-theme", clean);
    document.documentElement.setAttribute("data-ungani-theme", clean);
    document.documentElement.dataset.unganiTheme = clean;

    if (document.body) {
      document.body.setAttribute("data-theme", clean);
      document.body.setAttribute("data-ungani-theme", clean);
      document.body.dataset.unganiTheme = clean;
    }

    try {
      localStorage.setItem(CANONICAL_KEY, clean);
      localStorage.setItem("ungani_client_theme", clean);
    } catch (e) {
      // localStorage unavailable - theme still applies for this page load.
    }

    return clean;
  }

  function toggle() {
    return apply(get() === "dark" ? "light" : "dark");
  }

  function init() {
    return apply(get());
  }

  window.UnganiTheme = {
    get: get,
    apply: apply,
    toggle: toggle,
    init: init
  };
})();
