(function () {
  const VERSION = "portal14ab";

  const CARD_LINKS = {
    totalClients: "admin.html?v=portal14ab",
    approvedRegistrations: "admin.html?v=portal14ab",
    pendingRegistrations: "admin.html?v=portal14ab",
    openSupportIssues: "admin.html?v=portal14ab",
    unreadNotifications: "admin-home.html?v=portal14ab",
    warningLogs: "admin-health.html?v=portal14ab",
    pendingEmails: "admin-email-queue.html?v=portal14ab",
    failedEmails: "admin-email-queue.html?v=portal14ab"
  };

  const CARD_TITLES = {
    totalClients: "Open Client Admin",
    approvedRegistrations: "Open approved clients",
    pendingRegistrations: "Open pending registrations",
    openSupportIssues: "Open client support issues",
    unreadNotifications: "Open admin notifications",
    warningLogs: "Open system health",
    pendingEmails: "Open email queue",
    failedEmails: "Open failed email records"
  };

  function injectStyles() {
    if (document.getElementById("ungani-launch-card-links-style")) return;

    const style = document.createElement("style");
    style.id = "ungani-launch-card-links-style";
    style.textContent = `
      .card.ungani-launch-clickable-card {
        cursor: pointer !important;
        position: relative !important;
      }

      .card.ungani-launch-clickable-card:hover {
        transform: translateY(-3px) !important;
        border-color: rgba(212, 166, 58, 0.52) !important;
        box-shadow: 0 24px 65px rgba(0, 0, 0, 0.36) !important;
      }

      .card.ungani-launch-clickable-card::before {
        content: "Open";
        position: absolute;
        top: 12px;
        right: 12px;
        font-size: 10px;
        font-weight: 900;
        letter-spacing: 0.08em;
        text-transform: uppercase;
        color: #061C3D;
        background: linear-gradient(135deg, #D4A63A, #F0C85A);
        border-radius: 999px;
        padding: 5px 8px;
        opacity: 0;
        transition: 0.18s ease;
        z-index: 2;
      }

      .card.ungani-launch-clickable-card:hover::before {
        opacity: 1;
      }
    `;

    document.head.appendChild(style);
  }

  function makeCardsClickable() {
    injectStyles();

    Object.keys(CARD_LINKS).forEach((id) => {
      const valueEl = document.getElementById(id);
      if (!valueEl) return;

      const card = valueEl.closest(".card");
      if (!card) return;

      const url = CARD_LINKS[id];

      card.classList.add("ungani-launch-clickable-card");
      card.setAttribute("role", "link");
      card.setAttribute("tabindex", "0");
      card.setAttribute("title", CARD_TITLES[id] || "Open");
      card.setAttribute("data-ungani-card-link", url);
      card.setAttribute("data-ungani-card-link-version", VERSION);

      card.onclick = function () {
        window.location.href = url;
      };

      card.onkeydown = function (event) {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          window.location.href = url;
        }
      };
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", makeCardsClickable);
  } else {
    makeCardsClickable();
  }
})();
