import Base

# SHA-256 (FIPS 180-4), HMAC-SHA256 (RFC 2104), hex, and a constant-time
# compare, over byte lists (0..255 per cell). These sign webhooks and
# hub-to-hub requests (src/core/sign.bend), so bodies of a few hundred KB
# pass through: every walk over the message is a tail call (the bytes of the
# current block wait reversed in an accumulator), and only fixed-size work
# (one block, the padding, a 32-byte digest) recurses in the ordinary way.

type H8 is Data:
  H8{a: U32, b: U32, c: U32, d: U32, e: U32, f: U32, g: U32, h: U32}

def Sha256.ks() -> List<&2, U32>:
  [1116352408, 1899447441, 3049323471, 3921009573, 961987163, 1508970993, 2453635748, 2870763221,
   3624381080, 310598401, 607225278, 1426881987, 1925078388, 2162078206, 2614888103, 3248222580,
   3835390401, 4022224774, 264347078, 604807628, 770255983, 1249150122, 1555081692, 1996064986,
   2554220882, 2821834349, 2952996808, 3210313671, 3336571891, 3584528711, 113926993, 338241895,
   666307205, 773529912, 1294757372, 1396182291, 1695183700, 1986661051, 2177026350, 2456956037,
   2730485921, 2820302411, 3259730800, 3345764771, 3516065817, 3600352804, 4094571909, 275423344,
   430227734, 506948616, 659060556, 883997877, 958139571, 1322822218, 1537002063, 1747873779,
   1955562222, 2024104815, 2227730452, 2361852424, 2428436474, 2756734187, 3204031479, 3329325298]

def Sha256.init() -> H8:
  H8{1779033703, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635, 1541459225}

def Sha256.rotr(+x: U32, +k: Nat) -> U32:
  U32.or(U32.shrn(x, k), U32.shln(x, Nat.sub(32n, k)))

def Sha256.bs0(+x: U32) -> U32:
  U32.xor(Sha256.rotr(x, 2n), U32.xor(Sha256.rotr(x, 13n), Sha256.rotr(x, 22n)))

def Sha256.bs1(+x: U32) -> U32:
  U32.xor(Sha256.rotr(x, 6n), U32.xor(Sha256.rotr(x, 11n), Sha256.rotr(x, 25n)))

def Sha256.ss0(+x: U32) -> U32:
  U32.xor(Sha256.rotr(x, 7n), U32.xor(Sha256.rotr(x, 18n), U32.shrn(x, 3n)))

def Sha256.ss1(+x: U32) -> U32:
  U32.xor(Sha256.rotr(x, 17n), U32.xor(Sha256.rotr(x, 19n), U32.shrn(x, 10n)))

def Sha256.ch(+e: U32, +f: U32, +g: U32) -> U32:
  U32.xor(U32.and(e, f), U32.and(U32.not(e), g))

def Sha256.maj(+a: U32, +b: U32, +c: U32) -> U32:
  U32.xor(U32.xor(U32.and(a, b), U32.and(a, c)), U32.and(b, c))

def Sha256.round.k(+t1: U32, +t2: U32, a: U32, b: U32, c: U32, d: U32, e: U32, f: U32, g: U32) -> H8:
  H8{(t1 + t2 : U32), a, b, c, (d + t1 : U32), e, f, g}

def Sha256.round(+k: U32, +w: U32, s: H8) -> H8:
  match s:
    case H8{+a, +b, +c, d, +e, +f, +g, h}:
      Sha256.round.k((h + Sha256.bs1(e) + Sha256.ch(e, f, g) + k + w : U32),
        (Sha256.bs0(a) + Sha256.maj(a, b, c) : U32), a, b, c, d, e, f, g)

def Sha256.rounds(ws: List<&2, U32>, ks: List<&2, U32>, s: H8) -> H8:
  match ws ks:
    case +w <> wt +k <> kt:
      Sha256.rounds(wt, kt, Sha256.round(k, w, s))
    case _ _:
      s

def Sha256.at(xs: List<&2, U32>, n: Nat) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, xs, n), 0)

