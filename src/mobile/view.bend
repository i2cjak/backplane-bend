import Base
import ../core/json.bend as J
import ../core/client.bend as U
import ../app/viewer.bend as V
import ../core/look.bend as LO
import ../core/hier.bend as HI
import ../core/board.bend as B
import ../core/schematic.bend as SC
import ../core/mech.bend as MC

# The phones' board viewer, as the Bend client decides it. The viewer
# shows the selected thread's project board, schematic or 3D model
# ("@view:<thread>": "board", "schematic", "3d", "" closed; each thread
# keeps its own). The hub is asked for exactly the source on
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

# each thread's viewer is its own: "@view:<thread>"
def View.slot(+u: U.Ui) -> String:
  "@view:" ++ U.Ui.sel(u)

def View.kind(+u: U.Ui) -> String:
  U.Ui.scratch(u, View.slot(u))

# The schematic's sheet ("@view.sheet:<thread>", "" for the root) and the
# 3D model's parts ("@view.bare" set: the board alone, the hub's kind 3)
# are part of the source: the key a plot carries, the hub's Src.key
def View.sheet(+u: U.Ui) -> String:
  U.Ui.scratch(u, "@view.sheet:" ++ U.Ui.sel(u))

def View.bare(+u: U.Ui) -> Bool:
  Bool.not(String.is_empty(U.Ui.scratch(u, "@view.bare")))

def View.key.at(+kind: String, +root: String, +path: String, bare: Bool) -> String:
  Bool.pick(String, String.eq(kind, "schematic"), View.key(kind, root) ++ path,
    Bool.pick(String, Bool.and(bare, Bool.not(String.is_empty(View.key(kind, root)))), "3|" ++ root ++ "|", View.key(kind, root)))

def View.layers.at(+kind: String, +root: String, +path: String) -> String:
  Bool.pick(String, String.eq(kind, "schematic"), View.key.at(kind, root, path, False{}), View.layers(kind, root))

# a mechanical part the 3D view shows ("@view.part:<thread>", its absolute
# path; "" for the project's board): the Mechanical page's Open in 3D
def View.part(+u: U.Ui) -> String:
  U.Ui.scratch(u, "@view.part:" ++ U.Ui.sel(u))

def View.on_part(+u: U.Ui) -> Bool:
  Bool.and(String.eq(View.kind(u), "3d"), Bool.not(String.is_empty(View.part(u))))

# the source the screen shows now
def View.want(+u: U.Ui) -> String:
  Bool.pick(String, Bool.and(View.on_part(u), Bool.not(String.is_empty(U.Ui.root(u)))), "2|" ++ U.Ui.root(u) ++ "|" ++ View.part(u),
    View.key.at(View.kind(u), U.Ui.root(u), View.sheet(u), Bool.and(String.eq(View.kind(u), "3d"), View.bare(u))))

# the file a source names: a schematic's sheet, or a 3D view's part
def View.path(+u: U.Ui) -> String:
  Bool.pick(String, String.eq(View.kind(u), "3d"), View.part(u), View.sheet(u))

def View.ask(+want: String, +kind: String, +root: String, +path: String) -> List<&2, J.KV>:
  [J.KV{"kind", J.Str{Bool.pick(String, String.is_empty(want), "", Bool.pick(String, String.starts_with(want, "3|"), "3d-bare", kind))}}, J.KV{"root", J.Str{root}},
   J.KV{"path", J.Str{Bool.pick(String, Bool.or(String.eq(kind, "schematic"), String.eq(kind, "3d")), path, "")}}]

def View.join(a: U.Act, cmds: List<&2, U.Cmd>) -> U.Act:
  match a:
    case U.Act{u, cs}:
      U.Act{u, List.append(&2, U.Cmd, cmds, cs)}

def View.sync.k(same: Bool, u: U.Ui, +want: String, +kind: String, +root: String, +path: String, cmds: List<&2, U.Cmd>) -> U.Act:
  match same:
    case True{}:
      U.Act{u, cmds}
    case False{}:
      View.join(U.Ui.rpc(U.Ui.scratch_set(u, "@view.at", want), "kicad.watch", View.ask(want, kind, root, path)), cmds)

