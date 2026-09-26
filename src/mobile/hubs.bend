import Base
import ../core/json.bend as J
import ../core/model.bend as M
import ../core/client.bend as U
import ../core/codec.bend as C
import ./screen.bend as S
import ./notify.bend as N
import ./view.bend as VW
import ./picker.bend as PK
import ../core/botui.bend as BU
import ../core/bot.bend as BT
import ../core/once.bend as O

# The phone keeps every hub it paired with connected at once, each with
# its own client (Ui). A hub's key is its socket's host:port, which the
# app names it by. The screen is all of them in one: every hub's projects
# (tagged with the machine when there are several), alerts and the island
# from all, and the thread of the hub in focus.
#
# Everything a phone sends back names a thread or project by the id the
# screen gave it, and those ids carry their hub: "key|id". Actions on a
# row are routed by that prefix; the rest go to the hub in focus, which
# is the one whose thread was last opened.

type Hub is Data:
  Hub{key: String, ui: U.Ui}

type Hubs is Data:
  Hubs{cid: String, now: Nat, cur: String, hs: List<&2, Hub>}

# a command for one hub's socket
type HCmd is Data:
  HCmd{hub: String, cmd: U.Cmd}

type HAct is Data:
  HAct{hubs: Hubs, cmds: List<&2, HCmd>, alerts: List<&2, J.Json>}

def Hubs.cmds(a: HAct) -> List<&2, HCmd>:
  match a:
    case HAct{_, cs, _}:
      cs

def Hubs.after(a: HAct) -> Hubs:
  match a:
    case HAct{h, _, _}:
      h

def Hub.ui(h: Hub) -> U.Ui:
  match h:
    case Hub{_, u}:
      u

def Hub.key(h: Hub) -> String:
  match h:
    case Hub{k, _}:
      k

def Hubs.init(now: Nat, +cid: String) -> Hubs:
  Hubs{cid, now, "", Nil{}}

# Ids
# ---

# an id of hub k (no id stays none: law hubs_no_id)
def Hubs.id.k(none: Bool, +k: String, +s: String) -> String:
  match none:
    case True{}:
      ""
    case False{}:
      k ++ "|" ++ s

def Hubs.id(+k: String, +s: String) -> String:
  Hubs.id.k(String.is_empty(s), k, s)

# the hub a value names ("" when it names none), and the value without it
def Hubs.key_of(+v: String) -> String:
  Maybe.default(&2, String, List.head(&2, String, String.split(v, '|')), "")

def Hubs.rest.k(xs: List<&2, String>) -> String:
  match xs:
    case Nil{}:
      ""
    case _ <> t:
      String.join(t, "|")

def Hubs.rest(+v: String) -> String:
  Hubs.rest.k(String.split(v, '|'))

# what a field of the screen holds: 1 left alone (a thread's entries, the
# viewer's, model picker's and project picker's own values; the bot, room
# or remote bot shown and the bot and room forms, all of the hub in focus,
# whose actions go there), 2 an id of this hub, 0 anything else
# (asked of every field of the screen, which on a phone made this walk a
# third of a screen's cost: the key's first letters name the one name it
# could be, and one comparison settles it)
type Q4 is Data:
  Q4{a: U32, b: U32, c: U32, d: U32}

def Q.chars(+k: String) -> Q4:
  match k:
    case SCon{Chr{a}, SCon{Chr{b}, SCon{Chr{c}, SCon{Chr{d}, _}}}}:
      Q4{a, b, c, d}
    case SCon{Chr{a}, SCon{Chr{b}, SCon{Chr{c}, SNil{}}}}:
      Q4{a, b, c, 0}
    case SCon{Chr{a}, SCon{Chr{b}, SNil{}}}:
      Q4{a, b, 0, 0}
    case SCon{Chr{a}, SNil{}}:
      Q4{a, 0, 0, 0}
    case SNil{}:
      Q4{0, 0, 0, 0}

# a name, and its kind (1 left alone, 2 an id)
type QN is Data:
  QN{name: String, kind: Nat}

def Q.two(+a: U32, +b: U32, +x: U32, +y: U32) -> Bool:
  Bool.and(U32.is_eq(a, x), U32.is_eq(b, y))

