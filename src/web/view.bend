import Base
import ../core/model.bend as M
import ./dom.bend as D
import ../core/client.bend as U

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

def View.dot(t: M.TurnState) -> String:
  match t:
    case M.Running{}:
      "dot run"
    case M.Failed{}:
      "dot fail"
    case M.Interrupted{}:
      "dot stop"
    case _:
      "dot"

def View.row(t: M.Thread, +sel: String, +now: Nat) -> D.Node:
  match t:
    case M.Thread{+id, _, title, _, +a, turn, _, _, _, _, _, pinned, _, _, _, _, _, _, _, _, _}:
      D.El{"div", id, [D.At{"class", Bool.pick(String, String.eq(id, sel), "thread on", "thread")}, D.At{"data-value", id}, D.On{"click", "select"}],
        [D.Dom.span(View.dot(turn), ""), D.Dom.span("title", title), D.Dom.span("ago", U.Time.ago(now, a))]}

def View.rows_of(ts: List<&2, M.Thread>, +sel: String, +now: Nat) -> List<&2, D.Node>:
  match ts:
    case Nil{}:
      Nil{}
    case t <> rest:
      View.row(t, sel, now) <> View.rows_of(rest, sel, now)

def View.settled.k(open: Bool, +pid: String, n: Nat, ts: List<&2, M.Thread>, +sel: String, +now: Nat) -> List<&2, D.Node>:
  match open:
    case True{}:
      D.Dom.button("shelf open", "toggle-settled", pid, "Hide settled threads", "Settled " ++ Nat.show(n)) <> View.rows_of(ts, sel, now)
    case False{}:
      [D.Dom.button("shelf", "toggle-settled", pid, "Show settled threads", "Settled " ++ Nat.show(n))]

def View.settled(open: Bool, +pid: String, st: List<&2, M.Thread>, +sel: String, +now: Nat) -> List<&2, D.Node>:
  match st:
    case Nil{}:
      Nil{}
    case +t <> +rest:
      View.settled.k(open, pid, List.length(&2, M.Thread, t <> rest), t <> rest, sel, now)

def View.project(r: PRow, +open: Map<&2, Bool>, +sel: String, +now: Nat) -> D.Node:
  match r:
    case PRow{_, M.Project{+id, title, root, _, _}, M.Shelves{pinned, active, settled, _}}:
      D.El{"section", id, [D.At{"class", "project"}],
        D.Dom.cat([D.El{"div", "", [D.At{"class", "project-head"}, D.At{"title", root}],
            [D.Dom.span("name", title), D.Dom.button("icon", "new-thread", id, "New thread", "+")]}],
          D.Dom.cat(View.rows_of(pinned, sel, now),
            D.Dom.cat(View.rows_of(active, sel, now),
              View.settled(U.Flag.get(open, id), id, settled, sel, now))))}

def View.projects(rs: List<&2, PRow>, +open: Map<&2, Bool>, +sel: String, +now: Nat) -> List<&2, D.Node>:
  match rs:
    case Nil{}:
      Nil{}
    case r <> t:
      View.project(r, open, sel, now) <> View.projects(t, open, sel, now)

def View.add(adding: Bool) -> List<&2, D.Node>:
  match adding:
    case True{}:
      [D.El{"div", "", [D.At{"class", "add"}], [
        D.El{"input", "project-path", [D.At{"id", "project-path"}, D.At{"placeholder", "/path/to/project"}, D.At{"data-enter", "add-project"}, D.At{"data-value", "#project-path"}], Nil{}},
        D.Dom.button("primary", "add-project", "#project-path", "Add project", "Add")]}]
    case False{}:
      Nil{}

def View.sidebar(u: U.Ui) -> D.Node:
  match u:
    case U.Ui{+st, +sel, _, _, +open, on, +now, adding, _, v, _, _, _, _, _, _, _}:
      D.El{"aside", "sidebar", [D.At{"class", "sidebar"}],
        D.Dom.cat([D.El{"div", "", [D.At{"class", "brand"}], [
            D.Dom.span(Bool.pick(String, on, "conn on", "conn"), ""),
            D.Dom.span("name", "Backplane"), D.Dom.span("ver", v),
            D.Dom.button("icon", "toggle-add", "", "Add project", "+")]}],
          D.Dom.cat(View.add(adding),
            D.Dom.cat(View.projects(List.sort(~PRow, ~PRow.before, View.rows(U.Ui.projects(st), U.Kids.keep(U.Ui.threads(st), U.Kids.set(st)))), open, sel, now),
            [D.Dom.button("settings-link", "flag", "settings", "Settings", "Settings")])))}

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

