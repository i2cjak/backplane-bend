import Base
import ../core/board.bend as B
import ../core/glb.bend as G
import ../core/pcb3d.bend as P
import ./raster.bend as R
import ./draw.bend as D
import ./mesh.bend as MS

# A board in 3D, drawn from its own items rather than a mesh export. Its
# visible face (the top, or the bottom when the eye is below the board) is
# painted by the 2D rasterizer from the board's items projected through the
# camera: exact at any zoom, anti-aliased, and made again each frame for
# the new view. The mask over bare board, copper under the mask, silk,
# bare copper (pads, mask openings) and holes paint in that order; holes
# and everything off the outline are Face.key(), where the rasterizer
# looks through. The board's edges (and the walls of larger holes) are
# triangles in the model, so parts, walls and face meet in one z-buffer.

# the prims of each paint class on one side: copper under the mask, silk,
# mask openings, pads (bare copper), holes, and the copper that may show
# through an opening
type L4 is Data:
  L4{cu: List<&2, B.Prim>, silk: List<&2, B.Prim>, open: List<&2, B.Prim>, bare: List<&2, B.Prim>, holes: List<&2, B.Prim>, cand: List<&2, B.Prim>}

type Face3 is Data:
  FNone{}
  Face3{thick: F32, look: P.Look, outline: List<&2, B.Prim>, top: L4, bot: L4}

# what the 3D viewer holds: the model (board edges, then parts as they
# arrive), the board's face (none for a plain model; kept in a list, as
# the compiler would otherwise flatten the whole face into the viewer's
# state and exceed its arity limit), and when the board arrived (ms),
# which names the read its parts belong to, and when the viewer got it
# (ms), which decides whether a part is late enough to fade in
type Scene3 is Data:
  Scene3{model: MS.Model, face: List<&2, Face3>, t0: Nat, at: Nat}

def Scene3.none() -> Scene3:
  Scene3{MS.Model.none(), Nil{}, 0n, 0n}

# a plain model (a STEP or GLB file) with no board face
def Scene3.of_model(m: MS.Model) -> Scene3:
  Scene3{m, Nil{}, 0n, 0n}

# the scene as the viewer got it at `now`
def Scene3.got(s: Scene3, +now: Nat) -> Scene3:
  match s:
    case Scene3{m, f, t0, _}:
      Scene3{m, f, t0, now}

def Scene3.model(s: Scene3) -> MS.Model:
  match s:
    case Scene3{m, _, _, _}:
      m

def Scene3.is_empty(s: Scene3) -> Bool:
  match s:
    case Scene3{m, Nil{}, _, _}:
      MS.Model.is_empty(m)
    case _:
      False{}

def Scene3.fading(s: Scene3, +now: Nat) -> Bool:
  match s:
    case Scene3{m, _, _, _}:
      MS.Model.fading(m, now)

def Scene3.fit(s: Scene3) -> MS.Cam:
  match s:
    case Scene3{m, _, _, _}:
      MS.Model.fit(m)

# Sorting items
# -------------

def L4.none() -> L4:
  L4{Nil{}, Nil{}, Nil{}, Nil{}, Nil{}, Nil{}}

def L4.add.k(c1: Bool, c2: Bool, c3: Bool, c4: Bool, c5: Bool, +p: B.Prim, l: L4) -> L4:
  match c1 c2 c3 c4 c5 l:
    case True{} _ _ _ _ L4{a, b, o, c, d, e}:
      L4{p <> a, b, o, c, d, e}
    case _ True{} _ _ _ L4{a, b, o, c, d, e}:
      L4{a, p <> b, o, c, d, e}
    case _ _ True{} _ _ L4{a, b, o, c, d, e}:
      L4{a, b, o, p <> c, d, e}
    case _ _ _ True{} _ L4{a, b, o, c, d, e}:
      L4{a, b, o, c, p <> d, e}
    case _ _ _ _ True{} L4{a, b, o, c, d, e}:
      L4{a, b, p <> o, c, d, e}
    case _ _ _ _ _ _:
      l

# class 1 copper under mask, 2 silk, 3 bare copper, 4 hole, 5 mask
# opening, 0 not drawn
def L4.add(+c: U32, +p: B.Prim, l: L4) -> L4:
  L4.add.k(U32.is_eq(c, 1), U32.is_eq(c, 2), U32.is_eq(c, 3), U32.is_eq(c, 4), U32.is_eq(c, 5), p, l)

