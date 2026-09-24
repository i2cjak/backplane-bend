import Base
import ../core/glb.bend as G
import ./raster.bend as R

# A z-buffered triangle rasterizer for the 3D viewer, parallel from end to
# end. The model is a balanced tree of triangle chunks; the chunks project
# at once (back faces culled, flat Lambert shading, clipped at the near
# plane) and each drops its screen triangles into a grid of 64-px regions,
# keeping a triangle only where it really reaches a region (its edges, not
# just its box). The regions are then drawn in parallel, dealt out in
# bit-reversed order so every core gets a fair sample of the screen, not
# one busy corner. A region splits to 16-px tiles and 4x4 blocks that walk
# their short list once, keeping the nearest hit per pixel. Depth is 1/z,
# linear in screen space, taken from the triangle's first vertex so thin
# layers stay apart. A translucent triangle (a see-through material, or a
# part still fading in) is kept as one extra layer per pixel.
#
# Under the triangles lies an optional board face: an image of the board's
# visible side, drawn by the 2D rasterizer from ops projected through the
# same view (pcb3d.bend), and the plane it lies in. A face pixel starts its
# pixel's depth at the plane, so parts behind the board are hidden and
# parts on it are not; Face.key() pixels are not board (outside the outline,
# holes) and let what is behind show through.

# yaw and pitch in radians (pitch 0 looks level, pi/2 straight down),
# distance from the target, vertical field of view in radians
type Cam is Data:
  Cam{yaw: F32, pitch: F32, dist: F32, tx: F32, ty: F32, tz: F32, fov: F32}

# the camera resolved for a frame: eye, right, up and forward axes, focal
# length and centre in pixels, near plane, frame size, and the unit vector
# towards the light
type View is Data:
  View{ex: F32, ey: F32, ez: F32, rx: F32, ry: F32, rz: F32, ux: F32, uy: F32, uz: F32, fx: F32, fy: F32, fz: F32,
    focal: F32, cx: F32, cy: F32, near: F32, w: F32, h: F32, lx: F32, ly: F32, lz: F32}

# a screen triangle: pixel box (inclusive), three edge functions a*x+b*y+c
# (all >= 0 inside), the 1/z plane, the shaded colour and its opacity
type STri is Data:
  STri{x0: U32, y0: U32, x1: U32, y1: U32, a0: F32, b0: F32, c0: F32, a1: F32, b1: F32, c1: F32, a2: F32, b2: F32, c2: F32,
    za: F32, zb: F32, zc: F32, color: U32, alpha: U32}

# a pixel's nearest opaque hit and nearest translucent hit (depth is 1/z;
# 0 is the background at infinity)
type Hit is Data:
  Hit{z: F32, c: U32, tz: F32, tc: U32, ta: U32}

type Q4 is Data:
  Q4{a: List<&2, STri>, b: List<&2, STri>, c: List<&2, STri>, d: List<&2, STri>}

# a view-space point (x right, y up, z forward)
type VP is Data:
  VP{x: F32, y: F32, z: F32}

# the board face's 1/z at pixel centre (px, py): a*px + b*py + c
type Plane is Data:
  Plane{a: F32, b: F32, c: F32}

# Picking
# -------

def U32.pick(c: Bool, +a: U32, +b: U32) -> U32:
  match c:
    case True{}:
      a
    case False{}:
      b

# Camera
# ------

def Cam.orbit.k(c: Cam, +dx: F32, +dy: F32) -> Cam:
  match c:
    case Cam{yaw, pitch, dist, tx, ty, tz, fov}:
      Cam{F32.add(yaw, dx), F32.clamp(F32.add(pitch, dy), F32.neg(1.55), 1.55), dist, tx, ty, tz, fov}

# turn the camera around its target by dx (yaw) and dy (pitch), radians
def Cam.orbit(c: Cam, +dx: F32, +dy: F32) -> Cam:
  Cam.orbit.k(c, dx, dy)

# move towards (f < 1) or away from (f > 1) the target
def Cam.zoom(c: Cam, +f: F32) -> Cam:
  match c:
    case Cam{yaw, pitch, dist, tx, ty, tz, fov}:
      Cam{yaw, pitch, F32.mul(dist, f), tx, ty, tz, fov}

type Box3 is Data:
  Box3{x0: F32, y0: F32, z0: F32, x1: F32, y1: F32, z1: F32}

def Box3.empty() -> Box3:
  +big = {1000000000.0 : F32}
  Box3{big, big, big, F32.neg(big), F32.neg(big), F32.neg(big)}

def Box3.put(b: Box3, +x: F32, +y: F32, +z: F32) -> Box3:
  match b:
    case Box3{x0, y0, z0, x1, y1, z1}:
      Box3{F32.min(x0, x), F32.min(y0, y), F32.min(z0, z), F32.max(x1, x), F32.max(y1, y), F32.max(z1, z)}

def Box3.go(ts: List<&2, G.Tri3>, b: Box3) -> Box3:
  match ts:
    case Nil{}:
      b
    case G.Tri3{ax, ay, az, bx, by, bz, cx, cy, cz, _} <> t:
      Box3.go(t, Box3.put(Box3.put(Box3.put(b, ax, ay, az), bx, by, bz), cx, cy, cz))

def Cam.of_box(b: Box3, +fov: F32) -> Cam:
  match b:
    case Box3{+x0, +y0, +z0, +x1, +y1, +z1}:
      +dx = F32.sub(x1, x0)
      +dy = F32.sub(y1, y0)
      +dz = F32.sub(z1, z0)
      +r = F32.max(F32.mul(0.5, F32.sqrt(F32.add(F32.mul(dx, dx), F32.add(F32.mul(dy, dy), F32.mul(dz, dz))))), 0.000001)
      Cam{0.3, 0.95, F32.div(r, F32.sin(F32.mul(fov, 0.5))), F32.mul(0.5, F32.add(x0, x1)), F32.mul(0.5, F32.add(y0, y1)),
        F32.mul(0.5, F32.add(z0, z1)), fov}

# a camera that shows every triangle, looking down at the target from the
# front at about 55 degrees (glTF is Y up; a KiCad board lies in XZ)
def Cam.fit(ts: List<&2, G.Tri3>) -> Cam:
  Cam.of_box(Box3.go(ts, Box3.empty()), 0.7)

# Models
# ------
# Triangles in chunks of up to 1024, each stamped with the time (ms) it
# arrived (0: there from the start, never faded), kept as a list and as a
# balanced tree for the parallel projection. `last` is the newest stamp.

type Chunk is Data:
  Chunk{born: Nat, ts: List<&2, G.Tri3>}

type MTree is Data:
  TNone{}
  TOne{c: Chunk}
  TTwo{a: MTree, b: MTree}

type Model is Data:
  Model{n: Nat, box: Box3, cs: List<&2, Chunk>, t: MTree, last: Nat}

def Chunk.last(cur: List<&2, G.Tri3>, +born: Nat, acc: List<&2, Chunk>) -> List<&2, Chunk>:
  match cur:
    case Nil{}:
      acc
    case _:
      Chunk{born, cur} <> acc

# ts cut into chunks stamped `born`, onto acc (i: room left in the chunk)
def Chunk.cut(ts: List<&2, G.Tri3>, +i: Nat, +born: Nat, cur: List<&2, G.Tri3>, acc: List<&2, Chunk>) -> List<&2, Chunk>:
  match ts i:
    case Nil{} _:
      Chunk.last(cur, born, acc)
    case t <> r 0n:
      Chunk.cut(r, 1023n, born, [t], Chunk{born, cur} <> acc)
    case t <> r 1n+j:
      Chunk.cut(r, j, born, t <> cur, acc)

def MTree.leaves(cs: List<&2, Chunk>) -> List<&2, MTree>:
  match cs:
    case Nil{}:
      Nil{}
    case c <> t:
      TOne{c} <> MTree.leaves(t)

