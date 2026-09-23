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

def Lay.hit(+x: U32, +y: U32, +w: U32, +h: U32, action: String, value: String) -> S.Hit:
  S.Hit{x, y, (x + w : U32), (y + h : U32), action, value}

# a filled rectangle with rounded corners: two rects and four discs
def Lay.round(+c: D.Clip, +x: U32, +y: U32, +w: U32, +h: U32, +r: U32, +color: U32) -> List<&2, R.Op>:
  +fr = U32.to_f32(r)
  [D.Draw.rect(c, (x + r : U32), y, (w - r - r : U32), h, color, 255),
   D.Draw.rect(c, x, (y + r : U32), w, (h - r - r : U32), color, 255),
   D.Draw.disc(c, U32.to_f32((x + r : U32)), U32.to_f32((y + r : U32)), fr, color, 255),
   D.Draw.disc(c, U32.to_f32((x + w - r : U32)), U32.to_f32((y + r : U32)), fr, color, 255),
   D.Draw.disc(c, U32.to_f32((x + r : U32)), U32.to_f32((y + h - r : U32)), fr, color, 255),
   D.Draw.disc(c, U32.to_f32((x + w - r : U32)), U32.to_f32((y + h - r : U32)), fr, color, 255)]

# a rounded box with a 1px border
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

def Lay.dot(t: M.TurnState) -> U32:
  match t:
    case M.Running{}:
      T.Th.accent()
    case M.Failed{}:
      T.Th.bad()
    case M.Interrupted{}:
      T.Th.warn()
    case _:
      T.Th.faint()

def Lay.row.k(+ty: Ty, +on: Bool, id: String, title: String, +ago: String, +dot: U32, +c: D.Clip, +y: U32) -> Out:
  +aw = Ty.width(ty, 2n, ago)
  Out{List.concat(&2, R.Op, [
      Bool.pick(List<&2, R.Op>, on, Lay.round(c, 6, (y + 1 : U32), 252, 30, 6, T.Th.raise()), Nil{}),
      [D.Draw.disc(c, 19.0, U32.to_f32((y + 16 : U32)), 3.0, dot, 255)],
      Ty.text(ty, 0n, Ty.fit(ty, 0n, title, (252 - 32 - aw - 12 : U32)), c, 32, y, 32, Bool.pick(U32, on, T.Th.text(), T.Th.soft())),
      Ty.text(ty, 2n, ago, c, (252 - aw : U32), y, 32, T.Th.faint())]),
    [Lay.hit(0, y, 264, 32, "select", id)]}

