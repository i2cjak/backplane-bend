import Base
import ../core/board.bend as B
import ../gfx/raster.bend as R
import ../gfx/draw.bend as D
import ../core/schematic.bend as SC
import ../core/glb.bend as G
import ../gfx/mesh.bend as MS
import ../gfx/bitmap.bend as BM
import ../core/look.bend as LO

# The board viewer. A scene is the board's items, each with the time it
# appeared. A new file merges into the scene by key: an item whose key and
# signature are unchanged keeps its birth time (law scene_merge_self: an
# unchanged board never re-fades); anything new or changed is born now and
# fades in. Geometry always comes from the newest file.

type Seen is Data:
  Seen{item: B.Item, born: Nat}

# Keys
# ----

def Key.of(i: B.Item) -> String:
  match i:
    case B.Item{k, _, _, _, _}:
      k

def Key.sig(i: B.Item) -> U32:
  match i:
    case B.Item{_, s, _, _, _}:
      s

def Key.cmp.fin(r: (String & String) & Cmp) -> Cmp:
  (_, c) = r
  c

# string order of two keys
def Key.cmp(a: String, b: String) -> Cmp:
  Key.cmp.fin(String.cmp(a, b))

def Key.le(a: B.Item, b: B.Item) -> Bool:
  Cmp.is_le(Key.cmp(Key.of(a), Key.of(b)))

# items in key order (merge needs both sides sorted)
def Scene.sort(+xs: List<&2, B.Item>) -> List<&2, B.Item>:
  List.sort(~B.Item, ~Key.le, xs)

# Merging
# -------

# the order of the two heads (EQ when either list is empty; unused then)
def Scene.heads(os: List<&2, Seen>, ns: List<&2, B.Item>) -> Cmp:
  match os ns:
    case Seen{+o, _} <> _ +n <> _:
      Key.cmp(Key.of(o), Key.of(n))
    case _ _:
      EQ{}

def Scene.keep(same: Bool, n: B.Item, +born: Nat, +now: Nat) -> Seen:
  match same:
    case True{}:
      Seen{n, born}
    case False{}:
      Seen{n, now}

def Scene.born(ns: List<&2, B.Item>, +now: Nat) -> List<&2, Seen>:
  match ns:
    case Nil{}:
      Nil{}
    case n <> t:
      Seen{n, now} <> Scene.born(t, now)

# the new items (sorted), each born now unless the old scene (sorted) had it
# unchanged; `c` is the order of the two lists' heads
def Scene.merge(+os: List<&2, Seen>, ns: List<&2, B.Item>, c: Cmp, +now: Nat) -> List<&2, Seen>:
  match os ns c:
    case Nil{} _ _:
      Scene.born(ns, now)
    case _ Nil{} _:
      Nil{}
    case _ <> +ot +n <> nt GT{}:
      Seen{n, now} <> Scene.merge(os, nt, Scene.heads(os, nt), now)
    case _ <> +ot +n <> +nt LT{}:
      Scene.merge(ot, n <> nt, Scene.heads(ot, n <> nt), now)
    case Seen{+o, +b} <> +ot +n <> nt EQ{}:
      Scene.keep(U32.is_eq(Key.sig(o), Key.sig(n)), n, b, now) <> Scene.merge(ot, nt, Scene.heads(ot, nt), now)

def Scene.update(+os: List<&2, Seen>, +ns: List<&2, B.Item>, +now: Nat) -> List<&2, Seen>:
  Scene.merge(os, ns, Scene.heads(os, ns), now)

# the items of a scene (what a re-read of the same file yields)
def Scene.items(ss: List<&2, Seen>) -> List<&2, B.Item>:
  match ss:
    case Nil{}:
      Nil{}
    case Seen{i, _} <> t:
      i <> Scene.items(t)

# Fading
# ------

def Fade.ms() -> Nat:
  220n

def Fade.alpha.k(done: Bool, +age: Nat) -> U32:
  match done:
    case True{}:
      255
    case False{}:
      U32.from_nat(Nat.div(Nat.mul(age, 255n), Fade.ms()))

