import Base

# SHA-1 (FIPS 180-4) and Base64 (RFC 4648), over byte lists. SHA-1 is only
# here for the WebSocket handshake (RFC 6455 fixes the choice); nothing
# security-relevant depends on it.

type H5 is Data:
  H5{a: U32, b: U32, c: U32, d: U32, e: U32}

def Sha1.rotl(+x: U32, +k: Nat) -> U32:
  U32.or(U32.shln(x, k), U32.shrn(x, Nat.sub(32n, k)))

def Sha1.fk.k(lt20: Bool, lt40: Bool, lt60: Bool, +b: U32, +c: U32, +d: U32) -> U32 & U32:
  match lt20 lt40 lt60:
    case True{} _ _:
      (U32.or(U32.and(b, c), U32.and(U32.not(b), d)), 1518500249)
    case False{} True{} _:
      (U32.xor(b, U32.xor(c, d)), 1859775393)
    case False{} False{} True{}:
      (U32.or(U32.or(U32.and(b, c), U32.and(b, d)), U32.and(c, d)), 2400959708)
    case False{} False{} False{}:
      (U32.xor(b, U32.xor(c, d)), 3395469782)

def Sha1.fk(+t: U32, +b: U32, +c: U32, +d: U32) -> U32 & U32:
  Sha1.fk.k(U32.is_lt(t, 20), U32.is_lt(t, 40), U32.is_lt(t, 60), b, c, d)

def Sha1.round.k(fk: U32 & U32, +w: U32, h: H5) -> H5:
  (f, k) = fk
  match h:
    case H5{+a, +b, c, d, e}:
      H5{(Sha1.rotl(a, 5n) + f + e + k + w : U32), a, Sha1.rotl(b, 30n), c, d}

def Sha1.round(+t: U32, +w: U32, h: H5) -> H5:
  match h:
    case H5{a, +b, +c, +d, e}:
      Sha1.round.k(Sha1.fk(t, b, c, d), w, H5{a, b, c, d, e})

def Sha1.at(xs: List<&2, U32>, n: Nat) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, xs, n), 0)

# the window of 16 words moves one step: drop w[t], push w[t+16]
def Sha1.slide(+win: List<&2, U32>) -> List<&2, U32>:
  +nw = Sha1.rotl(U32.xor(U32.xor(Sha1.at(win, 13n), Sha1.at(win, 8n)), U32.xor(Sha1.at(win, 2n), Sha1.at(win, 0n))), 1n)
  List.append(&2, U32, List.drop(&2, U32, win, 1n), [nw])

def Sha1.rounds(n: Nat, +t: U32, +win: List<&2, U32>, h: H5) -> H5:
  match n:
    case 0n:
      h
    case 1n+m:
      Sha1.rounds(m, (t + 1 : U32), Sha1.slide(win), Sha1.round(t, Sha1.at(win, 0n), h))

def Sha1.add(x: H5, y: H5) -> H5:
  match x y:
    case H5{a, b, c, d, e} H5{a2, b2, c2, d2, e2}:
      H5{(a + a2 : U32), (b + b2 : U32), (c + c2 : U32), (d + d2 : U32), (e + e2 : U32)}

def Sha1.be32(+xs: List<&2, U32>) -> U32:
  U32.or(U32.or(U32.shln(Sha1.at(xs, 0n), 24n), U32.shln(Sha1.at(xs, 1n), 16n)),
    U32.or(U32.shln(Sha1.at(xs, 2n), 8n), Sha1.at(xs, 3n)))

