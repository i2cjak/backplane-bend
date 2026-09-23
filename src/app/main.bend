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
import ./viewer.bend as V
import ../core/board.bend as B
import ../gfx/draw.bend as D
import ../server/kicad.bend as K
import ../gfx/text.bend as X
import ../core/glb.bend as G
import ../gfx/mesh.bend as MS
import ../core/schematic.bend as SC
import ../server/proc.bend as P

# `backplane`: the hub, the web server (for other devices), and the native
# window as client 0. Window events and hub messages meet in one queue; a
# frame is drawn at most every 12 ms and only when something changed.

type ShellMsg is Data:
  FromWin{words: List<&2, U32>}
  FromHub{text: String}
  Frame{}
  Gone{}
  Board{key: String, items: List<&2, B.Item>}
  Mesh3{key: String, tris: List<&2, G.Tri3>}
  Status{key: String, text: String}

# the boards being watched and the fonts
type Aux is Data:
  Aux{watched: List<&2, String>, ty: L.Ty}

type Shell is Type:
  Shell{nui: N.Nui, win: Window, dirty: Bool, queued: Bool, q: Chan(ShellMsg), inbox: Chan(S.Msg), aux: Aux}

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
    case Shell{n, w, _, True{}, +q, i, wa}:
      IO.pure(Shell, Shell{n, w, True{}, True{}, q, i, wa})
    case Shell{n, w, _, False{}, +q, i, wa}:
      do IO<Shell>:
        IO.spawn(Unit, Timer.once(q))
        return Shell{n, w, True{}, True{}, q, i, wa}

def Shell.hits(n: N.Nui, hs: List<&2, N.Hit>, +now: Nat) -> N.Nui:
  match n:
    case N.Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, _, ms, vw}:
      N.Nui{U.Ui.tick(u, now), w, h, mx, my, sd, sc, ca, fo, pa, hs, ms, vw}

# a fade still running asks for the next frame
def Shell.again(anim: Bool, a: Shell) -> IO(Shell):
  match anim:
    case True{}:
      Shell.later(a)
    case False{}:
      IO.pure(Shell, a)

def Shell.shown(r: Window & Image, n: N.Nui, +q: Chan(ShellMsg), +i: Chan(S.Msg), wa: Aux, anim: Bool) -> IO(Shell):
  (w, img) = r
  do IO<Shell>:
    Unit <- IO.pure(Unit, Image.drop!(img))
    Shell.again(anim, Shell{n, w, False{}, False{}, q, i, wa})

def Shell.busy(vw: V.Vw, +now: Nat) -> Bool:
  match vw:
    case V.Vw{ss, _, _, _, _, _, _, _, _, _, vx}:
      V.Fade.busy(ss, now)

# Commands
# --------

def Shell.cmd(a: Shell, c: N.NCmd) -> IO(Shell):
  match a c:
    case Shell{n, w, d, qd, q, +i, wa} N.NSend{t}:
      do IO<Shell>:
        ok : Bool <- Chan.send(S.Msg, i, S.Rpc{0, t})
        return Shell{n, w, d, qd, q, i, wa}
    case Shell{n, w, d, qd, q, i, wa} N.NCopy{t}:
      do IO<Shell>:
        w2 : Window <- W.Win.copy(w, t)
        return Shell{n, w2, d, qd, q, i, wa}
    case Shell{n, w, d, qd, q, i, wa} N.NPaste{}:
      do IO<Shell>:
        w2 : Window <- W.Win.paste(w)
        return Shell{n, w2, d, qd, q, i, wa}
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
    case Shell{n, w, True{}, qd, q, i, wa}:
      Shell.later(Shell{n, w, True{}, qd, q, i, wa})
    case _:
      IO.pure(Shell, a)

# fold a step into the app: its state, its commands, maybe a frame
def Shell.step(a: Shell, s: N.Step) -> IO(Shell):
  match a s:
    case Shell{_, w, d, qd, q, i, wa} N.Step{n, cs, dirty}:
      IO.bind(Shell, Shell, Shell.cmds(cs, Shell{n, w, Bool.or(d, dirty), qd, q, i, wa}), Shell.dirty)

# Events
# ------

