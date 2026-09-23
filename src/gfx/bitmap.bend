import Base
import ./raster.bend as R

# Raw RGB pixels as an Image quadtree, and placing one into a frame.
#
# The browser helper (tools/browser) writes frames as a 16-byte header
# ("BPF1", width, height, seq; u32 little-endian) and then width*height*3
# bytes of RGB, row after row. `Bitmap.image` turns the bytes into a source
# quadtree (equal-colour quads merge, so flat page areas are one leaf), and
# `Bitmap.over` composites it into a frame at (x0, y0), stretched to fw x fh
# with nearest-neighbour sampling. A frame region the bitmap does not reach
# keeps the base image's subtree; a region inside it whose source rectangle
# lies in one flat source leaf is one leaf. Both walks split in four and run
# the quadrants in parallel.

# a w x h bitmap, as a quadtree 2^d pixels wide, to be drawn at (x0, y0)
# stretched to fw x fh
type Bitmap is Data:
  Bitmap{w: U32, h: U32, d: Nat, tree: Image, x0: U32, y0: U32, fw: U32, fh: U32}

# a frame file's header
type BmHead is Data:
  BmHead{w: U32, h: U32, seq: U32}

# Rows
# ----

def Bm.rgb(+r: U32, +g: U32, +b: U32) -> U32:
  U32.or(U32.shln(U32.and(r, 255), 16n), U32.or(U32.shln(U32.and(g, 255), 8n), U32.and(b, 255)))

type BmRow is Data:
  BmRow{row: List<&2, U32>, rest: List<&2, U32>}

def BmRow.cons(+c: U32, r: BmRow) -> BmRow:
  match r:
    case BmRow{row, rest}:
      BmRow{c <> row, rest}

# the first n pixels of the bytes, packed 0xRRGGBB, and the bytes after them
def BmRow.take(n: Nat, bs: List<&2, U32>) -> BmRow:
  match n bs:
    case 0n rest:
      BmRow{Nil{}, rest}
    case 1n+k r <> g <> b <> t:
      BmRow.cons(Bm.rgb(r, g, b), BmRow.take(k, t))
    case 1n+k _:
      BmRow{Nil{}, Nil{}}