# the only name a key starting a b c d could be ("" for none)
def Q.cand(q: Q4) -> QN:
  match q:
    case Q4{+a, +b, +c, +d}:
      Bool.pick(QN, Q.two(a, b, 101, 110), QN{"entries", 1n},
      Bool.pick(QN, Q.two(a, b, 108, 105), QN{"live", 1n},
      Bool.pick(QN, Q.two(a, b, 118, 105), QN{"viewer", 1n},
      Bool.pick(QN, Q.two(a, b, 118, 97), QN{"value", 2n},
      Bool.pick(QN, Q.two(a, b, 98, 108), QN{"blocks", 1n},
      Bool.pick(QN, Q.two(a, b, 98, 111), QN{"bot", 1n},
      Bool.pick(QN, Q.two(a, b, 112, 105), QN{"picker", 1n},
      Bool.pick(QN, Q.two(a, b, 102, 111), QN{"folders", 1n},
      Bool.pick(QN, Q.two(a, b, 102, 105), QN{"find", 1n},
      Bool.pick(QN, Q.two(a, b, 97, 115), QN{"asks", 1n},
      Bool.pick(QN, Q.two(a, b, 97, 116), QN{"attaching", 1n},
      Bool.pick(QN, Q.two(a, b, 109, 101), QN{"menu", 1n},
      Bool.pick(QN, Q.two(a, b, 100, 105), QN{"diff", 1n},
      Bool.pick(QN, Q.two(a, b, 116, 101), QN{"term", 1n},
      Bool.pick(QN, Q.two(a, b, 116, 104), QN{"thread", 2n},
      Bool.pick(QN, Q.two(a, b, 115, 107), QN{"skills", 1n},
      Bool.pick(QN, Bool.and(Q.two(a, b, 115, 101), U32.is_eq(c, 116)), QN{"settings", 1n},
      Bool.pick(QN, Bool.and(Q.two(a, b, 115, 101), U32.is_eq(c, 108)), QN{"sel", 2n},
      Bool.pick(QN, Bool.and(Q.two(a, b, 110, 101), U32.is_eq(d, 66)), QN{"newBot", 1n},
      Bool.pick(QN, Bool.and(Q.two(a, b, 110, 101), U32.is_eq(d, 82)), QN{"newRoom", 1n},
      Bool.pick(QN, Q.two(a, b, 105, 100), QN{"id", 2n}, QN{"", 0n})))))))))))))))))))))

def Q.kind.k(n: QN, +k: String) -> Nat:
  match n:
    case QN{+name, kind}:
      Bool.pick(Nat, Bool.and(Bool.not(String.is_empty(name)), String.eq(k, name)), kind, 0n)

def Q.kind(+k: String) -> Nat:
  Q.kind.k(Q.cand(Q.chars(k)), k)

# a hub's screen (or alerts) with every id made that hub's
def Q.walk(j: J.Json, +p: String, mode: Nat) -> J.Json:
  match j mode:
    case x 1n:
      x
    case J.Str{s} 2n:
      J.Str{Hubs.id(p, s)}
    case J.Obj{fs} _:
      J.Obj{Q.walk(fs, p, 0n)}
    case J.Arr{xs} _:
      J.Arr{Q.walk(xs, p, 0n)}
    case J.Item{h, t} _:
      J.Item{Q.walk(h, p, 0n), Q.walk(t, p, 0n)}
    case J.Field{+k, v, t} _:
      J.Field{k, Q.walk(v, p, Q.kind(k)), Q.walk(t, p, 0n)}
    case x _:
      x

def Q.all(j: J.Json, +p: String) -> J.Json:
  Q.walk(j, p, 0n)

# One hub's client
# ----------------

# a bot form shut (only those: the value names a scratch key)
def One.close(+u: U.Ui, +k: String) -> U.Ui:
  Bool.pick(U.Ui, Nat.is_lt(C.Codec.pos(["@bnew", "@rnew", "@onew"], k), 3n), U.Ui.scratch_set(u, k, ""), u)

# an action, as a phone's one client takes it: "view" opens or closes the
# board viewer ("board", "schematic", "3d", ""), "view-pick" inspects a
# tap, "view-unpick" closes the card, "view-mention" puts the inspected
# item into the draft; "picker-open" opens the project picker at ~/,
# "picker-type" is its field's new text (typed, or a folder tapped),
# "picker-mkdir" makes a folder and goes into it; "find-open" opens
# thread search ("search") or the file picker ("files", which asks for the
# thread's files), "find-q" sets its query, "find-close" closes it; "form-close" shuts a bot
# form ("@bnew", "@rnew", "@onew"; the phones' cancel); any action that moves to another project re-aims
# the viewer
def One.find(files: Bool, +u: U.Ui, +mode: String) -> U.Act:
  match files:
    case True{}:
      U.Ui.act(U.Palette.open(u, mode), "files", "")
    case False{}:
      U.Act{U.Palette.open(u, mode), Nil{}}

def One.act.k(i: Nat, +u: U.Ui, +action: String, +value: String) -> U.Act:
  match i:
    case 0n:
      VW.View.open(u, value)
    case 1n:
      VW.View.mention(u, value)
    case 2n:
      VW.View.pick(u, value)
    case 3n:
      U.Act{VW.Pick.clear(u), Nil{}}
    case 4n:
      PK.MPick.open(u)
    case 5n:
      PK.MPick.type(u, value)
    case 6n:
      PK.MPick.mkdir(u, value)
    case 7n:
      One.find(String.eq(value, "files"), u, value)
    case 8n:
      U.Act{U.Palette.set(u, value, 0n), Nil{}}
    case 9n:
      U.Act{U.Ui.flag_off(u, "palette"), Nil{}}
    case 10n:
      U.Act{One.close(u, value), Nil{}}
    case 11n:
      VW.View.sheet.pick(u, value)
    case 12n:
      VW.View.layer(u, value)
    case 13n:
      VW.View.parts(u)
    case _:
      VW.View.sync(U.Ui.act(u, action, value))

def One.act(+u: U.Ui, +action: String, +value: String) -> U.Act:
  One.act.k(C.Codec.pos(["view", "view-mention", "view-pick", "view-unpick", "picker-open", "picker-type", "picker-mkdir", "find-open", "find-q", "find-close", "form-close", "view-sheet", "view-layer", "view-parts"], action), u, action, value)