def Shell.pasted(r: Window & String, +n: N.Nui, d: Bool, qd: Bool, +q: Chan(ShellMsg), +i: Chan(S.Msg), wa: Aux) -> IO(Shell):
  (w, text) = r
  Shell.step(Shell{n, w, d, qd, q, i, wa}, N.Nui.paste(n, text))

def Shell.event(a: Shell, e: W.WinEv) -> IO(Shell):
  match a e:
    case Shell{n, w, d, qd, q, i, wa} W.WPaste{_}:
      IO.bind(Window & String, Shell, W.Win.pasted(w), r => Shell.pasted(r, n, d, qd, q, i, wa))
    case Shell{+n, w, d, qd, q, i, wa} _:
      Shell.step(Shell{n, w, d, qd, q, i, wa}, N.Nui.event(n, e))

def Shell.events(es: List<&2, W.WinEv>, a: Shell) -> IO(Shell):
  match es:
    case Nil{}:
      IO.pure(Shell, a)
    case e <> t:
      IO.bind(Shell, Shell, Shell.event(a, e), a2 => Shell.events(t, a2))

def Shell.recv(a: Shell, +text: String) -> IO(Shell):
  match a:
    case Shell{n, w, _, qd, q, i, wa}:
      Shell.later(Shell{N.Nui.recv(n, Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{})), w, True{}, qd, q, i, wa})

def Shell.queue(a: Shell, k: Chan(ShellMsg) -> Shell -> IO(Unit)) -> IO(Unit):
  match a:
    case Shell{n, w, d, qd, +q, i, wa}:
      k(q, Shell{n, w, d, qd, q, i, wa})

# The board watcher
# -----------------














def Shell.has(ws: List<&2, String>, +r: String) -> Bool:
  match ws:
    case Nil{}:
      False{}
    case w <> t:
      Bool.or(String.eq(w, r), Shell.has(t, r))

def Aux.ty(a: Aux) -> L.Ty:
  match a:
    case Aux{_, t}:
      t

def Aux.watched(a: Aux) -> List<&2, String>:
  match a:
    case Aux{ws, _}:
      ws

def Aux.add(a: Aux, r: String) -> Aux:
  match a:
    case Aux{ws, t}:
      Aux{r <> ws, t}

# no display: keep serving the web UI
def Shell.nowin(e: U32 & String) -> IO(Unit):
  (_, msg) = e
  IO.print_err("backplane: no window (" ++ msg ++ "); serving the web UI only")

# Viewer sources
# --------------
# A source key is "kind|root|path" (V.Src.key): kind 0 board, 1 schematic,
# 2 3D; path, when set, is a file an agent asked to show, else the
# project's canonical file of that kind.

def Src.at(+key: String, +i: Nat) -> String:
  Maybe.default(&2, String, List.head(&2, String, List.drop(&2, String, String.split(key, '|'), i)), "")

def Src.kind(+key: String) -> U32:
  Maybe.default(&2, U32, U32.read(Src.at(key, 0n)), 0)

def Watch.file.k(+kind: U32, f: K.Files, +path: String) -> String:
  match f:
    case K.Files{_, pcb, sch}:
      Bool.pick(String, String.is_empty(path), Bool.pick(String, U32.is_eq(kind, 1), sch, pcb), path)

# the file behind a source ("" when the project has none)
def Watch.file(+key: String) -> IO(String):
  IO.bind(K.Files, String, K.Files.read(Src.at(key, 1n)), f => IO.pure(String, Watch.file.k(Src.kind(key), f, Src.at(key, 2n))))

def Watch.say(+key: String, +text: String, +q: Chan(ShellMsg)) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(ShellMsg, q, Status{key, text})
    return Unit{}

def Watch.sorted(m: Maybe<&2, List<&2, B.Item>>) -> Maybe<&2, List<&2, B.Item>>:
  match m:
    case Some{+xs}:
      Some{V.Scene.sort(xs)}
    case None{}:
      None{}

def Watch.sent(m: Maybe<&2, List<&2, B.Item>>, +key: String, +q: Chan(ShellMsg)) -> IO(Unit):
  match m:
    case Some{xs}:
      do IO<Unit>:
        ok : Bool <- Chan.send(ShellMsg, q, Board{key, xs})
        return Unit{}
    case None{}:
      IO.pure(Unit, Unit{})

