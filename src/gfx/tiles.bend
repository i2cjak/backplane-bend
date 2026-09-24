import Base
import ./raster.bend as R
import ./font.bend as F
import ../core/eq.bend as Q

# Frames drawn again only where they changed. A frame is a tree of tiles;
# each tile keeps the ops that reached it, the base image under it, and
# the image they made. The next frame walks the same tree: a tile whose
# ops and base are exactly the same keeps its image, any other is drawn
# again. Laws tiles_again_exact and frame_again_exact (the result is the
# frame drawn from scratch) and tile_keep (an unchanged tile is not drawn
# again) hold this to account.

# Exact equality
# --------------
# Structural, bit for bit (floats by their bits): true only for equal
# values (laws eq_*_sound), so a reused tile is never a stale one.

def Eq.f32(a: F32, b: F32) -> Bool:
  match a b:
    case F32{x} F32{y}:
      U32.is_eq(U32{x}, U32{y})

def Eq.edge(a: R.Edge, b: R.Edge) -> Bool:
  match a b:
    case R.Edge{a0, a1, a2, a3} R.Edge{b0, b1, b2, b3}:
      Bool.and(Eq.f32(a0, b0), Bool.and(Eq.f32(a1, b1), Bool.and(Eq.f32(a2, b2), Eq.f32(a3, b3))))

def Eq.edges(xs: List<&2, R.Edge>, ys: List<&2, R.Edge>) -> Bool:
  match xs ys:
    case Nil{} Nil{}:
      True{}
    case x <> xt y <> yt:
      Bool.and(Eq.edge(x, y), Eq.edges(xt, yt))
    case _ _:
      False{}

def Eq.mask(a: R.Mask, b: R.Mask) -> Bool:
  match a b:
    case R.MWord{x} R.MWord{y}:
      U32.is_eq(x, y)
    case R.MPair{al, ah} R.MPair{bl, bh}:
      Bool.and(Eq.mask(al, bl), Eq.mask(ah, bh))
    case _ _:
      False{}

def Eq.glyph(a: F.Glyph, b: F.Glyph) -> Bool:
  match a b:
    case F.Glyph{a0, a1, a2, a3} F.Glyph{b0, b1, b2, b3}:
      Bool.and(U32.is_eq(a0, b0), Bool.and(U32.is_eq(a1, b1), Bool.and(U32.is_eq(a2, b2), U32.is_eq(a3, b3))))

def Eq.shape(a: R.Shape, b: R.Shape) -> Bool:
  match a b:
    case R.SRect{} R.SRect{}:
      True{}
    case R.SPoly{ai, ae} R.SPoly{bi, be}:
      Bool.and(Q.Eq.bool(ai, bi), Eq.edges(ae, be))
    case R.SGlyph{ax, ay, ag} R.SGlyph{bx, by, bg}:
      Bool.and(U32.is_eq(ax, bx), Bool.and(U32.is_eq(ay, by), Eq.glyph(ag, bg)))
    case R.SSeg{a0, a1, a2, a3, a4} R.SSeg{b0, b1, b2, b3, b4}:
      Bool.and(Eq.f32(a0, b0), Bool.and(Eq.f32(a1, b1), Bool.and(Eq.f32(a2, b2), Bool.and(Eq.f32(a3, b3), Eq.f32(a4, b4)))))
    case R.SDisc{a0, a1, a2} R.SDisc{b0, b1, b2}:
      Bool.and(Eq.f32(a0, b0), Bool.and(Eq.f32(a1, b1), Eq.f32(a2, b2)))
    case R.STri{a0, a1, a2, a3, a4, a5} R.STri{b0, b1, b2, b3, b4, b5}:
      Bool.and(Eq.f32(a0, b0), Bool.and(Eq.f32(a1, b1), Bool.and(Eq.f32(a2, b2), Bool.and(Eq.f32(a3, b3), Bool.and(Eq.f32(a4, b4), Eq.f32(a5, b5))))))
    case R.SMask{ax, ay, aw, ad, am} R.SMask{bx, by, bw, bd, bm}:
      Bool.and(U32.is_eq(ax, bx), Bool.and(U32.is_eq(ay, by), Bool.and(U32.is_eq(aw, bw), Bool.and(Nat.is_eq(ad, bd), Eq.mask(am, bm)))))
    case _ _:
      False{}

