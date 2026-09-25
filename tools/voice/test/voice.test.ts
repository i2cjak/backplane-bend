// bun test (in tools/voice). Runs src/main.ts against a local mock API;
// never calls OpenAI. BACKPLANE_VOICE=dist/backplane-voice tests a build.
import { afterAll, beforeAll, expect, test } from "bun:test";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { startMock, type Mock } from "./mock";
import { Segmenter } from "../src/vad";

const MAIN = join(import.meta.dir, "../src/main.ts");
const EXE = process.env.BACKPLANE_VOICE ? [process.env.BACKPLANE_VOICE] : [process.execPath, MAIN];
const RATE = 24000;

let mock: Mock;
let dir: string;
let noTools: string; // a PATH with nothing on it (no ffmpeg, no recorder)

beforeAll(() => {
  mock = startMock();
  dir = mkdtempSync(join(tmpdir(), "bp-voice-test-"));
  noTools = join(dir, "empty");
  Bun.spawnSync(["mkdir", "-p", noTools]);
});
afterAll(() => {
  mock.stop();
  rmSync(dir, { recursive: true, force: true });
});

function tone(ms: number, amp = 8000): Uint8Array {
  const n = Math.round((RATE * ms) / 1000);
  const b = new Uint8Array(n * 2);
  const v = new DataView(b.buffer);
  for (let i = 0; i < n; i++) v.setInt16(i * 2, Math.round(amp * Math.sin((2 * Math.PI * 220 * i) / RATE)), true);
  return b;
}
const quiet = (ms: number) => new Uint8Array(Math.round((RATE * ms) / 1000) * 2);
function cat(...ps: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(ps.reduce((s, p) => s + p.length, 0));
  let o = 0;
  for (const p of ps) out.set(p, o), (o += p.length);
  return out;
}
function wav(pcm: Uint8Array): Uint8Array {
  const h = new DataView(new ArrayBuffer(44));
  const s = (o: number, t: string) => [...t].forEach((c, i) => h.setUint8(o + i, c.charCodeAt(0)));
  s(0, "RIFF"); h.setUint32(4, 36 + pcm.length, true); s(8, "WAVE"); s(12, "fmt ");
  h.setUint32(16, 16, true); h.setUint16(20, 1, true); h.setUint16(22, 1, true);
  h.setUint32(24, RATE, true); h.setUint32(28, RATE * 2, true); h.setUint16(32, 2, true); h.setUint16(34, 16, true);
  s(36, "data"); h.setUint32(40, pcm.length, true);
  return cat(new Uint8Array(h.buffer), pcm);
}

type Run = { proc: Bun.Subprocess<"pipe", "pipe", "pipe">; events: any[]; next: (ev: string) => Promise<any>; done: Promise<number> };

function run(args: string[], env: Record<string, string | undefined> = {}): Run {
  const proc = Bun.spawn([...EXE, ...args], {
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
    env: Object.fromEntries(
      Object.entries({ PATH: process.env.PATH, OPENAI_API_KEY: "good", OPENAI_BASE_URL: mock.base, ...env }).filter(([, v]) => v !== undefined),
    ) as any,
  }) as any;
  const events: any[] = [];
  const waiting: { ev: string; ok: (e: any) => void }[] = [];
  const pump = (async () => {
    const dec = new TextDecoder();
    let buf = "";
    for await (const b of proc.stdout) {
      buf += dec.decode(b, { stream: true });
      const lines = buf.split("\n");
      buf = lines.pop()!;
      for (const l of lines) {
        const e = JSON.parse(l); // every stdout line must be JSON
        events.push(e);
        for (const w of waiting.filter((w) => w.ev === e.event)) waiting.splice(waiting.indexOf(w), 1), w.ok(e);
      }
    }
  })();
  new Response(proc.stderr).text().then((t) => t && process.stderr.write(t));
  return {
    proc,
    events,
    next: (ev) => {
      const e = events.find((e) => e.event === ev);
      return e ? Promise.resolve(e) : new Promise((ok) => waiting.push({ ev, ok }));
    },
    done: pump.then(() => proc.exited),
  };
}

