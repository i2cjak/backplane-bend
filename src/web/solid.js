// A part in 3D on the web page.
//
// The hub sends a part's model as it does to the phones: a CBOR "plot"
// with a mesh (core/plot.bend's Solid: triangles in board axes, z up, the
// hub's units; each the XOR of its colour with the one before, then
// nine zigzag coordinate deltas). Bend decides which part is on show and
// asks for it (client.bend's Solid.want, the canvas's data-key); this
// file only decodes the mesh and draws it with WebGL, turned by the
// pointer. Nothing animates: a frame is drawn when something changed.

// CBOR, as much as plots use (ints, byte and text strings, arrays, maps;
// keys 1 and 31 are the hub's dictionary words "t" and "key")
function cbor(b) {
  let i = 0;
  const arg = (ai) => {
    if (ai < 24) return ai;
    if (ai === 24) return b[i++];
    if (ai === 25) { i += 2; return (b[i - 2] << 8) | b[i - 1]; }
    if (ai === 26) { i += 4; return ((b[i - 4] << 24) >>> 0) + (b[i - 3] << 16) + (b[i - 2] << 8) + b[i - 1]; }
    return 0;
  };
  const item = () => {
    const h = b[i++];
    const n = arg(h & 31);
    switch (h >> 5) {
      case 0: return n;
      case 1: return -1 - n;
      case 2: i += n; return b.subarray(i - n, i);
      case 3: i += n; return new TextDecoder().decode(b.subarray(i - n, i));
      case 4: return Array.from({ length: n }, item);
      case 5: {
        const o = {};
        for (let k = 0; k < n; k += 1) {
          const key = item();
          o[key === 1 ? "t" : key === 31 ? "key" : String(key)] = item();
        }
        return o;
      }
      default: return null;
    }
  };
  return item();
}

// a frame the hub sent is a plot: a map whose first key is "t" (1) and
// value the text "plot"
export function isPlot(b) {
  return b.length > 7 && b[0] >= 0xa0 && b[0] <= 0xb7 && b[1] === 1 && b[2] === 0x64 &&
    b[3] === 0x70 && b[4] === 0x6c && b[5] === 0x6f && b[6] === 0x74;
}

// the triangles of a plot's mesh: positions, flat normals and colours
function mesh(o) {
  const bytes = o.mesh;
  const n = o.n | 0;
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
  const signed = () => { const z = next(); return z % 2 ? -(z + 1) / 2 : z / 2; };
  const pos = new Float32Array(n * 9), nrm = new Float32Array(n * 9), col = new Float32Array(n * 9);
  let color = 0, px = 0, py = 0, pz = 0, w = 0;
  const p = new Float32Array(9);
  for (let t = 0; t < n && i < bytes.length; t += 1) {
    color = (color ^ next()) >>> 0;
    for (let k = 0; k < 3; k += 1) {
      px += signed(); py += signed(); pz += signed();
      p[3 * k] = px; p[3 * k + 1] = py; p[3 * k + 2] = pz;
    }
    const ux = p[3] - p[0], uy = p[4] - p[1], uz = p[5] - p[2];
    const vx = p[6] - p[0], vy = p[7] - p[1], vz = p[8] - p[2];
    let nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
    const l = Math.hypot(nx, ny, nz) || 1;
    nx /= l; ny /= l; nz /= l;
    const r = ((color >> 16) & 255) / 255, g = ((color >> 8) & 255) / 255, bl = (color & 255) / 255;
    for (let k = 0; k < 9; k += 3) {
      pos.set(p.subarray(k, k + 3), w + k);
      nrm[w + k] = nx; nrm[w + k + 1] = ny; nrm[w + k + 2] = nz;
      col[w + k] = r; col[w + k + 1] = g; col[w + k + 2] = bl;
    }
    w += 9;
  }
  // the box the camera fits, from the positions themselves
  const box = [Infinity, Infinity, Infinity, -Infinity, -Infinity, -Infinity];
  for (let k = 0; k < w; k += 3) {
    for (let a = 0; a < 3; a += 1) {
      box[a] = Math.min(box[a], pos[k + a]);
      box[a + 3] = Math.max(box[a + 3], pos[k + a]);
    }
  }
  if (!w) box.splice(0, 6, 0, 0, 0, 1, 1, 1);
  return { pos: pos.subarray(0, w), nrm: nrm.subarray(0, w), col: col.subarray(0, w), count: w / 3, box };
}