def Lay.row(+ty: Ty, t: M.Thread, +sel: String, +now: Nat, +c: D.Clip, +y: U32) -> Out:
  match t:
    case M.Thread{+id, _, title, _, +a, turn, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      Lay.row.k(ty, String.eq(id, sel), id, title, U.Time.ago(now, a), Lay.dot(turn), c, y)

# rows from y down; answers the output and the next y
type Col is Data:
  Col{out: Out, y: U32}

def Lay.col.cat(o: Out, c: Col) -> Col:
  match c:
    case Col{o2, y}:
      Col{Out.cat(o, o2), y}

def Lay.rows(+ty: Ty, ts: List<&2, M.Thread>, +sel: String, +now: Nat, +c: D.Clip, +y: U32) -> Col:
  match ts:
    case Nil{}:
      Col{Out.none(), y}
    case t <> rest:
      Lay.col.cat(Lay.row(ty, t, sel, now, c, y), Lay.rows(ty, rest, sel, now, c, (y + 32 : U32)))

def Lay.col.then(a: Col, k: U32 -> Col) -> Col:
  match a:
    case Col{o, +y}:
      Lay.col.cat(o, k(y))

def Lay.settled.k(+ty: Ty, open: Bool, +pid: String, +label: String, ts: List<&2, M.Thread>, +sel: String, +now: Nat, +c: D.Clip, +y: U32) -> Col:
  match open:
    case True{}:
      Lay.col.cat(Out{Ty.text(ty, 2n, "▾ " ++ label, c, 16, y, 28, T.Th.dim()), [Lay.hit(0, y, 264, 28, "toggle-settled", pid)]},
        Lay.rows(ty, ts, sel, now, c, (y + 28 : U32)))
    case False{}:
      Col{Out{Ty.text(ty, 2n, "▸ " ++ label, c, 16, y, 28, T.Th.faint()), [Lay.hit(0, y, 264, 28, "toggle-settled", pid)]}, (y + 28 : U32)}

def Lay.settled(+ty: Ty, open: Bool, +pid: String, st: List<&2, M.Thread>, +sel: String, +now: Nat, +c: D.Clip, +y: U32) -> Col:
  match st:
    case Nil{}:
      Col{Out.none(), y}
    case +t <> +rest:
      Lay.settled.k(ty, open, pid, "Settled " ++ Nat.show(1n+List.length(&2, M.Thread, rest)), t <> rest, sel, now, c, y)

# Project order (as the web view: latest thread activity, newest first)
type PRow is Data:
  PRow{rank: Nat, project: M.Project, shelves: M.Shelves}

def Lay.project(+ty: Ty, r: PRow, +open: Map<&2, Bool>, +sel: String, +now: Nat, +c: D.Clip, +y: U32) -> Col:
  match r:
    case PRow{_, M.Project{+id, title, _, _, _}, M.Shelves{pinned, active, settled, _}}:
      Lay.col.cat(Out.cat(Out.ops(Ty.text(ty, 2n, Ty.fit(ty, 2n, title, 200), c, 16, (y + 4 : U32), 28, T.Th.dim())),
          Out{Ty.text(ty, 0n, "+", c, 238, (y + 4 : U32), 28, T.Th.faint()), [Lay.hit(230, (y + 4 : U32), 28, 28, "new-thread", id)]}),
        Lay.col.then(Lay.rows(ty, pinned, sel, now, c, (y + 32 : U32)), y1 =>
          Lay.col.then(Lay.rows(ty, active, sel, now, c, y1), y2 =>
            Lay.settled(ty, U.Flag.get(open, id), id, settled, sel, now, c, y2))))

def Lay.projects(+ty: Ty, rs: List<&2, PRow>, +open: Map<&2, Bool>, +sel: String, +now: Nat, +c: D.Clip, +y: U32) -> Col:
  match rs:
    case Nil{}:
      Col{Out.none(), y}
    case r <> t:
      Lay.col.then(Lay.project(ty, r, open, sel, now, c, y), y2 => Lay.projects(ty, t, open, sel, now, c, (y2 + 8 : U32)))

def PRow.before(a: PRow, b: PRow) -> Bool:
  match a b:
    case PRow{ra, _, _} PRow{rb, _, _}:
      Nat.is_ge(ra, rb)

def Lay.latest(ts: List<&2, M.Thread>, +acc: Nat) -> Nat:
  match ts:
    case Nil{}:
      acc
    case M.Thread{_, _, _, _, +a, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} <> t:
      Lay.latest(t, M.Time.max(acc, a))

def Lay.prows.k(removed: Bool, p: M.Project, +mine: List<&2, M.Thread>, +c: Nat, rest: List<&2, PRow>) -> List<&2, PRow>:
  match removed:
    case True{}:
      rest
    case False{}:
      PRow{Lay.latest(mine, c), p, M.Sidebar.order(M.Sidebar.split(mine))} <> rest

def Lay.prows(ps: List<&2, M.Project>, +ts: List<&2, M.Thread>) -> List<&2, PRow>:
  match ps:
    case Nil{}:
      Nil{}
    case M.Project{+id, ti, r, +c, +rm} <> t:
      Lay.prows.k(rm, M.Project{id, ti, r, c, rm}, M.Thread.filter_project(ts, id), c, Lay.prows(t, ts))

# delegated (child) threads live under their parent, not in the sidebar
def Kids.of(ts: List<&2, M.Task>, m: Map<&2, Bool>) -> Map<&2, Bool>:
  match ts:
    case Nil{}:
      m
    case M.Task{_, _, child, _, _, _, _, _, _} <> t:
      Kids.of(t, Map.set(&2, Bool, m, child, True{}))

def Kids.set(s: M.State) -> Map<&2, Bool>:
  match s:
    case M.State{_, _, _, _, tk, _}:
      Kids.of(Map.values(&2, M.Task, tk), Map.new(&2, Bool))

def Kids.keep.k(kid: Bool, t: M.Thread, rest: List<&2, M.Thread>) -> List<&2, M.Thread>:
  match kid:
    case True{}:
      rest
    case False{}:
      t <> rest

def Kids.keep(ts: List<&2, M.Thread>, +kids: Map<&2, Bool>) -> List<&2, M.Thread>:
  match ts:
    case Nil{}:
      Nil{}
    case M.Thread{+id, p, ti, c, a, tu, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de} <> t:
      Kids.keep.k(U.Flag.get(kids, id), M.Thread{id, p, ti, c, a, tu, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de}, Kids.keep(t, kids))

def Lay.field(+ty: Ty, +c: D.Clip, +x: U32, +y: U32, +w: U32, +text: String, +focused: Bool, +caret: Nat, +placeholder: String, +id: String) -> Out:
  +vis = Ty.fit(ty, 2n, text, (w - 16 : U32))
  Out{List.concat(&2, R.Op, [
      Lay.box(c, x, y, w, 28, 6, T.Th.bg(), Bool.pick(U32, focused, T.Th.accent(), T.Th.line())),
      Bool.pick(List<&2, R.Op>, String.is_empty(text), Ty.text(ty, 2n, placeholder, c, (x + 8 : U32), y, 28, T.Th.faint()),
        Ty.text(ty, 2n, vis, c, (x + 8 : U32), y, 28, T.Th.text())),
      Bool.pick(List<&2, R.Op>, focused, [D.Draw.rect(c, (x + 8 + Ty.width(ty, 2n, String.take(vis, caret)) : U32), (y + 7 : U32), 1, 14, T.Th.accent(), 255)], Nil{})]),
    [Lay.hit(x, y, w, 28, "focus", id)]}

def Lay.adding(+ty: Ty, adding: Bool, +path: String, +focused: Bool, +caret: Nat) -> Out:
  match adding:
    case True{}:
      Out.cat(Lay.field(ty, D.Clip.all(), 12, 58, 186, path, focused, caret, "/path/to/project", "project-path"),
        Lay.button(ty, D.Clip.all(), 204, 58, "Add", T.Th.accent(), "add-project", path))
    case False{}:
      Out.none()

def Lay.col.out(c: Col) -> Out:
  match c:
    case Col{o, _}:
      o

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
    Out{Ty.text(ty, 0n, "+", top, 238, 0, 52, T.Th.dim()), [Lay.hit(228, 12, 28, 28, "toggle-add", "")]},
    Lay.adding(ty, adding, path, String.eq(focus, "project-path"), caret),
    Lay.col.out(Lay.projects(ty, List.sort(~PRow, ~PRow.before, Lay.prows(U.Ui.projects(st), Kids.keep(U.Ui.threads(st), Kids.set(st)))), open, sel, now,
      D.Clip{0, y0, 264, (h - 48 : U32)}, U32.sub(y0, sd))),
    Out{List.append(&2, R.Op, [D.Draw.rect(D.Clip.all(), 0, (h - 48 : U32), 263, 48, T.Th.panel(), 255), D.Draw.rect(D.Clip.all(), 0, (h - 48 : U32), 263, 1, T.Th.line(), 255)],
        Ty.text(ty, 2n, "Settings", D.Clip.all(), 16, (h - 48 : U32), 48, Bool.pick(U32, settings, T.Th.text(), T.Th.dim()))),
      [Lay.hit(0, (h - 48 : U32), 263, 48, "flag", "settings")]}])

