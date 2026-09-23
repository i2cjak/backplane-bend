import Base
import ./json.bend as J
import ./model.bend as M
import ./codec.bend as C

# The client state, Elm-style, shared by the native window and the web
# page: a host feeds server messages to Ui.recv and user actions to Ui.act,
# then draws the result. The read model is folded by the same State.apply
# the server uses (law replay_snoc), so what a client shows is exactly what
# the server stored.

type Ui is Data:
  Ui{
    st: M.State,
    sel: String,
    drafts: Map<&2, String>,
    live: Map<&2, String>,
    open: Map<&2, Bool>,
    online: Bool,
    now: Nat,
    adding: Bool,
    panel: Bool,
    version: String,
    rid: Nat,
    want_new: Bool,
    error: String,
    note: String,
    info: Map<&2, String>
  }

type Cmd is Data:
  Send{text: String}
  Copy{text: String}
  Focus{id: String}
  Scroll{}

type Act is Data:
  Act{ui: Ui, cmds: List<&2, Cmd>}

def Ui.init(now: Nat) -> Ui:
  Ui{M.State.empty(), "", Map.new(&2, String), Map.new(&2, String), Map.new(&2, Bool), False{}, now, False{}, False{}, "", 0n, False{}, "", "", Map.new(&2, String)}

def Str.get.k(r: Map<&2, String> & String) -> String:
  (_, v) = r
  v

# Lookups
# -------

def Str.get(m: Map<&2, String>, +k: String) -> String:
  Str.get.k(Map.get(String, "", m, k))

def Flag.get.k(r: Map<&2, Bool> & Bool) -> Bool:
  (_, v) = r
  v

def Flag.get(m: Map<&2, Bool>, +k: String) -> Bool:
  Flag.get.k(Map.get(Bool, False{}, m, k))

def Ui.threads(s: M.State) -> List<&2, M.Thread>:
  match s:
    case M.State{_, ts, _, _, _, _}:
      Map.values(&2, M.Thread, ts)

def Ui.projects(s: M.State) -> List<&2, M.Project>:
  match s:
    case M.State{ps, _, _, _, _, _}:
      Map.values(&2, M.Project, ps)

def Ui.thread.k(r: Map<&2, M.Thread> & M.Thread) -> M.Thread:
  (_, t) = r
  t

def Ui.thread(s: M.State, +id: String) -> M.Thread:
  match s:
    case M.State{_, ts, _, _, _, _}:
      Ui.thread.k(Map.get(M.Thread, M.Thread.blank(id), ts, id))

def Ui.entries(s: M.State) -> List<&2, M.Entry>:
  match s:
    case M.State{_, _, es, _, _, _}:
      es

# Time
# ----

def Time.ago.k(m: Bool, h: Bool, d: Bool, +s: Nat) -> String:
  match m h d:
    case True{} _ _:
      "now"
    case False{} True{} _:
      Nat.show(Nat.div(s, 60n)) ++ "m"
    case False{} False{} True{}:
      Nat.show(Nat.div(s, 3600n)) ++ "h"
    case False{} False{} False{}:
      Nat.show(Nat.div(s, 86400n)) ++ "d"

# "now", "5m", "3h", "2d"
def Time.ago(+now: Nat, +at: Nat) -> String:
  +s = Nat.sub(now, at)
  Time.ago.k(Nat.is_lt(s, 60n), Nat.is_lt(s, 3600n), Nat.is_lt(s, 86400n), s)

def Ui.decode.k(m: Maybe<&2, M.Change>, rest: List<&2, M.Change>) -> List<&2, M.Change>:
  match m:
    case Some{c}:
      c <> rest
    case None{}:
      rest

# Receiving
# ---------

def Ui.decode(xs: List<&2, J.Json>) -> List<&2, M.Change>:
  match xs:
    case Nil{}:
      Nil{}
    case +x <> t:
      Ui.decode.k(C.Change.decode(x), Ui.decode(t))

