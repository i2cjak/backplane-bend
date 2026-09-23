import Base
import ./font.bend as F

# Draw ops to an Image quadtree. Ops are kept topmost first. A region with
# no ops is one Pix of the background; a region fully under a topmost
# opaque rectangle is one Pix of its colour; anything else splits in four,
# each quadrant keeping only the ops that reach it, and the four render at
# once. So a quiet frame costs little, and the cost of a busy one spreads
# over every core.

# Colours are 0xRRGGBB; alpha is 0..255.

type Shape is Data:
  SRect{}
  SGlyph{gx: U32, gy: U32, glyph: F.Glyph}
  SSeg{ax: F32, ay: F32, bx: F32, by: F32, hw: F32}
  SDisc{cx: F32, cy: F32, r: F32}
  STri{ax: F32, ay: F32, bx: F32, by: F32, cx: F32, cy: F32}

# an op's box [x0, x1) x [y0, y1) is its shape's extent cut to its clip
type Op is Data:
  Op{x0: U32, y0: U32, x1: U32, y1: U32, color: U32, alpha: U32, shape: Shape}

# Colour
# ------

def Rgb.ch(+c: U32, +s: Nat) -> U32:
  U32.and(U32.shrn(c, s), 255)

def Rgb.mix.ch(+a: U32, +b: U32, +t: U32) -> U32:
  (((a * t : U32) + (b * (255 - t : U32) : U32) : U32) / 255 : U32)

# fg over bg with opacity t
def Rgb.mix(+fg: U32, +bg: U32, +t: U32) -> U32:
  U32.or(U32.shln(Rgb.mix.ch(Rgb.ch(fg, 16n), Rgb.ch(bg, 16n), t), 16n),
    U32.or(U32.shln(Rgb.mix.ch(Rgb.ch(fg, 8n), Rgb.ch(bg, 8n), t), 8n), Rgb.mix.ch(Rgb.ch(fg, 0n), Rgb.ch(bg, 0n), t)))

# Coverage
# --------

def Cov.clamp(+x: F32) -> U32:
  F32.to_u32(F32.mul(F32.clamp(x, 0.0, 1.0), 255.0))

# distance from p to segment ab, as coverage of a line hw wide on each side
def Cov.seg(+ax: F32, +ay: F32, +bx: F32, +by: F32, +hw: F32, +px: F32, +py: F32) -> U32:
  +dx = F32.sub(bx, ax)
  +dy = F32.sub(by, ay)
  +ll = F32.add(F32.mul(dx, dx), F32.mul(dy, dy))
  +t = Bool.pick(F32, F32.is_le(ll, 0.0), 0.0, F32.clamp(F32.div(F32.add(F32.mul(F32.sub(px, ax), dx), F32.mul(F32.sub(py, ay), dy)), ll), 0.0, 1.0))
  Cov.clamp(F32.sub(F32.add(hw, 0.5), F32.hypot(F32.sub(px, F32.add(ax, F32.mul(t, dx))), F32.sub(py, F32.add(ay, F32.mul(t, dy))))))

def Cov.disc(+cx: F32, +cy: F32, +r: F32, +px: F32, +py: F32) -> U32:
  Cov.clamp(F32.sub(F32.add(r, 0.5), F32.hypot(F32.sub(px, cx), F32.sub(py, cy))))

def Cov.edge(+ax: F32, +ay: F32, +bx: F32, +by: F32, +px: F32, +py: F32) -> F32:
  F32.sub(F32.mul(F32.sub(bx, ax), F32.sub(py, ay)), F32.mul(F32.sub(by, ay), F32.sub(px, ax)))

def Cov.tri.k(+e0: F32, +e1: F32, +e2: F32) -> U32:
  +pos = Bool.and(F32.is_ge(e0, 0.0), Bool.and(F32.is_ge(e1, 0.0), F32.is_ge(e2, 0.0)))
  +neg = Bool.and(F32.is_le(e0, 0.0), Bool.and(F32.is_le(e1, 0.0), F32.is_le(e2, 0.0)))
  Bool.pick(U32, Bool.or(pos, neg), 255, 0)

