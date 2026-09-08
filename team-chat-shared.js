// UNGANI OS: shared Team Chat module (Team broadcast + private DMs +
// hashtag channels).
//
// Two consumption modes, same data layer underneath:
// 1. Launcher mode - client-shared.js's header chat icon and client.html's
//    own topbar (client.html does NOT load client-shared.js - fully
//    separate bespoke dashboard) both drop a #unganiTeamChatPanel
//    container on the page and call UnganiTeamChat.init(...); this module
//    renders a small unread-summary dropdown into it (real Team/DM/channel
//    counts, deep-linking into my-team-chat.html), NOT a second mini-chat -
//    composing a reply always happens on the real page. Used to be a full
//    self-contained popup with its own tabs/DM-picker/compose box; that
//    duplicated my-team-chat.html's UI in a 400px widget without ever
//    showing channels, avatars, or read ticks, which read as a stripped-
//    down, out-of-date parallel system next to the real page (Team Chat
//    redesign follow-up, 2026-09).
// 2. Embedded mode - my-team-chat.html (the dedicated Team Chat page) calls
//    init(...) for the exact same roster/message loading, polling, send,
//    and read-marking logic, but registers its own layout via
//    setRenderCallback(fn) instead of using this module's launcher DOM, and
//    reads state through getConversationList()/getMessagesFor()/getRoster()
//    etc. Only one real implementation of the data layer either way -
//    embedded mode was added specifically so my-team-chat.html could stop
//    being a second, independently-maintained reimplementation of the same
//    feature (Team Chat redesign, 2026-09).
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
    rosterLoaded: false,
    // Set via setRenderCallback() by a host page that wants to render its
    // own layout (e.g. the dedicated my-team-chat.html page) instead of
    // this module's own popup DOM. When set, every place that would
    // normally call renderPanel() calls this instead - the popup's own
    // rendering is completely unaffected on pages that never set this.
    renderCallback: null,
    // Channels. Full channel messages/content are still embedded-mode
    // only (my-team-chat.html) - the popup/launcher only ever loads the
    // channel list + unread counts (loadChannels()), for its own unread
    // summary, and never renders channel messages. Kept in their own
    // state rather than folded into state.messages/state.conversations so
    // the popup's existing rebuildConversations()-based rendering is
    // completely unaffected by any of this.
    channels: [],
    channelUnread: {},
    channelMessages: {},
    isOwner: false,
    // Read-receipt counts for Team/channel (group) messages only -
    // messageId -> number of OTHER members who've read it. DMs need no
    // entry here; a DM's read status is is_read itself (see
    // readReceiptHtml()). Populated by loadReadCounts(), written to by
    // recordGroupReadReceipts() - both live in the "Read receipts" block
    // below markActiveConversationRead().
    readCounts: {}
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

      /* Duplicated from my-team-chat.html's own stylesheet (same
         self-contained-CSS pattern as the rest of this popup) - avatarHtml()
         is shared data-layer logic, but each consumer styles its own
         .ungani-chat-avatar output since the popup can't assume the host
         page's own CSS is present. */
      .ungani-chat-avatar {
        border-radius: 999px;
        display: flex;
        align-items: center;
        justify-content: center;
        font-weight: 800;
        flex: none;
        line-height: 1;
      }

      /* Launcher (Team Chat redesign, 2026-09) - replaces what used to be
         a full second mini-chat (its own tabs, DM picker, compose box)
         with a real unread summary that deep-links into the actual
         my-team-chat.html page instead of duplicating its UI in a 400px
         popup. See toggle()/renderPanel() below. */
      .utc-launcher-body {
        flex: 1;
        overflow-y: auto;
        padding: 6px;
        display: flex;
        flex-direction: column;
        gap: 2px;
      }

      .utc-launcher-row {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 10px;
        border-radius: 14px;
        text-decoration: none;
        color: #061C3D;
      }

      .utc-launcher-row:hover { background: #F8FAFC; }

      body[data-theme="dark"] .utc-launcher-row { color: #F5F5F3; }
      body[data-theme="dark"] .utc-launcher-row:hover { background: rgba(255,255,255,0.06); }

      .utc-launcher-label {
        flex: 1;
        font-size: 13px;
        font-weight: 700;
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
      }

      .utc-launcher-count {
        flex: none;
        min-width: 20px;
        height: 20px;
        padding: 0 6px;
        border-radius: 999px;
        background: #DC2626;
        color: #FFFFFF;
        font-size: 11px;
        font-weight: 800;
        display: flex;
        align-items: center;
        justify-content: center;
      }

      .utc-launcher-footer {
        display: block;
        text-align: center;
        padding: 12px;
        border-top: 1px solid rgba(6,28,61,0.10);
        color: #061C3D;
        font-weight: 800;
        font-size: 12.5px;
        text-decoration: none;
        flex: none;
      }

      body[data-theme="dark"] .utc-launcher-footer {
        border-color: rgba(255,255,255,0.12);
        color: #F5F5F3;
      }

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

  // Time-only for today's messages, date+time for anything older - a
  // message sent 5 minutes ago showing "Sept 8, 3:41 PM" read as noise;
  // this only spells out the date once it's actually informative.
  function formatTime(value) {
    if (!value) return "";
    try {
      const d = new Date(value);
      const now = new Date();
      const isToday = d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate();

      if (isToday) {
        return d.toLocaleString(undefined, { hour: "2-digit", minute: "2-digit" });
      }

      return d.toLocaleString(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
    } catch (error) {
      return "";
    }
  }

  // --- Avatars (embedded mode only - see avatarHtml()) ----------------
  // Initials-based avatars, no photo upload yet (Team Chat redesign
  // Phase 2, 2026-09) - no photo/avatar_url column exists anywhere in
  // this app today (confirmed by inspecting the team-member roster and
  // every tracked SQL file), so this deliberately ships the fallback
  // treatment now and leaves a real upload as a separate future phase
  // rather than blocking the message-clarity improvement on new Storage
  // infrastructure. Colors are hashed from the sender's real auth user id
  // so the same person always gets the same color everywhere they appear.
  const AVATAR_PALETTE = [
    { bg: "var(--ungani-navy)", fg: "#FFFFFF" },
    { bg: "var(--ungani-gold)", fg: "var(--ungani-navy)" },
    { bg: "var(--ungani-green)", fg: "#FFFFFF" },
    { bg: "var(--ungani-blue)", fg: "#FFFFFF" },
    { bg: "var(--ungani-orange)", fg: "#FFFFFF" }
  ];

  function avatarInitials(name) {
    const parts = String(name || "?").trim().split(/\s+/).filter(Boolean);
    if (!parts.length) return "?";
    if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  function avatarColorFor(key) {
    const str = String(key || "x");
    let hash = 0;
    for (let i = 0; i < str.length; i++) hash = (hash * 31 + str.charCodeAt(i)) >>> 0;
    return AVATAR_PALETTE[hash % AVATAR_PALETTE.length];
  }

  // key: a stable identity string - a real auth_user_id for an actual
  // person, or the literal "team"/"channel" for a header representing the
  // whole conversation rather than one sender. name is only used to derive
  // initials (ignored for the "team"/"channel" special cases).
  function avatarHtml(key, name, sizePx) {
    const size = sizePx || 32;
    const color = avatarColorFor(key);
    const initials = key === "team" ? "T" : key === "channel" ? "#" : avatarInitials(name);
    return `<div class="ungani-chat-avatar" style="width:${size}px;height:${size}px;min-width:${size}px;font-size:${Math.round(size * 0.4)}px;background:${color.bg};color:${color.fg};">${safe(initials)}</div>`;
  }

  // Resolves a conversationList()/peerLabel() bucket key ("team", "owner",
  // "tm:<id>", "uid:<id>") to the stable {authId, name} avatarHtml() needs -
  // conversationList() only tracks bucket keys internally, so this is the
  // one place that bridges "which bucket is this" to "whose avatar is
  // this", used both for conversation-list rows and DM thread headers.
  function avatarIdentityForKey(key) {
    if (key === "team") return { authId: "team", name: "Team" };

    if (key === "owner") {
      return {
        authId: (state.roster.owner && state.roster.owner.auth_user_id) || "owner",
        name: (state.roster.owner && state.roster.owner.full_name) || "Owner"
      };
    }

    if (key.indexOf("tm:") === 0) {
      const id = key.slice(3);
      const member = state.roster.members.find(function (m) { return m.id === id; });
      return { authId: member ? member.auth_user_id : id, name: member ? member.full_name : "Team Member" };
    }

    if (key.indexOf("uid:") === 0) {
      return { authId: key.slice(4), name: "Team Member" };
    }

    return { authId: key, name: "Team Member" };
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

    // Real bug, confirmed live: a DM just started via startDm()
    // exists only as an empty placeholder (state.conversations[key] = []) until
    // its first message is actually sent - it has no rows in state.messages yet,
    // so the loop above never recreates it. Every poll (loadMessages() runs this
    // on a 12s timer) was rebuilding `conversations` from messages alone, which
    // silently dropped that empty conversation and the fallback below then
    // snapped activeKey back to "team" - from the user's side, opening a new DM
    // and pausing to read/type looked exactly like clicking it did nothing.
    // Any previously-known key (empty or not) is preserved here so it survives
    // until either a real message makes it permanent or the page reloads.
    Object.keys(state.conversations).forEach(function (key) {
      if (!conversations[key]) conversations[key] = state.conversations[key];
    });

    state.conversations = conversations;

    // Channel keys ("channel:<id>") are never stored in state.conversations
    // - they live in state.channelMessages instead (see the "Channels"
    // block above startDm()) - so this fallback must leave them alone.
    // Without this check, this Team/DM poll (loadMessages(), every 12s)
    // was stomping state.activeKey back to "team" out from under an open
    // channel every single cycle, the same bug class as the DM-reverting
    // one fixed above but via a different path (confirmed live, Team Chat
    // Phase 2 testing, 2026-09).
    if (state.activeKey.indexOf("channel:") !== 0 && !conversations[state.activeKey]) {
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

    const list = [{ key: "team", label: "Team", unread: unreadCountFor("team"), avatarKey: "team", avatarName: "Team" }];

    keys.forEach(function (key) {
      const rows = state.conversations[key];
      const identity = avatarIdentityForKey(key);
      list.push({
        key: key,
        label: peerLabel(key, rows[rows.length - 1]),
        unread: unreadCountFor(key),
        avatarKey: identity.authId,
        avatarName: identity.name
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
        // Channel messages (channel_id set) are excluded from this popup's
        // "Team" tab, which only ever shows the broadcast + DM view - real
        // channel browsing lives on the dedicated my-team-chat.html page
        // instead (ungani_chat_channels backend, Team Chat redesign 2026-09).
        // my-connect.html briefly hosted a Team+Channels+DMs view during
        // Ungani Connect Phase 1 but was scoped back down to Shared Files
        // only; this popup was never part of that page.
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

      // Team broadcast rows only (recipient_team_member_id/recipient_is_owner
      // both null/false, channel_id already excluded by this query) - see
      // the "Read receipts" block below markActiveConversationRead() for
      // why DMs need no equivalent call.
      const teamMessageIds = state.messages
        .filter(function (m) { return !m.recipient_team_member_id && !m.recipient_is_owner; })
        .map(function (m) { return m.id; });
      loadReadCounts(teamMessageIds);

      // The popup no longer has a compose input of its own (see the
      // "Launcher" block above toggle()) - it's a real unread-summary
      // list, not a second mini-chat - so the old "don't wipe an
      // in-progress draft on the 12s poll" special-casing for #utcInput
      // no longer applies here. A host page with its own renderCallback
      // (my-team-chat.html) still owns its own draft protection.
      if (state.isOpen || typeof state.renderCallback === "function") {
        notifyRender();
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

  // --- Launcher (header chat icon) -------------------------------------
  // Team Chat redesign, 2026-09: this used to open a full second mini-chat
  // (its own tabs, DM picker, compose box) reading the same Team/DM data
  // as my-team-chat.html but never showing channels, avatars, or read
  // ticks - a visibly stripped-down, out-of-date-looking parallel system
  // sitting right next to the real page. Replaced with a real unread
  // summary (Team/DM/channel counts, using the exact same data + the same
  // avatarHtml() the real page uses) that deep-links straight into
  // my-team-chat.html on the relevant conversation instead of duplicating
  // its UI in a 400px popup. Composing a reply now always happens on the
  // real page.
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
    loadChannels(); // fire-and-forget; re-renders itself once counts/names load
  }

  function close() {
    const panel = document.getElementById("unganiTeamChatPanel");
    state.isOpen = false;
    if (panel) panel.style.display = "none";
  }

  function selectConversation(key) {
    state.activeKey = key;
    notifyRender();
    markActiveConversationRead();
  }

  function renderPanel() {
    const panel = document.getElementById("unganiTeamChatPanel");
    if (!panel) return;

    const items = conversationList()
      .filter(function (c) { return c.unread > 0; })
      .map(function (c) { return { key: c.key, label: c.label, unread: c.unread, avatarKey: c.avatarKey, avatarName: c.avatarName }; })
      .concat(
        state.channels
          .map(function (c) {
            return { key: "channel:" + c.id, label: "#" + c.name, unread: state.channelUnread[c.id] || 0, avatarKey: "channel", avatarName: c.name };
          })
          .filter(function (c) { return c.unread > 0; })
      );

    panel.innerHTML = `
      <div class="utc-head">
        <strong>Team Chat</strong>
        <button class="utc-close-btn" type="button" onclick="UnganiTeamChat.close()">✕</button>
      </div>

      <div class="utc-launcher-body">
        ${items.length ? items.map(function (c) {
          return `
            <a class="utc-launcher-row" href="my-team-chat.html?open=${encodeURIComponent(c.key)}">
              ${avatarHtml(c.avatarKey, c.avatarName, 30)}
              <span class="utc-launcher-label">${safe(c.label)}</span>
              <span class="utc-launcher-count">${c.unread > 99 ? "99+" : c.unread}</span>
            </a>
          `;
        }).join("") : `
          <div class="utc-empty">
            <h4>You're all caught up</h4>
            <p>No unread messages right now.</p>
          </div>
        `}
      </div>

      <a class="utc-launcher-footer" href="my-team-chat.html">Open Team Chat →</a>
    `;
  }

  // Renders the popup's own DOM if that's what's on this page, or hands
  // control to a host page's own renderer if one is registered. Never
  // does both - a page either uses the popup or embeds its own layout,
  // never both at once.
  function notifyRender() {
    if (typeof state.renderCallback === "function") {
      state.renderCallback();
      return;
    }
    renderPanel();
  }

  // Ensures the conversation bucket exists, then switches to it - shared
  // by my-team-chat.html's own "start a DM" UI (the launcher no longer has
  // one of its own, see the "Launcher" block above toggle()).
  function startDm(key) {
    if (!key) return;
    if (!state.conversations[key]) state.conversations[key] = [];
    selectConversation(key);
  }

  // --- Channels ---------------------------------------------------------
  // Hashtag channels (Team Chat redesign Phase 2, 2026-09). Deliberately
  // kept out of state.messages/state.conversations/rebuildConversations()
  // so the popup/launcher's existing rebuildConversations()-based Team/DM
  // rendering is completely unaffected. The launcher calls loadChannels()
  // for its own unread summary (see toggle() above) but never calls
  // loadChannelMessages()/selectChannel() - full channel content stays
  // embedded-mode only. Channel messages share the same is_read column as
  // every other row in team_chat_messages, which is a single shared flag rather
  // than a per-reader read receipt; that's an existing limitation already
  // accepted for the "Team" broadcast tab above, not a new one introduced
  // here - channels just follow the same convention for consistency.

  async function loadChannels() {
    const ctx = getContext();
    if (!ctx || !ctx.supabaseClient) return;

    try {
      const response = await ctx.supabaseClient.rpc("get_my_ungani_chat_channels");
      if (!response.error && response.data && response.data.ok === true) {
        state.channels = response.data.channels || [];
        state.isOwner = !!response.data.is_owner;
      }
    } catch (error) {
      console.warn("Channel list load skipped:", error.message);
    }

    await loadChannelUnreadCounts();
    notifyRender();
  }

  async function loadChannelUnreadCounts() {
    const ctx = getContext();
    if (!ctx || !ctx.supabaseClient || !ctx.tenantId || !ctx.authUser) return;

    try {
      const response = await ctx.supabaseClient
        .from("team_chat_messages")
        .select("channel_id")
        .eq("tenant_id", ctx.tenantId)
        .not("channel_id", "is", null)
        .eq("is_read", false)
        .neq("sender_user_id", ctx.authUser.id);

      const counts = {};
      (response.data || []).forEach(function (row) {
        counts[row.channel_id] = (counts[row.channel_id] || 0) + 1;
      });
      state.channelUnread = counts;
    } catch (error) {
      console.warn("Channel unread count load skipped:", error.message);
    }
  }

  async function loadChannelMessages(channelId) {
    const ctx = getContext();
    if (!ctx || !ctx.supabaseClient || !ctx.tenantId) return;

    try {
      const response = await ctx.supabaseClient
        .from("team_chat_messages")
        .select("*")
        .eq("tenant_id", ctx.tenantId)
        .eq("channel_id", channelId)
        .order("created_at", { ascending: true })
        .limit(300);

      if (response.error) {
        console.warn("Channel message load skipped:", response.error.message);
        return;
      }

      state.channelMessages[channelId] = response.data || [];
      loadReadCounts((response.data || []).map(function (m) { return m.id; }));
    } catch (error) {
      console.warn("Channel message load skipped:", error.message);
    }
  }

  async function selectChannel(channelId) {
    state.activeKey = "channel:" + channelId;
    notifyRender();
    await loadChannelMessages(channelId);
    notifyRender();
    await markChannelRead(channelId);
  }

  async function markChannelRead(channelId) {
    const ctx = getContext();
    if (!ctx || !ctx.supabaseClient || !ctx.authUser) return;

    const rows = state.channelMessages[channelId] || [];
    const unreadIds = rows
      .filter(function (r) { return r.sender_user_id !== ctx.authUser.id && !r.is_read; })
      .map(function (r) { return r.id; });

    state.channelUnread[channelId] = 0;

    if (unreadIds.length) {
      try {
        await ctx.supabaseClient
          .from("team_chat_messages")
          .update({ is_read: true, updated_at: new Date().toISOString() })
          .in("id", unreadIds);

        rows.forEach(function (m) {
          if (unreadIds.indexOf(m.id) !== -1) m.is_read = true;
        });
      } catch (error) {
        console.warn("Could not mark channel read:", error.message);
      }
    }

    // Every other-authored message in this channel, not just the
    // currently-unread ones - see the "Read receipts" block above
    // markActiveConversationRead() for why is_read/unreadIds can't be
    // reused to gate this.
    const otherIds = rows.filter(function (r) { return r.sender_user_id !== ctx.authUser.id; }).map(function (r) { return r.id; });
    if (otherIds.length) await recordGroupReadReceipts(otherIds);

    notifyRender();
  }

  // name is required, "#" prefix optional (stripped server-side too, and
  // by the caller's own UI - see openCreateChannelModal() in
  // my-team-chat.html). Any active staff member can create a channel -
  // upsert_ungani_chat_channel() only gates on can_access, not is_owner
  // (loosened from the original owner-only design per explicit direction:
  // creating a channel is low-risk, matching the WhatsApp-simplicity
  // goal). Archiving a channel is still owner-only
  // (owner_archive_ungani_chat_channel, unchanged) - removal is a more
  // consequential action than creation.
  async function createChannel(name, description) {
    const ctx = getContext();
    if (!ctx || !ctx.supabaseClient) return { ok: false, message: "Still loading - try again in a moment." };

    try {
      const response = await ctx.supabaseClient.rpc("upsert_ungani_chat_channel", {
        p_name: name,
        p_description: description || null
      });

      if (response.error) return { ok: false, message: response.error.message };
      if (!response.data || response.data.ok !== true) {
        return { ok: false, message: (response.data && response.data.message) || "Could not create channel." };
      }

      await loadChannels();
      await selectChannel(response.data.channel_id);
      return { ok: true };
    } catch (error) {
      return { ok: false, message: error.message };
    }
  }

  function getChannelList() {
    return state.channels.map(function (c) {
      return {
        id: c.id,
        name: c.name,
        description: c.description,
        unread: state.channelUnread[c.id] || 0
      };
    });
  }

  // Called from a host page's own poll (channels are outside this
  // module's startPolling() - see the "Channels" comment above
  // loadChannels()). Refreshes the open channel's messages without
  // stealing scroll position or re-triggering the "start a DM" scroll-to-
  // bottom behaviour - same silent-refresh contract loadMessages() uses
  // for the Team/DM side on its own 12s poll.
  async function refreshActiveChannelIfOpen() {
    if (state.activeKey.indexOf("channel:") !== 0) return;
    const channelId = state.activeKey.slice(8);
    await loadChannelMessages(channelId);
    notifyRender();
    await markChannelRead(channelId);
  }

  // --- Read receipts ---------------------------------------------------
  // WhatsApp-style single/double tick (Team Chat redesign, 2026-09). DMs
  // need no new table or function here - team_chat_messages.is_read is
  // already an exact per-message read flag for a DM (exactly one possible
  // reader), so readReceiptHtml() reads it directly. Team broadcast and
  // channel messages have multiple possible readers sharing that SAME
  // is_read column, which only ever means "at least one member has read
  // this" - real bug avoided: gating a per-reader receipt write on
  // `!is_read` would mean only the FIRST reader of a group message ever
  // gets recorded, since is_read flips true globally after them and every
  // later reader's unreadIds filter would then skip it. recordGroupReadReceipts()
  // is therefore called with EVERY other-authored message in the bucket,
  // not just the currently-unread ones, and relies on the reads table's
  // own (message_id, reader_user_id) primary key + ignoreDuplicates to
  // stay cheap on repeat calls (every markActiveConversationRead()/
  // markChannelRead(), including the popup's own calls on any of the
  // other 30+ pages - group read counts should reflect reads from
  // wherever they happen, not just the dedicated page).

  async function loadReadCounts(messageIds) {
    const ctx = getContext();
    if (!ctx || !ctx.supabaseClient || !messageIds.length) return;

    try {
      const response = await ctx.supabaseClient
        .from("team_chat_message_reads")
        .select("message_id")
        .in("message_id", messageIds);

      const counts = {};
      messageIds.forEach(function (id) { counts[id] = 0; });
      (response.data || []).forEach(function (row) {
        counts[row.message_id] = (counts[row.message_id] || 0) + 1;
      });

      Object.assign(state.readCounts, counts);
      notifyRender();
    } catch (error) {
      console.warn("Read-count load skipped:", error.message);
    }
  }

  async function recordGroupReadReceipts(messageIds) {
    const ctx = getContext();
    if (!ctx || !ctx.supabaseClient || !ctx.tenantId || !ctx.authUser || !messageIds.length) return;

    try {
      const rows = messageIds.map(function (id) {
        return { message_id: id, reader_user_id: ctx.authUser.id, tenant_id: ctx.tenantId };
      });

      await ctx.supabaseClient
        .from("team_chat_message_reads")
        .upsert(rows, { onConflict: "message_id,reader_user_id", ignoreDuplicates: true });
    } catch (error) {
      console.warn("Could not record read receipts:", error.message);
    }

    await loadReadCounts(messageIds);
  }

  // isMine-only - a sender sees their own message's receipt, matching
  // every real chat app (nobody needs a tick on someone else's message).
  function readReceiptHtml(row) {
    const isGroup = !!row.channel_id || (!row.recipient_team_member_id && !row.recipient_is_owner);

    if (isGroup) {
      const count = state.readCounts[row.id] || 0;
      if (count > 0) {
        return `<span class="ttc-receipt read" title="Seen by ${count}"><i data-lucide="check-check"></i> Seen by ${count}</span>`;
      }
      return `<span class="ttc-receipt sent" title="Sent"><i data-lucide="check"></i></span>`;
    }

    if (row.is_read) {
      return `<span class="ttc-receipt read" title="Read"><i data-lucide="check-check"></i></span>`;
    }
    return `<span class="ttc-receipt sent" title="Sent"><i data-lucide="check"></i></span>`;
  }

  async function markActiveConversationRead() {
    const ctx = getContext();
    if (!ctx || !ctx.supabaseClient || !ctx.tenantId || !ctx.authUser) return;

    const rows = state.conversations[state.activeKey] || [];
    const unreadIds = rows
      .filter(function (r) { return r.sender_user_id !== ctx.authUser.id && !r.is_read; })
      .map(function (r) { return r.id; });

    if (unreadIds.length) {
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
      } catch (error) {
        console.warn("Could not mark team chat read:", error.message);
      }
    }

    if (state.activeKey === "team") {
      const otherIds = rows.filter(function (r) { return r.sender_user_id !== ctx.authUser.id; }).map(function (r) { return r.id; });
      if (otherIds.length) await recordGroupReadReceipts(otherIds);
    }

    notifyRender();
  }

  async function send(event) {
    if (event && event.preventDefault) event.preventDefault();

    const ctx = getContext();
    // #utcInput is the popup's own input; #ttcInput is my-team-chat.html's
    // (embedded mode) - send() is the one function genuinely shared by
    // both UIs, so it has to know about both ids rather than assuming the
    // popup's.
    const input = document.getElementById("utcInput") || document.getElementById("ttcInput");
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
    } else if (state.activeKey.indexOf("channel:") === 0) {
      payload.channel_id = state.activeKey.slice(8);
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

      if (state.activeKey.indexOf("channel:") === 0) {
        await loadChannelMessages(state.activeKey.slice(8));
        notifyRender();
      } else {
        await loadMessages(true);
      }
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

  // Registers a host page's own render function in place of this module's
  // popup DOM rendering (see notifyRender()). Pass null to go back to the
  // default popup rendering.
  function setRenderCallback(fn) {
    state.renderCallback = typeof fn === "function" ? fn : null;
  }

  window.UnganiTeamChat = {
    init: init,
    toggle: toggle,
    close: close,
    startPolling: startPolling,
    selectConversation: selectConversation,
    startDm: startDm,
    send: send,
    getUnreadCount: totalUnread,
    // Data-layer access for a host page rendering its own layout (e.g.
    // my-team-chat.html) instead of this module's own popup DOM. All of
    // these read the exact same state the popup uses - there is still
    // only one real implementation of loading/sending/read-marking.
    setRenderCallback: setRenderCallback,
    getConversationList: conversationList,
    getActiveKey: function () { return state.activeKey; },
    getMessagesForActive: function () {
      if (state.activeKey.indexOf("channel:") === 0) {
        return state.channelMessages[state.activeKey.slice(8)] || [];
      }
      return state.conversations[state.activeKey] || [];
    },
    getMessagesFor: function (key) { return state.conversations[key] || []; },
    getRoster: function () { return state.roster; },
    getMyIdentity: myIdentity,
    getAvailableDmTargets: availableDmTargets,
    formatTime: formatTime,
    // Channels - see the "Channels" block above startDm() for the
    // underlying logic. loadChannels() itself is also called internally
    // by the launcher's own toggle() for its unread summary; the rest
    // (selectChannel/createChannel/getChannelList/refreshActiveChannel)
    // are embedded-mode only (my-team-chat.html), since only that page
    // ever shows real channel content.
    loadChannels: loadChannels,
    selectChannel: selectChannel,
    createChannel: createChannel,
    getChannelList: getChannelList,
    getIsOwner: function () { return state.isOwner; },
    refreshActiveChannel: refreshActiveChannelIfOpen,
    // Initials-based avatars (embedded mode only, see the "Avatars" block
    // above init()) - avatarHtml("team"|"channel"|<auth_user_id>, name,
    // sizePx) returns the complete markup, so every render site (list
    // rows, thread headers, message bubbles) uses the identical
    // color/initials logic instead of three hand-copied versions.
    avatarHtml: avatarHtml,
    // Read receipts (embedded mode only - the popup shows no receipt
    // markup, though it still contributes to the underlying read data via
    // markActiveConversationRead(), same as any of the other 30+ pages).
    readReceiptHtml: readReceiptHtml
  };
})();
