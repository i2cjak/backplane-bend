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
    error: String
  }

type Cmd is Data:
  Send{text: String}
  Copy{text: String}
  Focus{id: String}
  Scroll{}

type Act is Data:
  Act{ui: Ui, cmds: List<&2, Cmd>}

def Ui.init(now: Nat) -> Ui:
  Ui{M.State.empty(), "", Map.new(&2, String), Map.new(&2, String), Map.new(&2, Bool), False{}, now, False{}, False{}, "", 0n, False{}, ""}

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
    case M.State{_, ts, _, _}:
      Map.values(&2, M.Thread, ts)

def Ui.projects(s: M.State) -> List<&2, M.Project>:
  match s:
    case M.State{ps, _, _, _}:
      Map.values(&2, M.Project, ps)

def Ui.thread.k(r: Map<&2, M.Thread> & M.Thread) -> M.Thread:
  (_, t) = r
  t

def Ui.thread(s: M.State, +id: String) -> M.Thread:
  match s:
    case M.State{_, ts, _, _}:
      Ui.thread.k(Map.get(M.Thread, M.Thread.blank(id), ts, id))

def Ui.entries(s: M.State) -> List<&2, M.Entry>:
  match s:
    case M.State{_, _, es, _}:
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
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, True{}, er} M.ThreadCreated{+id, _, _, _, _, _, _, _, _}:
      Ui{st, id, dr, live, op, on, now, ad, pa, v, rid, False{}, er}
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er} M.MessagePosted{+thread, _, M.Assistant{}, _, _}:
      Ui{st, sel, dr, Map.set(&2, String, live, thread, ""), op, on, now, ad, pa, v, rid, w, er}
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er} M.TurnChanged{+thread, M.Completed{}, _}:
      Ui{st, sel, dr, Map.set(&2, String, live, thread, ""), op, on, now, ad, pa, v, rid, w, er}
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er} M.TurnChanged{+thread, M.Failed{}, _}:
      Ui{st, sel, dr, Map.set(&2, String, live, thread, ""), op, on, now, ad, pa, v, rid, w, er}
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er} M.TurnChanged{+thread, M.Interrupted{}, _}:
      Ui{st, sel, dr, Map.set(&2, String, live, thread, ""), op, on, now, ad, pa, v, rid, w, er}
    case _ _:
      u

def Ui.fold(cs: List<&2, M.Change>, u: Ui) -> Ui:
  match cs u:
    case Nil{} _:
      u
    case +c <> t Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er}:
      Ui.fold(t, Ui.see(Ui{M.State.apply(st, c), sel, dr, live, op, on, now, ad, pa, v, rid, w, er}, c))

def Ui.reset(u: Ui, +o: J.Json) -> Ui:
  match u:
    case Ui{_, sel, dr, live, op, _, now, ad, pa, _, rid, w, er}:
      Ui.fold(Ui.decode(J.Json.elems(J.Json.get_obj(o, "items"))),
        Ui{M.State.empty(), sel, dr, live, op, True{}, now, ad, pa, J.Json.get_str(o, "version", ""), rid, w, er})

def Ui.delta(u: Ui, +thread: String, text: String) -> Ui:
  match u:
    case Ui{st, sel, dr, +live, op, on, now, ad, pa, v, rid, w, er}:
      Ui{st, sel, dr, Map.set(&2, String, live, thread, Str.get(live, thread) ++ text), op, on, now, ad, pa, v, rid, w, er}

def Ui.reply(u: Ui, +o: J.Json) -> Ui:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, _}:
      Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, J.Json.get_str(o, "error", "")}

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
    case _:
      u

# a message from the server
def Ui.recv(u: Ui, +o: J.Json) -> Ui:
  Ui.recv.k(C.Codec.pos(["log", "changes", "delta", "reply"], J.Json.get_str(o, "t", "")), u, o)

def Ui.online(u: Ui, b: Bool) -> Ui:
  match u:
    case Ui{st, sel, dr, live, op, _, now, ad, pa, v, rid, w, er}:
      Ui{st, sel, dr, live, op, b, now, ad, pa, v, rid, w, er}

def Ui.tick(u: Ui, now: Nat) -> Ui:
  match u:
    case Ui{st, sel, dr, live, op, on, _, ad, pa, v, rid, w, er}:
      Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er}

# Acting
# ------

def Rpc.text(+rid: Nat, m: String, p: List<&2, J.KV>) -> String:
  J.Json.show(J.Json.obj([J.KV{"id", J.Num{Nat.show(rid)}}, J.KV{"m", J.Str{m}}, J.KV{"p", J.Json.obj(p)}]))

