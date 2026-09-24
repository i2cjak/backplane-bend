import Base
import ./check.bend as C
import ../src/gfx/mesh.bend as M
import ../src/app/nui.bend as N

# The 3D viewer's camera moves like SolidWorks': it turns about the model's
# centre wherever that sits on screen, zooms at the pointer, and nothing is
# locked to the world's up. Points are checked where they land on an
# 800 x 600 view, to the nearest pixel.

def W() -> U32:
  800

def H() -> U32:
  600

def dot(+ax: F32, +ay: F32, +az: F32, +bx: F32, +by: F32, +bz: F32) -> F32:
  F32.add(F32.add(F32.mul(ax, bx), F32.mul(ay, by)), F32.mul(az, bz))

def px(+f: F32) -> String:
  U32.show(F32.to_u32(F32.max(F32.add(f, 0.5), 0.0)))

# where the world point (x, y, z) lands on the view
def at.k(v: M.View, +x: F32, +y: F32, +z: F32) -> String:
  match v:
    case M.View{+ex, +ey, +ez, +rx, +ry, +rz, +ux, +uy, +uz, +fx, +fy, +fz, +f, +cx, +cy, _, _, _, _, _, _, _}:
      +dx = F32.sub(x, ex)
      +dy = F32.sub(y, ey)
      +dz = F32.sub(z, ez)
      +d = dot(fx, fy, fz, dx, dy, dz)
      px(F32.add(cx, F32.div(F32.mul(f, dot(rx, ry, rz, dx, dy, dz)), d))) ++ "," ++ px(F32.sub(cy, F32.div(F32.mul(f, dot(ux, uy, uz, dx, dy, dz)), d)))

def at(+c: M.Cam, +x: F32, +y: F32, +z: F32) -> String:
  at.k(M.View.of(c, W(), H()), x, y, z)

# the pivot is at (1, 2, 3), ten units away
def cam(+yaw: F32, +pitch: F32) -> M.Cam:
  M.Cam.at(yaw, pitch, 1.0, 2.0, 3.0, 10.0, 0.7)

def unit(+c: M.Cam) -> F32:
  M.Cam.unit(c, W(), H())

def pivot(+c: M.Cam) -> String:
  at(c, 1.0, 2.0, 3.0)

# the point on the pivot's plane (dx, dy) pixels off the centre of the
# unpanned camera c
def plane(c: M.Cam, +dx: F32, +dy: F32, +s: F32) -> String:
  match c:
    case M.Cam{+rx, +ry, +rz, +ux, +uy, +uz, +x, +y, +z, d, sx, sy, fov}:
      +a = F32.mul(dx, s)
      +b = F32.neg(F32.mul(dy, s))
      at(M.Cam{rx, ry, rz, ux, uy, uz, x, y, z, d, sx, sy, fov}, F32.add(x, F32.add(F32.mul(rx, a), F32.mul(ux, b))),
        F32.add(y, F32.add(F32.mul(ry, a), F32.mul(uy, b))), F32.add(z, F32.add(F32.mul(rz, a), F32.mul(uz, b))))

def plane.after(c: M.Cam, +z: M.Cam, +dx: F32, +dy: F32, +s: F32) -> String:
  match c:
    case M.Cam{+rx, +ry, +rz, +ux, +uy, +uz, +x, +y, +zz, _, _, _, _}:
      +a = F32.mul(dx, s)
      +b = F32.neg(F32.mul(dy, s))
      at(z, F32.add(x, F32.add(F32.mul(rx, a), F32.mul(ux, b))),
        F32.add(y, F32.add(F32.mul(ry, a), F32.mul(uy, b))), F32.add(zz, F32.add(F32.mul(rz, a), F32.mul(uz, b))))

# many turns in a row: the axes stay unit length and square
def spin(n: Nat, c: M.Cam) -> M.Cam:
  match n:
    case 0n:
      c
    case 1n+k:
      spin(k, M.Cam.roll(M.Cam.orbit(c, 0.37, F32.neg(0.23)), 0.11))

def square(c: M.Cam) -> String:
  match c:
    case M.Cam{+rx, +ry, +rz, +ux, +uy, +uz, _, _, _, _, _, _, _}:
      Bool.pick(String, Bool.and(F32.is_lt(F32.abs(F32.sub(dot(rx, ry, rz, rx, ry, rz), 1.0)), 0.0001),
        Bool.and(F32.is_lt(F32.abs(F32.sub(dot(ux, uy, uz, ux, uy, uz), 1.0)), 0.0001), F32.is_lt(F32.abs(dot(rx, ry, rz, ux, uy, uz)), 0.0001))), "yes", "no")

def main() -> IO(Unit):
  +c0 = cam(0.3, 0.95)
  +s = unit(c0)
  +panned = M.Cam.pan(c0, 50.0, F32.neg(20.0), s)
  +front = cam(0.0, 0.0)
  do IO<Unit>:
    C.Check.str("pivot at the centre", pivot(c0), "400,300")
    C.Check.str("pan: the model follows the pointer", pivot(panned), "450,280")
    C.Check.str("turn about the pivot where it is", pivot(M.Cam.orbit(panned, 0.7, F32.neg(0.4))), "450,280")
    C.Check.str("roll about the pivot where it is", pivot(M.Cam.roll(panned, 1.1)), "450,280")
    C.Check.str("over the top: no up lock", pivot(M.Cam.orbit(panned, 0.0, 4.0)), "450,280")
    C.Check.str("the point to zoom at", plane(c0, 200.0, F32.neg(100.0), s), "600,200")
    C.Check.str("zoom in keeps it under the pointer", plane.after(c0, M.Cam.zoom_at(c0, 0.5, 200.0, F32.neg(100.0), s), 200.0, F32.neg(100.0), s), "600,200")
    C.Check.str("zoom out keeps it under the pointer", plane.after(c0, M.Cam.zoom_at(c0, 1.2, 200.0, F32.neg(100.0), s), 200.0, F32.neg(100.0), s), "600,200")
    C.Check.str("front: the near side at the centre", at(front, 1.0, 2.0, 4.0), "400,300")
    C.Check.str("drag right: near side right", String.take(at(M.Cam.orbit(front, 0.2, 0.0), 1.0, 2.0, 4.0), 3n), "418")
    C.Check.str("drag down: near side down", at(M.Cam.orbit(front, 0.0, 0.2), 1.0, 2.0, 4.0), "400,318")
    C.Check.str("roll: the right side turns down (clockwise)", at(M.Cam.roll(front, 0.2), 2.0, 2.0, 3.0), "481,316")
    C.Check.str("front: up is up", at(N.Cam.key(1, c0, s), 1.0, 3.0, 3.0), "400,218")
    C.Check.str("top: looks down y", at(N.Cam.key(5, c0, s), 1.0, 3.0, 3.0), "400,300")
    C.Check.str("top: the back (-z) is up", at(N.Cam.key(5, c0, s), 1.0, 2.0, 2.0), "400,218")
    C.Check.str("right: looks along -x", at(N.Cam.key(4, c0, s), 2.0, 2.0, 3.0), "400,300")
    C.Check.str("left: looks along +x", at(N.Cam.key(3, c0, s), 0.0, 2.0, 3.0), "400,300")
    C.Check.str("standard views recentre", pivot(N.Cam.key(7, panned, s)), "400,300")
    C.Check.str("turns stay square", square(spin(500n, c0)), "yes")
    C.Check.str("wheel forward zooms out", Bool.pick(String, F32.is_gt(N.Wheel.dist(0), 1.0), "out", "in"), "out")
