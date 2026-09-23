import Base
import ../core/glb.bend as G
import ./raster.bend as R

# A z-buffered triangle rasterizer for the 3D model viewer. The host pass
# projects every world triangle through an orbit camera, culls the ones
# facing away, shades each flat (Lambert with a fixed light and a little
# ambient) and sets up its edge and depth planes. The frame is then a
# quadtree: each region keeps the triangles whose pixel boxes reach it,
# forks four ways down to 16-px tiles, and a tile splits (without forking)
# to 4x4 blocks that walk their short list once, keeping the nearest hit
# per pixel. No sort: depth is 1/z, interpolated linearly in screen space.
# A translucent triangle (colour transparency > 25) is kept as one extra
# layer per pixel, mixed over the nearest opaque hit when it is in front.

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
  +big = {1000000000.0 : F32}
  Cam.of_box(Box3.go(ts, Box3{big, big, big, F32.neg(big), F32.neg(big), F32.neg(big)}), 0.7)

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

# edges AB, BC, CA and the 1/z plane of a screen triangle
def Proj.edges(+xa: F32, +ya: F32, +ia: F32, +xb: F32, +yb: F32, +ib: F32, +xc: F32, +yc: F32, +ic: F32,
    +w: F32, +h: F32, +col: U32, +alpha: U32, acc: List<&2, STri>) -> List<&2, STri>:
  +a0 = F32.sub(ya, yb)
  +b0 = F32.sub(xb, xa)
  +c0 = F32.sub(F32.mul(xa, yb), F32.mul(xb, ya))
  +a1 = F32.sub(yb, yc)
  +b1 = F32.sub(xc, xb)
  +c1 = F32.sub(F32.mul(xb, yc), F32.mul(xc, yb))
  +a2 = F32.sub(yc, ya)
  +b2 = F32.sub(xa, xc)
  +c2 = F32.sub(F32.mul(xc, ya), F32.mul(xa, yc))
  +area = F32.add(F32.add(F32.mul(a0, xc), F32.mul(b0, yc)), c0)
  +inv = F32.div(1.0, area)
  Proj.box(area, xa, ya, xb, yb, xc, yc, w, h, a0, b0, c0, a1, b1, c1, a2, b2, c2,
    F32.mul(F32.add(F32.add(F32.mul(ia, a1), F32.mul(ib, a2)), F32.mul(ic, a0)), inv),
    F32.mul(F32.add(F32.add(F32.mul(ia, b1), F32.mul(ib, b2)), F32.mul(ic, b0)), inv),
    F32.mul(F32.add(F32.add(F32.mul(ia, c1), F32.mul(ib, c2)), F32.mul(ic, c0)), inv), col, alpha, acc)

def Proj.screen(ok: Bool, +v: View, +xa: F32, +ya: F32, +za: F32, +xb: F32, +yb: F32, +zb: F32, +xc: F32, +yc: F32, +zc: F32,
    +col: U32, +alpha: U32, acc: List<&2, STri>) -> List<&2, STri>:
  match ok v:
    case True{} View{_, _, _, _, _, _, _, _, _, _, _, _, +f, +cx, +cy, _, w, h, _, _, _}:
      Proj.edges(F32.add(cx, F32.div(F32.mul(f, xa), za)), F32.sub(cy, F32.div(F32.mul(f, ya), za)), F32.div(1.0, za),
        F32.add(cx, F32.div(F32.mul(f, xb), zb)), F32.sub(cy, F32.div(F32.mul(f, yb), zb)), F32.div(1.0, zb),
        F32.add(cx, F32.div(F32.mul(f, xc), zc)), F32.sub(cy, F32.div(F32.mul(f, yc), zc)), F32.div(1.0, zc), w, h, col, alpha, acc)
    case _ _:
      acc

def Proj.dot(+a: F32, +b: F32, +c: F32, +x: F32, +y: F32, +z: F32) -> F32:
  F32.add(F32.add(F32.mul(a, x), F32.mul(b, y)), F32.mul(c, z))

