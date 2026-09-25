import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/codec.bend as K
import ../src/core/json.bend as J
import ../src/mobile/hubs.bend as H
import ../src/mobile/app.bend as A
import ../src/core/bot.bend as BT

# Each bot once in the bot list (law bot_rows_once): on one hub, and on a
# phone paired with several hubs that are linked to each other.

def items(cs: List<&2, M.Change>) -> List<&2, J.Json>:
  match cs:
    case Nil{}:
      Nil{}
    case c <> t:
      K.Change.encode(c) <> items(t)

def log(cs: List<&2, M.Change>) -> J.Json:
  J.Json.obj([J.KV{"t", J.Json.str("log")}, J.KV{"items", J.Json.arr(items(cs))}])

def info(+remote: String) -> J.Json:
  J.Json.obj([J.KV{"t", J.Json.str("info")}, J.KV{"info", J.Json.obj([J.KV{"bots.remote", J.Json.str(remote)}])}])

def strs(js: List<&2, J.Json>, +key: String) -> String:
  match js:
    case Nil{}:
      ""
    case j <> t:
      J.Json.get_str(j, key, "") ++ ";" ++ strs(t, key)

def list(+h: H.Hubs, +key: String, +field: String) -> String:
  strs(J.Json.elems(J.Json.get_obj(H.Hubs.screen(h), key)), field)

# lap and box are linked (link p1 on both); box's bot Kit failed a turn,
# and lap lists it as Kit@box
def linked() -> H.Hubs:
  H.Hubs.after(A.recv(H.Hubs.after(H.Hubs.recv(
    H.Hubs.after(H.Hubs.recv(H.Hubs.set(H.Hubs.init(0n, "c"), ["lap:3787", "box:3787"]), "lap:3787",
      log([M.PeerSet{"p1", "box", "http://box:3787", False{}, 50n}]))),
    "box:3787",
    log([M.ThreadCreated{"bt1", "", "Kit", M.Local{}, "", "", "claude", "", 100n},
      M.BotSet{"b1", "Kit", "bt1", 7n, "helps", 100n},
      M.PeerSet{"p1", "lap", "http://lap:3787", False{}, 50n},
      M.TurnChanged{"bt1", M.Running{}, 110n},
      M.TurnChanged{"bt1", M.Failed{}, 120n}]))),
    "lap:3787", info("[{\"name\":\"Kit\",\"peer\":\"p1\",\"peerName\":\"box\",\"look\":7,\"state\":\"failed\"}]")))

def one(+cs: List<&2, M.Change>, +remote: String) -> H.Hubs:
  H.Hubs.after(A.recv(H.Hubs.after(H.Hubs.recv(H.Hubs.set(H.Hubs.init(0n, "c"), ["box:3787"]), "box:3787", log(cs))),
    "box:3787", info(remote)))

def go(+h: H.Hubs, +a: String, +v: String) -> H.Hubs:
  H.Hubs.after(H.Hubs.act(h, a, v))

def picks(+h: H.Hubs, +field: String) -> String:
  strs(J.Json.elems(J.Json.get_obj(J.Json.get_obj(H.Hubs.screen(h), "newRoom"), "picks")), field)

def ons(js: List<&2, J.Json>) -> String:
  match js:
    case Nil{}:
      ""
    case j <> t:
      J.Json.show(J.Json.get_obj(j, "on")) ++ ";" ++ ons(t)

def pick_ons(+h: H.Hubs) -> String:
  ons(J.Json.elems(J.Json.get_obj(J.Json.get_obj(H.Hubs.screen(h), "newRoom"), "picks")))

def links() -> List<&2, M.Change>:
  [M.PeerSet{"p1", "laptop", "http://laptop:3787", False{}, 10n}, M.PeerSet{"p2", "desk", "http://desk:3787", False{}, 11n}]