# what a step does to one hub's client
type Op is Data:
  Do{action: String, value: String}
  Got{o: J.Json}
  On{b: Bool}
  Tick{now: Nat}
  Reg{platform: String, token: String, kind: String, thread: String, env: String, bundle: String}

type Did is Data:
  Did{act: U.Act, alerts: List<&2, J.Json>}

def One.got.k(+seen: List<&2, N.Seen>, a: U.Act) -> Did:
  match a:
    case U.Act{+u, cmds}:
      Did{U.Act{u, cmds}, N.Note.alerts(U.Ui.threads(S.Mob.st(u)), seen, S.Mob.st(u), U.Ui.entries(S.Mob.st(u)))}

def One.got.seen(a: U.Act) -> U.Act:
  match a:
    case U.Act{u, cmds}:
      U.Act{PK.MPick.seen(u), cmds}

# a frame from the hub, and the alerts it raised
def One.got(+u: U.Ui, +o: J.Json) -> Did:
  One.got.k(N.Note.seen(U.Ui.threads(S.Mob.st(u))), One.got.seen(U.Ui.recv_act(VW.View.sheets(VW.View.picked(u, o), o), o)))

def One.run(op: Op, +u: U.Ui) -> Did:
  match op:
    case Do{+a, +v}:
      Did{One.act(u, a, v), Nil{}}
    case Got{+o}:
      One.got(u, o)
    case On{b}:
      Did{VW.View.online(u, b), Nil{}}
    case Tick{now}:
      Did{U.Act{U.Ui.tick(u, now), Nil{}}, Nil{}}
    case Reg{p, t, k, th, e, b}:
      Did{U.Ui.rpc.keep(u, "device.register", [J.KV{"platform", J.Json.str(p)}, J.KV{"token", J.Json.str(t)},
        J.KV{"kind", J.Json.str(k)}, J.KV{"thread", J.Json.str(th)}, J.KV{"env", J.Json.str(e)}, J.KV{"bundle", J.Json.str(b)}]), Nil{}}

# Steps over the hubs
# -------------------

type Step is Data:
  Step{hs: List<&2, Hub>, cmds: List<&2, HCmd>, alerts: List<&2, J.Json>}

def Step.hs(s: Step) -> List<&2, Hub>:
  match s:
    case Step{hs, _, _}:
      hs

def Hubs.tag(cs: List<&2, U.Cmd>, +k: String) -> List<&2, HCmd>:
  match cs:
    case Nil{}:
      Nil{}
    case c <> t:
      HCmd{k, c} <> Hubs.tag(t, k)

def Hubs.qual(xs: List<&2, J.Json>, +k: String) -> List<&2, J.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      Q.all(x, k) <> Hubs.qual(t, k)

def Hubs.put(d: Did, +k: String, rest: Step) -> Step:
  match d rest:
    case Did{U.Act{u, cs}, al} Step{hs, cmds, als}:
      Step{Hub{k, u} <> hs, List.append(&2, HCmd, Hubs.tag(cs, k), cmds), List.append(&2, J.Json, Hubs.qual(al, k), als)}

def Hubs.keep(h: Hub, rest: Step) -> Step:
  match rest:
    case Step{hs, cmds, als}:
      Step{h <> hs, cmds, als}

def Hubs.one(h: Hub, +op: Op, rest: Step) -> Step:
  match h:
    case Hub{+k, +u}:
      Hubs.put(One.run(op, u), k, rest)

def Hubs.pick(hit: Bool, h: Hub, +op: Op, rest: Step) -> Step:
  match hit:
    case True{}:
      Hubs.one(h, op, rest)
    case False{}:
      Hubs.keep(h, rest)

# op on hub `key`, or on every hub
def Hubs.run(hs: List<&2, Hub>, +all: Bool, +key: String, +op: Op) -> Step:
  match hs:
    case Nil{}:
      Step{Nil{}, Nil{}, Nil{}}
    case +h <> t:
      Hubs.pick(Bool.or(all, String.eq(Hub.key(h), key)), h, op, Hubs.run(t, all, key, op))

def Hubs.done(+cid: String, +now: Nat, +cur: String, s: Step) -> HAct:
  match s:
    case Step{hs, cmds, als}:
      HAct{Hubs{cid, now, cur, hs}, cmds, als}

def Hubs.step(hs: Hubs, +all: Bool, +key: String, +op: Op) -> HAct:
  match hs:
    case Hubs{+cid, +now, +cur, list}:
      Hubs.done(cid, now, cur, Hubs.run(list, all, key, op))

def Hubs.has(hs: List<&2, Hub>, +key: String) -> Bool:
  match hs:
    case Nil{}:
      False{}
    case +h <> t:
      Bool.or(String.eq(Hub.key(h), key), Hubs.has(t, key))

# The bridge's calls
# ------------------

def Hubs.find(hs: List<&2, Hub>, +key: String) -> Maybe<&2, Hub>:
  match hs:
    case Nil{}:
      None{}
    case +h <> t:
      Bool.pick(Maybe<&2, Hub>, String.eq(Hub.key(h), key), Some{h}, Hubs.find(t, key))

