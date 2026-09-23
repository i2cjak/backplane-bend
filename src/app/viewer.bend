import Base
import ../core/board.bend as B
import ../gfx/raster.bend as R
import ../gfx/draw.bend as D

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
  match i:
    case 0n:
      (5791108, 0)
    case 1n:
      (2549247, 0)
    case 2n:
      (49858, 0)
    case 3n:
      (15250087, 200)
    case 4n:
      (196590, 0)
    case 5n:
      (5078980, 190)
    case 6n:
      (8421631, 150)
    case 7n:
      (13148979, 150)
    case 8n:
      (12900552, 150)
    case 9n:
      (8374015, 150)
    case 10n:
      (13532460, 160)
    case 11n:
      (8340095, 160)
    case 12n:
      (13120564, 210)
    case 13n:
      (13148212, 220)
    case 14n:
      (14045866, 0)
    case 15n:
      (11513775, 0)
    case 16n:
      (15920545, 230)
    case 17n:
      (16721634, 0)
    case 18n:
      (11513775, 0)
    case 22n:
      (13685453, 255)
    case 23n:
      (11842740, 255)
    case 24n:
      (526603, 255)
    case _:
      (10000536, 90)

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

def Ops.layer.k(on: Bool, p: B.Prim, +layer: U32, +v: View, +c: D.Clip, +fade: U32, rest: List<&2, R.Op>) -> List<&2, R.Op>:
  match on:
    case True{}:
      List.append(&2, R.Op, Ops.item.k(Layer.look(U32.to_nat(layer)), p, v, c, fade), rest)
    case False{}:
      rest

def Ops.pick(keep: Bool, on: Bool, p: B.Prim, +layer: U32, +v: View, +c: D.Clip, +fade: U32, rest: List<&2, R.Op>) -> List<&2, R.Op>:
  match keep:
    case True{}:
      Ops.layer.k(on, p, layer, v, c, fade, rest)
    case False{}:
      rest

# Viewer state (held by the window's state)
# ----------------------------------------

# the scene and its view; `root` is the project the scene belongs to;
# `base` caches the settled board drawn at `view` (valid while `fresh`)
# `cut` is when the base was drawn: the base holds exactly the items whose
# fade had ended by then; the rest are drawn over it every frame
type Vw is Data:
  Vw{scene: List<&2, Seen>, view: View, fitted: Bool, root: String, drag: Bool, lx: U32, ly: U32, base: Image, fresh: Bool, cut: Nat}

def Vw.init() -> Vw:
  Vw{Nil{}, View{1.0, 0.0, 0.0}, False{}, "", False{}, 0, 0, Pix{0}, False{}, 0n}

# whether an item belongs in a base drawn at `cut`
def Vw.settled(+born: Nat, +cut: Nat) -> Bool:
  Nat.is_le(Nat.add(born, Fade.ms()), cut)

# the ops of one layer's items, in paint order: those in a base drawn at
# `cut` when `base` is set, the others when it is not
def Ops.layer(ss: List<&2, Seen>, +layer: U32, +v: View, +c: D.Clip, +now: Nat, +cut: Nat, +base: Bool) -> List<&2, R.Op>:
  match ss:
    case Nil{}:
      Nil{}
    case Seen{B.Item{_, _, +l, p, _}, +b} <> t:
      Ops.pick(Bool.not(Bool.xor(base, Vw.settled(b, cut))), U32.is_eq(l, layer), p, layer, v, c, Fade.alpha(now, b),
        Ops.layer(t, layer, v, c, now, cut, base))

def Ops.layers(n: Nat, +i: U32, +ss: List<&2, Seen>, +v: View, +c: D.Clip, +now: Nat, +cut: Nat, +base: Bool) -> List<&2, R.Op>:
  match n:
    case 0n:
      Nil{}
    case 1n+m:
      List.append(&2, R.Op, Ops.layer(ss, i, v, c, now, cut, base), Ops.layers(m, (i + 1 : U32), ss, v, c, now, cut, base))

# the whole scene bottom-up (paint order), cut to the panel
def Ops.scene(+ss: List<&2, Seen>, +v: View, +c: D.Clip, +now: Nat, +cut: Nat, +base: Bool) -> List<&2, R.Op>:
  Ops.layers(25n, 0, ss, v, c, now, cut, base)

# some item's fade ended after the base was drawn: fold it into the base
def Vw.late(ss: List<&2, Seen>, +cut: Nat, +now: Nat) -> Bool:
  match ss:
    case Nil{}:
      False{}
    case Seen{_, +b} <> t:
      Bool.or(Bool.and(Bool.not(Vw.settled(b, cut)), Vw.settled(b, now)), Vw.late(t, cut, now))