# the three vertices in view space (x right, y up, z forward)
def Proj.view(+v: View, +ax: F32, +ay: F32, +az: F32, +bx: F32, +by: F32, +bz: F32, +cx: F32, +cy: F32, +cz: F32,
    +col: U32, +alpha: U32, acc: List<&2, STri>) -> List<&2, STri>:
  match v:
    case View{+ex, +ey, +ez, +rx, +ry, +rz, +ux, +uy, +uz, +fx, +fy, +fz, _, _, _, +near, _, _, _, _, _}:
      +za = Proj.dot(fx, fy, fz, F32.sub(ax, ex), F32.sub(ay, ey), F32.sub(az, ez))
      +zb = Proj.dot(fx, fy, fz, F32.sub(bx, ex), F32.sub(by, ey), F32.sub(bz, ez))
      +zc = Proj.dot(fx, fy, fz, F32.sub(cx, ex), F32.sub(cy, ey), F32.sub(cz, ez))
      Proj.screen(Bool.and(F32.is_gt(za, near), Bool.and(F32.is_gt(zb, near), F32.is_gt(zc, near))), v,
        Proj.dot(rx, ry, rz, F32.sub(ax, ex), F32.sub(ay, ey), F32.sub(az, ez)), Proj.dot(ux, uy, uz, F32.sub(ax, ex), F32.sub(ay, ey), F32.sub(az, ez)), za,
        Proj.dot(rx, ry, rz, F32.sub(bx, ex), F32.sub(by, ey), F32.sub(bz, ez)), Proj.dot(ux, uy, uz, F32.sub(bx, ex), F32.sub(by, ey), F32.sub(bz, ez)), zb,
        Proj.dot(rx, ry, rz, F32.sub(cx, ex), F32.sub(cy, ey), F32.sub(cz, ez)), Proj.dot(ux, uy, uz, F32.sub(cx, ex), F32.sub(cy, ey), F32.sub(cz, ez)), zc,
        col, alpha, acc)

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
    F32.mul(dist, 0.0001), w, h,
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

# flat Lambert over a little ambient, lit from whichever side faces us
def Proj.shade(+c: U32, +facing: Bool, +nx: F32, +ny: F32, +nz: F32, +lx: F32, +ly: F32, +lz: F32) -> U32:
  +len = F32.max(F32.sqrt(Proj.dot(nx, ny, nz, nx, ny, nz)), 0.0000000001)
  +lam = F32.max(F32.div(Proj.flip(Bool.not(facing), Proj.dot(nx, ny, nz, lx, ly, lz)), len), 0.0)
  Rgb.scale(U32.and(c, 16777215), F32.add(0.3, F32.mul(0.7, lam)))

def Proj.light(v: View, +c: U32, +facing: Bool, +nx: F32, +ny: F32, +nz: F32) -> U32:
  match v:
    case View{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, lx, ly, lz}:
      Proj.shade(c, facing, nx, ny, nz, lx, ly, lz)

def Proj.front(keep: Bool, +facing: Bool, +v: View, +ax: F32, +ay: F32, +az: F32, +bx: F32, +by: F32, +bz: F32, +cx: F32, +cy: F32, +cz: F32,
    +nx: F32, +ny: F32, +nz: F32, +col: U32, acc: List<&2, STri>) -> List<&2, STri>:
  match keep:
    case True{}:
      Proj.view(v, ax, ay, az, bx, by, bz, cx, cy, cz, Proj.light(v, col, facing, nx, ny, nz), (255 - U32.shrn(col, 24n) : U32), acc)
    case False{}:
      acc

