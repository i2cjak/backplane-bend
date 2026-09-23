import Base
import ../core/json.bend as J
import ../core/client.bend as U
import ../app/viewer.bend as V

# The phones' board viewer, as the Bend client decides it. The viewer
# shows the selected thread's project board, schematic or 3D model
# ("@view": "board", "schematic", "3d", "" closed). The hub is asked for exactly the source on
# screen (kicad.watch), once per change of source, and again after a
# reconnect (a new connection watches nothing). Plots (core/plot.bend)
# come straight to the phone's renderer, not through here; one whose key
# is not the screen's viewer key is stale and never shown.

def View.known(+kind: String) -> Bool:
  Bool.or(String.eq(kind, "board"), Bool.or(String.eq(kind, "schematic"), String.eq(kind, "3d")))

def View.num(+kind: String) -> String:
  Bool.pick(String, String.eq(kind, "schematic"), "1", Bool.pick(String, String.eq(kind, "3d"), "2", "0"))

# the source key a plot for kind and root carries ("" when none)
def View.key(+kind: String, +root: String) -> String:
  Bool.pick(String, Bool.or(Bool.or(String.is_empty(root), String.is_empty(kind)), Bool.not(View.known(kind))), "",
    View.num(kind) ++ "|" ++ root ++ "|")

# the plot whose chunks the view draws: a 3D view draws the board's
# layers on its faces ("" for none)
def View.layers(+kind: String, +root: String) -> String:
  View.key(Bool.pick(String, String.eq(kind, "3d"), "board", kind), root)

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

# open a viewer ("board", "schematic", "3d") or close it (""); what was
# picked is let go
def View.open(u: U.Ui, v: String) -> U.Act:
  View.sync(U.Act{U.Ui.scratch_set(U.Ui.scratch_set(U.Ui.scratch_set(U.Ui.scratch_set(u, "@view", v), "@pick", ""), "@card", ""), "@pick.rid", ""), Nil{}})

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

# which board layers a 3D view lays on the board's top and bottom faces,
# in paint order as seen from that side (from below, B.Cu first and
# B.SilkS over it); inner layers are inside the board
def View.top() -> List<&2, U32>:
  [12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24]

def View.bottom() -> List<&2, U32>:
  [5, 13, 4, 2, 3, 1, 0, 22, 23, 24]

def View.nums(xs: List<&2, U32>) -> List<&2, J.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      J.Num{U32.show(x)} <> View.nums(t)

def View.choice(+label: String, +value: String, +kind: String) -> J.Json:
  J.Json.obj([J.KV{"label", J.Str{label}}, J.KV{"value", J.Str{value}}, J.KV{"on", J.Flag{String.eq(kind, value)}}])

# Inspecting a tap
# ----------------
# The phone hit-tests its own geometry and hands over what lies under the
# finger: each piece's place (its chunk's index in the plot, the piece's
# index in the chunk), its size (in 100 square micrometres) and its layer.
# The smallest wins (a pad over the zone it sits in), then the one drawn on
# top. It is highlighted at once, and its info (net, ref, value...) asked
# of the hub, which answers from the very chunks this phone holds (law
# plot_delta_exact); the card shows it as the window's inspector does.

type Cand is Data:
  Cand{id: String, area: U32, layer: U32}

def Pick.num(+o: J.Json, +k: String) -> U32:
  Maybe.default(&2, U32, U32.read(J.Json.as_raw(J.Json.get(o, k), "0")), 0)

def Pick.cand(+o: J.Json) -> Cand:
  Cand{J.Json.as_raw(J.Json.get(o, "c"), "0") ++ "," ++ J.Json.as_raw(J.Json.get(o, "p"), "0"), Pick.num(o, "a"), Pick.num(o, "l")}

def Pick.cands(js: List<&2, J.Json>) -> List<&2, Cand>:
  match js:
    case Nil{}:
      Nil{}
    case j <> t:
      Pick.cand(j) <> Pick.cands(t)

def Pick.over(c: Cand, b: Cand) -> Bool:
  match c b:
    case Cand{_, +a, +l} Cand{_, +ba, +bl}:
      Bool.or(U32.is_lt(a, ba), Bool.and(U32.is_eq(a, ba), U32.is_ge(l, bl)))

def Pick.better.k(take: Bool, c: Cand, b: Cand) -> Cand:
  match take:
    case True{}:
      c
    case False{}:
      b

def Pick.better(+c: Cand, m: Maybe<&2, Cand>) -> Maybe<&2, Cand>:
  match m:
    case None{}:
      Some{c}
    case Some{+b}:
      Some{Pick.better.k(Pick.over(c, b), c, b)}

# the piece a tap picks, of those under the finger
def Pick.best(cs: List<&2, Cand>, m: Maybe<&2, Cand>) -> Maybe<&2, Cand>:
  match cs:
    case Nil{}:
      m
    case c <> t:
      Pick.best(t, Pick.better(c, m))

def Pick.of(+text: String) -> Maybe<&2, Cand>:
  Pick.best(Pick.cands(J.Json.elems(Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{}))), None{})

def Pick.clear(u: U.Ui) -> U.Ui:
  U.Ui.scratch_set(U.Ui.scratch_set(U.Ui.scratch_set(u, "@pick", ""), "@card", ""), "@pick.rid", "")

def Pick.ask.k(+at: String, a: U.Act) -> U.Act:
  match a:
    case U.Act{u, cs}:
      U.Act{U.Ui.scratch_set(u, "@pick", at), cs}

