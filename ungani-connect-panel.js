// UNGANI OS: shared Ungani Connect record panel (Discussion + Timeline +
// optional Attachments), built on Phase 0's foundation
// (ungani_record_comments/ungani_record_activity/can_access_ungani_record/
// add_ungani_record_comment/log_ungani_record_activity).
//
// First built bespoke inside my-tasks.html for Phase 2 (Tasks). Phase 3
// rolls the same panel out to 3 more record types (Payments/Documents/
// People) that all already load client-shared.js - extracted here once,
// rather than copy-pasting ~350 lines into each page 3 more times.
// Employees (my-team-access.html) does NOT use this module - that page
// deliberately never loads client-shared.js (same standalone-shell
// pattern as client.html), so it has its own bespoke implementation
// calling the same underlying RPCs directly.
//
// Usage: UnganiConnectPanel.open(context, {
//   recordTable: "transactions", recordId: row.id, title: "...",
//   subtitleHtml: "...", attachments: { linkColumn: "linked_transaction_id",
//   deepLinkParam: "linkedTransactionId" } // or null to omit the tab
// })
// `context` is whatever the host page's UnganiClientShared.initPage()
// onReady callback received (needs .supabaseClient, .tenantId, .authUser,
// .userProfile - the exact same shape every host page already has).
(function () {
  let activeCtx = null;
  let activeOptions = null;

  function injectStylesOnce() {
    if (document.getElementById("unganiConnectPanelStyles")) return;

    const style = document.createElement("style");
    style.id = "unganiConnectPanelStyles";
    style.textContent = `
      .ucp-list {
        display: grid;
        gap: 10px;
      }

      .ucp-item {
        position: relative;
        display: grid;
        grid-template-columns: 36px minmax(0, 1fr);
        gap: 12px;
        align-items: center;
        padding: 12px 12px 12px 14px;
        border: 1px solid var(--ungani-border, rgba(6,28,61,0.1));
        background: var(--ungani-soft, rgba(6,28,61,0.03));
        border-radius: 14px;
        border-left: 3px solid var(--accent, var(--ungani-muted, #64748B));
      }

      .ucp-icon {
        width: 36px;
        height: 36px;
        border-radius: 12px;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        font-size: 16px;
        background: var(--ungani-card, #FFFFFF);
      }

      .ucp-item strong {
        display: block;
        font-size: 13.5px;
      }

      .ucp-item p {
        margin: 2px 0 0;
        color: var(--ungani-muted, #6B7280);
        font-size: 12px;
        line-height: 1.4;
      }

      .ucp-time {
        grid-column: 2;
        justify-self: start;
        white-space: nowrap;
      }

      .ucp-doc-row {
        display: grid;
        grid-template-columns: 36px minmax(0, 1fr);
        gap: 12px;
        align-items: center;
        padding: 12px 12px 12px 14px;
        border: 1px solid var(--ungani-border, rgba(6,28,61,0.1));
        background: var(--ungani-soft, rgba(6,28,61,0.03));
        border-radius: 14px;
        text-decoration: none;
        color: inherit;
        transition: 0.18s ease;
      }

      .ucp-doc-row:hover {
        transform: translateY(-2px);
        box-shadow: 0 14px 30px var(--ungani-shadow, rgba(6,28,61,0.1));
      }

      .ucp-doc-row strong {
        display: block;
        font-size: 13.5px;
      }
    `;
    document.head.appendChild(style);
  }

  function isMe(authUserId) {
    return authUserId && activeCtx && activeCtx.authUser && authUserId === activeCtx.authUser.id;
  }

  async function open(context, options) {
    activeCtx = context;
    activeOptions = options;

    injectStylesOnce();

    UnganiClientShared.openSidePanel({
      title: options.title || "Discussion",
      bodyHtml: UnganiClientShared.loadingCard("Loading discussion...")
    });

    render();
  }

  function render() {
    const options = activeOptions;

    document.getElementById("unganiPanelTitle").innerText = options.title || "Discussion";

    document.getElementById("unganiPanelBody").innerHTML = `
      ${options.subtitleHtml ? `<div class="ungani-card">${options.subtitleHtml}</div>` : ""}

      <div class="ungani-card" style="margin-top:${options.subtitleHtml ? "18px" : "0"};">
        <div class="ungani-section-title">
          <div>
            <h3>Discussion</h3>
            <p class="ungani-small">Comments visible to anyone who can see this record.</p>
          </div>
        </div>

        <div id="ucpDiscussionList" class="ucp-list">
          <p class="ungani-small">Loading comments...</p>
        </div>

        <form onsubmit="UnganiConnectPanel.postComment(event)" style="margin-top:12px;display:flex;gap:8px;align-items:flex-end;">
          <textarea id="ucpCommentInput" rows="2" placeholder="Write a comment..." style="flex:1;" required></textarea>
          <button class="ungani-btn gold" type="submit">Post</button>
        </form>
      </div>

      ${options.attachments ? `
        <div class="ungani-card" style="margin-top:18px;">
          <div class="ungani-section-title">
            <div>
              <h3>Attachments</h3>
              <p class="ungani-small">Documents linked to this record.</p>
            </div>
            <a class="ungani-btn small gold" href="${UnganiClientShared.attr("my-documents.html?action=add&" + options.attachments.deepLinkParam + "=" + encodeURIComponent(options.recordId))}">Attach Document</a>
          </div>

          <div id="ucpAttachmentsList" class="ucp-list">
            <p class="ungani-small">Loading documents...</p>
          </div>
        </div>
      ` : ""}

      <div class="ungani-card" style="margin-top:18px;">
        <div class="ungani-section-title">
          <div>
            <h3>Activity Timeline</h3>
            <p class="ungani-small">Everything logged against this record, newest first.</p>
          </div>
        </div>

        <div id="ucpTimelineList" class="ucp-list">
          <p class="ungani-small">Loading activity...</p>
        </div>
      </div>
    `;

    loadComments();
    if (options.attachments) loadAttachments();
    loadTimeline();
  }

  async function loadComments() {
    const container = document.getElementById("ucpDiscussionList");
    if (!container) return;

    let response;

    try {
      response = await activeCtx.supabaseClient
        .from("ungani_record_comments")
        .select("id, author_name, body, created_at")
        .eq("record_table", activeOptions.recordTable)
        .eq("record_id", activeOptions.recordId)
        .is("deleted_at", null)
        .order("created_at", { ascending: true });
    } catch (error) {
      container.innerHTML = `<p class="ungani-small">Could not load comments.</p>`;
      return;
    }

    if (response.error) {
      container.innerHTML = `<p class="ungani-small">Could not load comments.</p>`;
      return;
    }

    renderComments(response.data || []);
  }

  function renderComments(rows) {
    const container = document.getElementById("ucpDiscussionList");
    if (!container) return;

    if (!rows.length) {
      container.innerHTML = `<p class="ungani-small">No comments yet - start the discussion below.</p>`;
      return;
    }

    container.innerHTML = rows.map(function (row) {
      return `
        <div class="ucp-item">
          <div class="ucp-icon">💬</div>
          <div>
            <strong>${UnganiClientShared.safe(row.author_name || "Someone")}</strong>
            <p style="white-space:pre-wrap;">${UnganiClientShared.safe(row.body)}</p>
          </div>
          <span class="ungani-small ucp-time">${UnganiClientShared.safe(UnganiClientShared.formatDateTime(row.created_at))}</span>
        </div>
      `;
    }).join("");
  }

  async function postComment(event) {
    event.preventDefault();

    const input = document.getElementById("ucpCommentInput");
    const body = input ? String(input.value || "").trim() : "";
    if (!body) return;

    const submitBtn = event.submitter || (event.target.querySelector && event.target.querySelector('button[type="submit"]'));

    await UnganiClientShared.withButtonLoading(submitBtn, async () => {
      let response;

      try {
        response = await activeCtx.supabaseClient.rpc("add_ungani_record_comment", {
          p_record_table: activeOptions.recordTable,
          p_record_id: activeOptions.recordId,
          p_body: body
        });
      } catch (error) {
        UnganiClientShared.showToast("Could not post comment: " + (error.message || "Network error. Please check your connection."));
        return;
      }

      if (response.error || !response.data || response.data.ok !== true) {
        UnganiClientShared.showToast((response.data && response.data.message) || (response.error && response.error.message) || "Could not post comment.");
        return;
      }

      if (input) input.value = "";
      await loadComments();
      await loadTimeline();
    });
  }

  async function loadAttachments() {
    const container = document.getElementById("ucpAttachmentsList");
    if (!container || !activeOptions.attachments) return;

    let response;

    try {
      response = await activeCtx.supabaseClient
        .from("documents")
        .select("id, document_title, document_type, document_date, file_url")
        .eq(activeOptions.attachments.linkColumn, activeOptions.recordId)
        .eq("tenant_id", activeCtx.tenantId)
        .order("document_date", { ascending: false });
    } catch (error) {
      container.innerHTML = `<p class="ungani-small">Could not load documents.</p>`;
      return;
    }

    if (response.error) {
      container.innerHTML = `<p class="ungani-small">Could not load documents.</p>`;
      return;
    }

    renderAttachments(response.data || []);
  }

  function toTitle(value) {
    return String(value || "").replace(/\b\w/g, function (c) { return c.toUpperCase(); });
  }

  function renderAttachments(rows) {
    const container = document.getElementById("ucpAttachmentsList");
    if (!container) return;

    if (!rows.length) {
      container.innerHTML = `<p class="ungani-small">No documents linked yet - use "Attach Document" above to add one.</p>`;
      return;
    }

    container.innerHTML = rows.map(function (row) {
      const title = UnganiClientShared.getValue(row, ["document_title"], "Document");
      const docType = UnganiClientShared.getValue(row, ["document_type"], "Document");
      const editHref = "my-documents.html?highlight=" + encodeURIComponent(row.id);

      return `
        <a class="ucp-doc-row" href="${UnganiClientShared.attr(row.file_url || editHref)}"${row.file_url ? ' target="_blank" rel="noopener noreferrer"' : ""}>
          <span class="ucp-icon">📄</span>
          <span>
            <strong>${UnganiClientShared.safe(title)}</strong>
            <span class="ungani-small">${UnganiClientShared.safe(toTitle(docType))} · ${UnganiClientShared.safe(UnganiClientShared.formatDate(row.document_date))}</span>
          </span>
        </a>
      `;
    }).join("");
  }

  async function loadTimeline() {
    const container = document.getElementById("ucpTimelineList");
    if (!container) return;

    let response;

    try {
      response = await activeCtx.supabaseClient
        .from("ungani_record_activity")
        .select("id, event_type, description, actor_name, created_at")
        .eq("record_table", activeOptions.recordTable)
        .eq("record_id", activeOptions.recordId)
        .order("created_at", { ascending: false })
        .limit(30);
    } catch (error) {
      container.innerHTML = `<p class="ungani-small">Could not load activity history.</p>`;
      return;
    }

    if (response.error) {
      container.innerHTML = `<p class="ungani-small">Could not load activity history.</p>`;
      return;
    }

    renderTimeline(response.data || []);
  }

  const TIMELINE_ICONS = {
    created: "✨",
    status_changed: "🔄",
    assigned: "👤",
    commented: "💬"
  };

  function renderTimeline(rows) {
    const container = document.getElementById("ucpTimelineList");
    if (!container) return;

    if (!rows.length) {
      container.innerHTML = `<p class="ungani-small">No activity logged yet - creating, commenting on, or updating this record will show up here.</p>`;
      return;
    }

    container.innerHTML = rows.map(function (row) {
      const icon = TIMELINE_ICONS[row.event_type] || "•";

      return `
        <div class="ucp-item">
          <div class="ucp-icon">${icon}</div>
          <div>
            <p>${UnganiClientShared.safe(row.description || "")}${row.actor_name ? " · " + UnganiClientShared.safe(row.actor_name) : ""}</p>
          </div>
          <span class="ungani-small ucp-time">${UnganiClientShared.safe(UnganiClientShared.formatDateTime(row.created_at))}</span>
        </div>
      `;
    }).join("");
  }

  // Best-effort, non-blocking helper for host pages to log a real
  // Timeline event from their own save paths (created/status changed/
  // reassigned) - mirrors my-tasks.html's logTaskActivity(), generalized.
  async function logActivity(context, recordTable, recordId, eventType, description) {
    if (!recordId) return;

    try {
      await context.supabaseClient.rpc("log_ungani_record_activity", {
        p_record_table: recordTable,
        p_record_id: recordId,
        p_event_type: eventType,
        p_description: description
      });
    } catch (error) {
      console.warn("Could not log activity:", error.message);
    }
  }

  window.UnganiConnectPanel = {
    open: open,
    postComment: postComment,
    logActivity: logActivity
  };
})();