# 64 bytes as 16 big-endian words
def Sha1.words(n: Nat, +bs: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+m:
      Sha1.be32(bs) <> Sha1.words(m, List.drop(&2, U32, bs, 4n))

def Sha1.block(h: H5, +blk: List<&2, U32>) -> H5:
  +h2 = h
  Sha1.add(h2, Sha1.rounds(80n, 0, Sha1.words(16n, blk), h2))

def Sha1.blocks(n: Nat, +bs: List<&2, U32>, h: H5) -> H5:
  match n:
    case 0n:
      h
    case 1n+m:
      Sha1.blocks(m, List.drop(&2, U32, bs, 64n), Sha1.block(h, List.take(&2, U32, bs, 64n)))

def Sha1.be_bytes(+x: U32, rest: List<&2, U32>) -> List<&2, U32>:
  U32.shrn(x, 24n) <> U32.and(U32.shrn(x, 16n), 255) <> U32.and(U32.shrn(x, 8n), 255) <> U32.and(x, 255) <> rest

def Sha1.zeros(n: Nat, rest: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      rest
    case 1n+m:
      0 <> Sha1.zeros(m, rest)

# message ++ 0x80 ++ zeros ++ 64-bit bit length, a multiple of 64 bytes
def Sha1.pad(+bs: List<&2, U32>) -> List<&2, U32>:
  +len = List.length(&2, U32, bs)
  +z = Nat.mod(Nat.sub(Nat.add(64n, 55n), Nat.mod(len, 64n)), 64n)
  List.append(&2, U32, bs, 128 <> Sha1.zeros(z, Sha1.be_bytes(0, Sha1.be_bytes(U32.from_nat(Nat.mul(len, 8n)), Nil{}))))

def Sha1.digest(h: H5) -> List<&2, U32>:
  match h:
    case H5{a, b, c, d, e}:
      Sha1.be_bytes(a, Sha1.be_bytes(b, Sha1.be_bytes(c, Sha1.be_bytes(d, Sha1.be_bytes(e, Nil{})))))

# the 20-byte SHA-1 of a byte list
def Sha1.hash(bs: List<&2, U32>) -> List<&2, U32>:
  +p = Sha1.pad(bs)
  Sha1.digest(Sha1.blocks(Nat.div(List.length(&2, U32, p), 64n), p, H5{1732584193, 4023233417, 2562383102, 271733878, 3285377520}))

# Base64
# ------

def B64.chr.k(up: Bool, lo: Bool, dg: Bool, +n: U32) -> Char:
  match up lo dg:
    case True{} _ _:
      Chr{(n + 65 : U32)}
    case False{} True{} _:
      Chr{(n + 71 : U32)}
    case False{} False{} True{}:
      Chr{(n - 4 : U32)}
    case False{} False{} False{}:
      Chr{U32.add(43, U32.mul(Bool.to_u32(U32.is_eq(n, 63)), 4))}

def B64.chr(+n: U32) -> Char:
  B64.chr.k(U32.is_lt(n, 26), U32.is_lt(n, 52), U32.is_lt(n, 62), n)

def B64.enc3(+a: U32, +b: U32, +c: U32, rest: String) -> String:
  SCon{B64.chr(U32.shrn(a, 2n)),
    SCon{B64.chr(U32.or(U32.shln(U32.and(a, 3), 4n), U32.shrn(b, 4n))),
      SCon{B64.chr(U32.or(U32.shln(U32.and(b, 15), 2n), U32.shrn(c, 6n))),
        SCon{B64.chr(U32.and(c, 63)), rest}}}}

# the text so far reversed in acc, so each group of three is a tail call
# (an image or a long message is megabytes)
def B64.encode.go(bs: List<&2, U32>, acc: String) -> String:
  match bs:
    case Nil{}:
      String.reverse(acc)
    case +a <> Nil{}:
      String.reverse.go(acc, String.take(B64.enc3(a, 0, 0, ""), 2n) ++ "==")
    case +a <> +b <> Nil{}:
      String.reverse.go(acc, String.take(B64.enc3(a, b, 0, ""), 3n) ++ "=")
    case +a <> +b <> +c <> rest:
      B64.encode.go(rest, String.reverse.go(B64.enc3(a, b, c, ""), acc))

# standard alphabet with = padding
def B64.encode(bs: List<&2, U32>) -> String:
  B64.encode.go(bs, "")
