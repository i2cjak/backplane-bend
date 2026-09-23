import Base
import ../server/server.bend as S
import ../server/host.bend as H
import ../core/prompt.bend as Q
import ../core/json.bend as J
import ../core/client.bend as U
import ../gfx/raster.bend as R
import ./win.bend as W
import ./nui.bend as N
import ./layout.bend as L
import ./theme.bend as T

# `backplane`: the hub, the web server (for other devices), and the native
# window as client 0. Window events and hub messages meet in one queue; a
# frame is drawn at most every 12 ms and only when something changed.

type ShellMsg is Data:
  FromWin{words: List<&2, U32>}
  FromHub{text: String}
  Frame{}
  Gone{}

type Shell is Type:
  Shell{nui: N.Nui, win: Window, dirty: Bool, queued: Bool, q: Chan(ShellMsg), inbox: Chan(S.Msg)}

def Pump.got(r: Window & List<&2, U32>, +q: Chan(ShellMsg), k: Window -> IO(Unit)) -> IO(Unit):
  (w, ws) = r
  do IO<Unit>:
    ok : Bool <- Chan.send(ShellMsg, q, FromWin{ws})
    k(w)

# Feeders
# -------

def Pump.loop(fuel: Nat, w: Window, +q: Chan(ShellMsg)) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      IO.bind(Window & List<&2, U32>, Unit, W.Win.words(w), r => Pump.got(r, q, w2 => Pump.loop(f, w2, q)))

def Fwd.got(m: Maybe<&1, S.Wire>, +q: Chan(ShellMsg), k: Unit -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{S.WText{t}}:
      do IO<Unit>:
        ok : Bool <- Chan.send(ShellMsg, q, FromHub{t})
        k(Unit{})
    case Some{_}:
      k(Unit{})
    case None{}:
      do IO<Unit>:
        ok : Bool <- Chan.send(ShellMsg, q, Gone{})
        return Unit{}

# the hub's messages for client 0
def Fwd.loop(fuel: Nat, +out: Chan(S.Wire), +q: Chan(ShellMsg)) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      IO.bind(Maybe<&1, S.Wire>, Unit, Chan.recv(S.Wire, out), m => Fwd.got(m, q, u => Fwd.loop(f, out, q)))

def Timer.once(+q: Chan(ShellMsg)) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(12)
    ok : Bool <- Chan.send(ShellMsg, q, Frame{})
    return Unit{}

# Drawing
# -------

def Shell.later(a: Shell) -> IO(Shell):
  match a:
    case Shell{n, w, _, True{}, +q, i}:
      IO.pure(Shell, Shell{n, w, True{}, True{}, q, i})
    case Shell{n, w, _, False{}, +q, i}:
      do IO<Shell>:
        IO.spawn(Unit, Timer.once(q))
        return Shell{n, w, True{}, True{}, q, i}

def Shell.hits(n: N.Nui, hs: List<&2, N.Hit>, +now: Nat) -> N.Nui:
  match n:
    case N.Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, _, ms}:
      N.Nui{U.Ui.tick(u, now), w, h, mx, my, sd, sc, ca, fo, pa, hs, ms}

def Shell.shown(r: Window & Image, n: N.Nui, +q: Chan(ShellMsg), +i: Chan(S.Msg)) -> IO(Shell):
  (w, img) = r
  do IO<Shell>:
    Unit <- IO.pure(Unit, Image.drop!(img))
    return Shell{n, w, False{}, False{}, q, i}

def Shell.paint(n: N.Nui, w: Window, +q: Chan(ShellMsg), +i: Chan(S.Msg), o: L.Out, +now: Nat) -> IO(Shell):
  match n o:
    case N.Nui{u, +ww, +hh, mx, my, sd, sc, ca, fo, pa, _, ms} L.Out{ops, hs}:
      IO.bind(Window & Image, Shell, W.Win.present(w, R.Frame.render(ww, hh, ops, T.Th.bg())),
        r => Shell.shown(r, Shell.hits(N.Nui{u, ww, hh, mx, my, sd, sc, ca, fo, pa, Nil{}, ms}, hs, now), q, i))

# draw now if anything changed since the last frame
def Shell.frame(a: Shell) -> IO(Shell):
  match a:
    case Shell{+n, w, True{}, _, q, i}:
      do IO<Shell>:
        t : U32 <- H.Clock.epoch()
        Shell.paint(n, w, q, i, L.Lay.frame(n), U32.to_nat(t))
    case Shell{n, w, False{}, _, q, i}:
      IO.pure(Shell, Shell{n, w, False{}, False{}, q, i})

# Commands
# --------

def Shell.cmd(a: Shell, c: N.NCmd) -> IO(Shell):
  match a c:
    case Shell{n, w, d, qd, q, +i} N.NSend{t}:
      do IO<Shell>:
        ok : Bool <- Chan.send(S.Msg, i, S.Rpc{0, t})
        return Shell{n, w, d, qd, q, i}
    case Shell{n, w, d, qd, q, i} N.NCopy{t}:
      do IO<Shell>:
        w2 : Window <- W.Win.copy(w, t)
        return Shell{n, w2, d, qd, q, i}
    case Shell{n, w, d, qd, q, i} N.NPaste{}:
      do IO<Shell>:
        w2 : Window <- W.Win.paste(w)
        return Shell{n, w2, d, qd, q, i}
    case _ N.NQuit{}:
      IO.die(Shell, 0, "")