def Hubs.made(+m: Maybe<&2, Hub>, +k: String, +cid: String, +now: Nat) -> Hub:
  match m:
    case Some{h}:
      h
    case None{}:
      Hub{k, U.Ui.set_cid(U.Ui.init(now), cid)}

def Hubs.set.go(ks: List<&2, String>, +old: List<&2, Hub>, +cid: String, +now: Nat) -> List<&2, Hub>:
  match ks:
    case Nil{}:
      Nil{}
    case +k <> t:
      Hubs.made(Hubs.find(old, k), k, cid, now) <> Hubs.set.go(t, old, cid, now)

def Hubs.first(hs: List<&2, Hub>) -> String:
  match hs:
    case Nil{}:
      ""
    case h <> _:
      Hub.key(h)

def Hubs.set.k(+cid: String, +now: Nat, +cur: String, +hs: List<&2, Hub>) -> Hubs:
  Hubs{cid, now, Bool.pick(String, Hubs.has(hs, cur), cur, Hubs.first(hs)), hs}

# the hubs the phone is paired with, in its order: a new one gets a new
# client, one no longer paired is dropped with all it held, and the focus
# stays where it was while that hub stays
def Hubs.set(hs: Hubs, ks: List<&2, String>) -> Hubs:
  match hs:
    case Hubs{+cid, +now, +cur, +list}:
      Hubs.set.k(cid, now, cur, Hubs.set.go(ks, list, cid, now))

# a hub's client (a fresh one for a key it does not hold)
def Hubs.ui(hs: Hubs, +key: String) -> U.Ui:
  match hs:
    case Hubs{+cid, +now, _, +list}:
      Hub.ui(Hubs.made(Hubs.find(list, key), key, cid, now))

def Hubs.recv(hs: Hubs, +key: String, o: J.Json) -> HAct:
  Hubs.step(hs, False{}, key, Got{o})

def Hubs.online(hs: Hubs, +key: String, b: Bool) -> HAct:
  Hubs.step(hs, False{}, key, On{b})

def Hubs.now(hs: Hubs, now: Nat) -> Hubs:
  match hs:
    case Hubs{cid, _, cur, list}:
      Hubs{cid, now, cur, list}

def Hubs.tick(hs: Hubs, +now: Nat) -> HAct:
  Hubs.step(Hubs.now(hs, now), True{}, "", Tick{now})

# this phone's push tokens go to every hub it is paired with
def Hubs.register(hs: Hubs, p: String, t: String, k: String, th: String, e: String, b: String) -> HAct:
  Hubs.step(hs, True{}, "", Reg{p, t, k, th, e, b})

# Actions
# -------

# actions whose value names a row, a project, a bot or room, or (opening
# the project picker or a bot or room form, adding a project) a hub: they
# go to the hub it names; the first nine also bring it into focus, so the
# picker's, the bot's and the forms' own actions follow it
def Hubs.routed(+action: String) -> Nat:
  C.Codec.pos(["select", "new-thread", "picker-open", "bot", "room", "remote", "bot-new", "room-new", "proj-go",
    "row-settle", "row-unsettle", "row-snooze", "row-delete", "toggle-settled", "add-project", "proj-remove"], action)

def Hubs.moves() -> Nat:
  9n

def Hubs.routes() -> Nat:
  16n

# answers to what any hub may be showing (its error, a delete or remove
# to confirm); the project search is every hub's at once, since the list
# it filters spans them all ("proj-find", "proj-find-q", unrouted, go to all)
def Hubs.everywhere(+action: String) -> Bool:
  Nat.is_lt(C.Codec.pos(["dismiss", "delete-no", "proj-keep", "proj-find", "proj-find-q"], action), 5n)

# of what the hub let go says, only what it sends (its viewer's watch
# ends); its focus and scroll are for a screen no longer shown
def Hubs.sends(cs: List<&2, HCmd>) -> List<&2, HCmd>:
  match cs:
    case Nil{}:
      Nil{}
    case HCmd{k, U.Send{t}} <> r:
      HCmd{k, U.Send{t}} <> Hubs.sends(r)
    case _ <> r:
      Hubs.sends(r)

def Hubs.then.k(cmds: List<&2, HCmd>, als: List<&2, J.Json>, +cid: String, +now: Nat, +cur: String, s: Step) -> HAct:
  match s:
    case Step{hs2, cmds2, als2}:
      HAct{Hubs{cid, now, cur, hs2}, List.append(&2, HCmd, cmds, cmds2), List.append(&2, J.Json, als, als2)}

def Hubs.then(s: Step, +cid: String, +now: Nat, +cur: String, +key: String, +op: Op) -> HAct:
  match s:
    case Step{hs, cmds, als}:
      Hubs.then.k(Hubs.sends(cmds), als, cid, now, cur, Hubs.run(hs, False{}, key, op))

def Op.action(op: Op) -> String:
  match op:
    case Do{a, _}:
      a
    case _:
      ""

# into another hub's thread: the hub in focus lets go of its own first
# (closing its viewer), then the other takes the action
def Hubs.focus(move: Bool, hs: Hubs, +key: String, +op: Op) -> HAct:
  match move hs:
    case True{} Hubs{+cid, +now, +cur, list}:
      Hubs.then(Hubs.run(list, False{}, cur, Do{"select", ""}), cid, now, key, key, op)
    case False{} Hubs{+cid, +now, +cur, list}:
      Hubs.step(Hubs{cid, now, cur, list}, Hubs.everywhere(Op.action(op)), key, op)

