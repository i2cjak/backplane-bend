import Base
import ../core/model.bend as M
import ../core/json.bend as J
import ../core/client.bend as U
import ../core/edit.bend as ED
import ../core/images.bend as IM
import ../core/links.bend as LK
import ../gfx/raster.bend as R
import ../gfx/draw.bend as D
import ../gfx/text.bend as X
import ../gfx/icon.bend as IC
import ../web/dom.bend as N
import ./theme.bend as T
import ./nui.bend as S
import ./viewer.bend as V
import ../core/board.bend as B
import ../core/schematic.bend as SC
import ../core/hier.bend as HI
import ../core/glb.bend as G
import ../gfx/bitmap.bend as BM
import ../core/diff.bend as DF
import ../core/vt.bend as VT
import ../core/attach.bend as AT
import ../core/eq.bend as Q
import ../core/fold.bend as FO
import ../core/menu.bend as MN
import ../core/badge.bend as BG

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

def Out.hits_below.k(keep: Bool, h: S.Hit, rest: List<&2, S.Hit>) -> List<&2, S.Hit>:
  match keep:
    case True{}:
      h <> rest
    case False{}:
      rest

def Out.hits_below.go(hs: List<&2, S.Hit>, +top: U32) -> List<&2, S.Hit>:
  match hs:
    case Nil{}:
      Nil{}
    case S.Hit{+x0, +y0, +x1, +y1, +a, +v} <> t:
      Out.hits_below.k(U32.is_ge(y0, top), S.Hit{x0, y0, x1, y1, a, v}, Out.hits_below.go(t, top))

# o with only the hits that start at or below top (what scrolled under a
# header cannot be clicked through it)
def Out.hits_below(+top: U32, o: Out) -> Out:
  match o:
    case Out{os, hs}:
      Out{os, Out.hits_below.go(hs, top)}

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
    +c : Map<&2, X.TG> <- Ty.fonts.warm([ui, bold, meta, code], Map.new(&2, X.TG))
    return Ty{IC.Ico.warm(c, 16), X.Face.tabled(ui, c), X.Face.tabled(bold, c), X.Face.tabled(meta, c), X.Face.tabled(ui, c), X.Face.tabled(code, c)}

# Shapes
# ------

# a - b, or 0 when b is larger (U32 subtraction wraps)
def U32.dim(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, U32.is_gt(a, b), (a - b : U32), 0)

def Lay.hit(+x: U32, +y: U32, +w: U32, +h: U32, action: String, value: String) -> S.Hit:
  S.Hit{x, y, (x + w : U32), (y + h : U32), action, value}

# a Nat position (core/menu.bend's boxes) as a pixel
def Picker.px(+n: Nat) -> U32:
  U32.from_nat(n)

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

# an icon (core/icons.bend) at 16 px with its top-left at (x, y)
def Lay.icon(+ty: Ty, +name: String, +c: D.Clip, +x: U32, +y: U32, +color: U32) -> List<&2, R.Op>:
  IC.Ico.op(Ty.cache(ty), name, 16, c, x, y, color)

# a square 28 px button holding an icon
def Lay.ibutton(+ty: Ty, +c: D.Clip, +x: U32, +y: U32, +name: String, +color: U32, action: String, value: String) -> Out:
  Out{List.append(&2, R.Op, Lay.box(c, x, y, 28, 28, 6, T.Th.raise(), T.Th.line()), Lay.icon(ty, name, c, (x + 6 : U32), (y + 6 : U32), color)),
    [Lay.hit(x, y, 28, 28, action, value)]}

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

# a thread's row; the selected one is raised, with its project's colour
# (tint) down its left edge
def Lay.row.k(+ty: Ty, +on: Bool, id: String, title: String, +ago: String, +dot: U32, +tint: U32, +c: D.Clip, +y: U32) -> Out:
  +aw = Ty.width(ty, 2n, ago)
  Out{List.concat(&2, R.Op, [
      Bool.pick(List<&2, R.Op>, on, List.append(&2, R.Op, Lay.round(c, 6, (y + 1 : U32), 252, 30, 6, T.Th.raise()), [D.Draw.rect(c, 6, (y + 1 : U32), 2, 30, tint, 255)]), Nil{}),
      [D.Draw.disc(c, 19.0, U32.to_f32((y + 16 : U32)), 3.0, dot, 255)],
      Ty.text(ty, 0n, Ty.fit(ty, 0n, title, (252 - 32 - aw - 12 : U32)), c, 32, y, 32, Bool.pick(U32, on, T.Th.text(), T.Th.soft())),
      Ty.text(ty, 2n, ago, c, (252 - aw : U32), y, 32, T.Th.faint())]),
    [Lay.hit(0, y, 264, 32, "select", id)]}

