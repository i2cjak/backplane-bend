import Base
import ./check.bend as C
import ../src/core/json.bend as J
import ../src/core/space.bend as SP
import ../src/web/dom.bend as D
import ../src/web/space.bend as WS
import ../src/mobile/space.bend as MS

def rt(+s: String) -> String:
  SP.Space.show(SP.Space.read(s))

# parse(json(parse(x))) prints as parse(x)
def again(+s: String) -> String:
  SP.Space.show(SP.Space.parse(SP.Space.json(SP.Space.read(s))))

def spec() -> String:
  "{\"title\": \"Deploys\", \"blocks\": [" ++
  "{\"type\": \"heading\", \"text\": \"Today\"}," ++
  "{\"type\": \"text\", \"text\": \"All **green**.\"}," ++
  "{\"type\": \"stat\", \"label\": \"Builds\", \"value\": 42, \"hint\": \"+3\"}," ++
  "{\"type\": \"progress\", \"label\": \"Rollout\", \"value\": 0.4}," ++
  "{\"type\": \"list\", \"items\": [\"a\", \"b\"]}," ++
  "{\"type\": \"kv\", \"rows\": [[\"k\", \"v\"], {\"key\": \"x\", \"value\": \"y\"}]}," ++
  "{\"type\": \"table\", \"head\": [\"a\", \"b\"], \"rows\": [[\"1\", \"2\"]]}," ++
  "{\"type\": \"button\", \"label\": \"Ship\", \"action\": \"ship\"}," ++
  "{\"type\": \"input\", \"label\": \"Note\", \"action\": \"note\", \"placeholder\": \"say\"}," ++
  "{\"type\": \"divider\"}," ++
  "{\"type\": \"badge\", \"text\": \"live\", \"tone\": \"ok\"}," ++
  "{\"type\": \"code\", \"text\": \"x = 1\"}," ++
  "{\"type\": \"sparkle\", \"text\": \"?\"}," ++
  "{\"type\": \"row\", \"blocks\": [{\"type\": \"stat\", \"label\": \"A\", \"value\": \"1\"}, {\"type\": \"row\", \"blocks\": []}, {\"type\": \"button\", \"label\": \"Go\", \"action\": \"go\"}]}" ++
  "]}"

def want() -> String:
  "{\"title\":\"Deploys\",\"blocks\":[" ++
  "{\"type\":\"heading\",\"text\":\"Today\"}," ++
  "{\"type\":\"text\",\"text\":\"All **green**.\"}," ++
  "{\"type\":\"stat\",\"label\":\"Builds\",\"value\":\"42\",\"hint\":\"+3\"}," ++
  "{\"type\":\"progress\",\"label\":\"Rollout\",\"value\":0.400,\"permille\":400,\"pct\":\"40%\"}," ++
  "{\"type\":\"list\",\"items\":[\"a\",\"b\"]}," ++
  "{\"type\":\"kv\",\"rows\":[[\"k\",\"v\"],[\"x\",\"y\"]]}," ++
  "{\"type\":\"table\",\"head\":[\"a\",\"b\"],\"rows\":[[\"1\",\"2\"]]}," ++
  "{\"type\":\"button\",\"label\":\"Ship\",\"action\":\"ship\"}," ++
  "{\"type\":\"input\",\"label\":\"Note\",\"action\":\"note\",\"placeholder\":\"say\"}," ++
  "{\"type\":\"divider\"}," ++
  "{\"type\":\"badge\",\"text\":\"live\",\"tone\":\"ok\"}," ++
  "{\"type\":\"code\",\"text\":\"x = 1\"}," ++
  "{\"type\":\"row\",\"blocks\":[{\"type\":\"stat\",\"label\":\"A\",\"value\":\"1\",\"hint\":\"\"},{\"type\":\"button\",\"label\":\"Go\",\"action\":\"go\"}]}" ++
  "]}"

def prog(+v: String) -> String:
  Nat.show(SP.Space.permille(v))

# n copies of a block, as JSON items
def many(n: Nat, +b: String) -> String:
  match n:
    case 0n:
      ""
    case 1n+0n:
      b
    case 1n+p:
      b ++ "," ++ many(p, b)

def blocks(+s: String) -> String:
  Nat.show(SP.Space.count(SP.Space.read(s)))

# the first block's text length, and its list's length
def len.first(bs: List<&2, SP.Block>) -> String:
  match bs:
    case SP.BText{s} <> _:
      Nat.show(String.length(s))
    case SP.BList{xs} <> _:
      Nat.show(List.length(&2, String, xs))
    case SP.BTable{h, rs} <> _:
      Nat.show(List.length(&2, String, h)) ++ "x" ++ Nat.show(List.length(&2, List<&2, String>, rs))
    case SP.BRow{ks} <> _:
      Nat.show(List.length(&2, SP.Block, ks))
    case SP.BButton{l, a} <> _:
      Nat.show(String.length(a))
    case _:
      "?"

def first(+s: String) -> String:
  len.first(SP.Space.blocks(SP.Space.read(s)))

# the values of the web view's actions
def Web.attrs(xs: List<&2, D.Attr>) -> String:
  match xs:
    case Nil{}:
      ""
    case D.At{"data-value", v} <> t:
      "[" ++ v ++ "]" ++ Web.attrs(t)
    case D.At{"data-space", v} <> t:
      "{" ++ v ++ "}" ++ Web.attrs(t)
    case D.On{e, a} <> t:
      e ++ ":" ++ a ++ " " ++ Web.attrs(t)
    case _ <> t:
      Web.attrs(t)

def Web.acts(ns: List<&2, D.Node>) -> String:
  match ns:
    case Nil{}:
      ""
    case D.Txt{_} <> t:
      Web.acts(t)
    case D.El{_, _, xs, ks} <> t:
      Web.attrs(xs) ++ Web.acts(ks) ++ Web.acts(t)

