import Base
import ../core/svg.bend as S
import ../core/cat.bend as C
import ./draw.bend as D
import ./raster.bend as R
import ./icon.bend as I

# Cats in the window: a posed cat (C.Cat.pose / C.Cat.pose.at) as draw
# ops. Outlines are anti-aliased segments with round ends; a fill under an
# outline (its own, or one drawn over it later) is an even-odd polygon,
# whose hard edge the outline covers. A bare fill (eyes, nose, markings)
# needs its own soft edge: on a small cat it is a coverage bitmap (as icons
# are made), on a large one a polygon with a faint one-pixel rim.

def CatG.p2(p: S.Pt, +x: F32, +y: F32, +s: F32) -> D.P2:
  match p:
    case S.Pt{+px, +py}:
      D.P2{F32.add(x, F32.mul(px, s)), F32.add(y, F32.mul(py, s))}

def CatG.p2s(ps: List<&2, S.Pt>, +x: F32, +y: F32, +s: F32) -> List<&2, D.P2>:
  match ps:
    case Nil{}:
      Nil{}
    case p <> t:
      CatG.p2(p, x, y, s) <> CatG.p2s(t, x, y, s)

def CatG.ring.edges(+ps: List<&2, D.P2>, acc: List<&2, R.Edge>) -> List<&2, R.Edge>:
  List.append(&2, R.Edge, D.Poly.edges(ps, D.Poly.first(ps)), acc)

# every ring's edges, and the box around them
type Fill is Data:
  Fill{es: List<&2, R.Edge>, box: D.Box}

def CatG.fill.ring(+ps: List<&2, D.P2>, f: Fill) -> Fill:
  match f:
    case Fill{es, b}:
      Fill{CatG.ring.edges(ps, es), D.Poly.box(ps, b)}

def CatG.fill.go(rs: List<&2, C.Ring>, +x: F32, +y: F32, +s: F32, f: Fill) -> Fill:
  match rs:
    case Nil{}:
      f
    case C.Ring{ps, _} <> t:
      CatG.fill.go(t, x, y, s, CatG.fill.ring(CatG.p2s(ps, x, y, s), f))

def CatG.fill.op(+c: D.Clip, f: Fill, +color: U32, +alpha: U32) -> R.Op:
  match f:
    case Fill{es, b}:
      D.Poly.op(c, b, es, color, alpha)

def CatG.fill(on: Bool, +rs: List<&2, C.Ring>, +c: D.Clip, +x: F32, +y: F32, +s: F32, +color: U32, +alpha: U32, rest: List<&2, R.Op>) -> List<&2, R.Op>:
  match on:
    case True{}:
      CatG.fill.op(c, CatG.fill.go(rs, x, y, s, Fill{Nil{}, D.Box{1000000.0, 1000000.0, F32.neg(1000000.0), F32.neg(1000000.0)}}), color, alpha) <> rest
    case False{}:
      rest

def CatG.close(closed: Bool, +ax: F32, +ay: F32, first: D.P2, +c: D.Clip, +w: F32, +color: U32, +alpha: U32, rest: List<&2, R.Op>) -> List<&2, R.Op>:
  match closed first:
    case True{} D.P2{+bx, +by}:
      D.Draw.seg(c, ax, ay, bx, by, w, color, alpha) <> rest
    case False{} _:
      rest

# a stroke's segments: point to point, then back to the first when closed
def CatG.segs(ps: List<&2, D.P2>, +first: D.P2, +closed: Bool, +c: D.Clip, +w: F32, +color: U32, +alpha: U32, rest: List<&2, R.Op>) -> List<&2, R.Op>:
  match ps:
    case Nil{}:
      rest
    case D.P2{+ax, +ay} <> Nil{}:
      CatG.close(closed, ax, ay, first, c, w, color, alpha, rest)
    case D.P2{+ax, +ay} <> D.P2{+bx, +by} <> t:
      D.Draw.seg(c, ax, ay, bx, by, w, color, alpha) <> CatG.segs(D.P2{bx, by} <> t, first, closed, c, w, color, alpha, rest)

def CatG.ring.segs(+ps: List<&2, D.P2>, +closed: Bool, +c: D.Clip, +w: F32, +color: U32, +alpha: U32, rest: List<&2, R.Op>) -> List<&2, R.Op>:
  CatG.segs(ps, D.Poly.first(ps), closed, c, w, color, alpha, rest)