# opacity of something born at `born`, now: 0 at birth, 255 once FADE ms
# have passed (law fade_done), in between a straight ramp
def Fade.alpha(+now: Nat, +born: Nat) -> U32:
  Fade.alpha.k(Nat.is_ge(now, Nat.add(born, Fade.ms())), Nat.sub(now, born))

# whether anything is still fading (the window keeps drawing only then)
def Fade.busy(ss: List<&2, Seen>, +now: Nat) -> Bool:
  match ss:
    case Nil{}:
      False{}
    case Seen{_, +b} <> t:
      Bool.or(Nat.is_lt(now, Nat.add(b, Fade.ms())), Fade.busy(t, now))

# Layers
# ------

# colour and opacity per layer index (B.Layer.names); 0 opacity hides it
def Layer.look(i: Nat) -> U32 & U32:
  LO.Look.board(i)

# View
# ----

# pixels per mm, and where the board's origin lands on screen
type View is Data:
  View{zoom: F32, ox: F32, oy: F32}

def View.x(v: View, +x: F32) -> F32:
  match v:
    case View{z, ox, _}:
      F32.add(ox, F32.mul(x, z))

def View.y(v: View, +y: F32) -> F32:
  match v:
    case View{z, _, oy}:
      F32.add(oy, F32.mul(y, z))

def View.p(+v: View, p: B.Pt) -> D.P2:
  match p:
    case B.Pt{x, y}:
      D.P2{View.x(v, x), View.y(v, y)}

def View.ps(ps: List<&2, B.Pt>, +v: View) -> List<&2, D.P2>:
  match ps:
    case Nil{}:
      Nil{}
    case p <> t:
      View.p(v, p) <> View.ps(t, v)

def View.w(v: View, +w: F32) -> F32:
  match v:
    case View{z, _, _}:
      F32.max(F32.mul(w, z), 1.0)

def View.box.pt(p: B.Pt, b: D.Box) -> D.Box:
  match p b:
    case B.Pt{+x, +y} D.Box{+x0, +y0, +x1, +y1}:
      D.Box{F32.min(x0, x), F32.min(y0, y), F32.max(x1, x), F32.max(y1, y)}

def View.box.pts(ps: List<&2, B.Pt>, b: D.Box) -> D.Box:
  match ps:
    case Nil{}:
      b
    case p <> t:
      View.box.pts(t, View.box.pt(p, b))

def View.box.prim(p: B.Prim, b: D.Box) -> D.Box:
  match p:
    case B.PSeg{a, e, _}:
      View.box.pt(e, View.box.pt(a, b))
    case B.PLine{ps, _}:
      View.box.pts(ps, b)
    case B.PCirc{c, _, _, _}:
      View.box.pt(c, b)
    case B.PPoly{ps, _, _}:
      View.box.pts(ps, b)

# the scene's extent in mm
def View.box(ss: List<&2, Seen>, b: D.Box) -> D.Box:
  match ss:
    case Nil{}:
      b
    case Seen{B.Item{_, _, _, p, _}, _} <> t:
      View.box(t, View.box.prim(p, b))

def View.fit.z(+z: F32, +cx: F32, +cy: F32, +x0: F32, +y0: F32, +w: F32, +h: F32) -> View:
  View{z, F32.sub(F32.add(x0, F32.div(w, 2.0)), F32.mul(cx, z)), F32.sub(F32.add(y0, F32.div(h, 2.0)), F32.mul(cy, z))}

def View.fit.k(b: D.Box, +x0: F32, +y0: F32, +w: F32, +h: F32) -> View:
  match b:
    case D.Box{+bx0, +by0, +bx1, +by1}:
      View.fit.z(F32.mul(0.9, F32.min(F32.div(w, F32.max(F32.sub(bx1, bx0), 1.0)), F32.div(h, F32.max(F32.sub(by1, by0), 1.0)))),
        F32.div(F32.add(bx0, bx1), 2.0), F32.div(F32.add(by0, by1), 2.0), x0, y0, w, h)

