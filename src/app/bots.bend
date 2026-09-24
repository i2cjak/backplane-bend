import Base
import ../core/model.bend as M
import ../core/client.bend as U
import ../core/bot.bend as BT
import ../core/botui.bend as BU
import ../core/cron.bend as CR
import ../core/cat.bend as CT
import ../gfx/raster.bend as R
import ../gfx/draw.bend as D
import ./theme.bend as T
import ./nui.bend as S
import ./layout.bend as L
import ./cats.bend as CA
import ./forms.bend as F
import ./space.bend as SV

# The bots in the window (docs/bots.md): their cats under the projects in
# the sidebar, the rooms, and the main area for a bot (its tabs), a room or
# a bot on another machine. What is shown comes from core/botui.bend; the
# actions are the client's (client.bend's Bots section). Chosen by match,
# so only the screen on show is laid out.

def Bv.sep() -> String:
  SCon{Chr{31}, SNil{}}

# Sidebar
# -------

# a section's name and its + button
def Bv.head(+ty: L.Ty, +c: D.Clip, +label: String, action: String, +on: Bool, +y: U32) -> L.Out:
  L.Out{List.append(&2, R.Op, L.Ty.text(ty, 2n, label, c, 16, y, 28, T.Th.faint()), L.Lay.icon(ty, Bool.pick(String, on, "x", "plus"), c, 236, (y + 6 : U32), T.Th.faint())),
    [L.Lay.hit(228, y, 30, 28, action, "")]}

def Bv.title(+name: String, +remote: Bool, +peer: String) -> String:
  Bool.pick(String, Bool.and(remote, Bool.not(String.is_empty(peer))), name ++ " · " ++ peer, name)

def Bv.note.color(+mood: String) -> U32:
  Bool.pick(U32, String.eq(mood, "wait"), T.Th.warn(), Bool.pick(U32, String.eq(mood, "error"), T.Th.bad(), T.Th.faint()))

# a cat's row: the cat, its name, and its mood
def Bv.row(+ty: L.Ty, +cats: Map<&2, CA.CatF>, +ms: Nat, r: BU.BRow, +c: D.Clip, +y: U32) -> L.Out:
  match r:
    case BU.BRow{+id, +name, _, +look, +mood, +note, +sel, +remote, +peer}:
      +nw = L.Ty.width(ty, 2n, note)
      L.Out{List.concat(&2, R.Op, [
          Bool.pick(List<&2, R.Op>, sel, [D.Draw.rect(c, 6, (y + 1 : U32), 252, 34, T.Th.raise(), 255), D.Draw.rect(c, 6, (y + 1 : U32), 2, 34, T.Th.accent(), 255)], Nil{}),
          CA.Cats.draw(cats, look, mood, ms, c, 14, (y + 4 : U32), 28),
          L.Ty.text(ty, 0n, L.Ty.fit(ty, 0n, Bv.title(name, remote, peer), L.U32.dim(192, nw)), c, 50, y, 36, Bool.pick(U32, sel, T.Th.text(), T.Th.soft())),
          L.Ty.text(ty, 2n, note, c, (252 - nw : U32), y, 36, Bv.note.color(mood))]),
        [L.Lay.hit(0, y, 264, 36, Bool.pick(String, remote, "remote", "bot"), id)]}

def Bv.rows(rs: List<&2, BU.BRow>, +ty: L.Ty, +cats: Map<&2, CA.CatF>, +ms: Nat, +c: D.Clip, +y: U32) -> L.Col:
  match rs:
    case Nil{}:
      L.Col{L.Out.none(), y}
    case r <> t:
      L.Lay.col.cat(Bv.row(ty, cats, ms, r, c, y), Bv.rows(t, ty, cats, ms, c, (y + 36 : U32)))

# the provider chips of the new-bot form (the default one until picked)
def Bv.provs(ps: List<&2, String>, +ty: L.Ty, +cur: String, +c: D.Clip, +x: U32, +y: U32) -> L.Out:
  match ps:
    case Nil{}:
      L.Out.none()
    case +p <> t:
      L.Out.cat(F.Fm.chip(ty, c, x, y, p, String.eq(p, cur), "bfield", "provider" ++ Bv.sep() ++ p), Bv.provs(t, ty, cur, c, (x + L.Lay.button.w(ty, p) + 6 : U32), y))

def Bv.prov(+u: U.Ui) -> String:
  Bool.pick(String, String.is_empty(BU.BU.field(u, "provider")), M.Setting.get(U.Ui.state(u), "agent.provider", "claude"), BU.BU.field(u, "provider"))

# a new bot: its name, who it is, which agent runs it
def Bv.bform(open: Bool, +ty: L.Ty, +f: F.FS, +c: D.Clip, +y: U32) -> L.Col:
  match open:
    case True{}:
      L.Col{L.Out.all([
          F.Fm.field(ty, f, c, 12, y, 240, "name", "bot-create", "", "Name"),
          F.Fm.area(ty, f, c, 12, (y + 34 : U32), 240, 3n, "persona", "bot-create", "", "Who it is, what it does"),
          Bv.provs(["claude", "codex", "grok"], ty, Bv.prov(F.FS.ui(f)), c, 12, (y + 112 : U32)),
          F.Fm.button(ty, c, 12, (y + 146 : U32), "Create", T.Th.accent(), "bot-create", "")]),
        (y + 182 : U32)}
    case False{}:
      L.Col{L.Out.none(), y}

def Bv.picks(ps: List<&2, BU.Pick>, +ty: L.Ty, +c: D.Clip, +x: U32, +y: U32) -> L.Col:
  match ps:
    case Nil{}:
      L.Col{L.Out.none(), (y + 34 : U32)}
    case BU.Pick{+id, +name, +on} <> t:
      +w = L.Lay.button.w(ty, name)
      +wrap = Bool.and(U32.is_gt(x, 12), U32.is_gt((x + w : U32), 252))
      +cx = {Bool.pick(U32, wrap, 12, x) : U32}
      +cy = {Bool.pick(U32, wrap, (y + 34 : U32), y) : U32}
      L.Lay.col.cat(F.Fm.chip(ty, c, cx, cy, name, on, "room-pick", id), Bv.picks(t, ty, c, (cx + w + 6 : U32), cy))

# a new room: its name and the bots in it
def Bv.rform(open: Bool, +ty: L.Ty, +f: F.FS, +c: D.Clip, +y: U32) -> L.Col:
  match open:
    case True{}:
      L.Lay.col.cat(F.Fm.field(ty, f, c, 12, y, 240, "rname", "room-save", "", "Room name"),
        L.Lay.col.then(Bv.picks(BU.BU.picks(F.FS.ui(f)), ty, c, 12, (y + 34 : U32)), +y2 =>
          L.Col{F.Fm.button(ty, c, 12, y2, "Save", T.Th.accent(), "room-save", ""), (y2 + 36 : U32)}))
    case False{}:
      L.Col{L.Out.none(), y}

