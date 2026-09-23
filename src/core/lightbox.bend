import Base

# The image lightbox: a picture from a thread shown over everything, zoomed
# smoothly at the pointer and panned by dragging. Both clients keep an Lb
# and ask the defs here where the picture goes; every number is a Nat.
#
# Zoom is per mille of the fitted size (the picture shrunk to fit the
# window less a margin, never enlarged), kept within Lb.zmin() and
# Lb.zmax() (laws lightbox_zoom_min, lightbox_zoom_max). A wheel notch
# eases the zoom from where it is to its new target over Lb.ms() (laws
# lightbox_ease_start, lightbox_ease_done); a client asks for frames only
# while that runs (lightbox_idle).
#
# The view is an anchor: a point of the picture (ax, ay, in 1/2^24ths of
# its size) held at a point of the window (mx, my: the offset from the
# window's centre, plus Lb.bias() so it stays a Nat). Zooming at the pointer
# anchors the picture point under it, so that point stays put while the
# zoom eases; a drag carries the anchor's window point with the pointer.
# The scroll that results is clamped so a picture larger than the window
# always covers it (lightbox_scroll_max) and a smaller one sits centred.

# z0 -> z1 since t0 (t0 0: starts at the next frame), the anchor, the last
# pointer (px, py) and the press (qx, qy) of a drag, whether a button is
# down and whether the press was off the picture
type Lb is Data:
  Lb{z0: Nat, z1: Nat, t0: Nat, ax: Nat, ay: Nat, mx: Nat, my: Nat, px: Nat, py: Nat, qx: Nat, qy: Nat, down: Bool, out: Bool}

# the picture's own size and the window's
type LbBox is Data:
  LbBox{iw: Nat, ih: Nat, vw: Nat, vh: Nat}

# one axis of the view: the picture's shown length, the space before it
# (when it is shorter than the window) and how far it is scrolled (when
# longer), in pixels and in 1/256ths (sf); its window position is pad - s
type LbAx is Data:
  LbAx{d: Nat, pad: Nat, s: Nat, sf: Nat}

def Lb.zmin() -> Nat:
  1000n

def Lb.zmax() -> Nat:
  8000n

def Lb.ms() -> Nat:
  180n

def Lb.one() -> Nat:
  16777216n

# sub-pixel steps the scroll is kept in, so re-anchoring never drifts
def Lb.sub() -> Nat:
  256n

def Lb.bias() -> Nat:
  65536n

def Lb.margin() -> Nat:
  32n

def Lb.min(+a: Nat, +b: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_le(a, b), a, b)

def Lb.max(+a: Nat, +b: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_ge(a, b), a, b)

# a zoom kept within zmin .. zmax
def Lb.clamp(+z: Nat) -> Nat:
  Lb.max(Lb.zmin(), Lb.min(z, Lb.zmax()))

# Easing
# ------

# the eased share (per mille) of an ease age ms in (ease-out cubic)
def Lb.curve(age: Nat) -> Nat:
  match age:
    case 0n:
      0n
    case 1n+a:
      +r = Nat.sub(1000n, Nat.div(Nat.mul(1n+a, 1000n), Lb.ms()))
      Nat.sub(1000n, Nat.div(Nat.mul(Nat.mul(r, r), r), 1000000n))

def Lb.lerp.k(up: Bool, +e: Nat, +z0: Nat, +z1: Nat) -> Nat:
  match up:
    case True{}:
      Nat.add(z0, Nat.div(Nat.mul(Nat.sub(z1, z0), e), 1000n))
    case False{}:
      Nat.sub(z0, Nat.div(Nat.mul(Nat.sub(z0, z1), e), 1000n))

def Lb.lerp(e: Nat, +z0: Nat, +z1: Nat) -> Nat:
  match e:
    case 0n:
      z0
    case 1n+k:
      Lb.lerp.k(Nat.is_le(z0, z1), 1n+k, z0, z1)

def Lb.ease(done: Bool, +age: Nat, +z0: Nat, +z1: Nat) -> Nat:
  match done:
    case True{}:
      z1
    case False{}:
      Lb.lerp(Lb.curve(age), z0, z1)

# the zoom at `now` of an ease from z0 to z1 that began at t0: z0 at t0
# (lightbox_ease_start), z1 once Lb.ms() has passed (lightbox_ease_done)
def Lb.ease.at(+z0: Nat, +z1: Nat, +t0: Nat, +now: Nat) -> Nat:
  Lb.ease(Nat.is_ge(now, Nat.add(t0, Lb.ms())), Nat.sub(now, t0), z0, z1)