def CatG.stroke.go(rs: List<&2, C.Ring>, +c: D.Clip, +x: F32, +y: F32, +s: F32, +w: F32, +color: U32, +alpha: U32, rest: List<&2, R.Op>) -> List<&2, R.Op>:
  match rs:
    case Nil{}:
      rest
    case C.Ring{ps, +closed} <> t:
      CatG.ring.segs(CatG.p2s(ps, x, y, s), closed, c, w, color, alpha, CatG.stroke.go(t, c, x, y, s, w, color, alpha, rest))

def CatG.stroke(on: Bool, +rs: List<&2, C.Ring>, +c: D.Clip, +x: F32, +y: F32, +s: F32, +w: F32, +color: U32, +alpha: U32, rest: List<&2, R.Op>) -> List<&2, R.Op>:
  match on:
    case True{}:
      CatG.stroke.go(rs, c, x, y, s, w, color, alpha, rest)
    case False{}:
      rest

# Coverage bitmaps
# ----------------

def CatM.close(close: Bool, +ax: F32, +ay: F32, first: D.P2, acc: List<&2, S.Ln>) -> List<&2, S.Ln>:
  match close first:
    case True{} D.P2{+bx, +by}:
      S.Ln{ax, ay, bx, by, False{}} <> acc
    case False{} _:
      acc

def CatM.lines(ps: List<&2, D.P2>, +first: D.P2, +close: Bool, acc: List<&2, S.Ln>) -> List<&2, S.Ln>:
  match ps:
    case Nil{}:
      acc
    case D.P2{+ax, +ay} <> Nil{}:
      CatM.close(close, ax, ay, first, acc)
    case D.P2{+ax, +ay} <> D.P2{+bx, +by} <> t:
      CatM.lines(D.P2{bx, by} <> t, first, close, S.Ln{ax, ay, bx, by, False{}} <> acc)

# the rings' lines in the bitmap's pixels; fill closes every ring, an
# outline only the closed ones
def CatM.ring.lines(+ps: List<&2, D.P2>, +close: Bool, acc: List<&2, S.Ln>) -> List<&2, S.Ln>:
  CatM.lines(ps, D.Poly.first(ps), close, acc)

def CatM.all(rs: List<&2, C.Ring>, +fill: Bool, +x: F32, +y: F32, +s: F32, acc: List<&2, S.Ln>) -> List<&2, S.Ln>:
  match rs:
    case Nil{}:
      acc
    case C.Ring{ps, +closed} <> t:
      CatM.all(t, fill, x, y, s, CatM.ring.lines(CatG.p2s(ps, x, y, s), Bool.or(fill, closed), acc))

def CatM.box(rs: List<&2, C.Ring>, b: D.Box) -> D.Box:
  match rs:
    case Nil{}:
      b
    case C.Ring{ps, _} <> t:
      CatM.box(t, D.Poly.box(CatG.p2s(ps, 0.0, 0.0, 1.0), b))

def CatM.depth(+n: U32) -> Nat:
  Bool.pick(Nat, U32.is_le(n, 1), 0n, 1n+U32.log2((n - 1 : U32)))

def CatM.meets(l: S.Ln, +ya: F32, +yb: F32) -> Bool:
  match l:
    case S.Ln{_, +ay, _, +by, _}:
      Bool.and(F32.is_ge(F32.max(ay, by), ya), F32.is_le(F32.min(ay, by), yb))

def CatM.keep.k(hit: Bool, l: S.Ln, rest: List<&2, S.Ln>) -> List<&2, S.Ln>:
  match hit:
    case True{}:
      l <> rest
    case False{}:
      rest

# the lines that reach the rows [ya, yb]
def CatM.keep(ls: List<&2, S.Ln>, +ya: F32, +yb: F32) -> List<&2, S.Ln>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      CatM.keep.k(CatM.meets(l, ya, yb), l, CatM.keep(t, ya, yb))

def CatM.cov.k(fill: Bool, +ls: List<&2, S.Ln>, +d: F32, +px: F32, +py: F32, +hw: F32) -> F32:
  match fill:
    case True{}:
      Bool.pick(F32, I.Ico.inside(ls, px, py, False{}), I.Ico.ramp(F32.add(0.5, d)), I.Ico.ramp(F32.sub(0.5, d)))
    case False{}:
      I.Ico.ramp(F32.sub(F32.add(hw, 0.5), d))

# the coverage (0..255) of pixel (x, y): inside the fill, or within hw of
# the outline, with a one-pixel ramp at the edge
def CatM.cov(+ls: List<&2, S.Ln>, +fill: Bool, +hw: F32, +x: U32, +y: U32) -> U32:
  +px = F32.add(U32.to_f32(x), 0.5)
  +py = F32.add(U32.to_f32(y), 0.5)
  F32.to_u32(F32.mul(CatM.cov.k(fill, ls, I.Ico.near(ls, px, py, 1000.0), px, py, hw), 255.0))