# one bot, reported twice by its machine (once in another case)
def twice() -> H.Hubs:
  one(links(), "[{\"name\":\"Nori\",\"peer\":\"p1\",\"peerName\":\"laptop\",\"look\":3,\"state\":\"failed\"},{\"name\":\"Nori\",\"peer\":\"p1\",\"peerName\":\"laptop\",\"look\":3,\"state\":\"away\"},{\"name\":\"nori\",\"peer\":\"p1\",\"peerName\":\"laptop\",\"look\":3,\"state\":\"ready\"}]")

# one name on two machines
def spread() -> H.Hubs:
  one(links(), "[{\"name\":\"Nori\",\"peer\":\"p1\",\"peerName\":\"laptop\",\"look\":3,\"state\":\"ready\"},{\"name\":\"Nori\",\"peer\":\"p2\",\"peerName\":\"desk\",\"look\":4,\"state\":\"ready\"}]")

# two linked machines both called laptop (any case)
def namesake() -> H.Hubs:
  one([M.PeerSet{"p1", "laptop", "http://laptop:3787", False{}, 10n}, M.PeerSet{"p2", "Laptop", "http://laptop2:3787", False{}, 11n}],
    "[{\"name\":\"Nori\",\"peer\":\"p1\",\"peerName\":\"laptop\",\"look\":3,\"state\":\"ready\"},{\"name\":\"Nori\",\"peer\":\"p2\",\"peerName\":\"Laptop\",\"look\":4,\"state\":\"ready\"}]")

# two bots here with one name (an old log could hold them)
def alike() -> H.Hubs:
  one([M.ThreadCreated{"t1", "", "Kit", M.Local{}, "", "", "claude", "", 100n}, M.BotSet{"b1", "Kit", "t1", 7n, "", 100n},
    M.ThreadCreated{"t2", "", "kit", M.Local{}, "", "", "claude", "", 101n}, M.BotSet{"b2", "kit", "t2", 8n, "", 101n},
    M.ThreadCreated{"t3", "", "Pip", M.Local{}, "", "", "claude", "", 102n}, M.BotSet{"b3", "Pip", "t3", 9n, "", 102n}], "[]")

# a bot here named like one elsewhere
def mirror() -> H.Hubs:
  one(List.append(&2, M.Change, [M.ThreadCreated{"t1", "", "Nori", M.Local{}, "", "", "claude", "", 100n}, M.BotSet{"b1", "Nori", "t1", 7n, "", 100n}], links()),
    "[{\"name\":\"Nori\",\"peer\":\"p1\",\"peerName\":\"laptop\",\"look\":3,\"state\":\"ready\"}]")

# a room that names one bot two ways
def room(+h: H.Hubs) -> H.Hubs:
  go(go(h, "room-new", "box:3787|"), "bfield", "rmembers\u{1f}Nori@p1\nnori@LAPTOP\nGhost@far\nghost@FAR")

# three hubs: lap and box both linked to far, which the phone is not
# paired with; each reports far's Moss
def third() -> H.Hubs:
  H.Hubs.after(A.recv(H.Hubs.after(A.recv(H.Hubs.after(H.Hubs.recv(H.Hubs.after(H.Hubs.recv(
    H.Hubs.set(H.Hubs.init(0n, "c"), ["lap:3787", "box:3787"]),
    "lap:3787", log([M.PeerSet{"pa", "far", "http://far:3787", False{}, 10n}]))),
    "box:3787", log([M.PeerSet{"pb", "far", "http://far:3787", False{}, 10n}]))),
    "lap:3787", info("[{\"name\":\"Moss\",\"peer\":\"pa\",\"peerName\":\"far\",\"look\":1,\"state\":\"ready\"}]"))),
    "box:3787", info("[{\"name\":\"Moss\",\"peer\":\"pb\",\"peerName\":\"far\",\"look\":1,\"state\":\"ready\"}]")))

