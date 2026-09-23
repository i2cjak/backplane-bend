import Base
import ../core/json.bend as J
import ../core/client.bend as U
import ../app/viewer.bend as V

# The phones' board viewer, as the Bend client decides it. The viewer
# shows the selected thread's project board or schematic ("@view": "board",
# "schematic", "" closed). The hub is asked for exactly the source on
# screen (kicad.watch), once per change of source, and again after a
# reconnect (a new connection watches nothing). Plots (core/plot.bend)
# come straight to the phone's renderer, not through here; one whose key
# is not the screen's viewer key is stale and never shown.

# the source key a plot for kind and root carries ("" when none)
def View.key(+kind: String, +root: String) -> String:
  Bool.pick(String, Bool.or(Bool.or(String.is_empty(root), String.is_empty(kind)), Bool.not(Bool.or(String.eq(kind, "board"), String.eq(kind, "schematic")))), "",
    Bool.pick(String, String.eq(kind, "schematic"), "1", "0") ++ "|" ++ root ++ "|")

def View.kind(+u: U.Ui) -> String:
  U.Ui.scratch(u, "@view")

# the source the screen shows now
def View.want(+u: U.Ui) -> String:
  View.key(View.kind(u), U.Ui.root(u))

def View.ask(+want: String, +kind: String, +root: String) -> List<&2, J.KV>:
  [J.KV{"kind", J.Str{Bool.pick(String, String.is_empty(want), "", kind)}}, J.KV{"root", J.Str{root}}, J.KV{"path", J.Str{""}}]

def View.join(a: U.Act, cmds: List<&2, U.Cmd>) -> U.Act:
  match a:
    case U.Act{u, cs}:
      U.Act{u, List.append(&2, U.Cmd, cmds, cs)}

def View.sync.k(same: Bool, u: U.Ui, +want: String, +kind: String, +root: String, cmds: List<&2, U.Cmd>) -> U.Act:
  match same:
    case True{}:
      U.Act{u, cmds}
    case False{}:
      View.join(U.Ui.rpc(U.Ui.scratch_set(u, "@view.at", want), "kicad.watch", View.ask(want, kind, root)), cmds)

def View.sync.u(+u: U.Ui, cmds: List<&2, U.Cmd>) -> U.Act:
  View.sync.k(String.eq(View.want(u), U.Ui.scratch(u, "@view.at")), u, View.want(u), View.kind(u), U.Ui.root(u), cmds)

# an action's result with the hub asked for the source now on screen,
# when that changed (law view_asks_once)
def View.sync(a: U.Act) -> U.Act:
  match a:
    case U.Act{+u, cmds}:
      View.sync.u(u, cmds)

# open a viewer ("board", "schematic") or close it ("")
def View.open(u: U.Ui, v: String) -> U.Act:
  View.sync(U.Act{U.Ui.scratch_set(u, "@view", v), Nil{}})

# a new connection watches nothing: ask again once online
def View.online.k(on: Bool, u: U.Ui) -> U.Act:
  match on:
    case True{}:
      View.sync(U.Act{U.Ui.scratch_set(u, "@view.at", ""), Nil{}})
    case False{}:
      U.Act{u, Nil{}}

def View.online(u: U.Ui, +on: Bool) -> U.Act:
  View.online.k(on, U.Ui.online(u, on))

# The screen's part
# -----------------

def View.bg(+kind: String) -> U32:
  855826

def View.choice(+label: String, +value: String, +kind: String) -> J.Json:
  J.Json.obj([J.KV{"label", J.Str{label}}, J.KV{"value", J.Str{value}}, J.KV{"on", J.Flag{String.eq(kind, value)}}])

# what the phone's viewer needs: the source open ("" closed) and its key,
# the choices, and how to draw: background, the fade of new chunks (ms,
# as the window's), the first view's margin, and the zoom range as a
# share of that view and in pixels per micrometre
def View.json(+u: U.Ui) -> J.Json:
  J.Json.obj([J.KV{"open", J.Str{Bool.pick(String, String.is_empty(View.want(u)), "", View.kind(u))}}, J.KV{"key", J.Str{View.want(u)}},
    J.KV{"choices", J.Json.arr(Bool.pick(List<&2, J.Json>, String.is_empty(U.Ui.root(u)), Nil{},
      [View.choice("Board", "board", View.kind(u)), View.choice("Schematic", "schematic", View.kind(u))]))},
    J.KV{"bg", J.Num{U32.show(View.bg(View.kind(u)))}}, J.KV{"fade", J.Num{Nat.show(V.Fade.ms())}}, J.KV{"margin", J.Num{"0.9"}},
    J.KV{"zmin", J.Num{"0.5"}}, J.KV{"zmax", J.Num{"0.5"}}])