# whether an ease that began at t0 still runs at `now`
def Lb.easing(+t0: Nat, +now: Nat) -> Bool:
  Bool.not(Nat.is_ge(now, Nat.add(t0, Lb.ms())))

def Lb.zoom.k(t0: Nat, +z0: Nat, +z1: Nat, +now: Nat) -> Nat:
  match t0:
    case 0n:
      z0
    case 1n+p:
      Lb.ease.at(z0, z1, 1n+p, now)

# the zoom shown at `now`
def Lb.zoom(lb: Lb, +now: Nat) -> Nat:
  match lb:
    case Lb{+z0, +z1, t0, _, _, _, _, _, _, _, _, _, _}:
      Lb.zoom.k(t0, z0, z1, now)

def Lb.busy.k(t0: Nat, +z0: Nat, +z1: Nat, +now: Nat) -> Bool:
  match t0:
    case 0n:
      Bool.not(Nat.is_eq(z0, z1))
    case 1n+p:
      Bool.and(Bool.not(Nat.is_eq(z0, z1)), Lb.easing(1n+p, now))

# whether the zoom is still easing (a client draws another frame only then)
def Lb.busy(lb: Lb, +now: Nat) -> Bool:
  match lb:
    case Lb{+z0, +z1, t0, _, _, _, _, _, _, _, _, _, _}:
      Lb.busy.k(t0, z0, z1, now)

def Lb.stamp.k(t0: Nat, +now: Nat) -> Nat:
  match t0:
    case 0n:
      now
    case 1n+p:
      1n+p

# an ease waiting for its first frame starts now
def Lb.stamp(lb: Lb, +now: Nat) -> Lb:
  match lb:
    case Lb{z0, z1, t0, ax, ay, mx, my, px, py, qx, qy, dn, o}:
      Lb{z0, z1, Lb.stamp.k(t0, now), ax, ay, mx, my, px, py, qx, qy, dn, o}

# Geometry
# --------

# the picture's size at zoom 1000: shrunk to fit the window less a margin
# on each side, never enlarged
def Lb.fit.k(wide: Bool, +iw: Nat, +ih: Nat, +aw: Nat, +ah: Nat) -> Nat & Nat:
  match wide:
    case True{}:
      +w = Lb.min(iw, aw)
      (w, Nat.div(Nat.mul(ih, w), Lb.max(iw, 1n)))
    case False{}:
      +h = Lb.min(ih, ah)
      (Nat.div(Nat.mul(iw, h), Lb.max(ih, 1n)), h)

def Lb.fit(b: LbBox) -> Nat & Nat:
  match b:
    case LbBox{+iw, +ih, +vw, +vh}:
      +aw = Nat.sub(vw, Nat.mul(2n, Lb.margin()))
      +ah = Nat.sub(vh, Nat.mul(2n, Lb.margin()))
      Lb.fit.k(Nat.is_ge(Nat.mul(iw, ah), Nat.mul(ih, aw)), iw, ih, aw, ah)

def Lb.pad(+d: Nat, +v: Nat) -> Nat:
  Nat.div(Nat.sub(v, d), 2n)

# the scroll (in 1/256 px) that holds picture point a (of a picture shown d
# long) at anchor m, clamped so the picture covers the window: it never
# passes d - v (lightbox_scroll_max)
def Lb.scroll(+a: Nat, +m: Nat, +d: Nat, +v: Nat) -> Nat:
  Lb.min(Nat.sub(Nat.add(Nat.div(Nat.mul(Nat.mul(a, d), Lb.sub()), Lb.one()), Nat.mul(Nat.add(Lb.pad(d, v), Lb.bias()), Lb.sub())),
    Nat.mul(Nat.add(m, Nat.div(v, 2n)), Lb.sub())), Nat.mul(Nat.sub(d, v), Lb.sub()))

# one axis: the fitted length f at zoom z, anchored at (a, m), window v long
def Lb.axis(+f: Nat, +z: Nat, +a: Nat, +m: Nat, +v: Nat) -> LbAx:
  +d = Nat.div(Nat.mul(f, z), 1000n)
  +sf = Lb.scroll(a, m, d, v)
  LbAx{d, Lb.pad(d, v), Nat.div(sf, Lb.sub()), sf}

