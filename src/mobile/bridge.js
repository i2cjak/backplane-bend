// Backplane phone bridge.
//
// Loaded into JavaScriptCore (iOS) or a JavaScriptSandbox isolate
// (Android). It only moves data: server JSON in, the screen JSON and
// commands out, as strings. The native app owns the socket and the views;
// app.bend decides everything (AGENTS.md: the UI is dumb).

import App from "./app.bend";

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

const secs = (n) => BigInt(Math.floor(Number(n)));
let ui = null;

// every call answers {"screen": <screen>, "cmds": [...]} as one string;
// alerts ride along as {"type": "notify", ...} commands
function out(cmds, quiet, alerts) {
  const cs = [];
  for (const c of each(cmds)) {
    if (c.$ === "Send") cs.push({ type: "send", text: c.text });
    else if (c.$ === "Copy") cs.push({ type: "copy", text: c.text });
    else if (c.$ === "Focus") cs.push({ type: "focus", id: c.id });
    else if (c.$ === "Scroll") cs.push({ type: "scroll" });
  }
  for (const a of alerts ?? []) cs.push({ type: "notify", ...a });
  return '{"screen":' + (quiet ? "null" : App.screen(ui)) + ',"cmds":' + JSON.stringify(cs) + "}";
}

globalThis.Backplane = {
  // cid: this phone's id, part of every message id (a resend is stored once)
  start(cid) {
    ui = App.init(secs(Date.now() / 1000), cid);
    return out(null);
  },
  // the socket's query: resume from what this app already holds
  resume() {
    return JSON.stringify({ since: App.seq(ui), origin: App.origin(ui) });
  },
  screen() {
    return out(null);
  },
  recv(text) {
    const r = App.recv(ui, toJson(JSON.parse(text)));
    ui = r.act.ui;
    return out(r.act.cmds, false, JSON.parse(r.alerts));
  },
  register(platform, token, kind, thread, env, bundle) {
    const r = App.register(ui, platform, token, kind, thread, env, bundle);
    ui = r.ui;
    return out(r.cmds, true);
  },
  act(action, value) {
    const r = App.act(ui, action, value);
    ui = r.ui;
    return out(r.cmds);
  },
  // an action whose screen the native side already shows (typing a draft)
  quiet(action, value) {
    const r = App.act(ui, action, value);
    ui = r.ui;
    return out(r.cmds, true);
  },
  online(b) {
    ui = App.online(ui, !!b);
    return out(null);
  },
  tick(now) {
    ui = App.tick(ui, secs(now));
    return out(null);
  },
};