# Timeline
# --------

# one laid-out line. kind: 0 text, 1 code, 2 user, 3 activity, 4 gap,
# 5 heading, 6 user padding, 7 footer with a Copy button, 8 code header,
# 9 code bottom. w is a user bubble's width
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

def TL.entry(+ty: Ty, e: M.Entry, +px: U32) -> List<&2, TLine>:
  match e:
    case M.Msg{_, _, M.User{}, +text, _}:
      TL.bubble(ty, Ty.wrap(ty, 3n, text, U32.min((px * 7 / 10 : U32), 560)), text)
    case M.Msg{_, _, _, +text, _}:
      List.append(&2, TLine, TL.blocks(ty, N.Md.render(text), px), [TLine{"", 0, 7, text, 0}, TLine{"", 0, 4, "", 0}])
    case M.Act{_, _, +tone, kind, summary, _}:
      [TLine{Ty.fit(ty, 2n, kind ++ "  " ++ summary, px), Bool.pick(U32, String.eq(tone, "error"), T.Th.bad(), T.Th.dim()), 3, "", 0}]

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

# a thread's entries, oldest first
def TL.mine(es: List<&2, M.Entry>, +th: String, acc: List<&2, M.Entry>) -> List<&2, M.Entry>:
  match es:
    case Nil{}:
      acc
    case +e <> t:
      TL.mine(t, th, TL.mine.k(String.eq(TL.thread_of(e), th), e, acc))

def TL.entries(+ty: Ty, es: List<&2, M.Entry>, +px: U32) -> List<&2, TLine>:
  match es:
    case Nil{}:
      Nil{}
    case e <> t:
      List.append(&2, TLine, TL.entry(ty, e, px), TL.entries(ty, t, px))

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

def TL.draw.k(+ty: Ty, k: Nat, text: String, +color: U32, +copy: String, +bw: U32, +c: D.Clip, +x0: U32, +x1: U32, +y: U32) -> Out:
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

