import Base
import ./json.bend as J
import ./model.bend as M
import ./codec.bend as C
import ./vt.bend as VT
import ./fuzzy.bend as FZ

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
    info: Map<&2, String>,
    outbox: Map<&2, String>,
    terms: Map<&2, VT.Vt>
  }

type Cmd is Data:
  Send{text: String}
  Copy{text: String}
  Focus{id: String}
  Scroll{}

type Act is Data:
  Act{ui: Ui, cmds: List<&2, Cmd>}

def Ui.init(now: Nat) -> Ui:
  Ui{M.State.empty(), "", Map.new(&2, String), Map.new(&2, String), Map.new(&2, Bool), False{}, now, False{}, False{}, "", 0n, False{}, "", "", Map.new(&2, String), Map.new(&2, String), Map.new(&2, VT.Vt)}

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
    case M.State{_, ts, _, _, _, _, _, _, _}:
      Map.values(&2, M.Thread, ts)

def Ui.projects(s: M.State) -> List<&2, M.Project>:
  match s:
    case M.State{ps, _, _, _, _, _, _, _, _}:
      Map.values(&2, M.Project, ps)

def Ui.thread.k(r: Map<&2, M.Thread> & M.Thread) -> M.Thread:
  (_, t) = r
  t

def Ui.thread(s: M.State, +id: String) -> M.Thread:
  match s:
    case M.State{_, ts, _, _, _, _, _, _, _}:
      Ui.thread.k(Map.get(M.Thread, M.Thread.blank(id), ts, id))

def Ui.entries(s: M.State) -> List<&2, M.Entry>:
  match s:
    case M.State{_, _, es, _, _, _, _, _, _}:
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
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, True{}, er, note, nf, ob, tr} M.ThreadCreated{+id, _, _, _, _, _, _, _, _}:
      Ui{st, id, dr, live, op, on, now, ad, pa, v, rid, False{}, er, note, nf, ob, tr}
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr} M.MessagePosted{+thread, _, M.Assistant{}, _, _}:
      Ui{st, sel, dr, Map.set(&2, String, live, thread, ""), op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr} M.TurnChanged{+thread, M.Completed{}, _}:
      Ui{st, sel, dr, Map.set(&2, String, live, thread, ""), op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr} M.TurnChanged{+thread, M.Failed{}, _}:
      Ui{st, sel, dr, Map.set(&2, String, live, thread, ""), op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr} M.TurnChanged{+thread, M.Interrupted{}, _}:
      Ui{st, sel, dr, Map.set(&2, String, live, thread, ""), op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}
    case _ _:
      u

def Ui.fold(cs: List<&2, M.Change>, u: Ui) -> Ui:
  match cs u:
    case Nil{} _:
      u
    case +c <> t Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}:
      Ui.fold(t, Ui.see(Ui{M.State.apply(st, c), sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}, c))

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

def Ui.base(resume: Bool, st: M.State) -> M.State:
  match resume:
    case True{}:
      st
    case False{}:
      M.State.empty()

# the server's log on (re)connect: from nothing, or, when it says `since`
# (the client already has that many changes), just what was missed; the
# client's id survives the machine info being replaced
def Ui.reset(u: Ui, +o: J.Json) -> Ui:
  match u:
    case Ui{st, sel, dr, live, op, _, now, ad, pa, _, rid, w, er, note, +nf, ob, tr}:
      Ui.fold(Ui.decode(J.Json.elems(J.Json.get_obj(o, "items"))),
        Ui{Ui.base(Nat.is_gt(J.Json.get_nat(o, "since", 0n), 0n), st), sel, dr, live, op, True{}, now, ad, pa, J.Json.get_str(o, "version", ""), rid, w, er, note,
          Map.set(&2, String, Map.set(&2, String, Info.of(J.Json.get_obj(o, "info")), "cid", Str.get(nf, "cid")), "origin", J.Json.get_str(o, "origin", "")), ob, tr})

# how many changes this client holds (a reconnect asks for the rest)
def Ui.seq(u: Ui) -> Nat:
  match u:
    case Ui{st, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, tr}:
      M.State.seq(st)

def Ui.delta(u: Ui, +thread: String, text: String) -> Ui:
  match u:
    case Ui{st, sel, dr, +live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}:
      Ui{st, sel, dr, Map.set(&2, String, live, thread, Str.get(live, thread) ++ text), op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}

# a failed request shows its error, or the text of a failed git step
def Ui.reply.err(+o: J.Json) -> String:
  Bool.pick(String, J.Json.get_bool(o, "ok", True{}), "", J.Json.get_str(o, "error", String.take(J.Json.get_str(J.Json.get_obj(o, "result"), "text", "failed"), 200n)))

# an answer: its request leaves the outbox
def Ui.reply.k(u: Ui, +o: J.Json) -> Ui:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, _, note, nf, ob, tr}:
      Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, Ui.reply.err(o), note, nf, Map.set(&2, String, ob, J.Json.as_raw(J.Json.get(o, "id"), ""), ""), tr}