# the view that shows the whole scene in the w x h panel at (x0, y0)
def View.fit(+ss: List<&2, Seen>, +x0: F32, +y0: F32, +w: F32, +h: F32) -> View:
  View.fit.k(View.box(ss, D.Box{1000000.0, 1000000.0, F32.neg(1000000.0), F32.neg(1000000.0)}), x0, y0, w, h)

# zoom by f around screen point (px, py)
def View.zoom(v: View, +f: F32, +px: F32, +py: F32) -> View:
  match v:
    case View{z, ox, oy}:
      View{F32.mul(z, f), F32.add(px, F32.mul(F32.sub(ox, px), f)), F32.add(py, F32.mul(F32.sub(oy, py), f))}

def View.pan(v: View, +dx: F32, +dy: F32) -> View:
  match v:
    case View{z, ox, oy}:
      View{z, F32.add(ox, dx), F32.add(oy, dy)}

# Ops
# ---

def Ops.line(ps: List<&2, D.P2>, +c: D.Clip, +w: F32, +color: U32, +alpha: U32) -> List<&2, R.Op>:
  match ps:
    case D.P2{+ax, +ay} <> D.P2{+bx, +by} <> t:
      D.Draw.seg(c, ax, ay, bx, by, w, color, alpha) <> Ops.line(D.P2{bx, by} <> t, c, w, color, alpha)
    case _:
      Nil{}

def Ops.at(+i: Nat, +cx: F32, +cy: F32, +r: F32) -> D.P2:
  +a = F32.mul(F32.div(F32.from_nat(i), 32.0), F32.mul(2.0, F32.pi()))
  D.P2{F32.add(cx, F32.mul(r, F32.cos(a))), F32.add(cy, F32.mul(r, F32.sin(a)))}

def Ops.circle(n: Nat, +i: Nat, +cx: F32, +cy: F32, +r: F32) -> List<&2, D.P2>:
  match n:
    case 0n:
      [Ops.at(i, cx, cy, r)]
    case 1n+m:
      Ops.at(i, cx, cy, r) <> Ops.circle(m, 1n+i, cx, cy, r)

def Ops.ring(+c: D.Clip, +cx: F32, +cy: F32, +r: F32, +w: F32, +color: U32, +alpha: U32) -> List<&2, R.Op>:
  Ops.line(Ops.circle(32n, 0n, cx, cy, r), c, w, color, alpha)

def Ops.z(v: View) -> F32:
  match v:
    case View{z, _, _}:
      z

def Ops.prim(p: B.Prim, +v: View, +c: D.Clip, +color: U32, +alpha: U32) -> List<&2, R.Op>:
  match p:
    case B.PSeg{a, b, w}:
      Ops.line([View.p(v, a), View.p(v, b)], c, View.w(v, w), color, alpha)
    case B.PLine{ps, w}:
      Ops.line(View.ps(ps, v), c, View.w(v, w), color, alpha)
    case B.PCirc{B.Pt{+x, +y}, +r, +w, True{}}:
      [D.Draw.disc(c, View.x(v, x), View.y(v, y), F32.max(F32.mul(r, Ops.z(v)), 0.5), color, alpha)]
    case B.PCirc{B.Pt{+x, +y}, +r, +w, False{}}:
      Ops.ring(c, View.x(v, x), View.y(v, y), F32.mul(r, Ops.z(v)), View.w(v, w), color, alpha)
    case B.PPoly{+ps, w, True{}}:
      [D.Draw.poly(c, View.ps(ps, v), color, alpha)]
    case B.PPoly{+ps, +w, False{}}:
      Ops.line(List.append(&2, D.P2, View.ps(ps, v), [View.p(v, Maybe.default(&2, B.Pt, List.head(&2, B.Pt, ps), B.Pt{0.0, 0.0}))]), c, View.w(v, w), color, alpha)

def Ops.item.show(hidden: Bool, p: B.Prim, +v: View, +c: D.Clip, +color: U32, +alpha: U32) -> List<&2, R.Op>:
  match hidden:
    case True{}:
      Nil{}
    case False{}:
      Ops.prim(p, v, c, color, alpha)