def View.sync.u(+u: U.Ui, cmds: List<&2, U.Cmd>) -> U.Act:
  View.sync.k(String.eq(View.want(u), U.Ui.scratch(u, "@view.at")), u, View.want(u), View.kind(u), U.Ui.root(u), View.path(u), cmds)

# an action's result with the hub asked for the source now on screen,
# when that changed (law view_asks_once)
# (and the Mechanical page's parts, when that is the phone's view: its
# own slot, kept across launches, which the client's view kind is not)
def View.sync(a: U.Act) -> U.Act:
  match a:
    case U.Act{+u, cmds}:
      U.Mpage.sync.if(String.eq(View.kind(u), "mech"), View.sync.u(u, cmds))

# open a viewer ("board", "schematic", "3d") or close it (""); what was
# picked is let go
def View.open.k(+u: U.Ui, v: String) -> U.Act:
  View.sync(U.Act{U.Ui.scratch_set(U.Ui.scratch_set(U.Ui.scratch_set(U.Ui.scratch_set(u, View.slot(u), v), "@pick", ""), "@card", ""), "@pick.rid", ""), Nil{}})

# (the Mechanical page, "mech", is the client's: its view is set there,
# and the parts asked for; a view picked by hand shows the project's own
# board, not a part)
def View.open.mech(mech: Bool, a: U.Act) -> U.Act:
  match mech a:
    case True{} U.Act{u, cs}:
      View.join(U.Ui.act(u, "mech", ""), cs)
    case False{} _:
      a

def View.open(+u: U.Ui, +v: String) -> U.Act:
  View.open.mech(String.eq(v, "mech"), View.open.k(U.Ui.scratch_set(u, "@view.part:" ++ U.Ui.sel(u), ""), v))

# a part opened in 3D from the Mechanical page (its absolute path)
def View.part.open(+u: U.Ui, +path: String) -> U.Act:
  View.open.k(U.Ui.scratch_set(u, "@view.part:" ++ U.Ui.sel(u), path), "3d")

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

def View.bg(+kind: String, light: Bool) -> U32:
  Bool.pick(U32, light, LO.Look.ground(True{}), 855826)

# the viewer's own light ground ("vw-light" flips it, as the window's sun
# and moon button does): the phone paints each layer in its colour here
# (look.bend's light table, by layer index) over View.bg
def View.light(+u: U.Ui) -> Bool:
  Bool.not(String.is_empty(U.Ui.scratch(u, "@vw.light")))

def View.look.go(n: Nat, +kind: U32, +i: U32) -> List<&2, J.Json>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      J.Num{U32.show(LO.Look.light.k(U32.is_eq(kind, 1), i))} <> View.look.go(k, kind, (i + 1 : U32))

def View.look(light: Bool, +kind: String) -> List<&2, J.Json>:
  match light:
    case True{}:
      View.look.go(LO.Look.count(Bool.pick(U32, String.eq(kind, "schematic"), 1, 0)), Bool.pick(U32, String.eq(kind, "schematic"), 1, 0), 0)
    case False{}:
      Nil{}

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

# what was picked let go
def Pick.clear(u: U.Ui) -> U.Ui:
  U.Ui.scratch_set(U.Ui.scratch_set(U.Ui.scratch_set(u, "@pick", ""), "@card", ""), "@pick.rid", "")

# Layers
# ------
# The layers of the board or the schematic the user turned off, a bit per
# layer ("@view.off.<kind>"): the phone does not draw them and a tap does
# not pick them. Only layers the hub sends (those shown by default) are
# listed.

def View.off.key(+u: U.Ui) -> String:
  "@view.off." ++ View.kind(u)

def View.off(+u: U.Ui) -> U32:
  Maybe.default(&2, U32, U32.read(U.Ui.scratch(u, View.off.key(u))), 0)

