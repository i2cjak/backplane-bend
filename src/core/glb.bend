import Base
import ./json.bend as J
import ./utf8.bend as U

# Binary glTF (GLB) to world-space triangles, for the 3D board viewer.
# A GLB is a 12-byte header, a JSON chunk and a BIN chunk. The BIN chunk
# becomes a balanced tree of little-endian words, so an accessor's bytes
# are one range walk (log n + k), not a list scan. Scenes lead to nodes
# (matrix or TRS, children), nodes to meshes, meshes to primitives (mode 4
# only), primitives to POSITION (float32 vec3) and indices (u8/u16/u32).
# A primitive's colour is its material's baseColorFactor.

# Colours are 0xTTRRGGBB: TT is transparency (0 = opaque, 255 = clear), so
# an opaque colour is the plain 0xRRGGBB the rest of the app uses.
type Tri3 is Data:
  Tri3{ax: F32, ay: F32, az: F32, bx: F32, by: F32, bz: F32, cx: F32, cy: F32, cz: F32, color: U32}

# a named group of triangles (a KiCad footprint's model, the board, ...)
type Part is Data:
  Part{name: String, tris: List<&2, Tri3>}

type Mesh is Data:
  Mesh{parts: List<&2, Part>}

type V3 is Data:
  V3{x: F32, y: F32, z: F32}

# an affine transform, row-major: [a b c d; e f g h; i j k l]
type M4 is Data:
  M4{a: F32, b: F32, c: F32, d: F32, e: F32, f: F32, g: F32, h: F32, i: F32, j: F32, k: F32, l: F32}

# a complete binary tree of values, indexed by the bits of the index
type Tab<-A: Data> is Data:
  TNil{}
  TLeaf{x: A}
  TNode{lo: Tab<A>, hi: Tab<A>}

# a table of JSON values (nodes, meshes, accessors, ...) and its depth
type Tbl is Data:
  Tbl{d: Nat, t: Tab<J.Json>}

# the BIN chunk as words, and the tree's depth
type Bin is Data:
  Bin{d: Nat, t: Tab<U32>}

# where an accessor's elements are: byte start, element count, stride,
# component type and the byte length that covers all elements
type Acc is Data:
  Acc{start: U32, count: U32, stride: U32, ctype: U32, len: U32}

type Gltf is Data:
  Gltf{nodes: Tbl, meshes: Tbl, accs: Tbl, views: Tbl, mats: Tbl, bin: Bin}

# a node waiting to be visited: its index, its parent's world transform,
# and the part name it inherits
type Work is Data:
  Work{idx: U32, m: M4, name: String}

# a mesh to decode: its part name, world transform and primitives
type Job is Data:
  Job{name: String, m: M4, prims: List<&2, J.Json>}

# Bytes
# -----

def Bytes.drop(n: Nat, xs: List<&2, U32>) -> List<&2, U32>:
  match n xs:
    case 0n _:
      xs
    case 1n+p _ <> t:
      Bytes.drop(p, t)
    case _ Nil{}:
      Nil{}

def Bytes.take(n: Nat, xs: List<&2, U32>) -> List<&2, U32>:
  match n xs:
    case 0n _:
      Nil{}
    case 1n+p x <> t:
      x <> Bytes.take(p, t)
    case _ Nil{}:
      Nil{}