def Ops.item.k(look: U32 & U32, p: B.Prim, +v: View, +c: D.Clip, +fade: U32) -> List<&2, R.Op>:
  (color, +base) = look
  Ops.item.show(U32.is_eq(base, 0), p, v, c, color, ((base * fade : U32) / 255 : U32))

# a layer's colour and opacity in a board (kind 0) or a schematic (kind 1)
def Look.of(+kind: U32, +layer: U32) -> U32 & U32:
  LO.Look.of(kind, layer)

def Look.count(+kind: U32) -> Nat:
  LO.Look.count(kind)

def Ops.layer.k(on: Bool, p: B.Prim, +layer: U32, +v: View, +c: D.Clip, +fade: U32, +kind: U32, rest: List<&2, R.Op>) -> List<&2, R.Op>:
  match on:
    case True{}:
      List.append(&2, R.Op, Ops.item.k(Look.of(kind, layer), p, v, c, fade), rest)
    case False{}:
      rest

def Ops.pick(keep: Bool, on: Bool, p: B.Prim, +layer: U32, +v: View, +c: D.Clip, +fade: U32, +kind: U32, rest: List<&2, R.Op>) -> List<&2, R.Op>:
  match keep:
    case True{}:
      Ops.layer.k(on, p, layer, v, c, fade, kind, rest)
    case False{}:
      rest

# what the viewer shows: kind 0 board, 1 schematic, 2 3D, 3 the agents'
# browser (`bmp` its latest frame); `pick` is the
# selected item's key; `tris` and `cam` the 3D model and camera; `shown`
# the source (Src.key) the scene belongs to; `busy` a status line; (px,
# py) where the pointer went down; `path` a file an agent asked to show
type Vx is Data:
  Vx{kind: U32, pick: String, tris: List<&2, G.Tri3>, cam: MS.Cam, shown: String, busy: String, px: U32, py: U32, path: String, seen: String, bmp: BM.Bitmap}

# Viewer state (held by the window's state)
# ----------------------------------------

# the scene and its view; `root` is the project the scene belongs to;
# `base` caches the settled board drawn at `view` (valid while `fresh`)
# `cut` is when the base was drawn: the base holds exactly the items whose
# fade had ended by then; the rest are drawn over it every frame
type Vw is Data:
  Vw{scene: List<&2, Seen>, view: View, fitted: Bool, root: String, drag: Bool, lx: U32, ly: U32, base: Image, fresh: Bool, cut: Nat, x: Vx}

def Vx.init() -> Vx:
  Vx{0, "", Nil{}, MS.Cam{0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.8}, "", "", 0, 0, "", "", BM.Bitmap{0, 0, 0n, Pix{0}, 0, 0, 0, 0}}

def Vw.init() -> Vw:
  Vw{Nil{}, View{1.0, 0.0, 0.0}, False{}, "", False{}, 0, 0, Pix{0}, False{}, 0n, Vx.init()}

# the source a scene comes from: kind, project root and an explicit path
def Src.key(+kind: U32, +root: String, +path: String) -> String:
  U32.show(kind) ++ "|" ++ root ++ "|" ++ path

# whether an item belongs in a base drawn at `cut`
def Vw.settled(+born: Nat, +cut: Nat) -> Bool:
  Nat.is_le(Nat.add(born, Fade.ms()), cut)

# the ops of one layer's items, in paint order: those in a base drawn at
# `cut` when `base` is set, the others when it is not
def Ops.layer(ss: List<&2, Seen>, +layer: U32, +v: View, +c: D.Clip, +now: Nat, +cut: Nat, +base: Bool, +kind: U32) -> List<&2, R.Op>:
  match ss:
    case Nil{}:
      Nil{}
    case Seen{B.Item{_, _, +l, p, _}, +b} <> t:
      Ops.pick(Bool.not(Bool.xor(base, Vw.settled(b, cut))), U32.is_eq(l, layer), p, layer, v, c, Fade.alpha(now, b), kind,
        Ops.layer(t, layer, v, c, now, cut, base, kind))