test("segmenter: silence sends nothing, a click is cleared, speech then quiet commits", () => {
  const s = new Segmenter();
  const chunk = (b: Uint8Array) => {
    const out = [];
    for (let o = 0; o < b.length; o += 4800) out.push(...s.push(b.subarray(o, o + 4800)));
    return out;
  };
  expect(chunk(quiet(3000))).toEqual([]);
  expect(s.flush()).toEqual([]);
  const click = chunk(cat(tone(100), quiet(1000)));
  expect(click.some((a) => "clear" in a)).toBe(true);
  expect(click.some((a) => "commit" in a)).toBe(false);
  const speech = chunk(cat(tone(1000), quiet(800)));
  expect(speech.filter((a) => "commit" in a).length).toBe(1);
  const long = chunk(tone(16000));
  expect(long.filter((a) => "commit" in a).length).toBe(1); // cut at 15 s
  expect(s.flush()).toEqual([{ commit: true }]);
});

test("live from stdin: session, appends, commit after quiet, deltas and done", async () => {
  mock.ws.length = 0;
  const kw = join(dir, "dictionary.txt");
  writeFileSync(kw, "  AC-42 \n\npremium plan\n");
  const r = run(["live", "--source", "stdin", "--keywords-file", kw, "--delay", "medium", "--language", "en", "--prompt", "KiCad talk"]);
  const pcm = cat(quiet(500), tone(1500), quiet(1000), tone(1000));
  r.proc.stdin.write(pcm);
  r.proc.stdin.end();
  expect(await r.done).toBe(0);

  const s = mock.ws[0];
  expect(s.type).toBe("session.update");
  expect(s.session.type).toBe("transcription");
  expect(s.session.audio.input.format).toEqual({ type: "audio/pcm", rate: 24000 });
  expect(s.session.audio.input.turn_detection).toBeNull();
  expect(s.session.audio.input.transcription).toEqual({
    model: "gpt-live-transcribe",
    prompt: "KiCad talk",
    keywords: ["AC-42", "premium plan"],
    languages: ["en"],
    delay: "medium",
  });

  const appends = mock.ws.filter((e) => e.type === "input_audio_buffer.append");
  expect(appends.length).toBeGreaterThan(0);
  let sent = 0;
  for (const a of appends) {
    const b = Buffer.from(a.audio, "base64");
    expect(Buffer.from(b.toString("base64"), "base64").equals(b)).toBe(true);
    expect(b.length % 2).toBe(0);
    sent += b.length;
  }
  expect(sent).toBeLessThan(pcm.length); // leading silence beyond the pre-roll is not sent
  expect(mock.ws.filter((e) => e.type === "input_audio_buffer.commit").length).toBe(2);

  const ev = r.events.map((e) => e.event).filter((e) => e !== "level");
  expect(ev[0]).toBe("ready");
  expect(r.events[0]).toEqual({ event: "ready", recorder: "stdin", device: "", label: "" });
  expect(ev.at(-1)).toBe("end");
  expect(ev).toContain("stopping");
  expect(ev).not.toContain("error");
  const dones = r.events.filter((e) => e.event === "done");
  expect(dones.map((d) => d.item)).toEqual(["item_1", "item_2"]);
  expect(dones[0].text).toMatch(/^seg1 \d+ms$/);
  const deltas = r.events.filter((e) => e.event === "delta" && e.item === "item_1").map((e) => e.text).join("");
  expect(deltas).toBe(dones[0].text);
});

// A fake recorder on PATH: writes its arguments to <bin>/args, then runs
// `body` (sh, absolute paths). Default: plays speech, then waits to be killed.
let binN = 0;
function fakeBin(files: Record<string, string>): string {
  const bin = join(dir, `bin-${++binN}`);
  Bun.spawnSync(["mkdir", "-p", bin]);
  for (const [name, body] of Object.entries(files)) {
    writeFileSync(join(bin, name), `#!/bin/sh\n${body}\n`);
    chmodSync(join(bin, name), 0o755);
  }
  return bin;
}
function pcmFile(name: string, b: Uint8Array): string {
  const p = join(dir, name);
  writeFileSync(p, b);
  return p;
}
const recorderBody = (play: string) => `[ "$1" = -L ] && exit 1\necho "$@" > "$(/usr/bin/dirname "$0")/args"\n${play}\nexec /bin/sleep 60`;
function fakeRecorder(name = "arecord", play?: string, extra: Record<string, string> = {}): string {
  const speech = pcmFile("speech.pcm", cat(quiet(200), tone(1200)));
  return fakeBin({ [name]: recorderBody(play ?? `/bin/cat '${speech}'`), ...extra });
}