# a sidebar row; a snoozed one shows the time left instead of its age
def Lay.row(+ty: Ty, +t: M.Thread, +st: M.State, +sel: String, +now: Nat, +snoozed: Bool, +c: D.Clip, +y: U32) -> Out:
  match t:
    case M.Thread{+id, +p, title, _, +a, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      Lay.row.k(ty, String.eq(id, sel), id, title, Bool.pick(String, snoozed, U.Time.ago(U.Side.until(st, id), now), U.Time.ago(now, a)), Lay.status(U.Side.status(st, t)), BG.Badge.rgb_of(st, p), c, y)

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
      Lay.col.cat(Out{List.append(&2, R.Op, Lay.icon(ty, "chevron-down", c, 12, (y + 6 : U32), T.Th.dim()), Ty.text(ty, 2n, label, c, 32, y, 28, T.Th.dim())), [Lay.hit(0, y, 264, 28, "toggle-settled", key)]},
        Lay.rows(ty, ts, st, sel, now, False{}, c, (y + 28 : U32)))
    case False{}:
      Col{Out{List.append(&2, R.Op, Lay.icon(ty, "chevron-right", c, 12, (y + 6 : U32), T.Th.faint()), Ty.text(ty, 2n, label, c, 32, y, 28, T.Th.faint())), [Lay.hit(0, y, 264, 28, "toggle-settled", key)]}, (y + 28 : U32)}

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

# A project's badge editor, open under its name: the tints, then the
# icons, each set placed by the flow in core/menu.bend (law
# menu_chips_apart), so neither set ever overlaps itself or the other
def Look.n(n: Nat, +w: Nat) -> List<&2, Nat>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      w <> Look.n(k, w)

def Look.swatches(bs: List<&2, MN.Box>, cs: List<&2, String>, +cur: String, +id: String, +c: D.Clip) -> Out:
  match bs:
    case Nil{}:
      Out.none()
    case MN.Box{+x, +y, +w, +h} <> bt:
      match cs:
        case Nil{}:
          Out.none()
        case +k <> ct:
          Out.cat(Out{List.append(&2, R.Op,
              Bool.pick(List<&2, R.Op>, String.eq(k, cur), [D.Draw.rect(c, Picker.px(Nat.sub(x, 2n)), Picker.px(Nat.sub(y, 2n)), Picker.px(Nat.add(w, 4n)), Picker.px(Nat.add(h, 4n)), T.Th.text(), 255)], Nil{}),
              [D.Draw.rect(c, Picker.px(x), Picker.px(y), Picker.px(w), Picker.px(h), BG.Badge.rgb(k), 255)]),
              [Lay.hit(Picker.px(x), Picker.px(y), Picker.px(w), Picker.px(h), "look-set", BG.Badge.color_key(id) ++ "=" ++ k)]},
            Look.swatches(bt, ct, cur, id, c))

def Look.icons(+ty: Ty, bs: List<&2, MN.Box>, ns: List<&2, String>, +cur: String, +id: String, +tint: U32, +c: D.Clip) -> Out:
  match bs:
    case Nil{}:
      Out.none()
    case MN.Box{+x, +y, _, _} <> bt:
      match ns:
        case Nil{}:
          Out.none()
        case +k <> nt:
          Out.cat(Out{List.append(&2, R.Op,
              Lay.box(c, Picker.px(x), Picker.px(y), 28, 28, 0, Bool.pick(U32, String.eq(k, cur), T.Th.sel(), T.Th.raise()), Bool.pick(U32, String.eq(k, cur), tint, T.Th.line())),
              Lay.icon(ty, k, c, Picker.px(Nat.add(x, 6n)), Picker.px(Nat.add(y, 6n)), Bool.pick(U32, String.eq(k, cur), tint, T.Th.dim()))),
              [Lay.hit(Picker.px(x), Picker.px(y), 28, 28, "look-set", BG.Badge.icon_key(id) ++ "=" ++ k)]},
            Look.icons(ty, bt, nt, cur, id, tint, c))

def Look.panel(+ty: Ty, +st: M.State, +id: String, +c: D.Clip, +y: U32) -> Col:
  +sws = Look.n(List.length(&2, String, BG.Badge.colors()), 18n)
  +iws = Look.n(List.length(&2, String, BG.Badge.icons()), 28n)
  +y0 = {Nat.add(U32.to_nat(y), 12n) : Nat}
  +y1 = {Nat.add(MN.Flow.under(sws, 18n, 248n, 18n, y0, 18n, 5n), 5n) : Nat}
  +y2 = MN.Flow.under(iws, 18n, 248n, 18n, y1, 28n, 4n)
  +hh = {Nat.sub(Nat.add(y2, 6n), U32.to_nat(y)) : Nat}
  Col{Out.all([
      Out{Lay.box(c, 8, (y + 2 : U32), 248, Picker.px(Nat.sub(hh, 2n)), 0, T.Th.raise(), T.Th.line()), [Lay.hit(8, (y + 2 : U32), 248, Picker.px(Nat.sub(hh, 2n)), "look-bg", id)]},
      Look.swatches(MN.Flow.place(sws, 18n, 248n, 18n, y0, 18n, 5n), BG.Badge.colors(), BG.Badge.color(st, id), id, c),
      Look.icons(ty, MN.Flow.place(iws, 18n, 248n, 18n, y1, 28n, 4n), BG.Badge.icons(), BG.Badge.icon(st, id), id, BG.Badge.rgb_of(st, id), c)]),
    Picker.px(Nat.add(U32.to_nat(y), Nat.add(hh, 6n)))}

def Look.open(open: Bool, +ty: Ty, +st: M.State, +id: String, +c: D.Clip, +y: U32) -> Col:
  match open:
    case True{}:
      Look.panel(ty, st, id, c, y)
    case False{}:
      Col{Out.none(), y}

# a project's name under its badge's icon (a click opens the editor; its
# hit starts past x 10, where a drag drops onto the header), its
# + for a new thread, the editor when open, then its threads
def Lay.project(+ty: Ty, r: U.SRow, +open: Map<&2, Bool>, +st: M.State, +sel: String, +now: Nat, +look: String, +c: D.Clip, +y: U32) -> Col:
  match r:
    case U.SRow{_, M.Project{+id, title, _, _, _}, M.Shelves{pinned, active, settled, hidden, snoozed}}:
      Lay.col.cat(Out.all([Out{Ty.text(ty, 2n, Ty.fit(ty, 2n, title, 180), c, 38, (y + 4 : U32), 28, T.Th.dim()), [Lay.hit(0, y, 228, 32, "project", id)]},
          Out{Lay.icon(ty, BG.Badge.icon(st, id), c, 14, (y + 10 : U32), BG.Badge.rgb_of(st, id)), [Lay.hit(12, (y + 4 : U32), 24, 28, "look", id)]},
          Out{Lay.icon(ty, "plus", c, 236, (y + 10 : U32), T.Th.faint()), [Lay.hit(230, (y + 4 : U32), 28, 28, "new-thread", id)]}]),
        Lay.col.then(Look.open(String.eq(look, id), ty, st, id, c, (y + 32 : U32)), y0 =>
        Lay.col.then(Lay.rows(ty, pinned, st, sel, now, False{}, c, y0), y1 =>
          Lay.col.then(Lay.rows(ty, active, st, sel, now, False{}, c, y1), y2 =>
            Lay.col.then(Lay.snoozed(ty, snoozed, st, sel, now, c, y2), y3 =>
              Lay.col.then(Lay.shelf(ty, U.Flag.get(open, id), id, "Settled", settled, st, sel, now, c, y3), y4 =>
                Lay.shelf(ty, U.Flag.get(open, "arch:" ++ id), "arch:" ++ id, "Archived", M.Archive.of(hidden), st, sel, now, c, y4)))))))

def Lay.projects(+ty: Ty, rs: List<&2, U.SRow>, +open: Map<&2, Bool>, +st: M.State, +sel: String, +now: Nat, +look: String, +c: D.Clip, +y: U32) -> Col:
  match rs:
    case Nil{}:
      Col{Out.none(), y}
    case r <> t:
      Lay.col.then(Lay.project(ty, r, open, st, sel, now, look, c, y), y2 => Lay.projects(ty, t, open, st, sel, now, look, c, (y2 + 8 : U32)))

def Lay.field(+ty: Ty, +c: D.Clip, +x: U32, +y: U32, +w: U32, +text: String, +focused: Bool, +blink: Bool, +caret: Nat, +mark: Nat, +placeholder: String, +id: String) -> Out:
  +vis = Ty.fit(ty, 2n, text, (w - 16 : U32))
  +a = {Ty.width(ty, 2n, String.take(vis, ED.Edit.lo(caret, mark))) : U32}
  +b = {Ty.width(ty, 2n, String.take(vis, ED.Edit.hi(caret, mark))) : U32}
  Out{List.concat(&2, R.Op, [
      Lay.box(c, x, y, w, 28, 6, T.Th.bg(), Bool.pick(U32, focused, T.Th.accent(), T.Th.line())),
      Bool.pick(List<&2, R.Op>, Bool.and(focused, U32.is_gt(b, a)), [D.Draw.rect(c, (x + 8 + a : U32), (y + 5 : U32), (b - a : U32), 18, T.Th.sel(), 255)], Nil{}),
      Bool.pick(List<&2, R.Op>, String.is_empty(text), Ty.text(ty, 2n, placeholder, c, (x + 8 : U32), y, 28, T.Th.faint()),
        Ty.text(ty, 2n, vis, c, (x + 8 : U32), y, 28, T.Th.text())),
      Bool.pick(List<&2, R.Op>, Bool.and(focused, blink), [D.Draw.rect(c, (x + 8 + Ty.width(ty, 2n, String.take(vis, caret)) : U32), (y + 7 : U32), 1, 14, T.Th.accent(), 255)], Nil{})]),
    [Lay.hit(x, y, w, 28, "focus", id)]}

def Lay.adding(+ty: Ty, adding: Bool, +path: String, +focused: Bool, +caret: Nat, +mark: Nat) -> Out:
  match adding:
    case True{}:
      Out.cat(Lay.field(ty, D.Clip.all(), 12, 58, 186, path, focused, True{}, caret, mark, "/path/to/project", "project-path"),
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

# Machines
# --------
# With more than one machine, a row under the header names the one shown
# and opens the list to switch.

def Mach.rows(+ty: Ty, rs: List<&2, U.MRow>, +y: U32) -> Out:
  match rs:
    case Nil{}:
      Out.none()
    case U.MRow{+n, +url, +on} <> t:
      Out.cat(Out{List.append(&2, R.Op,
          [D.Draw.disc(D.Clip.all(), 22.0, U32.to_f32((y + 15 : U32)), 3.0, Bool.pick(U32, on, T.Th.accent(), T.Th.line()), 255)],
          Ty.text(ty, 2n, Ty.fit(ty, 2n, n, 200), D.Clip.all(), 34, y, 30, Bool.pick(U32, on, T.Th.text(), T.Th.soft()))),
          [Lay.hit(4, y, 256, 30, "machine", url)]},
        Mach.rows(ty, t, (y + 30 : U32)))

def Mach.menu(+ty: Ty, open: Bool, +rs: List<&2, U.MRow>) -> Out:
  match open:
    case True{}:
      Out.cat(Out.ops(Lay.box(D.Clip.all(), 4, 88, 256, (U32.from_nat(List.length(&2, U.MRow, rs)) * 30 + 8 : U32), 0, T.Th.raise(), T.Th.line())),
        Mach.rows(ty, rs, 92))
    case False{}:
      Out.none()

def Mach.bar.k(any: Bool, +ty: Ty, +rs: List<&2, U.MRow>) -> Out:
  match any:
    case True{}:
      Out{List.concat(&2, R.Op, [[D.Draw.rect(D.Clip.all(), 0, 87, 264, 1, T.Th.line(), 255)],
          Ty.text(ty, 2n, Ty.fit(ty, 2n, U.Machines.current(rs), 200), D.Clip.all(), 16, 52, 36, T.Th.text()),
          Lay.icon(ty, "chevron-down", D.Clip.all(), 236, 62, T.Th.dim())]), [Lay.hit(0, 52, 263, 36, "flag", "machines")]}
    case False{}:
      Out.none()

# how far the machine row pushes the projects down
def Mach.h(any: Bool) -> U32:
  Bool.pick(U32, any, 36, 0)

# Hotkey hints: while alt or ctrl is held (nui.bend's Hint) each row a
# number reaches shows it: projects by their new-thread button, threads by
# their row. The numbers come from the lists the keys count in.

def Lay.badge(+ty: Ty, +c: D.Clip, +y0: U32, +y1: U32, +k: Nat) -> List<&2, R.Op>:
  +s = Nat.show(k)
  +y = {(y0 + (((y1 - y0 : U32) - 20 : U32) / 2 : U32) : U32) : U32}
  List.append(&2, R.Op, [D.Draw.rect(c, 230, y, 22, 20, T.Th.accent(), 255)],
    Ty.text(ty, 2n, s, c, (241 - (Ty.width(ty, 2n, s) / 2 : U32) : U32), y, 20, T.Th.bg()))

def Lay.badge.k(on: Bool, +ty: Ty, +c: D.Clip, +y0: U32, +y1: U32, +k: Nat) -> List<&2, R.Op>:
  match on:
    case True{}:
      Lay.badge(ty, c, y0, y1, k)
    case False{}:
      Nil{}

def Lay.badge.at(+a: String, +act: String, +ty: Ty, +c: D.Clip, +y0: U32, +y1: U32, +k: Nat) -> List<&2, R.Op>:
  Lay.badge.k(Bool.and(String.eq(a, act), Bool.and(Nat.is_gt(k, 0n), Nat.is_le(k, 9n))), ty, c, y0, y1, k)

def Lay.badges(+ty: Ty, +c: D.Clip, hs: List<&2, S.Hit>, +act: String, +ids: List<&2, String>) -> List<&2, R.Op>:
  match hs:
    case Nil{}:
      Nil{}
    case S.Hit{_, +y0, _, +y1, +a, +v} <> t:
      List.append(&2, R.Op, Lay.badge.at(a, act, ty, c, y0, y1, U.Side.num(ids, v, 0n)), Lay.badges(ty, c, t, act, ids))

def Lay.hints.o(o: Out, +ty: Ty, +c: D.Clip, +act: String, +ids: List<&2, String>) -> Out:
  match o:
    case Out{ops, +hs}:
      Out{List.append(&2, R.Op, ops, Lay.badges(ty, c, hs, act, ids)), hs}

def Lay.hints.k(on: Bool, o: Out, +ty: Ty, +c: D.Clip, +alt: Bool, +ids: List<&2, String>) -> Out:
  match on:
    case True{}:
      Lay.hints.o(o, ty, c, Bool.pick(String, alt, "new-thread", "select"), ids)
    case False{}:
      o

def Lay.hints(+hint: String, o: Out, +ty: Ty, +c: D.Clip, +ids: List<&2, String>) -> Out:
  Lay.hints.k(Bool.not(String.is_empty(hint)), o, ty, c, String.eq(hint, "alt"), ids)

# the list a held key counts in
def Lay.hint.ids(alt: Bool, ctrl: Bool, +u: U.Ui) -> List<&2, String>:
  match alt ctrl:
    case True{} _:
      U.Side.projects(u)
    case False{} True{}:
      U.Side.here(u)
    case False{} False{}:
      Nil{}

def Lay.sidebar.k(+ty: Ty, +c: D.Clip, +st: M.State, +sel: String, +open: Map<&2, Bool>, on: Bool, +now: Nat, +adding: Bool, +v: String,
    +sd: U32, +caret: Nat, +mark: Nat, +focus: String, +path: String, +h: U32, +settings: Bool, +ms: List<&2, U.MRow>, +hint: String, +ids: List<&2, String>, +look: String) -> Out:
  +top = {D.Clip{0, 0, 264, 52} : D.Clip}
  +many = Nat.is_gt(List.length(&2, U.MRow, ms), 1n)
  +y0 = {(Bool.pick(U32, adding, 96, 60) + Mach.h(many) : U32) : U32}
  Out.all([
    Out.ops([D.Draw.rect(D.Clip.all(), 0, 0, 264, h, T.Th.panel(), 255), D.Draw.rect(D.Clip.all(), 263, 0, 1, h, T.Th.line(), 255),
      D.Draw.rect(top, 0, 51, 264, 1, T.Th.line(), 255),
      D.Draw.disc(top, 19.0, 26.0, 3.5, Bool.pick(U32, on, T.Th.ok(), T.Th.bad()), 255)]),
    Out.ops(List.append(&2, R.Op, Ty.text(ty, 1n, "Backplane", top, 30, 0, 52, T.Th.text()),
      Ty.text(ty, 2n, "v" ++ v, top, (30 + Ty.width(ty, 1n, "Backplane") + 8 : U32), 0, 52, T.Th.faint()))),
    Out{Lay.icon(ty, "plus", top, 234, 18, T.Th.dim()), [Lay.hit(228, 12, 28, 28, "vw-projo", "")]},
    Lay.adding(ty, adding, path, String.eq(focus, "project-path"), caret, mark),
    Links.over(Lay.hints(hint, Lay.col.out(Lay.projects(ty, U.Side.rows(st, now), open, st, sel, now, look,
      D.Clip{0, y0, 264, (h - 48 : U32)}, U32.sub(y0, sd))), ty, D.Clip{0, y0, 264, (h - 48 : U32)}, ids), U.Links.recent(st, now), now, D.Clip{0, y0, 264, (h - 48 : U32)}),
    Out{List.append(&2, R.Op, [D.Draw.rect(D.Clip.all(), 0, (h - 48 : U32), 263, 48, T.Th.panel(), 255), D.Draw.rect(D.Clip.all(), 0, (h - 48 : U32), 263, 1, T.Th.line(), 255)],
        List.append(&2, R.Op, Lay.icon(ty, "settings", D.Clip.all(), 16, (h - 32 : U32), Bool.pick(U32, settings, T.Th.text(), T.Th.dim())), Ty.text(ty, 2n, "Settings", D.Clip.all(), 40, (h - 48 : U32), 48, Bool.pick(U32, settings, T.Th.text(), T.Th.dim())))),
      [Lay.hit(0, (h - 48 : U32), 263, 48, "flag", "settings")]},
    Mach.bar.k(many, ty, ms),
    Mach.menu(ty, Bool.and(many, U.Flag.get(open, "machines")), ms)])

# Timeline
# --------

# one laid-out line. kind: 0 text, 1 code, 2 user, 3 activity, 4 gap,
# 5 heading, 6 user padding, 7 footer with a Copy button, 8 code header,
# 9 code bottom, 10 a message sent to another thread, 11 the thread a
# message came from (copy holds the other thread), 12 an image row, 13 a
# line with links, 14 a run of tool calls folded into one row (copy holds
# what a click asks, FO.Fold.ask; w is 1 when the run is open). w is a user
# bubble's width
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
    case 12n:
      20
    case 13n:
      23
    case 14n:
      24
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

# the links (<a>) of a node list, in order
def Nd.href(xs: List<&2, N.Attr>) -> String:
  match xs:
    case Nil{}:
      ""
    case N.At{"href", v} <> _:
      v
    case _ <> t:
      Nd.href(t)

def Nd.links(ns: List<&2, N.Node>) -> List<&2, LK.Piece>:
  match ns:
    case Nil{}:
      Nil{}
    case N.Txt{_} <> t:
      Nd.links(t)
    case N.El{"a", _, +at, +ks} <> t:
      LK.PLink{Nd.plain(ks), Nd.href(at)} <> Nd.links(t)
    case N.El{_, _, _, ks} <> t:
      List.append(&2, LK.Piece, Nd.links(ks), Nd.links(t))

# Links
# -----
# A paragraph with links lays out as kind 13 lines: the paragraph's links
# ride in the line's copy field (LK.Link.enc); drawing cuts each line into
# runs (LK.Link.cut) and each link run hits "open-url" with its address.

def TL.linked.k(+none: Bool, ls: List<&2, String>, +color: U32, +enc: String) -> List<&2, TLine>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> t:
      TLine{l, color, Bool.pick(U32, none, 0, 13), Bool.pick(String, none, "", enc), 0} <> TL.linked.k(none, t, color, enc)

def TL.linked(ls: List<&2, String>, +color: U32, +enc: String) -> List<&2, TLine>:
  TL.linked.k(String.is_empty(enc), ls, color, enc)

def TL.link.w(+ty: Ty, p: LK.Piece) -> U32:
  match p:
    case LK.PText{s}:
      Ty.width(ty, 3n, s)
    case LK.PLink{l, _}:
      Ty.width(ty, 3n, l)

def TL.link.seg(+ty: Ty, p: LK.Piece, +c: D.Clip, +x: U32, +y: U32, +color: U32) -> Out:
  match p:
    case LK.PText{s}:
      Out.ops(Ty.text(ty, 3n, s, c, x, y, 23, color))
    case LK.PLink{+l, u}:
      Out{D.Draw.rect(c, x, (y + 19 : U32), Ty.width(ty, 3n, l), 1, T.Th.accent(), 255) <> Ty.text(ty, 3n, l, c, x, y, 23, T.Th.accent()),
        [Lay.hit(x, y, Ty.width(ty, 3n, l), 23, "open-url", u)]}

def TL.link.segs(ps: List<&2, LK.Piece>, +ty: Ty, +c: D.Clip, +x: U32, +y: U32, +color: U32) -> Out:
  match ps:
    case Nil{}:
      Out.none()
    case +p <> t:
      Out.cat(TL.link.seg(ty, p, c, x, y, color), TL.link.segs(t, ty, c, (x + TL.link.w(ty, p) : U32), y, color))

def TL.texts(ls: List<&2, String>, +color: U32, +kind: U32) -> List<&2, TLine>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> t:
      TLine{l, color, kind, "", 0} <> TL.texts(t, color, kind)

def TL.bullets(ls: List<&2, String>, first: Bool, +enc: String) -> List<&2, TLine>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> t:
      TLine{Bool.pick(String, first, "•  ", "   ") ++ l, T.Th.soft(), Bool.pick(U32, String.is_empty(enc), 0, 13), enc, 0} <> TL.bullets(t, False{}, enc)

def TL.items(+ty: Ty, ns: List<&2, N.Node>, +px: U32) -> List<&2, TLine>:
  match ns:
    case Nil{}:
      Nil{}
    case +n <> t:
      List.append(&2, TLine, TL.bullets(Ty.wrap(ty, 3n, Nd.plain([n]), (px - 24 : U32)), True{}, LK.Link.enc(Nd.links([n]))), TL.items(ty, t, px))

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
      TL.linked(Ty.wrap(ty, 3n, Nd.plain(ks), px), T.Th.soft(), LK.Link.enc(Nd.links(ks)))
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

# Images
# ------
# An image a reply names takes whole 20 px lines. Each of its lines hits
# the image's full rectangle ("img"), so the window draws the image (under
# the UI, from the frame's base) whenever any part of it is in view. The
# window notes each image's state in the client info as "img:<path>":
# "<w>x<h>" once decoded (its size, shrunk to fit), "err:<why>", or nothing
# while it loads.

def TL.img.rows(k: Nat, +i: Nat, +size: String, +path: String) -> List<&2, TLine>:
  match k:
    case 0n:
      Nil{}
    case 1n+j:
      TLine{size, 0, 12, path, U32.from_nat(i)} <> TL.img.rows(j, 1n+i, size, path)

def TL.img.h(+size: String) -> Nat:
  Maybe.default(&2, Nat, Nat.read(Maybe.default(&2, String, List.get(&2, String, String.split(size, 'x'), 1n), "")), 0n)

def TL.img.k(state: Nat, +ty: Ty, +st: String, +path: String, +px: U32) -> List<&2, TLine>:
  match state:
    case 0n:
      [TLine{"loading " ++ Ty.fit(ty, 2n, path, (px - 80 : U32)), T.Th.faint(), 12, path, 4096}]
    case 1n:
      [TLine{Ty.fit(ty, 2n, "cannot show " ++ path ++ ": " ++ String.drop(st, 4n), px), T.Th.dim(), 3, "", 0}]
    case _:
      TL.img.rows(Nat.div(Nat.add(TL.img.h(st), 27n), 20n), 0n, st, path)

def TL.img(+ty: Ty, +st: String, +path: String, +px: U32) -> List<&2, TLine>:
  TL.img.k(Bool.pick(Nat, String.is_empty(st), 0n, Bool.pick(Nat, String.starts_with(st, "err:"), 1n, 2n)), ty, st, path, px)

def TL.images(+ty: Ty, ps: List<&2, String>, +pics: Map<&2, String>, +px: U32) -> List<&2, TLine>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      List.append(&2, TLine, TL.img(ty, U.Str.get(pics, "img:" ++ p), p, px), TL.images(ty, t, pics, px))

def TL.img.size(+size: String, +i: Nat) -> U32:
  U32.from_nat(Maybe.default(&2, Nat, Nat.read(Maybe.default(&2, String, List.get(&2, String, String.split(size, 'x'), i), "")), 0n))

# a line of an image: row k of it (4096: still loading, a note)
def TL.img.draw(loading: Bool, +ty: Ty, +text: String, +color: U32, +path: String, +k: U32, +c: D.Clip, +x0: U32, +y: U32) -> Out:
  match loading:
    case True{}:
      Out{Ty.text(ty, 2n, text, c, x0, y, 20, color), [Lay.hit(x0, y, 1, 20, "img", path)]}
    case False{}:
      Bool.pick(Out, U32.is_lt(y, (k * 20 + 8 : U32)), Out.none(),
        Out{Nil{}, [Lay.hit(x0, (y - k * 20 + 4 : U32), TL.img.size(text, 0n), TL.img.size(text, 1n), "img", path)]})

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
    case 13n:
      TL.link.segs(LK.Link.cut(text, LK.Link.dec(copy)), ty, c, x0, y, color)
    case 12n:
      TL.img.draw(U32.is_eq(bw, 4096), ty, text, color, copy, bw, c, x0, y)
    case 14n:
      Out{List.append(&2, R.Op, Lay.icon(ty, Bool.pick(String, U32.is_eq(bw, 1), "chevron-down", "chevron-right"), c, x0, (y + 4 : U32), color),
          Ty.text(ty, 2n, text, c, (x0 + 22 : U32), y, 24, color)),
        [Lay.hit(x0, y, (Ty.width(ty, 2n, text) + 26 : U32), 24, "fold", copy)]}
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

# Selecting text in the timeline
# ------------------------------
# A drag over the thread's lines selects text (nui.bend keeps where it
# began and where it is, as "@ts": thread|line,x|line,x). Here those
# points become characters: the selection is drawn over the lines it
# covers, and its text rides on a hit region no pointer can reach
# ("tl-sel"), which ctrl+c copies.

# lines la..lb (their numbers in the thread's lines), from window x xa on
# la to xb on lb; `on` is false when nothing is selected
type TSel is Data:
  TSel{on: Bool, la: Nat, xa: U32, lb: Nat, xb: U32}

def TSel.none() -> TSel:
  TSel{False{}, 0n, 0, 0n, 0}

def TSel.num(+s: String, +i: Nat) -> Nat:
  Maybe.default(&2, Nat, Nat.read(Maybe.default(&2, String, List.get(&2, String, String.split(s, ','), i), "")), 0n)

# in order: the earlier point first
def TSel.put(+la: Nat, +xa: Nat, +lb: Nat, +xb: Nat) -> TSel:
  Bool.pick(TSel, Bool.or(Nat.is_lt(la, lb), Bool.and(Nat.is_eq(la, lb), Nat.is_le(xa, xb))),
    TSel{Bool.not(Bool.and(Nat.is_eq(la, lb), Nat.is_eq(xa, xb))), la, U32.from_nat(xa), lb, U32.from_nat(xb)},
    TSel{True{}, lb, U32.from_nat(xb), la, U32.from_nat(xa)})

def TSel.parts(+ps: List<&2, String>, +thread: String) -> TSel:
  Bool.pick(TSel, Bool.and(Nat.is_eq(List.length(&2, String, ps), 3n), String.eq(Maybe.default(&2, String, List.head(&2, String, ps), ""), thread)),
    TSel.put(TSel.num(Maybe.default(&2, String, List.get(&2, String, ps, 1n), ""), 0n), TSel.num(Maybe.default(&2, String, List.get(&2, String, ps, 1n), ""), 1n),
      TSel.num(Maybe.default(&2, String, List.get(&2, String, ps, 2n), ""), 0n), TSel.num(Maybe.default(&2, String, List.get(&2, String, ps, 2n), ""), 1n)),
    TSel.none())

# the selection "@ts" holds, when it is this thread's
def TSel.of(+raw: String, +thread: String) -> TSel:
  Bool.pick(TSel, String.is_empty(raw), TSel.none(), TSel.parts(String.split(raw, '|'), thread))

# which lines hold text a selection can take, the face they are drawn in
# and where that text starts (as TL.draw.k draws them)
def TL.textual(+k: Nat) -> Bool:
  Bool.not(Bool.or(Bool.or(Bool.or(Nat.is_eq(k, 4n), Nat.is_eq(k, 6n)), Bool.or(Nat.is_eq(k, 7n), Nat.is_eq(k, 9n))), Nat.is_eq(k, 12n)))

def TL.face(+k: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_eq(k, 1n), 4n, Bool.pick(Nat, Bool.or(Bool.or(Nat.is_eq(k, 8n), Nat.is_eq(k, 3n)), Bool.or(Nat.is_eq(k, 10n), Nat.is_eq(k, 11n))), 2n,
    Bool.pick(Nat, Nat.is_eq(k, 5n), 1n, 3n)))

def TL.tx(+ty: Ty, +k: Nat, +text: String, +bw: U32, +x0: U32, +x1: U32) -> U32:
  Bool.pick(U32, Bool.or(Nat.is_eq(k, 1n), Nat.is_eq(k, 8n)), (x0 + 14 : U32), Bool.pick(U32, Nat.is_eq(k, 2n), (x1 - bw + 20 : U32),
    Bool.pick(U32, Nat.is_eq(k, 10n), (x0 + 10 : U32), Bool.pick(U32, Nat.is_eq(k, 11n), (x1 - Ty.width(ty, 2n, text) : U32), x0))))

# the characters of text before window x (text starting at tx)
def TL.col(+ty: Ty, +k: Nat, +text: String, +tx: U32, +x: U32) -> Nat:
  X.Fit.count(text, Ty.cache(ty), Ty.face(ty, TL.face(k)), (U32.dim(x, tx) * 64 + 192 : U32), 0)

# the part of line i the selection covers, as characters [a, b)
def TL.sel.a(+ty: Ty, +sel: TSel, +i: Nat, +k: Nat, +text: String, +tx: U32) -> Nat:
  match sel:
    case TSel{_, +la, +xa, _, _}:
      Bool.pick(Nat, Nat.is_eq(i, la), TL.col(ty, k, text, tx, xa), 0n)

def TL.sel.b(+ty: Ty, +sel: TSel, +i: Nat, +k: Nat, +text: String, +tx: U32) -> Nat:
  match sel:
    case TSel{_, _, _, +lb, +xb}:
      Bool.pick(Nat, Nat.is_eq(i, lb), TL.col(ty, k, text, tx, xb), String.length(text))

def TL.sel.in(+sel: TSel, +i: Nat, +k: Nat) -> Bool:
  match sel:
    case TSel{+on, +la, _, +lb, _}:
      Bool.and(Bool.and(on, TL.textual(k)), Bool.and(Nat.is_ge(i, la), Nat.is_le(i, lb)))

def TL.sel.last(+sel: TSel, +i: Nat) -> Bool:
  match sel:
    case TSel{_, _, _, +lb, _}:
      Nat.is_eq(i, lb)

def TL.sel.box(+ty: Ty, +c: D.Clip, +k: Nat, +text: String, +tx: U32, +a: Nat, +b: Nat, +more: Bool, +y: U32) -> List<&2, R.Op>:
  +x0 = {(tx + Ty.width(ty, TL.face(k), String.take(text, a)) : U32) : U32}
  +x1 = {(tx + Ty.width(ty, TL.face(k), String.take(text, b)) + Bool.pick(U32, more, 6, 0) : U32) : U32}
  Bool.pick(List<&2, R.Op>, U32.is_gt(x1, x0), [D.Draw.rect(c, x0, (y + 2 : U32), (x1 - x0 : U32), (TL.h(U32.from_nat(k)) - 4 : U32), T.Th.accent(), 70)], Nil{})

def TL.sel.draw.k(on: Bool, +ty: Ty, +sel: TSel, +i: Nat, +k: Nat, +text: String, +tx: U32, +c: D.Clip, +y: U32) -> List<&2, R.Op>:
  match on:
    case True{}:
      TL.sel.box(ty, c, k, text, tx, TL.sel.a(ty, sel, i, k, text, tx), TL.sel.b(ty, sel, i, k, text, tx), Bool.not(TL.sel.last(sel, i)), y)
    case False{}:
      Nil{}

# line i's share of the selection, drawn over it
def TL.sel.draw(+ty: Ty, +sel: TSel, +i: Nat, l: TLine, +c: D.Clip, +x0: U32, +x1: U32, +y: U32) -> Out:
  match l:
    case TLine{+text, _, +kind, _, +bw}:
      Out.ops(TL.sel.draw.k(TL.sel.in(sel, i, U32.to_nat(kind)), ty, sel, i, U32.to_nat(kind), text, TL.tx(ty, U32.to_nat(kind), text, bw, x0, x1), c, y))

def TL.sel.piece(in: Bool, +ty: Ty, +sel: TSel, +i: Nat, +k: Nat, +text: String, +tx: U32, rest: List<&2, String>) -> List<&2, String>:
  match in:
    case True{}:
      ED.Edit.slice(text, TL.sel.a(ty, sel, i, k, text, tx), TL.sel.b(ty, sel, i, k, text, tx)) <> rest
    case False{}:
      rest

# the selected text of every line it covers (in view or not)
def TL.sel.texts(ls: List<&2, TLine>, +ty: Ty, +sel: TSel, +i: Nat, +x0: U32, +x1: U32) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case TLine{+text, _, +kind, _, +bw} <> t:
      TL.sel.piece(TL.sel.in(sel, i, U32.to_nat(kind)), ty, sel, i, U32.to_nat(kind), text, TL.tx(ty, U32.to_nat(kind), text, bw, x0, x1),
        TL.sel.texts(t, ty, sel, 1n+i, x0, x1))

def TL.sel.hit.k(on: Bool, +ty: Ty, +ls: List<&2, TLine>, +sel: TSel, +x0: U32, +x1: U32) -> Out:
  match on:
    case True{}:
      Out{Nil{}, [Lay.hit(0, 0, 0, 0, "tl-sel", String.join(TL.sel.texts(ls, ty, sel, 0n, x0, x1), "\n"))]}
    case False{}:
      Out.none()

def TSel.on(+s: TSel) -> Bool:
  match s:
    case TSel{+on, _, _, _, _}:
      on

# the selected text, for ctrl+c
def TL.sel.hit(+ty: Ty, +ls: List<&2, TLine>, +sel: TSel, +x0: U32, +x1: U32) -> Out:
  TL.sel.hit.k(TSel.on(sel), ty, ls, sel, x0, x1)

# draw the lines from y down while they start above y1; i numbers them in
# the thread's lines. Each line is a "tl-line" region (under its own
# buttons and links) where a drag selects text
def TL.draw_all(+ty: Ty, ls: List<&2, TLine>, more: Bool, +c: D.Clip, +x0: U32, +x1: U32, +y: U32, +y1: U32, +i: Nat, +sel: TSel) -> Out:
  match ls more:
    case TLine{+t, +co, +k, +cp, +bw} <> +rest True{}:
      Out.all([Out{Nil{}, [Lay.hit(x0, y, (x1 - x0 : U32), TL.h(k), "tl-line", Nat.show(i))]}, TL.draw(ty, TLine{t, co, k, cp, bw}, c, x0, x1, y),
        TL.sel.draw(ty, sel, i, TLine{t, co, k, cp, bw}, c, x0, x1, y),
        TL.draw_all(ty, rest, TL.more(rest, (y + TL.h(k) : U32), y1), c, x0, x1, (y + TL.h(k) : U32), y1, 1n+i, sel)])
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

# Delete asks first: once armed it reads "Delete thread" beside Cancel
def Lay.del(on: Bool) -> List<&2, S.Hit>:
  match on:
    case True{}:
      [S.Hit{0, 0, 0, 0, "Delete thread", "delete"}, S.Hit{0, 0, 0, 0, "Cancel", "delete-no"}]
    case False{}:
      [S.Hit{0, 0, 0, 0, "Delete", "delete"}]

def Lay.header.bs(turn: M.TurnState, override: M.Override, +sa: Nat, +ua: Nat, pinned: Bool, panel: Bool, +archived: Bool, +snoozed: Bool, del: Bool) -> List<&2, S.Hit>:
  List.concat(&2, S.Hit, [
    [S.Hit{0, 0, 0, 0, Bool.pick(String, panel, "Hide viewer", "Viewer"), "panel"},
     S.Hit{0, 0, 0, 0, "Diff", "diff"}],
    Lay.del(del),
    [
     Bool.pick(S.Hit, archived, S.Hit{0, 0, 0, 0, "Unarchive", "unarchive"}, S.Hit{0, 0, 0, 0, "Archive", "archive"}),
     Bool.pick(S.Hit, snoozed, S.Hit{0, 0, 0, 0, "Snoozed", "snooze|off"}, S.Hit{0, 0, 0, 0, "Snooze", "vw-find|snooze"})],
    Lay.settle(override, Nat.is_gt(sa, ua)),
    [Lay.pin(pinned)],
    Bool.pick(List<&2, S.Hit>, Lay.running(turn), [S.Hit{0, 0, 0, 0, "Stop", "interrupt"}], Nil{})])

# the title and branch get what the buttons leave
# s fitted to px, or nothing when there is no room for a few letters
def Lay.fit_or_none(+ty: Ty, +k: Nat, +s: String, +px: U32) -> String:
  Bool.pick(String, U32.is_lt(px, 32), "", Ty.fit(ty, k, s, px))

# the thread's project badge (its icon in its colour), then the title and
# branch in what the buttons leave
def Lay.header.k(+ty: Ty, +title: String, +branch: String, +icon: String, +tint: U32, +bs: List<&2, S.Hit>, +x0: U32, +x1: U32) -> Out:
  +room = {U32.dim(U32.dim((x1 - x0 : U32), Lay.buttons.w(ty, bs)), 80) : U32}
  +t = Ty.fit(ty, 0n, title, room)
  +tw = Ty.width(ty, 0n, t)
  Out.all([
    Out.ops([D.Draw.rect(D.Clip.all(), x0, 51, (x1 - x0 : U32), 1, T.Th.line(), 255)]),
    Out.ops(Lay.icon(ty, icon, D.Clip.all(), (x0 + 24 : U32), 18, tint)),
    Out.ops(Ty.text(ty, 0n, t, D.Clip.all(), (x0 + 48 : U32), 0, 52, T.Th.text())),
    Out.ops(Ty.text(ty, 2n, Lay.fit_or_none(ty, 2n, branch, U32.dim(room, (tw + 12 : U32))), D.Clip.all(), (x0 + 60 + tw : U32), 0, 52, T.Th.faint())),
    Lay.buttons(ty, bs, 12, (x1 - 16 : U32))])

def Lay.header(+ty: Ty, t: M.Thread, +st: M.State, +x0: U32, +x1: U32, panel: Bool, +snoozed: Bool, del: Bool) -> Out:
  match t:
    case M.Thread{_, +p, +title, _, _, turn, _, +archived, override, +sa, +ua, pinned, _, +branch, _, _, _, _, _, _, _}:
      Lay.header.k(ty, title, branch, BG.Badge.icon(st, p), BG.Badge.rgb_of(st, p), Lay.header.bs(turn, override, sa, ua, pinned, panel, archived, snoozed, del), x0, x1)

def Lay.lines(+ty: Ty, ls: List<&2, String>, +c: D.Clip, +x: U32, +y: U32) -> Out:
  match ls:
    case Nil{}:
      Out.none()
    case l <> t:
      Out.cat(Out.ops(Ty.text(ty, 3n, l, c, x, y, 23, T.Th.text())), Lay.lines(ty, t, c, x, (y + 23 : U32)))

def Picker.name(+m: String) -> String:
  Bool.pick(String, String.is_empty(m), "default", m)

# the widest model name, and the widest label, in pixels
def Picker.names_w(+ty: Ty, ms: List<&2, String>) -> Nat:
  match ms:
    case Nil{}:
      0n
    case +m <> t:
      MN.Menu.max(U32.to_nat(Ty.width(ty, 2n, Picker.name(m))), Picker.names_w(ty, t))

def Picker.labels_w(+ty: Ty, ms: List<&2, String>, +info: String, +prov: String) -> Nat:
  match ms:
    case Nil{}:
      0n
    case +m <> t:
      MN.Menu.max(U32.to_nat(Ty.width(ty, 2n, U.Models.label_of(info, prov, m))), Picker.labels_w(ty, t, info, prov))

# the effort chips' widths, and all of them in a line with their gaps
def Picker.chip_ws(+ty: Ty, es: List<&2, String>) -> List<&2, Nat>:
  match es:
    case Nil{}:
      Nil{}
    case +e <> t:
      U32.to_nat(Lay.button.w(ty, U.Effort.name(e))) <> Picker.chip_ws(ty, t)

def Picker.line_w(ws: List<&2, Nat>) -> Nat:
  match ws:
    case Nil{}:
      0n
    case +w <> t:
      Nat.add(Nat.add(w, 4n), Picker.line_w(t))

# reasoning effort chips, where the flow put them
def Picker.chips(+ty: Ty, bs: List<&2, MN.Box>, es: List<&2, String>, +cur: String) -> Out:
  match bs:
    case Nil{}:
      Out.none()
    case MN.Box{+x, +y, _, _} <> bt:
      match es:
        case Nil{}:
          Out.none()
        case +e <> et:
          Out.cat(Lay.chip(ty, Picker.px(x), Picker.px(y), U.Effort.name(e), String.eq(e, cur), "effort", e), Picker.chips(ty, bt, et, cur))

# one model row: its name clipped to the name column, its label past it
def Picker.row(+ty: Ty, +m: String, +cur: String, +info: String, +prov: String, +x: Nat, +y: Nat, +w: Nat, +col: Nat) -> Out:
  +on = String.eq(m, cur)
  +nx = {Nat.add(x, 10n) : Nat}
  +lx = MN.Menu.label_x(nx, col)
  +lw = {Nat.sub(Nat.add(x, w), Nat.add(lx, 10n)) : Nat}
  Out{List.concat(&2, R.Op, [
      Bool.pick(List<&2, R.Op>, on, Lay.round(D.Clip.all(), Picker.px(x), Picker.px(y), Picker.px(w), 28, 5, T.Th.sel()), Nil{}),
      Ty.text(ty, 2n, Ty.fit(ty, 2n, Picker.name(m), Picker.px(col)), D.Clip{Picker.px(nx), Picker.px(y), Picker.px(Nat.add(nx, col)), Picker.px(Nat.add(y, 28n))},
        Picker.px(nx), Picker.px(y), 28, Bool.pick(U32, on, T.Th.text(), T.Th.soft())),
      Ty.text(ty, 2n, Lay.fit_or_none(ty, 2n, U.Models.label_of(info, prov, m), Picker.px(lw)), D.Clip{Picker.px(lx), Picker.px(y), Picker.px(Nat.add(lx, lw)), Picker.px(Nat.add(y, 28n))},
        Picker.px(lx), Picker.px(y), 28, T.Th.faint())]),
    [Lay.hit(Picker.px(x), Picker.px(y), Picker.px(w), 28, "model", m)]}

def Picker.rows(+ty: Ty, bs: List<&2, MN.Box>, ms: List<&2, String>, +cur: String, +info: String, +prov: String, +col: Nat) -> Out:
  match bs:
    case Nil{}:
      Out.none()
    case MN.Box{+x, +y, +w, _} <> bt:
      match ms:
        case Nil{}:
          Out.none()
        case +m <> mt:
          Out.cat(Picker.row(ty, m, cur, info, prov, x, y, w, col), Picker.rows(ty, bt, mt, cur, info, prov, col))

def Picker.pos(xs: List<&2, String>, +x: String, +i: Nat) -> Nat:
  match xs:
    case Nil{}:
      0n
    case +h <> t:
      Bool.pick(Nat, String.eq(h, x), i, Picker.pos(t, x, 1n+i))

# the first row shown: where the wheel left it (raw), else so the current
# model shows; never past the last page (law menu_scroll_in_list)
def Picker.off(+raw: String, +ms: List<&2, String>, +cur: String, +n: Nat, +shown: Nat) -> Nat:
  MN.Menu.off(Maybe.default(&2, Nat, Nat.read(raw), MN.Menu.reveal(Picker.pos(ms, cur, 0n), 0n, shown)), n, shown)

# a thin bar at the right edge when not every model fits
def Picker.bar(more: Bool, +x: Nat, +y: Nat, +span: Nat, +off: Nat, +shown: Nat, +n: Nat) -> List<&2, R.Op>:
  match more:
    case True{}:
      [D.Draw.rect(D.Clip.all(), Picker.px(x), Picker.px(Nat.add(y, Nat.div(Nat.mul(span, off), n))), 3, Picker.px(MN.Menu.max(Nat.div(Nat.mul(span, shown), n), 8n)), T.Th.faint(), 255)]
    case False{}:
      Nil{}

# the model menu, above the composer (bottom) and at its left edge, never
# above `limit` nor wider than x0..x1: effort chips on top where the
# provider has them, then the models, as many as fit (the wheel scrolls
# the rest). Every place comes from core/menu.bend (laws menu_*).
def Lay.picker.k(+ty: Ty, +ms: List<&2, String>, +cur: String, +info: String, +prov: String, +x0: U32, +x1: U32, +bottom: U32, +limit: U32, +es: List<&2, String>, +effort: String, +raw: String) -> Out:
  +x = U32.to_nat(x0)
  +n = List.length(&2, String, ms)
  +cws = Picker.chip_ws(ty, es)
  +names = Picker.names_w(ty, ms)
  +want = MN.Menu.max(MN.Menu.max(Nat.add(Nat.add(names, Picker.labels_w(ty, ms, info, prov)), 56n), Nat.add(Picker.line_w(cws), 12n)), 280n)
  +w = MN.Menu.width(want, U32.to_nat((x1 - x0 : U32)))
  +col = MN.Menu.col(names, Nat.sub(w, 40n))
  +rel = MN.Flow.under(cws, 6n, Nat.sub(w, 6n), 6n, 6n, 28n, 8n)
  +room = {Nat.sub(Nat.sub(U32.to_nat(bottom), U32.to_nat(limit)), Nat.add(rel, 6n)) : Nat}
  +shown = MN.Menu.fit(n, room)
  +span = MN.Menu.span(n, room)
  +hb = {Nat.add(Nat.add(rel, span), 6n) : Nat}
  +top = {Nat.sub(U32.to_nat(bottom), hb) : Nat}
  +off = Picker.off(raw, ms, cur, n, shown)
  Out.all([
    Out{Lay.box(D.Clip.all(), x0, Picker.px(top), Picker.px(w), Picker.px(hb), 8, T.Th.panel(), T.Th.line()),
      [Lay.hit(x0, Picker.px(top), Picker.px(w), Picker.px(hb), "menu", Nat.show(off) ++ "|" ++ Nat.show(Nat.sub(n, shown)))]},
    Out.ops(Bool.pick(List<&2, R.Op>, List.is_empty(&2, String, es), Nil{}, [D.Draw.rect(D.Clip.all(), (x0 + 1 : U32), Picker.px(Nat.sub(Nat.add(top, rel), 5n)), Picker.px(Nat.sub(w, 2n)), 1, T.Th.line(), 255)])),
    Picker.chips(ty, MN.Flow.place(cws, Nat.add(x, 6n), Nat.sub(Nat.add(x, w), 6n), Nat.add(x, 6n), Nat.add(top, 6n), 28n, 8n), es, effort),
    Picker.rows(ty, MN.Menu.rows(shown, Nat.add(x, 6n), Nat.add(top, rel), Nat.sub(w, 12n)), List.drop(&2, String, ms, off), cur, info, prov, col),
    Out.ops(Picker.bar(Nat.is_lt(shown, n), Nat.sub(Nat.add(x, w), 4n), Nat.add(top, rel), span, off, shown, n))])

def Lay.picker(open: Bool, +ty: Ty, +ms: List<&2, String>, +cur: String, +info: String, +prov: String, +x0: U32, +x1: U32, +bottom: U32, +limit: U32, +es: List<&2, String>, +effort: String, +raw: String) -> Out:
  match open:
    case True{}:
      Lay.picker.k(ty, ms, cur, info, prov, x0, x1, bottom, limit, es, effort, raw)
    case False{}:
      Out.none()

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

# where position p of the draft sits: its wrapped line and x
def Comp.row(+ty: Ty, +draft: String, +p: Nat, +tw: U32) -> Nat:
  Nat.sub(List.length(&2, String, Ty.wrap(ty, 3n, String.take(draft, p), tw)), 1n)

def Comp.x(+ty: Ty, +draft: String, +p: Nat, +tw: U32) -> U32:
  Ty.width(ty, 3n, Maybe.default(&2, String, List.last(&2, String, Ty.wrap(ty, 3n, String.take(draft, p), tw)), ""))

# the selection behind the shown lines (j is the first one's number),
# from line rlo at xlo to line rhi at xhi
def Comp.sel.go(ls: List<&2, String>, +ty: Ty, +j: Nat, +rlo: Nat, +xlo: U32, +rhi: Nat, +xhi: U32, +x: U32, +y: U32) -> List<&2, R.Op>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      +a = {Bool.pick(U32, Nat.is_eq(j, rlo), xlo, 0) : U32}
      +b = {Bool.pick(U32, Nat.is_eq(j, rhi), xhi, (Ty.width(ty, 3n, l) + 6 : U32)) : U32}
      List.append(&2, R.Op, Bool.pick(List<&2, R.Op>, Bool.and(Bool.and(Nat.is_ge(j, rlo), Nat.is_le(j, rhi)), U32.is_gt(b, a)),
        [D.Draw.rect(D.Clip.all(), (x + a : U32), y, (b - a : U32), 20, T.Th.sel(), 255)], Nil{}),
        Comp.sel.go(t, ty, 1n+j, rlo, xlo, rhi, xhi, x, (y + 23 : U32)))

def Comp.sel(on: Bool, +ty: Ty, +shown: List<&2, String>, +top: Nat, +draft: String, +lo: Nat, +hi: Nat, +tw: U32, +x: U32, +y: U32) -> Out:
  match on:
    case True{}:
      Out.ops(Comp.sel.go(shown, ty, top, Comp.row(ty, draft, lo, tw), Comp.x(ty, draft, lo, tw), Comp.row(ty, draft, hi, tw), Comp.x(ty, draft, hi, tw), x, y))
    case False{}:
      Out.none()

# how much taller than two lines the composer is for n wrapped lines
def Comp.eh(+n: Nat) -> U32:
  (U32.from_nat(Nat.sub(S.Cs.rows(n), 2n)) * 23 : U32)

# the draft wrapped as the composer shows it, cw wide
def Comp.wrap(+ty: Ty, +draft: String, +cw: U32) -> List<&2, String>:
  Ty.wrap(ty, 3n, draft, (cw - 40 : U32))

# a scrollbar at x beside v of n lines from top, the view th tall
def Comp.bar(on: Bool, +n: Nat, +v: Nat, +top: Nat, +x: U32, +y: U32, +th: U32) -> Out:
  match on:
    case True{}:
      +bh = {U32.max(16, U32.from_nat(Nat.div(Nat.mul(U32.to_nat(th), v), n))) : U32}
      +by = {U32.from_nat(Nat.div(Nat.mul(U32.to_nat((th - bh : U32)), top), Nat.sub(n, v))) : U32}
      Out.ops([D.Draw.rect(D.Clip.all(), x, y, 4, th, T.Th.raise(), 255), D.Draw.rect(D.Clip.all(), x, (y + by : U32), 4, bh, T.Th.dim(), 255)])
    case False{}:
      Out.none()

# the composer grows upward with its draft (its footer stays put); held
# is the wheel's choice of first line (nui.bend's Cs). Its footer row sits
# 10 px in from the box's bottom and sides, and the model chip's text lines
# up with the draft's.
def Comp.foot(+h: U32) -> U32:
  (h - 58 : U32)

def Comp.send_x(+ty: Ty, +x1: U32, +send: String) -> U32:
  (x1 - 10 - Lay.button.w(ty, send) : U32)

def Lay.composer(+ty: Ty, +draft: String, +ls: List<&2, String>, +held: String, +caret: Nat, +mark: Nat, +focused: Bool, +blink: Bool, +x0: U32, +x1: U32, +h: U32, running: Bool, +models: String, +rs: List<&2, U.SkillRow>) -> Out:
  +tw = {(x1 - x0 - 40 : U32) : U32}
  +n = List.length(&2, String, ls)
  +v = S.Cs.rows(n)
  +eh = Comp.eh(n)
  +crow = Comp.row(ty, draft, caret, tw)
  +top = S.Cs.top(held, n, crow)
  +shown = List.take(&2, String, List.drop(&2, String, ls, top), v)
  +row = Nat.sub(crow, top)
  +cx = Comp.x(ty, draft, caret, tw)
  +y = {(h - 120 - eh : U32) : U32}
  +fy = Comp.foot(h)
  +send = Bool.pick(String, running, "Queue", "Send")
  Out.all([
    Out.ops(Lay.box(D.Clip.all(), x0, y, (x1 - x0 : U32), (100 + eh : U32), 10, T.Th.panel(), Bool.pick(U32, focused, T.Th.focus(), T.Th.line()))),
    Comp.sel(Bool.and(focused, Bool.not(Nat.is_eq(caret, mark))), ty, shown, top, draft, ED.Edit.lo(caret, mark), ED.Edit.hi(caret, mark), tw, (x0 + 16 : U32), (y + 12 : U32)),
    Bool.pick(Out, String.is_empty(draft),
      Out.ops(Ty.text(ty, 3n, Ty.fit(ty, 3n, "Ask anything, @tag files, $skill, or describe the change", tw), D.Clip.all(), (x0 + 16 : U32), (y + 10 : U32), 23, T.Th.faint())),
      Lay.lines(ty, shown, D.Clip{(x0 + 1 : U32), (y + 1 : U32), (x1 - 1 : U32), (y + 60 + eh : U32)}, (x0 + 16 : U32), (y + 10 : U32))),
    Bool.pick(Out, Bool.and(Bool.and(focused, blink), Bool.and(Nat.is_ge(crow, top), Nat.is_lt(row, v))), Out.ops([D.Draw.rect(D.Clip.all(), (x0 + 16 + cx : U32), (y + 14 + (U32.from_nat(row) * 23 : U32) : U32), 1, 16, T.Th.accent(), 255)]), Out.none()),
    Comp.bar(Nat.is_gt(n, v), n, v, top, (x1 - 12 : U32), (y + 12 : U32), (U32.from_nat(v) * 23 - 4 : U32)),
    Out{Nil{}, [Lay.hit(x0, y, (x1 - x0 : U32), (64 + eh : U32), "focus", "composer"), Lay.hit(0, 0, 0, 0, "cs", Nat.show(top) ++ "," ++ Nat.show(Nat.sub(n, v)))]},
    Out{List.append(&2, R.Op, Ty.text(ty, 2n, models, D.Clip.all(), (x0 + 16 : U32), fy, 28, T.Th.dim()), Lay.icon(ty, "chevron-down", D.Clip.all(), (x0 + 22 + Ty.width(ty, 2n, models) : U32), (fy + 6 : U32), T.Th.dim())), [Lay.hit((x0 + 8 : U32), fy, (Ty.width(ty, 2n, models) + 38 : U32), 28, "flag", "models")]},
    Lay.button(ty, D.Clip.all(), Comp.send_x(ty, x1, send), fy, send, T.Th.accent(), "send", ""),
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
def Lay.timeline(+ty: Ty, +ls: List<&2, TLine>, +x0: U32, +x1: U32, +top: U32, +h: U32, +sc: U32, +sel: TSel, chrome: Out) -> Out:
  +bot = {(h - 132 : U32) : U32}
  +view = {U32.dim(bot, (top + 16 : U32)) : U32}
  +total = TL.height(ls, 0)
  +over = {U32.dim(total, view) : U32}
  +off = {U32.dim(over, U32.min(sc, over)) : U32}
  +rest = TL.drop(ls, TL.drop.more(ls, 0, off), 0, off)
  +acc = TL.drop.acc(ls, TL.drop.more(ls, 0, off), 0, off)
  +ry = {((top + 16 + acc : U32) - off : U32) : U32}
  Out.all([TL.draw_all(ty, rest, TL.more(rest, ry, bot), D.Clip{x0, top, x1, bot}, x0, x1, ry, bot,
    Nat.sub(List.length(&2, TLine, ls), List.length(&2, TLine, rest)), sel), TL.sel.hit(ty, ls, sel, x0, x1), chrome])

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

# The settings screen, in place of the thread. Taller than the window, it
# scrolls ("@set.sc", clamped here); the header stays on top.
def Lay.settings(+ty: Ty, +st: M.State, +info: Map<&2, String>, +v: String, +note: String, +x0: U32, +x1: U32, +h: U32, +raw: U32) -> Out:
  +w = {U32.min((x1 - x0 - 64 : U32), 720) : U32}
  +x = {(x0 + U32.shr((x1 - x0 - w : U32)) : U32) : U32}
  +prov = M.Setting.get(st, "agent.provider", "claude")
  +ipc = M.Setting.get(st, "kicad.ipc", "on")
  +ms = U.Models.menu(U.Str.get(info, "models"), prov)
  +dy = {(Set.rows(ty, ms, (x + 16 : U32), (x + w - 16 : U32), (x + 16 : U32)) * 34 + 26 : U32) : U32}
  +tp = U.TextGen.provider(st)
  +tm = U.TextGen.model(st)
  +tms = U.Models.menu(U.Str.get(info, "models"), tp)
  +er = {(Set.rows(ty, tms, (x + 16 : U32), (x + w - 16 : U32), (x + 16 : U32)) * 34 : U32) : U32}
  +ey = {(202 + er : U32) : U32}
  +total = {(804 + dy + ey : U32) : U32}
  +off = {U32.min(raw, U32.dim(total, h)) : U32}
  +b = {(0 - off : U32) : U32}
  Out.all([
    Out{Nil{}, [Lay.hit(x0, 52, (x1 - x0 : U32), (h - 52 : U32), "set-bg", U32.show(U32.dim(total, h)))]},
    Out.hits_below(52, Out.all([
    Set.head(ty, "Threads", x, (b + 76 : U32)),
    Set.card(x, (b + 108 : U32), w, 64),
    Set.row.r(ty, "Settle after", "Threads idle this long move to Settled. They stay saved.", x, (b + 110 : U32), w, 190),
    Set.days(ty, M.Setting.get(st, "settle.days", "3"), (x + w - 172 : U32), (b + 126 : U32)),
    Set.head(ty, "Agents", x, (b + 192 : U32)),
    Set.card(x, (b + 224 : U32), w, (124 + dy : U32)),
    Set.row(ty, "Provider and model for new threads", Set.cli(U.Models.cli(U.Str.get(info, "models"), prov), prov) ++ ". Each thread keeps its own; change it from the composer.", x, (b + 226 : U32), w),
    Set.chips(ty, ["claude", "codex", "grok"], prov, "agent.provider", (x + 16 : U32), (x + w - 16 : U32), (x + 16 : U32), (b + 274 : U32)),
    Set.chips(ty, ms, M.Setting.get(st, "agent.model", ""), "agent.model", (x + 16 : U32), (x + w - 16 : U32), (x + 16 : U32), (b + 308 : U32)),
    Out.ops(Ty.text(ty, 2n, Ty.fit(ty, 2n, Set.model_line(U.Models.label_of(U.Str.get(info, "models"), prov, M.Setting.get(st, "agent.model", "")), M.Setting.get(st, "agent.model", "")), (w - 32 : U32)),
      D.Clip.all(), (x + 16 : U32), (b + 318 + dy : U32), 24, T.Th.dim())),
    Set.head(ty, "Writing", x, (b + 368 + dy : U32)),
    Set.card(x, (b + 400 + dy : U32), w, (150 + er : U32)),
    Set.row(ty, "Model for titles, branch names and commit messages", "A small model keeps this cheap. It names each thread from its first message.", x, (b + 402 + dy : U32), w),
    Set.chips(ty, ["claude", "codex", "grok"], tp, "text.provider", (x + 16 : U32), (x + w - 16 : U32), (x + 16 : U32), (b + 450 + dy : U32)),
    Set.chips(ty, tms, tm, "text.model", (x + 16 : U32), (x + w - 16 : U32), (x + 16 : U32), (b + 484 + dy : U32)),
    Out.ops(Ty.text(ty, 2n, Ty.fit(ty, 2n, Set.model_line(U.Models.label_of(U.Str.get(info, "models"), tp, tm), tm), (w - 32 : U32)),
      D.Clip.all(), (x + 16 : U32), (b + 520 + dy + er : U32), 24, T.Th.dim())),
    Set.head(ty, "KiCad", x, (b + 368 + dy + ey : U32)),
    Set.card(x, (b + 400 + dy + ey : U32), w, 150),
    Set.row(ty, "KiCad CLI", U.Str.get(info, "kicad.cli"), x, (b + 402 + dy + ey : U32), w),
    Set.fork(ty, U.Str.get(info, "kicad.fork"), (x + 16 : U32), (b + 450 + dy + ey : U32)),
    Set.row.r(ty, "KiCad IPC", "Agents may drive KiCad through the fork's api-server (NNG/protobuf).", x, (b + 486 + dy + ey : U32), w, 140),
    Lay.chip(ty, (x + w - 120 : U32), (b + 500 + dy + ey : U32), "On", String.eq(ipc, "on"), "setting", "kicad.ipc=on"),
    Lay.chip(ty, (x + w - 70 : U32), (b + 500 + dy + ey : U32), "Off", String.eq(ipc, "off"), "setting", "kicad.ipc=off"),
    Set.head(ty, "Network and updates", x, (b + 570 + dy + ey : U32)),
    Set.card(x, (b + 602 + dy + ey : U32), w, 164),
    Set.row(ty, "Tailscale: " ++ U.Str.get(info, "tailnet"), Bool.pick(String, String.eq(U.Str.get(info, "tailnet"), "off"), "Listening on " ++ U.Str.get(info, "listen") ++ " only (started with --no-tailscale, or Tailscale is not up).",
      "Also on your tailnet: your own devices get in, others need the pairing token."), x, (b + 604 + dy + ey : U32), w),
    Set.row.r(ty, "Backplane " ++ v, Bool.pick(String, String.is_empty(note), "Up to date, checked hourly.", note), x, (b + 656 + dy + ey : U32), w, 150),
    Bool.pick(Out, String.starts_with(note, "update "), Lay.button(ty, D.Clip.all(), (x + w - 16 - Lay.button.w(ty, "Install update") : U32), (b + 666 + dy + ey : U32), "Install update", T.Th.accent(), "update", ""),
      Lay.button(ty, D.Clip.all(), (x + w - 16 - Lay.button.w(ty, "Check now") : U32), (b + 666 + dy + ey : U32), "Check now", T.Th.soft(), "update-check", "")),
    Set.row.r(ty, "Update channel", "Stable takes releases; nightly also takes the daily builds.", x, (b + 708 + dy + ey : U32), w, 190),
    Lay.chip(ty, (x + w - 16 - Lay.button.w(ty, "Nightly") - 6 - Lay.button.w(ty, "Stable") : U32), (b + 722 + dy + ey : U32), "Stable", Bool.not(String.eq(M.Setting.get(st, "update.channel", "stable"), "nightly")), "setting", "update.channel=stable"),
    Lay.chip(ty, (x + w - 16 - Lay.button.w(ty, "Nightly") : U32), (b + 722 + dy + ey : U32), "Nightly", String.eq(M.Setting.get(st, "update.channel", "stable"), "nightly"), "setting", "update.channel=nightly")])),
    Out{List.append(&2, R.Op, [D.Draw.rect(D.Clip.all(), x0, 0, (x1 - x0 : U32), 51, T.Th.bg(), 255), D.Draw.rect(D.Clip.all(), x0, 51, (x1 - x0 : U32), 1, T.Th.line(), 255)],
      Ty.text(ty, 0n, "Settings", D.Clip.all(), (x0 + 24 : U32), 0, 52, T.Th.text())), Nil{}},
    Lay.button(ty, D.Clip.all(), (x1 - 16 - Lay.button.w(ty, "Close") : U32), 12, "Close", T.Th.soft(), "flag", "settings")])

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
# the value of the first "key=value" part (key given with its "=")
def Info.get(ps: List<&2, String>, +k: String) -> String:
  match ps:
    case Nil{}:
      ""
    case +p <> t:
      Bool.pick(String, String.starts_with(p, k), String.drop(p, String.length(k)), Info.get(t, k))

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
    Out{Lay.icon(ty, "x", D.Clip.all(), (x0 + w - 10 : U32), (y + 12 : U32), T.Th.dim()), [Lay.hit((x0 + w - 16 : U32), (y + 6 : U32), 28, 28, "vw-unpick", "")]},
    Info.draw(ty, rows, (x0 + 16 : U32), (y + 38 : U32), w),
    Lay.button(ty, D.Clip.all(), (x0 + 30 : U32), (y + ch - 40 : U32), "Mention in chat", T.Th.accent(), "draft", draft ++ Bool.pick(String, String.is_empty(draft), "", " ") ++ mention),
    Out.when(String.eq(title, "sheet"), Lay.button(ty, D.Clip.all(), (x0 + 38 + Lay.button.w(ty, "Mention in chat") : U32), (y + ch - 40 : U32), "Open sheet", T.Th.accent(), "vw-open", Info.get(ps, "name=")))]))

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

def Lay.diff.if(open: Bool, +ty: Ty, +diff: String, +x0: U32, +x1: U32, +h: U32, +scroll: U32) -> Out:
  match open:
    case True{}:
      Lay.diff(ty, diff, x0, x1, h, scroll)
    case False{}:
      Out.none()

# a board, schematic or model on show opens in the bundled KiCad
def Lay.kicad.on(+k: U32, +empty: Bool, +ts: List<&2, G.Tri3>, +bm: BM.Bitmap) -> Bool:
  Bool.and(U32.is_le(k, 2), Lay.shown(k, empty, ts, bm))

# a - b, never below 0
def Lay.room(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, U32.is_gt(a, b), (a - b : U32), 0)

# the header width the Open in KiCad button takes
def Lay.kicad.w(+ty: Ty, +on: Bool) -> U32:
  Bool.pick(U32, on, (Lay.button.w(ty, "Open in KiCad") + 12 : U32), 0)

def Lay.kicad(on: Bool, +ty: Ty, +x1: U32) -> Out:
  match on:
    case True{}:
      Lay.button(ty, D.Clip.all(), (x1 - 16 - Lay.button.w(ty, "Open in KiCad") : U32), 12, "Open in KiCad", T.Th.text(), "kicad-open", "")
    case False{}:
      Out.none()

def Lay.viewer.k(+ty: Ty, +x0: U32, +x1: U32, +h: U32, +empty: Bool, x: V.Vx, +info: String, +draft: String, +diff: String, +scroll: U32) -> Out:
  match x:
    case V.Vx{+k, _, +ts, _, _, +busy, _, _, _, _, +bm}:
      +help = Lay.help(k)
      +ko = Lay.kicad.on(k, empty, ts, bm)
      +kw = Lay.kicad.w(ty, ko)
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
        Lay.diff.if(U32.is_eq(k, 4), ty, diff, x0, x1, h, scroll),
        Lay.kicad(ko, ty, x1),
        Out.ops(Ty.text(ty, 2n, Ty.fit(ty, 2n, help, Lay.room((x1 - x0 : U32), (380 + kw : U32))), D.Clip.all(), (x1 - 16 - kw - Ty.width(ty, 2n, Ty.fit(ty, 2n, help, Lay.room((x1 - x0 : U32), (380 + kw : U32)))) : U32), 0, 52, T.Th.faint())),
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

# Layers and sheets
# -----------------
# Over a board or schematic: a "Layers" chip opening a list of the layers
# the scene has items on (a click turns one on or off, S.Nui.flip), and
# for a schematic with sheets, the trail from the root to the sheet on
# show and the whole sheet tree in the same list (a click goes there).

def Side.names(+k: U32) -> List<&2, String>:
  Bool.pick(List<&2, String>, U32.is_eq(k, 1), SC.Sch.layer_names(), B.Layer.names())

def Side.color(l: U32 & U32) -> U32:
  (c, _) = l
  c

def Side.has(+present: U32, +i: U32, +count: Nat) -> Bool:
  Bool.and(Nat.is_lt(U32.to_nat(i), count), Bool.not(U32.is_eq(U32.and(present, V.Look.bit(i)), 0)))

def Side.layer(+ty: Ty, +k: U32, +l: U32, +name: String, +flip: U32, +x: U32, +y: U32, +w: U32, +c: D.Clip) -> Out:
  +on = V.Look.shows(k, l, flip)
  Out{List.append(&2, R.Op, [D.Draw.rect(c, (x + 12 : U32), (y + 6 : U32), 10, 10, Side.color(V.Look.of(k, l)), Bool.pick(U32, on, 255, 50))],
      Ty.text(ty, 2n, name, c, (x + 32 : U32), y, 22, Bool.pick(U32, on, T.Th.text(), T.Th.faint()))),
    [Lay.hit(x, y, w, 22, "vw-layer", U32.show(l))]}

def Side.layer.if(show: Bool, +ty: Ty, +k: U32, +l: U32, +name: String, +flip: U32, +x: U32, +y: U32, +w: U32, +c: D.Clip) -> Out:
  match show:
    case True{}:
      Side.layer(ty, k, l, name, flip, x, y, w, c)
    case False{}:
      Out.none()

# one row per layer the scene has, from y down
def Side.layers(ns: List<&2, String>, +i: U32, +y: U32, +ty: Ty, +k: U32, +present: U32, +flip: U32, +x: U32, +w: U32, +c: D.Clip) -> List<&2, Out>:
  match ns:
    case Nil{}:
      Nil{}
    case +nm <> t:
      Side.layer.if(Side.has(present, i, V.Look.count(k)), ty, k, i, nm, flip, x, y, w, c)
      <> Side.layers(t, (i + 1 : U32), Bool.pick(U32, Side.has(present, i, V.Look.count(k)), (y + 22 : U32), y), ty, k, present, flip, x, w, c)

def Side.n(ns: List<&2, String>, +i: U32, +present: U32, +count: Nat, +acc: U32) -> U32:
  match ns:
    case Nil{}:
      acc
    case _ <> t:
      Side.n(t, (i + 1 : U32), present, count, Bool.pick(U32, Side.has(present, i, count), (acc + 1 : U32), acc))

def Side.sheet(+ty: Ty, r: HI.Row, +j: Nat, +at: Nat, +x: U32, +y: U32, +w: U32, +c: D.Clip) -> Out:
  match r:
    case HI.Row{+d, +nm, _, +loop}:
      +ind = {U32.from_nat(Nat.mul(d, 14n)) : U32}
      Out{List.append(&2, R.Op, Bool.pick(List<&2, R.Op>, Nat.is_eq(j, at), [D.Draw.rect(c, x, y, w, 22, T.Th.sel(), 255)], Nil{}),
          Ty.text(ty, 2n, Bool.pick(String, loop, nm ++ " (repeats a sheet above)", nm), c, (x + 12 + ind : U32), y, 22,
            Bool.pick(U32, loop, T.Th.faint(), Bool.pick(U32, Nat.is_eq(j, at), T.Th.text(), T.Th.dim())))),
        Bool.pick(List<&2, S.Hit>, loop, Nil{}, [Lay.hit(x, y, w, 22, "vw-sheet", Nat.show(j))])}

def Side.sheets(rs: List<&2, HI.Row>, +j: Nat, +at: Nat, +ty: Ty, +x: U32, +y: U32, +w: U32, +c: D.Clip) -> List<&2, Out>:
  match rs:
    case Nil{}:
      Nil{}
    case r <> t:
      Side.sheet(ty, r, j, at, x, y, w, c) <> Side.sheets(t, 1n+j, at, ty, x, (y + 22 : U32), w, c)

def Side.reset(+ty: Ty, +x: U32, +y: U32, +c: D.Clip) -> Out:
  Out{Ty.text(ty, 2n, "Reset layers", c, (x + 12 : U32), y, 22, T.Th.accent()), [Lay.hit(x, y, 200, 22, "vw-layers-reset", "")]}

# the open list: the sheet tree (schematics with sheets), then the layers
def Side.list(+ty: Ty, +k: U32, +present: U32, +flip: U32, +rs: List<&2, HI.Row>, +at: Nat, +x1: U32, +h: U32) -> Out:
  +w = {240 : U32}
  +x = {(x1 - 16 - w : U32) : U32}
  +ns = {U32.from_nat(Bool.pick(Nat, Nat.is_gt(List.length(&2, HI.Row, rs), 1n), List.length(&2, HI.Row, rs), 0n)) : U32}
  +sh = {Bool.pick(U32, U32.is_eq(ns, 0), 0, (ns * 22 + 9 : U32)) : U32}
  +nl = {Side.n(Side.names(k), 0, present, V.Look.count(k), 0) : U32}
  +rh = {Bool.pick(U32, U32.is_eq(flip, 0), 0, 22) : U32}
  +ph = {U32.min((sh + nl * 22 + rh + 12 : U32), (h - 112 : U32)) : U32}
  +c = {D.Clip{x, 96, (x + w : U32), (96 + ph : U32)} : D.Clip}
  Out.all([
    Out{Lay.box(D.Clip.all(), x, 96, w, ph, 6, T.Th.panel(), T.Th.line()), [Lay.hit(x, 96, w, ph, "vw-panel", "")]},
    Out.all(Side.sheets(Bool.pick(List<&2, HI.Row>, U32.is_eq(ns, 0), Nil{}, rs), 0n, at, ty, x, 102, w, c)),
    Out.ops(Bool.pick(List<&2, R.Op>, U32.is_eq(ns, 0), Nil{}, [D.Draw.rect(c, (x + 8 : U32), (102 + sh - 5 : U32), (w - 16 : U32), 1, T.Th.line(), 255)])),
    Out.all(Side.layers(Side.names(k), 0, (102 + sh : U32), ty, k, present, flip, x, w, c)),
    Out.when(Bool.not(U32.is_eq(flip, 0)), Side.reset(ty, x, (102 + sh + nl * 22 : U32), c))])

def Side.list.if(open: Bool, +ty: Ty, +k: U32, +ss: List<&2, V.Seen>, +flip: U32, +rs: List<&2, HI.Row>, +at: Nat, +x1: U32, +h: U32) -> Out:
  match open:
    case True{}:
      Side.list(ty, k, V.Layers.present(ss, 0), flip, rs, at, x1, h)
    case False{}:
      Out.none()

# the sheets from the root to the one on show, each a chip that goes there
def Side.trail(cs: List<&2, Nat>, +rs: List<&2, HI.Row>, +at: Nat, +ty: Ty, +x: U32) -> List<&2, Out>:
  match cs:
    case Nil{}:
      Nil{}
    case +j <> t:
      Lay.chip(ty, x, 60, HI.Hier.name(rs, j), Nat.is_eq(j, at), "vw-sheet", Nat.show(j))
      <> Side.trail(t, rs, at, ty, (x + Lay.button.w(ty, HI.Hier.name(rs, j)) + 6 : U32))

def Side.k(board: Bool, +ty: Ty, +n: S.Nui, +k: U32, +ss: List<&2, V.Seen>, +x0: U32, +x1: U32, +h: U32) -> Out:
  match board:
    case True{}:
      +rs = S.Nui.rows(n)
      +at = S.Nui.sheet.at(n)
      +open = Bool.not(String.is_empty(U.Ui.scratch(S.Nui.ui(n), "@vw.layers")))
      +sheets = Bool.and(U32.is_eq(k, 1), Nat.is_gt(List.length(&2, HI.Row, rs), 1n))
      Out.all([
        Out.all(Side.trail(Bool.pick(List<&2, Nat>, sheets, HI.Hier.chain(rs, at), Nil{}), rs, at, ty, (x0 + 16 : U32))),
        Lay.chip(ty, (x1 - 16 - Lay.button.w(ty, "Layers") : U32), 60, "Layers", open, "vw-layers", ""),
        Side.list.if(open, ty, k, ss, S.Nui.flip(n), Bool.pick(List<&2, HI.Row>, sheets, rs, Nil{}), at, x1, h)])
    case False{}:
      Out.none()

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

# the viewer's chrome; the scene under it is drawn by the viewer
def Lay.viewer(+ty: Ty, +n: S.Nui, +x0: U32, +x1: U32, +h: U32) -> Out:
  Out.all([
    Lay.viewer.vw(ty, S.Nui.vw(n), U.Ui.draft_text(S.Nui.ui(n)), U.Ui.view_get(S.Nui.ui(n), "diff"), x0, x1, h),
    Side.k(U32.is_lt(S.Vw.kind(S.Nui.vw(n)), 2), ty, n, S.Vw.kind(S.Nui.vw(n)), Lay.scene(n), x0, x1, h)])

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
  Lay.note.k(ty, String.is_empty(note), String.starts_with(note, "update "), Ty.fit(ty, 2n, note, 150), U32.dim(248, (Ty.width(ty, 2n, Ty.fit(ty, 2n, note, 150)) + 16 : U32)), (h - 34 : U32))

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
        U.Drag.title(U.Ui.state(u), U.Ui.scratch(u, "@drag")), U32.max(my, 67))