def Ui.diff(u: Ui, +r: J.Json) -> Ui:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, _, v, rid, w, er, note, +nf, ob, tr}:
      Ui{st, sel, dr, live, op, on, now, ad, True{}, v, rid, w, er, note,
        Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, nf, "diff", J.Json.get_str(r, "diff", "")), "view.kind", "diff"), "view.path", ""),
          "view.n", Nat.show(1n+Maybe.default(&2, Nat, Nat.read(Str.get(nf, "view.n")), 0n))), ob, tr}

def Ui.reply.diff(has: Bool, u: Ui, +o: J.Json) -> Ui:
  match has:
    case True{}:
      Ui.diff(Ui.reply.k(u, o), J.Json.get_obj(o, "result"))
    case False{}:
      Ui.reply.k(u, o)

def Ui.reply.dispatch(u: Ui, +o: J.Json) -> Ui:
  Ui.reply.diff(Bool.not(String.eq(J.Json.show(Maybe.default(&2, J.Json, J.Json.get(J.Json.get_obj(o, "result"), "diff"), J.Null{})), "null")), u, o)

def Ui.update.note(+ver: String, +state: String) -> String:
  Bool.pick(String, String.is_empty(state), Bool.pick(String, String.is_empty(ver), "", "update " ++ ver), state)

# an update notice: a version to offer, or the progress of one being applied
def Ui.update(u: Ui, +o: J.Json) -> Ui:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, _, nf, ob, tr}:
      Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w,
        J.Json.get_str(o, "error", ""), Ui.update.note(J.Json.get_str(o, "version", ""), J.Json.get_str(o, "state", "")), nf, ob, tr}

# an agent asked to show a file: the viewer opens on it (view.n counts
# requests, so the same file asked for twice still comes to the front)
def Ui.view(u: Ui, +o: J.Json) -> Ui:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, _, v, rid, w, er, note, +nf, ob, tr}:
      Ui{st, sel, dr, live, op, on, now, ad, True{}, v, rid, w, er, note,
        Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, nf, "view.path", J.Json.get_str(o, "path", "")), "view.kind", J.Json.get_str(o, "kind", "")),
          "view.n", Nat.show(1n+Maybe.default(&2, Nat, Nat.read(Str.get(nf, "view.n")), 0n))), ob, tr}

def Out.resend.k(skip: Bool, x: String, rest: List<&2, Cmd>) -> List<&2, Cmd>:
  match skip:
    case True{}:
      rest
    case False{}:
      Send{x} <> rest

def Out.resend(xs: List<&2, String>) -> List<&2, Cmd>:
  match xs:
    case Nil{}:
      Nil{}
    case +x <> t:
      Out.resend.k(String.is_empty(x), x, Out.resend(t))

# what the outbox still holds, to send again
def Ui.outbox(u: Ui) -> List<&2, Cmd>:
  match u:
    case Ui{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, ob, tr}:
      Out.resend(Map.values(&2, String, ob))

def Ui.recv_act.k(connected: Bool, +u: Ui) -> Act:
  Act{u, Bool.pick(List<&2, Cmd>, connected, Ui.outbox(u), Nil{})}

# the client's own id (a host sets it once at start)
def Ui.set_cid(u: Ui, +cid: String) -> Ui:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}:
      Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, Map.set(&2, String, nf, "cid", cid), ob, tr}

def Pending.stored(es: List<&2, M.Entry>, +id: String) -> Bool:
  match es:
    case Nil{}:
      False{}
    case M.Msg{i, _, _, _, _} <> t:
      Bool.or(String.eq(i, id), Pending.stored(t, id))
    case M.Act{_, _, _, _, _, _} <> t:
      Pending.stored(t, id)

def Pending.one.k(+p: J.Json, +thread: String, +es: List<&2, M.Entry>) -> List<&2, String>:
  Bool.pick(List<&2, String>, Bool.and(String.eq(J.Json.get_str(p, "thread", ""), thread), Bool.not(Pending.stored(es, J.Json.get_str(p, "msg", "")))),
    [J.Json.get_str(p, "text", "")], Nil{})

# texts sent to a thread and not yet stored by the server, oldest first
def Pending.one(+x: String, +thread: String, +es: List<&2, M.Entry>) -> List<&2, String>:
  Pending.one.k(J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(x), J.Null{}), "p"), thread, es)

def Pending.go(xs: List<&2, String>, +thread: String, +es: List<&2, M.Entry>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case +x <> t:
      List.append(&2, String, Bool.pick(List<&2, String>, String.is_empty(x), Nil{}, Pending.one(x, thread, es)), Pending.go(t, thread, es))

def Ui.pending(u: Ui, +thread: String) -> List<&2, String>:
  match u:
    case Ui{st, _, _, _, _, _, _, _, _, _, _, _, _, _, _, ob, tr}:
      Pending.go(Map.values(&2, String, ob), thread, Ui.entries(st))

def Ui.online(u: Ui, b: Bool) -> Ui:
  match u:
    case Ui{st, sel, dr, live, op, _, now, ad, pa, v, rid, w, er, note, nf, ob, tr}:
      Ui{st, sel, dr, live, op, b, now, ad, pa, v, rid, w, er, note, nf, ob, tr}

def Ui.tick(u: Ui, now: Nat) -> Ui:
  match u:
    case Ui{st, sel, dr, live, op, on, _, ad, pa, v, rid, w, er, note, nf, ob, tr}:
      Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}

# Acting
# ------