def View.entry.own(e: M.Entry) -> D.Node:
  match e:
    case M.Msg{id, _, M.User{}, +text, _}:
      D.El{"div", id, [D.At{"class", "msg user"}], [D.El{"div", "", [D.At{"class", "body plain"}], [D.Txt{text}]}, D.Dom.copy(text)]}
    case M.Msg{id, _, _, +text, _}:
      D.El{"div", id, [D.At{"class", "msg assistant"}], [D.El{"div", "", [D.At{"class", "body"}], D.Md.render(text)}, D.Dom.copy(text)]}
    case M.Act{id, _, tone, kind, summary, _}:
      D.El{"div", id, [D.At{"class", "act " ++ tone}], [D.Dom.span("kind", kind), D.Dom.span("summary", summary)]}

def View.link(+cls: String, +label: String, +to: String) -> D.Node:
  D.El{"button", "", [D.At{"class", "link " ++ cls}, D.At{"data-value", to}, D.On{"click", "select"}], [D.Txt{label}]}

def View.from.k(none: Bool, +from: String, +st: M.State) -> List<&2, D.Node>:
  match none:
    case True{}:
      Nil{}
    case False{}:
      [View.link("in", "← from " ++ U.Tasks.title(st, from), from)]

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

def View.entries(es: List<&2, M.Entry>, +st: M.State, +sel: String) -> List<&2, D.Node>:
  match es:
    case Nil{}:
      Nil{}
    case e <> t:
      List.append(&2, D.Node, View.entry(e, st, sel), View.entries(t, st, sel))

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

def View.header(t: M.Thread, panel: Bool) -> D.Node:
  match t:
    case M.Thread{_, _, title, _, _, turn, _, _, override, +sa, +ua, pinned, _, +branch, _, _, model, _, _, _, _}:
      D.El{"header", "", [D.At{"class", "thread-head"}], [
        D.Dom.button("back", "select", "", "Threads", "‹"),
        D.Dom.span("title", title),
        D.Dom.span("meta", Bool.pick(String, String.is_empty(branch), "", branch)),
        D.El{"div", "", [D.At{"class", "tools"}], D.Dom.cat(D.Dom.when(View.running(turn), D.Dom.button("", "interrupt", "", "Stop the running turn", "Stop")),
          [View.pin(pinned), View.settle(override, Nat.is_gt(sa, ua)), D.Dom.button("", "archive", "", "Archive thread", "Archive"),
           D.Dom.button(Bool.pick(String, panel, "on", ""), "panel", "", "Board viewer", "Board")])}]}

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

def View.composer(+draft: String, running: Bool, +label: String, +picking: Bool, +ms: List<&2, String>, +model: String, +es: List<&2, String>, +effort: String, +rs: List<&2, U.SkillRow>) -> D.Node:
  D.El{"div", "", [D.At{"class", "composer"}], D.Dom.cat(
    D.Dom.when(picking, D.El{"div", "", [D.At{"class", "picker"}], D.Dom.cat(View.effort_row(es, effort), View.models(ms, model))}), D.Dom.cat(View.skills(rs), [
    D.El{"textarea", "composer", [D.At{"id", "composer"}, D.At{"rows", "3"}, D.At{"placeholder", "Ask anything, @tag files, $skill, or describe the change"}, D.At{"value", draft}, D.On{"input", "draft"},
      D.At{"data-enter", Bool.pick(String, List.is_empty(&2, U.SkillRow, rs), "send", "skill")}, D.At{"data-tab", Bool.pick(String, List.is_empty(&2, U.SkillRow, rs), "", "skill")}], Nil{}},
    D.El{"div", "", [D.At{"class", "composer-foot"}], [
      D.Dom.button("model-chip", "flag", "models", "Choose the model and effort", U.Effort.label(label, effort) ++ " ▾"),
      D.Dom.button("primary", "send", "", "Send (Enter)", Bool.pick(String, running, "Queue", "Send"))]}]))}

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

def View.sending(ps: List<&2, String>) -> List<&2, D.Node>:
  match ps:
    case Nil{}:
      Nil{}
    case p <> t:
      D.El{"div", "", [D.At{"class", "msg user sending"}], [D.El{"div", "", [D.At{"class", "body plain"}], [D.Txt{p}]}, D.Dom.span("note", "sending…")]} <> View.sending(t)

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

