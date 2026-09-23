import Base
import ./utf8.bend as U

# KiCad S-expressions over bytes. A board is split into its top-level forms
# by one flat pass (which also tells a finished file from one still being
# written); each form then parses on its own, so forms parse in parallel.

# A tree in one self-recursive type (lists are XCons chains ending in XEnd).
type Sx is Data:
  XAtom{text: String}
  XStr{text: String}
  XList{items: Sx}
  XCons{head: Sx, tail: Sx}
  XEnd{}

# Splitting into top-level forms
# ------------------------------

# depth, inside a string, after a backslash, the form being read (reversed
# bytes), and the finished forms (newest first)
type Cut is Data:
  Cut{depth: U32, str: Bool, esc: Bool, cur: List<&2, U32>, forms: List<&2, List<&2, U32>>}

def Cut.push(deep: Bool, +b: U32, cur: List<&2, U32>) -> List<&2, U32>:
  match deep:
    case True{}:
      b <> cur
    case False{}:
      cur

# "(" at depth d: depth 1 -> 2 starts a form
def Cut.open(one: Bool, +d: U32, cur: List<&2, U32>, forms: List<&2, List<&2, U32>>) -> Cut:
  match one:
    case True{}:
      Cut{2, False{}, False{}, [40], forms}
    case False{}:
      Cut{(d + 1 : U32), False{}, False{}, Cut.push(U32.is_ge(d, 2), 40, cur), forms}

# ")" at depth d: depth 2 -> 1 ends a form
def Cut.close(two: Bool, +d: U32, cur: List<&2, U32>, forms: List<&2, List<&2, U32>>) -> Cut:
  match two:
    case True{}:
      Cut{1, False{}, False{}, Nil{}, List.reverse(&2, U32, 41 <> cur) <> forms}
    case False{}:
      Cut{(d - 1 : U32), False{}, False{}, Cut.push(U32.is_ge(d, 3), 41, cur), forms}

def Cut.k(s: Bool, e: Bool, q: Bool, bs: Bool, o: Bool, c: Bool, +d: U32, +b: U32, cur: List<&2, U32>, forms: List<&2, List<&2, U32>>) -> Cut:
  match s e q bs o c:
    case True{} True{} _ _ _ _:
      Cut{d, True{}, False{}, b <> cur, forms}
    case True{} False{} _ True{} _ _:
      Cut{d, True{}, True{}, b <> cur, forms}
    case True{} False{} True{} False{} _ _:
      Cut{d, False{}, False{}, b <> cur, forms}
    case True{} False{} False{} False{} _ _:
      Cut{d, True{}, False{}, b <> cur, forms}
    case False{} _ True{} _ _ _:
      Cut{d, True{}, False{}, Cut.push(U32.is_ge(d, 2), b, cur), forms}
    case False{} _ False{} _ True{} _:
      Cut.open(U32.is_eq(d, 1), d, cur, forms)
    case False{} _ False{} _ False{} True{}:
      Cut.close(U32.is_eq(d, 2), d, cur, forms)
    case False{} _ False{} _ False{} False{}:
      Cut{d, False{}, False{}, Cut.push(U32.is_ge(d, 2), b, cur), forms}

def Cut.step(st: Cut, +b: U32) -> Cut:
  match st:
    case Cut{+d, s, e, cur, forms}:
      Cut.k(s, e, U32.is_eq(b, 34), U32.is_eq(b, 92), U32.is_eq(b, 40), U32.is_eq(b, 41), d, b, cur, forms)

def Cut.go(bs: List<&2, U32>, st: Cut) -> Cut:
  match bs:
    case Nil{}:
      st
    case b <> t:
      Cut.go(t, Cut.step(st, b))

def Cut.done.k(closed: Bool, s: Bool, forms: List<&2, List<&2, U32>>) -> Maybe<&2, List<&2, List<&2, U32>>>:
  match closed s:
    case True{} False{}:
      Some{List.reverse(&2, List<&2, U32>, forms)}
    case _ _:
      None{}

def Cut.done(st: Cut) -> Maybe<&2, List<&2, List<&2, U32>>>:
  match st:
    case Cut{+d, s, _, _, forms}:
      Cut.done.k(U32.is_eq(d, 0), s, forms)

