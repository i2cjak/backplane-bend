import Base
import ../core/json.bend as J
import ../core/model.bend as M
import ../core/client.bend as U
import ./screen.bend as S
import ./notify.bend as N

# What bridge.js calls. The phone apps see only strings: server messages
# in; the screen, commands and alerts out.

def init(now: Nat, cid: String) -> U.Ui:
  U.Ui.set_cid(U.Ui.init(now), cid)

# a server message, with what to send and the alerts it raised
type Recv is Data:
  Recv{act: U.Act, alerts: String}

def recv.k(+seen: List<&2, N.Seen>, a: U.Act) -> Recv:
  match a:
    case U.Act{+u, cmds}:
      Recv{U.Act{u, cmds}, J.Json.show(J.Json.arr(N.Note.alerts(U.Ui.threads(S.Mob.st(u)), seen, U.Ui.entries(S.Mob.st(u)))))}

def recv(+u: U.Ui, +o: J.Json) -> Recv:
  recv.k(N.Note.seen(U.Ui.threads(S.Mob.st(u))), U.Ui.recv_act(u, o))

def act(u: U.Ui, action: String, value: String) -> U.Act:
  U.Ui.act(u, action, value)

def screen(+u: U.Ui) -> String:
  J.Json.show(S.Mob.screen(u))

def online(u: U.Ui, b: Bool) -> U.Ui:
  U.Ui.online(u, b)

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
