import Base
import ./board.bend as B
import ./look.bend as LO
import ./eq.bend as Q
import ./json.bend as J

# A board or schematic for the phones. The hub turns the viewer's items
# into chunks the phone draws as one path each: the fills, the strokes of
# one width or the dots of one diameter on one layer, in paint order, in
# integer micrometres, delta coded as text (Plot.enc). Only visible layers
# are sent (law plot_hidden_not_sent).
#
# A group's items are spread over 16 chunks by a hash of their keys, so an
# edit to one item changes one chunk, whatever else the file holds. A new
# version of the file goes to a phone as a delta against the chunks it
# already holds (Plot.delta): a chunk it has goes as its index, so an
# unchanged board sends no geometry (law plot_unchanged_sends_nothing),
# and what the phone rebuilds is exactly the new plot (law
# plot_delta_exact). The phone fades in exactly the chunks sent whole.

# mode: 0 fill, 1 stroke (width), 2 dots (width is the diameter); sig is a
# hash of the rest, so most unequal chunks differ at the first compare;
# rev is the chunk's text last digit first, as it was built (a message
# puts it in place in one pass)
type Chunk is Data:
  Chunk{sig: U32, layer: U32, color: U32, alpha: U32, mode: U32, width: U32, rev: String}

# one item's share of a chunk: where it sorts (rank, then its key's hash),
# how many points it has and their coordinates, x y x y ...
type Piece is Data:
  Piece{rank: U32, kh: U32, n: U32, ints: List<&2, U32>}

# what a phone gets for each chunk of a plot: the index of a chunk it
# already holds, or the chunk itself
type Ref is Data:
  Keep{at: Nat}
  Fresh{chunk: Chunk}

# Numbers
# -------
# Coordinates are micrometres as two's complement U32, so a delta is one
# wrapping subtraction. Each number goes out zigzag coded (small magnitudes
# of either sign stay small) as base64url digits of 5 bits each, low
# first, the digit's sixth bit set while more follow. No digit needs
# escaping in JSON.

def Num.um.k(neg: Bool, +x: F32) -> U32:
  match neg:
    case True{}:
      U32.sub(0, F32.to_u32(F32.round(F32.mul(F32.neg(x), 1000.0))))
    case False{}:
      F32.to_u32(F32.round(F32.mul(x, 1000.0)))

# millimetres to micrometres
def Num.um(+x: F32) -> U32:
  Num.um.k(F32.is_lt(x, 0.0), x)

def Num.zig(+d: U32) -> U32:
  U32.xor(U32.shln(d, 1n), U32.sub(0, U32.shrn(d, 31n)))

def Num.unzig(+z: U32) -> U32:
  U32.xor(U32.shrn(z, 1n), U32.sub(0, U32.and(z, 1)))

def Num.digit(+v: U32) -> U32:
  Bool.pick(U32, U32.is_lt(v, 26), (v + 65 : U32),
    Bool.pick(U32, U32.is_lt(v, 52), (v + 71 : U32),
      Bool.pick(U32, U32.is_lt(v, 62), (v - 4 : U32), Bool.pick(U32, U32.is_eq(v, 62), 45, 95))))

def Num.value(+c: U32) -> U32:
  Bool.pick(U32, Bool.and(U32.is_ge(c, 65), U32.is_le(c, 90)), (c - 65 : U32),
    Bool.pick(U32, Bool.and(U32.is_ge(c, 97), U32.is_le(c, 122)), (c - 71 : U32),
      Bool.pick(U32, Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57)), (c + 4 : U32), Bool.pick(U32, U32.is_eq(c, 45), 62, 63))))

# Encoding
# --------
# The text is built backwards (a cons per digit, tail calls only) with a
# running FNV-1a hash of it, and turned around once.

type Enc is Data:
  Enc{rev: String, px: U32, py: U32, h: U32}

def Enc.put(+c: U32, e: Enc) -> Enc:
  match e:
    case Enc{rev, px, py, +h}:
      Enc{SCon{Chr{c}, rev}, px, py, (U32.xor(h, c) * 16777619 : U32)}

# one number, 5 bits a digit; `last` says nothing is left above them
def Enc.var(n: Nat, last: Bool, +z: U32, e: Enc) -> Enc:
  match n last:
    case 0n _:
      Enc.put(Num.digit(U32.and(z, 31)), e)
    case 1n+m True{}:
      Enc.put(Num.digit(U32.and(z, 31)), e)
    case 1n+m False{}:
      Enc.var(m, U32.is_eq(U32.shrn(z, 10n), 0), U32.shrn(z, 5n), Enc.put(Num.digit(U32.or(U32.and(z, 31), 32)), e))

