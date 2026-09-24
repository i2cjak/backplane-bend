import Base
import ./json.bend as J
import ./model.bend as M
import ./codec.bend as C
import ./vt.bend as VT
import ./fuzzy.bend as FZ
import ./agent.bend as AG
import ./attach.bend as AT
import ./fold.bend as FO

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
  # talk to another machine's hub ("" is this machine's own)
  Connect{url: String}

type Act is Data:
  Act{ui: Ui, cmds: List<&2, Cmd>}

def Act.cmds(a: Act) -> List<&2, Cmd>:
  match a:
    case Act{_, cs}:
      cs

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
    case M.State{_, ts, _, _, _, _, _, _, _, _}:
      Map.values(&2, M.Thread, ts)

def Ui.projects(s: M.State) -> List<&2, M.Project>:
  match s:
    case M.State{ps, _, _, _, _, _, _, _, _, _}:
      Map.values(&2, M.Project, ps)

def Ui.thread.k(r: Map<&2, M.Thread> & M.Thread) -> M.Thread:
  (_, t) = r
  t

def Ui.thread(s: M.State, +id: String) -> M.Thread:
  match s:
    case M.State{_, ts, _, _, _, _, _, _, _, _}:
      Ui.thread.k(Map.get(M.Thread, M.Thread.blank(id), ts, id))

def Ui.entries(s: M.State) -> List<&2, M.Entry>:
  match s:
    case M.State{_, _, es, _, _, _, _, _, _, _}:
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

# tail-recursive, reversed once: a log holds thousands of changes, and a
# frame per change overflowed the phone's JavaScriptCore
def Ui.decode.go(xs: List<&2, J.Json>, acc: List<&2, M.Change>) -> List<&2, M.Change>:
  match xs:
    case Nil{}:
      acc
    case +x <> t:
      Ui.decode.go(t, Ui.decode.k(C.Change.decode(x), acc))

def Ui.decode(xs: List<&2, J.Json>) -> List<&2, M.Change>:
  List.reverse(&2, M.Change, Ui.decode.go(xs, Nil{}))

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

# the machine info changed while connected (new models): its fields replace
# the old ones, the rest stays
# Machines
# --------
# The owner's machines that run Backplane (the hub finds them on the
# tailnet). This client's own keys start with "local." and survive a new
# log: which machine it talks to ("" is its home hub) and the home hub's
# list, so the switcher stays the same while another machine is shown.

def Local.keep.go(ks: List<&2, String>, +old: Map<&2, String>, m: Map<&2, String>) -> Map<&2, String>:
  match ks:
    case Nil{}:
      m
    case +k <> t:
      Local.keep.go(t, old, Map.set(&2, String, m, k, Str.get(old, k)))

def Local.keep(+old: Map<&2, String>, m: Map<&2, String>) -> Map<&2, String>:
  Local.keep.go(["local.machine", "local.machines"], old, m)

def Machines.home.k(home: Bool, +nf: Map<&2, String>) -> Map<&2, String>:
  Bool.pick(Map<&2, String>, Bool.and(home, Bool.not(String.is_empty(Str.get(nf, "machines")))), Map.set(&2, String, nf, "local.machines", Str.get(nf, "machines")), nf)

# what the home hub says about machines becomes the switcher's list
def Machines.home(+nf: Map<&2, String>) -> Map<&2, String>:
  Machines.home.k(String.is_empty(Str.get(nf, "local.machine")), nf)

type MRow is Data:
  MRow{name: String, url: String, on: Bool}

def Machines.peer(skip: Bool, +n: String, +url: String, +cur: String, rest: List<&2, MRow>) -> List<&2, MRow>:
  match skip:
    case True{}:
      rest
    case False{}:
      MRow{n, url, String.eq(url, cur)} <> rest

def Machines.peers(ps: List<&2, J.Json>, +me: String, +cur: String) -> List<&2, MRow>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      Machines.peer(String.eq(J.Json.get_str(p, "url", ""), me), J.Json.get_str(p, "name", ""), J.Json.get_str(p, "url", ""), cur, Machines.peers(t, me, cur))

def Machines.of(+j: J.Json, +cur: String) -> List<&2, MRow>:
  MRow{Bool.pick(String, String.is_empty(J.Json.get_str(J.Json.get_obj(j, "self"), "name", "")), "This machine", J.Json.get_str(J.Json.get_obj(j, "self"), "name", "")), "", String.is_empty(cur)}
    <> Machines.peers(J.Json.elems(J.Json.get_obj(j, "peers")), J.Json.get_str(J.Json.get_obj(j, "self"), "url", ""), cur)

# the name of the machine shown
def Machines.current(rs: List<&2, MRow>) -> String:
  match rs:
    case Nil{}:
      ""
    case MRow{+n, _, +on} <> t:
      Bool.pick(String, on, n, Machines.current(t))

# switch to a machine: the host connects there, and its log replaces this
# one (the selection and anything still unsent belong to the old machine)
def Ui.machine(u: Ui, +url: String) -> Act:
  match u:
    case Ui{st, _, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, _, tr}:
      Act{Ui{st, "", dr, live, Map.set(&2, Bool, op, "machines", False{}), on, now, ad, pa, v, rid, w, er, note, Map.set(&2, String, nf, "local.machine", url), Map.new(&2, String), tr}, [Connect{url}]}

def Ui.info_merge(u: Ui, o: J.Json) -> Ui:
  match u o:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr} J.Obj{fs}:
      Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, Machines.home(Info.fields(fs, nf)), ob, tr}
    case _ _:
      u

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
          Machines.home(Local.keep(nf, Map.set(&2, String, Map.set(&2, String, Info.of(J.Json.get_obj(o, "info")), "cid", Str.get(nf, "cid")), "origin", J.Json.get_str(o, "origin", "")))), ob, tr})

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
  Bool.pick(String, J.Json.get_bool(o, "ok", True{}), "", J.Json.get_str(o, "error", J.Json.get_str(J.Json.get_obj(o, "result"), "error", String.take(J.Json.get_str(J.Json.get_obj(o, "result"), "text", "failed"), 200n))))

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

def Files.strs(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case J.Str{x} <> t:
      x <> Files.strs(t)
    case _ <> t:
      Files.strs(t)

def Ui.files(u: Ui, +r: J.Json) -> Ui:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}:
      Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note,
        Map.set(&2, String, Map.set(&2, String, nf, "files", String.join(Files.strs(J.Json.elems(J.Json.get_obj(r, "files"))), "\n")), "files.thread", J.Json.get_str(r, "thread", "")), ob, tr}

def Ui.reply.files(has: Bool, u: Ui, +o: J.Json) -> Ui:
  match has:
    case True{}:
      Ui.files(u, J.Json.get_obj(o, "result"))
    case False{}:
      u

def Skills.has(+o: J.Json) -> Bool:
  Bool.not(String.eq(J.Json.show(Maybe.default(&2, J.Json, J.Json.get(J.Json.get_obj(o, "result"), "skills"), J.Null{})), "null"))

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
      Act{Ui{st, id, Map.set(&2, String, dr, "@del", ""), live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}, [Focus{"composer"}, Scroll{}]}

def Ui.draft.set(u: Ui, text: String) -> Act:
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
      Ui.also(Ui.rpc.keep(Ui{st, sel, Map.set(&2, String, Map.set(&2, String, dr, sel, ""), "@att:" ++ sel, ""), live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr},
        "turn.start", [J.KV{"thread", J.Str{sel}}, J.KV{"text", J.Str{text}}, J.KV{"msg", J.Str{Ui.msg_id(Str.get(nf, "cid"), now, rid)}}]), [Scroll{}])

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

# the switcher: this machine first, then the others ("on" marks the one shown)
def Machines.rows(+u: Ui) -> List<&2, MRow>:
  Machines.of(Maybe.default(&2, J.Json, J.Json.parse(Ui.info(u, "local.machines")), J.Null{}), Ui.info(u, "local.machine"))