def Lay.sidebar(+ty: Ty, +n: S.Nui, +h: U32) -> Out:
  match n:
    case S.Nui{U.Ui{+st, +sel, _, _, +open, on, +now, adding, _, +v, _, _, _, +note, _, _, _}, _, _, _, _, +sd, _, +caret, +focus, +path, _, _, vw}:
      Out.all([Lay.sidebar.k(ty, D.Clip{0, 52, 264, h}, st, sel, open, on, now, adding, v, sd, caret, S.Nui.mark(n), focus, path, h, U.Flag.get(open, "settings"), U.Machines.rows(S.Nui.ui(n)),
        U.Ui.scratch(S.Nui.ui(n), "@hint"), Lay.hint.ids(String.eq(U.Ui.scratch(S.Nui.ui(n), "@hint"), "alt"), String.eq(U.Ui.scratch(S.Nui.ui(n), "@hint"), "ctrl"), S.Nui.ui(n)), U.Ui.scratch(S.Nui.ui(n), "@look")), Lay.note(ty, note, h), Lay.ghost(ty, n)])

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

def Lay.term.of.k(on: Bool, +ty: Ty, +n: S.Nui, +x1: U32, +h: U32) -> Out:
  match on:
    case True{}:
      Lay.term(ty, U.Ui.term(S.Nui.ui(n), U.Ui.sel(S.Nui.ui(n))), 264, x1, (h - Lay.term_h(n) : U32), h, String.eq(S.Nui.focus_of(n), "terminal"), S.Blink.on(n))
    case False{}:
      Out.none()