# Openings
# --------
# Copper shows (as bare finish) only where the mask is open. Which copper
# an opening may uncover is found once, by bounding boxes.

type PBox is Data:
  PBox{x0: F32, y0: F32, x1: F32, y1: F32}

def PBox.pts(ps: List<&2, B.Pt>, +r: F32, b: PBox) -> PBox:
  match ps b:
    case Nil{} _:
      b
    case B.Pt{+x, +y} <> t PBox{+x0, +y0, +x1, +y1}:
      PBox.pts(t, r, PBox{F32.min(x0, F32.sub(x, r)), F32.min(y0, F32.sub(y, r)), F32.max(x1, F32.add(x, r)), F32.max(y1, F32.add(y, r))})

def PBox.none() -> PBox:
  PBox{1000000.0, 1000000.0, F32.neg(1000000.0), F32.neg(1000000.0)}

def PBox.of(p: B.Prim) -> PBox:
  match p:
    case B.PSeg{a, b, +w}:
      PBox.pts([a, b], F32.mul(0.5, w), PBox.none())
    case B.PLine{ps, +w}:
      PBox.pts(ps, F32.mul(0.5, w), PBox.none())
    case B.PCirc{c, +r, +w, _}:
      PBox.pts([c], F32.add(r, F32.mul(0.5, w)), PBox.none())
    case B.PPoly{ps, +w, _}:
      PBox.pts(ps, F32.mul(0.5, w), PBox.none())

def PBox.meets(a: PBox, b: PBox) -> Bool:
  match a b:
    case PBox{+ax0, +ay0, +ax1, +ay1} PBox{+bx0, +by0, +bx1, +by1}:
      Bool.and(Bool.and(F32.is_le(ax0, bx1), F32.is_le(bx0, ax1)), Bool.and(F32.is_le(ay0, by1), F32.is_le(by0, ay1)))

def PBox.all(ps: List<&2, B.Prim>) -> List<&2, PBox>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      PBox.of(p) <> PBox.all(t)

def PBox.any(bs: List<&2, PBox>, +b: PBox) -> Bool:
  match bs:
    case Nil{}:
      False{}
    case +x <> t:
      Bool.or(PBox.meets(x, b), PBox.any(t, b))

def Cand.keep(hit: Bool, +p: B.Prim, rest: List<&2, B.Prim>) -> List<&2, B.Prim>:
  match hit:
    case True{}:
      p <> rest
    case False{}:
      rest

def Cand.go(ps: List<&2, B.Prim>, +bs: List<&2, PBox>) -> List<&2, B.Prim>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      Cand.keep(PBox.any(bs, PBox.of(p)), p, Cand.go(t, bs))

def Cand.of(l: L4) -> L4:
  match l:
    case L4{+cu, silk, +op, bare, holes, _}:
      L4{cu, silk, op, bare, holes, Bool.pick(List<&2, B.Prim>, List.is_empty(&2, B.Prim, op), Nil{}, Cand.go(cu, PBox.all(op)))}

# layer ids are board.bend's Layer.names
def Cls.side(+layer: U32, +pad: Bool, +cu: U32, +mask: U32, +silk: U32) -> U32:
  Bool.pick(U32, U32.is_eq(layer, cu), Bool.pick(U32, pad, 3, 1),
  Bool.pick(U32, U32.is_eq(layer, 13), 3,
  Bool.pick(U32, U32.is_eq(layer, mask), 5,
  Bool.pick(U32, U32.is_eq(layer, silk), 2,
  Bool.pick(U32, U32.is_eq(layer, 23), 1,
  Bool.pick(U32, U32.is_eq(layer, 24), 4, 0))))))

type Sort is Data:
  Sort{o: List<&2, B.Prim>, t: L4, b: L4}

def Sort.o(edge: Bool, +p: B.Prim, o: List<&2, B.Prim>) -> List<&2, B.Prim>:
  match edge:
    case True{}:
      p <> o
    case False{}:
      o