// pactl answering like PulseAudio (or pipewire-pulse) does
const PACTL_JSON = JSON.stringify([
  { name: "alsa_input.usb-mic.mono", description: "USB Mic Mono", monitor_of_sink: null, properties: {} },
  { name: "alsa_output.hdmi.monitor", description: "Monitor of HDMI", monitor_of_sink: "alsa_output.hdmi", properties: { "device.class": "monitor" } },
  { name: "alsa_input.webcam.stereo", description: "Webcam Stereo", monitor_of_sink: "n/a", properties: {} },
]);
const fakePactl = `if [ "$1" = get-default-source ]; then echo alsa_input.usb-mic.mono; else /bin/cat <<'J'\n${PACTL_JSON}\nJ\nfi`;

for (const how of ["stop line", "SIGTERM"]) {
  test(`live from a recorder, stopped by ${how}: commits what it has and ends cleanly`, async () => {
    mock.ws.length = 0;
    const r = run(["live"], { PATH: fakeRecorder() });
    await r.next("ready");
    await Bun.sleep(700);
    if (how === "SIGTERM") r.proc.kill("SIGTERM");
    else r.proc.stdin.write("stop\n");
    expect(await r.done).toBe(0);
    const ev = r.events.map((e) => e.event).filter((e) => e !== "level");
    expect(ev.slice(0, 2)).toEqual(["ready", "stopping"]);
    expect(ev.at(-1)).toBe("end");
    expect(mock.ws.filter((e) => e.type === "input_audio_buffer.commit").length).toBe(1);
    expect(r.events.find((e) => e.event === "done")?.text).toMatch(/^seg1/);
  });
}

test("devices: parsers skip monitors", async () => {
  const { fromPactl, fromPwDump, fromArecord } = await import("../src/devices");
  expect(fromPactl(PACTL_JSON)).toEqual([
    { name: "alsa_input.usb-mic.mono", label: "USB Mic Mono" },
    { name: "alsa_input.webcam.stereo", label: "Webcam Stereo" },
  ]);
  const dump = [
    { type: "PipeWire:Interface:Node", info: { props: { "media.class": "Audio/Source", "node.name": "mic", "node.description": "The Mic" } } },
    { type: "PipeWire:Interface:Node", info: { props: { "media.class": "Audio/Sink", "node.name": "spk", "node.description": "Speakers" } } },
    { type: "PipeWire:Interface:Metadata", metadata: [{ key: "default.audio.source", value: { name: "mic" } }] },
  ];
  expect(fromPwDump(JSON.stringify(dump))).toEqual({ default: "mic", devices: [{ name: "mic", label: "The Mic" }] });
  expect(fromArecord("null\n    Discard all samples\ndefault\n    Default ALSA Output\nhw:CARD=X,DEV=0\n    X, USB Audio\n    Direct\n")).toEqual([
    { name: "default", label: "Default ALSA Output" },
    { name: "hw:CARD=X,DEV=0", label: "X, USB Audio, Direct" },
  ]);
});

test("devices: from pactl; nothing to ask is an empty list and an error", async () => {
  const r = run(["devices"], { PATH: fakeBin({ pactl: fakePactl }) });
  expect(await r.done).toBe(0);
  expect(r.events).toEqual([
    {
      event: "devices",
      default: "alsa_input.usb-mic.mono",
      devices: [
        { name: "alsa_input.usb-mic.mono", label: "USB Mic Mono" },
        { name: "alsa_input.webcam.stereo", label: "Webcam Stereo" },
      ],
    },
    { event: "end" },
  ]);
  const r2 = run(["devices"], { PATH: noTools });
  expect(await r2.done).toBe(1);
  expect(r2.events.map((e) => e.event)).toEqual(["devices", "error", "end"]);
  expect(r2.events[0].devices).toEqual([]);
});

