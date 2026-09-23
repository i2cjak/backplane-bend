import Base
import ../core/model.bend as M
import ../core/json.bend as J
import ../core/client.bend as U
import ../gfx/raster.bend as R
import ../gfx/draw.bend as D
import ../gfx/text.bend as X
import ../web/dom.bend as N
import ./theme.bend as T
import ./nui.bend as S
import ./viewer.bend as V
import ../core/glb.bend as G
import ../gfx/bitmap.bend as BM
import ../core/diff.bend as DF
import ../core/vt.bend as VT
import ../core/attach.bend as AT

# Nui -> draw ops and hit regions. Ops are gathered bottom-up (paint
# order) and reversed once into the topmost-first order the rasterizer
# wants; hits likewise. Text is measured and drawn in the system's fonts
# (Ty), the same faces and sizes as the Backplane web app.

# Nui -> draw ops and hit regions. Ops are gathered bottom-up (paint
# order) and reversed once into the topmost-first order the rasterizer
# wants; hits likewise. Text is measured and drawn in the system's fonts
# (Ty), the same faces and sizes as the Backplane web app.

type Out is Data:
  Out{ops: List<&2, R.Op>, hits: List<&2, S.Hit>}

def Out.none() -> Out:
  Out{Nil{}, Nil{}}

# a then b on top
def Out.cat(a: Out, b: Out) -> Out:
  match a b:
    case Out{o1, h1} Out{o2, h2}:
      Out{List.append(&2, R.Op, o1, o2), List.append(&2, S.Hit, h1, h2)}

def Out.ops(os: List<&2, R.Op>) -> Out:
  Out{os, Nil{}}

def Out.all(xs: List<&2, Out>) -> Out:
  match xs:
    case Nil{}:
      Out.none()
    case x <> t:
      Out.cat(x, Out.all(t))

def Out.when(on: Bool, o: Out) -> Out:
  match on:
    case True{}:
      o
    case False{}:
      Out.none()

# Typography
# ----------

# the glyph cache and the faces: interface, bold, meta, chat body, code
type Ty is Data:
  Ty{cache: Map<&2, X.TG>, ui: X.Face, bold: X.Face, meta: X.Face, body: X.Face, code: X.Face}

def Ty.cache(t: Ty) -> Map<&2, X.TG>:
  match t:
    case Ty{c, _, _, _, _, _}:
      c

# 0 interface 14px, 1 bold, 2 meta 12px, 3 chat body 14px, 4 code 13px
def Ty.face(t: Ty, k: Nat) -> X.Face:
  match t k:
    case Ty{_, f, _, _, _, _} 0n:
      f
    case Ty{_, _, f, _, _, _} 1n:
      f
    case Ty{_, _, _, f, _, _} 2n:
      f
    case Ty{_, _, _, _, f, _} 3n:
      f
    case Ty{_, _, _, _, _, f} _:
      f

def Ty.text(+ty: Ty, +k: Nat, s: String, +c: D.Clip, +x: U32, +y: U32, +lh: U32, +color: U32) -> List<&2, R.Op>:
  X.Text.line(Ty.cache(ty), Ty.face(ty, k), s, c, x, y, lh, color)

def Ty.width(+ty: Ty, +k: Nat, s: String) -> U32:
  X.Text.width(Ty.cache(ty), Ty.face(ty, k), s)

def Ty.fit(+ty: Ty, +k: Nat, +s: String, +px: U32) -> String:
  X.Text.fit(Ty.cache(ty), Ty.face(ty, k), s, px)

def Ty.wrap(+ty: Ty, +k: Nat, s: String, +px: U32) -> List<&2, String>:
  X.Text.wrap(Ty.cache(ty), Ty.face(ty, k), s, px)

# Backplane's type: Berkeley Mono where installed, else the system's
# monospace; FreeType via fontconfig, the Spleen bitmap without them
def Ty.fonts.ui() -> List<&2, String>:
  ["Berkeley Mono", "monospace"]

def Ty.fonts.bold() -> List<&2, String>:
  ["Berkeley Mono:weight=bold", "monospace:weight=bold"]

def Ty.fonts.code() -> List<&2, String>:
  ["Berkeley Mono", "SF Mono", "SFMono-Regular", "Menlo", "Consolas", "Liberation Mono", "monospace"]

def Ty.fonts.warm(fs: List<&2, X.Face>, c: Map<&2, X.TG>) -> IO(Map<&2, X.TG>):
  match fs:
    case Nil{}:
      IO.pure(Map<&2, X.TG>, c)
    case +f <> t:
      IO.bind(Map<&2, X.TG>, Map<&2, X.TG>, X.Text.warm(c, f), c2 => IO.bind(Map<&2, X.TG>, Map<&2, X.TG>, X.Text.ensure(c2, f, "▾▸←−×"), c3 => Ty.fonts.warm(t, c3)))

def Ty.load() -> IO(Ty):
  do IO<Ty>:
    +ui : X.Face <- X.Text.face(Ty.fonts.ui(), 14)
    +bold : X.Face <- X.Text.face(Ty.fonts.bold(), 14)
    +meta : X.Face <- X.Text.face(Ty.fonts.ui(), 12)
    +code : X.Face <- X.Text.face(Ty.fonts.code(), 13)
    c : Map<&2, X.TG> <- Ty.fonts.warm([ui, bold, meta, code], Map.new(&2, X.TG))
    return Ty{c, ui, bold, meta, ui, code}

# Shapes
# ------

# a - b, or 0 when b is larger (U32 subtraction wraps)
def U32.dim(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, U32.is_gt(a, b), (a - b : U32), 0)

def Lay.hit(+x: U32, +y: U32, +w: U32, +h: U32, action: String, value: String) -> S.Hit:
  S.Hit{x, y, (x + w : U32), (y + h : U32), action, value}

# a filled box; corners stay square (house rule), r is kept for callers
def Lay.round(+c: D.Clip, +x: U32, +y: U32, +w: U32, +h: U32, +r: U32, +color: U32) -> List<&2, R.Op>:
  [D.Draw.rect(c, x, y, w, h, color, 255)]

# a box with a 1px border
def Lay.box(+c: D.Clip, +x: U32, +y: U32, +w: U32, +h: U32, +r: U32, +fill: U32, +line: U32) -> List<&2, R.Op>:
  List.append(&2, R.Op, Lay.round(c, x, y, w, h, r, line), Lay.round(c, (x + 1 : U32), (y + 1 : U32), (w - 2 : U32), (h - 2 : U32), (r - 1 : U32), fill))

# a text button: rounded, 10px padding, 28px tall
def Lay.button.w(+ty: Ty, +label: String) -> U32:
  (Ty.width(ty, 2n, label) + 20 : U32)

def Lay.button(+ty: Ty, +c: D.Clip, +x: U32, +y: U32, +label: String, +color: U32, action: String, value: String) -> Out:
  +w = Lay.button.w(ty, label)
  Out{List.append(&2, R.Op, Lay.box(c, x, y, w, 28, 6, T.Th.raise(), T.Th.line()),
      Ty.text(ty, 2n, label, c, (x + 10 : U32), y, 28, color)),
    [Lay.hit(x, y, w, 28, action, value)]}

# a chip that is on or off
def Lay.chip(+ty: Ty, +x: U32, +y: U32, +label: String, +on: Bool, action: String, value: String) -> Out:
  +w = Lay.button.w(ty, label)
  Out{List.append(&2, R.Op, Lay.box(D.Clip.all(), x, y, w, 28, 6, Bool.pick(U32, on, T.Th.sel(), T.Th.raise()), Bool.pick(U32, on, T.Th.accent(), T.Th.line())),
      Ty.text(ty, 2n, label, D.Clip.all(), (x + 10 : U32), y, 28, Bool.pick(U32, on, T.Th.text(), T.Th.dim()))),
    [Lay.hit(x, y, w, 28, action, value)]}

# Sidebar
# -------

# the dot's color for a thread's status (M.Status.of orders them)
def Lay.status(s: M.Status) -> U32:
  match s:
    case M.StApproval{}:
      T.Th.warn()
    case M.StInput{}:
      T.Th.input()
    case M.StWorking{}:
      T.Th.accent()
    case M.StFailed{}:
      T.Th.bad()
    case M.StQueued{}:
      T.Th.queued()
    case M.StReady{}:
      T.Th.faint()

def Lay.row.k(+ty: Ty, +on: Bool, id: String, title: String, +ago: String, +dot: U32, +c: D.Clip, +y: U32) -> Out:
  +aw = Ty.width(ty, 2n, ago)
  Out{List.concat(&2, R.Op, [
      Bool.pick(List<&2, R.Op>, on, Lay.round(c, 6, (y + 1 : U32), 252, 30, 6, T.Th.raise()), Nil{}),
      [D.Draw.disc(c, 19.0, U32.to_f32((y + 16 : U32)), 3.0, dot, 255)],
      Ty.text(ty, 0n, Ty.fit(ty, 0n, title, (252 - 32 - aw - 12 : U32)), c, 32, y, 32, Bool.pick(U32, on, T.Th.text(), T.Th.soft())),
      Ty.text(ty, 2n, ago, c, (252 - aw : U32), y, 32, T.Th.faint())]),
    [Lay.hit(0, y, 264, 32, "select", id)]}