def CatM.px(+ls: List<&2, S.Ln>, +fill: Bool, +hw: F32, +w: U32, +n: U32, +i: U32) -> U32:
  Bool.pick(U32, U32.is_lt(i, n), CatM.cov(ls, fill, hw, U32.mod(i, w), U32.div(i, w)), 0)

def CatM.word(+ls: List<&2, S.Ln>, +fill: Bool, +hw: F32, +w: U32, +n: U32, +i: U32) -> U32:
  +p = U32.shln(i, 2n)
  U32.or(U32.or(CatM.px(ls, fill, hw, w, n, p), U32.shln(CatM.px(ls, fill, hw, w, n, (p + 1 : U32)), 8n)),
    U32.or(U32.shln(CatM.px(ls, fill, hw, w, n, (p + 2 : U32)), 16n), U32.shln(CatM.px(ls, fill, hw, w, n, (p + 3 : U32)), 24n)))

# words [i, i + 2^d) as a mask tree; each level keeps only the lines
# within reach (m) of its rows, so a pixel looks at the few lines near its
# row, not the whole part. Halves big enough to be worth it (par) render at
# once.
def CatM.tree(d: Nat, par: Bool, +ls: List<&2, S.Ln>, +fill: Bool, +hw: F32, +m: F32, +w: U32, +n: U32, +i: U32) -> R.Mask:
  match d par:
    case 0n _:
      R.MWord{CatM.word(ls, fill, hw, w, n, i)}
    case 1n+e0 True{}:
      +e = e0
      +r0 = U32.to_f32(U32.div(U32.shln(i, 2n), w))
      +r1 = U32.to_f32(U32.div((U32.shln((i + U32.shln(1, 1n+e) : U32), 2n) - 1 : U32), w))
      +ks = CatM.keep(ls, F32.sub(r0, m), F32.add(F32.add(r1, 1.0), m))
      lo hi = CatM.tree(e, Nat.is_ge(e, 5n), ks, fill, hw, m, w, n, i) CatM.tree(e, Nat.is_ge(e, 5n), ks, fill, hw, m, w, n, (i + U32.shln(1, e) : U32))
      R.MPair{lo, hi}
    case 1n+e0 False{}:
      +e = e0
      +r0 = U32.to_f32(U32.div(U32.shln(i, 2n), w))
      +r1 = U32.to_f32(U32.div((U32.shln((i + U32.shln(1, 1n+e) : U32), 2n) - 1 : U32), w))
      +ks = CatM.keep(ls, F32.sub(r0, m), F32.add(F32.add(r1, 1.0), m))
      R.MPair{CatM.tree(e, False{}, ks, fill, hw, m, w, n, i), CatM.tree(e, False{}, ks, fill, hw, m, w, n, (i + U32.shln(1, e) : U32))}

# one coverage bitmap at (gx, gy), w x h
def CatM.op(+c: D.Clip, +gx: U32, +gy: U32, +w: U32, +h: U32, +ls: List<&2, S.Ln>, +fill: Bool, +hw: F32, +color: U32, +alpha: U32) -> R.Op:
  +n = (w * h : U32)
  +d = CatM.depth(((n + 3 : U32) / 4 : U32))
  D.Clip.cut(c, gx, gy, (gx + w : U32), (gy + h : U32), color, alpha, R.SMask{gx, gy, w, d, CatM.tree(d, Nat.is_ge(d, 5n), ls, fill, hw, F32.add(hw, 1.0), w, n, 0)})

# the part's box in pixels, grown by m
def CatM.at(b: D.Box, +rs: List<&2, C.Ring>, +stroke: Bool, +x: F32, +y: F32, +s: F32, +m: F32, +hw: F32, +c: D.Clip, +color: U32, +alpha: U32) -> R.Op:
  match b:
    case D.Box{+x0, +y0, +x1, +y1}:
      +gx = D.Draw.floor(F32.sub(F32.add(x, F32.mul(x0, s)), m))
      +gy = D.Draw.floor(F32.sub(F32.add(y, F32.mul(y0, s)), m))
      +w = (D.Draw.ceil(F32.add(F32.add(x, F32.mul(x1, s)), m)) - gx : U32)
      +h = (D.Draw.ceil(F32.add(F32.add(y, F32.mul(y1, s)), m)) - gy : U32)
      +ox = F32.sub(x, U32.to_f32(gx))
      +oy = F32.sub(y, U32.to_f32(gy))
      +ls = CatM.all(rs, Bool.not(stroke), ox, oy, s, Nil{})
      CatM.op(c, gx, gy, w, h, ls, Bool.not(stroke), hw, color, alpha)