def Bv.rrow(+ty: L.Ty, r: BU.RRow, +c: D.Clip, +y: U32) -> L.Out:
  match r:
    case BU.RRow{+id, +name, +k, +sel}:
      +cnt = Nat.show(k)
      L.Out{List.concat(&2, R.Op, [
          Bool.pick(List<&2, R.Op>, sel, [D.Draw.rect(c, 6, (y + 1 : U32), 252, 30, T.Th.raise(), 255), D.Draw.rect(c, 6, (y + 1 : U32), 2, 30, T.Th.accent(), 255)], Nil{}),
          L.Ty.text(ty, 0n, "#", c, 20, y, 32, T.Th.faint()),
          L.Ty.text(ty, 0n, L.Ty.fit(ty, 0n, name, 180), c, 38, y, 32, Bool.pick(U32, sel, T.Th.text(), T.Th.soft())),
          L.Ty.text(ty, 2n, cnt, c, (252 - L.Ty.width(ty, 2n, cnt) : U32), y, 32, T.Th.faint())]),
        [L.Lay.hit(0, y, 264, 32, "room", id)]}

def Bv.rrows(rs: List<&2, BU.RRow>, +ty: L.Ty, +c: D.Clip, +y: U32) -> L.Col:
  match rs:
    case Nil{}:
      L.Col{L.Out.none(), (y + 12 : U32)}
    case r <> t:
      L.Lay.col.cat(Bv.rrow(ty, r, c, y), Bv.rrows(t, ty, c, (y + 32 : U32)))

# the sidebar under the projects: a rule, the cats, then the rooms
# what the sidebar's bots section needs, gathered before the sidebar's
# layout calls it (one value, so the call back holds little)
type Sd is Data:
  Sd{ty: L.Ty, cats: Map<&2, CA.CatF>, f: F.FS, ms: Nat, bn: Bool, rn: Bool, rows: List<&2, BU.BRow>, rooms: List<&2, BU.RRow>}

def Bv.sd(+ty: L.Ty, +cats: Map<&2, CA.CatF>, +n: S.Nui) -> Sd:
  Sd{ty, cats, F.Fm.fs(n), S.Nui.ms_of(n), BU.BU.open(S.Nui.ui(n), "@bnew"), BU.BU.open(S.Nui.ui(n), "@rnew"), BU.BU.rows(S.Nui.ui(n)), BU.BU.rooms(S.Nui.ui(n))}

def Bv.side.k(+ty: L.Ty, +cats: Map<&2, CA.CatF>, +f: F.FS, +ms: Nat, +bn: Bool, +rn: Bool, rows: List<&2, BU.BRow>, rooms: List<&2, BU.RRow>, +c: D.Clip, +y: U32) -> L.Col:
  L.Lay.col.cat(L.Out.cat(L.Out.ops([D.Draw.rect(c, 12, (y + 4 : U32), 240, 1, T.Th.line(), 255)]), Bv.head(ty, c, "Bots", "bot-new", bn, (y + 10 : U32))),
    L.Lay.col.then(Bv.bform(bn, ty, f, c, (y + 40 : U32)), y1 =>
      L.Lay.col.then(Bv.rows(rows, ty, cats, ms, c, y1), +y2 =>
        L.Lay.col.cat(Bv.head(ty, c, "Rooms", "room-new", rn, (y2 + 8 : U32)),
          L.Lay.col.then(Bv.rform(rn, ty, f, c, (y2 + 38 : U32)), y3 =>
            Bv.rrows(rooms, ty, c, y3))))))

# the sidebar under the projects: a rule, the cats, then the rooms
def Bv.side.of(sd: Sd, +c: D.Clip, +y: U32) -> L.Col:
  match sd:
    case Sd{+ty, +cats, +f, +ms, +bn, +rn, rows, rooms}:
      Bv.side.k(ty, cats, f, ms, bn, rn, rows, rooms, c, y)

def Bv.side(+ty: L.Ty, +cats: Map<&2, CA.CatF>, +n: S.Nui, +c: D.Clip, +y: U32) -> L.Col:
  Bv.side.of(Bv.sd(ty, cats, n), c, y)

# the selected cat is also drawn large at the top of its view
def Bv.warm.sel(sel: Bool, c: Map<&2, CA.CatF>, +look: Nat, +mood: String, +remote: Bool, +clock: Nat) -> Map<&2, CA.CatF>:
  match sel:
    case True{}:
      CA.Cats.warm(c, look, mood, Bool.pick(U32, remote, 36, 64), clock)
    case False{}:
      c

# the cats on show, posed into the cache at the clock before a frame
def Bv.warm.go(rs: List<&2, BU.BRow>, c: Map<&2, CA.CatF>, +clock: Nat) -> Map<&2, CA.CatF>:
  match rs:
    case Nil{}:
      c
    case BU.BRow{_, _, _, +look, +mood, _, sel, +remote, _} <> t:
      Bv.warm.go(t, Bv.warm.sel(sel, CA.Cats.warm(c, look, mood, 28, clock), look, mood, remote, clock), clock)

def Bv.warm(+u: U.Ui, c: Map<&2, CA.CatF>, +clock: Nat) -> Map<&2, CA.CatF>:
  Bv.warm.go(BU.BU.rows(u), c, clock)

# frames for the cats: while a shown cat moves and the window has the keys
def Bv.moving(+n: S.Nui) -> Bool:
  Bool.and(Bool.and(S.Nui.has_focus(n), Bool.not(S.Lbx.on(n))), BU.BU.moving(S.Nui.ui(n)))

def Bv.info.nat(+n: S.Nui, +k: String) -> Nat:
  Maybe.default(&2, Nat, Nat.read(U.Ui.info(S.Nui.ui(n), k)), 0n)

# the cats' clock ("cat.clock"): a frame at or past the next cat frame
# ("cat.due", main.bend's Shell.cats) while a cat moves sets it to its
# time; any other frame (a key typed) keeps it, so the cats' ops stay as
# they were and no tile of them is drawn again
def Bv.clock(+n: S.Nui, +ms: Nat) -> Nat:
  Bool.pick(Nat, Bool.and(Bv.moving(n), Nat.is_ge(ms, Bv.info.nat(n, "cat.due"))), ms, Bv.info.nat(n, "cat.clock"))

def Bv.stamp(+n: S.Nui, +ms: Nat) -> S.Nui:
  S.Nui.with_ui(n, U.Ui.info_set(S.Nui.ui(n), "cat.clock", Nat.show(Bv.clock(n, ms))))

def Bv.clock.of(+n: S.Nui) -> Nat:
  Bv.info.nat(n, "cat.clock")

# Panes
# -----
# A tab other than Chat is a column under the bot's header that scrolls
# on the wheel ("@set.sc", its hit "set-bg" says how far it may go).