def Lay.term.of(+ty: Ty, +n: S.Nui, +x1: U32, +h: U32) -> Out:
  Lay.term.of.k(Lay.term_on(n), ty, n, x1, h)

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

# an entry's own lines in three parts: what depends on the entry and the
# width alone (the costly part: markdown, wrapping, measuring; kept across
# frames), the image paths it names, and its footer. The images' lines
# are made each frame, since their sizes arrive later.
type TLPart is Data:
  TLPart{head: List<&2, TLine>, paths: List<&2, String>, tail: List<&2, TLine>}

def TL.part.own(+ty: Ty, e: M.Entry, +px: U32) -> TLPart:
  match e:
    case M.Msg{_, _, M.User{}, +text, _}:
      TLPart{TL.bubble.a(ty, text, px), Nil{}, Nil{}}
    case M.Msg{_, _, _, +text, _}:
      TLPart{TL.blocks(ty, N.Md.render(text), px), IM.Img.paths(text), [TLine{"", 0, 7, text, 0}, TLine{"", 0, 4, "", 0}]}
    case M.Act{_, _, +tone, kind, summary, _}:
      TLPart{[TLine{Ty.fit(ty, 2n, kind ++ "  " ++ summary, px), Bool.pick(U32, String.eq(tone, "error"), T.Th.bad(), T.Th.dim()), 3, "", 0}], Nil{}, Nil{}}

