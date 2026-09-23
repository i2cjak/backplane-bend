// End to end: a running hub sends a phone a board as a plot, then only
// deltas (src/core/plot.bend, src/server/plot.bend).
//
//   bun test/tools/plot_e2e.ts ws://127.0.0.1:PORT/ws?token=T /abs/project /abs/empty-project WIREDIR
//
// Frames are binary: plots as their JSON text, everything else CBOR
// through the hub's own codec (WIREDIR: bend test/wire/index.html -o it).
//
// The project must hold a .kicad_pcb with the segment this edits (the
// KiCad "video" demo). Prints "ok ..." / "FAIL ..." lines.
import { readdirSync, readFileSync, writeFileSync } from "node:fs";

const [url, root, empty, wire] = process.argv.slice(2);
for (const f of readdirSync(wire).filter((f) => f.endsWith(".js"))) (0, eval)(readFileSync(`${wire}/${f}`, "utf8"));
const W = (globalThis as any).Wire;
const plotPrefix = new TextEncoder().encode('{"t":"plot"');
const isPlot = (b: Uint8Array) => b.length >= plotPrefix.length && plotPrefix.every((x, i) => b[i] === x);
const pcb = `${root}/video.kicad_pcb`;
const ws = new WebSocket(url);
ws.binaryType = "arraybuffer";
const inbox: any[] = [];
let wake: (() => void) | null = null;
let id = 0;
let failed = false;

ws.onmessage = (e) => {
  if (typeof e.data === "string") { check("binary frames only", false, e.data.slice(0, 40)); return; }
  const b = new Uint8Array(e.data);
  if (isPlot(b)) inbox.push({ plot: JSON.parse(new TextDecoder().decode(b)), bytes: b.length });
  else inbox.push(JSON.parse(W.decode(b)));
  wake?.();
};

const rpc = (m: string, p: object) => ws.send(W.encode(JSON.stringify({ id: String(++id), m, p })));
const check = (name: string, ok: boolean, got?: unknown) => {
  console.log(ok ? `ok ${name}` : `FAIL ${name}: ${JSON.stringify(got)}`);
  if (!ok) failed = true;
};

// the next plot within ms, or null
async function plot(ms: number): Promise<any> {
  const end = Date.now() + ms;
  for (;;) {
    const i = inbox.findIndex((m) => m.plot);
    if (i >= 0) return inbox.splice(i, 1)[0];
    const left = end - Date.now();
    if (left <= 0) return null;
    await new Promise<void>((r) => { wake = r; setTimeout(r, left); });
  }
}

await new Promise((r) => (ws.onopen = r));
const t0 = Date.now();
rpc("kicad.watch", { kind: "board", root, path: "" });
const first = await plot(20000);
const ms = Date.now() - t0;
const cs = first?.plot?.cs ?? [];
check("first plot arrives", !!first, first);
check("first plot is all chunks", cs.length > 50 && cs.every((c: any) => typeof c === "object"), cs.length);
check("first plot key", first?.plot?.key === `0|${root}|`, first?.plot?.key);
console.log(`  ${cs.length} chunks, ${first?.bytes} bytes, ${ms} ms from ask to arrival`);

// the same bytes saved again: nothing is sent
const text = readFileSync(pcb, "utf8");
writeFileSync(pcb, text);
check("unchanged save sends nothing", (await plot(2500)) === null);

// one track moved: a delta, one chunk sent whole
writeFileSync(pcb, text.replace("(start 124.46 151.765)", "(start 124.46 150.765)"));
const t1 = Date.now();
const d = await plot(10000);
const fresh = (d?.plot?.cs ?? []).filter((c: any) => typeof c === "object");
check("an edit sends a delta", !!d && d.plot.cs.length === cs.length, d?.plot?.cs?.length);
check("an edit sends one chunk", fresh.length === 1, fresh.length);
console.log(`  delta: ${d?.bytes} bytes (${fresh.length} chunk whole), ${Date.now() - t1} ms from save to arrival`);
writeFileSync(pcb, text);
await plot(10000);

// another source, then a project with no board
rpc("kicad.watch", { kind: "schematic", root, path: "" });
const s = await plot(10000);
check("schematic plot", s?.plot?.key === `1|${root}|` && s.plot.cs.length > 10, s?.plot?.key);
rpc("kicad.watch", { kind: "board", root: empty, path: "" });
const n = await plot(5000);
check("no board says so", n?.plot?.none === "No board in this project yet", n?.plot);
rpc("kicad.watch", { kind: "", root: "", path: "" });
ws.close();
process.exit(failed ? 1 : 0);