def Bv.hy() -> U32:
  88

def Bv.pane.w(+x0: U32, +x1: U32) -> U32:
  U32.min((x1 - x0 - 64 : U32), 760)

def Bv.pane.x(+x0: U32, +x1: U32) -> U32:
  (x0 + U32.shr((x1 - x0 - Bv.pane.w(x0, x1) : U32)) : U32)

def Bv.off(+u: U.Ui) -> U32:
  Maybe.default(&2, U32, U32.read(U.Ui.scratch(u, "@set.sc")), 0)

# a pane's column laid out from top - off, with its scroll region
def Bv.pane(col: L.Col, +x0: U32, +x1: U32, +top: U32, +off: U32, +h: U32) -> L.Out:
  match col:
    case L.Col{o, +y}:
      L.Out.cat(L.Out{Nil{}, [L.Lay.hit(x0, top, (x1 - x0 : U32), (h - top : U32), "set-bg", U32.show(L.U32.dim((y + off + 40 : U32), h))), L.Lay.hit(0, 0, 0, 0, "", "")]},
        L.Out.hits_below(top, o))

def Bv.h2(+ty: L.Ty, +c: D.Clip, +s: String, +x: U32, +y: U32) -> L.Out:
  L.Out.ops(L.Ty.text(ty, 1n, s, c, x, y, 28, T.Th.text()))

def Bv.faint(+ty: L.Ty, +c: D.Clip, +s: String, +x: U32, +w: U32, +y: U32) -> L.Out:
  L.Out.ops(L.Ty.text(ty, 2n, L.Ty.fit(ty, 2n, s, w), c, x, y, 20, T.Th.faint()))

# lines of wrapped chat text
def Bv.lines(ls: List<&2, String>, +ty: L.Ty, +c: D.Clip, +x: U32, +y: U32, +color: U32) -> List<&2, R.Op>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> t:
      List.append(&2, R.Op, L.Ty.text(ty, 3n, l, c, x, y, 22, color), Bv.lines(t, ty, c, x, (y + 22 : U32), color))

def Bv.nl(+ls: List<&2, String>) -> U32:
  U32.from_nat(List.length(&2, String, ls))

# Memory
# ------

def Bv.mem(+ty: L.Ty, m: BT.Mem, +c: D.Clip, +x: U32, +w: U32, +y: U32) -> L.Col:
  match m:
    case BT.Mem{_, +key, +kind, +text, +tags, _, _}:
      +kw = L.Ty.width(ty, 2n, kind)
      +fw = L.Lay.button.w(ty, "Forget")
      +ls = L.Ty.wrap(ty, 3n, text, (w - 24 : U32))
      +th = {Bool.pick(U32, String.is_empty(tags), 0, 20) : U32}
      +h = {(48 + Bv.nl(ls) * 22 + th : U32) : U32}
      L.Col{L.Out.all([
          L.Out.ops(L.Lay.box(c, x, y, w, h, 0, T.Th.panel(), T.Th.line())),
          L.Out.ops(L.Ty.text(ty, 0n, L.Ty.fit(ty, 0n, key, L.U32.dim(w, (kw + fw + 48 : U32))), c, (x + 12 : U32), (y + 6 : U32), 28, T.Th.text())),
          L.Out.ops(L.Ty.text(ty, 2n, kind, c, (x + w - fw - 20 - kw : U32), (y + 6 : U32), 28, T.Th.accent())),
          F.Fm.button(ty, c, (x + w - fw - 8 : U32), (y + 6 : U32), "Forget", T.Th.soft(), "mem-forget", key),
          L.Out.ops(Bv.lines(ls, ty, c, (x + 12 : U32), (y + 38 : U32), T.Th.soft())),
          Bv.faint(ty, c, tags, (x + 12 : U32), (w - 24 : U32), (y + 40 + Bv.nl(ls) * 22 : U32))]),
        (y + h + 8 : U32)}

def Bv.mems(ms: List<&2, BT.Mem>, +ty: L.Ty, +c: D.Clip, +x: U32, +w: U32, +y: U32) -> L.Col:
  match ms:
    case Nil{}:
      L.Col{L.Out.none(), y}
    case m <> t:
      L.Lay.col.then(Bv.mem(ty, m, c, x, w, y), y2 => Bv.mems(t, ty, c, x, w, y2))

def Bv.memory(+ty: L.Ty, +u: U.Ui, +bot: String, +c: D.Clip, +x: U32, +w: U32, +y: U32) -> L.Col:
  +ms = BU.BU.mems(u, bot)
  L.Lay.col.cat(L.Out.cat(Bv.h2(ty, c, "Memory", x, y),
      Bv.faint(ty, c, Bool.pick(String, List.is_empty(&2, BT.Mem, ms), "Nothing remembered yet. It keeps what it learns about you, your preferences, facts and how-tos here.",
        Nat.show(List.length(&2, BT.Mem, ms)) ++ " items. The ones about you and your preferences go into every turn."), x, w, (y + 30 : U32))),
    Bv.mems(ms, ty, c, x, w, (y + 60 : U32)))

# Routines
# --------

def Bv.onoff(+on: Bool) -> String:
  Bool.pick(String, on, "On", "Off")

def Bv.routine(+ty: L.Ty, r: BT.Routine, +now: Nat, +c: D.Clip, +x: U32, +w: U32, +y: U32) -> L.Col:
  match r:
    case BT.Routine{+id, _, +name, +cron, +prompt, +on, +last, _, _}:
      +b1 = L.Lay.button.w(ty, "Delete")
      +b2 = L.Lay.button.w(ty, "Edit")
      +b3 = L.Lay.button.w(ty, "Run now")
      +b4 = L.Lay.button.w(ty, Bv.onoff(on))
      +bx = {(x + w - 12 - b1 - b2 - b3 - b4 - 18 : U32) : U32}
      L.Col{L.Out.all([
          L.Out.ops(L.Lay.box(c, x, y, w, 90, 0, T.Th.panel(), T.Th.line())),
          L.Out.ops(L.Ty.text(ty, 0n, L.Ty.fit(ty, 0n, name, L.U32.dim((bx - x : U32), 24)), c, (x + 12 : U32), (y + 8 : U32), 28, Bool.pick(U32, on, T.Th.text(), T.Th.dim()))),
          F.Fm.chip(ty, c, bx, (y + 8 : U32), Bv.onoff(on), on, "routine-toggle", id),
          F.Fm.button(ty, c, (bx + b4 + 6 : U32), (y + 8 : U32), "Run now", T.Th.soft(), "routine-run", id),
          F.Fm.button(ty, c, (bx + b4 + b3 + 12 : U32), (y + 8 : U32), "Edit", T.Th.soft(), "routine-edit", id),
          F.Fm.button(ty, c, (bx + b4 + b3 + b2 + 18 : U32), (y + 8 : U32), "Delete", T.Th.soft(), "routine-delete", id),
          Bv.faint(ty, c, CR.Cron.describe(cron), (x + 12 : U32), (w - 24 : U32), (y + 40 : U32)),
          L.Out.ops(L.Ty.text(ty, 2n, L.Ty.fit(ty, 2n, prompt, (w - 24 : U32)), c, (x + 12 : U32), (y + 62 : U32), 20, T.Th.soft()))]),
        (y + 98 : U32)}

