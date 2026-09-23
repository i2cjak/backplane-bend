import Base
import ../core/client.bend as U
import ./win.bend as W
import ../core/json.bend as J
import ./viewer.bend as V
import ../core/board.bend as B
import ../core/glb.bend as G
import ../gfx/mesh.bend as MS
import ../gfx/bitmap.bend as BM

# The native window's state around the shared client state (Ui): size,
# pointer, scroll, focus and the composer caret. Input is pure: an event
# goes in, the next state and the commands to run come out.

# a clickable region from the last layout (topmost first)
type Hit is Data:
  Hit{x0: U32, y0: U32, x1: U32, y1: U32, action: String, value: String}

type Nui is Data:
  Nui{
    ui: U.Ui,
    w: U32,
    h: U32,
    mx: U32,
    my: U32,
    side: U32,
    scroll: U32,
    caret: Nat,
    focus: String,
    path: String,
    hits: List<&2, Hit>,
    ms: Nat,
    vw: V.Vw
  }

# what the window loop must do
type NCmd is Data:
  NSend{text: String}
  NCopy{text: String}
  NPaste{}
  NQuit{}

type Step is Data:
  Step{nui: Nui, cmds: List<&2, NCmd>, dirty: Bool}

def Nui.init(ui: U.Ui, +w: U32, +h: U32) -> Nui:
  Nui{ui, w, h, 0, 0, 0, 0, 0n, "composer", "", Nil{}, 0n, V.Vw.init()}

# Keys (X keysyms)
# ----------------

def Key.backspace() -> U32:
  65288

def Key.tab() -> U32:
  65289

def Key.enter() -> U32:
  65293

def Key.escape() -> U32:
  65307

def Key.delete() -> U32:
  65535

def Key.home() -> U32:
  65360

def Key.left() -> U32:
  65361

def Key.right() -> U32:
  65363

def Key.end() -> U32:
  65367

def Key.kp_enter() -> U32:
  65421

# Commands from the client state
# ------------------------------

def Nui.cmd(c: U.Cmd, rest: List<&2, NCmd>) -> List<&2, NCmd>:
  match c:
    case U.Send{t}:
      NSend{t} <> rest
    case U.Copy{t}:
      NCopy{t} <> rest
    case _:
      rest

def Nui.cmds(cs: List<&2, U.Cmd>) -> List<&2, NCmd>:
  match cs:
    case Nil{}:
      Nil{}
    case c <> t:
      Nui.cmd(c, Nui.cmds(t))

# Focus and scroll requests from the client state apply here
def Nui.effects(cs: List<&2, U.Cmd>, n: Nui) -> Nui:
  match cs n:
    case Nil{} _:
      n
    case U.Focus{id} <> t Nui{u, w, h, mx, my, sd, sc, ca, _, pa, hi, ms, vw}:
      Nui.effects(t, Nui{u, w, h, mx, my, sd, sc, ca, id, pa, hi, ms, vw})
    case U.Scroll{} <> t Nui{u, w, h, mx, my, sd, _, ca, fo, pa, hi, ms, vw}:
      Nui.effects(t, Nui{u, w, h, mx, my, sd, 0, ca, fo, pa, hi, ms, vw})
    case _ <> t _:
      Nui.effects(t, n)

# run a client action and fold its commands in
def Nui.act.k(a: U.Act, n: Nui) -> Step:
  match a n:
    case U.Act{u, +cs} Nui{_, w, h, mx, my, sd, sc, ca, fo, pa, hi, ms, vw}:
      Step{Nui.effects(cs, Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, hi, ms, vw}), Nui.cmds(cs), True{}}

def Nui.act(n: Nui, +action: String, +value: String) -> Step:
  match n:
    case Nui{+u, w, h, mx, my, sd, sc, ca, fo, pa, hi, ms, vw}:
      Nui.act.k(U.Ui.act(u, action, value), Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, hi, ms, vw})

# Server messages
# ---------------

def Nui.recv(n: Nui, +o: J.Json) -> Nui:
  match n:
    case Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, hi, ms, vw}:
      Nui{U.Ui.recv(u, o), w, h, mx, my, sd, sc, ca, fo, pa, hi, ms, vw}

# Editing a text field
# --------------------

type Ed is Data:
  Ed{text: String, caret: Nat, submit: Bool, changed: Bool}

def Ed.insert(+s: String, +i: Nat, +x: String) -> Ed:
  Ed{String.take(s, i) ++ x ++ String.drop(s, i), Nat.add(i, String.length(x)), False{}, True{}}

def Ed.back(+s: String, +i: Nat) -> Ed:
  Bool.pick(Ed, Nat.is_eq(i, 0n), Ed{s, i, False{}, False{}},
    Ed{String.take(s, Nat.sub(i, 1n)) ++ String.drop(s, i), Nat.sub(i, 1n), False{}, True{}})

def Ed.del(+s: String, +i: Nat) -> Ed:
  Ed{String.take(s, i) ++ String.drop(s, 1n+i), i, False{}, True{}}