def BmRow.next(r: BmRow, go: List<&2, U32> -> List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match r:
    case BmRow{row, rest}:
      row <> go(rest)

# h rows of w pixels
def BmRow.rows(h: Nat, bs: List<&2, U32>, +w: Nat) -> List<&2, List<&2, U32>>:
  match h:
    case 0n:
      Nil{}
    case 1n+k:
      BmRow.next(BmRow.take(w, bs), rest => BmRow.rows(k, rest, w))

# Building the quadtree
# ---------------------

# the colour of a solid image, or 2^24 (no colour) for a split one
def Bm.solid(img: Image) -> U32:
  match img:
    case Pix{c}:
      c
    case Qua{_, _, _, _}:
      16777216

def Bm.join.k(same: Bool, a: Image, b: Image, c: Image, d: Image) -> Image:
  match same:
    case True{}:
      a
    case False{}:
      Qua{a, b, c, d}

def Bm.same(+p: U32, +q: U32, +r: U32, +s: U32) -> Bool:
  Bool.and(U32.is_lt(p, 16777216), Bool.and(U32.is_eq(p, q), Bool.and(U32.is_eq(p, r), U32.is_eq(p, s))))

# four quadrants, one leaf when they are the same solid colour
def Bm.join(+a: Image, +b: Image, +c: Image, +d: Image) -> Image:
  Bm.join.k(Bm.same(Bm.solid(a), Bm.solid(b), Bm.solid(c), Bm.solid(d)), a, b, c, d)

type BmHalf is Data:
  BmHalf{l: List<&2, List<&2, U32>>, r: List<&2, List<&2, U32>>}

def BmHalf.cons(+x: List<&2, U32>, +y: List<&2, U32>, h: BmHalf) -> BmHalf:
  match h:
    case BmHalf{l, r}:
      BmHalf{x <> l, y <> r}

# every row cut after n pixels: the left parts and the right parts
def BmHalf.cols(rows: List<&2, List<&2, U32>>, +n: Nat) -> BmHalf:
  match rows:
    case Nil{}:
      BmHalf{Nil{}, Nil{}}
    case +row <> t:
      BmHalf.cons(List.take(&2, U32, row, n), List.drop(&2, U32, row, n), BmHalf.cols(t, n))

def Bm.first(rows: List<&2, List<&2, U32>>) -> U32:
  match rows:
    case (c <> _) <> _:
      c
    case _:
      0

# no pixels left in the region (rows all have the same length)
def Bm.blank(rows: List<&2, List<&2, U32>>) -> Bool:
  match rows:
    case Nil{}:
      True{}
    case Nil{} <> _:
      True{}
    case _:
      False{}

def Bm.split(top: BmHalf, bot: BmHalf, k: List<&2, List<&2, U32>> -> List<&2, List<&2, U32>> -> List<&2, List<&2, U32>> -> List<&2, List<&2, U32>> -> Image) -> Image:
  match top bot:
    case BmHalf{tl, tr} BmHalf{bl, br}:
      k(tl, tr, bl, br)

# the quadtree of rows (each at most 2^d long, at most 2^d of them),
# padded with black; blank says the rows hold no pixel
def Bm.build(d: Nat, blank: Bool, +rows: List<&2, List<&2, U32>>) -> Image:
  match d blank:
    case _ True{}:
      Pix{0}
    case 0n False{}:
      Pix{Bm.first(rows)}
    case 1n+e0 False{}:
      +e = e0
      +h = U32.to_nat(U32.shln(1, e))
      Bm.split(BmHalf.cols(List.take(&2, List<&2, U32>, rows, h), h), BmHalf.cols(List.drop(&2, List<&2, U32>, rows, h), h),
        +tl => +tr => +bl => +br => (
          a b c dd = Bm.build(e, Bm.blank(tl), tl) Bm.build(e, Bm.blank(tr), tr) Bm.build(e, Bm.blank(bl), bl) Bm.build(e, Bm.blank(br), br)
          Bm.join(a, b, c, dd)))

# Sampling
# --------

# where the bitmap lands: at (x0, y0), fw x fh, from a w x h source
type BmGeo is Data:
  BmGeo{x0: U32, y0: U32, fw: U32, fh: U32, w: U32, h: U32}

# the source column / row of frame column x / row y (nearest neighbour)
def BmGeo.sx(g: BmGeo, +x: U32) -> U32:
  match g:
    case BmGeo{+x0, _, +fw, _, +w, _}:
      (((x - x0 : U32) * w : U32) / fw : U32)

def BmGeo.sy(g: BmGeo, +y: U32) -> U32:
  match g:
    case BmGeo{_, +y0, _, +fh, _, +h}:
      (((y - y0 : U32) * h : U32) / fh : U32)

# a source node at (ox, oy), 2^e pixels wide
type BmSrc is Data:
  BmSrc{img: Image, ox: U32, oy: U32, e: Nat}

type BmSide is Data:
  BmLo{}
  BmHi{}
  BmBoth{}

type BmPick is Data:
  BmA{}
  BmB{}
  BmC{}
  BmD{}
  BmStop{}

def BmSide.of(lo: Bool, hi: Bool) -> BmSide:
  match lo hi:
    case True{} _:
      BmLo{}
    case False{} True{}:
      BmHi{}
    case False{} False{}:
      BmBoth{}

def BmPick.of(sx: BmSide, sy: BmSide) -> BmPick:
  match sx sy:
    case BmLo{} BmLo{}:
      BmA{}
    case BmHi{} BmLo{}:
      BmB{}
    case BmLo{} BmHi{}:
      BmC{}
    case BmHi{} BmHi{}:
      BmD{}
    case _ _:
      BmStop{}

# the child of the node at (ox, oy) (children 2^e wide) that holds all of
# the source rectangle [sx0, sx1] x [sy0, sy1], if one does
def BmPick.at(+e: Nat, +ox: U32, +oy: U32, +sx0: U32, +sy0: U32, +sx1: U32, +sy1: U32) -> BmPick:
  +mx = (ox + U32.shln(1, e) : U32)
  +my = (oy + U32.shln(1, e) : U32)
  BmPick.of(BmSide.of(U32.is_lt(sx1, mx), U32.is_ge(sx0, mx)), BmSide.of(U32.is_lt(sy1, my), U32.is_ge(sy0, my)))

# the smallest source node holding all of the rectangle (or a leaf)
def BmSrc.find(e: Nat, img: Image, p: BmPick, +ox: U32, +oy: U32, +sx0: U32, +sy0: U32, +sx1: U32, +sy1: U32) -> BmSrc:
  match e img p:
    case 0n q _:
      BmSrc{q, ox, oy, 0n}
    case 1n+k0 Pix{c} _:
      BmSrc{Pix{c}, ox, oy, 1n+k0}
    case 1n+k0 Qua{a, b, c, dd} BmStop{}:
      BmSrc{Qua{a, b, c, dd}, ox, oy, 1n+k0}
    case 1n+k0 Qua{a, _, _, _} BmA{}:
      +k = k0
      BmSrc.find(k, a, BmPick.at(Nat.sub(k, 1n), ox, oy, sx0, sy0, sx1, sy1), ox, oy, sx0, sy0, sx1, sy1)
    case 1n+k0 Qua{_, b, _, _} BmB{}:
      +k = k0
      +x = (ox + U32.shln(1, k) : U32)
      BmSrc.find(k, b, BmPick.at(Nat.sub(k, 1n), x, oy, sx0, sy0, sx1, sy1), x, oy, sx0, sy0, sx1, sy1)
    case 1n+k0 Qua{_, _, c, _} BmC{}:
      +k = k0
      +y = (oy + U32.shln(1, k) : U32)
      BmSrc.find(k, c, BmPick.at(Nat.sub(k, 1n), ox, y, sx0, sy0, sx1, sy1), ox, y, sx0, sy0, sx1, sy1)
    case 1n+k0 Qua{_, _, _, dd} BmD{}:
      +k = k0
      +x = (ox + U32.shln(1, k) : U32)
      +y = (oy + U32.shln(1, k) : U32)
      BmSrc.find(k, dd, BmPick.at(Nat.sub(k, 1n), x, y, sx0, sy0, sx1, sy1), x, y, sx0, sy0, sx1, sy1)

def BmSrc.go(+e: Nat, +img: Image, +ox: U32, +oy: U32, +sx0: U32, +sy0: U32, +sx1: U32, +sy1: U32) -> BmSrc:
  BmSrc.find(e, img, BmPick.at(Nat.sub(e, 1n), ox, oy, sx0, sy0, sx1, sy1), ox, oy, sx0, sy0, sx1, sy1)

# the source node for the n x n frame region at (rx, ry), searched from s
def BmSrc.region(s: BmSrc, +g: BmGeo, +rx: U32, +ry: U32, +n: U32) -> BmSrc:
  match s:
    case BmSrc{+img, +ox, +oy, +e}:
      BmSrc.go(e, img, ox, oy, BmGeo.sx(g, rx), BmGeo.sy(g, ry), BmGeo.sx(g, (rx + n - 1 : U32)), BmGeo.sy(g, (ry + n - 1 : U32)))

# the n x n frame region at (rx, ry) (n = 2^d), wholly inside the bitmap's
# place, drawn from the source node s that holds its source rectangle
def Bm.sample(d: Nat, s: BmSrc, +g: BmGeo, +rx: U32, +ry: U32) -> Image:
  match d s:
    case _ BmSrc{Pix{c}, _, _, _}:
      Pix{c}
    case 0n _:
      Pix{0}
    case 1n+k0 BmSrc{+img, +ox, +oy, +e}:
      +k = k0
      +src = {BmSrc{img, ox, oy, e} : BmSrc}
      +h = U32.shln(1, k)
      +x2 = (rx + h : U32)
      +y2 = (ry + h : U32)
      a b c dd = Bm.sample(k, BmSrc.region(src, g, rx, ry, h), g, rx, ry) Bm.sample(k, BmSrc.region(src, g, x2, ry, h), g, x2, ry) Bm.sample(k, BmSrc.region(src, g, rx, y2, h), g, rx, y2) Bm.sample(k, BmSrc.region(src, g, x2, y2, h), g, x2, y2)
      Bm.join(a, b, c, dd)

# Placing into a frame
# --------------------

type BmCut is Data:
  BmOut{}
  BmIn{}
  BmEdge{}

def BmCut.of(out: Bool, inside: Bool) -> BmCut:
  match out inside:
    case True{} _:
      BmOut{}
    case False{} True{}:
      BmIn{}
    case False{} False{}:
      BmEdge{}

# how the n x n frame region at (rx, ry) meets the bitmap's place
def BmCut.at(g: BmGeo, +rx: U32, +ry: U32, +n: U32) -> BmCut:
  match g:
    case BmGeo{+x0, +y0, +fw, +fh, _, _}:
      +x1 = (x0 + fw : U32)
      +y1 = (y0 + fh : U32)
      BmCut.of(Bool.or(Bool.or(U32.is_ge(rx, x1), U32.is_le((rx + n : U32), x0)), Bool.or(U32.is_ge(ry, y1), U32.is_le((ry + n : U32), y0))),
        Bool.and(Bool.and(U32.is_ge(rx, x0), U32.is_le((rx + n : U32), x1)), Bool.and(U32.is_ge(ry, y0), U32.is_le((ry + n : U32), y1))))

# the n x n frame region at (rx, ry) (n = 2^d) over the base's same region
def Bm.place(d: Nat, cut: BmCut, +base: Image, +root: BmSrc, +g: BmGeo, +rx: U32, +ry: U32) -> Image:
  match d cut:
    case _ BmOut{}:
      base
    case 0n BmIn{}:
      Bm.sample(0n, BmSrc.region(root, g, rx, ry, 1), g, rx, ry)
    case 1n+k0 BmIn{}:
      +k = {1n+k0 : Nat}
      Bm.sample(k, BmSrc.region(root, g, rx, ry, U32.shln(1, k)), g, rx, ry)
    case 0n BmEdge{}:
      base
    case 1n+k0 BmEdge{}:
      +k = k0
      +h = U32.shln(1, k)
      +x2 = (rx + h : U32)
      +y2 = (ry + h : U32)
      R.Four.base(base, ba => bb => bc => bd => (
        a b c dd = Bm.place(k, BmCut.at(g, rx, ry, h), ba, root, g, rx, ry) Bm.place(k, BmCut.at(g, x2, ry, h), bb, root, g, x2, ry) Bm.place(k, BmCut.at(g, rx, y2, h), bc, root, g, rx, y2) Bm.place(k, BmCut.at(g, x2, y2, h), bd, root, g, x2, y2)
        Qua{a, b, c, dd}))

# API
# ---

# a w x h bitmap from raw RGB bytes (3 per pixel, rows top to bottom), to
# be placed at (x0, y0) stretched to fw x fh
def Bitmap.image(+w: U32, +h: U32, rgb: List<&2, U32>, +x0: U32, +y0: U32, +fw: U32, +fh: U32) -> Bitmap:
  +d = R.Frame.depth(w, h)
  +rows = BmRow.rows(U32.to_nat(h), rgb, U32.to_nat(w))
  Bitmap{w, h, d, Bm.build(d, Bm.blank(rows), rows), x0, y0, fw, fh}

# the same bitmap, placed elsewhere
def Bitmap.move(b: Bitmap, +x0: U32, +y0: U32, +fw: U32, +fh: U32) -> Bitmap:
  match b:
    case Bitmap{w, h, d, t, _, _, _, _}:
      Bitmap{w, h, d, t, x0, y0, fw, fh}

def Bitmap.over.k(+fd: Nat, b: Bitmap, +base: Image) -> Image:
  match b:
    case Bitmap{+w, +h, d, t, +x0, +y0, +fw, +fh}:
      +g = {BmGeo{x0, y0, fw, fh, w, h} : BmGeo}
      Bm.place(fd, BmCut.at(g, 0, 0, U32.shln(1, fd)), base, BmSrc{t, 0, 0, d}, g, 0, 0)

# a W x H frame (the base, as from R.Frame.render) with the bitmap drawn
# over it; draw ops go on top with R.Frame.over(W, H, ops, this)
def Bitmap.over(+fw: U32, +fh: U32, b: Bitmap, +base: Image) -> Image:
  Bitmap.over.k(R.Frame.depth(fw, fh), b, base)

# a W x H frame of the bitmap over a solid background
def Bitmap.frame(+fw: U32, +fh: U32, b: Bitmap, +bg: U32) -> Image:
  Bitmap.over(fw, fh, b, Pix{bg})

# Frame files
# -----------

def Bm.u32(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  U32.or(U32.or(a, U32.shln(b, 8n)), U32.or(U32.shln(c, 16n), U32.shln(d, 24n)))

# the header of a frame file ("BPF1", then w, h, seq as u32 LE); 0 x 0
# when the bytes are too short
def Bitmap.head(bs: List<&2, U32>) -> BmHead:
  match bs:
    case _ <> _ <> _ <> _ <> w0 <> w1 <> w2 <> w3 <> h0 <> h1 <> h2 <> h3 <> s0 <> s1 <> s2 <> s3 <> _:
      BmHead{Bm.u32(w0, w1, w2, w3), Bm.u32(h0, h1, h2, h3), Bm.u32(s0, s1, s2, s3)}
    case _:
      BmHead{0, 0, 0}

def Bitmap.load.k(h: BmHead, rgb: List<&2, U32>, +x0: U32, +y0: U32, +fw: U32, +fh: U32) -> Bitmap:
  match h:
    case BmHead{+w, +hh, _}:
      Bitmap.image(w, hh, rgb, x0, y0, fw, fh)

# a frame file's bytes as a bitmap placed at (x0, y0), fw x fh
def Bitmap.load(+bs: List<&2, U32>, +x0: U32, +y0: U32, +fw: U32, +fh: U32) -> Bitmap:
  Bitmap.load.k(Bitmap.head(bs), List.drop(&2, U32, bs, 16n), x0, y0, fw, fh)

# Input
# -----

# is frame point (x, y) on the placed bitmap?
def Bitmap.hit(b: Bitmap, +x: U32, +y: U32) -> Bool:
  match b:
    case Bitmap{_, _, _, _, +x0, +y0, +fw, +fh}:
      Bool.and(Bool.and(U32.is_ge(x, x0), U32.is_lt(x, (x0 + fw : U32))), Bool.and(U32.is_ge(y, y0), U32.is_lt(y, (y0 + fh : U32))))

# a frame point as a page (source) pixel, for forwarding clicks
def Bitmap.page_x(b: Bitmap, +x: U32) -> U32:
  match b:
    case Bitmap{+w, +h, _, _, +x0, +y0, +fw, +fh}:
      BmGeo.sx(BmGeo{x0, y0, fw, fh, w, h}, x)

def Bitmap.page_y(b: Bitmap, +y: U32) -> U32:
  match b:
    case Bitmap{+w, +h, _, _, +x0, +y0, +fw, +fh}:
      BmGeo.sy(BmGeo{x0, y0, fw, fh, w, h}, y)