def Eq.op(a: R.Op, b: R.Op) -> Bool:
  match a b:
    case R.Op{a0, a1, a2, a3, ac, aa, as} R.Op{b0, b1, b2, b3, bc, ba, bs}:
      Bool.and(U32.is_eq(a0, b0), Bool.and(U32.is_eq(a1, b1), Bool.and(U32.is_eq(a2, b2), Bool.and(U32.is_eq(a3, b3),
        Bool.and(U32.is_eq(ac, bc), Bool.and(U32.is_eq(aa, ba), Eq.shape(as, bs)))))))

def Eq.ops(xs: List<&2, R.Op>, ys: List<&2, R.Op>) -> Bool:
  match xs ys:
    case Nil{} Nil{}:
      True{}
    case x <> xt y <> yt:
      Bool.and(Eq.op(x, y), Eq.ops(xt, yt))
    case _ _:
      False{}

def Eq.image(a: Image, b: Image) -> Bool:
  match a b:
    case Pix{x} Pix{y}:
      U32.is_eq(x, y)
    case Qua{a0, a1, a2, a3} Qua{b0, b1, b2, b3}:
      Bool.and(Eq.image(a0, b0), Bool.and(Eq.image(a1, b1), Bool.and(Eq.image(a2, b2), Eq.image(a3, b3))))
    case _ _:
      False{}

# Tiles
# -----
# A tile is drawn in its own coordinates: its ops moved so its corner is
# (0, 0). Two tiles with the same local ops over the same base are the
# same image wherever they sit, so when the view scrolls by whole tiles a
# tile takes the image the last frame drew one scroll step away.

# Local ops
# ---------

def Loc.f(+v: F32, +o: F32) -> F32:
  F32.sub(v, o)

def Loc.edge(e: R.Edge, +fx: F32, +fy: F32) -> R.Edge:
  match e:
    case R.Edge{ax, ay, bx, by}:
      R.Edge{Loc.f(ax, fx), Loc.f(ay, fy), Loc.f(bx, fx), Loc.f(by, fy)}

def Loc.edges(es: List<&2, R.Edge>, +fx: F32, +fy: F32) -> List<&2, R.Edge>:
  match es:
    case Nil{}:
      Nil{}
    case e <> t:
      Loc.edge(e, fx, fy) <> Loc.edges(t, fx, fy)

# glyph corners wrap below 0: pixel lookups subtract them again, modulo
# 2^32, so they land on the same bits
def Loc.shape(s: R.Shape, +ox: U32, +oy: U32) -> R.Shape:
  match s:
    case R.SRect{}:
      R.SRect{}
    case R.SPoly{i, es}:
      R.SPoly{i, Loc.edges(es, U32.to_f32(ox), U32.to_f32(oy))}
    case R.SGlyph{gx, gy, g}:
      R.SGlyph{(gx - ox : U32), (gy - oy : U32), g}
    case R.SSeg{ax, ay, bx, by, hw}:
      R.SSeg{Loc.f(ax, U32.to_f32(ox)), Loc.f(ay, U32.to_f32(oy)), Loc.f(bx, U32.to_f32(ox)), Loc.f(by, U32.to_f32(oy)), hw}
    case R.SDisc{cx, cy, r}:
      R.SDisc{Loc.f(cx, U32.to_f32(ox)), Loc.f(cy, U32.to_f32(oy)), r}
    case R.STri{ax, ay, bx, by, cx, cy}:
      R.STri{Loc.f(ax, U32.to_f32(ox)), Loc.f(ay, U32.to_f32(oy)), Loc.f(bx, U32.to_f32(ox)), Loc.f(by, U32.to_f32(oy)), Loc.f(cx, U32.to_f32(ox)), Loc.f(cy, U32.to_f32(oy))}
    case R.SMask{gx, gy, w, d, m}:
      R.SMask{(gx - ox : U32), (gy - oy : U32), w, d, m}

# a box edge cut to [o, o + n], from o
def Loc.lo(+v: U32, +o: U32, +n: U32) -> U32:
  (U32.min(U32.max(v, o), (o + n : U32)) - o : U32)

