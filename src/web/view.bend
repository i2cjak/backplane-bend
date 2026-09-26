import Base
import ../core/model.bend as M
import ./dom.bend as D
import ./icon.bend as WI
import ../core/client.bend as U
import ../core/attach.bend as AT
import ../core/vt.bend as VT
import ../core/diff.bend as DF
import ../core/images.bend as IM
import ../core/fold.bend as FO
import ../core/badge.bend as BG
import ../core/todo.bend as TD
import ../core/bot.bend as BT
import ../core/botui.bend as BI
import ./bots.bend as WB
import ../core/voice.bend as VC

# Ui -> Node. Every decision (order, shelf, status) comes from core defs
# with laws behind them; this file only lays them out.

# Sidebar
# -------

type PRow is Data:
  PRow{rank: Nat, project: M.Project, shelves: M.Shelves}

def PRow.before(a: PRow, b: PRow) -> Bool:
  match a b:
    case PRow{ra, _, _} PRow{rb, _, _}:
      Nat.is_ge(ra, rb)

def View.latest(ts: List<&2, M.Thread>, +acc: Nat) -> Nat:
  match ts:
    case Nil{}:
      acc
    case M.Thread{_, _, _, _, +a, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} <> t:
      View.latest(t, M.Time.max(acc, a))

def View.rows.k(removed: Bool, p: M.Project, +mine: List<&2, M.Thread>, +c: Nat, rest: List<&2, PRow>) -> List<&2, PRow>:
  match removed:
    case True{}:
      rest
    case False{}:
      PRow{View.latest(mine, c), p, M.Sidebar.order(M.Sidebar.split(mine))} <> rest

# a project's place in the sidebar: its latest thread activity (or its
# creation), newest first, as T3Code's default "updated" order
def View.rows(ps: List<&2, M.Project>, +ts: List<&2, M.Thread>) -> List<&2, PRow>:
  match ps:
    case Nil{}:
      Nil{}
    case M.Project{+id, ti, r, +c, +rm} <> t:
      View.rows.k(rm, M.Project{id, ti, r, c, rm}, M.Thread.filter_project(ts, id), c, View.rows(t, ts))

# a sidebar row: its status dot, title and age (a snoozed row: the time
# left); rows of a shelf with manual order get move buttons on hover
def View.row.k(+id: String, +title: String, +ago: String, +dot: String, +sel: String, +movable: Bool) -> D.Node:
  D.El{"div", id, [D.At{"class", Bool.pick(String, String.eq(id, sel), "thread on", "thread")}, D.At{"data-value", id}, D.On{"click", "select"}, D.On{"contextmenu", "row-toggle"}],
    D.Dom.cat([D.Dom.span("dot " ++ dot, ""), D.Dom.span("title", title)],
      D.Dom.cat(Bool.pick(List<&2, D.Node>, movable, [D.El{"span", "", [D.At{"class", "moves"}], [D.Dom.button("move", "move", id ++ "|up", "Move up", "↑"), D.Dom.button("move", "move", id ++ "|down", "Move down", "↓")]}], Nil{}),
        [D.Dom.span("ago", ago)]))}