def Rpc.text(+rid: Nat, m: String, p: List<&2, J.KV>) -> String:
  J.Json.show(J.Json.obj([J.KV{"id", J.Num{Nat.show(rid)}}, J.KV{"m", J.Str{m}}, J.KV{"p", J.Json.obj(p)}]))

# send method m with params p, counting the request
# an rpc that must reach the server: kept in the outbox, sent again on
# every reconnect, until the server answers it
def Ui.rpc.keep(u: Ui, +m: String, +p: List<&2, J.KV>) -> Act:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, +rid, w, er, note, nf, +ob, tr}:
      Act{Ui{st, sel, dr, live, op, on, now, ad, pa, v, 1n+rid, w, er, note, nf, Map.set(&2, String, ob, Nat.show(rid), Rpc.text(rid, m, p)), tr}, [Send{Rpc.text(rid, m, p)}]}

def Ui.rpc(u: Ui, m: String, p: List<&2, J.KV>) -> Act:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, +rid, w, er, note, nf, ob, tr}:
      Act{Ui{st, sel, dr, live, op, on, now, ad, pa, v, 1n+rid, w, er, note, nf, ob, tr}, [Send{Rpc.text(rid, m, p)}]}

# a request about the selected thread, with more params
def Ui.on_thread.p(u: Ui, m: String, p: List<&2, J.KV>) -> Act:
  match u:
    case Ui{st, +sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}:
      Ui.rpc(Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}, m, J.KV{"thread", J.Str{sel}} <> p)

def Ui.on_thread(u: Ui, m: String) -> Act:
  match u:
    case Ui{st, +sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}:
      Ui.rpc(Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}, m, [J.KV{"thread", J.Str{sel}}])

def Ui.select(u: Ui, +id: String) -> Act:
  match u:
    case Ui{st, _, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}:
      Act{Ui{st, id, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}, [Focus{"composer"}, Scroll{}]}

def Ui.draft(u: Ui, text: String) -> Act:
  match u:
    case Ui{st, +sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}:
      Act{Ui{st, sel, Map.set(&2, String, dr, sel, text), live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}, Nil{}}

def Ui.also(a: Act, more: List<&2, Cmd>) -> Act:
  match a:
    case Act{u, cs}:
      Act{u, List.append(&2, Cmd, cs, more)}

# a message's id, made here so a resend is recognised: this client, the
# second and the request number
def Ui.msg_id(+cid: String, +now: Nat, +rid: Nat) -> String:
  "c" ++ cid ++ Nat.show(now) ++ "-" ++ Nat.show(rid)

def Ui.send.k(empty: Bool, u: Ui, text: String) -> Act:
  match empty u:
    case True{} _:
      Act{u, Nil{}}
    case False{} Ui{st, +sel, dr, live, op, on, +now, ad, pa, v, +rid, w, er, note, +nf, ob, tr}:
      Ui.also(Ui.rpc.keep(Ui{st, sel, Map.set(&2, String, dr, sel, ""), live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr},
        "turn.start", [J.KV{"thread", J.Str{sel}}, J.KV{"text", J.Str{text}}, J.KV{"msg", J.Str{Ui.msg_id(Str.get(nf, "cid"), now, rid)}}]), [Scroll{}])

def Ui.send(u: Ui) -> Act:
  match u:
    case Ui{st, +sel, +dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}:
      Ui.send.k(String.is_empty(String.trim(Str.get(dr, sel))), Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}, String.trim(Str.get(dr, sel)))

def Ui.new_thread(u: Ui, +pid: String) -> Act:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, _, er, note, nf, ob, tr}:
      Ui.rpc(Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, True{}, er, note, nf, ob, tr}, "thread.create", [J.KV{"project", J.Str{pid}}, J.KV{"title", J.Str{"New thread"}}])

def Ui.add_project(u: Ui, +path: String) -> Act:
  match u:
    case Ui{st, sel, dr, live, op, on, now, _, pa, v, rid, w, er, note, nf, ob, tr}:
      Ui.rpc(Ui{st, sel, dr, live, op, on, now, False{}, pa, v, rid, w, er, note, nf, ob, tr}, "project.add", [J.KV{"path", J.Str{path}}])

def Ui.toggle_add(u: Ui) -> Act:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}:
      Act{Ui{st, sel, dr, live, op, on, now, Bool.not(ad), pa, v, rid, w, er, note, nf, ob, tr}, [Focus{"project-path"}]}

def Ui.toggle_panel(u: Ui) -> Act:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}:
      Act{Ui{st, sel, dr, live, op, on, now, ad, Bool.not(pa), v, rid, w, er, note, nf, ob, tr}, Nil{}}

def Ui.toggle_settled(u: Ui, +pid: String) -> Act:
  match u:
    case Ui{st, sel, dr, live, +op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}:
      Act{Ui{st, sel, dr, live, Map.set(&2, Bool, op, pid, Bool.not(Flag.get(op, pid))), on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}, Nil{}}

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
    case Ui{st, sel, dr, live, +op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}:
      Ui{st, sel, dr, live, Map.set(&2, Bool, op, key, False{}), on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}