def Sort.put(+it: B.Item, s: Sort) -> Sort:
  match it s:
    case B.Item{_, _, +layer, +p, +info} Sort{o, t, b}:
      +pad = String.starts_with(info, "pad")
      Sort{Sort.o(U32.is_eq(layer, 22), p, o), L4.add(Cls.side(layer, pad, 12, 14, 16), p, t), L4.add(Cls.side(layer, pad, 5, 4, 3), p, b)}

def Sort.go(its: List<&2, B.Item>, s: Sort) -> Sort:
  match its:
    case Nil{}:
      s
    case +i <> t:
      Sort.go(t, Sort.put(i, s))

def Face3.k(+thick: F32, +look: P.Look, s: Sort) -> Face3:
  match s:
    case Sort{o, t, b}:
      Face3{thick, look, o, Cand.of(t), Cand.of(b)}

# a board's face from its items and its 3D facts (silk text included)
def Face3.of(+items: List<&2, B.Item>, p: P.Pcb3) -> Face3:
  match p:
    case P.Pcb3{+thick, +look, +text, _}:
      Face3.k(thick, look, Sort.go(List.append(&2, B.Item, text, items), Sort{Nil{}, L4.none(), L4.none()}))

# Walls
# -----

def Wall.rgb(+c: U32) -> U32:
  U32.and(c, 16777215)

# a vertical quad from (ax, ay) to (bx, by), y0 to y1 high, both windings
def Wall.quad(+ax: F32, +ay: F32, +bx: F32, +by: F32, +y0: F32, +y1: F32, +col: U32, acc: List<&2, G.Tri3>) -> List<&2, G.Tri3>:
  G.Tri3{ax, y0, ay, bx, y0, by, bx, y1, by, col} <> G.Tri3{ax, y0, ay, bx, y1, by, ax, y1, ay, col}
    <> G.Tri3{ax, y0, ay, bx, y1, by, bx, y0, by, col} <> G.Tri3{ax, y0, ay, ax, y1, ay, bx, y1, by, col} <> acc

def Wall.path(ps: List<&2, B.Pt>, +y0: F32, +y1: F32, +col: U32, acc: List<&2, G.Tri3>) -> List<&2, G.Tri3>:
  match ps:
    case B.Pt{+ax, +ay} <> B.Pt{+bx, +by} <> t:
      Wall.path(B.Pt{bx, by} <> t, y0, y1, col, Wall.quad(ax, ay, bx, by, y0, y1, col, acc))
    case _:
      acc

def Circ.pt(+cx: F32, +cy: F32, +r: F32, +i: Nat, +n: Nat) -> B.Pt:
  +a = F32.mul(F32.mul(2.0, F32.pi()), F32.div(F32.from_nat(i), F32.from_nat(n)))
  B.Pt{F32.add(cx, F32.mul(r, F32.cos(a))), F32.add(cy, F32.mul(r, F32.sin(a)))}

# n + 1 points round a circle (the last is the first again)
def Circ.pts(+k: Nat, +cx: F32, +cy: F32, +r: F32, +n: Nat, acc: List<&2, B.Pt>) -> List<&2, B.Pt>:
  match k:
    case 0n:
      Circ.pt(cx, cy, r, 0n, n) <> acc
    case 1n+j:
      Circ.pts(j, cx, cy, r, n, Circ.pt(cx, cy, r, k, n) <> acc)

def Wall.close(ps: List<&2, B.Pt>) -> List<&2, B.Pt>:
  match ps:
    case +p <> t:
      List.append(&2, B.Pt, p <> t, [p])
    case Nil{}:
      Nil{}

# the walls along an outline prim
def Wall.prim(p: B.Prim, +y0: F32, +y1: F32, +col: U32, acc: List<&2, G.Tri3>) -> List<&2, G.Tri3>:
  match p:
    case B.PSeg{a, b, _}:
      Wall.path([a, b], y0, y1, col, acc)
    case B.PLine{ps, _}:
      Wall.path(ps, y0, y1, col, acc)
    case B.PCirc{B.Pt{+cx, +cy}, +r, _, _}:
      Wall.path(Circ.pts(48n, cx, cy, r, 48n, Nil{}), y0, y1, col, acc)
    case B.PPoly{ps, _, _}:
      Wall.path(Wall.close(ps), y0, y1, col, acc)