def View.layer(+u: U.Ui, +v: String) -> U.Act:
  U.Act{Pick.clear(U.Ui.scratch_set(u, View.off.key(u), U32.show(V.Look.toggle(View.off(u), Maybe.default(&2, U32, U32.read(v), 31))))), Nil{}}

def View.names(+kind: String) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.eq(kind, "schematic"), SC.Sch.layer_names(), B.Layer.names())

def View.layer.row(shown: Bool, +i: U32, +name: String, +off: U32, rest: List<&2, J.Json>) -> List<&2, J.Json>:
  match shown:
    case True{}:
      J.Json.obj([J.KV{"layer", J.Num{U32.show(i)}}, J.KV{"name", J.Str{name}}, J.KV{"on", J.Flag{Bool.not(V.Look.flipped(off, i))}}]) <> rest
    case False{}:
      rest

def View.layer.rows(ns: List<&2, String>, +k: U32, +i: U32, +off: U32) -> List<&2, J.Json>:
  match ns:
    case Nil{}:
      Nil{}
    case +n <> t:
      View.layer.row(U32.is_gt(V.Look.alpha(k, i, 0), 0), i, n, off, View.layer.rows(t, k, (i + 1 : U32), off))

# the list the phone's Layers menu shows (none for 3D)
def View.layer.list(+u: U.Ui) -> List<&2, J.Json>:
  Bool.pick(List<&2, J.Json>, Bool.or(String.eq(View.kind(u), "board"), String.eq(View.kind(u), "schematic")),
    View.layer.rows(View.names(View.kind(u)), Bool.pick(U32, String.eq(View.kind(u), "schematic"), 1, 0), 0, View.off(u)), Nil{})

# Sheets
# ------
# The hub sends a schematic's sheets when a phone watches it ({"t":
# "sheets", root, rows as Hier.show writes them}); "view-sheet" picks one
# by its row, the root being row 0.

def View.sheets.k(hit: Bool, +u: U.Ui, +o: J.Json) -> U.Ui:
  match hit:
    case True{}:
      U.Ui.scratch_set(U.Ui.scratch_set(u, "@view.tree", J.Json.get_str(o, "rows", "")), "@view.tree.root", J.Json.get_str(o, "root", ""))
    case False{}:
      u

# a 3D model's note ({"t":"plotnote", key, text}: parts with no model),
# kept with the source it is about
def View.note.k(hit: Bool, +u: U.Ui, +o: J.Json) -> U.Ui:
  match hit:
    case True{}:
      U.Ui.scratch_set(U.Ui.scratch_set(u, "@view.note", J.Json.get_str(o, "text", "")), "@view.note.key", J.Json.get_str(o, "key", ""))
    case False{}:
      u

def View.sheets(+u: U.Ui, +o: J.Json) -> U.Ui:
  View.note.k(String.eq(J.Json.get_str(o, "t", ""), "plotnote"), View.sheets.k(String.eq(J.Json.get_str(o, "t", ""), "sheets"), u, o), o)

def View.note(+u: U.Ui) -> String:
  Bool.pick(String, String.eq(U.Ui.scratch(u, "@view.note.key"), View.want(u)), U.Ui.scratch(u, "@view.note"), "")

def View.rows(+u: U.Ui) -> List<&2, HI.Row>:
  Bool.pick(List<&2, HI.Row>, String.eq(U.Ui.scratch(u, "@view.tree.root"), U.Ui.root(u)), HI.Hier.read(U.Ui.scratch(u, "@view.tree")), Nil{})

def View.sheet.go(+u: U.Ui, +i: Nat, +file: String) -> U.Act:
  View.sync(U.Act{Pick.clear(U.Ui.scratch_set(u, "@view.sheet:" ++ U.Ui.sel(u), Bool.pick(String, Nat.is_eq(i, 0n), "", file))), Nil{}})

def View.sheet.pick(+u: U.Ui, +v: String) -> U.Act:
  View.sheet.go(u, Maybe.default(&2, Nat, Nat.read(v), 0n), HI.Hier.file(View.rows(u), Maybe.default(&2, Nat, Nat.read(v), 0n)))

