(function () {
  // Dashboard labels and default categories per business type now live in
  // ungani-business-config.js (the single source of truth shared with
  // ungani-analytics.js). This file stays as a thin wrapper so every page
  // that already calls UnganiPresets.getPreset(...) keeps working exactly
  // as before, with no changes needed on their side.

  function getPreset(tenant) {
    const matched = window.UnganiBusinessConfig.resolveWithSections(tenant);
    return window.UnganiBusinessConfig.mergeWithGeneral(matched);
  }

  function escapeHtml(value) {
    return String(value === null || value === undefined ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  function optionList(values, selectedValue) {
    const selected = String(selectedValue || "").toLowerCase();

    return (values || []).map(function (value) {
      const clean = String(value || "").trim();
      const isSelected = clean.toLowerCase() === selected ? "selected" : "";

      return `<option value="${escapeHtml(clean)}" ${isSelected}>${escapeHtml(clean)}</option>`;
    }).join("");
  }

  function datalist(id, values) {
    return `
      <datalist id="${escapeHtml(id)}">
        ${(values || []).map(function (value) {
          return `<option value="${escapeHtml(value)}"></option>`;
        }).join("")}
      </datalist>
    `;
  }

  function presetSummaryCards(preset) {
    return `
      <div class="ungani-grid">
        <div class="ungani-card">
          <h3>${escapeHtml(preset.itemsLabel)}</h3>
          <p class="ungani-small">${escapeHtml(preset.itemTypes.slice(0, 5).join(" · "))}</p>
        </div>

        <div class="ungani-card">
          <h3>${escapeHtml(preset.peopleLabel)}</h3>
          <p class="ungani-small">${escapeHtml(preset.peopleTypes.slice(0, 5).join(" · "))}</p>
        </div>

        <div class="ungani-card">
          <h3>${escapeHtml(preset.tasksLabel)}</h3>
          <p class="ungani-small">${escapeHtml(preset.taskTypes.slice(0, 5).join(" · "))}</p>
        </div>

        <div class="ungani-card">
          <h3>Money Categories</h3>
          <p class="ungani-small">${escapeHtml(preset.incomeCategories.slice(0, 3).join(" · "))}</p>
        </div>
      </div>
    `;
  }

  window.UnganiPresets = {
    get GENERAL() { return window.UnganiBusinessConfig.mergeWithGeneral(null); },
    get PRESETS() { return window.UnganiBusinessConfig.TYPES; },
    getPreset,
    optionList,
    datalist,
    presetSummaryCards,
    escapeHtml
  };
})();