def Cov.tri(+ax: F32, +ay: F32, +bx: F32, +by: F32, +cx: F32, +cy: F32, +px: F32, +py: F32) -> U32:
  Cov.tri.k(Cov.edge(ax, ay, bx, by, px, py), Cov.edge(bx, by, cx, cy, px, py), Cov.edge(cx, cy, ax, ay, px, py))

def Cov.glyph(g: F.Glyph, +gx: U32, +gy: U32, +x: U32, +y: U32) -> U32:
  Bool.pick(U32, F.Font.bit(g, (x - gx : U32), (y - gy : U32)), 255, 0)

def Cov.at(s: Shape, +x: U32, +y: U32, +px: F32, +py: F32) -> U32:
  match s:
    case SRect{}:
      255
    case SGlyph{gx, gy, g}:
      Cov.glyph(g, gx, gy, x, y)
    case SSeg{ax, ay, bx, by, hw}:
      Cov.seg(ax, ay, bx, by, hw, px, py)
    case SDisc{cx, cy, r}:
      Cov.disc(cx, cy, r, px, py)
    case STri{ax, ay, bx, by, cx, cy}:
      Cov.tri(ax, ay, bx, by, cx, cy, px, py)

# how much of pixel (x, y) the shape covers, 0..255
def Cov.of(s: Shape, +x: U32, +y: U32) -> U32:
  Cov.at(s, x, y, F32.add(U32.to_f32(x), 0.5), F32.add(U32.to_f32(y), 0.5))

# Shading one pixel
# -----------------

def Shade.inside(+x0: U32, +y0: U32, +x1: U32, +y1: U32, +x: U32, +y: U32) -> Bool:
  Bool.and(Bool.and(U32.is_ge(x, x0), U32.is_lt(x, x1)), Bool.and(U32.is_ge(y, y0), U32.is_lt(y, y1)))

def Shade.k(+cov: U32, +c: U32, +a: U32, +below: U32) -> U32:
  Rgb.mix(c, below, ((cov * a : U32) / 255 : U32))

# the topmost op that covers the pixel decides; a translucent one mixes
# with what lies below it
def Shade.px(ops: List<&2, Op>, +x: U32, +y: U32, +bg: U32) -> U32:
  match ops:
    case Nil{}:
      bg
    case Op{+x0, +y0, +x1, +y1, +c, +a, s} <> t:
      Shade.k(Bool.pick(U32, Shade.inside(x0, y0, x1, y1, x, y), Cov.of(s, x, y), 0), c, a, Shade.px(t, x, y, bg))

# Regions
# -------

def Region.hits(+x0: U32, +y0: U32, +x1: U32, +y1: U32, +rx: U32, +ry: U32, +n: U32) -> Bool:
  Bool.and(Bool.and(U32.is_lt(x0, (rx + n : U32)), U32.is_gt(x1, rx)), Bool.and(U32.is_lt(y0, (ry + n : U32)), U32.is_gt(y1, ry)))

def Region.keep.k(hit: Bool, o: Op, rest: List<&2, Op>) -> List<&2, Op>:
  match hit:
    case True{}:
      o <> rest
    case False{}:
      rest

# the ops that reach the n x n region at (rx, ry), order kept
def Region.keep(ops: List<&2, Op>, +rx: U32, +ry: U32, +n: U32) -> List<&2, Op>:
  match ops:
    case Nil{}:
      Nil{}
    case Op{+x0, +y0, +x1, +y1, c, a, s} <> t:
      Region.keep.k(Region.hits(x0, y0, x1, y1, rx, ry, n), Op{x0, y0, x1, y1, c, a, s}, Region.keep(t, rx, ry, n))

# the topmost op is an opaque rectangle over the whole region
def Region.solid(ops: List<&2, Op>, +rx: U32, +ry: U32, +n: U32) -> Bool:
  match ops:
    case Op{x0, y0, x1, y1, _, a, SRect{}} <> _:
      Bool.and(Bool.and(U32.is_eq(a, 255), Bool.and(U32.is_le(x0, rx), U32.is_le(y0, ry))),
        Bool.and(U32.is_ge(x1, (rx + n : U32)), U32.is_ge(y1, (ry + n : U32))))
    case _:
      False{}

