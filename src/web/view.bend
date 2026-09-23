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
    case U.Ui{+st, +sel, _, _, +open, on, +now, adding, _, v, _, _, _, _, _}:
      D.El{"aside", "sidebar", [D.At{"class", "sidebar"}],
        D.Dom.cat([D.El{"div", "", [D.At{"class", "brand"}], [
            D.Dom.span(Bool.pick(String, on, "conn on", "conn"), ""),
            D.Dom.span("name", "Backplane"), D.Dom.span("ver", v),
            D.Dom.button("icon", "toggle-add", "", "Add project", "+")]}],
          D.Dom.cat(View.add(adding),
            View.projects(List.sort(~PRow, ~PRow.before, View.rows(U.Ui.projects(st), U.Ui.threads(st))), open, sel, now)))}

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

# a thread's entries, oldest first (the state keeps them newest first)
def View.mine(es: List<&2, M.Entry>, +th: String, acc: List<&2, M.Entry>) -> List<&2, M.Entry>:
  match es:
    case Nil{}:
      acc
    case +e <> t:
      View.mine(t, th, View.mine.k(String.eq(View.entry_thread(e), th), e, acc))

def View.entry(e: M.Entry) -> D.Node:
  match e:
    case M.Msg{id, _, M.User{}, +text, _}:
      D.El{"div", id, [D.At{"class", "msg user"}], [D.El{"div", "", [D.At{"class", "body plain"}], [D.Txt{text}]}, D.Dom.copy(text)]}
    case M.Msg{id, _, _, +text, _}:
      D.El{"div", id, [D.At{"class", "msg assistant"}], [D.El{"div", "", [D.At{"class", "body"}], D.Md.render(text)}, D.Dom.copy(text)]}
    case M.Act{id, _, tone, kind, summary, _}:
      D.El{"div", id, [D.At{"class", "act " ++ tone}], [D.Dom.span("kind", kind), D.Dom.span("summary", summary)]}

def View.entries(es: List<&2, M.Entry>) -> List<&2, D.Node>:
  match es:
    case Nil{}:
      Nil{}
    case e <> t:
      View.entry(e) <> View.entries(t)

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
        D.Dom.span("title", title),
        D.Dom.span("meta", Bool.pick(String, String.is_empty(branch), "", branch)),
        D.El{"div", "", [D.At{"class", "tools"}], D.Dom.cat(D.Dom.when(View.running(turn), D.Dom.button("", "interrupt", "", "Stop the running turn", "Stop")),
          [View.pin(pinned), View.settle(override, Nat.is_gt(sa, ua)), D.Dom.button("", "archive", "", "Archive thread", "Archive"),
           D.Dom.button(Bool.pick(String, panel, "on", ""), "panel", "", "Board viewer", "Board")])}]}

def View.composer(+draft: String, running: Bool) -> D.Node:
  D.El{"div", "", [D.At{"class", "composer"}], [
    D.El{"textarea", "composer", [D.At{"id", "composer"}, D.At{"rows", "3"}, D.At{"placeholder", "Ask the agent"}, D.At{"value", draft}, D.On{"input", "draft"}, D.At{"data-enter", "send"}], Nil{}},
    D.Dom.button("primary", "send", "", "Send (Enter)", Bool.pick(String, running, "Queue", "Send"))]}

def View.thread(u: U.Ui, t: M.Thread) -> D.Node:
  match u t:
    case U.Ui{st, +sel, drafts, +live, _, _, _, _, panel, _, _, _, _, _, _} M.Thread{+id, p, ti, c, a, +turn, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de}:
      D.El{"main", "thread", [D.At{"class", "thread-view"}], [
        View.header(M.Thread{id, p, ti, c, a, turn, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de}, panel),
        D.El{"div", "timeline", [D.At{"class", "timeline"}, D.At{"id", "timeline"}],
          D.Dom.cat(View.entries(View.mine(U.Ui.entries(st), id, Nil{})),
            View.live.k(String.is_empty(U.Str.get(live, id)), View.running(turn), U.Str.get(live, id)))},
        View.composer(U.Str.get(drafts, sel), View.running(turn))]}

def View.empty(n: Nat) -> D.Node:
  D.El{"main", "empty", [D.At{"class", "empty"}], [D.Txt{Bool.pick(String, Nat.is_eq(n, 0n), "Add a project with + to start.", "Pick a thread, or start one with + next to a project.")}]}

def View.main.k(none: Bool, u: U.Ui, +sel: String, +n: Nat) -> D.Node:
  match none u:
    case True{} _:
      View.empty(n)
    case False{} U.Ui{+st, s2, d, l, o, on, now, ad, pa, v, r, w, e, note, nf}:
      View.thread(U.Ui{st, s2, d, l, o, on, now, ad, pa, v, r, w, e, note, nf}, U.Ui.thread(st, sel))

def View.error(e: String) -> List<&2, D.Node>:
  match e:
    case SNil{}:
      Nil{}
    case SCon{h, t}:
      [D.El{"div", "error", [D.At{"class", "toast"}, D.On{"click", "dismiss"}], [D.Txt{SCon{h, t}}]}]

# the whole page
def View.page(u: U.Ui) -> D.Node:
  match u:
    case U.Ui{+st, +sel, +d, +l, +o, +on, +now, +ad, +pa, +v, +r, +w, +e, +note, +nf}:
      D.El{"div", "app", [D.At{"class", Bool.pick(String, pa, "app panel", "app")}],
        D.Dom.cat([View.sidebar(U.Ui{st, sel, d, l, o, on, now, ad, pa, v, r, w, e, note, nf}),
          View.main.k(String.is_empty(sel), U.Ui{st, sel, d, l, o, on, now, ad, pa, v, r, w, e, note, nf}, sel, List.length(&2, M.Project, U.Ui.projects(st)))],
          D.Dom.cat(D.Dom.when(pa, D.El{"aside", "viewer", [D.At{"class", "viewer"}, D.At{"id", "viewer"}], [D.El{"canvas", "board", [D.At{"id", "board"}], Nil{}}]}),
            View.error(e)))}