# a sidebar row; a snoozed one shows the time left instead of its age
def Lay.row(+ty: Ty, +t: M.Thread, +st: M.State, +sel: String, +now: Nat, +snoozed: Bool, +c: D.Clip, +y: U32) -> Out:
  match t:
    case M.Thread{+id, _, title, _, +a, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      Lay.row.k(ty, String.eq(id, sel), id, title, Bool.pick(String, snoozed, U.Time.ago(U.Side.until(st, id), now), U.Time.ago(now, a)), Lay.status(U.Side.status(st, t)), c, y)

# rows from y down; answers the output and the next y
type Col is Data:
  Col{out: Out, y: U32}

def Lay.col.cat(o: Out, c: Col) -> Col:
  match c:
    case Col{o2, y}:
      Col{Out.cat(o, o2), y}

def Lay.rows(+ty: Ty, ts: List<&2, M.Thread>, +st: M.State, +sel: String, +now: Nat, +snoozed: Bool, +c: D.Clip, +y: U32) -> Col:
  match ts:
    case Nil{}:
      Col{Out.none(), y}
    case +t <> rest:
      Lay.col.cat(Lay.row(ty, t, st, sel, now, snoozed, c, y), Lay.rows(ty, rest, st, sel, now, snoozed, c, (y + 32 : U32)))

def Lay.col.then(a: Col, k: U32 -> Col) -> Col:
  match a:
    case Col{o, +y}:
      Lay.col.cat(o, k(y))

def Lay.shelf.k(+ty: Ty, open: Bool, +key: String, +label: String, ts: List<&2, M.Thread>, +st: M.State, +sel: String, +now: Nat, +c: D.Clip, +y: U32) -> Col:
  match open:
    case True{}:
      Lay.col.cat(Out{Ty.text(ty, 2n, "▾ " ++ label, c, 16, y, 28, T.Th.dim()), [Lay.hit(0, y, 264, 28, "toggle-settled", key)]},
        Lay.rows(ty, ts, st, sel, now, False{}, c, (y + 28 : U32)))
    case False{}:
      Col{Out{Ty.text(ty, 2n, "▸ " ++ label, c, 16, y, 28, T.Th.faint()), [Lay.hit(0, y, 264, 28, "toggle-settled", key)]}, (y + 28 : U32)}

# a collapsible shelf (Settled, Archived): its name and count, then its rows
# when open; nothing when empty
def Lay.shelf(+ty: Ty, open: Bool, +key: String, +name: String, st: List<&2, M.Thread>, +s: M.State, +sel: String, +now: Nat, +c: D.Clip, +y: U32) -> Col:
  match st:
    case Nil{}:
      Col{Out.none(), y}
    case +t <> +rest:
      Lay.shelf.k(ty, open, key, name ++ " " ++ Nat.show(1n+List.length(&2, M.Thread, rest)), t <> rest, s, sel, now, c, y)

# snoozed threads under a label, soonest to wake first
def Lay.snoozed(+ty: Ty, ts: List<&2, M.Thread>, +st: M.State, +sel: String, +now: Nat, +c: D.Clip, +y: U32) -> Col:
  match ts:
    case Nil{}:
      Col{Out.none(), y}
    case +t <> +rest:
      Lay.col.cat(Out.ops(Ty.text(ty, 2n, "Snoozed", c, 16, y, 28, T.Th.faint())), Lay.rows(ty, t <> rest, st, sel, now, True{}, c, (y + 28 : U32)))

def Lay.project(+ty: Ty, r: U.SRow, +open: Map<&2, Bool>, +st: M.State, +sel: String, +now: Nat, +c: D.Clip, +y: U32) -> Col:
  match r:
    case U.SRow{_, M.Project{+id, title, _, _, _}, M.Shelves{pinned, active, settled, hidden, snoozed}}:
      Lay.col.cat(Out.cat(Out.ops(Ty.text(ty, 2n, Ty.fit(ty, 2n, title, 200), c, 16, (y + 4 : U32), 28, T.Th.dim())),
          Out{Ty.text(ty, 0n, "+", c, 238, (y + 4 : U32), 28, T.Th.faint()), [Lay.hit(230, (y + 4 : U32), 28, 28, "new-thread", id)]}),
        Lay.col.then(Lay.rows(ty, pinned, st, sel, now, False{}, c, (y + 32 : U32)), y1 =>
          Lay.col.then(Lay.rows(ty, active, st, sel, now, False{}, c, y1), y2 =>
            Lay.col.then(Lay.snoozed(ty, snoozed, st, sel, now, c, y2), y3 =>
              Lay.col.then(Lay.shelf(ty, U.Flag.get(open, id), id, "Settled", settled, st, sel, now, c, y3), y4 =>
                Lay.shelf(ty, U.Flag.get(open, "arch:" ++ id), "arch:" ++ id, "Archived", M.Archive.of(hidden), st, sel, now, c, y4))))))

def Lay.projects(+ty: Ty, rs: List<&2, U.SRow>, +open: Map<&2, Bool>, +st: M.State, +sel: String, +now: Nat, +c: D.Clip, +y: U32) -> Col:
  match rs:
    case Nil{}:
      Col{Out.none(), y}
    case r <> t:
      Lay.col.then(Lay.project(ty, r, open, st, sel, now, c, y), y2 => Lay.projects(ty, t, open, st, sel, now, c, (y2 + 8 : U32)))

def Lay.field(+ty: Ty, +c: D.Clip, +x: U32, +y: U32, +w: U32, +text: String, +focused: Bool, +blink: Bool, +caret: Nat, +placeholder: String, +id: String) -> Out:
  +vis = Ty.fit(ty, 2n, text, (w - 16 : U32))
  Out{List.concat(&2, R.Op, [
      Lay.box(c, x, y, w, 28, 6, T.Th.bg(), Bool.pick(U32, focused, T.Th.accent(), T.Th.line())),
      Bool.pick(List<&2, R.Op>, String.is_empty(text), Ty.text(ty, 2n, placeholder, c, (x + 8 : U32), y, 28, T.Th.faint()),
        Ty.text(ty, 2n, vis, c, (x + 8 : U32), y, 28, T.Th.text())),
      Bool.pick(List<&2, R.Op>, Bool.and(focused, blink), [D.Draw.rect(c, (x + 8 + Ty.width(ty, 2n, String.take(vis, caret)) : U32), (y + 7 : U32), 1, 14, T.Th.accent(), 255)], Nil{})]),
    [Lay.hit(x, y, w, 28, "focus", id)]}

def Lay.adding(+ty: Ty, adding: Bool, +path: String, +focused: Bool, +caret: Nat) -> Out:
  match adding:
    case True{}:
      Out.cat(Lay.field(ty, D.Clip.all(), 12, 58, 186, path, focused, True{}, caret, "/path/to/project", "project-path"),
        Lay.button(ty, D.Clip.all(), 204, 58, "Add", T.Th.accent(), "add-project", path))
    case False{}:
      Out.none()

def Lay.col.out(c: Col) -> Out:
  match c:
    case Col{o, _}:
      o

def Links.row.k(sel: Bool, +v: String, +y: U32, m: Map<&2, U32>) -> Map<&2, U32>:
  match sel:
    case True{}:
      Map.set(&2, U32, m, v, (y + 1 : U32))
    case False{}:
      m

# Links in the sidebar
# --------------------
# A message between two threads draws a connector between their rows in
# the sidebar gutter: bright while fresh, fading over 15 minutes.

def Links.rows(hs: List<&2, S.Hit>, m: Map<&2, U32>) -> Map<&2, U32>:
  match hs:
    case Nil{}:
      m
    case S.Hit{_, +y0, _, _, +a, +v} <> t:
      Links.rows(t, Links.row.k(String.eq(a, "select"), v, y0, m))

def Links.y.k(r: Map<&2, U32> & U32) -> U32:
  (_, y) = r
  y

# a row's y plus one (0: not on screen)
def Links.y(+m: Map<&2, U32>, +id: String) -> U32:
  Links.y.k(Map.get(U32, 0, m, id))

def Links.alpha(+age: Nat) -> U32:
  Bool.pick(U32, Nat.is_lt(age, 120n), 255, U32.from_nat(Nat.sub(255n, Nat.div(Nat.mul(Nat.sub(age, 120n), 185n), 780n))))

def Links.one.k(ok: Bool, +ya: U32, +yb: U32, +x: U32, +alpha: U32, +c: D.Clip) -> List<&2, R.Op>:
  match ok:
    case True{}:
      [D.Draw.rect(c, x, (U32.min(ya, yb) + 15 : U32), 2, (U32.max(ya, yb) - U32.min(ya, yb) + 2 : U32), T.Th.accent(), alpha),
       D.Draw.rect(c, x, (ya + 15 : U32), (14 - x : U32), 2, T.Th.accent(), alpha),
       D.Draw.rect(c, x, (yb + 15 : U32), (14 - x : U32), 2, T.Th.accent(), alpha),
       D.Draw.disc(c, 15.0, U32.to_f32((yb + 16 : U32)), 2.5, T.Th.accent(), alpha)]
    case False{}:
      Nil{}

def Links.one(l: U.Link2, +rows: Map<&2, U32>, +k: Nat, +now: Nat, +c: D.Clip) -> List<&2, R.Op>:
  match l:
    case U.Link2{+from, +to, +at}:
      Links.one.k(Bool.and(Bool.and(U32.is_gt(Links.y(rows, from), 0), U32.is_gt(Links.y(rows, to), 0)), Bool.not(String.eq(from, to))),
        (Links.y(rows, from) - 1 : U32), (Links.y(rows, to) - 1 : U32), U32.from_nat(Nat.sub(9n, Nat.mul(Nat.mod(k, 3n), 3n))),
        Links.alpha(Nat.sub(now, at)), c)

def Links.all(ls: List<&2, U.Link2>, +rows: Map<&2, U32>, +k: Nat, +now: Nat, +c: D.Clip) -> List<&2, R.Op>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> t:
      List.append(&2, R.Op, Links.one(l, rows, k, now, c), Links.all(t, rows, 1n+k, now, c))

# the sidebar's rows with their links drawn over them
def Links.over(o: Out, ls: List<&2, U.Link2>, +now: Nat, +c: D.Clip) -> Out:
  match o:
    case Out{os, +hs}:
      Out{List.append(&2, R.Op, os, Links.all(ls, Links.rows(hs, Map.new(&2, U32)), 0n, now, c)), hs}

def Lay.sidebar.k(+ty: Ty, +c: D.Clip, +st: M.State, +sel: String, +open: Map<&2, Bool>, on: Bool, +now: Nat, +adding: Bool, +v: String,
    +sd: U32, +caret: Nat, +focus: String, +path: String, +h: U32, +settings: Bool) -> Out:
  +top = {D.Clip{0, 0, 264, 52} : D.Clip}
  +y0 = {Bool.pick(U32, adding, 96, 60) : U32}
  Out.all([
    Out.ops([D.Draw.rect(D.Clip.all(), 0, 0, 264, h, T.Th.panel(), 255), D.Draw.rect(D.Clip.all(), 263, 0, 1, h, T.Th.line(), 255),
      D.Draw.rect(top, 0, 51, 264, 1, T.Th.line(), 255),
      D.Draw.disc(top, 19.0, 26.0, 3.5, Bool.pick(U32, on, T.Th.ok(), T.Th.bad()), 255)]),
    Out.ops(List.append(&2, R.Op, Ty.text(ty, 1n, "Backplane", top, 30, 0, 52, T.Th.text()),
      Ty.text(ty, 2n, "v" ++ v, top, (30 + Ty.width(ty, 1n, "Backplane") + 8 : U32), 0, 52, T.Th.faint()))),
    Out{Ty.text(ty, 0n, "+", top, 238, 0, 52, T.Th.dim()), [Lay.hit(228, 12, 28, 28, "vw-projo", "")]},
    Lay.adding(ty, adding, path, String.eq(focus, "project-path"), caret),
    Links.over(Lay.col.out(Lay.projects(ty, U.Side.rows(st, now), open, st, sel, now,
      D.Clip{0, y0, 264, (h - 48 : U32)}, U32.sub(y0, sd))), U.Links.recent(st, now), now, D.Clip{0, y0, 264, (h - 48 : U32)}),
    Out{List.append(&2, R.Op, [D.Draw.rect(D.Clip.all(), 0, (h - 48 : U32), 263, 48, T.Th.panel(), 255), D.Draw.rect(D.Clip.all(), 0, (h - 48 : U32), 263, 1, T.Th.line(), 255)],
        Ty.text(ty, 2n, "Settings", D.Clip.all(), 16, (h - 48 : U32), 48, Bool.pick(U32, settings, T.Th.text(), T.Th.dim()))),
      [Lay.hit(0, (h - 48 : U32), 263, 48, "flag", "settings")]}])

# Timeline
# --------

# one laid-out line. kind: 0 text, 1 code, 2 user, 3 activity, 4 gap,
# 5 heading, 6 user padding, 7 footer with a Copy button, 8 code header,
# 9 code bottom, 10 a message sent to another thread, 11 the thread a
# message came from (copy holds the other thread). w is a user bubble's width
type TLine is Data:
  TLine{text: String, color: U32, kind: U32, copy: String, w: U32}

def TL.h.k(k: Nat) -> U32:
  match k:
    case 0n:
      23
    case 1n:
      21
    case 2n:
      23
    case 3n:
      22
    case 4n:
      14
    case 5n:
      28
    case 6n:
      10
    case 7n:
      22
    case 8n:
      32
    case 10n:
      24
    case 11n:
      22
    case _:
      10

def TL.h(+kind: U32) -> U32:
  TL.h.k(U32.to_nat(kind))

# the text of a node list, markup dropped
def Nd.plain(ns: List<&2, N.Node>) -> String:
  match ns:
    case Nil{}:
      ""
    case N.Txt{s} <> t:
      s ++ Nd.plain(t)
    case N.El{"button", _, _, _} <> t:
      Nd.plain(t)
    case N.El{_, _, _, ks} <> t:
      Nd.plain(ks) ++ Nd.plain(t)

def TL.texts(ls: List<&2, String>, +color: U32, +kind: U32) -> List<&2, TLine>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> t:
      TLine{l, color, kind, "", 0} <> TL.texts(t, color, kind)

def TL.bullets(ls: List<&2, String>, first: Bool) -> List<&2, TLine>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> t:
      TLine{Bool.pick(String, first, "•  ", "   ") ++ l, T.Th.soft(), 0, "", 0} <> TL.bullets(t, False{})

def TL.items(+ty: Ty, ns: List<&2, N.Node>, +px: U32) -> List<&2, TLine>:
  match ns:
    case Nil{}:
      Nil{}
    case n <> t:
      List.append(&2, TLine, TL.bullets(Ty.wrap(ty, 3n, Nd.plain([n]), (px - 24 : U32)), True{}), TL.items(ty, t, px))

def TL.code(ls: List<&2, String>) -> List<&2, TLine>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> t:
      TLine{l, T.Th.text(), 1, "", 0} <> TL.code(t)

def TL.trim.k(blank: Bool, +ls: List<&2, String>) -> List<&2, String>:
  match blank:
    case True{}:
      List.take(&2, String, ls, Nat.sub(List.length(&2, String, ls), 1n))
    case False{}:
      ls

# a code block's text without its trailing blank line
def TL.trim(+ls: List<&2, String>) -> List<&2, String>:
  TL.trim.k(String.is_empty(Maybe.default(&2, String, List.last(&2, String, ls), "x")), ls)

def TL.block(+ty: Ty, n: N.Node, +px: U32) -> List<&2, TLine>:
  match n:
    case N.El{"p", _, _, +ks}:
      TL.texts(Ty.wrap(ty, 3n, Nd.plain(ks), px), T.Th.soft(), 0)
    case N.El{"ul", _, _, ks}:
      TL.items(ty, ks, px)
    case N.El{"ol", _, _, ks}:
      TL.items(ty, ks, px)
    case N.El{"div", _, _, +ks}:
      List.concat(&2, TLine, [[TLine{"code", T.Th.faint(), 8, Nd.plain(ks), 0}], TL.code(TL.trim(String.split(Nd.plain(ks), '\n'))), [TLine{"", 0, 9, "", 0}]])
    case N.El{_, _, _, ks}:
      TL.texts(Ty.wrap(ty, 1n, Nd.plain(ks), px), T.Th.text(), 5)
    case N.Txt{s}:
      TL.texts(Ty.wrap(ty, 3n, s, px), T.Th.soft(), 0)

# markdown blocks as lines, a gap between blocks
def TL.blocks(+ty: Ty, ns: List<&2, N.Node>, +px: U32) -> List<&2, TLine>:
  match ns:
    case Nil{}:
      Nil{}
    case n <> Nil{}:
      TL.block(ty, n, px)
    case n <> t:
      List.append(&2, TLine, TL.block(ty, n, px), TLine{"", 0, 4, "", 0} <> TL.blocks(ty, t, px))

def TL.widest(+ty: Ty, ls: List<&2, String>, +acc: U32) -> U32:
  match ls:
    case Nil{}:
      acc
    case l <> t:
      TL.widest(ty, t, U32.max(acc, Ty.width(ty, 3n, l)))

def TL.user(ls: List<&2, String>, +copy: String, first: Bool, +w: U32) -> List<&2, TLine>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> t:
      TLine{l, T.Th.text(), 2, Bool.pick(String, first, copy, ""), w} <> TL.user(t, copy, False{}, w)

def TL.bubble(+ty: Ty, +ls: List<&2, String>, +text: String) -> List<&2, TLine>:
  +w = {(TL.widest(ty, ls, 0) + 40 : U32) : U32}
  List.concat(&2, TLine, [[TLine{"", 0, 6, "", w}], TL.user(ls, text, True{}, w), [TLine{"", 0, 6, "", w}, TLine{"", 0, 4, "", 0}]])

def TL.first_line(+text: String) -> String:
  Maybe.default(&2, String, List.head(&2, String, String.split(text, '\n')), "")

def TL.from.k(none: Bool, +from: String, +st: M.State, +px: U32, +ty: Ty) -> List<&2, TLine>:
  match none:
    case True{}:
      Nil{}
    case False{}:
      [TLine{Ty.fit(ty, 2n, "← from " ++ U.Tasks.title(st, from), px), T.Th.accent(), 11, from, 0}]

def TL.id_of(e: M.Entry) -> String:
  match e:
    case M.Msg{i, _, _, _, _}:
      i
    case M.Act{i, _, _, _, _, _}:
      i

def TL.mine.k(same: Bool, e: M.Entry, rest: List<&2, M.Entry>) -> List<&2, M.Entry>:
  match same:
    case True{}:
      e <> rest
    case False{}:
      rest

def TL.thread_of(e: M.Entry) -> String:
  match e:
    case M.Msg{_, t, _, _, _}:
      t
    case M.Act{_, t, _, _, _, _}:
      t

# a thread's entries and the messages it sent to other threads, oldest first
def TL.mine(es: List<&2, M.Entry>, +th: String, acc: List<&2, M.Entry>) -> List<&2, M.Entry>:
  match es:
    case Nil{}:
      acc
    case +e <> t:
      TL.mine(t, th, TL.mine.k(Bool.or(String.eq(TL.thread_of(e), th), String.eq(M.Link.from(TL.id_of(e)), th)), e, acc))

def TL.height(ls: List<&2, TLine>, +acc: U32) -> U32:
  match ls:
    case Nil{}:
      acc
    case TLine{_, _, +k, _, _} <> t:
      TL.height(t, (acc + TL.h(k) : U32))

def TL.copy(+ty: Ty, +c: D.Clip, +x1: U32, +y: U32, +lh: U32, +copy: String) -> Out:
  Bool.pick(Out, String.is_empty(copy), Out.none(),
    Out{Ty.text(ty, 2n, "Copy", c, (x1 - Ty.width(ty, 2n, "Copy") - 12 : U32), y, lh, T.Th.faint()), [Lay.hit((x1 - 56 : U32), y, 56, lh, "copy", copy)]})

def TL.sides(+c: D.Clip, +x0: U32, +x1: U32, +y: U32, +h: U32) -> List<&2, R.Op>:
  [D.Draw.rect(c, x0, y, 1, h, T.Th.line(), 255), D.Draw.rect(c, (x1 - 1 : U32), y, 1, h, T.Th.line(), 255)]

def TL.draw.k(+ty: Ty, k: Nat, +text: String, +color: U32, +copy: String, +bw: U32, +c: D.Clip, +x0: U32, +x1: U32, +y: U32) -> Out:
  match k:
    case 1n:
      Out.ops(List.concat(&2, R.Op, [[D.Draw.rect(c, x0, y, (x1 - x0 : U32), 21, T.Th.code(), 255)], TL.sides(c, x0, x1, y, 21),
        Ty.text(ty, 4n, text, c, (x0 + 14 : U32), y, 21, color)]))
    case 8n:
      Out.cat(Out.ops(List.concat(&2, R.Op, [[D.Draw.rect(c, x0, y, (x1 - x0 : U32), 32, T.Th.code(), 255), D.Draw.rect(c, x0, y, (x1 - x0 : U32), 1, T.Th.line(), 255),
          D.Draw.rect(c, x0, (y + 31 : U32), (x1 - x0 : U32), 1, T.Th.line(), 255)], TL.sides(c, x0, x1, y, 32),
          Ty.text(ty, 2n, text, c, (x0 + 14 : U32), y, 32, color)])),
        TL.copy(ty, c, x1, y, 32, copy))
    case 9n:
      Out.ops(List.concat(&2, R.Op, [[D.Draw.rect(c, x0, y, (x1 - x0 : U32), 9, T.Th.code(), 255), D.Draw.rect(c, x0, (y + 9 : U32), (x1 - x0 : U32), 1, T.Th.line(), 255)],
        TL.sides(c, x0, x1, y, 10)]))
    case 2n:
      Out.cat(Out.ops(D.Draw.rect(c, (x1 - bw : U32), y, bw, 23, T.Th.raise(), 255) <> Ty.text(ty, 3n, text, c, (x1 - bw + 20 : U32), y, 23, color)),
        Bool.pick(Out, String.is_empty(copy), Out.none(), Out{Nil{}, [Lay.hit((x1 - bw : U32), y, bw, 23, "copy", copy)]}))
    case 6n:
      Out.ops([D.Draw.rect(c, (x1 - bw : U32), y, bw, 10, T.Th.raise(), 255)])
    case 7n:
      TL.copy(ty, c, x1, y, 22, copy)
    case 4n:
      Out.none()
    case 3n:
      Out.ops(Ty.text(ty, 2n, text, c, x0, y, 22, color))
    case 10n:
      Out{List.append(&2, R.Op, [D.Draw.rect(c, x0, (y + 4 : U32), 2, 16, color, 255)], Ty.text(ty, 2n, text, c, (x0 + 10 : U32), y, 24, color)),
        [Lay.hit(x0, y, (Ty.width(ty, 2n, text) + 12 : U32), 24, "select", copy)]}
    case 11n:
      Out{Ty.text(ty, 2n, text, c, (x1 - Ty.width(ty, 2n, text) : U32), y, 22, color), [Lay.hit((x1 - Ty.width(ty, 2n, text) : U32), y, Ty.width(ty, 2n, text), 22, "select", copy)]}
    case 5n:
      Out.ops(Ty.text(ty, 1n, text, c, x0, y, 28, color))
    case _:
      Out.ops(Ty.text(ty, 3n, text, c, x0, y, 23, color))

def TL.draw(+ty: Ty, l: TLine, +c: D.Clip, +x0: U32, +x1: U32, +y: U32) -> Out:
  match l:
    case TLine{text, color, +kind, +copy, +w}:
      TL.draw.k(ty, U32.to_nat(kind), text, color, copy, w, c, x0, x1, y)

# whether the head line starts above y1
def TL.more(ls: List<&2, TLine>, +y: U32, +y1: U32) -> Bool:
  match ls:
    case Nil{}:
      False{}
    case _ <> _:
      U32.is_lt(y, y1)

# draw the lines from y down while they start above y1
def TL.draw_all(+ty: Ty, ls: List<&2, TLine>, more: Bool, +c: D.Clip, +x0: U32, +x1: U32, +y: U32, +y1: U32) -> Out:
  match ls more:
    case TLine{t, co, +k, cp, bw} <> +rest True{}:
      Out.cat(TL.draw(ty, TLine{t, co, k, cp, bw}, c, x0, x1, y), TL.draw_all(ty, rest, TL.more(rest, (y + TL.h(k) : U32), y1), c, x0, x1, (y + TL.h(k) : U32), y1))
    case _ _:
      Out.none()

def TL.live.k(+ty: Ty, empty: Bool, running: Bool, text: String, +px: U32) -> List<&2, TLine>:
  match empty running:
    case False{} _:
      TL.blocks(ty, N.Md.render(text), px)
    case True{} True{}:
      [TLine{"Working…", T.Th.faint(), 3, "", 0}]
    case True{} False{}:
      Nil{}

# Main area
# ---------

def Lay.running(t: M.TurnState) -> Bool:
  match t:
    case M.Running{}:
      True{}
    case _:
      False{}

# a header button's action and value, written "action|value"
def Lay.act(+a: String) -> String:
  Maybe.default(&2, String, List.head(&2, String, String.split(a, '|')), "")

def Lay.val(+a: String) -> String:
  String.join(List.drop(&2, String, String.split(a, '|'), 1n), "|")

# header buttons right to left from x; answers the output
def Lay.buttons(+ty: Ty, bs: List<&2, S.Hit>, +y: U32, +x: U32) -> Out:
  match bs:
    case Nil{}:
      Out.none()
    case S.Hit{_, _, _, _, +label, +action} <> t:
      Out.cat(Lay.button(ty, D.Clip.all(), (x - Lay.button.w(ty, label) : U32), y, label, T.Th.soft(), Lay.act(action), Lay.val(action)),
        Lay.buttons(ty, t, y, (x - Lay.button.w(ty, label) - 8 : U32)))

def Lay.pin(p: Bool) -> S.Hit:
  match p:
    case True{}:
      S.Hit{0, 0, 0, 0, "Pinned", "unpin"}
    case False{}:
      S.Hit{0, 0, 0, 0, "Pin", "pin"}

def Lay.settle(o: M.Override, auto: Bool) -> List<&2, S.Hit>:
  match o auto:
    case M.ForcedSettled{} _:
      [S.Hit{0, 0, 0, 0, "Settled", "unsettle"}]
    case M.NoOverride{} True{}:
      [S.Hit{0, 0, 0, 0, "Settled", "unsettle"}]
    case _ _:
      [S.Hit{0, 0, 0, 0, "Settle", "settle"}]

def Lay.buttons.w(+ty: Ty, bs: List<&2, S.Hit>) -> U32:
  match bs:
    case Nil{}:
      0
    case S.Hit{_, _, _, _, +label, _} <> t:
      (Lay.button.w(ty, label) + 8 + Lay.buttons.w(ty, t) : U32)

def Lay.header.bs(turn: M.TurnState, override: M.Override, +sa: Nat, +ua: Nat, pinned: Bool, panel: Bool, +archived: Bool, +snoozed: Bool) -> List<&2, S.Hit>:
  List.concat(&2, S.Hit, [
    [S.Hit{0, 0, 0, 0, Bool.pick(String, panel, "Hide viewer", "Viewer"), "panel"},
     S.Hit{0, 0, 0, 0, "Diff", "diff"},
     Bool.pick(S.Hit, archived, S.Hit{0, 0, 0, 0, "Unarchive", "unarchive"}, S.Hit{0, 0, 0, 0, "Archive", "archive"}),
     Bool.pick(S.Hit, snoozed, S.Hit{0, 0, 0, 0, "Snoozed", "snooze|off"}, S.Hit{0, 0, 0, 0, "Snooze", "vw-find|snooze"})],
    Lay.settle(override, Nat.is_gt(sa, ua)),
    [Lay.pin(pinned)],
    Bool.pick(List<&2, S.Hit>, Lay.running(turn), [S.Hit{0, 0, 0, 0, "Stop", "interrupt"}], Nil{})])

# the title and branch get what the buttons leave
# s fitted to px, or nothing when there is no room for a few letters
def Lay.fit_or_none(+ty: Ty, +k: Nat, +s: String, +px: U32) -> String:
  Bool.pick(String, U32.is_lt(px, 32), "", Ty.fit(ty, k, s, px))

def Lay.header.k(+ty: Ty, +title: String, +branch: String, +bs: List<&2, S.Hit>, +x0: U32, +x1: U32) -> Out:
  +room = {U32.dim(U32.dim((x1 - x0 : U32), Lay.buttons.w(ty, bs)), 56) : U32}
  +t = Ty.fit(ty, 0n, title, room)
  +tw = Ty.width(ty, 0n, t)
  Out.all([
    Out.ops([D.Draw.rect(D.Clip.all(), x0, 51, (x1 - x0 : U32), 1, T.Th.line(), 255)]),
    Out.ops(Ty.text(ty, 0n, t, D.Clip.all(), (x0 + 24 : U32), 0, 52, T.Th.text())),
    Out.ops(Ty.text(ty, 2n, Lay.fit_or_none(ty, 2n, branch, U32.dim(room, (tw + 12 : U32))), D.Clip.all(), (x0 + 36 + tw : U32), 0, 52, T.Th.faint())),
    Lay.buttons(ty, bs, 12, (x1 - 16 : U32))])

def Lay.header(+ty: Ty, t: M.Thread, +x0: U32, +x1: U32, panel: Bool, +snoozed: Bool) -> Out:
  match t:
    case M.Thread{_, _, +title, _, _, turn, _, +archived, override, +sa, +ua, pinned, _, +branch, _, _, _, _, _, _, _}:
      Lay.header.k(ty, title, branch, Lay.header.bs(turn, override, sa, ua, pinned, panel, archived, snoozed), x0, x1)

def Lay.lines(+ty: Ty, ls: List<&2, String>, +c: D.Clip, +x: U32, +y: U32) -> Out:
  match ls:
    case Nil{}:
      Out.none()
    case l <> t:
      Out.cat(Out.ops(Ty.text(ty, 3n, l, c, x, y, 23, T.Th.text())), Lay.lines(ty, t, c, x, (y + 23 : U32)))

def Picker.rows(+ty: Ty, ms: List<&2, String>, +cur: String, +info: String, +prov: String, +x: U32, +y: U32, +w: U32) -> Out:
  match ms:
    case Nil{}:
      Out.none()
    case +m <> t:
      Out.cat(Out{List.concat(&2, R.Op, [
          Bool.pick(List<&2, R.Op>, String.eq(m, cur), Lay.round(D.Clip.all(), (x + 4 : U32), y, (w - 8 : U32), 28, 5, T.Th.sel()), Nil{}),
          Ty.text(ty, 2n, Bool.pick(String, String.is_empty(m), "default", m), D.Clip.all(), (x + 14 : U32), y, 28, Bool.pick(U32, String.eq(m, cur), T.Th.text(), T.Th.soft())),
          Ty.text(ty, 2n, Ty.fit(ty, 2n, U.Models.label_of(info, prov, m), (w - 150 : U32)), D.Clip.all(), (x + 130 : U32), y, 28, T.Th.faint())]),
          [Lay.hit(x, y, w, 28, "model", m)]},
        Picker.rows(ty, t, cur, info, prov, x, (y + 28 : U32), w))

# reasoning effort chips, left to right
def Picker.efforts(+ty: Ty, es: List<&2, String>, +cur: String, +x: U32, +y: U32) -> Out:
  match es:
    case Nil{}:
      Out.none()
    case +e <> t:
      Out.cat(Lay.chip(ty, x, y, U.Effort.name(e), String.eq(e, cur), "effort", e),
        Picker.efforts(ty, t, cur, (x + Lay.button.w(ty, U.Effort.name(e)) + 4 : U32), y))

# the model menu, opening upward from the composer's footer: the effort
# chips on top (where the provider has them), then the models
def Lay.picker(+ty: Ty, open: Bool, +ms: List<&2, String>, +cur: String, +info: String, +prov: String, +x: U32, +bottom: U32, +es: List<&2, String>, +effort: String) -> Out:
  +n = {U32.from_nat(List.length(&2, String, ms)) : U32}
  +eh = {Bool.pick(U32, List.is_empty(&2, String, es), 0, 36) : U32}
  +h = {(n * 28 + 8 + eh : U32) : U32}
  Out.when(Bool.and(open, U32.is_gt((n + eh : U32), 0)),
    Out.all([Out.ops(Lay.box(D.Clip.all(), x, (bottom - h : U32), 460, h, 8, T.Th.panel(), T.Th.line())),
      Picker.efforts(ty, es, effort, (x + 4 : U32), (bottom - h + 4 : U32)),
      Picker.rows(ty, ms, cur, info, prov, x, (bottom - h + 4 + eh : U32), 460)]))

def Skills.row(+ty: Ty, +n: String, +d: String, +x: U32, +y: U32, +w: U32, first: Bool) -> Out:
  +nw = Ty.width(ty, 2n, "$" ++ n)
  Out{List.concat(&2, R.Op, [Bool.pick(List<&2, R.Op>, first, Lay.round(D.Clip.all(), (x + 4 : U32), y, (w - 8 : U32), 28, 5, T.Th.sel()), Nil{}),
      Ty.text(ty, 2n, "$" ++ n, D.Clip.all(), (x + 14 : U32), y, 28, T.Th.text()),
      Ty.text(ty, 2n, Lay.fit_or_none(ty, 2n, d, U32.dim(w, (nw + 48 : U32))), D.Clip.all(), (x + 30 + nw : U32), y, 28, T.Th.dim())]),
    [Lay.hit(x, y, w, 28, "skill", n)]}

def Skills.rows(+ty: Ty, rs: List<&2, U.SkillRow>, +x: U32, +y: U32, +w: U32, first: Bool) -> Out:
  match rs:
    case Nil{}:
      Out.none()
    case U.SkillRow{+n, +d} <> t:
      Out.cat(Skills.row(ty, n, d, x, y, w, first), Skills.rows(ty, t, x, (y + 28 : U32), w, False{}))

# the skills a `$` being typed may complete to, above the composer (Tab
# or Enter takes the first, highlighted)
def Lay.skills(+ty: Ty, +rs: List<&2, U.SkillRow>, +x0: U32, +x1: U32, +bottom: U32) -> Out:
  +n = {U32.from_nat(List.length(&2, U.SkillRow, rs)) : U32}
  +h = {(n * 28 + 8 : U32) : U32}
  Out.when(U32.is_gt(n, 0),
    Out.cat(Out.ops(Lay.box(D.Clip.all(), x0, (bottom - h : U32), (x1 - x0 : U32), h, 8, T.Th.panel(), T.Th.line())),
      Skills.rows(ty, rs, x0, (bottom - h + 4 : U32), (x1 - x0 : U32), True{})))

def Lay.composer(+ty: Ty, +draft: String, +caret: Nat, +focused: Bool, +blink: Bool, +x0: U32, +x1: U32, +h: U32, running: Bool, +models: String, +picking: Bool, +ms: List<&2, String>, +model: String, +info: String, +prov: String,
    +es: List<&2, String>, +effort: String, +rs: List<&2, U.SkillRow>) -> Out:
  +tw = {(x1 - x0 - 40 : U32) : U32}
  +ls = Ty.wrap(ty, 3n, draft, tw)
  +shown = List.drop(&2, String, ls, Nat.sub(List.length(&2, String, ls), 2n))
  +before = Ty.wrap(ty, 3n, String.take(draft, caret), tw)
  +row = Nat.sub(Nat.sub(List.length(&2, String, before), 1n), Nat.sub(List.length(&2, String, ls), List.length(&2, String, shown)))
  +cx = Ty.width(ty, 3n, Maybe.default(&2, String, List.last(&2, String, before), ""))
  +y = {(h - 120 : U32) : U32}
  +send = Bool.pick(String, running, "Queue", "Send")
  Out.all([
    Out.ops(Lay.box(D.Clip.all(), x0, y, (x1 - x0 : U32), 100, 10, T.Th.panel(), Bool.pick(U32, focused, T.Th.focus(), T.Th.line()))),
    Bool.pick(Out, String.is_empty(draft),
      Out.ops(Ty.text(ty, 3n, "Ask anything, @tag files, $skill, or describe the change", D.Clip.all(), (x0 + 16 : U32), (y + 10 : U32), 23, T.Th.faint())),
      Lay.lines(ty, shown, D.Clip{(x0 + 1 : U32), (y + 1 : U32), (x1 - 1 : U32), (y + 60 : U32)}, (x0 + 16 : U32), (y + 10 : U32))),
    Bool.pick(Out, Bool.and(focused, blink), Out.ops([D.Draw.rect(D.Clip.all(), (x0 + 16 + cx : U32), (y + 14 + (U32.from_nat(row) * 23 : U32) : U32), 1, 16, T.Th.accent(), 255)]), Out.none()),
    Out{Nil{}, [Lay.hit(x0, y, (x1 - x0 : U32), 64, "focus", "composer")]},
    Out{Ty.text(ty, 2n, models ++ "  ▾", D.Clip.all(), (x0 + 16 : U32), (y + 64 : U32), 28, T.Th.dim()), [Lay.hit((x0 + 8 : U32), (y + 64 : U32), (Ty.width(ty, 2n, models) + 36 : U32), 28, "flag", "models")]},
    Lay.button(ty, D.Clip.all(), (x1 - 12 - Lay.button.w(ty, send) : U32), (y + 64 : U32), send, T.Th.accent(), "send", ""),
    Lay.picker(ty, picking, "" <> ms, model, info, prov, (x0 + 8 : U32), (y + 64 : U32), es, effort),
    Lay.skills(ty, rs, x0, x1, (y - 4 : U32))])

# whether the head line ends above top (it is out of view)
def TL.above(ls: List<&2, TLine>, +y: U32, +top: U32) -> Bool:
  match ls:
    case TLine{_, _, +k, _, _} <> _:
      U32.is_lt((y + TL.h(k) : U32), top)
    case Nil{}:
      False{}

# the lines from the first one that reaches the view
def Lay.skip(ls: List<&2, TLine>, above: Bool, +y: U32, +top: U32) -> List<&2, TLine>:
  match ls above:
    case TLine{_, _, +k, _, _} <> +rest True{}:
      Lay.skip(rest, TL.above(rest, (y + TL.h(k) : U32), top), (y + TL.h(k) : U32), top)
    case _ _:
      ls

def Lay.skip_y(ls: List<&2, TLine>, +y: U32, +top: U32) -> U32:
  match ls:
    case Nil{}:
      y
    case TLine{_, _, +k, _, _} <> rest:
      Bool.pick(U32, U32.is_lt((y + TL.h(k) : U32), top), Lay.skip_y(rest, (y + TL.h(k) : U32), top), y)

# the timeline sits between top and the composer, pinned to the bottom;
# sc scrolls up into history
# the lines from the first one still (partly) below `off` pixels, and how
# many pixels the skipped lines took
def TL.drop.more(ls: List<&2, TLine>, +acc: U32, +off: U32) -> Bool:
  match ls:
    case TLine{_, _, +k, _, _} <> _:
      U32.is_le((acc + TL.h(k) : U32), off)
    case Nil{}:
      False{}

def TL.drop(ls: List<&2, TLine>, more: Bool, +acc: U32, +off: U32) -> List<&2, TLine>:
  match ls more:
    case TLine{_, _, +k, _, _} <> +rest True{}:
      TL.drop(rest, TL.drop.more(rest, (acc + TL.h(k) : U32), off), (acc + TL.h(k) : U32), off)
    case _ _:
      ls

def TL.drop.acc(ls: List<&2, TLine>, more: Bool, +acc: U32, +off: U32) -> U32:
  match ls more:
    case TLine{_, _, +k, _, _} <> +rest True{}:
      TL.drop.acc(rest, TL.drop.more(rest, (acc + TL.h(k) : U32), off), (acc + TL.h(k) : U32), off)
    case _ _:
      acc

# the timeline sits between top and the composer, pinned to the bottom;
# sc scrolls up into history. `off` is how many pixels of it are hidden
# above the view (never negative: all arithmetic stays unsigned-safe)
def Lay.timeline(+ty: Ty, +ls: List<&2, TLine>, +x0: U32, +x1: U32, +top: U32, +h: U32, +sc: U32, chrome: Out) -> Out:
  +bot = {(h - 132 : U32) : U32}
  +view = {U32.dim(bot, (top + 16 : U32)) : U32}
  +total = TL.height(ls, 0)
  +over = {U32.dim(total, view) : U32}
  +off = {U32.dim(over, U32.min(sc, over)) : U32}
  +rest = TL.drop(ls, TL.drop.more(ls, 0, off), 0, off)
  +acc = TL.drop.acc(ls, TL.drop.more(ls, 0, off), 0, off)
  +ry = {((top + 16 + acc : U32) - off : U32) : U32}
  Out.cat(TL.draw_all(ty, rest, TL.more(rest, ry, bot), D.Clip{x0, top, x1, bot}, x0, x1, ry, bot), chrome)

# Subagents
# ---------

def Task.color(s: M.TaskState) -> U32:
  match s:
    case M.TaskQueued{}:
      T.Th.faint()
    case M.TaskRunning{}:
      T.Th.accent()
    case M.TaskDone{}:
      T.Th.ok()
    case M.TaskFailed{}:
      T.Th.bad()
    case M.TaskCancelled{}:
      T.Th.warn()

def Tasks.row(+ty: Ty, t: M.Task, +st: M.State, +x0: U32, +x1: U32, +y: U32) -> Out:
  match t:
    case M.Task{_, _, +child, _, +s, _, _, +pr, +mo}:
      +word = U.Task.word(s)
      +who = U.Models.label(pr, mo)
      +ww = Ty.width(ty, 2n, word)
      +whw = Ty.width(ty, 2n, who)
      Out{List.concat(&2, R.Op, [
          [D.Draw.disc(D.Clip.all(), U32.to_f32((x0 + 14 : U32)), U32.to_f32((y + 14 : U32)), 3.0, Task.color(s), 255)],
          Ty.text(ty, 2n, who, D.Clip.all(), (x0 + 26 : U32), y, 28, T.Th.dim()),
          Ty.text(ty, 0n, Ty.fit(ty, 0n, U.Tasks.title(st, child), (x1 - x0 - whw - ww - 64 : U32)), D.Clip.all(), (x0 + 38 + whw : U32), y, 28, T.Th.soft()),
          Ty.text(ty, 2n, word, D.Clip.all(), (x1 - ww - 12 : U32), y, 28, Task.color(s))]),
        [Lay.hit(x0, y, (x1 - x0 : U32), 28, "select", child)]}

def Tasks.rows(+ty: Ty, ts: List<&2, M.Task>, +st: M.State, +x0: U32, +x1: U32, +y: U32) -> Out:
  match ts:
    case Nil{}:
      Out.none()
    case t <> rest:
      Out.cat(Tasks.row(ty, t, st, x0, x1, y), Tasks.rows(ty, rest, st, x0, x1, (y + 28 : U32)))

# the subagent viewer: every task this thread delegated, its model and its
# state; click one to open its thread
def Lay.tasks(+ty: Ty, +ts: List<&2, M.Task>, +st: M.State, +x0: U32, +x1: U32, +y: U32) -> Out:
  +n = {U32.from_nat(List.length(&2, M.Task, ts)) : U32}
  Out.when(U32.is_gt(n, 0),
    Out.all([
      Out.ops(Lay.box(D.Clip.all(), x0, y, (x1 - x0 : U32), (n * 28 + 36 : U32), 8, T.Th.panel(), T.Th.line())),
      Out.ops(Ty.text(ty, 2n, "Subagents", D.Clip.all(), (x0 + 12 : U32), y, 32, T.Th.faint())),
      Tasks.rows(ty, ts, st, x0, x1, (y + 30 : U32))]))

def Tasks.height(+ts: List<&2, M.Task>) -> U32:
  +n = {U32.from_nat(List.length(&2, M.Task, ts)) : U32}
  Bool.pick(U32, U32.is_eq(n, 0), 0, (n * 28 + 48 : U32))

def Lay.parent.k(+ty: Ty, +p: String, +st: M.State, +x0: U32, +y: U32) -> Out:
  +label = "← delegated by " ++ U.Tasks.title(st, p)
  Out.when(Bool.not(String.is_empty(p)),
    Out{Ty.text(ty, 2n, label, D.Clip.all(), x0, y, 28, T.Th.accent()), [Lay.hit(x0, y, (Ty.width(ty, 2n, label) + 8 : U32), 28, "select", p)]})

# a child thread links back to its parent
def Lay.parent(+ty: Ty, +st: M.State, +thread: String, +x0: U32, +y: U32) -> Out:
  Lay.parent.k(ty, U.Tasks.parent(st, thread), st, x0, y)

# Asks: what the agent waits on the user for
# ------------------------------------------

def Ask.plan_lines(+ty: Ty, +text: String, +px: U32) -> List<&2, String>:
  List.take(&2, String, Ty.wrap(ty, 4n, text, px), 8n)

def Ask.h(+ty: Ty, a: M.Ask, +px: U32) -> U32:
  match a:
    case M.Ask{_, _, +k, _, +d, _, _, _}:
      Bool.pick(U32, String.eq(k, "plan"), (U32.from_nat(List.length(&2, String, Ask.plan_lines(ty, d, px))) * 21 + 76 : U32), 76)

def Asks.h(+ty: Ty, as: List<&2, M.Ask>, +px: U32) -> U32:
  match as:
    case Nil{}:
      0
    case a <> t:
      (Ask.h(ty, a, px) + 8 + Asks.h(ty, t, px) : U32)

def Ask.buttons(+ty: Ty, bs: List<&2, S.Hit>, +y: U32, +x: U32) -> Out:
  match bs:
    case Nil{}:
      Out.none()
    case S.Hit{_, _, _, _, +label, +value} <> t:
      Out.cat(Lay.button(ty, D.Clip.all(), (x - Lay.button.w(ty, label) : U32), y, label, T.Th.soft(), "answer", value),
        Ask.buttons(ty, t, y, (x - Lay.button.w(ty, label) - 8 : U32)))

def Ask.opts(ls: List<&2, String>, +id: String) -> List<&2, S.Hit>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      S.Hit{0, 0, 0, 0, l, id ++ "|" ++ l} <> Ask.opts(t, id)

def Lay.plan.lines(+ty: Ty, ls: List<&2, String>, +x0: U32, +y: U32) -> Out:
  match ls:
    case Nil{}:
      Out.none()
    case l <> t:
      Out.cat(Out.ops(Ty.text(ty, 3n, l, D.Clip.all(), (x0 + 14 : U32), y, 21, T.Th.soft())), Lay.plan.lines(ty, t, x0, (y + 21 : U32)))

# the buttons of an ask, right to left
def Ask.choices(+k: String, +id: String, +o: String, +draft: String) -> List<&2, S.Hit>:
  Bool.pick(List<&2, S.Hit>, String.eq(k, "plan"), [S.Hit{0, 0, 0, 0, "Implement", id ++ "|implement"}, S.Hit{0, 0, 0, 0, "Dismiss", id ++ "|dismiss"}],
    Bool.pick(List<&2, S.Hit>, String.eq(k, "input"),
      List.append(&2, S.Hit, Bool.pick(List<&2, S.Hit>, String.is_empty(String.trim(draft)), [S.Hit{0, 0, 0, 0, "Dismiss", id ++ "|"}], [S.Hit{0, 0, 0, 0, "Answer with draft", id ++ "|" ++ String.trim(draft)}]),
        List.reverse(&2, S.Hit, Ask.opts(String.split(o, '\n'), id))),
      [S.Hit{0, 0, 0, 0, "Allow", id ++ "|accept"}, S.Hit{0, 0, 0, 0, "Allow for session", id ++ "|session"}, S.Hit{0, 0, 0, 0, "Deny", id ++ "|decline"}]))

def Ask.card(+ty: Ty, a: M.Ask, +draft: String, +x0: U32, +x1: U32, +y: U32) -> Out:
  match a:
    case M.Ask{+id, _, +k, +tool, +d, +o, _, _}:
      +h = Ask.h(ty, M.Ask{id, "", k, tool, d, o, True{}, ""}, (x1 - x0 - 32 : U32))
      +head = Bool.pick(String, String.eq(k, "plan"), "Proposed plan", Bool.pick(String, String.eq(k, "input"), "The agent asks", "Allow " ++ tool ++ "?"))
      Out.all([
        Out.ops(Lay.box(D.Clip.all(), x0, y, (x1 - x0 : U32), h, 0, T.Th.panel(), T.Th.warn())),
        Out.ops(Ty.text(ty, 2n, head, D.Clip.all(), (x0 + 14 : U32), (y + 4 : U32), 22, T.Th.warn())),
        Bool.pick(Out, String.eq(k, "plan"), Lay.plan.lines(ty, Ask.plan_lines(ty, d, (x1 - x0 - 32 : U32)), x0, (y + 28 : U32)),
          Out.ops(Ty.text(ty, Bool.pick(Nat, String.eq(k, "approval"), 4n, 3n), Ty.fit(ty, 4n, d, (x1 - x0 - 28 : U32)), D.Clip.all(), (x0 + 14 : U32), (y + 26 : U32), 22, T.Th.text()))),
        Ask.buttons(ty, Ask.choices(k, id, o, draft), (y + h - 36 : U32), (x1 - 12 : U32))])

def Lay.asks(+ty: Ty, as: List<&2, M.Ask>, +draft: String, +x0: U32, +x1: U32, +y: U32) -> Out:
  match as:
    case Nil{}:
      Out.none()
    case +a <> t:
      Out.cat(Ask.card(ty, a, draft, x0, x1, y), Lay.asks(ty, t, draft, x0, x1, (y + Ask.h(ty, a, (x1 - x0 - 32 : U32)) + 8 : U32)))

# messages waiting for the running turn (stored on the server)
def Lay.queued(+ty: Ty, +q: String, +x0: U32, +x1: U32, +h: U32) -> Out:
  +label = "Queued: " ++ Ty.fit(ty, 2n, String.join(String.split(q, '\n'), " "), (x1 - x0 - 260 : U32)) ++ " · sends when this turn ends"
  Out.when(Bool.not(String.is_empty(q)),
    Out.ops(List.append(&2, R.Op, Lay.box(D.Clip.all(), x0, (h - 150 : U32), (x1 - x0 : U32), 26, 0, T.Th.raise(), T.Th.line()),
      Ty.text(ty, 2n, label, D.Clip.all(), (x0 + 12 : U32), (h - 150 : U32), 26, T.Th.dim()))))

def Lay.empty(+ty: Ty, +x0: U32, +x1: U32, +h: U32, +n: Nat) -> Out:
  +msg = Bool.pick(String, Nat.is_eq(n, 0n), "Add a project with + to start.", "Pick a thread, or start one with + next to a project.")
  Out.ops(Ty.text(ty, 3n, msg, D.Clip.all(), (x0 + U32.shr((x1 - x0 - Ty.width(ty, 3n, msg) : U32)) : U32), (U32.shr(h) - 12 : U32), 23, T.Th.faint()))

# Settings
# --------

def Set.head(+ty: Ty, +label: String, +x: U32, +y: U32) -> Out:
  Out.ops(Ty.text(ty, 1n, label, D.Clip.all(), x, y, 28, T.Th.text()))

# a row whose right `rw` pixels hold controls
def Set.row.r(+ty: Ty, +label: String, +note: String, +x: U32, +y: U32, +w: U32, +rw: U32) -> Out:
  Out.ops(List.append(&2, R.Op, Ty.text(ty, 0n, Ty.fit(ty, 0n, label, U32.dim(w, (32 + rw : U32))), D.Clip.all(), (x + 16 : U32), y, 28, T.Th.soft()),
    Ty.text(ty, 2n, Ty.fit(ty, 2n, note, U32.dim(w, (32 + rw : U32))), D.Clip.all(), (x + 16 : U32), (y + 24 : U32), 20, T.Th.faint())))

def Set.row(+ty: Ty, +label: String, +note: String, +x: U32, +y: U32, +w: U32) -> Out:
  Set.row.r(ty, label, note, x, y, w, 0)

def Set.card(+x: U32, +y: U32, +w: U32, +h: U32) -> Out:
  Out.ops(Lay.box(D.Clip.all(), x, y, w, h, 10, T.Th.panel(), T.Th.line()))

def Set.days(+ty: Ty, +d: String, +x: U32, +y: U32) -> Out:
  +n = {Maybe.default(&2, U32, U32.read(d), 3) : U32}
  Out.all([
    Lay.button(ty, D.Clip.all(), x, y, "−", T.Th.soft(), "setting", "settle.days=" ++ U32.show(U32.max((n - 1 : U32), 1))),
    Out.ops(Ty.text(ty, 0n, U32.show(n) ++ Bool.pick(String, U32.is_eq(n, 1), " day", " days"), D.Clip.all(), (x + 44 : U32), y, 28, T.Th.text())),
    Lay.button(ty, D.Clip.all(), (x + 116 : U32), y, "+", T.Th.soft(), "setting", "settle.days=" ++ U32.show(U32.min((n + 1 : U32), 90)))])

# what the chosen model is ("opus: Opus 5.5 · claude-opus-5-5")
def Set.model_line(+label: String, +m: String) -> String:
  Bool.pick(String, String.is_empty(m), "default: " ++ label, m ++ Bool.pick(String, String.is_empty(label), "", ": " ++ label))

def Set.cli(+v: String, +prov: String) -> String:
  Bool.pick(String, String.is_empty(v), prov ++ " is not installed", v)

def Set.label(+v: String) -> String:
  Bool.pick(String, String.is_empty(v), "default", v)

def Set.wraps(+ty: Ty, +v: String, +x0: U32, +x1: U32, +x: U32) -> Bool:
  Bool.and(U32.is_gt(x, x0), U32.is_gt((x + Lay.button.w(ty, Set.label(v)) : U32), x1))

# chips from (x, y), wrapping at x1 back to x0 on the next row
def Set.chips(+ty: Ty, xs: List<&2, String>, +cur: String, +key: String, +x0: U32, +x1: U32, +x: U32, +y: U32) -> Out:
  match xs:
    case Nil{}:
      Out.none()
    case +v <> t:
      +cx = {Bool.pick(U32, Set.wraps(ty, v, x0, x1, x), x0, x) : U32}
      +cy = {Bool.pick(U32, Set.wraps(ty, v, x0, x1, x), (y + 34 : U32), y) : U32}
      Out.cat(Lay.chip(ty, cx, cy, Set.label(v), String.eq(v, cur), "setting", key ++ "=" ++ v),
        Set.chips(ty, t, cur, key, x0, x1, (cx + Lay.button.w(ty, Set.label(v)) + 8 : U32), cy))

# how many extra rows the chips take
def Set.rows(+ty: Ty, xs: List<&2, String>, +x0: U32, +x1: U32, +x: U32) -> U32:
  match xs:
    case Nil{}:
      0
    case +v <> t:
      +cx = {Bool.pick(U32, Set.wraps(ty, v, x0, x1, x), x0, x) : U32}
      (Bool.pick(U32, Set.wraps(ty, v, x0, x1, x), 1, 0) + Set.rows(ty, t, x0, x1, (cx + Lay.button.w(ty, Set.label(v)) + 8 : U32)) : U32)

def Set.fork(+ty: Ty, +fork: String, +x: U32, +y: U32) -> Out:
  Bool.pick(Out, String.is_empty(fork),
    Lay.button(ty, D.Clip.all(), x, y, "Install Backplane KiCad", T.Th.accent(), "kicad-install", ""),
    Out.ops(Ty.text(ty, 2n, "Backplane KiCad " ++ fork ++ ", IPC available", D.Clip.all(), x, y, 28, T.Th.ok())))

# the settings screen, in place of the thread
def Lay.settings(+ty: Ty, +st: M.State, +info: Map<&2, String>, +v: String, +note: String, +x0: U32, +x1: U32, +h: U32) -> Out:
  +w = {U32.min((x1 - x0 - 64 : U32), 720) : U32}
  +x = {(x0 + U32.shr((x1 - x0 - w : U32)) : U32) : U32}
  +prov = M.Setting.get(st, "agent.provider", "claude")
  +ipc = M.Setting.get(st, "kicad.ipc", "on")
  +ms = {"" <> U.Models.list(U.Str.get(info, "models"), prov) : List<&2, String>}
  +dy = {(Set.rows(ty, ms, (x + 16 : U32), (x + w - 16 : U32), (x + 16 : U32)) * 34 + 26 : U32) : U32}
  Out.all([
    Out.ops([D.Draw.rect(D.Clip.all(), x0, 51, (x1 - x0 : U32), 1, T.Th.line(), 255)]),
    Out.ops(Ty.text(ty, 0n, "Settings", D.Clip.all(), (x0 + 24 : U32), 0, 52, T.Th.text())),
    Lay.button(ty, D.Clip.all(), (x1 - 16 - Lay.button.w(ty, "Close") : U32), 12, "Close", T.Th.soft(), "flag", "settings"),
    Set.head(ty, "Threads", x, 76),
    Set.card(x, 108, w, 64),
    Set.row.r(ty, "Settle after", "Threads idle this long move to Settled. They stay saved.", x, 110, w, 190),
    Set.days(ty, M.Setting.get(st, "settle.days", "3"), (x + w - 172 : U32), 126),
    Set.head(ty, "Agents", x, 192),
    Set.card(x, 224, w, (124 + dy : U32)),
    Set.row(ty, "Provider and model for new threads", Set.cli(U.Models.cli(U.Str.get(info, "models"), prov), prov) ++ ". Each thread keeps its own; change it from the composer.", x, 226, w),
    Set.chips(ty, ["claude", "codex", "grok"], prov, "agent.provider", (x + 16 : U32), (x + w - 16 : U32), (x + 16 : U32), 274),
    Set.chips(ty, ms, M.Setting.get(st, "agent.model", ""), "agent.model", (x + 16 : U32), (x + w - 16 : U32), (x + 16 : U32), 308),
    Out.ops(Ty.text(ty, 2n, Ty.fit(ty, 2n, Set.model_line(U.Models.label_of(U.Str.get(info, "models"), prov, M.Setting.get(st, "agent.model", "")), M.Setting.get(st, "agent.model", "")), (w - 32 : U32)),
      D.Clip.all(), (x + 16 : U32), (318 + dy : U32), 24, T.Th.dim())),
    Set.head(ty, "KiCad", x, (368 + dy : U32)),
    Set.card(x, (400 + dy : U32), w, 150),
    Set.row(ty, "KiCad CLI", U.Str.get(info, "kicad.cli"), x, (402 + dy : U32), w),
    Set.fork(ty, U.Str.get(info, "kicad.fork"), (x + 16 : U32), (450 + dy : U32)),
    Set.row.r(ty, "KiCad IPC", "Agents may drive KiCad through the fork's api-server (NNG/protobuf).", x, (486 + dy : U32), w, 140),
    Lay.chip(ty, (x + w - 120 : U32), (500 + dy : U32), "On", String.eq(ipc, "on"), "setting", "kicad.ipc=on"),
    Lay.chip(ty, (x + w - 70 : U32), (500 + dy : U32), "Off", String.eq(ipc, "off"), "setting", "kicad.ipc=off"),
    Set.head(ty, "Network and updates", x, (570 + dy : U32)),
    Set.card(x, (602 + dy : U32), w, 164),
    Set.row(ty, "Tailscale: " ++ U.Str.get(info, "tailnet"), "Listening on " ++ U.Str.get(info, "listen") ++ ". Start with --tailscale to serve your tailnet.", x, (604 + dy : U32), w),
    Set.row.r(ty, "Backplane " ++ v, Bool.pick(String, String.is_empty(note), "Up to date, checked hourly.", note), x, (656 + dy : U32), w, 150),
    Bool.pick(Out, String.starts_with(note, "update "), Lay.button(ty, D.Clip.all(), (x + w - 16 - Lay.button.w(ty, "Install update") : U32), (666 + dy : U32), "Install update", T.Th.accent(), "update", ""),
      Lay.button(ty, D.Clip.all(), (x + w - 16 - Lay.button.w(ty, "Check now") : U32), (666 + dy : U32), "Check now", T.Th.soft(), "update-check", "")),
    Set.row.r(ty, "Update channel", "Stable takes releases; nightly also takes the daily builds.", x, (708 + dy : U32), w, 190),
    Lay.chip(ty, (x + w - 16 - Lay.button.w(ty, "Nightly") - 6 - Lay.button.w(ty, "Stable") : U32), (722 + dy : U32), "Stable", Bool.not(String.eq(M.Setting.get(st, "update.channel", "stable"), "nightly")), "setting", "update.channel=stable"),
    Lay.chip(ty, (x + w - 16 - Lay.button.w(ty, "Nightly") : U32), (722 + dy : U32), "Nightly", String.eq(M.Setting.get(st, "update.channel", "stable"), "nightly"), "setting", "update.channel=nightly")])

# Terminal
# --------

def Term.runs(+ty: Ty, rs: List<&2, VT.VRun>, +cw: U32, +c: D.Clip, +x: U32, +y: U32) -> List<&2, R.Op>:
  match rs:
    case Nil{}:
      Nil{}
    case VT.VRun{+t, +fg, +bg, +bold, _} <> rest:
      +w = {(U32.from_nat(String.length(t)) * cw : U32) : U32}
      List.concat(&2, R.Op, [
        Bool.pick(List<&2, R.Op>, U32.is_eq(bg, VT.Vt.bg()), Nil{}, [D.Draw.rect(c, x, y, w, 18, bg, 255)]),
        Ty.text(ty, Bool.pick(Nat, bold, 1n, 4n), t, c, x, y, 18, fg),
        Term.runs(ty, rest, cw, c, (x + w : U32), y)])

def Term.lines(+ty: Ty, ls: List<&2, VT.VLine>, +cw: U32, +c: D.Clip, +x: U32, +y: U32) -> List<&2, R.Op>:
  match ls:
    case Nil{}:
      Nil{}
    case VT.VLine{rs} <> t:
      List.append(&2, R.Op, Term.runs(ty, rs, cw, c, x, y), Term.lines(ty, t, cw, c, x, (y + 18 : U32)))

def Term.cursor(cur: VT.VCur, +focused: Bool, +blink: Bool, +cw: U32, +c: D.Clip, +x: U32, +y: U32) -> List<&2, R.Op>:
  match cur:
    case VT.VCur{+cx, +cy, True{}}:
      [D.Draw.rect(c, (x + cx * cw : U32), (y + cy * 18 : U32), Bool.pick(U32, focused, cw, 2), 18, T.Th.accent(), Bool.pick(U32, focused, Bool.pick(U32, blink, 150, 0), 255))]
    case VT.VCur{_, _, False{}}:
      Nil{}

# the thread's terminal (ctrl+j), a shell in the thread's directory
def Lay.term(+ty: Ty, +v: VT.Vt, +x0: U32, +x1: U32, +y0: U32, +h: U32, +focused: Bool, +blink: Bool) -> Out:
  +cw = {U32.max(Ty.width(ty, 4n, "0"), 1) : U32}
  +c = {D.Clip{x0, (y0 + 28 : U32), x1, h} : D.Clip}
  Out.all([
    Out.ops([D.Draw.rect(D.Clip.all(), x0, y0, (x1 - x0 : U32), (h - y0 : U32), VT.Vt.bg(), 255),
      D.Draw.rect(D.Clip.all(), x0, y0, (x1 - x0 : U32), 1, Bool.pick(U32, focused, T.Th.focus(), T.Th.line()), 255)]),
    Out.ops(Ty.text(ty, 2n, "Terminal" ++ Bool.pick(String, String.is_empty(VT.Vt.title(v)), "", "  ·  " ++ VT.Vt.title(v)), D.Clip.all(), (x0 + 16 : U32), y0, 28, T.Th.faint())),
    Out.ops(Ty.text(ty, 2n, "ctrl+j", D.Clip.all(), (x1 - 16 - Ty.width(ty, 2n, "ctrl+j") : U32), y0, 28, T.Th.faint())),
    Out{List.append(&2, R.Op, Term.lines(ty, VT.Vt.lines(v, 0n), cw, c, (x0 + 12 : U32), (y0 + 30 : U32)), Term.cursor(VT.Vt.cursor(v), focused, blink, cw, c, (x0 + 12 : U32), (y0 + 30 : U32))),
      [Lay.hit(x0, y0, (x1 - x0 : U32), (h - y0 : U32), "focus", "terminal")]}])

# Viewer chrome
# -------------

type KV2 is Data:
  KV2{k: String, v: String}

def Info.row(kv: List<&2, String>) -> KV2:
  match kv:
    case k <> v:
      KV2{k, String.join(v, "=")}
    case Nil{}:
      KV2{"", ""}

def Info.rows(ps: List<&2, String>) -> List<&2, KV2>:
  match ps:
    case Nil{}:
      Nil{}
    case p <> t:
      Info.row(String.split(p, '=')) <> Info.rows(t)

def Info.draw.k(+ty: Ty, r: KV2, +x: U32, +y: U32, +w: U32) -> Out:
  KV2{k, v} = r
  Out.ops(List.append(&2, R.Op, Ty.text(ty, 2n, k, D.Clip.all(), (x + 14 : U32), y, 22, T.Th.faint()),
    Ty.text(ty, 2n, Ty.fit(ty, 2n, v, (w - 110 : U32)), D.Clip.all(), (x + 96 : U32), y, 22, T.Th.text())))

def Info.draw(+ty: Ty, rs: List<&2, KV2>, +x: U32, +y: U32, +w: U32) -> Out:
  match rs:
    case Nil{}:
      Out.none()
    case r <> t:
      Out.cat(Info.draw.k(ty, r, x, y, w), Info.draw(ty, t, x, (y + 22 : U32), w))

# what the picked item is: its kind, then key = value rows (the info the
# parser recorded: net, ref, value, footprint, pin, label...)
def Lay.inspect(+ty: Ty, +info: String, +draft: String, +x0: U32, +x1: U32, +h: U32) -> Out:
  +ps = String.split(info, ';')
  +title = Maybe.default(&2, String, List.head(&2, String, ps), "")
  +rows = Info.rows(List.drop(&2, String, ps, 1n))
  +n = {U32.from_nat(List.length(&2, KV2, rows)) : U32}
  +w = {U32.min((x1 - x0 - 32 : U32), 420) : U32}
  +ch = {(n * 22 + 88 : U32) : U32}
  +y = {(h - 16 - ch : U32) : U32}
  +mention = "[" ++ info ++ "] "
  Out.when(Bool.not(String.is_empty(info)), Out.all([
    Out.ops(Lay.box(D.Clip.all(), (x0 + 16 : U32), y, w, ch, 10, T.Th.panel(), T.Th.line())),
    Out.ops(Ty.text(ty, 1n, title, D.Clip.all(), (x0 + 30 : U32), (y + 8 : U32), 28, T.Th.text())),
    Out{Ty.text(ty, 0n, "×", D.Clip.all(), (x0 + w - 8 : U32), (y + 8 : U32), 28, T.Th.dim()), [Lay.hit((x0 + w - 16 : U32), (y + 6 : U32), 28, 28, "vw-unpick", "")]},
    Info.draw(ty, rows, (x0 + 16 : U32), (y + 38 : U32), w),
    Lay.button(ty, D.Clip.all(), (x0 + 30 : U32), (y + ch - 40 : U32), "Mention in chat", T.Th.accent(), "draft", draft ++ Bool.pick(String, String.is_empty(draft), "", " ") ++ mention)]))

def Lay.tab(+ty: Ty, +label: String, +k: U32, +cur: U32, +x: U32) -> Out:
  Lay.chip(ty, x, 12, label, U32.is_eq(k, cur), "vw-kind", U32.show(k))

def Lay.shown(+k: U32, +empty: Bool, +ts: List<&2, G.Tri3>, b: BM.Bitmap) -> Bool:
  match b:
    case BM.Bitmap{w, _, _, _, _, _, _, _}:
      Bool.pick(Bool, U32.is_ge(k, 4), True{}, Bool.pick(Bool, U32.is_eq(k, 3), U32.is_gt(w, 0), Bool.pick(Bool, U32.is_eq(k, 2), Bool.not(List.is_empty(&2, G.Tri3, ts)), Bool.not(empty))))

def Lay.help(+k: U32) -> String:
  Bool.pick(String, U32.is_eq(k, 4), "wheel scroll",
  Bool.pick(String, U32.is_eq(k, 3), "what the agents' browser shows, live",
    Bool.pick(String, U32.is_eq(k, 2), "drag orbit · wheel zoom · f fit", "click inspect · drag pan · wheel zoom · f fit")))

# Diff view
# ---------

type DRow is Data:
  DRow{text: String, kind: U32}

def DRow.lines(ls: List<&2, DF.DLine>, rest: List<&2, DRow>) -> List<&2, DRow>:
  match ls:
    case Nil{}:
      rest
    case DF.DLine{k, t, _, _} <> tl:
      DRow{t, (k + 10 : U32)} <> DRow.lines(tl, rest)

def DRow.hunks(hs: List<&2, DF.DHunk>, rest: List<&2, DRow>) -> List<&2, DRow>:
  match hs:
    case Nil{}:
      rest
    case DF.DHunk{hd, ls} <> t:
      DRow{hd, 3} <> DRow.lines(ls, DRow.hunks(t, rest))

def DRow.files(fs: List<&2, DF.DFile>) -> List<&2, DRow>:
  match fs:
    case Nil{}:
      Nil{}
    case DF.DFile{_, nw, st, hs} <> t:
      DRow{nw ++ "  " ++ st, 1} <> DRow.hunks(hs, DRow{"", 2} <> DRow.files(t))

def DRow.color(+k: U32) -> U32:
  Bool.pick(U32, U32.is_eq(k, 11), T.Th.ok(), Bool.pick(U32, U32.is_eq(k, 12), T.Th.bad(), Bool.pick(U32, Bool.or(U32.is_eq(k, 3), U32.is_eq(k, 13)), T.Th.faint(), T.Th.soft())))

def DRow.draw(+ty: Ty, r: DRow, +c: D.Clip, +x0: U32, +x1: U32, +y: U32) -> List<&2, R.Op>:
  match r:
    case DRow{t, +k}:
      List.append(&2, R.Op,
        Bool.pick(List<&2, R.Op>, U32.is_eq(k, 11), [D.Draw.rect(c, x0, y, (x1 - x0 : U32), 20, 1127459, 255)], Bool.pick(List<&2, R.Op>, U32.is_eq(k, 12), [D.Draw.rect(c, x0, y, (x1 - x0 : U32), 20, 3279380, 255)], Nil{})),
        Ty.text(ty, Bool.pick(Nat, U32.is_eq(k, 1), 1n, 4n), Bool.pick(String, U32.is_eq(k, 11), "+", Bool.pick(String, U32.is_eq(k, 12), "-", " ")) ++ t, c, (x0 + 12 : U32), y, 20, Bool.pick(U32, U32.is_eq(k, 1), T.Th.text(), DRow.color(k))))

def DRow.more(rs: List<&2, DRow>, +y: U32, +y1: U32) -> Bool:
  match rs:
    case Nil{}:
      False{}
    case _ <> _:
      U32.is_lt(y, y1)

# rows from y down while they start above y1
def DRow.all(+ty: Ty, rs: List<&2, DRow>, more: Bool, +c: D.Clip, +x0: U32, +x1: U32, +y: U32, +y1: U32) -> List<&2, R.Op>:
  match rs more:
    case r <> +t True{}:
      List.append(&2, R.Op, DRow.draw(ty, r, c, x0, x1, y), DRow.all(ty, t, DRow.more(t, (y + 20 : U32), y1), c, x0, x1, (y + 20 : U32), y1))
    case _ _:
      Nil{}

def DRow.go(+ty: Ty, +rs: List<&2, DRow>, +c: D.Clip, +x0: U32, +x1: U32, +y: U32, +y1: U32) -> List<&2, R.Op>:
  DRow.all(ty, rs, DRow.more(rs, y, y1), c, x0, x1, y, y1)

# what this thread changed (checkpoint 0 against the files now), with the
# git actions T3Code offers
def Lay.diff(+ty: Ty, +text: String, +x0: U32, +x1: U32, +h: U32, +scroll: U32) -> Out:
  +fs = DF.Diff.parse(text)
  +top = {96 : U32}
  +bc = Lay.button.w(ty, "Commit & push")
  +bp = Lay.button.w(ty, "Open PR")
  Out.all([
    Out.ops(Ty.text(ty, 2n, Bool.pick(String, List.is_empty(&2, DF.DFile, fs), "No changes since this thread began.", DF.Diff.summary(fs)), D.Clip.all(), (x0 + 16 : U32), 58, 30, T.Th.dim())),
    Lay.button(ty, D.Clip.all(), (x1 - 16 - bc : U32), 60, "Commit & push", T.Th.accent(), "git", "commit_push"),
    Lay.button(ty, D.Clip.all(), (x1 - 24 - bc - bp : U32), 60, "Open PR", T.Th.soft(), "git", "commit_push_pr"),
    Lay.button(ty, D.Clip.all(), (x1 - 32 - bc - bp - Lay.button.w(ty, "Revert thread") : U32), 60, "Revert thread", T.Th.bad(), "revert", "0"),
    Out.ops(DRow.go(ty, List.drop(&2, DRow, DRow.files(fs), U32.to_nat((scroll / 20 : U32))), D.Clip{x0, top, x1, h}, x0, x1, top, h))])

def Lay.viewer.k(+ty: Ty, +x0: U32, +x1: U32, +h: U32, +empty: Bool, x: V.Vx, +info: String, +draft: String, +diff: String, +scroll: U32) -> Out:
  match x:
    case V.Vx{+k, _, +ts, _, _, +busy, _, _, _, _, bm}:
      +help = Lay.help(k)
      +bw = Lay.button.w(ty, "Board")
      +sw = Lay.button.w(ty, "Schematic")
      +tw = Lay.button.w(ty, "3D")
      Out.all([
        Out.ops([D.Draw.rect(D.Clip.all(), x0, 0, (x1 - x0 : U32), 52, T.Th.bg(), 255), D.Draw.rect(D.Clip.all(), x0, 51, (x1 - x0 : U32), 1, T.Th.line(), 255),
          D.Draw.rect(D.Clip.all(), x0, 0, 1, h, T.Th.line(), 255)]),
        Lay.tab(ty, "Board", 0, k, (x0 + 16 : U32)),
        Lay.tab(ty, "Schematic", 1, k, (x0 + 24 + bw : U32)),
        Lay.tab(ty, "3D", 2, k, (x0 + 32 + bw + sw : U32)),
        Lay.tab(ty, "Browser", 3, k, (x0 + 40 + bw + sw + tw : U32)),
        Lay.tab(ty, "Diff", 4, k, (x0 + 48 + bw + sw + tw + Lay.button.w(ty, "Browser") : U32)),
        Out.when(U32.is_eq(k, 4), Lay.diff(ty, diff, x0, x1, h, scroll)),
        Out.ops(Ty.text(ty, 2n, Ty.fit(ty, 2n, help, (x1 - x0 - 380 : U32)), D.Clip.all(), (x1 - 16 - Ty.width(ty, 2n, Ty.fit(ty, 2n, help, (x1 - x0 - 380 : U32))) : U32), 0, 52, T.Th.faint())),
        Out.when(Bool.and(Bool.not(String.is_empty(busy)), Bool.not(Lay.shown(k, empty, ts, bm))),
          Out.ops(Ty.text(ty, 3n, busy, D.Clip.all(), (x0 + U32.shr((x1 - x0 - U32.min(Ty.width(ty, 3n, busy), (x1 - x0 : U32)) : U32)) : U32), (U32.shr(h) - 12 : U32), 23, T.Th.dim()))),
        Lay.inspect(ty, info, draft, x0, x1, h)])

def Lay.picked(x: V.Vx) -> String:
  match x:
    case V.Vx{_, p, _, _, _, _, _, _, _, _, bm}:
      p

def Lay.viewer.vw(+ty: Ty, v: V.Vw, +draft: String, +diff: String, +x0: U32, +x1: U32, +h: U32) -> Out:
  match v:
    case V.Vw{+ss, V.View{_, _, oy}, _, _, _, _, _, _, _, _, +vx}:
      Lay.viewer.k(ty, x0, x1, h, List.is_empty(&2, V.Seen, ss), vx, V.Pick.info(ss, Lay.picked(vx)), draft, diff, D.Draw.floor(F32.max(oy, 0.0)))

# the viewer's chrome; the scene under it is drawn by the viewer
def Lay.viewer(+ty: Ty, +n: S.Nui, +x0: U32, +x1: U32, +h: U32) -> Out:
  Lay.viewer.vw(ty, S.Nui.vw(n), U.Ui.draft_text(S.Nui.ui(n)), U.Ui.info(S.Nui.ui(n), "diff"), x0, x1, h)

def Lay.toast(+ty: Ty, +e: String, +w: U32, +h: U32) -> Out:
  +tw = {(Ty.width(ty, 2n, e) + 28 : U32) : U32}
  Bool.pick(Out, String.is_empty(e), Out.none(),
    Out{List.append(&2, R.Op, Lay.box(D.Clip.all(), (w - tw - 16 : U32), (h - 52 : U32), tw, 32, 8, T.Th.raise(), T.Th.bad()),
        Ty.text(ty, 2n, e, D.Clip.all(), (w - tw - 2 : U32), (h - 52 : U32), 32, T.Th.bad())),
      [Lay.hit((w - tw - 16 : U32), (h - 52 : U32), tw, 32, "dismiss", "")]})

def Lay.rev(o: Out) -> Out:
  match o:
    case Out{os, hs}:
      Out{List.reverse(&2, R.Op, os), List.reverse(&2, S.Hit, hs)}

def Lay.scene(n: S.Nui) -> List<&2, V.Seen>:
  match n:
    case S.Nui{_, _, _, _, _, _, _, _, _, _, _, _, V.Vw{ss, _, _, _, _, _, _, _, _, _, vx}}:
      ss

def Lay.note.k(+ty: Ty, empty: Bool, offer: Bool, +note: String, +x: U32, +y: U32) -> Out:
  match empty offer:
    case True{} _:
      Out.none()
    case False{} True{}:
      Out{List.append(&2, R.Op, Lay.round(D.Clip.all(), x, y, (Ty.width(ty, 2n, note) + 16 : U32), 20, 10, T.Th.sel()),
          Ty.text(ty, 2n, note, D.Clip.all(), (x + 8 : U32), y, 20, T.Th.accent())),
        [Lay.hit(x, y, (Ty.width(ty, 2n, note) + 16 : U32), 20, "update", "")]}
    case False{} False{}:
      Out.ops(Ty.text(ty, 2n, note, D.Clip.all(), x, y, 20, T.Th.warn()))

# an update to offer (clickable) or one being applied (status only), in
# the sidebar's footer beside Settings
def Lay.note(+ty: Ty, +note: String, +h: U32) -> Out:
  Lay.note.k(ty, String.is_empty(note), String.starts_with(note, "update "), note, U32.dim(248, (Ty.width(ty, 2n, note) + 16 : U32)), (h - 34 : U32))

def Lay.ghost.k(on: Bool, +ty: Ty, +title: String, +y: U32) -> Out:
  match on:
    case True{}:
      Out.ops(List.concat(&2, R.Op, [Lay.box(D.Clip.all(), 6, (y - 15 : U32), 252, 30, 0, T.Th.raise(), T.Th.accent()),
        Ty.text(ty, 0n, Ty.fit(ty, 0n, title, 220), D.Clip.all(), 32, (y - 16 : U32), 32, T.Th.text())]))
    case False{}:
      Out.none()

# a row being dragged, drawn under the pointer
def Lay.ghost(+ty: Ty, +n: S.Nui) -> Out:
  match n:
    case S.Nui{+u, _, _, _, +my, _, _, _, _, _, _, _, vw}:
      Lay.ghost.k(Bool.and(Bool.not(String.is_empty(U.Ui.scratch(u, "@drag"))), S.Row.far(S.Row.y(n), my)), ty,
        U.Tasks.title(U.Ui.state(u), U.Ui.scratch(u, "@drag")), U32.max(my, 67))

def Lay.sidebar(+ty: Ty, +n: S.Nui, +h: U32) -> Out:
  match n:
    case S.Nui{U.Ui{+st, +sel, _, _, +open, on, +now, adding, _, +v, _, _, _, +note, _, _, _}, _, _, _, _, +sd, _, +caret, +focus, +path, _, _, vw}:
      Out.all([Lay.sidebar.k(ty, D.Clip{0, 52, 264, h}, st, sel, open, on, now, adding, v, sd, caret, focus, path, h, U.Flag.get(open, "settings")), Lay.note(ty, note, h), Lay.ghost(ty, n)])

# Command palette (ctrl+k)
# ------------------------

def Pal.rows(+ty: Ty, ps: List<&2, U.PItem>, +i: Nat, +sel: Nat, +x: U32, +y: U32, +w: U32, left: Nat) -> Out:
  match ps left:
    case U.PItem{+l, +a, _} <> t 1n+m:
      Out.cat(Out{List.concat(&2, R.Op, [
          Bool.pick(List<&2, R.Op>, Nat.is_eq(i, sel), [D.Draw.rect(D.Clip.all(), (x + 4 : U32), y, (w - 8 : U32), 30, T.Th.sel(), 255)], Nil{}),
          Ty.text(ty, 0n, Ty.fit(ty, 0n, l, (w - 140 : U32)), D.Clip.all(), (x + 16 : U32), y, 30, Bool.pick(U32, Nat.is_eq(i, sel), T.Th.text(), T.Th.soft())),
          Ty.text(ty, 2n, U.Palette.kind(a), D.Clip.all(), (x + w - 16 - Ty.width(ty, 2n, U.Palette.kind(a)) : U32), y, 30, T.Th.faint())]),
          [Lay.hit(x, y, w, 30, "vw-pal", Nat.show(i))]},
        Pal.rows(ty, t, 1n+i, sel, x, (y + 30 : U32), w, m))
    case _ _:
      Out.none()

def Pal.prompt(+mode: String) -> String:
  Bool.pick(String, String.eq(mode, "search"), "Search threads and messages", Bool.pick(String, String.eq(mode, "files"), "Find a file to mention", "Type a command or a thread"))

def Lay.palette(+ty: Ty, +u: U.Ui, +ww: U32, +hh: U32, +blink: Bool) -> Out:
  +w = {U32.min(600, (ww - 40 : U32)) : U32}
  +x = {U32.shr((ww - w : U32)) : U32}
  +ps = U.Palette.items(u)
  +n = {U32.from_nat(Nat.min(List.length(&2, U.PItem, ps), 12n)) : U32}
  +q = U.Palette.query(u)
  Out.all([
    Out{[D.Draw.rect(D.Clip.all(), 0, 0, ww, hh, 0, 140)], [Lay.hit(0, 0, ww, hh, "vw-palx", "")]},
    Out{Lay.box(D.Clip.all(), x, 80, w, (n * 30 + 58 : U32), 0, T.Th.panel(), T.Th.line()), [Lay.hit(x, 80, w, (n * 30 + 58 : U32), "", "")]},
    Out.ops(Ty.text(ty, 0n, Bool.pick(String, String.is_empty(q), Pal.prompt(U.Palette.mode(u)), q), D.Clip.all(), (x + 16 : U32), 86, 36, Bool.pick(U32, String.is_empty(q), T.Th.faint(), T.Th.text()))),
    Out.ops([D.Draw.rect(D.Clip.all(), (x + 16 + Bool.pick(U32, String.is_empty(q), 0, Ty.width(ty, 0n, q)) : U32), 95, 1, 18, T.Th.accent(), Bool.pick(U32, blink, 255, 0)),
      D.Draw.rect(D.Clip.all(), x, 126, w, 1, T.Th.line(), 255)]),
    Pal.rows(ty, ps, 0n, U.Palette.index(u), x, 132, w, 12n)])

# Project picker
# --------------
# The folder being browsed, a filter line (fuzzy), then what can be done:
# add the folder, create the typed folder, go up, or open a subfolder.

def Proj.rows(+ty: Ty, ps: List<&2, U.PItem>, +i: Nat, +sel: Nat, +x: U32, +y: U32, +w: U32, left: Nat) -> Out:
  match ps left:
    case U.PItem{+l, +a, _} <> t 1n+m:
      Out.cat(Out{List.concat(&2, R.Op, [
          Bool.pick(List<&2, R.Op>, Nat.is_eq(i, sel), [D.Draw.rect(D.Clip.all(), (x + 4 : U32), y, (w - 8 : U32), 28, T.Th.sel(), 255)], Nil{}),
          Ty.text(ty, 2n, Ty.fit(ty, 2n, l, (w - 32 : U32)), D.Clip.all(), (x + 16 : U32), y, 28,
            Bool.pick(U32, String.eq(a, "proj-cd"), Bool.pick(U32, Nat.is_eq(i, sel), T.Th.text(), T.Th.soft()), Bool.pick(U32, String.is_empty(a), T.Th.faint(), T.Th.accent())))]),
          [Lay.hit(x, y, w, 28, "vw-proj", Nat.show(i))]},
        Proj.rows(ty, t, 1n+i, sel, x, (y + 28 : U32), w, m))
    case _ _:
      Out.none()

def Proj.first(+sel: Nat, +rows: Nat) -> Nat:
  Nat.sub(sel, Nat.sub(rows, 1n))

def Lay.proj(+ty: Ty, +u: U.Ui, +ww: U32, +hh: U32, +blink: Bool) -> Out:
  +w = {U32.min(640, (ww - 40 : U32)) : U32}
  +x = {U32.shr((ww - w : U32)) : U32}
  +ps = U.Proj.items(u)
  +rows = Nat.max(Nat.min(U32.to_nat((U32.dim(hh, 300) / 28 : U32)), 16n), 4n)
  +n = {U32.from_nat(Nat.min(List.length(&2, U.PItem, ps), rows)) : U32}
  +q = U.Proj.query(u)
  +err = U.Ui.info(u, "proj.err")
  +ey = {Bool.pick(U32, String.is_empty(err), 0, 26) : U32}
  +sel = U.Proj.index(u)
  +top = Proj.first(sel, rows)
  +bh = {(n * 28 + 118 + ey : U32) : U32}
  Out.all([
    Out{[D.Draw.rect(D.Clip.all(), 0, 0, ww, hh, 0, 140)], [Lay.hit(0, 0, ww, hh, "vw-projx", "")]},
    Out{Lay.box(D.Clip.all(), x, 80, w, bh, 0, T.Th.panel(), T.Th.line()), [Lay.hit(x, 80, w, bh, "", "")]},
    Out.ops(Ty.text(ty, 2n, Ty.fit(ty, 2n, U.Proj.dir(u), (w - 32 : U32)), D.Clip.all(), (x + 16 : U32), 84, 26, T.Th.dim())),
    Out.ops(Ty.text(ty, 0n, Bool.pick(String, String.is_empty(q), "Filter, name a new folder, or type a path", q), D.Clip.all(), (x + 16 : U32), 110, 36,
      Bool.pick(U32, String.is_empty(q), T.Th.faint(), T.Th.text()))),
    Out.ops([D.Draw.rect(D.Clip.all(), (x + 16 + Bool.pick(U32, String.is_empty(q), 0, Ty.width(ty, 0n, q)) : U32), 119, 1, 18, T.Th.accent(), Bool.pick(U32, blink, 255, 0)),
      D.Draw.rect(D.Clip.all(), x, 150, w, 1, T.Th.line(), 255)]),
    Out.when(Bool.not(String.is_empty(err)), Out.ops(Ty.text(ty, 2n, Ty.fit(ty, 2n, err, (w - 32 : U32)), D.Clip.all(), (x + 16 : U32), 152, 26, T.Th.bad()))),
    Proj.rows(ty, List.drop(&2, U.PItem, ps, top), top, sel, x, (154 + ey : U32), w, rows),
    Out.ops(Ty.text(ty, 2n, "enter  choose     tab  open     backspace  up     esc  close", D.Clip.all(), (x + 16 : U32), (158 + ey + n * 28 : U32), 36, T.Th.faint()))])

def Lay.term_on(+n: S.Nui) -> Bool:
  Bool.and(U.Ui.flag(S.Nui.ui(n), "term"), Bool.not(String.is_empty(U.Ui.sel(S.Nui.ui(n)))))

# the terminal's height (0 when closed)
def Lay.term_h(+n: S.Nui) -> U32:
  Bool.pick(U32, Lay.term_on(n), (S.Nui.height(n) * 2 / 5 : U32), 0)

def Lay.term.of(+ty: Ty, +n: S.Nui, +x1: U32, +h: U32) -> Out:
  Out.when(Lay.term_on(n), Lay.term(ty, U.Ui.term(S.Nui.ui(n), U.Ui.sel(S.Nui.ui(n))), 264, x1, (h - Lay.term_h(n) : U32), h, String.eq(S.Nui.focus_of(n), "terminal"), S.Blink.on(n)))

# the window as the main area sees it with the terminal below
def Lay.shrink(n: S.Nui, +dh: U32) -> S.Nui:
  match n:
    case S.Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, hi, ms, vw}:
      S.Nui{u, w, (h - dh : U32), mx, my, sd, sc, ca, fo, pa, hi, ms, vw}

