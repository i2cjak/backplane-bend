// Exposes the hub's CBOR codec (wire.bend) as globalThis.Wire for
// test/smoke.ts: encode(JSON text) -> Uint8Array, decode(Uint8Array) -> JSON text.

import W from "./wire.bend";

function toList(u8) {
  let xs = { $: "Nil" };
  for (let i = u8.length - 1; i >= 0; i -= 1) xs = { $: "Con", head: u8[i], tail: xs };
  return xs;
}

function fromList(xs) {
  const out = [];
  for (let x = xs; x && x.$ === "Con"; x = x.tail) out.push(x.head);
  return new Uint8Array(out);
}

globalThis.Wire = {
  encode: (text) => fromList(W.encode(text)),
  decode: (u8) => W.decode(toList(u8)),
};