# (matches, not Bool.pick: an unrouted value, which may be a big piece of
# an upload, is never split)
def Hubs.act.k(+hs: Hubs, +cur: String, known: Bool, +action: String, +value: String) -> HAct:
  match known:
    case True{}:
      Hubs.focus(Bool.and(Nat.is_lt(Hubs.routed(action), Hubs.moves()), Bool.not(String.eq(Hubs.key_of(value), cur))), hs, Hubs.key_of(value), Do{action, Hubs.rest(value)})
    case False{}:
      Hubs.focus(False{}, hs, cur, Do{action, value})

def Hubs.cur(hs: Hubs) -> String:
  match hs:
    case Hubs{_, _, c, _}:
      c

def Hubs.list(hs: Hubs) -> List<&2, Hub>:
  match hs:
    case Hubs{_, _, _, l}:
      l

def Hubs.act.r(routed: Bool, +hs: Hubs, +action: String, +value: String) -> HAct:
  match routed:
    case True{}:
      Hubs.act.k(hs, Hubs.cur(hs), Hubs.has(Hubs.list(hs), Hubs.key_of(value)), action, value)
    case False{}:
      Hubs.act.k(hs, Hubs.cur(hs), False{}, action, value)

def Hubs.act.one(+hs: Hubs, +action: String, +value: String) -> HAct:
  Hubs.act.r(Nat.is_lt(Hubs.routed(action), Hubs.routes()), hs, action, value)

def Hubs.act.then(a: HAct, b: HAct) -> HAct:
  match a b:
    case HAct{_, cs, als} HAct{h, cs2, als2}:
      HAct{h, List.append(&2, HCmd, cs, cs2), List.append(&2, J.Json, als, als2)}

def Hubs.act.go.after(+a: HAct, +action: String, +value: String) -> HAct:
  Hubs.act.then(a, Hubs.act.one(Hubs.after(a), action, value))

def Hubs.act.go.k(go: Bool, +hs: Hubs, +action: String, +value: String) -> HAct:
  match go:
    case True{}:
      Hubs.act.go.after(Hubs.act.one(hs, "proj-find", "off"), action, value)
    case False{}:
      Hubs.act.one(hs, action, value)

# going to a found project shuts the search on every hub, then goes
def Hubs.act(+hs: Hubs, +action: String, +value: String) -> HAct:
  Hubs.act.go.k(String.eq(action, "proj-go"), hs, action, value)

def Hubs.self(+u: U.Ui) -> String:
  J.Json.get_str(J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(U.Ui.info(u, "machines")), J.Null{}), "self"), "name", "")

# The screen
# ----------

# what a hub calls itself, else its host
def Hubs.name(+key: String, +u: U.Ui) -> String:
  Bool.pick(String, String.is_empty(Hubs.self(u)), Maybe.default(&2, String, List.head(&2, String, String.split(key, ':')), key), Hubs.self(u))

type Shown is Data:
  Shown{key: String, name: String, j: J.Json}

def Hubs.shown(hs: List<&2, Hub>) -> List<&2, Shown>:
  match hs:
    case Nil{}:
      Nil{}
    case Hub{+k, +u} <> t:
      Shown{k, Hubs.name(k, u), Q.all(S.Mob.screen(u), k)} <> Hubs.shown(t)

def Hubs.named(ss: List<&2, Shown>, +n: String) -> Nat:
  match ss:
    case Nil{}:
      0n
    case Shown{_, +m, _} <> t:
      Nat.add(Bool.pick(Nat, String.eq(String.to_lower(m), String.to_lower(n)), 1n, 0n), Hubs.named(t, n))

def Hubs.relabel.go(ss: List<&2, Shown>, +all: List<&2, Shown>) -> List<&2, Shown>:
  match ss:
    case Nil{}:
      Nil{}
    case Shown{+k, +n, j} <> t:
      Shown{k, Bool.pick(String, Nat.is_gt(Hubs.named(all, n), 1n), n ++ " (" ++ k ++ ")", n), j} <> Hubs.relabel.go(t, all)

# two paired machines with one name (any case) are told apart by their key
def Hubs.relabel(+ss: List<&2, Shown>) -> List<&2, Shown>:
  Hubs.relabel.go(ss, ss)

def Shown.j(s: Shown) -> J.Json:
  match s:
    case Shown{_, _, j}:
      j

def Hubs.of(ss: List<&2, Shown>, +key: String) -> J.Json:
  match ss:
    case Nil{}:
      J.Null{}
    case Shown{+k, _, +j} <> t:
      Bool.pick(J.Json, String.eq(k, key), j, Hubs.of(t, key))

def Hubs.all_on(ss: List<&2, Shown>) -> Bool:
  match ss:
    case Nil{}:
      True{}
    case +s <> t:
      Bool.and(J.Json.get_bool(Shown.j(s), "online", False{}), Hubs.all_on(t))

# the first hub's non-empty string at k
def Hubs.said(ss: List<&2, Shown>, +k: String) -> String:
  match ss:
    case Nil{}:
      ""
    case +s <> t:
      Bool.pick(String, String.is_empty(J.Json.get_str(Shown.j(s), k, "")), Hubs.said(t, k), J.Json.get_str(Shown.j(s), k, ""))