def Ed.move(+s: String, +i: Nat) -> Ed:
  Ed{s, Bool.pick(Nat, Nat.is_gt(i, String.length(s)), String.length(s), i), False{}, False{}}

def Ed.key.k(enter: Bool, back: Bool, del: Bool, left: Bool, right: Bool, home: Bool, end: Bool, typed: Bool,
    +shift: Bool, +s: String, +i: Nat, +text: U32) -> Ed:
  match enter back del left right home end typed:
    case True{} _ _ _ _ _ _ _:
      Bool.pick(Ed, shift, Ed.insert(s, i, "\n"), Ed{s, i, True{}, False{}})
    case _ True{} _ _ _ _ _ _:
      Ed.back(s, i)
    case _ _ True{} _ _ _ _ _:
      Ed.del(s, i)
    case _ _ _ True{} _ _ _ _:
      Ed.move(s, Nat.sub(i, 1n))
    case _ _ _ _ True{} _ _ _:
      Ed.move(s, 1n+i)
    case _ _ _ _ _ True{} _ _:
      Ed.move(s, 0n)
    case _ _ _ _ _ _ True{} _:
      Ed.move(s, String.length(s))
    case _ _ _ _ _ _ _ True{}:
      Ed.insert(s, i, SCon{Chr{text}, SNil{}})
    case _ _ _ _ _ _ _ _:
      Ed{s, i, False{}, False{}}

# one key on a field holding s with the caret at i
def Ed.key(+code: U32, +text: U32, +mods: U32, +s: String, +i: Nat) -> Ed:
  Ed.key.k(Bool.or(U32.is_eq(code, Key.enter()), U32.is_eq(code, Key.kp_enter())), U32.is_eq(code, Key.backspace()),
    U32.is_eq(code, Key.delete()), U32.is_eq(code, Key.left()), U32.is_eq(code, Key.right()),
    U32.is_eq(code, Key.home()), U32.is_eq(code, Key.end()),
    Bool.and(U32.is_ne(text, 0), U32.is_eq(U32.and(mods, 6), 0)),
    U32.is_ne(U32.and(mods, 1), 0), s, i, text)

# Keys
# ----

def Nui.with_caret(n: Nui, +c: Nat) -> Nui:
  match n:
    case Nui{u, w, h, mx, my, sd, sc, _, fo, pa, hi, ms, vw}:
      Nui{u, w, h, mx, my, sd, sc, c, fo, pa, hi, ms, vw}

def Nui.with_path(n: Nui, s: String, +c: Nat) -> Nui:
  match n:
    case Nui{u, w, h, mx, my, sd, sc, _, fo, _, hi, ms, vw}:
      Nui{u, w, h, mx, my, sd, sc, c, fo, s, hi, ms, vw}

def Step.caret(s: Step, +c: Nat) -> Step:
  match s:
    case Step{n, cs, d}:
      Step{Nui.with_caret(n, c), cs, d}

def Nui.composer.k(e: Ed, n: Nui) -> Step:
  match e:
    case Ed{_, _, True{}, _}:
      Step.caret(Nui.act(n, "send", ""), 0n)
    case Ed{+t, +c, False{}, True{}}:
      Step.caret(Nui.act(n, "draft", t), c)
    case Ed{_, +c, False{}, False{}}:
      Step{Nui.with_caret(n, c), Nil{}, True{}}

def Nui.path.k(e: Ed, n: Nui) -> Step:
  match e:
    case Ed{+t, _, True{}, _}:
      Nui.act(Nui.with_path(n, "", 0n), "add-project", t)
    case Ed{t, +c, False{}, _}:
      Step{Nui.with_path(n, t, c), Nil{}, True{}}

def Nui.field.k(comp: Bool, path: Bool, n: Nui, +code: U32, +text: U32, +mods: U32) -> Step:
  match comp path n:
    case True{} _ Nui{+u, w, h, mx, my, sd, sc, +ca, fo, pa, hi, ms, vw}:
      Nui.composer.k(Ed.key(code, text, mods, U.Ui.draft_text(u), ca), Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, hi, ms, vw})
    case False{} True{} Nui{u, w, h, mx, my, sd, sc, +ca, fo, +pa, hi, ms, vw}:
      Nui.path.k(Ed.key(code, text, mods, pa, ca), Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, hi, ms, vw})
    case _ _ _:
      Step{n, Nil{}, False{}}

def Nui.focus_of(n: Nui) -> String:
  match n:
    case Nui{_, _, _, _, _, _, _, _, fo, _, _, _, vw}:
      fo

def Nui.focus(n: Nui, fo: String) -> Step:
  match n:
    case Nui{u, w, h, mx, my, sd, sc, ca, _, pa, hi, ms, vw}:
      Step{Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, hi, ms, vw}, Nil{}, True{}}