def Lb.x.k(lb: Lb, f: Nat & Nat, +v: Nat, +now: Nat) -> LbAx:
  match lb:
    case Lb{+z0, +z1, t0, +ax, _, +mx, _, _, _, _, _, _, _}:
      (+fw, _) = f
      Lb.axis(fw, Lb.zoom.k(t0, z0, z1, now), ax, mx, v)

def Lb.y.k(lb: Lb, f: Nat & Nat, +v: Nat, +now: Nat) -> LbAx:
  match lb:
    case Lb{+z0, +z1, t0, _, +ay, _, +my, _, _, _, _, _, _}:
      (_, +fh) = f
      Lb.axis(fh, Lb.zoom.k(t0, z0, z1, now), ay, my, v)

def LbBox.vw(b: LbBox) -> Nat:
  match b:
    case LbBox{_, _, vw, _}:
      vw

def LbBox.vh(b: LbBox) -> Nat:
  match b:
    case LbBox{_, _, _, vh}:
      vh

# the view across and down at `now`
def Lb.x(+lb: Lb, +b: LbBox, +now: Nat) -> LbAx:
  Lb.x.k(lb, Lb.fit(b), LbBox.vw(b), now)

def Lb.y(+lb: Lb, +b: LbBox, +now: Nat) -> LbAx:
  Lb.y.k(lb, Lb.fit(b), LbBox.vh(b), now)

# the picture point (1/2^24ths) at window coordinate c on an axis
def Lb.point(ax: LbAx, +c: Nat) -> Nat:
  match ax:
    case LbAx{+d, +pad, _, +sf}:
      Nat.div(Nat.mul(Nat.sub(Nat.add(sf, Nat.mul(c, Lb.sub())), Nat.mul(pad, Lb.sub())), Lb.one()), Nat.mul(d, Lb.sub()))

# window coordinate c as an anchor
def Lb.mark(+c: Nat, +v: Nat) -> Nat:
  Nat.sub(Nat.add(Lb.bias(), c), Nat.div(v, 2n))

# whether window coordinate c is on the picture along an axis
def Lb.on(ax: LbAx, +c: Nat) -> Bool:
  match ax:
    case LbAx{+d, +pad, +s, _}:
      Bool.and(Nat.is_ge(c, pad), Nat.is_lt(Nat.add(s, c), Nat.add(pad, d)))

# Interaction
# -----------

# a picture just opened: fitted and centred
def Lb.open() -> Lb:
  Lb{1000n, 1000n, 1n, 8388608n, 8388608n, Lb.bias(), Lb.bias(), 0n, 0n, 0n, 0n, False{}, False{}}

def Lb.anchor.k(lb: Lb, +z: Nat, +x: LbAx, +y: LbAx, +cx: Nat, +cy: Nat, +vw: Nat, +vh: Nat) -> Lb:
  match lb:
    case Lb{_, z1, _, _, _, _, _, px, py, qx, qy, dn, o}:
      Lb{z, z1, 1n, Lb.point(x, cx), Lb.point(y, cy), Lb.mark(cx, vw), Lb.mark(cy, vh), px, py, qx, qy, dn, o}

# hold the picture point now at window point (cx, cy), with the zoom
# frozen where it is now
def Lb.anchor(+lb: Lb, +b: LbBox, +cx: Nat, +cy: Nat, +now: Nat) -> Lb:
  Lb.anchor.k(lb, Lb.zoom(lb, now), Lb.x(lb, b, now), Lb.y(lb, b, now), cx, cy, LbBox.vw(b), LbBox.vh(b))

def Lb.target(lb: Lb) -> Nat:
  match lb:
    case Lb{_, z1, _, _, _, _, _, _, _, _, _, _, _}:
      z1

def Lb.retarget(lb: Lb, +z1: Nat, +t0: Nat) -> Lb:
  match lb:
    case Lb{z0, _, _, ax, ay, mx, my, px, py, qx, qy, dn, o}:
      Lb{z0, z1, t0, ax, ay, mx, my, px, py, qx, qy, dn, o}

# the zoom set at once to z (no ease)
def Lb.snap(lb: Lb, +z: Nat) -> Lb:
  match lb:
    case Lb{_, _, _, ax, ay, mx, my, px, py, qx, qy, dn, o}:
      Lb{z, z, 1n, ax, ay, mx, my, px, py, qx, qy, dn, o}