def Bv.routines(rs: List<&2, BT.Routine>, +ty: L.Ty, +now: Nat, +c: D.Clip, +x: U32, +w: U32, +y: U32) -> L.Col:
  match rs:
    case Nil{}:
      L.Col{L.Out.none(), y}
    case r <> t:
      L.Lay.col.then(Bv.routine(ty, r, now, c, x, w, y), y2 => Bv.routines(t, ty, now, c, x, w, y2))

def Bv.oform(+ty: L.Ty, +f: F.FS, +editing: Bool, +c: D.Clip, +x: U32, +w: U32, +y: U32) -> L.Col:
  L.Col{L.Out.all([
      L.Out.ops(L.Ty.text(ty, 0n, Bool.pick(String, editing, "Change routine", "New routine"), c, x, y, 28, T.Th.soft())),
      F.Fm.field(ty, f, c, x, (y + 32 : U32), U32.min(w, 280), "oname", "routine-save", "", "Name"),
      F.Fm.field(ty, f, c, (x + U32.min(w, 280) + 8 : U32), (y + 32 : U32), L.U32.dim(w, (U32.min(w, 280) + 8 : U32)), "ocron", "routine-save", "", "When: @daily, 0 9 * * 1-5"),
      Bv.faint(ty, c, CR.Cron.describe(F.Fm.text(f, "ocron")), (x + U32.min(w, 280) + 8 : U32), w, (y + 62 : U32)),
      F.Fm.area(ty, f, c, x, (y + 86 : U32), w, 4n, "oprompt", "routine-save", "", "What it should do each time"),
      F.Fm.button(ty, c, x, (y + 186 : U32), Bool.pick(String, editing, "Save", "Add routine"), T.Th.accent(), "routine-save", "")]),
    (y + 230 : U32)}

def Bv.rtab(+ty: L.Ty, +f: F.FS, +bot: String, +c: D.Clip, +x: U32, +w: U32, +y: U32) -> L.Col:
  +rs = BU.BU.routines(F.FS.ui(f), bot)
  L.Lay.col.cat(L.Out.cat(Bv.h2(ty, c, "Routines", x, y),
      Bv.faint(ty, c, Bool.pick(String, List.is_empty(&2, BT.Routine, rs), "None yet. A routine gives it a prompt on a schedule, in this hub's time zone.",
        "Each runs once when due, even after the hub was off."), x, w, (y + 30 : U32))),
    L.Lay.col.then(Bv.routines(rs, ty, U.Side.now(F.FS.ui(f)), c, x, w, (y + 60 : U32)), y2 =>
      Bv.oform(ty, f, BU.BU.open(F.FS.ui(f), "@onew"), c, x, w, (y2 + 12 : U32))))

# Webhooks
# --------

def Bv.hook(+ty: L.Ty, h: BT.Hook, +now: Nat, +c: D.Clip, +x: U32, +w: U32, +y: U32) -> L.Col:
  match h:
    case BT.Hook{+id, _, +name, _, +revoked, +last, +k}:
      +rw = L.Lay.button.w(ty, "Revoke")
      L.Col{L.Out.all([
          L.Out.ops(L.Lay.box(c, x, y, w, 66, 0, T.Th.panel(), T.Th.line())),
          L.Out.ops(L.Ty.text(ty, 0n, L.Ty.fit(ty, 0n, name, (w - rw - 40 : U32)), c, (x + 12 : U32), (y + 6 : U32), 28, Bool.pick(U32, revoked, T.Th.dim(), T.Th.text()))),
          Bv.faint(ty, c, "POST /hook/" ++ id ++ " · " ++ Bool.pick(String, revoked, "revoked", Bool.pick(String, Nat.is_eq(k, 0n), "never called", Nat.show(k) ++ " calls, last " ++ U.Time.ago(now, last) ++ " ago")),
            (x + 12 : U32), (w - rw - 40 : U32), (y + 36 : U32)),
          Bool.pick(L.Out, revoked, L.Out.none(), F.Fm.button(ty, c, (x + w - rw - 12 : U32), (y + 19 : U32), "Revoke", T.Th.soft(), "hook-revoke", id))]),
        (y + 74 : U32)}

def Bv.hooks(hs: List<&2, BT.Hook>, +ty: L.Ty, +now: Nat, +c: D.Clip, +x: U32, +w: U32, +y: U32) -> L.Col:
  match hs:
    case Nil{}:
      L.Col{L.Out.none(), y}
    case h <> t:
      L.Lay.col.then(Bv.hook(ty, h, now, c, x, w, y), y2 => Bv.hooks(t, ty, now, c, x, w, y2))

# a secret shown once, with a button to copy it
def Bv.secret.k(none: Bool, +ty: L.Ty, +label: String, +s: String, +c: D.Clip, +x: U32, +w: U32, +y: U32) -> L.Col:
  match none:
    case True{}:
      L.Col{L.Out.none(), y}
    case False{}:
      +cw = L.Lay.button.w(ty, "Copy")
      L.Col{L.Out.all([
          L.Out.ops(L.Lay.box(c, x, y, w, 72, 0, T.Th.sel(), T.Th.accent())),
          L.Out.ops(L.Ty.text(ty, 2n, L.Ty.fit(ty, 2n, label, (w - cw - 36 : U32)), c, (x + 12 : U32), (y + 6 : U32), 24, T.Th.accent())),
          L.Out.ops(L.Ty.text(ty, 4n, L.Ty.fit(ty, 4n, s, (w - cw - 36 : U32)), c, (x + 12 : U32), (y + 34 : U32), 28, T.Th.text())),
          F.Fm.button(ty, c, (x + w - cw - 12 : U32), (y + 34 : U32), "Copy", T.Th.accent(), "copy", s)]),
        (y + 84 : U32)}

def Bv.secret(+ty: L.Ty, +label: String, +s: String, +c: D.Clip, +x: U32, +w: U32, +y: U32) -> L.Col:
  Bv.secret.k(String.is_empty(s), ty, label, s, c, x, w, y)

