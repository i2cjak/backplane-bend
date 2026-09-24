import Base
import ./check.bend as C
import ../src/core/client.bend as U
import ../src/core/json.bend as J
import ../src/mobile/picker.bend as PK

def ui(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}:
      u

def sent(cs: List<&2, U.Cmd>) -> String:
  match cs:
    case Nil{}:
      ""
    case U.Send{t} <> r:
      J.Json.show(J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(t), J.Null{}), "p")) ++ sent(r)
    case _ <> r:
      sent(r)

def asks(a: U.Act) -> String:
  match a:
    case U.Act{_, cs}:
      sent(cs)

def json(+s: String) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(s), J.Null{})

def listing(+id: String, +dir: String) -> J.Json:
  json("{\"t\":\"reply\",\"id\":" ++ id ++ ",\"ok\":true,\"result\":{\"dir\":\"" ++ dir ++ "\",\"entries\":[\"Development\",\"docs\",\".cache\",\"dev-notes\"]}}")

def recv(u: U.Ui, +o: J.Json) -> U.Ui:
  PK.MPick.seen(U.Ui.recv(u, o))

def labels(xs: List<&2, J.Json>) -> String:
  match xs:
    case Nil{}:
      ""
    case +x <> t:
      J.Json.get_str(x, "label", "") ++ "=" ++ J.Json.get_str(x, "value", "") ++ "|" ++ labels(t)

def rows(+u: U.Ui) -> String:
  labels(J.Json.elems(J.Json.get_obj(PK.MPick.json(u), "items")))

def field(+u: U.Ui) -> String:
  J.Json.get_str(PK.MPick.json(u), "text", "?")

# opened (its fs.list of ~/ is request 0) and that listing arrived
def listed() -> U.Ui:
  recv(ui(PK.MPick.open(U.Ui.init(0n))), listing("0", "/home/h"))

def main() -> IO(Unit):
  +l = listed()
  +docs = PK.MPick.type(l, "~/docs/")
  +filtered = PK.MPick.type(l, "~/dev")
  +made = recv(ui(PK.MPick.mkdir(l, "/home/h/new")), json("{\"t\":\"reply\",\"id\":1,\"ok\":true,\"result\":{\"dir\":\"/home/h/new\",\"entries\":[]}}"))
  +missing = recv(ui(PK.MPick.type(l, "~/nope/")), json("{\"t\":\"reply\",\"id\":1,\"ok\":false,\"result\":{\"error\":\"no such folder: /home/h/nope\"}}"))
  do IO<Unit>:
    C.Check.str("opens at home", asks(PK.MPick.open(U.Ui.init(0n))), "{\"path\":\"~/\"}")
    C.Check.str("closed is null", J.Json.show(PK.MPick.json(U.Ui.init(0n))), "null")
    C.Check.str("field", field(l), "~/")
    C.Check.str("home learned", U.Ui.info(l, "proj.home"), "/home/h")
    C.Check.str("rows", rows(l), "Add ~ as a project=/home/h|..=/home/|Development=~/Development/|docs=~/docs/|dev-notes=~/dev-notes/|")
    C.Check.str("tap lists the folder", asks(docs), "{\"path\":\"~/docs/\"}")
    C.Check.str("tap fills the field", field(ui(docs)), "~/docs/")
    C.Check.str("filter asks nothing", asks(filtered), "")
    C.Check.str("filter", rows(ui(filtered)), "Development=~/Development/|dev-notes=~/dev-notes/|Create project 'dev' here=/home/h/dev|Create folder 'dev' here=/home/h/dev|Add ~ as a project=/home/h|")
    C.Check.str("folder made is followed", field(made), "~/new/")
    C.Check.str("followed without asking", asks(PK.MPick.type(made, "~/new/")), "")
    C.Check.str("error hides rows", rows(missing), "")
    C.Check.str("error shown", J.Json.get_str(PK.MPick.json(missing), "error", ""), "no such folder: /home/h/nope")
    C.Check.str("dir of ~", PK.MPick.dir("~"), "~/")
    C.Check.str("dir of bare name", PK.MPick.dir("abc"), "~/")
    C.Check.str("dir of root", PK.MPick.dir("/"), "/")
    C.Check.str("filter of ~", PK.MPick.filter("~"), "")
    C.Check.str("tilde elsewhere", PK.MPick.tilde("/home/h", "/home/hx"), "/home/hx")
