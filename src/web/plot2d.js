// A board or schematic on the web page.
//
// The hub sends them as it does to the phones (core/plot.bend): a "plot"
// lists chunks in paint order, each either the index of one this page
// already holds (the last plot applied) or the chunk itself: a layer's
// colour and opacity, and its pieces as capsules (tracks, pads, lines,
// round ends) or polygons (fills), in micrometres. Bend decides which
// source is on screen and asks for it (client.bend's Solid.want, the
// canvas's data-key); this file only decodes and draws, panned and zoomed
// by the pointer. Nothing animates: a frame is drawn when something changed.

// varints (7 bits a byte, low first) and zigzag, as the hub writes them
function reader(bytes) {
  let i = 0;
  const next = () => {
    let acc = 0, sh = 0;
    while (i < bytes.length) {
      const v = bytes[i++];
      acc += (v & 127) * 2 ** sh;
      if (v < 128) break;
      sh += 7;
    }
    return acc;
  };
  return { more: () => i < bytes.length, next, signed: () => { const z = next(); return z % 2 ? -(z + 1) / 2 : z / 2; } };
}

// one chunk as two paths in board coordinates: its fills and its strokes
// (capsules of the chunk's width; a dot is a capsule of no length)
function chunk(o) {
  const mode = o.m ?? 1;
  const r = (o.w ?? 0) / 2;
  const v = reader(o.d ?? new Uint8Array(0));
  const fill = new Path2D(), line = new Path2D(), dots = new Path2D();
  let px = 0, py = 0;
  while (v.more()) {
    v.next(); // the piece's info index (what a tap would ask about)
    if (mode === 2) {
      px += v.signed(); py += v.signed();
      dots.moveTo(px + r, py);
      dots.arc(px, py, r, 0, Math.PI * 2);
      continue;
    }
    const n = v.next();
    const pts = [];
    for (let k = 0; k < n && v.more(); k += 1) { px += v.signed(); py += v.signed(); pts.push(px, py); }
    if (pts.length < 2) continue;
    const p = mode === 0 ? fill : line;
    p.moveTo(pts[0], pts[1]);
    for (let k = 2; k < pts.length; k += 2) p.lineTo(pts[k], pts[k + 1]);
    if (mode === 0) p.closePath();
    else if (pts.length === 2) { dots.moveTo(pts[0] + r, pts[1]); dots.arc(pts[0], pts[1], r, 0, Math.PI * 2); }
  }
  const c = o.c ?? 0;
  const color = `rgba(${(c >> 16) & 255},${(c >> 8) & 255},${c & 255},${(o.a ?? 255) / 255})`;
  return { fill, line, dots, r, color, layer: o.l ?? 0 };
}

// what this connection holds: the chunks of the last plot, in its order
let held = [];
// the newest plot of each source (or why there is none), by its key
const plots = new Map();

// a new connection holds nothing
export function reset() {
  held = [];
  plots.clear();
}

export function got(o) {
  const key = typeof o.key === "string" ? o.key : "";
  if (typeof o.none === "string") {
    held = [];
    plots.set(key, { none: o.none });
  } else {
    const refs = Array.isArray(o.cs) ? o.cs : [];
    const all = [];
    for (const r of refs) {
      const c = typeof r === "number" ? held[r] : r && typeof r === "object" ? chunk(r) : null;
      if (c) all.push(c);
    }
    held = all;
    const box = Array.isArray(o.box) && o.box.length === 4 ? o.box : [0, 0, 1, 1];
    plots.set(key, { chunks: all, box });
  }
  if (view && view.key === key) { view.show(plots.get(key)); present(plots.get(key)); }
}