def Enc.num(+z: U32, e: Enc) -> Enc:
  Enc.var(7n, U32.is_eq(U32.shrn(z, 5n), 0), z, e)

def Enc.pt(+x: U32, +y: U32, e: Enc) -> Enc:
  match e:
    case Enc{rev, +px, +py, h}:
      Enc.num(Num.zig((y - py : U32)), Enc.num(Num.zig((x - px : U32)), Enc{rev, x, y, h}))

def Enc.fix(e: Enc, +px: U32, +py: U32) -> Enc:
  match e:
    case Enc{rev, _, _, h}:
      Enc{rev, px, py, h}

def Enc.pts(xs: List<&2, U32>, e: Enc) -> Enc:
  match xs:
    case +x <> +y <> t:
      Enc.pts(t, Enc.pt(x, y, e))
    case _:
      e

# a path is its point count, then its points; a dot is its one point
def Enc.piece.k(dot: Bool, +n: U32, xs: List<&2, U32>, e: Enc) -> Enc:
  match dot:
    case True{}:
      Enc.pts(xs, e)
    case False{}:
      Enc.pts(xs, Enc.num(n, e))

def Enc.piece(+mode: U32, p: Piece, e: Enc) -> Enc:
  match p:
    case Piece{_, _, +n, xs}:
      Enc.piece.k(U32.is_eq(mode, 2), n, xs, e)

def Enc.pieces(ps: List<&2, Piece>, +mode: U32, e: Enc) -> Enc:
  match ps:
    case Nil{}:
      e
    case p <> t:
      Enc.pieces(t, mode, Enc.piece(mode, p, e))

def Enc.list(xs: List<&2, U32>, e: Enc) -> Enc:
  match xs:
    case Nil{}:
      e
    case +x <> t:
      Enc.list(t, Enc.num(x, e))

def Enc.rev(e: Enc) -> String:
  match e:
    case Enc{rev, _, _, _}:
      rev

# some numbers as text
def Enc.text(xs: List<&2, U32>) -> String:
  String.reverse(Enc.rev(Enc.list(xs, Enc{SNil{}, 0, 0, 0})))

# the numbers of a text (what the phones decode; the tests' reference)
type DecS is Data:
  DecS{acc: U32, sh: U32, out: List<&2, U32>}

def Dec.step.k(more: Bool, +acc: U32, +sh: U32, out: List<&2, U32>) -> DecS:
  match more:
    case True{}:
      DecS{acc, (sh + 5 : U32), out}
    case False{}:
      DecS{0, 0, acc <> out}

def Dec.step(+v: U32, st: DecS) -> DecS:
  match st:
    case DecS{+acc, +sh, out}:
      Dec.step.k(U32.is_ge(v, 32), U32.or(acc, U32.shln(U32.and(v, 31), U32.to_nat(sh))), sh, out)

def Dec.go(s: String, st: DecS) -> List<&2, U32>:
  match s st:
    case SNil{} DecS{_, _, out}:
      List.reverse(&2, U32, out)
    case SCon{Chr{+c}, t} _:
      Dec.go(t, Dec.step(Num.value(c), st))

def Dec.nums(s: String) -> List<&2, U32>:
  Dec.go(s, DecS{0, 0, Nil{}})

# Rank
# ----
# A piece sorts by layer (paint order), mode, width, then bucket (its
# key's hash, 16 ways), packed in one U32: 5 + 2 + 21 + 4 bits.

def Rank.of(+layer: U32, +mode: U32, +width: U32, +kh: U32) -> U32:
  U32.or(U32.or(U32.shln(layer, 27n), U32.shln(mode, 25n)), U32.or(U32.shln(U32.min(width, 2097151), 4n), U32.and(kh, 15)))

def Rank.layer(+r: U32) -> U32:
  U32.shrn(r, 27n)

def Rank.mode(+r: U32) -> U32:
  U32.and(U32.shrn(r, 25n), 3)

def Rank.width(+r: U32) -> U32:
  U32.and(U32.shrn(r, 4n), 2097151)

def Piece.le.k(same: Bool, +ra: U32, +rb: U32, +ka: U32, +kb: U32) -> Bool:
  match same:
    case True{}:
      U32.is_le(ka, kb)
    case False{}:
      U32.is_lt(ra, rb)