def Lb.wheel.k(eased: Bool, a: Lb, +z: Nat) -> Lb:
  match eased:
    case True{}:
      Lb.retarget(a, z, 0n)
    case False{}:
      Lb.snap(a, z)

# a wheel turn (up: zoom in) of size mag at (cx, cy): the zoom target moves
# by up to 1.5x a step from where it was headed; eased (t0 0: from the next
# frame) or at once (a trackpad pinch, already smooth)
def Lb.wheel(+lb: Lb, up: Bool, +mag: Nat, eased: Bool, +cx: Nat, +cy: Nat, +b: LbBox, +now: Nat) -> Lb:
  +f = Nat.add(1000n, Lb.min(Nat.mul(mag, 2n), 500n))
  +t = Lb.target(lb)
  +z = Lb.clamp(Bool.pick(Nat, up, Nat.div(Nat.mul(t, f), 1000n), Nat.div(Nat.mul(t, 1000n), f)))
  Lb.wheel.k(eased, Lb.anchor(lb, b, cx, cy, now), z)

# two fingers going from d0 apart to d1 apart around (cx, cy)
def Lb.pinch(+lb: Lb, +d0: Nat, +d1: Nat, +cx: Nat, +cy: Nat, +b: LbBox, +now: Nat) -> Lb:
  Lb.snap(Lb.anchor(lb, b, cx, cy, now), Lb.clamp(Nat.div(Nat.mul(Lb.zoom(lb, now), d1), Lb.max(d0, 1n))))

def Lb.pressed(lb: Lb, +x: Nat, +y: Nat, out: Bool) -> Lb:
  match lb:
    case Lb{+z0, _, _, ax, ay, mx, my, _, _, _, _, _, _}:
      Lb{z0, z0, 1n, ax, ay, mx, my, x, y, x, y, True{}, out}

# a press at (x, y): the zoom stops where it is and the point under the
# pointer is held there; out: the press was off the picture
def Lb.press(+lb: Lb, +x: Nat, +y: Nat, +b: LbBox, +now: Nat) -> Lb:
  Lb.pressed(Lb.anchor(lb, b, x, y, now), x, y, Bool.not(Bool.and(Lb.on(Lb.x(lb, b, now), x), Lb.on(Lb.y(lb, b, now), y))))

def Lb.dragged(lb: Lb, +x: Nat, +y: Nat, +vw: Nat, +vh: Nat) -> Lb:
  match lb:
    case Lb{z0, z1, t0, ax, ay, _, _, _, _, qx, qy, dn, o}:
      Lb{z0, z1, t0, ax, ay, Lb.mark(x, vw), Lb.mark(y, vh), x, y, qx, qy, dn, o}

def Lb.px(lb: Lb) -> Nat:
  match lb:
    case Lb{_, _, _, _, _, _, _, px, _, _, _, _, _}:
      px

def Lb.py(lb: Lb) -> Nat:
  match lb:
    case Lb{_, _, _, _, _, _, _, _, py, _, _, _, _}:
      py

def Lb.is_down(lb: Lb) -> Bool:
  match lb:
    case Lb{_, _, _, _, _, _, _, _, _, _, _, dn, _}:
      dn

def Lb.move.k(down: Bool, +lb: Lb, +x: Nat, +y: Nat, +b: LbBox, +now: Nat) -> Lb:
  match down:
    case True{}:
      Lb.dragged(Lb.anchor(lb, b, Lb.px(lb), Lb.py(lb), now), x, y, LbBox.vw(b), LbBox.vh(b))
    case False{}:
      lb

# the pointer moved to (x, y): while a button is down the picture follows
# it (re-anchored where the pointer was, so a clamped edge lets go at once
# when the pointer turns back)
def Lb.move(+lb: Lb, +x: Nat, +y: Nat, +b: LbBox, +now: Nat) -> Lb:
  Lb.move.k(Lb.is_down(lb), lb, x, y, b, now)

def Lb.released(lb: Lb) -> Lb:
  match lb:
    case Lb{z0, z1, t0, ax, ay, mx, my, px, py, qx, qy, _, _}:
      Lb{z0, z1, t0, ax, ay, mx, my, px, py, qx, qy, False{}, False{}}

def Lb.release(+lb: Lb, +x: Nat, +y: Nat, +b: LbBox, +now: Nat) -> Lb:
  Lb.released(Lb.move(lb, x, y, b, now))