def Wall.all(ps: List<&2, B.Prim>, +y0: F32, +y1: F32, +col: U32, acc: List<&2, G.Tri3>) -> List<&2, G.Tri3>:
  match ps:
    case Nil{}:
      acc
    case p <> t:
      Wall.all(t, y0, y1, col, Wall.prim(p, y0, y1, col, acc))

# a plated wall round a hole big enough to see into
def Wall.hole(p: B.Prim, +y0: F32, +y1: F32, +col: U32, acc: List<&2, G.Tri3>) -> List<&2, G.Tri3>:
  match p:
    case B.PCirc{B.Pt{+cx, +cy}, +r, _, _}:
      Bool.pick(List<&2, G.Tri3>, F32.is_ge(r, 0.25), Wall.path(Circ.pts(20n, cx, cy, r, 20n, Nil{}), y0, y1, col, Nil{}), Nil{})
    case _:
      Nil{}

def Wall.holes(ps: List<&2, B.Prim>, +y0: F32, +y1: F32, +col: U32, acc: List<&2, G.Tri3>) -> List<&2, G.Tri3>:
  match ps:
    case Nil{}:
      acc
    case p <> t:
      Wall.holes(t, y0, y1, col, List.append(&2, G.Tri3, Wall.hole(p, y0, y1, col, Nil{}), acc))

# the board's edges and hole walls, as triangles
def Face3.walls(f: Face3) -> List<&2, G.Tri3>:
  match f:
    case FNone{}:
      Nil{}
    case Face3{+thick, P.Look{+body, _, _, _, +fin, _}, o, L4{_, _, _, _, hs, _}, _}:
      Wall.all(o, 0.0, thick, Wall.rgb(body), Wall.holes(hs, 0.0, thick, Wall.rgb(fin), Nil{}))

# a board as a scene: its face, and its walls as the first triangles
def Scene3.board(+f: Face3, +now: Nat) -> Scene3:
  Scene3{MS.Model.of(Face3.walls(f)), [f], now, now}

# parts (world triangles) that arrived at `now`: faded in, unless they
# came so soon after the board (350 ms) that it looks like one arrival
def Scene3.add(s: Scene3, +ts: List<&2, G.Tri3>, +now: Nat) -> Scene3:
  match s:
    case Scene3{m, f, t0, +at}:
      Scene3{MS.Model.add(m, ts, Bool.pick(Nat, Nat.is_lt(Nat.sub(now, at), 350n), 0n, now)), f, t0, at}

def Scene3.add_if.k(same: Bool, s: Scene3, +ts: List<&2, G.Tri3>, +now: Nat) -> Scene3:
  match same:
    case True{}:
      Scene3.add(s, ts, now)
    case False{}:
      s

def Scene3.t0(s: Scene3) -> Nat:
  match s:
    case Scene3{_, _, t0, _}:
      t0

# parts for the scene made at t0 (parts of an older read are dropped)
def Scene3.add_if(+s: Scene3, +t0: Nat, +ts: List<&2, G.Tri3>, +now: Nat) -> Scene3:
  Scene3.add_if.k(Nat.is_eq(Scene3.t0(s), t0), s, ts, now)

# Projecting the face
# -------------------

def Face.p2(p: MS.VP) -> D.P2:
  match p:
    case MS.VP{x, y, _}:
      D.P2{x, y}

def Face.in(+n: F32, p: MS.VP) -> Bool:
  match p:
    case MS.VP{_, _, z}:
      F32.is_gt(z, n)

# one edge (prev -> cur) of Sutherland-Hodgman against the near plane
def Near.edge(pin: Bool, cin: Bool, +prev: MS.VP, +cur: MS.VP, +n: F32, acc: List<&2, MS.VP>) -> List<&2, MS.VP>:
  match pin cin:
    case True{} True{}:
      cur <> acc
    case False{} True{}:
      cur <> MS.VP.cut(cur, prev, n) <> acc
    case True{} False{}:
      MS.VP.cut(prev, cur, n) <> acc
    case False{} False{}:
      acc

def Near.go(ps: List<&2, MS.VP>, +prev: MS.VP, +n: F32, acc: List<&2, MS.VP>) -> List<&2, MS.VP>:
  match ps:
    case Nil{}:
      acc
    case +c <> t:
      Near.go(t, c, n, Near.edge(Face.in(n, prev), Face.in(n, c), prev, c, n, acc))

