// Times the phone client (bridge.js, as the apps run it) against a running
// hub: open threads and bots one after another, and type into a draft.
//   bun test/tools/phone_bench.ts <bridge.js> <host:port> <token> [rounds]
// Build bridge.js with `scripts/build-mobile.sh --js`. Bun runs it in
// JavaScriptCore, the engine the iOS app uses (with a JIT, so absolute
// numbers are lower than on a phone; compare builds with each other).
import { readFileSync } from "fs";

const [bridge, key, token, roundsArg] = process.argv.slice(2);
const rounds = Number(roundsArg ?? 3);
(0, eval)(readFileSync(bridge, "utf8"));
const B = (globalThis as any).Backplane;

const b64 = (u: Uint8Array) => Buffer.from(u).toString("base64");
let ws: WebSocket;
let last = Date.now();
let busy = 0;
let frames = 0;
let bytes = 0;
let screen: any = null;

function handle(text: string) {
  const o = JSON.parse(text);
  if (o.screen) screen = o.screen;
  for (const c of o.cmds ?? []) if (c.type === "send") ws.send(Buffer.from(c.data, "base64"));
}

handle(B.start("bench", "{}"));
handle(B.hubs([key]));
const r = JSON.parse(B.resume(key));
ws = new WebSocket(`ws://${key}/ws?token=${token}&since=${r.since}&origin=${encodeURIComponent(r.origin)}&enc=cbor`);
ws.binaryType = "arraybuffer";
last = Date.now();
ws.onopen = () => handle(B.online(key, true));
ws.onmessage = (m) => {
  const u = new Uint8Array(m.data as ArrayBuffer);
  const t0 = performance.now();
  handle(B.recv(key, b64(u)));
  busy += performance.now() - t0;
  frames += 1;
  bytes += u.length;
  last = Date.now();
};

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const start = last;
while (Date.now() - last < 2500 || !screen || frames === 0) await sleep(100);
console.log(`cold start: ${frames} frames, ${(bytes / 1e6).toFixed(2)} MB, ${busy.toFixed(0)} ms in the client, caught up after ${last - start} ms`);

// the thread and bot rows the list shows
const ids: string[] = [];
const walk = (v: any) => {
  if (Array.isArray(v)) v.forEach(walk);
  else if (v && typeof v === "object") {
    if (typeof v.id === "string" && v.id.includes("|") && (v.title !== undefined || v.name !== undefined)) ids.push(v.id);
    Object.values(v).forEach(walk);
  }
};
walk(screen);
const pick = [...new Set(ids)].slice(0, 8);
console.log(`rows: ${ids.length}, opening ${pick.length}`);

const time = (f: () => string) => {
  const t0 = performance.now();
  handle(f());
  return performance.now() - t0;
};
const stats = (xs: number[]) => {
  xs.sort((a, b) => a - b);
  const mean = xs.reduce((a, b) => a + b, 0) / xs.length;
  return `mean ${mean.toFixed(1)} ms  p50 ${xs[xs.length >> 1].toFixed(1)}  max ${xs[xs.length - 1].toFixed(1)}  (n ${xs.length})`;
};
const opens: number[] = [];
for (let i = 0; i < rounds; i++) for (const id of pick) {
  opens.push(time(() => B.act("select", id)));
  await sleep(30);
}
console.log("open a thread/bot: " + stats(opens));
for (const id of pick) {
  const ms = time(() => B.act("select", id));
  const s2 = time(() => B.screen());
  const th = screen?.thread;
  console.log(`  ${id.slice(id.indexOf("|") + 1)}: open ${ms.toFixed(0)} ms, again ${s2.toFixed(0)} ms, ${th?.entries?.length ?? "-"} rows${screen?.bot ? " (bot)" : ""}`);
}
const acts: number[] = [];
for (const id of pick) {
  acts.push(time(() => B.quiet("select", id)));
  await sleep(30);
}
console.log("  of which the action (no screen): " + stats(acts));
handle(B.act("select", pick[0]));
const keys: number[] = [];
let draft = "";
for (const ch of "the quick brown fox jumps over the lazy dog") {
  draft += ch;
  keys.push(time(() => B.quiet("draft", draft)));
}
console.log("type a key (quiet): " + stats(keys));
const shown: number[] = [];
for (let i = 0; i < 10; i++) shown.push(time(() => B.screen()));
console.log("screen of an open thread: " + stats(shown));
handle(B.quiet("draft", ""));
handle(B.act("select", ""));
const list: number[] = [];
for (let i = 0; i < 10; i++) list.push(time(() => B.screen()));
console.log("screen of the list: " + stats(list));
ws.close();
process.exit(0);