# the selected thread's model (the picker closes)
def Ui.model(u: Ui, +model: String) -> Act:
  match u:
    case Ui{st, +sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}:
      Ui.rpc(Ui.close(Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}, "models"), "thread.modes", [J.KV{"thread", J.Str{sel}}, J.KV{"model", J.Str{model}}])

def Ui.info(u: Ui, +k: String) -> String:
  match u:
    case Ui{_, _, _, _, _, _, _, _, _, _, _, _, _, _, nf, ob, tr}:
      Str.get(nf, k)

def Ui.flag(u: Ui, +k: String) -> Bool:
  match u:
    case Ui{_, _, _, _, op, _, _, _, _, _, _, _, _, _, _, ob, tr}:
      Flag.get(op, k)

def Ui.dismiss(u: Ui) -> Act:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, _, note, nf, ob, tr}:
      Act{Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, "", note, nf, ob, tr}, Nil{}}

def Ui.actions() -> List<&2, String>:
  ["select", "new-thread", "draft", "send", "add-project", "toggle-add", "settle", "unsettle",
   "pin", "unpin", "archive", "interrupt", "toggle-settled", "copy", "panel", "dismiss", "delete", "update",
   "flag", "setting", "model", "kicad-install", "answer", "git", "diff", "revert", "proj-open", "proj-cd", "proj-add", "proj-mkdir", "proj-q", "proj-close", "proj-enter"]

# Reading the client state
# ------------------------

def Ui.sel(u: Ui) -> String:
  match u:
    case Ui{_, sel, _, _, _, _, _, _, _, _, _, _, _, _, nf, ob, tr}:
      sel

# the selected thread's draft
def Ui.draft_text(u: Ui) -> String:
  match u:
    case Ui{_, +sel, drafts, _, _, _, _, _, _, _, _, _, _, _, nf, ob, tr}:
      Str.get(drafts, sel)

def Ui.project_root.k(r: Map<&2, M.Project> & M.Project) -> String:
  (_, p) = r
  match p:
    case M.Project{_, _, root, _, _}:
      root

def Ui.project_root(s: M.State, +id: String) -> String:
  match s:
    case M.State{ps, _, _, _, _, _, _, _, _}:
      Ui.project_root.k(Map.get(M.Project, M.Project.blank(id), ps, id))

def Ui.thread_project(t: M.Thread) -> String:
  match t:
    case M.Thread{_, p, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      p

# the selected thread's project directory ("" with nothing selected)
def Ui.root(u: Ui) -> String:
  match u:
    case Ui{+st, +sel, _, _, _, _, _, _, _, _, _, _, _, _, nf, ob, tr}:
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
    case M.State{_, _, _, _, tk, _, _, _, _}:
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
    case M.State{_, _, _, _, tk, _, _, _, _}:
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
    case M.State{_, _, _, _, tk, _, _, _, _}:
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

# Asks
# ----

# "askid|answer" -> ask.answer
def Ui.answer.k(ps: List<&2, String>) -> List<&2, J.KV>:
  match ps:
    case id <> t:
      [J.KV{"id", J.Str{id}}, J.KV{"answer", J.Str{String.join(t, "|")}}]
    case Nil{}:
      Nil{}

def Ui.answer(u: Ui, v: String) -> Act:
  Ui.rpc(u, "ask.answer", Ui.answer.k(String.split(v, '|')))

def Asks.open.k(keep: Bool, a: M.Ask, rest: List<&2, M.Ask>) -> List<&2, M.Ask>:
  match keep:
    case True{}:
      a <> rest
    case False{}:
      rest

def Asks.open.go(as: List<&2, M.Ask>, +thread: String) -> List<&2, M.Ask>:
  match as:
    case Nil{}:
      Nil{}
    case M.Ask{i, +th, k, t, d, o, +op, an} <> rest:
      Asks.open.k(Bool.and(op, String.eq(th, thread)), M.Ask{i, th, k, t, d, o, op, an}, Asks.open.go(rest, thread))

# what a thread's agent waits on the user for
def Asks.open(s: M.State, +thread: String) -> List<&2, M.Ask>:
  Asks.open.go(M.Asks.all(s), thread)

# the sidebar marks a thread that waits on the user
def Asks.waiting(s: M.State, +thread: String) -> Bool:
  Bool.not(List.is_empty(&2, M.Ask, Asks.open(s, thread)))

# Links between threads
# ---------------------

type Link2 is Data:
  Link2{from: String, to: String, at: Nat}

def Links.recent.k(keep: Bool, +from: String, +to: String, +at: Nat, rest: List<&2, Link2>) -> List<&2, Link2>:
  match keep:
    case True{}:
      Link2{from, to, at} <> rest
    case False{}:
      rest

def Links.recent.go(es: List<&2, M.Entry>, +now: Nat) -> List<&2, Link2>:
  match es:
    case Nil{}:
      Nil{}
    case M.Msg{+id, +to, _, _, +at} <> t:
      Links.recent.k(Bool.and(Bool.not(String.is_empty(M.Link.from(id))), Nat.is_le(now, Nat.add(at, 900n))), M.Link.from(id), to, at, Links.recent.go(t, now))
    case M.Act{_, _, _, _, _, _} <> t:
      Links.recent.go(t, now)

# messages between threads in the last 15 minutes (the sidebar draws them)
def Links.recent(s: M.State, +now: Nat) -> List<&2, Link2>:
  Links.recent.go(Ui.entries(s), now)

# Terminals
# ---------
# Each thread's terminal screen is folded here from the shell's output (the
# same bytes reach every client, so every client's screen agrees).

def Term.bytes(xs: List<&2, J.Json>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case +x <> t:
      U32.from_nat(Maybe.default(&2, Nat, Nat.read(J.Json.as_raw(Some{x}, "0")), 0n)) <> Term.bytes(t)

def Term.nums(bs: List<&2, U32>) -> List<&2, J.Json>:
  match bs:
    case Nil{}:
      Nil{}
    case b <> t:
      J.Num{U32.show(b)} <> Term.nums(t)

def Term.get.k(r: Map<&2, VT.Vt> & VT.Vt) -> VT.Vt:
  (_, v) = r
  v

# a thread's screen (a blank 100x24 one before its shell spoke)
def Term.get(+m: Map<&2, VT.Vt>, +thread: String) -> VT.Vt:
  Term.get.k(Map.get(VT.Vt, VT.Vt.new(100, 24), m, thread))

def Ui.term(u: Ui, +thread: String) -> VT.Vt:
  match u:
    case Ui{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, tr}:
      Term.get(tr, thread)

def Ui.term_set(u: Ui, +thread: String, v: VT.Vt) -> Ui:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, ve, rid, w, er, note, nf, ob, tr}:
      Ui{st, sel, dr, live, op, on, now, ad, pa, ve, rid, w, er, note, nf, ob, Map.set(&2, VT.Vt, tr, thread, v)}

def Ui.term_feed(u: Ui, +thread: String, bs: List<&2, U32>) -> Ui:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, ve, rid, w, er, note, nf, ob, +tr}:
      Ui{st, sel, dr, live, op, on, now, ad, pa, ve, rid, w, er, note, nf, ob, Map.set(&2, VT.Vt, tr, thread, VT.Vt.feed(Term.get(tr, thread), bs))}