def Hover.nums(ps: List<&2, String>) -> List<&2, U32>:
  match ps:
    case Nil{}:
      Nil{}
    case p <> t:
      Maybe.default(&2, U32, U32.read(p), 0) <> Hover.nums(t)

def Hover.rect(xs: List<&2, U32>, +alpha: U32) -> Out:
  match xs:
    case +x0 <> +y0 <> +x1 <> +y1 <> _:
      Out.when(Bool.and(U32.is_lt((y1 - y0 : U32), 90), U32.is_gt(x1, x0)),
        Out.ops([D.Draw.rect(D.Clip.all(), x0, y0, (x1 - x0 : U32), (y1 - y0 : U32), T.Th.text(), ((alpha * 22 : U32) / 255 : U32)),
          D.Draw.rect(D.Clip.all(), x0, (y1 - 1 : U32), (x1 - x0 : U32), 1, T.Th.accent(), ((alpha * 160 : U32) / 255 : U32))]))
    case _:
      Out.none()

# the region under the pointer, lit (big regions like panels are skipped)
def Lay.hover(+key: String, +alpha: U32) -> Out:
  Bool.pick(Out, String.is_empty(key), Out.none(), Hover.rect(Hover.nums(String.split(key, ',')), alpha))

# a message's attachments, as the lines closing its bubble
def TL.chip(+p: String) -> String:
  Bool.pick(String, AT.Att.image(p), "▣ ", "▤ ") ++ AT.Att.label(p)