def Near.last(ps: List<&2, MS.VP>) -> MS.VP:
  match ps:
    case p <> Nil{}:
      p
    case _ <> t:
      Near.last(t)
    case Nil{}:
      MS.VP{0.0, 0.0, 0.0}

# the part of a polygon (view space) past the near plane
def Near.poly(+ps: List<&2, MS.VP>, +n: F32) -> List<&2, MS.VP>:
  Near.go(ps, Near.last(ps), n, Nil{})

def Face.vps(ps: List<&2, B.Pt>, +v: MS.View, +h: F32) -> List<&2, MS.VP>:
  match ps:
    case Nil{}:
      Nil{}
    case B.Pt{+x, +y} <> t:
      MS.View.pt(v, x, h, y) <> Face.vps(t, v, h)

def Face.scr(ps: List<&2, MS.VP>, +v: MS.View) -> List<&2, D.P2>:
  match ps:
    case Nil{}:
      Nil{}
    case p <> t:
      Face.p2(MS.View.proj(v, p)) <> Face.scr(t, v)

def Ops.put(ok: Bool, o: R.Op, acc: List<&2, R.Op>) -> List<&2, R.Op>:
  match ok:
    case True{}:
      o <> acc
    case False{}:
      acc

def Face.poly.k(+ps: List<&2, D.P2>, +clip: D.Clip, +col: U32, acc: List<&2, R.Op>) -> List<&2, R.Op>:
  Ops.put(Nat.is_ge(List.length(&2, D.P2, ps), 3n), D.Draw.poly(clip, ps, col, 255), acc)

# a filled polygon of board points
def Face.poly(+ps: List<&2, B.Pt>, +v: MS.View, +h: F32, +clip: D.Clip, +col: U32, acc: List<&2, R.Op>) -> List<&2, R.Op>:
  Face.poly.k(Face.scr(Near.poly(Face.vps(ps, v, h), MS.View.near(v)), v), clip, col, acc)

# the half width on screen of a track w wide at board point (mx, my)
# running along (dx, dy): its two sides projected, so a track seen edge-on
# narrows as it should
def Face.hw.k(p: MS.VP, q: MS.VP, +n: F32) -> F32:
  match p q:
    case MS.VP{+px, +py, +pz} MS.VP{+qx, +qy, +qz}:
      Bool.pick(F32, Bool.and(F32.is_gt(pz, n), F32.is_gt(qz, n)), F32.mul(0.5, F32.hypot(F32.sub(qx, px), F32.sub(qy, py))), 0.5)

def Face.hw(+v: MS.View, +h: F32, +mx: F32, +my: F32, +dx: F32, +dy: F32, +w: F32) -> F32:
  +len = F32.max(F32.hypot(dx, dy), 0.000001)
  +nx = F32.mul(F32.neg(F32.div(dy, len)), F32.mul(0.5, w))
  +ny = F32.mul(F32.div(dx, len), F32.mul(0.5, w))
  Face.hw.k(MS.View.screen(v, F32.add(mx, nx), h, F32.add(my, ny)), MS.View.screen(v, F32.sub(mx, nx), h, F32.sub(my, ny)), MS.View.near(v))

def Face.cap.k(p: MS.VP, q: MS.VP, +hw: F32, +clip: D.Clip, +col: U32, acc: List<&2, R.Op>) -> List<&2, R.Op>:
  match p q:
    case MS.VP{ax, ay, _} MS.VP{bx, by, _}:
      D.Draw.seg(clip, ax, ay, bx, by, F32.mul(2.0, hw), col, 255) <> acc

def Face.cap(ia: Bool, ib: Bool, +v: MS.View, +a: MS.VP, +b: MS.VP, +hw: F32, +clip: D.Clip, +col: U32, acc: List<&2, R.Op>) -> List<&2, R.Op>:
  match ia ib:
    case True{} True{}:
      Face.cap.k(MS.View.proj(v, a), MS.View.proj(v, b), hw, clip, col, acc)
    case True{} False{}:
      Face.cap.k(MS.View.proj(v, a), MS.View.proj(v, MS.VP.cut(a, b, MS.View.near(v))), hw, clip, col, acc)
    case False{} True{}:
      Face.cap.k(MS.View.proj(v, MS.VP.cut(b, a, MS.View.near(v))), MS.View.proj(v, b), hw, clip, col, acc)
    case False{} False{}:
      acc