def Piece.le(a: Piece, b: Piece) -> Bool:
  match a b:
    case Piece{+ra, +ka, _, _} Piece{+rb, +kb, _, _}:
      Piece.le.k(U32.is_eq(ra, rb), ra, rb, ka, kb)

def Piece.rank(p: Piece) -> U32:
  match p:
    case Piece{r, _, _, _}:
      r

# Pieces
# ------

def Key.hash(s: String, +h: U32) -> U32:
  match s:
    case SNil{}:
      h
    case SCon{Chr{+c}, t}:
      Key.hash(t, (U32.xor(h, c) * 16777619 : U32))

def Pts.put(p: B.Pt, acc: List<&2, U32>) -> List<&2, U32>:
  match p:
    case B.Pt{+x, +y}:
      Num.um(y) <> Num.um(x) <> acc

# a path's coordinates, backwards (then turned around once)
def Pts.rev(ps: List<&2, B.Pt>, acc: List<&2, U32>) -> List<&2, U32>:
  match ps:
    case Nil{}:
      acc
    case p <> t:
      Pts.rev(t, Pts.put(p, acc))

def Pts.of(ps: List<&2, B.Pt>) -> List<&2, U32>:
  List.reverse(&2, U32, Pts.rev(ps, Nil{}))

def Pts.ring.at(+i: Nat, +cx: F32, +cy: F32, +r: F32) -> B.Pt:
  +a = F32.mul(F32.div(F32.from_nat(i), 32.0), F32.mul(2.0, F32.pi()))
  B.Pt{F32.add(cx, F32.mul(r, F32.cos(a))), F32.add(cy, F32.mul(r, F32.sin(a)))}

def Pts.ring(n: Nat, +i: Nat, +cx: F32, +cy: F32, +r: F32) -> List<&2, B.Pt>:
  match n:
    case 0n:
      [Pts.ring.at(i, cx, cy, r)]
    case 1n+m:
      Pts.ring.at(i, cx, cy, r) <> Pts.ring(m, 1n+i, cx, cy, r)

def Pts.closed(+ps: List<&2, B.Pt>) -> List<&2, B.Pt>:
  List.append(&2, B.Pt, ps, List.take(&2, B.Pt, ps, 1n))

def Piece.make(+layer: U32, +mode: U32, +width: U32, +kh: U32, +n: Nat, xs: List<&2, U32>) -> Piece:
  Piece{Rank.of(layer, mode, width, kh), kh, U32.from_nat(n), xs}

def Piece.path(+layer: U32, +mode: U32, +width: U32, +kh: U32, +ps: List<&2, B.Pt>) -> Piece:
  Piece.make(layer, mode, width, kh, List.length(&2, B.Pt, ps), Pts.of(ps))

# how one primitive is drawn: its mode, width and points
def Piece.prim(p: B.Prim, +layer: U32, +kh: U32) -> Piece:
  match p:
    case B.PSeg{+a, +b, +w}:
      Piece.path(layer, 1, Num.um(w), kh, [a, b])
    case B.PLine{+ps, +w}:
      Piece.path(layer, 1, Num.um(w), kh, ps)
    case B.PCirc{+c, +r, _, True{}}:
      Piece.make(layer, 2, Num.um(F32.mul(r, 2.0)), kh, 1n, Pts.of([c]))
    case B.PCirc{B.Pt{+cx, +cy}, +r, +w, False{}}:
      Piece.path(layer, 1, Num.um(w), kh, Pts.ring(32n, 0n, cx, cy, r))
    case B.PPoly{+ps, _, True{}}:
      Piece.path(layer, 0, 0, kh, ps)
    case B.PPoly{+ps, +w, False{}}:
      Piece.path(layer, 1, Num.um(w), kh, Pts.closed(ps))

def Piece.shown(+alpha: U32) -> Bool:
  U32.is_ne(alpha, 0)

def Piece.alpha.k(l: U32 & U32) -> U32:
  (_, a) = l
  a

# the viewers' opacity for a layer (0 hides it)
def Piece.alpha(+kind: U32, +layer: U32) -> U32:
  Piece.alpha.k(LO.Look.of(kind, layer))

def Piece.put.k(shown: Bool, i: B.Item, acc: List<&2, Piece>) -> List<&2, Piece>:
  match shown i:
    case True{} B.Item{+key, _, +layer, p, _}:
      Piece.prim(p, layer, Key.hash(key, 2166136261)) <> acc
    case False{} _:
      acc