def Nui.paste.k(comp: Bool, path: Bool, n: Nui, +text: String) -> Step:
  match comp path n:
    case True{} _ Nui{+u, w, h, mx, my, sd, sc, +ca, fo, pa, hi, ms, vw}:
      Nui.composer.k(Ed.insert(U.Ui.draft_text(u), ca, text), Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, hi, ms, vw})
    case False{} True{} Nui{u, w, h, mx, my, sd, sc, +ca, fo, +pa, hi, ms, vw}:
      Nui.path.k(Ed.insert(pa, ca, text), Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, hi, ms, vw})
    case _ _ _:
      Step{n, Nil{}, False{}}

# pasted text lands in the focused field at the caret
def Nui.paste(+n: Nui, text: String) -> Step:
  Nui.paste.k(String.eq(Nui.focus_of(n), "composer"), String.eq(Nui.focus_of(n), "project-path"), n, text)

# Pointer
# -------

def Hit.inside(h: Hit, +x: U32, +y: U32) -> Bool:
  match h:
    case Hit{x0, y0, x1, y1, _, _}:
      Bool.and(Bool.and(U32.is_ge(x, x0), U32.is_lt(x, x1)), Bool.and(U32.is_ge(y, y0), U32.is_lt(y, y1)))

def Hit.first(hs: List<&2, Hit>, +x: U32, +y: U32) -> Bool:
  match hs:
    case h <> _:
      Hit.inside(h, x, y)
    case Nil{}:
      False{}

def Hit.go(hs: List<&2, Hit>, hit: Bool, +x: U32, +y: U32) -> Maybe<&2, Hit>:
  match hs hit:
    case h <> _ True{}:
      Some{h}
    case _ <> +t False{}:
      Hit.go(t, Hit.first(t, x, y), x, y)
    case Nil{} _:
      None{}

# the topmost region under the pointer
def Hit.find(+hs: List<&2, Hit>, +x: U32, +y: U32) -> Maybe<&2, Hit>:
  Hit.go(hs, Hit.first(hs, x, y), x, y)

# show another kind of view: the scene starts empty and refits
def Vw.kind_set(v: V.Vw, +k: U32, +path: String) -> V.Vw:
  match v:
    case V.Vw{_, vi, _, r, d, lx, ly, b, _, cu, V.Vx{_, _, t, c, sh, bu, px, py, _, se, bm}}:
      V.Vw{Nil{}, vi, False{}, "", d, lx, ly, b, False{}, cu, V.Vx{k, "", t, c, sh, bu, px, py, path, se, bm}}

def Vw.pick_set(v: V.Vw, +key: String) -> V.Vw:
  match v:
    case V.Vw{s, vi, f, r, d, lx, ly, b, fr, cu, V.Vx{k, _, t, c, sh, bu, px, py, pa, se, bm}}:
      V.Vw{s, vi, f, r, d, lx, ly, b, fr, cu, V.Vx{k, key, t, c, sh, bu, px, py, pa, se, bm}}

def Nui.pos(xs: List<&2, String>, +x: String, +i: Nat) -> Nat:
  match xs:
    case Nil{}:
      i
    case +h <> t:
      Bool.pick(Nat, String.eq(h, x), i, Nui.pos(t, x, 1n+i))

def Nui.hits(n: Nui) -> List<&2, Hit>:
  match n:
    case Nui{_, _, _, _, _, _, _, _, _, _, hi, _, vw}:
      hi

def Nui.wheel.k(side: Bool, up: Bool, down: Bool, n: Nui, +sd: U32, +sc: U32) -> Step:
  match side up down n:
    case True{} True{} _ Nui{u, w, h, mx, my, _, sc2, ca, fo, pa, hi, ms, vw}:
      Step{Nui{u, w, h, mx, my, Bool.pick(U32, U32.is_ge(sd, 48), (sd - 48 : U32), 0), sc2, ca, fo, pa, hi, ms, vw}, Nil{}, True{}}
    case True{} False{} True{} Nui{u, w, h, mx, my, _, sc2, ca, fo, pa, hi, ms, vw}:
      Step{Nui{u, w, h, mx, my, (sd + 48 : U32), sc2, ca, fo, pa, hi, ms, vw}, Nil{}, True{}}
    case False{} True{} _ Nui{u, w, h, mx, my, sd2, _, ca, fo, pa, hi, ms, vw}:
      Step{Nui{u, w, h, mx, my, sd2, (sc + 48 : U32), ca, fo, pa, hi, ms, vw}, Nil{}, True{}}
    case False{} False{} True{} Nui{u, w, h, mx, my, sd2, _, ca, fo, pa, hi, ms, vw}:
      Step{Nui{u, w, h, mx, my, sd2, Bool.pick(U32, U32.is_ge(sc, 48), (sc - 48 : U32), 0), ca, fo, pa, hi, ms, vw}, Nil{}, True{}}
    case _ _ _ _:
      Step{n, Nil{}, False{}}

