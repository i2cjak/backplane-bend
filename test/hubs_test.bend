import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/codec.bend as K
import ../src/core/json.bend as J
import ../src/core/client.bend as U
import ../src/mobile/hubs.bend as H

# The phone with several hubs: one client each, one screen, actions
# routed by the hub their value names.

def items(cs: List<&2, M.Change>) -> List<&2, J.Json>:
  match cs:
    case Nil{}:
      Nil{}
    case c <> t:
      K.Change.encode(c) <> items(t)

def machines(+name: String) -> String:
  "{\"self\":{\"name\":\"" ++ name ++ "\",\"url\":\"http://x\"},\"peers\":[{\"name\":\"desk\",\"url\":\"http://100.2.2.2:3787\"},{\"name\":\"lap\",\"url\":\"http://100.1.1.1:3787\"},{\"name\":\"desk\",\"url\":\"http://100.2.2.2:3787\"}]}"

def log(cs: List<&2, M.Change>, +name: String) -> J.Json:
  J.Json.obj([J.KV{"t", J.Json.str("log")}, J.KV{"items", J.Json.arr(items(cs))},
    J.KV{"info", J.Json.obj([J.KV{"machines", J.Json.str(machines(name))}])}])

def two() -> H.Hubs:
  H.Hubs.after(H.Hubs.recv(
    H.Hubs.after(H.Hubs.recv(H.Hubs.set(H.Hubs.init(0n, "c"), ["100.1.1.1:3787", "box:3787"]), "100.1.1.1:3787",
      log([M.ProjectCreated{"p1", "Lap", "/lap", 50n}, M.ThreadCreated{"t1", "p1", "One", M.Local{}, "", "", "claude", "", 100n}], "lap"))),
    "box:3787",
    log([M.ProjectCreated{"p2", "Box", "/box", 50n}, M.ThreadCreated{"t2", "p2", "Two", M.Local{}, "", "", "claude", "", 100n}], "")))

def strs(js: List<&2, J.Json>, +key: String) -> String:
  match js:
    case Nil{}:
      ""
    case j <> t:
      J.Json.get_str(j, key, "") ++ ";" ++ strs(t, key)

def screen(+h: H.Hubs, +key: String) -> String:
  J.Json.get_str(H.Hubs.screen(h), key, "")

def list(+h: H.Hubs, +key: String, +field: String) -> String:
  strs(J.Json.elems(J.Json.get_obj(H.Hubs.screen(h), key)), field)

def rows(+h: H.Hubs) -> String:
  strs(J.Json.elems(J.Json.get_obj(Maybe.default(&2, J.Json, List.head(&2, J.Json, J.Json.elems(J.Json.get_obj(H.Hubs.screen(h), "projects"))), J.Null{}), "threads")), "id")

def cmds(cs: List<&2, H.HCmd>) -> String:
  match cs:
    case Nil{}:
      ""
    case H.HCmd{k, U.Send{_}} <> t:
      "send@" ++ k ++ " " ++ cmds(t)
    case H.HCmd{k, _} <> t:
      "cmd@" ++ k ++ " " ++ cmds(t)

def sel(+h: H.Hubs, +k: String) -> String:
  U.Ui.sel(H.Hubs.ui(h, k))

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("first hub is current", H.Hubs.cur(two()), "100.1.1.1:3787")
    C.Check.str("projects of both", list(two(), "projects", "id"), "100.1.1.1:3787|p1;box:3787|p2;")
    C.Check.str("under machine names", list(two(), "projects", "machine"), "lap;box;")
    C.Check.str("thread ids qualified", rows(two()), "100.1.1.1:3787|t1;")
    C.Check.str("hubs listed", list(two(), "hubs", "name"), "lap;box;")
    C.Check.str("nothing selected", screen(two(), "sel"), "")
    C.Check.str("peers not paired, once each", list(two(), "found", "url"), "http://100.2.2.2:3787;")
    C.Check.str("select moves to its hub", H.Hubs.cur(H.Hubs.after(H.Hubs.act(two(), "select", "box:3787|t2"))), "box:3787")
    C.Check.str("selected there", sel(H.Hubs.after(H.Hubs.act(two(), "select", "box:3787|t2")), "box:3787"), "t2")
    C.Check.str("screen sel qualified", screen(H.Hubs.after(H.Hubs.act(two(), "select", "box:3787|t2")), "sel"), "box:3787|t2")
    C.Check.str("thread shown", J.Json.get_str(J.Json.get_obj(H.Hubs.screen(H.Hubs.after(H.Hubs.act(two(), "select", "box:3787|t2"))), "thread"), "title", ""), "Two")
    C.Check.str("the hub left drops its thread",
      sel(H.Hubs.after(H.Hubs.act(H.Hubs.after(H.Hubs.act(two(), "select", "100.1.1.1:3787|t1")), "select", "box:3787|t2")), "100.1.1.1:3787"), "")
    C.Check.str("a thread's action goes to the current hub",
      cmds(H.Hubs.cmds(H.Hubs.act(H.Hubs.after(H.Hubs.act(two(), "select", "box:3787|t2")), "pin", ""))), "send@box:3787 ")
    C.Check.str("a row's action goes to its hub", cmds(H.Hubs.cmds(H.Hubs.act(two(), "row-settle", "box:3787|t2"))), "send@box:3787 ")
    C.Check.str("a row's action keeps the current hub", H.Hubs.cur(H.Hubs.after(H.Hubs.act(two(), "row-settle", "box:3787|t2"))), "100.1.1.1:3787")
    C.Check.str("unknown hub: the current", cmds(H.Hubs.cmds(H.Hubs.act(two(), "add-project", "/some/path"))), "send@100.1.1.1:3787 ")
    C.Check.str("add a project on a hub", cmds(H.Hubs.cmds(H.Hubs.act(two(), "add-project", "box:3787|/some/path"))), "send@box:3787 ")
    C.Check.str("unpaired: current stays while paired", H.Hubs.cur(H.Hubs.set(H.Hubs.after(H.Hubs.act(two(), "select", "box:3787|t2")), ["box:3787"])), "box:3787")
    C.Check.str("unpaired: current falls to the first", H.Hubs.cur(H.Hubs.set(two(), ["box:3787"])), "box:3787")
    C.Check.str("kept hub keeps its log", list(H.Hubs.set(two(), ["box:3787"]), "projects", "id"), "box:3787|p2;")
    C.Check.str("one hub: no machine name", list(H.Hubs.set(two(), ["box:3787"]), "projects", "machine"), ";")
    C.Check.str("no hubs", screen(H.Hubs.init(0n, "c"), "empty"), "Pair with a hub to start.")
    C.Check.str("register tells every hub", cmds(H.Hubs.cmds(H.Hubs.register(two(), "ios", "tok", "alert", "", "sandbox", "b"))), "send@100.1.1.1:3787 send@box:3787 ")
    C.Check.str("picker opens on its hub", H.Hubs.cur(H.Hubs.after(H.Hubs.act(two(), "picker-open", "box:3787|"))), "box:3787")
    C.Check.str("picker asks that hub", cmds(H.Hubs.cmds(H.Hubs.act(two(), "picker-open", "box:3787|"))), "send@box:3787 ")
    C.Check.str("picker's paths stay as they are",
      J.Json.get_str(J.Json.get_obj(H.Hubs.screen(H.Hubs.after(H.Hubs.act(two(), "picker-open", "box:3787|"))), "folders"), "text", ""), "~/")
    C.Check.str("snooze value", H.Hubs.rest("box:3787|t2|1h"), "t2|1h")