# header buttons right to left from x; answers the output
def Lay.buttons(+ty: Ty, bs: List<&2, S.Hit>, +y: U32, +x: U32) -> Out:
  match bs:
    case Nil{}:
      Out.none()
    case S.Hit{_, _, _, _, +label, +action} <> t:
      Out.cat(Lay.button(ty, D.Clip.all(), (x - Lay.button.w(ty, label) : U32), y, label, T.Th.soft(), action, ""),
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

def Lay.header.bs(turn: M.TurnState, override: M.Override, +sa: Nat, +ua: Nat, pinned: Bool, panel: Bool) -> List<&2, S.Hit>:
  List.concat(&2, S.Hit, [
    [S.Hit{0, 0, 0, 0, Bool.pick(String, panel, "Hide viewer", "Viewer"), "panel"},
     S.Hit{0, 0, 0, 0, "Archive", "archive"}],
    Lay.settle(override, Nat.is_gt(sa, ua)),
    [Lay.pin(pinned)],
    Bool.pick(List<&2, S.Hit>, Lay.running(turn), [S.Hit{0, 0, 0, 0, "Stop", "interrupt"}], Nil{})])

# the title and branch get what the buttons leave
# s fitted to px, or nothing when there is no room for a few letters
def Lay.fit_or_none(+ty: Ty, +k: Nat, +s: String, +px: U32) -> String:
  Bool.pick(String, U32.is_lt(px, 32), "", Ty.fit(ty, k, s, px))

def Lay.header.k(+ty: Ty, +title: String, +branch: String, +bs: List<&2, S.Hit>, +x0: U32, +x1: U32) -> Out:
  +room = {U32.sub(U32.sub((x1 - x0 : U32), Lay.buttons.w(ty, bs)), 56) : U32}
  +t = Ty.fit(ty, 0n, title, room)
  +tw = Ty.width(ty, 0n, t)
  Out.all([
    Out.ops([D.Draw.rect(D.Clip.all(), x0, 51, (x1 - x0 : U32), 1, T.Th.line(), 255)]),
    Out.ops(Ty.text(ty, 0n, t, D.Clip.all(), (x0 + 24 : U32), 0, 52, T.Th.text())),
    Out.ops(Ty.text(ty, 2n, Lay.fit_or_none(ty, 2n, branch, U32.sub(room, (tw + 12 : U32))), D.Clip.all(), (x0 + 36 + tw : U32), 0, 52, T.Th.faint())),
    Lay.buttons(ty, bs, 12, (x1 - 16 : U32))])

def Lay.header(+ty: Ty, t: M.Thread, +x0: U32, +x1: U32, panel: Bool) -> Out:
  match t:
    case M.Thread{_, _, +title, _, _, turn, _, _, override, +sa, +ua, pinned, _, +branch, _, _, _, _, _, _, _}:
      Lay.header.k(ty, title, branch, Lay.header.bs(turn, override, sa, ua, pinned, panel), x0, x1)

def Lay.lines(+ty: Ty, ls: List<&2, String>, +c: D.Clip, +x: U32, +y: U32) -> Out:
  match ls:
    case Nil{}:
      Out.none()
    case l <> t:
      Out.cat(Out.ops(Ty.text(ty, 3n, l, c, x, y, 23, T.Th.text())), Lay.lines(ty, t, c, x, (y + 23 : U32)))

# Models: the machine's {"provider": [model, ...]} and the picker
def Models.strs(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case J.Str{s} <> t:
      s <> Models.strs(t)
    case _ <> t:
      Models.strs(t)

def Models.list(+info: String, +provider: String) -> List<&2, String>:
  Models.strs(J.Json.elems(J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(info), J.Null{}), provider)))

def Models.label(+provider: String, +model: String) -> String:
  provider ++ " · " ++ Bool.pick(String, String.is_empty(model), "default", model)

def Picker.rows(+ty: Ty, ms: List<&2, String>, +cur: String, +x: U32, +y: U32, +w: U32) -> Out:
  match ms:
    case Nil{}:
      Out.none()
    case +m <> t:
      Out.cat(Out{List.append(&2, R.Op,
          Bool.pick(List<&2, R.Op>, String.eq(m, cur), Lay.round(D.Clip.all(), (x + 4 : U32), y, (w - 8 : U32), 28, 5, T.Th.sel()), Nil{}),
          Ty.text(ty, 2n, m, D.Clip.all(), (x + 14 : U32), y, 28, Bool.pick(U32, String.eq(m, cur), T.Th.text(), T.Th.soft()))),
          [Lay.hit(x, y, w, 28, "model", m)]},
        Picker.rows(ty, t, cur, x, (y + 28 : U32), w))