def MTree.pairs(ts: List<&2, MTree>) -> List<&2, MTree>:
  match ts:
    case a <> b <> t:
      TTwo{a, b} <> MTree.pairs(t)
    case a <> Nil{}:
      [a]
    case Nil{}:
      Nil{}

def MTree.up(d: Nat, ts: List<&2, MTree>) -> MTree:
  match d ts:
    case 0n t <> _:
      t
    case 0n Nil{}:
      TNone{}
    case 1n+p _:
      MTree.up(p, MTree.pairs(ts))

def MTree.of(+cs: List<&2, Chunk>) -> MTree:
  MTree.up(G.Tab.depth(U32.from_nat(List.length(&2, Chunk, cs))), MTree.leaves(cs))

def Model.none() -> Model:
  Model{0n, Box3.empty(), Nil{}, TNone{}, 0n}

def Model.add.k(+n: Nat, +box: Box3, +cs: List<&2, Chunk>, +last: Nat) -> Model:
  Model{n, box, cs, MTree.of(cs), last}

# more triangles, arrived at `born`
def Model.add(m: Model, +ts: List<&2, G.Tri3>, +born: Nat) -> Model:
  match m:
    case Model{+n, box, cs, _, +last}:
      Model.add.k(Nat.add(n, List.length(&2, G.Tri3, ts)), Box3.go(ts, box), Chunk.cut(ts, 1024n, born, Nil{}, cs),
        Bool.pick(Nat, Nat.is_ge(born, last), born, last))

def Model.of(+ts: List<&2, G.Tri3>) -> Model:
  Model.add(Model.none(), ts, 0n)

def Model.is_empty(m: Model) -> Bool:
  match m:
    case Model{n, _, _, _, _}:
      Nat.is_eq(n, 0n)

def Model.size(m: Model) -> Nat:
  match m:
    case Model{n, _, _, _, _}:
      n

def Model.fit(m: Model) -> Cam:
  match m:
    case Model{_, box, _, _, _}:
      Cam.of_box(box, 0.7)

def Model.tree(m: Model) -> MTree:
  match m:
    case Model{_, _, _, t, _}:
      t

# Fades
# -----

def Fade.ms() -> Nat:
  450n

# a chunk's opacity at `now` (smoothstep over Fade.ms)
def Fade.ease(+t: F32) -> U32:
  F32.to_u32(F32.mul(255.0, F32.mul(F32.mul(t, t), F32.sub(3.0, F32.mul(2.0, t)))))

def Fade.alpha.k(zero: Bool, +born: Nat, +now: Nat) -> U32:
  match zero:
    case True{}:
      255
    case False{}:
      Fade.ease(F32.clamp(F32.div(F32.from_nat(Nat.sub(now, born)), F32.from_nat(Fade.ms())), 0.0, 1.0))

def Fade.alpha(+born: Nat, +now: Nat) -> U32:
  Fade.alpha.k(Nat.is_eq(born, 0n), born, now)

# whether a chunk is still fading in at `now`
def Model.fading(m: Model, +now: Nat) -> Bool:
  match m:
    case Model{_, _, _, _, +last}:
      Bool.and(Nat.is_gt(last, 0n), Nat.is_lt(now, Nat.add(last, Fade.ms())))

# Projection
# ----------

def Rgb.scale.ch(+c: U32, +s: Nat, +k: F32) -> U32:
  U32.shln(F32.to_u32(F32.mul(U32.to_f32(U32.and(U32.shrn(c, s), 255)), k)), s)

def Rgb.scale(+c: U32, +k: F32) -> U32:
  U32.or(Rgb.scale.ch(c, 16n, k), U32.or(Rgb.scale.ch(c, 8n, k), Rgb.scale.ch(c, 0n, k)))

def Proj.flip(neg: Bool, +v: F32) -> F32:
  match neg:
    case True{}:
      F32.neg(v)
    case False{}:
      v

def Proj.floor(+f: F32) -> U32:
  F32.to_u32(F32.max(f, 0.0))

# the triangle once its box has pixel centres in it
def Proj.keep(ok: Bool, +x0: F32, +y0: F32, +x1: F32, +y1: F32, +s: Bool,
    +a0: F32, +b0: F32, +c0: F32, +a1: F32, +b1: F32, +c1: F32, +a2: F32, +b2: F32, +c2: F32,
    +za: F32, +zb: F32, +zc: F32, +col: U32, +alpha: U32, acc: List<&2, STri>) -> List<&2, STri>:
  match ok:
    case True{}:
      STri{Proj.floor(x0), Proj.floor(y0), Proj.floor(x1), Proj.floor(y1),
        Proj.flip(s, a0), Proj.flip(s, b0), Proj.flip(s, c0), Proj.flip(s, a1), Proj.flip(s, b1), Proj.flip(s, c1),
        Proj.flip(s, a2), Proj.flip(s, b2), Proj.flip(s, c2), za, zb, zc, col, alpha} <> acc
    case False{}:
      acc

# pixel box: the pixel centres (i + 0.5) the triangle's bounds contain
def Proj.box(+area: F32, +xa: F32, +ya: F32, +xb: F32, +yb: F32, +xc: F32, +yc: F32, +w: F32, +h: F32,
    +a0: F32, +b0: F32, +c0: F32, +a1: F32, +b1: F32, +c1: F32, +a2: F32, +b2: F32, +c2: F32,
    +za: F32, +zb: F32, +zc: F32, +col: U32, +alpha: U32, acc: List<&2, STri>) -> List<&2, STri>:
  +x0 = F32.max(F32.ceil(F32.sub(F32.min(xa, F32.min(xb, xc)), 0.5)), 0.0)
  +y0 = F32.max(F32.ceil(F32.sub(F32.min(ya, F32.min(yb, yc)), 0.5)), 0.0)
  +x1 = F32.min(F32.floor(F32.sub(F32.max(xa, F32.max(xb, xc)), 0.5)), F32.sub(w, 1.0))
  +y1 = F32.min(F32.floor(F32.sub(F32.max(ya, F32.max(yb, yc)), 0.5)), F32.sub(h, 1.0))
  Proj.keep(Bool.and(Bool.and(F32.is_le(x0, x1), F32.is_le(y0, y1)), F32.is_gt(F32.abs(area), 0.0001)), x0, y0, x1, y1,
    F32.is_lt(area, 0.0), a0, b0, c0, a1, b1, c1, a2, b2, c2, za, zb, zc, col, alpha, acc)

# edges AB, BC, CA and the 1/z plane of a screen triangle. The plane's
# slopes come from differences to vertex A and its offset from A itself:
# solving it from the edge functions' constant terms (pixel coordinates
# squared) loses the depth that keeps copper, mask and silk apart.
def Proj.edges(+xa: F32, +ya: F32, +ia: F32, +xb: F32, +yb: F32, +ib: F32, +xc: F32, +yc: F32, +ic: F32,
    +w: F32, +h: F32, +col: U32, +alpha: U32, acc: List<&2, STri>) -> List<&2, STri>:
  +e1x = F32.sub(xb, xa)
  +e1y = F32.sub(yb, ya)
  +e2x = F32.sub(xc, xa)
  +e2y = F32.sub(yc, ya)
  +d1 = F32.sub(ib, ia)
  +d2 = F32.sub(ic, ia)
  +area = F32.sub(F32.mul(e1x, e2y), F32.mul(e2x, e1y))
  +gx = F32.div(F32.sub(F32.mul(d1, e2y), F32.mul(d2, e1y)), area)
  +gy = F32.div(F32.sub(F32.mul(d2, e1x), F32.mul(d1, e2x)), area)
  Proj.box(area, xa, ya, xb, yb, xc, yc, w, h,
    F32.sub(ya, yb), F32.sub(xb, xa), F32.sub(F32.mul(xa, yb), F32.mul(xb, ya)),
    F32.sub(yb, yc), F32.sub(xc, xb), F32.sub(F32.mul(xb, yc), F32.mul(xc, yb)),
    F32.sub(yc, ya), F32.sub(xa, xc), F32.sub(F32.mul(xc, ya), F32.mul(xa, yc)),
    gx, gy, F32.sub(ia, F32.add(F32.mul(gx, xa), F32.mul(gy, ya))), col, alpha, acc)