def Lb.near(+a: Nat, +b: Nat) -> Bool:
  Nat.is_lt(Nat.add(Nat.sub(a, b), Nat.sub(b, a)), 5n)

# whether a release at (x, y) closes the lightbox: a click (it did not
# drag) that began off the picture
def Lb.closes(lb: Lb, +x: Nat, +y: Nat) -> Bool:
  match lb:
    case Lb{_, _, _, _, _, _, _, _, _, +qx, +qy, dn, o}:
      Bool.and(Bool.and(dn, o), Bool.and(Lb.near(qx, x), Lb.near(qy, y)))

# Drawing
# -------

# where the picture lands on one axis of a frame: its window start, the
# visible length, and the scroll into the shown picture
def LbAx.at(ax: LbAx) -> Nat:
  match ax:
    case LbAx{_, pad, _, _}:
      pad

def LbAx.len(ax: LbAx, +v: Nat) -> Nat:
  match ax:
    case LbAx{+d, +pad, +s, _}:
      Lb.min(Nat.sub(d, s), Nat.sub(v, pad))

def LbAx.s(ax: LbAx) -> Nat:
  match ax:
    case LbAx{_, _, s, _}:
      s

def LbAx.d(ax: LbAx) -> Nat:
  match ax:
    case LbAx{d, _, _, _}:
      d

# a window offset as CSS pixels (negative when scrolled)
def LbAx.css(ax: LbAx) -> String:
  match ax:
    case LbAx{_, +pad, +s, _}:
      Bool.pick(String, Nat.is_eq(s, 0n), Nat.show(pad), "-" ++ Nat.show(s)) ++ "px"

def Lb.css.k(x: LbAx, y: LbAx) -> String:
  match x y:
    case LbAx{+dx, px, sx, fx} LbAx{+dy, py, sy, fy}:
      "width:" ++ Nat.show(dx) ++ "px;height:" ++ Nat.show(dy) ++ "px;transform:translate(" ++ LbAx.css(LbAx{dx, px, sx, fx}) ++ "," ++ LbAx.css(LbAx{dy, py, sy, fy}) ++ ")"

# the web picture's style at `now`
def Lb.css(+lb: Lb, +b: LbBox, +now: Nat) -> String:
  Lb.css.k(Lb.x(lb, b, now), Lb.y(lb, b, now))

# The close control: a square at the window's top right
def Lb.close_x(+vw: Nat) -> Nat:
  Nat.sub(vw, 48n)

def Lb.close_hit(+x: Nat, +y: Nat, +vw: Nat) -> Bool:
  Bool.and(Bool.and(Nat.is_ge(x, Lb.close_x(vw)), Nat.is_lt(x, Nat.add(Lb.close_x(vw), 36n))), Bool.and(Nat.is_ge(y, 12n), Nat.is_lt(y, 48n)))

# State as text (the native window keeps it in its scratch strings)
# ----------------------------------------------------------------

def Lb.bit(b: Bool) -> String:
  Bool.pick(String, b, "1", "0")

def Lb.show(lb: Lb) -> String:
  match lb:
    case Lb{z0, z1, t0, ax, ay, mx, my, px, py, qx, qy, dn, o}:
      String.join([Nat.show(z0), Nat.show(z1), Nat.show(t0), Nat.show(ax), Nat.show(ay), Nat.show(mx), Nat.show(my),
        Nat.show(px), Nat.show(py), Nat.show(qx), Nat.show(qy), Lb.bit(dn), Lb.bit(o)], ",")

def Lb.num(+s: String) -> Nat:
  Maybe.default(&2, Nat, Nat.read(s), 0n)

def Lb.read.k(xs: List<&2, String>) -> Lb:
  match xs:
    case +a <> +b <> +c <> +d <> +e <> +f <> +g <> +h <> +i <> +j <> +k <> +l <> +m <> _:
      Lb{Lb.num(a), Lb.num(b), Lb.num(c), Lb.num(d), Lb.num(e), Lb.num(f), Lb.num(g), Lb.num(h), Lb.num(i), Lb.num(j), Lb.num(k), String.eq(l, "1"), String.eq(m, "1")}
    case _:
      Lb.open()

# a kept Lb (anything unreadable: a fresh one)
def Lb.read(+s: String) -> Lb:
  Lb.read.k(String.split(s, ','))
