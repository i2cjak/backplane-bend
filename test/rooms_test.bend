import Base
import ./check.bend as C
import ../src/core/json.bend as J
import ../src/core/model.bend as M
import ../src/core/codec.bend as K
import ../src/core/hub.bend as B
import ../src/core/bothub.bend as BH
import ../src/mobile/hubs.bend as H

# Each room listed once: a room shared by two machines is kept on both under
# one id, and every list (a hub's own, a phone's over several hubs) shows it
# once. Two rooms with one name both show, told apart.

def items(cs: List<&2, M.Change>) -> List<&2, J.Json>:
  match cs:
    case Nil{}:
      Nil{}
    case c <> t:
      K.Change.encode(c) <> items(t)

def log(cs: List<&2, M.Change>) -> J.Json:
  J.Json.obj([J.KV{"t", J.Json.str("log")}, J.KV{"items", J.Json.arr(items(cs))}])

def json(+t: String) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(t), J.Null{})

def changes(st: B.Step) -> List<&2, M.Change>:
  match st:
    case B.Step{cs, _}:
      cs

# what a machine's log holds, and what it then takes in from a linked one
def recv(+cs: List<&2, M.Change>, +now: Nat, +peer: String, +post: String) -> List<&2, M.Change>:
  List.append(&2, M.Change, cs, changes(BH.Bots.incoming(M.State.replay(cs, M.State.empty()), now, peer, json(post))))

# the desk: Bub makes ring-requests with Pebble on box
def desk() -> List<&2, M.Change>:
  [M.ThreadCreated{"bt1", "", "Bub", M.Local{}, "", "", "claude", "", 100n},
   M.BotSet{"b1", "Bub", "bt1", 3n, "", 100n},
   M.PeerSet{"p2", "box", "http://box:3787", False{}, 100n},
   M.RoomSet{"r9", "ring-requests", "b1\nPebble@box", 110n},
   M.RoomPosted{"x1", "r9", "Bub", "ring requests go here", 1n, 111n}]

def box.base() -> List<&2, M.Change>:
  [M.ThreadCreated{"bt2", "", "Pebble", M.Local{}, "", "", "claude", "", 100n},
   M.BotSet{"b2", "Pebble", "bt2", 5n, "", 100n},
   M.PeerSet{"p1", "desk", "http://desk:3787", False{}, 100n}]

# box hears Bub's post and keeps the room under the same id
def box() -> List<&2, M.Change>:
  recv(box.base(), 112n, "p1", "{\"from\":\"Bub\",\"tos\":[\"Pebble\"],\"members\":[\"Bub@\",\"Pebble\"],\"room\":\"r9\",\"roomName\":\"ring-requests\",\"text\":\"ring requests go here\",\"hop\":1}")

# and Pebble's answer comes back to the desk's copy
def desk.back() -> List<&2, M.Change>:
  recv(desk(), 113n, "p2", "{\"from\":\"Pebble\",\"tos\":[\"Bub\"],\"members\":[\"Bub\",\"Pebble@\"],\"room\":\"r9\",\"roomName\":\"ring-requests\",\"text\":\"got it\",\"hop\":2}")

def one(+k: String, cs: List<&2, M.Change>) -> H.Hubs:
  H.Hubs.after(H.Hubs.recv(H.Hubs.set(H.Hubs.init(0n, "c"), [k]), k, log(cs)))

def both(a: List<&2, M.Change>, b: List<&2, M.Change>) -> H.Hubs:
  H.Hubs.after(H.Hubs.recv(
    H.Hubs.after(H.Hubs.recv(H.Hubs.set(H.Hubs.init(0n, "c"), ["desk:3787", "box:3787"]), "desk:3787", log(a))),
    "box:3787", log(b)))

def strs(js: List<&2, J.Json>, +key: String) -> String:
  match js:
    case Nil{}:
      ""
    case j <> t:
      J.Json.get_str(j, key, "") ++ ";" ++ strs(t, key)

def rooms(+h: H.Hubs, +field: String) -> String:
  strs(J.Json.elems(J.Json.get_obj(H.Hubs.screen(h), "rooms")), field)

def main() -> IO(Unit):
  do IO<Unit>:
    # a hub's own list: the window's sidebar and the web draw the same rows
    C.Check.str("desk lists it", rooms(one("desk:3787", desk()), "name"), "ring-requests;")
    C.Check.str("box keeps it under its id", rooms(one("box:3787", box()), "id"), "box:3787|r9;")
    C.Check.str("box lists it once", rooms(one("box:3787", box()), "name"), "ring-requests;")
    C.Check.str("an answer from box adds no room", rooms(one("desk:3787", desk.back()), "id"), "desk:3787|r9;")
    # a phone paired with both machines
    C.Check.str("two hubs, one room", rooms(both(desk.back(), box()), "name"), "ring-requests;")
    C.Check.str("either order", rooms(both(box(), desk.back()), "name"), "ring-requests;")
    C.Check.str("opened through a hub that has it", rooms(both(desk.back(), box()), "id"), "box:3787|r9;")
    # two rooms with one name are two rooms, told apart by id on one machine
    C.Check.str("same name here", rooms(one("desk:3787", List.append(&2, M.Change, desk(), [M.RoomSet{"r7", "Ring-Requests", "b1", 120n}])), "name"),
      "Ring-Requests · r7;ring-requests · r9;")
    C.Check.str("both kept", rooms(one("desk:3787", List.append(&2, M.Change, desk(), [M.RoomSet{"r7", "Ring-Requests", "b1", 120n}])), "id"),
      "desk:3787|r7;desk:3787|r9;")
    # and by machine on two
    C.Check.str("same name, two machines", rooms(both(desk(), List.append(&2, M.Change, box.base(), [M.RoomSet{"r4", "ring-requests", "b2", 120n}])), "id"),
      "desk:3787|r9;box:3787|r4;")
    C.Check.str("named by machine", rooms(both(desk(), List.append(&2, M.Change, box.base(), [M.RoomSet{"r4", "ring-requests", "b2", 120n}])), "machine"),
      "desk;box;")
    # a shared room and a same-named room of box's own
    C.Check.str("shared and same name", rooms(both(desk.back(), List.append(&2, M.Change, box(), [M.RoomSet{"r4", "ring-requests", "b2", 120n}])), "id"),
      "box:3787|r4;box:3787|r9;")
    C.Check.str("shared and same name, labels", rooms(both(desk.back(), List.append(&2, M.Change, box(), [M.RoomSet{"r4", "ring-requests", "b2", 120n}])), "name"),
      "ring-requests · r4;ring-requests · r9;")