# three view-space points (all past the near plane) on screen
def Proj.screen(+v: View, a: VP, b: VP, c: VP, +col: U32, +alpha: U32, acc: List<&2, STri>) -> List<&2, STri>:
  match v a b c:
    case View{_, _, _, _, _, _, _, _, _, _, _, _, +f, +cx, +cy, _, w, h, _, _, _} VP{xa, ya, +za} VP{xb, yb, +zb} VP{xc, yc, +zc}:
      Proj.edges(F32.add(cx, F32.div(F32.mul(f, xa), za)), F32.sub(cy, F32.div(F32.mul(f, ya), za)), F32.div(1.0, za),
        F32.add(cx, F32.div(F32.mul(f, xb), zb)), F32.sub(cy, F32.div(F32.mul(f, yb), zb)), F32.div(1.0, zb),
        F32.add(cx, F32.div(F32.mul(f, xc), zc)), F32.sub(cy, F32.div(F32.mul(f, yc), zc)), F32.div(1.0, zc), w, h, col, alpha, acc)

def VP.lerp(+t: F32, +a: F32, +b: F32) -> F32:
  F32.add(a, F32.mul(t, F32.sub(b, a)))

# where the segment from p (in front) to q (behind) crosses the near plane
def VP.cut(+p: VP, +q: VP, +near: F32) -> VP:
  match p q:
    case VP{+px, +py, +pz} VP{+qx, +qy, +qz}:
      +t = F32.div(F32.sub(pz, near), F32.sub(pz, qz))
      VP{VP.lerp(t, px, qx), VP.lerp(t, py, qy), near}

def View.near(v: View) -> F32:
  match v:
    case View{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, n, _, _, _, _, _}:
      n

# a triangle with one vertex (a) in front of the near plane: the corner
# of it that is in front
def Clip.one(+v: View, +a: VP, +b: VP, +c: VP, +col: U32, +alpha: U32, acc: List<&2, STri>) -> List<&2, STri>:
  Proj.screen(v, a, VP.cut(a, b, View.near(v)), VP.cut(a, c, View.near(v)), col, alpha, acc)

# two vertices (a, b) in front: the quad that is in front, as two
def Clip.two(+v: View, +a: VP, +b: VP, +c: VP, +col: U32, +alpha: U32, acc: List<&2, STri>) -> List<&2, STri>:
  +bc = VP.cut(b, c, View.near(v))
  Proj.screen(v, a, b, bc, col, alpha, Proj.screen(v, a, bc, VP.cut(a, c, View.near(v)), col, alpha, acc))

# the part of a triangle past the near plane
def Proj.clip(ia: Bool, ib: Bool, ic: Bool, +v: View, +a: VP, +b: VP, +c: VP, +col: U32, +alpha: U32, acc: List<&2, STri>) -> List<&2, STri>:
  match ia ib ic:
    case True{} True{} True{}:
      Proj.screen(v, a, b, c, col, alpha, acc)
    case True{} False{} False{}:
      Clip.one(v, a, b, c, col, alpha, acc)
    case False{} True{} False{}:
      Clip.one(v, b, c, a, col, alpha, acc)
    case False{} False{} True{}:
      Clip.one(v, c, a, b, col, alpha, acc)
    case True{} True{} False{}:
      Clip.two(v, a, b, c, col, alpha, acc)
    case False{} True{} True{}:
      Clip.two(v, b, c, a, col, alpha, acc)
    case True{} False{} True{}:
      Clip.two(v, c, a, b, col, alpha, acc)
    case False{} False{} False{}:
      acc

def Proj.dot(+a: F32, +b: F32, +c: F32, +x: F32, +y: F32, +z: F32) -> F32:
  F32.add(F32.add(F32.mul(a, x), F32.mul(b, y)), F32.mul(c, z))

# a world point in view space (x right, y up, z forward)
def View.pt(+v: View, +x: F32, +y: F32, +z: F32) -> VP:
  match v:
    case View{+ex, +ey, +ez, +rx, +ry, +rz, +ux, +uy, +uz, +fx, +fy, +fz, _, _, _, _, _, _, _, _, _}:
      +dx = F32.sub(x, ex)
      +dy = F32.sub(y, ey)
      +dz = F32.sub(z, ez)
      VP{Proj.dot(rx, ry, rz, dx, dy, dz), Proj.dot(ux, uy, uz, dx, dy, dz), Proj.dot(fx, fy, fz, dx, dy, dz)}

def VP.z(p: VP) -> F32:
  match p:
    case VP{_, _, z}:
      z

def Proj.view.k(+v: View, +a: VP, +b: VP, +c: VP, +col: U32, +alpha: U32, acc: List<&2, STri>) -> List<&2, STri>:
  +n = View.near(v)
  Proj.clip(F32.is_gt(VP.z(a), n), F32.is_gt(VP.z(b), n), F32.is_gt(VP.z(c), n), v, a, b, c, col, alpha, acc)

# the three vertices in view space, cut at the near plane, on screen
def Proj.view(+v: View, +ax: F32, +ay: F32, +az: F32, +bx: F32, +by: F32, +bz: F32, +cx: F32, +cy: F32, +cz: F32,
    +col: U32, +alpha: U32, acc: List<&2, STri>) -> List<&2, STri>:
  Proj.view.k(v, View.pt(v, ax, ay, az), View.pt(v, bx, by, bz), View.pt(v, cx, cy, cz), col, alpha, acc)

# the light is fixed to the camera: a unit vector towards it in the view's
# right, up and backward axes (over the viewer's left shoulder), so every
# side of a model reads the same while orbiting
def Light.r() -> F32:
  F32.neg(0.3)

def Light.u() -> F32:
  0.55

def Light.b() -> F32:
  0.78

def View.k(+ex: F32, +ey: F32, +ez: F32, +cy: F32, +sy: F32, +cp: F32, +sp: F32, +dist: F32, +fov: F32, +w: F32, +h: F32) -> View:
  View{ex, ey, ez, cy, 0.0, F32.neg(sy), F32.neg(F32.mul(sy, sp)), cp, F32.neg(F32.mul(cy, sp)),
    F32.neg(F32.mul(cp, sy)), F32.neg(sp), F32.neg(F32.mul(cp, cy)),
    F32.div(F32.mul(0.5, F32.min(w, h)), F32.tan(F32.mul(0.5, fov))), F32.mul(0.5, w), F32.mul(0.5, h),
    F32.mul(dist, 0.001), w, h,
    F32.add(F32.mul(Light.r(), cy), F32.add(F32.mul(Light.u(), F32.neg(F32.mul(sy, sp))), F32.mul(Light.b(), F32.mul(cp, sy)))),
    F32.add(F32.mul(Light.u(), cp), F32.mul(Light.b(), sp)),
    F32.add(F32.mul(Light.r(), F32.neg(sy)), F32.add(F32.mul(Light.u(), F32.neg(F32.mul(cy, sp))), F32.mul(Light.b(), F32.mul(cp, cy))))}