def View.sheet.row(r: HI.Row, +i: Nat, +cur: String) -> J.Json:
  match r:
    case HI.Row{+d, n, +f, l}:
      J.Json.obj([J.KV{"label", J.Str{String.repeat("  ", d) ++ n}}, J.KV{"value", J.Str{Nat.show(i)}}, J.KV{"on", J.Flag{String.eq(f, cur)}}, J.KV{"loop", J.Flag{l}}])

def View.sheet.rows(rs: List<&2, HI.Row>, +i: Nat, +cur: String) -> List<&2, J.Json>:
  match rs:
    case Nil{}:
      Nil{}
    case r <> t:
      View.sheet.row(r, i, cur) <> View.sheet.rows(t, 1n+i, cur)

# the schematic's sheets for the phone's Sheet menu (none with one sheet)
def View.sheet.list(+u: U.Ui) -> List<&2, J.Json>:
  Bool.pick(List<&2, J.Json>, Bool.and(String.eq(View.kind(u), "schematic"), Nat.is_gt(List.length(&2, HI.Row, View.rows(u)), 1n)),
    View.sheet.rows(View.rows(u), 0n, Bool.pick(String, String.is_empty(View.sheet(u)), HI.Hier.file(View.rows(u), 0n), View.sheet(u))), Nil{})

# the 3D model with its parts or the board alone ("view-parts")
def View.parts(+u: U.Ui) -> U.Act:
  View.sync(U.Act{U.Ui.scratch_set(u, "@view.bare", Bool.pick(String, View.bare(u), "", "1")), Nil{}})

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

# a layer the user turned off is not there to tap
def Pick.shown.k(off: Bool, c: Cand, rest: List<&2, Cand>) -> List<&2, Cand>:
  match off:
    case True{}:
      rest
    case False{}:
      c <> rest

def Pick.shown(cs: List<&2, Cand>, +off: U32) -> List<&2, Cand>:
  match cs:
    case Nil{}:
      Nil{}
    case Cand{+id, +a, +l} <> t:
      Pick.shown.k(V.Look.flipped(off, l), Cand{id, a, l}, Pick.shown(t, off))

def Pick.of(+text: String, +off: U32) -> Maybe<&2, Cand>:
  Pick.best(Pick.shown(Pick.cands(J.Json.elems(Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{}))), off), None{})

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
        [J.KV{"key", J.Str{View.layers.at(View.kind(u), U.Ui.root(u), View.sheet(u))}},
         J.KV{"at", J.Num{Maybe.default(&2, String, List.head(&2, String, String.split(id, ',')), "0")}},
         J.KV{"idx", J.Num{Maybe.default(&2, String, List.head(&2, String, List.drop(&2, String, String.split(id, ','), 1n)), "0")}}]))

# a tap in the viewer, given what lies under the finger: the piece it
# picks is highlighted and its info asked of the hub; a tap on nothing
# clears the card (law pick_nothing_there)
def View.pick(+u: U.Ui, +text: String) -> U.Act:
  Pick.ask(Pick.of(text, View.off(u)), u)

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

# The Mechanical page, as the phones draw it: what to say while there are
# no parts, the parts as chips (action "mech-part"), the part on show
# (Open in 3D: "mech-3d" with its path) and its renders (hub URLs), and
# where to get FreeCAD when the hub has none (client.bend's Mpage)
def Mech.chips(ps: List<&2, MC.MPart>, +cur: String) -> List<&2, J.Json>:
  match ps:
    case Nil{}:
      Nil{}
    case MC.MPart{+p, n, _} <> t:
      J.Json.obj([J.KV{"label", J.Str{n}}, J.KV{"value", J.Str{p}}, J.KV{"on", J.Flag{String.eq(p, cur)}}]) <> Mech.chips(t, cur)