class View {
  constructor(canvas, bg) {
    this.canvas = canvas;
    this.bg = bg;
    this.key = "";
    this.plot = null;
    this.off = 0;
    this.scale = 1; this.ox = 0; this.oy = 0;
    this.fitted = false;
    this.drag = null;
    canvas.addEventListener("pointerdown", (e) => { canvas.setPointerCapture(e.pointerId); this.drag = { x: e.clientX, y: e.clientY }; canvas.classList.add("dragging"); });
    canvas.addEventListener("pointermove", (e) => {
      if (!this.drag) return;
      this.ox += e.clientX - this.drag.x; this.oy += e.clientY - this.drag.y;
      this.touched = true;
      this.drag.x = e.clientX; this.drag.y = e.clientY;
      this.later();
    });
    const up = () => { this.drag = null; canvas.classList.remove("dragging"); };
    canvas.addEventListener("pointerup", up);
    canvas.addEventListener("pointercancel", up);
    canvas.addEventListener("wheel", (e) => {
      e.preventDefault();
      const b = canvas.getBoundingClientRect();
      const mx = e.clientX - b.left, my = e.clientY - b.top;
      const f = Math.exp(-e.deltaY * 0.0015);
      this.ox = mx - (mx - this.ox) * f; this.oy = my - (my - this.oy) * f;
      this.scale *= f;
      this.touched = true;
      this.later();
    }, { passive: false });
    canvas.addEventListener("dblclick", () => this.fit());
    // a new size refits the view, unless the user has moved it
    new ResizeObserver(() => { if (!this.fitted || !this.touched) this.fit(); else this.later(); }).observe(canvas);
  }

  // the whole plot in view, centred, with a margin
  fit() {
    const w = this.canvas.clientWidth, h = this.canvas.clientHeight;
    if (!this.plot || !this.plot.box || w === 0 || h === 0) { this.later(); return; }
    const [x0, y0, x1, y1] = this.plot.box;
    this.scale = 0.9 * Math.min(w / Math.max(x1 - x0, 1), h / Math.max(y1 - y0, 1));
    this.ox = w / 2 - (x0 + x1) / 2 * this.scale;
    this.oy = h / 2 - (y0 + y1) / 2 * this.scale;
    this.fitted = true;
    this.touched = false;
    this.later();
  }

  show(p) {
    const first = !this.plot || !this.plot.box;
    this.plot = p;
    if (first) this.fit(); else this.later();
  }

  later() {
    if (this.queued) return;
    this.queued = true;
    requestAnimationFrame(() => { this.queued = false; this.draw(); });
  }

  draw() {
    const c = this.canvas, dpr = window.devicePixelRatio || 1;
    const w = Math.max(1, Math.round(c.clientWidth * dpr)), h = Math.max(1, Math.round(c.clientHeight * dpr));
    if (c.width !== w || c.height !== h) { c.width = w; c.height = h; }
    const g = c.getContext("2d");
    g.setTransform(1, 0, 0, 1, 0, 0);
    g.fillStyle = this.bg;
    g.fillRect(0, 0, w, h);
    const p = this.plot;
    if (!p || !p.chunks) {
      g.fillStyle = "#8a8f98";
      g.font = `${13 * dpr}px system-ui, sans-serif`;
      g.textAlign = "center";
      g.fillText(p && p.none ? p.none : "Loading…", w / 2, h / 2);
      return;
    }
    g.setTransform(this.scale * dpr, 0, 0, this.scale * dpr, this.ox * dpr, this.oy * dpr);
    g.lineCap = "round";
    g.lineJoin = "round";
    for (const k of p.chunks) {
      if (Math.floor(this.off / 2 ** k.layer) % 2) continue; // a layer turned off
      g.fillStyle = k.color;
      g.strokeStyle = k.color;
      g.fill(k.fill);
      g.fill(k.dots);
      // a line never thinner than a pixel, however far out the view is
      g.lineWidth = Math.max(k.r * 2, 1 / this.scale);
      g.stroke(k.line);
    }
  }
}

let view = null;

// the Layers menu lists only the layers the plot has something on
function present(p) {
  const has = new Set(p && p.chunks ? p.chunks.map((c) => c.layer) : []);
  for (const b of document.querySelectorAll(".layer-list [data-layer]")) b.hidden = has.size > 0 && !has.has(Number(b.dataset.layer));
}

// after each render: the canvas on the page (if any) shows the source its
// data-key names, once the hub has sent it
export function mount(canvas) {
  if (!canvas) { view = null; return; }
  if (!view || view.canvas !== canvas) view = new View(canvas, canvas.dataset.bg || "#0d0f12");
  const off = Number(canvas.dataset.off || 0);
  if (off !== view.off) { view.off = off; view.later(); }
  present(view.plot);
  const key = canvas.dataset.key || "";
  if (key !== view.key) {
    view.key = key;
    view.plot = null;
    view.fitted = false;
    if (plots.has(key)) view.show(plots.get(key)); else view.later();
  }
}

export function fit() {
  view?.fit();
}
