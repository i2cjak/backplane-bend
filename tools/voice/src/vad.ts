// Segmenting for live dictation: a small energy VAD over 16-bit mono PCM.
// gpt-live-transcribe has no server turn detection, so the client commits.
// Before any speech, audio is held locally as pre-roll (never sent), so a
// silent stretch sends nothing and commits nothing.

export const RATE = 24000;
export const BYTES_PER_MS = (RATE * 2) / 1000; // 48

export type Action = { append: Uint8Array } | { commit: true } | { clear: true };

export type VadOpts = {
  quietMs: number; // quiet after speech that ends a segment
  maxMs: number; // longest segment
  prerollMs: number; // audio kept from before speech starts
  minMs: number; // shortest segment worth committing
  minSpeechMs: number; // less speech than this is a click: cleared, not committed
  level: number; // RMS floor for speech (int16 units)
  ratio: number; // speech is also above ratio x the noise floor
};

export const defaults: VadOpts = {
  quietMs: 700,
  maxMs: 15000,
  prerollMs: 300,
  minMs: 100,
  minSpeechMs: 200,
  level: 500,
  ratio: 3,
};

export function rms(pcm: Uint8Array): number {
  const n = pcm.length >> 1;
  if (n === 0) return 0;
  const v = new DataView(pcm.buffer, pcm.byteOffset, n * 2);
  let s = 0;
  for (let i = 0; i < n; i++) {
    const x = v.getInt16(i * 2, true);
    s += x * x;
  }
  return Math.sqrt(s / n);
}

function concat(parts: Uint8Array[]): Uint8Array {
  let len = 0;
  for (const p of parts) len += p.length;
  const out = new Uint8Array(len);
  let o = 0;
  for (const p of parts) {
    out.set(p, o);
    o += p.length;
  }
  return out;
}

export class Segmenter {
  o: VadOpts;
  floor = 150;
  active = false;
  preroll: Uint8Array[] = [];
  prerollMs = 0;
  sentMs = 0;
  quiet = 0;
  speech = 0;
  lastRms = 0; // the last chunk's RMS
  lastLoud = false; // whether it counted as speech

  constructor(o: Partial<VadOpts> = {}) {
    this.o = { ...defaults, ...o };
  }

  // One chunk of whole samples in; what to send out.
  push(chunk: Uint8Array): Action[] {
    const ms = chunk.length / BYTES_PER_MS;
    const r = rms(chunk);
    const loud = r > Math.max(this.o.level, this.floor * this.o.ratio);
    this.lastRms = r;
    this.lastLoud = loud;
    if (!loud) this.floor = this.floor * 0.95 + r * 0.05;
    if (!this.active) {
      if (!loud) {
        this.preroll.push(chunk);
        this.prerollMs += ms;
        while (this.preroll.length > 1 && this.prerollMs - this.preroll[0].length / BYTES_PER_MS >= this.o.prerollMs) {
          this.prerollMs -= this.preroll.shift()!.length / BYTES_PER_MS;
        }
        return [];
      }
      const a = concat([...this.preroll, chunk]);
      this.active = true;
      this.sentMs = this.prerollMs + ms;
      this.preroll = [];
      this.prerollMs = 0;
      this.quiet = 0;
      this.speech = ms;
      return [{ append: a }];
    }
    this.sentMs += ms;
    if (loud) {
      this.quiet = 0;
      this.speech += ms;
    } else this.quiet += ms;
    const out: Action[] = [{ append: chunk }];
    if (this.quiet >= this.o.quietMs || this.sentMs >= this.o.maxMs) out.push(this.end());
    return out;
  }

  // At stop: commit what's buffered, if it is worth it.
  flush(): Action[] {
    if (!this.active) return [];
    if (this.sentMs < this.o.minMs) {
      this.reset();
      return [{ clear: true }];
    }
    return [this.end()];
  }

  private end(): Action {
    const a: Action = this.speech >= this.o.minSpeechMs ? { commit: true } : { clear: true };
    this.reset();
    return a;
  }

  private reset() {
    this.active = false;
    this.sentMs = 0;
    this.quiet = 0;
    this.speech = 0;
  }
}

// Regroups a byte stream into chunks of `size` bytes (the last may be short
// but always holds whole samples).
export class Rechunker {
  buf = new Uint8Array(0);
  constructor(public size: number) {}
  push(b: Uint8Array): Uint8Array[] {
    const all = this.buf.length ? concat([this.buf, b]) : b;
    const out: Uint8Array[] = [];
    let o = 0;
    while (all.length - o >= this.size) {
      out.push(all.slice(o, o + this.size));
      o += this.size;
    }
    this.buf = all.slice(o);
    return out;
  }
  rest(): Uint8Array[] {
    const n = this.buf.length & ~1;
    const r = n ? [this.buf.slice(0, n)] : [];
    this.buf = new Uint8Array(0);
    return r;
  }
}