# the schedule, newest word first: w[t] from w[t-2], w[t-7], w[t-15], w[t-16]
def Sha256.sched(n: Nat, +rev: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      rev
    case 1n+m:
      Sha256.sched(m, (Sha256.ss1(Sha256.at(rev, 1n)) + Sha256.at(rev, 6n) + Sha256.ss0(Sha256.at(rev, 14n)) + Sha256.at(rev, 15n) : U32) <> rev)

def Sha256.be32(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  U32.or(U32.or(U32.shln(a, 24n), U32.shln(b, 16n)), U32.or(U32.shln(c, 8n), d))

# a block's bytes, last first, as its 16 words, last first
def Sha256.words.rev(bs: List<&2, U32>) -> List<&2, U32>:
  match bs:
    case +d <> +c <> +b <> +a <> t:
      Sha256.be32(a, b, c, d) <> Sha256.words.rev(t)
    case _:
      Nil{}

def Sha256.add(x: H8, y: H8) -> H8:
  match x y:
    case H8{a, b, c, d, e, f, g, h} H8{a2, b2, c2, d2, e2, f2, g2, h2}:
      H8{(a + a2 : U32), (b + b2 : U32), (c + c2 : U32), (d + d2 : U32),
        (e + e2 : U32), (f + f2 : U32), (g + g2 : U32), (h + h2 : U32)}

# one 64-byte block, its bytes last first
def Sha256.block(s: H8, rev: List<&2, U32>) -> H8:
  +s2 = s
  Sha256.add(s2, Sha256.rounds(List.reverse(&2, U32, Sha256.sched(48n, Sha256.words.rev(rev))), Sha256.ks(), s2))

# the walk: bytes of the current block (last first), how many, bytes so far
type St is Data:
  St{acc: List<&2, U32>, k: Nat, n: Nat, s: H8}

def Sha256.feed.k(full: Bool, +b: U32, acc: List<&2, U32>, k: Nat, n: Nat, s: H8) -> St:
  match full:
    case True{}:
      St{Nil{}, 0n, 1n+n, Sha256.block(s, b <> acc)}
    case False{}:
      St{b <> acc, 1n+k, 1n+n, s}

def Sha256.feed(st: St, +b: U32) -> St:
  match st:
    case St{acc, +k, n, s}:
      Sha256.feed.k(Nat.is_eq(k, 63n), b, acc, k, n, s)

def Sha256.go(bs: List<&2, U32>, st: St) -> St:
  match bs:
    case Nil{}:
      st
    case +b <> t:
      Sha256.go(t, Sha256.feed(st, b))

def Sha256.be_bytes(+x: U32, rest: List<&2, U32>) -> List<&2, U32>:
  U32.shrn(x, 24n) <> U32.and(U32.shrn(x, 16n), 255) <> U32.and(U32.shrn(x, 8n), 255) <> U32.and(x, 255) <> rest

def Sha256.zeros(n: Nat, rest: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      rest
    case 1n+m:
      Sha256.zeros(m, 0 <> rest)

# the last partial block ++ 0x80 ++ zeros ++ the 64-bit bit length: one or
# two blocks, fed through the same walk
def Sha256.state(st: St) -> H8:
  match st:
    case St{a, k, n, s}:
      s

def Sha256.fin(st: St) -> H8:
  match st:
    case St{acc, +k, +n, s}:
      Sha256.state(Sha256.go(List.append(&2, U32, List.reverse(&2, U32, acc),
          128 <> Sha256.zeros(Nat.mod(Nat.sub(119n, k), 64n),
            Sha256.be_bytes(U32.from_nat(Nat.div(n, 536870912n)), Sha256.be_bytes(U32.from_nat(Nat.mul(Nat.mod(n, 536870912n), 8n)), Nil{})))),
        St{Nil{}, 0n, 0n, s}))

def Sha256.digest(s: H8) -> List<&2, U32>:
  match s:
    case H8{a, b, c, d, e, f, g, h}:
      Sha256.be_bytes(a, Sha256.be_bytes(b, Sha256.be_bytes(c, Sha256.be_bytes(d,
        Sha256.be_bytes(e, Sha256.be_bytes(f, Sha256.be_bytes(g, Sha256.be_bytes(h, Nil{}))))))))

# the 32-byte SHA-256 of a byte list
def Sha256.hash(bs: List<&2, U32>) -> List<&2, U32>:
  Sha256.digest(Sha256.fin(Sha256.go(bs, St{Nil{}, 0n, 0n, Sha256.init()})))

# HMAC-SHA256
# -----------

def Hmac.pad(+k: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, k, Sha256.zeros(Nat.sub(64n, List.length(&2, U32, k)), Nil{}))

def Hmac.key.k(long: Bool, key: List<&2, U32>) -> List<&2, U32>:
  match long:
    case True{}:
      Hmac.pad(Sha256.hash(key))
    case False{}:
      Hmac.pad(key)

# the key as one 64-byte block: hashed first when longer
def Hmac.key(+key: List<&2, U32>) -> List<&2, U32>:
  Hmac.key.k(Nat.is_gt(List.length(&2, U32, key), 64n), key)

def Hmac.xor(k: List<&2, U32>, +p: U32) -> List<&2, U32>:
  match k:
    case Nil{}:
      Nil{}
    case x <> t:
      U32.xor(x, p) <> Hmac.xor(t, p)

# RFC 2104: H((K ^ opad) ++ H((K ^ ipad) ++ msg))
def Hmac.sha256(key: List<&2, U32>, msg: List<&2, U32>) -> List<&2, U32>:
  +k = Hmac.key(key)
  Sha256.hash(List.append(&2, U32, Hmac.xor(k, 92), Sha256.hash(List.append(&2, U32, Hmac.xor(k, 54), msg))))

# Hex
# ---

def Hex.digit(+n: U32) -> Char:
  Chr{U32.add(n, Bool.pick(U32, U32.is_lt(n, 10), 48, 87))}

def Hex.encode.go(bs: List<&2, U32>, acc: String) -> String:
  match bs:
    case Nil{}:
      String.reverse(acc)
    case +b <> t:
      Hex.encode.go(t, SCon{Hex.digit(U32.and(b, 15)), SCon{Hex.digit(U32.shrn(b, 4n)), acc}})

# lowercase, two digits a byte
def Hex.encode(bs: List<&2, U32>) -> String:
  Hex.encode.go(bs, "")

def Hex.val.k(dig: Bool, lo: Bool, up: Bool, +x: U32) -> U32:
  match dig lo up:
    case True{} _ _:
      (x - 48 : U32)
    case False{} True{} _:
      (x - 87 : U32)
    case False{} False{} True{}:
      (x - 55 : U32)
    case False{} False{} False{}:
      16

# a digit's value, 16 when it is not one
def Hex.val(c: Char) -> U32:
  match c:
    case Chr{+x}:
      Hex.val.k(Bool.and(U32.is_ge(x, 48), U32.is_le(x, 57)),
        Bool.and(U32.is_ge(x, 97), U32.is_le(x, 102)),
        Bool.and(U32.is_ge(x, 65), U32.is_le(x, 70)), x)

def Hex.pair.k(ok: Bool, +hi: U32, +lo: U32, xs: List<&2, U32>) -> Maybe<&2, List<&2, U32>>:
  match ok:
    case True{}:
      Some{U32.or(U32.shln(hi, 4n), lo) <> xs}
    case False{}:
      None{}

def Hex.pair(m: Maybe<&2, List<&2, U32>>, +hi: U32, +lo: U32) -> Maybe<&2, List<&2, U32>>:
  match m:
    case None{}:
      None{}
    case Some{xs}:
      Hex.pair.k(Bool.and(U32.is_lt(hi, 16), U32.is_lt(lo, 16)), hi, lo, xs)

def Hex.done(m: Maybe<&2, List<&2, U32>>) -> Maybe<&2, List<&2, U32>>:
  match m:
    case None{}:
      None{}
    case Some{xs}:
      Some{List.reverse(&2, U32, xs)}

# bytes so far last first; a failed pair makes it None for good
def Hex.decode.go(s: String, m: Maybe<&2, List<&2, U32>>) -> Maybe<&2, List<&2, U32>>:
  match s:
    case SNil{}:
      Hex.done(m)
    case SCon{a, SNil{}}:
      None{}
    case SCon{a, SCon{b, t}}:
      Hex.decode.go(t, Hex.pair(m, Hex.val(a), Hex.val(b)))

# either case; None on an odd length or a character that is not a digit
def Hex.decode(s: String) -> Maybe<&2, List<&2, U32>>:
  Hex.decode.go(s, Some{Nil{}})

# Constant-time compare
# ---------------------

# a byte, or 256 past the end (never equal to a byte)
def Ct.hd(xs: List<&2, U32>) -> U32:
  match xs:
    case Nil{}:
      256
    case h <> t:
      h

def Ct.tl(xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case h <> t:
      t

def Ct.go(n: Nat, +a: List<&2, U32>, +b: List<&2, U32>, +acc: U32) -> Bool:
  match n:
    case 0n:
      U32.is_eq(acc, 0)
    case 1n+m:
      Ct.go(m, Ct.tl(a), Ct.tl(b), U32.or(acc, U32.xor(Ct.hd(a), Ct.hd(b))))

# equal bytes, looking at every position of the longer list whatever the
# first difference, so the time says nothing about where two MACs part
def Ct.eq(+a: List<&2, U32>, +b: List<&2, U32>) -> Bool:
  +la = List.length(&2, U32, a)
  +lb = List.length(&2, U32, b)
  Ct.go(Bool.pick(Nat, Nat.is_ge(la, lb), la, lb), a, b, 0)