# the wheel moves the sidebar or the timeline, 3 lines a notch
def Nui.wheel(n: Nui, +x: U32, +dir: U32) -> Step:
  match n:
    case Nui{u, w, h, mx, my, +sd, +sc, ca, fo, pa, hi, ms, vw}:
      Nui.wheel.k(U32.is_lt(x, 264), U32.is_eq(dir, 0), U32.is_eq(dir, 1), Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, hi, ms, vw}, sd, sc)

def Nui.resize(n: Nui, +w: U32, +h: U32) -> Step:
  match n:
    case Nui{u, _, _, mx, my, sd, sc, ca, fo, pa, hi, ms, vw}:
      Step{Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, hi, ms, vw}, Nil{}, True{}}

def Nui.moved(n: Nui, +x: U32, +y: U32) -> Step:
  match n:
    case Nui{u, w, h, _, _, sd, sc, ca, fo, pa, hi, ms, vw}:
      Step{Nui{u, w, h, x, y, sd, sc, ca, fo, pa, hi, ms, vw}, Nil{}, False{}}

def Step.merge(a: Step, b: Step) -> Step:
  match a b:
    case Step{_, c1, d1} Step{n2, c2, d2}:
      Step{n2, List.append(&2, NCmd, c1, c2), Bool.or(d1, d2)}

def Nui.ui(n: Nui) -> U.Ui:
  match n:
    case Nui{u, _, _, _, _, _, _, _, _, _, _, _, vw}:
      u

# The board viewer
# ----------------

def Nui.panel(n: Nui) -> Bool:
  match n:
    case Nui{U.Ui{_, _, _, _, _, _, _, _, pa, _, _, _, _, _, _}, _, _, _, _, _, _, _, _, _, _, _, _}:
      pa

def Nui.vx0.k(open: Bool, +w: U32) -> U32:
  Bool.pick(U32, open, (264 + U32.shr((w - 264 : U32)) : U32), w)

def Nui.width(n: Nui) -> U32:
  match n:
    case Nui{_, w, _, _, _, _, _, _, _, _, _, _, _}:
      w

# the viewer's left edge (the window's width when it is closed)
def Nui.vx0(+n: Nui) -> U32:
  Nui.vx0.k(Nui.panel(n), Nui.width(n))

def Nui.in_viewer(+n: Nui, +x: U32) -> Bool:
  Bool.and(Nui.panel(n), U32.is_ge(x, Nui.vx0(n)))

def Nui.with_vw(n: Nui, vw: V.Vw) -> Nui:
  match n:
    case Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, hi, ms, _}:
      Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, hi, ms, vw}

def Nui.vw(n: Nui) -> V.Vw:
  match n:
    case Nui{_, _, _, _, _, _, _, _, _, _, _, _, vw}:
      vw

def Nui.vw_act.k(i: Nat, +n: Nui, +value: String) -> Step:
  match i:
    case 0n:
      Step{Nui.with_vw(n, Vw.kind_set(Nui.vw(n), Maybe.default(&2, U32, U32.read(value), 0), "")), Nil{}, True{}}
    case 1n:
      Step{Nui.with_vw(n, Vw.pick_set(Nui.vw(n), "")), Nil{}, True{}}
    case _:
      Step{n, Nil{}, False{}}

# the viewer's own actions (they never reach the client state)
def Nui.vw_act(+n: Nui, +action: String, +value: String) -> Step:
  Nui.vw_act.k(Nui.pos(["vw-kind", "vw-unpick"], action, 0n), n, value)

def Nui.click.act(focus: Bool, +n: Nui, +action: String, +value: String) -> Step:
  match focus:
    case True{}:
      Nui.focus(n, value)
    case False{}:
      Bool.pick(Step, String.starts_with(action, "vw-"), Nui.vw_act(n, action, value), Nui.act(n, action, value))

def Nui.click.k(m: Maybe<&2, Hit>, +n: Nui) -> Step:
  match m:
    case Some{Hit{_, _, _, _, +action, +value}}:
      Nui.click.act(String.eq(action, "focus"), n, action, value)
    case None{}:
      Step{n, Nil{}, False{}}

def Nui.click(+n: Nui, +x: U32, +y: U32) -> Step:
  Nui.click.k(Hit.find(Nui.hits(n), x, y), n)

def Vw.drag(v: V.Vw, on: Bool, +x: U32, +y: U32) -> V.Vw:
  match v:
    case V.Vw{s, vi, f, r, _, _, _, b, fr, cu, vx}:
      V.Vw{s, vi, f, r, on, x, y, b, fr, cu, vx}

def Vx.kind(x: V.Vx) -> U32:
  match x:
    case V.Vx{k, _, _, _, _, _, _, _, _, _, bm}:
      k

def Vw.x(v: V.Vw) -> V.Vx:
  match v:
    case V.Vw{_, _, _, _, _, _, _, _, _, _, vx}:
      vx

def Vw.kind(v: V.Vw) -> U32:
  Vx.kind(Vw.x(v))

