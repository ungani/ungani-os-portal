// Single source of truth for stock quantity/reorder-level resolution and
// the out_of_stock / low_stock / in_stock rule. Every call site that used
// to compute this locally (client.html, my-items.html,
// my-stock-tracking.html, nia-assistant.js, admin-items.html,
// admin-home.html, reports.html, print-report.html) now calls this module
// instead. The SQL side mirrors getStockStatus()'s exact bucketing rule in
// public.ungani_stock_status() (sql/stock-status-unification.sql) - the
// two are tested for agreement by stock-status-parity-test.js. If you
// change the bucketing logic here, the SQL function must change
// identically in the same migration.
//
// Hospitality's F&B items use a genuinely different data model - a
// status-text field, not a tracked quantity - so isLowStockByStatusText/
// isOutOfStockByStatusText are kept here as clearly separate functions,
// not folded into the numeric ones.
(function () {
  "use strict";

  function readField(obj, keys, fallback) {
    if (!obj) return fallback;
    for (let i = 0; i < keys.length; i++) {
      const v = obj[keys[i]];
      if (v !== undefined && v !== null && v !== "") return v;
    }
    return fallback;
  }

  // A tenant that's never turned Stock Tracking on at all, on an item with
  // no custom_fields.reorder_level of its own, has no per-type default to
  // fall back to (the type-based default is only ever seeded by
  // enable_ungani_stock_tracking()). This is the one narrow legacy case
  // this constant still covers - it is NOT a general-purpose fallback
  // once tracking has been enabled even once, since default_reorder_level
  // persists after a later disable.
  const LEGACY_PRE_TRACKING_FALLBACK = 5;

  // Mirrors client.html's original getStockQuantity() exactly, just
  // parameterized on tenant instead of a closure variable. Once Stock
  // Tracking is on, business_items.quantity (a real column) is
  // authoritative; before that, custom_fields.stock_quantity is read;
  // units_available is a legacy fallback for old Real Estate rows.
  function getQuantity(item, tenant) {
    if (tenant && tenant.stock_tracking_enabled === true) {
      const trackedQty = readField(item, ["quantity"], null);
      if (trackedQty !== null && trackedQty !== "") {
        const trackedNum = Number(trackedQty);
        if (!isNaN(trackedNum)) return trackedNum;
      }
    }

    const customFields = (item && item.custom_fields) || {};
    const customQty = customFields.stock_quantity;
    if (customQty !== undefined && customQty !== null && customQty !== "") {
      const num = Number(customQty);
      if (!isNaN(num)) return num;
    }

    const raw = readField(item, ["units_available"], null);
    if (raw === null || raw === "") return null;
    const num = Number(raw);
    return isNaN(num) ? null : num;
  }

  // item-level override (business_items.reorder_level while tracking is
  // on, else custom_fields.reorder_level) wins over
  // tenant.default_reorder_level, which is guaranteed non-null while
  // stock_tracking_enabled is true (DB check constraint in
  // sql/stock-status-unification.sql) - and persists even after a later
  // disable, so a tenant that's ever enabled tracking keeps using its own
  // real default rather than falling back to the flat legacy constant.
  function getEffectiveReorderLevel(item, tenant) {
    const trackingOn = !!(tenant && tenant.stock_tracking_enabled === true);
    const customFields = (item && item.custom_fields) || {};

    if (trackingOn) {
      const trackedLevel = readField(item, ["reorder_level"], null);
      if (trackedLevel !== null && trackedLevel !== "") {
        const trackedNum = Number(trackedLevel);
        if (!isNaN(trackedNum) && trackedNum > 0) return trackedNum;
      }
    } else {
      const raw = customFields.reorder_level;
      if (raw !== undefined && raw !== null && raw !== "") {
        const num = Number(raw);
        if (!isNaN(num) && num > 0) return num;
      }
    }

    const tenantDefault = tenant && tenant.default_reorder_level !== null && tenant.default_reorder_level !== undefined && tenant.default_reorder_level !== ""
      ? Number(tenant.default_reorder_level)
      : null;

    if (tenantDefault !== null && !isNaN(tenantDefault)) return tenantDefault;

    return LEGACY_PRE_TRACKING_FALLBACK;
  }

  // Mirrors public.ungani_stock_status(p_quantity, p_effective_reorder_level):
  // out_of_stock at qty<=0, low_stock at 0<qty<=effective reorder level
  // (only when a reorder level is actually known), in_stock otherwise.
  function getStockStatus(quantity, effectiveReorderLevel) {
    if (quantity === null || quantity === undefined || quantity === "") return null;

    const qty = Number(quantity);
    if (isNaN(qty)) return null;

    if (qty <= 0) return "out_of_stock";

    const reorderLevel = effectiveReorderLevel === null || effectiveReorderLevel === undefined || effectiveReorderLevel === ""
      ? null
      : Number(effectiveReorderLevel);

    if (reorderLevel !== null && !isNaN(reorderLevel) && qty <= reorderLevel) return "low_stock";

    return "in_stock";
  }

  // Convenience wrapper: resolves quantity + effective reorder level from
  // the item/tenant, then buckets. This is what every call site should
  // use - the two-argument getStockStatus() above stays exposed only
  // because the parity test calls it directly with raw numbers to diff
  // against the SQL function.
  //
  // Car Showroom vehicles are serialized units (quantity always 1 or 0,
  // never a pool), not restockable inventory - reorder levels/low-stock
  // alerts make no sense against them. This one guard is the single
  // point every call site (client.html, my-items.html,
  // my-stock-tracking.html, admin-items.html, admin-home.html,
  // reports.html, print-report.html, nia-assistant.js) funnels through,
  // so it covers all of them without touching any of those 8 files.
  function getItemStockStatus(item, tenant) {
    if (tenant && tenant.business_type_key === "car_showroom") return null;
    return getStockStatus(getQuantity(item, tenant), getEffectiveReorderLevel(item, tenant));
  }

  function isOutOfStock(quantity, effectiveReorderLevel) {
    return getStockStatus(quantity, effectiveReorderLevel) === "out_of_stock";
  }

  function isLowStock(quantity, effectiveReorderLevel) {
    return getStockStatus(quantity, effectiveReorderLevel) === "low_stock";
  }

  function isItemOutOfStock(item, tenant) {
    return getItemStockStatus(item, tenant) === "out_of_stock";
  }

  function isItemLowStock(item, tenant) {
    return getItemStockStatus(item, tenant) === "low_stock";
  }

  // Hospitality's F&B items (Restaurant/Bar Lounge/Catering) tag stock via
  // a status-text field instead of a tracked quantity - genuinely
  // different data model, kept separate from the numeric functions above.
  function isOutOfStockByStatusText(item) {
    return String(readField(item, ["property_status", "item_status", "status"], "")).toLowerCase().includes("out of stock");
  }

  function isLowStockByStatusText(item) {
    return String(readField(item, ["property_status", "item_status", "status"], "")).toLowerCase().includes("low stock");
  }

  const api = {
    getQuantity: getQuantity,
    getEffectiveReorderLevel: getEffectiveReorderLevel,
    getStockStatus: getStockStatus,
    getItemStockStatus: getItemStockStatus,
    isOutOfStock: isOutOfStock,
    isLowStock: isLowStock,
    isItemOutOfStock: isItemOutOfStock,
    isItemLowStock: isItemLowStock,
    isOutOfStockByStatusText: isOutOfStockByStatusText,
    isLowStockByStatusText: isLowStockByStatusText
  };

  if (typeof module !== "undefined" && module.exports) {
    module.exports = api;
  }
  if (typeof window !== "undefined") {
    window.UnganiStockStatus = api;
  }
})();
