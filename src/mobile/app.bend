import Base
import ../core/json.bend as J
import ../core/client.bend as U
import ../core/cbor.bend as CB
import ../core/sha1.bend as SH
import ./hubs.bend as H
import ./bots.bend as MB

# What bridge.js calls. The phone apps see only strings: server messages
# in (binary CBOR frames, carried as base64, decoded by bridge.js) from
# each hub the phone is paired with, named by its key; the screen,
# commands (each for one hub) and alerts out, and what to send (CBOR, as
# base64). hubs.bend keeps a client per hub and makes one screen of them.

def init(now: Nat, +cid: String) -> H.Hubs:
  H.Hubs.init(now, cid)

def hubs.keys(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      J.Json.as_str(Some{x}, "") <> hubs.keys(t)

# the hubs the phone is paired with, by key, as a JSON array of strings
def hubs.k(+hs: H.Hubs, j: J.Json) -> H.Hubs:
  H.Hubs.set(hs, hubs.keys(J.Json.elems(j)))

def hubs(+hs: H.Hubs, text: String) -> H.Hubs:
  hubs.k(hs, Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{}))

# Drafts the phone kept (keep commands, named "<hub>|<thread>"), read back
# into the client of the hub they belong to once the hubs are known

def restore.one(hit: Bool, u: U.Ui, +id: String, +text: String) -> U.Ui:
  match hit:
    case True{}:
      U.Ui.restore(u, id, text)
    case False{}:
      u

def restore.go(hs: List<&2, H.Hub>, +key: String, +id: String, +text: String) -> List<&2, H.Hub>:
  match hs:
    case Nil{}:
      Nil{}
    case H.Hub{+k, u} <> t:
      H.Hub{k, restore.one(String.eq(k, key), u, id, text)} <> restore.go(t, key, id, text)

def restore(hs: H.Hubs, +key: String, +id: String, +text: String) -> H.Hubs:
  match hs:
    case H.Hubs{c, n, cur, l}:
      H.Hubs{c, n, cur, restore.go(l, key, id, text)}

# the alerts a step raised, as JSON text
def alerts(a: H.HAct) -> String:
  match a:
    case H.HAct{_, _, als}:
      J.Json.show(J.Json.arr(als))

# a bot's browser has a new frame ({"t":"shot","bot":id,"n":n}): kept as
# the client's info "shot.<bot>", which the bot's Browser tab shows as n
# (the apps fetch the frame again when it changes)
def shot(hit: Bool, +o: J.Json) -> J.Json:
  match hit:
    case True{}:
      J.Json.obj([J.KV{"t", J.Json.str("info")},
        J.KV{"info", J.Json.obj([J.KV{"shot." ++ J.Json.get_str(o, "bot", ""), J.Json.str(Nat.show(J.Json.get_nat(o, "n", 0n)))}])}])
    case False{}:
      o

# a frame from hub `key`, already decoded: bridge.js reads the base64 and
# CBOR natively (Cbor.decode here took 17x as long on a phone's
# JavaScriptCore, which has no JIT), with these dictionaries
def recv(+hs: H.Hubs, +key: String, +o: J.Json) -> H.HAct:
  H.Hubs.recv(hs, key, shot(String.eq(J.Json.get_str(o, "t", ""), "shot"), o))

# a cat's rig as JSON text, for the key the screen names it by
# ("look:mood"); the apps ask once per key and keep it
def cat(+look: Nat, +mood: String) -> String:
  J.Json.show(MB.MBots.rig(look, mood))

def cbor_keys() -> List<&2, String>:
  CB.Cbor.keys()

def cbor_words() -> List<&2, String>:
  CB.Cbor.words()

# a message for the hub (a Send command's JSON text) as the base64 of the
# CBOR frame the app sends
def wire(text: String) -> String:
  SH.B64.encode(CB.Cbor.encode(Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{})))

# an action, routed to the hub it names (hubs.bend)
def act(+hs: H.Hubs, +action: String, +value: String) -> H.HAct:
  H.Hubs.act(hs, action, value)

def screen(+hs: H.Hubs) -> String:
  J.Json.show(H.Hubs.screen(hs))

def online(+hs: H.Hubs, +key: String, b: Bool) -> H.HAct:
  H.Hubs.online(hs, key, b)

def tick(+hs: H.Hubs, now: Nat) -> H.HAct:
  H.Hubs.tick(hs, now)

# how many changes this app holds from hub `key` and which log they came
# from (a reconnect asks that hub for the rest)
def seq(+hs: H.Hubs, +key: String) -> String:
  Nat.show(U.Ui.seq(H.Hubs.ui(hs, key)))

def origin(+hs: H.Hubs, +key: String) -> String:
  U.Ui.info(H.Hubs.ui(hs, key), "origin")

# this phone, for pushes while the app sleeps: an APNs token for alerts,
# for one Live Activity ("activity", with its thread) or for starting one
# ("start"). Every paired hub gets it, kept in each outbox until answered.
def register(+hs: H.Hubs, platform: String, token: String, kind: String, thread: String, env: String, bundle: String) -> H.HAct:
  H.Hubs.register(hs, platform, token, kind, thread, env, bundle)