# a round-ended stroke w wide from a to b (board points)
def Face.seg(a: B.Pt, b: B.Pt, +w: F32, +v: MS.View, +h: F32, +clip: D.Clip, +col: U32, acc: List<&2, R.Op>) -> List<&2, R.Op>:
  match a b:
    case B.Pt{+ax, +ay} B.Pt{+bx, +by}:
      +pa = MS.View.pt(v, ax, h, ay)
      +pb = MS.View.pt(v, bx, h, by)
      Face.cap(Face.in(MS.View.near(v), pa), Face.in(MS.View.near(v), pb), v, pa, pb,
        F32.max(Face.hw(v, h, F32.mul(0.5, F32.add(ax, bx)), F32.mul(0.5, F32.add(ay, by)), F32.sub(bx, ax), F32.sub(by, ay), w), 0.35),
        clip, col, acc)

def Face.line(ps: List<&2, B.Pt>, +w: F32, +v: MS.View, +h: F32, +clip: D.Clip, +col: U32, acc: List<&2, R.Op>) -> List<&2, R.Op>:
  match ps:
    case +a <> +b <> t:
      Face.line(b <> t, w, v, h, clip, col, Face.seg(a, b, w, v, h, clip, col, acc))
    case _:
      acc

def Face.disc.s(p: MS.VP, +r: F32, +v: MS.View, +clip: D.Clip, +col: U32, acc: List<&2, R.Op>) -> List<&2, R.Op>:
  match p:
    case MS.VP{x, y, +z}:
      Ops.put(F32.is_gt(z, MS.View.near(v)), D.Draw.disc(clip, x, y, F32.max(F32.div(F32.mul(r, MS.View.focal(v)), F32.max(z, 0.0001)), 0.4), col, 255), acc)

# a filled circle: a disc when it is small on screen, else a polygon
def Face.disc.k(small: Bool, +c: B.Pt, +r: F32, +v: MS.View, +h: F32, +clip: D.Clip, +col: U32, acc: List<&2, R.Op>) -> List<&2, R.Op>:
  match small c:
    case True{} B.Pt{+x, +y}:
      Face.disc.s(MS.View.screen(v, x, h, y), r, v, clip, col, acc)
    case False{} B.Pt{+x, +y}:
      Face.poly(Circ.pts(31n, x, y, r, 32n, Nil{}), v, h, clip, col, acc)

def Face.small(+c: B.Pt, +r: F32, +v: MS.View, +h: F32) -> Bool:
  match c:
    case B.Pt{+x, +y}:
      F32.is_lt(F32.div(F32.mul(r, MS.View.focal(v)), F32.max(MS.VP.z(MS.View.pt(v, x, h, y)), 0.0001)), 3.0)

def Face.disc(+c: B.Pt, +r: F32, +v: MS.View, +h: F32, +clip: D.Clip, +col: U32, acc: List<&2, R.Op>) -> List<&2, R.Op>:
  Face.disc.k(Face.small(c, r, v, h), c, r, v, h, clip, col, acc)

def Face.ring(+c: B.Pt, +r: F32, +w: F32, +v: MS.View, +h: F32, +clip: D.Clip, +col: U32, acc: List<&2, R.Op>) -> List<&2, R.Op>:
  match c:
    case B.Pt{+x, +y}:
      Face.line(Circ.pts(32n, x, y, r, 32n, Nil{}), w, v, h, clip, col, acc)

def Face.circ(fill: Bool, +c: B.Pt, +r: F32, +w: F32, +v: MS.View, +h: F32, +clip: D.Clip, +col: U32, acc: List<&2, R.Op>) -> List<&2, R.Op>:
  match fill:
    case True{}:
      Face.disc(c, F32.add(r, F32.mul(0.5, w)), v, h, clip, col, acc)
    case False{}:
      Face.ring(c, r, w, v, h, clip, col, acc)

def Face.pgon(fill: Bool, stroke: Bool, +ps: List<&2, B.Pt>, +w: F32, +v: MS.View, +h: F32, +clip: D.Clip, +col: U32, acc: List<&2, R.Op>) -> List<&2, R.Op>:
  match fill stroke:
    case True{} True{}:
      Face.line(Wall.close(ps), w, v, h, clip, col, Face.poly(ps, v, h, clip, col, acc))
    case True{} False{}:
      Face.poly(ps, v, h, clip, col, acc)
    case False{} _:
      Face.line(Wall.close(ps), w, v, h, clip, col, acc)

