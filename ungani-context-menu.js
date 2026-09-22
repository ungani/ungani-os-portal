(function () {
  // Reusable right-click / long-press context menu for record rows across
  // list pages (Money, Tasks, Items, People, Documents, Quotations, Orders,
  // Customer Invoices). Registry-driven: each page calls UnganiContextMenu
  // .init({ tableName: [ {key,label,icon,handler,danger?,condition?} ] })
  // using ITS OWN existing functions as handlers (delete/discuss/print) -
  // this module is a thin dispatcher, never a place business logic gets
  // duplicated or reimplemented.
  //
  // Row/card elements must carry data-record-id + data-record-table for
  // the delegated listener below to find them - see each page's own
  // render function for where these attributes were added.
  //
  // Deliberately different from the existing profile-menu pattern
  // (client-shared.js) in one respect: this menu DOES close on click-
  // outside and Escape. A stray context menu left open is a worse
  // experience than a profile dropdown, so this isn't an inconsistency,
  // it's a considered difference.

  let currentMenu = null;
  let longPressTimer = null;
  let longPressStart = null;
  const LONG_PRESS_MS = 500;
  const MOVE_CANCEL_PX = 10;
  let stylesInjected = false;

  function injectStylesOnce() {
    if (stylesInjected) return;
    stylesInjected = true;
    const style = document.createElement("style");
    style.textContent = `
      .ungani-context-menu {
        position: fixed;
        z-index: 10500;
        min-width: 190px;
        background: var(--card-bg, #0E2A52);
        border: 1px solid var(--border, rgba(255,255,255,0.12));
        border-radius: 12px;
        box-shadow: 0 12px 32px rgba(0,0,0,0.35);
        padding: 6px;
        font-family: inherit;
      }
      .ungani-context-menu-item {
        display: flex;
        align-items: center;
        gap: 10px;
        width: 100%;
        padding: 9px 12px;
        border: none;
        background: transparent;
        color: var(--text, #fff);
        font-size: 14px;
        text-align: left;
        border-radius: 8px;
        cursor: pointer;
      }
      .ungani-context-menu-item:hover { background: rgba(212,166,58,0.16); }
      .ungani-context-menu-item.danger { color: #F87171; }
      .ungani-context-menu-item i { width: 16px; height: 16px; flex-shrink: 0; }
    `;
    document.head.appendChild(style);
  }

  function closeMenu() {
    if (!currentMenu) return;
    currentMenu.remove();
    currentMenu = null;
    document.removeEventListener("click", closeMenu, true);
    document.removeEventListener("contextmenu", closeMenuOnOutsideContext, true);
    document.removeEventListener("keydown", handleEscape, true);
  }

  function closeMenuOnOutsideContext(e) {
    if (currentMenu && !currentMenu.contains(e.target)) closeMenu();
  }

  function handleEscape(e) {
    if (e.key === "Escape") closeMenu();
  }

  function findRecordEl(target) {
    return target.closest ? target.closest("[data-record-id][data-record-table]") : null;
  }

  function resolveActions(registry, recordEl) {
    const table = recordEl.getAttribute("data-record-table");
    const entries = registry[table] || [];
    return entries.filter(function (a) {
      return typeof a.condition !== "function" || a.condition(recordEl);
    });
  }

  function buildMenu(recordEl, clientX, clientY, actions) {
    closeMenu();
    injectStylesOnce();

    const menu = document.createElement("div");
    menu.className = "ungani-context-menu";
    menu.innerHTML = actions.map(function (a) {
      return '<button type="button" class="ungani-context-menu-item' + (a.danger ? " danger" : "") + '" data-action-key="' + a.key + '">' +
        '<i data-lucide="' + a.icon + '"></i><span>' + a.label + "</span></button>";
    }).join("");

    // Off-screen first so getBoundingClientRect reflects real size before
    // clamping to the viewport - avoids a visible jump on open.
    menu.style.left = "-9999px";
    menu.style.top = "-9999px";
    document.body.appendChild(menu);

    const rect = menu.getBoundingClientRect();
    let left = clientX;
    let top = clientY;
    if (left + rect.width > window.innerWidth) left = window.innerWidth - rect.width - 8;
    if (top + rect.height > window.innerHeight) top = window.innerHeight - rect.height - 8;
    menu.style.left = Math.max(8, left) + "px";
    menu.style.top = Math.max(8, top) + "px";

    menu.querySelectorAll("[data-action-key]").forEach(function (btn) {
      btn.addEventListener("click", function (e) {
        e.stopPropagation();
        const action = actions.find(function (a) { return a.key === btn.getAttribute("data-action-key"); });
        closeMenu();
        if (action && typeof action.handler === "function") action.handler(recordEl);
      });
    });

    currentMenu = menu;
    if (window.UnganiClientShared && typeof UnganiClientShared.renderLucideIcons === "function") {
      UnganiClientShared.renderLucideIcons();
    }

    setTimeout(function () {
      document.addEventListener("click", closeMenu, true);
      document.addEventListener("contextmenu", closeMenuOnOutsideContext, true);
      document.addEventListener("keydown", handleEscape, true);
    }, 0);
  }

  function init(registry) {
    document.addEventListener("contextmenu", function (e) {
      const recordEl = findRecordEl(e.target);
      if (!recordEl) return;
      const actions = resolveActions(registry, recordEl);
      if (!actions.length) return;
      e.preventDefault();
      buildMenu(recordEl, e.clientX, e.clientY, actions);
    });

    document.addEventListener("touchstart", function (e) {
      const recordEl = findRecordEl(e.target);
      if (!recordEl) return;
      const touch = e.touches[0];
      longPressStart = { x: touch.clientX, y: touch.clientY, el: recordEl };
      longPressTimer = setTimeout(function () {
        longPressTimer = null;
        const actions = resolveActions(registry, recordEl);
        if (!actions.length) return;
        buildMenu(recordEl, longPressStart.x, longPressStart.y, actions);
      }, LONG_PRESS_MS);
    }, { passive: true });

    document.addEventListener("touchmove", function (e) {
      if (!longPressTimer || !longPressStart) return;
      const touch = e.touches[0];
      if (Math.abs(touch.clientX - longPressStart.x) > MOVE_CANCEL_PX ||
          Math.abs(touch.clientY - longPressStart.y) > MOVE_CANCEL_PX) {
        clearTimeout(longPressTimer);
        longPressTimer = null;
      }
    }, { passive: true });

    document.addEventListener("touchend", function () {
      if (longPressTimer) {
        clearTimeout(longPressTimer);
        longPressTimer = null;
      }
    }, { passive: true });
  }

  window.UnganiContextMenu = { init: init, close: closeMenu };
})();
