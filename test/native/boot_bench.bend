import Base
import ../../src/server/server.bend as S
import ../../src/core/model.bend as M
import ../../src/core/client.bend as U
import ../../src/core/json.bend as J
import ../../src/core/store.bend as ST
import ../../src/app/nui.bend as N
import ../../src/app/layout.bend as L
import ../../src/app/theme.bend as T
import ../../src/gfx/raster.bend as R
import ../../src/gfx/tiles.bend as TI
import ../../src/app/win.bend as W

# Start-up, timed step by step on a real event log, as the app does it
# before its first frame: read, parse, replay, the log message for the
# window, the window's own replay of it, fonts, the first layout and tiles.
#   scripts/build-app.sh test/native/boot_bench.bend build/boot_bench
#   build/boot_bench ~/.backplane-bend/events.jsonl   (only reads it)

def ops(o: L.Out) -> List<&2, R.Op>:
  match o:
    case L.Out{os, _}:
      os

def prepared(+n: N.Nui, +ms: Nat) -> N.Nui:
  N.Lbx.stamp(N.Blink.stamp(N.Hover.stamp(N.Nui.prepare(n), ms), ms), ms)

def seen(+n: Nat, +what: String, +a: Nat, +b: Nat) -> IO(Unit):
  IO.print(what ++ ": " ++ Nat.show(Nat.sub(b, a)) ++ " ms (" ++ Nat.show(n) ++ ")")

def count(s: M.State) -> Nat:
  match s:
    case M.State{_, _, es, _, _, _, _, _, _, _}:
      List.length(&2, M.Entry, es)

def some(f: TI.Tiles) -> Nat:
  match f:
    case _:
      1n

def path(xs: List<String>) -> String:
  match xs:
    case Nil{}:
      "/dev/null"
    case p <> Nil{}:
      p
    case _ <> t:
      path(t)

def ent_thread(e: M.Entry) -> String:
  match e:
    case M.Msg{_, t, _, _, _}:
      t
    case M.Act{_, t, _, _, _, _}:
      t

def entries(s: M.State) -> List<&2, M.Entry>:
  match s:
    case M.State{_, _, es, _, _, _, _, _, _, _}:
      es

# the thread of the first entry not in `not`
def other(es: List<&2, M.Entry>, +not: String) -> String:
  match es:
    case Nil{}:
      ""
    case +e <> t:
      Bool.pick(String, String.eq(ent_thread(e), not), other(t, not), ent_thread(e))

def act_ui(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}:
      u

def hits(o: L.Out) -> List<&2, N.Hit>:
  match o:
    case L.Out{_, hs}:
      hs

def with_hits(n: N.Nui, hs: List<&2, N.Hit>, +ms: Nat) -> N.Nui:
  match n:
    case N.Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, _, _, vw}:
      N.Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, hs, ms, vw}

def step_nui(s: N.Step) -> N.Nui:
  match s:
    case N.Step{n, _, _}:
      n

# what one frame leaves for the next
type Kept is Data:
  Kept{n: N.Nui, memo: L.TLMemo, frames: TI.Frames}

def kept_n(k: Kept) -> N.Nui:
  match k:
    case Kept{n, _, _}:
      n

def warm(+ty: L.Ty, +n0: N.Nui) -> Kept:
  +n = prepared(n0, 0n)
  +memo = L.Lay.memo(ty, n, L.TL.memo.none())
  +o = L.Lay.frame(ty, memo, n)
  Kept{with_hits(n, hits(o), 0n), memo, TI.FSome{N.Nui.width(n), N.Nui.height(n), TI.Frame.again(N.Nui.width(n), N.Nui.height(n), ops(o), Pix{T.Th.bg()}, TI.FNone{})}}

# one event and the frame after it, timed: event, memo, layout, tiles (ms)
def step(+what: String, e: W.WinEv, +ty: L.Ty, k: Kept) -> IO(Kept):
  match k:
    case Kept{n0, memo0, fr0}:
      do IO<Kept>:
        +t0 : Nat <- IO.now()
        +n1 : N.Nui = prepared(step_nui(N.Nui.event(n0, e)), 7n)
        +t1 : Nat <- IO.now()
        +memo : L.TLMemo = L.Lay.memo(ty, n1, memo0)
        +t2 : Nat <- IO.now()
        +o : L.Out = L.Lay.frame(ty, memo, n1)
        +k2 : Nat = List.length(&2, R.Op, ops(o))
        +t3 : Nat <- IO.now()
        +tiles : TI.Tiles = TI.Frame.again(N.Nui.width(n1), N.Nui.height(n1), ops(o), Pix{T.Th.bg()}, fr0)
        +img : Image = TI.Tiles.image(tiles)
        +t4 : Nat <- IO.now()
        IO.print(what ++ ": event " ++ Nat.show(Nat.sub(t1, t0)) ++ "  memo " ++ Nat.show(Nat.sub(t2, t1)) ++ "  layout " ++ Nat.show(Nat.sub(t3, t2))
          ++ "  tiles " ++ Nat.show(Nat.sub(t4, t3)) ++ "  = " ++ Nat.show(Nat.sub(t4, t0)) ++ " ms (" ++ Nat.show(k2) ++ " ops)")
        return Kept{with_hits(n1, hits(o), t4), memo, TI.FSome{N.Nui.width(n1), N.Nui.height(n1), tiles}}