// the newest model of each source, by its key
const models = new Map();

export function got(b) {
  const o = cbor(b);
  if (!o || !o.mesh || typeof o.key !== "string") return;
  models.set(o.key, mesh(o));
  if (view && view.key === o.key) view.show(models.get(o.key));
}

const VS = `attribute vec3 p; attribute vec3 n; attribute vec3 c; uniform mat4 m; uniform vec3 eye;
varying vec3 vc; varying float vl;
void main() { gl_Position = m * vec4(p, 1.0); vc = c; vl = abs(dot(normalize(n), normalize(eye - p))); }`;
const FS = `precision mediump float; varying vec3 vc; varying float vl;
void main() { gl_FragColor = vec4(vc * (0.35 + 0.65 * vl), 1.0); }`;

function persp(fov, a, near, far) {
  const f = 1 / Math.tan(fov / 2), nf = 1 / (near - far);
  return [f / a, 0, 0, 0, 0, f, 0, 0, 0, 0, (far + near) * nf, -1, 0, 0, 2 * far * near * nf, 0];
}

function look(e, c, u) {
  const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
  const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
  const norm = (a) => { const l = Math.hypot(...a) || 1; return a.map((x) => x / l); };
  const z = norm(sub(e, c)), x = norm(cross(u, z)), y = cross(z, x);
  const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
  return [x[0], y[0], z[0], 0, x[1], y[1], z[1], 0, x[2], y[2], z[2], 0, -dot(x, e), -dot(y, e), -dot(z, e), 1];
}

function mul(a, b) {
  const o = new Array(16).fill(0);
  for (let c = 0; c < 4; c += 1) for (let r = 0; r < 4; r += 1) for (let k = 0; k < 4; k += 1) o[c * 4 + r] += a[k * 4 + r] * b[c * 4 + k];
  return o;
}

