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
import ./link.bend as LK
import ./imgfx.bend as IF
import ../core/images.bend as IM
import ../gfx/bitmap.bend as BM
import ../gfx/tiles.bend as TI
import ../core/lightbox.bend as LBX

# `backplane`: the hub, the web server (for other devices), and the native
# window as client 0. Window events and hub messages meet in one queue; a
# frame is drawn at most every 12 ms and only when something changed.

type ShellMsg is Data:
  FromWin{words: List<&2, U32>}
  FromHub{tag: String, text: String}
  Frame{}
  Gone{tag: String}
  Retry{tag: String}
  Board{key: String, items: List<&2, B.Item>}
  Mesh3{key: String, tris: List<&2, G.Tri3>}
  Status{key: String, text: String}
  Shot{key: String, bmp: BM.Bitmap}
  PicOk{tag: String, path: String, w: U32, h: U32, rgb: List<&2, U32>}
  PicErr{tag: String, path: String, why: String}
  Blink{}

# which hub the window talks to: its own (url "") or another machine's
# through a link; each connection gets its own tag so messages from one
# already left are dropped
type Tie is Data:
  Tie{home: Chan(S.Msg), url: String, tag: String, n: Nat, pics: Map<&2, BM.Bitmap>, asked: Map<&2, Bool>}

# what one frame keeps for the next: its tiles and the timeline's memo
type Kept is Data:
  Kept{frames: TI.Frames, memo: L.TLMemo}

# the boards being watched and the fonts
type Aux is Data:
  Aux{watched: List<&2, String>, ty: L.Ty, tie: Tie, kept: Kept}

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