# an item's piece on the list, when its layer is shown
def Piece.put(i: B.Item, +kind: U32, acc: List<&2, Piece>) -> List<&2, Piece>:
  match i:
    case B.Item{+key, sig, +layer, p, info}:
      Piece.put.k(Piece.shown(Piece.alpha(kind, layer)), B.Item{key, sig, layer, p, info}, acc)

def Piece.all(its: List<&2, B.Item>, +kind: U32, acc: List<&2, Piece>) -> List<&2, Piece>:
  match its:
    case Nil{}:
      acc
    case i <> t:
      Piece.all(t, kind, Piece.put(i, kind, acc))

# the pieces of some items (order is the sort's business)
def Piece.of(its: List<&2, B.Item>, +kind: U32) -> List<&2, Piece>:
  Piece.all(its, kind, Nil{})

# Chunks
# ------

type Group is Data:
  Group{i: Nat, rank: U32, ps: List<&2, Piece>}

type Hand is Data:
  Hand{a: List<&2, Group>, b: List<&2, Group>}

def Group.close(+i: Nat, +rank: U32, ps: List<&2, Piece>, gs: List<&2, Group>) -> List<&2, Group>:
  match ps:
    case Nil{}:
      gs
    case _:
      Group{i, rank, List.reverse(&2, Piece, ps)} <> gs

# the walk's state: the open group's number, rank and pieces (backwards),
# and the closed groups (backwards)
type GS is Data:
  GS{i: Nat, rank: U32, cur: List<&2, Piece>, gs: List<&2, Group>}

def Group.step.k(same: Bool, +p: Piece, st: GS) -> GS:
  match same st:
    case True{} GS{i, rank, cur, gs}:
      GS{i, rank, p <> cur, gs}
    case False{} GS{+i, +rank, +cur, gs}:
      GS{Bool.pick(Nat, List.is_empty(&2, Piece, cur), i, 1n+i), Piece.rank(p), [p], Group.close(i, rank, cur, gs)}

def Group.step(+p: Piece, st: GS) -> GS:
  match st:
    case GS{i, +rank, cur, gs}:
      Group.step.k(U32.is_eq(Piece.rank(p), rank), p, GS{i, rank, cur, gs})

def Group.fin(st: GS) -> List<&2, Group>:
  match st:
    case GS{+i, +rank, cur, gs}:
      List.reverse(&2, Group, Group.close(i, rank, cur, gs))

# runs of equal rank in sorted pieces, numbered in order
def Group.go(ps: List<&2, Piece>, st: GS) -> List<&2, Group>:
  match ps:
    case Nil{}:
      Group.fin(st)
    case p <> t:
      Group.go(t, Group.step(p, st))

def Chunk.fin(e: Enc, +rank: U32, +color: U32, +alpha: U32) -> Chunk:
  match e:
    case Enc{rev, _, _, +h}:
      Chunk{U32.xor(h, rank), Rank.layer(rank), color, alpha, Rank.mode(rank), Rank.width(rank), rev}

def Chunk.look(l: U32 & U32, +rank: U32, e: Enc) -> Chunk:
  (+color, +alpha) = l
  Chunk.fin(e, rank, color, alpha)

def Chunk.of(g: Group, +kind: U32) -> Chunk:
  match g:
    case Group{_, +rank, ps}:
      Chunk.look(LO.Look.of(kind, Rank.layer(rank)), rank, Enc.pieces(ps, Rank.mode(rank), Enc{SNil{}, 0, 0, 2166136261}))

# Parallel encoding
# -----------------
# Groups are dealt alternately into two hands, as board.bend deals forms,
# so halves cost about the same; each chunk keeps its group's number and
# the plot is put back in order after.

type Ix is Data:
  Ix{i: Nat, c: Chunk}

def Ix.le(a: Ix, b: Ix) -> Bool:
  match a b:
    case Ix{x, _} Ix{y, _}:
      Nat.is_le(x, y)

def Ix.chunks(xs: List<&2, Ix>) -> List<&2, Chunk>:
  match xs:
    case Nil{}:
      Nil{}
    case Ix{_, c} <> t:
      c <> Ix.chunks(t)

def Group.deal(gs: List<&2, Group>, h: Hand) -> Hand:
  match gs h:
    case Nil{} _:
      h
    case g <> t Hand{a, b}:
      Group.deal(t, Hand{b, g <> a})

