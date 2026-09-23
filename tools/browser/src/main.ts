// backplane-browser: a headless Chromium the Bend side drives over
// newline-delimited JSON on stdin/stdout. Raw RGB frames go to a file
// (see README.md). Only protocol lines are written to stdout; logs go to
// stderr.

import { renameSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";
import { chromium, type Browser, type BrowserContext, type CDPSession, type Locator, type Page } from "playwright-core";

import { findChromium, INSTALL_HINT } from "./chromium.ts";
import { decodePng } from "./png.ts";

type Json = Record<string, any>;

const VERSION = "1";
const MAX_VISIBLE_TEXT = 20_000;
const MAX_ELEMENTS = 200;
const MAX_EVAL_BYTES = 64_000;
const MAX_LOG = 100;
const DEFAULT_TIMEOUT = 15_000;

// Arguments
// ---------

function argValue(name: string): string | null {
  const i = process.argv.indexOf(name);
  return i >= 0 && i + 1 < process.argv.length ? process.argv[i + 1] : null;
}

if (process.argv.includes("--help") || process.argv.includes("-h")) {
  process.stderr.write(
    "usage: backplane-browser [--frames FILE] [--chromium PATH] [--headed]\n" +
      "  newline-delimited JSON requests on stdin, replies and events on stdout.\n" +
      "  raw RGB frames are written to FILE (atomically, via rename).\n",
  );
  process.exit(0);
}

const FRAMES_ARG = argValue("--frames");
const FRAMES_PATH = FRAMES_ARG ?? join(tmpdir(), `backplane-browser-${process.pid}.rgb`);
const CHROMIUM_ARG = argValue("--chromium");
const HEADED = process.argv.includes("--headed");
const DEBUG = Boolean(process.env.BACKPLANE_BROWSER_DEBUG);

// Output
// ------

function send(obj: Json): void {
  process.stdout.write(JSON.stringify(obj) + "\n");
}

function log(msg: string): void {
  process.stderr.write(`backplane-browser: ${msg}\n`);
}

// State
// -----

let browser: Browser | null = null;
let context: BrowserContext | null = null;
let page: Page | null = null;
let cdp: CDPSession | null = null;
let executable: string | null = null;
let viewport = { width: 1280, height: 800 };
const consoleLog: Json[] = [];

const frames = {
  on: false,
  maxFps: 15,
  seq: 0,
  lastHash: 0n as bigint,
  pending: null as Buffer | null,
  timer: null as ReturnType<typeof setInterval> | null,
  screencasting: false,
  busy: false,
};

function pushLog(entry: Json): void {
  consoleLog.push({ ...entry, timestamp: new Date().toISOString() });
  if (consoleLog.length > MAX_LOG) consoleLog.shift();
}

// URLs: absolute http(s) passes; a schemeless host gets https, a loopback
// host http; about:, data:, file: pass as they are.
function normalizeUrl(raw: string): string {
  const url = String(raw).trim();
  if (/^[a-z][a-z0-9+.-]*:/i.test(url) && !/^[^/]+:\d+(\/|$)/.test(url)) return url;
  const host = url.split(/[/:?#]/)[0].toLowerCase();
  const loopback = host === "localhost" || host === "127.0.0.1" || host === "[::1]" || host === "0.0.0.0" || host.endsWith(".localhost");
  return (loopback ? "http://" : "https://") + url;
}

// Browser lifecycle
// -----------------

async function ensurePage(): Promise<Page> {
  if (page && !page.isClosed()) return page;
  if (!browser) {
    executable = CHROMIUM_ARG ?? findChromium();
    if (!executable) throw new Error(INSTALL_HINT);
    browser = await chromium.launch({
      executablePath: executable,
      headless: !HEADED,
      args: ["--hide-scrollbars", "--mute-audio", "--no-first-run", "--no-default-browser-check"],
    });
    browser.on("disconnected", () => {
      browser = null; context = null; page = null; cdp = null;
      frames.screencasting = false;
      send({ event: "closed" });
    });
  }
  if (!context) context = await browser.newContext({ viewport, deviceScaleFactor: 1 });
  page = await context.newPage();
  page.setDefaultTimeout(DEFAULT_TIMEOUT);
  page.on("console", (m) => pushLog({ level: m.type(), text: m.text() }));
  page.on("pageerror", (e) => pushLog({ level: "error", text: String(e) }));
  page.on("framenavigated", (f) => {
    if (f === page?.mainFrame()) send({ event: "navigated", url: f.url() });
  });
  page.on("load", () => page && send({ event: "load", url: page.url() }));
  cdp = await context.newCDPSession(page);
  cdp.on("Page.screencastFrame", (e: any) => {
    cdp?.send("Page.screencastFrameAck", { sessionId: e.sessionId }).catch(() => {});
    frames.pending = Buffer.from(e.data, "base64");
  });
  if (frames.on) await startScreencast();
  return page;
}

async function status(): Promise<Json> {
  const p = page && !page.isClosed() ? page : null;
  return {
    version: VERSION,
    open: p !== null,
    chromium: executable ?? CHROMIUM_ARG ?? findChromium(),
    url: p ? p.url() : null,
    title: p ? await p.title().catch(() => "") : null,
    loading: p ? await p.evaluate(() => document.readyState !== "complete").catch(() => false) : false,
    width: viewport.width,
    height: viewport.height,
    frames: { on: frames.on, maxFps: frames.maxFps, seq: frames.seq, path: FRAMES_PATH },
  };
}

// Frames
// ------

async function startScreencast(): Promise<void> {
  if (!cdp) return;
  if (frames.screencasting) await cdp.send("Page.stopScreencast").catch(() => {});
  await cdp.send("Page.startScreencast", {
    format: "png",
    maxWidth: viewport.width,
    maxHeight: viewport.height,
    everyNthFrame: 1,
  });
  frames.screencasting = true;
}

async function stopScreencast(): Promise<void> {
  if (cdp && frames.screencasting) await cdp.send("Page.stopScreencast").catch(() => {});
  frames.screencasting = false;
}

// write the frame file atomically and announce it; `force` skips the
// unchanged-page check
function publish(png: Buffer, force: boolean): Json | null {
  const t0 = performance.now();
  const { width, height, rgb } = decodePng(png);
  const hash = Bun.hash(rgb) as bigint;
  if (!force && hash === frames.lastHash) return null;
  frames.lastHash = hash;
  frames.seq += 1;
  const header = Buffer.alloc(16);
  header.write("BPF1", 0, "latin1");
  header.writeUInt32LE(width, 4);
  header.writeUInt32LE(height, 8);
  header.writeUInt32LE(frames.seq >>> 0, 12);
  const tmp = FRAMES_PATH + ".tmp";
  writeFileSync(tmp, Buffer.concat([header, rgb]));
  renameSync(tmp, FRAMES_PATH);
  if (DEBUG) log(`frame ${frames.seq}: ${width}x${height}, png ${png.length} B, decode+write ${(performance.now() - t0).toFixed(1)} ms`);
  const ev = { event: "frame", w: width, h: height, seq: frames.seq, path: FRAMES_PATH };
  send(ev);
  return ev;
}

function tick(): void {
  const png = frames.pending;
  if (!png || frames.busy) return;
  frames.pending = null;
  try {
    publish(png, false);
  } catch (e) {
    log(`frame: ${e}`);
  }
}

function restartTimer(): void {
  if (frames.timer) clearInterval(frames.timer);
  frames.timer = null;
  if (frames.on) frames.timer = setInterval(tick, Math.max(1, Math.round(1000 / frames.maxFps)));
}

// one screenshot now, published even when unchanged
async function captureNow(force: boolean): Promise<Json | null> {
  const p = await ensurePage();
  frames.busy = true;
  try {
    const png = await p.screenshot({ type: "png", animations: "allow", caret: "initial", timeout: DEFAULT_TIMEOUT });
    return publish(png, force);
  } finally {
    frames.busy = false;
  }
}

// Targets
// -------

function targetOf(p: Page, a: Json): Locator | null {
  if (a.ref) return p.locator(`aria-ref=${a.ref}`);
  if (a.locator) return p.locator(String(a.locator)).first();
  if (a.selector) return p.locator(`css=${a.selector}`).first();
  return null;
}

function timeoutOf(a: Json): number {
  const t = Number(a.timeoutMs ?? DEFAULT_TIMEOUT);
  return Math.max(1, Math.min(60_000, Number.isFinite(t) ? t : DEFAULT_TIMEOUT));
}

const SNAPSHOT_SCRIPT = `(() => {
  const selectorFor = (element) => {
    if (element.id) return "#" + CSS.escape(element.id);
    for (const attribute of ["data-testid", "name"]) {
      const value = element.getAttribute(attribute);
      if (value) return element.tagName.toLowerCase() + "[" + attribute + "=" + JSON.stringify(value) + "]";
    }
    const parts = [];
    for (let cur = element; cur && cur.nodeType === 1 && parts.length < 8; cur = cur.parentElement) {
      const parent = cur.parentElement;
      const same = parent ? Array.from(parent.children).filter((c) => c.tagName === cur.tagName) : [];
      const base = cur.tagName.toLowerCase();
      parts.unshift(same.length > 1 ? base + ":nth-of-type(" + (same.indexOf(cur) + 1) + ")" : base);
    }
    return parts.join(" > ");
  };
  const visible = (el) => {
    const s = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    return s.visibility !== "hidden" && s.display !== "none" && r.width > 0 && r.height > 0;
  };
  const elements = Array.from(document.querySelectorAll("a[href],button,input,textarea,select,[role],[tabindex]"))
    .filter(visible).slice(0, ${MAX_ELEMENTS}).map((el) => {
      const r = el.getBoundingClientRect();
      return {
        tag: el.tagName.toLowerCase(),
        role: el.getAttribute("role"),
        name: (el.getAttribute("aria-label") || el.innerText || el.getAttribute("name") || el.getAttribute("placeholder") || "").trim().slice(0, 200),
        selector: selectorFor(el),
        x: Math.round(r.x), y: Math.round(r.y), width: Math.round(r.width), height: Math.round(r.height),
      };
    });
  return {
    loading: document.readyState !== "complete",
    visibleText: (document.body ? document.body.innerText : "").slice(0, ${MAX_VISIBLE_TEXT}),
    interactiveElements: elements,
  };
})()`;

// Requests
// --------

const handlers: Record<string, (a: Json) => Promise<any>> = {
  async open(a) {
    if (a.width && a.height) viewport = { width: Math.round(a.width), height: Math.round(a.height) };
    const p = await ensurePage();
    await p.setViewportSize(viewport);
    if (a.url) await p.goto(normalizeUrl(a.url), { waitUntil: "load", timeout: timeoutOf(a) });
    return status();
  },
  async navigate(a) {
    if (!a.url) throw new Error("navigate needs url");
    const p = await ensurePage();
    const waitUntil = a.readiness === "none" ? "commit" : a.readiness === "domContentLoaded" ? "domcontentloaded" : "load";
    await p.goto(normalizeUrl(a.url), { waitUntil, timeout: timeoutOf(a) });
    return status();
  },
  async back(a) {
    await (await ensurePage()).goBack({ timeout: timeoutOf(a) });
    return status();
  },
  async forward(a) {
    await (await ensurePage()).goForward({ timeout: timeoutOf(a) });
    return status();
  },
  async reload(a) {
    await (await ensurePage()).reload({ timeout: timeoutOf(a) });
    return status();
  },
  async resize(a) {
    const width = Math.round(Number(a.width)), height = Math.round(Number(a.height));
    if (!(width > 0 && height > 0 && width <= 4096 && height <= 4096)) throw new Error("resize needs width and height in 1..4096");
    viewport = { width, height };
    const p = await ensurePage();
    await p.setViewportSize(viewport);
    if (frames.on) {
      await startScreencast();
      await captureNow(true);
    }
    return status();
  },
  async click(a) {
    const p = await ensurePage();
    const button = a.button ?? "left";
    const clickCount = a.clickCount ?? 1;
    const t = targetOf(p, a);
    if (t) await t.click({ button, clickCount, timeout: timeoutOf(a) });
    else if (typeof a.x === "number" && typeof a.y === "number") await p.mouse.click(a.x, a.y, { button, clickCount });
    else throw new Error("click needs x and y, selector, locator, or ref");
    return {};
  },
  async mouse(a) {
    const p = await ensurePage();
    const button = a.button ?? "left";
    if (typeof a.x === "number" && typeof a.y === "number") await p.mouse.move(a.x, a.y);
    if (a.type === "down") await p.mouse.down({ button });
    else if (a.type === "up") await p.mouse.up({ button });
    else if (a.type !== "move") throw new Error("mouse type must be move, down or up");
    return {};
  },
  async type(a) {
    const p = await ensurePage();
    const text = String(a.text ?? "");
    const t = targetOf(p, a);
    if (t) {
      if (a.clear) await t.fill("", { timeout: timeoutOf(a) });
      else await t.focus({ timeout: timeoutOf(a) });
    } else if (a.clear) {
      await p.keyboard.press("ControlOrMeta+A");
      await p.keyboard.press("Delete");
    }
    await p.keyboard.insertText(text);
    return {};
  },
  async press(a) {
    const p = await ensurePage();
    if (!a.key) throw new Error("press needs key");
    const mods: string[] = Array.isArray(a.modifiers) ? a.modifiers : [];
    await p.keyboard.press([...mods, String(a.key)].join("+"));
    return {};
  },
  async scroll(a) {
    const p = await ensurePage();
    const dx = Number(a.dx ?? a.deltaX ?? 0), dy = Number(a.dy ?? a.deltaY ?? 0);
    const t = targetOf(p, a);
    if (t) {
      await t.evaluate((el, d) => el.scrollBy(d[0], d[1]), [dx, dy], { timeout: timeoutOf(a) });
    } else {
      const x = typeof a.x === "number" ? a.x : viewport.width / 2;
      const y = typeof a.y === "number" ? a.y : viewport.height / 2;
      await p.mouse.move(x, y);
      await p.mouse.wheel(dx, dy);
    }
    return {};
  },
  async snapshot(a) {
    const p = await ensurePage();
    const page = await p.evaluate(SNAPSHOT_SCRIPT) as Json;
    const outline = await p.ariaSnapshot({ mode: "ai", timeout: timeoutOf(a) }).catch((e) => `(no outline: ${e.message})`);
    const out: Json = {
      url: p.url(),
      title: await p.title(),
      ...page,
      outline,
      console: consoleLog.slice(-50),
    };
    if (a.screenshot) {
      const png = await p.screenshot({ type: "png" });
      out.screenshot = { mimeType: "image/png", data: png.toString("base64"), width: viewport.width, height: viewport.height };
    }
    return out;
  },
  async evaluate(a) {
    const p = await ensurePage();
    if (!a.expression) throw new Error("evaluate needs expression");
    const expr = String(a.expression);
    const value = a.awaitPromise === false
      ? await p.evaluate(`(() => { const v = (${expr}); return v instanceof Promise ? "[Promise]" : v; })()`)
      : await p.evaluate(expr);
    const json = JSON.stringify(value ?? null);
    if (json.length > MAX_EVAL_BYTES) return { truncated: true, json: json.slice(0, MAX_EVAL_BYTES) };
    return value ?? null;
  },
  async wait_for(a) {
    const p = await ensurePage();
    const timeout = timeoutOf(a);
    const url = a.url ?? a.urlIncludes;
    if (!a.selector && !a.locator && !a.ref && !a.text && !url) throw new Error("wait_for needs selector, locator, text or url");
    const waits: Promise<unknown>[] = [];
    const t = targetOf(p, a);
    if (t) waits.push(t.waitFor({ state: "visible", timeout }));
    if (a.text) waits.push(p.waitForFunction((s) => (document.body?.innerText ?? "").includes(s), String(a.text), { timeout }));
    if (url) waits.push(p.waitForFunction((s) => location.href.includes(s), String(url), { timeout }));
    await Promise.all(waits);
    return {};
  },
  async frames(a) {
    frames.on = Boolean(a.on);
    if (a.maxFps !== undefined) frames.maxFps = Math.max(1, Math.min(60, Number(a.maxFps) || 15));
    restartTimer();
    if (frames.on) {
      await ensurePage();
      await startScreencast();
      await captureNow(true);
    } else {
      await stopScreencast();
    }
    return { on: frames.on, maxFps: frames.maxFps, seq: frames.seq, path: FRAMES_PATH };
  },
  async frame(_a) {
    const ev = await captureNow(true);
    return ev ?? { seq: frames.seq, path: FRAMES_PATH };
  },
  async status(_a) {
    return status();
  },
  async close(_a) {
    await shutdown(false);
    return {};
  },
};

// Loop
// ----

async function handle(line: string): Promise<void> {
  if (!line.trim()) return;
  let req: Json;
  try {
    req = JSON.parse(line);
  } catch {
    send({ id: null, ok: false, error: "bad JSON" });
    return;
  }
  const id = req.id ?? null;
  const op = String(req.op ?? req.type ?? req.method ?? "");
  const h = Object.hasOwn(handlers, op) ? handlers[op] : undefined;
  if (!h) {
    send({ id, ok: false, error: `unknown op: ${op}` });
    return;
  }
  const args = req.args && typeof req.args === "object" ? { ...req, ...req.args } : req;
  try {
    const result = await h(args);
    send({ id, ok: true, result });
  } catch (e: any) {
    send({ id, ok: false, error: String(e?.message ?? e).split("\n")[0] });
  }
  if (op === "close") process.exit(0);
}

let closing = false;
async function shutdown(exit: boolean): Promise<void> {
  if (closing) return;
  closing = true;
  if (frames.timer) clearInterval(frames.timer);
  frames.on = false;
  try {
    await browser?.close();
  } catch {}
  browser = null;
  if (!FRAMES_ARG) rmSync(FRAMES_PATH, { force: true });
  rmSync(FRAMES_PATH + ".tmp", { force: true });
  if (exit) process.exit(0);
}

process.on("SIGTERM", () => void shutdown(true));
process.on("SIGINT", () => void shutdown(true));

const rl = createInterface({ input: process.stdin, crlfDelay: Infinity });
rl.on("line", (line) => void handle(line));
rl.on("close", () => void shutdown(true));
send({ event: "ready", version: VERSION, frames: FRAMES_PATH });