def Fwd.got(m: Maybe<&1, S.Wire>, +q: Chan(ShellMsg), +tag: String, k: Unit -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{S.WText{t}}:
      do IO<Unit>:
        ok : Bool <- Chan.send(ShellMsg, q, FromHub{tag, t})
        k(Unit{})
    case Some{_}:
      k(Unit{})
    case None{}:
      do IO<Unit>:
        ok : Bool <- Chan.send(ShellMsg, q, Gone{tag})
        return Unit{}

# a hub's messages for client 0, tagged with the connection
def Fwd.loop(fuel: Nat, +out: Chan(S.Wire), +q: Chan(ShellMsg), +tag: String) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      IO.bind(Maybe<&1, S.Wire>, Unit, Chan.recv(S.Wire, out), m => Fwd.got(m, q, tag, u => Fwd.loop(f, out, q, tag)))

# the next frame after wait ms (0: at once, behind what is queued)
def Timer.once(+q: Chan(ShellMsg), +wait: Nat) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(U32.from_nat(wait))
    ok : Bool <- Chan.send(ShellMsg, q, Frame{})
    return Unit{}

def Frame.gap() -> Nat:
  12n

# frames keep Frame.gap() apart: a change after a quiet spell draws at once
# (a key shows in the next frame, not 12 ms later); changes that come
# faster are drawn together once the gap has passed
def Frame.wait(+last: Nat, +now: Nat) -> Nat:
  Nat.sub(Frame.gap(), Nat.sub(now, last))

def Frame.soon(+q: Chan(ShellMsg), +wait: Nat) -> IO(Unit):
  Bool.pick(IO(Unit), Nat.is_eq(wait, 0n), IO.bind(Bool, Unit, Chan.send(ShellMsg, q, Frame{}), _ => IO.pure(Unit, Unit{})), IO.spawn(Unit, Timer.once(q, wait)))

# the caret's next toggle
def Timer.blink(+q: Chan(ShellMsg), wait: Nat) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(U32.from_nat(wait))
    ok : Bool <- Chan.send(ShellMsg, q, Blink{})
    return Unit{}

# Drawing
# -------

def Shell.later(a: Shell) -> IO(Shell):
  match a:
    case Shell{n, w, _, True{}, +q, i, wa}:
      IO.pure(Shell, Shell{n, w, True{}, True{}, q, i, wa})
    case Shell{+n, w, _, False{}, +q, i, wa}:
      do IO<Shell>:
        now : Nat <- IO.now()
        Frame.soon(q, Frame.wait(N.Nui.ms_of(n), now))
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

# a focused field asks for one frame at its caret's next toggle, unless
# one is already due
def Shell.blink.k(go: Bool, +n: N.Nui, +q: Chan(ShellMsg), +wait: Nat, +ms: Nat) -> IO(N.Nui):
  match go:
    case True{}:
      do IO<N.Nui>:
        IO.spawn(Unit, Timer.blink(q, wait))
        return N.Nui.with_ui(n, U.Ui.info_set(N.Nui.ui(n), "caret.due", Nat.show(Nat.add(ms, wait))))
    case False{}:
      IO.pure(N.Nui, n)

def Shell.blink(+n: N.Nui, +q: Chan(ShellMsg), +ms: Nat) -> IO(N.Nui):
  Shell.blink.k(Bool.and(Nat.is_gt(N.Blink.wait(n, ms), 0n), Nat.is_le(Maybe.default(&2, Nat, Nat.read(U.Ui.info(N.Nui.ui(n), "caret.due")), 0n), ms)),
    n, q, N.Blink.wait(n, ms), ms)

def Shell.busy(vw: V.Vw, +now: Nat) -> Bool:
  match vw:
    case V.Vw{ss, _, _, _, _, _, _, _, _, _, vx}:
      V.Fade.busy(ss, now)

# Images in threads
# -----------------
# The layout marks each image a reply names with "img" hit regions (its
# rectangle once its size is known). New ones are decoded off the loop
# (fetched from the hub first when it is another machine's), kept per
# connection, noted in the client info ("img:<path>") so the layout gives
# them room, and drawn into the frame's base under the UI.

# the largest an image is drawn (the timeline's width, a screen's third)
def Pics.maxw() -> U32:
  760

def Pics.maxh() -> U32:
  360

def Pics.size(+w: U32, +h: U32) -> String:
  U32.show(w) ++ "x" ++ U32.show(h)

def Tie.pics(t: Tie) -> Map<&2, BM.Bitmap>:
  match t:
    case Tie{_, _, _, _, ps, _}:
      ps

def Pics.sent.ok(got: U32 & U32 & List<&2, U32>, +q: Chan(ShellMsg), +tag: String, +path: String) -> IO(Unit):
  (w, rest) = got
  (h, rgb) = rest
  do IO<Unit>:
    ok : Bool <- Chan.send(ShellMsg, q, PicOk{tag, path, w, h, rgb})
    return Unit{}

def Pics.sent.err(e: U32 & String, +q: Chan(ShellMsg), +tag: String, +path: String) -> IO(Unit):
  (_, why) = e
  do IO<Unit>:
    ok : Bool <- Chan.send(ShellMsg, q, PicErr{tag, path, why})
    return Unit{}

def Pics.sent(r: Result<&1, &1, U32 & String, U32 & U32 & List<&2, U32>>, +q: Chan(ShellMsg), +tag: String, +path: String) -> IO(Unit):
  match r:
    case Done{got}:
      Pics.sent.ok(got, q, tag, path)
    case Fail{e}:
      Pics.sent.err(e, q, tag, path)

# "full:<path>": the image for the lightbox, decoded as large as a screen
def Pics.full(+key: String) -> Bool:
  String.starts_with(key, "full:")

def Pics.src(+key: String) -> String:
  Bool.pick(String, Pics.full(key), String.drop(key, 5n), key)

def Pics.maxw.of(+key: String) -> U32:
  Bool.pick(U32, Pics.full(key), 1600, Pics.maxw())

def Pics.maxh.of(+key: String) -> U32:
  Bool.pick(U32, Pics.full(key), 1000, Pics.maxh())

def Pics.decode(+file: String, +q: Chan(ShellMsg), +tag: String, +path: String) -> IO(Unit):
  IO.bind(Result<&1, &1, U32 & String, U32 & U32 & List<&2, U32>>, Unit, IF.Imgfx.decode(file, Pics.maxw.of(path), Pics.maxh.of(path)), r => Pics.sent(r, q, tag, path))

def Pics.fetched(r: P.Ran, +q: Chan(ShellMsg), +tag: String, +path: String) -> IO(Unit):
  match r:
    case P.Ran{0, +out}:
      do IO<Unit>:
        Pics.decode(String.trim(out), q, tag, path)
        r2 : P.Ran <- P.Proc.run("rm", ["-f", String.trim(out)], "/")
        return Unit{}
    case P.Ran{_, _}:
      do IO<Unit>:
        ok : Bool <- Chan.send(ShellMsg, q, PicErr{tag, path, "that machine did not send it"})
        return Unit{}

# an image on this machine is read here; another machine's hub sends it
def Pics.load(local: Bool, +path: String, +url: String, +q: Chan(ShellMsg), +tag: String) -> IO(Unit):
  match local:
    case True{}:
      IO.bind(String, Unit, S.Env.get("HOME", ""), home => Pics.decode(Bool.pick(String, String.starts_with(Pics.src(path), "~/"), home ++ String.drop(Pics.src(path), 1n), Pics.src(path)), q, tag, path))
    case False{}:
      IO.bind(P.Ran, Unit, P.Proc.run("sh", ["-c", "f=$(mktemp) && curl -sf -m 30 -o \"$f\" \"$1\" && echo \"$f\"", "sh", url ++ IM.Img.url(Pics.src(path))], "/"),
        r => Pics.fetched(r, q, tag, path))

def Pics.new.k(fresh: Bool, +v: String, rest: List<&2, String>) -> List<&2, String>:
  match fresh:
    case True{}:
      v <> rest
    case False{}:
      rest

def Pics.new(hs: List<&2, N.Hit>, +asked: Map<&2, Bool>) -> List<&2, String>:
  match hs:
    case Nil{}:
      Nil{}
    case N.Hit{_, _, _, _, +a, +v} <> t:
      Pics.new.k(Bool.and(String.eq(a, "img"), Bool.not(U.Flag.get(asked, v))), v, Pics.new(t, asked))

def Pics.mark(ps: List<&2, String>, asked: Map<&2, Bool>) -> Map<&2, Bool>:
  match ps:
    case Nil{}:
      asked
    case p <> t:
      Pics.mark(t, Map.set(&2, Bool, asked, p, True{}))

def Pics.spawn(ps: List<&2, String>, +url: String, +q: Chan(ShellMsg), +tag: String) -> IO(Unit):
  match ps:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case +p <> t:
      do IO<Unit>:
        IO.spawn(Unit, Pics.load(String.is_empty(url), p, url, q, tag))
        Pics.spawn(t, url, q, tag)

def Pics.keep(m: Maybe<&2, BM.Bitmap>, ps: Map<&2, BM.Bitmap>, +path: String) -> Map<&2, BM.Bitmap>:
  match m:
    case Some{b}:
      Map.set(&2, BM.Bitmap, ps, path, b)
    case None{}:
      ps

def Pics.store(a: Shell, +path: String, +note: String, m: Maybe<&2, BM.Bitmap>) -> IO(Shell):
  match a:
    case Shell{+n, w, _, qd, q, i, Aux{ws, ty, Tie{home, url, tag, k, ps, ak}, fr}}:
      Shell.later(Shell{N.Nui.with_ui(n, U.Ui.info_set(N.Nui.ui(n), "img:" ++ path, note)), w, True{}, qd, q, i, Aux{ws, ty, Tie{home, url, tag, k, Pics.keep(m, ps, path), ak}, fr}})

# an image loaded (or failed) for this connection: keep it and redraw
def Pics.got(current: Bool, a: Shell, +path: String, +note: String, m: Maybe<&2, BM.Bitmap>) -> IO(Shell):
  match current:
    case True{}:
      Pics.store(a, path, note, m)
    case False{}:
      IO.pure(Shell, a)

def Pics.had(xs: List<&2, String>, +x: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case +h <> t:
      Bool.or(String.eq(h, x), Pics.had(t, x))

def Pics.uniq(ps: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match ps:
    case Nil{}:
      List.reverse(&2, String, acc)
    case +p <> t:
      Pics.uniq(t, Bool.pick(List<&2, String>, Pics.had(acc, p), acc, p <> acc))

# images the frame shows that were never asked for start loading
def Pics.ask(+hs: List<&2, N.Hit>, wa: Aux, +q: Chan(ShellMsg)) -> IO(Aux):
  match wa:
    case Aux{ws, ty, Tie{home, +url, +tag, n, ps, +ak}, fr}:
      +fresh = Pics.uniq(Pics.new(hs, ak), Nil{})
      IO.bind(Unit, Aux, Pics.spawn(fresh, url, q, tag), u => IO.pure(Aux, Aux{ws, ty, Tie{home, url, tag, n, ps, Pics.mark(fresh, ak)}, fr}))

# no caret blinks under the lightbox (nothing else asks for frames then)
def Lbv.blink(on: Bool, +n: N.Nui, +q: Chan(ShellMsg), +ms: Nat) -> IO(N.Nui):
  match on:
    case True{}:
      IO.pure(N.Nui, n)
    case False{}:
      Shell.blink(n, q, ms)

# the lightbox's picture, asked for as large as a screen while it is up
def Lbv.want(on: Bool, +path: String) -> List<&2, N.Hit>:
  match on:
    case True{}:
      [N.Hit{0, 0, 0, 0, "img", "full:" ++ path}]
    case False{}:
      Nil{}

def Shell.shown(r: Window & Image, +n: N.Nui, +q: Chan(ShellMsg), +i: Chan(S.Msg), wa: Aux, anim: Bool, +ms: Nat) -> IO(Shell):
  (w, img) = r
  do IO<Shell>:
    Unit <- IO.pure(Unit, Image.drop!(img))
    +n2 : N.Nui <- Lbv.blink(N.Lbx.on(n), n, q, ms)
    wa2 : Aux <- Pics.ask(List.append(&2, N.Hit, Lbv.want(N.Lbx.on(n2), N.Lbx.path(n2)), N.Nui.hits(n2)), wa, q)
    Shell.again(anim, Shell{n2, w, False{}, False{}, q, i, wa2})

def Pics.found(r: Map<&2, BM.Bitmap> & BM.Bitmap) -> BM.Bitmap:
  (_, b) = r
  b

# a loaded image (none yet: an empty one, width 0)
def Pics.get(pics: Map<&2, BM.Bitmap>, +k: String) -> BM.Bitmap:
  Pics.found(Map.get(BM.Bitmap, BM.Bitmap{0, 0, 0n, Pix{0}, 0, 0, 0, 0}, pics, k))

def Pics.place(b: BM.Bitmap, +x: U32, +y: U32, +w: U32, +h: U32, +ww: U32, +hh: U32, base: Image) -> Image:
  match b:
    case BM.Bitmap{0, _, _, _, _, _, _, _}:
      base
    case BM.Bitmap{bw, bh, d, t, _, _, _, _}:
      BM.Bitmap.over(ww, hh, BM.Bitmap.move(BM.Bitmap{bw, bh, d, t, 0, 0, 0, 0}, x, y, w, h), base)

def Pics.over.k(draw: Bool, +x: U32, +y: U32, +w: U32, +h: U32, +v: String, +pics: Map<&2, BM.Bitmap>, +ww: U32, +hh: U32, base: Image) -> Image:
  match draw:
    case True{}:
      Pics.place(Pics.get(pics, v), x, y, w, h, ww, hh, base)
    case False{}:
      base

# each image once, at its rectangle, under the UI
def Pics.over(hs: List<&2, N.Hit>, +pics: Map<&2, BM.Bitmap>, +done: List<&2, String>, +ww: U32, +hh: U32, base: Image) -> Image:
  match hs:
    case Nil{}:
      base
    case N.Hit{+x0, +y0, +x1, +y1, +a, +v} <> t:
      Pics.over(t, pics, v <> done, ww, hh,
        Pics.over.k(Bool.and(Bool.and(String.eq(a, "img"), U32.is_gt((x1 - x0 : U32), 1)), Bool.not(Pics.had(done, v))), x0, y0, (x1 - x0 : U32), (y1 - y0 : U32), v, pics, ww, hh, base))

# Machines
# --------

def Tie.tag(t: Tie) -> String:
  match t:
    case Tie{_, _, g, _, _, _}:
      g

def Tie.url(t: Tie) -> String:
  match t:
    case Tie{_, u, _, _, _, _}:
      u

# the hub to join: this machine's own, or a link to another
def Shell.hub(local: Bool, +home: Chan(S.Msg), +url: String) -> IO(Chan(S.Msg)):
  match local:
    case True{}:
      IO.pure(Chan(S.Msg), home)
    case False{}:
      LK.Link.start(url)

def Shell.joined(+i2: Chan(S.Msg), +q: Chan(ShellMsg), +tag: String) -> IO(Unit):
  do IO<Unit>:
    +out : Chan(S.Wire) <- Chan.new(S.Wire, 8192)
    ok : Bool <- Chan.send(S.Msg, i2, S.Join{0, out, 0n, ""})
    IO.spawn(Unit, Fwd.loop(S.Fuel.forever(), out, q, tag))

def Shell.connect.k(t: Tie, a: Shell, +url: String) -> IO(Shell):
  match t a:
    case Tie{+home, _, _, +n, _, _} Shell{nu, w, d, qd, +q, +i, Aux{ws, ty, _, fr}}:
      do IO<Shell>:
        ok : Bool <- Chan.send(S.Msg, i, S.Leave{0})
        +tag : String = url ++ "#" ++ Nat.show(n)
        +i2 : Chan(S.Msg) <- Shell.hub(String.is_empty(url), home, url)
        Shell.joined(i2, q, tag)
        return Shell{nu, w, True{}, qd, q, i2, Aux{ws, ty, Tie{home, url, tag, 1n+n, Map.new(&2, BM.Bitmap), Map.new(&2, Bool)}, fr}}

def Shell.retry.later(+q: Chan(ShellMsg), +tag: String) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(3000)
    ok : Bool <- Chan.send(ShellMsg, q, Retry{tag})
    return Unit{}

# the caret toggled: the next frame redraws it
def Shell.blinked(a: Shell) -> Shell:
  match a:
    case Shell{n, w, _, qd, q, i, wa}:
      Shell{n, w, True{}, qd, q, i, wa}

def Shell.dirty(a: Shell) -> IO(Shell):
  match a:
    case Shell{n, w, True{}, qd, q, i, wa}:
      Shell.later(Shell{n, w, True{}, qd, q, i, wa})
    case _:
      IO.pure(Shell, a)

def Shell.recv(a: Shell, +text: String) -> IO(Shell):
  match a:
    case Shell{n, w, _, qd, q, i, wa}:
      Shell.later(Shell{N.Nui.recv(n, Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{})), w, True{}, qd, q, i, wa})

def Shell.from(current: Bool, a: Shell, +t: String) -> IO(Shell):
  match current:
    case True{}:
      Shell.recv(a, t)
    case False{}:
      IO.pure(Shell, a)

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
    case Aux{_, t, _, _}:
      t

def Aux.watched(a: Aux) -> List<&2, String>:
  match a:
    case Aux{ws, _, _, _}:
      ws

def Aux.add(a: Aux, r: String) -> Aux:
  match a:
    case Aux{ws, t, ti, fr}:
      Aux{r <> ws, t, ti, fr}

def Aux.tie(a: Aux) -> Tie:
  match a:
    case Aux{_, _, ti, _}:
      ti

# talk to the hub at url ("" is this machine's): leave the one now joined,
# join the other; its log replaces what the window shows
def Shell.connect(a: Shell, +url: String) -> IO(Shell):
  match a:
    case Shell{n, w, d, qd, q, i, Aux{ws, ty, +ti, fr}}:
      Shell.connect.k(ti, Shell{n, w, d, qd, q, i, Aux{ws, ty, ti, fr}}, url)

# Commands
# --------

# a link opens in the system's browser, detached (BACKPLANE_OPEN names
# another opener); the address goes as an argument, never as shell text
def Shell.open(+url: String) -> IO(Unit):
  IO.bind(P.Ran, Unit, P.Proc.run("sh", ["-c", "${BACKPLANE_OPEN:-xdg-open} \"$1\" >/dev/null 2>&1 &", "sh", url], "/"), r => IO.pure(Unit, Unit{}))

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
    case _ N.NConnect{url}:
      Shell.connect(a, url)
    case Shell{n, w, d, qd, q, i, wa} N.NOpen{url}:
      do IO<Shell>:
        IO.spawn(Unit, Shell.open(url))
        return Shell{n, w, d, qd, q, i, wa}

# a connection closed: this machine's own hub means the app is ending;
# another machine's is tried again in a moment; an old one is let go
def Shell.gone(current: Bool, local: Bool, a: Shell, +tag: String) -> IO(Shell):
  match current local a:
    case True{} True{} _:
      IO.die(Shell, 0, "")
    case True{} False{} Shell{n, w, d, qd, +q, i, wa}:
      do IO<Shell>:
        IO.spawn(Unit, Shell.retry.later(q, tag))
        return Shell{n, w, d, qd, q, i, wa}
    case False{} _ _:
      IO.pure(Shell, a)

def Shell.retry(current: Bool, a: Shell, +url: String) -> IO(Shell):
  match current:
    case True{}:
      Shell.connect(a, url)
    case False{}:
      IO.pure(Shell, a)

# messages that belong to one connection: only the current one's count
def Shell.tagged.k(m: ShellMsg, +ti: Tie, a: Shell) -> IO(Shell):
  match m:
    case FromHub{tag, t}:
      Shell.from(String.eq(tag, Tie.tag(ti)), a, t)
    case Gone{tag}:
      Shell.gone(String.eq(tag, Tie.tag(ti)), String.is_empty(Tie.url(ti)), a, Tie.tag(ti))
    case Retry{tag}:
      Shell.retry(String.eq(tag, Tie.tag(ti)), a, Tie.url(ti))
    case PicOk{tag, +path, +w, +h, rgb}:
      Pics.got(String.eq(tag, Tie.tag(ti)), a, path, Pics.size(w, h), Some{BM.Bitmap.image(w, h, rgb, 0, 0, w, h)})
    case PicErr{tag, +path, why}:
      Pics.got(String.eq(tag, Tie.tag(ti)), a, path, "err:" ++ why, None{})
    case _:
      IO.pure(Shell, a)

def Shell.tagged(a: Shell, m: ShellMsg) -> IO(Shell):
  match a:
    case Shell{n, w, d, qd, q, i, Aux{ws, ty, +ti, fr}}:
      Shell.tagged.k(m, ti, Shell{n, w, d, qd, q, i, Aux{ws, ty, ti, fr}})

def Shell.cmds(cs: List<&2, N.NCmd>, a: Shell) -> IO(Shell):
  match cs:
    case Nil{}:
      IO.pure(Shell, a)
    case c <> t:
      IO.bind(Shell, Shell, Shell.cmd(a, c), a2 => Shell.cmds(t, a2))

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

def Shell.dropped(r: Window & String, +n: N.Nui, d: Bool, qd: Bool, +q: Chan(ShellMsg), +i: Chan(S.Msg), wa: Aux) -> IO(Shell):
  (w, text) = r
  Shell.step(Shell{n, w, d, qd, q, i, wa}, N.Nui.drop(n, text))

def Shell.event(a: Shell, e: W.WinEv) -> IO(Shell):
  match a e:
    case Shell{n, w, d, qd, q, i, wa} W.WPaste{_}:
      IO.bind(Window & String, Shell, W.Win.pasted(w), r => Shell.pasted(r, n, d, qd, q, i, wa))
    case Shell{n, w, d, qd, q, i, wa} W.WDrop{_}:
      IO.bind(Window & String, Shell, W.Win.dropped(w), r => Shell.dropped(r, n, d, qd, q, i, wa))
    case Shell{+n, w, d, qd, q, i, wa} _:
      Shell.step(Shell{n, w, d, qd, q, i, wa}, N.Nui.event.lb(N.Lbx.on(n), n, e))

def Shell.events(es: List<&2, W.WinEv>, a: Shell) -> IO(Shell):
  match es:
    case Nil{}:
      IO.pure(Shell, a)
    case e <> t:
      IO.bind(Shell, Shell, Shell.event(a, e), a2 => Shell.events(t, a2))

def Aux.with_tie(a: Aux, ti: Tie) -> Aux:
  match a:
    case Aux{ws, t, _, fr}:
      Aux{ws, t, ti, fr}

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

def Watch.seq(h: BM.BmHead) -> U32:
  match h:
    case BM.BmHead{_, _, s}:
      s

# The agents' browser: its frame file starts with a 16-byte header whose
# seq grows with each frame; poll the header, load the pixels on a change

def Watch.head.k(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(U32):
  (f, res) = r
  do IO<U32>:
    File.close(f)
    return Watch.seq(BM.Bitmap.head(Result.default(&1, &1, U32 & String, List<&2, U32>, res, Nil{})))

def Watch.head.o(r: Result<&1, &1, U32 & String, File>) -> IO(U32):
  match r:
    case Done{f}:
      IO.bind(File & Result<&1, &1, U32 & String, List<&2, U32>>, U32, File.read_bytes(f, 16), Watch.head.k)
    case Fail{_}:
      IO.pure(U32, 0)

def Watch.head(+path: String) -> IO(U32):
  IO.bind(Result<&1, &1, U32 & String, File>, U32, File.open(path, "r"), Watch.head.o)

def Watch.w(h: BM.BmHead) -> U32:
  match h:
    case BM.BmHead{w, _, _}:
      w

def Watch.h(h: BM.BmHead) -> U32:
  match h:
    case BM.BmHead{_, h2, _}:
      h2

def Watch.shot(+path: String, +key: String, +q: Chan(ShellMsg)) -> IO(Unit):
  do IO<Unit>:
    +bs : List<&2, U32> <- S.Files.read(path)
    ok : Bool <- Chan.send(ShellMsg, q, Shot{key, BM.Bitmap.load(bs, 0, 0, Watch.w(BM.Bitmap.head(bs)), Watch.h(BM.Bitmap.head(bs)))})
    return Unit{}

def Watch.shots.k(changed: Bool, +seq: U32, +key: String, +path: String, +q: Chan(ShellMsg), k: U32 -> IO(Unit)) -> IO(Unit):
  match changed:
    case True{}:
      do IO<Unit>:
        Watch.shot(path, key, q)
        k(seq)
    case False{}:
      k(seq)

def Watch.shots(fuel: Nat, +key: String, +path: String, +last: U32, +q: Chan(ShellMsg)) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      do IO<Unit>:
        IO.sleep(120)
        +seq : U32 <- Watch.head(path)
        Watch.shots.k(Bool.and(U32.is_ne(seq, last), U32.is_ne(seq, 0)), seq, key, path, q, s2 => Watch.shots(f, key, path, s2, q))

def Watch.none(+key: String) -> String:
  Bool.pick(String, U32.is_eq(Src.kind(key), 1), "No schematic in this project yet", "No board in this project yet")

def Watch.go(none: Bool, once: Bool, +key: String, +path: String, +q: Chan(ShellMsg)) -> IO(Unit):
  match none once:
    case True{} _:
      Watch.say(key, Watch.none(key), q)
    case False{} True{}:
      Bool.pick(IO(Unit), U32.is_eq(Src.kind(key), 3), Watch.shot(path, key, q), Watch.read(path, key, q))
    case False{} False{}:
      Bool.pick(IO(Unit), U32.is_eq(Src.kind(key), 3), Watch.shots(S.Fuel.forever(), key, path, 0, q), Watch.loop(S.Fuel.forever(), key, path, 0, 0, 0n, q))

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

def Shell.shot(a: Shell, +key: String, b: BM.Bitmap) -> IO(Shell):
  match a:
    case Shell{n, w, _, qd, q, i, wa}:
      Shell.later(Shell{N.Nui.shot(n, key, b), w, True{}, qd, q, i, wa})

def Shell.status(a: Shell, +key: String, +text: String) -> IO(Shell):
  match a:
    case Shell{n, w, _, qd, q, i, wa}:
      Shell.later(Shell{N.Nui.status(n, key, text), w, True{}, qd, q, i, wa})

# Viewer frames
# -------------

def Vx.kind(x: V.Vx) -> U32:
  match x:
    case V.Vx{k, _, _, _, _, _, _, _, _, _, bm}:
      k

# the browser's frame, scaled down to fit the panel and centred
def Shell.shot.base(+ww: U32, +hh: U32, +x0: U32, b: BM.Bitmap) -> Image:
  match b:
    case BM.Bitmap{+w, +h, d, t, _, _, _, _}:
      +pw = {(ww - x0 : U32) : U32}
      +ph = {(hh - 52 : U32) : U32}
      +sc = {F32.min(1.0, F32.min(F32.div(U32.to_f32(pw), F32.max(U32.to_f32(w), 1.0)), F32.div(U32.to_f32(ph), F32.max(U32.to_f32(h), 1.0)))) : F32}
      +fw = {D.Draw.floor(F32.mul(U32.to_f32(w), sc)) : U32}
      +fh = {D.Draw.floor(F32.mul(U32.to_f32(h), sc)) : U32}
      BM.Bitmap.over(ww, hh, BM.Bitmap.move(BM.Bitmap{w, h, d, t, 0, 0, 0, 0}, (x0 + U32.shr((pw - fw : U32)) : U32), (52 + U32.shr((ph - fh : U32)) : U32), fw, fh),
        R.Frame.render(ww, hh, [D.Draw.rect(D.Clip.all(), x0, 52, pw, ph, 526603, 255)], T.Th.bg()))

# the viewer's settled scene, drawn once per scene/view (the frame's base):
# a 3D model rendered into the panel, or the board/schematic's items
def Shell.base(+ww: U32, +hh: U32, +x0: U32, +ss: List<&2, V.Seen>, +v: V.View, +now: Nat, x: V.Vx) -> Image:
  match x:
    case V.Vx{2, _, ts, c, _, _, _, _, _, _, bm}:
      MS.Mesh.render.at(ww, hh, x0, 52, (ww - x0 : U32), (hh - 52 : U32), ts, c, 526603)
    case V.Vx{3, _, _, _, _, _, _, _, _, _, bm}:
      Shell.shot.base(ww, hh, x0, bm)
    case V.Vx{+k, _, _, _, _, _, _, _, _, _, bm}:
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
    case V.Vx{_, p, _, _, _, _, _, _, _, _, bm}:
      p

# UI ops over the fading items and the picked item, over the base; tiles
# the last frame drew the same way are kept (TI.Frame.again)
def Shell.image.over(+ops: List<&2, R.Op>, vw: V.Vw, +ww: U32, +hh: U32, +x0: U32, +now: Nat, +hs: List<&2, N.Hit>, +pics: Map<&2, BM.Bitmap>, prev: TI.Frames) -> TI.Tiles:
  match vw:
    case V.Vw{+ss, +v, _, _, _, _, _, +b, _, +cut, +vx}:
      TI.Frame.again(ww, hh, List.append(&2, R.Op, ops, List.reverse(&2, R.Op,
        List.append(&2, R.Op, Bool.pick(List<&2, R.Op>, U32.is_eq(Vx.kind(vx), 2), Nil{}, V.Ops.scene(ss, v, D.Clip{x0, 52, ww, hh}, now, cut, False{}, Vx.kind(vx))),
          V.Ops.picked(ss, Vx.pick(vx), v, D.Clip{x0, 52, ww, hh})))),
        Pics.over(hs, pics, Nil{}, ww, hh, R.Frame.over(ww, hh, [D.Draw.rect(D.Clip.all(), 264, 0, (x0 - 264 : U32), hh, T.Th.bg(), 255)], b)), prev)

# the frame: UI ops over the fading items over the base
def Shell.image(pa: Bool, +ops: List<&2, R.Op>, +vw: V.Vw, +ww: U32, +hh: U32, +x0: U32, +now: Nat, +hs: List<&2, N.Hit>, +pics: Map<&2, BM.Bitmap>, prev: TI.Frames) -> TI.Tiles:
  match pa:
    case True{}:
      Shell.image.over(ops, vw, ww, hh, x0, now, hs, pics, prev)
    case False{}:
      TI.Frame.again(ww, hh, ops, Pics.over(hs, pics, Nil{}, ww, hh, Pix{T.Th.bg()}), prev)

def Aux.frames(a: Aux) -> TI.Frames:
  match a:
    case Aux{_, _, _, Kept{f, _}}:
      f

def Aux.memo(a: Aux) -> L.TLMemo:
  match a:
    case Aux{_, _, _, Kept{_, m}}:
      m

def Aux.with_frames(a: Aux, f: TI.Frames) -> Aux:
  match a:
    case Aux{ws, ty, ti, Kept{_, m}}:
      Aux{ws, ty, ti, Kept{f, m}}

def Aux.with_memo(a: Aux, m: L.TLMemo) -> Aux:
  match a:
    case Aux{ws, ty, ti, Kept{f, _}}:
      Aux{ws, ty, ti, Kept{f, m}}

# frames go on while a fade, a hover ease or a lightbox ease runs
def Shell.anim(+n: N.Nui, +ms: Nat) -> Bool:
  Bool.or(Bool.or(Bool.and(N.Nui.panel(n), Shell.busy(N.Nui.vw(n), ms)), N.Hover.busy(n, ms)), N.Lbx.busy(n, ms))

# present the frame's tiles and keep them for the next frame
def Shell.present(+tiles: TI.Tiles, o: L.Out, +n: N.Nui, w: Window, +q: Chan(ShellMsg), +i: Chan(S.Msg), +wa: Aux, +epoch: Nat, +ms: Nat) -> IO(Shell):
  match o:
    case L.Out{_, +hs}:
      IO.bind(Window & Image, Shell, W.Win.present(w, TI.Tiles.image(tiles)),
        r => Shell.shown(r, Shell.hits(n, hs, epoch), q, i, Aux.with_frames(wa, TI.FSome{N.Nui.width(n), N.Nui.height(n), tiles}), Shell.anim(n, ms), ms))

# The lightbox (nui.bend's Lbx, core/lightbox.bend's Lb): the picture
# alone on a dark window, zoomed and panned, its full decode once there
# (else the thread's copy), and the close square on top
def Lbv.bg() -> U32:
  1052688

def Lbv.pick(full: BM.Bitmap, +thumb: BM.Bitmap) -> BM.Bitmap:
  match full:
    case BM.Bitmap{0, _, _, _, _, _, _, _}:
      thumb
    case BM.Bitmap{w, h, d, t, x0, y0, fw, fh}:
      BM.Bitmap{w, h, d, t, x0, y0, fw, fh}

def Lbv.pic(b: BM.Bitmap, +x: LBX.LbAx, +y: LBX.LbAx, +ww: U32, +hh: U32) -> Image:
  match b:
    case BM.Bitmap{0, _, _, _, _, _, _, _}:
      Pix{Lbv.bg()}
    case BM.Bitmap{bw, bh, d, t, x0, y0, fw, fh}:
      BM.Bitmap.view(ww, hh, BM.Bitmap{bw, bh, d, t, x0, y0, fw, fh},
        U32.from_nat(LBX.LbAx.at(x)), U32.from_nat(LBX.LbAx.at(y)), U32.from_nat(LBX.LbAx.d(x)), U32.from_nat(LBX.LbAx.d(y)),
        U32.from_nat(LBX.LbAx.s(x)), U32.from_nat(LBX.LbAx.s(y)), U32.from_nat(LBX.LbAx.len(x, U32.to_nat(ww))), U32.from_nat(LBX.LbAx.len(y, U32.to_nat(hh))), Pix{Lbv.bg()})

# the close square (LBX.Lb.close_hit's): a frame with an x in it (ops
# topmost first, as R.Frame.over takes them)
def Lbv.close(+ww: U32) -> List<&2, R.Op>:
  +x = U32.from_nat(LBX.Lb.close_x(U32.to_nat(ww)))
  List.append(&2, R.Op, [D.Draw.seg(D.Clip.all(), U32.to_f32((x + 12 : U32)), 24.0, U32.to_f32((x + 24 : U32)), 36.0, 1.5, T.Th.text(), 255),
      D.Draw.seg(D.Clip.all(), U32.to_f32((x + 24 : U32)), 24.0, U32.to_f32((x + 12 : U32)), 36.0, 1.5, T.Th.text(), 255)],
    List.append(&2, R.Op, D.Draw.frame(D.Clip.all(), x, 12, 36, 36, T.Th.line()), [D.Draw.rect(D.Clip.all(), x, 12, 36, 36, T.Th.panel(), 255)]))

def Lbv.draw(+n: N.Nui, +pics: Map<&2, BM.Bitmap>, +ms: Nat) -> Image:
  R.Frame.over(N.Nui.width(n), N.Nui.height(n), Lbv.close(N.Nui.width(n)),
    Lbv.pic(Lbv.pick(Pics.get(pics, "full:" ++ N.Lbx.path(n)), Pics.get(pics, N.Lbx.path(n))),
      LBX.Lb.x(N.Lbx.get(n), N.Lbx.box(n), ms), LBX.Lb.y(N.Lbx.get(n), N.Lbx.box(n), ms), N.Nui.width(n), N.Nui.height(n)))

# the frame: the lightbox while it is up, else the window's tiles. The
# lightbox is drawn whole and leaves the kept tiles alone: they still hold
# the window's last frame, which is what shows again when it closes
def Lbv.paint(on: Bool, +ops: List<&2, R.Op>, +hs: List<&2, N.Hit>, +n: N.Nui, w: Window, +q: Chan(ShellMsg), +i: Chan(S.Msg), +wa: Aux, +epoch: Nat, +ms: Nat) -> IO(Shell):
  match on:
    case True{}:
      IO.bind(Window & Image, Shell, W.Win.present(w, Lbv.draw(n, Tie.pics(Aux.tie(wa)), ms)),
        r => Shell.shown(r, Shell.hits(n, hs, epoch), q, i, wa, Shell.anim(n, ms), ms))
    case False{}:
      Shell.present(Shell.image(N.Nui.panel(n), ops, N.Nui.vw(n), N.Nui.width(n), N.Nui.height(n), N.Nui.vx0(n), ms, hs, Tie.pics(Aux.tie(wa)), Aux.frames(wa)),
        L.Out{ops, hs}, n, w, q, i, wa, epoch, ms)

def Shell.paint.out(o: L.Out, +n: N.Nui, w: Window, +q: Chan(ShellMsg), +i: Chan(S.Msg), +wa: Aux, +epoch: Nat, +ms: Nat) -> IO(Shell):
  match o:
    case L.Out{+ops, +hs}:
      Lbv.paint(N.Lbx.on(n), ops, hs, n, w, q, i, wa, epoch, ms)

# the timeline's memo is brought up to this frame first; layout draws from it
def Shell.paint.m(+memo: L.TLMemo, +n: N.Nui, w: Window, +q: Chan(ShellMsg), +i: Chan(S.Msg), +wa: Aux, +epoch: Nat, +ms: Nat) -> IO(Shell):
  Shell.paint.out(L.Lay.frame(Aux.ty(wa), memo, n), n, w, q, i, Aux.with_memo(wa, memo), epoch, ms)

def Shell.paint.go(+n: N.Nui, w: Window, +q: Chan(ShellMsg), +i: Chan(S.Msg), +wa: Aux, +epoch: Nat, +ms: Nat) -> IO(Shell):
  Shell.paint.m(L.Lay.memo(Aux.ty(wa), n, Aux.memo(wa)), n, w, q, i, wa, epoch, ms)

def Shell.paint.k(+n0: N.Nui, w: Window, +q: Chan(ShellMsg), +i: Chan(S.Msg), wa: Aux, +epoch: Nat, +ms: Nat) -> IO(Shell):
  match n0:
    case N.Nui{u, +ww, +hh, mx, my, sd, sc, ca, fo, pa, _, _, vw0}:
      Shell.paint.go(N.Nui{u, ww, hh, mx, my, sd, sc, ca, fo, pa, Nil{}, ms,
        Shell.vw.if(N.Nui.panel(n0), vw0, ww, hh, N.Nui.vx0(n0), ms)}, w, q, i, wa, epoch, ms)

def Shell.paint(+n: N.Nui, w: Window, +q: Chan(ShellMsg), +i: Chan(S.Msg), wa: Aux, +epoch: Nat, +ms: Nat) -> IO(Shell):
  Shell.paint.k(N.Lbx.stamp(N.Blink.stamp(N.Hover.stamp(N.Nui.prepare(n), ms), ms), ms), w, q, i, wa, epoch, ms)

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
    case FromHub{tag, t}:
      Shell.tagged(a, FromHub{tag, t})
    case Frame{}:
      Shell.frame(a)
    case Blink{}:
      Shell.frame(Shell.blinked(a))
    case Gone{tag}:
      Shell.tagged(a, Gone{tag})
    case Retry{tag}:
      Shell.tagged(a, Retry{tag})
    case Board{key, items}:
      Shell.board(a, key, items)
    case Mesh3{key, ts}:
      Shell.mesh(a, key, ts)
    case Status{key, text}:
      Shell.status(a, key, text)
    case Shot{key, b}:
      Shell.shot(a, key, b)
    case PicOk{tag, path, w, h, rgb}:
      Shell.tagged(a, PicOk{tag, path, w, h, rgb})
    case PicErr{tag, path, why}:
      Shell.tagged(a, PicErr{tag, path, why})

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
    ok : Bool <- Chan.send(S.Msg, inbox, S.Join{0, out, 0n, ""})
    IO.spawn(Unit, Pump.loop(S.Fuel.forever(), ev, q))
    IO.spawn(Unit, Fwd.loop(S.Fuel.forever(), out, q, "#0"))
    ty : L.Ty <- L.Ty.load()
    a : Shell <- Shell.later(Shell{N.Nui.init(U.Ui.init(U32.to_nat(t)), 1400, 900), pw, True{}, False{}, q, inbox, Aux{Nil{}, ty, Tie{inbox, "", "#0", 1n, Map.new(&2, BM.Bitmap), Map.new(&2, Bool)}, Kept{TI.FNone{}, L.TL.memo.none()}}})
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
