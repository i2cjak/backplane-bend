// Smoke test for a built server: page, websocket, one project + thread,
// persisted log. Usage: bun test/smoke.ts PORT HOME
const [port, home] = process.argv.slice(2);
const base = `http://127.0.0.1:${port}`;
const fail = (m: string) => { console.error("smoke: " + m); process.exit(1); };

const page = await fetch(base + "/");
if (page.status !== 200 || !(await page.text()).includes("<title>Backplane</title>")) fail("index.html not served");

const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
const seen: any[] = [];
let n = 0;
const send = (m: string, p: any) => ws.send(JSON.stringify({ id: ++n, m, p }));
const done = new Promise<void>((resolve) => {
  ws.onmessage = (e) => {
    const o = JSON.parse(e.data);
    for (const c of o.items ?? []) seen.push(c);
    const proj = seen.find((c) => c.$ === "ProjectCreated");
    if (o.t === "log") send("project.add", { path: home });
    if (o.t === "changes" && proj && !seen.some((c) => c.$ === "ThreadCreated")) send("thread.create", { project: proj.id, title: "Smoke" });
    if (seen.some((c) => c.$ === "ThreadCreated")) resolve();
  };
});
ws.onerror = () => fail("websocket failed");
await Promise.race([done, new Promise((_, rej) => setTimeout(() => rej(new Error("timeout")), 5000))]).catch((e) => fail(String(e)));
ws.close();

const log = await Bun.file(`${home}/events.jsonl`).text();
if (!log.includes('"ThreadCreated"') || !log.includes('"ProjectCreated"')) fail("events.jsonl missing changes");
console.log("smoke: ok");
process.exit(0);