def Watch.parse.k(sch: Bool, bs: List<&2, U32>) -> Maybe<&2, List<&2, B.Item>>:
  match sch:
    case True{}:
      SC.Sch.items(bs)
    case False{}:
      B.Board.items(bs)

def Watch.parse(+kind: U32, bs: List<&2, U32>) -> Maybe<&2, List<&2, B.Item>>:
  Watch.parse.k(U32.is_eq(kind, 1), bs)

# a filename-safe form of a source key
def Watch.safe(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{Chr{+c}, t}:
      SCon{Chr{Bool.pick(U32, Bool.or(Bool.or(Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57)), Bool.and(U32.is_ge(c, 97), U32.is_le(c, 122))), Bool.and(U32.is_ge(c, 65), U32.is_le(c, 90))), c, 95)}, Watch.safe(t)}

def Watch.cli.k(rt: K.Rt) -> String:
  match rt:
    case K.Rt{cli, _, _, _}:
      cli

def Watch.cli() -> IO(String):
  do IO<String>:
    +home : String <- S.Env.get("HOME", "/tmp")
    explicit : String <- S.Env.get("BACKPLANE_KICAD_CLI", "")
    exe : String <- S.Sys.exe_dir.io()
    rt : K.Rt <- K.Rt.resolve(explicit, exe, home ++ "/.backplane-bend")
    return Watch.cli.k(rt)

def Watch.step2glb() -> IO(String):
  do IO<String>:
    +d : String <- S.Sys.exe_dir.io()
    ok : Bool <- K.Io.is_file(d ++ "/backplane-step2glb")
    return Bool.pick(String, ok, d ++ "/backplane-step2glb", "backplane-step2glb")

# how a file becomes a GLB: as it is, from STEP, or exported from a board
def Watch.glb.cmd(+path: String, +out: String, +cli: String, +step: String) -> String & List<&2, String>:
  Bool.pick(String & List<&2, String>, Bool.or(String.ends_with(path, ".step"), Bool.or(String.ends_with(path, ".stp"), Bool.or(String.ends_with(path, ".STEP"), String.ends_with(path, ".STP")))),
    (step, [path, out]),
    (cli, ["pcb", "export", "glb", "--subst-models", "--include-tracks", "--include-pads", "--include-zones", "--include-soldermask", "--include-silkscreen", "-f", "-o", out, path]))

def Watch.glb.run(cmd: String & List<&2, String>) -> IO(P.Ran):
  (c, args) = cmd
  P.Proc.run(c, args, "/")

def Watch.glb.done(r: P.Ran, +glb: String, +key: String, +q: Chan(ShellMsg)) -> IO(Unit):
  match r:
    case P.Ran{0, _}:
      do IO<Unit>:
        bs : List<&2, U32> <- S.Files.read(glb)
        ok : Bool <- Chan.send(ShellMsg, q, Mesh3{key, G.Mesh.tris(G.Glb.parse(bs))})
        return Unit{}
    case P.Ran{_, out}:
      Watch.say(key, "3D export failed: " ++ String.take(String.trim(out), 160n), q)

def Watch.mesh.k(glb: Bool, +path: String, +key: String, +q: Chan(ShellMsg)) -> IO(Unit):
  match glb:
    case True{}:
      Watch.glb.done(P.Ran{0, ""}, path, key, q)
    case False{}:
      do IO<Unit>:
        +out : String = "/tmp/backplane-3d-" ++ String.drop(Watch.safe(key), Nat.sub(String.length(key), 120n)) ++ ".glb"
        cli : String <- Watch.cli()
        step : String <- Watch.step2glb()
        r : P.Ran <- Watch.glb.run(Watch.glb.cmd(path, out, cli, step))
        Watch.glb.done(r, out, key, q)

# a 3D model: a .glb as it is; a STEP or board converted to GLB first
def Watch.mesh(+path: String, +key: String, +q: Chan(ShellMsg)) -> IO(Unit):
  Watch.mesh.k(String.ends_with(path, ".glb"), path, key, q)

def Watch.read.k(three: Bool, +path: String, +key: String, +q: Chan(ShellMsg)) -> IO(Unit):
  match three:
    case True{}:
      Watch.mesh(path, key, q)
    case False{}:
      do IO<Unit>:
        bs : List<&2, U32> <- S.Files.read(path)
        Watch.sent(Watch.sorted(Watch.parse(Src.kind(key), bs)), key, q)