# send method m with params p, counting the request
def Ui.rpc(u: Ui, m: String, p: List<&2, J.KV>) -> Act:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, +rid, w, er}:
      Act{Ui{st, sel, dr, live, op, on, now, ad, pa, v, 1n+rid, w, er}, [Send{Rpc.text(rid, m, p)}]}

def Ui.on_thread(u: Ui, m: String) -> Act:
  match u:
    case Ui{st, +sel, dr, live, op, on, now, ad, pa, v, rid, w, er}:
      Ui.rpc(Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er}, m, [J.KV{"thread", J.Str{sel}}])

def Ui.select(u: Ui, +id: String) -> Act:
  match u:
    case Ui{st, _, dr, live, op, on, now, ad, pa, v, rid, w, er}:
      Act{Ui{st, id, dr, live, op, on, now, ad, pa, v, rid, w, er}, [Focus{"composer"}, Scroll{}]}

def Ui.draft(u: Ui, text: String) -> Act:
  match u:
    case Ui{st, +sel, dr, live, op, on, now, ad, pa, v, rid, w, er}:
      Act{Ui{st, sel, Map.set(&2, String, dr, sel, text), live, op, on, now, ad, pa, v, rid, w, er}, Nil{}}

def Ui.also(a: Act, more: List<&2, Cmd>) -> Act:
  match a:
    case Act{u, cs}:
      Act{u, List.append(&2, Cmd, cs, more)}

def Ui.send.k(empty: Bool, u: Ui, text: String) -> Act:
  match empty u:
    case True{} _:
      Act{u, Nil{}}
    case False{} Ui{st, +sel, dr, live, op, on, now, ad, pa, v, rid, w, er}:
      Ui.also(Ui.rpc(Ui{st, sel, Map.set(&2, String, dr, sel, ""), live, op, on, now, ad, pa, v, rid, w, er},
        "turn.start", [J.KV{"thread", J.Str{sel}}, J.KV{"text", J.Str{text}}]), [Scroll{}])

def Ui.send(u: Ui) -> Act:
  match u:
    case Ui{st, +sel, +dr, live, op, on, now, ad, pa, v, rid, w, er}:
      Ui.send.k(String.is_empty(String.trim(Str.get(dr, sel))), Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er}, String.trim(Str.get(dr, sel)))

def Ui.new_thread(u: Ui, +pid: String) -> Act:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, _, er}:
      Ui.rpc(Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, True{}, er}, "thread.create", [J.KV{"project", J.Str{pid}}, J.KV{"title", J.Str{"New thread"}}])

def Ui.add_project(u: Ui, +path: String) -> Act:
  match u:
    case Ui{st, sel, dr, live, op, on, now, _, pa, v, rid, w, er}:
      Ui.rpc(Ui{st, sel, dr, live, op, on, now, False{}, pa, v, rid, w, er}, "project.add", [J.KV{"path", J.Str{path}}])

def Ui.toggle_add(u: Ui) -> Act:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er}:
      Act{Ui{st, sel, dr, live, op, on, now, Bool.not(ad), pa, v, rid, w, er}, [Focus{"project-path"}]}

def Ui.toggle_panel(u: Ui) -> Act:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er}:
      Act{Ui{st, sel, dr, live, op, on, now, ad, Bool.not(pa), v, rid, w, er}, Nil{}}

def Ui.toggle_settled(u: Ui, +pid: String) -> Act:
  match u:
    case Ui{st, sel, dr, live, +op, on, now, ad, pa, v, rid, w, er}:
      Act{Ui{st, sel, dr, live, Map.set(&2, Bool, op, pid, Bool.not(Flag.get(op, pid))), on, now, ad, pa, v, rid, w, er}, Nil{}}

def Ui.dismiss(u: Ui) -> Act:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, _}:
      Act{Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, ""}, Nil{}}

def Ui.actions() -> List<&2, String>:
  ["select", "new-thread", "draft", "send", "add-project", "toggle-add", "settle", "unsettle",
   "pin", "unpin", "archive", "interrupt", "toggle-settled", "copy", "panel", "dismiss", "delete"]

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
    case _:
      Act{u, Nil{}}

# a user action with its value
def Ui.act(u: Ui, +action: String, +value: String) -> Act:
  Ui.act.k(C.Codec.pos(Ui.actions(), action), u, value)

# Reading the client state
# ------------------------

def Ui.sel(u: Ui) -> String:
  match u:
    case Ui{_, sel, _, _, _, _, _, _, _, _, _, _, _}:
      sel

# the selected thread's draft
def Ui.draft_text(u: Ui) -> String:
  match u:
    case Ui{_, +sel, drafts, _, _, _, _, _, _, _, _, _, _}:
      Str.get(drafts, sel)
