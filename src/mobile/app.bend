import Base
import ../core/json.bend as J
import ../core/model.bend as M
import ../core/client.bend as U
import ./screen.bend as S
import ./notify.bend as N
import ../core/cbor.bend as CB
import ../core/sha1.bend as SH
import ./view.bend as VW
import ../core/codec.bend as C

# What bridge.js calls. The phone apps see only strings: server messages
# in (binary CBOR frames, carried as base64, decoded by bridge.js); the
# screen, commands and alerts out, and what to send (CBOR, as base64).

def init(now: Nat, cid: String) -> U.Ui:
  U.Ui.set_cid(U.Ui.init(now), cid)

# a server message, with what to send and the alerts it raised
type Recv is Data:
  Recv{act: U.Act, alerts: String}

def recv.k(+seen: List<&2, N.Seen>, a: U.Act) -> Recv:
  match a:
    case U.Act{+u, cmds}:
      Recv{U.Act{u, cmds}, J.Json.show(J.Json.arr(N.Note.alerts(U.Ui.threads(S.Mob.st(u)), seen, U.Ui.entries(S.Mob.st(u)))))}

def recv.j(+u: U.Ui, +o: J.Json) -> Recv:
  recv.k(N.Note.seen(U.Ui.threads(S.Mob.st(u))), U.Ui.recv_act(VW.View.picked(u, o), o))

# a frame from the hub, already decoded: bridge.js reads the base64 and
# CBOR natively (Cbor.decode here took 17x as long on a phone's
# JavaScriptCore, which has no JIT), with these dictionaries
def recv(+u: U.Ui, +o: J.Json) -> Recv:
  recv.j(u, o)

def cbor_keys() -> List<&2, String>:
  CB.Cbor.keys()

def cbor_words() -> List<&2, String>:
  CB.Cbor.words()

# a message for the hub (a Send command's JSON text) as the base64 of the
# CBOR frame the app sends
def wire(text: String) -> String:
  SH.B64.encode(CB.Cbor.encode(Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{})))

def act.k(i: Nat, +u: U.Ui, +action: String, +value: String) -> U.Act:
  match i:
    case 0n:
      VW.View.open(u, value)
    case 1n:
      VW.View.mention(u, value)
    case 2n:
      VW.View.pick(u, value)
    case 3n:
      U.Act{VW.Pick.clear(u), Nil{}}
    case _:
      VW.View.sync(U.Ui.act(u, action, value))

# an action; "view" opens or closes the board viewer ("board",
# "schematic", "3d", ""), "view-pick" inspects a tap (what lies under
# the finger), "view-unpick" closes the card, "view-mention" puts the
# inspected item into the draft; any action that moves to another project
# re-aims the viewer
def act(+u: U.Ui, +action: String, +value: String) -> U.Act:
  act.k(C.Codec.pos(["view", "view-mention", "view-pick", "view-unpick"], action), u, action, value)

def screen(+u: U.Ui) -> String:
  J.Json.show(S.Mob.screen(u))

def online(u: U.Ui, b: Bool) -> U.Act:
  VW.View.online(u, b)

def tick(u: U.Ui, now: Nat) -> U.Ui:
  U.Ui.tick(u, now)

# how many changes this app holds and which log they came from (a
# reconnect asks the server for the rest)
def seq(u: U.Ui) -> String:
  Nat.show(U.Ui.seq(u))

def origin(u: U.Ui) -> String:
  U.Ui.info(u, "origin")

# this phone, for pushes while the app sleeps: an APNs token for alerts,
# for one Live Activity ("activity", with its thread) or for starting one
# ("start"). Kept in the outbox until the hub answers.
def register(u: U.Ui, platform: String, token: String, kind: String, thread: String, env: String, bundle: String) -> U.Act:
  U.Ui.rpc.keep(u, "device.register", [J.KV{"platform", J.Json.str(platform)}, J.KV{"token", J.Json.str(token)},
    J.KV{"kind", J.Json.str(kind)}, J.KV{"thread", J.Json.str(thread)}, J.KV{"env", J.Json.str(env)}, J.KV{"bundle", J.Json.str(bundle)}])
