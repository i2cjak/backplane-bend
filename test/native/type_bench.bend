import Base
import ../../src/core/client.bend as U
import ../../src/core/model.bend as M
import ../../src/app/nui.bend as N
import ../../src/app/win.bend as W
import ../../src/app/layout.bend as L
import ../../src/app/theme.bend as T
import ../../src/gfx/raster.bend as R
import ../../src/gfx/tiles.bend as TI

# Typing in the window, timed: each key goes through the same steps as in
# the app (the event, the timeline memo, layout, the tiles redrawn) with
# no window. A made-up log: one long thread and 30 short ones.
#   scripts/build-app.sh test/native/type_bench.bend build/type_bench
#   build/type_bench

def para(+i: Nat) -> String:
  "Message " ++ Nat.show(i) ++ ": the regulator's enable pin is pulled up through R12 to VBAT, so the output comes up before the MCU "
    ++ "drives it low. Moving R12 to the 3V3 rail fixes the sequencing, and C7 can stay where it is. **Next:** check the footprint "
    ++ "of U3 against the datasheet, then rerun DRC.\n\n- item one\n- item two with `code`\n"

def msg(+k: Nat, +th: String, +at: Nat) -> M.Change:
  M.MessagePosted{th, th ++ "m" ++ Nat.show(k), Bool.pick(M.Role, Nat.is_eq(Nat.mod(k, 2n), 0n), M.User{}, M.Assistant{}), para(k), Nat.add(at, k)}

def msgs(+n: Nat, +th: String, +at: Nat) -> List<&2, M.Change>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      msg(k, th, at) <> msgs(k, th, at)

def short(+k: Nat, +at: Nat) -> List<&2, M.Change>:
  M.ThreadCreated{"t" ++ Nat.show(1n+k), "p1", "Thread " ++ Nat.show(k), M.Local{}, "", "", "claude", "", at} <> msgs(20n, "t" ++ Nat.show(1n+k), at)

def threads(+n: Nat, +at: Nat) -> List<&2, M.Change>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      List.append(&2, M.Change, short(k, at), threads(k, at))

def log(+at: Nat) -> List<&2, M.Change>:
  List.concat(&2, M.Change, [[M.ProjectCreated{"p1", "board", "/tmp/board", at}, M.ThreadCreated{"t0", "p1", "Power sequencing", M.Local{}, "", "", "claude", "", at}],
    msgs(200n, "t0", at), threads(30n, at)])

def ui_sel(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}:
      u

# what one frame leaves: the window state (with its hit regions), the memo
# and the tiles
type Kept is Data:
  Kept{n: N.Nui, memo: L.TLMemo, frames: TI.Frames}

type Times is Data:
  Times{ev: Nat, memo: Nat, lay: Nat, tiles: Nat, worst: Nat, each: String}

def Times.add(t: Times, +a: Nat, +b: Nat, +c: Nat, +d: Nat) -> Times:
  match t:
    case Times{e, m, l, ti, +w, ea}:
      Times{Nat.add(e, a), Nat.add(m, b), Nat.add(l, c), Nat.add(ti, d), Bool.pick(Nat, Nat.is_gt(Nat.add(Nat.add(a, b), Nat.add(c, d)), w), Nat.add(Nat.add(a, b), Nat.add(c, d)), w),
        ea ++ " " ++ Nat.show(Nat.add(Nat.add(a, b), Nat.add(c, d)))}

def Times.show(t: Times, +keys: Nat) -> String:
  match t:
    case Times{+e, +m, +l, +ti, w, ea}:
      "per key (ms, mean of " ++ Nat.show(keys) ++ "): event " ++ Nat.show(Nat.div(e, keys)) ++ "." ++ Nat.show(Nat.div(Nat.mod(Nat.mul(e, 10n), Nat.mul(keys, 10n)), keys))
        ++ "  memo " ++ Nat.show(Nat.div(m, keys)) ++ "  layout " ++ Nat.show(Nat.div(l, keys)) ++ "  tiles " ++ Nat.show(Nat.div(ti, keys))
        ++ "  total " ++ Nat.show(Nat.div(Nat.add(Nat.add(e, m), Nat.add(l, ti)), keys)) ++ "  worst " ++ Nat.show(w) ++ "\n each:" ++ ea