# two paired hubs with one name, each with a bot of one name
def same_hubs() -> H.Hubs:
  H.Hubs.after(H.Hubs.recv(H.Hubs.after(H.Hubs.recv(H.Hubs.set(H.Hubs.init(0n, "c"), ["lap:3787", "LAP:4000"]),
    "lap:3787", log([M.ThreadCreated{"t1", "", "Kit", M.Local{}, "", "", "claude", "", 100n}, M.BotSet{"b1", "Kit", "t1", 7n, "", 100n}]))),
    "LAP:4000", log([M.ThreadCreated{"t1", "", "Kit", M.Local{}, "", "", "claude", "", 100n}, M.BotSet{"b1", "Kit", "t1", 7n, "", 100n}])))

def peers() -> List<&2, BT.Peer>:
  [BT.Peer{"p1", "p2", "", 0n, False{}}, BT.Peer{"p2", "desk", "", 0n, False{}}]

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("a failed bot on a linked hub is listed once", list(linked(), "bots", "name"), "Kit;")
    C.Check.str("as its own hub's bot", list(linked(), "bots", "id"), "box:3787|b1;")
    C.Check.str("looking unwell", list(linked(), "bots", "note"), "failed;")
    C.Check.str("one bot reported twice by its machine is listed once", list(twice(), "bots", "id"), "box:3787|Nori@laptop;")
    C.Check.str("as first reported", list(twice(), "bots", "note"), "failed;")
    C.Check.str("one name on two machines is two bots", list(spread(), "bots", "id"), "box:3787|Nori@laptop;box:3787|Nori@desk;")
    C.Check.str("each by its machine", list(spread(), "bots", "peer"), "laptop;desk;")
    C.Check.str("machines with one name stay apart", list(namesake(), "bots", "id"), "box:3787|Nori@p1;box:3787|Nori@p2;")
    C.Check.str("labelled with their ids", list(namesake(), "bots", "peer"), "laptop (p1);Laptop (p2);")
    C.Check.str("two bots here with one name stay two", list(alike(), "bots", "id"), "box:3787|b1;box:3787|b2;box:3787|b3;")
    C.Check.str("labelled with their ids too", list(alike(), "bots", "name"), "Kit (b1);kit (b2);Pip;")
    C.Check.str("a bot here and one elsewhere with one name", list(mirror(), "bots", "id"), "box:3787|b1;box:3787|Nori@laptop;")
    C.Check.str("the picker lists them once", picks(go(twice(), "room-new", "box:3787|"), "id"), "Nori@laptop;")
    C.Check.str("the picker keeps namesake machines apart", picks(go(namesake(), "room-new", "box:3787|"), "name"), "Nori@laptop (p1);Nori@Laptop (p2);")
    C.Check.str("the picker keeps namesake bots apart", picks(go(alike(), "room-new", "box:3787|"), "name"), "Kit (b1);kit (b2);Pip;")
    C.Check.str("a member named two ways is one pick", picks(room(twice()), "id"), "Nori@laptop;Ghost@far;")
    C.Check.str("picked", pick_ons(room(twice())), "true;true;")
    C.Check.str("dropping it drops both spellings", picks(go(room(twice()), "room-pick", "Nori@laptop"), "id"), "Nori@laptop;Ghost@far;")
    C.Check.str("and it is not picked", pick_ons(go(room(twice()), "room-pick", "Nori@laptop")), "false;true;")
    C.Check.str("a machine two hubs report is listed once", list(third(), "bots", "id"), "lap:3787|Moss@far;")
    C.Check.str("paired hubs with one name are told apart", list(same_hubs(), "bots", "machine"), "lap (lap:3787);LAP (LAP:4000);")
    C.Check.str("and their bots stay two", list(same_hubs(), "bots", "id"), "lap:3787|b1;LAP:4000|b1;")
    C.Check.str("an id is matched before a name", BT.Peer.of.id(BT.Peer.of(peers(), "p2")), "p2")
    C.Check.str("a name when no id matches", BT.Peer.of.id(BT.Peer.of(peers(), "DESK")), "p2")
    C.Check.str("a name that is another's id clashes", J.Json.show(J.Json.bool(BT.Peer.clash(peers(), "p1", "p2"))), "true")