test("live: ready names the recorder and the default device; --device reaches the recorder", async () => {
  const bin = fakeRecorder("arecord", undefined, { pactl: fakePactl });
  const r = run(["live"], { PATH: bin });
  expect(await r.next("ready")).toEqual({ event: "ready", recorder: "arecord", device: "alsa_input.usb-mic.mono", label: "USB Mic Mono" });
  r.proc.kill("SIGTERM");
  expect(await r.done).toBe(0);
  expect(await Bun.file(join(bin, "args")).text()).not.toContain("-D");

  const r2 = run(["live", "--device", "alsa_input.webcam.stereo"], { PATH: bin });
  expect(await r2.next("ready")).toEqual({ event: "ready", recorder: "arecord", device: "alsa_input.webcam.stereo", label: "Webcam Stereo" });
  r2.proc.kill("SIGTERM");
  expect(await r2.done).toBe(0);
  expect((await Bun.file(join(bin, "args")).text()).trim()).toEndWith("-D alsa_input.webcam.stereo");

  const pw = fakeRecorder("pw-record");
  const r3 = run(["live", "--source", "pw-record", "--device", "mic2"], { PATH: pw });
  expect(await r3.next("ready")).toMatchObject({ recorder: "pw-record", device: "mic2", label: "" });
  r3.proc.kill("SIGTERM");
  expect(await r3.done).toBe(0);
  expect((await Bun.file(join(pw, "args")).text()).trim()).toEndWith("--target mic2 -");
});

test("live: a recorder that gives nothing gets the no-audio hint", async () => {
  const r = run(["live"], { PATH: fakeRecorder("arecord", ":") });
  await r.next("ready");
  expect(await r.next("hint")).toEqual({ event: "hint", hint: "no-audio" });
  r.proc.kill("SIGTERM");
  expect(await r.done).toBe(0);
  const levels = r.events.filter((e) => e.event === "level");
  expect(levels.length).toBeGreaterThanOrEqual(10);
  expect(levels.every((e) => e.v === 0)).toBe(true);
}, 15000);

test("live: silence gets the silent hint, then speech gets ok; levels follow the sound", async () => {
  const q = pcmFile("quiet5.pcm", quiet(5000));
  const sp = pcmFile("speech2.pcm", tone(1500));
  // audio at about real time: a quiet second a second, then speech
  const play = `for i in 1 2 3 4 5; do /usr/bin/head -c 48000 '${q}'; /bin/sleep 1; done\n/bin/cat '${sp}'\n/usr/bin/head -c 48000 '${q}'`; // quiet after: a commit
  const r = run(["live"], { PATH: fakeRecorder("arecord", play) });
  await r.next("ready");
  expect(await r.next("hint")).toEqual({ event: "hint", hint: "silent" });
  await r.next("done");
  while (!r.events.some((e) => e.event === "level" && e.v > 0)) await Bun.sleep(50);
  r.proc.kill("SIGTERM");
  expect(await r.done).toBe(0);
  const hints = r.events.filter((e) => e.event === "hint").map((e) => e.hint);
  expect(hints).toEqual(["silent", "ok"]);
  const vs = r.events.filter((e) => e.event === "level").map((e) => e.v);
  expect(vs.every((v) => Number.isInteger(v) && v >= 0 && v <= 100)).toBe(true);
  expect(Math.max(...vs)).toBe(75); // a sine peaking at 8000 is about -15 dBFS
  expect(vs.slice(0, 8).every((v) => v === 0)).toBe(true);
}, 20000);

test("levels: -60 dBFS is 0, full scale is 100", async () => {
  const { levelOf } = await import("../src/main");
  expect(levelOf(0)).toBe(0);
  expect(levelOf(32768 / 1000)).toBe(0);
  expect(levelOf(32768)).toBe(100);
  expect(levelOf(32768 / 31.62)).toBe(50);
});

test("live with no recorder is an error event", async () => {
  const r = run(["live"], { PATH: noTools });
  expect(await r.done).toBe(1);
  expect(r.events.map((e) => e.event)).toEqual(["error", "end"]);
  expect(r.events[0].error).toContain("no recorder");
});

test("a bad key is a 401 error event", async () => {
  const r = run(["live", "--source", "stdin"], { OPENAI_API_KEY: "bad" });
  r.proc.stdin.end();
  expect(await r.done).toBe(1);
  expect(r.events.map((e) => e.event)).toEqual(["error", "end"]);
  expect(r.events[0].error).toContain("401");
});