def hits(o: L.Out) -> List<&2, N.Hit>:
  match o:
    case L.Out{_, hs}:
      hs

def ops(o: L.Out) -> List<&2, R.Op>:
  match o:
    case L.Out{os, _}:
      os

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

def kept_n(k: Kept) -> N.Nui:
  match k:
    case Kept{n, _, _}:
      n

# one key and the frame after it, timed
def key(cs: String, +ty: L.Ty, k: Kept, t: Times) -> IO(Times):
  match cs k:
    case SNil{} _:
      IO.pure(Times, t)
    case SCon{Chr{+c}, rest} Kept{+n0, memo0, fr0}:
      do IO<Times>:
        +t0 : Nat <- IO.now()
        +n1 : N.Nui = prepared(step_nui(N.Nui.event(n0, W.WKey{c, c, 0, True{}})), t0)
        +t1 : Nat <- IO.now()
        +memo : L.TLMemo = L.Lay.memo(ty, n1, memo0)
        +t2 : Nat <- IO.now()
        +o : L.Out = L.Lay.frame(ty, memo, n1)
        +k2 : Nat = List.length(&2, R.Op, ops(o))
        +t3 : Nat <- IO.now()
        +tiles : TI.Tiles = TI.Frame.again(N.Nui.width(n1), N.Nui.height(n1), ops(o), Pix{T.Th.bg()}, fr0, N.Hits.slide(hits(o), N.Nui.hits(n0)))
        +img : Image = TI.Tiles.image(tiles)
        +t4 : Nat <- IO.now()
        key(rest, ty, Kept{with_hits(n1, hits(o), t4), memo, TI.FSome{N.Nui.width(n1), N.Nui.height(n1), tiles}},
          Times.add(t, Nat.sub(t1, t0), Nat.sub(t2, t1), Nat.sub(t3, t2), Nat.sub(t4, t3)))

# the first frame (everything drawn), then the keys
def warm(+ty: L.Ty, +n0: N.Nui) -> Kept:
  +n = prepared(n0, 0n)
  +memo = L.Lay.memo(ty, n, L.TL.memo.none())
  +o = L.Lay.frame(ty, memo, n)
  Kept{with_hits(n, hits(o), 0n), memo, TI.FSome{N.Nui.width(n), N.Nui.height(n), TI.Frame.again(N.Nui.width(n), N.Nui.height(n), ops(o), Pix{T.Th.bg()}, TI.FNone{}, 0)}}

def text() -> String:
  "hello world, this is a test of typing speed in the composer "

def some(f: TI.Frames) -> Bool:
  match f:
    case TI.FNone{}:
      False{}
    case TI.FSome{_, _, _}:
      True{}

def nops(o: L.Out) -> Nat:
  List.length(&2, R.Op, ops(o))

# a part laid out r times (its op count, so each is made)
def rep.side(+r: Nat, +ty: L.Ty, +n: N.Nui) -> Nat:
  match r:
    case 0n:
      0n
    case 1n+q:
      Nat.add(nops(L.Lay.sidebar(ty, n, 900)), rep.side(q, ty, n))

def rep.thread(+r: Nat, +ty: L.Ty, +memo: L.TLMemo, +n: N.Nui) -> Nat:
  match r:
    case 0n:
      0n
    case 1n+q:
      Nat.add(nops(L.Lay.thread(ty, memo, n, 264, 1400)), rep.thread(q, ty, memo, n))

def rep.frame(+r: Nat, +ty: L.Ty, +memo: L.TLMemo, +n: N.Nui) -> Nat:
  match r:
    case 0n:
      0n
    case 1n+q:
      Nat.add(nops(L.Lay.frame(ty, memo, n)), rep.frame(q, ty, memo, n))

def rep.tiles(+r: Nat, +os: List<&2, R.Op>, +prev: TI.Frames) -> Nat:
  match r:
    case 0n:
      0n
    case 1n+q:
      Nat.add(Bool.pick(Nat, some(TI.FSome{1400, 900, TI.Frame.again(1400, 900, os, Pix{T.Th.bg()}, prev, 0)}), 1n, 0n), rep.tiles(q, os, prev))

