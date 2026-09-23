// step2glb: STEP (.step/.stp) -> binary glTF (GLB), via OpenCascade (occt-import-js, WASM).
//
//   step2glb IN.step OUT.glb [--linear 0.1] [--angular 0.5]
//   step2glb --tree IN.step
//
// A thin host adapter, like curl or git: it tessellates and packs; the Bend
// viewer owns everything after that. Coordinates stay in STEP millimetres
// (Z up, as authored); asset.extras records { unit: "mm", up: "Z" }.

import occtimportjs from "occt-import-js";
// Embedded into the executable by `bun build --compile`; a plain path under `bun run`.
import wasmPath from "occt-import-js/dist/occt-import-js.wasm" with { type: "file" };

const VERSION = "0.1.0";
const DEFAULT_COLOR: RGB = [0.8, 0.8, 0.8];

type RGB = [number, number, number];
type OcctFace = { first: number; last: number; color: RGB | null };
type OcctMesh = {
  name: string;
  color?: RGB;
  brep_faces: OcctFace[];
  attributes: { position: { array: number[] }; normal?: { array: number[] } };
  index: { array: number[] };
};
type OcctNode = { name: string; meshes: number[]; children: OcctNode[]; instance?: string };
type OcctResult = { success: boolean; root: OcctNode; meshes: OcctMesh[] };

type Box = { min: [number, number, number]; max: [number, number, number] };

function usage(code: number): never {
  const text = [
    "usage: step2glb IN.step OUT.glb [--linear MM] [--angular RAD]",
    "       step2glb --tree IN.step",
    "  --linear   linear deflection in mm (default 0.1)",
    "  --angular  angular deflection in radians (default 0.5)",
    "  --tree     print the parts tree as JSON (names, triangles, bbox in mm)",
  ].join("\n");
  (code === 0 ? console.log : console.error)(text);
  process.exit(code);
}

function fail(msg: string): never {
  console.error(`step2glb: ${msg}`);
  process.exit(1);
}

type Args = { tree: boolean; input: string; output?: string; linear: number; angular: number };

function parseArgs(argv: string[]): Args {
  const pos: string[] = [];
  let tree = false, linear = 0.1, angular = 0.5;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]!;
    const num = () => {
      const v = Number(argv[++i]);
      if (!(v > 0)) fail(`${a} needs a positive number`);
      return v;
    };
    if (a === "-h" || a === "--help") usage(0);
    else if (a === "--version") { console.log(VERSION); process.exit(0); }
    else if (a === "--tree") tree = true;
    else if (a === "--linear") linear = num();
    else if (a === "--angular") angular = num();
    else if (a.startsWith("--")) fail(`unknown option ${a}`);
    else pos.push(a);
  }
  if (tree ? pos.length !== 1 : pos.length !== 2) usage(2);
  return { tree, input: pos[0]!, output: pos[1], linear, angular };
}

async function readStep(path: string, linear: number, angular: number): Promise<[OcctResult, Uint8Array]> {
  const file = Bun.file(path);
  if (!(await file.exists())) fail(`no such file: ${path}`);
  const content = new Uint8Array(await file.arrayBuffer());
  const wasmBinary = new Uint8Array(await Bun.file(wasmPath).arrayBuffer());
  const occt = await occtimportjs({ wasmBinary, print: () => {}, printErr: () => {} });
  const result: OcctResult = occt.ReadStepFile(content, {
    linearUnit: "millimeter",
    linearDeflectionType: "absolute_value",
    linearDeflection: linear,
    angularDeflection: angular,
  });
  if (!result || !result.success) fail(`could not read STEP: ${path}`);
  return [result, content];
}

// ---- instance names ----------------------------------------------------------
//
// OCCT names each node after its product (the part: "C_0805_2012Metric"). The
// instance name (NEXT_ASSEMBLY_USAGE_OCCURRENCE, e.g. the reference designator
// "C14" in a KiCad board export) is dropped, so recover it from the STEP text.
// Applied only where the file's assembly structure matches OCCT's tree name for
// name, level by level; anything unexpected leaves the node without one.

const STR = "'((?:[^']|'')*)'";
const unq = (s: string) => s.replace(/''/g, "'");

