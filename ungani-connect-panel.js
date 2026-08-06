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
  // Ungani Connect Phase 4: mentions. Roster reuses the same
  // get_my_ungani_team_members_for_assignment() RPC already established
  // as the canonical reusable roster source (team-chat-shared.js,
  // my-documents.html's Staff Member linking). pendingMentions holds
  // {id (auth_user_id), name} for the CURRENT draft comment only -
  // cleared after a successful post or when the panel re-opens.
  let roster = { owner: null, members: [] };
  let pendingMentions = [];

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

      .ucp-mention-chips {
        display: flex;
        flex-wrap: wrap;
        gap: 6px;
      }

      .ucp-mention-chip {
        display: inline-flex;
        align-items: center;
        gap: 5px;
        background: rgba(212,166,58,0.16);
        color: var(--ungani-navy, #061C3D);
        border-radius: 999px;
        padding: 4px 10px;
        font-size: 11.5px;
        font-weight: 700;
      }

      .ucp-mention-chip button {
        border: none;
        background: transparent;
        color: inherit;
        cursor: pointer;
        font-size: 11px;
        padding: 0;
        line-height: 1;
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
    pendingMentions = [];

    injectStylesOnce();

    UnganiClientShared.openSidePanel({
      title: options.title || "Discussion",
      bodyHtml: UnganiClientShared.loadingCard("Loading discussion...")
    });

    await loadRoster();
    render();
  }

  async function loadRoster() {
    try {
      const response = await activeCtx.supabaseClient.rpc("get_my_ungani_team_members_for_assignment");
      if (!response.error && response.data && response.data.ok === true) {
        roster = { owner: response.data.owner || null, members: response.data.members || [] };
      }
    } catch (error) {
      console.warn("Could not load roster for mentions:", error.message);
    }
  }

  function mentionCandidates() {
    const candidates = [];
    const myAuthId = activeCtx && activeCtx.authUser ? activeCtx.authUser.id : null;

    if (roster.owner && roster.owner.auth_user_id && roster.owner.auth_user_id !== myAuthId) {
      candidates.push({ id: roster.owner.auth_user_id, name: (roster.owner.full_name || "Owner") + " (Owner)" });
    }

    roster.members.forEach(function (m) {
      if (!m.auth_user_id || m.auth_user_id === myAuthId) return;
      candidates.push({ id: m.auth_user_id, name: m.full_name + (m.role_key ? " (" + m.role_key + ")" : "") });
    });

    return candidates.filter(function (c) {
      return !pendingMentions.some(function (p) { return p.id === c.id; });
    });
  }

  function addMention(authUserId) {
    if (!authUserId) return;

    const candidate = mentionCandidates().find(function (c) { return c.id === authUserId; });
    if (!candidate) return;

    pendingMentions.push({ id: candidate.id, name: candidate.name.replace(/\s*\([^)]*\)\s*$/, "") });

    const input = document.getElementById("ucpCommentInput");
    if (input) {
      const current = input.value || "";
      input.value = (current && !/\s$/.test(current) ? current + " " : current) + "@" + pendingMentions[pendingMentions.length - 1].name + " ";
      input.focus();
    }

    renderMentionPicker();
    renderMentionChips();
  }

  function removeMention(authUserId) {
    pendingMentions = pendingMentions.filter(function (p) { return p.id !== authUserId; });
    renderMentionPicker();
    renderMentionChips();
  }

  function renderMentionPicker() {
    const picker = document.getElementById("ucpMentionPicker");
    if (!picker) return;

    const candidates = mentionCandidates();

    picker.innerHTML = `
      <option value="">+ Mention someone...</option>
      ${candidates.map(function (c) {
        return `<option value="${UnganiClientShared.attr(c.id)}">${UnganiClientShared.safe(c.name)}</option>`;
      }).join("")}
    `;
    picker.style.display = candidates.length ? "" : "none";
  }

  function renderMentionChips() {
    const container = document.getElementById("ucpMentionChips");
    if (!container) return;

    if (!pendingMentions.length) {
      container.innerHTML = "";
      return;
    }

    container.innerHTML = pendingMentions.map(function (m) {
      return `<span class="ucp-mention-chip">@${UnganiClientShared.safe(m.name)} <button type="button" onclick="UnganiConnectPanel.removeMention('${UnganiClientShared.attr(m.id)}')" aria-label="Remove mention">✕</button></span>`;
    }).join("");
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

        <div id="ucpMentionChips" class="ucp-mention-chips" style="margin-top:8px;"></div>

        <form onsubmit="UnganiConnectPanel.postComment(event)" style="margin-top:8px;display:flex;gap:8px;align-items:flex-end;flex-wrap:wrap;">
          <textarea id="ucpCommentInput" rows="2" placeholder="Write a comment... use + Mention to notify someone directly" style="flex:1;min-width:200px;" required></textarea>
          <select id="ucpMentionPicker" onchange="UnganiConnectPanel.addMention(this.value); this.value='';" style="border-radius:10px;border:1px solid var(--ungani-border,rgba(6,28,61,0.16));padding:8px;font-size:12.5px;"></select>
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
    renderMentionPicker();
    renderMentionChips();
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

    const mentionedUserIds = pendingMentions.map(function (m) { return m.id; });

    await UnganiClientShared.withButtonLoading(submitBtn, async () => {
      let response;

      try {
        response = await activeCtx.supabaseClient.rpc("add_ungani_record_comment", {
          p_record_table: activeOptions.recordTable,
          p_record_id: activeOptions.recordId,
          p_body: body,
          p_mentioned_user_ids: mentionedUserIds
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
      pendingMentions = [];
      renderMentionPicker();
      renderMentionChips();

      // Ungani Connect Phase 4: Smart Notifications - best-effort,
      // non-blocking, same "the real action already succeeded, this is
      // additive" pattern as notifyTaskAssignment(). The RPC re-derives
      // the recipient set (mentions + the record's relevant party, if
      // any) server-side from the real comment row - nothing here is
      // trusted client-side content.
      const commentId = response.data.comment_id;

      if (commentId) {
        try {
          await activeCtx.supabaseClient.rpc("notify_ungani_record_comment", { p_comment_id: commentId });
        } catch (error) {
          console.warn("Could not send comment notification:", error.message);
        }

        UnganiClientShared.triggerEmailSendNow();
        UnganiClientShared.triggerEventPush("record_comment", commentId);
      }

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
  // Returns the RPC's response data (now includes activity_id, Phase 4)
  // so callers can chain a Smart Notification off a real, persisted row.
  async function logActivity(context, recordTable, recordId, eventType, description) {
    if (!recordId) return null;

    try {
      const response = await context.supabaseClient.rpc("log_ungani_record_activity", {
        p_record_table: recordTable,
        p_record_id: recordId,
        p_event_type: eventType,
        p_description: description
      });
      return response.data || null;
    } catch (error) {
      console.warn("Could not log activity:", error.message);
      return null;
    }
  }

  // Ungani Connect Phase 4: Smart Notification for a status change -
  // call AFTER logActivity() with event_type "status_changed" succeeds.
  // Best-effort/non-blocking, same pattern as notifyTaskAssignment().
  // The RPC itself decides whether anyone needs notifying (only Tasks/
  // Transactions resolve a real relevant party today) - callers don't
  // need to know or care which record types qualify.
  async function notifyStatusChange(context, recordTable, recordId, activityId, oldStatus, newStatus) {
    try {
      await context.supabaseClient.rpc("notify_ungani_record_status_change", {
        p_record_table: recordTable,
        p_record_id: recordId,
        p_old_status: oldStatus,
        p_new_status: newStatus
      });
    } catch (error) {
      console.warn("Could not send status-change notification:", error.message);
    }

    context.supabaseClient && UnganiClientShared.triggerEmailSendNow();
    if (activityId) UnganiClientShared.triggerEventPush("record_status_changed", activityId);
  }

  // Ungani Connect Phase 4: Smart Notification for a document getting
  // linked to a Task/Transaction - call after a successful document
  // save in my-documents.html when linked_task_id/linked_transaction_id
  // was set. Same best-effort pattern; the RPC no-ops for record types
  // with no relevant party (People/Employees/an unlinked document).
  async function notifyAttachment(context, documentId) {
    if (!documentId) return;

    try {
      await context.supabaseClient.rpc("notify_ungani_record_attachment", { p_document_id: documentId });
    } catch (error) {
      console.warn("Could not send attachment notification:", error.message);
    }

    UnganiClientShared.triggerEmailSendNow();
    UnganiClientShared.triggerEventPush("record_attachment", documentId);
  }

  window.UnganiConnectPanel = {
    open: open,
    postComment: postComment,
    addMention: addMention,
    removeMention: removeMention,
    logActivity: logActivity,
    notifyStatusChange: notifyStatusChange,
    notifyAttachment: notifyAttachment
  };
})();