# what a change means for the page beyond the read model: a new thread we
# asked for gets selected; a finished reply ends its live text
def Ui.see(u: Ui, c: M.Change) -> Ui:
  match u c:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, True{}, er, note, nf} M.ThreadCreated{+id, _, _, _, _, _, _, _, _}:
      Ui{st, id, dr, live, op, on, now, ad, pa, v, rid, False{}, er, note, nf}
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf} M.MessagePosted{+thread, _, M.Assistant{}, _, _}:
      Ui{st, sel, dr, Map.set(&2, String, live, thread, ""), op, on, now, ad, pa, v, rid, w, er, note, nf}
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf} M.TurnChanged{+thread, M.Completed{}, _}:
      Ui{st, sel, dr, Map.set(&2, String, live, thread, ""), op, on, now, ad, pa, v, rid, w, er, note, nf}
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf} M.TurnChanged{+thread, M.Failed{}, _}:
      Ui{st, sel, dr, Map.set(&2, String, live, thread, ""), op, on, now, ad, pa, v, rid, w, er, note, nf}
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf} M.TurnChanged{+thread, M.Interrupted{}, _}:
      Ui{st, sel, dr, Map.set(&2, String, live, thread, ""), op, on, now, ad, pa, v, rid, w, er, note, nf}
    case _ _:
      u

def Ui.fold(cs: List<&2, M.Change>, u: Ui) -> Ui:
  match cs u:
    case Nil{} _:
      u
    case +c <> t Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf}:
      Ui.fold(t, Ui.see(Ui{M.State.apply(st, c), sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf}, c))

def Info.fields(fs: J.Json, m: Map<&2, String>) -> Map<&2, String>:
  match fs:
    case J.Field{k, J.Str{v}, t}:
      Info.fields(t, Map.set(&2, String, m, k, v))
    case J.Field{_, _, t}:
      Info.fields(t, m)
    case _:
      m

# the machine's info (strings only) from the log message
def Info.of(o: J.Json) -> Map<&2, String>:
  match o:
    case J.Obj{fs}:
      Info.fields(fs, Map.new(&2, String))
    case _:
      Map.new(&2, String)

def Ui.reset(u: Ui, +o: J.Json) -> Ui:
  match u:
    case Ui{_, sel, dr, live, op, _, now, ad, pa, _, rid, w, er, note, _}:
      Ui.fold(Ui.decode(J.Json.elems(J.Json.get_obj(o, "items"))),
        Ui{M.State.empty(), sel, dr, live, op, True{}, now, ad, pa, J.Json.get_str(o, "version", ""), rid, w, er, note, Info.of(J.Json.get_obj(o, "info"))})

def Ui.delta(u: Ui, +thread: String, text: String) -> Ui:
  match u:
    case Ui{st, sel, dr, +live, op, on, now, ad, pa, v, rid, w, er, note, nf}:
      Ui{st, sel, dr, Map.set(&2, String, live, thread, Str.get(live, thread) ++ text), op, on, now, ad, pa, v, rid, w, er, note, nf}

def Ui.reply(u: Ui, +o: J.Json) -> Ui:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, _, note, nf}:
      Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, J.Json.get_str(o, "error", ""), note, nf}

def Ui.update.note(+ver: String, +state: String) -> String:
  Bool.pick(String, String.is_empty(state), Bool.pick(String, String.is_empty(ver), "", "update " ++ ver), state)

# an update notice: a version to offer, or the progress of one being applied
def Ui.update(u: Ui, +o: J.Json) -> Ui:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, _, nf}:
      Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w,
        J.Json.get_str(o, "error", ""), Ui.update.note(J.Json.get_str(o, "version", ""), J.Json.get_str(o, "state", "")), nf}

