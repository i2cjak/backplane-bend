// End to end: bots on two headless hubs (docs/bots.md). Starts two hubs on
// temporary homes and free ports, then checks webhooks (signed, GitHub's,
// wrong, replayed, stale, too big), linking the hubs with an invite, a
// person on one hub writing to a bot on the other, the signed bot
// directory, and (on the minute tick) a routine and the linked machine's
// bots in the hub info. Agents never answer: `claude`, `codex` and `grok`
// are stand-ins that exit at once. Prints "ok ..." / "FAIL ..." lines.
//
//   bun test/tools/bots_e2e.ts [BINARY] [WIREDIR] [--quick]
//
// BINARY defaults to build/backplane (scripts/build-app.sh
// src/app/main.bend build/backplane); WIREDIR to build/wire (bend
// test/wire/index.html -o build/wire), the hub's own CBOR codec. --quick
// skips the checks that wait for the minute tick.
import { createHmac } from "node:crypto";
import { mkdtempSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync, chmodSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";

const args = process.argv.slice(2);
const quick = args.includes("--quick");
const [bin = "build/backplane", wire = "build/wire"] = args.filter((a) => !a.startsWith("--"));
for (const f of readdirSync(wire).filter((f) => f.endsWith(".js"))) (0, eval)(readFileSync(`${wire}/${f}`, "utf8"));
const W = (globalThis as any).Wire;

let failed = false;
const check = (name: string, ok: boolean, got?: unknown) => {
  console.log(ok ? `ok ${name}` : `FAIL ${name}: ${JSON.stringify(got)?.slice(0, 400)}`);
  if (!ok) failed = true;
};
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// a port nothing listens on
function freePort(): number {
  const s = Bun.listen({ hostname: "127.0.0.1", port: 0, socket: { data() {} } });
  const p = s.port;
  s.stop(true);
  return p;
}

// stand-in agents: they exit at once, so no real agent runs
const root = mkdtempSync(join(tmpdir(), "bp-bots-e2e-"));
const fake = join(root, "bin");
mkdirSync(fake);
for (const n of ["claude", "codex", "grok"]) {
  writeFileSync(join(fake, n), "#!/bin/sh\nexit 1\n");
  chmodSync(join(fake, n), 0o755);
}

type Hub = { name: string; home: string; port: number; proc: ReturnType<typeof Bun.spawn>; ws: WebSocket; seen: any[]; replies: Map<number, any>; info: any; n: number };

async function start(name: string): Promise<Hub> {
  const home = join(root, name);
  const port = freePort();
  const proc = Bun.spawn([resolve(bin), "--home", home, "--port", String(port), "--no-tailscale"], {
    env: { ...process.env, DISPLAY: "", WAYLAND_DISPLAY: "", BACKPLANE_NAME: name, BACKPLANE_NO_UPDATE: "1", BACKPLANE_PEERS: "", PATH: `${fake}:${process.env.PATH}` },
    stdout: "ignore",
    stderr: "pipe",
  });
  const h: Hub = { name, home, port, proc, ws: null as any, seen: [], replies: new Map(), info: null, n: 0 };
  for (let i = 0; i < 100; i++) {
    try {
      const r = await fetch(`http://127.0.0.1:${port}/hello`);
      if (r.status === 200) break;
    } catch {}
    await sleep(100);
  }
  const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
  ws.binaryType = "arraybuffer";
  ws.onmessage = (e) => {
    const o = JSON.parse(W.decode(new Uint8Array(e.data as ArrayBuffer)));
    for (const c of o.items ?? []) h.seen.push(c);
    if (o.t === "reply") h.replies.set(Number(o.id), o);
    if (o.info) h.info = o.info;
  };
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  h.ws = ws;
  return h;
}

async function until<T>(ms: number, f: () => T | undefined | null | false): Promise<T | undefined> {
  const end = Date.now() + ms;
  for (;;) {
    const v = f();
    if (v) return v;
    if (Date.now() > end) return undefined;
    await sleep(50);
  }
}

async function rpc(h: Hub, m: string, p: object): Promise<any> {
  const id = ++h.n;
  h.ws.send(W.encode(JSON.stringify({ id, m, p })));
  return await until(10000, () => h.replies.get(id));
}

const change = (h: Hub, tag: string, f: (c: any) => boolean = () => true) => until(8000, () => h.seen.find((c) => c.$ === tag && f(c)));

const hmac = (key: Buffer | string, text: string) => createHmac("sha256", key).update(text).digest("hex");
const sign = (secret: string, ts: number, body: string) => "sha256=" + hmac(Buffer.from(secret, "hex"), `${ts}.${body}`);
const now = () => Math.floor(Date.now() / 1000);

async function post(url: string, body: string, headers: Record<string, string>) {
  const r = await fetch(url, { method: "POST", body, headers: { "content-type": "application/json", ...headers } });
  return { status: r.status, text: await r.text() };
}

const hubs: Hub[] = [];
try {
  const a = await start("alpha");
  hubs.push(a);
  const b = await start("beta");
  hubs.push(b);
  const A = `http://127.0.0.1:${a.port}`;

  // bots
  const miso = await rpc(a, "bots.create", { name: "miso", persona: "a test bot" });
  const nori = await rpc(a, "bots.create", { name: "nori" });
  check("bots.create answers a bot id", miso?.ok && typeof miso.bot === "string" && nori?.ok, [miso, nori]);
  const home = await change(a, "WorktreeSet", (c) => String(c.worktree ?? c.path ?? JSON.stringify(c)).includes(`/bots/${miso?.bot}`));
  check("a bot's home folder becomes its thread's folder", !!home, a.seen.filter((c) => c.$ === "WorktreeSet"));
  check("the home folder is a git repository", (() => { try { return statSync(join(a.home, "bots", miso.bot, ".git")).isDirectory(); } catch { return false; } })());

  // webhooks
  const hk = await rpc(a, "bots.hook", { bot: miso.bot, name: "ci" });
  check("bots.hook answers a secret once", hk?.ok && /^[0-9a-f]{64}$/.test(hk.secret) && hk.path === `/hook/${hk.hook}`, hk);
  const secret: string = hk?.secret ?? "";
  const hookFile = join(a.home, "secrets", "hooks", hk?.hook ?? "x");
  check("the hook's secret file is 0600 in a 0700 folder",
    (statSync(hookFile).mode & 0o777) === 0o600 && (statSync(join(a.home, "secrets", "hooks")).mode & 0o777) === 0o700 && (statSync(join(a.home, "secrets")).mode & 0o777) === 0o700,
    [(statSync(hookFile).mode & 0o777).toString(8)]);
  check("the hook's secret file holds the secret", readFileSync(hookFile, "utf8").trim() === secret);
  const url = `${A}/hook/${hk?.hook}`;
  const body = JSON.stringify({ action: "opened", n: 1 });
  const ts = now();
  const good = { "x-backplane-timestamp": String(ts), "x-backplane-signature": sign(secret, ts, body) };
  const r1 = await post(url, body, good);
  check("a signed webhook is accepted (202)", r1.status === 202, r1);
  check("a HookHit change follows", !!(await change(a, "HookHit")), a.seen.map((c) => c.$).slice(-8));
  check("the hook wakes its bot", !!(await change(a, "BotWoke", (c) => c.bot === miso.bot)));
  const r2 = await post(url, body, good);
  check("the same request again is refused (401)", r2.status === 401, r2);
  const r3 = await post(url, body, { "x-backplane-timestamp": String(now()), "x-backplane-signature": sign("00".repeat(32), now(), body) });
  check("a wrong signature is refused (401)", r3.status === 401, r3);
  const old = now() - 1000;
  const r4 = await post(url, body, { "x-backplane-timestamp": String(old), "x-backplane-signature": sign(secret, old, body) });
  check("a stale timestamp is refused (401)", r4.status === 401, r4);
  const r5 = await post(url, body, {});
  check("an unsigned webhook is refused (401)", r5.status === 401, r5);
  const r6 = await post(`${A}/hook/h0-0`, body, good);
  check("an unknown webhook is refused (401)", r6.status === 401, r6);
  const big = JSON.stringify({ x: "y".repeat(300000) });
  const r7 = await post(url, big, { "x-backplane-timestamp": String(now()), "x-backplane-signature": sign(secret, now(), big) });
  check("a body over 256 KB is refused (413)", r7.status === 413, r7.status);
  const gbody = JSON.stringify({ zen: "Keep it logically awesome." });
  const gh = { "x-hub-signature-256": "sha256=" + hmac(secret, gbody), "x-github-delivery": "d-" + Date.now() };
  const r8 = await post(url, gbody, gh);
  check("GitHub's signature is accepted (202)", r8.status === 202, r8);
  const r9 = await post(url, gbody, gh);
  check("the same GitHub delivery again is refused (401)", r9.status === 401, r9);
  const r10 = await post(url, gbody, { ...gh, "x-github-delivery": "d-other", "x-hub-signature-256": "sha256=" + hmac("wrong", gbody) });
  check("a wrong GitHub signature is refused (401)", r10.status === 401, r10);

  // linking the hubs
  const inv = await rpc(a, "bots.invite", { url: A });
  check("bots.invite answers an invite", inv?.ok && typeof inv.invite === "string" && inv.invite.startsWith(`bp1:${A}:`), inv);
  const joined = await rpc(b, "bots.join", { invite: inv?.invite ?? "" });
  check("bots.join links", joined?.ok && joined.name === "alpha", joined);
  const peerA = await change(a, "PeerSet", (c) => !c.revoked);
  const peerB = await change(b, "PeerSet", (c) => !c.revoked);
  check("both hubs have a PeerSet", !!peerA && !!peerB, [peerA, peerB]);
  check("each names the other", peerA?.name === "beta" && peerB?.name === "alpha", [peerA, peerB]);
  const again = await rpc(b, "bots.join", { invite: inv?.invite ?? "" });
  check("an invite links once", again && !again.ok, again);
  const pid: string = inv?.peer ?? "";
  const peerSecret = JSON.parse(readFileSync(join(a.home, "secrets", "peers", pid), "utf8")).secret;
  check("both keep the same peer secret, 0600",
    peerSecret === JSON.parse(readFileSync(join(b.home, "secrets", "peers", pid), "utf8")).secret && (statSync(join(b.home, "secrets", "peers", pid)).mode & 0o777) === 0o600);

  // a person on beta writes to a bot on alpha
  const told = await rpc(b, "bots.tell", { to: "miso@alpha", text: "hello from beta" });
  check("bots.tell to name@machine answers ok", told?.ok, told);
  const posted = await change(a, "RoomPosted", (c) => c.text === "hello from beta");
  check("alpha logs the message as RoomPosted", !!posted, a.seen.filter((c) => c.$ === "RoomPosted"));
  check("from the person on beta", String(posted?.from ?? "").endsWith("@beta"), posted);

  // the bot directory, signed
  const dts = now();
  const dir = await fetch(`${A}/bots/dir`, { headers: { "x-backplane-peer": pid, "x-backplane-timestamp": String(dts), "x-backplane-signature": sign(peerSecret, dts, "") } });
  const listed = dir.status === 200 ? await dir.json() : await dir.text();
  check("GET /bots/dir signed lists alpha's bots", dir.status === 200 && Array.isArray(listed) && listed.map((x: any) => x.name).sort().join() === "miso,nori", listed);
  const d2 = await fetch(`${A}/bots/dir`);
  check("GET /bots/dir unsigned is refused (401)", d2.status === 401, d2.status);
  const d3 = await fetch(`${A}/bots/dir`, { headers: { "x-backplane-peer": pid, "x-backplane-timestamp": String(dts), "x-backplane-signature": sign(peerSecret, dts, "") } });
  check("the same directory request again is refused (401)", d3.status === 401, d3.status);
  const d4 = await post(`${A}/bots/deliver`, JSON.stringify({ from: "x", to: "miso", text: "forged", hop: 0 }), { "x-backplane-peer": pid, "x-backplane-timestamp": String(now()), "x-backplane-signature": sign("11".repeat(32), now(), "x") });
  check("a forged delivery is refused (401)", d4.status === 401, d4);
  const d5 = await post(`${A}/bots/link`, JSON.stringify({ url: "http://127.0.0.1:1", name: "evil" }), { "x-backplane-peer": "../../token", "x-backplane-timestamp": String(now()), "x-backplane-signature": "sha256=00" });
  check("a peer id that is not a plain id is refused (401)", d5.status === 401, d5);

  // screens are for clients only
  const s1 = await fetch(`${A}/bots/${miso.bot}/screen.jpg`);
  check("a bot's screen from loopback: 404 until it has one", s1.status === 404, s1.status);

  // secrets never reach the logs or a broadcast
  const logA = readFileSync(join(a.home, "events.jsonl"), "utf8");
  const logB = readFileSync(join(b.home, "events.jsonl"), "utf8");
  check("no secret in either event log", !logA.includes(secret) && !logA.includes(peerSecret) && !logB.includes(peerSecret));
  check("no secret in a broadcast change", !JSON.stringify(a.seen).includes(secret) && !JSON.stringify(b.seen).includes(peerSecret));

  // revoking a hook: its secret goes, its calls are refused
  await rpc(a, "bots.hook_revoke", { hook: hk.hook });
  await sleep(300);
  const r11 = await post(url, body, { "x-backplane-timestamp": String(now()), "x-backplane-signature": sign(secret, now(), body) });
  check("a revoked webhook is refused (401)", r11.status === 401, r11);
  check("a revoked webhook's secret file is gone", (() => { try { statSync(hookFile); return false; } catch { return true; } })());

  if (!quick) {
    // the minute tick: a routine fires; beta lists alpha's bots
    const ro = await rpc(a, "bots.routine", { bot: nori.bot, name: "tick", cron: "* * * * *", prompt: "tick" });
    check("bots.routine", ro?.ok, ro);
    const fired = await until(75000, () => a.seen.find((c) => c.$ === "RoutineFired"));
    check("the routine fires on the minute tick", !!fired, a.seen.map((c) => c.$).slice(-10));
    const remote = await until(75000, () => {
      try { const xs = JSON.parse(b.info?.["bots.remote"] ?? "[]"); return xs.length === 2 ? xs : undefined; } catch { return undefined; }
    });
    check("beta's info lists alpha's bots (bots.remote)", !!remote && remote.every((x: any) => x.peer === pid && x.peerName === "alpha"), b.info?.["bots.remote"]);
  }
} catch (e) {
  check("no exception", false, String(e));
} finally {
  for (const h of hubs) {
    try { h.ws?.close(); } catch {}
    h.proc.kill();
  }
  await Promise.all(hubs.map((h) => h.proc.exited));
  rmSync(root, { recursive: true, force: true });
}
console.log(failed ? "bots e2e: FAIL" : "bots e2e: ok");
process.exit(failed ? 1 : 0);