def Vx.orbit(x: V.Vx, +dx: F32, +dy: F32) -> V.Vx:
  match x:
    case V.Vx{k, p, t, c, sh, bu, px, py, pa, se, bm}:
      V.Vx{k, p, t, MS.Cam.orbit(c, F32.mul(dx, 0.01), F32.mul(dy, 0.01)), sh, bu, px, py, pa, se, bm}

def Vx.zoom(x: V.Vx, +f: F32) -> V.Vx:
  match x:
    case V.Vx{k, p, t, c, sh, bu, px, py, pa, se, bm}:
      V.Vx{k, p, t, MS.Cam.zoom(c, F32.div(1.0, f)), sh, bu, px, py, pa, se, bm}

def Vx.refit(x: V.Vx) -> V.Vx:
  match x:
    case V.Vx{k, p, +t, _, sh, bu, px, py, pa, se, bm}:
      V.Vx{k, p, t, MS.Cam.fit(t), sh, bu, px, py, pa, se, bm}

# a drag pans a board or schematic and orbits a 3D model
def Vw.moved.k(three: Bool, v: V.Vw, +x: U32, +y: U32) -> V.Vw:
  match three v:
    case False{} V.Vw{s, vi, f, r, True{}, +lx, +ly, b, _, cu, vx}:
      V.Vw{s, V.View.pan(vi, F32.sub(U32.to_f32(x), U32.to_f32(lx)), F32.sub(U32.to_f32(y), U32.to_f32(ly))), f, r, True{}, x, y, b, False{}, cu, vx}
    case True{} V.Vw{s, vi, f, r, True{}, +lx, +ly, b, _, cu, vx}:
      V.Vw{s, vi, f, r, True{}, x, y, b, False{}, cu, Vx.orbit(vx, F32.sub(U32.to_f32(x), U32.to_f32(lx)), F32.sub(U32.to_f32(y), U32.to_f32(ly)))}
    case _ _:
      v

def Vw.moved(+v: V.Vw, +x: U32, +y: U32) -> V.Vw:
  Vw.moved.k(U32.is_eq(Vw.kind(v), 2), v, x, y)

def Vw.zoom.k(three: Bool, v: V.Vw, +f: F32, +x: U32, +y: U32) -> V.Vw:
  match three v:
    case False{} V.Vw{s, vi, fi, r, d, lx, ly, b, _, cu, vx}:
      V.Vw{s, V.View.zoom(vi, f, U32.to_f32(x), U32.to_f32(y)), fi, r, d, lx, ly, b, False{}, cu, vx}
    case True{} V.Vw{s, vi, fi, r, d, lx, ly, b, _, cu, vx}:
      V.Vw{s, vi, fi, r, d, lx, ly, b, False{}, cu, Vx.zoom(vx, f)}

def Vw.zoom(+v: V.Vw, +f: F32, +x: U32, +y: U32) -> V.Vw:
  Vw.zoom.k(U32.is_eq(Vw.kind(v), 2), v, f, x, y)

def Vw.refit(v: V.Vw) -> V.Vw:
  match v:
    case V.Vw{s, vi, _, r, d, lx, ly, b, _, cu, vx}:
      V.Vw{s, vi, False{}, r, d, lx, ly, b, False{}, cu, Vx.refit(vx)}

def Nui.key.free(nofocus: Bool, fit: Bool, +n: Nui, +code: U32, +text: U32, +mods: U32) -> Step:
  match nofocus fit:
    case True{} True{}:
      Step{Nui.with_vw(n, Vw.refit(Nui.vw(n))), Nil{}, True{}}
    case _ _:
      Nui.field.k(String.eq(Nui.focus_of(n), "composer"), String.eq(Nui.focus_of(n), "project-path"), n, code, text, mods)

def Nui.key.k(paste: Bool, esc: Bool, +n: Nui, +code: U32, +text: U32, +mods: U32) -> Step:
  match paste esc:
    case True{} _:
      Step{n, [NPaste{}], False{}}
    case False{} True{}:
      Nui.focus(n, "")
    case False{} False{}:
      Nui.key.free(String.is_empty(Nui.focus_of(n)), U32.is_eq(code, 102), n, code, text, mods)

# a key press (releases do nothing)
def Nui.key(+n: Nui, +code: U32, +text: U32, +mods: U32) -> Step:
  Nui.key.k(Bool.and(U32.is_ne(U32.and(mods, 2), 0), U32.is_eq(code, 118)), U32.is_eq(code, Key.escape()), n, code, text, mods)

def Vw.stale(v: V.Vw) -> V.Vw:
  match v:
    case V.Vw{s, vi, f, r, d, lx, ly, b, _, cu, vx}:
      V.Vw{s, vi, f, r, d, lx, ly, b, False{}, cu, vx}

# a board file arrived for a project root: same root merges (only what
# changed fades), a new root starts over (the whole board fades in)
def Vx.shown(x: V.Vx) -> String:
  match x:
    case V.Vx{_, _, _, _, sh, _, _, _, _, _, bm}:
      sh