# an agent asked to show a file: the viewer opens on it (view.n counts
# requests, so the same file asked for twice still comes to the front)
def Ui.view(u: Ui, +o: J.Json) -> Ui:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, _, v, rid, w, er, note, +nf}:
      Ui{st, sel, dr, live, op, on, now, ad, True{}, v, rid, w, er, note,
        Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, nf, "view.path", J.Json.get_str(o, "path", "")), "view.kind", J.Json.get_str(o, "kind", "")),
          "view.n", Nat.show(1n+Maybe.default(&2, Nat, Nat.read(Str.get(nf, "view.n")), 0n)))}

def Ui.recv.k(i: Nat, u: Ui, +o: J.Json) -> Ui:
  match i:
    case 0n:
      Ui.reset(u, o)
    case 1n:
      Ui.fold(Ui.decode(J.Json.elems(J.Json.get_obj(o, "items"))), u)
    case 2n:
      Ui.delta(u, J.Json.get_str(o, "thread", ""), J.Json.get_str(o, "text", ""))
    case 3n:
      Ui.reply(u, o)
    case 4n:
      Ui.update(u, o)
    case 5n:
      Ui.view(u, o)
    case _:
      u

# a message from the server
def Ui.recv(u: Ui, +o: J.Json) -> Ui:
  Ui.recv.k(C.Codec.pos(["log", "changes", "delta", "reply", "update", "view"], J.Json.get_str(o, "t", "")), u, o)

def Ui.online(u: Ui, b: Bool) -> Ui:
  match u:
    case Ui{st, sel, dr, live, op, _, now, ad, pa, v, rid, w, er, note, nf}:
      Ui{st, sel, dr, live, op, b, now, ad, pa, v, rid, w, er, note, nf}

def Ui.tick(u: Ui, now: Nat) -> Ui:
  match u:
    case Ui{st, sel, dr, live, op, on, _, ad, pa, v, rid, w, er, note, nf}:
      Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf}

# Acting
# ------

def Rpc.text(+rid: Nat, m: String, p: List<&2, J.KV>) -> String:
  J.Json.show(J.Json.obj([J.KV{"id", J.Num{Nat.show(rid)}}, J.KV{"m", J.Str{m}}, J.KV{"p", J.Json.obj(p)}]))

# send method m with params p, counting the request
def Ui.rpc(u: Ui, m: String, p: List<&2, J.KV>) -> Act:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, +rid, w, er, note, nf}:
      Act{Ui{st, sel, dr, live, op, on, now, ad, pa, v, 1n+rid, w, er, note, nf}, [Send{Rpc.text(rid, m, p)}]}

def Ui.on_thread(u: Ui, m: String) -> Act:
  match u:
    case Ui{st, +sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf}:
      Ui.rpc(Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf}, m, [J.KV{"thread", J.Str{sel}}])

def Ui.select(u: Ui, +id: String) -> Act:
  match u:
    case Ui{st, _, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf}:
      Act{Ui{st, id, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf}, [Focus{"composer"}, Scroll{}]}

def Ui.draft(u: Ui, text: String) -> Act:
  match u:
    case Ui{st, +sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf}:
      Act{Ui{st, sel, Map.set(&2, String, dr, sel, text), live, op, on, now, ad, pa, v, rid, w, er, note, nf}, Nil{}}

def Ui.also(a: Act, more: List<&2, Cmd>) -> Act:
  match a:
    case Act{u, cs}:
      Act{u, List.append(&2, Cmd, cs, more)}

def Ui.send.k(empty: Bool, u: Ui, text: String) -> Act:
  match empty u:
    case True{} _:
      Act{u, Nil{}}
    case False{} Ui{st, +sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf}:
      Ui.also(Ui.rpc(Ui{st, sel, Map.set(&2, String, dr, sel, ""), live, op, on, now, ad, pa, v, rid, w, er, note, nf},
        "turn.start", [J.KV{"thread", J.Str{sel}}, J.KV{"text", J.Str{text}}]), [Scroll{}])

def Ui.send(u: Ui) -> Act:
  match u:
    case Ui{st, +sel, +dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf}:
      Ui.send.k(String.is_empty(String.trim(Str.get(dr, sel))), Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf}, String.trim(Str.get(dr, sel)))

