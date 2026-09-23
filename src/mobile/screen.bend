import Base
import ../core/json.bend as J
import ../core/model.bend as M
import ../core/client.bend as U
import ../web/dom.bend as D
import ../web/view.bend as V

# Ui -> the screen the phone apps draw, as JSON. SwiftUI and Compose map
# it onto native lists, toolbars and text fields; every decision (order,
# shelf, status, labels, markdown blocks) is made here or in core.

def Mob.state(t: M.TurnState) -> String:
  match t:
    case M.Running{}:
      "run"
    case M.Failed{}:
      "fail"
    case M.Interrupted{}:
      "stop"
    case _:
      "idle"

def Mob.row(t: M.Thread, +now: Nat) -> J.Json:
  match t:
    case M.Thread{id, _, title, _, +a, turn, _, _, _, _, _, pinned, _, _, _, _, _, _, _, _, _}:
      J.Json.obj([J.KV{"id", J.Json.str(id)}, J.KV{"title", J.Json.str(title)}, J.KV{"state", J.Json.str(Mob.state(turn))},
        J.KV{"ago", J.Json.str(U.Time.ago(now, a))}, J.KV{"pinned", J.Json.bool(pinned)}])

def Mob.rows(ts: List<&2, M.Thread>, +now: Nat) -> List<&2, J.Json>:
  match ts:
    case Nil{}:
      Nil{}
    case t <> rest:
      Mob.row(t, now) <> Mob.rows(rest, now)

def Mob.project(r: V.PRow, +open: Map<&2, Bool>, +now: Nat) -> J.Json:
  match r:
    case V.PRow{_, M.Project{+id, title, root, _, _}, M.Shelves{pinned, active, +settled, _}}:
      J.Json.obj([J.KV{"id", J.Json.str(id)}, J.KV{"title", J.Json.str(title)}, J.KV{"root", J.Json.str(root)},
        J.KV{"open", J.Json.bool(U.Flag.get(open, id))},
        J.KV{"threads", J.Json.arr(Mob.rows(List.append(&2, M.Thread, pinned, active), now))},
        J.KV{"shelf", J.Json.str("Settled " ++ Nat.show(List.length(&2, M.Thread, settled)))},
        J.KV{"settled", J.Json.arr(Mob.rows(settled, now))}])

def Mob.projects(rs: List<&2, V.PRow>, +open: Map<&2, Bool>, +now: Nat) -> List<&2, J.Json>:
  match rs:
    case Nil{}:
      Nil{}
    case r <> t:
      Mob.project(r, open, now) <> Mob.projects(t, open, now)

# markdown blocks from the same Md.render the web page uses
def Mob.nodes(ns: List<&2, D.Node>) -> List<&2, J.Json>:
  match ns:
    case Nil{}:
      Nil{}
    case D.El{tag, _, _, kids} <> t:
      J.Json.obj([J.KV{"tag", J.Json.str(tag)}, J.KV{"kids", J.Json.arr(Mob.nodes(kids))}]) <> Mob.nodes(t)
    case D.Txt{text} <> t:
      J.Json.obj([J.KV{"text", J.Json.str(text)}]) <> Mob.nodes(t)

def Mob.entry(e: M.Entry) -> J.Json:
  match e:
    case M.Msg{id, _, M.User{}, text, _}:
      J.Json.obj([J.KV{"id", J.Json.str(id)}, J.KV{"kind", J.Json.str("user")}, J.KV{"text", J.Json.str(text)}])
    case M.Msg{id, _, _, +text, _}:
      J.Json.obj([J.KV{"id", J.Json.str(id)}, J.KV{"kind", J.Json.str("assistant")}, J.KV{"text", J.Json.str(text)},
        J.KV{"blocks", J.Json.arr(Mob.nodes(D.Md.render(text)))}])
    case M.Act{id, _, tone, kind, summary, _}:
      J.Json.obj([J.KV{"id", J.Json.str(id)}, J.KV{"kind", J.Json.str("act")}, J.KV{"tone", J.Json.str(tone)},
        J.KV{"label", J.Json.str(kind)}, J.KV{"text", J.Json.str(summary)}])

def Mob.entries(es: List<&2, M.Entry>) -> List<&2, J.Json>:
  match es:
    case Nil{}:
      Nil{}
    case e <> t:
      Mob.entry(e) <> Mob.entries(t)

