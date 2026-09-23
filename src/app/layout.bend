import Base
import ../core/model.bend as M
import ../core/client.bend as U
import ../gfx/raster.bend as R
import ../gfx/draw.bend as D
import ../web/dom.bend as N
import ./theme.bend as T
import ./text.bend as X
import ./nui.bend as S

# Nui -> draw ops and hit regions. Ops are gathered bottom-up (paint
# order) and reversed once into the topmost-first order the rasterizer
# wants; hits likewise.

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

def Lay.hit(+x: U32, +y: U32, +w: U32, +h: U32, action: String, value: String) -> S.Hit:
  S.Hit{x, y, (x + w : U32), (y + h : U32), action, value}

def Lay.cols(+px: U32) -> Nat:
  U32.to_nat((px / 8 : U32))

def Lay.fit.k(long: Bool, s: String, +cols: Nat) -> String:
  match long:
    case True{}:
      String.take(s, Nat.sub(cols, 1n)) ++ "~"
    case False{}:
      s

def Lay.fit(+s: String, +cols: Nat) -> String:
  Lay.fit.k(Nat.is_gt(String.length(s), cols), s, cols)

def Lay.textw(s: String) -> U32:
  (U32.from_nat(String.length(s)) * 8 : U32)

# a text button: 1px frame, 8px padding, 24px tall
def Lay.button(+c: D.Clip, +x: U32, +y: U32, +label: String, +color: U32, action: String, value: String) -> Out:
  +w = {(Lay.textw(label) + 16 : U32) : U32}
  Out{List.append(&2, R.Op, D.Draw.rect(c, x, y, w, 24, T.Th.raise(), 255) <> D.Draw.frame(c, x, y, w, 24, T.Th.line()),
      D.Draw.text(label, c, (x + 8 : U32), (y + 4 : U32), color)),
    [Lay.hit(x, y, w, 24, action, value)]}

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

def Lay.row.k(on: Bool, id: String, title: String, +ago: String, +dot: U32, +c: D.Clip, +y: U32) -> Out:
  Out{List.concat(&2, R.Op, [
      Bool.pick(List<&2, R.Op>, on, [D.Draw.rect(c, 0, y, 264, 24, T.Th.raise(), 255), D.Draw.rect(c, 0, y, 2, 24, T.Th.accent(), 255)], Nil{}),
      [D.Draw.rect(c, 12, (y + 9 : U32), 6, 6, dot, 255)],
      D.Draw.text(Lay.fit(title, 24n), c, 26, (y + 4 : U32), T.Th.text()),
      D.Draw.text(ago, c, (252 - Lay.textw(ago) : U32), (y + 4 : U32), T.Th.faint())]),
    [Lay.hit(0, y, 264, 24, "select", id)]}

