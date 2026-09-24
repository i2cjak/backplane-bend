import Base
import ../../src/core/space.bend as SP
import ../../src/web/dom.bend as D
import ../../src/web/space.bend as WS

# Prints a sample space as HTML (the body only), for a look in a browser:
#   bend test/tools/space_preview.bend > body.html
# and wrap it with style.css and space.css (see the commit that added it).

def Html.esc.c(+c: U32) -> String:
  Bool.pick(String, U32.is_eq(c, 38), "&amp;",
    Bool.pick(String, U32.is_eq(c, 60), "&lt;",
      Bool.pick(String, U32.is_eq(c, 62), "&gt;",
        Bool.pick(String, U32.is_eq(c, 34), "&quot;",
          Bool.pick(String, U32.is_eq(c, 31), "&#31;", SCon{Chr{c}, SNil{}})))))

def Html.esc(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{Chr{+c}, t}:
      Html.esc.c(c) ++ Html.esc(t)

def Html.attrs(xs: List<&2, D.Attr>) -> String:
  match xs:
    case Nil{}:
      ""
    case D.At{n, v} <> t:
      " " ++ n ++ "=\"" ++ Html.esc(v) ++ "\"" ++ Html.attrs(t)
    case D.On{e, a} <> t:
      " data-on-" ++ e ++ "=\"" ++ Html.esc(a) ++ "\"" ++ Html.attrs(t)

def Html.void(+tag: String) -> Bool:
  Bool.or(String.eq(tag, "input"), String.eq(tag, "hr"))

def Html.close(v: Bool, +tag: String, kids: String) -> String:
  match v:
    case True{}:
      ">"
    case False{}:
      ">" ++ kids ++ "</" ++ tag ++ ">"

def Html.nodes(ns: List<&2, D.Node>) -> String:
  match ns:
    case Nil{}:
      ""
    case D.Txt{s} <> t:
      Html.esc(s) ++ Html.nodes(t)
    case D.El{+tag, _, xs, ks} <> t:
      "<" ++ tag ++ Html.attrs(xs) ++ Html.close(Html.void(tag), tag, Html.nodes(ks)) ++ Html.nodes(t)

def sample() -> String:
  "{\"title\": \"Deploy watch\", \"blocks\": [" ++
  "{\"type\": \"text\", \"text\": \"I watch **main** and the release branch, and ship when CI is green. Ask me in the thread for anything else, or use `ship` below.\"}," ++
  "{\"type\": \"row\", \"blocks\": [" ++
  "{\"type\": \"stat\", \"label\": \"Builds today\", \"value\": 42, \"hint\": \"+6 since noon\"}," ++
  "{\"type\": \"stat\", \"label\": \"Failing\", \"value\": \"1\", \"hint\": \"backplane-e2e\"}," ++
  "{\"type\": \"stat\", \"label\": \"Median build\", \"value\": \"3m 12s\"}]}," ++
  "{\"type\": \"progress\", \"label\": \"Rollout to fleet\", \"value\": 0.625}," ++
  "{\"type\": \"progress\", \"label\": \"Disk on build host\", \"value\": \"87%\"}," ++
  "{\"type\": \"heading\", \"text\": \"Status\"}," ++
  "{\"type\": \"row\", \"blocks\": [{\"type\": \"badge\", \"text\": \"main green\", \"tone\": \"ok\"}, {\"type\": \"badge\", \"text\": \"release 2 behind\", \"tone\": \"warn\"}, {\"type\": \"badge\", \"text\": \"e2e failing\", \"tone\": \"bad\"}, {\"type\": \"badge\", \"text\": \"idle\"}]}," ++
  "{\"type\": \"kv\", \"rows\": [[\"Last deploy\", \"v2.4.1, 14:02\"], [\"Next window\", \"tonight 22:00\"], [\"On call\", \"kelly\"]]}," ++
  "{\"type\": \"heading\", \"text\": \"Recent runs\"}," ++
  "{\"type\": \"table\", \"head\": [\"Branch\", \"Commit\", \"Result\", \"Time\"], \"rows\": [[\"main\", \"c331d99\", \"pass\", \"3m 02s\"], [\"release\", \"9084fa5\", \"pass\", \"3m 40s\"], [\"pr/412\", \"a81f07e\", \"fail\", \"1m 12s\"]]}," ++
  "{\"type\": \"heading\", \"text\": \"To do\"}," ++
  "{\"type\": \"list\", \"items\": [\"Bump the KiCad parser for v9 files\", \"Re-run e2e on pr/412 after the flake fix\", \"Write release notes\"]}," ++
  "{\"type\": \"divider\"}," ++
  "{\"type\": \"row\", \"blocks\": [{\"type\": \"button\", \"label\": \"Ship release\", \"action\": \"ship\"}, {\"type\": \"button\", \"label\": \"Re-run e2e\", \"action\": \"rerun e2e\"}, {\"type\": \"button\", \"label\": \"Pause\", \"action\": \"pause\"}]}," ++
  "{\"type\": \"input\", \"label\": \"Note for the release\", \"action\": \"note\", \"placeholder\": \"What changed?\"}," ++
  "{\"type\": \"code\", \"text\": \"$ gh run list --limit 3\\ncompleted  success  main     3m02s\\ncompleted  failure  pr/412   1m12s\"}" ++
  "]}"

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(Html.nodes([WS.WSpace.view(SP.Space.read(sample()), "Mochi")]))