function annotateInstances(root: OcctNode, content: Uint8Array) {
  const text = new TextDecoder("latin1").decode(content);
  const re = (head: string, tail: string) => new RegExp(`#(\\d+)\\s*=\\s*${head}\\s*\\(${tail}`, "g");
  const productName = new Map<string, string>();
  for (const m of text.matchAll(re("PRODUCT", `\\s*${STR}`))) productName.set(m[1]!, unq(m[2]!));
  const formation = new Map<string, string>();
  for (const m of text.matchAll(re("PRODUCT_DEFINITION_FORMATION(?:_WITH_SPECIFIED_SOURCE)?", `[^#;]*#(\\d+)`)))
    formation.set(m[1]!, m[2]!);
  const pdName = new Map<string, string>();
  const pds: string[] = [];
  for (const m of text.matchAll(re("PRODUCT_DEFINITION(?:_WITH_ASSOCIATED_DOCUMENTS)?", `\\s*${STR}\\s*,\\s*(?:${STR}|\\$)\\s*,\\s*#(\\d+)`))) {
    const prod = formation.get(m[4]!);
    if (prod !== undefined && productName.has(prod)) { pdName.set(m[1]!, productName.get(prod)!); pds.push(m[1]!); }
  }
  type Use = { name: string; child: string };
  const uses = new Map<string, Use[]>();
  const used = new Set<string>();
  for (const m of text.matchAll(re("NEXT_ASSEMBLY_USAGE_OCCURRENCE",
    `\\s*${STR}\\s*,\\s*${STR}\\s*,\\s*(?:${STR}|\\$)\\s*,\\s*#(\\d+)\\s*,\\s*#(\\d+)`))) {
    const [parent, child] = [m[5]!, m[6]!];
    if (!uses.has(parent)) uses.set(parent, []);
    uses.get(parent)!.push({ name: unq(m[3]!), child });
    used.add(child);
  }
  const walk = (node: OcctNode, kids: Use[]) => {
    if (kids.length !== node.children.length) return;
    if (!kids.every((u, i) => pdName.get(u.child) === node.children[i]!.name)) return;
    kids.forEach((u, i) => {
      const c = node.children[i]!;
      if (u.name && !u.name.startsWith("=>") && u.name !== c.name) c.instance = u.name;
      walk(c, uses.get(u.child) ?? []);
    });
  };
  walk(root, pds.filter((p) => !used.has(p)).map((p) => ({ name: "", child: p })));
}

// ---- geometry helpers ------------------------------------------------------

const triCount = (m: OcctMesh) => (m.index.array.length / 3) | 0;

function meshBox(m: OcctMesh): Box | null {
  const p = m.attributes.position.array;
  if (p.length < 3) return null;
  const min: Box["min"] = [Infinity, Infinity, Infinity];
  const max: Box["max"] = [-Infinity, -Infinity, -Infinity];
  for (let i = 0; i < p.length; i += 3)
    for (let k = 0; k < 3; k++) {
      const v = p[i + k]!;
      if (v < min[k]!) min[k] = v;
      if (v > max[k]!) max[k] = v;
    }
  return { min, max };
}

function union(a: Box | null, b: Box | null): Box | null {
  if (!a) return b;
  if (!b) return a;
  return {
    min: [Math.min(a.min[0], b.min[0]), Math.min(a.min[1], b.min[1]), Math.min(a.min[2], b.min[2])],
    max: [Math.max(a.max[0], b.max[0]), Math.max(a.max[1], b.max[1]), Math.max(a.max[2], b.max[2])],
  };
}

// Smooth vertex normals from the triangles, for meshes OCCT gave none.
function computeNormals(pos: number[], idx: number[]): Float32Array {
  const n = new Float32Array(pos.length);
  for (let t = 0; t < idx.length; t += 3) {
    const a = idx[t]! * 3, b = idx[t + 1]! * 3, c = idx[t + 2]! * 3;
    const ux = pos[b]! - pos[a]!, uy = pos[b + 1]! - pos[a + 1]!, uz = pos[b + 2]! - pos[a + 2]!;
    const vx = pos[c]! - pos[a]!, vy = pos[c + 1]! - pos[a + 1]!, vz = pos[c + 2]! - pos[a + 2]!;
    const nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
    for (const v of [a, b, c]) { n[v]! += nx; n[v + 1]! += ny; n[v + 2]! += nz; }
  }
  return normalize(n);
}

function normalize(n: Float32Array): Float32Array {
  for (let i = 0; i < n.length; i += 3) {
    const l = Math.hypot(n[i]!, n[i + 1]!, n[i + 2]!);
    if (l > 0) { n[i]! /= l; n[i + 1]! /= l; n[i + 2]! /= l; }
    else { n[i] = 0; n[i + 1] = 0; n[i + 2] = 1; }
  }
  return n;
}

