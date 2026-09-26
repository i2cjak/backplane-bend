import Base
import ./check.bend as C
import ../src/core/client.bend as U
import ../src/core/json.bend as J
import ../src/core/tailnet.bend as TN
import ../src/core/http.bend as W
import ../src/core/utf8.bend as UT
import ../src/core/model.bend as M
import ../src/core/codec.bend as K

# bytes as od -An -tu1 writes them (then tr squeezes the spaces)
def od(bs: List<&2, U32>, acc: String) -> String:
  match bs:
    case Nil{}:
      acc
    case b <> t:
      od(t, acc ++ " " ++ U32.show(b))

def rows(rs: List<&2, U.MRow>) -> String:
  match rs:
    case Nil{}:
      ""
    case U.MRow{n, u, on} <> t:
      n ++ "=" ++ u ++ Bool.pick(String, on, "*", "") ++ "|" ++ rows(t)

def msg(+text: String) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{})

def list() -> String:
  "{\"self\":{\"name\":\"laptop\",\"url\":\"http://100.1.1.1:3787\",\"domain\":\"tail1.ts.net\"},\"peers\":[{\"name\":\"desktop\",\"url\":\"http://100.2.2.2:3787\",\"version\":\"0.2.0\"},{\"name\":\"laptop\",\"url\":\"http://100.1.1.1:3787\"}]}"

def home() -> U.Ui:
  U.Ui.recv(U.Ui.init(0n), msg("{\"t\":\"log\",\"items\":[],\"info\":{\"machines\":" ++ J.Json.show(J.Str{list()}) ++ "}}"))

def after(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}:
      u

def cmds(a: U.Act) -> String:
  match a:
    case U.Act{_, U.Connect{url} <> _}:
      "connect " ++ url
    case _:
      "none"

# the home hub, with bots on linked machines: one on the owner's desktop,
# one on a friend's machine
def fars() -> String:
  "[{\"name\":\"Kit\",\"peer\":\"p1\",\"peerName\":\"desktop\",\"look\":3,\"state\":\"idle\"},{\"name\":\"Pal\",\"peer\":\"p2\",\"peerName\":\"desktop\",\"look\":1,\"state\":\"idle\"}]"

# the home hub's log: the links to desktop (on the owner's tailnet) and to
# a friend's machine also called desktop
def links() -> J.Json:
  J.Json.obj([J.KV{"t", J.Json.str("log")}, J.KV{"items", J.Json.arr([
    K.Change.encode(M.PeerSet{"p1", "desktop", "http://desktop.tail1.ts.net:3787", False{}, 10n}),
    K.Change.encode(M.PeerSet{"p2", "desktop", "http://desktop.tail9.ts.net:3787", False{}, 11n})])},
    J.KV{"info", J.Json.obj([J.KV{"machines", J.Str{list()}}])}])

def linked(+fixed: String) -> U.Ui:
  U.Ui.info_set(U.Ui.info_set(U.Ui.recv(U.Ui.init(0n), links()), "bots.remote", fars()), "local.fixed", fixed)

# the desktop hub's log: its bot Kit
def desk() -> J.Json:
  J.Json.obj([J.KV{"t", J.Json.str("log")}, J.KV{"items", J.Json.arr([
    K.Change.encode(M.ThreadCreated{"bt1", "", "Kit", M.Local{}, "", "", "claude", "", 100n}),
    K.Change.encode(M.BotSet{"b1", "Kit", "bt1", 3n, "helps", 100n})])}])

def shown(+u: U.Ui) -> String:
  U.Ui.scratch(u, "@bot") ++ "/" ++ U.Ui.sel(u) ++ "/" ++ U.Ui.scratch(u, "@remote")

def status() -> String:
  "{\"Self\":{\"HostName\":\"laptop\",\"UserID\":7,\"TailscaleIPs\":[\"100.1.1.1\"]},\"Peer\":{\"a\":{\"HostName\":\"desktop\",\"UserID\":7,\"Online\":true,\"TailscaleIPs\":[\"100.2.2.2\",\"fd7a::2\"]},\"b\":{\"HostName\":\"phone\",\"UserID\":7,\"Online\":false,\"TailscaleIPs\":[\"100.3.3.3\"]},\"c\":{\"HostName\":\"friend\",\"UserID\":9,\"Online\":true,\"TailscaleIPs\":[\"100.4.4.4\"]}}}"

def ips(ms: List<&2, TN.Machine>) -> String:
  match ms:
    case Nil{}:
      ""
    case TN.Machine{n, ip, _} <> t:
      n ++ "@" ++ ip ++ " " ++ ips(t)

def payload(m: Maybe<&2, W.Got>) -> String:
  match m:
    case Some{W.Got{W.Frame{_, op, p}, _}}:
      U32.show(op) ++ ":" ++ UT.Utf8.decode(p)
    case None{}:
      "none"

