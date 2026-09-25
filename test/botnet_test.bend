import Base
import ./check.bend as C
import ../src/server/botnet.bend as BN
import ../src/core/sign.bend as G
import ../src/core/json.bend as J
import ../src/server/proc.bend as P

# The pure parts of src/server/botnet.bend: which ids may name a secret
# file, which addresses a hub sends to, the verdict on a signed request,
# the replay cache, and merging linked machines' bots.

def yn(b: Bool) -> String:
  match b:
    case True{}:
      "yes"
    case False{}:
      "no"

def key() -> String:
  "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"

def seen(m: Maybe<&2, G.Seen>) -> String:
  match m:
    case Some{_}:
      "new"
    case None{}:
      "seen"

def again(m: Maybe<&2, G.Seen>, +k: String, +t: Nat) -> Maybe<&2, G.Seen>:
  match m:
    case Some{s}:
      BN.Bn.accept(BN.Bn.with_seen(BN.Bn.empty(), s), k, t)
    case None{}:
      None{}

# accept k at 1000, then k again at t
def twice(+k: String, +t: Nat) -> String:
  seen(again(BN.Bn.accept(BN.Bn.empty(), k, 1000n), k, t))

def resp(r: BN.Resp) -> String:
  match r:
    case BN.Resp{c, b}:
      Nat.show(c) ++ " " ++ b

def check(+sig: String, +ts: String) -> String:
  BN.Bn.check(True{}, key(), 1000n, "hook:h1", ts, sig, "", "", "{\"a\":1}")