def CatM.part(on: Bool, +rs: List<&2, C.Ring>, +stroke: Bool, +x: F32, +y: F32, +s: F32, +hw: F32, +c: D.Clip, +color: U32, +alpha: U32, rest: List<&2, R.Op>) -> List<&2, R.Op>:
  match on:
    case True{}:
      CatM.at(CatM.box(rs, D.Box{1000000.0, 1000000.0, F32.neg(1000000.0), F32.neg(1000000.0)}), rs, stroke, x, y, s, F32.add(hw, 1.5), hw, c, color, alpha) <> rest
    case False{}:
      rest

# Shapes
# -------

# a bare fill: a coverage bitmap (small), or a polygon with a rim of up to
# half strength in its own colour (large)
def CatG.bare(small: Bool, +rs: List<&2, C.Ring>, +c: D.Clip, +x: F32, +y: F32, +s: F32, +color: U32, +alpha: U32, rest: List<&2, R.Op>) -> List<&2, R.Op>:
  match small:
    case True{}:
      CatM.part(True{}, rs, False{}, x, y, s, 0.0, c, color, alpha, rest)
    case False{}:
      +ra = F32.to_u32(F32.mul(U32.to_f32(alpha), F32.clamp(F32.sub(s, 0.45), 0.0, 0.5)))
      CatG.stroke(Bool.and(U32.is_ge(ra, 24), U32.is_ge(alpha, 255)), rs, c, x, y, s, 1.0, color, ra, CatG.fill(True{}, rs, c, x, y, s, color, alpha, rest))

def CatG.body(bare: Bool, +small: Bool, +rs: List<&2, C.Ring>, +c: D.Clip, +x: F32, +y: F32, +s: F32, +color: U32, +alpha: U32, rest: List<&2, R.Op>) -> List<&2, R.Op>:
  match bare:
    case True{}:
      CatG.bare(small, rs, c, x, y, s, color, alpha, rest)
    case False{}:
      CatG.fill(True{}, rs, c, x, y, s, color, alpha, rest)

def CatG.fills(on: Bool, +bare: Bool, +small: Bool, +rs: List<&2, C.Ring>, +c: D.Clip, +x: F32, +y: F32, +s: F32, +color: U32, +alpha: U32, rest: List<&2, R.Op>) -> List<&2, R.Op>:
  match on:
    case True{}:
      CatG.body(bare, small, rs, c, x, y, s, color, alpha, rest)
    case False{}:
      rest

# a shape's ops, topmost first (its outline over its fill), onto rest; an
# outline thinner than a pixel is drawn one pixel wide and as much fainter
def CatG.shape(sh: C.Shape, +small: Bool, +c: D.Clip, +x: F32, +y: F32, +s: F32, rest: List<&2, R.Op>) -> List<&2, R.Op>:
  match sh:
    case C.Shape{+fill, +line, +lw, +alpha, +rim, +rs}:
      +w = F32.mul(lw, s)
      +la = F32.to_u32(F32.mul(U32.to_f32(alpha), F32.min(w, 1.0)))
      CatG.stroke(Bool.and(U32.is_ge(la, 24), U32.is_lt(line, C.Cat.none())), rs, c, x, y, s, w, line, la,
        CatG.fills(Bool.and(U32.is_gt(alpha, 0), U32.is_lt(fill, C.Cat.none())), rim, small, rs, c, x, y, s, fill, alpha, rest))

def CatG.go(shs: List<&2, C.Shape>, +small: Bool, +c: D.Clip, +x: F32, +y: F32, +s: F32, acc: List<&2, R.Op>) -> List<&2, R.Op>:
  match shs:
    case Nil{}:
      acc
    case sh <> t:
      CatG.go(t, small, c, x, y, s, CatG.shape(sh, small, c, x, y, s, acc))

# the size up to which bare fills are coverage bitmaps
def Cat.small() -> F32:
  64.0

# draw ops (topmost first) for a posed cat of px x px pixels with its box's
# top-left at (x, y)
def Cat.ops(shapes: List<&2, C.Shape>, +clip: D.Clip, +x: F32, +y: F32, +px: F32) -> List<&2, R.Op>:
  CatG.go(shapes, F32.is_le(px, Cat.small()), clip, x, y, F32.div(px, 64.0), Nil{})
