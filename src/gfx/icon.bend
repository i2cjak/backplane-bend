import Base
import ../core/svg.bend as S
import ../core/icons.bend as I
import ./raster.bend as R
import ./draw.bend as D
import ./text.bend as X

# Icons in the window: an icon's paths (core/icons.bend) flattened, scaled
# to the size asked for, and rendered once into an anti-aliased coverage
# bitmap (R.SMask), which draws in any colour. A stroke covers what lies
# within half its width of a line (round caps and joins for free); a fill
# covers what is inside, with a half-pixel ramp at its edges. The bitmap's
# words render in parallel, one balanced fork per level. Bitmaps are made
# at startup (Ico.warm) and kept in the glyph cache, so a frame only looks
# them up.

# the icon's lines in pixels: those it strokes and those it fills
type Ink is Data:
  Ink{stroke: List<&2, S.Ln>, fill: List<&2, S.Ln>, hw: F32}

def Ico.keep(on: Bool, l: S.Ln, acc: List<&2, S.Ln>) -> List<&2, S.Ln>:
  match on:
    case True{}:
      l <> acc
    case False{}:
      acc

# the lines scaled by s onto acc (a stroke leaves out the edges that only
# close a subpath for filling)
def Ico.scale(ls: List<&2, S.Ln>, +s: F32, +keep_fill: Bool, acc: List<&2, S.Ln>) -> List<&2, S.Ln>:
  match ls:
    case Nil{}:
      acc
    case S.Ln{+ax, +ay, +bx, +by, +f} <> t:
      Ico.scale(t, s, keep_fill, Ico.keep(Bool.or(keep_fill, Bool.not(f)), S.Ln{F32.mul(ax, s), F32.mul(ay, s), F32.mul(bx, s), F32.mul(by, s), f}, acc))

def Ico.layer(l: I.Layer, +s: F32, k: Ink) -> Ink:
  match l k:
    case I.Layer{d, True{}} Ink{st, fl, +hw}:
      Ink{st, Ico.scale(S.Svg.flat(S.Svg.parse(d)), s, True{}, fl), hw}
    case I.Layer{d, False{}} Ink{st, fl, +hw}:
      Ink{Ico.scale(S.Svg.flat(S.Svg.parse(d)), s, False{}, st), fl, hw}

def Ico.layers(ls: List<&2, I.Layer>, +s: F32, k: Ink) -> Ink:
  match ls:
    case Nil{}:
      k
    case l <> t:
      Ico.layers(t, s, Ico.layer(l, s, k))

# an icon's ink at px pixels: the 24-unit grid scaled, the 2-unit stroke
# never thinner than a pixel and a quarter
def Ico.ink(+name: String, +px: U32) -> Ink:
  +s = F32.div(U32.to_f32(px), 24.0)
  Ico.layers(I.Icon.layers(name), s, Ink{Nil{}, Nil{}, F32.max(s, 0.625)})

# Coverage
# --------

def Ico.dist(+ax: F32, +ay: F32, +bx: F32, +by: F32, +px: F32, +py: F32) -> F32:
  +dx = F32.sub(bx, ax)
  +dy = F32.sub(by, ay)
  +ll = F32.add(F32.mul(dx, dx), F32.mul(dy, dy))
  +t = Bool.pick(F32, F32.is_le(ll, 0.0), 0.0, F32.clamp(F32.div(F32.add(F32.mul(F32.sub(px, ax), dx), F32.mul(F32.sub(py, ay), dy)), ll), 0.0, 1.0))
  F32.hypot(F32.sub(px, F32.add(ax, F32.mul(t, dx))), F32.sub(py, F32.add(ay, F32.mul(t, dy))))

# the distance from (px, py) to the nearest line
def Ico.near(ls: List<&2, S.Ln>, +px: F32, +py: F32, +acc: F32) -> F32:
  match ls:
    case Nil{}:
      acc
    case S.Ln{+ax, +ay, +bx, +by, _} <> t:
      Ico.near(t, px, py, F32.min(acc, Ico.dist(ax, ay, bx, by, px, py)))

def Ico.cross1(+ax: F32, +ay: F32, +bx: F32, +by: F32, +px: F32, +py: F32) -> Bool:
  Bool.and(Bool.xor(F32.is_gt(ay, py), F32.is_gt(by, py)),
    F32.is_lt(px, F32.add(ax, F32.div(F32.mul(F32.sub(py, ay), F32.sub(bx, ax)), F32.sub(by, ay)))))

# even-odd: does a ray from (px, py) to the right cross an odd count of lines
def Ico.inside(ls: List<&2, S.Ln>, +px: F32, +py: F32, acc: Bool) -> Bool:
  match ls:
    case Nil{}:
      acc
    case S.Ln{+ax, +ay, +bx, +by, _} <> t:
      Ico.inside(t, px, py, Bool.xor(acc, Ico.cross1(ax, ay, bx, by, px, py)))