def Group.seq(gs: List<&2, Group>, +kind: U32, acc: List<&2, Ix>) -> List<&2, Ix>:
  match gs:
    case Nil{}:
      acc
    case Group{+i, rank, ps} <> t:
      Group.seq(t, kind, Ix{i, Chunk.of(Group{i, rank, ps}, kind)} <> acc)

def Group.split.k(h: Hand, k: List<&2, Group> -> List<&2, Group> -> List<&2, Ix>) -> List<&2, Ix>:
  match h:
    case Hand{a, b}:
      k(a, b)

def Group.par(d: Nat, gs: List<&2, Group>, +kind: U32) -> List<&2, Ix>:
  match d:
    case 0n:
      Group.seq(gs, kind, Nil{})
    case 1n+e0:
      +e = e0
      Group.split.k(Group.deal(gs, Hand{Nil{}, Nil{}}), a => b => (
        x y = Group.par(e, a, kind) Group.par(e, b, kind)
        List.append(&2, Ix, x, y)))

# Extent
# ------
# The box around every coordinate, in micrometres (signed), for the
# phone's first view.

type Box is Data:
  Box{x0: U32, y0: U32, x1: U32, y1: U32}

# signed order of two's complement numbers
def Box.lt(+a: U32, +b: U32) -> Bool:
  U32.is_lt(U32.xor(a, 2147483648), U32.xor(b, 2147483648))

def Box.pt(+x: U32, +y: U32, b: Box) -> Box:
  match b:
    case Box{+x0, +y0, +x1, +y1}:
      Box{Bool.pick(U32, Box.lt(x, x0), x, x0), Bool.pick(U32, Box.lt(y, y0), y, y0), Bool.pick(U32, Box.lt(x1, x), x, x1), Bool.pick(U32, Box.lt(y1, y), y, y1)}

def Box.ints(xs: List<&2, U32>, b: Box) -> Box:
  match xs:
    case +x <> +y <> t:
      Box.ints(t, Box.pt(x, y, b))
    case _:
      b

def Box.pieces(ps: List<&2, Piece>, b: Box) -> Box:
  match ps:
    case Nil{}:
      b
    case Piece{_, _, _, xs} <> t:
      Box.pieces(t, Box.ints(xs, b))

def Box.empty() -> Box:
  Box{2147483647, 2147483647, 2147483648, 2147483648}

# Sorting in parallel
# -------------------
# Items are dealt into 2^d hands; each hand becomes pieces and is sorted
# on its own core, and sorted hands merge pairwise on the way back.

type IHand is Data:
  IHand{a: List<&2, B.Item>, b: List<&2, B.Item>}

def Item.deal(its: List<&2, B.Item>, h: IHand) -> IHand:
  match its h:
    case Nil{} _:
      h
    case i <> t IHand{a, b}:
      Item.deal(t, IHand{b, i <> a})

def Piece.hle(xs: List<&2, Piece>, ys: List<&2, Piece>) -> Bool:
  match xs ys:
    case +x <> _ +y <> _:
      Piece.le(x, y)
    case _ _:
      True{}

# two sorted lists as one (backwards onto acc, then turned around); n
# bounds the steps, `le` is whether xs's head goes first
def Piece.merge(n: Nat, le: Bool, xs: List<&2, Piece>, ys: List<&2, Piece>, acc: List<&2, Piece>) -> List<&2, Piece>:
  match n le xs ys:
    case 1n+m True{} x <> +xt +ys2:
      Piece.merge(m, Piece.hle(xt, ys2), xt, ys2, x <> acc)
    case 1n+m False{} +xs2 y <> +yt:
      Piece.merge(m, Piece.hle(xs2, yt), xs2, yt, y <> acc)
    case _ _ Nil{} ys2:
      List.reverse.go(&2, Piece, acc, ys2)
    case _ _ xs2 Nil{}:
      List.reverse.go(&2, Piece, acc, xs2)
    case 0n _ xs2 ys2:
      List.reverse.go(&2, Piece, acc, List.append(&2, Piece, xs2, ys2))

def Piece.join(+xs: List<&2, Piece>, +ys: List<&2, Piece>) -> List<&2, Piece>:
  Piece.merge(Nat.add(List.length(&2, Piece, xs), List.length(&2, Piece, ys)), Piece.hle(xs, ys), xs, ys, Nil{})

def Piece.psort.k(h: IHand, k: List<&2, B.Item> -> List<&2, B.Item> -> List<&2, Piece>) -> List<&2, Piece>:
  match h:
    case IHand{a, b}:
      k(a, b)