def TL.chips.texts(ps: List<&2, String>) -> List<&2, String>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      TL.chip(p) <> TL.chips.texts(t)

def TL.chips(ps: List<&2, String>, +w: U32) -> List<&2, TLine>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      TLine{TL.chip(p), Bool.pick(U32, AT.Att.image(p), T.Th.accent(), T.Th.soft()), 2, "", w} <> TL.chips(t, w)

# a user message: its text (wrapped), then its attachments
def TL.bubble.a(+ty: Ty, +text: String, +px: U32) -> List<&2, TLine>:
  +ls = Ty.wrap(ty, 3n, AT.Att.body(text), U32.min((px * 7 / 10 : U32), 560))
  +ps = AT.Att.paths(text)
  +w = {(TL.widest(ty, List.append(&2, String, ls, TL.chips.texts(ps)), 0) + 40 : U32) : U32}
  List.concat(&2, TLine, [[TLine{"", 0, 6, "", w}], TL.user(ls, AT.Att.body(text), True{}, w), TL.chips(ps, w), [TLine{"", 0, 6, "", w}, TLine{"", 0, 4, "", 0}]])

def TL.entry.own(+ty: Ty, e: M.Entry, +px: U32) -> List<&2, TLine>:
  match e:
    case M.Msg{_, _, M.User{}, +text, _}:
      TL.bubble.a(ty, text, px)
    case M.Msg{_, _, _, +text, _}:
      List.append(&2, TLine, TL.blocks(ty, N.Md.render(text), px), [TLine{"", 0, 7, text, 0}, TLine{"", 0, 4, "", 0}])
    case M.Act{_, _, +tone, kind, summary, _}:
      [TLine{Ty.fit(ty, 2n, kind ++ "  " ++ summary, px), Bool.pick(U32, String.eq(tone, "error"), T.Th.bad(), T.Th.dim()), 3, "", 0}]

