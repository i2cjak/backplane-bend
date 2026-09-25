// Performance counters: the JS twin of perf.c (same rows, no trace file).

function perf_state() {
  if (globalThis.BACKPLANE_PERF === void 0) {
    globalThis.BACKPLANE_PERF = { t0: performance.now(), tab: new Map(), ring: [] };
  }
  return globalThis.BACKPLANE_PERF;
}

function perf_now_us() {
  return Math.floor((performance.now() - perf_state().t0) * 1000);
}

function perf_slot(name) {
  const tab = perf_state().tab;
  let s = tab.get(name);
  if (s === void 0) {
    s = { kind: 0, n: 0, sum: 0, max: 0, last: 0, mark: 0, b: [] };
    tab.set(name, s);
  }
  return s;
}

function perf_put(s, v) {
  s.n += 1;
  s.sum += v;
  s.last = v;
  s.max = Math.max(s.max, v);
  let i = 0;
  for (let x = v; x > 0 && i < 32; x = Math.floor(x / 2)) {
    i += 1;
  }
  while (s.b.length <= i) {
    s.b.push(0);
  }
  s.b[i] += 1;
}

function perf_us() {
  return perf_now_us() >>> 0;
}

function perf_span(name, t0) {
  const now = perf_now_us() >>> 0;
  perf_put(perf_slot(name), (now - t0) >>> 0);
  return now;
}

function perf_add(name, v) {
  const s = perf_slot(name);
  s.kind = 2;
  perf_put(s, v);
  return { $: "Unit" };
}

function perf_set(name, v) {
  const s = perf_slot(name);
  s.kind = 1;
  perf_put(s, v);
  return { $: "Unit" };
}

function perf_mark(name) {
  const s = perf_slot(name);
  if (s.mark === 0) {
    s.mark = perf_now_us() + 1;
  }
  return { $: "Unit" };
}

function perf_done(name) {
  const s = perf_slot(name);
  if (s.mark !== 0) {
    perf_put(s, perf_now_us() - (s.mark - 1));
    s.mark = 0;
  }
  return { $: "Unit" };
}

function perf_take() {
  const rows = [];
  const row = (name, s) => rows.push([name, s.kind, s.n, s.sum, s.max, s.last, (s.b.length ? s.b : [0]).join(",")].join("\t"));
  for (const [name, s] of perf_state().tab) {
    if (s.n > 0) {
      row(name, s);
    }
  }
  const g = (name, v) => {
    const s = { kind: 1, n: 0, sum: 0, max: 0, last: 0, b: [] };
    perf_put(s, v);
    row(name, s);
  };
  const mem = typeof process !== "undefined" ? process.memoryUsage().rss : 0;
  g("proc.rss_kb", Math.floor(mem / 1024));
  g("proc.up_ms", Math.floor(perf_now_us() / 1000));
  return rows.map((r) => r + "\n").join("");
}

function perf_emit(line) {
  io_out(2, io_bytes(line + "\n"));
  const ring = perf_state().ring;
  ring.push(line);
  if (ring.length > 512) {
    ring.shift();
  }
  return { $: "Unit" };
}

function perf_logs() {
  return perf_state().ring.map((l) => l + "\n").join("");
}
