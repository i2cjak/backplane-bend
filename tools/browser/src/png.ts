// A small PNG decoder: 8-bit, non-interlaced images of every colour type
// (what Chromium emits), inflated with zlib and un-filtered here. Output is
// packed RGB, 3 bytes per pixel, row after row; alpha is composited over
// white.

import { inflateSync } from "node:zlib";

export type Rgb = { width: number; height: number; rgb: Uint8Array };

const SIGNATURE = [137, 80, 78, 71, 13, 10, 26, 10];

function paeth(a: number, b: number, c: number): number {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
}

export function decodePng(png: Uint8Array): Rgb {
  for (let i = 0; i < 8; i++) if (png[i] !== SIGNATURE[i]) throw new Error("not a PNG");
  const view = new DataView(png.buffer, png.byteOffset, png.byteLength);
  let width = 0, height = 0, depth = 0, ctype = 0, interlace = 0;
  let palette: Uint8Array | null = null;
  const idat: Uint8Array[] = [];
  let pos = 8;
  while (pos + 8 <= png.length) {
    const len = view.getUint32(pos);
    const type = String.fromCharCode(png[pos + 4], png[pos + 5], png[pos + 6], png[pos + 7]);
    const data = png.subarray(pos + 8, pos + 8 + len);
    if (type === "IHDR") {
      width = view.getUint32(pos + 8);
      height = view.getUint32(pos + 12);
      depth = data[8];
      ctype = data[9];
      interlace = data[12];
    } else if (type === "PLTE") palette = data;
    else if (type === "IDAT") idat.push(data);
    else if (type === "IEND") break;
    pos += 12 + len;
  }
  if (depth !== 8) throw new Error(`PNG bit depth ${depth} unsupported`);
  if (interlace !== 0) throw new Error("interlaced PNG unsupported");
  const channels = ({ 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 } as Record<number, number>)[ctype];
  if (!channels) throw new Error(`PNG colour type ${ctype} unsupported`);
  const raw = inflateSync(idat.length === 1 ? idat[0] : Buffer.concat(idat));
  const stride = width * channels;
  if (raw.length < (stride + 1) * height) throw new Error("PNG data truncated");

  // un-filter in place into `cur`, one row at a time
  const out = new Uint8Array(width * height * 3);
  let prev = new Uint8Array(stride);
  let cur = new Uint8Array(stride);
  const bpp = channels;
  for (let y = 0; y < height; y++) {
    const base = y * (stride + 1);
    const filter = raw[base];
    const line = raw.subarray(base + 1, base + 1 + stride);
    switch (filter) {
      case 0:
        cur.set(line);
        break;
      case 1:
        for (let i = 0; i < stride; i++) cur[i] = (line[i] + (i >= bpp ? cur[i - bpp] : 0)) & 255;
        break;
      case 2:
        for (let i = 0; i < stride; i++) cur[i] = (line[i] + prev[i]) & 255;
        break;
      case 3:
        for (let i = 0; i < stride; i++) cur[i] = (line[i] + (((i >= bpp ? cur[i - bpp] : 0) + prev[i]) >> 1)) & 255;
        break;
      case 4:
        for (let i = 0; i < stride; i++) {
          const a = i >= bpp ? cur[i - bpp] : 0;
          const c = i >= bpp ? prev[i - bpp] : 0;
          cur[i] = (line[i] + paeth(a, prev[i], c)) & 255;
        }
        break;
      default:
        throw new Error(`PNG filter ${filter} unknown`);
    }
    let o = y * width * 3;
    if (ctype === 2) {
      out.set(cur, o);
    } else if (ctype === 6) {
      for (let i = 0; i < stride; i += 4) {
        const a = cur[i + 3];
        if (a === 255) {
          out[o++] = cur[i]; out[o++] = cur[i + 1]; out[o++] = cur[i + 2];
        } else {
          const w = 255 * (255 - a);
          out[o++] = ((cur[i] * a + w) / 255) | 0;
          out[o++] = ((cur[i + 1] * a + w) / 255) | 0;
          out[o++] = ((cur[i + 2] * a + w) / 255) | 0;
        }
      }
    } else if (ctype === 0 || ctype === 4) {
      for (let i = 0; i < stride; i += channels) {
        out[o++] = cur[i]; out[o++] = cur[i]; out[o++] = cur[i];
      }
    } else {
      if (!palette) throw new Error("PNG palette missing");
      for (let i = 0; i < stride; i++) {
        const p = cur[i] * 3;
        out[o++] = palette[p]; out[o++] = palette[p + 1]; out[o++] = palette[p + 2];
      }
    }
    const t = prev; prev = cur; cur = t;
  }
  return { width, height, rgb: out };
}