// Triangle ranges grouped by colour: face colour, else mesh colour, else grey.
function colorGroups(m: OcctMesh): Map<string, { color: RGB; tris: number[] }> {
  const groups = new Map<string, { color: RGB; tris: number[] }>();
  const base = m.color ?? DEFAULT_COLOR;
  const add = (color: RGB, first: number, last: number) => {
    const key = color.map((c) => c.toFixed(4)).join(",");
    let g = groups.get(key);
    if (!g) groups.set(key, (g = { color, tris: [] }));
    for (let t = first; t <= last; t++) g.tris.push(t);
  };
  const covered = new Uint8Array(triCount(m));
  for (const f of m.brep_faces ?? []) {
    add(f.color ?? base, f.first, f.last);
    covered.fill(1, f.first, f.last + 1);
  }
  for (let t = 0; t < covered.length; t++) if (!covered[t]) add(base, t, t);
  return groups;
}

// ---- --tree ----------------------------------------------------------------

type TreeNode = {
  name: string;
  instance?: string;
  triangles: number;
  bbox: Box | null;
  meshes?: { name: string; triangles: number; color: RGB | null; bbox: Box | null }[];
  children?: TreeNode[];
};

function tree(node: OcctNode, meshes: OcctMesh[]): TreeNode {
  const ms = node.meshes.map((i) => {
    const m = meshes[i]!;
    return { name: m.name, triangles: triCount(m), color: m.color ?? null, bbox: meshBox(m) };
  });
  const kids = node.children.map((c) => tree(c, meshes));
  let triangles = 0, bbox: Box | null = null;
  for (const x of [...ms, ...kids]) { triangles += x.triangles; bbox = union(bbox, x.bbox); }
  const out: TreeNode = { name: node.name, triangles, bbox };
  if (node.instance) out.instance = node.instance;
  if (ms.length) out.meshes = ms;
  if (kids.length) out.children = kids;
  return out;
}

// ---- GLB writer ------------------------------------------------------------

type Json = Record<string, unknown>;

class Glb {
  chunks: Uint8Array[] = [];
  length = 0;
  bufferViews: Json[] = [];
  accessors: Json[] = [];
  materials: Json[] = [];
  materialIndex = new Map<string, number>();
  meshes: Json[] = [];
  nodes: Json[] = [];

  view(bytes: Uint8Array, target: number): number {
    const pad = (4 - (this.length % 4)) % 4;
    if (pad) { this.chunks.push(new Uint8Array(pad)); this.length += pad; }
    this.bufferViews.push({ buffer: 0, byteOffset: this.length, byteLength: bytes.byteLength, target });
    this.chunks.push(bytes);
    this.length += bytes.byteLength;
    return this.bufferViews.length - 1;
  }

  accessor(a: Json): number {
    this.accessors.push(a);
    return this.accessors.length - 1;
  }

  material(color: RGB): number {
    const key = color.map((c) => c.toFixed(4)).join(",");
    let i = this.materialIndex.get(key);
    if (i === undefined) {
      i = this.materials.length;
      this.materials.push({
        name: `rgb(${color.map((c) => Math.round(c * 255)).join(",")})`,
        pbrMetallicRoughness: { baseColorFactor: [...color, 1], metallicFactor: 0, roughnessFactor: 0.7 },
        doubleSided: true,
      });
      this.materialIndex.set(key, i);
    }
    return i;
  }

  mesh(m: OcctMesh): number | null {
    const pos = m.attributes.position.array;
    const idx = m.index.array;
    const count = pos.length / 3;
    if (count === 0 || idx.length === 0) return null;
    const box = meshBox(m)!;
    const posAcc = this.accessor({
      bufferView: this.view(new Uint8Array(new Float32Array(pos).buffer), 34962),
      componentType: 5126, count, type: "VEC3",
      min: box.min.map(Math.fround), max: box.max.map(Math.fround),
    });
    const nrm = m.attributes.normal?.array.length === pos.length
      ? normalize(new Float32Array(m.attributes.normal!.array))
      : computeNormals(pos, idx);
    const nrmAcc = this.accessor({
      bufferView: this.view(new Uint8Array(nrm.buffer), 34962),
      componentType: 5126, count, type: "VEC3",
    });
    const primitives: Json[] = [];
    for (const g of colorGroups(m).values()) {
      const ix = new Uint32Array(g.tris.length * 3);
      g.tris.forEach((t, k) => { ix[k * 3] = idx[t * 3]!; ix[k * 3 + 1] = idx[t * 3 + 1]!; ix[k * 3 + 2] = idx[t * 3 + 2]!; });
      primitives.push({
        attributes: { POSITION: posAcc, NORMAL: nrmAcc },
        indices: this.accessor({
          bufferView: this.view(new Uint8Array(ix.buffer), 34963),
          componentType: 5125, count: ix.length, type: "SCALAR",
        }),
        material: this.material(g.color),
        mode: 4,
      });
    }
    this.meshes.push({ name: m.name, primitives });
    return this.meshes.length - 1;
  }