# the top-level forms of a whole file, or None when the file is incomplete
# (unbalanced, or cut inside a string): a half-written save is never shown
def Sx.forms(bs: List<&2, U32>) -> Maybe<&2, List<&2, List<&2, U32>>>:
  Cut.done(Cut.go(bs, Cut{0, False{}, False{}, Nil{}, Nil{}}))

# Tokens
# ------

type Tk is Data:
  KOpen{}
  KClose{}
  KAtom{text: String}
  KStr{text: String}

type Lx is Data:
  LNone{}
  LAtom{acc: List<&2, U32>}
  LStr{acc: List<&2, U32>, esc: Bool}

def Lx.text(acc: List<&2, U32>) -> String:
  U.Utf8.decode(List.reverse(&2, U32, acc))

def Lx.flush(l: Lx, out: List<&2, Tk>) -> List<&2, Tk>:
  match l:
    case LAtom{acc}:
      KAtom{Lx.text(acc)} <> out
    case _:
      out

def Lx.esc(+b: U32) -> U32:
  Bool.pick(U32, U32.is_eq(b, 110), 10, b)

def Lx.grow(l: Lx, +b: U32) -> Lx:
  match l:
    case LAtom{acc}:
      LAtom{b <> acc}
    case _:
      LAtom{[b]}

# outside a string: space ends an atom, parens are tokens, " opens a string
def Lx.out.k(sp: Bool, o: Bool, c: Bool, q: Bool, l: Lx, +b: U32, out: List<&2, Tk>) -> Lx & List<&2, Tk>:
  match sp o c q:
    case True{} _ _ _:
      (LNone{}, Lx.flush(l, out))
    case False{} True{} _ _:
      (LNone{}, KOpen{} <> Lx.flush(l, out))
    case False{} False{} True{} _:
      (LNone{}, KClose{} <> Lx.flush(l, out))
    case False{} False{} False{} True{}:
      (LStr{Nil{}, False{}}, Lx.flush(l, out))
    case False{} False{} False{} False{}:
      (Lx.grow(l, b), out)

def Lx.str.k(esc: Bool, q: Bool, bs: Bool, acc: List<&2, U32>, +b: U32, out: List<&2, Tk>) -> Lx & List<&2, Tk>:
  match esc q bs:
    case True{} _ _:
      (LStr{Lx.esc(b) <> acc, False{}}, out)
    case False{} True{} _:
      (LNone{}, KStr{Lx.text(acc)} <> out)
    case False{} False{} True{}:
      (LStr{acc, True{}}, out)
    case False{} False{} False{}:
      (LStr{b <> acc, False{}}, out)

def Lx.step(l: Lx, +b: U32, out: List<&2, Tk>) -> Lx & List<&2, Tk>:
  match l:
    case LStr{acc, esc}:
      Lx.str.k(esc, U32.is_eq(b, 34), U32.is_eq(b, 92), acc, b, out)
    case _:
      Lx.out.k(U32.is_le(b, 32), U32.is_eq(b, 40), U32.is_eq(b, 41), U32.is_eq(b, 34), l, b, out)

def Lx.step.pair(+b: U32, r: Lx & List<&2, Tk>) -> Lx & List<&2, Tk>:
  (l, out) = r
  Lx.step(l, b, out)

def Lx.fin(r: Lx & List<&2, Tk>) -> List<&2, Tk>:
  (l, out) = r
  List.reverse(&2, Tk, Lx.flush(l, out))

def Lx.go(bs: List<&2, U32>, r: Lx & List<&2, Tk>) -> List<&2, Tk>:
  match bs:
    case Nil{}:
      Lx.fin(r)
    case b <> t:
      Lx.go(t, Lx.step.pair(b, r))

def Sx.tokens(bs: List<&2, U32>) -> List<&2, Tk>:
  Lx.go(bs, (LNone{}, Nil{}))

# Trees
# -----

def Sx.chain(xs: List<&2, Sx>, end: Sx) -> Sx:
  match xs:
    case Nil{}:
      end
    case x <> t:
      Sx.chain(t, XCons{x, end})

