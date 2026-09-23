import Base
import ../core/json.bend as J
import ./dom.bend as D
import ../core/client.bend as U
import ./view.bend as V
import ../core/cbor.bend as C

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

# The wire: CBOR bytes in and out (the host only moves them)
def wire_in(bs: List<&2, U32>) -> J.Json:
  Maybe.default(&2, J.Json, C.Cbor.decode(bs), J.Null{})

def wire_out(text: String) -> List<&2, U32>:
  C.Cbor.encode(Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{}))

def show(j: J.Json) -> String:
  J.Json.show(j)