# read, parse (in parallel) and send; a half-written file sends nothing
def Watch.read(+path: String, +key: String, +q: Chan(ShellMsg)) -> IO(Unit):
  Watch.read.k(U32.is_eq(Src.kind(key), 2), path, key, q)

def Watch.stat.k(v: U32 & U32 & U32) -> U32 & U32:
  (_, sm) = v
  sm

def Watch.stat(r: Result<&1, &1, U32 & String, U32 & U32 & U32>) -> U32 & U32:
  match r:
    case Done{v}:
      Watch.stat.k(v)
    case Fail{_}:
      (0, 0)

def Watch.step.k(changed: Bool, re: Nat, +s2: U32, +m2: U32, +key: String, +path: String, +q: Chan(ShellMsg), k: U32 -> U32 -> Nat -> IO(Unit)) -> IO(Unit):
  match changed re:
    case True{} _:
      do IO<Unit>:
        Watch.read(path, key, q)
        k(s2, m2, 7n)
    case False{} 1n:
      do IO<Unit>:
        Watch.read(path, key, q)
        k(s2, m2, 0n)
    case False{} 1n+r:
      k(s2, m2, r)
    case False{} 0n:
      k(s2, m2, 0n)

def Watch.step(sm: U32 & U32, +sz: U32, +mt: U32, re: Nat, +key: String, +path: String, +q: Chan(ShellMsg), k: U32 -> U32 -> Nat -> IO(Unit)) -> IO(Unit):
  (+s2, +m2) = sm
  Watch.step.k(Bool.or(U32.is_ne(s2, sz), U32.is_ne(m2, mt)), re, s2, m2, key, path, q, k)

# every 150 ms: a changed size or mtime re-reads the file; one more read
# ~1 s after a change catches a second save within the same second (a 3D
# model re-exports only on a change: exports take seconds)
def Watch.loop(fuel: Nat, +key: String, +path: String, +sz: U32, +mt: U32, re: Nat, +q: Chan(ShellMsg)) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      do IO<Unit>:
        IO.sleep(150)
        st : Result<&1, &1, U32 & String, U32 & U32 & U32> <- H.FS.stat(path)
        Watch.step(Watch.stat(st), sz, mt, Bool.pick(Nat, U32.is_eq(Src.kind(key), 2), 0n, re), key, path, q, s2 => m2 => r2 => Watch.loop(f, key, path, s2, m2, r2, q))

def Watch.none(+key: String) -> String:
  Bool.pick(String, U32.is_eq(Src.kind(key), 1), "No schematic in this project yet", "No board in this project yet")

def Watch.go(none: Bool, once: Bool, +key: String, +path: String, +q: Chan(ShellMsg)) -> IO(Unit):
  match none once:
    case True{} _:
      Watch.say(key, Watch.none(key), q)
    case False{} True{}:
      Watch.read(path, key, q)
    case False{} False{}:
      Watch.loop(S.Fuel.forever(), key, path, 0, 0, 0n, q)

# watch a source (or, when it is watched already, read it once)
def Watch.start(once: Bool, +key: String, +q: Chan(ShellMsg)) -> IO(Unit):
  do IO<Unit>:
    +path : String <- Watch.file(key)
    Watch.go(String.is_empty(path), once, key, path, q)

def Shell.watch.go(go: Bool, +key: String, a: Shell) -> IO(Shell):
  match go a:
    case True{} Shell{n, w, d, qd, +q, i, +wa}:
      do IO<Shell>:
        IO.spawn(Unit, Watch.start(Shell.has(Aux.watched(wa), key), key, q))
        return Shell{N.Nui.asked(n, key), w, True{}, qd, q, i, Aux.add(wa, key)}
    case False{} _:
      IO.pure(Shell, a)

# when the viewer is open on a source it has not asked for, ask
def Shell.watch.k(open: Bool, +key: String, +shown: String, a: Shell) -> IO(Shell):
  Shell.watch.go(Bool.and(Bool.and(open, Bool.not(String.eq(key, shown))), Bool.not(String.ends_with(key, "||"))), key, a)