def Ui.term_replies.k(none: Bool, +u: Ui, +thread: String, +bs: List<&2, U32>, cs: List<&2, Cmd>) -> Act:
  match none:
    case True{}:
      Act{u, cs}
    case False{}:
      Ui.also(Ui.rpc(Ui.term_set(u, thread, VT.Vt.drain(Ui.term(u, thread))), "term.input", [J.KV{"thread", J.Str{thread}}, J.KV{"b", J.Json.arr(Term.nums(bs))}]), cs)

def Ui.term_replies(+u: Ui, +thread: String, cs: List<&2, Cmd>) -> Act:
  Ui.term_replies.k(List.is_empty(&2, U32, VT.Vt.replies(Ui.term(u, thread))), u, thread, VT.Vt.replies(Ui.term(u, thread)), cs)

# a terminal that asked something (cursor position, device attributes)
# gets its answer sent back to its shell
def Ui.recv_act.t(term: Bool, +thread: String, a: Act) -> Act:
  match term a:
    case True{} Act{u, cs}:
      Ui.term_replies(u, thread, cs)
    case False{} _:
      a

# open the selected thread's terminal at this size (or resize it)
def Ui.term_open(u: Ui, +cols: U32, +rows: U32) -> Act:
  match u:
    case Ui{st, +sel, dr, live, op, on, now, ad, pa, ve, rid, w, er, note, nf, ob, +tr}:
      Ui.rpc(Ui{st, sel, dr, live, op, on, now, ad, pa, ve, rid, w, er, note, nf, ob, Map.set(&2, VT.Vt, tr, sel, VT.Vt.resize(Term.get(tr, sel), cols, rows))},
        "term.open", [J.KV{"thread", J.Str{sel}}, J.KV{"cols", J.Num{U32.show(cols)}}, J.KV{"rows", J.Num{U32.show(rows)}}])

# keys typed into the selected thread's terminal
def Ui.term_keys(u: Ui, bs: List<&2, U32>) -> Act:
  match u:
    case Ui{st, +sel, dr, live, op, on, now, ad, pa, ve, rid, w, er, note, nf, ob, tr}:
      Ui.rpc(Ui{st, sel, dr, live, op, on, now, ad, pa, ve, rid, w, er, note, nf, ob, tr}, "term.input", [J.KV{"thread", J.Str{sel}}, J.KV{"b", J.Json.arr(Term.nums(bs))}])

def Keys.pos(xs: List<&2, String>, +x: String) -> Nat:
  C.Codec.pos(xs, x)