def Bv.htab(+ty: L.Ty, +f: F.FS, +bot: String, +c: D.Clip, +x: U32, +w: U32, +y: U32) -> L.Col:
  +u = F.FS.ui(f)
  +hs = BU.BU.hooks(u, bot)
  +nw = L.Lay.button.w(ty, "New webhook")
  L.Lay.col.cat(L.Out.all([Bv.h2(ty, c, "Webhooks", x, y),
      Bv.faint(ty, c, "Signed POSTs start a turn; the body reaches it as data, never as instructions.", x, w, (y + 30 : U32)),
      F.Fm.field(ty, f, c, x, (y + 58 : U32), (w - nw - 8 : U32), "hname", "hook-new", "", "Name, e.g. GitHub pushes"),
      F.Fm.button(ty, c, (x + w - nw : U32), (y + 58 : U32), "New webhook", T.Th.accent(), "hook-new", "")]),
    L.Lay.col.then(Bv.secret(ty, "Secret for /hook/" ++ U.Ui.scratch(u, "@hook.id") ++ ", shown once. Sign with HMAC-SHA256.", U.Ui.scratch(u, "@hook.secret"), c, x, w, (y + 98 : U32)), y2 =>
      Bv.hooks(hs, ty, U.Side.now(u), c, x, w, y2)))

# Settings
# --------

def Bv.del(armed: Bool, +ty: L.Ty, +name: String, +id: String, +c: D.Clip, +x: U32, +y: U32) -> L.Out:
  match armed:
    case True{}:
      L.Out.cat(F.Fm.button(ty, c, x, y, "Delete " ++ name, T.Th.bad(), "bot-delete", id),
        F.Fm.button(ty, c, (x + L.Lay.button.w(ty, "Delete " ++ name) + 8 : U32), y, "Cancel", T.Th.soft(), "bfield", "delask" ++ Bv.sep()))
    case False{}:
      F.Fm.button(ty, c, x, y, "Delete bot", T.Th.soft(), "bfield", "delask" ++ Bv.sep() ++ "1")

def Bv.peer(+ty: L.Ty, p: BT.Peer, +c: D.Clip, +x: U32, +w: U32, +y: U32) -> L.Col:
  match p:
    case BT.Peer{+id, +name, +url, _, +revoked}:
      +rw = L.Lay.button.w(ty, "Revoke")
      L.Col{L.Out.all([
          L.Out.ops(L.Ty.text(ty, 0n, L.Ty.fit(ty, 0n, name, (w - rw - 16 : U32)), c, x, y, 28, Bool.pick(U32, revoked, T.Th.dim(), T.Th.text()))),
          Bv.faint(ty, c, Bool.pick(String, revoked, "revoked", url), x, (w - rw - 16 : U32), (y + 26 : U32)),
          Bool.pick(L.Out, revoked, L.Out.none(), F.Fm.button(ty, c, (x + w - rw : U32), (y + 8 : U32), "Revoke", T.Th.soft(), "peer-revoke", id))]),
        (y + 54 : U32)}

def Bv.peers(ps: List<&2, BT.Peer>, +ty: L.Ty, +c: D.Clip, +x: U32, +w: U32, +y: U32) -> L.Col:
  match ps:
    case Nil{}:
      L.Col{L.Out.none(), y}
    case p <> t:
      L.Lay.col.then(Bv.peer(ty, p, c, x, w, y), y2 => Bv.peers(t, ty, c, x, w, y2))

def Bv.row2(+ty: L.Ty, +f: F.FS, +name: String, +action: String, +ph: String, +label: String, +value: String, +c: D.Clip, +x: U32, +w: U32, +y: U32) -> L.Out:
  +bw = L.Lay.button.w(ty, label)
  L.Out.cat(F.Fm.field(ty, f, c, x, y, (w - bw - 8 : U32), name, action, value, ph), F.Fm.button(ty, c, (x + w - bw : U32), y, label, T.Th.accent(), action, value))

def Bv.machines(+ty: L.Ty, +f: F.FS, +c: D.Clip, +x: U32, +w: U32, +y: U32) -> L.Col:
  +u = F.FS.ui(f)
  L.Lay.col.cat(L.Out.all([Bv.h2(ty, c, "Machines", x, y),
      Bv.faint(ty, c, "Bots here and on linked hubs can talk. An invite links one hub to another.", x, w, (y + 30 : U32)),
      Bv.row2(ty, f, "purl", "peer-invite", "This hub's address as the other reaches it", "Make invite", "", c, x, w, (y + 58 : U32)),
      Bv.row2(ty, f, "invite", "peer-join", "Paste an invite (bp1:...)", "Join", "", c, x, w, (y + 94 : U32))]),
    L.Lay.col.then(Bv.secret(ty, "Invite, shown once: paste it on the other hub", U.Ui.scratch(u, "@peer.invite"), c, x, w, (y + 134 : U32)), y2 =>
      Bv.peers(BU.BU.peers(u), ty, c, x, w, y2)))

def Bv.gurl.k(none: Bool, +ty: L.Ty, +s: String, +c: D.Clip, +x: U32, +w: U32, +y: U32) -> L.Col:
  match none:
    case True{}:
      L.Col{L.Out.none(), y}
    case False{}:
      +ow = L.Lay.button.w(ty, "Open")
      +cw = L.Lay.button.w(ty, "Copy")
      L.Col{L.Out.all([
          L.Out.ops(L.Ty.text(ty, 2n, L.Ty.fit(ty, 2n, s, (w - ow - cw - 20 : U32)), c, x, y, 28, T.Th.accent())),
          F.Fm.button(ty, c, (x + w - ow - cw - 8 : U32), y, "Open", T.Th.accent(), "open-url", s),
          F.Fm.button(ty, c, (x + w - cw : U32), y, "Copy", T.Th.soft(), "copy", s)]),
        (y + 36 : U32)}

def Bv.google(+ty: L.Ty, +f: F.FS, +c: D.Clip, +x: U32, +w: U32, +y: U32) -> L.Col:
  +u = F.FS.ui(f)
  +st = U.Ui.scratch(u, "@google")
  +hw = U32.shr((w - 8 : U32))
  L.Lay.col.cat(L.Out.all([Bv.h2(ty, c, "Google", x, y),
      Bv.faint(ty, c, Bool.pick(String, String.is_empty(st), "Gmail and Calendar through Google's APIs. Needs an OAuth client (Desktop app) id and secret.", st), x, w, (y + 30 : U32)),
      F.Fm.field(ty, f, c, x, (y + 58 : U32), hw, "gid", "google", "connect", "Client id"),
      F.Fm.field(ty, f, c, (x + hw + 8 : U32), (y + 58 : U32), hw, "gsecret", "google", "connect", "Client secret"),
      F.Fm.button(ty, c, x, (y + 94 : U32), "Sign in", T.Th.accent(), "google", "connect"),
      F.Fm.button(ty, c, (x + L.Lay.button.w(ty, "Sign in") + 8 : U32), (y + 94 : U32), "Sign out", T.Th.soft(), "google", "disconnect")]),
    L.Lay.col.then(Bv.gurl.k(String.is_empty(U.Ui.scratch(u, "@google.url")), ty, U.Ui.scratch(u, "@google.url"), c, x, w, (y + 132 : U32)), +y2 =>
      L.Col{Bv.row2(ty, f, "gpaste", "google", "Browser on another device? Paste where it landed", "Finish", "paste", c, x, w, y2), (y2 + 40 : U32)}))