# the model menu, opening upward from the composer's footer
def Lay.picker(+ty: Ty, open: Bool, +ms: List<&2, String>, +cur: String, +x: U32, +bottom: U32) -> Out:
  +n = {U32.from_nat(List.length(&2, String, ms)) : U32}
  +h = {(n * 28 + 8 : U32) : U32}
  Out.when(Bool.and(open, U32.is_gt(n, 0)),
    Out.cat(Out.ops(Lay.box(D.Clip.all(), x, (bottom - h : U32), 220, h, 8, T.Th.panel(), T.Th.line())),
      Picker.rows(ty, ms, cur, x, (bottom - h + 4 : U32), 220)))

# the draft's last lines and where the caret sits among them
def Lay.composer(+ty: Ty, +draft: String, +caret: Nat, +focused: Bool, +x0: U32, +x1: U32, +h: U32, running: Bool, +models: String, +picking: Bool, +ms: List<&2, String>, +model: String) -> Out:
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
      Out.ops(Ty.text(ty, 3n, "Ask anything, @tag files, or describe the change", D.Clip.all(), (x0 + 16 : U32), (y + 10 : U32), 23, T.Th.faint())),
      Lay.lines(ty, shown, D.Clip{(x0 + 1 : U32), (y + 1 : U32), (x1 - 1 : U32), (y + 60 : U32)}, (x0 + 16 : U32), (y + 10 : U32))),
    Bool.pick(Out, focused, Out.ops([D.Draw.rect(D.Clip.all(), (x0 + 16 + cx : U32), (y + 14 + (U32.from_nat(row) * 23 : U32) : U32), 1, 16, T.Th.accent(), 255)]), Out.none()),
    Out{Nil{}, [Lay.hit(x0, y, (x1 - x0 : U32), 64, "focus", "composer")]},
    Out{Ty.text(ty, 2n, models ++ "  ▾", D.Clip.all(), (x0 + 16 : U32), (y + 64 : U32), 28, T.Th.dim()), [Lay.hit((x0 + 8 : U32), (y + 64 : U32), (Ty.width(ty, 2n, models) + 36 : U32), 28, "flag", "models")]},
    Lay.button(ty, D.Clip.all(), (x1 - 12 - Lay.button.w(ty, send) : U32), (y + 64 : U32), send, T.Th.accent(), "send", ""),
    Lay.picker(ty, picking, ms, model, (x0 + 8 : U32), (y + 64 : U32))])

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
def Lay.timeline(+ty: Ty, +ls: List<&2, TLine>, +x0: U32, +x1: U32, +top: U32, +h: U32, +sc: U32, chrome: Out) -> Out:
  +bot = {(h - 132 : U32) : U32}
  +view = {(bot - top - 16 : U32) : U32}
  +total = TL.height(ls, 0)
  +over = {Bool.pick(U32, U32.is_gt(total, view), (total - view : U32), 0) : U32}
  +s = {U32.min(sc, over) : U32}
  +y0 = {Bool.pick(U32, U32.is_gt(total, view), (top + 16 + view + s - total : U32), (top + 16 : U32)) : U32}
  +rest = Lay.skip(ls, TL.above(ls, y0, top), y0, top)
  +ry = Lay.skip_y(ls, y0, top)
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

def Task.word(s: M.TaskState) -> String:
  match s:
    case M.TaskQueued{}:
      "queued"
    case M.TaskRunning{}:
      "running"
    case M.TaskDone{}:
      "done"
    case M.TaskFailed{}:
      "failed"
    case M.TaskCancelled{}:
      "cancelled"

def Tasks.mine.k(keep: Bool, t: M.Task, rest: List<&2, M.Task>) -> List<&2, M.Task>:
  match keep:
    case True{}:
      t <> rest
    case False{}:
      rest

def Tasks.mine(ts: List<&2, M.Task>, +parent: String) -> List<&2, M.Task>:
  match ts:
    case Nil{}:
      Nil{}
    case M.Task{i, +p, c, d, st, su, dl, pr, mo} <> t:
      Tasks.mine.k(String.eq(p, parent), M.Task{i, p, c, d, st, su, dl, pr, mo}, Tasks.mine(t, parent))

# the tasks this thread delegated
def Tasks.of(s: M.State, +parent: String) -> List<&2, M.Task>:
  match s:
    case M.State{_, _, _, _, tk, _}:
      Tasks.mine(Map.values(&2, M.Task, tk), parent)