def Ico.ramp(+v: F32) -> F32:
  F32.clamp(v, 0.0, 1.0)

def Ico.fill(+fl: List<&2, S.Ln>, +px: F32, +py: F32) -> F32:
  +d = Ico.near(fl, px, py, 1000.0)
  Bool.pick(F32, Ico.inside(fl, px, py, False{}), Ico.ramp(F32.add(0.5, d)), Ico.ramp(F32.sub(0.5, d)))

# the coverage (0..255) of pixel (x, y)
def Ico.cov(k: Ink, +x: U32, +y: U32) -> U32:
  match k:
    case Ink{+st, +fl, +hw}:
      +px = F32.add(U32.to_f32(x), 0.5)
      +py = F32.add(U32.to_f32(y), 0.5)
      F32.to_u32(F32.mul(F32.max(Ico.ramp(F32.sub(F32.add(hw, 0.5), Ico.near(st, px, py, 1000.0))), Ico.fill(fl, px, py)), 255.0))

# pixel i of the w x w bitmap (n pixels in all; zero past the end)
def Ico.px(+k: Ink, +w: U32, +n: U32, +i: U32) -> U32:
  Bool.pick(U32, U32.is_lt(i, n), Ico.cov(k, U32.mod(i, w), U32.div(i, w)), 0)

# word i: four pixels, the first in the low byte
def Ico.word(+k: Ink, +w: U32, +n: U32, +i: U32) -> U32:
  +p = U32.shln(i, 2n)
  U32.or(U32.or(Ico.px(k, w, n, p), U32.shln(Ico.px(k, w, n, (p + 1 : U32)), 8n)),
    U32.or(U32.shln(Ico.px(k, w, n, (p + 2 : U32)), 16n), U32.shln(Ico.px(k, w, n, (p + 3 : U32)), 24n)))

# words [i, i + 2^d) as a mask tree, both halves at once
def Ico.tree(d: Nat, +k: Ink, +w: U32, +n: U32, +i: U32) -> R.Mask:
  match d:
    case 0n:
      R.MWord{Ico.word(k, w, n, i)}
    case 1n+e0:
      +e = e0
      lo hi = Ico.tree(e, k, w, n, i) Ico.tree(e, k, w, n, (i + U32.shln(1, e) : U32))
      R.MPair{lo, hi}

# the icon rendered at px x px, as a cached glyph
def Ico.render(+name: String, +px: U32) -> X.TG:
  +n = (px * px : U32)
  +d = X.Mask.depth(((n + 3 : U32) / 4 : U32))
  X.TG{(px * 64 : U32), 32768, 32768, px, px, d, Ico.tree(d, Ico.ink(name, px), px, n, 0)}

def Ico.key(+name: String, +px: U32) -> String:
  "icon/" ++ name ++ "/" ++ U32.show(px)

def Ico.warm.one(c: Map<&2, X.TG>, +name: String, +px: U32) -> Map<&2, X.TG>:
  Map.set(&2, X.TG, c, Ico.key(name, px), Ico.render(name, px))

# the cache with every icon at px pixels
def Ico.warm.go(ns: List<&2, String>, c: Map<&2, X.TG>, +px: U32) -> Map<&2, X.TG>:
  match ns:
    case Nil{}:
      c
    case +n <> t:
      Ico.warm.go(t, Ico.warm.one(c, n, px), px)

def Ico.warm(c: Map<&2, X.TG>, +px: U32) -> Map<&2, X.TG>:
  Ico.warm.go(I.Icon.names(), c, px)

def Ico.got(r: Map<&2, X.TG> & X.TG) -> X.TG:
  (_, g) = r
  g

def Ico.draw(g: X.TG, +c: D.Clip, +x: U32, +y: U32, +color: U32) -> List<&2, R.Op>:
  match g:
    case X.TG{_, _, _, +w, +h, +d, m}:
      Bool.pick(List<&2, R.Op>, U32.is_eq(w, 0), Nil{}, [D.Clip.cut(c, x, y, (x + w : U32), (y + h : U32), color, 255, R.SMask{x, y, w, d, m})])

# draw ops for the icon at px pixels with its top-left at (x, y); nothing
# when it was not warmed
def Ico.op(+cache: Map<&2, X.TG>, +name: String, +px: U32, +c: D.Clip, +x: U32, +y: U32, +color: U32) -> List<&2, R.Op>:
  Ico.draw(Ico.got(Map.get(X.TG, X.TG.blank(0), cache, Ico.key(name, px))), c, x, y, color)