def Hubs.nonnull(+j: J.Json) -> Bool:
  match j:
    case J.Null{}:
      False{}
    case _:
      True{}

def Hubs.first_obj(ss: List<&2, Shown>, +k: String) -> J.Json:
  match ss:
    case Nil{}:
      J.Null{}
    case +s <> t:
      Bool.pick(J.Json, Hubs.nonnull(J.Json.get_obj(Shown.j(s), k)), J.Json.get_obj(Shown.j(s), k), Hubs.first_obj(t, k))

# a project row, named by its machine when there are several
def Hubs.machine(p: J.Json, +name: String) -> J.Json:
  match p:
    case J.Obj{fs}:
      J.Obj{J.Field{"machine", J.Str{name}, fs}}
    case x:
      x

def Hubs.machines(ps: List<&2, J.Json>, +name: String) -> List<&2, J.Json>:
  match ps:
    case Nil{}:
      Nil{}
    case p <> t:
      Hubs.machine(p, name) <> Hubs.machines(t, name)

def Hubs.projects(ss: List<&2, Shown>, +many: Bool) -> List<&2, J.Json>:
  match ss:
    case Nil{}:
      Nil{}
    case Shown{_, +n, +j} <> t:
      List.append(&2, J.Json, Hubs.machines(J.Json.elems(J.Json.get_obj(j, "projects")), Bool.pick(String, many, n, "")), Hubs.projects(t, many))

# every hub's list at k (bots, rooms), named by machine when there are several
def Hubs.all(ss: List<&2, Shown>, +k: String, +many: Bool) -> List<&2, J.Json>:
  match ss:
    case Nil{}:
      Nil{}
    case Shown{_, +n, +j} <> t:
      List.append(&2, J.Json, Hubs.machines(J.Json.elems(J.Json.get_obj(j, k)), Bool.pick(String, many, n, "")), Hubs.all(t, k, many))

# rooms keyed by their id as their own hub gives it (a room shared by two
# machines is one room, whichever hub reports it)
def Hubs.rkeyed(rs: List<&2, J.Json>) -> List<&2, BU.RK<J.Json>>:
  match rs:
    case Nil{}:
      Nil{}
    case +r <> t:
      BU.RK{Hubs.rest(J.Json.get_str(r, "id", "")), r} <> Hubs.rkeyed(t)

# every hub's rooms, each room once (law hubs_rooms_listed_once)
def Hubs.rooms.keyed(ss: List<&2, Shown>, +many: Bool) -> List<&2, BU.RK<J.Json>>:
  BU.BU.once.of(J.Json, Hubs.rkeyed(Hubs.all(ss, "rooms", many)))

def Hubs.rooms(ss: List<&2, Shown>, +many: Bool) -> List<&2, J.Json>:
  BU.BU.once.vals(J.Json, Hubs.rooms.keyed(ss, many))

def Hubs.lines(ss: List<&2, Shown>) -> List<&2, J.Json>:
  match ss:
    case Nil{}:
      Nil{}
    case +s <> t:
      List.append(&2, J.Json, J.Json.elems(J.Json.get_obj(J.Json.get_obj(Shown.j(s), "island"), "lines")), Hubs.lines(t))

def Hubs.rows(ss: List<&2, Shown>) -> List<&2, J.Json>:
  match ss:
    case Nil{}:
      Nil{}
    case Shown{+k, +n, +j} <> t:
      J.Json.obj([J.KV{"key", J.Json.str(k)}, J.KV{"name", J.Json.str(n)}, J.KV{"online", J.Json.bool(J.Json.get_bool(j, "online", False{}))}]) <> Hubs.rows(t)

# the host:port of a hub's url (http://host:3787 -> host:3787)
def Hubs.auth(+url: String) -> String:
  Bool.pick(String, String.contains(url, "://"),
    Maybe.default(&2, String, List.get(&2, String, String.split(url, '/'), 2n), ""),
    Maybe.default(&2, String, List.head(&2, String, String.split(url, '/')), ""))

# Bots over every paired hub
# --------------------------
# A hub lists its own bots and those of the machines it is linked to, so a
# phone paired with two linked hubs would list each bot twice: from its own
# hub, and as name@machine from the other. Each bot is keyed by what it
# stands for and kept once (law hubs_bots_once): a hub's own bot as
# "key|id"; a bot elsewhere, when another paired hub holds that link (or is
# the machine at its url) and has a bot of that name, as that hub's own
# bot; else by its machine's host:port and its name, so two hubs reporting
# the same machine agree. Every hub's own bots come first, so a bot shows
# as its own hub's.

def Hubs.state(h: Hub) -> M.State:
  U.Ui.state(Hub.ui(h))

def Hubs.bot.id(m: Maybe<&2, BT.Bot>) -> String:
  match m:
    case Some{b}:
      BT.Bot.id(b)
    case None{}:
      ""

def Hubs.peer.url(m: Maybe<&2, BT.Peer>) -> String:
  match m:
    case Some{BT.Peer{_, _, u, _, _}}:
      u
    case None{}:
      ""