# an entry of this thread (headed by the thread it came from, if another
# thread sent it) or one this thread sent elsewhere (a link line)
def TL.entry.k(mine: Bool, +ty: Ty, e: M.Entry, +st: M.State, +px: U32) -> List<&2, TLine>:
  match mine e:
    case True{} M.Msg{+id, t, r, x, at}:
      List.append(&2, TLine, TL.from.k(String.is_empty(M.Link.from(id)), M.Link.from(id), st, px, ty), TL.entry.own(ty, M.Msg{id, t, r, x, at}, px))
    case True{} _:
      TL.entry.own(ty, e, px)
    case False{} M.Msg{_, +t, _, +x, _}:
      [TLine{Ty.fit(ty, 2n, "→ " ++ U.Tasks.title(st, t) ++ ":  " ++ TL.first_line(x), px), T.Th.accent(), 10, t, 0}]
    case False{} _:
      Nil{}

def TL.entry(+ty: Ty, +e: M.Entry, +st: M.State, +sel: String, +px: U32) -> List<&2, TLine>:
  TL.entry.k(String.eq(TL.thread_of(e), sel), ty, e, st, px)

def TL.entries(+ty: Ty, es: List<&2, M.Entry>, +st: M.State, +sel: String, +px: U32) -> List<&2, TLine>:
  match es:
    case Nil{}:
      Nil{}
    case e <> t:
      List.append(&2, TLine, TL.entry(ty, e, st, sel, px), TL.entries(ty, t, st, sel, px))

