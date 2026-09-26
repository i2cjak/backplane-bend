import Base

# PNG (RFC 2083) from 8-bit RGB rows, for renders saved to disk. Each row
# is filtered with Sub (a flat colour becomes zeros) and deflated in one
# fixed-Huffman block (RFC 1951) whose only matches are runs of the byte
# before (distance 1): a render's plain ground and flat faces pack well,
# with no search tables. Everything walks once, tail-recursively, onto a
# reversed list.

# Checksums
# ---------

def Png.crc.bit(+c: U32) -> U32:
  Bool.pick(U32, U32.is_eq(U32.and(c, 1), 1), U32.xor(3988292384, U32.shr(c)), U32.shr(c))

def Png.crc.bits(k: Nat, +c: U32) -> U32:
  match k:
    case 0n:
      c
    case 1n+r:
      Png.crc.bits(r, Png.crc.bit(c))

def Png.crc.go(bs: List<&2, U32>, +c: U32) -> U32:
  match bs:
    case Nil{}:
      c
    case +b <> t:
      Png.crc.go(t, Png.crc.bits(8n, U32.xor(c, b)))

# CRC-32 as PNG chunks and zip use it
def Png.crc(bs: List<&2, U32>) -> U32:
  U32.xor(Png.crc.go(bs, 4294967295), 4294967295)

def Png.adler.go(bs: List<&2, U32>, +a: U32, +b: U32) -> U32:
  match bs:
    case Nil{}:
      U32.or(U32.shln(b, 16n), a)
    case +x <> t:
      +a2 = {((a + x : U32) % 65521 : U32) : U32}
      Png.adler.go(t, a2, ((b + a2 : U32) % 65521 : U32))

# Adler-32, zlib's trailer
def Png.adler(bs: List<&2, U32>) -> U32:
  Png.adler.go(bs, 1, 0)

# Bytes
# -----

def Png.be32(+x: U32) -> List<&2, U32>:
  [U32.and(U32.shrn(x, 24n), 255), U32.and(U32.shrn(x, 16n), 255), U32.and(U32.shrn(x, 8n), 255), U32.and(x, 255)]

def Png.ascii(s: String) -> List<&2, U32>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{Chr{c}, t}:
      U32.and(c, 255) <> Png.ascii(t)

# a chunk: length, type, data, and the CRC of type and data
def Png.chunk(+ty: String, +data: List<&2, U32>) -> List<&2, U32>:
  List.append(&2, U32, Png.be32(U32.from_nat(List.length(&2, U32, data))),
    List.append(&2, U32, Png.ascii(ty), List.append(&2, U32, data, Png.be32(Png.crc(List.append(&2, U32, Png.ascii(ty), data))))))

# Filtering
# ---------

# a Sub walk: the byte's place in its row, the row's last three bytes
# (a pixel back), the output so far reversed
type Sb is Data:
  Sb{i: U32, a: U32, b: U32, c: U32, out: List<&2, U32>}

# a filter byte (1) before each row, then each byte less the one three
# before it in the row (the pixel before's same channel)
def Png.sub.step(first: Bool, +x: U32, s: Sb) -> Sb:
  match first s:
    case True{} Sb{_, _, _, _, out}:
      Sb{1, 0, 0, x, x <> 1 <> out}
    case False{} Sb{+i, +a, +b, +c, out}:
      Sb{(i + 1 : U32), b, c, x, U32.and((x - a : U32), 255) <> out}

def Png.sub.at(s: Sb, +row: U32) -> Bool:
  match s:
    case Sb{+i, _, _, _, _}:
      U32.is_eq(i, row)

def Png.sub.go(bs: List<&2, U32>, +row: U32, +s: Sb) -> List<&2, U32>:
  match bs:
    case Nil{}:
      match s:
        case Sb{_, _, _, _, out}:
          out
    case +x <> t:
      Png.sub.go(t, row, Png.sub.step(Png.sub.at(s, row), x, s))

def Png.sub(bs: List<&2, U32>, +w: U32) -> List<&2, U32>:
  +row = {(w * 3 : U32) : U32}
  List.reverse(&2, U32, Png.sub.go(bs, row, Sb{row, 0, 0, 0, Nil{}}))

# Deflate
# -------

# bits out, least significant first: what is held, how many, bytes so far
type Bw is Data:
  Bw{acc: U32, n: U32, out: List<&2, U32>}

def Bw.drain.k(short: Bool, +acc: U32, +n: U32, out: List<&2, U32>) -> Bw:
  match short:
    case True{}:
      Bw{acc, n, out}
    case False{}:
      Bw{U32.shrn(acc, 8n), (n - 8 : U32), U32.and(acc, 255) <> out}

# a whole byte out, if one is held
def Bw.drain(w: Bw) -> Bw:
  match w:
    case Bw{+acc, +n, out}:
      Bw.drain.k(U32.is_lt(n, 8), acc, n, out)

# up to 9 bits in (under 8 were held, so at most two bytes go out)
def Bw.put(w: Bw, +v: U32, +len: U32) -> Bw:
  match w:
    case Bw{+acc, +n, out}:
      Bw.drain(Bw.drain(Bw{U32.or(acc, U32.shln(v, U32.to_nat(n))), (n + len : U32), out}))

def Bw.bytes(w: Bw) -> List<&2, U32>:
  match w:
    case Bw{_, _, out}:
      List.reverse(&2, U32, out)

# the bytes in order, a partial last one padded with zeros (seven zero
# bits more push out exactly the byte begun, if any)
def Bw.done(w: Bw) -> List<&2, U32>:
  Bw.bytes(Bw.put(w, 0, 7))

