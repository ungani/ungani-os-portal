(function () {
  const COLORS = {
    navy: "#061C3D",
    navyLight: "#0B2346",
    gold: "#D4A63A",
    offWhite: "#F5F5F3",
    white: "#FFFFFF",
    green: "#15803D",
    blue: "#2563EB",
    violet: "#7C3AED",
    teal: "#0891B2",
    orange: "#C77700",
    amber: "#F59E0B",
    slate: "#64748B",
    red: "#B91C1C"
  };

  // Business-type profiles (chart titles, hero copy, dashboard badge text)
  // now live in ungani-business-config.js, shared with ungani-presets.js,
  // so both files always describe the same business type identically.
  // See getBusinessProfile() below, which reads from
  // window.UnganiBusinessConfig instead of a local list.

  const EXPENSE_CATEGORY_COLORS = {
    "agent commission": COLORS.gold,
    "marketing / advertising": COLORS.blue,
    "marketing": COLORS.blue,
    "advertising": COLORS.blue,
    "legal / documentation fees": COLORS.violet,
    "legal fees": COLORS.violet,
    "documentation": COLORS.violet,
    "property maintenance": COLORS.teal,
    "maintenance": COLORS.teal,
    "repairs": COLORS.teal,
    "staff wages": "#0F766E",
    "site visit / transport cost": COLORS.orange,
    "transport": COLORS.orange,
    "project material cost": "#A16207",
    "other real estate cost": COLORS.slate,
    "other expense": COLORS.slate
  };

  let chartJsPromise = null;
  const chartInstances = {};

  function getBusinessProfile(tenant) {
    const matched = window.UnganiBusinessConfig.resolve(tenant);
    return Object.assign({}, window.UnganiBusinessConfig.GENERAL, matched || {});
  }

  function loadChartJs() {
    if (window.Chart) return Promise.resolve(window.Chart);
    if (chartJsPromise) return chartJsPromise;

    chartJsPromise = new Promise(function (resolve, reject) {
      const script = document.createElement("script");
      script.src = "https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js";
      script.async = true;
      script.onload = function () { resolve(window.Chart); };
      script.onerror = function () { reject(new Error("Chart.js could not load.")); };
      document.head.appendChild(script);
    });

    return chartJsPromise;
  }

  function injectChartStyles() {
    if (document.getElementById("ungani-analytics-styles")) return;

    const style = document.createElement("style");
    style.id = "ungani-analytics-styles";
    style.textContent = `
      .ungani-chart-card{min-height:360px;position:relative;}
      .ungani-chart-head{display:flex;align-items:flex-start;justify-content:space-between;gap:14px;margin-bottom:16px;}
      .ungani-chart-head h3{margin:0;font-size:20px;}
      .ungani-chart-head p{margin:5px 0 0;}
      .ungani-chart-canvas-wrap{position:relative;width:100%;height:270px;}
      .ungani-chart-canvas-wrap.small{height:230px;}
      .ungani-analytics-grid-2{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px;align-items:start;}
      .ungani-analytics-grid-3{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:18px;align-items:start;}
      .ungani-project-progress-card{border:1px solid var(--ungani-border);border-radius:20px;padding:14px;background:var(--ungani-soft);margin-bottom:12px;}
      .ungani-project-track{height:12px;border-radius:999px;background:rgba(6,28,61,0.10);overflow:hidden;margin:10px 0 7px;}
      html[data-ungani-theme="dark"] .ungani-project-track{background:rgba(255,255,255,0.11);}
      .ungani-project-fill{height:100%;border-radius:999px;background:linear-gradient(90deg,${COLORS.gold},${COLORS.green});}
      .ungani-rank-row{display:grid;grid-template-columns:44px minmax(0,1fr) auto;gap:12px;align-items:center;border-bottom:1px solid var(--ungani-border);padding:12px 0;}
      .ungani-rank-row:last-child{border-bottom:0;}
      .ungani-rank-number{width:38px;height:38px;border-radius:15px;background:${COLORS.gold};color:${COLORS.navy};display:inline-flex;align-items:center;justify-content:center;font-weight:950;}
      @media(max-width:1180px){.ungani-analytics-grid-2,.ungani-analytics-grid-3{grid-template-columns:1fr;}}
      @media(max-width:680px){.ungani-chart-card{min-height:auto;}.ungani-chart-head{flex-direction:column;}.ungani-chart-canvas-wrap{height:245px;}}
    `;
    document.head.appendChild(style);
  }

  function safeGet(row, fields, fallback) {
    if (!row) return fallback === undefined ? "" : fallback;

    for (let i = 0; i < fields.length; i++) {
      const key = fields[i];

      if (
        Object.prototype.hasOwnProperty.call(row, key) &&
        row[key] !== null &&
        row[key] !== undefined &&
        row[key] !== ""
      ) {
        return row[key];
      }
    }

    return fallback === undefined ? "" : fallback;
  }

  function moneyFormat(value) {
    const amount = Number(value || 0);

    if (window.UnganiClientShared && UnganiClientShared.formatKES) {
      return UnganiClientShared.formatKES(amount);
    }

    return "Ksh " + amount.toLocaleString("en-KE", { maximumFractionDigits: 0 });
  }

  function compactMoney(value) {
    const amount = Number(value || 0);
    const sign = amount < 0 ? "-" : "";
    const absolute = Math.abs(amount);

    if (absolute >= 1000000000) return "Ksh " + sign + trimDecimal(absolute / 1000000000) + "B";
    if (absolute >= 1000000) return "Ksh " + sign + trimDecimal(absolute / 1000000) + "M";
    if (absolute >= 1000) return "Ksh " + sign + trimDecimal(absolute / 1000) + "K";

    return moneyFormat(amount);
  }

  function trimDecimal(valueNumber) {
    const rounded = Math.round(valueNumber * 10) / 10;
    return Number.isInteger(rounded) ? String(rounded) : String(rounded);
  }

  function toTitle(value) {
    return String(value || "")
      .replace(/_/g, " ")
      .replace(/\w\S*/g, function (text) {
        return text.charAt(0).toUpperCase() + text.substr(1).toLowerCase();
      });
  }

  function isIncomeType(type) {
    const lower = String(type || "").toLowerCase();

    return (
      lower.includes("income") ||
      lower.includes("sale") ||
      lower.includes("rental") ||
      lower.includes("revenue") ||
      lower.includes("deposit") ||
      lower.includes("service fee") ||
      lower.includes("agency fee")
    );
  }

  function isExpenseType(type) {
    const lower = String(type || "").toLowerCase();

    return (
      lower.includes("expense") ||
      lower.includes("petty") ||
      lower.includes("cost") ||
      lower.includes("commission") ||
      lower.includes("maintenance")
    );
  }

  function calculateMoney(transactions) {
    let income = 0;
    let expenses = 0;
    let pending = 0;

    (transactions || []).forEach(function (row) {
      const amount = Number(safeGet(row, ["amount"], 0) || 0);
      const type = String(safeGet(row, ["transaction_type", "type"], "")).toLowerCase();
      const status = String(safeGet(row, ["status"], "completed")).toLowerCase();

      if (isIncomeType(type)) income += amount;
      else if (isExpenseType(type)) expenses += amount;

      if (status.includes("pending")) pending += amount;
    });

    return { income, expenses, pending, balance: income - expenses };
  }

  function calculateIncomeExpenseTrend(transactions) {
    const map = {};

    (transactions || []).forEach(function (row) {
      const amount = Number(safeGet(row, ["amount"], 0) || 0);
      const type = String(safeGet(row, ["transaction_type", "type"], "")).toLowerCase();
      const rawDate = safeGet(row, ["transaction_date", "created_at"], "");

      if (!rawDate) return;

      const date = new Date(rawDate);
      if (isNaN(date.getTime())) return;

      const key = date.getFullYear() + "-" + String(date.getMonth() + 1).padStart(2, "0");
      const label = date.toLocaleDateString("en-KE", { month: "short", year: "numeric" });

      if (!map[key]) {
        map[key] = { key, label, income: 0, expenses: 0, balance: 0 };
      }

      if (isIncomeType(type)) map[key].income += amount;
      else if (isExpenseType(type)) map[key].expenses += amount;

      map[key].balance = map[key].income - map[key].expenses;
    });

    return Object.keys(map).sort().map(function (key) { return map[key]; });
  }

  function normalizeExpenseCategory(category) {
    const lower = String(category || "Other Expense").toLowerCase();

    if (lower.includes("agent") && lower.includes("commission")) return "Agent Commission";
    if (lower.includes("marketing") || lower.includes("advertising")) return "Marketing / Advertising";
    if (lower.includes("legal") || lower.includes("documentation")) return "Legal / Documentation Fees";
    if (lower.includes("maintenance") || lower.includes("repair")) return "Maintenance / Repairs";
    if (lower.includes("staff") || lower.includes("wage")) return "Staff Wages";
    if (lower.includes("transport") || lower.includes("site visit")) return "Transport / Site Visit";
    if (lower.includes("material") || lower.includes("project")) return "Project / Material Cost";

    return category || "Other Expense";
  }

  function getExpenseCategoryColor(category) {
    const lower = String(category || "").toLowerCase();

    if (EXPENSE_CATEGORY_COLORS[lower]) return EXPENSE_CATEGORY_COLORS[lower];
    if (lower.includes("agent")) return EXPENSE_CATEGORY_COLORS["agent commission"];
    if (lower.includes("marketing") || lower.includes("advertising")) return EXPENSE_CATEGORY_COLORS["marketing / advertising"];
    if (lower.includes("legal") || lower.includes("documentation")) return EXPENSE_CATEGORY_COLORS["legal / documentation fees"];
    if (lower.includes("maintenance") || lower.includes("repair")) return EXPENSE_CATEGORY_COLORS["maintenance"];
    if (lower.includes("staff") || lower.includes("wage")) return EXPENSE_CATEGORY_COLORS["staff wages"];
    if (lower.includes("transport") || lower.includes("site visit")) return EXPENSE_CATEGORY_COLORS["transport"];
    if (lower.includes("material") || lower.includes("project")) return EXPENSE_CATEGORY_COLORS["project material cost"];

    return COLORS.slate;
  }

  function calculateExpenseBreakdown(transactions) {
    const map = {};

    (transactions || []).forEach(function (row) {
      const amount = Number(safeGet(row, ["amount"], 0) || 0);
      const type = String(safeGet(row, ["transaction_type", "type"], "")).toLowerCase();

      if (!isExpenseType(type)) return;

      const category = normalizeExpenseCategory(safeGet(row, ["category_name", "category", "category_key"], "Other Expense"));
      map[category] = (map[category] || 0) + amount;
    });

    return Object.keys(map).map(function (key) {
      return { label: key, value: Number(map[key] || 0), color: getExpenseCategoryColor(key) };
    }).sort(function (a, b) {
      return b.value - a.value;
    });
  }

  function calculateStatus(rows, fields) {
    const map = {};

    (rows || []).forEach(function (row) {
      const status = safeGet(row, fields, "Unknown");
      map[status] = (map[status] || 0) + 1;
    });

    return mapToRows(map);
  }

  function calculatePropertySummary(items) {
    let available = 0;
    let closed = 0;
    let reserved = 0;
    let negotiation = 0;

    (items || []).forEach(function (row) {
      const status = String(safeGet(row, ["property_status", "item_status", "status"], "available")).toLowerCase();

      if (status.includes("available") || status.includes("in stock") || status.includes("active")) available++;
      if (status.includes("sold") || status.includes("rented") || status.includes("closed") || status.includes("completed")) closed++;
      if (status.includes("reserved")) reserved++;
      if (status.includes("negotiation") || status.includes("progress")) negotiation++;
    });

    return { total: (items || []).length, available, closed, reserved, negotiation };
  }

  function calculatePeopleRoleSummary(people, profile) {
    const primaryTypes = profile.peoplePrimaryTypes || window.UnganiBusinessConfig.GENERAL.peoplePrimaryTypes;
    const secondaryTypes = profile.peopleSecondaryTypes || window.UnganiBusinessConfig.GENERAL.peopleSecondaryTypes;

    let primary = 0;
    let secondary = 0;

    (people || []).forEach(function (row) {
      const type = String(safeGet(row, ["person_type"], "")).toLowerCase();

      if (primaryTypes.includes(type)) primary++;
      if (secondaryTypes.includes(type)) secondary++;
    });

    return {
      total: (people || []).length,
      primary,
      secondary,
      primaryLabel: profile.peoplePrimary,
      secondaryLabel: profile.peopleSecondary
    };
  }

  function calculateTaskSummary(tasks) {
    const today = new Date().toISOString().slice(0, 10);
    let pending = 0;
    let overdue = 0;
    let completed = 0;
    let inProgress = 0;

    (tasks || []).forEach(function (row) {
      const status = String(safeGet(row, ["status"], "pending")).toLowerCase();
      const due = String(safeGet(row, ["due_date"], "")).slice(0, 10);

      if (status.includes("completed")) completed++;
      else if (status.includes("progress")) inProgress++;
      else if (!status.includes("cancelled")) pending++;

      if (due && due < today && !status.includes("completed") && !status.includes("cancelled")) overdue++;
    });

    return { pending, overdue, completed, inProgress };
  }

  function calculateProjects(items) {
    const map = {};

    (items || []).forEach(function (row) {
      const project = safeGet(row, ["project_name"], "");
      if (!project) return;

      if (!map[project]) {
        map[project] = {
          name: project,
          count: 0,
          totalUnits: 0,
          unitsSold: 0,
          unitsAvailable: 0,
          progressTotal: 0,
          progressCount: 0,
          value: 0
        };
      }

      const item = map[project];
      item.count += 1;
      item.totalUnits += Number(safeGet(row, ["total_units"], 0) || 0);
      item.unitsSold += Number(safeGet(row, ["units_sold"], 0) || 0);
      item.unitsAvailable += Number(safeGet(row, ["units_available"], 0) || 0);
      item.value += Number(safeGet(row, ["property_price", "selling_price", "cost_price"], 0) || 0);

      const progress = Number(safeGet(row, ["project_progress_percent"], 0) || 0);
      if (progress > 0) {
        item.progressTotal += progress;
        item.progressCount += 1;
      }
    });

    return Object.keys(map).map(function (key) {
      const item = map[key];

      if (item.progressCount > 0) item.progress = Math.round(item.progressTotal / item.progressCount);
      else if (item.totalUnits > 0) item.progress = Math.round((item.unitsSold / item.totalUnits) * 100);
      else item.progress = 0;

      item.progress = Math.max(0, Math.min(100, item.progress));
      return item;
    }).sort(function (a, b) {
      return b.value - a.value;
    });
  }

  function calculateAgentPerformance(people, profile) {
    const primaryTypes = profile.peoplePrimaryTypes || window.UnganiBusinessConfig.GENERAL.peoplePrimaryTypes;

    const rows = (people || []).filter(function (row) {
      const type = String(safeGet(row, ["person_type"], "")).toLowerCase();
      return primaryTypes.includes(type);
    });

    rows.sort(function (a, b) {
      const aDeals = Number(safeGet(a, ["deals_closed"], 0) || 0);
      const bDeals = Number(safeGet(b, ["deals_closed"], 0) || 0);
      const aCommission = Number(safeGet(a, ["commission_earned_month"], 0) || 0);
      const bCommission = Number(safeGet(b, ["commission_earned_month"], 0) || 0);

      return (bDeals * 1000000 + bCommission) - (aDeals * 1000000 + aCommission);
    });

    return rows.slice(0, 6);
  }

  function calculateLeadPipeline(people, records, profile) {
    const map = {};
    const secondaryTypes = profile.peopleSecondaryTypes || window.UnganiBusinessConfig.GENERAL.peopleSecondaryTypes;

    (people || []).forEach(function (row) {
      const type = String(safeGet(row, ["person_type"], "")).toLowerCase();

      if (secondaryTypes.length && !secondaryTypes.includes(type) && type) return;

      let stage = safeGet(row, ["lead_status", "relationship_status", "status"], "");

      if (!stage) stage = type || "Contact";

      map[stage] = (map[stage] || 0) + 1;
    });

    (records || []).forEach(function (row) {
      const stage = safeGet(row, ["lead_status", "deal_status", "status"], "");
      const recordType = String(safeGet(row, ["record_type"], "")).toLowerCase();

      if (stage || recordType.includes("lead") || recordType.includes("inquiry") || recordType.includes("booking") || recordType.includes("order")) {
        map[stage || "Record"] = (map[stage || "Record"] || 0) + 1;
      }
    });

    return mapToRows(map);
  }

  function mapToRows(map) {
    return Object.keys(map).map(function (key) {
      return { label: key, value: Number(map[key] || 0) };
    }).sort(function (a, b) {
      return b.value - a.value;
    });
  }

  function getMeaningColor(label) {
    const lower = String(label || "").toLowerCase();

    if (
      lower.includes("income") ||
      lower.includes("available") ||
      lower.includes("in stock") ||
      lower.includes("completed") ||
      lower.includes("closed") ||
      lower.includes("sold") ||
      lower.includes("rented") ||
      lower.includes("resolved") ||
      lower.includes("active")
    ) return COLORS.green;

    if (
      lower.includes("urgent") ||
      lower.includes("overdue") ||
      lower.includes("lost") ||
      lower.includes("cancelled") ||
      lower.includes("failed") ||
      lower.includes("low stock")
    ) return COLORS.red;

    if (lower.includes("legal") || lower.includes("document")) return COLORS.violet;
    if (lower.includes("maintenance") || lower.includes("repair")) return COLORS.teal;
    if (lower.includes("marketing") || lower.includes("advertising")) return COLORS.blue;

    return COLORS.gold;
  }

  function chartTextColor() {
    return document.documentElement.dataset.unganiTheme === "dark" ? "#F5F5F3" : "#061C3D";
  }

  function chartGridColor() {
    return document.documentElement.dataset.unganiTheme === "dark" ? "rgba(255,255,255,0.12)" : "rgba(6,28,61,0.10)";
  }

  function baseChartOptions(extraOptions) {
    const options = {
      responsive: true,
      maintainAspectRatio: false,
      animation: { duration: 1200, easing: "easeOutQuart" },
      interaction: { mode: "index", intersect: false },
      plugins: {
        legend: {
          labels: {
            color: chartTextColor(),
            usePointStyle: true,
            boxWidth: 8,
            font: { family: "Inter, system-ui, sans-serif", size: 12, weight: "700" }
          }
        },
        tooltip: {
          backgroundColor: COLORS.navy,
          titleColor: COLORS.white,
          bodyColor: COLORS.white,
          borderColor: COLORS.gold,
          borderWidth: 1,
          padding: 12,
          displayColors: true,
          callbacks: {}
        }
      },
      scales: {
        x: {
          ticks: { color: chartTextColor(), font: { family: "Inter, system-ui, sans-serif", weight: "700" } },
          grid: { color: "transparent" }
        },
        y: {
          ticks: { color: chartTextColor(), font: { family: "Inter, system-ui, sans-serif", weight: "700" } },
          grid: { color: chartGridColor() }
        }
      }
    };

    return deepMerge(options, extraOptions || {});
  }

  function deepMerge(target, source) {
    const output = Object.assign({}, target);

    Object.keys(source || {}).forEach(function (key) {
      if (
        source[key] &&
        typeof source[key] === "object" &&
        !Array.isArray(source[key]) &&
        !(source[key] instanceof Function)
      ) {
        output[key] = deepMerge(output[key] || {}, source[key]);
      } else {
        output[key] = source[key];
      }
    });

    return output;
  }

  async function createChart(canvasId, config) {
    await loadChartJs();

    const canvas = document.getElementById(canvasId);
    if (!canvas) return null;

    if (chartInstances[canvasId]) chartInstances[canvasId].destroy();

    chartInstances[canvasId] = new Chart(canvas, config);
    return chartInstances[canvasId];
  }

  async function renderIncomeExpenseChart(canvasId, trendRows) {
    const rows = (trendRows || []).filter(function (row) {
      return Number(row.income || 0) !== 0 || Number(row.expenses || 0) !== 0;
    });

    if (rows.length === 0) return;

    return createChart(canvasId, {
      type: "bar",
      data: {
        labels: rows.map(function (row) { return row.label; }),
        datasets: [
          { label: "Income", data: rows.map(function (row) { return Number(row.income || 0); }), backgroundColor: COLORS.green, borderRadius: 10 },
          { label: "Expenses", data: rows.map(function (row) { return Number(row.expenses || 0); }), backgroundColor: COLORS.gold, borderRadius: 10 },
          { label: "Balance", data: rows.map(function (row) { return Number(row.balance || 0); }), type: "line", borderColor: COLORS.navy, backgroundColor: COLORS.navy, tension: 0.35, pointRadius: 4, pointHoverRadius: 7 }
        ]
      },
      options: baseChartOptions({
        plugins: {
          tooltip: {
            callbacks: {
              label: function (context) {
                return context.dataset.label + ": " + moneyFormat(context.raw);
              }
            }
          }
        },
        scales: {
          y: {
            ticks: {
              callback: function (value) {
                return compactMoney(value);
              }
            }
          }
        }
      })
    });
  }

  async function renderExpenseDonutChart(canvasId, rows) {
    const cleanRows = (rows || []).filter(function (row) {
      return Number(row.value || 0) > 0;
    });

    if (cleanRows.length === 0) return;

    return createChart(canvasId, {
      type: "doughnut",
      data: {
        labels: cleanRows.map(function (row) { return row.label; }),
        datasets: [
          {
            data: cleanRows.map(function (row) { return Number(row.value || 0); }),
            backgroundColor: cleanRows.map(function (row) { return row.color || getExpenseCategoryColor(row.label); }),
            borderColor: "#FFFFFF",
            borderWidth: 3,
            hoverOffset: 12
          }
        ]
      },
      options: baseChartOptions({
        cutout: "64%",
        plugins: {
          tooltip: {
            callbacks: {
              label: function (context) {
                const total = context.dataset.data.reduce(function (sum, value) {
                  return sum + Number(value || 0);
                }, 0);

                const value = Number(context.raw || 0);
                const percent = total > 0 ? Math.round((value / total) * 100) : 0;

                return context.label + ": " + moneyFormat(value) + " (" + percent + "%)";
              }
            }
          }
        },
        scales: {}
      })
    });
  }

  async function renderDoughnutStatusChart(canvasId, rows) {
    const cleanRows = (rows || []).filter(function (row) {
      return Number(row.value || 0) > 0;
    });

    if (cleanRows.length === 0) return;

    return createChart(canvasId, {
      type: "doughnut",
      data: {
        labels: cleanRows.map(function (row) { return toTitle(row.label); }),
        datasets: [
          {
            data: cleanRows.map(function (row) { return Number(row.value || 0); }),
            backgroundColor: cleanRows.map(function (row) { return getMeaningColor(row.label); }),
            borderColor: "#FFFFFF",
            borderWidth: 3,
            hoverOffset: 12
          }
        ]
      },
      options: baseChartOptions({
        cutout: "62%",
        plugins: {
          tooltip: {
            callbacks: {
              label: function (context) {
                return context.label + ": " + context.raw;
              }
            }
          }
        },
        scales: {}
      })
    });
  }

  async function renderHorizontalBarChart(canvasId, rows, labelName) {
    const cleanRows = (rows || []).filter(function (row) {
      return Number(row.value || 0) > 0;
    }).slice(0, 8);

    if (cleanRows.length === 0) return;

    return createChart(canvasId, {
      type: "bar",
      data: {
        labels: cleanRows.map(function (row) { return toTitle(row.label); }),
        datasets: [
          {
            label: labelName || "Count",
            data: cleanRows.map(function (row) { return Number(row.value || 0); }),
            backgroundColor: cleanRows.map(function (row) { return getMeaningColor(row.label); }),
            borderRadius: 10
          }
        ]
      },
      options: baseChartOptions({
        indexAxis: "y",
        plugins: { legend: { display: false } },
        scales: {
          x: { beginAtZero: true, ticks: { precision: 0, color: chartTextColor() }, grid: { color: chartGridColor() } },
          y: { ticks: { color: chartTextColor() }, grid: { color: "transparent" } }
        }
      })
    });
  }

  function emptyChart(message) {
    return `
      <div class="ungani-empty">
        <h3>No chart data yet</h3>
        <p>${escapeHtml(message || "Add records to see this chart.")}</p>
      </div>
    `;
  }

  function escapeHtml(value) {
    return String(value === null || value === undefined ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  window.UnganiAnalytics = {
    COLORS,
    get BUSINESS_PROFILES() { return window.UnganiBusinessConfig.TYPES; },
    get GENERAL_PROFILE() { return window.UnganiBusinessConfig.GENERAL; },
    EXPENSE_CATEGORY_COLORS,

    getBusinessProfile,

    loadChartJs,
    injectChartStyles,
    createChart,

    safeGet,
    moneyFormat,
    compactMoney,
    toTitle,

    calculateMoney,
    calculateIncomeExpenseTrend,
    calculateExpenseBreakdown,
    calculateStatus,
    calculatePropertySummary,
    calculatePeopleRoleSummary,
    calculateTaskSummary,
    calculateProjects,
    calculateAgentPerformance,
    calculateLeadPipeline,
    mapToRows,

    normalizeExpenseCategory,
    getExpenseCategoryColor,
    getMeaningColor,

    renderIncomeExpenseChart,
    renderExpenseDonutChart,
    renderDoughnutStatusChart,
    renderHorizontalBarChart,
    emptyChart
  };
})();