# the eye is on the triangle's front side (glTF fronts wind CCW)
def Proj.facing(+v: View, +ax: F32, +ay: F32, +az: F32, +nx: F32, +ny: F32, +nz: F32) -> Bool:
  match v:
    case View{ex, ey, ez, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      F32.is_gt(Proj.dot(nx, ny, nz, F32.sub(ex, ax), F32.sub(ey, ay), F32.sub(ez, az)), 0.0)

def Proj.normal(+cull: Bool, +v: View, +ax: F32, +ay: F32, +az: F32, +bx: F32, +by: F32, +bz: F32, +cx: F32, +cy: F32, +cz: F32,
    +col: U32, acc: List<&2, STri>) -> List<&2, STri>:
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
  Proj.front(Bool.or(facing, Bool.not(cull)), facing, v, ax, ay, az, bx, by, bz, cx, cy, cz, nx, ny, nz, col, acc)

# every world triangle that shows, as a screen triangle
def Proj.all(ts: List<&2, G.Tri3>, +cull: Bool, +v: View, acc: List<&2, STri>) -> List<&2, STri>:
  match ts:
    case Nil{}:
      acc
    case G.Tri3{ax, ay, az, bx, by, bz, cx, cy, cz, col} <> t:
      Proj.all(t, cull, v, Proj.normal(cull, v, ax, ay, az, bx, by, bz, cx, cy, cz, col, acc))

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

def Blk.draw(ts: List<&2, STri>, +rx: U32, +ry: U32, +bg: U32) -> Image:
  match ts:
    case Nil{}:
      Pix{bg}
    case _:
      +h = {Hit{0.0, bg, 0.0, bg, 0} : Hit}
      +fx = F32.add(U32.to_f32(rx), 0.5)
      +fy = F32.add(U32.to_f32(ry), 0.5)
      Blk.go(ts, fx, F32.add(fx, 1.0), F32.add(fx, 2.0), F32.add(fx, 3.0), fy, F32.add(fy, 1.0), F32.add(fy, 2.0), F32.add(fy, 3.0),
        h, h, h, h, h, h, h, h, h, h, h, h, h, h, h, h)

# does the triangle's pixel box meet the h x h square at (qx, qy)?
def Q4.hits(+x0: U32, +y0: U32, +x1: U32, +y1: U32, +qx: U32, +qy: U32, +h: U32) -> Bool:
  Bool.and(Bool.and(U32.is_lt(x0, (qx + h : U32)), U32.is_ge(x1, qx)), Bool.and(U32.is_lt(y0, (qy + h : U32)), U32.is_ge(y1, qy)))

def Q4.keep(hit: Bool, +t: STri, rest: List<&2, STri>) -> List<&2, STri>:
  match hit:
    case True{}:
      t <> rest
    case False{}:
      rest

def Q4.put(+t: STri, +qx: U32, +qy: U32, +h: U32, q: Q4) -> Q4:
  match t q:
    case STri{+x0, +y0, +x1, +y1, _, _, _, _, _, _, _, _, _, _, _, _, _, _} Q4{a, b, c, d}:
      +mx = (qx + h : U32)
      +my = (qy + h : U32)
      Q4{Q4.keep(Q4.hits(x0, y0, x1, y1, qx, qy, h), t, a), Q4.keep(Q4.hits(x0, y0, x1, y1, mx, qy, h), t, b),
        Q4.keep(Q4.hits(x0, y0, x1, y1, qx, my, h), t, c), Q4.keep(Q4.hits(x0, y0, x1, y1, mx, my, h), t, d)}

# the triangles of each quadrant of the 2h square at (qx, qy), one pass
def Q4.go(ts: List<&2, STri>, +qx: U32, +qy: U32, +h: U32) -> Q4:
  match ts:
    case Nil{}:
      Q4{Nil{}, Nil{}, Nil{}, Nil{}}
    case +t <> r:
      Q4.put(t, qx, qy, h, Q4.go(r, qx, qy, h))

def Tile.b8.k(q: Q4, +rx: U32, +ry: U32, +bg: U32) -> Image:
  match q:
    case Q4{a, b, c, d}:
      Qua{Blk.draw(a, rx, ry, bg), Blk.draw(b, (rx + 4 : U32), ry, bg), Blk.draw(c, rx, (ry + 4 : U32), bg), Blk.draw(d, (rx + 4 : U32), (ry + 4 : U32), bg)}

def Tile.b8(ts: List<&2, STri>, +rx: U32, +ry: U32, +bg: U32) -> Image:
  match ts:
    case Nil{}:
      Pix{bg}
    case _:
      Tile.b8.k(Q4.go(ts, rx, ry, 4), rx, ry, bg)

def Tile.b16.k(q: Q4, +rx: U32, +ry: U32, +bg: U32) -> Image:
  match q:
    case Q4{a, b, c, d}:
      Qua{Tile.b8(a, rx, ry, bg), Tile.b8(b, (rx + 8 : U32), ry, bg), Tile.b8(c, rx, (ry + 8 : U32), bg), Tile.b8(d, (rx + 8 : U32), (ry + 8 : U32), bg)}

# a 16-px tile: split to blocks without forking
def Tile.b16(ts: List<&2, STri>, +rx: U32, +ry: U32, +bg: U32) -> Image:
  Tile.b16.k(Q4.go(ts, rx, ry, 8), rx, ry, bg)

def Node.split(q: Q4, k: List<&2, STri> -> List<&2, STri> -> List<&2, STri> -> List<&2, STri> -> Image) -> Image:
  match q:
    case Q4{a, b, c, d}:
      k(a, b, c, d)

# the region of 16 * 2^k pixels at (rx, ry): forks four ways per level
def Node.go(k: Nat, ts: List<&2, STri>, +rx: U32, +ry: U32, +n: U32, +bg: U32) -> Image:
  match k ts:
    case _ Nil{}:
      Pix{bg}
    case 0n _:
      Tile.b16(ts, rx, ry, bg)
    case 1n+e0 _:
      +e = e0
      +h = U32.shr(n)
      +x2 = (rx + h : U32)
      +y2 = (ry + h : U32)
      Node.split(Q4.go(ts, rx, ry, h), qa => qb => qc => qd => (
        a b c d = Node.go(e, qa, rx, ry, h, bg) Node.go(e, qb, x2, ry, h, bg) Node.go(e, qc, rx, y2, h, bg) Node.go(e, qd, x2, y2, h, bg)
        Qua{a, b, c, d}))

# Frames
# ------

# the screen triangles of a w x h frame (back faces culled when `cull`)
def Mesh.project(+w: U32, +h: U32, ts: List<&2, G.Tri3>, +c: Cam, +cull: Bool) -> List<&2, STri>:
  Proj.all(ts, cull, View.of(c, w, h), Nil{})

# a w x h frame of screen triangles over the background colour; the image
# spans 2^R.Frame.depth(w, h) pixels, like the 2D rasterizer's
def Mesh.raster(+w: U32, +h: U32, ts: List<&2, STri>, +bg: U32) -> Image:
  +d = R.Frame.depth(w, h)
  Node.go(Nat.sub(d, 4n), ts, 0, 0, U32.shln(1, d), bg)

# the triangles through the camera, z-buffered, over bg
def Mesh.render(+w: U32, +h: U32, ts: List<&2, G.Tri3>, +c: Cam, +bg: U32) -> Image:
  Mesh.raster(w, h, Mesh.project(w, h, ts, c, True{}), bg)

# the view of a pw x ph panel whose corner is at (x0, y0) in a W x H frame
def View.at(v: View, +x0: U32, +y0: U32, +ww: U32, +hh: U32) -> View:
  match v:
    case View{ex, ey, ez, rx, ry, rz, ux, uy, uz, fx, fy, fz, f, cx, cy, n, _, _, lx, ly, lz}:
      View{ex, ey, ez, rx, ry, rz, ux, uy, uz, fx, fy, fz, f, F32.add(cx, U32.to_f32(x0)), F32.add(cy, U32.to_f32(y0)), n, U32.to_f32(ww), U32.to_f32(hh), lx, ly, lz}

# render into a panel of a larger frame (the rest of the frame is bg or
# whatever falls outside the panel; the caller draws over it)
def Mesh.render.at(+ww: U32, +hh: U32, +x0: U32, +y0: U32, +pw: U32, +ph: U32, ts: List<&2, G.Tri3>, +c: Cam, +bg: U32) -> Image:
  Mesh.raster(ww, hh, Proj.all(ts, True{}, View.at(View.of(c, pw, ph), x0, y0, ww, hh), Nil{}), bg)
