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

def ui(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}:
      u

def json(+s: String) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(s), J.Null{})

def listing(+id: String, +dir: String) -> J.Json:
  json("{\"t\":\"reply\",\"id\":" ++ id ++ ",\"ok\":true,\"result\":{\"dir\":\"" ++ dir ++ "\",\"entries\":[\"Development\",\"docs\",\".cache\",\"dev-notes\"]}}")

# the picker opened (its fs.list is request 0) and that listing arrived
def listed() -> U.Ui:
  U.Ui.recv(ui(U.Ui.act(U.Ui.init(0n), "proj-open", "")), listing("0", "/home/h"))

def at(+q: String) -> String:
  labels(U.Proj.items(U.Proj.set(listed(), q, 0n)))

def main() -> IO(Unit):
  +cd = ui(U.Ui.act(listed(), "proj-cd", "/home/h/docs"))
  +late = U.Ui.recv(cd, listing("0", "/somewhere/old"))
  +adding = ui(U.Ui.act(listed(), "proj-add", "/home/h"))
  +refused = U.Ui.recv(adding, json("{\"t\":\"reply\",\"id\":1,\"ok\":false,\"error\":\"already a project: /home/h\"}"))
  +added = U.Ui.recv(adding, json("{\"t\":\"reply\",\"id\":1,\"ok\":true,\"result\":{}}"))
  +missing = U.Ui.recv(cd, json("{\"t\":\"reply\",\"id\":1,\"ok\":false,\"result\":{\"error\":\"no such folder: /home/h/docs\"}}"))
  do IO<Unit>:
    C.Check.str("no filter", at(""), "Add /home/h as a project|..|Development/|docs/|dev-notes/|")
    C.Check.str("filter ranks", at("dev"), "Development/|dev-notes/|Create project 'dev' here|Create folder 'dev' here|Add /home/h as a project|")
    C.Check.str("existing name is not created", at("docs"), "docs/|Add /home/h as a project|")
    C.Check.str("hidden on dot", at(".ca"), ".cache/|Create project '.ca' here|Create folder '.ca' here|Add /home/h as a project|")
    C.Check.str("name trimmed", at(" new "), "Create project 'new' here|Create folder 'new' here|Add /home/h as a project|")
    C.Check.str("path", at("~/x"), "Go to ~/x|Add ~/x as a project|Create project ~/x|")
    C.Check.str("slash name", at("a/b"), "Add /home/h as a project|")
    C.Check.str("parent", U.Proj.parent("/home/h"), "/home")
    C.Check.str("parent of top", U.Proj.parent("/home"), "/")
    C.Check.str("no match", Nat.show(FZ.Fuzzy.score("docs", "x")), "0")
    C.Check.str("late listing dropped", U.Proj.dir(late), "/home/h")
    C.Check.str("refused shows in picker", U.Ui.info(refused, "proj.err"), "already a project: /home/h")
    C.Check.str("refused stays open", Bool.show(U.Ui.flag(refused, "proj")), "True")
    C.Check.str("added closes", Bool.show(U.Ui.flag(added, "proj")), "False")
    C.Check.str("server error text", U.Ui.info(missing, "proj.err"), "no such folder: /home/h/docs")