  // One glTF node per STEP node; a node with several meshes gets one child per mesh.
  node(n: OcctNode, meshes: OcctMesh[], meshIds: (number | null)[]): number {
    const own = n.meshes.map((i) => ({ i, id: meshIds[i] })).filter((x) => x.id != null);
    const children = n.children.map((c) => this.node(c, meshes, meshIds));
    const out: Json = { name: n.name };
    if (n.instance) out.extras = { instance: n.instance };
    if (own.length === 1 && children.length === 0) out.mesh = own[0]!.id;
    else
      for (const { i, id } of own) {
        this.nodes.push({ name: meshes[i]!.name || n.name, mesh: id });
        children.push(this.nodes.length - 1);
      }
    if (children.length) out.children = children;
    this.nodes.push(out);
    return this.nodes.length - 1;
  }

  encode(root: number, source: string): Uint8Array {
    const json: Json = {
      asset: { version: "2.0", generator: `backplane-step2glb ${VERSION}`, extras: { unit: "mm", up: "Z", source } },
      scene: 0,
      scenes: [{ name: source, nodes: [root] }],
      nodes: this.nodes,
    };
    if (this.meshes.length) {
      Object.assign(json, {
        meshes: this.meshes, materials: this.materials, accessors: this.accessors,
        bufferViews: this.bufferViews, buffers: [{ byteLength: this.length }],
      });
    }
    let jsonBytes = new TextEncoder().encode(JSON.stringify(json));
    const jsonPad = (4 - (jsonBytes.length % 4)) % 4;
    const binPad = (4 - (this.length % 4)) % 4;
    const binLen = this.length + binPad;
    const hasBin = this.length > 0;
    const total = 12 + 8 + jsonBytes.length + jsonPad + (hasBin ? 8 + binLen : 0);
    const out = new Uint8Array(total);
    const dv = new DataView(out.buffer);
    dv.setUint32(0, 0x46546c67, true); // "glTF"
    dv.setUint32(4, 2, true);
    dv.setUint32(8, total, true);
    dv.setUint32(12, jsonBytes.length + jsonPad, true);
    dv.setUint32(16, 0x4e4f534a, true); // "JSON"
    out.set(jsonBytes, 20);
    out.fill(0x20, 20 + jsonBytes.length, 20 + jsonBytes.length + jsonPad);
    if (hasBin) {
      let o = 20 + jsonBytes.length + jsonPad;
      dv.setUint32(o, binLen, true);
      dv.setUint32(o + 4, 0x004e4942, true); // "BIN\0"
      o += 8;
      for (const c of this.chunks) { out.set(c, o); o += c.byteLength; }
    }
    return out;
  }
}

// ---- main ------------------------------------------------------------------

const args = parseArgs(process.argv.slice(2));
const t0 = performance.now();
const [result, content] = await readStep(args.input, args.linear, args.angular);
annotateInstances(result.root, content);
const source = args.input.split(/[\\/]/).pop()!;

if (args.tree) {
  const round = (_k: string, v: unknown) => (typeof v === "number" ? Math.round(v * 1e4) / 1e4 : v);
  console.log(JSON.stringify(tree(result.root, result.meshes), round));
} else {
  const glb = new Glb();
  const meshIds = result.meshes.map((m) => glb.mesh(m));
  const root = glb.node(result.root, result.meshes, meshIds);
  const bytes = glb.encode(root, source);
  await Bun.write(args.output!, bytes);
  const tris = result.meshes.reduce((s, m) => s + triCount(m), 0);
  console.error(
    `step2glb: ${source} -> ${args.output}: ${result.meshes.length} meshes, ${tris} triangles, ` +
      `${bytes.byteLength} bytes, ${Math.round(performance.now() - t0)} ms`,
  );
}
