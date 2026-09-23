import Base
import ./sexpr.bend as S

# A .kicad_pcb as drawable items. Each Item carries a stable key (KiCad's
# uuid, or the footprint's uuid and the child's) and the exact JSON the
# viewer draws, so "did this change?" is "did what we draw change?".
#
# Item JSON: {"k": key, "l": layer, "t": kind, "d": [numbers], "w": width, "f": filled}
#   kind "s" segment [x1 y1 x2 y2], "l" polyline [x y ...], "c" circle [x y r],
#   "p" polygon [x y ...]

type Item is Data:
  Item{key: String, json: String}

# Geometry
# --------

type Pt is Data:
  Pt{x: F32, y: F32}

# a footprint's placement: origin and rotation (radians)
type Place is Data:
  Place{x: F32, y: F32, a: F32}

def Geo.rad(+deg: F32) -> F32:
  F32.mul(deg, F32.div(F32.pi(), 180.0))

def Geo.rot(p: Pt, +a: F32) -> Pt:
  match p:
    case Pt{+x, +y}:
      Pt{F32.add(F32.mul(x, F32.cos(a)), F32.mul(y, F32.sin(a))), F32.sub(F32.mul(y, F32.cos(a)), F32.mul(x, F32.sin(a)))}

def Geo.place.k(p: Pt, +px: F32, +py: F32) -> Pt:
  match p:
    case Pt{x, y}:
      Pt{F32.add(x, px), F32.add(y, py)}

# a footprint-local point in board coordinates
def Geo.place(+pl: Place, p: Pt) -> Pt:
  match pl:
    case Place{+px, +py, +a}:
      Geo.place.k(Geo.rot(p, a), px, py)

def Geo.pt(+x: S.Sx) -> Pt:
  Pt{S.Sx.f(x, 0n), S.Sx.f(x, 1n)}

def Geo.at(+x: S.Sx, +name: String) -> Pt:
  Geo.pt(S.Sx.get(x, name))

# Numbers and JSON
# ----------------

def Js.num(+f: F32) -> String:
  F32.show(f)

def Js.pt(p: Pt, rest: String) -> String:
  match p:
    case Pt{x, y}:
      Js.num(x) ++ "," ++ Js.num(y) ++ rest

def Js.pts(ps: List<&2, Pt>) -> String:
  match ps:
    case Nil{}:
      ""
    case p <> Nil{}:
      Js.pt(p, "")
    case p <> t:
      Js.pt(p, "," ++ Js.pts(t))

def Js.esc.k(q: Bool, b: Bool, c: Char, rest: String) -> String:
  match q b:
    case True{} _:
      SCon{'\\', SCon{'"', rest}}
    case _ True{}:
      SCon{'\\', SCon{'\\', rest}}
    case _ _:
      SCon{c, rest}