def Lay.row(t: M.Thread, +sel: String, +now: Nat, +c: D.Clip, +y: U32) -> Out:
  match t:
    case M.Thread{+id, _, title, _, +a, turn, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      Lay.row.k(String.eq(id, sel), id, title, U.Time.ago(now, a), Lay.dot(turn), c, y)

# rows from y down; answers the output and the next y
type Col is Data:
  Col{out: Out, y: U32}

def Lay.col.cat(o: Out, c: Col) -> Col:
  match c:
    case Col{o2, y}:
      Col{Out.cat(o, o2), y}

def Lay.rows(ts: List<&2, M.Thread>, +sel: String, +now: Nat, +c: D.Clip, +y: U32) -> Col:
  match ts:
    case Nil{}:
      Col{Out.none(), y}
    case t <> rest:
      Lay.col.cat(Lay.row(t, sel, now, c, y), Lay.rows(rest, sel, now, c, (y + 24 : U32)))

def Lay.col.then(a: Col, k: U32 -> Col) -> Col:
  match a:
    case Col{o, +y}:
      Lay.col.cat(o, k(y))

def Lay.settled.k(open: Bool, +pid: String, +label: String, ts: List<&2, M.Thread>, +sel: String, +now: Nat, +c: D.Clip, +y: U32) -> Col:
  match open:
    case True{}:
      Lay.col.cat(Out{D.Draw.text(label, c, 12, (y + 4 : U32), T.Th.dim()), [Lay.hit(0, y, 264, 24, "toggle-settled", pid)]},
        Lay.rows(ts, sel, now, c, (y + 24 : U32)))
    case False{}:
      Col{Out{D.Draw.text(label, c, 12, (y + 4 : U32), T.Th.faint()), [Lay.hit(0, y, 264, 24, "toggle-settled", pid)]}, (y + 24 : U32)}

def Lay.settled(open: Bool, +pid: String, st: List<&2, M.Thread>, +sel: String, +now: Nat, +c: D.Clip, +y: U32) -> Col:
  match st:
    case Nil{}:
      Col{Out.none(), y}
    case +t <> +rest:
      Lay.settled.k(open, pid, "Settled " ++ Nat.show(1n+List.length(&2, M.Thread, rest)), t <> rest, sel, now, c, y)

# Project order (as the web view: latest thread activity, newest first)
type PRow is Data:
  PRow{rank: Nat, project: M.Project, shelves: M.Shelves}

def Lay.project(r: PRow, +open: Map<&2, Bool>, +sel: String, +now: Nat, +c: D.Clip, +y: U32) -> Col:
  match r:
    case PRow{_, M.Project{+id, title, _, _, _}, M.Shelves{pinned, active, settled, _}}:
      Lay.col.cat(Out.cat(Out.ops(D.Draw.text(Lay.fit(String.to_upper(title), 28n), c, 12, (y + 8 : U32), T.Th.dim())),
          Out{D.Draw.text("+", c, 244, (y + 8 : U32), T.Th.dim()), [Lay.hit(236, (y + 4 : U32), 24, 24, "new-thread", id)]}),
        Lay.col.then(Lay.rows(pinned, sel, now, c, (y + 32 : U32)), y1 =>
          Lay.col.then(Lay.rows(active, sel, now, c, y1), y2 =>
            Lay.settled(U.Flag.get(open, id), id, settled, sel, now, c, y2))))

def Lay.projects(rs: List<&2, PRow>, +open: Map<&2, Bool>, +sel: String, +now: Nat, +c: D.Clip, +y: U32) -> Col:
  match rs:
    case Nil{}:
      Col{Out.none(), y}
    case r <> t:
      Lay.col.then(Lay.project(r, open, sel, now, c, y), y2 => Lay.projects(t, open, sel, now, c, (y2 + 8 : U32)))

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

def Lay.field(+c: D.Clip, +x: U32, +y: U32, +w: U32, +text: String, +focused: Bool, +caret: Nat, +placeholder: String, +id: String) -> Out:
  +vis = {Lay.fit(text, Nat.sub(Lay.cols(w), 2n)) : String}
  Out{List.concat(&2, R.Op, [
      [D.Draw.rect(c, x, y, w, 24, T.Th.bg(), 255)],
      D.Draw.frame(c, x, y, w, 24, Bool.pick(U32, focused, T.Th.accent(), T.Th.line())),
      Bool.pick(List<&2, R.Op>, String.is_empty(text), D.Draw.text(placeholder, c, (x + 6 : U32), (y + 4 : U32), T.Th.faint()),
        D.Draw.text(vis, c, (x + 6 : U32), (y + 4 : U32), T.Th.text())),
      Bool.pick(List<&2, R.Op>, focused, [D.Draw.rect(c, (x + 6 + (U32.from_nat(Nat.min(caret, String.length(vis))) * 8 : U32) : U32), (y + 4 : U32), 2, 16, T.Th.accent(), 255)], Nil{})]),
    [Lay.hit(x, y, w, 24, "focus", id)]}

def Lay.adding(adding: Bool, +path: String, +focused: Bool, +caret: Nat) -> Out:
  match adding:
    case True{}:
      Out.cat(Lay.field(D.Clip.all(), 12, 46, 190, path, focused, caret, "/path/to/project", "project-path"),
        Lay.button(D.Clip.all(), 208, 46, "Add", T.Th.accent(), "add-project", path))
    case False{}:
      Out.none()

def Lay.col.out(c: Col) -> Out:
  match c:
    case Col{o, _}:
      o

def Lay.sidebar.k(+c: D.Clip, +st: M.State, +sel: String, +open: Map<&2, Bool>, on: Bool, +now: Nat, +adding: Bool, v: String,
    +sd: U32, +caret: Nat, +focus: String, +path: String, +h: U32) -> Out:
  +top = {D.Clip{0, 0, 264, 40} : D.Clip}
  +y0 = {Bool.pick(U32, adding, 76, 40) : U32}
  Out.all([
    Out.ops([D.Draw.rect(D.Clip.all(), 0, 0, 264, h, T.Th.panel(), 255), D.Draw.rect(D.Clip.all(), 263, 0, 1, h, T.Th.line(), 255),
      D.Draw.rect(top, 0, 39, 264, 1, T.Th.line(), 255),
      D.Draw.rect(top, 12, 17, 7, 7, Bool.pick(U32, on, T.Th.ok(), T.Th.bad()), 255)]),
    Out.ops(List.append(&2, R.Op, D.Draw.text("Backplane", top, 26, 12, T.Th.text()), D.Draw.text(v, top, 114, 12, T.Th.faint()))),
    Out{D.Draw.text("+", top, 244, 12, T.Th.dim()), [Lay.hit(236, 8, 24, 24, "toggle-add", "")]},
    Lay.adding(adding, path, String.eq(focus, "project-path"), caret),
    Lay.col.out(Lay.projects(List.sort(~PRow, ~PRow.before, Lay.prows(U.Ui.projects(st), U.Ui.threads(st))), open, sel, now,
      D.Clip{0, y0, 264, h}, U32.sub(y0, sd)))])

def Lay.sidebar(+n: S.Nui, +h: U32) -> Out:
  match n:
    case S.Nui{U.Ui{+st, +sel, _, _, +open, on, +now, adding, _, v, _, _, _}, _, _, _, _, +sd, _, +caret, +focus, +path, _, _}:
      Lay.sidebar.k(D.Clip{0, 40, 264, h}, st, sel, open, on, now, adding, v, sd, caret, focus, path, h)

# Timeline
# --------

# one laid-out line. kind: 0 text, 1 code, 2 user, 3 activity, 4 gap (8px),
# 5 heading, 6 user padding (8px), 7 footer with a Copy button
type TLine is Data:
  TLine{text: String, color: U32, kind: U32, copy: String}

def TL.h(+kind: U32) -> U32:
  Bool.pick(U32, Bool.or(U32.is_eq(kind, 4), U32.is_eq(kind, 6)), 8, 16)

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
      TLine{l, color, kind, ""} <> TL.texts(t, color, kind)

def TL.bullets(ls: List<&2, String>, first: Bool) -> List<&2, TLine>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> t:
      TLine{Bool.pick(String, first, "* ", "  ") ++ l, T.Th.text(), 0, ""} <> TL.bullets(t, False{})

def TL.items(ns: List<&2, N.Node>, +cols: Nat) -> List<&2, TLine>:
  match ns:
    case Nil{}:
      Nil{}
    case n <> t:
      List.append(&2, TLine, TL.bullets(X.Wrap.text(Nd.plain([n]), Nat.sub(cols, 2n)), True{}), TL.items(t, cols))

def TL.code(ls: List<&2, String>, +copy: String, first: Bool) -> List<&2, TLine>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> t:
      TLine{l, T.Th.text(), 1, Bool.pick(String, first, copy, "")} <> TL.code(t, copy, False{})

def TL.block(n: N.Node, +cols: Nat) -> List<&2, TLine>:
  match n:
    case N.El{"p", _, _, +ks}:
      TL.texts(X.Wrap.text(Nd.plain(ks), cols), T.Th.text(), 0)
    case N.El{"ul", _, _, ks}:
      TL.items(ks, cols)
    case N.El{"div", _, _, ks}:
      TL.code(String.split(Nd.plain(ks), '\n'), Nd.plain(ks), True{})
    case N.El{_, _, _, ks}:
      TL.texts(X.Wrap.text(Nd.plain(ks), cols), T.Th.accent(), 5)
    case N.Txt{s}:
      TL.texts(X.Wrap.text(s, cols), T.Th.text(), 0)

# markdown blocks as lines, a gap between blocks
def TL.blocks(ns: List<&2, N.Node>, +cols: Nat) -> List<&2, TLine>:
  match ns:
    case Nil{}:
      Nil{}
    case n <> Nil{}:
      TL.block(n, cols)
    case n <> t:
      List.append(&2, TLine, TL.block(n, cols), TLine{"", 0, 4, ""} <> TL.blocks(t, cols))

def TL.user(ls: List<&2, String>, +copy: String, first: Bool) -> List<&2, TLine>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> t:
      TLine{l, T.Th.text(), 2, Bool.pick(String, first, copy, "")} <> TL.user(t, copy, False{})

def TL.entry(e: M.Entry, +cols: Nat) -> List<&2, TLine>:
  match e:
    case M.Msg{_, _, M.User{}, +text, _}:
      List.concat(&2, TLine, [[TLine{"", 0, 6, ""}], TL.user(X.Wrap.text(text, Nat.sub(cols, 3n)), text, True{}), [TLine{"", 0, 6, ""}, TLine{"", 0, 4, ""}]])
    case M.Msg{_, _, _, +text, _}:
      List.append(&2, TLine, TL.blocks(N.Md.render(text), cols), [TLine{"", 0, 7, text}, TLine{"", 0, 4, ""}])
    case M.Act{_, _, +tone, kind, summary, _}:
      [TLine{Lay.fit(kind ++ "  " ++ summary, cols), Bool.pick(U32, String.eq(tone, "error"), T.Th.bad(), T.Th.dim()), 3, ""}]

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

def TL.entries(es: List<&2, M.Entry>, +cols: Nat) -> List<&2, TLine>:
  match es:
    case Nil{}:
      Nil{}
    case e <> t:
      List.append(&2, TLine, TL.entry(e, cols), TL.entries(t, cols))

def TL.height(ls: List<&2, TLine>, +acc: U32) -> U32:
  match ls:
    case Nil{}:
      acc
    case TLine{_, _, +k, _} <> t:
      TL.height(t, (acc + TL.h(k) : U32))

def TL.copy(+c: D.Clip, +x1: U32, +y: U32, +copy: String) -> Out:
  Bool.pick(Out, String.is_empty(copy), Out.none(),
    Out{D.Draw.text("Copy", c, (x1 - 44 : U32), y, T.Th.faint()), [Lay.hit((x1 - 48 : U32), y, 48, 16, "copy", copy)]})

def TL.draw.k(k: Nat, text: String, +color: U32, +copy: String, +c: D.Clip, +x0: U32, +x1: U32, +y: U32) -> Out:
  match k:
    case 1n:
      Out.cat(Out.ops(D.Draw.rect(c, x0, y, (x1 - x0 : U32), 16, T.Th.code(), 255) <> D.Draw.text(text, c, (x0 + 12 : U32), y, color)), TL.copy(c, x1, y, copy))
    case 2n:
      Out.cat(Out.ops(D.Draw.rect(c, x0, y, (x1 - x0 : U32), 16, T.Th.raise(), 255) <> D.Draw.text(text, c, (x0 + 12 : U32), y, color)), TL.copy(c, x1, y, copy))
    case 6n:
      Out.ops([D.Draw.rect(c, x0, y, (x1 - x0 : U32), 8, T.Th.raise(), 255)])
    case 7n:
      TL.copy(c, x1, y, copy)
    case 4n:
      Out.none()
    case _:
      Out.ops(D.Draw.text(text, c, x0, y, color))

def TL.draw(l: TLine, +c: D.Clip, +x0: U32, +x1: U32, +y: U32) -> Out:
  match l:
    case TLine{text, color, +kind, +copy}:
      TL.draw.k(U32.to_nat(kind), text, color, copy, c, x0, x1, y)

# whether the head line starts above y1
def TL.more(ls: List<&2, TLine>, +y: U32, +y1: U32) -> Bool:
  match ls:
    case Nil{}:
      False{}
    case _ <> _:
      U32.is_lt(y, y1)

# draw the lines from y down while they start above y1
def TL.draw_all(ls: List<&2, TLine>, more: Bool, +c: D.Clip, +x0: U32, +x1: U32, +y: U32, +y1: U32) -> Out:
  match ls more:
    case TLine{t, co, +k, cp} <> +rest True{}:
      Out.cat(TL.draw(TLine{t, co, k, cp}, c, x0, x1, y), TL.draw_all(rest, TL.more(rest, (y + TL.h(k) : U32), y1), c, x0, x1, (y + TL.h(k) : U32), y1))
    case _ _:
      Out.none()

def TL.live.k(empty: Bool, running: Bool, text: String, +cols: Nat) -> List<&2, TLine>:
  match empty running:
    case False{} _:
      TL.blocks(N.Md.render(text), cols)
    case True{} True{}:
      [TLine{"Working", T.Th.faint(), 0, ""}]
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
def Lay.buttons(bs: List<&2, S.Hit>, +y: U32, +x: U32) -> Out:
  match bs:
    case Nil{}:
      Out.none()
    case S.Hit{_, _, _, _, +label, +action} <> t:
      Out.cat(Lay.button(D.Clip.all(), (x - Lay.textw(label) - 16 : U32), y, label, T.Th.text(), action, ""),
        Lay.buttons(t, y, (x - Lay.textw(label) - 24 : U32)))

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

def Lay.header(t: M.Thread, +x0: U32, +x1: U32, panel: Bool) -> Out:
  match t:
    case M.Thread{_, _, +title, _, _, turn, _, _, override, +sa, +ua, pinned, _, branch, _, _, _, _, _, _, _}:
      Out.all([
        Out.ops([D.Draw.rect(D.Clip.all(), x0, 39, (x1 - x0 : U32), 1, T.Th.line(), 255)]),
        Out.ops(D.Draw.text(title, D.Clip{x0, 0, (x1 - 300 : U32), 40}, (x0 + 16 : U32), 12, T.Th.text())),
        Out.ops(D.Draw.text(branch, D.Clip{x0, 0, (x1 - 300 : U32), 40}, (x0 + 24 + Lay.textw(title) : U32), 12, T.Th.faint())),
        Lay.buttons(List.concat(&2, S.Hit, [
          [S.Hit{0, 0, 0, 0, Bool.pick(String, panel, "Board*", "Board"), "panel"},
           S.Hit{0, 0, 0, 0, "Archive", "archive"}],
          Lay.settle(override, Nat.is_gt(sa, ua)),
          [Lay.pin(pinned)],
          Bool.pick(List<&2, S.Hit>, Lay.running(turn), [S.Hit{0, 0, 0, 0, "Stop", "interrupt"}], Nil{})]), 8, (x1 - 16 : U32))])

def Lay.lines(ls: List<&2, String>, +c: D.Clip, +x: U32, +y: U32) -> Out:
  match ls:
    case Nil{}:
      Out.none()
    case l <> t:
      Out.cat(Out.ops(D.Draw.text(l, c, x, y, T.Th.text())), Lay.lines(t, c, x, (y + 16 : U32)))

# the draft's last lines and where the caret sits among them
def Lay.composer(+draft: String, +caret: Nat, +focused: Bool, +x0: U32, +x1: U32, +h: U32, running: Bool) -> Out:
  +cols = Lay.cols((x1 - x0 - 120 : U32))
  +ls = X.Wrap.text(draft, cols)
  +shown = List.drop(&2, String, ls, Nat.sub(List.length(&2, String, ls), 4n))
  +before = X.Wrap.text(String.take(draft, caret), cols)
  +row = Nat.sub(Nat.sub(List.length(&2, String, before), 1n), Nat.sub(List.length(&2, String, ls), List.length(&2, String, shown)))
  +col = String.length(Maybe.default(&2, String, List.last(&2, String, before), ""))
  +y = (h - 96 : U32)
  Out.all([
    Out.ops([D.Draw.rect(D.Clip.all(), x0, y, (x1 - x0 : U32), 1, T.Th.line(), 255),
      D.Draw.rect(D.Clip.all(), (x0 + 16 : U32), (y + 12 : U32), (x1 - x0 - 112 : U32), 72, T.Th.panel(), 255)]),
    Out.ops(D.Draw.frame(D.Clip.all(), (x0 + 16 : U32), (y + 12 : U32), (x1 - x0 - 112 : U32), 72, Bool.pick(U32, focused, T.Th.accent(), T.Th.line()))),
    Bool.pick(Out, String.is_empty(draft),
      Out.ops(D.Draw.text("Ask the agent", D.Clip.all(), (x0 + 26 : U32), (y + 18 : U32), T.Th.faint())),
      Lay.lines(shown, D.Clip{(x0 + 17 : U32), (y + 13 : U32), (x1 - 97 : U32), (y + 83 : U32)}, (x0 + 26 : U32), (y + 18 : U32))),
    Bool.pick(Out, focused, Out.ops([D.Draw.rect(D.Clip.all(), (x0 + 26 + (U32.from_nat(col) * 8 : U32) : U32), (y + 18 + (U32.from_nat(row) * 16 : U32) : U32), 2, 16, T.Th.accent(), 255)]), Out.none()),
    Out{Nil{}, [Lay.hit((x0 + 16 : U32), (y + 12 : U32), (x1 - x0 - 112 : U32), 72, "focus", "composer")]},
    Lay.button(D.Clip.all(), (x1 - 80 : U32), (y + 60 : U32), Bool.pick(String, running, "Queue", "Send"), T.Th.accent(), "send", "")])

# whether the head line ends above top (it is out of view)
def TL.above(ls: List<&2, TLine>, +y: U32, +top: U32) -> Bool:
  match ls:
    case TLine{_, _, +k, _} <> _:
      U32.is_lt((y + TL.h(k) : U32), top)
    case Nil{}:
      False{}

# the lines from the first one that reaches the view
def Lay.skip(ls: List<&2, TLine>, above: Bool, +y: U32, +top: U32) -> List<&2, TLine>:
  match ls above:
    case TLine{_, _, +k, _} <> +rest True{}:
      Lay.skip(rest, TL.above(rest, (y + TL.h(k) : U32), top), (y + TL.h(k) : U32), top)
    case _ _:
      ls

def Lay.skip_y(ls: List<&2, TLine>, +y: U32, +top: U32) -> U32:
  match ls:
    case Nil{}:
      y
    case TLine{_, _, +k, _} <> rest:
      Bool.pick(U32, U32.is_lt((y + TL.h(k) : U32), top), Lay.skip_y(rest, (y + TL.h(k) : U32), top), y)

# the timeline sits between the header (40) and the composer (96), pinned
# to the bottom; sc scrolls up into history
def Lay.timeline(+ls: List<&2, TLine>, +x0: U32, +x1: U32, +h: U32, +sc: U32, chrome: Out) -> Out:
  +top = {40 : U32}
  +bot = {(h - 96 : U32) : U32}
  +view = {(bot - top : U32) : U32}
  +total = TL.height(ls, 0)
  +over = {Bool.pick(U32, U32.is_gt(total, view), (total - view : U32), 0) : U32}
  +s = {U32.min(sc, over) : U32}
  +y0 = {Bool.pick(U32, U32.is_gt(total, view), (top + view + s - total : U32), top) : U32}
  +rest = Lay.skip(ls, TL.above(ls, y0, top), y0, top)
  +ry = Lay.skip_y(ls, y0, top)
  Out.cat(TL.draw_all(rest, TL.more(rest, ry, bot), D.Clip{x0, top, x1, bot}, (x0 + 24 : U32), (x1 - 24 : U32), ry, bot), chrome)

def Lay.thread.k(t: M.Thread, +draft: String, +st: M.State, +sel: String, +live: String, +caret: Nat, +focused: Bool,
    +x0: U32, +x1: U32, +h: U32, +sc: U32, pa: Bool) -> Out:
  match t:
    case M.Thread{id, p, ti, c, a, +turn, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de}:
      Lay.timeline(
        List.append(&2, TLine, TL.entries(TL.mine(U.Ui.entries(st), sel, Nil{}), Lay.cols((x1 - x0 - 48 : U32))),
          TL.live.k(String.is_empty(live), Lay.running(turn), live, Lay.cols((x1 - x0 - 48 : U32)))),
        x0, x1, h, sc,
        Out.cat(Lay.header(M.Thread{id, p, ti, c, a, turn, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de}, x0, x1, pa),
          Lay.composer(draft, caret, focused, x0, x1, h, Lay.running(turn))))

def Lay.thread(+n: S.Nui, +x0: U32, +x1: U32) -> Out:
  match n:
    case S.Nui{U.Ui{+st, +sel, _, +live, _, _, _, _, pa, _, _, _, _}, _, +h, _, _, _, +sc, +caret, +focus, _, _, _}:
      Lay.thread.k(U.Ui.thread(st, sel), U.Ui.draft_text(S.Nui.ui(n)), st, sel, U.Str.get(live, sel), caret, String.eq(focus, "composer"), x0, x1, h, sc, pa)

def Lay.empty(+x0: U32, +x1: U32, +h: U32, +n: Nat) -> Out:
  Out.ops(D.Draw.text(Bool.pick(String, Nat.is_eq(n, 0n), "Add a project with + to start.", "Pick a thread, or start one with + next to a project."),
    D.Clip.all(), (x0 + 32 : U32), (U32.shr(h) - 8 : U32), T.Th.faint()))

def Lay.main(+n: S.Nui, +x0: U32, +x1: U32) -> Out:
  match n:
    case S.Nui{U.Ui{+st, +sel, _, _, _, _, _, _, _, _, _, _, _}, _, +h, _, _, _, _, _, _, _, _, _}:
      Bool.pick(Out, String.is_empty(sel), Lay.empty(x0, x1, h, List.length(&2, M.Project, U.Ui.projects(st))), Lay.thread(n, x0, x1))

def Lay.viewer(+x0: U32, +x1: U32, +h: U32) -> Out:
  Out.ops(List.append(&2, R.Op, [D.Draw.rect(D.Clip.all(), x0, 0, (x1 - x0 : U32), h, 526603, 255), D.Draw.rect(D.Clip.all(), x0, 0, 1, h, T.Th.line(), 255)],
    D.Draw.text("Board", D.Clip.all(), (x0 + 16 : U32), 12, T.Th.dim())))

def Lay.toast(+e: String, +w: U32, +h: U32) -> Out:
  Bool.pick(Out, String.is_empty(e), Out.none(),
    Out{List.append(&2, R.Op, [D.Draw.rect(D.Clip.all(), (w - Lay.textw(e) - 40 : U32), (h - 44 : U32), (Lay.textw(e) + 24 : U32), 28, T.Th.raise(), 255)],
        List.append(&2, R.Op, D.Draw.frame(D.Clip.all(), (w - Lay.textw(e) - 40 : U32), (h - 44 : U32), (Lay.textw(e) + 24 : U32), 28, T.Th.bad()),
          D.Draw.text(e, D.Clip.all(), (w - Lay.textw(e) - 28 : U32), (h - 38 : U32), T.Th.bad()))),
      [Lay.hit((w - Lay.textw(e) - 40 : U32), (h - 44 : U32), (Lay.textw(e) + 24 : U32), 28, "dismiss", "")]})

def Lay.rev(o: Out) -> Out:
  match o:
    case Out{os, hs}:
      Out{List.reverse(&2, R.Op, os), List.reverse(&2, S.Hit, hs)}

# the whole window, topmost first
def Lay.frame(+n: S.Nui) -> Out:
  match n:
    case S.Nui{U.Ui{_, _, _, _, _, _, _, _, +pa, _, _, _, +err}, +w, +h, _, _, _, _, _, _, _, _, _}:
      Lay.rev(Out.all([
        Lay.main(n, 264, Bool.pick(U32, pa, (264 + U32.shr((w - 264 : U32)) : U32), w)),
        Bool.pick(Out, pa, Lay.viewer((264 + U32.shr((w - 264 : U32)) : U32), w, h), Out.none()),
        Lay.sidebar(n, h),
        Lay.toast(err, w, h)]))
