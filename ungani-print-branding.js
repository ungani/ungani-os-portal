// Shared branding for every printable/exported document (print-report.html,
// the new Customer Invoices print view, and any future one) - reads
// directly off the already-loaded tenant row (client-shared.js's
// initPage() already does .from("tenants").select("*"), so
// branding_email/branding_phone/branding_address/kra_pin/owner_name/
// logo_url/company_name are already present, no extra query needed here).
//
// Deliberately does NOT touch dashboard/sidebar/nav/in-app branding -
// printable documents only, per explicit scope.
(function () {
  function escapeHtml(value) {
    return String(value == null ? "" : value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  // Falls back to the UNGANI logo when a business hasn't uploaded their
  // own - every existing printable page already has an <img> element
  // with its own sizing/positioning, so this only resolves the URL
  // rather than dictating markup.
  function getLogoUrl(tenant) {
    return (tenant && tenant.logo_url) || "ungani-logo.png";
  }

  function getDisplayName(tenant) {
    return (tenant && tenant.company_name) || "Your Business";
  }

  // Address/phone-email/KRA PIN, one per line, skipping anything not
  // set - returns "" if nothing is set at all, so callers can safely
  // check truthiness before wrapping it in extra markup.
  function renderContactLines(tenant) {
    if (!tenant) return "";

    const lines = [];

    if (tenant.branding_address) {
      lines.push(escapeHtml(tenant.branding_address));
    }

    const contactBits = [];
    if (tenant.branding_phone) contactBits.push(escapeHtml(tenant.branding_phone));
    if (tenant.branding_email) contactBits.push(escapeHtml(tenant.branding_email));
    if (contactBits.length) lines.push(contactBits.join(" &middot; "));

    if (tenant.kra_pin) {
      lines.push("KRA PIN: " + escapeHtml(tenant.kra_pin));
    }

    return lines.join("<br />");
  }

  // Full header block (logo + name + contact lines) for documents that
  // don't already have their own header layout, like Customer Invoices.
  // opts.contactColor/opts.nameColor let a caller on a light background
  // (the invoice print view) override the defaults, which were tuned for
  // dark surfaces (print-report.html's cover).
  function renderHeaderBlock(tenant, options) {
    const opts = options || {};
    const logoSize = opts.logoSize || 66;
    const contactColor = opts.contactColor || "#B8C3D6";
    const nameColor = opts.nameColor || "inherit";
    const contactHtml = renderContactLines(tenant);

    return (
      '<div class="ungani-print-brand" style="display:flex;gap:14px;align-items:center;">' +
        '<img src="' + escapeHtml(getLogoUrl(tenant)) + '" alt="' + escapeHtml(getDisplayName(tenant)) + ' logo" ' +
          'style="width:' + logoSize + 'px;height:' + logoSize + 'px;object-fit:contain;background:#FFFFFF;border-radius:18px;padding:7px;border:1px solid rgba(6,28,61,0.08);" ' +
          'onerror="this.onerror=null;this.src=\'ungani-logo.png\';" />' +
        '<div>' +
          '<h1 style="margin:0 0 5px;font-size:26px;letter-spacing:0.3px;color:' + escapeHtml(nameColor) + ';">' + escapeHtml(getDisplayName(tenant)) + '</h1>' +
          (contactHtml ? '<p style="margin:0;color:' + escapeHtml(contactColor) + ';line-height:1.6;font-size:13px;">' + contactHtml + '</p>' : '') +
        '</div>' +
      '</div>'
    );
  }

  // Always shown regardless of whether a business has set branding -
  // UNGANI OS stays the platform brand per explicit requirement. Kept
  // deliberately small (a thin strip, not a logo) so the tenant's own
  // branding at the top of the document stays the dominant visual.
  function renderPoweredByFooter() {
    return (
      '<div class="ungani-powered-by" style="margin-top:22px;padding:9px 12px;background:#061C3D;border-radius:8px;text-align:center;">' +
        '<span style="font-size:10.5px;font-weight:700;letter-spacing:0.6px;color:#D4A63A;">Powered by UNGANI OS</span>' +
      '</div>'
    );
  }

  window.UnganiPrintBranding = {
    getLogoUrl: getLogoUrl,
    getDisplayName: getDisplayName,
    renderContactLines: renderContactLines,
    renderHeaderBlock: renderHeaderBlock,
    renderPoweredByFooter: renderPoweredByFooter
  };
})();