def unsep(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{Chr{+c}, t}:
      Bool.pick(String, U32.is_eq(c, 31), "|", SCon{Chr{c}, SNil{}}) ++ unsep(t)

def web() -> String:
  unsep(Web.acts([WS.WSpace.view(SP.Space.read(spec()), "kit")]))

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("every block type", rt(spec()), want())
    C.Check.str("round trip", again(spec()), rt(spec()))
    C.Check.str("round trip progress", again("{\"blocks\":[{\"type\":\"progress\",\"value\":\"12.5%\"},{\"type\":\"progress\",\"value\":1}]}"), rt("{\"blocks\":[{\"type\":\"progress\",\"value\":\"12.5%\"},{\"type\":\"progress\",\"value\":1}]}"))
    C.Check.str("bad json", rt("{\"title\": "), "{\"title\":\"\",\"blocks\":[{\"type\":\"text\",\"text\":\"The space spec could not be read: it is not valid JSON.\"}]}")
    C.Check.str("not an object", rt("[1, 2]"), "{\"title\":\"\",\"blocks\":[]}")
    C.Check.str("unknown skipped", blocks("{\"blocks\":[{\"type\":\"nope\"},{\"type\":\"divider\"},{\"text\":\"no type\"},3]}"), "1")
    C.Check.str("progress 0.4", prog("0.4"), "400")
    C.Check.str("progress 1", prog("1"), "1000")
    C.Check.str("progress 0", prog("0"), "0")
    C.Check.str("progress 40%", prog("40%"), "400")
    C.Check.str("progress 12.5 %", prog(" 12.5 %"), "125")
    C.Check.str("progress 40", prog("40"), "400")
    C.Check.str("progress 250%", prog("250%"), "1000")
    C.Check.str("progress 7", prog("7.5"), "75")
    C.Check.str("progress negative", prog("-0.5"), "0")
    C.Check.str("progress junk", prog("lots"), "0")
    C.Check.str("progress .05", prog("0.05"), "50")
    C.Check.str("pct", SP.Space.pct(125n) ++ " " ++ SP.Space.pct(1000n) ++ " " ++ SP.Space.pct(0n), "12.5% 100% 0%")
    C.Check.str("200 blocks", blocks("{\"blocks\":[" ++ many(250n, "{\"type\":\"divider\"}") ++ "]}"), "200")
    C.Check.str("text 2000", first("{\"blocks\":[{\"type\":\"text\",\"text\":\"" ++ String.repeat("ab", U32.to_nat(1500)) ++ "\"}]}"), "2000")
    C.Check.str("list 200", first("{\"blocks\":[{\"type\":\"list\",\"items\":[" ++ many(230n, "\"x\"") ++ "]}]}"), "200")
    C.Check.str("table 8 cols, 200 rows", first("{\"blocks\":[{\"type\":\"table\",\"head\":[" ++ many(10n, "\"h\"") ++ "],\"rows\":[" ++ many(210n, "[1]") ++ "]}]}"), "8x200")
    C.Check.str("row 6 kids", first("{\"blocks\":[{\"type\":\"row\",\"blocks\":[" ++ many(9n, "{\"type\":\"stat\"}") ++ "]}]}"), "6")
    C.Check.str("empty row dropped", blocks("{\"blocks\":[{\"type\":\"row\",\"blocks\":[{\"type\":\"row\",\"blocks\":[]}]}]}"), "0")
    C.Check.str("action 200", first("{\"blocks\":[{\"type\":\"button\",\"label\":\"b\",\"action\":\"" ++ String.repeat("a", 250n) ++ "\"}]}"), "200")
    C.Check.str("button label stands in", rt("{\"blocks\":[{\"type\":\"button\",\"label\":\"Go\"},{\"type\":\"button\"}]}"), "{\"title\":\"\",\"blocks\":[{\"type\":\"button\",\"label\":\"Go\",\"action\":\"Go\"}]}")
    C.Check.str("input needs an action", blocks("{\"blocks\":[{\"type\":\"input\",\"label\":\"x\"}]}"), "0")
    C.Check.str("message", SP.Space.message("ship", ""), "[space] ship")
    C.Check.str("message value", SP.Space.message("note", "hello there"), "[space] note: hello there")
    C.Check.str("empty", SP.Space.show(SP.Space.empty("Mochi")), "{\"title\":\"Mochi\",\"blocks\":[{\"type\":\"text\",\"text\":\"Mochi hasn't built a space yet.\"},{\"type\":\"text\",\"text\":\"Ask it to make one: a dashboard of what it watches, a checklist, buttons for what you ask it often.\"}]}")
    C.Check.str("web actions", web(), "[kit|ship]click:space {kit|note}{kit|note}click:space-input [kit|go]click:space ")
    C.Check.str("phone sends", unsep(J.Json.show(MS.MSpace.json(SP.Space.read("{\"title\":\"t\",\"blocks\":[{\"type\":\"row\",\"blocks\":[{\"type\":\"button\",\"label\":\"Go\",\"action\":\"go\"}]},{\"type\":\"input\",\"action\":\"note\"},{\"type\":\"divider\"}]}"), "kit"))),
      "{\"bot\":\"kit\",\"title\":\"t\",\"blocks\":[{\"type\":\"row\",\"blocks\":[{\"send\":\"kit\\u001fgo\",\"type\":\"button\",\"label\":\"Go\",\"action\":\"go\"}]},{\"send\":\"kit\\u001fnote\",\"type\":\"input\",\"label\":\"\",\"action\":\"note\",\"placeholder\":\"\"},{\"type\":\"divider\"}]}")