def Tasks.title.k(t: M.Thread) -> String:
  match t:
    case M.Thread{_, _, ti, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      ti

def Tasks.title(s: M.State, +id: String) -> String:
  Tasks.title.k(U.Ui.thread(s, id))

def Tasks.row(+ty: Ty, t: M.Task, +st: M.State, +x0: U32, +x1: U32, +y: U32) -> Out:
  match t:
    case M.Task{_, _, +child, _, +s, _, _, +pr, +mo}:
      +word = Task.word(s)
      +who = Models.label(pr, mo)
      +ww = Ty.width(ty, 2n, word)
      +whw = Ty.width(ty, 2n, who)
      Out{List.concat(&2, R.Op, [
          [D.Draw.disc(D.Clip.all(), U32.to_f32((x0 + 14 : U32)), U32.to_f32((y + 14 : U32)), 3.0, Task.color(s), 255)],
          Ty.text(ty, 2n, who, D.Clip.all(), (x0 + 26 : U32), y, 28, T.Th.dim()),
          Ty.text(ty, 0n, Ty.fit(ty, 0n, Tasks.title(st, child), (x1 - x0 - whw - ww - 64 : U32)), D.Clip.all(), (x0 + 38 + whw : U32), y, 28, T.Th.soft()),
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

def Lay.parent.find(ts: List<&2, M.Task>, +thread: String) -> String:
  match ts:
    case Nil{}:
      ""
    case M.Task{_, p, +c, _, _, _, _, _, _} <> t:
      Bool.pick(String, String.eq(c, thread), p, Lay.parent.find(t, thread))

def Lay.parent.of(+st: M.State, +thread: String) -> String:
  match st:
    case M.State{_, _, _, _, tk, _}:
      Lay.parent.find(Map.values(&2, M.Task, tk), thread)

def Lay.parent.k(+ty: Ty, +p: String, +st: M.State, +x0: U32, +y: U32) -> Out:
  +label = "← delegated by " ++ Tasks.title(st, p)
  Out.when(Bool.not(String.is_empty(p)),
    Out{Ty.text(ty, 2n, label, D.Clip.all(), x0, y, 28, T.Th.accent()), [Lay.hit(x0, y, (Ty.width(ty, 2n, label) + 8 : U32), 28, "select", p)]})

# a child thread links back to its parent
def Lay.parent(+ty: Ty, +st: M.State, +thread: String, +x0: U32, +y: U32) -> Out:
  Lay.parent.k(ty, Lay.parent.of(st, thread), st, x0, y)

def Lay.thread.k(+ty: Ty, t: M.Thread, +draft: String, +st: M.State, +sel: String, +live: String, +caret: Nat, +focused: Bool,
    +x0: U32, +x1: U32, +h: U32, +sc: U32, pa: Bool, +info: String, +picking: Bool) -> Out:
  match t:
    case M.Thread{id, p, ti, c, a, +turn, pe, ar, o, sa, ua, pi, en, br, wt, +pr, +mo, rm, im, se, de}:
      +cw = {U32.min((x1 - x0 - 64 : U32), 780) : U32}
      +cx0 = {(x0 + U32.shr((x1 - x0 - cw : U32)) : U32) : U32}
      +cx1 = {(cx0 + cw : U32) : U32}
      +ts = Tasks.of(st, sel)
      +pl = {Bool.pick(U32, String.is_empty(Lay.parent.of(st, sel)), 0, 32) : U32}
      +top = {(52 + pl + Tasks.height(ts) : U32) : U32}
      Lay.timeline(ty,
        List.append(&2, TLine, TL.entries(ty, TL.mine(U.Ui.entries(st), sel, Nil{}), cw),
          TL.live.k(ty, String.is_empty(live), Lay.running(turn), live, cw)),
        cx0, cx1, top, h, sc,
        Out.all([Lay.header(ty, M.Thread{id, p, ti, c, a, turn, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de}, x0, x1, pa),
          Lay.parent(ty, st, sel, cx0, 58),
          Lay.tasks(ty, ts, st, cx0, cx1, (60 + pl : U32)),
          Lay.composer(ty, draft, caret, focused, cx0, cx1, h, Lay.running(turn), Models.label(pr, mo), picking, Models.list(info, pr), mo)]))

def Lay.thread(+ty: Ty, +n: S.Nui, +x0: U32, +x1: U32) -> Out:
  match n:
    case S.Nui{U.Ui{+st, +sel, _, +live, +op, _, _, _, pa, _, _, _, _, _, +nf}, _, +h, _, _, _, +sc, +caret, +focus, _, _, _, _}:
      Lay.thread.k(ty, U.Ui.thread(st, sel), U.Ui.draft_text(S.Nui.ui(n)), st, sel, U.Str.get(live, sel), caret, String.eq(focus, "composer"), x0, x1, h, sc, pa,
        U.Str.get(nf, "models"), U.Flag.get(op, "models"))

def Lay.empty(+ty: Ty, +x0: U32, +x1: U32, +h: U32, +n: Nat) -> Out:
  +msg = Bool.pick(String, Nat.is_eq(n, 0n), "Add a project with + to start.", "Pick a thread, or start one with + next to a project.")
  Out.ops(Ty.text(ty, 3n, msg, D.Clip.all(), (x0 + U32.shr((x1 - x0 - Ty.width(ty, 3n, msg) : U32)) : U32), (U32.shr(h) - 12 : U32), 23, T.Th.faint()))

# Settings
# --------

def Set.head(+ty: Ty, +label: String, +x: U32, +y: U32) -> Out:
  Out.ops(Ty.text(ty, 1n, label, D.Clip.all(), x, y, 28, T.Th.text()))

# a row whose right `rw` pixels hold controls
def Set.row.r(+ty: Ty, +label: String, +note: String, +x: U32, +y: U32, +w: U32, +rw: U32) -> Out:
  Out.ops(List.append(&2, R.Op, Ty.text(ty, 0n, Ty.fit(ty, 0n, label, U32.sub(w, (32 + rw : U32))), D.Clip.all(), (x + 16 : U32), y, 28, T.Th.soft()),
    Ty.text(ty, 2n, Ty.fit(ty, 2n, note, U32.sub(w, (32 + rw : U32))), D.Clip.all(), (x + 16 : U32), (y + 24 : U32), 20, T.Th.faint())))

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
  +ms = {"" <> Models.list(U.Str.get(info, "models"), prov) : List<&2, String>}
  +dy = {(Set.rows(ty, ms, (x + 16 : U32), (x + w - 16 : U32), (x + 16 : U32)) * 34 : U32) : U32}
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
    Set.row(ty, "Provider and model for new threads", "Each thread keeps its own; change it from the composer.", x, 226, w),
    Set.chips(ty, ["claude", "codex"], prov, "agent.provider", (x + 16 : U32), (x + w - 16 : U32), (x + 16 : U32), 274),
    Set.chips(ty, ms, M.Setting.get(st, "agent.model", ""), "agent.model", (x + 16 : U32), (x + w - 16 : U32), (x + 16 : U32), 308),
    Set.head(ty, "KiCad", x, (368 + dy : U32)),
    Set.card(x, (400 + dy : U32), w, 150),
    Set.row(ty, "KiCad CLI", U.Str.get(info, "kicad.cli"), x, (402 + dy : U32), w),
    Set.fork(ty, U.Str.get(info, "kicad.fork"), (x + 16 : U32), (450 + dy : U32)),
    Set.row.r(ty, "KiCad IPC", "Agents may drive KiCad through the fork's api-server (NNG/protobuf).", x, (486 + dy : U32), w, 140),
    Lay.chip(ty, (x + w - 120 : U32), (500 + dy : U32), "On", String.eq(ipc, "on"), "setting", "kicad.ipc=on"),
    Lay.chip(ty, (x + w - 70 : U32), (500 + dy : U32), "Off", String.eq(ipc, "off"), "setting", "kicad.ipc=off"),
    Set.head(ty, "Network and updates", x, (570 + dy : U32)),
    Set.card(x, (602 + dy : U32), w, 112),
    Set.row(ty, "Tailscale: " ++ U.Str.get(info, "tailnet"), "Listening on " ++ U.Str.get(info, "listen") ++ ". Start with --tailscale to serve your tailnet.", x, (604 + dy : U32), w),
    Set.row(ty, "Backplane " ++ v, Bool.pick(String, String.is_empty(note), "Up to date, checked hourly.", note), x, (656 + dy : U32), w),
    Bool.pick(Out, String.starts_with(note, "update "), Lay.button(ty, D.Clip.all(), (x + w - 16 - Lay.button.w(ty, "Install update") : U32), (666 + dy : U32), "Install update", T.Th.accent(), "update", ""), Out.none())])

def Lay.main(+ty: Ty, +n: S.Nui, +x0: U32, +x1: U32) -> Out:
  match n:
    case S.Nui{U.Ui{+st, +sel, _, _, +op, _, _, _, _, +v, _, _, _, +note, +nf}, _, +h, _, _, _, _, _, _, _, _, _, _}:
      Bool.pick(Out, U.Flag.get(op, "settings"), Lay.settings(ty, st, nf, v, note, x0, x1, h),
        Bool.pick(Out, String.is_empty(sel), Lay.empty(ty, x0, x1, h, List.length(&2, M.Project, U.Ui.projects(st))), Lay.thread(ty, n, x0, x1)))

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
      Bool.pick(Bool, U32.is_eq(k, 3), U32.is_gt(w, 0), Bool.pick(Bool, U32.is_eq(k, 2), Bool.not(List.is_empty(&2, G.Tri3, ts)), Bool.not(empty)))

def Lay.help(+k: U32) -> String:
  Bool.pick(String, U32.is_eq(k, 3), "what the agents' browser shows, live",
    Bool.pick(String, U32.is_eq(k, 2), "drag orbit · wheel zoom · f fit", "click inspect · drag pan · wheel zoom · f fit"))

def Lay.viewer.k(+ty: Ty, +x0: U32, +x1: U32, +h: U32, +empty: Bool, x: V.Vx, +info: String, +draft: String) -> Out:
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
        Out.ops(Ty.text(ty, 2n, Ty.fit(ty, 2n, help, (x1 - x0 - 380 : U32)), D.Clip.all(), (x1 - 16 - Ty.width(ty, 2n, Ty.fit(ty, 2n, help, (x1 - x0 - 380 : U32))) : U32), 0, 52, T.Th.faint())),
        Out.when(Bool.and(Bool.not(String.is_empty(busy)), Bool.not(Lay.shown(k, empty, ts, bm))),
          Out.ops(Ty.text(ty, 3n, busy, D.Clip.all(), (x0 + U32.shr((x1 - x0 - U32.min(Ty.width(ty, 3n, busy), (x1 - x0 : U32)) : U32)) : U32), (U32.shr(h) - 12 : U32), 23, T.Th.dim()))),
        Lay.inspect(ty, info, draft, x0, x1, h)])

