import Base
import ../core/json.bend as J
import ../core/model.bend as M
import ../core/client.bend as U
import ../web/dom.bend as D
import ../web/view.bend as V
import ./notify.bend as N
import ./view.bend as VW
import ./picker.bend as PK

# Ui -> the screen the phone apps draw, as JSON. SwiftUI and Compose map
# it onto native lists, toolbars and text fields; every decision (order,
# shelf, status, labels, markdown blocks) is made here or in core.

def Mob.st(u: U.Ui) -> M.State:
  match u:
    case U.Ui{st, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      st

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

# a swipe button: what it says, the action it sends with its value, its
# tone ("danger", "settle", ""), and choices (a snooze) whose values it
# sends instead
def Mob.swipe(label: String, action: String, value: String, tone: String, opts: List<&2, J.Json>) -> J.Json:
  J.Json.obj([J.KV{"label", J.Json.str(label)}, J.KV{"action", J.Json.str(action)}, J.KV{"value", J.Json.str(value)},
    J.KV{"tone", J.Json.str(tone)}, J.KV{"options", J.Json.arr(opts)}])

def Mob.opt(label: String, value: String) -> J.Json:
  J.Json.obj([J.KV{"label", J.Json.str(label)}, J.KV{"value", J.Json.str(value)}])

def Mob.snoozes(+id: String) -> List<&2, J.Json>:
  [Mob.opt("1 hour", id ++ "|1h"), Mob.opt("Tomorrow", id ++ "|tomorrow"), Mob.opt("1 week", id ++ "|1w")]

# the swipe from the leading edge: settle an open thread, bring back a
# settled one, wake a snoozed one (shelf 0 open, 1 settled, 2 snoozed)
def Mob.lead(shelf: Nat, +id: String) -> J.Json:
  match shelf:
    case 0n:
      Mob.swipe("Settle", "row-settle", id, "settle", Nil{})
    case 1n:
      Mob.swipe("Unsettle", "row-unsettle", id, "settle", Nil{})
    case _:
      Mob.swipe("Wake", "row-snooze", id ++ "|off", "settle", Nil{})

# the swipe from the trailing edge: delete (asks first), snooze
def Mob.trail(+id: String) -> List<&2, J.Json>:
  [Mob.swipe("Delete", "row-delete", id, "danger", Nil{}), Mob.swipe("Snooze", "row-snooze", "", "", Mob.snoozes(id))]

# a row's time: since its last activity, or (snoozed) until it wakes
def Mob.when(shelf: Nat, +st: M.State, +id: String, +a: Nat, +now: Nat) -> String:
  match shelf:
    case 2n:
      U.Time.ago(U.Side.until(st, id), now)
    case _:
      U.Time.ago(now, a)

def Mob.row(t: M.Thread, +st: M.State, +now: Nat, +shelf: Nat) -> J.Json:
  match t:
    case M.Thread{+id, _, title, _, +a, turn, _, _, _, _, _, pinned, _, _, _, _, _, _, _, _, _}:
      J.Json.obj([J.KV{"id", J.Json.str(id)}, J.KV{"title", J.Json.str(title)}, J.KV{"state", J.Json.str(Mob.state(turn))},
        J.KV{"ago", J.Json.str(Mob.when(shelf, st, id, a, now))}, J.KV{"pinned", J.Json.bool(pinned)},
        J.KV{"lead", J.Json.arr([Mob.lead(shelf, id)])}, J.KV{"trail", J.Json.arr(Mob.trail(id))}])

def Mob.rows(ts: List<&2, M.Thread>, +st: M.State, +now: Nat, +shelf: Nat) -> List<&2, J.Json>:
  match ts:
    case Nil{}:
      Nil{}
    case t <> rest:
      Mob.row(t, st, now, shelf) <> Mob.rows(rest, st, now, shelf)

# snoozed threads sit on their own shelf, soonest to wake first
def Mob.project(r: U.SRow, +open: Map<&2, Bool>, +st: M.State, +now: Nat) -> J.Json:
  match r:
    case U.SRow{_, M.Project{+id, title, root, _, _}, M.Shelves{pinned, active, +settled, _, snoozed}}:
      J.Json.obj([J.KV{"id", J.Json.str(id)}, J.KV{"title", J.Json.str(title)}, J.KV{"root", J.Json.str(root)},
        J.KV{"open", J.Json.bool(U.Flag.get(open, id))},
        J.KV{"threads", J.Json.arr(Mob.rows(List.append(&2, M.Thread, pinned, active), st, now, 0n))},
        J.KV{"snoozedShelf", J.Json.str("Snoozed")},
        J.KV{"snoozed", J.Json.arr(Mob.rows(snoozed, st, now, 2n))},
        J.KV{"shelf", J.Json.str("Settled " ++ Nat.show(List.length(&2, M.Thread, settled)))},
        J.KV{"settled", J.Json.arr(Mob.rows(settled, st, now, 1n))}])

def Mob.projects(rs: List<&2, U.SRow>, +open: Map<&2, Bool>, +st: M.State, +now: Nat) -> List<&2, J.Json>:
  match rs:
    case Nil{}:
      Nil{}
    case r <> t:
      Mob.project(r, open, st, now) <> Mob.projects(t, open, st, now)

# markdown blocks from the same Md.render the web page uses; built onto a
# reversed accumulator so a long reply's many blocks cost no stack (only
# nesting does)
def Mob.nodes.go(ns: List<&2, D.Node>, acc: List<&2, J.Json>) -> List<&2, J.Json>:
  match ns:
    case Nil{}:
      acc
    case D.El{tag, _, _, kids} <> t:
      Mob.nodes.go(t, J.Json.obj([J.KV{"tag", J.Json.str(tag)}, J.KV{"kids", J.Json.arr(List.reverse(&2, J.Json, Mob.nodes.go(kids, Nil{})))}]) <> acc)
    case D.Txt{text} <> t:
      Mob.nodes.go(t, J.Json.obj([J.KV{"text", J.Json.str(text)}]) <> acc)

def Mob.nodes(ns: List<&2, D.Node>) -> List<&2, J.Json>:
  List.reverse(&2, J.Json, Mob.nodes.go(ns, Nil{}))

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

# a thread's entries, tail-recursive (a thread can hold thousands)
def Mob.entries.go(es: List<&2, M.Entry>, acc: List<&2, J.Json>) -> List<&2, J.Json>:
  match es:
    case Nil{}:
      acc
    case e <> t:
      Mob.entries.go(t, Mob.entry(e) <> acc)

def Mob.entries(es: List<&2, M.Entry>) -> List<&2, J.Json>:
  List.reverse(&2, J.Json, Mob.entries.go(es, Nil{}))

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

def Mob.strs(xs: List<&2, String>) -> List<&2, J.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      J.Json.str(x) <> Mob.strs(t)

# a choice of a menu: what it says, the value it sends, whether it is on
def Mob.choice(label: String, value: String, on: Bool) -> J.Json:
  J.Json.obj([J.KV{"label", J.Json.str(label)}, J.KV{"value", J.Json.str(value)}, J.KV{"on", J.Json.bool(on)}])

# a model's name in the menu: the CLI's label for it ("Opus 5.5 ·
# claude-opus-5-5"), else its name
def Mob.model_name(+info: String, +provider: String, +m: String) -> String:
  Bool.pick(String, String.is_empty(U.Models.label_of(info, provider, m)), Bool.pick(String, String.is_empty(m), "default", m), U.Models.label_of(info, provider, m))

def Mob.models(ms: List<&2, String>, +info: String, +provider: String, +cur: String) -> List<&2, J.Json>:
  match ms:
    case Nil{}:
      Nil{}
    case +m <> t:
      Mob.choice(Mob.model_name(info, provider, m), m, String.eq(m, cur)) <> Mob.models(t, info, provider, cur)

def Mob.efforts(es: List<&2, String>, +cur: String, +prov: String) -> List<&2, J.Json>:
  match es:
    case Nil{}:
      Nil{}
    case +e <> t:
      Mob.choice(U.Chip.name(e), e, U.Chip.on(e, cur, prov)) <> Mob.efforts(t, cur, prov)

# the composer's model chip and its menu: the thread's provider's models
# (its default first; "model" sends one) and the efforts that model takes
# ("effort")
def Mob.picker(+info: String, +provider: String, +model: String, +effort: String) -> J.Json:
  J.Json.obj([J.KV{"label", J.Json.str(U.Effort.label(U.Models.label(provider, model), effort))},
    J.KV{"models", J.Json.arr(Mob.models("" <> U.Models.list(info, provider), info, provider, model))},
    J.KV{"efforts", J.Json.arr(Mob.efforts(U.Effort.chips(info, provider, model), effort, provider))},
    J.KV{"providers", J.Json.arr(Mob.efforts(U.Chip.providers(), effort, provider))}])

def Mob.qbtns(bs: List<&2, U.QBtn>) -> List<&2, J.Json>:
  match bs:
    case Nil{}:
      Nil{}
    case U.QBtn{l, a, v} <> t:
      J.Json.obj([J.KV{"label", J.Json.str(l)}, J.KV{"action", J.Json.str(a)}, J.KV{"value", J.Json.str(v)}]) <> Mob.qbtns(t)

# the queue above the composer: each waiting message with its buttons
# (U.Qu.buttons)
def Mob.queue(qs: List<&2, M.QItem>, +first: Bool, +run: Bool) -> List<&2, J.Json>:
  match qs:
    case Nil{}:
      Nil{}
    case M.QItem{+msg, +text} <> t:
      J.Json.obj([J.KV{"msg", J.Json.str(msg)}, J.KV{"text", J.Json.str(U.Qu.label(msg, text))}, J.KV{"tag", J.Json.str(U.Qu.tag(run, msg))},
        J.KV{"buttons", J.Json.arr(Mob.qbtns(U.Qu.row_buttons(run, first, msg)))}]) <> Mob.queue(t, False{}, run)

def Mob.thread(u: U.Ui, t: M.Thread, pend: List<&2, String>, vw: J.Json) -> J.Json:
  match u t:
    case U.Ui{+st, +sel, drafts, +live, _, _, _, _, _, _, _, _, _, _, +nf, _, _} M.Thread{+id, _, title, _, _, +turn, _, _, o, +sa, +ua, pinned, _, branch, _, +pr, +mo, _, _, _, _}:
      J.Json.obj([J.KV{"id", J.Json.str(id)}, J.KV{"title", J.Json.str(title)}, J.KV{"branch", J.Json.str(branch)},
        J.KV{"state", J.Json.str(Mob.state(turn))},
        J.KV{"tools", J.Json.arr(List.concat(&2, J.Json, [Mob.stop(V.View.running(turn)), [Mob.pin(pinned), Mob.settle(o, Nat.is_gt(sa, ua)), Mob.tool("Archive", "archive", False{}), Mob.tool("Fork", "fork", False{})], Bool.pick(List<&2, J.Json>, String.is_empty(M.Fork.source(st, id)), Nil{}, [Mob.tool("Bring back", "back", False{})])]))},
        J.KV{"entries", J.Json.arr(Mob.entries(V.View.mine(U.Ui.entries(st), id, Nil{})))},
        J.KV{"sending", J.Json.arr(Mob.strs(pend))},
        J.KV{"queued", J.Json.str(M.Queue.of(st, id))},
        J.KV{"queue", J.Json.arr(Mob.queue(M.Queue.items(st, id), True{}, V.View.running(turn)))},
        J.KV{"live", J.Json.arr(Mob.nodes(D.Md.render(U.Str.get(live, id))))},
        J.KV{"working", J.Json.str(Mob.live(String.is_empty(U.Str.get(live, id)), V.View.running(turn)))},
        J.KV{"draft", J.Json.str(U.Str.get(drafts, sel))},
        J.KV{"send", J.Json.str(U.Follow.label(st, sel, V.View.running(turn)))},
        J.KV{"picker", Mob.picker(U.Str.get(nf, "models"), pr, mo, U.Effort.of(st, sel))},
        J.KV{"viewer", vw}])

def Mob.main(none: Bool, +u: U.Ui, +sel: String) -> J.Json:
  match none:
    case True{}:
      J.Null{}
    case False{}:
      Mob.thread(u, U.Ui.thread(Mob.st(u), sel), U.Ui.pending(u, sel), VW.View.json(u))

def Mob.empty(n: Nat) -> String:
  Bool.pick(String, Nat.is_eq(n, 0n), "Add a project to start.", "Pick a thread, or start one in a project.")

def Mob.title(t: M.Thread) -> String:
  match t:
    case M.Thread{_, _, title, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      title

# a delete a row asked for, to confirm: its thread, what to ask, the
# buttons (the yes button sends "row-delete id" again, the no "delete-no")
def Mob.deleting.k(none: Bool, +st: M.State, +id: String) -> J.Json:
  match none:
    case True{}:
      J.Null{}
    case False{}:
      J.Json.obj([J.KV{"id", J.Json.str(id)}, J.KV{"title", J.Json.str("Delete thread?")},
        J.KV{"body", J.Json.str(Mob.title(U.Ui.thread(st, id)))}, J.KV{"yes", J.Json.str("Delete")}, J.KV{"no", J.Json.str("Cancel")}])

def Mob.deleting(+u: U.Ui) -> J.Json:
  Mob.deleting.k(String.is_empty(U.Ui.row_deleting(u)), Mob.st(u), U.Ui.row_deleting(u))

# the whole screen
def Mob.screen(+u: U.Ui) -> J.Json:
  match u:
    case U.Ui{+st, +sel, _, _, +o, +on, +now, _, _, +v, _, _, +e, +note, _, _, _}:
      J.Json.obj([J.KV{"online", J.Json.bool(on)}, J.KV{"version", J.Json.str(v)}, J.KV{"error", J.Json.str(e)},
        J.KV{"note", J.Json.str(note)}, J.KV{"sel", J.Json.str(sel)},
        J.KV{"empty", J.Json.str(Mob.empty(List.length(&2, M.Project, U.Ui.projects(st))))},
        J.KV{"projects", J.Json.arr(Mob.projects(U.Side.rows(st, now), o, st, now))},
        J.KV{"deleting", Mob.deleting(u)},
        J.KV{"folders", PK.MPick.json(u)},
        J.KV{"island", N.Note.island(U.Ui.threads(st), U.Ui.entries(st))},
        J.KV{"thread", Mob.main(String.is_empty(sel), u, sel)}])