# only this thread's own entries have parts; a line it sent elsewhere is
# made each frame (it names the other thread)
def TL.part(mine: Bool, +ty: Ty, e: M.Entry, +px: U32) -> TLPart:
  match mine:
    case True{}:
      TL.part.own(ty, e, px)
    case False{}:
      TLPart{Nil{}, Nil{}, Nil{}}

def TL.part.join(+ty: Ty, p: TLPart, +pics: Map<&2, String>, +px: U32) -> List<&2, TLine>:
  match p:
    case TLPart{h, ps, t}:
      List.concat(&2, TLine, [h, TL.images(ty, ps, pics, px), t])

def TL.mine_of(+e: M.Entry, +sel: String) -> Bool:
  String.eq(TL.thread_of(e), sel)

# an entry of this thread (headed by the thread it came from, if another
# thread sent it) or one this thread sent elsewhere (a link line), from
# its part
def TL.entry.p(mine: Bool, +ty: Ty, e: M.Entry, +st: M.State, +px: U32, +pics: Map<&2, String>, p: TLPart) -> List<&2, TLine>:
  match mine e:
    case True{} M.Msg{+id, _, _, _, _}:
      List.append(&2, TLine, TL.from.k(String.is_empty(M.Link.from(id)), M.Link.from(id), st, px, ty), TL.part.join(ty, p, pics, px))
    case True{} _:
      TL.part.join(ty, p, pics, px)
    case False{} M.Msg{_, +t, _, +x, _}:
      [TLine{Ty.fit(ty, 2n, "→ " ++ U.Tasks.title(st, t) ++ ":  " ++ TL.first_line(x), px), T.Th.accent(), 10, t, 0}]
    case False{} _:
      Nil{}