def Bv.stab(+ty: L.Ty, +f: F.FS, b: BT.Bot, +c: D.Clip, +x: U32, +w: U32, +y: U32) -> L.Col:
  match b:
    case BT.Bot{+id, +name, _, +look, _, _, _}:
      +fw = L.Lay.button.w(ty, "New face")
      L.Lay.col.then(L.Col{L.Out.all([
          Bv.h2(ty, c, "Persona", x, y),
          Bv.faint(ty, c, "Who " ++ name ++ " is and how it works. It reads this at the start of every turn.", x, w, (y + 30 : U32)),
          F.Fm.area(ty, f, c, x, (y + 58 : U32), w, 8n, "persona", "bot-edit", "", "A helpful cat"),
          F.Fm.button(ty, c, x, (y + 234 : U32), "Save", T.Th.accent(), "bot-edit", ""),
          F.Fm.button(ty, c, (x + L.Lay.button.w(ty, "Save") + 8 : U32), (y + 234 : U32), "New face", T.Th.soft(), "bot-look", Nat.show(Nat.mod(1n+look, CT.Cat.looks()))),
          Bv.del(String.eq(F.Fm.text(f, "delask"), "1"), ty, name, id, c, (x + L.Lay.button.w(ty, "Save") + fw + 16 : U32), (y + 234 : U32))]), (y + 290 : U32)}, y2 =>
        L.Lay.col.then(Bv.machines(ty, f, c, x, w, y2), y3 =>
          Bv.google(ty, f, c, x, w, (y3 + 16 : U32))))

# Browser
# -------
# The bot's page: the hub writes its frames as <home>/shots/<bot>.jpg and
# says when a new one is there ("shot.<bot>", nui.bend's Shot). The frame
# is an image the window loads ("img" regions, main.bend's Pics) under the
# key "shot:<bot>:<n>"; the one last loaded ("shot.ok.<bot>") shows while
# the next loads.

def Bv.num(+s: String, +i: Nat) -> U32:
  U32.from_nat(Maybe.default(&2, Nat, Nat.read(Maybe.default(&2, String, List.get(&2, String, String.split(s, 'x'), i), "")), 0n))

def Bv.fit.w(+bw: U32, +bh: U32, +pw: U32, +ph: U32) -> U32:
  U32.min(bw, Bool.pick(U32, U32.is_gt((bw * ph : U32), (bh * pw : U32)), pw, ((bw * ph : U32) / U32.max(bh, 1) : U32)))

# the frame fitted to the pane (never enlarged), centred, with a rule round it
def Bv.shot.draw(+key: String, +size: String, +x0: U32, +x1: U32, +top: U32, +h: U32) -> L.Out:
  +bw = Bv.num(size, 0n)
  +bh = Bv.num(size, 1n)
  +fw = Bv.fit.w(bw, bh, (x1 - x0 - 48 : U32), (h - top - 24 : U32))
  +fh = {((fw * bh : U32) / U32.max(bw, 1) : U32) : U32}
  +x = {(x0 + U32.shr((x1 - x0 - fw : U32)) : U32) : U32}
  L.Out{D.Draw.frame(D.Clip.all(), (x - 1 : U32), (top - 1 : U32), (fw + 2 : U32), (fh + 2 : U32), T.Th.line()), [L.Lay.hit(x, top, fw, fh, "img", key)]}

def Bv.shot.k(state: Nat, +ty: L.Ty, +key: String, +size: String, +name: String, +x0: U32, +x1: U32, +top: U32, +h: U32) -> L.Out:
  match state:
    case 0n:
      L.Out.ops(L.Ty.text(ty, 2n, "Loading the page…", D.Clip.all(), (x0 + 24 : U32), top, 28, T.Th.faint()))
    case 1n:
      L.Out.ops(L.Ty.text(ty, 2n, "No page yet. Ask " ++ name ++ " to open one.", D.Clip.all(), (x0 + 24 : U32), top, 28, T.Th.faint()))
    case _:
      Bv.shot.draw(key, size, x0, x1, top, h)

def Bv.shot.state(+shown: String, +size: String, +next: String) -> Nat:
  Bool.pick(Nat, Bool.and(Bool.not(String.is_empty(shown)), Bool.not(String.is_empty(size))), 2n, Bool.pick(Nat, String.starts_with(next, "err:"), 1n, 0n))

def Bv.browser(+ty: L.Ty, +u: U.Ui, +id: String, +name: String, +x0: U32, +x1: U32, +top: U32, +h: U32) -> L.Out:
  +n = U.Ui.info(u, "shot." ++ id)
  +key = "shot:" ++ id ++ ":" ++ Bool.pick(String, String.is_empty(n), "0", n)
  +shown = U.Ui.info(u, "shot.ok." ++ id)
  +size = U.Ui.info(u, "img:" ++ shown)
  L.Out.cat(L.Out{Nil{}, [L.Lay.hit(x0, top, 1, 1, "img", key)]},
    Bv.shot.k(Bv.shot.state(shown, size, U.Ui.info(u, "img:" ++ key)), ty, shown, size, name, x0, x1, (top + 12 : U32), h))

# A bot
# -----

def Bv.tabs(ts: List<&2, String>, +ty: L.Ty, +cur: String, +x: U32, +y: U32) -> L.Out:
  match ts:
    case Nil{}:
      L.Out.none()
    case +t <> rest:
      L.Out.cat(F.Fm.chip(ty, D.Clip.all(), x, y, BU.BU.tab.label(t), String.eq(t, cur), "bot-tab", t),
        Bv.tabs(rest, ty, cur, (x + L.Lay.button.w(ty, BU.BU.tab.label(t)) + 6 : U32), y))

def Bv.busy(s: M.Status) -> Bool:
  match s:
    case M.StWorking{}:
      True{}
    case M.StQueued{}:
      True{}
    case _:
      False{}

def Bv.stop(on: Bool, +ty: L.Ty, +x1: U32) -> L.Out:
  match on:
    case True{}:
      F.Fm.button(ty, D.Clip.all(), (x1 - 16 - L.Lay.button.w(ty, "Stop") : U32), 12, "Stop", T.Th.soft(), "interrupt", "")
    case False{}:
      L.Out.none()