def Mech.shots(fs: List<&2, MC.MFile>, +root: String) -> List<&2, J.Json>:
  match fs:
    case Nil{}:
      Nil{}
    case +f <> t:
      J.Json.obj([J.KV{"view", J.Str{MC.Mech.view.of(f)}}, J.KV{"url", J.Str{MC.Mech.url(root, f)}}]) <> Mech.shots(t, root)

def Mech.part(m: Maybe<&2, MC.MPart>, +root: String) -> List<&2, J.KV>:
  match m:
    case Some{MC.MPart{+p, +n, +fs}}:
      [J.KV{"name", J.Str{n}}, J.KV{"path", J.Str{MC.Mech.abs(root, p)}}, J.KV{"shots", J.Json.arr(Mech.shots(fs, root))},
       J.KV{"empty", J.Str{Bool.pick(String, List.is_empty(&2, MC.MFile, fs), MC.Mech.unrendered(n), "")}}]
    case None{}:
      [J.KV{"name", J.Str{""}}, J.KV{"path", J.Str{""}}, J.KV{"shots", J.Json.arr(Nil{})}, J.KV{"empty", J.Str{""}}]

def Mech.say(+state: Nat) -> String:
  Bool.pick(String, Nat.is_eq(state, 0n), "Loading the parts…", Bool.pick(String, Nat.is_eq(state, 1n), MC.Mech.none(), ""))

def Mech.json(on: Bool, +u: U.Ui) -> J.Json:
  match on:
    case True{}:
      J.Json.obj(List.append(&2, J.KV, [J.KV{"say", J.Str{Mech.say(U.Mpage.state(u))}}, J.KV{"note", J.Str{U.Mpage.note(u)}},
        J.KV{"parts", J.Json.arr(Mech.chips(U.Mpage.parts(u), U.Mpage.cur.path(u)))}], Mech.part(U.Mpage.cur(u), U.Mpage.root(u))))
    case False{}:
      J.Null{}

# what the phone's viewer needs: the source open ("" closed), its key and
# the key of the plot it draws layers from, the choices, and how to draw:
# background, the fade of new chunks (ms, as the window's), the first
# view's margin, the zoom range as a share of that view and in pixels per
# micrometre, how far from a tap (points) an item still counts as tapped,
# and for 3D the faces' layers, the board's colour before its model
# arrives, and the field of view (degrees)
def View.json(+u: U.Ui) -> J.Json:
  J.Json.obj([J.KV{"open", J.Str{Bool.pick(String, Bool.or(Bool.not(String.is_empty(View.want(u))), String.eq(View.kind(u), "mech")), View.kind(u), "")}}, J.KV{"key", J.Str{View.want(u)}},
    J.KV{"layers", J.Str{Bool.pick(String, View.on_part(u), "", View.layers.at(View.kind(u), U.Ui.root(u), View.sheet(u)))}},
    J.KV{"mech", Mech.json(String.eq(View.kind(u), "mech"), u)},
    J.KV{"sheets", J.Json.arr(View.sheet.list(u))}, J.KV{"layerList", J.Json.arr(View.layer.list(u))}, J.KV{"off", J.Num{U32.show(View.off(u))}},
    J.KV{"parts", J.Flag{Bool.not(View.bare(u))}}, J.KV{"note", J.Str{View.note(u)}},
    J.KV{"choices", J.Json.arr(Bool.pick(List<&2, J.Json>, String.is_empty(U.Ui.root(u)), Nil{},
      [View.choice("Board", "board", View.kind(u)), View.choice("Schematic", "schematic", View.kind(u)), View.choice("3D", "3d", View.kind(u)), View.choice("Mech", "mech", View.kind(u))]))},
    J.KV{"bg", J.Num{U32.show(View.bg(View.kind(u), View.light(u)))}}, J.KV{"light", J.Json.bool(View.light(u))}, J.KV{"look", J.Json.arr(View.look(View.light(u), View.kind(u)))}, J.KV{"fade", J.Num{Nat.show(V.Fade.ms())}}, J.KV{"margin", J.Num{"0.9"}},
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