def Lay.picked(x: V.Vx) -> String:
  match x:
    case V.Vx{_, p, _, _, _, _, _, _, _, _, bm}:
      p

def Lay.viewer.vw(+ty: Ty, v: V.Vw, +draft: String, +x0: U32, +x1: U32, +h: U32) -> Out:
  match v:
    case V.Vw{+ss, _, _, _, _, _, _, _, _, _, +vx}:
      Lay.viewer.k(ty, x0, x1, h, List.is_empty(&2, V.Seen, ss), vx, V.Pick.info(ss, Lay.picked(vx)), draft)

# the viewer's chrome; the scene under it is drawn by the viewer
def Lay.viewer(+ty: Ty, +n: S.Nui, +x0: U32, +x1: U32, +h: U32) -> Out:
  Lay.viewer.vw(ty, S.Nui.vw(n), U.Ui.draft_text(S.Nui.ui(n)), x0, x1, h)

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

def Lay.note.k(+ty: Ty, empty: Bool, offer: Bool, +note: String, +x: U32) -> Out:
  match empty offer:
    case True{} _:
      Out.none()
    case False{} True{}:
      Out{List.append(&2, R.Op, Lay.round(D.Clip.all(), x, 16, (Ty.width(ty, 2n, note) + 16 : U32), 20, 10, T.Th.sel()),
          Ty.text(ty, 2n, note, D.Clip.all(), (x + 8 : U32), 16, 20, T.Th.accent())),
        [Lay.hit(x, 16, (Ty.width(ty, 2n, note) + 16 : U32), 20, "update", "")]}
    case False{} False{}:
      Out.ops(Ty.text(ty, 2n, note, D.Clip.all(), x, 16, 20, T.Th.warn()))

