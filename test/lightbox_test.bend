import Base
import ./check.bend as C
import ../src/core/lightbox.bend as L

# a 2000 x 1000 picture in a 1000 x 800 window
def box() -> L.LbBox:
  L.LbBox{2000n, 1000n, 1000n, 800n}

def ax(a: L.LbAx) -> String:
  match a:
    case L.LbAx{d, p, s, _}:
      Nat.show(d) ++ "/" ++ Nat.show(p) ++ "/" ++ Nat.show(s)

def view(+lb: L.Lb, +now: Nat) -> String:
  ax(L.Lb.x(lb, box(), now)) ++ " " ++ ax(L.Lb.y(lb, box(), now))

# the window position of picture point p (1/2^24ths) on an axis
def at(a: L.LbAx, +p: Nat) -> Nat:
  match a:
    case L.LbAx{+d, +pad, +s, _}:
      Nat.sub(Nat.add(pad, Nat.div(Nat.mul(p, d), 16777216n)), s)

# how far picture point p (under window point c before) is from c at `now`
def drift(+before: L.LbAx, +after: L.LbAx, +c: Nat) -> Nat:
  +p = L.Lb.point(before, c)
  Nat.add(Nat.sub(at(after, p), c), Nat.sub(c, at(after, p)))

def ins(n: Nat, lb: L.Lb) -> L.Lb:
  match n:
    case 0n:
      lb
    case 1n+k:
      ins(k, L.Lb.wheel(lb, True{}, 100n, False{}, 500n, 400n, box(), 0n))

def outs(n: Nat, lb: L.Lb) -> L.Lb:
  match n:
    case 0n:
      lb
    case 1n+k:
      outs(k, L.Lb.wheel(lb, False{}, 100n, False{}, 500n, 400n, box(), 0n))

def b(x: Bool) -> String:
  Bool.pick(String, x, "yes", "no")

def main() -> IO(Unit):
  +o = L.Lb.open()
  # a notch in at (700, 300), eased from t = 1000
  +w = L.Lb.stamp(L.Lb.wheel(o, True{}, 100n, True{}, 700n, 300n, box(), 1000n), 1000n)
  +big = ins(30n, o)
  +dragged = L.Lb.release(L.Lb.move(L.Lb.press(big, 500n, 400n, box(), 0n), 400n, 350n, box(), 0n), 400n, 350n, box(), 0n)
  +far = L.Lb.release(L.Lb.move(L.Lb.press(ins(2n, o), 500n, 400n, box(), 0n), 999n, 799n, box(), 0n), 999n, 799n, box(), 0n)
  do IO<Unit>:
    C.Check.str("opens fitted and centred", view(o, 0n), "936/32/0 468/166/0")
    C.Check.str("style", L.Lb.css(o, box(), 0n), "width:936px;height:468px;transform:translate(32px,166px)")
    C.Check.str("ease starts where it was", Nat.show(L.Lb.zoom(w, 1000n)), "1000")
    C.Check.str("ease moves", b(Nat.is_gt(L.Lb.zoom(w, 1060n), 1000n)), "yes")
    C.Check.str("ease ends at the target", Nat.show(L.Lb.zoom(w, 1180n)), "1200")
    C.Check.str("busy while easing", b(L.Lb.busy(w, 1100n)), "yes")
    C.Check.str("idle after", b(L.Lb.busy(w, 1180n)), "no")
    C.Check.str("pending ease is busy", b(L.Lb.busy(L.Lb.wheel(o, True{}, 100n, True{}, 700n, 300n, box(), 1000n), 5n)), "yes")
    C.Check.str("open is idle", b(L.Lb.busy(o, 0n)), "no")
    C.Check.str("anchor stays put mid-ease", b(Nat.is_le(drift(L.Lb.x(o, box(), 0n), L.Lb.x(w, box(), 1090n), 700n), 1n)), "yes")
    C.Check.str("anchor stays put after", b(Nat.is_le(drift(L.Lb.x(o, box(), 0n), L.Lb.x(w, box(), 5000n), 700n), 1n)), "yes")
    C.Check.str("zoom stops at the max", Nat.show(L.Lb.zoom(big, 0n)), "8000")
    C.Check.str("zoom stops at the fit", Nat.show(L.Lb.zoom(outs(5n, ins(3n, o)), 0n)), "1000")
    C.Check.str("zoomed in, the picture covers the window", view(big, 0n), "7488/0/3244 3744/0/1474")
    C.Check.str("drag follows the pointer", view(dragged, 0n), "7488/0/3344 3744/0/1524")
    C.Check.str("drag stops at the edge", view(far, 0n), "1347/0/0 673/63/0")
    C.Check.str("a click off the picture closes", b(L.Lb.closes(L.Lb.press(o, 10n, 10n, box(), 0n), 12n, 11n)), "yes")
    C.Check.str("a click on it does not", b(L.Lb.closes(L.Lb.press(o, 500n, 400n, box(), 0n), 500n, 400n)), "no")
    C.Check.str("a drag off it does not", b(L.Lb.closes(L.Lb.press(o, 10n, 10n, box(), 0n), 300n, 10n)), "no")
    C.Check.str("close control", b(Bool.and(L.Lb.close_hit(970n, 30n, 1000n), Bool.not(L.Lb.close_hit(500n, 30n, 1000n)))), "yes")
    C.Check.str("kept as text", L.Lb.show(L.Lb.read(L.Lb.show(dragged))), L.Lb.show(dragged))
    C.Check.str("unreadable is fresh", L.Lb.show(L.Lb.read("x")), L.Lb.show(o))