def Ops.layers(n: Nat, +i: U32, +ss: List<&2, Seen>, +v: View, +c: D.Clip, +now: Nat, +cut: Nat, +base: Bool, +kind: U32) -> List<&2, R.Op>:
  match n:
    case 0n:
      Nil{}
    case 1n+m:
      List.append(&2, R.Op, Ops.layer(ss, i, v, c, now, cut, base, kind), Ops.layers(m, (i + 1 : U32), ss, v, c, now, cut, base, kind))

# the whole scene bottom-up (paint order), cut to the panel
def Ops.scene(+ss: List<&2, Seen>, +v: View, +c: D.Clip, +now: Nat, +cut: Nat, +base: Bool, +kind: U32) -> List<&2, R.Op>:
  Ops.layers(Look.count(kind), 0, ss, v, c, now, cut, base, kind)

# Picking
# -------
# A click picks the smallest visible item under the pointer (a pad over
# the zone it sits in); tol is a few pixels in mm.

def Pick.d2(+ax: F32, +ay: F32, +bx: F32, +by: F32) -> F32:
  F32.add(F32.mul(F32.sub(ax, bx), F32.sub(ax, bx)), F32.mul(F32.sub(ay, by), F32.sub(ay, by)))

# distance from (x, y) to the segment a-b
def Pick.seg(a: B.Pt, b: B.Pt, +x: F32, +y: F32) -> F32:
  match a b:
    case B.Pt{+ax, +ay} B.Pt{+bx, +by}:
      +dx = F32.sub(bx, ax)
      +dy = F32.sub(by, ay)
      +l2 = F32.max(F32.add(F32.mul(dx, dx), F32.mul(dy, dy)), 0.000001)
      +t = F32.max(0.0, F32.min(1.0, F32.div(F32.add(F32.mul(F32.sub(x, ax), dx), F32.mul(F32.sub(y, ay), dy)), l2)))
      F32.sqrt(Pick.d2(x, y, F32.add(ax, F32.mul(t, dx)), F32.add(ay, F32.mul(t, dy))))

def Pick.path(ps: List<&2, B.Pt>, +x: F32, +y: F32, +acc: F32) -> F32:
  match ps:
    case +a <> +b <> t:
      Pick.path(b <> t, x, y, F32.min(acc, Pick.seg(a, b, x, y)))
    case _:
      acc

def Pick.inside(b: D.Box, +x: F32, +y: F32) -> Bool:
  match b:
    case D.Box{x0, y0, x1, y1}:
      Bool.and(Bool.and(F32.is_ge(x, x0), F32.is_le(x, x1)), Bool.and(F32.is_ge(y, y0), F32.is_le(y, y1)))

def Pick.area(b: D.Box) -> F32:
  match b:
    case D.Box{x0, y0, x1, y1}:
      F32.mul(F32.max(F32.sub(x1, x0), 0.01), F32.max(F32.sub(y1, y0), 0.01))

def Pick.big() -> D.Box:
  D.Box{1000000.0, 1000000.0, F32.neg(1000000.0), F32.neg(1000000.0)}

def Pick.circ(c: B.Pt, +r: F32) -> D.Box:
  match c:
    case B.Pt{+x, +y}:
      D.Box{F32.sub(x, r), F32.sub(y, r), F32.add(x, r), F32.add(y, r)}