def View.of(c: Cam, +w: U32, +h: U32) -> View:
  match c:
    case Cam{+yaw, +pitch, +dist, tx, ty, tz, +fov}:
      +cy = F32.cos(yaw)
      +sy = F32.sin(yaw)
      +cp = F32.cos(pitch)
      +sp = F32.sin(pitch)
      View.k(F32.add(tx, F32.mul(dist, F32.mul(cp, sy))), F32.add(ty, F32.mul(dist, sp)), F32.add(tz, F32.mul(dist, F32.mul(cp, cy))),
        cy, sy, cp, sp, dist, fov, U32.to_f32(w), U32.to_f32(h))

# a copy of its own for each parallel lane (a shared value costs every
# lane an atomic per read)
def View.copy(+v: View) -> View:
  match v:
    case View{ex, ey, ez, rx, ry, rz, ux, uy, uz, fx, fy, fz, f, cx, cy, n, w, h, lx, ly, lz}:
      View{ex, ey, ez, rx, ry, rz, ux, uy, uz, fx, fy, fz, f, cx, cy, n, w, h, lx, ly, lz}

def View.focal(v: View) -> F32:
  match v:
    case View{_, _, _, _, _, _, _, _, _, _, _, _, f, _, _, _, _, _, _, _, _}:
      f

def View.light_y(v: View) -> F32:
  match v:
    case View{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, ly, _}:
      ly