def Shell.watch(a: Shell) -> IO(Shell):
  match a:
    case Shell{+n, w, d, qd, q, i, wa}:
      Shell.watch.k(N.Nui.panel(n), N.Nui.source(n), N.Vx.shown(N.Vw.x(N.Nui.vw(n))), Shell{n, w, d, qd, q, i, wa})

def Shell.board(a: Shell, +key: String, +items: List<&2, B.Item>) -> IO(Shell):
  match a:
    case Shell{n, w, _, qd, q, i, wa}:
      do IO<Shell>:
        ms : Nat <- IO.now()
        Shell.later(Shell{N.Nui.board(n, key, items, ms), w, True{}, qd, q, i, wa})

def Shell.mesh(a: Shell, +key: String, ts: List<&2, G.Tri3>) -> IO(Shell):
  match a:
    case Shell{n, w, _, qd, q, i, wa}:
      Shell.later(Shell{N.Nui.mesh(n, key, ts), w, True{}, qd, q, i, wa})

def Shell.status(a: Shell, +key: String, +text: String) -> IO(Shell):
  match a:
    case Shell{n, w, _, qd, q, i, wa}:
      Shell.later(Shell{N.Nui.status(n, key, text), w, True{}, qd, q, i, wa})

# Viewer frames
# -------------

def Vx.kind(x: V.Vx) -> U32:
  match x:
    case V.Vx{k, _, _, _, _, _, _, _, _, _}:
      k

# the viewer's settled scene, drawn once per scene/view (the frame's base):
# a 3D model rendered into the panel, or the board/schematic's items
def Shell.base(+ww: U32, +hh: U32, +x0: U32, +ss: List<&2, V.Seen>, +v: V.View, +now: Nat, x: V.Vx) -> Image:
  match x:
    case V.Vx{2, _, ts, c, _, _, _, _, _, _}:
      MS.Mesh.render.at(ww, hh, x0, 52, (ww - x0 : U32), (hh - 52 : U32), ts, c, 526603)
    case V.Vx{+k, _, _, _, _, _, _, _, _, _}:
      R.Frame.render(ww, hh, List.reverse(&2, R.Op, D.Draw.rect(D.Clip.all(), x0, 52, (ww - x0 : U32), hh, 526603, 255)
        <> V.Ops.scene(ss, v, D.Clip{x0, 52, ww, hh}, now, now, True{}, k)), T.Th.bg())

def Shell.vw.k(redraw: Bool, vw: V.Vw, +ww: U32, +hh: U32, +x0: U32, +now: Nat) -> V.Vw:
  match redraw vw:
    case True{} V.Vw{+ss, +v, f, r, d, lx, ly, _, _, _, +vx}:
      V.Vw{ss, v, f, r, d, lx, ly, Shell.base(ww, hh, x0, ss, v, now, vx), True{}, now, vx}
    case False{} _:
      vw

# refresh the base if the scene or view changed, or fades ended since
def Shell.vw(+vw: V.Vw, +ww: U32, +hh: U32, +x0: U32, +now: Nat) -> V.Vw:
  match vw:
    case V.Vw{+ss, +v, f, r, d, lx, ly, b, +fr, +cut, vx}:
      Shell.vw.k(Bool.or(Bool.not(fr), V.Vw.late(ss, cut, now)), V.Vw{ss, v, f, r, d, lx, ly, b, fr, cut, vx}, ww, hh, x0, now)

def Shell.vw.if(open: Bool, +vw: V.Vw, +ww: U32, +hh: U32, +x0: U32, +ms: Nat) -> V.Vw:
  match open:
    case True{}:
      Shell.vw(vw, ww, hh, x0, ms)
    case False{}:
      vw

def Vx.pick(x: V.Vx) -> String:
  match x:
    case V.Vx{_, p, _, _, _, _, _, _, _, _}:
      p

# UI ops over the fading items and the picked item, over the base
def Shell.image.over(+ops: List<&2, R.Op>, vw: V.Vw, +ww: U32, +hh: U32, +x0: U32, +now: Nat) -> Image:
  match vw:
    case V.Vw{+ss, +v, _, _, _, _, _, +b, _, +cut, +vx}:
      R.Frame.over(ww, hh, List.append(&2, R.Op, ops, List.reverse(&2, R.Op,
        List.append(&2, R.Op, Bool.pick(List<&2, R.Op>, U32.is_eq(Vx.kind(vx), 2), Nil{}, V.Ops.scene(ss, v, D.Clip{x0, 52, ww, hh}, now, cut, False{}, Vx.kind(vx))),
          V.Ops.picked(ss, Vx.pick(vx), v, D.Clip{x0, 52, ww, hh})))), b)

