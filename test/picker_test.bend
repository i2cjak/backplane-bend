import Base
import ./check.bend as C
import ../src/core/client.bend as U
import ../src/core/fuzzy.bend as FZ
import ../src/core/json.bend as J

def labels(ps: List<&2, U.PItem>) -> String:
  match ps:
    case Nil{}:
      ""
    case U.PItem{l, _, _} <> t:
      l ++ "|" ++ labels(t)

# a picker listing /home/h with a few folders (as the fs.list reply
# arrives), filtered by q
def at(+q: String) -> String:
  labels(U.Proj.items(U.Proj.set(U.Proj.reply(True{}, U.Ui.init(0n),
    Maybe.default(&2, J.Json, J.Json.parse("{\"result\":{\"dir\":\"/home/h\",\"entries\":[\"Development\",\"docs\",\".cache\",\"dev-notes\"]}}"), J.Null{})), q, 0n)))

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("no filter", at(""), "Add /home/h as a project|..|Development/|docs/|dev-notes/|")
    C.Check.str("filter ranks", at("dev"), "Development/|dev-notes/|Create folder 'dev' here|Add /home/h as a project|")
    C.Check.str("existing name is not created", at("docs"), "docs/|Add /home/h as a project|")
    C.Check.str("hidden on dot", at(".ca"), ".cache/|Create folder '.ca' here|Add /home/h as a project|")
    C.Check.str("path", at("~/x"), "Go to ~/x|")
    C.Check.str("slash name", at("a/b"), "Add /home/h as a project|")
    C.Check.str("parent", U.Proj.parent("/home/h"), "/home")
    C.Check.str("parent of top", U.Proj.parent("/home"), "/")
    C.Check.str("no match", Nat.show(FZ.Fuzzy.score("docs", "x")), "0")