def Bytes.word(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  U32.or(U32.or(a, U32.shln(b, 8n)), U32.or(U32.shln(c, 16n), U32.shln(d, 24n)))

# the little-endian u32 at the head
def Bytes.u32(xs: List<&2, U32>) -> U32:
  match xs:
    case a <> b <> c <> d <> _:
      Bytes.word(a, b, c, d)
    case _:
      0

def Bytes.u16(xs: List<&2, U32>) -> U32:
  match xs:
    case a <> b <> _:
      U32.or(a, U32.shln(b, 8n))
    case _:
      0

def Bytes.u8(xs: List<&2, U32>) -> U32:
  match xs:
    case a <> _:
      a
    case _:
      0

def Words.bytes(ws: List<&2, U32>) -> List<&2, U32>:
  match ws:
    case Nil{}:
      Nil{}
    case +w <> t:
      U32.and(w, 255) <> U32.and(U32.shrn(w, 8n), 255) <> U32.and(U32.shrn(w, 16n), 255) <> U32.shrn(w, 24n) <> Words.bytes(t)

# the float whose IEEE 754 bits these are
def Glb.f32(u: U32) -> F32:
  match u:
    case U32{w}:
      F32{w}

# Tables
# ------

# the smallest d with 2^d >= n (at least 1)
def Tab.depth(+n: U32) -> Nat:
  1n+U32.log2((U32.max(n, 2) - 1 : U32))

def Tab.leaves(-A: Data, xs: List<&2, A>) -> List<&2, Tab<A>>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      TLeaf{x} <> Tab.leaves(A, t)

def Tab.pairs(-A: Data, ts: List<&2, Tab<A>>) -> List<&2, Tab<A>>:
  match ts:
    case a <> b <> t:
      TNode{a, b} <> Tab.pairs(A, t)
    case a <> Nil{}:
      [TNode{a, TNil{}}]
    case Nil{}:
      Nil{}

def Tab.up(-A: Data, d: Nat, ts: List<&2, Tab<A>>) -> Tab<A>:
  match d ts:
    case 0n t <> _:
      t
    case 0n Nil{}:
      TNil{}
    case 1n+p _:
      Tab.up(A, p, Tab.pairs(A, ts))

# the first 2^d values as a tree of depth d, padded with TNil
def Tab.of(-A: Data, +d: Nat, xs: List<&2, A>) -> Tab<A>:
  Tab.up(A, d, Tab.leaves(A, xs))

def Tab.bit(+i: U32, +k: Nat) -> Bool:
  U32.is_ne(U32.and(U32.shrn(i, k), 1), 0)

# hi is bit d-1 of i: which child holds the index. The walk only matches
# and recurses (never returns a subtree), so a shared tree is borrowed.
def Tab.go(-A: Data, d: Nat, t: Tab<A>, hi: Bool, +i: U32, dv: A) -> A:
  match d t hi:
    case _ TLeaf{x} _:
      x
    case 1n+p TNode{l, _} False{}:
      +q = p
      Tab.go(A, q, l, Tab.bit(i, Nat.sub(q, 1n)), i, dv)
    case 1n+p TNode{_, r} True{}:
      +q = p
      Tab.go(A, q, r, Tab.bit(i, Nat.sub(q, 1n)), i, dv)
    case _ _ _:
      dv

# the value at index i of a tree of depth d, or dv
def Tab.at(-A: Data, +d: Nat, t: Tab<A>, +i: U32, dv: A) -> A:
  Tab.go(A, d, t, Tab.bit(i, Nat.sub(d, 1n)), i, dv)

def Tbl.of(+xs: List<&2, J.Json>) -> Tbl:
  +d = Tab.depth(U32.from_nat(List.length(&2, J.Json, xs)))
  Tbl{d, Tab.of(J.Json, d, xs)}

def Tbl.at(tb: Tbl, +i: U32) -> J.Json:
  match tb:
    case Tbl{d, t}:
      Tab.at(J.Json, d, t, i, J.Null{})

# n words from little-endian bytes, as tree leaves
def Bin.leaves(n: Nat, xs: List<&2, U32>) -> List<&2, Tab<U32>>:
  match n xs:
    case 1n+p a <> b <> c <> d <> t:
      TLeaf{Bytes.word(a, b, c, d)} <> Bin.leaves(p, t)
    case _ _:
      Nil{}

# the BIN chunk (len bytes at the head of xs)
def Bin.of(+len: U32, xs: List<&2, U32>) -> Bin:
  +d = Tab.depth((len / 4 : U32))
  Bin{d, Tab.up(U32, d, Bin.leaves(U32.to_nat((len / 4 : U32)), xs))}

# does [base, base + 2^d) meet [lo, hi)?
def Words.hit(+base: U32, +d: Nat, +lo: U32, +hi: U32) -> Bool:
  Bool.and(U32.is_lt(base, hi), U32.is_gt((base + U32.shln(1, d) : U32), lo))

# the words with index in [lo, hi), in order, onto acc
def Words.range(d: Nat, t: Tab<U32>, hit: Bool, +base: U32, +lo: U32, +hi: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match d t hit:
    case _ _ False{}:
      acc
    case _ TLeaf{w} True{}:
      w <> acc
    case 1n+p TNode{l, r} True{}:
      +q = p
      +mid = (base + U32.shln(1, q) : U32)
      Words.range(q, l, Words.hit(base, q, lo, hi), base, lo, hi, Words.range(q, r, Words.hit(mid, q, lo, hi), mid, lo, hi, acc))
    case _ _ _:
      acc

# len bytes of the BIN chunk from byte start
def Bin.slice(b: Bin, +start: U32, +len: U32) -> List<&2, U32>:
  match b:
    case Bin{+d, t}:
      +lo = (start / 4 : U32)
      +hi = ((start + len + 3 : U32) / 4 : U32)
      Bytes.take(U32.to_nat(len), Bytes.drop(U32.to_nat((start % 4 : U32)), Words.bytes(Words.range(d, t, Words.hit(0, d, lo, hi), 0, lo, hi, Nil{}))))

# the words covering len bytes from an aligned byte start
def Bin.words(b: Bin, +start: U32, +len: U32) -> List<&2, U32>:
  match b:
    case Bin{+d, t}:
      +lo = (start / 4 : U32)
      +hi = ((start + len + 3 : U32) / 4 : U32)
      Words.range(d, t, Words.hit(0, d, lo, hi), 0, lo, hi, Nil{})

# JSON helpers
# ------------

def Glb.num(j: J.Json) -> F32:
  match j:
    case J.Num{r}:
      Maybe.default(&2, F32, F32.read(r), 0.0)
    case _:
      0.0

def Glb.nums.go(xs: List<&2, J.Json>) -> List<&2, F32>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      Glb.num(x) <> Glb.nums.go(t)

# the numbers of an array field, or []
def Glb.nums(o: J.Json, +key: String) -> List<&2, F32>:
  Glb.nums.go(J.Json.elems(J.Json.get_obj(o, key)))

def Glb.u32s.go(xs: List<&2, J.Json>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case J.Num{r} <> t:
      Maybe.default(&2, U32, U32.read(r), 0) <> Glb.u32s.go(t)
    case _ <> t:
      Glb.u32s.go(t)

def Glb.u32s(o: J.Json, +key: String) -> List<&2, U32>:
  Glb.u32s.go(J.Json.elems(J.Json.get_obj(o, key)))

def Glb.nth(xs: List<&2, F32>, n: Nat, dv: F32) -> F32:
  Maybe.default(&2, F32, List.get(&2, F32, xs, n), dv)

def Glb.has(m: Maybe<&2, J.Json>) -> Bool:
  match m:
    case Some{_}:
      True{}
    case None{}:
      False{}

# Transforms
# ----------

def M4.id() -> M4:
  M4{1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0}

def M4.dot(+a: F32, +b: F32, +c: F32, +x: F32, +y: F32, +z: F32) -> F32:
  F32.add(F32.add(F32.mul(a, x), F32.mul(b, y)), F32.mul(c, z))

# p then q: the transform applying q first, then p
def M4.mul(p: M4, q: M4) -> M4:
  match p q:
    case M4{+a, +b, +c, +d, +e, +f, +g, +h, +i, +j, +k, +l} M4{+A, +B, +C, +D, +E, +F, +G, +H, +I, +J, +K, +L}:
      M4{M4.dot(a, b, c, A, E, I), M4.dot(a, b, c, B, F, J), M4.dot(a, b, c, C, G, K), F32.add(M4.dot(a, b, c, D, H, L), d),
        M4.dot(e, f, g, A, E, I), M4.dot(e, f, g, B, F, J), M4.dot(e, f, g, C, G, K), F32.add(M4.dot(e, f, g, D, H, L), h),
        M4.dot(i, j, k, A, E, I), M4.dot(i, j, k, B, F, J), M4.dot(i, j, k, C, G, K), F32.add(M4.dot(i, j, k, D, H, L), l)}

def M4.app(m: M4, +x: F32, +y: F32, +z: F32) -> V3:
  match m:
    case M4{a, b, c, d, e, f, g, h, i, j, k, l}:
      V3{F32.add(M4.dot(a, b, c, x, y, z), d), F32.add(M4.dot(e, f, g, x, y, z), h), F32.add(M4.dot(i, j, k, x, y, z), l)}

# a glTF matrix is column-major
def M4.cols(+m: List<&2, F32>) -> M4:
  M4{Glb.nth(m, 0n, 1.0), Glb.nth(m, 4n, 0.0), Glb.nth(m, 8n, 0.0), Glb.nth(m, 12n, 0.0),
    Glb.nth(m, 1n, 0.0), Glb.nth(m, 5n, 1.0), Glb.nth(m, 9n, 0.0), Glb.nth(m, 13n, 0.0),
    Glb.nth(m, 2n, 0.0), Glb.nth(m, 6n, 0.0), Glb.nth(m, 10n, 1.0), Glb.nth(m, 14n, 0.0)}

# translation * rotation (unit quaternion x y z w) * scale
def M4.trs.k(+tx: F32, +ty: F32, +tz: F32, +x: F32, +y: F32, +z: F32, +w: F32, +sx: F32, +sy: F32, +sz: F32) -> M4:
  M4{F32.mul(F32.sub(1.0, F32.mul(2.0, F32.add(F32.mul(y, y), F32.mul(z, z)))), sx),
    F32.mul(F32.mul(2.0, F32.sub(F32.mul(x, y), F32.mul(z, w))), sy),
    F32.mul(F32.mul(2.0, F32.add(F32.mul(x, z), F32.mul(y, w))), sz), tx,
    F32.mul(F32.mul(2.0, F32.add(F32.mul(x, y), F32.mul(z, w))), sx),
    F32.mul(F32.sub(1.0, F32.mul(2.0, F32.add(F32.mul(x, x), F32.mul(z, z)))), sy),
    F32.mul(F32.mul(2.0, F32.sub(F32.mul(y, z), F32.mul(x, w))), sz), ty,
    F32.mul(F32.mul(2.0, F32.sub(F32.mul(x, z), F32.mul(y, w))), sx),
    F32.mul(F32.mul(2.0, F32.add(F32.mul(y, z), F32.mul(x, w))), sy),
    F32.mul(F32.sub(1.0, F32.mul(2.0, F32.add(F32.mul(x, x), F32.mul(y, y)))), sz), tz}

def M4.trs(+t: List<&2, F32>, +r: List<&2, F32>, +s: List<&2, F32>) -> M4:
  M4.trs.k(Glb.nth(t, 0n, 0.0), Glb.nth(t, 1n, 0.0), Glb.nth(t, 2n, 0.0),
    Glb.nth(r, 0n, 0.0), Glb.nth(r, 1n, 0.0), Glb.nth(r, 2n, 0.0), Glb.nth(r, 3n, 1.0),
    Glb.nth(s, 0n, 1.0), Glb.nth(s, 1n, 1.0), Glb.nth(s, 2n, 1.0))

def M4.pick(has: Bool, +n: J.Json) -> M4:
  match has:
    case True{}:
      M4.cols(Glb.nums(n, "matrix"))
    case False{}:
      M4.trs(Glb.nums(n, "translation"), Glb.nums(n, "rotation"), Glb.nums(n, "scale"))

# a node's local transform
def M4.of_node(+n: J.Json) -> M4:
  M4.pick(Glb.has(J.Json.get(n, "matrix")), n)

# Accessors
# ---------

def Acc.csize.k(b1: Bool, b2: Bool) -> U32:
  match b1 b2:
    case True{} _:
      1
    case _ True{}:
      2
    case _ _:
      4

def Acc.csize(+ct: U32) -> U32:
  Acc.csize.k(U32.is_le(ct, 5121), U32.is_le(ct, 5123))

def Acc.ncomp.k(s: Bool, v2: Bool, v3: Bool, v4: Bool) -> U32:
  match s v2 v3 v4:
    case True{} _ _ _:
      1
    case _ True{} _ _:
      2
    case _ _ True{} _:
      3
    case _ _ _ True{}:
      4
    case _ _ _ _:
      16

def Acc.ncomp(+t: String) -> U32:
  Acc.ncomp.k(String.eq(t, "SCALAR"), String.eq(t, "VEC2"), String.eq(t, "VEC3"), String.eq(t, "VEC4"))

def U32.pick(c: Bool, +a: U32, +b: U32) -> U32:
  match c:
    case True{}:
      a
    case False{}:
      b

def Acc.mk(+start: U32, +count: U32, +vstride: U32, +ct: U32, +esize: U32) -> Acc:
  +stride = U32.pick(U32.is_eq(vstride, 0), esize, vstride)
  Acc{start, count, stride, ct, U32.pick(U32.is_eq(count, 0), 0, ((stride * (count - 1 : U32) : U32) + esize : U32))}

def Acc.of(+a: J.Json, +views: Tbl) -> Acc:
  +v = Tbl.at(views, J.Json.get_u32(a, "bufferView", 0))
  +ct = J.Json.get_u32(a, "componentType", 5126)
  Acc.mk((J.Json.get_u32(v, "byteOffset", 0) + J.Json.get_u32(a, "byteOffset", 0) : U32), J.Json.get_u32(a, "count", 0),
    J.Json.get_u32(v, "byteStride", 0), ct, (Acc.csize(ct) * Acc.ncomp(J.Json.get_str(a, "type", "SCALAR")) : U32))

# the bytes an accessor covers
def Acc.bytes(a: Acc, +b: Bin) -> List<&2, U32>:
  match a:
    case Acc{start, _, _, _, len}:
      Bin.slice(b, start, len)

# n float32 vec3s every `skip` + 12 bytes, moved by m
def Pos.go(n: Nat, +bs: List<&2, U32>, +skip: Nat, +m: M4) -> List<&2, V3>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      M4.app(m, Glb.f32(Bytes.u32(bs)), Glb.f32(Bytes.u32(Bytes.drop(4n, bs))), Glb.f32(Bytes.u32(Bytes.drop(8n, bs))))
        <> Pos.go(p, Bytes.drop(Nat.add(12n, skip), bs), skip, m)

# the same from aligned words: n vec3s every `skip` + 3 words
def Pos.words(n: Nat, ws: List<&2, U32>, +skip: Nat, +m: M4) -> List<&2, V3>:
  match n ws:
    case 1n+p x <> y <> z <> t:
      M4.app(m, Glb.f32(x), Glb.f32(y), Glb.f32(z)) <> Pos.words(p, Bytes.drop(skip, t), skip, m)
    case _ _:
      Nil{}

def Pos.pick(aligned: Bool, +a: Acc, +b: Bin, +m: M4) -> List<&2, V3>:
  match aligned a:
    case True{} Acc{+start, count, +stride, _, +len}:
      Pos.words(U32.to_nat(count), Bin.words(b, start, len), U32.to_nat(((stride - 12 : U32) / 4 : U32)), m)
    case False{} Acc{_, count, stride, _, _}:
      Pos.go(U32.to_nat(count), Acc.bytes(a, b), U32.to_nat((stride - 12 : U32)), m)

def Acc.aligned(a: Acc) -> Bool:
  match a:
    case Acc{+start, _, +stride, _, _}:
      Bool.and(U32.is_eq((start % 4 : U32), 0), U32.is_eq((stride % 4 : U32), 0))

# an accessor's positions in world space
def Pos.of(+a: Acc, +b: Bin, +m: M4) -> List<&2, V3>:
  Pos.pick(Acc.aligned(a), a, b, m)

def Idx.one(one: Bool, two: Bool, +bs: List<&2, U32>) -> U32:
  match one two:
    case True{} _:
      Bytes.u8(bs)
    case _ True{}:
      Bytes.u16(bs)
    case _ _:
      Bytes.u32(bs)

def Idx.go(n: Nat, +bs: List<&2, U32>, +size: U32, +stride: Nat) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Idx.one(U32.is_eq(size, 1), U32.is_eq(size, 2), bs) <> Idx.go(p, Bytes.drop(stride, bs), size, stride)

# little-endian halves of words
def Words.halves(ws: List<&2, U32>) -> List<&2, U32>:
  match ws:
    case Nil{}:
      Nil{}
    case +w <> t:
      U32.and(w, 65535) <> U32.shrn(w, 16n) <> Words.halves(t)

# tightly packed u16 or u32 indices at an aligned start read as words
def Idx.fast(two: Bool, four: Bool, +a: Acc, +b: Bin) -> List<&2, U32>:
  match two four a:
    case True{} _ Acc{+start, count, _, _, +len}:
      Bytes.take(U32.to_nat(count), Words.halves(Bin.words(b, start, len)))
    case _ True{} Acc{+start, count, _, _, +len}:
      Bytes.take(U32.to_nat(count), Bin.words(b, start, len))
    case _ _ Acc{_, count, stride, ct, _}:
      Idx.go(U32.to_nat(count), Acc.bytes(a, b), Acc.csize(ct), U32.to_nat(stride))

def Idx.kind(a: Acc) -> U32:
  match a:
    case Acc{+start, _, +stride, ct, _}:
      U32.pick(U32.is_eq((start % 4 : U32), 0), U32.pick(U32.is_eq(stride, Acc.csize(ct)), stride, 0), 0)

# an accessor's indices
def Idx.of(+a: Acc, +b: Bin) -> List<&2, U32>:
  +k = Idx.kind(a)
  Idx.fast(U32.is_eq(k, 2), U32.is_eq(k, 4), a, b)

# Materials
# ---------

def Glb.chan(+f: F32) -> U32:
  F32.to_u32(F32.add(F32.mul(F32.clamp(f, 0.0, 1.0), 255.0), 0.5))

def Glb.rgb(+f: List<&2, F32>) -> U32:
  U32.or(U32.shln(Glb.chan(Glb.nth(f, 0n, 1.0)), 16n), U32.or(U32.shln(Glb.chan(Glb.nth(f, 1n, 1.0)), 8n), Glb.chan(Glb.nth(f, 2n, 1.0))))

def Glb.clear(blend: Bool, +f: List<&2, F32>) -> U32:
  match blend:
    case True{}:
      U32.shln((255 - Glb.chan(Glb.nth(f, 3n, 1.0)) : U32), 24n)
    case False{}:
      0

def Glb.paint(+m: J.Json, +f: List<&2, F32>) -> U32:
  U32.or(Glb.rgb(f), Glb.clear(String.eq(J.Json.get_str(m, "alphaMode", "OPAQUE"), "BLEND"), f))

# a material's colour (untextured: the base colour factor)
def Glb.color(+m: J.Json) -> U32:
  Glb.paint(m, Glb.nums(J.Json.get_obj(m, "pbrMetallicRoughness"), "baseColorFactor"))

# Triangles
# ---------

def Tri.mk(a: V3, b: V3, c: V3, +col: U32) -> Tri3:
  match a b c:
    case V3{ax, ay, az} V3{bx, by, bz} V3{cx, cy, cz}:
      Tri3{ax, ay, az, bx, by, bz, cx, cy, cz, col}

def Tri.idx(ix: List<&2, U32>, +vs: Tab<V3>, +d: Nat, +col: U32, acc: List<&2, Tri3>) -> List<&2, Tri3>:
  match ix:
    case a <> b <> c <> t:
      +o = {V3{0.0, 0.0, 0.0} : V3}
      Tri.mk(Tab.at(V3, d, vs, a, o), Tab.at(V3, d, vs, b, o), Tab.at(V3, d, vs, c, o), col) <> Tri.idx(t, vs, d, col, acc)
    case _:
      acc

def Tri.seq(vs: List<&2, V3>, +col: U32, acc: List<&2, Tri3>) -> List<&2, Tri3>:
  match vs:
    case a <> b <> c <> t:
      Tri.mk(a, b, c, col) <> Tri.seq(t, col, acc)
    case _:
      acc

def Tri.indexed(+vs: List<&2, V3>, +ix: List<&2, U32>, +col: U32, acc: List<&2, Tri3>) -> List<&2, Tri3>:
  +d = Tab.depth(U32.from_nat(List.length(&2, V3, vs)))
  Tri.idx(ix, Tab.of(V3, d, vs), d, col, acc)

def Prim.go(idx: Maybe<&2, J.Json>, +vs: List<&2, V3>, +g: Gltf, +col: U32, acc: List<&2, Tri3>) -> List<&2, Tri3>:
  match idx g:
    case Some{J.Num{r}} Gltf{_, _, accs, views, _, bin}:
      Tri.indexed(vs, Idx.of(Acc.of(Tbl.at(accs, Maybe.default(&2, U32, U32.read(r), 0)), views), bin), col, acc)
    case _ _:
      Tri.seq(vs, col, acc)

def Prim.color(has: Bool, +g: Gltf, +i: U32) -> U32:
  match has g:
    case True{} Gltf{_, _, _, _, mats, _}:
      Glb.color(Tbl.at(mats, i))
    case _ _:
      13421772

def Prim.verts(+g: Gltf, +attrs: J.Json, +m: M4) -> List<&2, V3>:
  match g:
    case Gltf{_, _, accs, views, _, bin}:
      Pos.of(Acc.of(Tbl.at(accs, J.Json.get_u32(attrs, "POSITION", 0)), views), bin, m)

def Prim.tri(tri: Bool, +p: J.Json, +g: Gltf, +m: M4, acc: List<&2, Tri3>) -> List<&2, Tri3>:
  match tri:
    case True{}:
      Prim.go(J.Json.get(p, "indices"), Prim.verts(g, J.Json.get_obj(p, "attributes"), m), g,
        Prim.color(Glb.has(J.Json.get(p, "material")), g, J.Json.get_u32(p, "material", 0)), acc)
    case False{}:
      acc

# a primitive's triangles onto acc (only mode 4 draws)
def Prim.tris(+p: J.Json, +g: Gltf, +m: M4, acc: List<&2, Tri3>) -> List<&2, Tri3>:
  Prim.tri(U32.is_eq(J.Json.get_u32(p, "mode", 4), 4), p, g, m, acc)

# a rope of triangle lists: parallel halves join in O(1)
type Rope is Data:
  RNil{}
  RLeaf{ts: List<&2, Tri3>}
  RCat{a: Rope, b: Rope}

def Rope.flat(r: Rope, acc: List<&2, Tri3>) -> List<&2, Tri3>:
  match r:
    case RNil{}:
      acc
    case RLeaf{ts}:
      List.append(&2, Tri3, ts, acc)
    case RCat{a, b}:
      Rope.flat(a, Rope.flat(b, acc))

# one primitive to decode, with its node's world transform
type PJob is Data:
  PJob{p: J.Json, m: M4}

def PJob.run(j: PJob, +g: Gltf) -> List<&2, Tri3>:
  match j:
    case PJob{+p, +m}:
      Prim.tris(p, g, m, Nil{})

# every primitive of a tree, both halves at once
def PJob.par(d: Nat, t: Tab<PJob>, +g: Gltf) -> Rope:
  match d t:
    case _ TLeaf{j}:
      RLeaf{PJob.run(j, g)}
    case 1n+q TNode{l, r}:
      +e = q
      a b = PJob.par(e, l, g) PJob.par(e, r, g)
      RCat{a, b}
    case _ _:
      RNil{}

# a rope's leaves, in order
def Rope.lists(r: Rope, acc: List<&2, List<&2, Tri3>>) -> List<&2, List<&2, Tri3>>:
  match r:
    case RNil{}:
      acc
    case RLeaf{ts}:
      ts <> acc
    case RCat{a, b}:
      Rope.lists(a, Rope.lists(b, acc))

# Nodes
# -----

def Name.arrow(s: String) -> Bool:
  match s:
    case SCon{Chr{a}, SCon{Chr{b}, _}}:
      Bool.and(U32.is_eq(a, 61), U32.is_eq(b, 62))
    case _:
      False{}

def Name.pick.k(own: Bool, n: String, inherited: String) -> String:
  match own:
    case True{}:
      n
    case False{}:
      inherited

# a node names its part unless it is unnamed or a KiCad instance
# ("=>[0:1:1:3]"), in which case it inherits its parent's name
def Name.pick(+n: String, inherited: String) -> String:
  Name.pick.k(Bool.and(Bool.not(String.eq(n, "")), Bool.not(Name.arrow(n))), n, inherited)

def Node.mesh.k(+name: String, +mesh: J.Json, +m: M4, acc: List<&2, Job>) -> List<&2, Job>:
  Job{Name.pick(name, J.Json.get_str(mesh, "name", "")), m, J.Json.elems(J.Json.get_obj(mesh, "primitives"))} <> acc

def Node.mesh(has: Bool, +n: J.Json, +g: Gltf, +m: M4, +name: String, acc: List<&2, Job>) -> List<&2, Job>:
  match has g:
    case True{} Gltf{_, meshes, _, _, _, _}:
      Node.mesh.k(name, Tbl.at(meshes, J.Json.get_u32(n, "mesh", 0)), m, acc)
    case _ _:
      acc

def Walk.kids(ks: List<&2, U32>, +m: M4, +name: String, rest: List<&2, Work>) -> List<&2, Work>:
  match ks:
    case Nil{}:
      rest
    case k <> t:
      Work{k, m, name} <> Walk.kids(t, m, name, rest)

def Walk.node(+n: J.Json, +m: M4, +name: String, rest: List<&2, Work>) -> List<&2, Work>:
  Walk.kids(Glb.u32s(n, "children"), m, name, rest)

# depth-first over the node forest; fuel bounds the visits
def Walk.go(fuel: Nat, ws: List<&2, Work>, +g: Gltf, acc: List<&2, Job>) -> List<&2, Job>:
  match fuel ws g:
    case 0n _ _:
      acc
    case _ Nil{} _:
      acc
    case 1n+f Work{idx, m, name} <> t Gltf{+nodes, _, _, _, _, _}:
      +n = Tbl.at(nodes, idx)
      +w = M4.mul(m, M4.of_node(n))
      +nm = Name.pick(J.Json.get_str(n, "name", ""), name)
      Walk.go(f, Walk.node(n, w, nm, t), g, Node.mesh(Glb.has(J.Json.get(n, "mesh")), n, g, w, nm, acc))

def Walk.roots(ks: List<&2, U32>) -> List<&2, Work>:
  match ks:
    case Nil{}:
      Nil{}
    case k <> t:
      Work{k, M4.id(), ""} <> Walk.roots(t)

# Loading
# -------

def Glb.gltf(+j: J.Json, +bin: Bin) -> Gltf:
  Gltf{Tbl.of(J.Json.elems(J.Json.get_obj(j, "nodes"))), Tbl.of(J.Json.elems(J.Json.get_obj(j, "meshes"))),
    Tbl.of(J.Json.elems(J.Json.get_obj(j, "accessors"))), Tbl.of(J.Json.elems(J.Json.get_obj(j, "bufferViews"))),
    Tbl.of(J.Json.elems(J.Json.get_obj(j, "materials"))), bin}

def Job.prims(ps: List<&2, J.Json>, +m: M4, rest: List<&2, PJob>) -> List<&2, PJob>:
  match ps:
    case Nil{}:
      rest
    case p <> t:
      PJob{p, m} <> Job.prims(t, m, rest)

# every job's primitives, in order
def Job.flat(js: List<&2, Job>) -> List<&2, PJob>:
  match js:
    case Nil{}:
      Nil{}
    case Job{_, +m, ps} <> t:
      Job.prims(ps, m, Job.flat(t))

def Job.cat(n: Nat, ls: List<&2, List<&2, Tri3>>) -> List<&2, Tri3>:
  match n ls:
    case 1n+p l <> t:
      List.append(&2, Tri3, l, Job.cat(p, t))
    case _ _:
      Nil{}

def Job.skip(n: Nat, ls: List<&2, List<&2, Tri3>>) -> List<&2, List<&2, Tri3>>:
  match n ls:
    case 0n _:
      ls
    case 1n+p _ <> t:
      Job.skip(p, t)
    case _ Nil{}:
      Nil{}

# each job's part from the primitives' triangle lists, in order
def Job.group(js: List<&2, Job>, +ls: List<&2, List<&2, Tri3>>) -> List<&2, Part>:
  match js:
    case Nil{}:
      Nil{}
    case Job{name, _, +ps} <> t:
      +k = List.length(&2, J.Json, ps)
      Part{name, Job.cat(k, ls)} <> Job.group(t, Job.skip(k, ls))

# the parts: every primitive of every job decoded at once (split evenly by
# primitive, not by node, so one heavy node does not hold up a core)
def Job.all(+js: List<&2, Job>, +g: Gltf) -> List<&2, Part>:
  +ps = Job.flat(js)
  +d = Tab.depth(U32.from_nat(List.length(&2, PJob, ps)))
  Job.group(js, Rope.lists(PJob.par(d, Tab.of(PJob, d, ps), g), Nil{}))

def Glb.scene(+j: J.Json, +g: Gltf) -> Mesh:
  +roots = Glb.u32s(Tbl.at(Tbl.of(J.Json.elems(J.Json.get_obj(j, "scenes"))), J.Json.get_u32(j, "scene", 0)), "nodes")
  +fuel = Nat.add(Nat.mul(List.length(&2, J.Json, J.Json.elems(J.Json.get_obj(j, "nodes"))), 2n), 16n)
  Mesh{Job.all(List.reverse(&2, Job, Walk.go(fuel, Walk.roots(roots), g, Nil{})), g)}

def Glb.load(m: Maybe<&2, J.Json>, +bin: Bin) -> Mesh:
  match m:
    case Some{+j}:
      Glb.scene(j, Glb.gltf(j, bin))
    case None{}:
      Mesh{Nil{}}

def Glb.chunks(ok: Bool, +bs: List<&2, U32>) -> Mesh:
  match ok:
    case True{}:
      +jl = Bytes.u32(Bytes.drop(12n, bs))
      +rest = Bytes.drop(Nat.add(20n, U32.to_nat(jl)), bs)
      Glb.load(J.Json.parse(U.Utf8.decode(Bytes.take(U32.to_nat(jl), Bytes.drop(20n, bs)))),
        Bin.of(Bytes.u32(rest), Bytes.drop(8n, rest)))
    case False{}:
      Mesh{Nil{}}

# a GLB file's meshes, or no parts when it is not a GLB
def Glb.parse(+bs: List<&2, U32>) -> Mesh:
  Glb.chunks(U32.is_eq(Bytes.u32(bs), 1179937895), bs)

# Reading a mesh
# --------------

def Mesh.names(ps: List<&2, Part>) -> List<&2, String>:
  match ps:
    case Nil{}:
      Nil{}
    case Part{n, _} <> t:
      n <> Mesh.names(t)

# the part names, in scene order
def Mesh.parts(m: Mesh) -> List<&2, String>:
  match m:
    case Mesh{ps}:
      Mesh.names(ps)

def Mesh.flat(ps: List<&2, Part>) -> List<&2, Tri3>:
  match ps:
    case Nil{}:
      Nil{}
    case Part{_, ts} <> t:
      List.append(&2, Tri3, ts, Mesh.flat(t))

# every triangle, in scene order
def Mesh.tris(m: Mesh) -> List<&2, Tri3>:
  match m:
    case Mesh{ps}:
      Mesh.flat(ps)