# a Huffman code goes out most significant bit first
def Png.rev(k: Nat, +c: U32, +r: U32) -> U32:
  match k:
    case 0n:
      r
    case 1n+m:
      Png.rev(m, U32.shr(c), U32.or(U32.shln(r, 1n), U32.and(c, 1)))

def Png.code(w: Bw, +c: U32, +len: U32) -> Bw:
  Bw.put(w, Png.rev(U32.to_nat(len), c, 0), len)

# a literal/length symbol in the fixed code (RFC 1951 3.2.6)
def Png.sym.code(+s: U32) -> U32:
  Bool.pick(U32, U32.is_lt(s, 144), (s + 48 : U32),
    Bool.pick(U32, U32.is_lt(s, 256), (s + 256 : U32), Bool.pick(U32, U32.is_lt(s, 280), (s - 256 : U32), (s - 88 : U32))))

def Png.sym.len(+s: U32) -> U32:
  Bool.pick(U32, U32.is_lt(s, 144), 8, Bool.pick(U32, U32.is_lt(s, 256), 9, Bool.pick(U32, U32.is_lt(s, 280), 7, 8)))

def Png.sym(w: Bw, +s: U32) -> Bw:
  Png.code(w, Png.sym.code(s), Png.sym.len(s))

def Png.bitlen(k: Nat, +x: U32, +n: U32) -> U32:
  match k:
    case 0n:
      n
    case 1n+r:
      Bool.pick(U32, U32.is_eq(x, 0), n, Png.bitlen(r, U32.shr(x), (n + 1 : U32)))

# a length's symbol, extra bit count and extra value (3..258)
type Len is Data:
  Len{sym: U32, ebits: U32, extra: U32}

def Png.len.k(+m: U32, +e: U32) -> Len:
  Len{(257 + (4 * (e + 1) : U32) + (U32.shrn(m, U32.to_nat(e)) - 4 : U32) : U32), e, U32.and(m, (U32.shln(1, U32.to_nat(e)) - 1 : U32))}

def Png.len(+l: U32) -> Len:
  +m = {(l - 3 : U32) : U32}
  Bool.pick(Len, U32.is_eq(l, 258), Len{285, 0, 0},
    Bool.pick(Len, U32.is_lt(m, 8), Len{(257 + m : U32), 0, 0}, Png.len.k(m, (Png.bitlen(9n, m, 0) - 3 : U32))))

# a match of l bytes at distance 1 (distance code 0, five zero bits)
def Png.match.k(w: Bw, n: Len) -> Bw:
  match n:
    case Len{s, e, x}:
      Bw.put(Bw.put(Png.sym(w, s), x, e), 0, 5)

def Png.match(w: Bw, +l: U32) -> Bw:
  Png.match.k(w, Png.len(l))

def Png.lits(k: Nat, w: Bw, +b: U32) -> Bw:
  match k:
    case 0n:
      w
    case 1n+r:
      Png.lits(r, Png.sym(w, b), b)

# a run of r copies of b after b itself: a match, or literals when short
def Png.run.k(short: Bool, w: Bw, +b: U32, +r: U32) -> Bw:
  match short:
    case True{}:
      Png.lits(U32.to_nat(r), w, b)
    case False{}:
      Png.match(w, r)

def Png.run(w: Bw, +b: U32, +r: U32) -> Bw:
  Png.run.k(U32.is_lt(r, 3), w, b, r)

# a deflate walk: the byte runs are of, how many copies so far, the bits
type Df is Data:
  Df{b: U32, r: U32, w: Bw}

def Png.defl.step(more: Bool, +x: U32, d: Df) -> Df:
  match more d:
    case True{} Df{b, +r, w}:
      Df{b, (r + 1 : U32), w}
    case False{} Df{+b, +r, w}:
      Df{x, 0, Png.sym(Png.run(w, b, r), x)}

def Png.defl.more(d: Df, +x: U32) -> Bool:
  match d:
    case Df{+b, +r, _}:
      Bool.and(U32.is_eq(x, b), U32.is_lt(r, 258))

def Png.defl.go(bs: List<&2, U32>, +d: Df) -> Bw:
  match bs:
    case Nil{}:
      match d:
        case Df{+b, +r, w}:
          Png.run(w, b, r)
    case +x <> t:
      Png.defl.go(t, Png.defl.step(Png.defl.more(d, x), x, d))

def Png.defl.k(bs: List<&2, U32>, w: Bw) -> Bw:
  match bs:
    case Nil{}:
      w
    case +x <> t:
      Png.defl.go(t, Df{x, 0, Png.sym(w, x)})

# one final fixed-Huffman block (BFINAL 1, BTYPE 01), then end of block
def Png.deflate(bs: List<&2, U32>) -> List<&2, U32>:
  Bw.done(Png.sym(Png.defl.k(bs, Bw.put(Bw{0, 0, Nil{}}, 3, 3)), 256))

# zlib: header (deflate, 32K window, no preset), data, Adler-32
def Png.zlib(+bs: List<&2, U32>) -> List<&2, U32>:
  120 <> 1 <> List.append(&2, U32, Png.deflate(bs), Png.be32(Png.adler(bs)))

# The file
# --------

# w x h pixels of 8-bit RGB, row by row, as a PNG file's bytes
def Png.rgb(bs: List<&2, U32>, +w: U32, +h: U32) -> List<&2, U32>:
  List.append(&2, U32, [137, 80, 78, 71, 13, 10, 26, 10],
    List.append(&2, U32, Png.chunk("IHDR", List.append(&2, U32, Png.be32(w), List.append(&2, U32, Png.be32(h), [8, 2, 0, 0, 0]))),
      List.append(&2, U32, Png.chunk("IDAT", Png.zlib(Png.sub(bs, w))), Png.chunk("IEND", Nil{}))))