def Loc.op(o: R.Op, +ox: U32, +oy: U32, +n: U32) -> R.Op:
  match o:
    case R.Op{x0, y0, x1, y1, c, a, s}:
      R.Op{Loc.lo(x0, ox, n), Loc.lo(y0, oy, n), Loc.lo(x1, ox, n), Loc.lo(y1, oy, n), c, a, Loc.shape(s, ox, oy)}

# the ops of the n x n tile at (ox, oy), in its own coordinates
def Loc.ops(ops: List<&2, R.Op>, +ox: U32, +oy: U32, +n: U32) -> List<&2, R.Op>:
  match ops:
    case Nil{}:
      Nil{}
    case o <> t:
      Loc.op(o, ox, oy, n) <> Loc.ops(t, ox, oy, n)

# Tiles
# -----

# ops as they reach the tile, the same in its own coordinates, the base
# under it and the image
type Tile is Data:
  Tile{ops: List<&2, R.Op>, loc: List<&2, R.Op>, base: Image, img: Image}

type Tiles is Data:
  TLeaf{t: Tile}
  TNode{a: Tiles, b: Tiles, c: Tiles, d: Tiles}

# the last frame's tiles (k levels over tiles, n wide from (0, 0)) and how
# far its content moved down since, modulo 2^32 (0: not at all)
type Past is Data:
  Past{k: Nat, t: Tiles, n: U32, dy: U32}

# quadrant i (0 top-left, 1 top-right, 2 bottom-left, 3 bottom-right) of
# an image (a solid one is solid in each)
def Img.q(img: Image, i: Nat) -> Image:
  match img i:
    case Pix{c} _:
      Pix{c}
    case Qua{a, _, _, _} 0n:
      a
    case Qua{_, b, _, _} 1n:
      b
    case Qua{_, _, c, _} 2n:
      c
    case Qua{_, _, _, d} _:
      d

def Tile.size(+e: Nat) -> U32:
  U32.shln(1, e)

# a 2^e tile of local ops over base
def Tile.draw(+e: Nat, +l: List<&2, R.Op>, +base: Image) -> Image:
  R.Region.node(e, R.Region.leaf(l, 0, 0, Tile.size(e)), l, 0, 0, Tile.size(e), base)

def Tile.of(+e: Nat, +ops: List<&2, R.Op>, +l: List<&2, R.Op>, +base: Image) -> Tile:
  Tile{ops, l, base, Tile.draw(e, l, base)}

# the tile at (rx, ry), 2^e wide, drawn from scratch
def Tile.make(+e: Nat, +ops: List<&2, R.Op>, +base: Image, +rx: U32, +ry: U32, +n: U32) -> Tile:
  Tile.of(e, ops, Loc.ops(ops, rx, ry, Tile.size(e)), base)

def Tiles.pick(right: Bool, down: Bool, a: Tiles, b: Tiles, c: Tiles, d: Tiles) -> Tiles:
  match right down:
    case False{} False{}:
      a
    case True{} False{}:
      b
    case False{} True{}:
      c
    case True{} True{}:
      d

def Tiles.seek.k(same: Bool, img: Image, +e: Nat, +l: List<&2, R.Op>, +base: Image) -> Image:
  match same:
    case True{}:
      img
    case False{}:
      Tile.draw(e, l, base)

def Tiles.seek.leaf(t: Tile, +e: Nat, +l: List<&2, R.Op>, +base: Image) -> Image:
  match t:
    case Tile{_, +o, +b, i}:
      Tiles.seek.k(Bool.and(Eq.ops(o, l), Eq.image(b, base)), i, e, l, base)

