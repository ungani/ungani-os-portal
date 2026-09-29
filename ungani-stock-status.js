// Single source of truth for the out_of_stock / low_stock / in_stock rule,
// shared by every JS call site (client.html, my-items.html,
// my-stock-tracking.html, nia-assistant.js, admin-items.html,
// admin-home.html, reports.html, print-report.html). The SQL side mirrors
// this exact rule in public.ungani_stock_status() (sql/stock-status-
// unification.sql) - the two are tested for agreement by
// stock-status-parity-test.js. If you change the bucketing logic here, the
// SQL function must change identically in the same migration.
//
// Hospitality's F&B items (isLowStockHospitalityItem/
// isOutOfStockHospitalityItem in client.html) use a genuinely different
// data model - a status-text field, not a tracked quantity - and are
// intentionally NOT part of this module.
(function () {
  "use strict";

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

  // item.reorder_level (per-item override) wins over tenant.default_reorder_level.
  // While stock_tracking_enabled is true, tenant.default_reorder_level is
  // guaranteed non-null by a DB check constraint (sql/stock-status-
  // unification.sql) - this function has no hardcoded fallback constant of
  // its own for that reason; if both are somehow null (tracking off, or a
  // pre-migration tenant), the result is null, matching the SQL function.
  function getEffectiveReorderLevel(item, tenant) {
    const itemLevel = item && item.reorder_level !== null && item.reorder_level !== undefined && item.reorder_level !== ""
      ? Number(item.reorder_level)
      : null;

    if (itemLevel !== null && !isNaN(itemLevel) && itemLevel > 0) return itemLevel;

    const tenantDefault = tenant && tenant.default_reorder_level !== null && tenant.default_reorder_level !== undefined && tenant.default_reorder_level !== ""
      ? Number(tenant.default_reorder_level)
      : null;

    return tenantDefault !== null && !isNaN(tenantDefault) ? tenantDefault : null;
  }

  function isOutOfStock(quantity, effectiveReorderLevel) {
    return getStockStatus(quantity, effectiveReorderLevel) === "out_of_stock";
  }

  function isLowStock(quantity, effectiveReorderLevel) {
    return getStockStatus(quantity, effectiveReorderLevel) === "low_stock";
  }

  const api = {
    getStockStatus: getStockStatus,
    getEffectiveReorderLevel: getEffectiveReorderLevel,
    isOutOfStock: isOutOfStock,
    isLowStock: isLowStock
  };

  if (typeof module !== "undefined" && module.exports) {
    module.exports = api;
  }
  if (typeof window !== "undefined") {
    window.UnganiStockStatus = api;
  }
})();