# messages the server has not stored yet, marked as sending
def TL.sending(+ty: Ty, ps: List<&2, String>, +px: U32) -> List<&2, TLine>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      List.concat(&2, TLine, [TL.bubble.a(ty, p, px), [TLine{"sending…", T.Th.faint(), 3, "", 0}], TL.sending(ty, t, px)])

# the draft's last lines and where the caret sits among them
# the next message's attachments, as chips from x (a click removes one),
# then the file still uploading
def Lay.atts(+ty: Ty, ps: List<&2, String>, +up: String, +x: U32, +y: U32) -> Out:
  match ps:
    case Nil{}:
      Out.when(Bool.not(String.is_empty(up)), Out.ops(Ty.text(ty, 2n, up ++ " …", D.Clip.all(), x, y, 28, T.Th.faint())))
    case +p <> t:
      Out.cat(Lay.chip(ty, x, y, TL.chip(p) ++ "  ×", AT.Att.image(p), "detach", p),
        Lay.atts(ty, t, up, (x + Lay.button.w(ty, TL.chip(p) ++ "  ×") + 6 : U32), y))

# the path field "Attach" opens above the composer (Enter attaches)
def Lay.attach_field(+ty: Ty, on: Bool, +path: String, +caret: Nat, +x0: U32, +x1: U32, +y: U32) -> Out:
  match on:
    case True{}:
      Out.cat(Lay.field(ty, D.Clip.all(), x0, y, (x1 - x0 - 12 - Lay.button.w(ty, "Attach") : U32), path, True{}, True{}, caret, "/path/to/a/file, or paste one (Enter attaches, Esc closes)", "attach-path"),
        Lay.button(ty, D.Clip.all(), (x1 - Lay.button.w(ty, "Attach") : U32), y, "Attach", T.Th.accent(), "attach-file", path))
    case False{}:
      Out.none()