# one prim's ops onto acc (ops are kept topmost first)
def Face.prim(p: B.Prim, +v: MS.View, +h: F32, +clip: D.Clip, +col: U32, acc: List<&2, R.Op>) -> List<&2, R.Op>:
  match p:
    case B.PSeg{a, b, +w}:
      Face.seg(a, b, w, v, h, clip, col, acc)
    case B.PLine{ps, +w}:
      Face.line(ps, w, v, h, clip, col, acc)
    case B.PCirc{+c, +r, +w, fill}:
      Face.circ(fill, c, r, w, v, h, clip, col, acc)
    case B.PPoly{+ps, +w, fill}:
      Face.pgon(fill, F32.is_gt(w, 0.0), ps, w, v, h, clip, col, acc)

def Face.prims(ps: List<&2, B.Prim>, +v: MS.View, +h: F32, +clip: D.Clip, +col: U32, acc: List<&2, R.Op>) -> List<&2, R.Op>:
  match ps:
    case Nil{}:
      acc
    case p <> t:
      Face.prims(t, v, h, clip, col, Face.prim(p, v, h, clip, col, acc))

# The outline
# -----------
# Every Edge.Cuts prim's edges together fill even-odd: the board, less its
# cutouts, with no need to join them into loops.

def Edge.of(p: MS.VP, q: MS.VP) -> R.Edge:
  match p q:
    case MS.VP{ax, ay, _} MS.VP{bx, by, _}:
      R.Edge{D.Poly.jit(ax), D.Poly.jit(ay), D.Poly.jit(bx), D.Poly.jit(by)}

def Edge.cut(ia: Bool, ib: Bool, +v: MS.View, +a: MS.VP, +b: MS.VP, acc: List<&2, R.Edge>) -> List<&2, R.Edge>:
  match ia ib:
    case True{} True{}:
      Edge.of(MS.View.proj(v, a), MS.View.proj(v, b)) <> acc
    case True{} False{}:
      Edge.of(MS.View.proj(v, a), MS.View.proj(v, MS.VP.cut(a, b, MS.View.near(v)))) <> acc
    case False{} True{}:
      Edge.of(MS.View.proj(v, MS.VP.cut(b, a, MS.View.near(v))), MS.View.proj(v, b)) <> acc
    case False{} False{}:
      acc

def Edge.path(ps: List<&2, B.Pt>, +v: MS.View, +h: F32, acc: List<&2, R.Edge>) -> List<&2, R.Edge>:
  match ps:
    case B.Pt{+ax, +ay} <> B.Pt{+bx, +by} <> t:
      +pa = MS.View.pt(v, ax, h, ay)
      +pb = MS.View.pt(v, bx, h, by)
      Edge.path(B.Pt{bx, by} <> t, v, h, Edge.cut(Face.in(MS.View.near(v), pa), Face.in(MS.View.near(v), pb), v, pa, pb, acc))
    case _:
      acc

def Edge.prim(p: B.Prim, +v: MS.View, +h: F32, acc: List<&2, R.Edge>) -> List<&2, R.Edge>:
  match p:
    case B.PSeg{a, b, _}:
      Edge.path([a, b], v, h, acc)
    case B.PLine{ps, _}:
      Edge.path(ps, v, h, acc)
    case B.PCirc{B.Pt{+cx, +cy}, +r, _, _}:
      Edge.path(Circ.pts(48n, cx, cy, r, 48n, Nil{}), v, h, acc)
    case B.PPoly{ps, _, _}:
      Edge.path(Wall.close(ps), v, h, acc)

def Edge.all(ps: List<&2, B.Prim>, +v: MS.View, +h: F32, acc: List<&2, R.Edge>) -> List<&2, R.Edge>:
  match ps:
    case Nil{}:
      acc
    case p <> t:
      Edge.all(t, v, h, Edge.prim(p, v, h, acc))