def View.eye_y(v: View) -> F32:
  match v:
    case View{_, ey, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      ey

def View.screen.k(p: VP, +f: F32, +cx: F32, +cy: F32) -> VP:
  match p:
    case VP{x, y, +z}:
      VP{F32.add(cx, F32.div(F32.mul(f, x), z)), F32.sub(cy, F32.div(F32.mul(f, y), z)), z}

# a world point on screen (x, y, and view depth z; z <= near is behind)
def View.screen(+v: View, +x: F32, +y: F32, +z: F32) -> VP:
  match v:
    case View{_, _, _, _, _, _, _, _, _, _, _, _, +f, +cx, +cy, _, _, _, _, _, _}:
      View.screen.k(View.pt(v, x, y, z), f, cx, cy)

# a view-space point on screen (z kept)
def View.proj(+v: View, p: VP) -> VP:
  match v:
    case View{_, _, _, _, _, _, _, _, _, _, _, _, +f, +cx, +cy, _, _, _, _, _, _}:
      View.screen.k(p, f, cx, cy)

# the 1/z plane of the horizontal plane at world height y: along the ray
# through pixel (px, py) the view depth z has (y - ey) = z * (fy + ry
# (px - cx) / f - uy (py - cy) / f)
def Plane.at_y(+v: View, +y: F32) -> Plane:
  match v:
    case View{_, +ey, _, _, +ry, _, _, +uy, _, _, +fy, _, +f, +cx, +cy, _, _, _, _, _, _}:
      +k = F32.div(1.0, F32.mul(F32.sub(y, ey), f))
      Plane{F32.mul(ry, k), F32.neg(F32.mul(uy, k)), F32.mul(F32.add(F32.sub(F32.mul(fy, f), F32.mul(ry, cx)), F32.mul(uy, cy)), k)}

def Plane.none() -> Plane:
  Plane{0.0, 0.0, 0.0}

def Plane.copy(+p: Plane) -> Plane:
  match p:
    case Plane{a, b, c}:
      Plane{a, b, c}

# flat Lambert over a little ambient, lit from whichever side faces us
def Proj.shade(+c: U32, +facing: Bool, +nx: F32, +ny: F32, +nz: F32, +lx: F32, +ly: F32, +lz: F32) -> U32:
  +len = F32.max(F32.sqrt(Proj.dot(nx, ny, nz, nx, ny, nz)), 0.0000000001)
  +lam = F32.max(F32.div(Proj.flip(Bool.not(facing), Proj.dot(nx, ny, nz, lx, ly, lz)), len), 0.0)
  Rgb.scale(U32.and(c, 16777215), F32.add(0.3, F32.mul(0.7, lam)))

def Proj.light(v: View, +c: U32, +facing: Bool, +nx: F32, +ny: F32, +nz: F32) -> U32:
  match v:
    case View{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, lx, ly, lz}:
      Proj.shade(c, facing, nx, ny, nz, lx, ly, lz)

# the material's opacity (from 0xTTRRGGBB) times the chunk's fade
def Proj.alpha(+col: U32, +fa: U32) -> U32:
  (((255 - U32.shrn(col, 24n) : U32) * fa : U32) / 255 : U32)

def Proj.front(keep: Bool, +facing: Bool, +v: View, +ax: F32, +ay: F32, +az: F32, +bx: F32, +by: F32, +bz: F32, +cx: F32, +cy: F32, +cz: F32,
    +nx: F32, +ny: F32, +nz: F32, +col: U32, +fa: U32, acc: List<&2, STri>) -> List<&2, STri>:
  match keep:
    case True{}:
      Proj.view(v, ax, ay, az, bx, by, bz, cx, cy, cz, Proj.light(v, col, facing, nx, ny, nz), Proj.alpha(col, fa), acc)
    case False{}:
      acc

# the eye is on the triangle's front side (glTF fronts wind CCW)
def Proj.facing(+v: View, +ax: F32, +ay: F32, +az: F32, +nx: F32, +ny: F32, +nz: F32) -> Bool:
  match v:
    case View{ex, ey, ez, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      F32.is_gt(Proj.dot(nx, ny, nz, F32.sub(ex, ax), F32.sub(ey, ay), F32.sub(ez, az)), 0.0)

def Proj.normal(+cull: Bool, +v: View, +ax: F32, +ay: F32, +az: F32, +bx: F32, +by: F32, +bz: F32, +cx: F32, +cy: F32, +cz: F32,
    +col: U32, +fa: U32, acc: List<&2, STri>) -> List<&2, STri>:
  +ux = F32.sub(bx, ax)
  +uy = F32.sub(by, ay)
  +uz = F32.sub(bz, az)
  +wx = F32.sub(cx, ax)
  +wy = F32.sub(cy, ay)
  +wz = F32.sub(cz, az)
  +nx = F32.sub(F32.mul(uy, wz), F32.mul(uz, wy))
  +ny = F32.sub(F32.mul(uz, wx), F32.mul(ux, wz))
  +nz = F32.sub(F32.mul(ux, wy), F32.mul(uy, wx))
  +facing = Proj.facing(v, ax, ay, az, nx, ny, nz)
  Proj.front(Bool.or(facing, Bool.not(cull)), facing, v, ax, ay, az, bx, by, bz, cx, cy, cz, nx, ny, nz, col, fa, acc)

# every world triangle that shows, as a screen triangle, faded by fa
def Proj.all(ts: List<&2, G.Tri3>, +cull: Bool, +v: View, +fa: U32, acc: List<&2, STri>) -> List<&2, STri>:
  match ts:
    case Nil{}:
      acc
    case G.Tri3{ax, ay, az, bx, by, bz, cx, cy, cz, col} <> t:
      Proj.all(t, cull, v, fa, Proj.normal(cull, v, ax, ay, az, bx, by, bz, cx, cy, cz, col, fa, acc))

# Reaching a square
# -----------------

def Q4.hits(+x0: U32, +y0: U32, +x1: U32, +y1: U32, +qx: U32, +qy: U32, +h: U32) -> Bool:
  Bool.and(Bool.and(U32.is_lt(x0, (qx + h : U32)), U32.is_ge(x1, qx)), Bool.and(U32.is_lt(y0, (qy + h : U32)), U32.is_ge(y1, qy)))

# the largest a*x + b*y + c over the square's pixel centres, with half a
# pixel to spare, is not below 0
def Edge.reaches(+a: F32, +b: F32, +c: F32, +x0: F32, +y0: F32, +x1: F32, +y1: F32) -> Bool:
  F32.is_ge(F32.add(F32.add(c, F32.max(F32.mul(a, x0), F32.mul(a, x1))), F32.add(F32.max(F32.mul(b, y0), F32.mul(b, y1)),
    F32.mul(0.5, F32.add(F32.abs(a), F32.abs(b))))), 0.0)

# does the triangle reach a pixel centre of the h x h square at (qx, qy)?
def STri.meets(+t: STri, +qx: U32, +qy: U32, +h: U32) -> Bool:
  match t:
    case STri{+x0, +y0, +x1, +y1, +a0, +b0, +c0, +a1, +b1, +c1, +a2, +b2, +c2, _, _, _, _, _}:
      +fx0 = F32.add(U32.to_f32(qx), 0.5)
      +fy0 = F32.add(U32.to_f32(qy), 0.5)
      +fx1 = F32.sub(U32.to_f32((qx + h : U32)), 0.5)
      +fy1 = F32.sub(U32.to_f32((qy + h : U32)), 0.5)
      Bool.and(Q4.hits(x0, y0, x1, y1, qx, qy, h), Bool.and(Edge.reaches(a0, b0, c0, fx0, fy0, fx1, fy1),
        Bool.and(Edge.reaches(a1, b1, c1, fx0, fy0, fx1, fy1), Edge.reaches(a2, b2, c2, fx0, fy0, fx1, fy1))))

# Rasterizing
# -----------

def Hit.op(near: Bool, +iz: F32, +col: U32, h: Hit) -> Hit:
  match near h:
    case True{} Hit{_, _, tz, tc, ta}:
      Hit{iz, col, tz, tc, ta}
    case _ _:
      h

def Hit.tr(near: Bool, +iz: F32, +col: U32, +alpha: U32, h: Hit) -> Hit:
  match near h:
    case True{} Hit{z, c, _, _, _}:
      Hit{z, c, iz, col, alpha}
    case _ _:
      h

def Hit.put(inside: Bool, opaque: Bool, +iz: F32, +col: U32, +alpha: U32, h: Hit) -> Hit:
  match inside opaque h:
    case True{} True{} Hit{+z, c, tz, tc, ta}:
      Hit.op(F32.is_gt(iz, z), iz, col, Hit{z, c, tz, tc, ta})
    case True{} False{} Hit{z, c, +tz, tc, ta}:
      Hit.tr(F32.is_gt(iz, tz), iz, col, alpha, Hit{z, c, tz, tc, ta})
    case _ _ _:
      h

# one triangle over one pixel centre (px, py)
def Hit.step(+a0: F32, +b0: F32, +c0: F32, +a1: F32, +b1: F32, +c1: F32, +a2: F32, +b2: F32, +c2: F32,
    +za: F32, +zb: F32, +zc: F32, +col: U32, +alpha: U32, +px: F32, +py: F32, h: Hit) -> Hit:
  Hit.put(Bool.and(F32.is_ge(F32.add(F32.add(F32.mul(a0, px), F32.mul(b0, py)), c0), 0.0),
      Bool.and(F32.is_ge(F32.add(F32.add(F32.mul(a1, px), F32.mul(b1, py)), c1), 0.0),
        F32.is_ge(F32.add(F32.add(F32.mul(a2, px), F32.mul(b2, py)), c2), 0.0))),
    U32.is_gt(alpha, 229), F32.add(F32.add(F32.mul(za, px), F32.mul(zb, py)), zc), col, alpha, h)

def Hit.color(h: Hit) -> U32:
  match h:
    case Hit{+z, +c, +tz, +tc, +ta}:
      U32.pick(F32.is_gt(tz, z), R.Rgb.mix(tc, c, ta), c)

def Hit.pix(h: Hit) -> Image:
  Pix{Hit.color(h)}

# Faces
# -----

# the colour a face image uses where there is no board
def Face.key() -> U32:
  1

# the colour a face image marks a mask opening with
def Face.open() -> U32:
  2

# a board face as 2D ops (topmost first): the face itself, and what
# shows where it marks a mask opening
type FaceOps is Data:
  FaceOps{face: List<&2, R.Op>, under: List<&2, R.Op>}

# a face pixel starts at the plane, pushed back a hair so a part's face
# lying on the board wins over it
def Hit.face(key: Bool, +fc: U32, +px: F32, +py: F32, +pl: Plane, +bg: U32) -> Hit:
  match key pl:
    case True{} _:
      Hit{0.0, bg, 0.0, bg, 0}
    case False{} Plane{+a, +b, +c}:
      Hit{F32.mul(F32.add(F32.add(F32.mul(a, px), F32.mul(b, py)), c), 0.99999), fc, 0.0, bg, 0}

# the hit a pixel starts with: the face at (i, j) of a 4x4 face image
def Hit.init(+f: Image, +i: U32, +j: U32, +px: F32, +py: F32, +pl: Plane, +bg: U32) -> Hit:
  +fc = R.Img.at(2n, f, i, j)
  Hit.face(U32.is_eq(fc, Face.key()), fc, px, py, pl, bg)

# a face image where no triangle reaches: its board pixels as they are
def Face.bare(f: Image, +bg: U32) -> Image:
  match f:
    case Pix{+c}:
      Pix{U32.pick(U32.is_eq(c, Face.key()), bg, c)}
    case Qua{a, b, c, d}:
      Qua{Face.bare(a, bg), Face.bare(b, bg), Face.bare(c, bg), Face.bare(d, bg)}

def Blk.img(h00: Hit, h10: Hit, h20: Hit, h30: Hit, h01: Hit, h11: Hit, h21: Hit, h31: Hit,
    h02: Hit, h12: Hit, h22: Hit, h32: Hit, h03: Hit, h13: Hit, h23: Hit, h33: Hit) -> Image:
  Qua{Qua{Hit.pix(h00), Hit.pix(h10), Hit.pix(h01), Hit.pix(h11)}, Qua{Hit.pix(h20), Hit.pix(h30), Hit.pix(h21), Hit.pix(h31)},
    Qua{Hit.pix(h02), Hit.pix(h12), Hit.pix(h03), Hit.pix(h13)}, Qua{Hit.pix(h22), Hit.pix(h32), Hit.pix(h23), Hit.pix(h33)}}

# a 4x4 block: one walk over its triangles, sixteen pixels at once; x0..x3
# and y0..y3 are the pixel centres
def Blk.go(ts: List<&2, STri>, +x0: F32, +x1: F32, +x2: F32, +x3: F32, +y0: F32, +y1: F32, +y2: F32, +y3: F32,
    h00: Hit, h10: Hit, h20: Hit, h30: Hit, h01: Hit, h11: Hit, h21: Hit, h31: Hit,
    h02: Hit, h12: Hit, h22: Hit, h32: Hit, h03: Hit, h13: Hit, h23: Hit, h33: Hit) -> Image:
  match ts:
    case Nil{}:
      Blk.img(h00, h10, h20, h30, h01, h11, h21, h31, h02, h12, h22, h32, h03, h13, h23, h33)
    case STri{_, _, _, _, +a0, +b0, +c0, +a1, +b1, +c1, +a2, +b2, +c2, +za, +zb, +zc, +k, +al} <> t:
      Blk.go(t, x0, x1, x2, x3, y0, y1, y2, y3,
        Hit.step(a0, b0, c0, a1, b1, c1, a2, b2, c2, za, zb, zc, k, al, x0, y0, h00),
        Hit.step(a0, b0, c0, a1, b1, c1, a2, b2, c2, za, zb, zc, k, al, x1, y0, h10),
        Hit.step(a0, b0, c0, a1, b1, c1, a2, b2, c2, za, zb, zc, k, al, x2, y0, h20),
        Hit.step(a0, b0, c0, a1, b1, c1, a2, b2, c2, za, zb, zc, k, al, x3, y0, h30),
        Hit.step(a0, b0, c0, a1, b1, c1, a2, b2, c2, za, zb, zc, k, al, x0, y1, h01),
        Hit.step(a0, b0, c0, a1, b1, c1, a2, b2, c2, za, zb, zc, k, al, x1, y1, h11),
        Hit.step(a0, b0, c0, a1, b1, c1, a2, b2, c2, za, zb, zc, k, al, x2, y1, h21),
        Hit.step(a0, b0, c0, a1, b1, c1, a2, b2, c2, za, zb, zc, k, al, x3, y1, h31),
        Hit.step(a0, b0, c0, a1, b1, c1, a2, b2, c2, za, zb, zc, k, al, x0, y2, h02),
        Hit.step(a0, b0, c0, a1, b1, c1, a2, b2, c2, za, zb, zc, k, al, x1, y2, h12),
        Hit.step(a0, b0, c0, a1, b1, c1, a2, b2, c2, za, zb, zc, k, al, x2, y2, h22),
        Hit.step(a0, b0, c0, a1, b1, c1, a2, b2, c2, za, zb, zc, k, al, x3, y2, h32),
        Hit.step(a0, b0, c0, a1, b1, c1, a2, b2, c2, za, zb, zc, k, al, x0, y3, h03),
        Hit.step(a0, b0, c0, a1, b1, c1, a2, b2, c2, za, zb, zc, k, al, x1, y3, h13),
        Hit.step(a0, b0, c0, a1, b1, c1, a2, b2, c2, za, zb, zc, k, al, x2, y3, h23),
        Hit.step(a0, b0, c0, a1, b1, c1, a2, b2, c2, za, zb, zc, k, al, x3, y3, h33))

def Blk.draw(ts: List<&2, STri>, +f: Image, +rx: U32, +ry: U32, +bg: U32, +pl: Plane) -> Image:
  match ts:
    case Nil{}:
      Face.bare(f, bg)
    case _:
      +x0 = F32.add(U32.to_f32(rx), 0.5)
      +y0 = F32.add(U32.to_f32(ry), 0.5)
      +x1 = F32.add(x0, 1.0)
      +x2 = F32.add(x0, 2.0)
      +x3 = F32.add(x0, 3.0)
      +y1 = F32.add(y0, 1.0)
      +y2 = F32.add(y0, 2.0)
      +y3 = F32.add(y0, 3.0)
      Blk.go(ts, x0, x1, x2, x3, y0, y1, y2, y3,
        Hit.init(f, 0, 0, x0, y0, pl, bg), Hit.init(f, 1, 0, x1, y0, pl, bg), Hit.init(f, 2, 0, x2, y0, pl, bg), Hit.init(f, 3, 0, x3, y0, pl, bg),
        Hit.init(f, 0, 1, x0, y1, pl, bg), Hit.init(f, 1, 1, x1, y1, pl, bg), Hit.init(f, 2, 1, x2, y1, pl, bg), Hit.init(f, 3, 1, x3, y1, pl, bg),
        Hit.init(f, 0, 2, x0, y2, pl, bg), Hit.init(f, 1, 2, x1, y2, pl, bg), Hit.init(f, 2, 2, x2, y2, pl, bg), Hit.init(f, 3, 2, x3, y2, pl, bg),
        Hit.init(f, 0, 3, x0, y3, pl, bg), Hit.init(f, 1, 3, x1, y3, pl, bg), Hit.init(f, 2, 3, x2, y3, pl, bg), Hit.init(f, 3, 3, x3, y3, pl, bg))

def Q4.keep(hit: Bool, +t: STri, rest: List<&2, STri>) -> List<&2, STri>:
  match hit:
    case True{}:
      t <> rest
    case False{}:
      rest

def Q4.put(+t: STri, +qx: U32, +qy: U32, +h: U32, q: Q4) -> Q4:
  match q:
    case Q4{a, b, c, d}:
      +mx = (qx + h : U32)
      +my = (qy + h : U32)
      Q4{Q4.keep(STri.meets(t, qx, qy, h), t, a), Q4.keep(STri.meets(t, mx, qy, h), t, b),
        Q4.keep(STri.meets(t, qx, my, h), t, c), Q4.keep(STri.meets(t, mx, my, h), t, d)}

# the triangles that reach each quadrant of the 2h square at (qx, qy)
def Q4.go(ts: List<&2, STri>, +qx: U32, +qy: U32, +h: U32) -> Q4:
  match ts:
    case Nil{}:
      Q4{Nil{}, Nil{}, Nil{}, Nil{}}
    case +t <> r:
      Q4.put(t, qx, qy, h, Q4.go(r, qx, qy, h))

# a quadrant split of the triangles and of the face image, together
def Four.with(q: Q4, f: Image, k: List<&2, STri> -> List<&2, STri> -> List<&2, STri> -> List<&2, STri> -> Image -> Image -> Image -> Image -> Image) -> Image:
  match q f:
    case Q4{a, b, c, d} Pix{+col}:
      k(a, b, c, d, Pix{col}, Pix{col}, Pix{col}, Pix{col})
    case Q4{a, b, c, d} Qua{fa, fb, fc, fd}:
      k(a, b, c, d, fa, fb, fc, fd)

def Tile.b8(ts: List<&2, STri>, f: Image, +rx: U32, +ry: U32, +bg: U32, +pl: Plane) -> Image:
  match ts:
    case Nil{}:
      Face.bare(f, bg)
    case _:
      Four.with(Q4.go(ts, rx, ry, 4), f, a => b => c => d => fa => fb => fc => fd =>
        Qua{Blk.draw(a, fa, rx, ry, bg, pl), Blk.draw(b, fb, (rx + 4 : U32), ry, bg, pl),
          Blk.draw(c, fc, rx, (ry + 4 : U32), bg, pl), Blk.draw(d, fd, (rx + 4 : U32), (ry + 4 : U32), bg, pl)})

# a 16-px tile: split to blocks
def Tile.b16(ts: List<&2, STri>, f: Image, +rx: U32, +ry: U32, +bg: U32, +pl: Plane) -> Image:
  Four.with(Q4.go(ts, rx, ry, 8), f, a => b => c => d => fa => fb => fc => fd =>
    Qua{Tile.b8(a, fa, rx, ry, bg, pl), Tile.b8(b, fb, (rx + 8 : U32), ry, bg, pl),
      Tile.b8(c, fc, rx, (ry + 8 : U32), bg, pl), Tile.b8(d, fd, (rx + 8 : U32), (ry + 8 : U32), bg, pl)})

# the n-px square at (rx, ry), 16 * 2^k pixels, on one core
def Seq.go(k: Nat, ts: List<&2, STri>, f: Image, +rx: U32, +ry: U32, +n: U32, +bg: U32, +pl: Plane) -> Image:
  match k ts:
    case _ Nil{}:
      Face.bare(f, bg)
    case 0n _:
      Tile.b16(ts, f, rx, ry, bg, pl)
    case 1n+e0 _:
      +e = e0
      +h = U32.shr(n)
      +x2 = (rx + h : U32)
      +y2 = (ry + h : U32)
      Four.with(Q4.go(ts, rx, ry, h), f, a => b => c => d => fa => fb => fc => fd =>
        Qua{Seq.go(e, a, fa, rx, ry, h, bg, pl), Seq.go(e, b, fb, x2, ry, h, bg, pl),
          Seq.go(e, c, fc, rx, y2, h, bg, pl), Seq.go(e, d, fd, x2, y2, h, bg, pl)})

# Regions
# -------
# Screen triangles go into a sparse quadtree of regions as they are made;
# the chunks' trees join level by level, a region's lists as a rope.

type Chunks is Data:
  CNil{}
  COne{ts: List<&2, STri>}
  CCat{a: Chunks, b: Chunks}

type Bins is Data:
  BNil{}
  BLeaf{c: Chunks}
  BNode{a: Bins, b: Bins, c: Bins, d: Bins}

def Chunks.push(+t: STri, c: Chunks) -> Chunks:
  match c:
    case CNil{}:
      COne{[t]}
    case COne{ts}:
      COne{t <> ts}
    case CCat{a, b}:
      CCat{a, Chunks.push(t, b)}

def Chunks.list(c: Chunks, acc: List<&2, STri>) -> List<&2, STri>:
  match c:
    case CNil{}:
      acc
    case COne{ts}:
      List.append(&2, STri, ts, acc)
    case CCat{a, b}:
      Chunks.list(a, Chunks.list(b, acc))

# t into every region of the n-px square at (qx, qy) it reaches, k levels
# down (hit: whether it reaches this square at all)
def Bins.put(k: Nat, hit: Bool, +t: STri, b: Bins, +qx: U32, +qy: U32, +n: U32) -> Bins:
  match k hit b:
    case _ False{} _:
      b
    case 0n True{} BLeaf{c}:
      BLeaf{Chunks.push(t, c)}
    case 0n True{} _:
      BLeaf{COne{[t]}}
    case 1n+e0 True{} BNode{a, bb, c, d}:
      +e = e0
      +h = U32.shr(n)
      +x2 = (qx + h : U32)
      +y2 = (qy + h : U32)
      BNode{Bins.put(e, STri.meets(t, qx, qy, h), t, a, qx, qy, h), Bins.put(e, STri.meets(t, x2, qy, h), t, bb, x2, qy, h),
        Bins.put(e, STri.meets(t, qx, y2, h), t, c, qx, y2, h), Bins.put(e, STri.meets(t, x2, y2, h), t, d, x2, y2, h)}
    case 1n+e0 True{} _:
      +e = e0
      +h = U32.shr(n)
      +x2 = (qx + h : U32)
      +y2 = (qy + h : U32)
      BNode{Bins.put(e, STri.meets(t, qx, qy, h), t, BNil{}, qx, qy, h), Bins.put(e, STri.meets(t, x2, qy, h), t, BNil{}, x2, qy, h),
        Bins.put(e, STri.meets(t, qx, y2, h), t, BNil{}, qx, y2, h), Bins.put(e, STri.meets(t, x2, y2, h), t, BNil{}, x2, y2, h)}

def Bins.all(ts: List<&2, STri>, +k: Nat, +s: U32, b: Bins) -> Bins:
  match ts:
    case Nil{}:
      b
    case +t <> r:
      Bins.all(r, k, s, Bins.put(k, True{}, t, b, 0, 0, s))

def Bins.merge(a: Bins, b: Bins) -> Bins:
  match a b:
    case BNil{} _:
      b
    case _ BNil{}:
      a
    case BLeaf{x} BLeaf{y}:
      BLeaf{CCat{x, y}}
    case BNode{a1, b1, c1, d1} BNode{a2, b2, c2, d2}:
      BNode{Bins.merge(a1, a2), Bins.merge(b1, b2), Bins.merge(c1, c2), Bins.merge(d1, d2)}
    case _ _:
      a

# every chunk projected and binned, both halves of the tree at once
def Proj.tree(t: MTree, +cull: Bool, +v: View, +now: Nat, +k: Nat, +s: U32) -> Bins:
  match t:
    case TNone{}:
      BNil{}
    case TOne{Chunk{+born, ts}}:
      Bins.all(Proj.all(ts, cull, v, Fade.alpha(born, now), Nil{}), k, s, BNil{})
    case TTwo{a, b}:
      x y = Proj.tree(a, cull, View.copy(v), now, k, s) Proj.tree(b, cull, View.copy(v), now, k, s)
      Bins.merge(x, y)

# a region's corner and its triangles
type Reg0 is Data:
  Reg0{x: U32, y: U32, c: Chunks}

# the regions k levels down, in quadtree (Morton) order, onto acc
def Bins.flat(k: Nat, b: Bins, +qx: U32, +qy: U32, +n: U32, acc: List<&2, Reg0>) -> List<&2, Reg0>:
  match k b:
    case 0n BLeaf{c}:
      Reg0{qx, qy, c} <> acc
    case 0n _:
      Reg0{qx, qy, CNil{}} <> acc
    case 1n+e0 BNode{a, bb, c, d}:
      +e = e0
      +h = U32.shr(n)
      +x2 = (qx + h : U32)
      +y2 = (qy + h : U32)
      Bins.flat(e, a, qx, qy, h, Bins.flat(e, bb, x2, qy, h, Bins.flat(e, c, qx, y2, h, Bins.flat(e, d, x2, y2, h, acc))))
    case 1n+e0 _:
      +e = e0
      +h = U32.shr(n)
      +x2 = (qx + h : U32)
      +y2 = (qy + h : U32)
      Bins.flat(e, BNil{}, qx, qy, h, Bins.flat(e, BNil{}, x2, qy, h, Bins.flat(e, BNil{}, qx, y2, h, Bins.flat(e, BNil{}, x2, y2, h, acc))))

def Fo.with(f: R.Four, k: List<&2, R.Op> -> List<&2, R.Op> -> List<&2, R.Op> -> List<&2, R.Op> -> List<&2, List<&2, R.Op>>) -> List<&2, List<&2, R.Op>>:
  match f:
    case R.Four{a, b, c, d}:
      k(a, b, c, d)

def Ops.cat(a: List<&2, List<&2, R.Op>>, b: List<&2, List<&2, R.Op>>, c: List<&2, List<&2, R.Op>>, d: List<&2, List<&2, R.Op>>) -> List<&2, List<&2, R.Op>>:
  List.append(&2, List<&2, R.Op>, a, List.append(&2, List<&2, R.Op>, b, List.append(&2, List<&2, R.Op>, c, d)))

# the face ops of each region k levels down, in Morton order; the four
# quadrants split at once
def Ops.flat(k: Nat, ops: List<&2, R.Op>, +qx: U32, +qy: U32, +n: U32) -> List<&2, List<&2, R.Op>>:
  match k:
    case 0n:
      [ops]
    case 1n+e0:
      +e = e0
      +h = U32.shr(n)
      +x2 = (qx + h : U32)
      +y2 = (qy + h : U32)
      Fo.with(R.Four.go(ops, qx, qy, h), a => b => c => d => (
        i j l m = Ops.flat(e, a, qx, qy, h) Ops.flat(e, b, x2, qy, h) Ops.flat(e, c, qx, y2, h) Ops.flat(e, d, x2, y2, h)
        Ops.cat(i, j, l, m)))

# a region: its corner, its triangles, and the face ops that reach it
# (the face, and what shows through its mask openings)
type Reg is Data:
  Reg{x: U32, y: U32, c: Chunks, ops: List<&2, R.Op>, under: List<&2, R.Op>}

def Reg.zip(rs: List<&2, Reg0>, os: List<&2, List<&2, R.Op>>, us: List<&2, List<&2, R.Op>>) -> List<&2, Reg>:
  match rs os us:
    case Reg0{x, y, c} <> rt o <> ot u <> ut:
      Reg{x, y, c, o, u} <> Reg.zip(rt, ot, ut)
    case _ _ _:
      Nil{}

# Dealing regions to cores
# ------------------------
# The runtime hands each half of a parallel call to a core once, so the
# halves must cost about the same. Splitting the Morton-ordered regions
# into even and odd places, level by level, is a bit reversal: each core
# gets regions spread evenly over the screen.

type EO is Data:
  EO{e: List<&2, Reg>, o: List<&2, Reg>}

def EO.cons(x: Reg, y: Reg, r: EO) -> EO:
  match r:
    case EO{e, o}:
      EO{x <> e, y <> o}

def EO.go(xs: List<&2, Reg>) -> EO:
  match xs:
    case x <> y <> t:
      EO.cons(x, y, EO.go(t))
    case x <> Nil{}:
      EO{[x], Nil{}}
    case Nil{}:
      EO{Nil{}, Nil{}}

type STree is Data:
  DNone{}
  DOne{r: Reg}
  DTwo{a: STree, b: STree}

def EO.with(p: EO, k: List<&2, Reg> -> List<&2, Reg> -> STree) -> STree:
  match p:
    case EO{e, o}:
      k(e, o)

def Sched.tree(k: Nat, xs: List<&2, Reg>) -> STree:
  match k xs:
    case 0n x <> _:
      DOne{x}
    case 0n Nil{}:
      DNone{}
    case 1n+e0 _:
      +e = e0
      EO.with(EO.go(xs), ev => od => DTwo{Sched.tree(e, ev), Sched.tree(e, od)})

type ITree is Data:
  INil{}
  ILeaf{i: Image}
  INode{a: ITree, b: ITree}

def Img.has(img: Image, +c: U32) -> Bool:
  match img:
    case Pix{x}:
      U32.is_eq(x, c)
    case Qua{a, b, d, e}:
      Bool.or(Bool.or(Img.has(a, c), Img.has(b, c)), Bool.or(Img.has(d, c), Img.has(e, c)))

def Img.pick(open: Bool, +c: U32, u: Image) -> Image:
  match open:
    case True{}:
      u
    case False{}:
      Pix{c}

# the face with its opening pixels taken from what lies under them
def Img.merge(f: Image, u: Image) -> Image:
  match f u:
    case Pix{+c} _:
      Img.pick(U32.is_eq(c, Face.open()), c, u)
    case Qua{a, b, c, d} Pix{+x}:
      Qua{Img.merge(a, Pix{x}), Img.merge(b, Pix{x}), Img.merge(c, Pix{x}), Img.merge(d, Pix{x})}
    case Qua{a, b, c, d} Qua{ua, ub, uc, ud}:
      Qua{Img.merge(a, ua), Img.merge(b, ub), Img.merge(c, uc), Img.merge(d, ud)}

def Face.under(open: Bool, f: Image, +under: List<&2, R.Op>, +x: U32, +y: U32, +n: U32, +d: Nat) -> Image:
  match open:
    case True{}:
      Img.merge(f, R.Region.node(d, R.Region.leaf(under, x, y, n), under, x, y, n, Pix{Face.key()}))
    case False{}:
      f

def Face.region(+f: Image, +under: List<&2, R.Op>, +x: U32, +y: U32, +n: U32, +d: Nat) -> Image:
  Face.under(Img.has(f, Face.open()), f, under, x, y, n, d)

# the face first (the 2D rasterizer, over no board), then the triangles
def Reg.draw(r: Reg, +k: Nat, +n: U32, +bg: U32, +pl: Plane) -> Image:
  match r:
    case Reg{+x, +y, c, +ops, +under}:
      Seq.go(k, Chunks.list(c, Nil{}),
        Face.region(R.Region.node(Nat.add(k, 4n), R.Region.leaf(ops, x, y, n), ops, x, y, n, Pix{Face.key()}), under, x, y, n, Nat.add(k, 4n)),
        x, y, n, bg, pl)

# every region drawn, both halves at once
def Sched.run(t: STree, +k: Nat, +n: U32, +bg: U32, +pl: Plane) -> ITree:
  match t:
    case DNone{}:
      INil{}
    case DOne{r}:
      ILeaf{Reg.draw(r, k, n, bg, pl)}
    case DTwo{a, b}:
      i j = Sched.run(a, k, n, bg, Plane.copy(pl)) Sched.run(b, k, n, bg, Plane.copy(pl))
      INode{i, j}

def Inter.go(xs: List<&2, Image>, ys: List<&2, Image>) -> List<&2, Image>:
  match xs ys:
    case x <> xt y <> yt:
      x <> y <> Inter.go(xt, yt)
    case Nil{} _:
      ys
    case _ Nil{}:
      xs

# the drawn regions back in Morton order
def Sched.flat(t: ITree) -> List<&2, Image>:
  match t:
    case INil{}:
      Nil{}
    case ILeaf{i}:
      [i]
    case INode{a, b}:
      Inter.go(Sched.flat(a), Sched.flat(b))

def Img.quads(xs: List<&2, Image>) -> List<&2, Image>:
  match xs:
    case a <> b <> c <> d <> t:
      Qua{a, b, c, d} <> Img.quads(t)
    case _:
      Nil{}

def Img.one(xs: List<&2, Image>) -> Image:
  match xs:
    case x <> _:
      x
    case Nil{}:
      Pix{0}

# Morton-ordered squares k levels up into one image
def Img.up(k: Nat, xs: List<&2, Image>) -> Image:
  match k:
    case 0n:
      Img.one(xs)
    case 1n+e:
      Img.up(e, Img.quads(xs))

# Frames
# ------

# the view of a pw x ph panel whose corner is at (x0, y0) in a W x H frame
def View.at(v: View, +x0: U32, +y0: U32, +ww: U32, +hh: U32) -> View:
  match v:
    case View{ex, ey, ez, rx, ry, rz, ux, uy, uz, fx, fy, fz, f, cx, cy, n, _, _, lx, ly, lz}:
      View{ex, ey, ez, rx, ry, rz, ux, uy, uz, fx, fy, fz, f, F32.add(cx, U32.to_f32(x0)), F32.add(cy, U32.to_f32(y0)), n, U32.to_f32(ww), U32.to_f32(hh), lx, ly, lz}

# the view of a panel of a larger frame
def Mesh.view(+ww: U32, +hh: U32, +x0: U32, +y0: U32, +pw: U32, +ph: U32, +c: Cam) -> View:
  View.at(View.of(c, pw, ph), x0, y0, ww, hh)

def Mesh.draw.k(+w: U32, +h: U32, m: Model, +v: View, +now: Nat, fops: List<&2, R.Op>, under: List<&2, R.Op>, +pl: Plane, +bg: U32) -> Image:
  +d = R.Frame.depth(w, h)
  +lv = Nat.sub(d, 6n)
  +rd = Nat.sub(d, lv)
  Img.up(lv, Sched.flat(Sched.run(Sched.tree(Nat.mul(2n, lv),
    Reg.zip(Bins.flat(lv, Proj.tree(Model.tree(m), True{}, v, now, lv, U32.shln(1, d)), 0, 0, U32.shln(1, d), Nil{}),
      Ops.flat(lv, fops, 0, 0, U32.shln(1, d)), Ops.flat(lv, under, 0, 0, U32.shln(1, d)))),
    Nat.sub(rd, 4n), U32.shln(1, rd), bg, pl)))

# a w x h frame of the model through v, over a face (2D ops, topmost
# first, over Face.key() where there is no board) lying on plane pl, over
# bg; the image spans 2^R.Frame.depth(w, h) pixels, like the 2D
# rasterizer's
def Mesh.draw(+w: U32, +h: U32, m: Model, +v: View, +now: Nat, fo: FaceOps, +pl: Plane, +bg: U32) -> Image:
  match fo:
    case FaceOps{a, u}:
      Mesh.draw.k(w, h, m, v, now, a, u, pl, bg)

# the model through the camera, z-buffered, over bg
def Mesh.render(+w: U32, +h: U32, m: Model, +c: Cam, +bg: U32) -> Image:
  Mesh.draw(w, h, m, View.of(c, w, h), 0n, FaceOps{Nil{}, Nil{}}, Plane.none(), bg)

# render into a panel of a larger frame (the rest of the frame is bg or
# whatever falls outside the panel; the caller draws over it)
def Mesh.render.at(+ww: U32, +hh: U32, +x0: U32, +y0: U32, +pw: U32, +ph: U32, m: Model, +c: Cam, +bg: U32) -> Image:
  Mesh.draw(ww, hh, m, Mesh.view(ww, hh, x0, y0, pw, ph, c), 0n, FaceOps{Nil{}, Nil{}}, Plane.none(), bg)
