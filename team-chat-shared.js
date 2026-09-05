// UNGANI OS: shared Team Chat module (Team broadcast + private DMs).
//
// Used by client-shared.js's popup, client.html's own topbar (which does
// NOT load client-shared.js - it has a fully separate bespoke dashboard
// implementation), and my-team-chat.html's dedicated full page. Previously
// this logic was duplicated three times; this is the one real
// implementation. Fully self-contained (injects its own CSS, doesn't
// depend on either host page's existing class names/custom properties)
// so it can be dropped into any authenticated page that has a
// #unganiTeamChatPanel container and calls UnganiTeamChat.init(...).
(function () {
  const state = {
    getContext: null,
    messages: [],
    conversations: {},
    activeKey: "team",
    isOpen: false,
    pollTimer: null,
    firstLoadDone: false,
    roster: { owner: null, members: [] },
    rosterLoaded: false
  };

  function injectStylesOnce() {
    if (document.getElementById("unganiTeamChatSharedStyles")) return;

    const style = document.createElement("style");
    style.id = "unganiTeamChatSharedStyles";
    style.textContent = `
      #unganiTeamChatPanel {
        position: fixed;
        z-index: 9999;
        right: 18px;
        bottom: 18px;
        top: auto;
        left: auto;
        width: min(400px, calc(100vw - 24px));
        height: min(560px, 78vh);
        background: #FFFFFF;
        border: 1px solid rgba(6,28,61,0.12);
        border-radius: 22px;
        box-shadow: 0 26px 70px rgba(6,28,61,0.28);
        display: flex;
        flex-direction: column;
        overflow: hidden;
        font-family: Inter, Arial, sans-serif;
      }

      body[data-theme="dark"] #unganiTeamChatPanel {
        background: #0B2346;
        border-color: rgba(255,255,255,0.12);
      }

      @media (max-width: 640px) {
        #unganiTeamChatPanel {
          right: 0;
          bottom: 0;
          left: 0;
          width: 100%;
          /* vh is calculated against the layout viewport, which most
             mobile browsers do NOT shrink when the on-screen keyboard
             opens - this fixed-position, bottom-anchored panel kept its
             full "no keyboard" height, pushing the compose input (the
             last flex child) behind the keyboard - invisible and
             unreachable while typing, especially on a longer message
             where the keyboard stays open for a while. dvh (dynamic
             viewport height) IS recalculated on keyboard open/close in
             modern mobile browsers; kept as a second declaration so
             older browsers that don't understand dvh simply ignore it
             and keep using the vh value above. */
          height: min(80vh, 580px);
          height: min(80dvh, 580px);
          border-radius: 22px 22px 0 0;
        }
      }

      .utc-head {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 14px 16px;
        border-bottom: 1px solid rgba(6,28,61,0.10);
        background: #061C3D;
        color: #FFFFFF;
        flex: none;
      }

      body[data-theme="dark"] .utc-head { border-color: rgba(255,255,255,0.12); }

      .utc-head strong { font-size: 15px; }

      .utc-close-btn {
        border: none;
        background: rgba(255,255,255,0.12);
        color: #FFFFFF;
        border-radius: 999px;
        width: 28px;
        height: 28px;
        cursor: pointer;
        font-size: 14px;
        line-height: 1;
      }

      .utc-tabs {
        display: flex;
        gap: 6px;
        padding: 10px 12px;
        overflow-x: auto;
        border-bottom: 1px solid rgba(6,28,61,0.08);
        flex: none;
      }

      body[data-theme="dark"] .utc-tabs { border-color: rgba(255,255,255,0.10); }

      .utc-active-label {
        padding: 6px 12px;
        font-size: 11.5px;
        font-weight: 800;
        color: rgba(6,28,61,0.55);
        text-transform: uppercase;
        letter-spacing: 0.02em;
        flex: none;
      }

      body[data-theme="dark"] .utc-active-label { color: rgba(255,255,255,0.55); }

      .utc-tab {
        position: relative;
        flex: none;
        border: 1px solid rgba(6,28,61,0.14);
        background: #F8FAFC;
        color: #061C3D;
        border-radius: 999px;
        padding: 7px 13px;
        font-size: 12px;
        font-weight: 700;
        cursor: pointer;
        white-space: nowrap;
      }

      body[data-theme="dark"] .utc-tab {
        background: rgba(255,255,255,0.06);
        color: #F5F5F3;
        border-color: rgba(255,255,255,0.14);
      }

      .utc-tab.active {
        background: #D4A63A;
        color: #061C3D;
        border-color: #D4A63A;
      }

      .utc-tab-dot {
        display: inline-block;
        width: 7px;
        height: 7px;
        border-radius: 999px;
        background: #DC2626;
        margin-left: 6px;
      }

      .utc-tab-add {
        flex: none;
        border: 1px dashed rgba(6,28,61,0.22);
        background: transparent;
        color: #061C3D;
        border-radius: 999px;
        width: 30px;
        height: 30px;
        cursor: pointer;
        font-size: 15px;
        font-weight: 900;
      }

      body[data-theme="dark"] .utc-tab-add {
        border-color: rgba(255,255,255,0.24);
        color: #F5F5F3;
      }

      .utc-picker {
        padding: 10px 12px;
        border-bottom: 1px solid rgba(6,28,61,0.08);
        display: flex;
        gap: 8px;
        flex: none;
      }

      body[data-theme="dark"] .utc-picker { border-color: rgba(255,255,255,0.10); }

      .utc-picker select {
        flex: 1;
        border-radius: 12px;
        border: 1px solid rgba(6,28,61,0.16);
        padding: 8px 10px;
        font-size: 13px;
        background: #FFFFFF;
        color: #061C3D;
      }

      body[data-theme="dark"] .utc-picker select {
        background: rgba(255,255,255,0.08);
        color: #F5F5F3;
        border-color: rgba(255,255,255,0.18);
      }

      .utc-picker button {
        border: none;
        background: #061C3D;
        color: #FFFFFF;
        border-radius: 12px;
        padding: 8px 12px;
        font-size: 12px;
        font-weight: 700;
        cursor: pointer;
      }

      .utc-messages {
        flex: 1;
        overflow-y: auto;
        padding: 14px;
        display: flex;
        flex-direction: column;
        gap: 10px;
      }

      .utc-empty {
        margin: auto;
        text-align: center;
        color: rgba(6,28,61,0.55);
        padding: 20px;
      }

      body[data-theme="dark"] .utc-empty { color: rgba(255,255,255,0.55); }

      .utc-empty h4 { margin: 0 0 6px; font-size: 14px; color: inherit; }
      .utc-empty p { margin: 0; font-size: 12.5px; }

      .utc-bubble {
        max-width: 82%;
        padding: 10px 14px;
        border-radius: 16px;
        font-size: 13px;
        line-height: 1.45;
      }

      .utc-bubble .utc-sender {
        display: block;
        font-size: 11px;
        font-weight: 900;
        text-transform: uppercase;
        letter-spacing: 0.04em;
        margin-bottom: 3px;
        opacity: 0.7;
      }

      .utc-bubble .utc-time {
        display: block;
        font-size: 10px;
        margin-top: 4px;
        opacity: 0.6;
      }

      .utc-bubble.mine {
        align-self: flex-end;
        background: #D4A63A;
        color: #061C3D;
        border-bottom-right-radius: 4px;
      }

      .utc-bubble.theirs {
        align-self: flex-start;
        background: #F8FAFC;
        color: #061C3D;
        border: 1px solid rgba(6,28,61,0.10);
        border-bottom-left-radius: 4px;
      }

      body[data-theme="dark"] .utc-bubble.theirs {
        background: rgba(255,255,255,0.06);
        color: #F5F5F3;
        border-color: rgba(255,255,255,0.12);
      }

      .utc-input-row {
        display: flex;
        gap: 8px;
        padding: 12px;
        border-top: 1px solid rgba(6,28,61,0.10);
        background: #F8FAFC;
        flex: none;
      }

      body[data-theme="dark"] .utc-input-row {
        border-color: rgba(255,255,255,0.12);
        background: rgba(255,255,255,0.04);
      }

      .utc-input-row input {
        flex: 1;
        border-radius: 999px;
        border: 1px solid rgba(6,28,61,0.16);
        background: #FFFFFF;
        color: #061C3D;
        padding: 10px 16px;
        font-size: 13px;
        outline: none;
      }

      body[data-theme="dark"] .utc-input-row input {
        background: rgba(255,255,255,0.08);
        color: #F5F5F3;
        border-color: rgba(255,255,255,0.18);
      }

      .utc-send {
        width: 40px;
        height: 40px;
        border-radius: 999px;
        border: 0;
        background: #D4A63A;
        color: #061C3D;
        font-weight: 900;
        cursor: pointer;
        flex: 0 0 auto;
      }

      .utc-toast {
        position: fixed;
        right: 18px;
        bottom: 18px;
        z-index: 99999;
        max-width: min(340px, calc(100vw - 32px));
        background: linear-gradient(135deg, rgba(8,38,84,0.98), rgba(6,28,61,0.98));
        color: #FFFFFF;
        border: 1px solid rgba(212,166,58,0.35);
        border-radius: 18px;
        box-shadow: 0 18px 45px rgba(0,0,0,0.35);
        padding: 14px;
        display: flex;
        gap: 11px;
        align-items: flex-start;
        cursor: pointer;
        transform: translateY(14px);
        opacity: 0;
        transition: 0.28s ease;
      }

      .utc-toast.show { transform: translateY(0); opacity: 1; }
      .utc-toast strong { display: block; color: #D4A63A; font-size: 13px; margin-bottom: 3px; }
      .utc-toast p { margin: 0; font-size: 13px; color: #F5F5F3; line-height: 1.4; }
    `;
    document.head.appendChild(style);
  }

  function getContext() {
    if (typeof state.getContext !== "function") return null;
    try {
      return state.getContext();
    } catch (error) {
      return null;
    }
  }

  function safe(value) {
    return String(value === null || value === undefined ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#039;");
  }

  function getField(row, keys, fallback) {
    if (!row) return fallback === undefined ? "" : fallback;
    for (let i = 0; i < keys.length; i++) {
      const v = row[keys[i]];
      if (v !== null && v !== undefined && v !== "") return v;
    }
    return fallback === undefined ? "" : fallback;
  }

  function formatTime(value) {
    if (!value) return "";
    try {
      const d = new Date(value);
      return d.toLocaleString(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
    } catch (error) {
      return "";
    }
  }

  async function init(getContextFn) {
    state.getContext = getContextFn;
    injectStylesOnce();
    await loadRoster();
    await loadMessages(true);
  }

  async function loadRoster() {
    const ctx = getContext();
    if (!ctx || !ctx.supabaseClient) return;

    try {
      const response = await ctx.supabaseClient.rpc("get_my_ungani_team_members_for_assignment");
      if (!response.error && response.data && response.data.ok === true) {
        state.roster = {
          owner: response.data.owner || null,
          members: response.data.members || []
        };
      }
    } catch (error) {
      console.warn("Team chat roster load skipped:", error.message);
    }

    state.rosterLoaded = true;
  }

  function myIdentity() {
    const ctx = getContext();
    const myAuthId = ctx && ctx.authUser ? ctx.authUser.id : null;
    const owner = state.roster.owner;
    const isOwner = !!(owner && myAuthId && owner.auth_user_id === myAuthId);
    const myMember = state.roster.members.find(function (m) { return m.auth_user_id === myAuthId; });
    return {
      authUserId: myAuthId,
      isOwner: isOwner,
      teamMemberId: myMember ? myMember.id : null
    };
  }

  function peerKeyForRow(row, me) {
    const recipientTeamMemberId = row.recipient_team_member_id || null;
    const recipientIsOwner = !!row.recipient_is_owner;

    if (!recipientTeamMemberId && !recipientIsOwner) return "team";

    const iSent = row.sender_user_id === me.authUserId;

    if (iSent) {
      return recipientIsOwner ? "owner" : "tm:" + recipientTeamMemberId;
    }

    // I'm the recipient - the peer is the sender. Resolve their team_member_id
    // via the roster (auth_user_id -> team member), falling back to the
    // owner bucket, then a raw-uid bucket for a sender who's no longer in
    // the active roster (e.g. deactivated after sending).
    if (state.roster.owner && row.sender_user_id === state.roster.owner.auth_user_id) return "owner";

    const senderMember = state.roster.members.find(function (m) { return m.auth_user_id === row.sender_user_id; });
    if (senderMember) return "tm:" + senderMember.id;

    return "uid:" + row.sender_user_id;
  }

  function peerLabel(key, row) {
    if (key === "team") return "Team";
    if (key === "owner") return (state.roster.owner && state.roster.owner.full_name) || "Owner";

    if (key.indexOf("tm:") === 0) {
      const id = key.slice(3);
      const member = state.roster.members.find(function (m) { return m.id === id; });
      if (member) return member.full_name;
    }

    return getField(row, ["sender_name"], "Team Member");
  }

  function rebuildConversations() {
    const me = myIdentity();
    const conversations = { team: [] };

    state.messages.forEach(function (row) {
      const key = peerKeyForRow(row, me);
      if (!conversations[key]) conversations[key] = [];
      conversations[key].push(row);
    });

    state.conversations = conversations;

    if (!conversations[state.activeKey]) {
      state.activeKey = "team";
    }
  }

  function conversationList() {
    const me = myIdentity();
    const keys = Object.keys(state.conversations).filter(function (k) { return k !== "team"; });

    keys.sort(function (a, b) {
      const aLast = state.conversations[a][state.conversations[a].length - 1];
      const bLast = state.conversations[b][state.conversations[b].length - 1];
      return new Date(getField(bLast, ["created_at"], 0)).getTime() - new Date(getField(aLast, ["created_at"], 0)).getTime();
    });

    const list = [{ key: "team", label: "Team", unread: unreadCountFor("team") }];

    keys.forEach(function (key) {
      const rows = state.conversations[key];
      list.push({
        key: key,
        label: peerLabel(key, rows[rows.length - 1]),
        unread: unreadCountFor(key)
      });
    });

    return list;
  }

  function unreadCountFor(key) {
    const ctx = getContext();
    const myAuthId = ctx && ctx.authUser ? ctx.authUser.id : null;
    const rows = state.conversations[key] || [];
    return rows.filter(function (r) { return r.sender_user_id !== myAuthId && !r.is_read; }).length;
  }

  function totalUnread() {
    return Object.keys(state.conversations).reduce(function (sum, key) { return sum + unreadCountFor(key); }, 0);
  }

  function availableDmTargets() {
    const me = myIdentity();
    const existingKeys = Object.keys(state.conversations);
    const targets = [];

    if (!me.isOwner && state.roster.owner) {
      targets.push({ key: "owner", label: (state.roster.owner.full_name || "Owner") + " (Owner)" });
    }

    state.roster.members.forEach(function (m) {
      if (m.id === me.teamMemberId) return;
      targets.push({ key: "tm:" + m.id, label: m.full_name + (m.role_key ? " (" + m.role_key + ")" : "") });
    });

    return targets;
  }

  async function loadMessages(silent) {
    const ctx = getContext();
    if (!ctx || !ctx.supabaseClient || !ctx.tenantId) return;

    try {
      const response = await ctx.supabaseClient
        .from("team_chat_messages")
        .select("*")
        // Department Channel messages (channel_id set) are a my-connect.html
        // hub concept as of Ungani Connect Phase 1 - deliberately excluded
        // here so this compact popup's "Team" tab isn't contaminated with
        // channel chatter it has no UI context for. See my-connect.html for
        // the full Team + Channels + DMs view.
        .is("channel_id", null)
        .eq("tenant_id", ctx.tenantId)
        .order("created_at", { ascending: true })
        .limit(300);

      if (response.error) {
        console.warn("Team chat load skipped:", response.error.message);
        return;
      }

      const previousMessages = state.messages;
      state.messages = response.data || [];
      rebuildConversations();

      if (state.firstLoadDone) {
        checkForNewMessages(previousMessages, state.messages);
      }

      state.firstLoadDone = true;
      updateBadges();

      if (state.isOpen) {
        // renderPanel() rebuilds the whole panel, including #utcInput -
        // on the 12s auto-poll that wipes a message in progress mid-
        // keystroke (worse on mobile, where it also drops the keyboard).
        // While the user is actively typing, only refresh the message
        // bubbles via renderMessages() (already a separate, input-
        // untouched update) - the tabs/unread-dots catch up next time
        // renderPanel() runs (switching conversations, sending, opening
        // the panel), which is a fine tradeoff against losing a draft.
        const inputEl = document.getElementById("utcInput");
        const userIsTyping = inputEl && (document.activeElement === inputEl || inputEl.value.trim().length > 0);

        if (userIsTyping) {
          renderMessages();
        } else {
          renderPanel();
        }

        if (!silent) scrollToBottom();
      }
    } catch (error) {
      console.warn("Team chat load skipped:", error.message);
    }
  }

  function checkForNewMessages(previousMessages, newMessages) {
    const ctx = getContext();
    const myAuthId = ctx && ctx.authUser ? ctx.authUser.id : null;
    const previousIds = new Set(previousMessages.map(function (m) { return m.id; }));

    const freshOnes = newMessages.filter(function (m) {
      return !previousIds.has(m.id) && m.sender_user_id !== myAuthId;
    });

    if (freshOnes.length > 0 && !state.isOpen) {
      showToast(freshOnes[freshOnes.length - 1]);
    }
  }

  function updateBadges() {
    const unread = totalUnread();
    document.querySelectorAll("[data-ungani-chat-badge]").forEach(function (el) {
      el.textContent = unread > 99 ? "99+" : String(unread);
      el.style.display = unread > 0 ? "inline-flex" : "none";
      el.classList.toggle("show", unread > 0);
    });
  }

  function showToast(message) {
    const existing = document.getElementById("unganiTeamChatToast");
    if (existing) existing.remove();

    const toast = document.createElement("div");
    toast.id = "unganiTeamChatToast";
    toast.className = "utc-toast";

    const senderName = getField(message, ["sender_name"], "Team Member");
    const rawBody = String(getField(message, ["message_body", "message", "body"], "New message"));
    const isDm = !!(message.recipient_team_member_id || message.recipient_is_owner);
    const body = (isDm ? "(Private) " : "") + (rawBody.length > 80 ? rawBody.slice(0, 80) + "..." : rawBody);

    toast.innerHTML = `
      <div style="font-size:20px;"><i data-lucide="message-circle"></i></div>
      <div>
        <strong>${safe(senderName)}</strong>
        <p>${safe(body)}</p>
      </div>
    `;

    toast.addEventListener("click", function () {
      toast.remove();
      toggle();
    });

    document.body.appendChild(toast);
    if (window.lucide) window.lucide.createIcons();

    setTimeout(function () { toast.classList.add("show"); }, 30);
    setTimeout(function () {
      toast.classList.remove("show");
      setTimeout(function () { toast.remove(); }, 300);
    }, 7000);
  }

  function toggle() {
    const panel = document.getElementById("unganiTeamChatPanel");
    if (!panel) return;

    if (state.isOpen) {
      close();
      return;
    }

    state.isOpen = true;
    panel.style.display = "flex";
    renderPanel();
    markActiveConversationRead();
    scrollToBottom();

    const input = document.getElementById("utcInput");
    if (input) input.focus();
  }

  function close() {
    const panel = document.getElementById("unganiTeamChatPanel");
    state.isOpen = false;
    if (panel) panel.style.display = "none";
  }

  function selectConversation(key) {
    state.activeKey = key;
    renderPanel();
    markActiveConversationRead();
    scrollToBottom();
  }

  function renderPanel() {
    const panel = document.getElementById("unganiTeamChatPanel");
    if (!panel) return;

    const list = conversationList();
    const targets = availableDmTargets();

    panel.innerHTML = `
      <div class="utc-head">
        <strong>Team Chat</strong>
        <button class="utc-close-btn" type="button" onclick="UnganiTeamChat.close()">✕</button>
      </div>

      <div class="utc-tabs">
        ${list.map(function (c) {
          return `
            <button class="utc-tab${c.key === state.activeKey ? " active" : ""}" type="button" onclick="UnganiTeamChat.selectConversation('${safe(c.key)}')">
              ${safe(c.label)}${c.unread > 0 ? '<span class="utc-tab-dot"></span>' : ""}
            </button>
          `;
        }).join("")}
        ${targets.length ? `<button class="utc-tab-add" type="button" title="Start a private message" onclick="UnganiTeamChat.toggleStartDm()">+</button>` : ""}
      </div>

      <div id="utcStartDmRow" class="utc-picker" style="display:none;">
        <select id="utcStartDmSelect">
          ${targets.map(function (t) { return `<option value="${safe(t.key)}">${safe(t.label)}</option>`; }).join("")}
        </select>
        <button type="button" onclick="UnganiTeamChat.confirmStartDm()">Start</button>
      </div>

      <div class="utc-active-label">
        ${state.activeKey === "team" ? "Chatting with your whole Team" : "Chatting with " + safe(peerLabel(state.activeKey, null)) + " (private)"}
      </div>

      <div id="utcMessages" class="utc-messages"></div>

      <form class="utc-input-row" onsubmit="UnganiTeamChat.send(event); return false;">
        <input id="utcInput" type="text" placeholder="${state.activeKey === "team" ? "Message your team..." : "Send a private message..."}" autocomplete="off" />
        <button class="utc-send" type="submit" title="Send">➤</button>
      </form>
    `;

    renderMessages();
  }

  function renderMessages() {
    const box = document.getElementById("utcMessages");
    if (!box) return;

    const ctx = getContext();
    const myAuthId = ctx && ctx.authUser ? ctx.authUser.id : null;
    const rows = state.conversations[state.activeKey] || [];

    if (!rows.length) {
      box.innerHTML = `
        <div class="utc-empty">
          <h4>No messages yet</h4>
          <p>${state.activeKey === "team" ? "Send a quick note to your team to get started." : "Send the first private message to start this conversation."}</p>
        </div>
      `;
      return;
    }

    box.innerHTML = rows.map(function (row) {
      const isMine = row.sender_user_id === myAuthId;
      const senderName = getField(row, ["sender_name"], isMine ? "You" : "Team Member");
      const body = getField(row, ["message_body", "message", "body"], "");
      const time = formatTime(getField(row, ["created_at"], ""));

      return `
        <div class="utc-bubble ${isMine ? "mine" : "theirs"}">
          ${isMine || state.activeKey !== "team" ? "" : `<span class="utc-sender">${safe(senderName)}</span>`}
          <span>${safe(body)}</span>
          <span class="utc-time">${safe(time)}</span>
        </div>
      `;
    }).join("");
  }

  function scrollToBottom() {
    const box = document.getElementById("utcMessages");
    if (box) box.scrollTop = box.scrollHeight;
  }

  function toggleStartDm() {
    const row = document.getElementById("utcStartDmRow");
    if (row) row.style.display = row.style.display === "none" ? "flex" : "none";
  }

  function confirmStartDm() {
    const select = document.getElementById("utcStartDmSelect");
    if (!select || !select.value) return;

    const key = select.value;
    if (!state.conversations[key]) state.conversations[key] = [];

    const row = document.getElementById("utcStartDmRow");
    if (row) row.style.display = "none";

    selectConversation(key);
  }

  async function markActiveConversationRead() {
    const ctx = getContext();
    if (!ctx || !ctx.supabaseClient || !ctx.tenantId || !ctx.authUser) return;

    const rows = state.conversations[state.activeKey] || [];
    const unreadIds = rows
      .filter(function (r) { return r.sender_user_id !== ctx.authUser.id && !r.is_read; })
      .map(function (r) { return r.id; });

    if (!unreadIds.length) return;

    try {
      await ctx.supabaseClient
        .from("team_chat_messages")
        .update({ is_read: true, updated_at: new Date().toISOString() })
        .in("id", unreadIds);

      state.messages.forEach(function (m) {
        if (unreadIds.indexOf(m.id) !== -1) m.is_read = true;
      });

      rebuildConversations();
      updateBadges();
      renderPanel();
    } catch (error) {
      console.warn("Could not mark team chat read:", error.message);
    }
  }

  async function send(event) {
    if (event && event.preventDefault) event.preventDefault();

    const ctx = getContext();
    const input = document.getElementById("utcInput");
    const body = input ? String(input.value || "").trim() : "";

    if (!body || !ctx || !ctx.authUser) return;

    const senderName = getField(ctx.userProfile, ["full_name", "name"], "") ||
      getField(ctx.authUser, ["email"], "Team Member");

    // Generated up front (not read back via .select() after insert) - the
    // same "avoid RETURNING against a table with no broad SELECT policy"
    // pattern already used for registrations - so there's an id to pass
    // to the push trigger below without an extra round trip.
    const messageId = crypto.randomUUID();

    const payload = {
      id: messageId,
      tenant_id: ctx.tenantId,
      sender_user_id: ctx.authUser.id,
      sender_name: senderName,
      sender_role: "team",
      message_type: "message",
      message_body: body,
      message: body,
      body: body,
      is_read: false,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    };

    if (state.activeKey === "owner") {
      payload.recipient_is_owner = true;
    } else if (state.activeKey.indexOf("tm:") === 0) {
      payload.recipient_team_member_id = state.activeKey.slice(3);
    }

    if (input) input.value = "";

    try {
      const response = await ctx.supabaseClient.from("team_chat_messages").insert(payload);

      if (response.error) {
        if (typeof window.UnganiClientShared !== "undefined" && window.UnganiClientShared.showToast) {
          window.UnganiClientShared.showToast("Could not send message: " + response.error.message);
        } else {
          alert("Could not send message: " + response.error.message);
        }
        return;
      }

      if (typeof window.UnganiClientShared !== "undefined" && typeof window.UnganiClientShared.triggerEventPush === "function") {
        window.UnganiClientShared.triggerEventPush("team_chat_message", messageId);
      }

      await loadMessages(true);
      scrollToBottom();
    } catch (error) {
      if (typeof window.UnganiClientShared !== "undefined" && window.UnganiClientShared.showToast) {
        window.UnganiClientShared.showToast("Could not send message: " + error.message);
      } else {
        alert("Could not send message: " + error.message);
      }
    }
  }

  function startPolling() {
    if (state.pollTimer) clearInterval(state.pollTimer);
    loadMessages(true);
    state.pollTimer = setInterval(function () { loadMessages(true); }, 12000);
  }

  window.UnganiTeamChat = {
    init: init,
    toggle: toggle,
    close: close,
    startPolling: startPolling,
    selectConversation: selectConversation,
    toggleStartDm: toggleStartDm,
    confirmStartDm: confirmStartDm,
    send: send,
    getUnreadCount: totalUnread
  };
})();