def Edge.box(es: List<&2, R.Edge>, b: D.Box) -> D.Box:
  match es b:
    case Nil{} _:
      b
    case R.Edge{+ax, +ay, +bx, +by} <> t D.Box{+x0, +y0, +x1, +y1}:
      Edge.box(t, D.Box{F32.min(x0, F32.min(ax, bx)), F32.min(y0, F32.min(ay, by)), F32.max(x1, F32.max(ax, bx)), F32.max(y1, F32.max(ay, by))})

def Face.outline(+es: List<&2, R.Edge>, +clip: D.Clip, +col: U32, acc: List<&2, R.Op>) -> List<&2, R.Op>:
  match es:
    case Nil{}:
      acc
    case _:
      D.Poly.op(clip, Edge.box(es, D.Box{1000000.0, 1000000.0, F32.neg(1000000.0), F32.neg(1000000.0)}), es, col, 255) <> acc

# Colours
# -------

# lit as the model is: Lambert with the view's light, over ambient
def Face.lit(+c: U32, +k: F32) -> U32:
  MS.Rgb.scale(c, k)

def Face.light(+v: MS.View, +up: Bool) -> F32:
  F32.add(0.3, F32.mul(0.7, F32.max(Bool.pick(F32, up, MS.View.light_y(v), F32.neg(MS.View.light_y(v))), 0.0)))

# the ops of one side, topmost first: the face, with openings marked
# Face.open(); and what shows through openings (bare board, bare copper)
def Face.ops(+o: List<&2, B.Prim>, l: L4, +lk: P.Look, +v: MS.View, +h: F32, +k: F32, +clip: D.Clip) -> MS.FaceOps:
  match l lk:
    case L4{cu, silk, +op, bare, holes, cand} P.Look{+body, +mask, +ma, +sk, +fin, +cop}:
      MS.FaceOps{Face.prims(holes, v, h, clip, MS.Face.key(),
          Face.prims(bare, v, h, clip, Face.lit(fin, k),
            Face.prims(op, v, h, clip, MS.Face.open(),
              Face.prims(silk, v, h, clip, Face.lit(sk, k),
                Face.prims(cu, v, h, clip, Face.lit(R.Rgb.mix(mask, cop, 175), k),
                  Face.outline(Edge.all(o, v, h, Nil{}), clip, Face.lit(R.Rgb.mix(mask, body, ma), k), Nil{})))))),
        Face.prims(cand, v, h, clip, Face.lit(fin, k), Face.prims(op, v, h, clip, Face.lit(MS.Rgb.scale(body, 0.35), k), Nil{}))}

def Face.side(up: Bool, +o: List<&2, B.Prim>, t: L4, b: L4, +lk: P.Look, +v: MS.View, +thick: F32, +clip: D.Clip) -> MS.FaceOps:
  match up:
    case True{}:
      Face.ops(o, t, lk, v, thick, Face.light(v, True{}), clip)
    case False{}:
      Face.ops(o, b, lk, v, 0.0, Face.light(v, False{}), clip)

# Frames
# ------

def Face.draw(f: Face3, m: MS.Model, +v: MS.View, +ww: U32, +hh: U32, +now: Nat, +clip: D.Clip, +bg: U32) -> Image:
  match f:
    case FNone{}:
      MS.Mesh.draw(ww, hh, m, v, now, MS.FaceOps{Nil{}, Nil{}}, MS.Plane.none(), bg)
    case Face3{+thick, +lk, +o, t, b}:
      +up = F32.is_ge(MS.View.eye_y(v), F32.mul(0.5, thick))
      MS.Mesh.draw(ww, hh, m, v, now, Face.side(up, o, t, b, lk, v, thick, clip), MS.Plane.at_y(v, Bool.pick(F32, up, thick, 0.0)), bg)

def Face3.first(fs: List<&2, Face3>) -> Face3:
  match fs:
    case f <> _:
      f
    case Nil{}:
      FNone{}

# the scene in a pw x ph panel at (x0, y0) of a ww x hh frame, over bg
def Scene3.render(+ww: U32, +hh: U32, +x0: U32, +y0: U32, +pw: U32, +ph: U32, s: Scene3, +c: MS.Cam, +now: Nat, +bg: U32) -> Image:
  match s:
    case Scene3{m, f, _, _}:
      Face.draw(Face3.first(f), m, MS.Mesh.view(ww, hh, x0, y0, pw, ph, c), ww, hh, now, D.Clip{x0, y0, ww, hh}, bg)