# whether the prim is under (x, y), and its size (for the smallest-wins rule)
def Pick.hit(p: B.Prim, +x: F32, +y: F32, +tol: F32) -> Bool & F32:
  match p:
    case B.PSeg{+a, +b, +w}:
      (F32.is_le(Pick.seg(a, b, x, y), F32.add(F32.mul(w, 0.5), tol)), Pick.area(View.box.pt(b, View.box.pt(a, Pick.big()))))
    case B.PLine{+ps, +w}:
      (F32.is_le(Pick.path(ps, x, y, 1000000.0), F32.add(F32.mul(w, 0.5), tol)), Pick.area(View.box.pts(ps, Pick.big())))
    case B.PCirc{B.Pt{+cx, +cy}, +r, +w, True{}}:
      (F32.is_le(F32.sqrt(Pick.d2(x, y, cx, cy)), F32.add(r, tol)), F32.mul(F32.mul(r, r), 4.0))
    case B.PCirc{B.Pt{+cx, +cy}, +r, +w, False{}}:
      (F32.is_le(F32.abs(F32.sub(F32.sqrt(Pick.d2(x, y, cx, cy)), r)), F32.add(F32.mul(w, 0.5), tol)), F32.mul(F32.mul(r, r), 4.0))
    case B.PPoly{+ps, _, True{}}:
      (Pick.inside(View.box.pts(ps, Pick.big()), x, y), Pick.area(View.box.pts(ps, Pick.big())))
    case B.PPoly{+ps, +w, False{}}:
      (F32.is_le(Pick.path(ps, x, y, 1000000.0), F32.add(F32.mul(w, 0.5), tol)), Pick.area(View.box.pts(ps, Pick.big())))

def Pick.better.k(take: Bool, +key: String, +area: F32, bk: String, +ba: F32) -> String & F32:
  match take:
    case True{}:
      (key, area)
    case False{}:
      (bk, ba)

def Pick.better(r: Bool & F32, +shown: Bool, +key: String, best: String & F32) -> String & F32:
  (hit, +area) = r
  (bk, +ba) = best
  Pick.better.k(Bool.and(Bool.and(hit, shown), F32.is_lt(area, ba)), key, area, bk, ba)

def Look.alpha.k(l: U32 & U32) -> U32:
  (_, a) = l
  a

def Look.alpha(+kind: U32, +layer: U32) -> U32:
  Look.alpha.k(Look.of(kind, layer))

def Pick.go(ss: List<&2, Seen>, +x: F32, +y: F32, +tol: F32, +kind: U32, best: String & F32) -> String & F32:
  match ss:
    case Nil{}:
      best
    case Seen{B.Item{+k, _, +l, p, _}, _} <> t:
      Pick.go(t, x, y, tol, kind, Pick.better(Pick.hit(p, x, y, tol), U32.is_gt(Look.alpha(kind, l), 0), k, best))

def Pick.key(r: String & F32) -> String:
  (k, _) = r
  k

# the key of the item under screen point (sx, sy), "" for none
def Pick.at(+ss: List<&2, Seen>, v: View, +sx: F32, +sy: F32, +kind: U32) -> String:
  match v:
    case View{+z, +ox, +oy}:
      Pick.key(Pick.go(ss, F32.div(F32.sub(sx, ox), z), F32.div(F32.sub(sy, oy), z), F32.div(4.0, z), kind, ("", 1000000000000.0)))

# the picked item's info ("" when it is gone)
def Pick.info(ss: List<&2, Seen>, +key: String) -> String:
  match ss:
    case Nil{}:
      ""
    case Seen{B.Item{+k, _, _, _, info}, _} <> t:
      Bool.pick(String, String.eq(k, key), info, Pick.info(t, key))

# (a match: only the picked item's ops are made, not every item's)
def Ops.picked.k(hit: Bool, p: B.Prim, +v: View, +c: D.Clip, rest: List<&2, R.Op>) -> List<&2, R.Op>:
  match hit:
    case True{}:
      Ops.prim(p, v, c, 16777215, 200)
    case False{}:
      rest

# the picked item drawn again on top, bright
def Ops.picked(ss: List<&2, Seen>, +key: String, +v: View, +c: D.Clip) -> List<&2, R.Op>:
  match ss:
    case Nil{}:
      Nil{}
    case Seen{B.Item{+k, _, _, p, _}, _} <> t:
      Ops.picked.k(String.eq(k, key), p, v, c, Ops.picked(t, key, v, c))

# some item's fade ended after the base was drawn: fold it into the base
def Vw.late(ss: List<&2, Seen>, +cut: Nat, +now: Nat) -> Bool:
  match ss:
    case Nil{}:
      False{}
    case Seen{_, +b} <> t:
      Bool.or(Bool.and(Bool.not(Vw.settled(b, cut)), Vw.settled(b, now)), Vw.late(t, cut, now))
