import Base
import ./check.bend as C
import ../src/core/client.bend as U
import ../src/core/json.bend as J

# The viewer belongs to a thread: a viewer_show lands in the viewer of the
# thread that asked, and each thread keeps its own.

def ui(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}:
      u

def json(+s: String) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(s), J.Null{})

def view(+th: String, +path: String) -> J.Json:
  json("{\"t\":\"view\",\"thread\":\"" ++ th ++ "\",\"path\":\"" ++ path ++ "\",\"kind\":\"\"}")

def on(u: U.Ui, +id: String) -> U.Ui:
  ui(U.Ui.select(u, id))

def main() -> IO(Unit):
  +a = on(U.Ui.init(0n), "a")
  +shown = U.Ui.recv(a, view("a", "/p/a.kicad_pcb"))
  +other = U.Ui.recv(a, view("b", "/p/b.kicad_sch"))
  +both = U.Ui.recv(shown, view("b", "/p/b.kicad_sch"))
  +old = U.Ui.recv(a, json("{\"t\":\"view\",\"path\":\"/p/x.glb\",\"kind\":\"\"}"))
  +picked = U.Ui.view_pick(both, "schematic")
  do IO<Unit>:
    C.Check.str("own thread shows", U.Ui.view_get(shown, "view.path"), "/p/a.kicad_pcb")
    C.Check.str("own thread opens", Bool.show(U.Ui.panel(shown)), "True")
    C.Check.str("other thread waits", U.Ui.view_get(other, "view.path"), "")
    C.Check.str("other thread stays shut", Bool.show(U.Ui.panel(other)), "False")
    C.Check.str("each keeps its own", U.Ui.view_get(both, "view.path"), "/p/a.kicad_pcb")
    C.Check.str("switching shows the other's", U.Ui.view_get(on(both, "b"), "view.path"), "/p/b.kicad_sch")
    C.Check.str("switching back", U.Ui.view_get(on(on(both, "b"), "a"), "view.path"), "/p/a.kicad_pcb")
    C.Check.str("unnamed goes to selected", U.Ui.view_get(old, "view.path"), "/p/x.glb")
    C.Check.str("picked kind clears path", U.Ui.view_get(picked, "view.kind") ++ "|" ++ U.Ui.view_get(picked, "view.path"), "schematic|")
    C.Check.str("picked for this thread only", U.Ui.view_get(on(picked, "b"), "view.path"), "/p/b.kicad_sch")
    C.Check.str("asking again counts", U.Ui.view_get(U.Ui.recv(shown, view("a", "/p/a.kicad_pcb")), "view.n"), "2")