def Hubs.twin.k(hit: Bool, +k: String, +id: String, +rest: String) -> String:
  Bool.pick(String, Bool.and(hit, Bool.not(String.is_empty(id))), k ++ "|" ++ id, rest)

# whether hub k (not `from`) is the machine a link or an url leads to
def Hubs.twin.is(+k: String, +st: M.State, +from: String, +link: String, +at: String) -> Bool:
  Bool.and(Bool.not(String.eq(k, from)),
    Bool.or(Bool.and(Bool.not(String.is_empty(link)), BT.Maybe.is(BT.Peer, BT.Peer.by.id(BT.World.peers(M.State.bots(st)), link))),
      Bool.and(Bool.not(String.is_empty(at)), String.eq(k, at))))

# that hub's own bot of the name, as "key|id" ("" when no paired hub is it)
def Hubs.twin(hs: List<&2, Hub>, +from: String, +link: String, +at: String, +name: String) -> String:
  match hs:
    case Nil{}:
      ""
    case +h <> t:
      Hubs.twin.k(Hubs.twin.is(Hub.key(h), Hubs.state(h), from, link, at), Hub.key(h),
        Hubs.bot.id(BT.World.find(M.State.bots(Hubs.state(h)), name)), Hubs.twin(t, from, link, at, name))

def Hubs.of.key(hs: List<&2, Hub>, +k: String) -> M.State:
  match hs:
    case Nil{}:
      M.State.empty()
    case +h <> t:
      Bool.pick(M.State, String.eq(Hub.key(h), k), Hubs.state(h), Hubs.of.key(t, k))

def Hubs.far.k(+twin: String, +at: String, +own: String, +name: String) -> String:
  Bool.pick(String, String.is_empty(twin), Bool.pick(String, String.is_empty(at), own, "@" ++ at ++ "|" ++ String.to_lower(name)), twin)

def Hubs.far.at(+st: M.State, +link: String) -> String:
  Bool.pick(String, String.is_empty(Hubs.peer.url(BT.Peer.by.id(BT.World.peers(M.State.bots(st)), link))), "",
    Hubs.auth(Hubs.peer.url(BT.Peer.by.id(BT.World.peers(M.State.bots(st)), link))))

def Hubs.far.key(+hs: List<&2, Hub>, +from: String, +at: String, +r: J.Json) -> String:
  Hubs.far.k(Hubs.twin(hs, from, J.Json.get_str(r, "link", ""), at, J.Json.get_str(r, "name", "")), at,
    from ++ "|" ++ J.Json.get_str(r, "key", ""), J.Json.get_str(r, "name", ""))

# what a row of hub `from` stands for
def Hubs.bot.key(+hs: List<&2, Hub>, +from: String, +r: J.Json) -> String:
  Bool.pick(String, J.Json.get_bool(r, "remote", False{}),
    Hubs.far.key(hs, from, Hubs.far.at(Hubs.of.key(hs, from), J.Json.get_str(r, "link", "")), r),
    from ++ "|" ++ J.Json.get_str(r, "key", ""))

def Hubs.bot.keep(+far: Bool, +want: Bool, +hs: List<&2, Hub>, +from: String, +r: J.Json, rest: List<&2, O.Ky<J.Json>>) -> List<&2, O.Ky<J.Json>>:
  BT.Post.keep(O.Ky<J.Json>, Bool.pick(Bool, want, far, Bool.not(far)), O.Ky{Hubs.bot.key(hs, from, r), r}, rest)

def Hubs.bot.rows(rs: List<&2, J.Json>, +want: Bool, +hs: List<&2, Hub>, +from: String) -> List<&2, O.Ky<J.Json>>:
  match rs:
    case Nil{}:
      Nil{}
    case +r <> t:
      Hubs.bot.keep(J.Json.get_bool(r, "remote", False{}), want, hs, from, r, Hubs.bot.rows(t, want, hs, from))

# every hub's own bots (want False) or those elsewhere (want True), keyed
def Hubs.bots.of(ss: List<&2, Shown>, +want: Bool, +hs: List<&2, Hub>, +many: Bool) -> List<&2, O.Ky<J.Json>>:
  match ss:
    case Nil{}:
      Nil{}
    case Shown{+k, +n, +j} <> t:
      List.append(&2, O.Ky<J.Json>, Hubs.bot.rows(Hubs.machines(J.Json.elems(J.Json.get_obj(j, "bots")), Bool.pick(String, many, n, "")), want, hs, k),
        Hubs.bots.of(t, want, hs, many))

def Hubs.bots.src(+ss: List<&2, Shown>, +hs: List<&2, Hub>, +many: Bool) -> List<&2, O.Ky<J.Json>>:
  List.append(&2, O.Ky<J.Json>, Hubs.bots.of(ss, False{}, hs, many), Hubs.bots.of(ss, True{}, hs, many))

def Hubs.bots.keyed(+ss: List<&2, Shown>, +hs: List<&2, Hub>, +many: Bool) -> List<&2, O.Ky<J.Json>>:
  O.Once.of(J.Json, Hubs.bots.src(ss, hs, many))

# the cats of every paired hub, each bot once
def Hubs.bots(+ss: List<&2, Shown>, +hs: List<&2, Hub>, +many: Bool) -> List<&2, J.Json>:
  O.Once.vals(J.Json, Hubs.bots.keyed(ss, hs, many))

