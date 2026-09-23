// check-glb: structural check of a GLB written by step2glb.
//   bun check-glb.ts FILE.glb...
// Parses the header and chunks, checks every bufferView/accessor is in bounds,
// every index is below its POSITION count, normals are unit length, and prints
// one line per file: nodes, named nodes, meshes, materials, triangles.

function check(path: string, buf: Uint8Array): string {
  const dv = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
  const need = (c: boolean, msg: string) => { if (!c) throw new Error(msg); };
  need(dv.getUint32(0, true) === 0x46546c67, "bad magic");
  need(dv.getUint32(4, true) === 2, "not glTF 2");
  need(dv.getUint32(8, true) === buf.byteLength, "length mismatch");
  const jsonLen = dv.getUint32(12, true);
  need(dv.getUint32(16, true) === 0x4e4f534a, "first chunk not JSON");
  need(jsonLen % 4 === 0, "JSON chunk not 4-aligned");
  const gltf = JSON.parse(new TextDecoder().decode(buf.subarray(20, 20 + jsonLen)));
  let bin: Uint8Array = new Uint8Array(0);
  const binAt = 20 + jsonLen;
  if (binAt < buf.byteLength) {
    need(dv.getUint32(binAt + 4, true) === 0x004e4942, "second chunk not BIN");
    const binLen = dv.getUint32(binAt, true);
    bin = buf.subarray(binAt + 8, binAt + 8 + binLen);
    need(bin.byteLength === binLen && gltf.buffers[0].byteLength <= binLen, "BIN too short");
  }
  const views = gltf.bufferViews ?? [];
  for (const v of views) need(v.byteOffset % 4 === 0 && v.byteOffset + v.byteLength <= bin.byteLength, "view out of bounds");
  const size: Record<number, number> = { 5126: 4, 5125: 4 };
  const comps: Record<string, number> = { SCALAR: 1, VEC3: 3 };
  const acc = (i: number) => {
    const a = gltf.accessors[i];
    const v = views[a.bufferView];
    need(a.count * comps[a.type]! * size[a.componentType]! <= v.byteLength, "accessor overruns view");
    const off = bin.byteOffset + v.byteOffset;
    return { a, data: a.componentType === 5125
      ? new Uint32Array(bin.buffer, off, a.count)
      : new Float32Array(bin.buffer, off, a.count * comps[a.type]!) };
  };
  let triangles = 0;
  for (const m of gltf.meshes ?? []) for (const p of m.primitives) {
    need(p.mode === undefined || p.mode === 4, "not triangles");
    const pos = acc(p.attributes.POSITION), nrm = acc(p.attributes.NORMAL), idx = acc(p.indices);
    need(pos.a.min && pos.a.max, "POSITION without min/max");
    need(nrm.a.count === pos.a.count, "NORMAL count != POSITION count");
    need(idx.a.componentType === 5125 && idx.a.count % 3 === 0, "indices not u32 triangles");
    for (const i of idx.data as Uint32Array) need(i < pos.a.count, "index out of range");
    const n = nrm.data as Float32Array;
    for (let k = 0; k < n.length; k += 3) need(Math.abs(Math.hypot(n[k]!, n[k + 1]!, n[k + 2]!) - 1) < 1e-3, "normal not unit");
    need(gltf.materials[p.material]?.pbrMetallicRoughness?.baseColorFactor?.length === 4, "no baseColorFactor");
    triangles += idx.a.count / 3;
  }
  const nodes = gltf.nodes ?? [];
  const named = nodes.filter((n: { name?: string }) => n.name).length;
  return `${path}: ok, ${nodes.length} nodes (${named} named), ${(gltf.meshes ?? []).length} meshes, ` +
    `${(gltf.materials ?? []).length} materials, ${triangles} triangles, ${buf.byteLength} bytes`;
}

let bad = 0;
for (const f of process.argv.slice(2)) {
  try { console.log(check(f, new Uint8Array(await Bun.file(f).arrayBuffer()))); }
  catch (e) { console.error(`${f}: FAIL ${(e as Error).message}`); bad++; }
}
process.exit(bad ? 1 : 0);