# the bot's cat (64 px), its name and mood, and its tabs
def Bv.header(+ty: L.Ty, +cats: Map<&2, CA.CatF>, +u: U.Ui, +ms: Nat, b: BT.Bot, +tab: String, +x0: U32, +x1: U32) -> L.Out:
  match b:
    case BT.Bot{+id, +name, +th, +look, pe, cr, de}:
      +st = U.Ui.state(u)
      +mood = BU.Mood.bot(st, U.Side.now(u), BT.Bot{id, name, th, look, pe, cr, de})
      +t = U.Ui.thread(st, th)
      +nw = L.Ty.width(ty, 1n, name)
      L.Out.all([
        L.Out{[D.Draw.rect(D.Clip.all(), x0, 0, (x1 - x0 : U32), Bv.hy(), T.Th.bg(), 255), D.Draw.rect(D.Clip.all(), x0, (Bv.hy() - 1 : U32), (x1 - x0 : U32), 1, T.Th.line(), 255)],
          [L.Lay.hit(x0, 0, (x1 - x0 : U32), Bv.hy(), "", "")]},
        L.Out.ops(CA.Cats.draw(cats, look, mood, ms, D.Clip.all(), (x0 + 20 : U32), 12, 64)),
        L.Out.ops(L.Ty.text(ty, 1n, name, D.Clip.all(), (x0 + 100 : U32), 10, 30, T.Th.text())),
        L.Out.ops(L.Ty.text(ty, 2n, BU.Mood.note(mood) ++ " · " ++ M.Thread.provider(t), D.Clip.all(), (x0 + 112 + nw : U32), 10, 30, Bv.note.color(mood))),
        Bv.stop(Bv.busy(U.Side.status(st, U.Ui.thread(st, th))), ty, x1),
        Bv.tabs(BU.BU.tabs(), ty, tab, (x0 + 100 : U32), 48)])

def Bv.tab.n(+t: String) -> Nat:
  S.Nui.pos(BU.BU.tabs(), t, 0n)

# a tab's pane (Chat is the thread itself, laid out by Bv.bot.k)
def Bv.pane.k(k: Nat, +ty: L.Ty, +f: F.FS, +b: BT.Bot, +c: D.Clip, +x: U32, +w: U32, +y: U32) -> L.Col:
  match k:
    case 1n:
      SV.Spv.draw(ty, f, BU.BU.space(F.FS.ui(f), b), BT.Bot.id(b), c, x, w, y)
    case 3n:
      Bv.memory(ty, F.FS.ui(f), BT.Bot.id(b), c, x, w, y)
    case 4n:
      Bv.rtab(ty, f, BT.Bot.id(b), c, x, w, y)
    case 5n:
      Bv.htab(ty, f, BT.Bot.id(b), c, x, w, y)
    case _:
      Bv.stab(ty, f, b, c, x, w, y)

def Bv.bot.k(k: Nat, +ty: L.Ty, +memo: L.TLMemo, +n: S.Nui, +b: BT.Bot, +x0: U32, +x1: U32) -> L.Out:
  match k:
    case 0n:
      L.Out.hits_below(Bv.hy(), L.Lay.thread.at(ty, memo, n, x0, x1, (Bv.hy() - 52 : U32)))
    case 2n:
      Bv.browser(ty, S.Nui.ui(n), BT.Bot.id(b), BT.Bot.name(b), x0, x1, (Bv.hy() + 16 : U32), S.Nui.height(n))
    case +j:
      +top = {(Bv.hy() + 24 : U32) : U32}
      +off = Bv.off(S.Nui.ui(n))
      Bv.pane(Bv.pane.k(j, ty, F.Fm.fs(n), b, D.Clip{x0, Bv.hy(), x1, S.Nui.height(n)}, Bv.pane.x(x0, x1), Bv.pane.w(x0, x1), (top - off : U32)),
        x0, x1, Bv.hy(), off, S.Nui.height(n))

def Bv.bot(+ty: L.Ty, +memo: L.TLMemo, +cats: Map<&2, CA.CatF>, +n: S.Nui, +b: BT.Bot, +x0: U32, +x1: U32) -> L.Out:
  +tab = BU.BU.tab(S.Nui.ui(n))
  L.Out.cat(Bv.bot.k(Bv.tab.n(tab), ty, memo, n, b, x0, x1), Bv.header(ty, cats, S.Nui.ui(n), S.Nui.ms_of(n), b, tab, x0, x1))

# Rooms and bots elsewhere
# ------------------------
# A conversation: its posts, newest at the bottom (the wheel goes back,
# "@chat.sc" from the bottom), and a line to write in.

type PostL is Data:
  PostL{from: String, when: String, lines: List<&2, String>}

def Bv.posts.l(ps: List<&2, BT.Post>, +ty: L.Ty, +u: U.Ui, +now: Nat, +w: U32) -> List<&2, PostL>:
  match ps:
    case Nil{}:
      Nil{}
    case BT.Post{_, _, +from, +text, _, +at} <> t:
      PostL{BU.BU.member(u, from), U.Time.ago(now, at), L.Ty.wrap(ty, 3n, text, w)} <> Bv.posts.l(t, ty, u, now, w)

def Bv.posts.h(ps: List<&2, PostL>, +acc: U32) -> U32:
  match ps:
    case Nil{}:
      acc
    case PostL{_, _, +ls} <> t:
      Bv.posts.h(t, (acc + 36 + Bv.nl(ls) * 22 : U32))

def Bv.posts.draw(ps: List<&2, PostL>, +ty: L.Ty, +c: D.Clip, +x: U32, +y: U32) -> List<&2, R.Op>:
  match ps:
    case Nil{}:
      Nil{}
    case PostL{+from, +when, +ls} <> t:
      List.concat(&2, R.Op, [
        L.Ty.text(ty, 0n, from, c, x, y, 24, Bool.pick(U32, String.eq(from, "you"), T.Th.soft(), T.Th.accent())),
        L.Ty.text(ty, 2n, when, c, (x + L.Ty.width(ty, 0n, from) + 10 : U32), y, 24, T.Th.faint()),
        Bv.lines(ls, ty, c, x, (y + 24 : U32), T.Th.text()),
        Bv.posts.draw(t, ty, c, x, (y + 36 + Bv.nl(ls) * 22 : U32))])

def Bv.chat.off(+u: U.Ui) -> U32:
  Maybe.default(&2, U32, U32.read(U.Ui.scratch(u, "@chat.sc")), 0)

# the posts from top to bottom, the newest at the bottom unless scrolled
def Bv.chat(+ty: L.Ty, ps: List<&2, BT.Post>, +u: U.Ui, +empty: String, +x0: U32, +x1: U32, +top: U32, +bottom: U32) -> L.Out:
  +w = Bv.pane.w(x0, x1)
  +x = Bv.pane.x(x0, x1)
  +pl = Bv.posts.l(ps, ty, u, U.Side.now(u), w)
  +total = Bv.posts.h(pl, 0)
  +view = {L.U32.dim(bottom, (top + 16 : U32)) : U32}
  +most = L.U32.dim(total, view)
  +off = U32.min(Bv.chat.off(u), most)
  +y = {Bool.pick(U32, U32.is_le(total, view), (top + 16 : U32), ((bottom - total : U32) + off : U32)) : U32}
  L.Out{List.append(&2, R.Op, Bool.pick(List<&2, R.Op>, U32.is_eq(total, 0), L.Ty.text(ty, 2n, empty, D.Clip.all(), x, (top + 16 : U32), 28, T.Th.faint()), Nil{}),
      Bv.posts.draw(pl, ty, D.Clip{x0, top, x1, bottom}, x, y)),
    [L.Lay.hit(x0, top, (x1 - x0 : U32), (bottom - top : U32), "chat-bg", U32.show(most))]}