def Pick.ask(m: Maybe<&2, Cand>, +u: U.Ui) -> U.Act:
  match m:
    case None{}:
      U.Act{Pick.clear(u), Nil{}}
    case Some{Cand{+id, _, _}}:
      Pick.ask.k(id, U.Ui.rpc(U.Ui.scratch_set(Pick.clear(u), "@pick.rid", Nat.show(U.Ui.rid(u))), "kicad.info",
        [J.KV{"key", J.Str{View.layers(View.kind(u), U.Ui.root(u))}},
         J.KV{"at", J.Num{Maybe.default(&2, String, List.head(&2, String, String.split(id, ',')), "0")}},
         J.KV{"idx", J.Num{Maybe.default(&2, String, List.head(&2, String, List.drop(&2, String, String.split(id, ','), 1n)), "0")}}]))

# a tap in the viewer, given what lies under the finger: the piece it
# picks is highlighted and its info asked of the hub; a tap on nothing
# clears the card (law pick_nothing_there)
def View.pick(+u: U.Ui, +text: String) -> U.Act:
  Pick.ask(Pick.of(text), u)

def View.picked.k(mine: Bool, +u: U.Ui, +o: J.Json) -> U.Ui:
  match mine:
    case True{}:
      U.Ui.scratch_set(U.Ui.scratch_set(u, "@pick.rid", ""), "@card", J.Json.get_str(J.Json.get_obj(o, "result"), "info", ""))
    case False{}:
      u

# the hub's answer to the newest pick fills the card (a late one for an
# earlier tap changes nothing)
def View.picked(+u: U.Ui, +o: J.Json) -> U.Ui:
  View.picked.k(Bool.and(Bool.and(Bool.not(String.is_empty(U.Ui.scratch(u, "@pick.rid"))), String.eq(J.Json.as_raw(J.Json.get(o, "id"), ""), U.Ui.scratch(u, "@pick.rid"))),
    String.eq(J.Json.get_str(o, "t", ""), "reply")), u, o)

def Insp.row(kv: List<&2, String>) -> J.Json:
  match kv:
    case k <> v:
      J.Json.obj([J.KV{"k", J.Str{k}}, J.KV{"v", J.Str{String.join(v, "=")}}])
    case Nil{}:
      J.Json.obj([J.KV{"k", J.Str{""}}, J.KV{"v", J.Str{""}}])

def Insp.rows(ps: List<&2, String>) -> List<&2, J.Json>:
  match ps:
    case Nil{}:
      Nil{}
    case p <> t:
      Insp.row(String.split(p, '=')) <> Insp.rows(t)

# an item's card: its kind, then key = value rows (net, ref, value,
# footprint, pin, label...), as the window's inspector
def Insp.card(+info: String) -> J.Json:
  J.Json.obj([J.KV{"info", J.Str{info}}, J.KV{"title", J.Str{Maybe.default(&2, String, List.head(&2, String, String.split(info, ';')), "")}},
    J.KV{"rows", J.Json.arr(Insp.rows(List.drop(&2, String, String.split(info, ';'), 1n)))}])

def Insp.json(+info: String) -> J.Json:
  Bool.pick(J.Json, String.is_empty(info), J.Null{}, Insp.card(info))

# what the phone's viewer needs: the source open ("" closed), its key and
# the key of the plot it draws layers from, the choices, and how to draw:
# background, the fade of new chunks (ms, as the window's), the first
# view's margin, the zoom range as a share of that view and in pixels per
# micrometre, how far from a tap (points) an item still counts as tapped,
# and for 3D the faces' layers, the board's colour before its model
# arrives, and the field of view (degrees)
def View.json(+u: U.Ui) -> J.Json:
  J.Json.obj([J.KV{"open", J.Str{Bool.pick(String, String.is_empty(View.want(u)), "", View.kind(u))}}, J.KV{"key", J.Str{View.want(u)}},
    J.KV{"layers", J.Str{View.layers(View.kind(u), U.Ui.root(u))}},
    J.KV{"choices", J.Json.arr(Bool.pick(List<&2, J.Json>, String.is_empty(U.Ui.root(u)), Nil{},
      [View.choice("Board", "board", View.kind(u)), View.choice("Schematic", "schematic", View.kind(u)), View.choice("3D", "3d", View.kind(u))]))},
    J.KV{"bg", J.Num{U32.show(View.bg(View.kind(u)))}}, J.KV{"fade", J.Num{Nat.show(V.Fade.ms())}}, J.KV{"margin", J.Num{"0.9"}},
    J.KV{"zmin", J.Num{"0.5"}}, J.KV{"zmax", J.Num{"0.5"}}, J.KV{"tap", J.Num{"14"}},
    J.KV{"top", J.Json.arr(View.nums(View.top()))}, J.KV{"bottom", J.Json.arr(View.nums(View.bottom()))},
    J.KV{"slab", J.Num{"2375219"}}, J.KV{"fov", J.Num{"35"}},
    J.KV{"picked", J.Str{U.Ui.scratch(u, "@pick")}}, J.KV{"card", Insp.json(U.Ui.scratch(u, "@card"))}])

def View.mention.text(+draft: String, +info: String) -> String:
  draft ++ Bool.pick(String, String.is_empty(draft), "", " ") ++ "[" ++ info ++ "] "

# "Mention in chat": the item goes into the thread's draft (as the
# window's inspector puts it) and the viewer closes on it
def View.mention.k(a: U.Act) -> U.Act:
  match a:
    case U.Act{u, cs}:
      View.join(View.open(u, ""), cs)

def View.mention(+u: U.Ui, +info: String) -> U.Act:
  View.mention.k(U.Ui.act(u, "draft", View.mention.text(U.Ui.draft_text(u), info)))
