import Base
import ../core/json.bend as J
import ./dom.bend as D
import ../core/client.bend as U
import ./view.bend as V

# What host.js calls. Everything the page decides happens behind these.

def init(now: Nat) -> U.Ui:
  U.Ui.init(now)

def recv(u: U.Ui, o: J.Json) -> U.Ui:
  U.Ui.recv(u, o)

def act(u: U.Ui, action: String, value: String) -> U.Act:
  U.Ui.act(u, action, value)

def view(u: U.Ui) -> D.Node:
  V.View.page(u)

def online(u: U.Ui, b: Bool) -> U.Ui:
  U.Ui.online(u, b)

def tick(u: U.Ui, now: Nat) -> U.Ui:
  U.Ui.tick(u, now)
