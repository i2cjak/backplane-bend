import Base
import ./check.bend as C
import ../src/core/client.bend as U
import ../src/core/model.bend as M
import ../src/app/nui.bend as N
import ../src/app/win.bend as W
import ../src/app/layout.bend as L

# Dragging a project in the window's sidebar: a press on a project's name,
# a drag and a release over another project ask the hub to reorder them.

def log() -> List<&2, M.Change>:
  [M.ProjectCreated{"p1", "board", "/tmp/board", 100n},
   M.ThreadCreated{"a", "p1", "Power sequencing", M.Local{}, "", "", "claude", "", 300n},
   M.ProjectCreated{"p2", "enclosure", "/tmp/enclosure", 400n},
   M.ProjectCreated{"p3", "firmware", "/tmp/firmware", 500n}]

def hits(o: L.Out) -> List<&2, N.Hit>:
  match o:
    case L.Out{_, hs}:
      hs

def with_hits(n: N.Nui, hs: List<&2, N.Hit>, +ms: Nat) -> N.Nui:
  match n:
    case N.Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, _, _, vw}:
      N.Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, hs, ms, vw}

def prepared(+n: N.Nui, +ms: Nat) -> N.Nui:
  N.Lbx.stamp(N.Blink.stamp(N.Hover.stamp(N.Nui.prepare(n), ms), ms), ms)

def step_nui(s: N.Step) -> N.Nui:
  match s:
    case N.Step{n, _, _}:
      n

def again(+ty: L.Ty, +n0: N.Nui) -> N.Nui:
  +n = prepared(n0, 0n)
  with_hits(n, hits(L.Lay.frame(ty, L.Lay.memo(ty, n, L.TL.memo.none()), n)), 0n)

def ev(+n: N.Nui, e: W.WinEv) -> N.Nui:
  step_nui(N.Nui.event(n, e))

# the middle of a project's name row (0: not drawn)
def head_y(hs: List<&2, N.Hit>, +id: String) -> U32:
  match hs:
    case Nil{}:
      0
    case N.Hit{_, +y0, _, _, +a, +v} <> t:
      Bool.pick(U32, Bool.and(String.eq(a, "project"), String.eq(v, id)), (y0 + 14 : U32), head_y(t, id))

def sent.go(cs: List<&2, N.NCmd>) -> String:
  match cs:
    case Nil{}:
      ""
    case N.NSend{t} <> _:
      t
    case _ <> r:
      sent.go(r)

def sent(s: N.Step) -> String:
  match s:
    case N.Step{_, cs, _}:
      sent.go(cs)

def nhits(n: N.Nui) -> List<&2, N.Hit>:
  match n:
    case N.Nui{_, _, _, _, _, _, _, _, _, _, hs, _, _}:
      hs

def main() -> IO(Unit):
  do IO<Unit>:
    +ty : L.Ty <- L.Ty.load()
    +n : N.Nui = again(ty, N.Nui.init(U.Ui.fold(log(), U.Ui.init(1000n)), 1400, 900))
    +y1 : U32 = head_y(nhits(n), "p1")
    +y3 : U32 = head_y(nhits(n), "p3")
    +n1 : N.Nui = again(ty, ev(n, W.WButton{100, y1, 1, True{}}))
    +n2 : N.Nui = again(ty, ev(n1, W.WMove{100, y3}))
    C.Check.str("order before", String.join(U.Side.projects(N.Nui.ui(n)), ","), "p3,p2,p1")
    C.Check.str("heads drawn", Bool.show(Bool.and(U32.is_gt(y1, y3), U32.is_gt(y3, 0))), "True")
    C.Check.str("press arms", U.Ui.scratch(N.Nui.ui(n1), "@drag"), "project:p1")
    C.Check.str("ghost title", U.Drag.title(U.Ui.state(N.Nui.ui(n1)), U.Ui.scratch(N.Nui.ui(n1), "@drag")), "board")
    C.Check.str("drop reorders", sent(N.Nui.event(n2, W.WButton{100, y3, 1, False{}})), "{\"id\":0,\"m\":\"project.reorder\",\"p\":{\"project\":\"p1\",\"ids\":[\"p1\",\"p3\",\"p2\"]}}")
    C.Check.str("a click is no drag", sent(N.Nui.event(n1, W.WButton{100, y1, 1, False{}})), "")