def Shell.cmds(cs: List<&2, N.NCmd>, a: Shell) -> IO(Shell):
  match cs:
    case Nil{}:
      IO.pure(Shell, a)
    case c <> t:
      IO.bind(Shell, Shell, Shell.cmd(a, c), a2 => Shell.cmds(t, a2))

def Shell.dirty(a: Shell) -> IO(Shell):
  match a:
    case Shell{n, w, True{}, qd, q, i}:
      Shell.later(Shell{n, w, True{}, qd, q, i})
    case _:
      IO.pure(Shell, a)

# fold a step into the app: its state, its commands, maybe a frame
def Shell.step(a: Shell, s: N.Step) -> IO(Shell):
  match a s:
    case Shell{_, w, d, qd, q, i} N.Step{n, cs, dirty}:
      IO.bind(Shell, Shell, Shell.cmds(cs, Shell{n, w, Bool.or(d, dirty), qd, q, i}), Shell.dirty)

# Events
# ------

def Shell.pasted(r: Window & String, +n: N.Nui, d: Bool, qd: Bool, +q: Chan(ShellMsg), +i: Chan(S.Msg)) -> IO(Shell):
  (w, text) = r
  Shell.step(Shell{n, w, d, qd, q, i}, N.Nui.paste(n, text))

def Shell.event(a: Shell, e: W.WinEv) -> IO(Shell):
  match a e:
    case Shell{n, w, d, qd, q, i} W.WPaste{_}:
      IO.bind(Window & String, Shell, W.Win.pasted(w), r => Shell.pasted(r, n, d, qd, q, i))
    case Shell{+n, w, d, qd, q, i} _:
      Shell.step(Shell{n, w, d, qd, q, i}, N.Nui.event(n, e))

def Shell.events(es: List<&2, W.WinEv>, a: Shell) -> IO(Shell):
  match es:
    case Nil{}:
      IO.pure(Shell, a)
    case e <> t:
      IO.bind(Shell, Shell, Shell.event(a, e), a2 => Shell.events(t, a2))

def Shell.recv(a: Shell, +text: String) -> IO(Shell):
  match a:
    case Shell{n, w, _, qd, q, i}:
      Shell.later(Shell{N.Nui.recv(n, Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{})), w, True{}, qd, q, i})

def Shell.handle(a: Shell, m: ShellMsg) -> IO(Shell):
  match m:
    case FromWin{ws}:
      Shell.events(W.Win.decode(ws), a)
    case FromHub{t}:
      Shell.recv(a, t)
    case Frame{}:
      Shell.frame(a)
    case Gone{}:
      IO.die(Shell, 0, "")

def Shell.queue(a: Shell, k: Chan(ShellMsg) -> Shell -> IO(Unit)) -> IO(Unit):
  match a:
    case Shell{n, w, d, qd, +q, i}:
      k(q, Shell{n, w, d, qd, q, i})

def Shell.got(m: Maybe<&1, ShellMsg>, a: Shell, k: Shell -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{msg}:
      IO.bind(Shell, Unit, Shell.handle(a, msg), k)
    case None{}:
      IO.pure(Unit, Unit{})

def Shell.loop(fuel: Nat, a: Shell) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      Shell.queue(a, q => a2 =>
        IO.bind(Maybe<&1, ShellMsg>, Unit, Chan.recv(ShellMsg, q), m => Shell.got(m, a2, a3 => Shell.loop(f, a3))))

# Start
# -----

def Shell.twin(r: Window & Window, +inbox: Chan(S.Msg)) -> IO(Unit):
  (ev, pw) = r
  do IO<Unit>:
    +q : Chan(ShellMsg) <- Chan.new(ShellMsg, 8192)
    +out : Chan(S.Wire) <- Chan.new(S.Wire, 8192)
    t : U32 <- H.Clock.epoch()
    ok : Bool <- Chan.send(S.Msg, inbox, S.Join{0, out})
    IO.spawn(Unit, Pump.loop(S.Fuel.forever(), ev, q))
    IO.spawn(Unit, Fwd.loop(S.Fuel.forever(), out, q))
    a : Shell <- Shell.later(Shell{N.Nui.init(U.Ui.init(U32.to_nat(t)), 1400, 900), pw, True{}, False{}, q, inbox})
    Shell.loop(S.Fuel.forever(), a)

# no display: keep serving the web UI
def Shell.nowin(e: U32 & String) -> IO(Unit):
  (_, msg) = e
  IO.print_err("backplane: no window (" ++ msg ++ "); serving the web UI only")

def Shell.opened(r: Result<&1, &1, U32 & String, Window>, +inbox: Chan(S.Msg)) -> IO(Unit):
  match r:
    case Done{w}:
      IO.bind(Window & Window, Unit, W.Win.twin(w), p => Shell.twin(p, inbox))
    case Fail{e}:
      Shell.nowin(e)

def Shell.run(+inbox: Chan(S.Msg)) -> IO(Unit):
  IO.bind(Result<&1, &1, U32 & String, Window>, Unit, W.Win.open("Backplane", 1400, 900), r => Shell.opened(r, inbox))

def main() -> IO(Unit):
  do IO<Unit>:
    +user : String <- S.Env.get("HOME", "/tmp")
    exe : String <- S.Sys.exe_dir.io()
    args : List<String> <- IO.args()
    ks : String & List<&2, Q.Skill> <- S.Skills.kistack(user)
    kicad : String <- S.Env.get("BACKPLANE_KICAD_CLI", "kicad-cli")
    S.Main.boot(S.Main.config(user, exe, args, ks, kicad), False{}, i => Shell.run(i))