def Ui.new_thread(u: Ui, +pid: String) -> Act:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, _, er, note, nf}:
      Ui.rpc(Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, True{}, er, note, nf}, "thread.create", [J.KV{"project", J.Str{pid}}, J.KV{"title", J.Str{"New thread"}}])

def Ui.add_project(u: Ui, +path: String) -> Act:
  match u:
    case Ui{st, sel, dr, live, op, on, now, _, pa, v, rid, w, er, note, nf}:
      Ui.rpc(Ui{st, sel, dr, live, op, on, now, False{}, pa, v, rid, w, er, note, nf}, "project.add", [J.KV{"path", J.Str{path}}])

def Ui.toggle_add(u: Ui) -> Act:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf}:
      Act{Ui{st, sel, dr, live, op, on, now, Bool.not(ad), pa, v, rid, w, er, note, nf}, [Focus{"project-path"}]}

def Ui.toggle_panel(u: Ui) -> Act:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf}:
      Act{Ui{st, sel, dr, live, op, on, now, ad, Bool.not(pa), v, rid, w, er, note, nf}, Nil{}}

def Ui.toggle_settled(u: Ui, +pid: String) -> Act:
  match u:
    case Ui{st, sel, dr, live, +op, on, now, ad, pa, v, rid, w, er, note, nf}:
      Act{Ui{st, sel, dr, live, Map.set(&2, Bool, op, pid, Bool.not(Flag.get(op, pid))), on, now, ad, pa, v, rid, w, er, note, nf}, Nil{}}

def Ui.setting.k(ps: List<&2, String>) -> List<&2, J.KV>:
  match ps:
    case k <> t:
      [J.KV{"key", J.Str{k}}, J.KV{"value", J.Str{String.join(t, "=")}}]
    case Nil{}:
      Nil{}

# "key=value" -> setting.set
def Ui.setting(u: Ui, kv: String) -> Act:
  Ui.rpc(u, "setting.set", Ui.setting.k(String.split(kv, '=')))

def Ui.close(u: Ui, +key: String) -> Ui:
  match u:
    case Ui{st, sel, dr, live, +op, on, now, ad, pa, v, rid, w, er, note, nf}:
      Ui{st, sel, dr, live, Map.set(&2, Bool, op, key, False{}), on, now, ad, pa, v, rid, w, er, note, nf}

# the selected thread's model (the picker closes)
def Ui.model(u: Ui, +model: String) -> Act:
  match u:
    case Ui{st, +sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf}:
      Ui.rpc(Ui.close(Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf}, "models"), "thread.modes", [J.KV{"thread", J.Str{sel}}, J.KV{"model", J.Str{model}}])

def Ui.info(u: Ui, +k: String) -> String:
  match u:
    case Ui{_, _, _, _, _, _, _, _, _, _, _, _, _, _, nf}:
      Str.get(nf, k)

def Ui.flag(u: Ui, +k: String) -> Bool:
  match u:
    case Ui{_, _, _, _, op, _, _, _, _, _, _, _, _, _, _}:
      Flag.get(op, k)

def Ui.dismiss(u: Ui) -> Act:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, _, note, nf}:
      Act{Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, "", note, nf}, Nil{}}

def Ui.actions() -> List<&2, String>:
  ["select", "new-thread", "draft", "send", "add-project", "toggle-add", "settle", "unsettle",
   "pin", "unpin", "archive", "interrupt", "toggle-settled", "copy", "panel", "dismiss", "delete", "update",
   "flag", "setting", "model", "kicad-install"]