def TL.entry(+ty: Ty, +e: M.Entry, +st: M.State, +sel: String, +px: U32, +pics: Map<&2, String>) -> List<&2, TLine>:
  TL.entry.p(TL.mine_of(e, sel), ty, e, st, px, pics, TL.part(TL.mine_of(e, sel), ty, e, px))

# Tool calls folded
# -----------------
# A run of tool calls shows as one row (FO.Fold decides the runs, their
# labels and which are open); an entry's lines are shown as its role says.
# What is open comes from the info map and the turn, both read each frame,
# so the memo of entries' parts is untouched by it.

def TL.fold.line(+ty: Ty, +id: String, +label: String, +open: Bool, +px: U32) -> TLine:
  TLine{Ty.fit(ty, 2n, label, (px - 26 : U32)), T.Th.dim(), 14, FO.Fold.ask(open, id), Bool.pick(U32, open, 1, 0)}

def TL.fold.shown(open: Bool, ls: List<&2, TLine>) -> List<&2, TLine>:
  match open:
    case True{}:
      ls
    case False{}:
      Nil{}

def TL.role(r: FO.Role, +ty: Ty, ls: List<&2, TLine>, +px: U32) -> List<&2, TLine>:
  match r:
    case FO.RShow{}:
      ls
    case FO.RHead{+id, +label, +open}:
      TL.fold.line(ty, id, label, open, px) <> TL.fold.shown(open, ls)
    case FO.RIn{open}:
      TL.fold.shown(open, ls)