// one canvas's view: the camera turns about the model's centre, z up,
// fitted to its box when a new part comes
class View {
  constructor(canvas) {
    this.canvas = canvas;
    this.key = "";
    this.gl = canvas.getContext("webgl", { antialias: true, alpha: true, premultipliedAlpha: true });
    this.count = 0;
    this.yaw = -0.6; this.pitch = 0.5; this.dist = 1; this.cx = 0; this.cy = 0; this.cz = 0; this.r = 1;
    if (!this.gl) return;
    const gl = this.gl;
    const sh = (type, src) => { const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s); return s; };
    this.prog = gl.createProgram();
    gl.attachShader(this.prog, sh(gl.VERTEX_SHADER, VS));
    gl.attachShader(this.prog, sh(gl.FRAGMENT_SHADER, FS));
    gl.linkProgram(this.prog);
    this.bufs = ["p", "n", "c"].map((a) => ({ a: gl.getAttribLocation(this.prog, a), b: gl.createBuffer() }));
    this.drag = null;
    canvas.addEventListener("pointerdown", (e) => { canvas.setPointerCapture(e.pointerId); this.drag = { x: e.clientX, y: e.clientY, pan: e.shiftKey || e.button !== 0 }; });
    canvas.addEventListener("pointermove", (e) => this.move(e));
    canvas.addEventListener("pointerup", () => { this.drag = null; });
    canvas.addEventListener("wheel", (e) => { e.preventDefault(); this.dist *= Math.exp(e.deltaY * 0.0015); this.later(); }, { passive: false });
    canvas.addEventListener("dblclick", () => { this.fit(); this.later(); });
    canvas.addEventListener("contextmenu", (e) => e.preventDefault());
  }

  move(e) {
    if (!this.drag) return;
    const dx = e.clientX - this.drag.x, dy = e.clientY - this.drag.y;
    this.drag.x = e.clientX; this.drag.y = e.clientY;
    if (this.drag.pan) {
      const s = this.dist / Math.max(this.canvas.clientHeight, 1);
      const cy = Math.cos(this.yaw), sy = Math.sin(this.yaw);
      this.cx -= (dx * cy) * s; this.cy -= (dx * sy) * s; this.cz += dy * s;
    } else {
      this.yaw -= dx * 0.008;
      this.pitch = Math.max(-1.55, Math.min(1.55, this.pitch + dy * 0.008));
    }
    this.later();
  }

  fit() {
    const [x0, y0, z0, x1, y1, z1] = this.box;
    this.cx = (x0 + x1) / 2; this.cy = (y0 + y1) / 2; this.cz = (z0 + z1) / 2;
    this.r = Math.max(Math.hypot(x1 - x0, y1 - y0, z1 - z0) / 2, 1);
    // the field of view is vertical: a narrow canvas fits the width instead
    const a = this.canvas.clientWidth / Math.max(this.canvas.clientHeight, 1);
    this.dist = this.r / Math.sin(Math.atan(Math.tan(0.35) * Math.min(a, 1))) * 1.05;
  }

  show(m) {
    if (!this.gl || !m) return;
    const gl = this.gl;
    [m.pos, m.nrm, m.col].forEach((d, k) => { gl.bindBuffer(gl.ARRAY_BUFFER, this.bufs[k].b); gl.bufferData(gl.ARRAY_BUFFER, d, gl.STATIC_DRAW); });
    const first = this.count === 0;
    this.count = m.count;
    this.box = m.box;
    if (first) this.fit();
    this.later();
  }

  later() {
    if (this.queued) return;
    this.queued = true;
    requestAnimationFrame(() => { this.queued = false; this.draw(); });
  }

  draw() {
    const gl = this.gl, c = this.canvas;
    if (!gl) return;
    const dpr = window.devicePixelRatio || 1;
    const w = Math.max(1, Math.round(c.clientWidth * dpr)), h = Math.max(1, Math.round(c.clientHeight * dpr));
    if (c.width !== w || c.height !== h) { c.width = w; c.height = h; }
    gl.viewport(0, 0, w, h);
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    if (!this.count) return;
    gl.enable(gl.DEPTH_TEST);
    gl.useProgram(this.prog);
    const cp = Math.cos(this.pitch);
    const eye = [this.cx + this.dist * cp * Math.sin(this.yaw), this.cy - this.dist * cp * Math.cos(this.yaw), this.cz + this.dist * Math.sin(this.pitch)];
    const m = mul(persp(0.7, w / h, this.dist / 100, this.dist + this.r * 4), look(eye, [this.cx, this.cy, this.cz], [0, 0, 1]));
    gl.uniformMatrix4fv(gl.getUniformLocation(this.prog, "m"), false, m);
    gl.uniform3fv(gl.getUniformLocation(this.prog, "eye"), eye);
    for (const { a, b } of this.bufs) {
      gl.bindBuffer(gl.ARRAY_BUFFER, b);
      gl.enableVertexAttribArray(a);
      gl.vertexAttribPointer(a, 3, gl.FLOAT, false, 0, 0);
    }
    gl.drawArrays(gl.TRIANGLES, 0, this.count);
  }
}

let view = null;

// after each render: the canvas on the page (if any) shows the model its
// data-key names, once the hub has sent it
export function mount(canvas) {
  if (!canvas) { view = null; return; }
  if (!view || view.canvas !== canvas) view = new View(canvas);
  const key = canvas.dataset.key || "";
  if (key !== view.key) {
    view.key = key;
    view.count = 0;
    if (models.has(key)) view.show(models.get(key));
    else view.later();
  } else {
    view.later();
  }
}