def Vx.busy(x: V.Vx, bu: String) -> V.Vx:
  match x:
    case V.Vx{k, p, t, c, sh, _, px, py, pa, se, bm}:
      V.Vx{k, p, t, c, sh, bu, px, py, pa, se, bm}

# a scene file arrived for a source: the same source merges (only what
# changed fades), another starts over (the whole scene fades in)
def Vw.board.k(same: Bool, v: V.Vw, +root: String, +items: List<&2, B.Item>, +now: Nat) -> V.Vw:
  match same v:
    case True{} V.Vw{+s, vi, f, _, d, lx, ly, b, _, cu, vx}:
      V.Vw{V.Scene.update(s, items, now), vi, f, root, d, lx, ly, b, False{}, cu, Vx.busy(vx, "")}
    case False{} V.Vw{_, vi, _, _, d, lx, ly, b, _, cu, vx}:
      V.Vw{V.Scene.update(Nil{}, items, now), vi, False{}, root, d, lx, ly, b, False{}, cu, Vx.busy(vx, "")}

def Vx.mesh(x: V.Vx, ts: List<&2, G.Tri3>) -> V.Vx:
  match x:
    case V.Vx{k, p, _, c, sh, _, px, py, pa, se, bm}:
      Vx.refit(V.Vx{k, p, ts, c, sh, "", px, py, pa, se, bm})

def Vw.mesh(v: V.Vw, ts: List<&2, G.Tri3>) -> V.Vw:
  match v:
    case V.Vw{s, vi, f, r, d, lx, ly, b, _, cu, vx}:
      V.Vw{s, vi, f, r, d, lx, ly, b, False{}, cu, Vx.mesh(vx, ts)}

def Vw.status(v: V.Vw, +text: String) -> V.Vw:
  match v:
    case V.Vw{s, vi, f, r, d, lx, ly, b, fr, cu, vx}:
      V.Vw{s, vi, f, r, d, lx, ly, b, fr, cu, Vx.busy(vx, text)}

def Vw.if(ok: Bool, v: V.Vw, k: V.Vw -> V.Vw) -> V.Vw:
  match ok:
    case True{}:
      k(v)
    case False{}:
      v

def Vw.root(v: V.Vw) -> String:
  match v:
    case V.Vw{_, _, _, r, _, _, _, _, _, _, vx}:
      r

def Vw.fresh_for(+v: V.Vw, +key: String) -> Bool:
  String.eq(Vx.shown(Vw.x(v)), key)

def Vw.board.same(+v: V.Vw, +key: String, +items: List<&2, B.Item>, +now: Nat) -> V.Vw:
  Vw.board.k(String.eq(Vw.root(v), key), v, key, items, now)

# results for a source other than the one on show are stale: dropped
def Nui.board(+n: Nui, +key: String, +items: List<&2, B.Item>, +now: Nat) -> Nui:
  Nui.with_vw(n, Vw.if(Vw.fresh_for(Nui.vw(n), key), Nui.vw(n), v => Vw.board.same(v, key, items, now)))

def Nui.mesh(+n: Nui, +key: String, ts: List<&2, G.Tri3>) -> Nui:
  Nui.with_vw(n, Vw.if(Vw.fresh_for(Nui.vw(n), key), Nui.vw(n), v => Vw.mesh(v, ts)))

def Vw.shot(v: V.Vw, b: BM.Bitmap) -> V.Vw:
  match v:
    case V.Vw{s, vi, f, r, d, lx, ly, bb, _, cu, V.Vx{k, p, t, c, sh, _, px, py, pa, se, _}}:
      V.Vw{s, vi, f, r, d, lx, ly, bb, False{}, cu, V.Vx{k, p, t, c, sh, "", px, py, pa, se, b}}

# a new frame of the agents' browser
def Nui.shot(+n: Nui, +key: String, b: BM.Bitmap) -> Nui:
  Nui.with_vw(n, Vw.if(Vw.fresh_for(Nui.vw(n), key), Nui.vw(n), v => Vw.shot(v, b)))

def Nui.status(+n: Nui, +key: String, +text: String) -> Nui:
  Nui.with_vw(n, Vw.if(Vw.fresh_for(Nui.vw(n), key), Nui.vw(n), v => Vw.status(v, text)))

# the browser's source is its frame file, whatever the project
def Nui.source.k(x: V.Vx, +root: String, +frames: String) -> String:
  match x:
    case V.Vx{+k, _, _, _, _, _, _, _, +pa, _, bm}:
      Bool.pick(String, U32.is_eq(k, 3), V.Src.key(3, "", frames), V.Src.key(k, root, pa))

# the source the viewer should show now (Src.key)
def Nui.source(+n: Nui) -> String:
  Nui.source.k(Vw.x(Nui.vw(n)), U.Ui.root(Nui.ui(n)), U.Ui.info(Nui.ui(n), "browser.frames"))