def Ui.state(u: Ui) -> M.State:
  match u:
    case Ui{st, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      st

# the ui with flag k on
def Ui.flag_on(u: Ui, +k: String) -> Ui:
  match u:
    case Ui{st, sel, dr, live, +op, on, now, ad, pa, ve, rid, w, er, note, nf, ob, tr}:
      Ui{st, sel, dr, live, Map.set(&2, Bool, op, k, True{}), on, now, ad, pa, ve, rid, w, er, note, nf, ob, tr}

# Command palette
# ---------------
# ctrl+k: threads and actions, filtered by what was typed. Its query and
# selection live in the drafts map under keys no thread id can take.

type PItem is Data:
  PItem{label: String, action: String, value: String}

def Palette.query(u: Ui) -> String:
  match u:
    case Ui{_, _, dr, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      Str.get(dr, "@palette")

def Palette.index(u: Ui) -> Nat:
  match u:
    case Ui{_, _, dr, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      Maybe.default(&2, Nat, Nat.read(Str.get(dr, "@palette.i")), 0n)

def Palette.set(u: Ui, +q: String, +i: Nat) -> Ui:
  match u:
    case Ui{st, sel, +dr, live, op, on, now, ad, pa, ve, rid, w, er, note, nf, ob, tr}:
      Ui{st, sel, Map.set(&2, String, Map.set(&2, String, dr, "@palette", q), "@palette.i", Nat.show(i)), live, op, on, now, ad, pa, ve, rid, w, er, note, nf, ob, tr}

def Palette.threads(ts: List<&2, M.Thread>) -> List<&2, PItem>:
  match ts:
    case Nil{}:
      Nil{}
    case M.Thread{id, _, ti, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} <> t:
      PItem{ti, "select", id} <> Palette.threads(t)

def Palette.actions(+pid: String) -> List<&2, PItem>:
  [PItem{"New thread", "new-thread", pid}, PItem{"Diff: what this thread changed", "diff", ""}, PItem{"Terminal", "key:term", ""},
   PItem{"Commit & push", "git", "commit_push"}, PItem{"Open pull request", "git", "commit_push_pr"}, PItem{"Revert thread", "revert", "0"},
   PItem{"Settle thread", "settle", ""}, PItem{"Pin thread", "pin", ""}, PItem{"Archive thread", "archive", ""},
   PItem{"Viewer", "panel", ""}, PItem{"Settings", "flag", "settings"}, PItem{"Update Backplane", "update", ""}]

def Palette.words(ws: List<&2, String>, +l: String) -> Bool:
  match ws:
    case Nil{}:
      True{}
    case +w <> t:
      Bool.and(Bool.or(String.is_empty(w), String.contains(l, w)), Palette.words(t, l))

# does every word of the query appear in the label (any case)?
def Palette.hit(+q: String, +label: String) -> Bool:
  Palette.words(String.split(String.to_lower(q), ' '), String.to_lower(label))

def Palette.filter.k(keep: Bool, p: PItem, rest: List<&2, PItem>) -> List<&2, PItem>:
  match keep:
    case True{}:
      p <> rest
    case False{}:
      rest

def Palette.filter(ps: List<&2, PItem>, +q: String) -> List<&2, PItem>:
  match ps:
    case Nil{}:
      Nil{}
    case PItem{+l, a, v} <> t:
      Palette.filter.k(Palette.hit(q, l), PItem{l, a, v}, Palette.filter(t, q))

# what the palette offers for this query, actions first
def Palette.items(+u: Ui) -> List<&2, PItem>:
  Palette.filter(List.append(&2, PItem, Palette.actions(Ui.thread_project(Ui.thread(Ui.state(u), Ui.sel(u)))),
    Palette.threads(Kids.keep(Ui.threads(Ui.state(u)), Kids.set(Ui.state(u))))), Palette.query(u))

def Palette.at(ps: List<&2, PItem>, i: Nat) -> PItem:
  match ps i:
    case p <> _ 0n:
      p
    case _ <> t 1n+j:
      Palette.at(t, j)
    case Nil{} _:
      PItem{"", "", ""}

def Ui.flag_off(u: Ui, +k: String) -> Ui:
  match u:
    case Ui{st, sel, dr, live, +op, on, now, ad, pa, ve, rid, w, er, note, nf, ob, tr}:
      Ui{st, sel, dr, live, Map.set(&2, Bool, op, k, False{}), on, now, ad, pa, ve, rid, w, er, note, nf, ob, tr}

def Ui.info_set(u: Ui, +k: String, +v: String) -> Ui:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, ve, rid, w, er, note, +nf, ob, tr}:
      Ui{st, sel, dr, live, op, on, now, ad, pa, ve, rid, w, er, note, Map.set(&2, String, nf, k, v), ob, tr}

# What the machine says about a provider: its CLI version ("" when it is
# not installed) and a label per model
def Models.about(+info: String, +provider: String) -> J.Json:
  J.Json.get_obj(J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(info), J.Null{}), "about"), provider)

def Models.cli(+info: String, +provider: String) -> String:
  J.Json.get_str(Models.about(info, provider), "cli", "")

# "opus" -> "Opus 5.5 · claude-opus-5-5" ("" when unknown)
def Models.label_of(+info: String, +provider: String, +model: String) -> String:
  J.Json.get_str(J.Json.get_obj(Models.about(info, provider), "labels"), Bool.pick(String, String.is_empty(model), "default", model), "")

# Project picker
# --------------
# A folder browser with fuzzy filtering: the listed folder and its
# subfolders come from the server (fs.list); the query and selection live
# in the drafts map under keys no thread id can take.

