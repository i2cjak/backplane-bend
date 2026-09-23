import Base
import ../core/json.bend as J
import ./dom.bend as D
import ../core/client.bend as U
import ./view.bend as V

# What host.js calls. Everything the page decides happens behind these.

def init(now: Nat, cid: String) -> U.Ui:
  U.Ui.set_cid(U.Ui.init(now), cid)

def recv(u: U.Ui, o: J.Json) -> U.Act:
  U.Ui.recv_act(u, o)

def act(u: U.Ui, action: String, value: String) -> U.Act:
  U.Ui.act(u, action, value)

def view(u: U.Ui) -> D.Node:
  V.View.page(u)

def online(u: U.Ui, b: Bool) -> U.Ui:
  U.Ui.online(u, b)

def tick(u: U.Ui, now: Nat) -> U.Ui:
  U.Ui.tick(u, now)

# how many changes this page holds and which log they came from (a
# reconnect asks the server for the rest)
def seq(u: U.Ui) -> String:
  Nat.show(U.Ui.seq(u))

def origin(u: U.Ui) -> String:
  U.Ui.info(u, "origin")