def need(m: Maybe<&2, Nat>) -> String:
  match m:
    case Some{n}:
      Nat.show(n)
    case None{}:
      "none"

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("home rows", rows(U.Machines.rows(home())), "laptop=*|desktop=http://100.2.2.2:3787|")
    C.Check.str("switch emits connect", cmds(U.Ui.act(home(), "machine", "http://100.2.2.2:3787")), "connect http://100.2.2.2:3787")
    C.Check.str("remote log keeps the home list",
      rows(U.Machines.rows(U.Ui.recv(after(U.Ui.act(home(), "machine", "http://100.2.2.2:3787")), msg("{\"t\":\"log\",\"items\":[],\"info\":{\"machines\":\"{}\"}}")))),
      "laptop=|desktop=http://100.2.2.2:3787*|")
    C.Check.str("a bot on the owner's machine opens there", cmds(U.Ui.act(linked(""), "remote", "Kit@p1")), "connect http://100.2.2.2:3787")
    C.Check.str("and is shown once that hub's log comes", shown(U.Ui.recv(after(U.Ui.act(linked(""), "remote", "Kit@p1")), desk())), "b1/bt1/")
    C.Check.str("a bot on someone else's machine is a conversation", cmds(U.Ui.act(linked(""), "remote", "Pal@p2")), "none")
    C.Check.str("shown as one", shown(after(U.Ui.act(linked(""), "remote", "Pal@p2"))), "//Pal@p2")
    C.Check.str("a machine name alone, off the tailnet, is not enough", cmds(U.Ui.act(U.Ui.info_set(U.Ui.info_set(home(), "bots.remote", fars()), "local.fixed", ""), "remote", "Kit@desktop")), "none")
    C.Check.str("a phone never switches hubs", shown(after(U.Ui.act(linked("1"), "remote", "Kit@p1"))), "//Kit@p1")
    C.Check.str("owner's online peers", ips(TN.Tailnet.online(TN.Tailnet.peers(status()))), "desktop@100.2.2.2 ")
    C.Check.str("self", ips([TN.Tailnet.self(status())]), "laptop@100.1.1.1 ")
    C.Check.str("serve https 443", TN.Tailnet.serve("{\"Web\":{\"d.ts.net:443\":{\"Handlers\":{\"/\":{\"Proxy\":\"http://127.0.0.1:3787\"}}}}}", "3787"), "https://d.ts.net")
    C.Check.str("serve https other port", TN.Tailnet.serve("{\"Web\":{\"d.ts.net:443\":{\"Handlers\":{\"/\":{\"Proxy\":\"http://127.0.0.1:3773\"}}},\"d.ts.net:3788\":{\"Handlers\":{\"/\":{\"Proxy\":\"http://localhost:3787/\"}}}}}", "3787"), "https://d.ts.net:3788")
    C.Check.str("serve not ours", TN.Tailnet.serve("{\"Web\":{\"d.ts.net:443\":{\"Handlers\":{\"/\":{\"Proxy\":\"http://127.0.0.1:13787\"}}}}}", "3787"), "")
    C.Check.str("serve none", TN.Tailnet.serve("{}", "3787"), "")
    C.Check.str("serve not json", TN.Tailnet.serve("No serve config", "3787"), "")
    C.Check.str("owner trusted", Bool.pick(String, TN.Tailnet.trusts("h@x", "h@x"), "yes", "no"), "yes")
    C.Check.str("other owner", Bool.pick(String, TN.Tailnet.trusts("h@x", "e@x"), "yes", "no"), "no")
    C.Check.str("tagged", Bool.pick(String, TN.Tailnet.trusts("tagged-devices", "tagged-devices"), "yes", "no"), "no")
    C.Check.str("whois login", TN.Tailnet.login("{\"UserProfile\":{\"LoginName\":\"h@x\"}}"), "h@x")
    C.Check.str("hello cbor", TN.Hello.version(TN.Hello.bytes(od(TN.Hello.answer("1.2.3"), ""))), "1.2.3")
    C.Check.str("hello json from an older hub", TN.Hello.version(UT.Utf8.encode("{\"backplane\":\"0.9.0\"}")), "0.9.0")
    C.Check.str("hello garbage", TN.Hello.version(TN.Hello.bytes(" 1 2 3 ")), "")
    C.Check.str("hello nothing", TN.Hello.version(TN.Hello.bytes("")), "")
    C.Check.str("masked frame round trip", payload(W.Ws.decode(W.Ws.client_text("hello"))), "1:hello")
    C.Check.str("long masked frame", payload(W.Ws.decode(W.Ws.client_text(String.repeat("ab", 100n)))), "1:" ++ String.repeat("ab", 100n))
    C.Check.str("need short", need(W.Ws.need(W.Ws.text("hi"))), "4")
    C.Check.str("need 16-bit", need(W.Ws.need(W.Ws.text(String.repeat("x", 300n)))), "304")
    C.Check.str("need incomplete", need(W.Ws.need([129])), "none")