# the composer with its attachments
def Lay.composer.a(+ty: Ty, +draft: String, +caret: Nat, +focus: String, +blink: Bool, +x0: U32, +x1: U32, +h: U32, +running: Bool, +models: String, +picking: Bool, +ms: List<&2, String>, +model: String,
    +info: String, +prov: String, +es: List<&2, String>, +effort: String, +rs: List<&2, U.SkillRow>, +atts: List<&2, String>, +up: String, +path: String) -> Out:
  +send = Bool.pick(String, running, "Queue", "Send")
  +y = {(h - 120 : U32) : U32}
  Out.all([
    Lay.composer(ty, draft, caret, String.eq(focus, "composer"), blink, x0, x1, h, running, models, picking, ms, model, info, prov, es, effort, rs),
    Lay.atts(ty, atts, up, (x0 + 24 + Ty.width(ty, 2n, models) + 36 : U32), (y + 64 : U32)),
    Lay.button(ty, D.Clip.all(), (x1 - 20 - Lay.button.w(ty, send) - Lay.button.w(ty, "Attach") : U32), (y + 64 : U32), "Attach", T.Th.soft(), "focus", "attach-path"),
    Lay.attach_field(ty, String.eq(focus, "attach-path"), path, caret, x0, x1, (y - 36 : U32))])

