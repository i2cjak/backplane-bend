// End to end: a running hub sends a phone a board as a plot, then only
// deltas; a 3D view gets the board's plot and its model
// (src/core/plot.bend, src/server/plot.bend).
//
//   bun test/tools/plot_e2e.ts PORT TOKEN /abs/project /abs/empty-project WIRE [3d]
//
// WIRE is test/wire built (bend test/wire/index.html -o build/wire): the
// hub's own codec for requests. Plot frames are read by the small CBOR
// reader below, the same shape the phones decode. The project must hold a
// .kicad_pcb with the segment this edits (the KiCad "video" demo). Prints
// "ok ..." / "FAIL ..." lines.
import { readFileSync, readdirSync, writeFileSync } from "node:fs";

const [port, token, root, empty, wire, three] = process.argv.slice(2);
for (const f of readdirSync(wire).filter((f) => f.endsWith(".js"))) (0, eval)(readFileSync(`${wire}/${f}`, "utf8"));
const W = (globalThis as any).Wire;
const pcb = `${root}/video.kicad_pcb`;

// a plot frame: a map whose first key is 1 ("t") and value "plot"
const isPlot = (b: Uint8Array) =>
  b.length > 7 && b[0] >= 0xa0 && b[0] <= 0xb7 && b[1] === 1 && b[2] === 0x64 &&
  b[3] === 0x70 && b[4] === 0x6c && b[5] === 0x6f && b[6] === 0x74;

// CBOR, as much as plots use: unsigned and negative ints, byte and text
// strings, arrays, maps (keys 1 and 31 are "t" and "key")
function cbor(b: Uint8Array): any {
  let i = 0;
  const arg = (ai: number) => {
    if (ai < 24) return ai;
    if (ai === 24) return b[i++];
    if (ai === 25) { const v = (b[i] << 8) | b[i + 1]; i += 2; return v; }
    const v = ((b[i] << 24) >>> 0) + (b[i + 1] << 16) + (b[i + 2] << 8) + b[i + 3];
    i += 4;
    return v;
  };
  const item = (): any => {
    const h = b[i++], mt = h >> 5, n = arg(h & 31);
    switch (mt) {
      case 0: return n;
      case 1: return -1 - n;
      case 2: { const v = b.subarray(i, i + n); i += n; return v; }
      case 3: { const v = new TextDecoder().decode(b.subarray(i, i + n)); i += n; return v; }
      case 4: return Array.from({ length: n }, item);
      case 5: {
        const o: any = {};
        for (let k = 0; k < n; k++) { let key = item(); key = key === 1 ? "t" : key === 31 ? "key" : key; o[key] = item(); }
        return o;
      }
    }
    throw new Error(`cbor major ${mt}`);
  };
  return item();
}

const ws = new WebSocket(`ws://127.0.0.1:${port}/ws?token=${token}`);
ws.binaryType = "arraybuffer";
const inbox: any[] = [];
let wake: (() => void) | null = null;
let id = 0;
let failed = false;
ws.onmessage = (e) => {
  const b = new Uint8Array(e.data as ArrayBuffer);
  if (isPlot(b)) inbox.push({ plot: cbor(b), bytes: b.length });
  else {
    const o = JSON.parse(W.decode(b));
    if (o.t === "plot") inbox.push({ plot: o, bytes: b.length });
  }
  wake?.();
};

const rpc = (m: string, p: object) => ws.send(W.encode(JSON.stringify({ id: ++id, m, p })));
const check = (name: string, ok: boolean, got?: unknown) => {
  console.log(ok ? `ok ${name}` : `FAIL ${name}: ${JSON.stringify(got)?.slice(0, 300)}`);
  if (!ok) failed = true;
};

// the next plot (for key, when given) within ms, or null
async function plot(ms: number, key?: string): Promise<any> {
  const end = Date.now() + ms;
  for (;;) {
    const i = inbox.findIndex((m) => !key || m.plot.key === key);
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
check("board thickness", first?.plot?.thick === 1600, first?.plot?.thick);
console.log(`  ${cs.length} chunks, ${first?.bytes} bytes, ${ms} ms from ask to arrival`);

// inspecting a tap: the hub answers from the chunks this phone holds
const replies: any[] = [];
const ask = async (at: number, idx: number) => {
  const want = ++id;
  ws.send(W.encode(JSON.stringify({ id: want, m: "kicad.info", p: { key: `0|${root}|`, at, idx } })));
  const t = Date.now();
  for (;;) {
    const r = replies.find((o) => String(o.id) === String(want));
    if (r || Date.now() - t > 5000) return { r, ms: Date.now() - t };
    await new Promise((res) => setTimeout(res, 5));
  }
};
const recv0 = ws.onmessage!;
ws.onmessage = (e) => {
  const b = new Uint8Array(e.data as ArrayBuffer);
  if (!isPlot(b)) { const o = JSON.parse(W.decode(b)); if (o.t === "reply") replies.push(o); }
  recv0.call(ws, e);
};
const dots = cs.findIndex((c: any) => c.m === 2);
const { r: info, ms: ims } = await ask(dots, 0);
check("a tapped piece's info", typeof info?.result?.info === "string" && info.result.info.length > 3, info);
console.log(`  info of chunk ${dots} piece 0: ${info?.result?.info} (${ims} ms)`);
const { r: none } = await ask(99999, 0);
check("no such piece: no info", none?.result?.info === "", none);

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

// 3D: the board's plot for its faces, and the model (body and parts)
if (three) {
  const t2 = Date.now();
  rpc("kicad.watch", { kind: "3d", root, path: "" });
  const b = await plot(20000, `0|${root}|`);
  check("3d sends the board's plot", !!b && b.plot.cs.length > 50, b?.plot?.key);
  console.log(`  3d: board layers in ${Date.now() - t2} ms`);
  const m = await plot(240000, `2|${root}|`);
  check("3d sends the model", !!m && m.plot.n > 1000 && m.plot.mesh?.length > 0 && m.plot.box3?.length === 6, m?.plot && { n: m.plot.n, box3: m.plot.box3, none: m.plot.none });
  console.log(`  3d: model ${m?.plot?.n} triangles, ${m?.bytes} bytes, box ${m?.plot?.box3}, ${Date.now() - t2} ms`);
}
rpc("kicad.watch", { kind: "", root: "", path: "" });
ws.close();
process.exit(failed ? 1 : 0);
