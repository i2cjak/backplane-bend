import Base
import ../core/json.bend as J
import ../core/client.bend as U
import ./screen.bend as S

# What bridge.js calls. The phone apps see only strings: server messages
# in, the screen and commands out.

def init(now: Nat) -> U.Ui:
  U.Ui.init(now)

def recv(u: U.Ui, o: J.Json) -> U.Ui:
  U.Ui.recv(u, o)

def act(u: U.Ui, action: String, value: String) -> U.Act:
  U.Ui.act(u, action, value)

def screen(u: U.Ui) -> String:
  J.Json.show(S.Mob.screen(u))

def online(u: U.Ui, b: Bool) -> U.Ui:
  U.Ui.online(u, b)

def tick(u: U.Ui, now: Nat) -> U.Ui:
  U.Ui.tick(u, now)