def Region.top(ops: List<&2, Op>) -> U32:
  match ops:
    case Op{_, _, _, _, c, _, _} <> _:
      c
    case Nil{}:
      0

type Leaf is Data:
  LEmpty{}
  LSolid{}
  LPixel{}
  LSplit{}

def Region.leaf.k(empty: Bool, solid: Bool, one: Bool) -> Leaf:
  match empty solid one:
    case True{} _ _:
      LEmpty{}
    case False{} True{} _:
      LSolid{}
    case False{} False{} True{}:
      LPixel{}
    case False{} False{} False{}:
      LSplit{}

def Region.leaf(+ops: List<&2, Op>, +rx: U32, +ry: U32, +n: U32) -> Leaf:
  Region.leaf.k(List.is_empty(&2, Op, ops), Region.solid(ops, rx, ry, n), U32.is_eq(n, 1))

# the image of the n x n region at (rx, ry); d counts levels left (n = 2^d)
def Region.node(d: Nat, l: Leaf, +ops: List<&2, Op>, +rx: U32, +ry: U32, +n: U32, +bg: U32) -> Image:
  match d l:
    case _ LEmpty{}:
      Pix{bg}
    case _ LSolid{}:
      Pix{Region.top(ops)}
    case _ LPixel{}:
      Pix{Shade.px(ops, rx, ry, bg)}
    case 0n LSplit{}:
      Pix{Shade.px(ops, rx, ry, bg)}
    case 1n+e0 LSplit{}:
      +e = e0
      +h = U32.shr(n)
      +ta = Region.keep(ops, rx, ry, h)
      +tb = Region.keep(ops, (rx + h : U32), ry, h)
      +tc = Region.keep(ops, rx, (ry + h : U32), h)
      +td = Region.keep(ops, (rx + h : U32), (ry + h : U32), h)
      a b c dd = Region.node(e, Region.leaf(ta, rx, ry, h), ta, rx, ry, h, bg) Region.node(e, Region.leaf(tb, (rx + h : U32), ry, h), tb, (rx + h : U32), ry, h, bg) Region.node(e, Region.leaf(tc, rx, (ry + h : U32), h), tc, rx, (ry + h : U32), h, bg) Region.node(e, Region.leaf(td, (rx + h : U32), (ry + h : U32), h), td, (rx + h : U32), (ry + h : U32), h, bg)
      Qua{a, b, c, dd}

# the exponent of the smallest power of two covering w and h
def Frame.depth(+w: U32, +h: U32) -> Nat:
  1n+U32.log2((U32.max(U32.max(w, h), 2) - 1 : U32))

# a w x h frame of ops (topmost first) over bg
def Frame.render(+w: U32, +h: U32, +ops: List<&2, Op>, +bg: U32) -> Image:
  +d = Frame.depth(w, h)
  Region.node(d, Region.leaf(ops, 0, 0, U32.shln(1, d)), ops, 0, 0, U32.shln(1, d), bg)

# Reading pixels back (snapshots, tests)
# --------------------------------------

def Img.pick(right: Bool, down: Bool, a: Image, b: Image, c: Image, e: Image) -> Image:
  match right down:
    case False{} False{}:
      a
    case True{} False{}:
      b
    case False{} True{}:
      c
    case True{} True{}:
      e

# the colour at (x, y) of an image whose root spans 2^d pixels
def Img.at(d: Nat, img: Image, +x: U32, +y: U32) -> U32:
  match d img:
    case _ Pix{c}:
      c
    case 0n Qua{_, _, _, _}:
      0
    case 1n+k0 Qua{a, b, c, e}:
      +k = k0
      Img.at(k, Img.pick(U32.is_ne(U32.and(U32.shrn(x, k), 1), 0), U32.is_ne(U32.and(U32.shrn(y, k), 1), 0), a, b, c, e), x, y)