def Js.esc(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{+c, t}:
      Js.esc.k(Char.is_eq(c, '"'), Char.is_eq(c, '\\'), c, Js.esc(t))

def Js.str(s: String) -> String:
  "\"" ++ Js.esc(s) ++ "\""

def Js.item(+key: String, layer: String, kind: String, d: String, +w: F32, fill: Bool) -> Item:
  Item{key, "{\"k\":" ++ Js.str(key) ++ ",\"l\":" ++ Js.str(layer) ++ ",\"t\":\"" ++ kind ++ "\",\"d\":[" ++ d
    ++ "],\"w\":" ++ Js.num(w) ++ ",\"f\":" ++ Bool.pick(String, fill, "1", "0") ++ "}"}

# Arcs
# ----

def Arc.norm(+x: F32) -> F32:
  +tau = F32.mul(2.0, F32.pi())
  F32.sub(x, F32.mul(tau, F32.floor(F32.div(x, tau))))

def Arc.sq(+x: F32) -> F32:
  F32.mul(x, x)

def Arc.at(+i: Nat, +ux: F32, +uy: F32, +r: F32, +a0: F32, +sw: F32) -> Pt:
  +a = F32.add(a0, F32.mul(sw, F32.div(F32.from_nat(i), 24.0)))
  Pt{F32.add(ux, F32.mul(r, F32.cos(a))), F32.add(uy, F32.mul(r, F32.sin(a)))}

def Arc.steps(n: Nat, +i: Nat, +ux: F32, +uy: F32, +r: F32, +a0: F32, +sw: F32) -> List<&2, Pt>:
  match n:
    case 0n:
      [Arc.at(i, ux, uy, r, a0, sw)]
    case 1n+m:
      Arc.at(i, ux, uy, r, a0, sw) <> Arc.steps(m, 1n+i, ux, uy, r, a0, sw)

def Arc.sweep(+ux: F32, +uy: F32, +ax: F32, +ay: F32, +bx: F32, +by: F32, +cx: F32, +cy: F32) -> List<&2, Pt>:
  +a0 = F32.atan2(F32.sub(ay, uy), F32.sub(ax, ux))
  +s1 = Arc.norm(F32.sub(F32.atan2(F32.sub(cy, uy), F32.sub(cx, ux)), a0))
  +sm = Arc.norm(F32.sub(F32.atan2(F32.sub(by, uy), F32.sub(bx, ux)), a0))
  Arc.steps(24n, 0n, ux, uy, F32.hypot(F32.sub(ax, ux), F32.sub(ay, uy)), a0,
    Bool.pick(F32, F32.is_lt(sm, s1), s1, F32.sub(s1, F32.mul(2.0, F32.pi()))))

def Arc.points.k(flat: Bool, +d: F32, +ax: F32, +ay: F32, +bx: F32, +by: F32, +cx: F32, +cy: F32) -> List<&2, Pt>:
  match flat:
    case True{}:
      [Pt{ax, ay}, Pt{cx, cy}]
    case False{}:
      Arc.sweep(
        F32.div(F32.add(F32.mul(F32.add(Arc.sq(ax), Arc.sq(ay)), F32.sub(by, cy)), F32.add(F32.mul(F32.add(Arc.sq(bx), Arc.sq(by)), F32.sub(cy, ay)), F32.mul(F32.add(Arc.sq(cx), Arc.sq(cy)), F32.sub(ay, by)))), d),
        F32.div(F32.add(F32.mul(F32.add(Arc.sq(ax), Arc.sq(ay)), F32.sub(cx, bx)), F32.add(F32.mul(F32.add(Arc.sq(bx), Arc.sq(by)), F32.sub(ax, cx)), F32.mul(F32.add(Arc.sq(cx), Arc.sq(cy)), F32.sub(bx, ax)))), d),
        ax, ay, bx, by, cx, cy)

def Arc.points.d(+d: F32, +ax: F32, +ay: F32, +bx: F32, +by: F32, +cx: F32, +cy: F32) -> List<&2, Pt>:
  Arc.points.k(F32.is_lt(F32.abs(d), 0.000001), d, ax, ay, bx, by, cx, cy)

# points along the circle through a, b, c from a to c (b decides the way)
def Arc.points(+a: Pt, +b: Pt, +c: Pt) -> List<&2, Pt>:
  match a b c:
    case Pt{+ax, +ay} Pt{+bx, +by} Pt{+cx, +cy}:
      Arc.points.d(F32.mul(2.0, F32.add(F32.mul(ax, F32.sub(by, cy)), F32.add(F32.mul(bx, F32.sub(cy, ay)), F32.mul(cx, F32.sub(ay, by))))), ax, ay, bx, by, cx, cy)

def Board.width.k(+w: F32, +sw: F32) -> F32:
  Bool.pick(F32, F32.is_gt(w, 0.0), w, sw)

# Board-level forms
# -----------------

def Board.width(+x: S.Sx) -> F32:
  Board.width.k(S.Sx.f(S.Sx.get(x, "width"), 0n), S.Sx.f(S.Sx.get(S.Sx.get(x, "stroke"), "width"), 0n))

def Board.filled(+x: S.Sx) -> Bool:
  +f = S.Sx.arg(S.Sx.get(x, "fill"), 0n)
  Bool.or(String.eq(f, "yes"), String.eq(f, "solid"))

def Board.key.k(+u: String, +t: String, +fallback: String) -> String:
  Bool.pick(String, Bool.not(String.is_empty(u)), u, Bool.pick(String, Bool.not(String.is_empty(t)), t, fallback))

def Board.key(+x: S.Sx, +fallback: String) -> String:
  Board.key.k(S.Sx.attr(x, "uuid"), S.Sx.attr(x, "tstamp"), fallback)

def Board.pts.k(xy: Bool, +x: S.Sx, +pl: Place, rest: List<&2, Pt>) -> List<&2, Pt>:
  match xy:
    case True{}:
      Geo.place(pl, Geo.pt(x)) <> rest
    case False{}:
      rest

def Board.pts(xs: List<&2, S.Sx>, +pl: Place) -> List<&2, Pt>:
  match xs:
    case Nil{}:
      Nil{}
    case +x <> t:
      Board.pts.k(String.eq(S.Sx.name(x), "xy"), x, pl, Board.pts(t, pl))

def Board.home() -> Place:
  Place{0.0, 0.0, 0.0}

def Board.circle(+key: String, +layer: String, c: Pt, e: Pt, +w: F32, fill: Bool) -> Item:
  match c e:
    case Pt{+cx, +cy} Pt{ex, ey}:
      Js.item(key, layer, "c", Js.pts([Pt{cx, cy}]) ++ "," ++ Js.num(F32.hypot(F32.sub(ex, cx), F32.sub(ey, cy))), w, fill)

def Board.rect(+key: String, +layer: String, a: Pt, b: Pt, +pl: Place, +w: F32, fill: Bool) -> Item:
  match a b:
    case Pt{+ax, +ay} Pt{+bx, +by}:
      Js.item(key, layer, "p", Js.pts([Geo.place(pl, Pt{ax, ay}), Geo.place(pl, Pt{bx, ay}), Geo.place(pl, Pt{bx, by}), Geo.place(pl, Pt{ax, by})]), w, fill)

# a graphic form (segment, gr_*, fp_*) placed by pl
def Board.graphic.k(i: Nat, +x: S.Sx, +key: String, +layer: String, +pl: Place) -> List<&2, Item>:
  match i:
    case 0n:
      [Js.item(key, layer, "s", Js.pts([Geo.place(pl, Geo.at(x, "start")), Geo.place(pl, Geo.at(x, "end"))]), Board.width(x), False{})]
    case 1n:
      [Js.item(key, layer, "l", Js.pts(Arc.points(Geo.place(pl, Geo.at(x, "start")), Geo.place(pl, Geo.at(x, "mid")), Geo.place(pl, Geo.at(x, "end")))), Board.width(x), False{})]
    case 2n:
      [Board.circle(key, layer, Geo.place(pl, Geo.at(x, "center")), Geo.place(pl, Geo.at(x, "end")), Board.width(x), Board.filled(x))]
    case 3n:
      [Board.rect(key, layer, Geo.at(x, "start"), Geo.at(x, "end"), pl, Board.width(x), Board.filled(x))]
    case 4n:
      [Js.item(key, layer, "p", Js.pts(Board.pts(S.Sx.args(S.Sx.get(x, "pts")), pl)), Board.width(x), Board.filled(x))]
    case _:
      Nil{}

def Board.kinds() -> List<&2, String>:
  ["line", "arc", "circle", "rect", "poly"]

def Board.pos.hit(ns: List<&2, String>, +s: String) -> Bool:
  match ns:
    case n <> _:
      String.eq(n, s)
    case Nil{}:
      False{}

def Board.pos.go(ns: List<&2, String>, hit: Bool, +s: String, +i: Nat) -> Nat:
  match ns hit:
    case _ <> _ True{}:
      i
    case _ <> +t False{}:
      Board.pos.go(t, Board.pos.hit(t, s), s, 1n+i)
    case Nil{} _:
      9n

def Board.index(+ns: List<&2, String>, +s: String) -> Nat:
  Board.pos.go(ns, Board.pos.hit(ns, s), s, 0n)

def Board.kind.k(gr: Bool, fp: Bool, seg: Bool, arc: Bool, +name: String) -> Nat:
  match gr fp seg arc:
    case True{} _ _ _:
      Board.index(Board.kinds(), String.drop(name, 3n))
    case _ True{} _ _:
      Board.index(Board.kinds(), String.drop(name, 3n))
    case _ _ True{} _:
      0n
    case _ _ _ True{}:
      1n
    case _ _ _ _:
      9n

# "gr_line" -> "line", "fp_arc" -> "arc", "segment" -> "line", "arc" -> "arc"
def Board.kind(+name: String) -> Nat:
  Board.kind.k(String.starts_with(name, "gr_"), String.starts_with(name, "fp_"), String.eq(name, "segment"), String.eq(name, "arc"), name)

def Board.graphic(+x: S.Sx, +key: String, +pl: Place) -> List<&2, Item>:
  Board.graphic.k(Board.kind(S.Sx.name(x)), x, key, S.Sx.attr(x, "layer"), pl)

# Vias and pads
# -------------

def Board.via(+x: S.Sx, +key: String) -> List<&2, Item>:
  +c = Geo.at(x, "at")
  [Js.item(key, "via", "c", Js.pts([c]) ++ "," ++ Js.num(F32.div(S.Sx.f(S.Sx.get(x, "size"), 0n), 2.0)), 0.0, True{}),
   Js.item(key ++ "/h", "hole", "c", Js.pts([c]) ++ "," ++ Js.num(F32.div(S.Sx.f(S.Sx.get(x, "drill"), 0n), 2.0)), 0.0, True{})]

def Pad.frame(c: Pt, +a: F32) -> Place:
  match c:
    case Pt{x, y}:
      Place{x, y, a}

# the pad's outline around its centre, rotated by its absolute angle
def Pad.corners(+c: Pt, +w: F32, +h: F32, +a: F32) -> List<&2, Pt>:
  +hw = F32.div(w, 2.0)
  +hh = F32.div(h, 2.0)
  [Geo.place(Pad.frame(c, a), Pt{F32.neg(hw), F32.neg(hh)}), Geo.place(Pad.frame(c, a), Pt{hw, F32.neg(hh)}),
   Geo.place(Pad.frame(c, a), Pt{hw, hh}), Geo.place(Pad.frame(c, a), Pt{F32.neg(hw), hh})]

def Pad.oval(+key: String, +layer: String, +c: Pt, +w: F32, +h: F32, +a: F32) -> Item:
  +horiz = F32.is_ge(w, h)
  +half = F32.div(F32.sub(Bool.pick(F32, horiz, w, h), Bool.pick(F32, horiz, h, w)), 2.0)
  Js.item(key, layer, "s", Js.pts([Geo.place(Pad.frame(c, a), Bool.pick(Pt, horiz, Pt{F32.neg(half), 0.0}, Pt{0.0, F32.neg(half)})),
    Geo.place(Pad.frame(c, a), Bool.pick(Pt, horiz, Pt{half, 0.0}, Pt{0.0, half}))]), Bool.pick(F32, horiz, h, w), True{})

def Pad.shape.k(circle: Bool, oval: Bool, +key: String, +layer: String, +c: Pt, +w: F32, +h: F32, +a: F32) -> Item:
  match circle oval:
    case True{} _:
      Js.item(key, layer, "c", Js.pts([c]) ++ "," ++ Js.num(F32.div(w, 2.0)), 0.0, True{})
    case False{} True{}:
      Pad.oval(key, layer, c, w, h, a)
    case False{} False{}:
      Js.item(key, layer, "p", Js.pts(Pad.corners(c, w, h, a)), 0.0, True{})

def Pad.hole.k(has: Bool, +key: String, +c: Pt, +d: F32) -> List<&2, Item>:
  match has:
    case True{}:
      [Js.item(key ++ "/h", "hole", "c", Js.pts([c]) ++ "," ++ Js.num(F32.div(d, 2.0)), 0.0, True{})]
    case False{}:
      Nil{}

# a pad on its first listed layer ("*.Cu" draws on both sides), plus its hole
def Board.pad(+x: S.Sx, +key: String, +pl: Place) -> List<&2, Item>:
  +at = S.Sx.get(x, "at")
  +c = Geo.place(pl, Geo.pt(at))
  +size = S.Sx.get(x, "size")
  +shape = S.Sx.arg(x, 1n)
  +drill = S.Sx.f(S.Sx.get(x, "drill"), 0n)
  Pad.shape.k(String.eq(shape, "circle"), String.eq(shape, "oval"), key, S.Sx.arg(S.Sx.get(x, "layers"), 0n), c,
    S.Sx.f(size, 0n), S.Sx.f(size, 1n), Geo.rad(F32.neg(S.Sx.f(at, 2n))))
  <> Pad.hole.k(F32.is_gt(drill, 0.0), key, c, drill)

# Footprints
# ----------

def Fp.child.k(pad: Bool, +x: S.Sx, +key: String, +pl: Place) -> List<&2, Item>:
  match pad:
    case True{}:
      Board.pad(x, key, pl)
    case False{}:
      Board.graphic(x, key, pl)

def Fp.children(xs: List<&2, S.Sx>, +fp: String, +pl: Place, +i: Nat) -> List<&2, Item>:
  match xs:
    case Nil{}:
      Nil{}
    case +x <> t:
      List.append(&2, Item,
        Fp.child.k(String.eq(S.Sx.name(x), "pad"), x, fp ++ "/" ++ Board.key(x, Nat.show(i)), pl),
        Fp.children(t, fp, pl, 1n+i))

def Board.footprint(+x: S.Sx, +key: String) -> List<&2, Item>:
  +at = S.Sx.get(x, "at")
  Fp.children(S.Sx.args(x), key, Place{S.Sx.f(at, 0n), S.Sx.f(at, 1n), Geo.rad(S.Sx.f(at, 2n))}, 0n)

def Zone.fill.k(hit: Bool, +x: S.Sx, +key: String, +i: Nat, rest: List<&2, Item>) -> List<&2, Item>:
  match hit:
    case True{}:
      Js.item(key ++ "/f" ++ Nat.show(i), S.Sx.attr(x, "layer"), "p", Js.pts(Board.pts(S.Sx.args(S.Sx.get(x, "pts")), Board.home())), 0.0, True{}) <> rest
    case False{}:
      rest

# Zones
# -----

def Zone.fills(xs: List<&2, S.Sx>, +key: String, +i: Nat) -> List<&2, Item>:
  match xs:
    case Nil{}:
      Nil{}
    case +x <> t:
      Zone.fill.k(String.eq(S.Sx.name(x), "filled_polygon"), x, key, i, Zone.fills(t, key, 1n+i))

# Forms
# -----

def Board.forms() -> List<&2, String>:
  ["segment", "arc", "via", "footprint", "zone", "gr_line", "gr_arc", "gr_circle", "gr_rect", "gr_poly"]

def Board.form.k(i: Nat, +x: S.Sx, +key: String) -> List<&2, Item>:
  match i:
    case 2n:
      Board.via(x, key)
    case 3n:
      Board.footprint(x, key)
    case 4n:
      Zone.fills(S.Sx.args(x), key, 0n)
    case 9n:
      Nil{}
    case _:
      Board.graphic(x, key, Board.home())

# the items one top-level form draws; unknown forms draw nothing
def Board.form(+x: S.Sx, +i: Nat) -> List<&2, Item>:
  Board.form.k(Board.index(Board.forms(), S.Sx.name(x)), x, Board.key(x, "n" ++ Nat.show(i)))

def Board.one(bs: List<&2, U32>, +i: Nat) -> List<&2, Item>:
  Board.form(S.Sx.parse(bs), i)

# Parallel conversion
# -------------------
# The runtime hands each half of a parallel call to a core once and never
# moves work afterwards, so halves must cost about the same. A board lists
# its heavy footprints before its light segments, so halves by position
# would not; dealing forms alternately gives each half a fair mix.

type Form is Data:
  Form{i: Nat, bytes: List<&2, U32>}

type Hand is Data:
  Hand{a: List<&2, Form>, b: List<&2, Form>}

def Board.number(fs: List<&2, List<&2, U32>>, +i: Nat) -> List<&2, Form>:
  match fs:
    case Nil{}:
      Nil{}
    case f <> t:
      Form{i, f} <> Board.number(t, 1n+i)

# alternate forms into two hands
def Board.deal(fs: List<&2, Form>, h: Hand) -> Hand:
  match fs h:
    case Nil{} _:
      h
    case f <> t Hand{a, b}:
      Board.deal(t, Hand{b, f <> a})

def Board.seq(fs: List<&2, Form>) -> List<&2, Item>:
  match fs:
    case Nil{}:
      Nil{}
    case Form{+i, bs} <> t:
      List.append(&2, Item, Board.one(bs, i), Board.seq(t))

# deal fs into two hands and hand them to k
def Board.split.k(h: Hand, k: List<&2, Form> -> List<&2, Form> -> List<&2, Item>) -> List<&2, Item>:
  match h:
    case Hand{a, b}:
      k(a, b)

def Board.split(fs: List<&2, Form>, k: List<&2, Form> -> List<&2, Form> -> List<&2, Item>) -> List<&2, Item>:
  Board.split.k(Board.deal(fs, Hand{Nil{}, Nil{}}), k)

# convert both hands at once, d levels deep
def Board.par(d: Nat, fs: List<&2, Form>) -> List<&2, Item>:
  match d:
    case 0n:
      Board.seq(fs)
    case 1n+e0:
      +e = e0
      Board.split(fs, a => b => (
        x y = Board.par(e, a) Board.par(e, b)
        List.append(&2, Item, x, y)))

def Board.items.k(m: Maybe<&2, List<&2, List<&2, U32>>>) -> Maybe<&2, List<&2, Item>>:
  match m:
    case Some{fs}:
      Some{Board.par(8n, Board.number(fs, 0n))}
    case None{}:
      None{}

# every item of a board file, or None while the file is half written
def Board.items(bs: List<&2, U32>) -> Maybe<&2, List<&2, Item>>:
  Board.items.k(S.Sx.forms(bs))