def Piece.psort(d: Nat, its: List<&2, B.Item>, +kind: U32) -> List<&2, Piece>:
  match d:
    case 0n:
      List.sort(~Piece, ~Piece.le, Piece.of(its, kind))
    case 1n+e0:
      +e = e0
      Piece.psort.k(Item.deal(its, IHand{Nil{}, Nil{}}), a => b => (
        x y = Piece.psort(e, a, kind) Piece.psort(e, b, kind)
        Piece.join(x, y)))

# A plot
# ------

type Plot is Data:
  Plot{cs: List<&2, Chunk>, box: Box}

def Plot.of.k(+ps: List<&2, Piece>, +kind: U32) -> Plot:
  Plot{Ix.chunks(List.sort(~Ix, ~Ix.le, Group.par(6n, Group.go(ps, GS{0n, 0, Nil{}, Nil{}}), kind))), Box.pieces(ps, Box.empty())}

# the chunks of some items, in paint order, and their extent
def Plot.of(its: List<&2, B.Item>, +kind: U32) -> Plot:
  Plot.of.k(Piece.psort(5n, its, kind), kind)

def Plot.chunks(p: Plot) -> List<&2, Chunk>:
  match p:
    case Plot{cs, _}:
      cs

def Plot.box(p: Plot) -> Box:
  match p:
    case Plot{_, b}:
      b

# Deltas
# ------

# exact equality of chunks, the cheap fields first (unequal chunks almost
# always differ in sig and stop there)
def Eq.chunk.k(same: Bool, a: Chunk, b: Chunk) -> Bool:
  match same a b:
    case False{} _ _:
      False{}
    case True{} Chunk{_, l1, c1, a1, m1, w1, d1} Chunk{_, l2, c2, a2, m2, w2, d2}:
      Bool.and(U32.is_eq(l1, l2), Bool.and(U32.is_eq(c1, c2), Bool.and(U32.is_eq(a1, a2), Bool.and(U32.is_eq(m1, m2), Bool.and(U32.is_eq(w1, w2), Q.Eq.str(d1, d2))))))

def Eq.sig(a: Chunk, b: Chunk) -> Bool:
  match a b:
    case Chunk{s1, _, _, _, _, _, _} Chunk{s2, _, _, _, _, _, _}:
      U32.is_eq(s1, s2)

def Eq.chunk(+a: Chunk, +b: Chunk) -> Bool:
  match a b:
    case Chunk{+s1, l1, c1, a1, m1, w1, d1} Chunk{+s2, l2, c2, a2, m2, w2, d2}:
      Eq.chunk.k(U32.is_eq(s1, s2), Chunk{s1, l1, c1, a1, m1, w1, d1}, Chunk{s2, l2, c2, a2, m2, w2, d2})

# whether the first held chunk is c
def Plot.hit(os: List<&2, Chunk>, +c: Chunk) -> Bool:
  match os:
    case Nil{}:
      False{}
    case +o <> _:
      Eq.chunk(c, o)

def Ref.next(r: Ref) -> Ref:
  match r:
    case Keep{i}:
      Keep{1n+i}
    case Fresh{c}:
      Fresh{c}

# c as the phone gets it: the index of an equal chunk it holds, or itself
def Plot.find(os: List<&2, Chunk>, hit: Bool, +c: Chunk) -> Ref:
  match os hit:
    case Nil{} _:
      Fresh{c}
    case _ <> _ True{}:
      Keep{0n}
    case _ <> +ot False{}:
      Ref.next(Plot.find(ot, Plot.hit(ot, c), c))

# the plot `ns` for a phone holding `old`
def Plot.delta(ns: List<&2, Chunk>, +old: List<&2, Chunk>) -> List<&2, Ref>:
  match ns:
    case Nil{}:
      Nil{}
    case +n <> t:
      Plot.find(old, Plot.hit(old, n), n) <> Plot.delta(t, old)

def Chunk.none() -> Chunk:
  Chunk{0, 0, 0, 0, 0, 0, ""}

def Plot.at(i: Nat, os: List<&2, Chunk>) -> Chunk:
  match i os:
    case 0n o <> _:
      o
    case 1n+j _ <> ot:
      Plot.at(j, ot)
    case _ Nil{}:
      Chunk.none()

def Ref.get(r: Ref, +os: List<&2, Chunk>) -> Chunk:
  match r:
    case Keep{i}:
      Plot.at(i, os)
    case Fresh{c}:
      c