# only worth showing when there is somewhere else to go
def Machines.any(+u: Ui) -> Bool:
  Nat.is_gt(List.length(&2, MRow, Machines.rows(u)), 1n)

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
   "flag", "setting", "model", "kicad-install", "answer", "git", "diff", "revert", "proj-open", "proj-cd", "proj-add", "proj-mkdir", "proj-q", "proj-close", "proj-enter",
   "effort", "skill", "snooze", "unarchive", "reorder", "move", "mention", "files",
   "delete-no", "proj-new", "-43", "-44", "-45", "-46", "-47", "-48", "drop-hover",
   "attach", "attach-file", "detach", "term-toggle", "term-key", "term-paste", "key", "update-check", "machine",
   "row-settle", "row-unsettle", "row-snooze", "row-delete", "fold", "row-toggle"]

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
    case M.State{ps, _, _, _, _, _, _, _, _, _}:
      Ui.project_root.k(Map.get(M.Project, M.Project.blank(id), ps, id))

def Ui.thread_project(t: M.Thread) -> String:
  match t:
    case M.Thread{_, p, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      p

def Ui.thread_worktree(t: M.Thread) -> String:
  match t:
    case M.Thread{_, _, _, _, _, _, _, _, _, _, _, _, _, _, wt, _, _, _, _, _, _}:
      wt

def Ui.dir(+st: M.State, +wt: String, +project: String) -> String:
  Bool.pick(String, String.is_empty(wt), Ui.project_root(st, project), wt)

# the selected thread's directory: its worktree, else its project's folder
# ("" with nothing selected). The viewer shows the board the thread edits.
def Ui.root(u: Ui) -> String:
  match u:
    case Ui{+st, +sel, _, _, _, _, _, _, _, _, _, _, _, _, nf, ob, tr}:
      Bool.pick(String, String.is_empty(sel), "", Ui.dir(st, Ui.thread_worktree(Ui.thread(st, sel)), Ui.thread_project(Ui.thread(st, sel))))

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
    case M.State{_, _, _, _, tk, _, _, _, _, _}:
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
    case M.State{_, _, _, _, tk, _, _, _, _, _}:
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
    case M.State{_, _, _, _, tk, _, _, _, _, _}:
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

# Sidebar model
# -------------
# Both clients draw the sidebar from these: projects by latest activity,
# each with its threads on shelves (M.Sidebar.at: keys and snoozes), and the
# visible order ctrl+1..9 counts in.

type SRow is Data:
  SRow{rank: Nat, project: M.Project, shelves: M.Shelves}

def SRow.before(a: SRow, b: SRow) -> Bool:
  match a b:
    case SRow{ra, _, _} SRow{rb, _, _}:
      Nat.is_ge(ra, rb)

def Side.latest(ts: List<&2, M.Thread>, +acc: Nat) -> Nat:
  match ts:
    case Nil{}:
      acc
    case M.Thread{_, _, _, _, +a, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} <> t:
      Side.latest(t, M.Time.max(acc, a))

def Side.rows.k(removed: Bool, p: M.Project, +mine: List<&2, M.Thread>, +c: Nat, +navs: Map<&2, M.Nav>, +now: Nat, rest: List<&2, SRow>) -> List<&2, SRow>:
  match removed:
    case True{}:
      rest
    case False{}:
      SRow{Side.latest(mine, c), p, M.Sidebar.at(mine, navs, now)} <> rest

def Side.rows.go(ps: List<&2, M.Project>, +ts: List<&2, M.Thread>, +navs: Map<&2, M.Nav>, +now: Nat) -> List<&2, SRow>:
  match ps:
    case Nil{}:
      Nil{}
    case M.Project{+id, ti, r, +c, +rm} <> t:
      Side.rows.k(rm, M.Project{id, ti, r, c, rm}, M.Thread.filter_project(ts, id), c, navs, now, Side.rows.go(t, ts, navs, now))

# the sidebar's projects in order, their threads on shelves (delegated
# child threads live under their parent instead)
def Side.rows(+st: M.State, +now: Nat) -> List<&2, SRow>:
  List.sort(~SRow, ~SRow.before, Side.rows.go(Ui.projects(st), Kids.keep(Ui.threads(st), Kids.set(st)), M.State.navs(st), now))

def Side.ids(ts: List<&2, M.Thread>) -> List<&2, String>:
  match ts:
    case Nil{}:
      Nil{}
    case t <> rest:
      M.Thread.id(t) <> Side.ids(rest)

def Side.when(on: Bool, xs: List<&2, String>) -> List<&2, String>:
  match on:
    case True{}:
      xs
    case False{}:
      Nil{}

def Side.visible.go(rs: List<&2, SRow>, +open: Map<&2, Bool>) -> List<&2, String>:
  match rs:
    case Nil{}:
      Nil{}
    case SRow{_, M.Project{+id, _, _, _, _}, M.Shelves{p, a, st, h, sn}} <> t:
      List.concat(&2, String, [Side.ids(p), Side.ids(a), Side.ids(sn), Side.when(Flag.get(open, id), Side.ids(st)),
        Side.when(Flag.get(open, "arch:" ++ id), Side.ids(M.Archive.of(h))), Side.visible.go(t, open)])

# the threads the sidebar shows, top to bottom (collapsed shelves left out)
def Side.visible(u: Ui) -> List<&2, String>:
  match u:
    case Ui{+st, _, _, _, +op, _, +now, _, _, _, _, _, _, _, _, _, _}:
      Side.visible.go(Side.rows(st, now), op)

def Side.nth(xs: List<&2, String>, i: Nat) -> String:
  match xs i:
    case x <> _ 0n:
      x
    case _ <> t 1n+j:
      Side.nth(t, j)
    case Nil{} _:
      ""

type Sect is Data:
  Sect{name: String, ids: List<&2, String>}

def Side.has(xs: List<&2, String>, +x: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case h <> t:
      Bool.or(String.eq(h, x), Side.has(t, x))

def Side.section.k(s: M.Shelves, +id: String) -> Sect:
  match s:
    case M.Shelves{+p, +a, _, _, _}:
      Bool.pick(Sect, Side.has(Side.ids(p), id), Sect{"pinned", Side.ids(p)},
        Bool.pick(Sect, Side.has(Side.ids(a), id), Sect{"active", Side.ids(a)}, Sect{"", Nil{}}))

# the shelf a thread can be dragged within, with its threads in order
# ("" for a shelf without manual order)
def Side.section(+st: M.State, +now: Nat, +id: String) -> Sect:
  Side.section.k(M.Sidebar.at(M.Thread.filter_project(Kids.keep(Ui.threads(st), Kids.set(st)), Ui.thread_project(Ui.thread(st, id))), M.State.navs(st), now), id)

# Reordering, snoozing, mentions
# ------------------------------

def Side.st(u: Ui) -> M.State:
  match u:
    case Ui{st, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      st

def Side.now(u: Ui) -> Nat:
  match u:
    case Ui{_, _, _, _, _, _, now, _, _, _, _, _, _, _, _, _, _}:
      now

def Side.pair(ps: List<&2, String>) -> Sect:
  match ps:
    case a <> t:
      Sect{a, t}
    case Nil{}:
      Sect{"", Nil{}}

def Side.first(xs: List<&2, String>) -> String:
  Maybe.default(&2, String, List.head(&2, String, xs), "")

def Side.strs(xs: List<&2, String>) -> List<&2, J.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      J.Str{x} <> Side.strs(t)

def Side.open(u: Ui) -> Map<&2, Bool>:
  match u:
    case Ui{_, _, _, _, op, _, _, _, _, _, _, _, _, _, _, _, _}:
      op

# Hotkeys: alt+1..9 goes to the Nth project the sidebar shows, ctrl+1..9 to
# the Nth thread the sidebar shows in the selected thread's project.

def Side.pids(rs: List<&2, SRow>) -> List<&2, String>:
  match rs:
    case Nil{}:
      Nil{}
    case SRow{_, M.Project{id, _, _, _, _}, _} <> t:
      id <> Side.pids(t)

# the sidebar's projects, top to bottom
def Side.projects(u: Ui) -> List<&2, String>:
  match u:
    case Ui{+st, _, _, _, _, _, +now, _, _, _, _, _, _, _, _, _, _}:
      Side.pids(Side.rows(st, now))

def Side.only.k(keep: Bool, r: SRow, rest: List<&2, SRow>) -> List<&2, SRow>:
  match keep:
    case True{}:
      r <> rest
    case False{}:
      rest

def Side.only(rs: List<&2, SRow>, +pid: String) -> List<&2, SRow>:
  match rs:
    case Nil{}:
      Nil{}
    case SRow{r, M.Project{+id, ti, ro, c, rm}, sh} <> t:
      Side.only.k(String.eq(id, pid), SRow{r, M.Project{id, ti, ro, c, rm}, sh}, Side.only(t, pid))

# the selected thread's project ("" with nothing selected)
def Side.cur(u: Ui) -> String:
  match u:
    case Ui{+st, +sel, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      Bool.pick(String, String.is_empty(sel), "", Ui.thread_project(Ui.thread(st, sel)))

# the threads the sidebar shows in project pid, top to bottom
def Side.of(+u: Ui, +pid: String) -> List<&2, String>:
  Side.visible.go(Side.only(Side.rows(Side.st(u), Side.now(u)), pid), Side.open(u))

# the threads ctrl+1..9 count in
def Side.here(+u: Ui) -> List<&2, String>:
  Side.of(u, Side.cur(u))

def Side.live.go(rs: List<&2, SRow>) -> List<&2, String>:
  match rs:
    case Nil{}:
      Nil{}
    case SRow{_, _, M.Shelves{p, a, st, _, sn}} <> t:
      List.concat(&2, String, [Side.ids(p), Side.ids(a), Side.ids(sn), Side.ids(st), Side.live.go(t)])

# where alt+N lands in project pid: the selected thread when it is already
# there, else the project's top thread, collapsed shelves included (""
# when it has none, so the caller starts one)
def Side.home.k(here: Bool, +u: Ui, +pid: String) -> String:
  match here:
    case True{}:
      Ui.sel(u)
    case False{}:
      Side.first(Side.live.go(Side.only(Side.rows(Side.st(u), Side.now(u)), pid)))

def Side.home(+u: Ui, +pid: String) -> String:
  Side.home.k(Bool.and(Bool.not(String.is_empty(pid)), String.eq(Side.cur(u), pid)), u, pid)

# x's place in xs counting from 1, 0 when absent (the number a hint shows)
def Side.num(xs: List<&2, String>, +x: String, +i: Nat) -> Nat:
  match xs:
    case Nil{}:
      0n
    case +h <> t:
      Bool.pick(Nat, String.eq(h, x), 1n+i, Side.num(t, x, 1n+i))

def Ui.reorder.k(ok: Bool, +u: Ui, s: Sect, +id: String, +to: Nat) -> Act:
  match ok s:
    case True{} Sect{+name, +ids}:
      Ui.rpc(u, "thread.reorder", [J.KV{"section", J.Str{name}}, J.KV{"thread", J.Str{id}}, J.KV{"ids", J.Json.arr(Side.strs(M.Order.move(ids, id, to)))}])
    case False{} _:
      Act{u, Nil{}}

def Ui.reorder.s(+u: Ui, +s: Sect, +id: String, +target: String) -> Act:
  match s:
    case Sect{+name, +ids}:
      Ui.reorder.k(Bool.and(Bool.and(Bool.not(String.is_empty(name)), Bool.not(String.eq(id, target))), Side.has(ids, target)), u, Sect{name, ids}, id, M.Order.index(ids, target, 0n))

# drop thread `id` where `target` sits on the same shelf
def Ui.reorder.to(+u: Ui, +id: String, +target: String) -> Act:
  Ui.reorder.s(u, Side.section(Side.st(u), Side.now(u), id), id, target)

def Ui.reorder.pair(+u: Ui, s: Sect) -> Act:
  match s:
    case Sect{+id, t}:
      Ui.reorder.to(u, id, Side.first(t))

# "id|target"
def Ui.reorder(+u: Ui, v: String) -> Act:
  Ui.reorder.pair(u, Side.pair(String.split(v, '|')))

def Ui.move.go(+u: Ui, +id: String, +up: Bool, +ids: List<&2, String>) -> Act:
  +i = M.Order.index(ids, id, 0n)
  Ui.reorder.to(u, id, Bool.pick(String, up, Bool.pick(String, Nat.is_eq(i, 0n), "", Side.nth(ids, Nat.sub(i, 1n))), Side.nth(ids, 1n+i)))

def Ui.move.s(+u: Ui, s: Sect, +id: String, +up: Bool) -> Act:
  match s:
    case Sect{_, +ids}:
      Ui.move.go(u, id, up, ids)

def Ui.move.k(+u: Ui, s: Sect) -> Act:
  match s:
    case Sect{+id, t}:
      Ui.move.s(u, Side.section(Side.st(u), Side.now(u), id), id, String.eq(Side.first(t), "up"))

# "id|up" or "id|down": one place up or down its shelf
def Ui.move(+u: Ui, v: String) -> Act:
  Ui.move.k(u, Side.pair(String.split(v, '|')))

# snooze the selected thread ("1h", "tomorrow", "1w"; "off" wakes it)
def Ui.snooze(u: Ui, v: String) -> Act:
  Ui.on_thread.p(Ui.close(u, "snooze"), "thread.snooze", [J.KV{"for", J.Str{v}}])

def Ui.mention.sep(+d: String) -> String:
  Bool.pick(String, Bool.or(String.is_empty(d), Bool.or(String.ends_with(d, " "), String.ends_with(d, "\n"))), "", " ")

# "@path " added to the selected thread's draft
def Ui.mention(u: Ui, +path: String) -> Act:
  match u:
    case Ui{st, +sel, +dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}:
      Act{Ui{st, sel, Map.set(&2, String, dr, sel, Str.get(dr, sel) ++ Ui.mention.sep(Str.get(dr, sel)) ++ "@" ++ path ++ " "), live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}, [Focus{"composer"}]}

# Skills in the composer
# ----------------------
# Typing `$` asks the server for the thread's skills (user and project,
# once per thread); the composer then offers those whose name starts with
# what follows the `$`, and Tab or Enter completes the first (or a
# clicked one).

type SkillRow is Data:
  SkillRow{name: String, description: String}

# the draft's last word
def Skills.token(+draft: String) -> String:
  Maybe.default(&2, String, List.last(&2, String, String.split(Maybe.default(&2, String, List.last(&2, String, String.lines(draft)), ""), ' ')), "")

# whether the draft ends in a `$name` being typed
def Skills.typing(+draft: String) -> Bool:
  Bool.and(String.starts_with(Skills.token(draft), "$"), String.eq(AG.Mention.name(Skills.token(draft)), String.drop(Skills.token(draft), 1n)))

def Skills.rows.k(keep: Bool, +r: SkillRow, rest: List<&2, SkillRow>) -> List<&2, SkillRow>:
  match keep:
    case True{}:
      r <> rest
    case False{}:
      rest

def Skills.rows(xs: List<&2, J.Json>, +q: String) -> List<&2, SkillRow>:
  match xs:
    case Nil{}:
      Nil{}
    case +x <> t:
      Skills.rows.k(String.starts_with(J.Json.get_str(x, "name", ""), q), SkillRow{J.Json.get_str(x, "name", ""), J.Json.get_str(x, "description", "")}, Skills.rows(t, q))

def Skills.offer(on: Bool, +list: String, +q: String) -> List<&2, SkillRow>:
  match on:
    case True{}:
      List.take(&2, SkillRow, Skills.rows(J.Json.elems(Maybe.default(&2, J.Json, J.Json.parse(list), J.Null{})), q), 6n)
    case False{}:
      Nil{}

# the skills the composer offers now (none unless a `$name` is being typed)
def Skills.of(+sel: String, +dr: Map<&2, String>, +nf: Map<&2, String>) -> List<&2, SkillRow>:
  Skills.offer(Bool.and(Skills.typing(Str.get(dr, sel)), String.eq(Str.get(nf, "skills.for"), sel)), Str.get(nf, "skills"), String.drop(Skills.token(Str.get(dr, sel)), 1n))

def Ui.skills(u: Ui) -> List<&2, SkillRow>:
  match u:
    case Ui{_, +sel, +dr, _, _, _, _, _, _, _, _, _, _, _, +nf, _, _}:
      Skills.of(sel, dr, nf)

def Skills.named(rs: List<&2, SkillRow>, +v: String) -> Bool:
  match rs:
    case Nil{}:
      False{}
    case SkillRow{n, _} <> t:
      Bool.or(String.eq(n, v), Skills.named(t, v))

def Skills.first(rs: List<&2, SkillRow>) -> String:
  match rs:
    case SkillRow{n, _} <> _:
      n
    case Nil{}:
      ""

# the name a completion puts in: the one clicked, else the first offered
def Skills.pick(+rs: List<&2, SkillRow>, +v: String) -> String:
  Bool.pick(String, Skills.named(rs, v), v, Skills.first(rs))

def Skills.complete(+draft: String, +name: String) -> String:
  String.take(draft, Nat.sub(String.length(draft), String.length(Skills.token(draft)))) ++ "$" ++ name ++ " "

def Ui.skill.k(+name: String, +u: Ui) -> Act:
  Bool.pick(Act, String.is_empty(name), Act{u, Nil{}}, Ui.draft.set(u, Skills.complete(Ui.draft_text(u), name)))

# complete the `$name` being typed
def Ui.skill(+u: Ui, +v: String) -> Act:
  Ui.skill.k(Skills.pick(Ui.skills(u), v), u)

def Skills.need(+u: Ui) -> Bool:
  Bool.and(Skills.typing(Ui.draft_text(u)), Bool.not(String.eq(Ui.info(u, "skills.for"), Ui.sel(u))))

# Reasoning effort in the composer
# --------------------------------

# a thread's effort ("" for its provider's default)
def Effort.of(+st: M.State, +thread: String) -> String:
  M.Setting.get(st, AG.Effort.key(thread), "")

def Ui.effort(u: Ui) -> String:
  match u:
    case Ui{+st, +sel, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      Effort.of(st, sel)

# the levels a provider offers, its default ("") first
def Effort.chips.of(+levels: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, List.is_empty(&2, String, levels), Nil{}, "" <> levels)

def Effort.known(m: Maybe<&2, J.Json>, +provider: String) -> List<&2, String>:
  match m:
    case Some{+j}:
      AG.Effort.keep(AG.Effort.levels(provider), Models.strs(J.Json.elems(j)))
    case None{}:
      AG.Effort.levels(provider)

def Effort.name(+e: String) -> String:
  Bool.pick(String, String.is_empty(e), "auto", e)

# the model chip's label with the thread's effort
def Effort.label(+label: String, +e: String) -> String:
  Bool.pick(String, String.is_empty(e), label, label ++ " · " ++ e)

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

# "" (commands), "search" (threads and messages) or "files"
def Palette.mode(u: Ui) -> String:
  match u:
    case Ui{_, _, dr, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      Str.get(dr, "@palette.mode")

def Palette.open(u: Ui, +mode: String) -> Ui:
  match u:
    case Ui{st, sel, +dr, live, op, on, now, ad, pa, ve, rid, w, er, note, nf, ob, tr}:
      Ui.flag_on(Ui{st, sel, Map.set(&2, String, Map.set(&2, String, Map.set(&2, String, dr, "@palette", ""), "@palette.i", "0"), "@palette.mode", mode), live, op, on, now, ad, pa, ve, rid, w, er, note, nf, ob, tr}, "palette")

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
   PItem{"Attach a file", "key:attach", ""}, PItem{"Commit & push", "git", "commit_push"}, PItem{"Open pull request", "git", "commit_push_pr"}, PItem{"Revert thread", "revert", "0"},
   PItem{"Settle thread", "settle", ""}, PItem{"Pin thread", "pin", ""}, PItem{"Archive thread", "archive", ""}, PItem{"Unarchive thread", "unarchive", ""}, PItem{"Delete thread", "delete", ""},
   PItem{"Snooze 1 hour", "snooze", "1h"}, PItem{"Snooze until tomorrow 9:00", "snooze", "tomorrow"}, PItem{"Snooze 1 week", "snooze", "1w"}, PItem{"Unsnooze", "snooze", "off"},
   PItem{"Search threads", "key:search", ""}, PItem{"Find file", "key:files", ""},
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

# what the command palette offers for this query, actions first
def Palette.cmds(+u: Ui) -> List<&2, PItem>:
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

# Thread search (ctrl+shift+f)
# ----------------------------
# Titles (fuzzy, FZ.Fuzzy) and message text (every word of the query) of
# every thread; a thread shows once, with the newest message line that
# matches when its title does not.

def Search.line(ls: List<&2, String>, +q: String) -> String:
  match ls:
    case Nil{}:
      ""
    case +l <> t:
      Bool.pick(String, Palette.hit(q, l), String.trim(l), Search.line(t, q))

def Search.put.k(r: Map<&2, String> & String, +th: String, +text: String, +q: String) -> Map<&2, String>:
  (+m, +cur) = r
  Bool.pick(Map<&2, String>, String.is_empty(cur), Map.set(&2, String, m, th, Search.line(String.lines(text), q)), m)

def Search.put(hit: Bool, m: Map<&2, String>, +th: String, +text: String, +q: String) -> Map<&2, String>:
  match hit:
    case True{}:
      Search.put.k(Map.get(String, "", m, th), th, text, q)
    case False{}:
      m

# thread -> the newest matching line of its messages
def Search.snips(es: List<&2, M.Entry>, +q: String, m: Map<&2, String>) -> Map<&2, String>:
  match es:
    case Nil{}:
      m
    case M.Msg{_, +th, _, +text, _} <> t:
      Search.snips(t, q, Search.put(Palette.hit(q, text), m, th, text, q))
    case M.Act{_, _, _, _, _, _} <> t:
      Search.snips(t, q, m)

def Search.one(t: M.Thread, +q: String, +snips: Map<&2, String>, +rest: List<&2, PItem>) -> List<&2, PItem>:
  match t:
    case M.Thread{+id, _, +ti, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, +de}:
      Bool.pick(List<&2, PItem>, de, rest,
        Bool.pick(List<&2, PItem>, Nat.is_gt(FZ.Fuzzy.score(ti, q), 0n), PItem{ti, "select", id} <> rest,
          Bool.pick(List<&2, PItem>, String.is_empty(Str.get(snips, id)), rest, PItem{ti ++ "  ·  " ++ Str.get(snips, id), "select", id} <> rest)))

def Search.all(ts: List<&2, M.Thread>, +q: String, +snips: Map<&2, String>) -> List<&2, PItem>:
  match ts:
    case Nil{}:
      Nil{}
    case t <> rest:
      Search.one(t, q, snips, Search.all(rest, q, snips))

def Search.newer(a: M.Thread, b: M.Thread) -> Bool:
  match a b:
    case M.Thread{_, _, _, _, +x, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} M.Thread{_, _, _, _, +y, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      Nat.is_ge(x, y)

def Search.items.k(empty: Bool, +q: String, +st: M.State) -> List<&2, PItem>:
  match empty:
    case True{}:
      Nil{}
    case False{}:
      Search.all(List.sort(~M.Thread, ~Search.newer, Ui.threads(st)), q, Search.snips(Ui.entries(st), q, Map.new(&2, String)))

# threads whose title or messages hold every word of the query, newest first
def Search.items(+u: Ui) -> List<&2, PItem>:
  Search.items.k(String.is_empty(String.trim(Palette.query(u))), Palette.query(u), Ui.state(u))

# File picker (ctrl+p)
# --------------------
# The selected thread's files (files.list: git ls-files, else a bounded
# walk); picking one mentions it in the draft as @path.

type FRow is Data:
  FRow{score: Nat, path: String}

def FRow.before(a: FRow, b: FRow) -> Bool:
  match a b:
    case FRow{x, _} FRow{y, _}:
      Nat.is_ge(x, y)

def Files.keep(+sc: Nat, +p: String, +rest: List<&2, FRow>) -> List<&2, FRow>:
  Bool.pick(List<&2, FRow>, Bool.and(Nat.is_gt(sc, 0n), Bool.not(String.is_empty(p))), FRow{sc, p} <> rest, rest)

def Files.scored(ps: List<&2, String>, +q: String) -> List<&2, FRow>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      Files.keep(FZ.Fuzzy.score(p, q), p, Files.scored(t, q))

def Files.rows(rs: List<&2, FRow>) -> List<&2, PItem>:
  match rs:
    case Nil{}:
      Nil{}
    case FRow{_, +p} <> t:
      PItem{p, "mention", p} <> Files.rows(t)

# the files that fuzzily match the query, best first
def Files.pick(+ps: List<&2, String>, +q: String) -> List<&2, PItem>:
  Files.rows(List.take(&2, FRow, List.sort(~FRow, ~FRow.before, Files.scored(ps, q)), 200n))

def Files.items.k(same: Bool, +files: String, +q: String) -> List<&2, PItem>:
  match same:
    case True{}:
      Files.pick(String.lines(files), q)
    case False{}:
      Nil{}

def Files.items(+u: Ui) -> List<&2, PItem>:
  Files.items.k(String.eq(Ui.info(u, "files.thread"), Ui.sel(u)), Ui.info(u, "files"), Palette.query(u))

# what the palette offers in its mode
def Palette.items.k(i: Nat, +u: Ui) -> List<&2, PItem>:
  match i:
    case 0n:
      Search.items(u)
    case 1n:
      Files.items(u)
    case _:
      Palette.cmds(u)

def Palette.items(+u: Ui) -> List<&2, PItem>:
  Palette.items.k(Keys.pos(["search", "files"], Palette.mode(u)), u)

# the kind of a row, shown at its right
def Palette.kind(+a: String) -> String:
  Bool.pick(String, String.eq(a, "select"), "thread", Bool.pick(String, String.eq(a, "mention"), "file", "action"))

# Row status
# ----------

def Asks.kind(as: List<&2, M.Ask>, +k: String) -> Bool:
  match as:
    case Nil{}:
      False{}
    case M.Ask{_, _, +x, _, _, _, _, _} <> t:
      Bool.or(String.eq(x, k), Asks.kind(t, k))

# what a thread's dot shows (M.Status.of has the order)
def Side.status(+st: M.State, t: M.Thread) -> M.Status:
  match t:
    case M.Thread{+id, _, _, _, _, turn, +pending, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      M.Status.of(Bool.or(Nat.is_gt(pending, 0n), Asks.kind(Asks.open(st, id), "approval")),
        Bool.or(Asks.kind(Asks.open(st, id), "input"), Asks.kind(Asks.open(st, id), "plan")), turn,
        Bool.not(String.is_empty(M.Queue.of(st, id))))

# when a thread's snooze ends (0: not snoozed)
def Side.until(+st: M.State, +id: String) -> Nat:
  M.Nav.until(M.Nav.get(M.State.navs(st), id))

# Scratch state
# -------------
# Small client-only values (a drag in progress) kept in the drafts map
# under "@" keys, which no thread id takes.

def Ui.scratch(u: Ui, +k: String) -> String:
  match u:
    case Ui{_, _, dr, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      Str.get(dr, k)

def Ui.scratch_set(u: Ui, +k: String, v: String) -> Ui:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, ve, rid, w, er, note, nf, ob, tr}:
      Ui{st, sel, Map.set(&2, String, dr, k, v), live, op, on, now, ad, pa, ve, rid, w, er, note, nf, ob, tr}

def Ui.info_set(u: Ui, +k: String, +v: String) -> Ui:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, ve, rid, w, er, note, +nf, ob, tr}:
      Ui{st, sel, dr, live, op, on, now, ad, pa, ve, rid, w, er, note, Map.set(&2, String, nf, k, v), ob, tr}

# a run of tool calls opened or shut: the value is "1" or "0", then the
# run's id (FO.Fold.ask); the choice is kept in the info map (FO.Fold.user)
def Ui.tool_fold(u: Ui, +v: String) -> Ui:
  Ui.info_set(u, FO.Fold.key(String.drop(v, 1n)), String.take(v, 1n))

def Skills.got(has: Bool, u: Ui, +o: J.Json) -> Ui:
  match has:
    case True{}:
      Ui.info_set(Ui.info_set(u, "skills", J.Json.show(J.Json.get_obj(J.Json.get_obj(o, "result"), "skills"))), "skills.for", J.Json.get_str(J.Json.get_obj(o, "result"), "thread", ""))
    case False{}:
      u

def Skills.fetch(need: Bool, a: Act) -> Act:
  match need a:
    case True{} Act{+u, cs}:
      Ui.also(Ui.on_thread(Ui.info_set(Ui.info_set(u, "skills.for", Ui.sel(u)), "skills", "[]"), "skills.list"), cs)
    case False{} _:
      a

def Skills.want(a: Act) -> Act:
  match a:
    case Act{+u, cs}:
      Skills.fetch(Skills.need(u), Act{u, cs})

# the selected thread's draft; typing a `$` fetches its skills once
def Ui.draft(u: Ui, text: String) -> Act:
  Skills.want(Ui.draft.set(u, text))

# What the machine says about a provider: its CLI version ("" when it is
# not installed) and a label per model
def Models.about(+info: String, +provider: String) -> J.Json:
  J.Json.get_obj(J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(info), J.Null{}), "about"), provider)

# the effort chips for a thread's model: the levels its CLI says that model
# takes (Claude reports them per model), else the provider's
def Effort.chips(+info: String, +provider: String, +model: String) -> List<&2, String>:
  Effort.chips.of(Effort.known(J.Json.get(J.Json.get_obj(Models.about(info, provider), "efforts"), Bool.pick(String, String.is_empty(model), "default", model)), provider))

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

def Ui.rid(u: Ui) -> Nat:
  match u:
    case Ui{_, _, _, _, _, _, _, _, _, _, rid, _, _, _, _, _, _}:
      rid

def Ui.error_put(u: Ui, e: String) -> Ui:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, _, note, nf, ob, tr}:
      Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, e, note, nf, ob, tr}

# a request of the picker's: only the answer to the newest one counts (a
# listing that arrives after the user has moved on is dropped)
def Proj.rpc(+u: Ui, m: String, p: List<&2, J.KV>) -> Act:
  Ui.rpc(Ui.scratch_set(u, "@proj.rid", Nat.show(Ui.rid(u))), m, p)

def Proj.mine(+u: Ui, +o: J.Json) -> Bool:
  Bool.and(Bool.not(String.is_empty(Ui.scratch(u, "@proj.rid"))), String.eq(J.Json.as_raw(J.Json.get(o, "id"), ""), Ui.scratch(u, "@proj.rid")))

def Proj.focus(a: Act) -> Act:
  match a:
    case Act{u, cs}:
      Act{u, List.append(&2, Cmd, cs, [Focus{"proj"}])}

# opens where it was last (home the first time)
def Proj.open(+u: Ui) -> Act:
  Proj.focus(Proj.rpc(Proj.reset(Ui.flag_on(u, "proj"), ""), "fs.list", [J.KV{"path", J.Str{Proj.dir(u)}}]))

def Proj.names(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case J.Str{s} <> t:
      s <> Proj.names(t)
    case _ <> t:
      Proj.names(t)

# names are kept joined by NUL, which no file name holds: split once per
# use rather than parsing JSON every frame
def Proj.sep() -> Char:
  Chr{0}

def Proj.nonempty.k(skip: Bool, x: String, rest: List<&2, String>) -> List<&2, String>:
  match skip:
    case True{}:
      rest
    case False{}:
      x <> rest

def Proj.nonempty(xs: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case +x <> t:
      Proj.nonempty.k(String.is_empty(x), x, Proj.nonempty(t))

# the subfolders of the listed folder
def Proj.entries(u: Ui) -> List<&2, String>:
  Proj.nonempty(String.split(Ui.info(u, "proj.entries"), Proj.sep()))

# what an answer is to the picker: 0 not its newest request's, 1 a
# listing, 2 a project added, 3 an error
def Proj.which(mine: Bool, ok: Bool, dir: Bool) -> Nat:
  match mine ok dir:
    case False{} _ _:
      0n
    case True{} True{} True{}:
      1n
    case True{} True{} False{}:
      2n
    case True{} False{} _:
      3n

# an error shows in the picker while it is open (not also as a toast)
def Proj.failed(open: Bool, u: Ui, +e: String) -> Ui:
  match open:
    case True{}:
      Ui.info_set(Ui.error_put(u, ""), "proj.err", e)
    case False{}:
      u

def Proj.reply.k(i: Nat, +u: Ui, +o: J.Json) -> Ui:
  match i:
    case 1n:
      Ui.info_set(Ui.info_set(Ui.info_set(Ui.scratch_set(u, "@proj.rid", ""), "proj.dir", J.Json.get_str(J.Json.get_obj(o, "result"), "dir", "")), "proj.entries",
        String.join(Proj.names(J.Json.elems(J.Json.get_obj(J.Json.get_obj(o, "result"), "entries"))), SCon{Proj.sep(), SNil{}})), "proj.err", "")
    case 2n:
      Ui.info_set(Ui.flag_off(Ui.scratch_set(u, "@proj.rid", ""), "proj"), "proj.err", "")
    case 3n:
      Proj.failed(Ui.flag(u, "proj"), Ui.scratch_set(u, "@proj.rid", ""), Ui.reply.err(o))
    case _:
      u

# an answer to the picker: a listing replaces the one shown, an added
# project closes it, an error shows in it
def Proj.reply(+o: J.Json, +u: Ui) -> Ui:
  Proj.reply.k(Proj.which(Proj.mine(u, o), J.Json.get_bool(o, "ok", True{}), Bool.not(String.is_empty(J.Json.get_str(J.Json.get_obj(o, "result"), "dir", "")))), u, o)

def Proj.join(+dir: String, +name: String) -> String:
  Bool.pick(String, String.ends_with(dir, "/"), dir ++ name, dir ++ "/" ++ name)

def Proj.parent.k(+ps: List<&2, String>) -> String:
  Bool.pick(String, Nat.is_le(List.length(&2, String, ps), 2n), "/", String.join(List.take(&2, String, ps, Nat.sub(List.length(&2, String, ps), 1n)), "/"))

def Proj.parent(+dir: String) -> String:
  Proj.parent.k(String.split(dir, '/'))

def Proj.plain(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{Chr{+c}, t}:
      Bool.and(Bool.and(U32.is_ge(c, 32), U32.is_ne(c, 127)), Proj.plain(t))

def Proj.name_ok.t(+q: String) -> Bool:
  Bool.and(Bool.and(Bool.not(String.is_empty(q)), Bool.and(Bool.not(String.contains(q, "/")), Proj.plain(q))), Bool.and(Bool.not(String.eq(q, ".")), Bool.not(String.eq(q, ".."))))

# a name a new folder may take (trimmed): not blank, no slash or control
# characters, not "." or ".."
def Proj.name_ok(+q: String) -> Bool:
  Proj.name_ok.t(String.trim(q))

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

# (a match, not Bool.pick: only the list shown is made)
def Proj.items.q(empty: Bool, +u: Ui, +q: String, +dir: String, +ns: List<&2, String>) -> List<&2, PItem>:
  match empty:
    case True{}:
      List.concat(&2, PItem, [Proj.add(u, dir), Bool.pick(List<&2, PItem>, String.eq(dir, "/"), Nil{}, [PItem{"..", "proj-cd", Proj.parent(dir)}]),
        Proj.rows(Proj.scored(ns, q), dir)])
    case False{}:
      List.concat(&2, PItem, [Proj.rows(List.sort(~Scored, ~Scored.before, Proj.scored(ns, q)), dir),
        Bool.pick(List<&2, PItem>, Bool.and(Proj.name_ok(q), Bool.not(Proj.exact(ns, String.trim(q)))),
          [PItem{"Create project '" ++ String.trim(q) ++ "' here", "proj-new", Proj.join(dir, String.trim(q))}, PItem{"Create folder '" ++ String.trim(q) ++ "' here", "proj-mkdir", Proj.join(dir, String.trim(q))}], Nil{}),
        Proj.add(u, dir)])

def Proj.items.k(path: Bool, +u: Ui, +q: String, +dir: String, +ns: List<&2, String>) -> List<&2, PItem>:
  match path:
    case True{}:
      [PItem{"Go to " ++ q, "proj-cd", q}, PItem{"Add " ++ q ++ " as a project", "proj-add", q}, PItem{"Create project " ++ q, "proj-new", q}]
    case False{}:
      Proj.items.q(String.is_empty(q), u, q, dir, ns)

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
      Proj.rpc(Ui.info_set(u, "proj.err", ""), "project.add", [J.KV{"path", J.Str{v}}])
    case 1n:
      Proj.rpc(Proj.reset(u, ""), "fs.list", [J.KV{"path", J.Str{v}}])
    case 2n:
      Proj.rpc(Proj.reset(u, ""), "fs.mkdir", [J.KV{"path", J.Str{v}}])
    case 3n:
      Proj.rpc(Ui.info_set(u, "proj.err", ""), "project.new", [J.KV{"path", J.Str{v}}])
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
      Proj.run.k(Proj.pos(["proj-add", "proj-cd", "proj-mkdir", "proj-new"], a, 0n), u, v)

# Enter runs the selected row
def Proj.enter(+u: Ui) -> Act:
  Proj.run(Palette.at(Proj.items(u), Proj.index(u)), u)

# Attachments
# -----------
# A thread's attachments wait in the drafts map under "@att:<thread>" (a
# path per line) until its message is sent; "@att.up:<thread>" names a file
# still uploading. No thread id starts with '@'.

def Att.keep(skip: Bool, +x: String, rest: List<&2, String>) -> List<&2, String>:
  match skip:
    case True{}:
      rest
    case False{}:
      x <> rest

def Att.nonblank(ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      Att.keep(String.is_empty(String.trim(l)), String.trim(l), Att.nonblank(t))

# the draft, then a line per attachment (attach.bend's format)
def Ui.send(u: Ui) -> Act:
  match u:
    case Ui{st, +sel, +dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}:
      +text = AT.Att.join(String.trim(Str.get(dr, sel)), Att.nonblank(String.lines(Str.get(dr, "@att:" ++ sel))))
      Ui.send.k(String.is_empty(String.trim(text)), Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}, text)

def Att.drop(ps: List<&2, String>, +p: String) -> List<&2, String>:
  match ps:
    case Nil{}:
      Nil{}
    case +x <> t:
      Att.keep(String.eq(x, p), x, Att.drop(t, p))

# what a thread's next message attaches
def Ui.atts(u: Ui, +thread: String) -> List<&2, String>:
  match u:
    case Ui{_, _, dr, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      Att.nonblank(String.lines(Str.get(dr, "@att:" ++ thread)))

# the file a thread is still uploading ("" for none)
def Ui.uploading(u: Ui, +thread: String) -> String:
  match u:
    case Ui{_, _, dr, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      Str.get(dr, "@att.up:" ++ thread)

def Ui.atts_set(u: Ui, +thread: String, ps: List<&2, String>) -> Ui:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}:
      Ui{st, sel, Map.set(&2, String, dr, "@att:" ++ thread, String.join(ps, "\n")), live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}

def Ui.up_set(u: Ui, +thread: String, name: String) -> Ui:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}:
      Ui{st, sel, Map.set(&2, String, dr, "@att.up:" ++ thread, name), live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}

# an upload finished: its path joins the thread's attachments
def Ui.attached(+u: Ui, +thread: String, +path: String) -> Ui:
  Ui.up_set(Ui.atts_set(u, thread, List.append(&2, String, Att.drop(Ui.atts(u, thread), path), [path])), thread, "")

def Ui.reply.att.k(done: Bool, failed: Bool, +thread: String, +path: String, u: Ui) -> Ui:
  match done failed:
    case True{} _:
      Ui.attached(u, thread, path)
    case False{} True{}:
      Ui.up_set(u, thread, "")
    case False{} False{}:
      u

def Ui.reply.att(+r: J.Json, +ok: Bool, u: Ui) -> Ui:
  Ui.reply.att.k(Bool.not(String.is_empty(J.Json.get_str(r, "attached", ""))), Bool.and(Bool.not(ok), J.Json.get_bool(r, "upload", False{})),
    J.Json.get_str(r, "thread", ""), J.Json.get_str(r, "attached", ""), u)

# a diff opens the diff view; a file list (files.list) is kept for the
# file picker; a finished upload becomes an attachment of its thread
def Ui.reply.body(u: Ui, +o: J.Json) -> Ui:
  Ui.reply.att(J.Json.get_obj(o, "result"), J.Json.get_bool(o, "ok", True{}),
    Ui.reply.files(Bool.not(String.eq(J.Json.show(Maybe.default(&2, J.Json, J.Json.get(J.Json.get_obj(o, "result"), "files"), J.Null{})), "null")),
      Ui.reply.diff(Bool.not(String.eq(J.Json.show(Maybe.default(&2, J.Json, J.Json.get(J.Json.get_obj(o, "result"), "diff"), J.Null{})), "null")), u, o), o))

# an answer: its request leaves the outbox; a diff opens the diff view; a
# skills list is kept for the composer
def Ui.reply.skills(u: Ui, +o: J.Json) -> Ui:
  Skills.got(Skills.has(o), Ui.reply.body(u, o), o)

# an answer: its request leaves the outbox; a diff opens the diff view
def Ui.reply(u: Ui, +o: J.Json) -> Ui:
  Proj.reply(o, Ui.reply.skills(u, o))

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
    case 7n:
      Ui.info_merge(u, J.Json.get_obj(o, "info"))
    case _:
      u

# a message from the server
def Ui.recv(u: Ui, +o: J.Json) -> Ui:
  Ui.recv.k(C.Codec.pos(["log", "changes", "delta", "reply", "update", "view", "term", "info"], J.Json.get_str(o, "t", "")), u, o)

# a message from the server, with what to send: a (re)connection (the
# server's log arrives first on each) sends the outbox again, so nothing
# the user sent is lost to a dropped link
def Ui.recv_act(u: Ui, +o: J.Json) -> Act:
  Ui.recv_act.t(String.eq(J.Json.get_str(o, "t", ""), "term"), J.Json.get_str(o, "thread", ""), Ui.recv_act.k(String.eq(J.Json.get_str(o, "t", ""), "log"), Ui.recv(u, o)))

def Ui.error_set(u: Ui, e: String) -> Ui:
  match u:
    case Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, _, note, nf, ob, tr}:
      Ui{st, sel, dr, live, op, on, now, ad, pa, v, rid, w, e, note, nf, ob, tr}

def Ui.attach.k(big: Bool, first: Bool, +u: Ui, +o: J.Json) -> Act:
  match big first:
    case True{} True{}:
      Act{Ui.error_set(u, "attachments are limited to " ++ Nat.show(Nat.div(AT.Att.cap(), 1048576n)) ++ " MB"), Nil{}}
    case True{} False{}:
      Act{u, Nil{}}
    case False{} _:
      Ui.on_thread.p(Bool.pick(Ui, first, Ui.up_set(u, Ui.sel(u), J.Json.get_str(o, "name", "file")), u), "attach.put",
        [J.KV{"key", J.Str{J.Json.get_str(o, "key", "u")}}, J.KV{"name", J.Str{J.Json.get_str(o, "name", "file")}},
         J.KV{"i", J.Num{Nat.show(J.Json.get_nat(o, "i", 0n))}}, J.KV{"last", J.Flag{J.Json.get_bool(o, "last", True{})}},
         J.KV{"data", J.Str{J.Json.get_str(o, "data", "")}}])

# a piece of a file the page read ({key, name, size, i, last, data} with
# data base64): sent to the selected thread's attachments; a file over the
# cap is refused here, before any of it is sent
def Ui.attach.o(+u: Ui, +o: J.Json) -> Act:
  Ui.attach.k(Nat.is_gt(J.Json.get_nat(o, "size", 0n), AT.Att.cap()), Nat.is_eq(J.Json.get_nat(o, "i", 0n), 0n), u, o)

def Ui.attach(+u: Ui, v: String) -> Act:
  Ui.attach.o(u, Maybe.default(&2, J.Json, J.Json.parse(v), J.Null{}))

# files are dragged over the window ("1") or have left it (""); while
# they hover, the composer shows where they drop
def Ui.drop_hover.k(on: Bool, u: Ui) -> Ui:
  match on:
    case True{}:
      Ui.flag_on(u, "drop")
    case False{}:
      Ui.flag_off(u, "drop")

def Ui.drop_hover(u: Ui, +v: String) -> Ui:
  Ui.drop_hover.k(Bool.not(String.is_empty(v)), u)

# a file on the machine the hub runs on (the native window), copied in
def Ui.attach_file(+u: Ui, +path: String) -> Act:
  Ui.on_thread.p(Ui.up_set(u, Ui.sel(u), AT.Att.base(AT.Att.from_uri(path))), "attach.file", [J.KV{"path", J.Str{path}}])

def Ui.detach(+u: Ui, +path: String) -> Act:
  Act{Ui.atts_set(u, Ui.sel(u), Att.drop(Ui.atts(u, Ui.sel(u)), path)), Nil{}}

# "120x30" -> (120, 30), else the default screen
def Term.size.k(ps: List<&2, String>) -> U32 & U32:
  match ps:
    case +c <> +r <> _:
      (U32.from_nat(Maybe.default(&2, Nat, Nat.read(c), 100n)), U32.from_nat(Maybe.default(&2, Nat, Nat.read(r), 24n)))
    case _:
      (100, 24)

# DOM key names and their X keysyms (what VT.Vt.key reads)
def Keys.dom.names() -> List<&2, String>:
  ["Enter", "Backspace", "Tab", "Escape", "ArrowLeft", "ArrowUp", "ArrowRight", "ArrowDown", "Home", "End", "PageUp", "PageDown", "Delete", "Insert",
   "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"]

def Keys.dom.syms() -> List<&2, U32>:
  [65293, 65288, 65289, 65307, 65361, 65362, 65363, 65364, 65360, 65367, 65365, 65366, 65535, 65379,
   65470, 65471, 65472, 65473, 65474, 65475, 65476, 65477, 65478, 65479, 65480, 65481]

def Keys.at(xs: List<&2, U32>, i: Nat) -> U32:
  match xs i:
    case x <> _ 0n:
      x
    case _ <> t 1n+j:
      Keys.at(t, j)
    case Nil{} _:
      0

def Keys.char.k(one: Bool, +cp: U32) -> U32 & U32:
  match one:
    case True{}:
      (Bool.pick(U32, U32.is_lt(cp, 256), cp, (cp + 16777216 : U32)), cp)
    case False{}:
      (0, 0)

def Keys.dom.k(named: Bool, +i: Nat, +k: String) -> U32 & U32:
  match named:
    case True{}:
      (Keys.at(Keys.dom.syms(), i), 0)
    case False{}:
      Keys.char.k(Nat.is_eq(String.length(k), 1n), Char.to_u32(Maybe.default(&2, Char, List.head(&2, Char, String.to_list(k)), ' ')))

# a DOM key name as (keysym, the code point it types); (0, 0) for keys a
# terminal ignores (Shift alone, Meta, ...)
def Keys.dom(+k: String) -> U32 & U32:
  Keys.dom.k(Nat.is_lt(C.Codec.pos(Keys.dom.names(), k), List.length(&2, String, Keys.dom.names())), C.Codec.pos(Keys.dom.names(), k), k)

# the shortcuts a page takes for itself (the rest reach the focused field;
# in the terminal only ctrl+j, so ctrl+d still ends a shell's input)
def Ui.keys(term: Bool) -> List<&2, String>:
  match term:
    case True{}:
      ["ctrl+j"]
    case False{}:
      ["ctrl+j", "ctrl+d"]

def Term.key.k(ks: U32 & U32, +u: Ui, +mods: U32) -> Act:
  (+sym, +cp) = ks
  Bool.pick(Act, U32.is_eq(sym, 0), Act{u, Nil{}}, Ui.term_keys(u, VT.Vt.key(Ui.term(u, Ui.sel(u)), sym, cp, mods)))

def Term.key.p(ps: List<&2, String>, +u: Ui) -> Act:
  match ps:
    case +k <> +m <> _:
      Term.key.k(Keys.dom(k), u, U32.from_nat(Maybe.default(&2, Nat, Nat.read(m), 0n)))
    case _:
      Act{u, Nil{}}

# a key typed into the web page's terminal: "<DOM key>\t<mods>" (mods: 1
# shift, 4 ctrl, 8 alt, as xterm counts them)
def Ui.term_key(+u: Ui, v: String) -> Act:
  Term.key.p(String.split(v, '\t'), u)

def Ui.term_paste(+u: Ui, text: String) -> Act:
  Ui.term_keys(u, VT.Vt.paste(Ui.term(u, Ui.sel(u)), text))

def Term.toggle.k(open: Bool, +u: Ui, +c: U32, +r: U32) -> Act:
  match open:
    case True{}:
      Act{Ui.flag_off(u, "term"), [Focus{"composer"}]}
    case False{}:
      Ui.also(Ui.term_open(Ui.flag_on(u, "term"), U32.max(c, 20), U32.max(r, 5)), [Focus{"term"}])

def Term.toggle.s(sz: U32 & U32, open: Bool, +u: Ui) -> Act:
  (+c, +r) = sz
  Term.toggle.k(open, u, c, r)

# open or close the selected thread's terminal (the web page's ctrl+j and
# button; value "<cols>x<rows>" is the size it has room for)
def Ui.term_toggle(+u: Ui, +size: String) -> Act:
  Term.toggle.s(Term.size.k(String.split(size, 'x')), Ui.flag(u, "term"), u)

def Ui.key.k(i: Nat, +u: Ui, +size: String) -> Act:
  match i:
    case 0n:
      Ui.term_toggle(u, size)
    case 1n:
      Ui.on_thread.p(u, "git.diff", [J.KV{"from", J.Num{"0"}}, J.KV{"to", J.Num{"-1"}}])
    case _:
      Act{u, Nil{}}

def Ui.key.p(ps: List<&2, String>, +u: Ui) -> Act:
  match ps:
    case +k <> +sz <> _:
      Ui.key.k(C.Codec.pos(["ctrl+j", "ctrl+d"], k), u, sz)
    case +k <> Nil{}:
      Ui.key.k(C.Codec.pos(["ctrl+j", "ctrl+d"], k), u, "")
    case Nil{}:
      Act{u, Nil{}}

# a page shortcut: "<combo>\t<terminal size>"
def Ui.key(+u: Ui, v: String) -> Act:
  Ui.key.p(String.split(v, '\t'), u)

# Deleting a thread
# -----------------
# Deleting asks first: "delete" arms it (the header asks to confirm),
# "delete" again deletes the thread and goes back to the start, and
# "delete-no" disarms it. Only the selected thread can be armed, so
# choosing another one disarms it too.

def Ui.deleting(+u: Ui) -> Bool:
  Bool.and(Bool.not(String.is_empty(Ui.sel(u))), String.eq(Ui.scratch(u, "@del"), Ui.sel(u)))

def Ui.unselect(a: Act) -> Act:
  match a:
    case Act{Ui{st, _, dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}, cs}:
      Act{Ui{st, "", dr, live, op, on, now, ad, pa, v, rid, w, er, note, nf, ob, tr}, cs}

def Ui.delete.k(armed: Bool, +u: Ui) -> Act:
  match armed:
    case True{}:
      Ui.unselect(Ui.on_thread(Ui.scratch_set(u, "@del", ""), "thread.delete"))
    case False{}:
      Act{Ui.scratch_set(u, "@del", Ui.sel(u)), Nil{}}

def Ui.delete(+u: Ui) -> Act:
  Ui.delete.k(Ui.deleting(u), u)

# Acting on a thread's row
# ------------------------
# The phone's swipes act on a thread without selecting it: the value is
# its id ("id|1h" for a snooze). Deleting from a row asks first the same
# way: "row-delete id" arms "@del" with that id, the same again deletes
# it, and "delete-no" disarms.

def Ui.on_row(u: Ui, +id: String, m: String) -> Act:
  Ui.rpc(u, m, [J.KV{"thread", J.Str{id}}])

# a right-click on a sidebar row settles it, or brings a settled one back
def Ui.row_toggle.m(sh: M.Shelf) -> String:
  match sh:
    case M.Settled{}:
      "thread.unsettle"
    case _:
      "thread.settle"

def Ui.row_toggle(+u: Ui, +id: String) -> Act:
  Ui.on_row(u, id, Ui.row_toggle.m(M.Shelf.of(Ui.thread(Ui.state(u), id))))

def Ui.row_snooze.k(u: Ui, s: Sect) -> Act:
  match s:
    case Sect{id, t}:
      Ui.rpc(u, "thread.snooze", [J.KV{"thread", J.Str{id}}, J.KV{"for", J.Str{Side.first(t)}}])

def Ui.row_snooze(u: Ui, v: String) -> Act:
  Ui.row_snooze.k(u, Side.pair(String.split(v, '|')))

def Ui.unselect.if(on: Bool, a: Act) -> Act:
  match on:
    case True{}:
      Ui.unselect(a)
    case False{}:
      a

def Ui.row_delete.k(armed: Bool, +u: Ui, +id: String) -> Act:
  match armed:
    case True{}:
      Ui.unselect.if(String.eq(id, Ui.sel(u)), Ui.on_row(Ui.scratch_set(u, "@del", ""), id, "thread.delete"))
    case False{}:
      Act{Ui.scratch_set(u, "@del", id), Nil{}}

# the thread a row asks to delete ("" when none)
def Ui.row_deleting(+u: Ui) -> String:
  Ui.scratch(u, "@del")

def Ui.row_delete(+u: Ui, +id: String) -> Act:
  Ui.row_delete.k(Bool.and(Bool.not(String.is_empty(id)), String.eq(Ui.row_deleting(u), id)), u, id)

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
      Ui.delete(u)
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
    case 33n:
      Ui.on_thread.p(u, "thread.effort", [J.KV{"effort", J.Str{value}}])
    case 34n:
      Ui.skill(u, value)
    case 35n:
      Ui.snooze(u, value)
    case 36n:
      Ui.on_thread(u, "thread.unarchive")
    case 37n:
      Ui.reorder(u, value)
    case 38n:
      Ui.move(u, value)
    case 39n:
      Ui.mention(u, value)
    case 40n:
      Ui.on_thread(u, "files.list")
    case 41n:
      Act{Ui.scratch_set(u, "@del", ""), Nil{}}
    case 42n:
      Proj.run.k(3n, u, value)
    case 49n:
      Act{Ui.drop_hover(u, value), Nil{}}
    case 50n:
      Ui.attach(u, value)
    case 51n:
      Ui.attach_file(u, value)
    case 52n:
      Ui.detach(u, value)
    case 53n:
      Ui.term_toggle(u, value)
    case 54n:
      Ui.term_key(u, value)
    case 55n:
      Ui.term_paste(u, value)
    case 56n:
      Ui.key(u, value)
    case 57n:
      Ui.rpc(u, "update.check", Nil{})
    case 58n:
      Ui.machine(u, value)
    case 59n:
      Ui.on_row(u, value, "thread.settle")
    case 60n:
      Ui.on_row(u, value, "thread.unsettle")
    case 61n:
      Ui.row_snooze(u, value)
    case 62n:
      Ui.row_delete(u, value)
    case 63n:
      Act{Ui.tool_fold(u, value), Nil{}}
    case 64n:
      Ui.row_toggle(u, value)
    case _:
      Act{u, Nil{}}

# a user action with its value
def Ui.act(u: Ui, +action: String, +value: String) -> Act:
  Ui.act.k(C.Codec.pos(Ui.actions(), action), u, value)