def Vw.asked(v: V.Vw, +key: String) -> V.Vw:
  match v:
    case V.Vw{s, vi, f, r, d, lx, ly, b, fr, cu, V.Vx{+k, p, t, c, _, _, px, py, pa, se, bm}}:
      V.Vw{s, vi, f, r, d, lx, ly, b, fr, cu, V.Vx{k, p, t, c, key, Bool.pick(String, U32.is_eq(k, 2), "Exporting 3D model…", Bool.pick(String, U32.is_eq(k, 3), "The agents' browser shows here when they open a page.", "Loading…")), px, py, pa, se, bm}}

# the viewer asked for a source (the shell starts reading it)
def Nui.asked(+n: Nui, +key: String) -> Nui:
  Nui.with_vw(n, Vw.asked(Nui.vw(n), key))

# fit the view to the board the first time the viewer shows it
def Vw.fit(v: V.Vw, +x0: U32, +h: U32, +w: U32) -> V.Vw:
  match v:
    case V.Vw{+s, vi, False{}, r, d, lx, ly, b, _, cu, vx}:
      V.Vw{s, V.View.fit(s, U32.to_f32(x0), 52.0, U32.to_f32((w - x0 : U32)), U32.to_f32((h - 52 : U32))), Bool.not(List.is_empty(&2, V.Seen, s)), r, d, lx, ly, b, False{}, cu, vx}
    case _:
      v

def Nui.height(n: Nui) -> U32:
  match n:
    case Nui{_, _, h, _, _, _, _, _, _, _, _, _, _}:
      h

def Nui.prepare.k(open: Bool, +n: Nui) -> Nui:
  match open:
    case True{}:
      Nui.with_vw(n, Vw.fit(Nui.vw(n), Nui.vx0(n), Nui.height(n), Nui.width(n)))
    case False{}:
      n

# the kind of view for a requested file: named, else from its extension
def View.kind_of(+kind: String, +path: String) -> U32:
  Bool.pick(U32, String.eq(kind, "browser"), 3,
  Bool.pick(U32, String.eq(kind, "schematic"), 1,
    Bool.pick(U32, Bool.or(String.eq(kind, "3d"), String.eq(kind, "step")), 2,
      Bool.pick(U32, String.eq(kind, "board"), 0,
        Bool.pick(U32, String.ends_with(path, ".kicad_sch"), 1,
          Bool.pick(U32, Bool.or(String.ends_with(path, ".glb"), Bool.or(String.ends_with(path, ".step"), String.ends_with(path, ".stp"))), 2, 0))))))

def Vx.seen(x: V.Vx) -> String:
  match x:
    case V.Vx{_, _, _, _, _, _, _, _, _, se, bm}:
      se

def Vw.seen_set(v: V.Vw, +seen: String) -> V.Vw:
  match v:
    case V.Vw{s, vi, f, r, d, lx, ly, b, fr, cu, V.Vx{k, p, t, c, sh, bu, px, py, pa, _, bm}}:
      V.Vw{s, vi, f, r, d, lx, ly, b, fr, cu, V.Vx{k, p, t, c, sh, bu, px, py, pa, seen, bm}}

def Nui.request.k(fresh: Bool, +n: Nui, +seen: String) -> Nui:
  match fresh:
    case True{}:
      Nui.with_vw(n, Vw.seen_set(Vw.kind_set(Nui.vw(n), View.kind_of(U.Ui.info(Nui.ui(n), "view.kind"), U.Ui.info(Nui.ui(n), "view.path")), U.Ui.info(Nui.ui(n), "view.path")), seen))
    case False{}:
      n

# an agent's viewer_show request not yet applied: switch to that file
def Nui.request(+n: Nui) -> Nui:
  Nui.request.k(Bool.not(String.eq(U.Ui.info(Nui.ui(n), "view.n"), Vx.seen(Vw.x(Nui.vw(n))))), n, U.Ui.info(Nui.ui(n), "view.n"))

def Nui.prepare(+n: Nui) -> Nui:
  Nui.prepare.k(Nui.panel(n), Nui.request(n))

# pointer events on the viewer: drag pans (or orbits), the wheel zooms at
# the pointer, and a press released where it began picks an item
def Vw.press(v: V.Vw, +x: U32, +y: U32) -> V.Vw:
  match v:
    case V.Vw{s, vi, f, r, _, _, _, b, fr, cu, V.Vx{k, p, t, c, sh, bu, _, _, pa, se, bm}}:
      V.Vw{s, vi, f, r, True{}, x, y, b, fr, cu, V.Vx{k, p, t, c, sh, bu, x, y, pa, se, bm}}

def Vw.release.k(click: Bool, v: V.Vw, +x: U32, +y: U32) -> V.Vw:
  match click v:
    case True{} V.Vw{+s, +vi, f, r, _, lx, ly, b, fr, cu, V.Vx{+k, _, t, c, sh, bu, px, py, pa, se, bm}}:
      V.Vw{s, vi, f, r, False{}, lx, ly, b, fr, cu, V.Vx{k, Bool.pick(String, U32.is_eq(k, 2), "", V.Pick.at(s, vi, U32.to_f32(x), U32.to_f32(y), k)), t, c, sh, bu, px, py, pa, se, bm}}
    case False{} V.Vw{s, vi, f, r, _, lx, ly, b, fr, cu, vx}:
      V.Vw{s, vi, f, r, False{}, lx, ly, b, fr, cu, vx}