# what the phone does with a delta: the chunks it names, in order
def Plot.apply(rs: List<&2, Ref>, +old: List<&2, Chunk>) -> List<&2, Chunk>:
  match rs:
    case Nil{}:
      Nil{}
    case r <> t:
      Ref.get(r, old) <> Plot.apply(t, old)

def Ref.fresh(r: Ref) -> Nat:
  match r:
    case Keep{_}:
      0n
    case Fresh{_}:
      1n

# how many chunks go out whole (the only geometry on the air)
def Plot.fresh(rs: List<&2, Ref>) -> Nat:
  match rs:
    case Nil{}:
      0n
    case r <> t:
      Nat.add(Ref.fresh(r), Plot.fresh(t))

# whether a delta changes nothing for a phone holding n chunks (each kept
# where it was): then nothing is sent
def Plot.quiet(rs: List<&2, Ref>, +i: Nat, +n: Nat) -> Bool:
  match rs:
    case Nil{}:
      Nat.is_eq(i, n)
    case Keep{k} <> t:
      Bool.and(Nat.is_eq(k, i), Plot.quiet(t, 1n+i, n))
    case Fresh{_} <> _:
      False{}

# The message
# -----------
# {"t":"plot","key":…,"box":[x0,y0,x1,y1],"cs":[…]}: each of cs is a number
# (keep that chunk of the last plot) or {l,c,a,m,w,d}. Built back to front
# with tail calls only: a chunk's text goes in place in one pass (it is
# kept backwards), so a big board never deepens the stack.

# how every plot message begins: the hub sends plots as binary frames of
# this JSON text, not CBOR (a CBOR message begins with a map byte, never
# '{'), and the apps hand them to their viewers without Bend
def Plot.prefix() -> String:
  "{\"t\":\"plot\""

def Plot.is(+t: String) -> Bool:
  String.starts_with(t, Plot.prefix())

# s in front of acc, given s backwards
def Out.pre(rs: String, acc: String) -> String:
  String.reverse.go(rs, acc)

def Out.put(s: String, acc: String) -> String:
  Out.pre(String.reverse(s), acc)

def Out.int(+v: U32) -> String:
  Bool.pick(String, U32.is_ge(v, 2147483648), "-" ++ U32.show(U32.sub(0, v)), U32.show(v))

def Out.chunk(c: Chunk, acc: String) -> String:
  match c:
    case Chunk{_, l, co, a, m, w, d}:
      Out.put("{\"l\":" ++ U32.show(l) ++ ",\"c\":" ++ U32.show(co) ++ ",\"a\":" ++ U32.show(a) ++ ",\"m\":" ++ U32.show(m) ++ ",\"w\":" ++ U32.show(w) ++ ",\"d\":\"", Out.pre(d, Out.put("\"}", acc)))

def Out.ref(r: Ref, acc: String) -> String:
  match r:
    case Keep{i}:
      Out.put(Nat.show(i), acc)
    case Fresh{c}:
      Out.chunk(c, acc)

# the refs, given last first, in front of acc
def Out.refs(rs: List<&2, Ref>, last: Bool, acc: String) -> String:
  match rs:
    case Nil{}:
      acc
    case r <> t:
      Out.refs(t, False{}, Out.ref(r, Out.put(Bool.pick(String, last, "", ","), acc)))

def Out.box(b: Box) -> String:
  match b:
    case Box{x0, y0, x1, y1}:
      "[" ++ Out.int(x0) ++ "," ++ Out.int(y0) ++ "," ++ Out.int(x1) ++ "," ++ Out.int(y1) ++ "]"

# a plot for one phone
def Plot.msg(+key: String, b: Box, rs: List<&2, Ref>) -> String:
  Out.put("{\"t\":\"plot\",\"key\":" ++ J.Json.show(J.Str{key}) ++ ",\"box\":" ++ Out.box(b) ++ ",\"cs\":[", Out.refs(List.reverse(&2, Ref, rs), True{}, "]}"))

# Plots between processes
# ----------------------
# The hub reads each file in a child process (src/server/plot.bend: a
# fresh heap every time) that prints the plot as lines: "b" and the box,
# then "c" and each chunk's sig, layer, colour, alpha, mode and width, a
# space, and its text. Numbers are U32 decimals, the first right after its
# letter. Both ways use tail calls only.