def Proj.query(u: Ui) -> String:
  match u:
    case Ui{_, _, dr, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      Str.get(dr, "@proj")

def Proj.index(u: Ui) -> Nat:
  match u:
    case Ui{_, _, dr, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      Maybe.default(&2, Nat, Nat.read(Str.get(dr, "@proj.i")), 0n)

def Proj.set(u: Ui, +q: String, +i: Nat) -> Ui:
  match u:
    case Ui{st, sel, +dr, live, op, on, now, ad, pa, ve, rid, w, er, note, nf, ob, tr}:
      Ui{st, sel, Map.set(&2, String, Map.set(&2, String, dr, "@proj", q), "@proj.i", Nat.show(i)), live, op, on, now, ad, pa, ve, rid, w, er, note, nf, ob, tr}

def Proj.reset(u: Ui, +q: String) -> Ui:
  Ui.info_set(Proj.set(u, q, 0n), "proj.err", "")

def Proj.dir(u: Ui) -> String:
  Ui.info(u, "proj.dir")

def Proj.focus(a: Act) -> Act:
  match a:
    case Act{u, cs}:
      Act{u, List.append(&2, Cmd, cs, [Focus{"proj"}])}

# opens where it was last (home the first time)
def Proj.open(+u: Ui) -> Act:
  Proj.focus(Ui.rpc(Proj.reset(Ui.flag_on(u, "proj"), ""), "fs.list", [J.KV{"path", J.Str{Proj.dir(u)}}]))

def Proj.names(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case J.Str{s} <> t:
      s <> Proj.names(t)
    case _ <> t:
      Proj.names(t)

# the subfolders of the listed folder
def Proj.entries(u: Ui) -> List<&2, String>:
  Proj.names(J.Json.elems(Maybe.default(&2, J.Json, J.Json.parse(Ui.info(u, "proj.entries")), J.Null{})))

# a listing (or its error) arrived
def Proj.reply(has: Bool, u: Ui, +o: J.Json) -> Ui:
  match has:
    case True{}:
      Ui.info_set(Ui.info_set(Ui.info_set(u, "proj.dir", J.Json.get_str(J.Json.get_obj(o, "result"), "dir", "")), "proj.entries",
        J.Json.show(J.Json.get_obj(J.Json.get_obj(o, "result"), "entries"))), "proj.err", "")
    case False{}:
      Ui.info_set(u, "proj.err", J.Json.get_str(J.Json.get_obj(o, "result"), "error", ""))

# an answer: its request leaves the outbox; a diff opens the diff view
def Ui.reply(u: Ui, +o: J.Json) -> Ui:
  Proj.reply(Bool.not(String.is_empty(J.Json.get_str(J.Json.get_obj(o, "result"), "dir", ""))), Ui.reply.dispatch(u, o), o)

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
    case 6n:
      Ui.term_feed(u, J.Json.get_str(o, "thread", ""), Term.bytes(J.Json.elems(J.Json.get_obj(o, "b"))))
    case _:
      u

# a message from the server
def Ui.recv(u: Ui, +o: J.Json) -> Ui:
  Ui.recv.k(C.Codec.pos(["log", "changes", "delta", "reply", "update", "view", "term"], J.Json.get_str(o, "t", "")), u, o)

# a message from the server, with what to send: a (re)connection (the
# server's log arrives first on each) sends the outbox again, so nothing
# the user sent is lost to a dropped link
def Ui.recv_act(u: Ui, +o: J.Json) -> Act:
  Ui.recv_act.t(String.eq(J.Json.get_str(o, "t", ""), "term"), J.Json.get_str(o, "thread", ""), Ui.recv_act.k(String.eq(J.Json.get_str(o, "t", ""), "log"), Ui.recv(u, o)))

def Proj.join(+dir: String, +name: String) -> String:
  Bool.pick(String, String.ends_with(dir, "/"), dir ++ name, dir ++ "/" ++ name)

def Proj.parent.k(+ps: List<&2, String>) -> String:
  Bool.pick(String, Nat.is_le(List.length(&2, String, ps), 2n), "/", String.join(List.take(&2, String, ps, Nat.sub(List.length(&2, String, ps), 1n)), "/"))

def Proj.parent(+dir: String) -> String:
  Proj.parent.k(String.split(dir, '/'))

# a name a new folder may take: no slash, not "." or "..", not blank
def Proj.name_ok(+q: String) -> Bool:
  Bool.and(Bool.and(Bool.not(String.is_empty(String.trim(q))), Bool.not(String.contains(q, "/"))), Bool.and(Bool.not(String.eq(q, ".")), Bool.not(String.eq(q, ".."))))

def Proj.exact(ns: List<&2, String>, +q: String) -> Bool:
  match ns:
    case Nil{}:
      False{}
    case n <> t:
      Bool.or(String.eq(n, q), Proj.exact(t, q))

type Scored is Data:
  Scored{score: Nat, name: String}

def Scored.before(a: Scored, b: Scored) -> Bool:
  match a b:
    case Scored{+x, n} Scored{+y, m}:
      Bool.or(Nat.is_gt(x, y), Bool.and(Nat.is_eq(x, y), String.is_le(n, m)))

def Proj.scored.k(+sc: Nat, +n: String, +rest: List<&2, Scored>) -> List<&2, Scored>:
  Bool.pick(List<&2, Scored>, Nat.is_eq(sc, 0n), rest, Scored{sc, n} <> rest)

# matching folders; hidden ones (.git) only for a filter starting with "."
def Proj.scored(ns: List<&2, String>, +q: String) -> List<&2, Scored>:
  match ns:
    case Nil{}:
      Nil{}
    case +n <> t:
      Proj.scored.k(Bool.pick(Nat, Bool.and(String.starts_with(n, "."), Bool.not(String.starts_with(q, "."))), 0n, FZ.Fuzzy.score(n, q)), n, Proj.scored(t, q))

def Proj.rows(xs: List<&2, Scored>, +dir: String) -> List<&2, PItem>:
  match xs:
    case Nil{}:
      Nil{}
    case Scored{_, +n} <> t:
      PItem{n ++ "/", "proj-cd", Proj.join(dir, n)} <> Proj.rows(t, dir)

def Proj.is_project(ps: List<&2, M.Project>, +root: String) -> Bool:
  match ps:
    case Nil{}:
      False{}
    case M.Project{_, _, r, _, rm} <> t:
      Bool.or(Bool.and(String.eq(r, root), Bool.not(rm)), Proj.is_project(t, root))

# the listed folder as a project (once)
def Proj.add(+u: Ui, +dir: String) -> List<&2, PItem>:
  Bool.pick(List<&2, PItem>, Proj.is_project(Ui.projects(Ui.state(u)), dir), [PItem{dir ++ " is already a project", "", ""}], [PItem{"Add " ++ dir ++ " as a project", "proj-add", dir}])

def Proj.items.k(path: Bool, +u: Ui, +q: String, +dir: String, +ns: List<&2, String>) -> List<&2, PItem>:
  match path:
    case True{}:
      [PItem{"Go to " ++ q, "proj-cd", q}]
    case False{}:
      Bool.pick(List<&2, PItem>, String.is_empty(q),
        List.concat(&2, PItem, [Proj.add(u, dir), Bool.pick(List<&2, PItem>, String.eq(dir, "/"), Nil{}, [PItem{"..", "proj-cd", Proj.parent(dir)}]),
          Proj.rows(Proj.scored(ns, q), dir)]),
        List.concat(&2, PItem, [Proj.rows(List.sort(~Scored, ~Scored.before, Proj.scored(ns, q)), dir),
          Bool.pick(List<&2, PItem>, Bool.and(Proj.name_ok(q), Bool.not(Proj.exact(ns, q))), [PItem{"Create folder '" ++ q ++ "' here", "proj-mkdir", Proj.join(dir, q)}], Nil{}),
          Proj.add(u, dir)]))

# what the picker offers. No filter: add the listed folder (once), the
# parent, the subfolders. A filter: matching subfolders best first, then
# creating the typed name (only when no folder has it), then adding. A
# typed path (/..., ~...) goes there instead
def Proj.items(+u: Ui) -> List<&2, PItem>:
  Proj.items.k(Bool.or(String.starts_with(Proj.query(u), "/"), String.starts_with(Proj.query(u), "~")), u, Proj.query(u), Proj.dir(u), Proj.entries(u))

# add (closes the picker), browse, create
def Proj.run.k(i: Nat, u: Ui, +v: String) -> Act:
  match i:
    case 0n:
      Ui.rpc(Ui.flag_off(u, "proj"), "project.add", [J.KV{"path", J.Str{v}}])
    case 1n:
      Ui.rpc(Proj.reset(u, ""), "fs.list", [J.KV{"path", J.Str{v}}])
    case 2n:
      Ui.rpc(Proj.reset(u, ""), "fs.mkdir", [J.KV{"path", J.Str{v}}])
    case _:
      Act{u, Nil{}}

def Proj.pos(xs: List<&2, String>, +x: String, +i: Nat) -> Nat:
  match xs:
    case Nil{}:
      i
    case +h <> t:
      Bool.pick(Nat, String.eq(h, x), i, Proj.pos(t, x, 1n+i))

def Proj.run(it: PItem, u: Ui) -> Act:
  match it:
    case PItem{_, +a, +v}:
      Proj.run.k(Proj.pos(["proj-add", "proj-cd", "proj-mkdir"], a, 0n), u, v)

# Enter runs the selected row
def Proj.enter(+u: Ui) -> Act:
  Proj.run(Palette.at(Proj.items(u), Proj.index(u)), u)

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
    case 22n:
      Ui.answer(u, value)
    case 23n:
      Ui.on_thread.p(u, "git.act", [J.KV{"action", J.Str{value}}])
    case 24n:
      Ui.on_thread.p(u, "git.diff", [J.KV{"from", J.Num{"0"}}, J.KV{"to", J.Num{"-1"}}])
    case 25n:
      Ui.on_thread.p(u, "git.revert", [J.KV{"turn", J.Num{Bool.pick(String, String.is_empty(value), "0", value)}}])
    case 26n:
      Proj.open(u)
    case 27n:
      Proj.run.k(1n, u, value)
    case 28n:
      Proj.run.k(0n, u, value)
    case 29n:
      Proj.run.k(2n, u, value)
    case 30n:
      Act{Proj.set(u, value, 0n), Nil{}}
    case 31n:
      Act{Ui.flag_off(u, "proj"), Nil{}}
    case 32n:
      Proj.enter(u)
    case _:
      Act{u, Nil{}}

# a user action with its value
def Ui.act(u: Ui, +action: String, +value: String) -> Act:
  Ui.act.k(C.Codec.pos(Ui.actions(), action), u, value)