def rep.make(+r: Nat, +os: List<&2, R.Op>) -> Nat:
  match r:
    case 0n:
      0n
    case 1n+q:
      Nat.add(Bool.pick(Nat, some(TI.FSome{1400, 900, TI.Frame.make(1400, 900, os, Pix{T.Th.bg()})}), 1n, 0n), rep.make(q, os))

def kept_memo(k: Kept) -> L.TLMemo:
  match k:
    case Kept{_, m, _}:
      m

def kept_frames(k: Kept) -> TI.Frames:
  match k:
    case Kept{_, _, f}:
      f

# each part of one frame, 50 times over (ms for all 50)
def parts(+ty: L.Ty, +k: Kept) -> IO(Unit):
  +n = prepared(kept_n(k), 5n)
  +memo = kept_memo(k)
  +os = ops(L.Lay.frame(ty, memo, n))
  do IO<Unit>:
    IO.print("ops per frame: " ++ Nat.show(List.length(&2, R.Op, os)) ++ " (sidebar " ++ Nat.show(nops(L.Lay.sidebar(ty, n, 900))) ++ ", thread " ++ Nat.show(nops(L.Lay.thread(ty, memo, n, 264, 1400))) ++ ")")
    +a : Nat <- IO.now()
    +x1 : Nat = rep.side(50n, ty, n)
    +b : Nat <- IO.now()
    +x2 : Nat = rep.thread(50n, ty, memo, n)
    +c : Nat <- IO.now()
    +x3 : Nat = rep.frame(50n, ty, memo, n)
    +d : Nat <- IO.now()
    +x4 : Nat = rep.tiles(50n, os, kept_frames(k))
    +e : Nat <- IO.now()
    +x5 : Nat = rep.make(10n, os)
    +f : Nat <- IO.now()
    IO.print("x50 ms: sidebar " ++ Nat.show(Nat.sub(b, a)) ++ "  thread " ++ Nat.show(Nat.sub(c, b)) ++ "  whole layout " ++ Nat.show(Nat.sub(d, c))
      ++ "  tiles (same frame again) " ++ Nat.show(Nat.sub(e, d)) ++ "   x10 tiles from scratch " ++ Nat.show(Nat.sub(f, e)) ++ "  " ++ Nat.show(Nat.add(Nat.add(x1, x2), Nat.add(x3, Nat.add(x4, x5)))))

# the first timeline line region of the last frame (its line and y)
def first_line(hs: List<&2, N.Hit>) -> U32:
  match hs:
    case Nil{}:
      0
    case N.Hit{_, +y0, _, _, +a, _} <> t:
      Bool.pick(U32, String.eq(a, "tl-line"), y0, first_line(t))

# a frame for n, its hits kept
def again(+ty: L.Ty, +n0: N.Nui, +memo: L.TLMemo) -> N.Nui:
  +n = prepared(n0, 0n)
  with_hits(n, hits(L.Lay.frame(ty, memo, n)), 0n)

def ev(+n: N.Nui, e: W.WinEv) -> N.Nui:
  step_nui(N.Nui.event(n, e))

# press on a line, drag three lines down, release: what ctrl+c copies
def select(+ty: L.Ty, +k: Kept) -> String:
  +n = kept_n(k)
  +y = first_line(N.Nui.hits(n))
  +n1 = again(ty, ev(n, W.WButton{460, 300, 1, True{}}), kept_memo(k))
  +n2 = again(ty, ev(n1, W.WMove{800, 380, 0}), kept_memo(k))
  +n3 = again(ty, ev(n2, W.WButton{800, 380, 1, False{}}), kept_memo(k))
  N.Sel.text(n3)

def main() -> IO(Unit):
  do IO<Unit>:
    +ty : L.Ty <- L.Ty.load()
    +a : Nat <- IO.now()
    +u : U.Ui = ui_sel(U.Ui.act(U.Ui.fold(log(1790000000n), U.Ui.init(1790000100n)), "select", "t0"))
    +k : Kept = warm(ty, N.Nui.init(u, 1400, 900))
    +b : Nat <- IO.now()
    IO.print("state and first frame: " ++ Nat.show(Nat.sub(b, a)) ++ " ms")
    parts(ty, k)
    IO.print("selected: [" ++ select(ty, k) ++ "]")
    t : Times <- key(text(), ty, k, Times{0n, 0n, 0n, 0n, 0n, ""})
    IO.print(Times.show(t, String.length(text())))