def Vx.press_at(x: V.Vx) -> U32 & U32:
  match x:
    case V.Vx{_, _, _, _, _, _, px, py, _, _, bm}:
      (px, py)

def Vw.near(p: U32 & U32, +x: U32, +y: U32) -> Bool:
  (+px, +py) = p
  U32.is_lt((U32.max(x, px) - U32.min(x, px) + U32.max(y, py) - U32.min(y, py) : U32), 4)

def Vw.dragging(v: V.Vw) -> Bool:
  match v:
    case V.Vw{_, _, _, _, d, _, _, _, _, _, _}:
      d

def Vw.release(+v: V.Vw, +x: U32, +y: U32) -> V.Vw:
  Vw.release.k(Bool.and(Vw.dragging(v), Vw.near(Vx.press_at(Vw.x(v)), x, y)), v, x, y)

def Nui.view_press(+n: Nui, +x: U32, +y: U32, down: Bool) -> Step:
  match down:
    case True{}:
      Step{Nui.with_vw(n, Vw.press(Nui.vw(n), x, y)), Nil{}, False{}}
    case False{}:
      Step{Nui.with_vw(n, Vw.release(Nui.vw(n), x, y)), Nil{}, Vw.dragging(Nui.vw(n))}

def Nui.dragging(n: Nui) -> Bool:
  match n:
    case Nui{_, _, _, _, _, _, _, _, _, _, _, _, V.Vw{_, _, _, _, d, _, _, _, _, _, vx}}:
      d

def Nui.view_move(+n: Nui, +x: U32, +y: U32) -> Step:
  Step{Nui.with_vw(n, Vw.moved(Nui.vw(n), x, y)), Nil{}, Nui.dragging(n)}

def Nui.view_wheel(+n: Nui, +x: U32, +y: U32, +dir: U32) -> Step:
  Step{Nui.with_vw(n, Vw.zoom(Nui.vw(n), Bool.pick(F32, U32.is_eq(dir, 0), 1.25, 0.8), x, y)), Nil{}, True{}}

def Nui.nohit(m: Maybe<&2, Hit>) -> Bool:
  match m:
    case Some{_}:
      False{}
    case None{}:
      True{}

def Nui.press.k(drag: Bool, +n: Nui, +x: U32, +y: U32) -> Step:
  match drag:
    case True{}:
      Nui.view_press(n, x, y, True{})
    case False{}:
      Nui.click(n, x, y)

# a press on the viewer's own buttons is a click, elsewhere in it a drag
def Nui.press(viewer: Bool, +n: Nui, +x: U32, +y: U32) -> Step:
  Nui.press.k(Bool.and(viewer, Nui.nohit(Hit.find(Nui.hits(n), x, y))), n, x, y)

def Nui.move(drag: Bool, +n: Nui, +x: U32, +y: U32) -> Step:
  match drag:
    case True{}:
      Nui.view_move(n, x, y)
    case False{}:
      Nui.moved(n, x, y)

def Nui.spin(viewer: Bool, +n: Nui, +x: U32, +y: U32, +dir: U32) -> Step:
  match viewer:
    case True{}:
      Nui.view_wheel(n, x, y, dir)
    case False{}:
      Nui.wheel(n, x, dir)

# one window event
def Nui.event(+n: Nui, e: W.WinEv) -> Step:
  match e:
    case W.WKey{code, text, mods, True{}}:
      Nui.key(n, code, text, mods)
    case W.WKey{_, _, _, False{}}:
      Step{n, Nil{}, False{}}
    case W.WButton{+x, +y, 1, True{}}:
      Nui.press(Nui.in_viewer(n, x), n, x, y)
    case W.WButton{+x, +y, 1, False{}}:
      Nui.view_press(n, x, y, False{})
    case W.WButton{_, _, _, _}:
      Step{n, Nil{}, False{}}
    case W.WMove{+x, +y}:
      Nui.move(Nui.dragging(n), n, x, y)
    case W.WWheel{+x, +y, +dir}:
      Nui.spin(Nui.in_viewer(n, x), n, x, y, dir)
    case W.WSize{w, h}:
      Nui.resize(n, w, h)
    case W.WExpose{}:
      Step{n, Nil{}, True{}}
    case W.WQuit{}:
      Step{n, [NQuit{}], False{}}
    case W.WPaste{t}:
      Nui.paste(n, t)

# every event of a batch, in order
def Nui.events(es: List<&2, W.WinEv>, s: Step) -> Step:
  match es s:
    case Nil{} _:
      s
    case e <> t Step{+n, cs, d}:
      Nui.events(t, Step.merge(Step{n, cs, d}, Nui.event(n, e)))