def keys(cs: String, +ty: L.Ty, k: Kept) -> IO(Kept):
  match cs:
    case SNil{}:
      IO.pure(Kept, k)
    case SCon{Chr{+c}, rest}:
      IO.bind(Kept, Kept, step("key", W.WKey{c, c, 0, True{}}, ty, k), k2 => keys(rest, ty, k2))

def wheels(+i: Nat, +dir: U32, +ty: L.Ty, k: Kept) -> IO(Kept):
  match i:
    case 0n:
      IO.pure(Kept, k)
    case 1n+j:
      IO.bind(Kept, Kept, step("wheel", W.WWheel{700, 400, dir}, ty, k), k2 => wheels(j, dir, ty, k2))

def moves(+i: Nat, +ty: L.Ty, k: Kept) -> IO(Kept):
  match i:
    case 0n:
      IO.pure(Kept, k)
    case 1n+j:
      IO.bind(Kept, Kept, step("move", W.WMove{(100 + U32.from_nat(Nat.mul(j, 23n)) : U32), (200 + U32.from_nat(Nat.mul(j, 17n)) : U32)}, ty, k), k2 => moves(j, ty, k2))

def switch(+id: String, +ty: L.Ty, k: Kept) -> IO(Kept):
  match k:
    case Kept{+n0, memo0, fr0}:
      step("switch", W.WExpose{}, ty, Kept{N.Nui.with_ui(n0, act_ui(U.Ui.act(N.Nui.ui(n0), "select", id))), memo0, fr0})

def steady(+ty: L.Ty, +u: U.Ui) -> IO(Unit):
  +es = entries(U.Ui.state(u))
  +a = other(es, "")
  +b = other(es, a)
  +k = warm(ty, N.Nui.init(act_ui(U.Ui.act(u, "select", a)), 1400, 900))
  do IO<Unit>:
    k1 : Kept <- step("same frame", W.WExpose{}, ty, k)
    k2 : Kept <- keys("hello there", ty, k1)
    k3 : Kept <- wheels(4n, 1, ty, k2)
    k4 : Kept <- moves(4n, ty, k3)
    k5 : Kept <- switch(b, ty, k4)
    k6 : Kept <- switch(a, ty, k5)
    k7 : Kept <- step("resize", W.WSize{1300, 850}, ty, k6)
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +file : String = path(args)
    +t0 : Nat <- IO.now()
    +bs : List<&2, U32> <- S.Files.read(file)
    +t1 : Nat <- IO.now()
    seen(List.length(&2, U32, bs), "read bytes", t0, t1)
    +raw : List<&2, String> = S.Store.lines(bs)
    +t2 : Nat <- IO.now()
    seen(List.length(&2, String, raw), "split lines", t1, t2)
    +ld : ST.Loaded = ST.Store.load(raw, ST.Loaded{M.State.empty(), Nil{}})
    +st : M.State = ST.Loaded.st(ld)
    +ls : List<&2, String> = ST.Loaded.wire(ld)
    +t6 : Nat <- IO.now()
    seen(count(st), "load (parse, replay, wire: one pass)", t2, t6)
    +msg : String = "{\"t\":\"log\",\"since\":0,\"origin\":\"x\",\"version\":\"0\",\"info\":{},\"items\":[" ++ String.join(List.reverse(&2, String, ls), ",") ++ "]}"
    +t7 : Nat <- IO.now()
    seen(String.length(msg), "log message", t6, t7)
    +o : J.Json = Maybe.default(&2, J.Json, J.Json.parse(msg), J.Null{})
    +t8 : Nat <- IO.now()
    seen(List.length(&2, J.Json, J.Json.elems(J.Json.get_obj(o, "items"))), "window: parse message", t7, t8)
    +u : U.Ui = U.Ui.recv(U.Ui.init(1790000000n), o)
    +t9 : Nat <- IO.now()
    seen(count(U.Ui.state(u)), "window: replay", t8, t9)
    +ty : L.Ty <- L.Ty.load()
    +t10 : Nat <- IO.now()
    seen(0n, "fonts", t9, t10)
    +n : N.Nui = prepared(N.Nui.init(u, 1400, 900), t10)
    +memo : L.TLMemo = L.Lay.memo(ty, n, L.TL.memo.none())
    +out : L.Out = L.Lay.frame(ty, memo, n)
    +k : Nat = List.length(&2, R.Op, ops(out))
    +t11 : Nat <- IO.now()
    seen(k, "first layout", t10, t11)
    +tl : TI.Tiles = TI.Frame.again(1400, 900, ops(out), Pix{T.Th.bg()}, TI.FNone{})
    +im : Image = TI.Tiles.image(tl)
    +t12 : Nat <- IO.now()
    seen(some(tl), "first tiles", t11, t12)
    seen(0n, "total", t0, t12)
    steady(ty, u)