# the line at the bottom: Enter or Send posts it
def Bv.say(+ty: L.Ty, +f: F.FS, +name: String, +action: String, +ph: String, +x0: U32, +x1: U32, +h: U32) -> L.Out:
  +w = Bv.pane.w(x0, x1)
  +x = Bv.pane.x(x0, x1)
  L.Out.cat(L.Out.ops([D.Draw.rect(D.Clip.all(), x0, (h - 60 : U32), (x1 - x0 : U32), 1, T.Th.line(), 255)]),
    Bv.row2(ty, f, name, action, ph, "Send", "", D.Clip.all(), x, w, (h - 44 : U32)))

def Bv.top(+ty: L.Ty, +title: String, +sub: String, +x0: U32, +x1: U32, right: L.Out) -> L.Out:
  +tw = L.Ty.width(ty, 1n, title)
  L.Out.all([L.Out.ops([D.Draw.rect(D.Clip.all(), x0, 0, (x1 - x0 : U32), 52, T.Th.bg(), 255), D.Draw.rect(D.Clip.all(), x0, 51, (x1 - x0 : U32), 1, T.Th.line(), 255)]),
    L.Out.ops(L.Ty.text(ty, 1n, title, D.Clip.all(), (x0 + 24 : U32), 0, 52, T.Th.text())),
    L.Out.ops(L.Ty.text(ty, 2n, L.Ty.fit(ty, 2n, sub, L.U32.dim((x1 - x0 : U32), (tw + 200 : U32))), D.Clip.all(), (x0 + 36 + tw : U32), 0, 52, T.Th.faint())),
    right])

def Bv.room(+ty: L.Ty, +n: S.Nui, r: BT.Room, +x0: U32, +x1: U32) -> L.Out:
  match r:
    case BT.Room{+id, +name, ms, cr, de}:
      +u = S.Nui.ui(n)
      +h = S.Nui.height(n)
      +dw = L.Lay.button.w(ty, "Delete room")
      L.Out.all([
        Bv.chat(ty, BU.BU.posts(u, id), u, "Nothing said here yet. Every bot in the room hears what is posted.", x0, x1, 52, (h - 60 : U32)),
        Bv.say(ty, F.Fm.fs(n), "rpost", "room-post", "Write to the room", x0, x1, h),
        Bv.top(ty, "# " ++ name, BU.BU.members(u, BT.Room{id, name, ms, cr, de}), x0, x1,
          F.Fm.button(ty, D.Clip.all(), (x1 - 16 - dw : U32), 12, "Delete room", T.Th.soft(), "room-delete", id))])

def Bv.far.find(rs: List<&2, BU.BRow>, +id: String) -> Maybe<&2, BU.BRow>:
  match rs:
    case Nil{}:
      None{}
    case BU.BRow{+i, +na, +th, +lk, +mo, +no, +se, +re, +pe} <> t:
      Bool.pick(Maybe<&2, BU.BRow>, String.eq(i, id), Some{BU.BRow{i, na, th, lk, mo, no, se, re, pe}}, Bv.far.find(t, id))

def Bv.far.cat(m: Maybe<&2, BU.BRow>, +cats: Map<&2, CA.CatF>, +ms: Nat, +x0: U32) -> L.Out:
  match m:
    case Some{BU.BRow{_, _, _, +look, +mood, +note, _, _, _}}:
      L.Out.ops(List.append(&2, R.Op, CA.Cats.draw(cats, look, mood, ms, D.Clip.all(), (x0 + 16 : U32), 8, 36), []))
    case None{}:
      L.Out.none()

def Bv.remote(+ty: L.Ty, +cats: Map<&2, CA.CatF>, +n: S.Nui, +id: String, +x0: U32, +x1: U32) -> L.Out:
  +u = S.Nui.ui(n)
  +h = S.Nui.height(n)
  L.Out.all([
    Bv.chat(ty, BU.BU.remote.posts(u, id), u, "Write to " ++ id ++ ". It answers from its own machine.", x0, x1, 52, (h - 60 : U32)),
    Bv.say(ty, F.Fm.fs(n), "rtext", "remote-send", "Write to " ++ id, x0, x1, h),
    Bv.top(ty, "     " ++ id, "on a linked machine", x0, x1, Bv.far.cat(Bv.far.find(BU.BU.remote(u), id), cats, S.Nui.ms_of(n), x0))])

# The main area and the frame
# ---------------------------

def Bv.view(v: BU.View, +ty: L.Ty, +memo: L.TLMemo, +cats: Map<&2, CA.CatF>, +n: S.Nui, +x1: U32) -> Maybe<&2, L.Out>:
  match v:
    case BU.VThread{}:
      None{}
    case BU.VBot{b}:
      Some{Bv.bot(ty, memo, cats, n, b, 264, x1)}
    case BU.VRoom{r}:
      Some{Bv.room(ty, n, r, 264, x1)}
    case BU.VRemote{+id}:
      Some{Bv.remote(ty, cats, n, id, 264, x1)}

def Bv.main.k(settings: Bool, +ty: L.Ty, +memo: L.TLMemo, +cats: Map<&2, CA.CatF>, +n: S.Nui) -> Maybe<&2, L.Out>:
  match settings:
    case True{}:
      None{}
    case False{}:
      Bv.view(BU.BU.view(S.Nui.ui(n)), ty, memo, cats, L.Lay.shrink(n, L.Lay.term_h(n)), L.Lay.x1(n))

# a bot's, room's or remote bot's main area (None: the usual one)
def Bv.main(+ty: L.Ty, +memo: L.TLMemo, +cats: Map<&2, CA.CatF>, +n: S.Nui) -> Maybe<&2, L.Out>:
  Bv.main.k(U.Ui.flag(S.Nui.ui(n), "settings"), ty, memo, cats, n)

def Bv.frame.k(sd: Sd, +ty: L.Ty, +memo: L.TLMemo, +cats: Map<&2, CA.CatF>, +n: S.Nui) -> L.Out:
  L.Lay.frame.x(ty, memo, n, c => y => Bv.side.of(sd, c, y), Bv.main(ty, memo, cats, n))

# the whole window, topmost first, with the bots in it
def Bv.frame(+ty: L.Ty, +memo: L.TLMemo, +cats: Map<&2, CA.CatF>, +n: S.Nui) -> L.Out:
  Bv.frame.k(Bv.sd(ty, cats, n), ty, memo, cats, n)
