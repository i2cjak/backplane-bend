// Backplane browser host.
//
// This file only moves data: JSON <-> Bend values, a keyed DOM patch of the
// Node tree app.bend's view returns, event delegation back to app.bend's
// act, and the socket. No product decision is made here (AGENTS.md: the UI
// is dumb).

import App from "./app.bend";

// JSON <-> Bend Json
// ------------------

function toJson(v) {
  if (v === null || v === undefined) return { $: "Null" };
  if (typeof v === "boolean") return { $: "Flag", value: v };
  if (typeof v === "number") return { $: "Num", raw: String(v) };
  if (typeof v === "string") return { $: "Str", text: v };
  if (Array.isArray(v)) {
    let items = { $: "End" };
    for (let i = v.length - 1; i >= 0; i -= 1) items = { $: "Item", head: toJson(v[i]), tail: items };
    return { $: "Arr", items };
  }
  let fields = { $: "End" };
  const keys = Object.keys(v);
  for (let i = keys.length - 1; i >= 0; i -= 1) {
    fields = { $: "Field", key: keys[i], value: toJson(v[keys[i]]), tail: fields };
  }
  return { $: "Obj", fields };
}

function* each(list) {
  for (let xs = list; xs && xs.$ === "Con"; xs = xs.tail) yield xs.head;
}

// DOM patch
// ---------

const EVENTS = ["click", "input"];

function create(v) {
  if (v.$ === "Txt") return document.createTextNode(v.text);
  const el = document.createElement(v.tag);
  el.__v = { $: "El", tag: v.tag, key: v.key, attrs: { $: "Nil" }, kids: { $: "Nil" } };
  el.__kids = [];
  patch(el, v);
  return el;
}

function setAttrs(el, oldAttrs, attrs) {
  const seen = new Set();
  for (const a of each(attrs)) {
    if (a.$ === "At") {
      seen.add(a.name);
      if (a.name === "value") {
        if (el.value !== a.value) el.value = a.value;
      } else if (el.getAttribute(a.name) !== a.value) {
        el.setAttribute(a.name, a.value);
      }
    } else {
      const name = "data-on-" + a.event;
      seen.add(name);
      if (el.getAttribute(name) !== a.action) el.setAttribute(name, a.action);
    }
  }
  for (const a of each(oldAttrs)) {
    const name = a.$ === "At" ? a.name : "data-on-" + a.event;
    if (!seen.has(name)) {
      if (name === "value") el.value = "";
      else el.removeAttribute(name);
    }
  }
}

function same(a, b) {
  return a.$ === b.$ && (a.$ === "Txt" || (a.tag === b.tag && a.key === b.key));
}

// make el (whose last vnode is el.__v) match v
function patch(el, v) {
  const old = el.__v;
  setAttrs(el, old.attrs, v.attrs);
  const kids = [...each(v.kids)];
  const prev = el.__kids;
  const byKey = new Map();
  const free = [];
  for (const p of prev) {
    if (p.v.$ === "El" && p.v.key) byKey.set(p.v.tag + "\u0000" + p.v.key, p);
    else free.push(p);
  }
  const next = [];
  let f = 0;
  for (let i = 0; i < kids.length; i += 1) {
    const k = kids[i];
    let hit = null;
    if (k.$ === "El" && k.key) {
      hit = byKey.get(k.tag + "\u0000" + k.key) ?? null;
      if (hit) byKey.delete(k.tag + "\u0000" + k.key);
    } else {
      while (f < free.length && !same(free[f].v, k)) f += 1;
      if (f < free.length) hit = free[f++];
    }
    let node;
    if (hit) {
      node = hit.node;
      if (k.$ === "Txt") {
        if (node.nodeValue !== k.text) node.nodeValue = k.text;
      } else if (hit.v !== k) {
        patch(node, k);
      }
      hit.used = true;
    } else {
      node = create(k);
    }
    const at = el.childNodes[i];
    if (at !== node) el.insertBefore(node, at ?? null);
    next.push({ v: k, node });
  }
  for (const p of prev) if (!p.used && p.node.parentNode === el) el.removeChild(p.node);
  for (const p of next) p.used = false;
  el.__kids = next;
  el.__v = v;
}

