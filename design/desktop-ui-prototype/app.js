"use strict";

(() => {
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
  const rooms = window.PAL_ROOMS;
  const storageKey = "gd-pal-desktop-design-v1";
  const validPoses = ["free", "window", "taskbar"];
  let saved = {};
  try { saved = JSON.parse(localStorage.getItem(storageKey) || "{}"); } catch { /* file:// or private storage can be unavailable. */ }
  if (!saved || typeof saved !== "object") saved = {};
  const state = {
    roomId: rooms.some(room => room.id === saved.roomId) ? saved.roomId : rooms[0].id,
    panelOpen: typeof saved.panelOpen === "boolean" ? saved.panelOpen : true,
    pose: validPoses.includes(saved.pose) ? saved.pose : "window",
    view: "call", panel: "chat", sound: false, busy: false,
    messages: [], serial: 0, generation: 0, replyTimer: null, streamTimer: null,
    windowPosition: null, freePosition: null, petRect: null, initializedDesktop: false
  };
  const currentRoom = () => rooms.find(room => room.id === state.roomId) || rooms[0];
  const clamp = (value, minimum, maximum) => Math.max(minimum, Math.min(value, Math.max(minimum, maximum)));
  const localTime = () => new Intl.DateTimeFormat("zh-CN", { timeZone: "Asia/Shanghai", hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date());
  const escape = value => String(value).replace(/[&<>"']/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]);
  const icon = name => `<svg class="icon" aria-hidden="true"><use href="#i-${name}"/></svg>`;
  const node = (tag, className, text) => { const element = document.createElement(tag); if (className) element.className = className; if (text !== undefined) element.textContent = text; return element; };
  function savePreferences() {
    try { localStorage.setItem(storageKey, JSON.stringify({ roomId: state.roomId, panelOpen: state.panelOpen, pose: state.pose })); } catch { /* All controls remain usable without persistence. */ }
  }
  let toastTimer;
  function toast(message) {
    clearTimeout(toastTimer);
    const element = $("#toast");
    element.textContent = message;
    element.hidden = false;
    toastTimer = setTimeout(() => { element.hidden = true; }, 2600);
  }

  // Background renderers own only the backdrop. Character and controls stay in their own layers.
  // Renderer contract: prepare(room) -> Promise<{ element, dispose() }>.
  // A future "scene3d" adapter can return a canvas and release its renderer in dispose().
  const backgroundRenderers = {
    image: room => new Promise((resolve, reject) => {
      const image = new Image();
      image.className = "room-layer";
      image.alt = "";
      image.onload = () => resolve({ element: image, dispose() { image.remove(); } });
      image.onerror = () => reject(new Error("房间暂时无法打开，请试试另一间。"));
      image.src = room.background;
    })
  };
  class BackgroundHost {
    constructor(element) { this.element = element; this.active = null; this.revision = 0; }
    async show(room) {
      const revision = ++this.revision;
      const factory = backgroundRenderers[room.kind];
      if (!factory) { toast("这个房间暂时无法在原型中打开。"); return false; }
      try {
        const prepared = await factory(room);
        if (revision !== this.revision) { prepared.dispose(); return false; }
        if (this.active) this.active.dispose();
        this.element.replaceChildren(prepared.element);
        this.active = prepared;
        return true;
      } catch (error) { if (revision === this.revision) toast(error.message); return false; }
    }
  }
  const background = new BackgroundHost($("#room-host"));
  async function selectRoom(id, notify = true) {
    const room = rooms.find(item => item.id === id);
    if (!room || !(await background.show(room))) return;
    state.roomId = room.id;
    document.documentElement.style.setProperty("--accent", room.accent);
    $("#stage-description").textContent = room.caption;
    $("#stage-room-name").textContent = room.name;
    $("#stage-room-time").textContent = room.time;
    $("#context-name").textContent = "日常 · " + room.name;
    $("#context-description").textContent = room.context;
    $("#selected-room-name").textContent = room.name;
    updateRoomCards();
    if (state.panel === "story") renderAuxiliary();
    savePreferences();
    if (notify) toast("已来到" + room.name + "，刚才的对话还在。");
  }
  function buildRoomCards() {
    const grid = $("#room-grid");
    for (const [index, room] of rooms.entries()) {
      const card = node("button", "room-card");
      card.dataset.room = room.id;
      card.style.setProperty("--room-accent", room.accent);
      card.setAttribute("aria-label", "选择" + room.name);
      card.innerHTML = `<div class="room-card-image"><img src="${escape(room.thumbnail)}" alt="${escape(room.name)}的室内场景"><span class="room-card-badge" hidden>${icon("check")}正在停留</span><span class="room-card-time">${escape(room.time)}</span></div><div class="room-card-content"><div class="eyebrow">0${index + 1} / ${escape(room.english)}</div><h2>${escape(room.name)}${icon("arrow")}</h2><p>${escape(room.description)}</p><div class="room-card-tags">${escape(room.mood)}</div></div>`;
      grid.append(card);
    }
    $(".room-section-label b").textContent = String(rooms.length).padStart(2, "0");
    updateRoomCards();
  }
  function updateRoomCards() {
    $$("[data-room]").forEach(card => {
      const selected = card.dataset.room === state.roomId;
      card.classList.toggle("selected", selected);
      card.setAttribute("aria-pressed", String(selected));
      $(".room-card-badge", card).hidden = !selected;
    });
  }

  function showView(view) {
    if (!["call", "rooms", "desktop"].includes(view)) view = "call";
    state.view = view;
    $$(".view").forEach(element => { element.hidden = element.id !== "view-" + view; });
    $$(".view-tab").forEach(button => {
      const active = button.dataset.view === view;
      button.classList.toggle("active", active);
      if (active) button.setAttribute("aria-current", "page"); else button.removeAttribute("aria-current");
    });
    closeInteractionMenu();
    if (view === "desktop") requestAnimationFrame(layoutDesktop);
  }
  function setPanelOpen(open, returnFocus = false) {
    state.panelOpen = open;
    $("#call-layout").classList.toggle("sidebar-closed", !open);
    $("#conversation-sidebar").hidden = !open;
    $("#chat-toggle").setAttribute("aria-pressed", String(open));
    $("#chat-toggle").title = open ? "收起对话栏" : "展开对话栏";
    $("#focus-button").setAttribute("aria-pressed", String(!open));
    $("#focus-button").setAttribute("aria-label", open ? "展开角色画面" : "恢复对话布局");
    $("#focus-button").title = open ? "展开角色画面" : "恢复对话布局";
    savePreferences();
    if (returnFocus) $("#chat-toggle").focus();
  }
  function showPanel(panel) {
    if (!["chat", "profile", "story", "memory"].includes(panel)) return;
    state.panel = panel;
    showView("call");
    setPanelOpen(true);
    $("#chat-panel").hidden = panel !== "chat";
    $("#aux-panel").hidden = panel === "chat";
    $("#clear-chat").hidden = panel !== "chat";
    const headings = { chat: ["A MOMENT TOGETHER", "我们的对话"], profile: ["THE PERSON BESIDE YOU", "关于凛"], story: ["OUR UNFINISHED STORY", "此刻的故事"], memory: ["THINGS WE KEEP", "共同回忆"] };
    $("#sidebar-kicker").textContent = headings[panel][0];
    $("#sidebar-title").replaceChildren(document.createTextNode(headings[panel][1]), node("span", "heading-dot"));
    $$(".rail-button[data-panel]").forEach(button => {
      const active = button.dataset.panel === panel;
      button.classList.toggle("active", active);
      button.setAttribute("aria-pressed", String(active));
    });
    if (panel !== "chat") renderAuxiliary();
  }
  function renderAuxiliary() {
    const room = currentRoom();
    let body = "";
    if (state.panel === "profile") body = `<div class="aux-portrait"><img src="assets/character-portrait.svg" alt="凛的头像"></div><div class="eyebrow">RIN · 日常里的同行者</div><h3 style="margin-top:12px">凛</h3><p>喜欢把故事读到很晚，也喜欢在你说话时，安静地看着你。</p><div class="tag-row"><span>温柔慢热</span><span>喜欢雨天</span><span>认真倾听</span></div><span class="aux-label">相处的方式</span><p>你可以分享今天的小事，也可以什么都不说。对她来说，陪伴本身就已经有意义。</p><span class="aux-label">此刻的心情</span><p>放松，带着一点见到你的雀跃。</p>`;
    if (state.panel === "story") body = `<span class="story-number">01</span><div class="eyebrow">日常篇 · 未完待续</div><h3 style="margin-top:12px">${escape(room.name)}</h3><img class="story-image" src="${escape(room.thumbnail)}" alt="${escape(room.name)}"><p>${escape(room.description)}</p><span class="aux-label">这一幕</span><p>${escape(room.arrival)}没有预定好的结局，接下来的故事，由你们慢慢写。</p><div class="tag-row"><span>一对一陪伴</span><span>${escape(room.time)}</span><span>日常剧情</span></div><button class="subtle-button" data-view="rooms">${icon("room")}换一个场景</button>`;
    if (state.panel === "memory") body = `<div class="eyebrow">回忆示例</div><h3 style="margin-top:12px">小事，也值得记住。</h3><p>一句不经意的话，一次安静的陪伴。共同的日常，就这样一点点积攒。</p><article class="aux-card"><div class="eyebrow">生活偏好</div><h4>你喜欢不被催促的夜晚</h4><p>忙完以后，比起建议，更想先有人听你说完。</p></article><article class="aux-card"><div class="eyebrow">我们的约定</div><h4>那本书，下次接着读</h4><p>书签留在了第十二页，故事还没有结束。</p></article><article class="aux-card"><div class="eyebrow">温暖的瞬间</div><h4>第一次一起听雨</h4><p>窗外雨下了很久，桌上的茶却一直温热。</p></article>`;
    $("#aux-panel").innerHTML = `<button class="aux-back" data-panel="chat">${icon("back")}回到对话</button>${body}`;
  }

  const scroll = $("#message-scroll");
  const atBottom = () => scroll.scrollHeight - scroll.scrollTop - scroll.clientHeight < 55;
  function scrollToBottom() { scroll.scrollTop = scroll.scrollHeight; $("#new-message-button").hidden = true; }
  function messageRecord(role, text, narration = "") { return { id: ++state.serial, role, text, narration, time: localTime(), streaming: false }; }
  function renderMessages(forceBottom = false) {
    const follow = forceBottom || atBottom();
    const oldTop = scroll.scrollTop;
    const list = $("#messages");
    const fragment = document.createDocumentFragment();
    if (!state.messages.length) {
      const empty = node("div", "empty-chat");
      empty.innerHTML = `${icon("chat")}<h3>这一刻，留给你们。</h3><p>说说今天的事，或者打个招呼。<br>凛一直在这里。</p>`;
      fragment.append(empty);
    } else {
      fragment.append(node("div", "message-divider", "今天 · 一段属于我们的时间"));
      for (const message of state.messages) {
        const article = node("article", "message " + message.role + (message.streaming ? " streaming" : ""));
        article.dataset.messageId = message.id;
        if (message.role !== "narration") {
          const author = node("div", "message-author");
          if (message.role === "assistant") { const avatar = node("img"); avatar.src = "assets/character-avatar.svg"; avatar.alt = ""; author.append(avatar); }
          author.append(node("span", "", message.role === "user" ? "你" : "凛"), node("span", "", message.time));
          article.append(author);
        }
        if (message.narration) article.append(node("p", "message-narration", message.narration));
        if (message.role !== "narration") article.append(node("p", "message-text", message.text || (message.streaming ? "…" : "")));
        fragment.append(article);
      }
    }
    list.replaceChildren(fragment);
    if (follow) requestAnimationFrame(scrollToBottom);
    else { scroll.scrollTop = oldTop; $("#new-message-button").hidden = false; }
  }
  function refreshComposer() {
    const send = $("#send-button");
    send.disabled = !state.busy && !$("#message-input").value.trim();
    send.setAttribute("aria-label", state.busy ? "停止回复" : "发送消息");
    send.title = state.busy ? "停止回复" : "Ctrl + Enter 发送";
    $("use", send).setAttribute("href", state.busy ? "#i-stop" : "#i-send");
    $("#character-count").textContent = $("#message-input").value.length + " / 4000";
    $("#reply-state").classList.toggle("busy", state.busy);
    $("#reply-state span:last-child").textContent = state.busy ? "凛正在回应你…" : "凛正在聆听";
    $("#desktop-send").disabled = state.busy || !$("#desktop-input").value.trim();
  }
  function updateBubble() {
    const last = [...state.messages].reverse().find(message => message.role === "assistant");
    $("#desktop-bubble-text").textContent = last ? (last.text || "嗯，我在听。让我想一想…") : "忙你的就好，偶尔看看我就够啦。";
    if (!$("#desktop-bubble").hidden && state.view === "desktop") positionBubble();
  }
  function stopReply() {
    state.generation++;
    clearTimeout(state.replyTimer);
    clearInterval(state.streamTimer);
    state.busy = false;
    state.messages = state.messages.filter(message => !(message.streaming && !message.text));
    state.messages.forEach(message => { message.streaming = false; });
    refreshComposer();
    renderMessages();
    updateBubble();
  }
  function pickReply(text, room) {
    if (/累|疲|烦|忙/.test(text)) return room.id === "warm-bedroom" ? room.reply : "辛苦啦。先把肩膀放松一点，好吗？\n今天没有处理完的事情，就先放在一旁。现在的这几分钟，只属于你。";
    if (/安静|不用说|待一会|陪我/.test(text)) return "好呀，那我们就安静地待一会儿。\n不需要找话题，也不用担心冷场。你在这里，我就很开心了。";
    if (/书|读/.test(text)) return "在读一本关于旅行的小书。里面有句话我很喜欢：有时候，最好的目的地，就是有人等你回来的地方。\n要不要一起读下一页？";
    if (/茶|喝/.test(text)) return "当然。这杯给你，小心还有一点烫。\n我喜欢这种时候——茶慢慢凉下来，我们的距离却近了一点。";
    return room.reply;
  }
  function sendMessage(raw, source = "main") {
    const text = raw.trim().slice(0, 4000);
    if (!text || state.busy) return;
    const room = currentRoom();
    const reply = pickReply(text, room);
    state.messages.push(messageRecord("user", text));
    const assistant = messageRecord("assistant", "", room.arrival);
    assistant.streaming = true;
    state.messages.push(assistant);
    state.busy = true;
    const generation = ++state.generation;
    $(source === "desktop" ? "#desktop-input" : "#message-input").value = "";
    refreshComposer();
    renderMessages(true);
    updateBubble();
    state.replyTimer = setTimeout(() => {
      if (generation !== state.generation) return;
      const characters = Array.from(reply);
      let cursor = 0;
      state.streamTimer = setInterval(() => {
        if (generation !== state.generation) return;
        const follow = atBottom();
        cursor = Math.min(characters.length, cursor + 2);
        assistant.text = characters.slice(0, cursor).join("");
        const paragraph = $(`[data-message-id="${assistant.id}"] .message-text`);
        if (paragraph) paragraph.textContent = assistant.text;
        if (follow) scrollToBottom(); else $("#new-message-button").hidden = false;
        updateBubble();
        if (cursor === characters.length) {
          clearInterval(state.streamTimer);
          assistant.streaming = false;
          state.busy = false;
          const article = $(`[data-message-id="${assistant.id}"]`);
          if (article) article.classList.remove("streaming");
          refreshComposer();
        }
      }, 38);
    }, 750);
  }
  $("#chat-form").addEventListener("submit", event => {
    event.preventDefault();
    if (state.busy) stopReply(); else sendMessage($("#message-input").value);
  });
  $("#message-input").addEventListener("input", refreshComposer);
  $("#message-input").addEventListener("keydown", event => {
    if (event.isComposing || event.keyCode === 229) return;
    if (event.key === "Enter" && event.ctrlKey) { event.preventDefault(); if (!state.busy) sendMessage(event.currentTarget.value); }
  });
  $("#desktop-chat-form").addEventListener("submit", event => { event.preventDefault(); sendMessage($("#desktop-input").value, "desktop"); });
  $("#desktop-input").addEventListener("input", refreshComposer);
  $("#desktop-input").addEventListener("keydown", event => { if (event.key === "Enter" && (event.isComposing || event.keyCode === 229)) event.preventDefault(); });
  $("#clear-chat").addEventListener("click", () => { stopReply(); state.messages = []; renderMessages(true); updateBubble(); toast("示例对话已清空，重新打个招呼吧。"); });
  $("#new-message-button").addEventListener("click", scrollToBottom);
  scroll.addEventListener("scroll", () => { if (atBottom()) $("#new-message-button").hidden = true; });
  $("#chat-toggle").addEventListener("click", () => setPanelOpen(!state.panelOpen));
  $("#collapse-chat").addEventListener("click", () => setPanelOpen(false, true));
  $("#focus-button").addEventListener("click", () => setPanelOpen(!state.panelOpen));

  function closeInteractionMenu() { $("#interaction-menu").hidden = true; $("#interaction-button").setAttribute("aria-expanded", "false"); }
  $("#interaction-button").addEventListener("click", () => {
    const menu = $("#interaction-menu"); menu.hidden = !menu.hidden;
    $("#interaction-button").setAttribute("aria-expanded", String(!menu.hidden));
  });
  $("#sound-button").addEventListener("click", () => {
    state.sound = !state.sound;
    const button = $("#sound-button");
    button.setAttribute("aria-pressed", String(state.sound));
    $("use", button).setAttribute("href", state.sound ? "#i-volume" : "#i-muted");
    $("span", button).textContent = state.sound ? "声音开" : "声音关";
    toast(state.sound ? "声音已开启 · 演示状态" : "声音已关闭 · 演示状态");
  });
  function interact(action) {
    const descriptions = { greet: "你向她挥了挥手。她微微歪头，也笑着向你打招呼。", tea: "你们一起捧起茶杯，热气模糊了她温柔的笑意。", quiet: "你们安静地坐着。她轻轻点了点头，没有打破这份宁静。" };
    state.messages.push(messageRecord("narration", "", descriptions[action]));
    renderMessages(); closeInteractionMenu();
    const portrait = $("#hero-portrait");
    portrait.classList.remove("greeting");
    $(".portrait-frame").classList.remove("responding");
    requestAnimationFrame(() => { portrait.classList.add("greeting"); $(".portrait-frame").classList.add("responding"); });
    toast({ greet: "她也看见你啦。", tea: "茶还热着，慢慢喝。", quiet: "安静的陪伴，也很好。" }[action]);
  }

  const canvas = $("#desktop-canvas");
  const demoWindow = $("#demo-window");
  const pet = $("#desktop-pet");
  const petImage = $("#desktop-pet-image");
  const taskbarHeight = 64;
  function setPose(pose, notify = false) {
    if (!validPoses.includes(pose)) return;
    state.pose = pose;
    petImage.src = pose === "free" ? "assets/character-standing.svg" : "assets/character-seated.svg";
    petImage.alt = { free: "自由站立的凛", window: "坐在窗口上沿的凛", taskbar: "坐在任务栏上沿的凛" }[pose];
    pet.classList.toggle("free", pose === "free");
    $$("[data-pose]").forEach(button => { const active = button.dataset.pose === pose; button.classList.toggle("active", active); button.setAttribute("aria-pressed", String(active)); });
    $("#desktop-pose-hint").textContent = { free: "拖动角色，为她找一个舒服的位置。", window: "她会跟着窗口一起移动。拖动窗口或用方向键试试。", taskbar: "坐在任务栏上，也能陪你把事情慢慢做完。" }[pose];
    savePreferences();
    if (state.view === "desktop") layoutDesktop();
    if (notify) toast({ free: "现在可以自由移动她了。", window: "她在窗口边坐下了。", taskbar: "她在任务栏上找到一个位置。" }[pose]);
  }
  function layoutDesktop() {
    if (state.view !== "desktop") return;
    const height = canvas.clientHeight;
    const width = canvas.clientWidth;
    pet.style.width = clamp((height - 180) * .36, 100, 126) + "px";
    demoWindow.style.height = clamp(height * .44, 160, 258) + "px";
    if (!state.windowPosition) state.windowPosition = { x: width * .23, y: height * .32 };
    if (!state.freePosition) state.freePosition = { x: width * .75, y: height - taskbarHeight - pet.offsetWidth * 1040 / 540 - 12 };
    const minTop = state.pose === "window" ? pet.offsetWidth * 535 / 540 + 12 : 12;
    const maxTop = height - taskbarHeight - demoWindow.offsetHeight - 8;
    state.windowPosition.x = clamp(state.windowPosition.x, 95, width - demoWindow.offsetWidth - 16);
    state.windowPosition.y = clamp(state.windowPosition.y, Math.min(minTop, maxTop), maxTop);
    demoWindow.style.left = state.windowPosition.x + "px";
    demoWindow.style.top = state.windowPosition.y + "px";
    positionPet();
  }
  function positionPet() {
    if (state.view !== "desktop") return;
    const width = canvas.clientWidth;
    const height = canvas.clientHeight;
    const petWidth = pet.offsetWidth;
    const petHeight = petWidth * (state.pose === "free" ? 1040 : 780) / 540;
    const hipOffset = petWidth * 535 / 540;
    let x, y;
    if (state.pose === "window") {
      x = state.windowPosition.x + demoWindow.offsetWidth * .78 - petWidth * .5;
      y = state.windowPosition.y - hipOffset;
    } else if (state.pose === "taskbar") {
      x = width * .79 - petWidth * .5;
      y = height - taskbarHeight - hipOffset;
    } else {
      state.freePosition.x = clamp(state.freePosition.x, 12, width - petWidth - 12);
      state.freePosition.y = clamp(state.freePosition.y, 12, height - taskbarHeight - petHeight - 5);
      x = state.freePosition.x; y = state.freePosition.y;
    }
    pet.style.height = petHeight + "px";
    pet.style.left = x + "px";
    pet.style.top = y + "px";
    pet.classList.toggle("toolbar-low", y < 38);
    state.petRect = { x, y, width: petWidth, height: petHeight };
    positionBubble();
  }
  function positionBubble() {
    const bubble = $("#desktop-bubble");
    if (bubble.hidden || !state.petRect || state.view !== "desktop") return;
    const rect = state.petRect;
    const right = rect.x + rect.width + 10;
    const left = rect.x - bubble.offsetWidth - 10;
    const x = right + bubble.offsetWidth < canvas.clientWidth - 12 ? right : left;
    bubble.style.left = clamp(x, 12, canvas.clientWidth - bubble.offsetWidth - 12) + "px";
    bubble.style.top = clamp(rect.y + 20, 12, canvas.clientHeight - taskbarHeight - bubble.offsetHeight - 12) + "px";
  }
  function toggleBubble(open = $("#desktop-bubble").hidden) {
    $("#desktop-bubble").hidden = !open;
    $("#pet-chat-button").setAttribute("aria-expanded", String(open));
    $("#pet-chat-button").setAttribute("aria-label", open ? "收起聊天气泡" : "展开聊天气泡");
    if (open) { updateBubble(); positionBubble(); $("#desktop-input").focus(); }
  }
  let drag = null;
  const handle = $("#demo-window-handle");
  function startDrag(event, kind) {
    if (event.button !== 0 || (kind === "pet" && state.pose !== "free")) return;
    const origin = kind === "window" ? state.windowPosition : state.freePosition;
    if (!origin) return;
    event.preventDefault();
    drag = { kind, x: event.clientX, y: event.clientY, origin: { ...origin }, moved: false, pointer: event.pointerId };
    event.currentTarget.setPointerCapture(event.pointerId);
    if (kind === "pet") pet.classList.add("dragging");
  }
  function moveDrag(event) {
    if (!drag || drag.pointer !== event.pointerId) return;
    const dx = event.clientX - drag.x, dy = event.clientY - drag.y;
    if (Math.hypot(dx, dy) > 3) drag.moved = true;
    const target = { x: drag.origin.x + dx, y: drag.origin.y + dy };
    if (drag.kind === "window") state.windowPosition = target; else state.freePosition = target;
    layoutDesktop();
  }
  let suppressPetClick = false;
  function endDrag(event) {
    if (!drag || drag.pointer !== event.pointerId) return;
    if (drag.kind === "pet" && drag.moved) { suppressPetClick = true; setTimeout(() => { suppressPetClick = false; }, 0); }
    pet.classList.remove("dragging");
    if (event.currentTarget.hasPointerCapture(event.pointerId)) event.currentTarget.releasePointerCapture(event.pointerId);
    drag = null;
  }
  for (const [element, kind] of [[handle, "window"], [petImage, "pet"]]) {
    element.addEventListener("pointerdown", event => startDrag(event, kind));
    element.addEventListener("pointermove", moveDrag);
    element.addEventListener("pointerup", endDrag);
    element.addEventListener("pointercancel", endDrag);
  }
  handle.addEventListener("keydown", event => {
    const directions = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] };
    const direction = directions[event.key];
    if (!direction || !state.windowPosition) return;
    event.preventDefault();
    state.windowPosition.x += direction[0] * (event.shiftKey ? 25 : 10);
    state.windowPosition.y += direction[1] * (event.shiftKey ? 25 : 10);
    layoutDesktop();
  });
  petImage.addEventListener("click", () => { if (!suppressPetClick) toggleBubble(); });
  petImage.addEventListener("keydown", event => { if (event.key === "Enter" || event.key === " ") { event.preventDefault(); toggleBubble(); } });
  $("#pet-chat-button").addEventListener("click", () => toggleBubble());
  $("#bubble-close").addEventListener("click", () => toggleBubble(false));
  $("#pet-pose-button").addEventListener("click", () => setPose(validPoses[(validPoses.indexOf(state.pose) + 1) % validPoses.length], true));
  new ResizeObserver(() => { if (state.view === "desktop") layoutDesktop(); }).observe(canvas);

  document.addEventListener("click", event => {
    const viewButton = event.target.closest("button[data-view]");
    if (viewButton) showView(viewButton.dataset.view);
    const panelButton = event.target.closest("[data-panel]");
    if (panelButton) showPanel(panelButton.dataset.panel);
    const roomCard = event.target.closest("[data-room]");
    if (roomCard) selectRoom(roomCard.dataset.room);
    const poseButton = event.target.closest("[data-pose]");
    if (poseButton) setPose(poseButton.dataset.pose);
    const suggestion = event.target.closest("[data-suggestion]");
    if (suggestion) { $("#message-input").value = suggestion.dataset.suggestion; refreshComposer(); $("#message-input").focus(); }
    const interaction = event.target.closest("[data-interaction]");
    if (interaction) interact(interaction.dataset.interaction);
    if (!event.target.closest(".interaction-wrap")) closeInteractionMenu();
  });
  document.addEventListener("keydown", event => {
    if (event.key !== "Escape" || $("#about-dialog").open) return;
    if (!$("#interaction-menu").hidden) { closeInteractionMenu(); $("#interaction-button").focus(); }
    else if (state.view === "desktop" && !$("#desktop-bubble").hidden) { toggleBubble(false); petImage.focus(); }
    else if (state.view !== "call") showView("call");
    else if (state.panel !== "chat") showPanel("chat");
    else if (state.panelOpen) setPanelOpen(false, true);
  });
  $("#about-button").addEventListener("click", () => $("#about-dialog").showModal());
  for (const id of ["#about-close", "#about-start"]) $(id).addEventListener("click", () => $("#about-dialog").close());
  $(".brand").addEventListener("click", event => { event.preventDefault(); showView("call"); });
  const sampleRoom = currentRoom();
  state.messages = [
    messageRecord("assistant", "你来啦。刚好泡了热茶，今天过得怎么样？", sampleRoom.arrival),
    messageRecord("user", "忙完了，想在这里待一会儿。"),
    messageRecord("assistant", "那就把今天留在门外吧。\n不用急着说什么，我会陪着你。")
  ];
  state.messages.forEach(message => { message.time = sampleRoom.time; });
  buildRoomCards();
  selectRoom(state.roomId, false);
  setPanelOpen(state.panelOpen);
  setPose(state.pose);
  renderMessages(true);
  refreshComposer();
  showView(location.hash.slice(1) || "call");
  const clock = localTime();
  $(".desktop-clock>span").textContent = clock;
  $(".taskbar-time>span").textContent = clock;
  $(".taskbar-time>small").textContent = new Intl.DateTimeFormat("zh-CN", { timeZone: "Asia/Shanghai", weekday: "long" }).format(new Date());
})();