# an update to offer (clickable) or one being applied (status only)
def Lay.note(+ty: Ty, +note: String, +v: String) -> Out:
  Lay.note.k(ty, String.is_empty(note), String.starts_with(note, "update "), note, (30 + Ty.width(ty, 1n, "Backplane") + Ty.width(ty, 2n, "v" ++ v) + 16 : U32))

def Lay.sidebar(+ty: Ty, +n: S.Nui, +h: U32) -> Out:
  match n:
    case S.Nui{U.Ui{+st, +sel, _, _, +open, on, +now, adding, _, +v, _, _, _, +note, _}, _, _, _, _, +sd, _, +caret, +focus, +path, _, _, vw}:
      Out.cat(Lay.sidebar.k(ty, D.Clip{0, 52, 264, h}, st, sel, open, on, now, adding, v, sd, caret, focus, path, h, U.Flag.get(open, "settings")), Lay.note(ty, note, v))

# the whole window, topmost first
def Lay.frame(+ty: Ty, +n: S.Nui) -> Out:
  match n:
    case S.Nui{U.Ui{_, _, _, _, _, _, _, _, +pa, _, _, _, +err, note, _}, +w, +h, _, _, _, _, _, _, _, _, _, _}:
      Lay.rev(Out.all([
        Out.when(pa, Out.ops([D.Draw.rect(D.Clip.all(), 264, 0, U32.shr((w - 264 : U32)), h, T.Th.bg(), 255)])),
        Lay.main(ty, n, 264, Bool.pick(U32, pa, (264 + U32.shr((w - 264 : U32)) : U32), w)),
        Bool.pick(Out, pa, Lay.viewer(ty, n, (264 + U32.shr((w - 264 : U32)) : U32), w, h), Out.none()),
        Lay.sidebar(ty, n, h),
        Lay.toast(ty, err, w, h)]))