// Loop
// ----

const root = document.getElementById("root");
root.__v = { $: "El", tag: "div", key: "", attrs: { $: "Nil" }, kids: { $: "Nil" } };
root.__kids = [];

const now = () => BigInt(Math.floor(Date.now() / 1000));
let ui = App.init(now());
let socket = null;
let queued = false;
let scroll = false;

function render() {
  queued = false;
  const tl = document.getElementById("timeline");
  const pinned = tl ? tl.scrollHeight - tl.scrollTop - tl.clientHeight < 40 : true;
  patch(root, { $: "El", tag: "div", key: "", attrs: { $: "Nil" }, kids: { $: "Con", head: App.view(ui), tail: { $: "Nil" } } });
  const tl2 = document.getElementById("timeline");
  if (tl2 && (scroll || pinned)) tl2.scrollTop = tl2.scrollHeight;
  scroll = false;
}

function later() {
  if (!queued) {
    queued = true;
    requestAnimationFrame(render);
  }
}

function copy(text) {
  if (navigator.clipboard && window.isSecureContext) {
    navigator.clipboard.writeText(text);
    return;
  }
  const t = document.createElement("textarea");
  t.value = text;
  document.body.appendChild(t);
  t.select();
  document.execCommand("copy");
  t.remove();
}

function run(cmds) {
  for (const c of each(cmds)) {
    if (c.$ === "Send") {
      if (socket && socket.readyState === 1) socket.send(c.text);
    } else if (c.$ === "Copy") {
      copy(c.text);
    } else if (c.$ === "Focus") {
      requestAnimationFrame(() => document.getElementById(c.id)?.focus());
    } else if (c.$ === "Scroll") {
      scroll = true;
    }
  }
}

function dispatch(action, value) {
  const r = App.act(ui, action, value);
  ui = r.ui;
  run(r.cmds);
  later();
}

function valueOf(el) {
  const v = el.getAttribute("data-value");
  if (v === null) return el.value ?? "";
  if (v.startsWith("#")) return document.getElementById(v.slice(1))?.value ?? "";
  return v;
}

for (const ev of EVENTS) {
  document.addEventListener(ev, (e) => {
    const el = e.target.closest?.(`[data-on-${ev}]`);
    if (!el) return;
    const action = el.getAttribute(`data-on-${ev}`);
    dispatch(action, ev === "input" ? el.value : valueOf(el));
  });
}

document.addEventListener("keydown", (e) => {
  const el = e.target.closest?.("[data-enter]");
  if (!el || e.key !== "Enter" || e.shiftKey || e.isComposing) return;
  e.preventDefault();
  dispatch(el.getAttribute("data-enter"), valueOf(el));
});

// Socket
// ------

let backoff = 250;

// A tailnet link carries the pairing token in its fragment; keep it for
// later visits and never send it anywhere but this server's socket.
const token = (() => {
  const m = location.hash.match(/token=([0-9a-f]+)/);
  if (m) {
    localStorage.setItem("backplane-token", m[1]);
    history.replaceState(null, "", location.pathname);
  }
  return localStorage.getItem("backplane-token") ?? "";
})();

function connect() {
  const proto = location.protocol === "https:" ? "wss:" : "ws:";
  const s = new WebSocket(`${proto}//${location.host}/ws${token ? "?token=" + token : ""}`);
  s.onopen = () => {
    socket = s;
    backoff = 250;
    ui = App.online(ui, true);
    later();
  };
  s.onmessage = (e) => {
    ui = App.recv(ui, toJson(JSON.parse(e.data)));
    later();
  };
  s.onclose = () => {
    if (socket === s) socket = null;
    ui = App.online(ui, false);
    later();
    setTimeout(connect, backoff);
    backoff = Math.min(backoff * 2, 5000);
  };
}

setInterval(() => {
  ui = App.tick(ui, now());
  later();
}, 30000);

connect();
render();