def Lay.thread.k(+ty: Ty, t: M.Thread, +draft: String, +st: M.State, +sel: String, +live: String, +caret: Nat, +focus: String, +blink: Bool,
    +x0: U32, +x1: U32, +h: U32, +sc: U32, pa: Bool, +info: String, +picking: Bool, +pend: List<&2, String>, +rs: List<&2, U.SkillRow>, +now: Nat,
    +atts: List<&2, String>, +up: String, +path: String) -> Out:
  match t:
    case M.Thread{id, p, ti, c, a, +turn, pe, ar, o, sa, ua, pi, en, br, wt, +pr, +mo, rm, im, se, de}:
      +cw = {U32.min((x1 - x0 - 64 : U32), 780) : U32}
      +cx0 = {(x0 + U32.shr((x1 - x0 - cw : U32)) : U32) : U32}
      +cx1 = {(cx0 + cw : U32) : U32}
      +ts = U.Tasks.of(st, sel)
      +pl = {Bool.pick(U32, String.is_empty(U.Tasks.parent(st, sel)), 0, 32) : U32}
      +top = {(52 + pl + Tasks.height(ts) : U32) : U32}
      +asks = U.Asks.open(st, sel)
      +ah = Asks.h(ty, asks, (cw - 32 : U32))
      +qh = {Bool.pick(U32, String.is_empty(M.Queue.of(st, sel)), 0, 30) : U32}
      Lay.timeline(ty,
        List.concat(&2, TLine, [TL.entries(ty, TL.mine(U.Ui.entries(st), sel, Nil{}), st, sel, cw), TL.sending(ty, pend, cw),
          TL.live.k(ty, String.is_empty(live), Lay.running(turn), live, cw)]),
        cx0, cx1, top, (h - ah - qh : U32), sc,
        Out.all([Lay.header(ty, M.Thread{id, p, ti, c, a, turn, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de}, x0, x1, pa, M.Snooze.on(now, U.Side.until(st, sel))),
          Lay.parent(ty, st, sel, cx0, 58),
          Lay.tasks(ty, ts, st, cx0, cx1, (60 + pl : U32)),
          Lay.composer.a(ty, draft, caret, focus, blink, cx0, cx1, h, Lay.running(turn), U.Effort.label(U.Models.label(pr, mo), U.Effort.of(st, sel)), picking, U.Models.list(info, pr), mo, info, pr,
            U.Effort.chips(info, pr, mo), U.Effort.of(st, sel), rs, atts, up, path),
          Lay.queued(ty, M.Queue.of(st, sel), cx0, cx1, h),
          Lay.asks(ty, asks, draft, cx0, cx1, (h - 132 - ah - qh + 4 : U32))]))

def Lay.thread(+ty: Ty, +n: S.Nui, +x0: U32, +x1: U32) -> Out:
  match n:
    case S.Nui{U.Ui{+st, +sel, _, +live, +op, _, _, _, pa, _, _, _, _, _, +nf, _, _}, _, +h, _, _, _, +sc, +caret, +focus, +path, _, _, _}:
      Lay.thread.k(ty, U.Ui.thread(st, sel), U.Ui.draft_text(S.Nui.ui(n)), st, sel, U.Str.get(live, sel), caret, focus, S.Blink.on(n), x0, x1, h, sc, pa,
        U.Str.get(nf, "models"), U.Flag.get(op, "models"), U.Ui.pending(S.Nui.ui(n), sel), U.Ui.skills(S.Nui.ui(n)), U.Side.now(S.Nui.ui(n)),
        U.Ui.atts(S.Nui.ui(n), sel), U.Ui.uploading(S.Nui.ui(n), sel), path)

def Lay.main(+ty: Ty, +n: S.Nui, +x0: U32, +x1: U32) -> Out:
  match n:
    case S.Nui{U.Ui{+st, +sel, _, _, +op, _, _, _, _, +v, _, _, _, +note, +nf, _, _}, _, +h, _, _, _, _, _, _, _, _, _, _}:
      Bool.pick(Out, U.Flag.get(op, "settings"), Lay.settings(ty, st, nf, v, note, x0, x1, h),
        Bool.pick(Out, String.is_empty(sel), Lay.empty(ty, x0, x1, h, List.length(&2, M.Project, U.Ui.projects(st))), Lay.thread(ty, n, x0, x1)))

# the whole window, topmost first
def Lay.frame(+ty: Ty, +n: S.Nui) -> Out:
  match n:
    case S.Nui{U.Ui{_, _, _, _, _, _, _, _, +pa, _, _, _, +err, note, _, _, _}, +w, +h, _, _, _, _, _, _, _, _, _, _}:
      Lay.rev(Out.all([
        Out.when(pa, Out.ops([D.Draw.rect(D.Clip.all(), 264, 0, U32.shr((w - 264 : U32)), h, T.Th.bg(), 255)])),
        Lay.main(ty, Lay.shrink(n, Lay.term_h(n)), 264, Bool.pick(U32, pa, (264 + U32.shr((w - 264 : U32)) : U32), w)),
        Bool.pick(Out, pa, Lay.viewer(ty, n, (264 + U32.shr((w - 264 : U32)) : U32), w, h), Out.none()),
        Lay.term.of(ty, n, Bool.pick(U32, pa, (264 + U32.shr((w - 264 : U32)) : U32), w), h),
        Lay.sidebar(ty, n, h),
        Lay.toast(ty, err, w, h),
        Out.when(U.Ui.flag(S.Nui.ui(n), "palette"), Lay.palette(ty, S.Nui.ui(n), w, h, S.Blink.on(n))),
        Out.when(U.Ui.flag(S.Nui.ui(n), "proj"), Lay.proj(ty, S.Nui.ui(n), w, h, S.Blink.on(n))),
        Lay.hover(U.Ui.info(S.Nui.ui(n), "hover"), S.Hover.alpha(n, S.Nui.ms_of(n)))]))