# the frame: UI ops over the fading items over the base
def Shell.image(pa: Bool, +ops: List<&2, R.Op>, +vw: V.Vw, +ww: U32, +hh: U32, +x0: U32, +now: Nat) -> Image:
  match pa:
    case True{}:
      Shell.image.over(ops, vw, ww, hh, x0, now)
    case False{}:
      R.Frame.render(ww, hh, ops, T.Th.bg())

def Shell.paint.out(o: L.Out, +n: N.Nui, w: Window, +q: Chan(ShellMsg), +i: Chan(S.Msg), wa: Aux, +epoch: Nat, +ms: Nat) -> IO(Shell):
  match o:
    case L.Out{+ops, hs}:
      IO.bind(Window & Image, Shell, W.Win.present(w, Shell.image(N.Nui.panel(n), ops, N.Nui.vw(n), N.Nui.width(n), N.Nui.height(n), N.Nui.vx0(n), ms)),
        r => Shell.shown(r, Shell.hits(n, hs, epoch), q, i, wa, Bool.and(N.Nui.panel(n), Shell.busy(N.Nui.vw(n), ms))))

def Shell.paint.go(+n: N.Nui, w: Window, +q: Chan(ShellMsg), +i: Chan(S.Msg), +wa: Aux, +epoch: Nat, +ms: Nat) -> IO(Shell):
  Shell.paint.out(L.Lay.frame(Aux.ty(wa), n), n, w, q, i, wa, epoch, ms)

def Shell.paint.k(+n0: N.Nui, w: Window, +q: Chan(ShellMsg), +i: Chan(S.Msg), wa: Aux, +epoch: Nat, +ms: Nat) -> IO(Shell):
  match n0:
    case N.Nui{u, +ww, +hh, mx, my, sd, sc, ca, fo, pa, _, _, vw0}:
      Shell.paint.go(N.Nui{u, ww, hh, mx, my, sd, sc, ca, fo, pa, Nil{}, ms,
        Shell.vw.if(N.Nui.panel(n0), vw0, ww, hh, N.Nui.vx0(n0), ms)}, w, q, i, wa, epoch, ms)

def Shell.paint(+n: N.Nui, w: Window, +q: Chan(ShellMsg), +i: Chan(S.Msg), wa: Aux, +epoch: Nat, +ms: Nat) -> IO(Shell):
  Shell.paint.k(N.Nui.prepare(n), w, q, i, wa, epoch, ms)

# draw now if anything changed since the last frame
def Shell.frame(a: Shell) -> IO(Shell):
  match a:
    case Shell{+n, w, True{}, _, q, i, wa}:
      do IO<Shell>:
        t : U32 <- H.Clock.epoch()
        ms : Nat <- IO.now()
        Shell.paint(n, w, q, i, wa, U32.to_nat(t), ms)
    case Shell{n, w, False{}, _, q, i, wa}:
      IO.pure(Shell, Shell{n, w, False{}, False{}, q, i, wa})

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
    case Board{key, items}:
      Shell.board(a, key, items)
    case Mesh3{key, ts}:
      Shell.mesh(a, key, ts)
    case Status{key, text}:
      Shell.status(a, key, text)

def Shell.got(m: Maybe<&1, ShellMsg>, a: Shell, k: Shell -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{msg}:
      IO.bind(Shell, Unit, IO.bind(Shell, Shell, Shell.handle(a, msg), Shell.watch), k)
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
    ty : L.Ty <- L.Ty.load()
    a : Shell <- Shell.later(Shell{N.Nui.init(U.Ui.init(U32.to_nat(t)), 1400, 900), pw, True{}, False{}, q, inbox, Aux{Nil{}, ty}})
    Shell.loop(S.Fuel.forever(), a)

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
    +exe : String <- S.Sys.exe_dir.io()
    args : List<String> <- IO.args()
    b : S.Boot <- S.Main.prepare(user, exe)
    S.Main.boot(S.Main.config(user, exe, args, b), False{}, i => Shell.run(i))