def View.row(+t: M.Thread, +st: M.State, +sel: String, +now: Nat, +movable: Bool, +snoozed: Bool) -> D.Node:
  match t:
    case M.Thread{+id, _, +title, _, +a, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      View.row.k(id, title, Bool.pick(String, snoozed, U.Time.ago(U.Side.until(st, id), now), U.Time.ago(now, a)), M.Status.name(U.Side.status(st, t)), sel, movable)

def View.rows_in(ts: List<&2, M.Thread>, +st: M.State, +sel: String, +now: Nat, +movable: Bool, +snoozed: Bool) -> List<&2, D.Node>:
  match ts:
    case Nil{}:
      Nil{}
    case +t <> rest:
      View.row(t, st, sel, now, movable, snoozed) <> View.rows_in(rest, st, sel, now, movable, snoozed)

def View.rows_of(ts: List<&2, M.Thread>, +st: M.State, +sel: String, +now: Nat) -> List<&2, D.Node>:
  View.rows_in(ts, st, sel, now, False{}, False{})

def View.shelf.k(open: Bool, +key: String, +label: String, ts: List<&2, M.Thread>, +st: M.State, +sel: String, +now: Nat) -> List<&2, D.Node>:
  match open:
    case True{}:
      WI.WIcon.button("shelf open", "toggle-settled", key, "Hide", "chevron-down", 14, label) <> View.rows_of(ts, st, sel, now)
    case False{}:
      [WI.WIcon.button("shelf", "toggle-settled", key, "Show", "chevron-right", 14, label)]

# a collapsible shelf (Settled, Archived): its label and count, then its
# rows when open; nothing when empty
def View.shelf(open: Bool, +key: String, +name: String, ts: List<&2, M.Thread>, +st: M.State, +sel: String, +now: Nat) -> List<&2, D.Node>:
  match ts:
    case Nil{}:
      Nil{}
    case +t <> +rest:
      View.shelf.k(open, key, name ++ " " ++ Nat.show(List.length(&2, M.Thread, t <> rest)), t <> rest, st, sel, now)

# snoozed threads, soonest to wake first
def View.snoozed(ts: List<&2, M.Thread>, +st: M.State, +sel: String, +now: Nat) -> List<&2, D.Node>:
  match ts:
    case Nil{}:
      Nil{}
    case +t <> +rest:
      D.Dom.span("shelf-label", "Snoozed") <> View.rows_in(t <> rest, st, sel, now, False{}, True{})

# a project's badge editor, open under its name: its tints, then its
# icons (a click sets one and leaves it open; a click anywhere else, on the
# shade behind it, closes it)
def View.swatches(cs: List<&2, String>, +cur: String, +id: String) -> List<&2, D.Node>:
  match cs:
    case Nil{}:
      Nil{}
    case +c <> t:
      D.El{"button", "", [D.At{"class", Bool.pick(String, String.eq(c, cur), "swatch on", "swatch")}, D.At{"style", "background:" ++ BG.Badge.css(c)}, D.At{"title", c},
        D.At{"data-value", BG.Badge.color_key(id) ++ "=" ++ c}, D.On{"click", "look-set"}], Nil{}} <> View.swatches(t, cur, id)

def View.glyphs(ns: List<&2, String>, +cur: String, +id: String) -> List<&2, D.Node>:
  match ns:
    case Nil{}:
      Nil{}
    case +n <> t:
      WI.WIcon.button(Bool.pick(String, String.eq(n, cur), "glyph on", "glyph"), "look-set", BG.Badge.icon_key(id) ++ "=" ++ n, n, n, 16, "") <> View.glyphs(t, cur, id)

# its last row removes the project (two clicks: client.bend's
# Ui.remove_project)
def View.look(open: Bool, +st: M.State, +id: String, +rm: Bool) -> List<&2, D.Node>:
  match open:
    case True{}:
      [D.El{"div", "", [D.At{"class", "shade"}, D.At{"data-value", ""}, D.On{"click", "look"}], Nil{}},
       D.El{"div", "", [D.At{"class", "look"}], [
         D.El{"div", "", [D.At{"class", "swatches"}], View.swatches(BG.Badge.colors(), BG.Badge.color(st, id), id)},
         D.El{"div", "", [D.At{"class", "glyphs"}], View.glyphs(BG.Badge.icons(), BG.Badge.icon(st, id), id)},
         D.Dom.button("remove", "proj-remove", id, "Remove from the sidebar (adding its folder again brings it back)", Bool.pick(String, rm, "Click again to remove", "Remove project"))]}]
    case False{}:
      Nil{}

def View.project(r: U.SRow, +open: Map<&2, Bool>, +st: M.State, +sel: String, +now: Nat, +look: String, +rm: String) -> D.Node:
  match r:
    case U.SRow{_, M.Project{+id, title, root, _, _}, M.Shelves{pinned, active, settled, hidden, snoozed}}:
      D.El{"section", id, [D.At{"class", "project"}, D.At{"style", "--tint:" ++ BG.Badge.css_of(st, id)}, D.At{"data-drag-to", id}, D.At{"data-drag-act", "reorder-project"}],
        List.concat(&2, D.Node, [[D.El{"div", "", [D.At{"class", "project-head"}, D.At{"title", root}, D.At{"draggable", "true"}, D.At{"data-drag", id}, D.At{"data-drag-act", "reorder-project"}],
            [WI.WIcon.button("badge", "look", id, "Colour and icon", BG.Badge.icon(st, id), 14, ""), D.Dom.span("name", title), WI.WIcon.button("icon", "new-thread", id, "New thread", "plus", 16, "")]}],
          View.look(String.eq(look, id), st, id, String.eq(rm, id)),
          View.rows_in(pinned, st, sel, now, True{}, False{}),
          View.rows_in(active, st, sel, now, True{}, False{}),
          View.snoozed(snoozed, st, sel, now),
          View.shelf(U.Flag.get(open, id), id, "Settled", settled, st, sel, now),
          View.shelf(U.Flag.get(open, "arch:" ++ id), "arch:" ++ id, "Archived", M.Archive.of(hidden), st, sel, now)])}

def View.projects(rs: List<&2, U.SRow>, +open: Map<&2, Bool>, +st: M.State, +sel: String, +now: Nat, +look: String, +rm: String) -> List<&2, D.Node>:
  match rs:
    case Nil{}:
      Nil{}
    case r <> t:
      View.project(r, open, st, sel, now, look, rm) <> View.projects(t, open, st, sel, now, look, rm)

# the project search, while open ("proj-find" opens and shuts it)
def View.find(find: Bool, +q: String) -> List<&2, D.Node>:
  match find:
    case True{}:
      [D.El{"div", "", [D.At{"class", "find"}], [WB.WB.input("proj-find", "pq", q, "Find a project", "proj-go")]}]
    case False{}:
      Nil{}

def View.add(adding: Bool) -> List<&2, D.Node>:
  match adding:
    case True{}:
      [D.El{"div", "", [D.At{"class", "add"}], [
        D.El{"input", "project-path", [D.At{"id", "project-path"}, D.At{"placeholder", "/path/to/project"}, D.At{"data-enter", "add-project"}, D.At{"data-value", "#project-path"}], Nil{}},
        D.Dom.button("primary", "add-project", "#project-path", "Add project", "Add")]}]
    case False{}:
      Nil{}

# the owner's machines (only with more than one): this page's hub first;
# picking another opens that machine's page
def View.mrows(rs: List<&2, U.MRow>) -> List<&2, D.Node>:
  match rs:
    case Nil{}:
      Nil{}
    case U.MRow{+n, url, +on} <> t:
      D.Dom.button(Bool.pick(String, on, "machine on", "machine"), "machine", url, n, n) <> View.mrows(t)

def View.machines(many: Bool, rs: List<&2, U.MRow>) -> List<&2, D.Node>:
  match many:
    case True{}:
      [D.El{"div", "", [D.At{"class", "machines"}], View.mrows(rs)}]
    case False{}:
      Nil{}

def View.sidebar.k(+ms: List<&2, U.MRow>, +st: M.State, +sel: String, +open: Map<&2, Bool>, on: Bool, +now: Nat, adding: Bool, v: String, +look: String, +rm: String, +q: String, bots: List<&2, D.Node>) -> D.Node:
  D.El{"aside", "sidebar", [D.At{"class", "sidebar"}],
        D.Dom.cat([D.El{"div", "", [D.At{"class", "brand"}], [
            D.Dom.span(Bool.pick(String, on, "conn on", "conn"), ""),
            D.Dom.span("name", "Backplane"), D.Dom.span("ver", v),
            WI.WIcon.button(Bool.pick(String, U.Flag.get(open, "psearch"), "icon on", "icon"), "proj-find", "", "Find a project", "search", 16, ""),
            WI.WIcon.button("icon", "proj-open", "", "Add project", "plus", 16, "")]}],
          D.Dom.cat(View.machines(Nat.is_gt(List.length(&2, U.MRow, ms), 1n), ms), D.Dom.cat(View.add(adding), D.Dom.cat(View.find(U.Flag.get(open, "psearch"), q),
            D.Dom.cat(View.projects(U.Side.shown(st, now, q), open, st, sel, now, look, rm), D.Dom.cat(bots,
            [WI.WIcon.button("settings-link", "flag", "settings", "Settings", "settings", 16, "Settings")]))))))}

def View.sidebar.u(bots: List<&2, D.Node>, u: U.Ui) -> D.Node:
  match u:
    case U.Ui{+st, +sel, +d, l, +open, +on, +now, +adding, pa, +v, r, w, e, note, nf, ob, tr}:
      View.sidebar.k(U.Machines.rows(U.Ui{st, sel, d, l, open, on, now, adding, pa, v, r, w, e, note, nf, ob, tr}), st, sel, open, on, now, adding, v, U.Str.get(d, "@look"), U.Str.get(d, "@rm"), U.Find.q(open, d), bots)

# the sidebar: the projects, then the bots and rooms (bots.bend)
def View.sidebar(+u: U.Ui) -> D.Node:
  View.sidebar.u(WB.WB.side(u), u)

# Thread
# ------

def View.mine.k(same: Bool, e: M.Entry, rest: List<&2, M.Entry>) -> List<&2, M.Entry>:
  match same:
    case True{}:
      e <> rest
    case False{}:
      rest

def View.entry_thread(e: M.Entry) -> String:
  match e:
    case M.Msg{_, t, _, _, _}:
      t
    case M.Act{_, t, _, _, _, _}:
      t

def View.link(+cls: String, +label: String, +to: String) -> D.Node:
  D.El{"button", "", [D.At{"class", "link " ++ cls}, D.At{"data-value", to}, D.On{"click", "select"}], [D.Txt{label}]}

def View.from.k(none: Bool, +from: String, +st: M.State) -> List<&2, D.Node>:
  match none:
    case True{}:
      Nil{}
    case False{}:
      [View.link("in", "← from " ++ U.Tasks.title(st, from), from)]

def View.entry_id(e: M.Entry) -> String:
  match e:
    case M.Msg{i, _, _, _, _}:
      i
    case M.Act{i, _, _, _, _, _}:
      i

# a thread's entries, oldest first (the state keeps them newest first)
def View.mine(es: List<&2, M.Entry>, +th: String, acc: List<&2, M.Entry>) -> List<&2, M.Entry>:
  match es:
    case Nil{}:
      acc
    case +e <> t:
      View.mine(t, th, View.mine.k(Bool.or(String.eq(View.entry_thread(e), th), String.eq(M.Link.from(View.entry_id(e)), th)), e, acc))

def View.phase.k(idle: Bool, +label: String, +name: String) -> List<&2, D.Node>:
  match idle:
    case True{}:
      Nil{}
    case False{}:
      [D.El{"div", "live", [D.At{"class", "phase " ++ name}], [D.El{"span", "", [D.At{"class", "dot " ++ name}], Nil{}}, D.Txt{label}]}]

# the reply streaming in, else the thread's phase
def View.live.k(empty: Bool, +ph: M.Phase, text: String) -> List<&2, D.Node>:
  match empty:
    case False{}:
      [D.El{"div", "live", [D.At{"class", "msg assistant live"}], [D.El{"div", "", [D.At{"class", "body"}], D.Md.render(text)}]}]
    case True{}:
      View.phase.k(String.is_empty(M.Phase.label(ph)), M.Phase.label(ph), M.Phase.name(ph))

def View.running(t: M.TurnState) -> Bool:
  match t:
    case M.Running{}:
      True{}
    case _:
      False{}

def View.pin(p: Bool) -> D.Node:
  match p:
    case True{}:
      D.Dom.button("on", "unpin", "", "Unpin", "Pinned")
    case False{}:
      D.Dom.button("", "pin", "", "Pin", "Pin")

def View.settle(o: M.Override, auto: Bool) -> D.Node:
  match o auto:
    case M.ForcedSettled{} _:
      D.Dom.button("on", "unsettle", "", "Bring back to active", "Settled")
    case M.NoOverride{} True{}:
      D.Dom.button("on", "unsettle", "", "Bring back to active", "Settled")
    case _ _:
      D.Dom.button("", "settle", "", "Settle thread", "Settle")

def View.archive(a: Bool) -> D.Node:
  match a:
    case True{}:
      D.Dom.button("on", "unarchive", "", "Bring back from the archive", "Archived")
    case False{}:
      D.Dom.button("", "archive", "", "Archive thread", "Archive")

# snoozed: the button wakes it; else it opens the snooze choices
def View.snooze(snoozed: Bool, picking: Bool) -> List<&2, D.Node>:
  match snoozed picking:
    case True{} _:
      [D.Dom.button("on", "snooze", "off", "Wake it now", "Snoozed")]
    case False{} False{}:
      [D.Dom.button("", "flag", "snooze", "Snooze", "Snooze")]
    case False{} True{}:
      [D.Dom.button("", "snooze", "1h", "Snooze for an hour", "1 hour"), D.Dom.button("", "snooze", "tomorrow", "Snooze until 9:00 tomorrow", "Tomorrow"),
       D.Dom.button("", "snooze", "1w", "Snooze for a week", "1 week"), D.Dom.button("on", "flag", "snooze", "Cancel", "Snooze")]

# Delete asks first: once armed it reads "Delete thread" beside Cancel
def View.del(on: Bool) -> List<&2, D.Node>:
  match on:
    case True{}:
      [D.Dom.button("danger", "delete", "", "Delete this thread for good", "Delete thread"), D.Dom.button("", "delete-no", "", "Keep it", "Cancel")]
    case False{}:
      [D.Dom.button("", "delete", "", "Delete thread", "Delete")]

def View.header(t: M.Thread, +st: M.State, +panel: Bool, snoozed: Bool, picking: Bool, term: Bool, +diff: Bool, del: Bool) -> D.Node:
  match t:
    case M.Thread{+id, +p, title, _, _, turn, _, archived, override, +sa, +ua, pinned, _, +branch, _, _, model, _, _, _, _}:
      D.El{"header", "", [D.At{"class", "thread-head"}, D.At{"style", "--tint:" ++ BG.Badge.css_of(st, p)}], [
        D.Dom.button("back", "select", "", "Threads", "‹"),
        D.El{"span", "", [D.At{"class", "badge"}], [WI.WIcon.svg(BG.Badge.icon(st, p), 16)]},
        D.Dom.span("title", title),
        D.Dom.span("meta", Bool.pick(String, String.is_empty(branch), "", branch)),
        D.El{"div", "", [D.At{"class", "tools"}], List.concat(&2, D.Node, [D.Dom.when(View.running(turn), D.Dom.button("", "interrupt", "", "Stop the running turn", "Stop")),
          [View.pin(pinned), View.settle(override, Nat.is_gt(sa, ua))], View.snooze(snoozed, picking), [View.archive(archived)], View.del(del), [
           D.Dom.button("", "fork", "", "A new thread that goes on from here", "Fork")],
          D.Dom.when(Bool.not(String.is_empty(M.Fork.source(st, id))), D.Dom.button("", "back", "", "Send what this fork did to the thread it came from, with its next message", "Bring back")), [
           D.Dom.button(Bool.pick(String, term, "on", ""), "term-toggle", "@term-size", "Terminal (ctrl+j)", "Terminal"),
           D.Dom.button(Bool.pick(String, Bool.and(panel, diff), "on", ""), "diff", "", "What this thread changed (ctrl+d)", "Diff"),
           D.Dom.button(Bool.pick(String, Bool.and(panel, Bool.not(diff)), "on", ""), "panel", "", "Board viewer", "Board")]])}]}

# the model menu's rows: each model's name, then what its CLI calls it,
# in two columns (the names' as wide as the longest, --namew)
def View.models(ms: List<&2, String>, +cur: String, +info: String, +prov: String) -> List<&2, D.Node>:
  match ms:
    case Nil{}:
      Nil{}
    case +m <> t:
      D.El{"button", "", [D.At{"class", Bool.pick(String, String.eq(m, cur), "row on", "row")}, D.At{"title", "Use " ++ Bool.pick(String, String.is_empty(m), "the default", m)}, D.At{"data-value", m}, D.On{"click", "model"}],
        [D.Dom.span("name", Bool.pick(String, String.is_empty(m), "default", m)), D.Dom.span("label", U.Models.label_of(info, prov, m))]} <> View.models(t, cur, info, prov)

def View.namew(ms: List<&2, String>) -> Nat:
  match ms:
    case Nil{}:
      7n
    case +m <> t:
      Nat.max(String.length(m), View.namew(t))

# reasoning effort chips, the provider's default first
def View.efforts(es: List<&2, String>, +cur: String, +prov: String) -> List<&2, D.Node>:
  match es:
    case Nil{}:
      Nil{}
    case +e <> t:
      D.Dom.button(Bool.pick(String, U.Chip.on(e, cur, prov), "on", ""), "effort", e,
        Bool.pick(String, String.starts_with(e, "@"), "Go on with " ++ U.Chip.name(e) ++ " from the next turn", "Reasoning effort: " ++ U.Chip.name(e)), U.Chip.name(e)) <> View.efforts(t, cur, prov)

def View.effort_row(+es: List<&2, String>, +cur: String, +prov: String) -> List<&2, D.Node>:
  Bool.pick(List<&2, D.Node>, List.is_empty(&2, String, es), Nil{}, [D.El{"div", "", [D.At{"class", "efforts"}], View.efforts(es, cur, prov)}])

# the model menu over the composer, and a shade behind it: a click
# anywhere off the menu lands on the shade and closes it
def View.menu(open: Bool, +ms: List<&2, String>, +cur: String, +info: String, +prov: String, +es: List<&2, String>, +effort: String) -> List<&2, D.Node>:
  match open:
    case True{}:
      [D.El{"div", "", [D.At{"class", "shade"}, D.At{"data-value", "models"}, D.On{"click", "flag"}], Nil{}},
       D.El{"div", "", [D.At{"class", "model-menu"}, D.At{"style", "--namew:" ++ Nat.show(View.namew(ms)) ++ "ch"}],
         D.Dom.cat(View.effort_row(es, effort, prov), [D.El{"div", "", [D.At{"class", "rows"}], View.models(ms, cur, info, prov)}])}]
    case False{}:
      Nil{}

# the skills a `$` being typed may complete to (Tab or Enter takes the first)
def View.skills.go(rs: List<&2, U.SkillRow>) -> List<&2, D.Node>:
  match rs:
    case Nil{}:
      Nil{}
    case U.SkillRow{+n, d} <> t:
      D.El{"button", "", [D.At{"class", "skill"}, D.At{"data-value", n}, D.On{"click", "skill"}], [D.Dom.span("name", "$" ++ n), D.Dom.span("desc", d)]} <> View.skills.go(t)

def View.skills(+rs: List<&2, U.SkillRow>) -> List<&2, D.Node>:
  Bool.pick(List<&2, D.Node>, List.is_empty(&2, U.SkillRow, rs), Nil{}, [D.El{"div", "", [D.At{"class", "skills"}], View.skills.go(rs)}])

# Subagents
# ---------


def View.task(t: M.Task, +st: M.State) -> D.Node:
  match t:
    case M.Task{_, _, +child, _, +s, _, _, +pr, +mo}:
      D.El{"div", child, [D.At{"class", "task " ++ U.Task.word(s)}, D.At{"data-value", child}, D.On{"click", "select"}],
        [D.Dom.span("state-dot", ""), D.Dom.span("who", U.Models.label(pr, mo)), D.Dom.span("title", U.Tasks.title(st, child)), D.Dom.span("state", U.Task.word(s))]}

def View.tasks.go(ts: List<&2, M.Task>, +st: M.State) -> List<&2, D.Node>:
  match ts:
    case Nil{}:
      Nil{}
    case t <> rest:
      View.task(t, st) <> View.tasks.go(rest, st)

# the subagent viewer: the tasks this thread delegated
def View.tasks(+ts: List<&2, M.Task>, +st: M.State) -> List<&2, D.Node>:
  Bool.pick(List<&2, D.Node>, List.is_empty(&2, M.Task, ts), Nil{},
    [D.El{"div", "tasks", [D.At{"class", "tasks"}], D.Dom.span("tasks-head", "Subagents") <> View.tasks.go(ts, st)}])

def View.parent(+st: M.State, +p: String) -> List<&2, D.Node>:
  Bool.pick(List<&2, D.Node>, String.is_empty(p), Nil{},
    [D.El{"button", "", [D.At{"class", "parent"}, D.At{"data-value", p}, D.On{"click", "select"}], [D.Txt{"← delegated by " ++ U.Tasks.title(st, p)}]}])

# Asks: what the agent waits on the user for

def View.ask.opts(ls: List<&2, String>, +id: String) -> List<&2, D.Node>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      D.Dom.button("", "answer", id ++ "|" ++ l, l, l) <> View.ask.opts(t, id)

def View.ask.btns(+k: String, +id: String, +o: String, +draft: String) -> List<&2, D.Node>:
  Bool.pick(List<&2, D.Node>, String.eq(k, "plan"), [D.Dom.button("primary", "answer", id ++ "|implement", "Implement the plan", "Implement"), D.Dom.button("", "answer", id ++ "|dismiss", "Dismiss", "Dismiss")],
    Bool.pick(List<&2, D.Node>, String.eq(k, "input"),
      List.append(&2, D.Node, View.ask.opts(String.split(o, '\n'), id),
        Bool.pick(List<&2, D.Node>, String.is_empty(String.trim(draft)), [D.Dom.button("", "answer", id ++ "|", "Dismiss", "Dismiss")], [D.Dom.button("primary", "answer", id ++ "|" ++ String.trim(draft), "Answer with your draft", "Answer with draft")])),
      [D.Dom.button("primary", "answer", id ++ "|accept", "Allow once", "Allow"), D.Dom.button("", "answer", id ++ "|session", "Allow this tool for the session", "Allow for session"), D.Dom.button("", "answer", id ++ "|decline", "Deny", "Deny")]))

def View.ask(a: M.Ask, +draft: String) -> D.Node:
  match a:
    case M.Ask{+id, _, +k, +tool, +d, +o, _, _}:
      D.El{"div", id, [D.At{"class", "ask " ++ k}], [
        D.Dom.span("ask-head", Bool.pick(String, String.eq(k, "plan"), "Proposed plan", Bool.pick(String, String.eq(k, "input"), "The agent asks", "Allow " ++ tool ++ "?"))),
        Bool.pick(D.Node, String.eq(k, "plan"), D.El{"div", "", [D.At{"class", "body"}], D.Md.render(d)}, D.El{"div", "", [D.At{"class", "ask-detail"}], [D.Txt{d}]}),
        D.El{"div", "", [D.At{"class", "ask-btns"}], View.ask.btns(k, id, o, draft)}]}

def View.asks(as: List<&2, M.Ask>, +draft: String) -> List<&2, D.Node>:
  match as:
    case Nil{}:
      Nil{}
    case a <> t:
      View.ask(a, draft) <> View.asks(t, draft)

def View.qbtns(bs: List<&2, U.QBtn>) -> List<&2, D.Node>:
  match bs:
    case Nil{}:
      Nil{}
    case U.QBtn{+l, a, v} <> t:
      D.Dom.button("", a, v, l, l) <> View.qbtns(t)

def View.qrow(q: M.QItem, +first: Bool, +run: Bool) -> D.Node:
  match q:
    case M.QItem{+msg, text}:
      D.El{"div", "", [D.At{"class", "queued"}], [D.Dom.span("label", U.Qu.tag(run, msg)), D.Dom.span("text", U.Qu.label(msg, text)),
        D.El{"span", "", [D.At{"class", "q-acts"}], View.qbtns(U.Qu.row_buttons(run, first, msg))}]}

def View.qrows(qs: List<&2, M.QItem>, +first: Bool, +run: Bool) -> List<&2, D.Node>:
  match qs:
    case Nil{}:
      Nil{}
    case q <> t:
      View.qrow(q, first, run) <> View.qrows(t, False{}, run)

def View.tdlines(ts: List<&2, TD.Todo>) -> List<&2, D.Node>:
  match ts:
    case Nil{}:
      Nil{}
    case +t <> rest:
      D.Dom.span("todo " ++ TD.Todo.status(t), TD.Todo.line(t)) <> View.tdlines(rest)

# the agent's todo list above the queue (U.Todos.shown)
def View.todos(+ts: List<&2, TD.Todo>) -> D.Node:
  D.El{"div", "", [D.At{"class", "todos"}], Bool.pick(List<&2, D.Node>, List.is_empty(&2, TD.Todo, ts), Nil{}, D.Dom.span("head", TD.Todo.head(ts)) <> View.tdlines(ts))}

# what waits for a later turn (stored on the server), next first, each
# with its buttons (U.Qu.buttons)
def View.queued(qs: List<&2, M.QItem>, +run: Bool) -> D.Node:
  D.El{"div", "", [D.At{"class", "queue"}], View.qrows(qs, True{}, run)}

# Settings
# --------

def View.chips(xs: List<&2, String>, +cur: String, +key: String) -> List<&2, D.Node>:
  match xs:
    case Nil{}:
      Nil{}
    case +v <> t:
      D.Dom.button(Bool.pick(String, String.eq(v, cur), "on", ""), "setting", key ++ "=" ++ v, key, Bool.pick(String, String.is_empty(v), "default", v)) <> View.chips(t, cur, key)

def View.setrow(+label: String, +note: String, ctl: List<&2, D.Node>) -> D.Node:
  D.El{"div", "", [D.At{"class", "set-row"}], [D.El{"div", "", [D.At{"class", "set-text"}], [D.Dom.span("set-label", label), D.Dom.span("set-note", note)]},
    D.El{"div", "", [D.At{"class", "set-ctl"}], ctl}]}

def View.days(+d: String) -> List<&2, D.Node>:
  +n = {Maybe.default(&2, Nat, Nat.read(d), 3n) : Nat}
  [D.Dom.button("", "setting", "settle.days=" ++ Nat.show(Bool.pick(Nat, Nat.is_gt(n, 1n), Nat.sub(n, 1n), 1n)), "Fewer days", "−"),
   D.Dom.span("days", Nat.show(n) ++ Bool.pick(String, Nat.is_eq(n, 1n), " day", " days")),
   D.Dom.button("", "setting", "settle.days=" ++ Nat.show(Bool.pick(Nat, Nat.is_lt(n, 90n), 1n+n, 90n)), "More days", "+")]

def View.fork(+fork: String) -> List<&2, D.Node>:
  Bool.pick(List<&2, D.Node>, String.is_empty(fork), [D.Dom.button("primary", "kicad-install", "", "Install Backplane KiCad", "Install Backplane KiCad")],
    [D.Dom.span("ok", "Backplane KiCad " ++ fork)])

# Voice: the OpenAI key (only ever shown masked), the microphone, the
# dictionary (× takes a term out), as in the native window
def View.devs(ds: List<&2, U.VDev>, +cur: String) -> List<&2, D.Node>:
  match ds:
    case Nil{}:
      Nil{}
    case U.VDev{+name, +label} <> t:
      D.Dom.button(Bool.pick(String, String.eq(name, cur), "on", ""), "setting", "voice.device=" ++ name, name, label) <> View.devs(t, cur)

def View.terms(ts: List<&2, String>) -> List<&2, D.Node>:
  match ts:
    case Nil{}:
      Nil{}
    case +t <> r:
      D.Dom.button("chip", "voice-unterm", t, "Take it out of the dictionary", t ++ " ×") <> View.terms(r)

def View.voice.set(+u: U.Ui, +st: M.State) -> List<&2, D.Node>:
  [View.setrow("OpenAI API key", Bool.pick(String, String.is_empty(U.Ui.scratch(u, "@voice.key")), "For GPT-Live-Transcribe. Kept in this machine's secrets; never shown again.",
      "Saved: " ++ U.Ui.scratch(u, "@voice.key") ++ ". Paste a new one to replace it."),
     [WB.WB.secret("voice-key", "vkey", U.Ui.scratch(u, "@f.vkey"), "sk-…"), D.Dom.button("primary", "voice-key", "", "Keep this key", "Save"),
      D.Dom.button("", "voice-unkey", "", "Forget the key", "Remove")]),
   View.setrow("Microphone", "The mic button in the composer records the hub machine's " ++
      Bool.pick(String, String.is_empty(M.Setting.get(st, "voice.device", "")), "default microphone, " ++ U.Voice.label(u, U.Voice.default(u)), U.Voice.label(u, M.Setting.get(st, "voice.device", ""))) ++ ".",
     D.Dom.button(Bool.pick(String, String.is_empty(M.Setting.get(st, "voice.device", "")), "on", ""), "setting", "voice.device=", "The default microphone", "Default") <>
       View.devs(U.Voice.devices(u), M.Setting.get(st, "voice.device", ""))),
   View.setrow("Dictionary", "Names and terms to expect. Words you clarify after dictating join it. Pebble ring: set its webhook to send the recording.",
     List.append(&2, D.Node, View.terms(U.Voice.dict(u)), [WB.WB.input("voice-term", "vterm", U.Ui.scratch(u, "@f.vterm"), "Add a term", "voice-term"),
       D.Dom.button("", "voice-term", "", "Add it to the dictionary", "Add")]))]

# the same settings as the native window
def View.settings(+u: U.Ui, +st: M.State, +nf: Map<&2, String>, +v: String, +note: String) -> D.Node:
  +prov = M.Setting.get(st, "agent.provider", "claude")
  +ipc = M.Setting.get(st, "kicad.ipc", "on")
  D.El{"main", "settings", [D.At{"class", "settings-view"}], [
    D.El{"header", "", [D.At{"class", "thread-head"}], [D.Dom.span("title", "Settings"), D.Dom.span("meta", ""), D.Dom.button("", "flag", "settings", "Close settings", "Close")]},
    D.El{"div", "", [D.At{"class", "settings"}], List.append(&2, D.Node, [
      View.setrow("Settle after", "Threads idle this long move to Settled. They stay saved.", View.days(M.Setting.get(st, "settle.days", "3"))),
      View.setrow("Follow-ups while a turn runs", "Queue waits for the turn to end; steer sends into it. Ctrl+Enter does the other. Default: Claude steers, Codex and Grok queue.",
        View.chips(["", "queue", "steer"], M.Setting.get(st, "followup", ""), "followup")),
      View.setrow("Provider for new threads", Bool.pick(String, String.is_empty(U.Models.cli(U.Str.get(nf, "models"), prov)), prov ++ " is not installed", U.Models.cli(U.Str.get(nf, "models"), prov)) ++ ". Each thread keeps its own; change it from the composer.", View.chips(["claude", "codex", "grok"], prov, "agent.provider")),
      View.setrow("Model for new threads", Bool.pick(String, String.is_empty(M.Setting.get(st, "agent.model", "")), "default", M.Setting.get(st, "agent.model", "")) ++ ": " ++ U.Models.label_of(U.Str.get(nf, "models"), prov, M.Setting.get(st, "agent.model", "")), View.chips(U.Models.menu(U.Str.get(nf, "models"), prov), M.Setting.get(st, "agent.model", ""), "agent.model")),
      View.setrow("Writing: provider", "Titles threads, names branches and writes commit messages. A small model keeps this cheap.", View.chips(["claude", "codex", "grok"], U.TextGen.provider(st), "text.provider")),
      View.setrow("Writing: model", Bool.pick(String, String.is_empty(U.TextGen.model(st)), "default", U.TextGen.model(st)) ++ ": " ++ U.Models.label_of(U.Str.get(nf, "models"), U.TextGen.provider(st), U.TextGen.model(st)),
        View.chips(U.Models.menu(U.Str.get(nf, "models"), U.TextGen.provider(st)), U.TextGen.model(st), "text.model")),
      View.setrow(U.KiCad.cli.label(nf), U.KiCad.cli.note(nf), View.fork(U.Str.get(nf, "kicad.fork"))),
      View.setrow(U.KiCad.ipc.label(nf), U.KiCad.ipc.note(nf), Bool.pick(List<&2, D.Node>, U.KiCad.ipc.ready(nf), View.chips(["on", "off"], ipc, "kicad.ipc"), Nil{})),
      View.setrow("Theme", "The window and the web page (phones unset follow their own system).", View.chips(["dark", "light"], Bool.pick(String, String.eq(M.Setting.get(st, "ui.theme", ""), "light"), "light", "dark"), "ui.theme")),
      View.setrow("Tailscale: " ++ U.Str.get(nf, "tailnet"), "Listening on " ++ U.Str.get(nf, "listen"), Nil{}),
      View.setrow("Pairing link", U.Pair.note(U.Pair.link(nf)), D.Dom.when(Bool.not(String.is_empty(U.Pair.link(nf))), D.Dom.copy(U.Pair.link(nf)))),
      View.setrow("Update channel", "Stable takes releases; nightly also takes the daily builds.", View.chips(["stable", "nightly"], M.Setting.get(st, "update.channel", "stable"), "update.channel")),
      View.setrow("Backplane " ++ v, U.Update.line(nf, note),
        Bool.pick(List<&2, D.Node>, U.Update.packaged(nf), Nil{}, Bool.pick(List<&2, D.Node>, String.starts_with(note, "update "), [D.Dom.button("primary", "update", "", "Install the update", "Install update")],
          [D.Dom.button("", "update-check", "", "Look for an update now", "Check now")])))], View.voice.set(u, st))}]}

def View.empty(n: Nat) -> D.Node:
  D.El{"main", "empty", [D.At{"class", "empty"}], [D.Txt{Bool.pick(String, Nat.is_eq(n, 0n), "Add a project with + to start.", "Pick a thread, or start one with + next to a project.")}]}

def View.error(e: String) -> List<&2, D.Node>:
  match e:
    case SNil{}:
      Nil{}
    case SCon{h, t}:
      [D.El{"div", "error", [D.At{"class", "toast"}, D.On{"click", "dismiss"}], [D.Txt{SCon{h, t}}]}]

# Project picker
# --------------

def View.prow.cls(+a: String) -> String:
  Bool.pick(String, Bool.or(String.eq(a, "proj-cd"), String.eq(a, "proj-pick")), "prow", Bool.pick(String, String.is_empty(a), "prow off", "prow act"))

# a row: its label, and a project's path at the right
def View.prows(+u: U.Ui, ps: List<&2, U.PItem>, +i: Nat, +sel: Nat) -> List<&2, D.Node>:
  match ps:
    case Nil{}:
      Nil{}
    case U.PItem{+l, +a, +v} <> t:
      D.El{"button", "", [D.At{"class", View.prow.cls(a) ++ Bool.pick(String, Nat.is_eq(i, sel), " sel", "")}, D.At{"title", l}, D.At{"data-value", v}, D.On{"click", a}],
        [D.El{"span", "", [D.At{"class", "pl"}], [D.Txt{l}]}, D.El{"span", "", [D.At{"class", "pd"}], [D.Txt{U.Proj.detail(u, U.PItem{l, a, v})}]}]} <> View.prows(u, t, 1n+i, sel)

# above the filter: "Projects", or the folder browsed and the way back
def View.phead(dir: Bool, +u: U.Ui) -> D.Node:
  match dir:
    case True{}:
      D.El{"div", "", [D.At{"class", "dir"}], [D.Dom.button("pback", "proj-back", "", "Back to projects", "Projects"), D.Txt{U.Proj.dir(u)}]}
    case False{}:
      D.El{"div", "", [D.At{"class", "dir"}], [D.Txt{"Projects"}]}

def View.picker(open: Bool, +u: U.Ui) -> List<&2, D.Node>:
  match open:
    case True{}:
      [D.El{"div", "", [D.At{"class", "modal-back"}, D.On{"click", "proj-close"}], Nil{}},
        D.El{"div", "picker", [D.At{"class", "picker"}], D.Dom.cat([
          View.phead(U.Proj.browsing(u), u),
          D.El{"input", "proj", [D.At{"id", "proj"}, D.At{"placeholder", Bool.pick(String, U.Proj.browsing(u), "Filter, name a new folder, or type a path", "Find a project, or type a path")},
            D.At{"autocomplete", "off"}, D.At{"value", U.Proj.query(u)}, D.On{"input", "proj-q"}, D.At{"data-enter", "proj-enter"}], Nil{}}],
          D.Dom.cat(Bool.pick(List<&2, D.Node>, String.is_empty(U.Ui.info(u, "proj.err")), Nil{}, [D.El{"div", "", [D.At{"class", "perr"}], [D.Txt{U.Ui.info(u, "proj.err")}]}]),
            [D.El{"div", "", [D.At{"class", "prows"}], View.prows(u, U.Proj.items(u), 0n, U.Proj.index(u))}]))}]
    case False{}:
      Nil{}

# Attachments: a message's attachment lines drawn as chips
def View.chip(+path: String) -> D.Node:
  D.El{"span", "", [D.At{"class", Bool.pick(String, AT.Att.image(path), "chip image", "chip")}, D.At{"title", path}], [D.Txt{AT.Att.label(path)}]}

def View.chips.go(ps: List<&2, String>) -> List<&2, D.Node>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      View.chip(p) <> View.chips.go(t)

def View.chips.of(ps: List<&2, String>) -> List<&2, D.Node>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> +t:
      [D.El{"div", "", [D.At{"class", "chips"}], View.chips.go(p <> t)}]

# a user message: what was written, then its attachments
def View.user_body(+text: String) -> List<&2, D.Node>:
  D.Dom.cat(Bool.pick(List<&2, D.Node>, String.is_empty(AT.Att.body(text)), Nil{}, [D.El{"div", "", [D.At{"class", "body plain"}], D.Dom.linked(AT.Att.body(text))}]),
    View.chips.of(AT.Att.paths(text)))

# the images a reply names; a click opens one in the lightbox (data-lightbox,
# app.bend's lb_*), a middle click in a new tab
def View.images(ps: List<&2, String>) -> List<&2, D.Node>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      D.El{"a", "", [D.At{"class", "shot"}, D.At{"href", IM.Img.url(p)}, D.At{"target", "_blank"}, D.At{"title", p}, D.At{"data-lightbox", IM.Img.url(p)}],
        [D.El{"img", "", [D.At{"src", IM.Img.url(p)}, D.At{"alt", p}, D.At{"loading", "lazy"}], Nil{}}]} <> View.images(t)

def View.entry.own(e: M.Entry) -> D.Node:
  match e:
    case M.Msg{id, _, M.User{}, +text, _}:
      D.El{"div", id, [D.At{"class", "msg user"}], D.Dom.cat(View.user_body(text), [D.Dom.copy(AT.Att.body(text))])}
    case M.Msg{id, _, _, +text, _}:
      D.El{"div", id, [D.At{"class", "msg assistant"}], D.Dom.cat([D.El{"div", "", [D.At{"class", "body"}], D.Md.render(text)}], D.Dom.cat(View.images(IM.Img.paths(text)), [D.Dom.copy(text)]))}
    case M.Act{id, _, tone, kind, summary, _}:
      D.El{"div", id, [D.At{"class", "act " ++ tone}], [D.Dom.span("kind", kind), D.Dom.span("summary", summary)]}

# an entry of this thread (headed by the thread that sent it) or a message
# this thread sent to another (a link)
def View.entry.k(mine: Bool, e: M.Entry, +st: M.State) -> List<&2, D.Node>:
  match mine e:
    case True{} M.Msg{+id, t, r, x, at}:
      List.append(&2, D.Node, View.from.k(String.is_empty(M.Link.from(id)), M.Link.from(id), st), [View.entry.own(M.Msg{id, t, r, x, at})])
    case True{} _:
      [View.entry.own(e)]
    case False{} M.Msg{_, +t, _, x, _}:
      [View.link("out", "→ " ++ U.Tasks.title(st, t) ++ ": " ++ Maybe.default(&2, String, List.head(&2, String, String.split(x, '\n')), ""), t)]
    case False{} _:
      Nil{}

def View.entry(+e: M.Entry, +st: M.State, +sel: String) -> List<&2, D.Node>:
  View.entry.k(String.eq(View.entry_thread(e), sel), e, st)

# a run of tool calls, or a turn's work, folded into one row (FO.Fold
# decides the runs, their labels and which are open); a click opens or
# shuts it
def View.fold.row(+id: String, +label: String, +open: Bool) -> D.Node:
  WI.WIcon.button("fold", "fold", FO.Fold.ask(open, id), Bool.pick(String, open, "Hide ", "Show ") ++ Bool.pick(String, String.starts_with(id, "work:"), "what the agent did", "these tool calls"),
    Bool.pick(String, open, "chevron-down", "chevron-right"), 14, label)

def View.fold.shown(open: Bool, ns: List<&2, D.Node>) -> List<&2, D.Node>:
  match open:
    case True{}:
      ns
    case False{}:
      Nil{}

# an entry's nodes as its role says
def View.role(r: FO.Role, ns: List<&2, D.Node>) -> List<&2, D.Node>:
  match r:
    case FO.RShow{}:
      ns
    case FO.RHead{+id, +label, +open}:
      View.fold.row(id, label, open) <> View.fold.shown(open, ns)
    case FO.RIn{open}:
      View.fold.shown(open, ns)
    case FO.RWork{+id, +label, open, inner}:
      match open:
        case True{}:
          View.fold.row(id, label, True{}) <> View.role(inner, ns)
        case False{}:
          [View.fold.row(id, label, False{})]

def View.entries.r(es: List<&2, M.Entry>, rs: List<&2, FO.Role>, +st: M.State, +sel: String) -> List<&2, D.Node>:
  match es rs:
    case Nil{} _:
      Nil{}
    case e <> t r <> rt:
      List.append(&2, D.Node, View.role(r, View.entry(e, st, sel)), View.entries.r(t, rt, st, sel))
    case e <> t Nil{}:
      List.append(&2, D.Node, View.entry(e, st, sel), View.entries.r(t, Nil{}, st, sel))

# the newest page of a thread's entries (core's Page), with a button for
# the earlier ones when some are left out
def View.earlier(+hidden: Nat, +id: String) -> List<&2, D.Node>:
  Bool.pick(List<&2, D.Node>, Nat.is_eq(hidden, 0n), Nil{},
    [D.Dom.div("earlier", [D.Dom.button("earlier-btn", "earlier", id, "Show earlier messages", "Show earlier")])])

# a thread's entries, its runs of tool calls folded (the last stays open
# while its turn runs)
def View.entries(+es: List<&2, M.Entry>, +st: M.State, +sel: String, +info: Map<&2, String>, +running: Bool) -> List<&2, D.Node>:
  View.entries.r(es, FO.Fold.roles(es, info, running), st, sel)

def View.paged.w(w: U.Win, +st: M.State, +sel: String, +info: Map<&2, String>, +running: Bool) -> List<&2, D.Node>:
  match w:
    case U.Win{+h, es}:
      List.append(&2, D.Node, View.earlier(h, sel), View.entries(es, st, sel, info, running))

def View.paged(+drafts: Map<&2, String>, +es: List<&2, M.Entry>, +st: M.State, +sel: String, +info: Map<&2, String>, +running: Bool) -> List<&2, D.Node>:
  View.paged.w(U.Page.newest.from(es, sel, U.Page.since(st, sel), U.Page.count(Maybe.default(&2, Nat, Nat.read(U.Str.get(drafts, "@more." ++ sel)), 0n))), st, sel, info, running)

def View.sending(ps: List<&2, String>) -> List<&2, D.Node>:
  match ps:
    case Nil{}:
      Nil{}
    case p <> t:
      D.El{"div", "", [D.At{"class", "msg user sending"}], D.Dom.cat(View.user_body(p), [D.Dom.span("note", "sending…")])} <> View.sending(t)

# Terminal
# --------

def View.nib(+n: U32) -> Char:
  Chr{Bool.pick(U32, U32.is_lt(n, 10), (n + 48 : U32), (n + 87 : U32))}

def View.hex.go(k: Nat, +x: U32, acc: String) -> String:
  match k:
    case 0n:
      acc
    case 1n+j:
      View.hex.go(j, U32.shrn(x, 4n), SCon{View.nib(U32.and(x, 15)), acc})

# 0xRRGGBB as "#rrggbb"
def View.hex(+x: U32) -> String:
  "#" ++ View.hex.go(6n, x, "")

def View.run.style(+fg: U32, +bg: U32, bold: Bool, ul: Bool) -> String:
  String.concat([Bool.pick(String, U32.is_eq(fg, VT.Vt.fg()), "", "color:" ++ View.hex(fg) ++ ";"),
    Bool.pick(String, U32.is_eq(bg, VT.Vt.bg()), "", "background:" ++ View.hex(bg) ++ ";"),
    Bool.pick(String, bold, "font-weight:700;", ""), Bool.pick(String, ul, "text-decoration:underline;", "")])

def View.runs(rs: List<&2, VT.VRun>) -> List<&2, D.Node>:
  match rs:
    case Nil{}:
      Nil{}
    case VT.VRun{t, +fg, +bg, bo, ul} <> rest:
      D.El{"span", "", [D.At{"style", View.run.style(fg, bg, bo, ul)}], [D.Txt{t}]} <> View.runs(rest)

def View.tlines(ls: List<&2, VT.VLine>) -> List<&2, D.Node>:
  match ls:
    case Nil{}:
      Nil{}
    case VT.VLine{rs} <> t:
      D.El{"div", "", [D.At{"class", "tl"}], View.runs(rs)} <> View.tlines(t)

def View.cursor(c: VT.VCur) -> List<&2, D.Node>:
  match c:
    case VT.VCur{+x, +y, True{}}:
      [D.El{"div", "cur", [D.At{"class", "cur"}, D.At{"style", "left:" ++ U32.show(x) ++ "ch;top:" ++ U32.show((y * 17 : U32)) ++ "px"}], Nil{}}]
    case VT.VCur{_, _, False{}}:
      Nil{}

# the thread's shell: its screen, and over it a transparent field that
# takes keys (and a phone's keyboard)
def View.term(+v: VT.Vt) -> D.Node:
  D.El{"section", "term-pane", [D.At{"class", "term-pane"}], [
    D.El{"div", "", [D.At{"class", "term-head"}], [D.Dom.span("label", "Terminal" ++ Bool.pick(String, String.is_empty(VT.Vt.title(v)), "", " · " ++ VT.Vt.title(v))),
      WI.WIcon.button("icon", "term-toggle", "", "Close (ctrl+j)", "x", 16, "")]},
    D.El{"div", "", [D.At{"class", "screen"}, D.At{"style", "background:" ++ View.hex(VT.Vt.bg()) ++ ";color:" ++ View.hex(VT.Vt.fg())}],
      D.Dom.cat(View.tlines(VT.Vt.lines(v, 0n)), D.Dom.cat(View.cursor(VT.Vt.cursor(v)),
        [D.El{"textarea", "term", [D.At{"id", "term"}, D.At{"class", "term-in"}, D.At{"data-keys", "term-key"}, D.At{"data-text", "term-paste"},
          D.At{"autocapitalize", "off"}, D.At{"autocomplete", "off"}, D.At{"spellcheck", "false"}, D.At{"aria-label", "Terminal input"}], Nil{}}]))}]}

# Diff
# ----

def View.dl.cls(+k: U32) -> String:
  Bool.pick(String, U32.is_eq(k, 1), "dl add", Bool.pick(String, U32.is_eq(k, 2), "dl del", Bool.pick(String, U32.is_eq(k, 3), "dl meta", "dl")))

def View.dl.no(+n: Nat) -> String:
  Bool.pick(String, Nat.is_eq(n, 0n), "", Nat.show(n))

def View.dlines(ls: List<&2, DF.DLine>) -> List<&2, D.Node>:
  match ls:
    case Nil{}:
      Nil{}
    case DF.DLine{+k, t, +o, +n} <> rest:
      D.El{"div", "", [D.At{"class", View.dl.cls(k)}], [D.Dom.span("no", View.dl.no(o)), D.Dom.span("no", View.dl.no(n)),
        D.Dom.span("sign", Bool.pick(String, U32.is_eq(k, 1), "+", Bool.pick(String, U32.is_eq(k, 2), "-", " "))), D.Dom.span("code", t)]} <> View.dlines(rest)

def View.dhunks(hs: List<&2, DF.DHunk>) -> List<&2, D.Node>:
  match hs:
    case Nil{}:
      Nil{}
    case DF.DHunk{+hd, ls} <> t:
      D.Dom.cat(Bool.pick(List<&2, D.Node>, String.is_empty(hd), Nil{}, [D.Dom.span("dhunk", hd)]), D.Dom.cat(View.dlines(ls), View.dhunks(t)))

def View.dfiles(fs: List<&2, DF.DFile>) -> List<&2, D.Node>:
  match fs:
    case Nil{}:
      Nil{}
    case DF.DFile{_, +nw, st, hs} <> t:
      D.El{"div", nw, [D.At{"class", "dfile"}], D.El{"div", "", [D.At{"class", "dhead"}], [D.Dom.span("name", nw), D.Dom.span("status", st)]} <> View.dhunks(hs)} <> View.dfiles(t)

# what this thread changed, with the git actions (as the native Lay.diff)
def View.diff(+text: String) -> D.Node:
  +fs = DF.Diff.parse(text)
  D.El{"aside", "diff", [D.At{"class", "viewer diff"}, D.At{"id", "viewer"}], [
    D.El{"div", "", [D.At{"class", "diff-head"}], [
      D.Dom.span("summary", Bool.pick(String, List.is_empty(&2, DF.DFile, fs), "No changes since this thread began.", DF.Diff.summary(fs))),
      D.El{"div", "", [D.At{"class", "diff-btns"}], [
        D.Dom.button("", "revert", "0", "Put the files back as they were when this thread began", "Revert thread"),
        D.Dom.button("", "git", "commit_push_pr", "Commit, push and open a pull request", "Open PR"),
        D.Dom.button("primary", "git", "commit_push", "Commit and push", "Commit & push"),
        WI.WIcon.button("icon", "panel", "", "Close", "x", 16, "")]}]},
    D.El{"div", "", [D.At{"class", "diff-body"}], View.dfiles(fs)}]}

def View.pending(ps: List<&2, String>) -> List<&2, D.Node>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      D.El{"button", "", [D.At{"class", Bool.pick(String, AT.Att.image(p), "chip image", "chip")}, D.At{"title", "Remove " ++ p}, D.At{"data-value", p}, D.On{"click", "detach"}],
        [D.Txt{AT.Att.label(p) ++ " ×"}]} <> View.pending(t)

# what the next message attaches (and what is still uploading)
def View.attaching(+ps: List<&2, String>, +up: String) -> List<&2, D.Node>:
  Bool.pick(List<&2, D.Node>, Bool.and(List.is_empty(&2, String, ps), String.is_empty(up)), Nil{},
    [D.El{"div", "", [D.At{"class", "chips"}], D.Dom.cat(View.pending(ps),
      Bool.pick(List<&2, D.Node>, String.is_empty(up), Nil{}, [D.Dom.span("chip up", up ++ " …")]))}])

# Voice: dictation into the composer (client.bend's Voice). The mic is red
# while it records; above the composer, what is being heard, a note when
# nothing comes in or something failed, and the words to clarify, one at
# a time.
def View.mic(+state: String) -> D.Node:
  WI.WIcon.button(Bool.pick(String, String.is_empty(state), "mic", "mic " ++ state), "voice", "",
    Bool.pick(String, String.is_empty(state), "Dictate with the hub machine's microphone", "Stop dictating"), "mic", 16, "")

def View.vhint(+h: String, +dev: String) -> String:
  +d = Bool.pick(String, String.is_empty(dev), "the microphone", dev)
  Bool.pick(String, String.eq(h, "no-audio"), "Nothing received from " ++ d ++ " yet. Is it plugged in? Pick another in Settings, Voice.",
    Bool.pick(String, String.eq(h, "silent"), "Only silence from " ++ d ++ " so far. Is it muted, or the wrong one?", h))

def View.vstrip(on: Bool, +u: U.Ui) -> List<&2, D.Node>:
  match on:
    case True{}:
      +state = U.Ui.scratch(u, "@voice")
      [D.El{"div", "", [D.At{"class", "voice-strip"}], [D.Dom.span("rec", ""),
        D.Dom.span("voice-head", Bool.pick(String, String.eq(state, "starting"), "Starting the microphone…", Bool.pick(String, String.eq(state, "stopping"), "Finishing…",
          "Listening" ++ Bool.pick(String, String.is_empty(U.Ui.scratch(u, "@voice.dev")), "", " · " ++ U.Ui.scratch(u, "@voice.dev"))))),
        D.El{"span", "", [D.At{"class", "meter"}], [D.El{"span", "", [D.At{"style", "width:" ++ Nat.show(Maybe.default(&2, Nat, Nat.read(U.Ui.scratch(u, "@voice.lv")), 0n)) ++ "%"}], Nil{}}]},
        D.Dom.span("voice-part", U.Ui.scratch(u, "@voice.part")),
        D.Dom.button("stop", "voice", "", "Stop dictating", "Stop")]}]
    case False{}:
      Nil{}

def View.vnote(on: Bool, +u: U.Ui) -> List<&2, D.Node>:
  match on:
    case True{}:
      [D.El{"div", "", [D.At{"class", Bool.pick(String, String.is_empty(U.Ui.scratch(u, "@voice.err")), "voice-note warn", "voice-note bad")}], [
        D.Dom.span("", Bool.pick(String, String.is_empty(U.Ui.scratch(u, "@voice.err")), View.vhint(U.Ui.scratch(u, "@voice.hint"), U.Ui.scratch(u, "@voice.dev")),
          "Dictation: " ++ U.Ui.scratch(u, "@voice.err"))),
        WI.WIcon.button("", "voice-err", "", "Close", "x", 14, "")]}]
    case False{}:
      Nil{}

def View.vask.k(x: VC.Unsure, +n: Nat) -> List<&2, D.Node>:
  match x:
    case VC.Unsure{+w, +g}:
      [D.El{"div", "", [D.At{"class", "voice-ask"}], List.append(&2, D.Node,
        [D.Dom.span("", "Heard \u{201c}" ++ w ++ "\u{201d}" ++ Bool.pick(String, Nat.is_gt(n, 1n), " (1 of " ++ Nat.show(n) ++ ")", ""))],
        List.append(&2, D.Node, Bool.pick(List<&2, D.Node>, String.is_empty(g), Nil{}, [D.Dom.button("primary", "voice-use", "0", "Use the guess", "Use " ++ g)]),
          [D.Dom.button("", "voice-fix", "0", "Type the right spelling", "Fix…"), D.Dom.button("", "voice-add", "0", "Add it to the dictionary as heard", "Add to dictionary"),
           D.Dom.button("", "voice-skip", "0", "Leave it", "Skip")]))}]

def View.vask.go(fixing: Bool, +u: U.Ui, +us: List<&2, VC.Unsure>) -> List<&2, D.Node>:
  match fixing:
    case True{}:
      [D.El{"div", "", [D.At{"class", "voice-ask"}], [WB.WB.input("voice-fix", "vfix", U.Ui.scratch(u, "@f.vfix"), "The right spelling (it joins the dictionary)", "voice-fixed"),
        D.Dom.button("primary", "voice-fixed", "", "Replace the word and add it to the dictionary", "Save"), D.Dom.button("", "form-close", "@voice.fix", "Cancel", "Cancel")]}]
    case False{}:
      View.vask.k(Maybe.default(&2, VC.Unsure, List.head(&2, VC.Unsure, us), VC.Unsure{"", ""}), List.length(&2, VC.Unsure, us))

def View.vask(on: Bool, +u: U.Ui) -> List<&2, D.Node>:
  match on:
    case True{}:
      View.vask.go(Bool.not(String.is_empty(U.Ui.scratch(u, "@voice.fix"))), u, U.Voice.unsure(u))
    case False{}:
      Nil{}

# what sits over the composer for dictation, and the mic's state
def View.voice(+u: U.Ui, +sel: String) -> List<&2, D.Node>:
  +here = Bool.or(String.eq(U.Ui.scratch(u, "@voice.th"), sel), String.is_empty(U.Ui.scratch(u, "@voice.th")))
  D.Dom.cat(View.vnote(Bool.and(here, Bool.or(Bool.not(String.is_empty(U.Ui.scratch(u, "@voice.err"))), Bool.and(U.Voice.on(u), Bool.not(String.is_empty(U.Ui.scratch(u, "@voice.hint")))))), u),
    D.Dom.cat(View.vstrip(Bool.and(here, U.Voice.on(u)), u),
      View.vask(Bool.and(String.eq(U.Ui.scratch(u, "@voice.uth"), sel), Bool.not(List.is_empty(&2, VC.Unsure, U.Voice.unsure(u)))), u)))

# a side question (/btw) and its answer, over the composer until closed
def View.btw(+u: U.Ui) -> List<&2, D.Node>:
  Bool.pick(List<&2, D.Node>, String.is_empty(U.Btw.question(u)), Nil{},
    [D.El{"div", "", [D.At{"class", "btw"}], [
      D.El{"div", "", [D.At{"class", "btw-head"}], [D.Dom.span("btw-q", "btw · " ++ U.Btw.question(u)),
        WI.WIcon.button("btw-close", "btw-close", "", "Close", "x", 14, "")]},
      D.Dom.div("btw-a", [D.Txt{U.Btw.text(U.Btw.reply.of(u))}])]}])

def View.mic.of(+u: U.Ui, +sel: String) -> String:
  Bool.pick(String, Bool.or(String.eq(U.Ui.scratch(u, "@voice.th"), sel), String.is_empty(U.Ui.scratch(u, "@voice.th"))), U.Ui.scratch(u, "@voice"), "")

# the send button, or Stop while a turn runs with nothing typed
def View.send(+act: String, +send: String) -> D.Node:
  Bool.pick(D.Node, String.eq(act, "interrupt"), D.Dom.button("primary stop", act, "", "Stop the running turn", send),
    D.Dom.button("primary", act, "", "Enter; ctrl+Enter to " ++ Bool.pick(String, String.eq(send, "Queue"), "steer", "queue") ++ " instead", send))

def View.composer(+draft: String, +send: String, +act: String, +label: String, +ctx: String, +picking: Bool, +ms: List<&2, String>, +model: String, +info: String, +prov: String, +es: List<&2, String>, +effort: String, +rs: List<&2, U.SkillRow>,
    +atts: List<&2, String>, +up: String, vo: List<&2, D.Node>, +mic: String) -> D.Node:
  D.El{"div", "", [D.At{"class", "composer"}], D.Dom.cat(
    View.menu(picking, ms, model, info, prov, es, effort), D.Dom.cat(View.skills(rs), D.Dom.cat(vo, D.Dom.cat(View.attaching(atts, up), [
    D.El{"textarea", "composer", [D.At{"id", "composer"}, D.At{"rows", "3"}, D.At{"placeholder", "Ask anything, @tag files, $skill, /btw a side question"}, D.At{"value", draft}, D.On{"input", "draft"},
      D.At{"data-enter", Bool.pick(String, List.is_empty(&2, U.SkillRow, rs), "send", "skill")}, D.At{"data-enter-alt", "send-alt"}, D.At{"data-tab", Bool.pick(String, List.is_empty(&2, U.SkillRow, rs), "", "skill")}, D.At{"data-paste", "attach"}], Nil{}},
    D.El{"div", "", [D.At{"class", "composer-foot"}], [
      WI.WIcon.after("model-chip", "flag", "models", "Choose the model and effort", U.Effort.label(label, effort) ++ ctx, "chevron-down", 14),
      D.El{"label", "", [D.At{"class", "attach"}, D.At{"title", "Attach files or images (or paste an image)"}], [WI.WIcon.svg("paperclip", 16),
        D.El{"input", "attach-file", [D.At{"type", "file"}, D.At{"multiple", ""}, D.At{"data-attach", "attach"}], Nil{}}]},
      D.El{"span", "", [D.At{"class", "foot-end"}], [View.mic(mic),
        View.send(act, send)]}]}]))))}

# the thread's header, or the one given (a bot's)
def View.top(hd: List<&2, D.Node>, t: M.Thread, +st: M.State, +panel: Bool, snoozed: Bool, picking: Bool, term: Bool, +diff: Bool, del: Bool) -> List<&2, D.Node>:
  match hd:
    case Nil{}:
      [View.header(t, st, panel, snoozed, picking, term, diff, del)]
    case h <> r:
      h <> r

def View.thread.p(u: U.Ui, t: M.Thread, pend: List<&2, String>, +atts: List<&2, String>, +up: String, +term: Bool, hd: List<&2, D.Node>, vo: List<&2, D.Node>, +mic: String) -> D.Node:
  match u t:
    case U.Ui{+st, +sel, +drafts, +live, +op, _, +now, _, panel, _, _, _, _, _, +nf, _, +tr} M.Thread{+id, p, ti, c, a, +turn, pe, ar, o, sa, ua, pi, en, br, wt, +pr, +mo, rm, im, se, de}:
      +stop = U.Follow.stop(View.running(turn), U.Str.get(drafts, sel), atts)
      D.El{"main", "thread", [D.At{"class", Bool.pick(String, term, "thread-view with-term", "thread-view") ++ Bool.pick(String, U.Flag.get(op, "drop"), " dropping", "")},
        D.At{"data-drop", "attach"}, D.At{"data-drop-hover", "drop-hover"}], D.Dom.cat(D.Dom.cat(
        View.top(hd, M.Thread{id, p, ti, c, a, turn, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de}, st, panel, M.Snooze.on(now, U.Side.until(st, id)), U.Flag.get(op, "snooze"), term, String.eq(U.Str.get(nf, "view.kind:" ++ id), "diff"), String.eq(U.Str.get(drafts, "@del"), id)), [
        D.El{"div", "timeline", [D.At{"class", "timeline"}, D.At{"id", "timeline"}],
          D.Dom.cat(View.parent(st, U.Tasks.parent(st, id)), D.Dom.cat(View.tasks(U.Tasks.of(st, id), st),
          D.Dom.cat(View.paged(drafts, U.Ui.entries(st), st, id, nf, View.running(turn)), D.Dom.cat(View.sending(pend),
            View.live.k(String.is_empty(U.Str.get(live, id)), U.Side.phase(st, U.Ui.thread(st, id)), U.Str.get(live, id))))))},
        D.El{"div", "asks", [D.At{"class", "asks"}], View.asks(U.Asks.open(st, id), U.Str.get(drafts, sel))},
        View.todos(U.Todos.shown(st, id, View.running(turn))),
        View.queued(M.Queue.items(st, id), View.running(turn)),
        View.composer(U.Str.get(drafts, sel), U.Follow.button(st, sel, View.running(turn), stop, U.Str.get(drafts, sel)), U.Follow.act(stop), U.Models.label(pr, mo), U.Usage.tail(st, sel), U.Flag.get(op, "models"), U.Models.menu(U.Str.get(nf, "models"), pr), mo, U.Str.get(nf, "models"), pr,
          U.Chip.all(U.Str.get(nf, "models"), pr, mo), U.Effort.of(st, sel), U.Skills.of(sel, drafts, nf), atts, up, vo, mic)]),
        D.Dom.when(term, View.term(U.Term.get(tr, id))))}

def View.thread.h(+u: U.Ui, t: M.Thread, hd: List<&2, D.Node>) -> D.Node:
  View.thread.p(u, t, U.Ui.pending(u, U.Ui.sel(u)), U.Ui.atts(u, U.Ui.sel(u)), U.Ui.uploading(u, U.Ui.sel(u)), U.Ui.flag(u, "term"), hd, D.Dom.cat(View.btw(u), View.voice(u, U.Ui.sel(u))), View.mic.of(u, U.Ui.sel(u)))

def View.thread(+u: U.Ui, t: M.Thread) -> D.Node:
  View.thread.h(u, t, Nil{})

# a bot: its header and tabs, then its thread (Chat) or another tab
def View.bot.k(chat: Bool, +u: U.Ui, +b: BT.Bot, +tab: String) -> D.Node:
  match chat:
    case True{}:
      View.thread.h(u, U.Ui.thread(U.Ui.state(u), BT.Bot.thread(b)), [WB.WB.head(u, b), WB.WB.tabs(tab)])
    case False{}:
      D.El{"main", "bot", [D.At{"class", "thread-view bot-view"}], [WB.WB.head(u, b), WB.WB.tabs(tab), WB.WB.body(u, b, tab)]}

def View.bot(+u: U.Ui, +b: BT.Bot) -> D.Node:
  View.bot.k(String.eq(BI.BU.tab(u), "chat"), u, b, BI.BU.tab(u))

def View.main.s(settings: Bool, none: Bool, u: U.Ui, +sel: String, +n: Nat) -> D.Node:
  match settings none u:
    case True{} _ U.Ui{+st, s2, d, l, o, on, now, ad, pa, +v, r, w, e, +note, +nf, ob, tr}:
      View.settings(U.Ui{st, s2, d, l, o, on, now, ad, pa, v, r, w, e, note, nf, ob, tr}, st, nf, v, note)
    case False{} True{} _:
      View.empty(n)
    case False{} False{} U.Ui{+st, s2, d, l, o, on, now, ad, pa, v, r, w, e, note, nf, ob, tr}:
      View.thread(U.Ui{st, s2, d, l, o, on, now, ad, pa, v, r, w, e, note, nf, ob, tr}, U.Ui.thread(st, sel))

def View.main.k(none: Bool, u: U.Ui, +sel: String, +n: Nat) -> D.Node:
  match none u:
    case _ U.Ui{+st, _, _, _, +o, _, _, _, _, +v, _, _, _, +note, +nf, +ob, +tr}:
      View.main.s(U.Flag.get(o, "settings"), none, u, sel, n)

# settings, else a bot, a room or a bot elsewhere, else the thread
def View.main.b(settings: Bool, bv: BI.View, +u: U.Ui, +sel: String, +n: Nat) -> D.Node:
  match settings bv:
    case False{} BI.VBot{b}:
      View.bot(u, b)
    case False{} BI.VRoom{r}:
      WB.WB.room(u, r)
    case False{} BI.VRemote{id}:
      WB.WB.remote(u, id)
    case _ _:
      View.main.k(String.is_empty(sel), u, sel, n)

# the thread's own browser page (a bot's is the bot's), as a bot's
# Browser tab shows it
def View.browser(+u: U.Ui) -> D.Node:
  D.El{"aside", "viewer", [D.At{"class", "viewer"}, D.At{"id", "viewer"}], [
    WB.WB.browser.k(String.is_empty(U.Ui.info(u, "shot." ++ U.Ui.page(u))), U.Ui.info(u, "shot." ++ U.Ui.page(u)), U.Ui.page(u), "This thread")]}

# the side pane of the selected thread: its diff, its browser, or the
# board canvas
def View.aside.k(i: Nat, +u: U.Ui) -> D.Node:
  match i:
    case 0n:
      View.diff(U.Ui.view_get(u, "diff"))
    case 1n:
      View.browser(u)
    case _:
      D.El{"aside", "viewer", [D.At{"class", "viewer"}, D.At{"id", "viewer"}], [D.El{"canvas", "board", [D.At{"id", "board"}], Nil{}}]}

def View.aside(+kind: String, +u: U.Ui) -> D.Node:
  View.aside.k(Bool.pick(Nat, String.eq(kind, "diff"), 0n, Bool.pick(Nat, String.eq(kind, "browser"), 1n, 2n)), u)

def View.aside.if(open: Bool, +kind: String, +u: U.Ui) -> List<&2, D.Node>:
  match open:
    case True{}:
      [View.aside(kind, u)]
    case False{}:
      Nil{}

# the whole page
def View.page.b(+bv: BI.View, u: U.Ui) -> D.Node:
  match u:
    case U.Ui{+st, +sel, +d, +l, +o, +on, +now, +ad, +pa, +v, +r, +w, +e, +note, +nf, +ob, +tr}:
      D.El{"div", "app", [D.At{"class", Bool.pick(String, pa, "app panel", "app") ++ Bool.pick(String, Bool.or(Bool.or(Bool.not(String.is_empty(sel)), U.Flag.get(o, "settings")), WB.WB.shown(bv)), " picked", "")
        ++ Bool.pick(String, String.eq(M.Setting.get(st, "ui.theme", ""), "light"), " light", "")}],
        D.Dom.cat([View.sidebar(U.Ui{st, sel, d, l, o, on, now, ad, pa, v, r, w, e, note, nf, ob, tr}),
          View.main.b(U.Flag.get(o, "settings"), bv, U.Ui{st, sel, d, l, o, on, now, ad, pa, v, r, w, e, note, nf, ob, tr}, sel, List.length(&2, M.Project, U.Ui.projects(st)))],
          D.Dom.cat(View.aside.if(pa, U.Str.get(nf, "view.kind:" ++ sel), U.Ui{st, sel, d, l, o, on, now, ad, pa, v, r, w, e, note, nf, ob, tr}),
            D.Dom.cat(View.picker(U.Flag.get(o, "proj"), U.Ui{st, sel, d, l, o, on, now, ad, pa, v, r, w, e, note, nf, ob, tr}), View.error(e))))}

def View.page(+u: U.Ui) -> D.Node:
  View.page.b(BI.BU.view(u), u)