test("no key is an error event; --key-file wins over the environment", async () => {
  const r = run(["live", "--source", "stdin"], { OPENAI_API_KEY: undefined });
  r.proc.stdin.end();
  expect(await r.done).toBe(1);
  expect(r.events.map((e) => e.event)).toEqual(["error", "end"]);

  const kf = join(dir, "openai.key");
  writeFileSync(kf, "good\n");
  const r2 = run(["live", "--source", "stdin", "--key-file", kf], { OPENAI_API_KEY: "bad" });
  r2.proc.stdin.end();
  expect(await r2.done).toBe(0);
  expect(r2.events.map((e) => e.event)).toEqual(["ready", "stopping", "end"]);
});

// A Pebble Index style webhook body: multipart with an audio part.
async function pebbleBody(withAudio = true): Promise<{ path: string; ct: string }> {
  const f = new FormData();
  if (withAudio) f.append("audio", new File([wav(cat(tone(2000), quiet(300), tone(1000)))], "note.wav", { type: "audio/wav" }));
  f.append("transcription", "on-ring text");
  f.append("recordedAt", "2026-09-25T10:00:00Z");
  f.append("client", "pebble");
  const res = new Response(f);
  const ct = res.headers.get("content-type")!; // read before the body: Bun drops it after
  const path = join(dir, `body-${withAudio}.bin`);
  writeFileSync(path, new Uint8Array(await res.arrayBuffer()));
  return { path, ct };
}

test("file: multipart audio part through the realtime path (with ffmpeg)", async () => {
  if (!Bun.which("ffmpeg")) return console.warn("ffmpeg not found: skipped");
  mock.ws.length = 0;
  mock.rest.length = 0;
  const { path, ct } = await pebbleBody();
  const r = run(["file", path, "--content-type", ct]);
  expect(await r.done).toBe(0);
  expect(r.events.map((e) => e.event)).toEqual(["ready", "done", "end"]);
  expect(r.events[1]).toMatchObject({ item: "file" });
  expect(r.events[1].text).toMatch(/^seg1 3\d{3}ms$/);
  expect(mock.ws[0].session.audio.input.transcription.model).toBe("gpt-live-transcribe");
  expect(mock.rest.length).toBe(0);
});

test("file: without ffmpeg, REST gpt-transcribe with keywords[] and languages[]", async () => {
  mock.rest.length = 0;
  const { path, ct } = await pebbleBody();
  const kw = join(dir, "kw.txt");
  writeFileSync(kw, "AC-42\npremium plan\n");
  const r = run(["file", path, "--content-type", ct, "--keywords-file", kw, "--language", "en", "--prompt", "p"], { PATH: noTools });
  expect(await r.done).toBe(0);
  expect(r.events.map((e) => e.event)).toEqual(["ready", "done", "end"]);
  expect(r.events[1].text).toMatch(/^rest \d+ bytes$/);
  const f = mock.rest[0];
  expect(f.get("model")).toBe("gpt-transcribe");
  expect(f.get("response_format")).toBe("json");
  expect(f.get("prompt")).toBe("p");
  expect(f.getAll("keywords[]")).toEqual(["AC-42", "premium plan"]);
  expect(f.getAll("languages[]")).toEqual(["en"]);
  expect((f.get("file") as File).name).toBe("note.wav");
});

test("file: realtime refused falls back to REST; a 400 about keywords retries without them", async () => {
  mock.rest.length = 0;
  mock.opts.refuseWs = true;
  mock.opts.rejectHints = true;
  try {
    const p = join(dir, "raw.wav");
    writeFileSync(p, wav(tone(1000)));
    const kw = join(dir, "kw2.txt");
    writeFileSync(kw, "AC-42\n");
    const r = run(["file", p, "--keywords-file", kw]);
    expect(await r.done).toBe(0);
    expect(r.events.map((e) => e.event)).toEqual(["ready", "done", "end"]);
    expect(mock.rest.length).toBe(2);
    expect(mock.rest[1].getAll("keywords[]")).toEqual([]);
  } finally {
    mock.opts.refuseWs = false;
    mock.opts.rejectHints = false;
  }
});

test("file: a multipart body without an audio part", async () => {
  const { path, ct } = await pebbleBody(false);
  const r = run(["file", path, "--content-type", ct]);
  expect(await r.done).toBe(1);
  expect(r.events.map((e) => e.event)).toEqual(["ready", "error", "end"]);
  expect(r.events[1].error).toBe("no audio part");
});

test("usage: no arguments exits 2 with nothing on stdout", async () => {
  const r = run([]);
  expect(await r.done).toBe(2);
  expect(r.events).toEqual([]);
});