def Line.chunks(cs: List<&2, Chunk>, acc: String) -> String:
  match cs:
    case Nil{}:
      acc
    case Chunk{s, l, c, a, m, w, d} <> t:
      Line.chunks(t, Out.put("c" ++ U32.show(s) ++ " " ++ U32.show(l) ++ " " ++ U32.show(c) ++ " " ++ U32.show(a) ++ " " ++ U32.show(m) ++ " " ++ U32.show(w) ++ " ", Out.pre(d, Out.put("\n", acc))))

def Line.box(b: Box) -> String:
  match b:
    case Box{x0, y0, x1, y1}:
      "b" ++ U32.show(x0) ++ " " ++ U32.show(y0) ++ " " ++ U32.show(x1) ++ " " ++ U32.show(y1) ++ "\n"

def Line.plot(p: Plot) -> String:
  match p:
    case Plot{cs, b}:
      Out.put(Line.box(b), Line.chunks(List.reverse(&2, Chunk, cs), ""))

# the scan's state: the line's letter (0 at a line's start), its numbers
# so far (backwards), the number being read, which field it is, the
# chunk's text (built backwards, as a chunk keeps it), and what is done
type Sc is Data:
  Sc{tag: U32, nums: List<&2, U32>, n: U32, f: U32, rev: String, cs: List<&2, Chunk>, box: Box}

def Scan.box(ns: List<&2, U32>, b: Box) -> Box:
  match ns:
    case y1 <> x1 <> y0 <> x0 <> _:
      Box{x0, y0, x1, y1}
    case _:
      b

def Scan.chunk(ns: List<&2, U32>, rev: String, cs: List<&2, Chunk>) -> List<&2, Chunk>:
  match ns:
    case w <> m <> a <> c <> l <> s <> _:
      Chunk{s, l, c, a, m, w, rev} <> cs
    case _:
      cs

def Scan.line.k(box: Bool, s: Sc) -> Sc:
  match box s:
    case True{} Sc{_, ns, +n, _, _, cs, b}:
      Sc{0, Nil{}, 0, 0, SNil{}, cs, Scan.box(n <> ns, b)}
    case False{} Sc{_, ns, _, _, rev, cs, b}:
      Sc{0, Nil{}, 0, 0, SNil{}, Scan.chunk(ns, rev, cs), b}

def Sc.tag(s: Sc) -> U32:
  match s:
    case Sc{t, _, _, _, _, _, _}:
      t

def Sc.f(s: Sc) -> U32:
  match s:
    case Sc{_, _, _, f, _, _, _}:
      f

def Scan.step.k(nl: Bool, start: Bool, text: Bool, sp: Bool, +c: U32, +s: Sc) -> Sc:
  match nl start text sp s:
    case True{} _ _ _ _:
      Scan.line.k(U32.is_eq(Sc.tag(s), 98), s)
    case False{} True{} _ _ Sc{_, ns, n, f, rev, cs, b}:
      Sc{c, ns, n, f, rev, cs, b}
    case False{} False{} True{} _ Sc{t, ns, n, f, rev, cs, b}:
      Sc{t, ns, n, f, SCon{Chr{c}, rev}, cs, b}
    case False{} False{} False{} True{} Sc{t, ns, +n, +f, rev, cs, b}:
      Sc{t, n <> ns, 0, (f + 1 : U32), rev, cs, b}
    case False{} False{} False{} False{} Sc{t, ns, +n, f, rev, cs, b}:
      Sc{t, ns, ((n * 10 : U32) + (c - 48 : U32) : U32), f, rev, cs, b}

def Scan.step(+c: U32, +s: Sc) -> Sc:
  Scan.step.k(U32.is_eq(c, 10), U32.is_eq(Sc.tag(s), 0), Bool.and(U32.is_eq(Sc.tag(s), 99), U32.is_ge(Sc.f(s), 6)), U32.is_eq(c, 32), c, s)

def Scan.go(t: String, s: Sc) -> Sc:
  match t:
    case SNil{}:
      s
    case SCon{Chr{+c}, rest}:
      Scan.go(rest, Scan.step(c, s))

def Scan.fin(s: Sc) -> Plot:
  match s:
    case Sc{_, _, _, _, _, cs, b}:
      Plot{List.reverse(&2, Chunk, cs), b}

# the plot a child printed (Line.plot)
def Scan.plot(t: String) -> Plot:
  Scan.fin(Scan.go(t, Sc{0, Nil{}, 0, 0, SNil{}, Nil{}, Box.empty()}))

# no plot for the source (yet): why, for the phone to show
def Plot.none(+key: String, +why: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"t", J.Str{"plot"}}, J.KV{"key", J.Str{key}}, J.KV{"none", J.Str{why}}]))
