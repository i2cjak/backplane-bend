// Backplane phone bridge.
//
// Loaded into JavaScriptCore (iOS) or a JavaScriptSandbox isolate
// (Android). It only moves data: the hub's CBOR frames in (as base64), the
// screen JSON and commands out, as strings. The native app owns the socket and the views;
// app.bend decides everything (AGENTS.md: the UI is dumb).
//
// Frames are decoded here rather than by Cbor.decode in Bend: neither
// engine has a JIT in an app, and a 900 KB snapshot took 8 s in Bend
// against 0.5 s here. The result is the same Json tree (cbor.bend is the
// wire format; its dictionaries come from there).

import App from "./app.bend";

function* each(list) {
  for (let xs = list; xs && xs.$ === "Con"; xs = xs.tail) yield xs.head;
}

const secs = (n) => BigInt(Math.floor(Number(n)));

const listed = (list) => Array.from(each(list));
const KEYS = listed(App.cbor_keys());
const WORDS = listed(App.cbor_words());

// base64 to bytes (neither engine has atob)
const B64 = new Int16Array(128).fill(-1);
for (let i = 0; i < 64; i += 1) B64["ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".charCodeAt(i)] = i;
function bytes(b64) {
  const out = new Uint8Array((b64.length * 3) >> 2);
  let n = 0, acc = 0, bits = 0;
  for (let i = 0; i < b64.length; i += 1) {
    const c = b64.charCodeAt(i);
    const v = c < 128 ? B64[c] : -1;
    if (v < 0) continue;
    acc = ((acc << 6) | v) & 0xffffff;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out[n++] = (acc >> bits) & 255;
    }
  }
  return out.subarray(0, n);
}

// UTF-8 bytes [i, end) as a string
function utf8(b, i, end) {
  let s = "";
  const cs = [];
  while (i < end) {
    let c = b[i++];
    if (c >= 0xf0) c = ((c & 7) << 18) | ((b[i++] & 63) << 12) | ((b[i++] & 63) << 6) | (b[i++] & 63);
    else if (c >= 0xe0) c = ((c & 15) << 12) | ((b[i++] & 63) << 6) | (b[i++] & 63);
    else if (c >= 0xc0) c = ((c & 31) << 6) | (b[i++] & 63);
    if (c > 0xffff) {
      c -= 0x10000;
      cs.push(0xd800 | (c >> 10), 0xdc00 | (c & 1023));
    } else cs.push(c);
    if (cs.length > 4096) {
      s += String.fromCharCode.apply(null, cs);
      cs.length = 0;
    }
  }
  return s + String.fromCharCode.apply(null, cs);
}

// CBOR bytes to Bend's Json tree, as Cbor.decode reads them; malformed or
// truncated bytes are Null, as there
function cbor(b) {
  let i = 0;
  const bad = () => {
    throw new Error("cbor");
  };
  const arg = (ai) => {
    if (ai < 24) return ai;
    if (ai === 24) return b[i++];
    if (ai === 25) return (b[i++] << 8) | b[i++];
    if (ai === 26) return ((b[i++] << 24) | (b[i++] << 16) | (b[i++] << 8) | b[i++]) >>> 0;
    return bad();
  };
  const text = (n) => {
    if (i + n > b.length) bad();
    const s = utf8(b, i, i + n);
    i += n;
    return s;
  };
  // tag: 0 none, 6 a dictionary word, 7 a number's raw text
  const item = (tag) => {
    if (i >= b.length) bad();
    const h = b[i++], maj = h >> 5, ai = h & 31;
    if (maj === 6) return tag === 0 && (ai === 6 || ai === 7) ? item(ai) : bad();
    if (maj === 7) {
      if (tag !== 0) bad();
      if (ai === 20) return { $: "Flag", value: false };
      if (ai === 21) return { $: "Flag", value: true };
      if (ai === 22) return { $: "Null" };
      return bad();
    }
    const n = arg(ai);
    if (i > b.length) bad();
    if (maj === 0 && tag === 0) return { $: "Num", raw: String(n) };
    if (maj === 0 && tag === 6) return n < WORDS.length ? { $: "Str", text: WORDS[n] } : bad();
    if (maj === 1 && tag === 0) return { $: "Num", raw: String(-1 - n) };
    if (maj === 3 && tag === 0) return { $: "Str", text: text(n) };
    if (maj === 3 && tag === 7) return { $: "Num", raw: text(n) };
    if (maj === 4 && tag === 0) {
      const vs = [];
      for (let k = 0; k < n; k += 1) vs.push(item(0));
      let items = { $: "End" };
      for (let k = n - 1; k >= 0; k -= 1) items = { $: "Item", head: vs[k], tail: items };
      return { $: "Arr", items };
    }
    if (maj === 5 && tag === 0) {
      const ks = [], vs = [];
      for (let k = 0; k < n; k += 1) {
        const key = item(0);
        if (key.$ === "Str") ks.push(key.text);
        else if (key.$ === "Num" && /^[0-9]+$/.test(key.raw) && Number(key.raw) < KEYS.length) ks.push(KEYS[Number(key.raw)]);
        else bad();
        vs.push(item(0));
      }
      let fields = { $: "End" };
      for (let k = n - 1; k >= 0; k -= 1) fields = { $: "Field", key: ks[k], value: vs[k], tail: fields };
      return { $: "Obj", fields };
    }
    return bad();
  };
  try {
    const v = item(0);
    return i === b.length ? v : { $: "Null" };
  } catch {
    return { $: "Null" };
  }
}
let ui = null;

// every call answers {"screen": <screen>, "cmds": [...]} as one string;
// alerts ride along as {"type": "notify", ...} commands
function out(cmds, quiet, alerts) {
  const cs = [];
  for (const c of each(cmds)) {
    if (c.$ === "Send") cs.push({ type: "send", data: App.wire(c.text) });
    else if (c.$ === "Copy") cs.push({ type: "copy", text: c.text });
    else if (c.$ === "Focus") cs.push({ type: "focus", id: c.id });
    else if (c.$ === "Scroll") cs.push({ type: "scroll" });
    else if (c.$ === "Connect") cs.push({ type: "connect", url: c.url });
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
  // a binary frame from the hub, as base64
  recv(data) {
    const r = App.recv(ui, cbor(bytes(data)));
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
  // a new connection re-asks for the viewer's plot
  online(b) {
    const r = App.online(ui, !!b);
    ui = r.ui;
    return out(r.cmds);
  },
  tick(now) {
    ui = App.tick(ui, secs(now));
    return out(null);
  },
};