def Hubs.peer(skip: Bool, +p: J.Json, rest: List<&2, J.Json>) -> List<&2, J.Json>:
  match skip:
    case True{}:
      rest
    case False{}:
      J.Json.obj([J.KV{"name", J.Json.str(J.Json.get_str(p, "name", ""))}, J.KV{"url", J.Json.str(J.Json.get_str(p, "url", ""))}]) <> rest

def Hubs.known(ks: List<&2, String>, +a: String) -> Bool:
  match ks:
    case Nil{}:
      False{}
    case k <> t:
      Bool.or(String.eq(k, a), Hubs.known(t, a))

# peers a hub knows of, not paired yet: each once, the first hub's first
def Hubs.peers(ps: List<&2, J.Json>, +ks: List<&2, String>) -> List<&2, J.Json>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      Hubs.peer(Bool.or(String.is_empty(J.Json.get_str(p, "url", "")), Hubs.known(ks, Hubs.auth(J.Json.get_str(p, "url", "")))), p,
        Hubs.peers(t, Hubs.auth(J.Json.get_str(p, "url", "")) <> ks))

def Hubs.peer_lists(hs: List<&2, Hub>) -> List<&2, J.Json>:
  match hs:
    case Nil{}:
      Nil{}
    case Hub{_, +u} <> t:
      List.append(&2, J.Json, J.Json.elems(J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(U.Ui.info(u, "machines")), J.Null{}), "peers")), Hubs.peer_lists(t))

def Hubs.keys(hs: List<&2, Hub>) -> List<&2, String>:
  match hs:
    case Nil{}:
      Nil{}
    case +h <> t:
      Hub.key(h) <> Hubs.keys(t)

# the owner's machines the paired hubs know of that this phone is not
# paired with: one tap adds each
def Hubs.found(+hs: List<&2, Hub>) -> List<&2, J.Json>:
  Hubs.peers(Hubs.peer_lists(hs), Hubs.keys(hs))

def Hubs.empty(+n: Nat, +m: Nat, +finding: Bool) -> String:
  Bool.pick(String, Nat.is_eq(m, 0n), "Pair with a hub to start.",
    Bool.pick(String, Bool.and(finding, Nat.is_eq(n, 0n)), "No project matches.", S.Mob.empty(n)))

def Hubs.screen.k(+ss: List<&2, Shown>, +cur: String, +list: List<&2, Hub>) -> J.Json:
  J.Json.obj([J.KV{"online", J.Json.bool(Hubs.all_on(ss))}, J.KV{"version", J.Json.str(J.Json.get_str(Hubs.of(ss, cur), "version", ""))},
    J.KV{"error", J.Json.str(Hubs.said(ss, "error"))}, J.KV{"note", J.Json.str(Hubs.said(ss, "note"))},
    J.KV{"sel", J.Json.str(J.Json.get_str(Hubs.of(ss, cur), "sel", ""))},
    J.KV{"theme", J.Json.str(J.Json.get_str(Hubs.of(ss, cur), "theme", ""))},
    J.KV{"empty", J.Json.str(Hubs.empty(List.length(&2, J.Json, Hubs.projects(ss, False{})), List.length(&2, Shown, ss), J.Json.get_bool(Hubs.first_obj(ss, "search"), "open", False{})))},
    J.KV{"projects", J.Json.arr(Hubs.projects(ss, Nat.is_gt(List.length(&2, Shown, ss), 1n)))},
    J.KV{"deleting", Hubs.first_obj(ss, "deleting")},
    J.KV{"removing", Hubs.first_obj(ss, "removing")},
    J.KV{"search", Hubs.first_obj(ss, "search")},
    J.KV{"folders", J.Json.get_obj(Hubs.of(ss, cur), "folders")},
    J.KV{"settings", J.Json.get_obj(Hubs.of(ss, cur), "settings")},
    J.KV{"find", J.Json.get_obj(Hubs.of(ss, cur), "find")},
    J.KV{"island", N.Note.island.k(Hubs.lines(ss))},
    J.KV{"thread", J.Json.get_obj(Hubs.of(ss, cur), "thread")},
    J.KV{"bots", J.Json.arr(Hubs.bots(ss, list, Nat.is_gt(List.length(&2, Shown, ss), 1n)))},
    J.KV{"rooms", J.Json.arr(Hubs.rooms(ss, Nat.is_gt(List.length(&2, Shown, ss), 1n)))},
    J.KV{"newBot", J.Json.get_obj(Hubs.of(ss, cur), "newBot")},
    J.KV{"newRoom", J.Json.get_obj(Hubs.of(ss, cur), "newRoom")},
    J.KV{"bot", J.Json.get_obj(Hubs.of(ss, cur), "bot")},
    J.KV{"hub", J.Json.str(cur)},
    J.KV{"hubs", J.Json.arr(Hubs.rows(ss))},
    J.KV{"found", J.Json.arr(Hubs.found(list))}])

# the whole screen: every hub's in one
def Hubs.screen(hs: Hubs) -> J.Json:
  match hs:
    case Hubs{_, _, +cur, +list}:
      Hubs.screen.k(Hubs.relabel(Hubs.shown(list)), cur, list)