# the image of a tile of local ops l over base: the one the old tile at
# (x, y) holds when it drew the same, else drawn (law seek_made)
def Tiles.seek(k: Nat, t: Tiles, +x: U32, +y: U32, +rx: U32, +ry: U32, +n: U32, +e: Nat, +l: List<&2, R.Op>, +base: Image) -> Image:
  match k t:
    case 0n TLeaf{tl}:
      Tiles.seek.leaf(tl, e, l, base)
    case 1n+j0 TNode{a, b, c, d}:
      +j = j0
      Tiles.seek(j, Tiles.pick(U32.is_ge(x, (rx + U32.shr(n) : U32)), U32.is_ge(y, (ry + U32.shr(n) : U32)), a, b, c, d), x, y,
        Bool.pick(U32, U32.is_ge(x, (rx + U32.shr(n) : U32)), (rx + U32.shr(n) : U32), rx), Bool.pick(U32, U32.is_ge(y, (ry + U32.shr(n) : U32)), (ry + U32.shr(n) : U32), ry), U32.shr(n), e, l, base)
    case _ _:
      Tile.draw(e, l, base)

def Tile.fresh.k(look: Bool, +e: Nat, +ops: List<&2, R.Op>, +l: List<&2, R.Op>, +base: Image, p: Past, +rx: U32, +ry: U32) -> Tile:
  match look p:
    case True{} Past{pk, pt, pn, dy}:
      Tile{ops, l, base, Tiles.seek(pk, pt, rx, (ry - dy : U32), 0, 0, pn, e, l, base)}
    case False{} _:
      Tile{ops, l, base, Tile.draw(e, l, base)}

# a changed tile: when the view moved, the old tile its content came from
# may hold it already
def Tile.fresh(+e: Nat, +ops: List<&2, R.Op>, +l: List<&2, R.Op>, +base: Image, p: Past, +rx: U32, +ry: U32) -> Tile:
  match p:
    case Past{pk, pt, pn, +dy}:
      Tile.fresh.k(U32.is_ne(dy, 0), e, ops, l, base, Past{pk, pt, pn, dy}, rx, ry)

def Tile.again.k(same: Bool, +e: Nat, +ops: List<&2, R.Op>, +base: Image, t: Tile, p: Past, +rx: U32, +ry: U32, +n: U32) -> Tile:
  match same:
    case True{}:
      t
    case False{}:
      Tile.fresh(e, ops, Loc.ops(ops, rx, ry, Tile.size(e)), base, p, rx, ry)

# the same ops over the same base keep the tile; else it is drawn again
# (or found where the view moved it from)
def Tile.again(+e: Nat, +ops: List<&2, R.Op>, +base: Image, t: Tile, p: Past, +rx: U32, +ry: U32, +n: U32) -> Tile:
  match t:
    case Tile{+o, l, +b, i}:
      Tile.again.k(Bool.and(Eq.ops(ops, o), Eq.image(base, b)), e, ops, base, Tile{o, l, b, i}, p, rx, ry, n)

# the n x n region at (rx, ry) as tiles k levels down; each tile is 2^e
# wide. ops reach each child as Region.keep cuts them (the parent's
# corner is the region's own)
def Tiles.make(k: Nat, +e: Nat, +ops: List<&2, R.Op>, +base: Image, +rx: U32, +ry: U32, +n: U32) -> Tiles:
  match k:
    case 0n:
      TLeaf{Tile.make(e, ops, base, rx, ry, n)}
    case 1n+j0:
      +j = j0
      # the four quadrants at once (a first frame, or one after a resize)
      a b c d = Tiles.make(j, e, R.Region.keep(ops, rx, ry, rx, ry, U32.shr(n)), Img.q(base, 0n), rx, ry, U32.shr(n)) Tiles.make(j, e, R.Region.keep(ops, rx, ry, (rx + U32.shr(n) : U32), ry, U32.shr(n)), Img.q(base, 1n), (rx + U32.shr(n) : U32), ry, U32.shr(n)) Tiles.make(j, e, R.Region.keep(ops, rx, ry, rx, (ry + U32.shr(n) : U32), U32.shr(n)), Img.q(base, 2n), rx, (ry + U32.shr(n) : U32), U32.shr(n)) Tiles.make(j, e, R.Region.keep(ops, rx, ry, (rx + U32.shr(n) : U32), (ry + U32.shr(n) : U32), U32.shr(n)), Img.q(base, 3n), (rx + U32.shr(n) : U32), (ry + U32.shr(n) : U32), U32.shr(n))
      TNode{a, b, c, d}

def Tiles.node(a: Tiles, b: Tiles, c: Tiles, d: Tiles) -> Tiles:
  TNode{a, b, c, d}

