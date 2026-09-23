// Drives backplane-browser end to end: bun test/smoke.ts [URL] [FRAMES]
// Uses dist/backplane-browser when BACKPLANE_BROWSER is set, else src/main.ts.

const url = process.argv[2] ?? "https://example.com";
const framesPath = process.argv[3] ?? "/tmp/backplane-browser-smoke.rgb";
const cmd = process.env.BACKPLANE_BROWSER
  ? [process.env.BACKPLANE_BROWSER, "--frames", framesPath]
  : ["bun", new URL("../src/main.ts", import.meta.url).pathname, "--frames", framesPath];

const proc = Bun.spawn(cmd, { stdin: "pipe", stdout: "pipe", stderr: "inherit" });
const waiting = new Map<number, (v: any) => void>();
const events: any[] = [];
let nextId = 1;

(async () => {
  const dec = new TextDecoder();
  let buf = "";
  for await (const chunk of proc.stdout) {
    buf += dec.decode(chunk);
    let nl;
    while ((nl = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, nl);
      buf = buf.slice(nl + 1);
      const msg = JSON.parse(line);
      if (msg.event) {
        events.push(msg);
        console.log("event", JSON.stringify(msg));
      } else waiting.get(msg.id)?.(msg);
    }
  }
})();

function call(op: string, args: Record<string, unknown> = {}): Promise<any> {
  const id = nextId++;
  const t0 = performance.now();
  proc.stdin.write(JSON.stringify({ id, op, ...args }) + "\n");
  proc.stdin.flush();
  return new Promise((res) => waiting.set(id, (m) => {
    const ms = (performance.now() - t0).toFixed(0);
    console.log(op, ms + "ms", JSON.stringify(m).slice(0, 300));
    res(m);
  }));
}

await call("status");
await call("open", { url, width: 700, height: 800 });
await call("frames", { on: true, maxFps: 10 });
await Bun.sleep(500);
const snap = await call("snapshot");
console.log(snap.result.outline);
if (url.startsWith("file:")) {
  await call("type", { locator: "role=textbox", text: "bend" });
  await call("click", { locator: "role=button[name='Go']" });
  await call("wait_for", { text: "clicked bend", timeoutMs: 3000 });
  const ref = /link "a link" \[ref=(e\d+)\]/.exec(snap.result.outline)?.[1];
  await call("click", { ref });
  await call("wait_for", { url: "#x", timeoutMs: 3000 });
}
await call("evaluate", { expression: "document.title" });
await call("scroll", { dy: 200 });
await Bun.sleep(500);
await call("scroll", { dy: -200 });
await Bun.sleep(500);
await call("close");
await proc.exited;
console.log("frames seen:", events.filter((e) => e.event === "frame").length);
