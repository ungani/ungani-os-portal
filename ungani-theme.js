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
//
// CROSS-ACCOUNT BUG FIX (see memory theme_cross_account_bleed_fix): every
// read/write below used ONE global, unscoped localStorage key for the
// whole browser origin - switching accounts on a shared device (a real,
// common testing/demo scenario) made one business's theme choice
// permanently "stick" for the next, completely unrelated business logged
// into on the same browser. get/apply/toggle/init now accept an optional
// scopeId (the current auth user's id) and read/write a key namespaced to
// it FIRST. The unscoped legacy keys are still written as a fallback
// ONLY for the brief pre-auth paint (client.html/my-profile.html/
// my-settings.html all call init() with no scopeId immediately on load,
// before any Supabase round-trip, purely to avoid a flash of the wrong
// theme) - every caller re-applies with the real scopeId the moment
// identity is known, which is what actually stops the bleed from
// persisting past that first, sub-second paint.
(function () {
  var CANONICAL_KEY = "ungani_theme";
  var LEGACY_READ_KEYS = ["ungani_client_theme", "ungani_appearance", "unganiTheme", "theme"];

  function scopedKey(scopeId) {
    return scopeId ? (CANONICAL_KEY + "::" + scopeId) : null;
  }

  function readStoredTheme(scopeId) {
    try {
      var key = scopedKey(scopeId);
      if (key) {
        var scopedValue = localStorage.getItem(key);
        if (scopedValue) return scopedValue;
        // No scoped value yet for this account (e.g. their first ever
        // visit) - fall through to the unscoped keys ONLY as a last
        // resort, same as having no scopeId at all. This never leaks a
        // DIFFERENT account's choice into a brand-new account that
        // hasn't set anything yet.
      }

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

  function get(scopeId) {
    var stored = readStoredTheme(scopeId);
    if (stored) return String(stored).toLowerCase().indexOf("dark") !== -1 ? "dark" : "light";
    return systemPrefersDark() ? "dark" : "light";
  }

  // Sets every attribute/element combination any current stylesheet in the
  // app reads (data-theme and data-ungani-theme, on both <html> and
  // <body>), and persists to the account-scoped key (when scopeId is
  // given) plus the unscoped canonical/legacy keys (kept for the pre-auth
  // paint case - see the file header comment).
  function apply(theme, scopeId) {
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
      var key = scopedKey(scopeId);
      if (key) localStorage.setItem(key, clean);
      localStorage.setItem(CANONICAL_KEY, clean);
      localStorage.setItem("ungani_client_theme", clean);
    } catch (e) {
      // localStorage unavailable - theme still applies for this page load.
    }

    return clean;
  }

  // Set the moment a human explicitly toggles the theme, so a slower
  // in-flight syncFromServer() (see below) knows not to stomp on that
  // choice with a stale DB read that started before the toggle - found
  // live while testing the cross-account fix: initClientDashboard()'s
  // initial correction call can still be awaiting its network round-trip
  // when a user clicks the toggle, and without this guard its late
  // resolution silently reverted the manual toggle back to the old value
  // a moment later.
  var userToggledThisPageLoad = false;

  function toggle(scopeId) {
    userToggledThisPageLoad = true;
    return apply(get(scopeId) === "dark" ? "light" : "dark", scopeId);
  }

  function init(scopeId) {
    return apply(get(scopeId), scopeId);
  }

  // Best-effort DB sync for the account-scoped preference, using the
  // real, already-live user_preferences table (per auth user_id, not
  // per-tenant - see my-settings.html's own fetchUserPreferences()/
  // savePreferences(), the only place this table was previously read
  // from). Sends ONLY {user_id, theme} on write so it never clobbers a
  // different page's language/currency/timezone columns on the same row.
  // Both fully fail-open: a network/RLS error just means this device
  // keeps relying on its local cache, matching every other non-critical
  // sync in this app.
  async function syncFromServer(supabaseClient, userId) {
    if (!supabaseClient || !userId) return get(userId);

    try {
      var response = await supabaseClient
        .from("user_preferences")
        .select("theme")
        .eq("user_id", userId)
        .maybeSingle();

      if (userToggledThisPageLoad) return get(userId);

      if (!response.error && response.data && response.data.theme) {
        return apply(response.data.theme, userId);
      }
    } catch (e) {
      // Fall through to the local cache below.
    }

    if (userToggledThisPageLoad) return get(userId);
    return apply(get(userId), userId);
  }

  function persistToServer(supabaseClient, userId, theme) {
    if (!supabaseClient || !userId) return;

    supabaseClient
      .from("user_preferences")
      .upsert({ user_id: userId, theme: theme }, { onConflict: "user_id" })
      .then(function (response) {
        if (response && response.error) {
          console.warn("Theme preference sync skipped:", response.error.message);
        }
      })
      .catch(function () {});
  }

  window.UnganiTheme = {
    get: get,
    apply: apply,
    toggle: toggle,
    init: init,
    syncFromServer: syncFromServer,
    persistToServer: persistToServer
  };
})();