# the next frame over the last one's tiles: unchanged tiles are kept, the
# rest drawn again or taken from the past; the four quadrants run at once
def Tiles.again(+k: Nat, +e: Nat, +ops: List<&2, R.Op>, +base: Image, prev: Tiles, +p: Past, +rx: U32, +ry: U32, +n: U32) -> Tiles:
  match k prev:
    case 0n TLeaf{t}:
      TLeaf{Tile.again(e, ops, base, t, p, rx, ry, n)}
    case 1n+j0 TNode{pa, pb, pc, pd}:
      +j = j0
      a b c d = Tiles.again(j, e, R.Region.keep(ops, rx, ry, rx, ry, U32.shr(n)), Img.q(base, 0n), pa, p, rx, ry, U32.shr(n)) Tiles.again(j, e, R.Region.keep(ops, rx, ry, (rx + U32.shr(n) : U32), ry, U32.shr(n)), Img.q(base, 1n), pb, p, (rx + U32.shr(n) : U32), ry, U32.shr(n)) Tiles.again(j, e, R.Region.keep(ops, rx, ry, rx, (ry + U32.shr(n) : U32), U32.shr(n)), Img.q(base, 2n), pc, p, rx, (ry + U32.shr(n) : U32), U32.shr(n)) Tiles.again(j, e, R.Region.keep(ops, rx, ry, (rx + U32.shr(n) : U32), (ry + U32.shr(n) : U32), U32.shr(n)), Img.q(base, 3n), pd, p, (rx + U32.shr(n) : U32), (ry + U32.shr(n) : U32), U32.shr(n))
      Tiles.node(a, b, c, d)
    case _ _:
      Tiles.make(k, e, ops, base, rx, ry, n)

# the frame the tiles make
def Tiles.image(t: Tiles) -> Image:
  match t:
    case TLeaf{Tile{_, _, _, i}}:
      i
    case TNode{a, b, c, d}:
      Qua{Tiles.image(a), Tiles.image(b), Tiles.image(c), Tiles.image(d)}

# Frames
# ------

# tiles are 2^6 = 64 pixels wide (32 cut a 1400 x 900 frame into so many
# that comparing them cost more than the redraws they saved)
def Frame.tile() -> Nat:
  6n

# a frame's tiles and the size they cover (none yet: an empty cache)
type Frames is Data:
  FNone{}
  FSome{w: U32, h: U32, tiles: Tiles}

# levels from the root to the tiles, for a w x h frame
def Frame.levels(+w: U32, +h: U32) -> Nat:
  Nat.sub(R.Frame.depth(w, h), Frame.tile())

def Frame.edge(+w: U32, +h: U32) -> Nat:
  Nat.sub(R.Frame.depth(w, h), Frame.levels(w, h))

def Frame.make(+w: U32, +h: U32, +ops: List<&2, R.Op>, +base: Image) -> Tiles:
  Tiles.make(Frame.levels(w, h), Frame.edge(w, h), ops, base, 0, 0, U32.shln(1, R.Frame.depth(w, h)))

def Frame.again.k(same: Bool, +w: U32, +h: U32, +ops: List<&2, R.Op>, +base: Image, +prev: Tiles, +dy: U32) -> Tiles:
  match same:
    case True{}:
      Tiles.again(Frame.levels(w, h), Frame.edge(w, h), ops, base, prev, Past{Frame.levels(w, h), prev, U32.shln(1, R.Frame.depth(w, h)), dy}, 0, 0, U32.shln(1, R.Frame.depth(w, h)))
    case False{}:
      Frame.make(w, h, ops, base)

# a w x h frame of ops (topmost first) over base, reusing the last frame's
# tiles when it had the same size; dy is how far the content moved down
# since (a hint: tiles are only taken when they drew exactly the same)
def Frame.again(+w: U32, +h: U32, +ops: List<&2, R.Op>, +base: Image, prev: Frames, +dy: U32) -> Tiles:
  match prev:
    case FNone{}:
      Frame.make(w, h, ops, base)
    case FSome{pw, ph, t}:
      Frame.again.k(Bool.and(U32.is_eq(pw, w), U32.is_eq(ph, h)), w, h, ops, base, t, dy)
