import Base
import ./font.bend as F
import ./raster.bend as R

# Building draw ops. Every op is cut to a clip rectangle, so a scrolled
# panel never paints outside itself. Text is Spleen 8x16: a cell is 8 by 16
# pixels, so layout is arithmetic.

type Clip is Data:
  Clip{x0: U32, y0: U32, x1: U32, y1: U32}

def Clip.all() -> Clip:
  Clip{0, 0, 65535, 65535}

def Clip.cut(c: Clip, +x0: U32, +y0: U32, +x1: U32, +y1: U32, +color: U32, +alpha: U32, s: R.Shape) -> R.Op:
  match c:
    case Clip{+cx0, +cy0, +cx1, +cy1}:
      R.Op{U32.max(x0, cx0), U32.max(y0, cy0), U32.min(x1, cx1), U32.min(y1, cy1), color, alpha, s}

def Draw.rect(+c: Clip, +x: U32, +y: U32, +w: U32, +h: U32, +color: U32, +alpha: U32) -> R.Op:
  Clip.cut(c, x, y, (x + w : U32), (y + h : U32), color, alpha, R.SRect{})

# a 1-pixel frame inside the rectangle
def Draw.frame(+c: Clip, +x: U32, +y: U32, +w: U32, +h: U32, +color: U32) -> List<&2, R.Op>:
  [Draw.rect(c, x, y, w, 1, color, 255), Draw.rect(c, x, (y + h - 1 : U32), w, 1, color, 255),
   Draw.rect(c, x, y, 1, h, color, 255), Draw.rect(c, (x + w - 1 : U32), y, 1, h, color, 255)]

def Draw.glyph(+c: Clip, +x: U32, +y: U32, +cp: U32, +color: U32) -> R.Op:
  Clip.cut(c, x, y, (x + 8 : U32), (y + 16 : U32), color, 255, R.SGlyph{x, y, F.Font.glyph(cp)})

def Draw.space(+cp: U32) -> Bool:
  U32.is_le(cp, 32)

def Draw.text.k(sp: Bool, +c: Clip, +x: U32, +y: U32, +cp: U32, +color: U32, rest: List<&2, R.Op>) -> List<&2, R.Op>:
  match sp:
    case True{}:
      rest
    case False{}:
      Draw.glyph(c, x, y, cp, color) <> rest

# one line of text; spaces draw nothing
def Draw.text(s: String, +c: Clip, +x: U32, +y: U32, +color: U32) -> List<&2, R.Op>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{Chr{+cp}, t}:
      Draw.text.k(Draw.space(cp), c, x, y, cp, color, Draw.text(t, c, (x + 8 : U32), y, color))

def Draw.floor(+f: F32) -> U32:
  F32.to_u32(F32.max(F32.floor(f), 0.0))

def Draw.ceil(+f: F32) -> U32:
  F32.to_u32(F32.max(F32.ceil(f), 0.0))

# an anti-aliased segment of width w
def Draw.seg(+c: Clip, +ax: F32, +ay: F32, +bx: F32, +by: F32, +w: F32, +color: U32, +alpha: U32) -> R.Op:
  +hw = F32.max(F32.div(w, 2.0), 0.5)
  Clip.cut(c, Draw.floor(F32.sub(F32.min(ax, bx), F32.add(hw, 1.0))), Draw.floor(F32.sub(F32.min(ay, by), F32.add(hw, 1.0))),
    Draw.ceil(F32.add(F32.max(ax, bx), F32.add(hw, 1.0))), Draw.ceil(F32.add(F32.max(ay, by), F32.add(hw, 1.0))),
    color, alpha, R.SSeg{ax, ay, bx, by, hw})

def Draw.disc(+c: Clip, +cx: F32, +cy: F32, +r: F32, +color: U32, +alpha: U32) -> R.Op:
  Clip.cut(c, Draw.floor(F32.sub(cx, F32.add(r, 1.0))), Draw.floor(F32.sub(cy, F32.add(r, 1.0))),
    Draw.ceil(F32.add(cx, F32.add(r, 1.0))), Draw.ceil(F32.add(cy, F32.add(r, 1.0))), color, alpha, R.SDisc{cx, cy, r})

def Draw.tri(+c: Clip, +ax: F32, +ay: F32, +bx: F32, +by: F32, +cx: F32, +cy: F32, +color: U32, +alpha: U32) -> R.Op:
  Clip.cut(c, Draw.floor(F32.min(ax, F32.min(bx, cx))), Draw.floor(F32.min(ay, F32.min(by, cy))),
    Draw.ceil(F32.add(F32.max(ax, F32.max(bx, cx)), 1.0)), Draw.ceil(F32.add(F32.max(ay, F32.max(by, cy)), 1.0)),
    color, alpha, R.STri{ax, ay, bx, by, cx, cy})

def Snap.ascii(s: String) -> List<&2, U32>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{Chr{c}, t}:
      c <> Snap.ascii(t)

def Snap.put(+c: U32, acc: List<&2, U32>) -> List<&2, U32>:
  U32.and(U32.shrn(c, 16n), 255) <> U32.and(U32.shrn(c, 8n), 255) <> U32.and(c, 255) <> acc

def Snap.go(n: Nat, +img: Image, +d: Nat, +w: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+i0:
      +i = i0
      Snap.go(i, img, d, w, Snap.put(R.Img.at(d, img, U32.from_nat(Nat.mod(i, U32.to_nat(w))), U32.from_nat(Nat.div(i, U32.to_nat(w)))), acc))

# Snapshots
# ---------

# the frame as binary PPM bytes (w x h, 8-bit RGB)
def Snap.ppm(+img: Image, +w: U32, +h: U32) -> List<&2, U32>:
  List.append(&2, U32, Snap.ascii("P6\n" ++ U32.show(w) ++ " " ++ U32.show(h) ++ "\n255\n"),
    Snap.go(U32.to_nat((w * h : U32)), img, R.Frame.depth(w, h), w, Nil{}))