# a toolbar button: what it says and the action it sends
def Mob.tool(label: String, action: String, on: Bool) -> J.Json:
  J.Json.obj([J.KV{"label", J.Json.str(label)}, J.KV{"action", J.Json.str(action)}, J.KV{"on", J.Json.bool(on)}])

def Mob.pin(p: Bool) -> J.Json:
  match p:
    case True{}:
      Mob.tool("Pinned", "unpin", True{})
    case False{}:
      Mob.tool("Pin", "pin", False{})

def Mob.settle(o: M.Override, auto: Bool) -> J.Json:
  match o auto:
    case M.ForcedSettled{} _:
      Mob.tool("Settled", "unsettle", True{})
    case M.NoOverride{} True{}:
      Mob.tool("Settled", "unsettle", True{})
    case _ _:
      Mob.tool("Settle", "settle", False{})

def Mob.stop(running: Bool) -> List<&2, J.Json>:
  match running:
    case True{}:
      [Mob.tool("Stop", "interrupt", False{})]
    case False{}:
      Nil{}

def Mob.live(empty: Bool, running: Bool) -> String:
  match empty running:
    case True{} True{}:
      "Working"
    case _ _:
      ""

def Mob.thread(u: U.Ui, t: M.Thread) -> J.Json:
  match u t:
    case U.Ui{st, +sel, drafts, +live, _, _, _, _, _, _, _, _, _, _, _} M.Thread{+id, _, title, _, _, +turn, _, _, o, +sa, +ua, pinned, _, branch, _, _, _, _, _, _, _}:
      J.Json.obj([J.KV{"id", J.Json.str(id)}, J.KV{"title", J.Json.str(title)}, J.KV{"branch", J.Json.str(branch)},
        J.KV{"state", J.Json.str(Mob.state(turn))},
        J.KV{"tools", J.Json.arr(List.append(&2, J.Json, Mob.stop(V.View.running(turn)), [Mob.pin(pinned), Mob.settle(o, Nat.is_gt(sa, ua)), Mob.tool("Archive", "archive", False{})]))},
        J.KV{"entries", J.Json.arr(Mob.entries(V.View.mine(U.Ui.entries(st), id, Nil{})))},
        J.KV{"live", J.Json.arr(Mob.nodes(D.Md.render(U.Str.get(live, id))))},
        J.KV{"working", J.Json.str(Mob.live(String.is_empty(U.Str.get(live, id)), V.View.running(turn)))},
        J.KV{"draft", J.Json.str(U.Str.get(drafts, sel))},
        J.KV{"send", J.Json.str(Bool.pick(String, V.View.running(turn), "Queue", "Send"))}])

def Mob.main(none: Bool, u: U.Ui, +sel: String) -> J.Json:
  match none u:
    case True{} _:
      J.Null{}
    case False{} U.Ui{+st, s2, d, l, o, on, now, ad, pa, v, r, w, e, note, nf}:
      Mob.thread(U.Ui{st, s2, d, l, o, on, now, ad, pa, v, r, w, e, note, nf}, U.Ui.thread(st, sel))

def Mob.empty(n: Nat) -> String:
  Bool.pick(String, Nat.is_eq(n, 0n), "Add a project to start.", "Pick a thread, or start one in a project.")

# the whole screen
def Mob.screen(u: U.Ui) -> J.Json:
  match u:
    case U.Ui{+st, +sel, +d, +l, +o, +on, +now, +ad, +pa, +v, +r, +w, +e, +note, +nf}:
      J.Json.obj([J.KV{"online", J.Json.bool(on)}, J.KV{"version", J.Json.str(v)}, J.KV{"error", J.Json.str(e)},
        J.KV{"note", J.Json.str(note)}, J.KV{"sel", J.Json.str(sel)},
        J.KV{"empty", J.Json.str(Mob.empty(List.length(&2, M.Project, U.Ui.projects(st))))},
        J.KV{"projects", J.Json.arr(Mob.projects(List.sort(~V.PRow, ~V.PRow.before, V.View.rows(U.Ui.projects(st), U.Ui.threads(st))), o, now))},
        J.KV{"thread", Mob.main(String.is_empty(sel), U.Ui{st, sel, d, l, o, on, now, ad, pa, v, r, w, e, note, nf}, sel)}])