def Ui.act.k(i: Nat, u: Ui, +value: String) -> Act:
  match i:
    case 0n:
      Ui.select(u, value)
    case 1n:
      Ui.new_thread(u, value)
    case 2n:
      Ui.draft(u, value)
    case 3n:
      Ui.send(u)
    case 4n:
      Ui.add_project(u, value)
    case 5n:
      Ui.toggle_add(u)
    case 6n:
      Ui.on_thread(u, "thread.settle")
    case 7n:
      Ui.on_thread(u, "thread.unsettle")
    case 8n:
      Ui.on_thread(u, "thread.pin")
    case 9n:
      Ui.on_thread(u, "thread.unpin")
    case 10n:
      Ui.on_thread(u, "thread.archive")
    case 11n:
      Ui.on_thread(u, "turn.interrupt")
    case 12n:
      Ui.toggle_settled(u, value)
    case 13n:
      Act{u, [Copy{value}]}
    case 14n:
      Ui.toggle_panel(u)
    case 15n:
      Ui.dismiss(u)
    case 16n:
      Ui.on_thread(u, "thread.delete")
    case 17n:
      Ui.rpc(u, "app.update", Nil{})
    case 18n:
      Ui.toggle_settled(u, value)
    case 19n:
      Ui.setting(u, value)
    case 20n:
      Ui.model(u, value)
    case 21n:
      Ui.rpc(u, "kicad.install", Nil{})
    case _:
      Act{u, Nil{}}

# a user action with its value
def Ui.act(u: Ui, +action: String, +value: String) -> Act:
  Ui.act.k(C.Codec.pos(Ui.actions(), action), u, value)

# Reading the client state
# ------------------------

def Ui.sel(u: Ui) -> String:
  match u:
    case Ui{_, sel, _, _, _, _, _, _, _, _, _, _, _, _, nf}:
      sel

# the selected thread's draft
def Ui.draft_text(u: Ui) -> String:
  match u:
    case Ui{_, +sel, drafts, _, _, _, _, _, _, _, _, _, _, _, nf}:
      Str.get(drafts, sel)

def Ui.project_root.k(r: Map<&2, M.Project> & M.Project) -> String:
  (_, p) = r
  match p:
    case M.Project{_, _, root, _, _}:
      root

def Ui.project_root(s: M.State, +id: String) -> String:
  match s:
    case M.State{ps, _, _, _, _, _}:
      Ui.project_root.k(Map.get(M.Project, M.Project.blank(id), ps, id))

def Ui.thread_project(t: M.Thread) -> String:
  match t:
    case M.Thread{_, p, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      p

# the selected thread's project directory ("" with nothing selected)
def Ui.root(u: Ui) -> String:
  match u:
    case Ui{+st, +sel, _, _, _, _, _, _, _, _, _, _, _, _, nf}:
      Bool.pick(String, String.is_empty(sel), "", Ui.project_root(st, Ui.thread_project(Ui.thread(st, sel))))

# Views both clients share
# ------------------------
# Delegated child threads live under their parent, not in the sidebar; a
# thread lists the tasks it delegated; the model list comes from the
# machine's info ({"provider": [model, ...]}).

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
      Kids.keep.k(Flag.get(kids, id), M.Thread{id, p, ti, c, a, tu, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de}, Kids.keep(t, kids))

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

def Tasks.of(s: M.State, +parent: String) -> List<&2, M.Task>:
  match s:
    case M.State{_, _, _, _, tk, _}:
      Tasks.mine(Map.values(&2, M.Task, tk), parent)

def Tasks.title.k(t: M.Thread) -> String:
  match t:
    case M.Thread{_, _, ti, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      ti

def Tasks.title(s: M.State, +id: String) -> String:
  Tasks.title.k(Ui.thread(s, id))

def Tasks.parent.find(ts: List<&2, M.Task>, +thread: String) -> String:
  match ts:
    case Nil{}:
      ""
    case M.Task{_, p, +c, _, _, _, _, _, _} <> t:
      Bool.pick(String, String.eq(c, thread), p, Tasks.parent.find(t, thread))

def Tasks.parent(+st: M.State, +thread: String) -> String:
  match st:
    case M.State{_, _, _, _, tk, _}:
      Tasks.parent.find(Map.values(&2, M.Task, tk), thread)

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