def names.go(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case +o <> t:
      (J.Json.get_str(o, "name", "") ++ "/" ++ J.Json.get_str(o, "state", "")) <> names.go(t)

def names(xs: List<&2, J.Json>) -> String:
  String.join(names.go(xs), ",")

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("id plain", yn(BN.Bn.safe("h1727-12")), "yes")
    C.Check.str("id underscore", yn(BN.Bn.safe("p_0aF")), "yes")
    C.Check.str("id empty", yn(BN.Bn.safe("")), "no")
    C.Check.str("id dots", yn(BN.Bn.safe("..")), "no")
    C.Check.str("id slash", yn(BN.Bn.safe("a/b")), "no")
    C.Check.str("id parent", yn(BN.Bn.safe("../token")), "no")
    C.Check.str("id space", yn(BN.Bn.safe("a b")), "no")
    C.Check.str("id long", yn(BN.Bn.safe(String.repeat("a", 81n))), "no")
    C.Check.str("url http", yn(BN.Bn.url.ok("http://100.64.0.1:3787")), "yes")
    C.Check.str("url https", yn(BN.Bn.url.ok("https://desk.tail.ts.net")), "yes")
    C.Check.str("url file", yn(BN.Bn.url.ok("file:///etc/passwd")), "no")
    C.Check.str("url option", yn(BN.Bn.url.ok("-K/etc/passwd")), "no")
    C.Check.str("url space", yn(BN.Bn.url.ok("http://a b")), "no")
    C.Check.str("url newline", yn(BN.Bn.url.ok("http://a\nb")), "no")
    C.Check.str("url base", BN.Bn.url.base("http://a:1/"), "http://a:1")
    C.Check.str("clean name", BN.Bn.clean("miso@evil/../x"), "misoevil..x")
    C.Check.str("clean long", Nat.show(String.length(BN.Bn.clean(String.repeat("a", 90n)))), "40")
    C.Check.str("signed", check(G.Sign.header(key(), 1000n, "{\"a\":1}"), "1000"), "hook:h1:s:" ++ G.Sign.header(key(), 1000n, "{\"a\":1}"))
    C.Check.str("signed within window", yn(String.is_empty(check(G.Sign.header(key(), 800n, "{\"a\":1}"), "800"))), "no")
    C.Check.str("stale", check(G.Sign.header(key(), 600n, "{\"a\":1}"), "600"), "")
    C.Check.str("wrong body", check(G.Sign.header(key(), 1000n, "{\"a\":2}"), "1000"), "")
    C.Check.str("wrong time", check(G.Sign.header(key(), 1000n, "{\"a\":1}"), "1001"), "")
    C.Check.str("no time", check(G.Sign.header(key(), 1000n, "{\"a\":1}"), ""), "")
    C.Check.str("no signature", check("", "1000"), "")
    C.Check.str("no secret", BN.Bn.check(True{}, "", 1000n, "hook:h1", "1000", G.Sign.header("", 1000n, "x"), "", "", "x"), "")
    C.Check.str("github", BN.Bn.check(True{}, key(), 1000n, "hook:h1", "", "", "sha256=0", "d1", "x"), "")
    C.Check.str("github not for peers", BN.Bn.check(False{}, key(), 1000n, "dir:p1", "", "", "sha256=0", "d1", "x"), "")
    C.Check.str("bearer ok", BN.Bn.bearer("0a1b", "0a1b", "hook:h1", "9.ab"), "hook:h1:b:9.ab")
    C.Check.str("bearer wrong", BN.Bn.bearer("0a1b", "0a1c", "hook:h1", "9.ab"), "!bearer")
    C.Check.str("bearer prefix", BN.Bn.bearer("0a1b", "0a1", "hook:h1", "9.ab"), "!bearer")
    C.Check.str("bearer longer", BN.Bn.bearer("0a1b", "0a1b0", "hook:h1", "9.ab"), "!bearer")
    C.Check.str("bearer empty", BN.Bn.bearer("0a1b", "", "hook:h1", "9.ab"), "!bearer")
    C.Check.str("bearer no token kept", BN.Bn.bearer("", "", "hook:h1", "9.ab"), "!notoken")
    C.Check.str("bearer refused", yn(BN.Bn.refused("!bearer")), "yes")
    C.Check.str("empty refused", yn(BN.Bn.refused("")), "yes")
    C.Check.str("key let in", yn(BN.Bn.refused("hook:h1:b:9.ab")), "no")
    C.Check.str("denied none", BN.Bn.denied("!none"), "no credentials: send Authorization: Bearer <the webhook's token>, or sign the request")
    C.Check.str("denied wrong", BN.Bn.denied("!bearer"), "wrong bearer token")
    C.Check.str("denied signature", BN.Bn.denied(""), "bad or stale signature")
    C.Check.str("replay refused", twice("k", 1100n), "seen")
    C.Check.str("replay other key", seen(BN.Bn.accept(BN.Bn.empty(), "k", 1000n)), "new")
    C.Check.str("replay late still refused", twice("k", 1301n), "seen")
    C.Check.str("replay pruned after the window", seen(again(again(BN.Bn.accept(BN.Bn.empty(), "k", 1000n), "j", 1400n), "k", 1401n)), "new")
    C.Check.str("resp", resp(BN.Bn.resp.k(List.reverse(&2, String, String.lines("{\"name\":\"a\"}\n200")))), "200 {\"name\":\"a\"}")
    C.Check.str("resp failed", resp(BN.Bn.resp(P.Ran{7, "x"})), "0 ")
    C.Check.str("dir items", names(BN.Bn.items(J.Json.elems(Maybe.default(&2, J.Json, J.Json.parse("[{\"name\":\"miso\",\"state\":\"ready\"},{\"name\":\"\"},{\"name\":\"a@b\",\"state\":\"work\"}]"), J.Null{})), "p1", "desk", 5n)), "miso/ready,ab/work")
    C.Check.str("dir away", names(BN.Bn.fetched(BN.Resp{0n, ""}, "p1", "desk", 9n,
      BN.Bn.items(J.Json.elems(Maybe.default(&2, J.Json, J.Json.parse("[{\"name\":\"miso\",\"state\":\"ready\"}]"), J.Null{})), "p1", "desk", 5n))), "miso/away")
    C.Check.str("dir away other peer", names(BN.Bn.fetched(BN.Resp{0n, ""}, "p2", "lap", 9n,
      BN.Bn.items(J.Json.elems(Maybe.default(&2, J.Json, J.Json.parse("[{\"name\":\"miso\",\"state\":\"ready\"}]"), J.Null{})), "p1", "desk", 5n))), "")
    C.Check.str("dir fresh", names(BN.Bn.fetched(BN.Resp{200n, "[{\"name\":\"nori\",\"state\":\"idle\"}]"}, "p1", "desk", 9n, Nil{})), "nori/idle")