# the open lists (innermost first), each holding its children reversed
def Tree.add(st: List<&2, List<&2, Sx>>, x: Sx) -> List<&2, List<&2, Sx>>:
  match st:
    case top <> rest:
      (x <> top) <> rest
    case Nil{}:
      [[x]]

def Tree.close(st: List<&2, List<&2, Sx>>) -> List<&2, List<&2, Sx>>:
  match st:
    case top <> rest:
      Tree.add(rest, XList{Sx.chain(top, XEnd{})})
    case Nil{}:
      Nil{}

def Tree.step(st: List<&2, List<&2, Sx>>, t: Tk) -> List<&2, List<&2, Sx>>:
  match t:
    case KOpen{}:
      Nil{} <> st
    case KClose{}:
      Tree.close(st)
    case KAtom{s}:
      Tree.add(st, XAtom{s})
    case KStr{s}:
      Tree.add(st, XStr{s})

def Tree.go(ts: List<&2, Tk>, st: List<&2, List<&2, Sx>>) -> List<&2, List<&2, Sx>>:
  match ts:
    case Nil{}:
      st
    case t <> rest:
      Tree.go(rest, Tree.step(st, t))

def Tree.fin(st: List<&2, List<&2, Sx>>) -> Sx:
  match st:
    case [x] <> Nil{}:
      x
    case _:
      XEnd{}

# one form's bytes as a tree (XEnd when malformed)
def Sx.parse(bs: List<&2, U32>) -> Sx:
  Tree.fin(Tree.go(Sx.tokens(bs), [Nil{}]))

# Reading
# -------

def Sx.list(c: Sx) -> List<&2, Sx>:
  match c:
    case XCons{h, t}:
      h <> Sx.list(t)
    case _:
      Nil{}

# a list's head atom ("segment", "at", ...), or ""
def Sx.name(x: Sx) -> String:
  match x:
    case XList{XCons{XAtom{s}, _}}:
      s
    case _:
      ""

# a list's children after its name
def Sx.args(x: Sx) -> List<&2, Sx>:
  match x:
    case XList{XCons{_, t}}:
      Sx.list(t)
    case _:
      Nil{}

def Sx.text(x: Sx) -> String:
  match x:
    case XAtom{s}:
      s
    case XStr{s}:
      s
    case _:
      ""

def Sx.hit(xs: List<&2, Sx>, +name: String) -> Bool:
  match xs:
    case x <> _:
      String.eq(Sx.name(x), name)
    case Nil{}:
      False{}

def Sx.find.go(xs: List<&2, Sx>, hit: Bool, +name: String) -> Sx:
  match xs hit:
    case x <> _ True{}:
      x
    case _ <> +t False{}:
      Sx.find.go(t, Sx.hit(t, name), name)
    case _ _:
      XEnd{}

# the first child list called name (XEnd when there is none)
def Sx.find(+xs: List<&2, Sx>, +name: String) -> Sx:
  Sx.find.go(xs, Sx.hit(xs, name), name)

def Sx.get(x: Sx, +name: String) -> Sx:
  Sx.find(Sx.args(x), name)

def Sx.all.k(same: Bool, x: Sx, rest: List<&2, Sx>) -> List<&2, Sx>:
  match same:
    case True{}:
      x <> rest
    case False{}:
      rest

# every child list called name
def Sx.all(xs: List<&2, Sx>, +name: String) -> List<&2, Sx>:
  match xs:
    case Nil{}:
      Nil{}
    case +x <> t:
      Sx.all.k(String.eq(Sx.name(x), name), x, Sx.all(t, name))

# the i-th argument's text ("" when absent)
def Sx.arg(x: Sx, i: Nat) -> String:
  Sx.text(Maybe.default(&2, Sx, List.get(&2, Sx, Sx.args(x), i), XEnd{}))

def Sx.num(+s: String) -> F32:
  Maybe.default(&2, F32, F32.read(s), 0.0)

# the i-th argument as a number (0 when absent)
def Sx.f(+x: Sx, i: Nat) -> F32:
  Sx.num(Sx.arg(x, i))

# the text of (name "value") under x, e.g. (uuid "...") or (layer "F.Cu")
def Sx.attr(x: Sx, +name: String) -> String:
  Sx.arg(Sx.get(x, name), 0n)
