// The microphones on this machine: PulseAudio's pactl, else PipeWire's
// pw-dump, else ALSA's arecord -L. Monitors of outputs are not microphones.

export type Device = { name: string; label: string };
export type Devices = { default: string; devices: Device[]; via: string };

const isMonitor = (name: string, cls = "") => name.endsWith(".monitor") || /monitor/i.test(cls);

// `pactl -f json list sources`
export function fromPactl(json: string): Device[] {
  const out: Device[] = [];
  for (const s of JSON.parse(json) as any[]) {
    const name = String(s?.name ?? "");
    const of = s?.monitor_of_sink;
    const monitorOf = of !== undefined && of !== null && of !== "" && of !== "n/a";
    if (!name || isMonitor(name) || monitorOf || s?.properties?.["device.class"] === "monitor") continue;
    out.push({ name, label: String(s?.description ?? s?.properties?.["device.description"] ?? name) });
  }
  return out;
}

// `pw-dump`: Audio/Source nodes, and the default from the "default" metadata
export function fromPwDump(json: string): { default: string; devices: Device[] } {
  const out: Device[] = [];
  let def = "";
  for (const o of JSON.parse(json) as any[]) {
    const p = o?.info?.props;
    const cls = String(p?.["media.class"] ?? "");
    if (cls.startsWith("Audio/Source") && p?.["node.name"] && !isMonitor(p["node.name"], cls)) {
      out.push({ name: String(p["node.name"]), label: String(p["node.description"] ?? p["node.nick"] ?? p["node.name"]) });
    }
    if (o?.type === "PipeWire:Interface:Metadata" && Array.isArray(o.metadata)) {
      for (const m of o.metadata) {
        if (m?.key === "default.audio.source") def = String(m?.value?.name ?? def);
        else if (m?.key === "default.configured.audio.source" && !def) def = String(m?.value?.name ?? "");
      }
    }
  }
  return { default: def, devices: out };
}

// `arecord -L`: a name at the start of a line, its description indented below
export function fromArecord(text: string): Device[] {
  const out: Device[] = [];
  for (const line of text.split("\n")) {
    if (!line.trim()) continue;
    if (!/^\s/.test(line)) out.push({ name: line.trim(), label: "" });
    else if (out.length) {
      const d = out[out.length - 1];
      d.label = d.label ? `${d.label}, ${line.trim()}` : line.trim();
    }
  }
  return out.filter((d) => d.name !== "null");
}

async function run(cmd: string[]): Promise<string | undefined> {
  const exe = Bun.which(cmd[0]);
  if (!exe) return undefined;
  try {
    const p = Bun.spawn([exe, ...cmd.slice(1)], { stdin: "ignore", stdout: "pipe", stderr: "ignore" });
    const t = setTimeout(() => p.kill(), 3000);
    const [out, code] = await Promise.all([new Response(p.stdout).text(), p.exited]);
    clearTimeout(t);
    return code === 0 ? out : undefined;
  } catch {
    return undefined;
  }
}

// Never throws: an empty list when nothing answers.
export async function listDevices(): Promise<Devices> {
  const pa = await run(["pactl", "-f", "json", "list", "sources"]);
  if (pa !== undefined) {
    try {
      const devices = fromPactl(pa);
      const def = ((await run(["pactl", "get-default-source"])) ?? "").trim();
      return { default: def, devices, via: "pactl" };
    } catch {}
  }
  const pw = await run(["pw-dump"]);
  if (pw !== undefined) {
    try {
      return { ...fromPwDump(pw), via: "pw-dump" };
    } catch {}
  }
  const al = await run(["arecord", "-L"]);
  if (al !== undefined) {
    const devices = fromArecord(al);
    return { default: devices.some((d) => d.name === "default") ? "default" : "", devices, via: "arecord" };
  }
  return { default: "", devices: [], via: "" };
}
