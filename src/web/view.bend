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
  D.El{"div", id, [D.At{"class", Bool.pick(String, String.eq(id, sel), "thread on", "thread")}, D.At{"data-value", id}, D.On{"click", "select"}],
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

def View.project(r: U.SRow, +open: Map<&2, Bool>, +st: M.State, +sel: String, +now: Nat) -> D.Node:
  match r:
    case U.SRow{_, M.Project{+id, title, root, _, _}, M.Shelves{pinned, active, settled, hidden, snoozed}}:
      D.El{"section", id, [D.At{"class", "project"}],
        List.concat(&2, D.Node, [[D.El{"div", "", [D.At{"class", "project-head"}, D.At{"title", root}],
            [D.Dom.span("name", title), WI.WIcon.button("icon", "new-thread", id, "New thread", "plus", 16, "")]}],
          View.rows_in(pinned, st, sel, now, True{}, False{}),
          View.rows_in(active, st, sel, now, True{}, False{}),
          View.snoozed(snoozed, st, sel, now),
          View.shelf(U.Flag.get(open, id), id, "Settled", settled, st, sel, now),
          View.shelf(U.Flag.get(open, "arch:" ++ id), "arch:" ++ id, "Archived", M.Archive.of(hidden), st, sel, now)])}

def View.projects(rs: List<&2, U.SRow>, +open: Map<&2, Bool>, +st: M.State, +sel: String, +now: Nat) -> List<&2, D.Node>:
  match rs:
    case Nil{}:
      Nil{}
    case r <> t:
      View.project(r, open, st, sel, now) <> View.projects(t, open, st, sel, now)

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

def View.sidebar.k(+ms: List<&2, U.MRow>, +st: M.State, +sel: String, +open: Map<&2, Bool>, on: Bool, +now: Nat, adding: Bool, v: String) -> D.Node:
  D.El{"aside", "sidebar", [D.At{"class", "sidebar"}],
        D.Dom.cat([D.El{"div", "", [D.At{"class", "brand"}], [
            D.Dom.span(Bool.pick(String, on, "conn on", "conn"), ""),
            D.Dom.span("name", "Backplane"), D.Dom.span("ver", v),
            WI.WIcon.button("icon", "proj-open", "", "Add project", "plus", 16, "")]}],
          D.Dom.cat(View.machines(Nat.is_gt(List.length(&2, U.MRow, ms), 1n), ms), D.Dom.cat(View.add(adding),
            D.Dom.cat(View.projects(U.Side.rows(st, now), open, st, sel, now),
            [WI.WIcon.button("settings-link", "flag", "settings", "Settings", "settings", 16, "Settings")]))))}

def View.sidebar(u: U.Ui) -> D.Node:
  match u:
    case U.Ui{+st, +sel, d, l, +open, +on, +now, +adding, pa, +v, r, w, e, note, nf, ob, tr}:
      View.sidebar.k(U.Machines.rows(U.Ui{st, sel, d, l, open, on, now, adding, pa, v, r, w, e, note, nf, ob, tr}), st, sel, open, on, now, adding, v)

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

def View.live.k(empty: Bool, running: Bool, text: String) -> List<&2, D.Node>:
  match empty running:
    case False{} _:
      [D.El{"div", "live", [D.At{"class", "msg assistant live"}], [D.El{"div", "", [D.At{"class", "body"}], D.Md.render(text)}]}]
    case True{} True{}:
      [D.El{"div", "live", [D.At{"class", "working"}], [D.Txt{"Working"}]}]
    case True{} False{}:
      Nil{}

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

def View.header(t: M.Thread, +panel: Bool, snoozed: Bool, picking: Bool, term: Bool, +diff: Bool, del: Bool) -> D.Node:
  match t:
    case M.Thread{_, _, title, _, _, turn, _, archived, override, +sa, +ua, pinned, _, +branch, _, _, model, _, _, _, _}:
      D.El{"header", "", [D.At{"class", "thread-head"}], [
        D.Dom.button("back", "select", "", "Threads", "‹"),
        D.Dom.span("title", title),
        D.Dom.span("meta", Bool.pick(String, String.is_empty(branch), "", branch)),
        D.El{"div", "", [D.At{"class", "tools"}], List.concat(&2, D.Node, [D.Dom.when(View.running(turn), D.Dom.button("", "interrupt", "", "Stop the running turn", "Stop")),
          [View.pin(pinned), View.settle(override, Nat.is_gt(sa, ua))], View.snooze(snoozed, picking), [View.archive(archived)], View.del(del), [
           D.Dom.button(Bool.pick(String, term, "on", ""), "term-toggle", "@term-size", "Terminal (ctrl+j)", "Terminal"),
           D.Dom.button(Bool.pick(String, Bool.and(panel, diff), "on", ""), "diff", "", "What this thread changed (ctrl+d)", "Diff"),
           D.Dom.button(Bool.pick(String, Bool.and(panel, Bool.not(diff)), "on", ""), "panel", "", "Board viewer", "Board")]])}]}

def View.models(ms: List<&2, String>, +cur: String) -> List<&2, D.Node>:
  match ms:
    case Nil{}:
      Nil{}
    case +m <> t:
      D.Dom.button(Bool.pick(String, String.eq(m, cur), "on", ""), "model", m, "Use " ++ m, m) <> View.models(t, cur)

# reasoning effort chips, the provider's default first
def View.efforts(es: List<&2, String>, +cur: String) -> List<&2, D.Node>:
  match es:
    case Nil{}:
      Nil{}
    case +e <> t:
      D.Dom.button(Bool.pick(String, String.eq(e, cur), "on", ""), "effort", e, "Reasoning effort: " ++ U.Effort.name(e), U.Effort.name(e)) <> View.efforts(t, cur)

def View.effort_row(+es: List<&2, String>, +cur: String) -> List<&2, D.Node>:
  Bool.pick(List<&2, D.Node>, List.is_empty(&2, String, es), Nil{}, [D.El{"div", "", [D.At{"class", "efforts"}], View.efforts(es, cur)}])

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

# what waits for the running turn (already stored on the server)
def View.queued(+q: String) -> D.Node:
  Bool.pick(D.Node, String.is_empty(q), D.El{"div", "", [D.At{"class", "queued none"}], Nil{}},
    D.El{"div", "", [D.At{"class", "queued"}], [D.Dom.span("label", "Queued"), D.Dom.span("text", q), D.Dom.span("note", "sends when this turn ends")]})

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

# the same settings as the native window
def View.settings(+st: M.State, +nf: Map<&2, String>, +v: String, +note: String) -> D.Node:
  +prov = M.Setting.get(st, "agent.provider", "claude")
  +ipc = M.Setting.get(st, "kicad.ipc", "on")
  D.El{"main", "settings", [D.At{"class", "settings-view"}], [
    D.El{"header", "", [D.At{"class", "thread-head"}], [D.Dom.span("title", "Settings"), D.Dom.span("meta", ""), D.Dom.button("", "flag", "settings", "Close settings", "Close")]},
    D.El{"div", "", [D.At{"class", "settings"}], [
      View.setrow("Settle after", "Threads idle this long move to Settled. They stay saved.", View.days(M.Setting.get(st, "settle.days", "3"))),
      View.setrow("Provider for new threads", Bool.pick(String, String.is_empty(U.Models.cli(U.Str.get(nf, "models"), prov)), prov ++ " is not installed", U.Models.cli(U.Str.get(nf, "models"), prov)) ++ ". Each thread keeps its own; change it from the composer.", View.chips(["claude", "codex", "grok"], prov, "agent.provider")),
      View.setrow("Model for new threads", Bool.pick(String, String.is_empty(M.Setting.get(st, "agent.model", "")), "default", M.Setting.get(st, "agent.model", "")) ++ ": " ++ U.Models.label_of(U.Str.get(nf, "models"), prov, M.Setting.get(st, "agent.model", "")), View.chips("" <> U.Models.list(U.Str.get(nf, "models"), prov), M.Setting.get(st, "agent.model", ""), "agent.model")),
      View.setrow("KiCad CLI", U.Str.get(nf, "kicad.cli"), View.fork(U.Str.get(nf, "kicad.fork"))),
      View.setrow("KiCad IPC", "Agents may drive KiCad through the fork's api-server.", View.chips(["on", "off"], ipc, "kicad.ipc")),
      View.setrow("Tailscale: " ++ U.Str.get(nf, "tailnet"), "Listening on " ++ U.Str.get(nf, "listen"), Nil{}),
      View.setrow("Update channel", "Stable takes releases; nightly also takes the daily builds.", View.chips(["stable", "nightly"], M.Setting.get(st, "update.channel", "stable"), "update.channel")),
      View.setrow("Backplane " ++ v, Bool.pick(String, String.is_empty(note), "Up to date, checked hourly.", note),
        Bool.pick(List<&2, D.Node>, String.starts_with(note, "update "), [D.Dom.button("primary", "update", "", "Install the update", "Install update")],
          [D.Dom.button("", "update-check", "", "Look for an update now", "Check now")]))]}]}

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

def View.prows(ps: List<&2, U.PItem>, +i: Nat, +sel: Nat) -> List<&2, D.Node>:
  match ps:
    case Nil{}:
      Nil{}
    case U.PItem{+l, +a, v} <> t:
      D.Dom.button(Bool.pick(String, String.eq(a, "proj-cd"), "prow", Bool.pick(String, String.is_empty(a), "prow off", "prow act")) ++ Bool.pick(String, Nat.is_eq(i, sel), " sel", ""),
        a, v, l, l) <> View.prows(t, 1n+i, sel)

def View.picker(open: Bool, +u: U.Ui) -> List<&2, D.Node>:
  match open:
    case True{}:
      [D.El{"div", "", [D.At{"class", "modal-back"}, D.On{"click", "proj-close"}], Nil{}},
        D.El{"div", "picker", [D.At{"class", "picker"}], D.Dom.cat([
          D.El{"div", "", [D.At{"class", "dir"}], [D.Txt{U.Proj.dir(u)}]},
          D.El{"input", "proj", [D.At{"id", "proj"}, D.At{"placeholder", "Filter, name a new folder, or type a path"}, D.At{"autocomplete", "off"},
            D.On{"input", "proj-q"}, D.At{"data-enter", "proj-enter"}], Nil{}}],
          D.Dom.cat(Bool.pick(List<&2, D.Node>, String.is_empty(U.Ui.info(u, "proj.err")), Nil{}, [D.El{"div", "", [D.At{"class", "perr"}], [D.Txt{U.Ui.info(u, "proj.err")}]}]),
            [D.El{"div", "", [D.At{"class", "prows"}], View.prows(U.Proj.items(u), 0n, U.Proj.index(u))}]))}]
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

# a run of tool calls folded into one row (FO.Fold decides the runs, their
# labels and which are open); a click opens or shuts it
def View.fold.row(+id: String, +label: String, +open: Bool) -> D.Node:
  WI.WIcon.button("fold", "fold", FO.Fold.ask(open, id), Bool.pick(String, open, "Hide these tool calls", "Show these tool calls"),
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

def View.entries.r(es: List<&2, M.Entry>, rs: List<&2, FO.Role>, +st: M.State, +sel: String) -> List<&2, D.Node>:
  match es rs:
    case Nil{} _:
      Nil{}
    case e <> t r <> rt:
      List.append(&2, D.Node, View.role(r, View.entry(e, st, sel)), View.entries.r(t, rt, st, sel))
    case e <> t Nil{}:
      List.append(&2, D.Node, View.entry(e, st, sel), View.entries.r(t, Nil{}, st, sel))

# a thread's entries, its runs of tool calls folded (the last stays open
# while its turn runs)
def View.entries(+es: List<&2, M.Entry>, +st: M.State, +sel: String, +info: Map<&2, String>, +running: Bool) -> List<&2, D.Node>:
  View.entries.r(es, FO.Fold.roles(es, info, running), st, sel)

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

def View.composer(+draft: String, running: Bool, +label: String, +picking: Bool, +ms: List<&2, String>, +model: String, +es: List<&2, String>, +effort: String, +rs: List<&2, U.SkillRow>,
    +atts: List<&2, String>, +up: String) -> D.Node:
  D.El{"div", "", [D.At{"class", "composer"}], D.Dom.cat(
    D.Dom.when(picking, D.El{"div", "", [D.At{"class", "picker"}], D.Dom.cat(View.effort_row(es, effort), View.models(ms, model))}), D.Dom.cat(View.skills(rs), D.Dom.cat(View.attaching(atts, up), [
    D.El{"textarea", "composer", [D.At{"id", "composer"}, D.At{"rows", "3"}, D.At{"placeholder", "Ask anything, @tag files, $skill, or describe the change"}, D.At{"value", draft}, D.On{"input", "draft"},
      D.At{"data-enter", Bool.pick(String, List.is_empty(&2, U.SkillRow, rs), "send", "skill")}, D.At{"data-tab", Bool.pick(String, List.is_empty(&2, U.SkillRow, rs), "", "skill")}, D.At{"data-paste", "attach"}], Nil{}},
    D.El{"div", "", [D.At{"class", "composer-foot"}], [
      WI.WIcon.after("model-chip", "flag", "models", "Choose the model and effort", U.Effort.label(label, effort), "chevron-down", 14),
      D.El{"label", "", [D.At{"class", "attach"}, D.At{"title", "Attach files or images (or paste an image)"}], [WI.WIcon.svg("paperclip", 16),
        D.El{"input", "attach-file", [D.At{"type", "file"}, D.At{"multiple", ""}, D.At{"data-attach", "attach"}], Nil{}}]},
      D.Dom.button("primary", "send", "", "Send (Enter)", Bool.pick(String, running, "Queue", "Send"))]}])))}

def View.thread.p(u: U.Ui, t: M.Thread, pend: List<&2, String>, +atts: List<&2, String>, +up: String, +term: Bool) -> D.Node:
  match u t:
    case U.Ui{+st, +sel, +drafts, +live, +op, _, +now, _, panel, _, _, _, _, _, +nf, _, +tr} M.Thread{+id, p, ti, c, a, +turn, pe, ar, o, sa, ua, pi, en, br, wt, +pr, +mo, rm, im, se, de}:
      D.El{"main", "thread", [D.At{"class", Bool.pick(String, term, "thread-view with-term", "thread-view") ++ Bool.pick(String, U.Flag.get(op, "drop"), " dropping", "")},
        D.At{"data-drop", "attach"}, D.At{"data-drop-hover", "drop-hover"}], D.Dom.cat([
        View.header(M.Thread{id, p, ti, c, a, turn, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de}, panel, M.Snooze.on(now, U.Side.until(st, id)), U.Flag.get(op, "snooze"), term, String.eq(U.Str.get(nf, "view.kind"), "diff"), String.eq(U.Str.get(drafts, "@del"), id)),
        D.El{"div", "timeline", [D.At{"class", "timeline"}, D.At{"id", "timeline"}],
          D.Dom.cat(View.parent(st, U.Tasks.parent(st, id)), D.Dom.cat(View.tasks(U.Tasks.of(st, id), st),
          D.Dom.cat(View.entries(View.mine(U.Ui.entries(st), id, Nil{}), st, id, nf, View.running(turn)), D.Dom.cat(View.sending(pend),
            View.live.k(String.is_empty(U.Str.get(live, id)), View.running(turn), U.Str.get(live, id))))))},
        D.El{"div", "asks", [D.At{"class", "asks"}], View.asks(U.Asks.open(st, id), U.Str.get(drafts, sel))},
        View.queued(M.Queue.of(st, id)),
        View.composer(U.Str.get(drafts, sel), View.running(turn), U.Models.label(pr, mo), U.Flag.get(op, "models"), U.Models.list(U.Str.get(nf, "models"), pr), mo,
          U.Effort.chips(U.Str.get(nf, "models"), pr, mo), U.Effort.of(st, sel), U.Skills.of(sel, drafts, nf), atts, up)],
        D.Dom.when(term, View.term(U.Term.get(tr, id))))}

def View.thread(+u: U.Ui, t: M.Thread) -> D.Node:
  View.thread.p(u, t, U.Ui.pending(u, U.Ui.sel(u)), U.Ui.atts(u, U.Ui.sel(u)), U.Ui.uploading(u, U.Ui.sel(u)), U.Ui.flag(u, "term"))

def View.main.s(settings: Bool, none: Bool, u: U.Ui, +sel: String, +n: Nat) -> D.Node:
  match settings none u:
    case True{} _ U.Ui{+st, _, _, _, _, _, _, _, _, +v, _, _, _, +note, +nf, +ob, +tr}:
      View.settings(st, nf, v, note)
    case False{} True{} _:
      View.empty(n)
    case False{} False{} U.Ui{+st, s2, d, l, o, on, now, ad, pa, v, r, w, e, note, nf, ob, tr}:
      View.thread(U.Ui{st, s2, d, l, o, on, now, ad, pa, v, r, w, e, note, nf, ob, tr}, U.Ui.thread(st, sel))

def View.main.k(none: Bool, u: U.Ui, +sel: String, +n: Nat) -> D.Node:
  match none u:
    case _ U.Ui{+st, _, _, _, +o, _, _, _, _, +v, _, _, _, +note, +nf, +ob, +tr}:
      View.main.s(U.Flag.get(o, "settings"), none, u, sel, n)

# the side pane: the diff view, or the board canvas
def View.aside(diff: Bool, +text: String) -> D.Node:
  match diff:
    case True{}:
      View.diff(text)
    case False{}:
      D.El{"aside", "viewer", [D.At{"class", "viewer"}, D.At{"id", "viewer"}], [D.El{"canvas", "board", [D.At{"id", "board"}], Nil{}}]}

# the whole page
def View.page(u: U.Ui) -> D.Node:
  match u:
    case U.Ui{+st, +sel, +d, +l, +o, +on, +now, +ad, +pa, +v, +r, +w, +e, +note, +nf, +ob, +tr}:
      D.El{"div", "app", [D.At{"class", Bool.pick(String, pa, "app panel", "app") ++ Bool.pick(String, Bool.or(Bool.not(String.is_empty(sel)), U.Flag.get(o, "settings")), " picked", "")}],
        D.Dom.cat([View.sidebar(U.Ui{st, sel, d, l, o, on, now, ad, pa, v, r, w, e, note, nf, ob, tr}),
          View.main.k(String.is_empty(sel), U.Ui{st, sel, d, l, o, on, now, ad, pa, v, r, w, e, note, nf, ob, tr}, sel, List.length(&2, M.Project, U.Ui.projects(st)))],
          D.Dom.cat(D.Dom.when(pa, View.aside(String.eq(U.Str.get(nf, "view.kind"), "diff"), U.Str.get(nf, "diff"))),
            D.Dom.cat(View.picker(U.Flag.get(o, "proj"), U.Ui{st, sel, d, l, o, on, now, ad, pa, v, r, w, e, note, nf, ob, tr}), View.error(e))))}