def TL.turn(t: M.Thread) -> Bool:
  match t:
    case M.Thread{_, _, _, _, _, turn, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      Lay.running(turn)

# the roles of the open thread's entries (its last run stays open while
# its turn runs)
def TL.roles(es: List<&2, M.Entry>, +st: M.State, +sel: String, +pics: Map<&2, String>) -> List<&2, FO.Role>:
  FO.Fold.roles(es, pics, TL.turn(U.Ui.thread(st, sel)))

# the entries, each as its role says (one with no role as it is)
def TL.entries.r(+ty: Ty, es: List<&2, M.Entry>, rs: List<&2, FO.Role>, +st: M.State, +sel: String, +px: U32, +pics: Map<&2, String>) -> List<&2, TLine>:
  match es rs:
    case Nil{} _:
      Nil{}
    case +e <> t r <> rt:
      List.append(&2, TLine, TL.role(r, ty, TL.entry(ty, e, st, sel, px, pics), px), TL.entries.r(ty, t, rt, st, sel, px, pics))
    case +e <> t Nil{}:
      List.append(&2, TLine, TL.entry(ty, e, st, sel, px, pics), TL.entries.r(ty, t, Nil{}, st, sel, px, pics))

# the timeline from scratch
def TL.entries(+ty: Ty, +es: List<&2, M.Entry>, +st: M.State, +sel: String, +px: U32, +pics: Map<&2, String>) -> List<&2, TLine>:
  TL.entries.r(ty, es, TL.roles(es, st, sel, pics), st, sel, px, pics)

# The timeline's memo
# -------------------
# Each entry of the open thread with its part, made at one width. The next
# frame keeps the part of every entry exactly equal to the one it was made
# for and makes the rest (laws tl_again_exact, tl_keep, tl_memo_exact,
# tl_entries_memo: the memo's timeline is the timeline from scratch).

type TLE is Data:
  TLE{e: M.Entry, part: TLPart}

type TLMemo is Data:
  TLMemo{px: U32, sel: String, items: List<&2, TLE>}

def TL.memo.none() -> TLMemo:
  TLMemo{0, "", Nil{}}

def TL.memo.item(+ty: Ty, +e: M.Entry, +px: U32, +sel: String) -> TLE:
  TLE{e, TL.part(TL.mine_of(e, sel), ty, e, px)}

def TL.memo.make(+ty: Ty, es: List<&2, M.Entry>, +px: U32, +sel: String) -> List<&2, TLE>:
  match es:
    case Nil{}:
      Nil{}
    case +e <> t:
      TL.memo.item(ty, e, px, sel) <> TL.memo.make(ty, t, px, sel)

def TL.memo.one.k(same: Bool, +ty: Ty, +e: M.Entry, +px: U32, +sel: String, it: TLE) -> TLE:
  match same:
    case True{}:
      it
    case False{}:
      TL.memo.item(ty, e, px, sel)

# an entry equal to the one its item was made for keeps the item
def TL.memo.one(+ty: Ty, +e: M.Entry, +px: U32, +sel: String, it: TLE) -> TLE:
  match it:
    case TLE{+pe, +pp}:
      TL.memo.one.k(Q.Eq.entry(e, pe), ty, e, px, sel, TLE{pe, pp})

# the entries now, over the items last made at the same width and thread
def TL.memo.again(es: List<&2, M.Entry>, +ty: Ty, +px: U32, +sel: String, prev: List<&2, TLE>) -> List<&2, TLE>:
  match es prev:
    case Nil{} _:
      Nil{}
    case +e <> t +it <> pt:
      TL.memo.one(ty, e, px, sel, it) <> TL.memo.again(t, ty, px, sel, pt)
    case +e <> t Nil{}:
      TL.memo.item(ty, e, px, sel) <> TL.memo.make(ty, t, px, sel)

def TL.memo.of.k(same: Bool, +ty: Ty, es: List<&2, M.Entry>, +px: U32, +sel: String, prev: List<&2, TLE>) -> TLMemo:
  match same:
    case True{}:
      TLMemo{px, sel, TL.memo.again(es, ty, px, sel, prev)}
    case False{}:
      TLMemo{px, sel, TL.memo.make(ty, es, px, sel)}

def TL.memo.of(+ty: Ty, es: List<&2, M.Entry>, +px: U32, +sel: String, prev: TLMemo) -> TLMemo:
  match prev:
    case TLMemo{ppx, psel, items}:
      TL.memo.of.k(Bool.and(U32.is_eq(ppx, px), Q.Eq.str(psel, sel)), ty, es, px, sel, items)

# the entries the memo's items were made for
def TL.memo.es(its: List<&2, TLE>) -> List<&2, M.Entry>:
  match its:
    case Nil{}:
      Nil{}
    case TLE{e, _} <> t:
      e <> TL.memo.es(t)

# the memo's items, each as its role says
def TL.entries.mr(+ty: Ty, its: List<&2, TLE>, rs: List<&2, FO.Role>, +st: M.State, +sel: String, +px: U32, +pics: Map<&2, String>) -> List<&2, TLine>:
  match its rs:
    case Nil{} _:
      Nil{}
    case TLE{+e, p} <> t r <> rt:
      List.append(&2, TLine, TL.role(r, ty, TL.entry.p(TL.mine_of(e, sel), ty, e, st, px, pics, p), px), TL.entries.mr(ty, t, rt, st, sel, px, pics))
    case TLE{+e, p} <> t Nil{}:
      List.append(&2, TLine, TL.entry.p(TL.mine_of(e, sel), ty, e, st, px, pics, p), TL.entries.mr(ty, t, Nil{}, st, sel, px, pics))

# the timeline from the memo's items
def TL.entries.m(+ty: Ty, +its: List<&2, TLE>, +st: M.State, +sel: String, +px: U32, +pics: Map<&2, String>) -> List<&2, TLine>:
  TL.entries.mr(ty, its, TL.roles(TL.memo.es(its), st, sel, pics), st, sel, px, pics)

def TL.memo.lines.k(same: Bool, +ty: Ty, m: TLMemo, +es: List<&2, M.Entry>, +st: M.State, +sel: String, +px: U32, +pics: Map<&2, String>) -> List<&2, TLine>:
  match same m:
    case True{} TLMemo{_, _, its}:
      TL.entries.m(ty, TL.memo.again(es, ty, px, sel, its), st, sel, px, pics)
    case False{} _:
      TL.entries(ty, es, st, sel, px, pics)

def TL.memo.fits(m: TLMemo, +px: U32, +sel: String) -> Bool:
  match m:
    case TLMemo{mpx, msel, _}:
      Bool.and(U32.is_eq(mpx, px), Q.Eq.str(msel, sel))

# the timeline from a memo already brought up to this frame (Lay.memo, as
# the window does before each frame): its items are the entries' parts, so
# they are not compared again (law tl_frame_exact)
def TL.memo.shown(+ty: Ty, m: TLMemo, +st: M.State, +sel: String, +px: U32, +pics: Map<&2, String>) -> List<&2, TLine>:
  match m:
    case TLMemo{_, _, its}:
      TL.entries.m(ty, its, st, sel, px, pics)

# the timeline, from the memo when it was made for this width and thread
def TL.memo.lines(+ty: Ty, +m: TLMemo, +es: List<&2, M.Entry>, +st: M.State, +sel: String, +px: U32, +pics: Map<&2, String>) -> List<&2, TLine>:
  TL.memo.lines.k(TL.memo.fits(m, px, sel), ty, m, es, st, sel, px, pics)

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
def Lay.attach_field(+ty: Ty, on: Bool, +path: String, +caret: Nat, +mark: Nat, +x0: U32, +x1: U32, +y: U32) -> Out:
  match on:
    case True{}:
      Out.cat(Lay.field(ty, D.Clip.all(), x0, y, (x1 - x0 - 12 - Lay.button.w(ty, "Attach") : U32), path, True{}, True{}, caret, mark, "/path/to/a/file, or paste one (Enter attaches, Esc closes)", "attach-path"),
        Lay.button(ty, D.Clip.all(), (x1 - Lay.button.w(ty, "Attach") : U32), y, "Attach", T.Th.accent(), "attach-file", path))
    case False{}:
      Out.none()

# the composer with its attachments
def Lay.composer.a(+ty: Ty, +draft: String, +ls: List<&2, String>, +held: String, +caret: Nat, +mark: Nat, +focus: String, +blink: Bool, +x0: U32, +x1: U32, +h: U32, +running: Bool, +models: String,
    +rs: List<&2, U.SkillRow>, +atts: List<&2, String>, +up: String, +path: String) -> Out:
  +send = Bool.pick(String, running, "Queue", "Send")
  +y = {(h - 120 - Comp.eh(List.length(&2, String, ls)) : U32) : U32}
  +fy = Comp.foot(h)
  Out.all([
    Lay.composer(ty, draft, ls, held, caret, mark, String.eq(focus, "composer"), blink, x0, x1, h, running, models, rs),
    Lay.atts(ty, atts, up, (x0 + 58 + Ty.width(ty, 2n, models) : U32), fy),
    Lay.ibutton(ty, D.Clip.all(), (Comp.send_x(ty, x1, send) - 34 : U32), fy, "paperclip", T.Th.soft(), "focus", "attach-path"),
    Lay.attach_field(ty, String.eq(focus, "attach-path"), path, caret, mark, x0, x1, (y - 36 : U32))])

def Lay.thread.k(+ty: Ty, +memo: TLMemo, t: M.Thread, +draft: String, +held: String, +st: M.State, +sel: String, +live: String, +caret: Nat, +mark: Nat, +focus: String, +blink: Bool,
    +x0: U32, +x1: U32, +h: U32, +sc: U32, pa: Bool, +info: String, +picking: Bool, +pend: List<&2, String>, +rs: List<&2, U.SkillRow>, +now: Nat,
    +atts: List<&2, String>, +up: String, +path: String, +pics: Map<&2, String>, del: Bool, +tsel: TSel, +moff: String) -> Out:
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
      # the composer grows by eh, and all above it moves up
      +ls = Comp.wrap(ty, draft, cw)
      +eh = Comp.eh(List.length(&2, String, ls))
      # the timeline and what sits around it are laid out at once
      tl ch = Lay.timeline(ty,
        List.concat(&2, TLine, [TL.memo.shown(ty, memo, st, sel, cw, pics), TL.sending(ty, pend, cw),
          TL.live.k(ty, String.is_empty(live), Lay.running(turn), live, cw)]),
        cx0, cx1, top, (h - ah - qh - eh : U32), sc, tsel, Out.none()) Out.all([Lay.header(ty, M.Thread{id, p, ti, c, a, turn, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de}, st, x0, x1, pa, M.Snooze.on(now, U.Side.until(st, sel)), del),
          Lay.parent(ty, st, sel, cx0, 58),
          Lay.tasks(ty, ts, st, cx0, cx1, (60 + pl : U32)),
          Lay.composer.a(ty, draft, ls, held, caret, mark, focus, blink, cx0, cx1, h, Lay.running(turn), U.Effort.label(U.Models.label(pr, mo), U.Effort.of(st, sel)), rs, atts, up, path),
          Lay.queued(ty, M.Queue.of(st, sel), cx0, cx1, (h - eh : U32)),
          Lay.asks(ty, asks, draft, cx0, cx1, (h - 132 - ah - qh - eh + 4 : U32)),
          Lay.picker(picking, ty, U.Models.menu(info, pr), mo, info, pr, cx0, cx1, (h - 128 - eh : U32), 60, U.Effort.chips(info, pr, mo), U.Effort.of(st, sel), moff)])
      Out.cat(tl, ch)

# while files dragged in hover over the window, an accent ring around the
# composer (placed as Lay.thread.k places it) shows where they drop
def Lay.drop_mark(on: Bool, +ty: Ty, +draft: String, +x0: U32, +x1: U32, +h: U32) -> Out:
  match on:
    case True{}:
      +cw = {U32.min((x1 - x0 - 64 : U32), 780) : U32}
      +cx0 = {(x0 + U32.shr((x1 - x0 - cw : U32)) - 5 : U32) : U32}
      +eh = Comp.eh(List.length(&2, String, Comp.wrap(ty, draft, cw)))
      +y = {(h - 125 - eh : U32) : U32}
      Out.ops([D.Draw.rect(D.Clip.all(), cx0, y, (cw + 10 : U32), 2, T.Th.accent(), 255),
        D.Draw.rect(D.Clip.all(), cx0, (y + 108 + eh : U32), (cw + 10 : U32), 2, T.Th.accent(), 255),
        D.Draw.rect(D.Clip.all(), cx0, y, 2, (110 + eh : U32), T.Th.accent(), 255),
        D.Draw.rect(D.Clip.all(), (cx0 + cw + 8 : U32), y, 2, (110 + eh : U32), T.Th.accent(), 255)])
    case False{}:
      Out.none()

def Lay.thread(+ty: Ty, +memo: TLMemo, +n: S.Nui, +x0: U32, +x1: U32) -> Out:
  match n:
    case S.Nui{U.Ui{+st, +sel, _, +live, +op, _, _, _, pa, _, _, _, _, _, +nf, _, _}, _, +h, _, _, _, +sc, +caret, +focus, +path, _, _, _}:
      Out.cat(Lay.drop_mark(U.Flag.get(op, "drop"), ty, U.Ui.draft_text(S.Nui.ui(n)), x0, x1, h), Lay.thread.k(ty, memo, U.Ui.thread(st, sel), U.Ui.draft_text(S.Nui.ui(n)), S.Cs.held(n), st, sel, U.Str.get(live, sel), caret, S.Nui.mark(n), focus, S.Blink.on(n), x0, x1, h, sc, pa,
        U.Str.get(nf, "models"), U.Flag.get(op, "models"), U.Ui.pending(S.Nui.ui(n), sel), U.Ui.skills(S.Nui.ui(n)), U.Side.now(S.Nui.ui(n)),
        U.Ui.atts(S.Nui.ui(n), sel), U.Ui.uploading(S.Nui.ui(n), sel), path, nf, U.Ui.deleting(S.Nui.ui(n)), TSel.of(U.Ui.scratch(S.Nui.ui(n), "@ts"), sel), U.Ui.scratch(S.Nui.ui(n), "@menu.off")))

# only the screen shown is laid out (a Bool.pick would lay out all three)
def Lay.main.k(settings: Bool, empty: Bool, +ty: Ty, +memo: TLMemo, +n: S.Nui, +st: M.State, +nf: Map<&2, String>, +v: String, +note: String, +x0: U32, +x1: U32, +h: U32) -> Out:
  match settings empty:
    case True{} _:
      Lay.settings(ty, st, nf, v, note, x0, x1, h, Maybe.default(&2, U32, U32.read(U.Ui.scratch(S.Nui.ui(n), "@set.sc")), 0))
    case False{} True{}:
      Lay.empty(ty, x0, x1, h, List.length(&2, M.Project, U.Ui.projects(st)))
    case False{} False{}:
      Lay.thread(ty, memo, n, x0, x1)

def Lay.main(+ty: Ty, +memo: TLMemo, +n: S.Nui, +x0: U32, +x1: U32) -> Out:
  match n:
    case S.Nui{U.Ui{+st, +sel, _, _, +op, _, _, _, _, +v, _, _, _, +note, +nf, _, _}, _, +h, _, _, _, _, _, _, _, _, _, _}:
      Lay.main.k(U.Flag.get(op, "settings"), String.is_empty(sel), ty, memo, n, st, nf, v, note, x0, x1, h)

def Lay.viewer.if(open: Bool, +ty: Ty, +n: S.Nui, +x0: U32, +w: U32, +h: U32) -> Out:
  match open:
    case True{}:
      Lay.viewer(ty, n, x0, w, h)
    case False{}:
      Out.none()

def Lay.palette.if(open: Bool, +ty: Ty, +n: S.Nui, +w: U32, +h: U32) -> Out:
  match open:
    case True{}:
      Lay.palette(ty, S.Nui.ui(n), w, h, S.Blink.on(n))
    case False{}:
      Out.none()

def Lay.proj.if(open: Bool, +ty: Ty, +n: S.Nui, +w: U32, +h: U32) -> Out:
  match open:
    case True{}:
      Lay.proj(ty, S.Nui.ui(n), w, h, S.Blink.on(n))
    case False{}:
      Out.none()

# the whole window, topmost first
def Lay.frame(+ty: Ty, +memo: TLMemo, +n: S.Nui) -> Out:
  match n:
    case S.Nui{U.Ui{_, _, _, _, _, _, _, _, +pa, _, _, _, +err, note, _, _, _}, +w, +h, _, _, _, _, _, _, _, _, _, _}:
      # the main area and the sidebar are laid out at once
      mn sb = Lay.main(ty, memo, Lay.shrink(n, Lay.term_h(n)), 264, Bool.pick(U32, pa, (264 + U32.shr((w - 264 : U32)) : U32), w)) Lay.sidebar(ty, n, h)
      Lay.rev(Out.all([
        mn,
        Lay.viewer.if(pa, ty, n, (264 + U32.shr((w - 264 : U32)) : U32), w, h),
        Lay.term.of(ty, n, Bool.pick(U32, pa, (264 + U32.shr((w - 264 : U32)) : U32), w), h),
        sb,
        Lay.toast(ty, err, w, h),
        Lay.palette.if(U.Ui.flag(S.Nui.ui(n), "palette"), ty, n, w, h),
        Lay.proj.if(U.Ui.flag(S.Nui.ui(n), "proj"), ty, n, w, h),
        Lay.hover(U.Ui.info(S.Nui.ui(n), "hover"), S.Hover.alpha(n, S.Nui.ms_of(n)))]))

# the timeline's width, as Lay.frame lays it out
def Lay.tl.px(+n: S.Nui) -> U32:
  +w = S.Nui.width(n)
  +x1 = Bool.pick(U32, S.Nui.panel(n), (264 + U32.shr((w - 264 : U32)) : U32), w)
  U32.min((x1 - 264 - 64 : U32), 780)

# the open thread's entries (none with no thread open)
def Lay.memo.es(none: Bool, +n: S.Nui) -> List<&2, M.Entry>:
  match none:
    case True{}:
      Nil{}
    case False{}:
      TL.mine(U.Ui.entries(U.Ui.state(S.Nui.ui(n))), U.Ui.sel(S.Nui.ui(n)), Nil{})

# the memo brought up to this frame: the open thread's entries at its width
def Lay.memo(+ty: Ty, +n: S.Nui, prev: TLMemo) -> TLMemo:
  TL.memo.of(ty, Lay.memo.es(String.is_empty(U.Ui.sel(S.Nui.ui(n))), n), Lay.tl.px(n), U.Ui.sel(S.Nui.ui(n)), prev)

def TL.memo.size(m: TLMemo) -> Nat:
  match m:
    case TLMemo{_, _, its}:
      List.length(&2, TLE, its)