def View.thread.p(u: U.Ui, t: M.Thread, pend: List<&2, String>) -> D.Node:
  match u t:
    case U.Ui{+st, +sel, +drafts, +live, +op, _, _, _, panel, _, _, _, _, _, +nf, _, _} M.Thread{+id, p, ti, c, a, +turn, pe, ar, o, sa, ua, pi, en, br, wt, +pr, +mo, rm, im, se, de}:
      D.El{"main", "thread", [D.At{"class", "thread-view"}], [
        View.header(M.Thread{id, p, ti, c, a, turn, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de}, panel),
        D.El{"div", "timeline", [D.At{"class", "timeline"}, D.At{"id", "timeline"}],
          D.Dom.cat(View.parent(st, U.Tasks.parent(st, id)), D.Dom.cat(View.tasks(U.Tasks.of(st, id), st),
          D.Dom.cat(View.entries(View.mine(U.Ui.entries(st), id, Nil{}), st, id), D.Dom.cat(View.sending(pend),
            View.live.k(String.is_empty(U.Str.get(live, id)), View.running(turn), U.Str.get(live, id))))))},
        D.El{"div", "asks", [D.At{"class", "asks"}], View.asks(U.Asks.open(st, id), U.Str.get(drafts, sel))},
        View.queued(M.Queue.of(st, id)),
        View.composer(U.Str.get(drafts, sel), View.running(turn), U.Models.label(pr, mo), U.Flag.get(op, "models"), U.Models.list(U.Str.get(nf, "models"), pr), mo,
          U.Effort.chips(pr), U.Effort.of(st, sel), U.Skills.of(sel, drafts, nf))]}

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
      View.setrow("Provider for new threads", "Each thread keeps its own; change it from the composer.", View.chips(["claude", "codex", "grok"], prov, "agent.provider")),
      View.setrow("Model for new threads", "The models this machine's " ++ prov ++ " install offers.", View.chips("" <> U.Models.list(U.Str.get(nf, "models"), prov), M.Setting.get(st, "agent.model", ""), "agent.model")),
      View.setrow("KiCad CLI", U.Str.get(nf, "kicad.cli"), View.fork(U.Str.get(nf, "kicad.fork"))),
      View.setrow("KiCad IPC", "Agents may drive KiCad through the fork's api-server.", View.chips(["on", "off"], ipc, "kicad.ipc")),
      View.setrow("Tailscale: " ++ U.Str.get(nf, "tailnet"), "Listening on " ++ U.Str.get(nf, "listen"), Nil{}),
      View.setrow("Backplane " ++ v, Bool.pick(String, String.is_empty(note), "Up to date, checked hourly.", note),
        Bool.pick(List<&2, D.Node>, String.starts_with(note, "update "), [D.Dom.button("primary", "update", "", "Install the update", "Install update")], Nil{}))]}]}

def View.empty(n: Nat) -> D.Node:
  D.El{"main", "empty", [D.At{"class", "empty"}], [D.Txt{Bool.pick(String, Nat.is_eq(n, 0n), "Add a project with + to start.", "Pick a thread, or start one with + next to a project.")}]}

def View.thread(+u: U.Ui, t: M.Thread) -> D.Node:
  View.thread.p(u, t, U.Ui.pending(u, U.Ui.sel(u)))

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

def View.error(e: String) -> List<&2, D.Node>:
  match e:
    case SNil{}:
      Nil{}
    case SCon{h, t}:
      [D.El{"div", "error", [D.At{"class", "toast"}, D.On{"click", "dismiss"}], [D.Txt{SCon{h, t}}]}]

# the whole page
def View.page(u: U.Ui) -> D.Node:
  match u:
    case U.Ui{+st, +sel, +d, +l, +o, +on, +now, +ad, +pa, +v, +r, +w, +e, +note, +nf, +ob, +tr}:
      D.El{"div", "app", [D.At{"class", Bool.pick(String, pa, "app panel", "app") ++ Bool.pick(String, Bool.or(Bool.not(String.is_empty(sel)), U.Flag.get(o, "settings")), " picked", "")}],
        D.Dom.cat([View.sidebar(U.Ui{st, sel, d, l, o, on, now, ad, pa, v, r, w, e, note, nf, ob, tr}),
          View.main.k(String.is_empty(sel), U.Ui{st, sel, d, l, o, on, now, ad, pa, v, r, w, e, note, nf, ob, tr}, sel, List.length(&2, M.Project, U.Ui.projects(st)))],
          D.Dom.cat(D.Dom.when(pa, D.El{"aside", "viewer", [D.At{"class", "viewer"}, D.At{"id", "viewer"}], [D.El{"canvas", "board", [D.At{"id", "board"}], Nil{}}]}),
            View.error(e)))}
