import Base

# Where a menu's pieces go (the model picker): boxes in pixels, for any
# number of models and effort chips, so a new model can never make two
# pieces overlap (laws menu_*). The window draws with these; the web gets
# the same from CSS flow.

type Box is Data:
  Box{x: Nat, y: Nat, w: Nat, h: Nat}

def Box.right(b: Box) -> Nat:
  match b:
    case Box{x, _, w, _}:
      Nat.add(x, w)

def Box.bottom(b: Box) -> Nat:
  match b:
    case Box{_, y, _, h}:
      Nat.add(y, h)

def Box.top(b: Box) -> Nat:
  match b:
    case Box{_, y, _, _}:
      y

def Box.left(b: Box) -> Nat:
  match b:
    case Box{x, _, _, _}:
      x

# b lies wholly below a or wholly to its right: they cannot overlap
def Box.apart(+a: Box, +b: Box) -> Bool:
  Bool.or(Nat.is_ge(Box.top(b), Box.bottom(a)), Nat.is_ge(Box.left(b), Box.right(a)))

# each box apart from the one before it (laid out in reading order)
def Boxes.apart.k(bs: List<&2, Box>, +a: Box) -> Bool:
  match bs:
    case Nil{}:
      True{}
    case +b <> t:
      Bool.and(Box.apart(a, b), Boxes.apart.k(t, b))

def Boxes.apart(bs: List<&2, Box>) -> Bool:
  match bs:
    case Nil{}:
      True{}
    case +b <> t:
      Boxes.apart.k(t, b)

# every box ends at or above y
def Boxes.above(bs: List<&2, Box>, +y: Nat) -> Bool:
  match bs:
    case Nil{}:
      True{}
    case +b <> t:
      Bool.and(Nat.is_ge(y, Box.bottom(b)), Boxes.above(t, y))

# Chips in a flow
# ---------------
# Chips of widths ws go left to right from x, h high, gap apart; one that
# would pass `right` starts a new line at `left` (never the first on its
# line, so a too-wide chip still gets a line of its own).

def Flow.wraps(+left: Nat, +right: Nat, +x: Nat, +w: Nat) -> Bool:
  Bool.and(Nat.is_gt(x, left), Nat.is_gt(Nat.add(x, w), right))

def Flow.place(ws: List<&2, Nat>, +left: Nat, +right: Nat, +x: Nat, +y: Nat, +h: Nat, +gap: Nat) -> List<&2, Box>:
  match ws:
    case Nil{}:
      Nil{}
    case +w <> t:
      +cx = Bool.pick(Nat, Flow.wraps(left, right, x, w), left, x)
      +cy = Bool.pick(Nat, Flow.wraps(left, right, x, w), Nat.add(y, Nat.add(h, gap)), y)
      Box{cx, cy, w, h} <> Flow.place(t, left, right, Nat.add(cx, Nat.add(w, gap)), cy, h, gap)

# the top of the flow's last line (y when there are no chips)
def Flow.end(ws: List<&2, Nat>, +left: Nat, +right: Nat, +x: Nat, +y: Nat, +h: Nat, +gap: Nat) -> Nat:
  match ws:
    case Nil{}:
      y
    case +w <> t:
      +cx = Bool.pick(Nat, Flow.wraps(left, right, x, w), left, x)
      +cy = Bool.pick(Nat, Flow.wraps(left, right, x, w), Nat.add(y, Nat.add(h, gap)), y)
      Flow.end(t, left, right, Nat.add(cx, Nat.add(w, gap)), cy, h, gap)

# where the rows under a flow start: past its last line and a gap, or at
# y itself when there are no chips
def Flow.under(+ws: List<&2, Nat>, +left: Nat, +right: Nat, +x: Nat, +y: Nat, +h: Nat, +gap: Nat) -> Nat:
  Bool.pick(Nat, List.is_empty(&2, Nat, ws), y, Nat.add(Flow.end(ws, left, right, x, y, h, gap), Nat.add(h, gap)))

# Rows
# ----

# a menu row's height
def Menu.rh() -> Nat:
  28n

# n rows from y down, each w wide
def Menu.rows(n: Nat, +x: Nat, +y: Nat, +w: Nat) -> List<&2, Box>:
  match n:
    case 0n:
      Nil{}
    case 1n+k:
      Box{x, y, w, Menu.rh()} <> Menu.rows(k, x, Nat.add(y, Menu.rh()), w)

# the height n rows take, as many of them as fit in room
def Menu.span(n: Nat, +room: Nat) -> Nat:
  match n:
    case 0n:
      0n
    case 1n+k:
      Bool.pick(Nat, Nat.is_ge(room, Menu.rh()), Nat.add(Menu.rh(), Menu.span(k, Nat.sub(room, Menu.rh()))), 0n)

# how many of n rows fit in room
def Menu.fit(n: Nat, +room: Nat) -> Nat:
  match n:
    case 0n:
      0n
    case 1n+k:
      Bool.pick(Nat, Nat.is_ge(room, Menu.rh()), 1n+Menu.fit(k, Nat.sub(room, Menu.rh())), 0n)

def Menu.min(+a: Nat, +b: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_le(a, b), a, b)

def Menu.max(+a: Nat, +b: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_ge(a, b), a, b)

# the first of n rows shown when `shown` fit: off, kept so the shown ones
# never run past the last
def Menu.off(+off: Nat, +n: Nat, +shown: Nat) -> Nat:
  Menu.min(off, Nat.sub(n, shown))

# the offset that brings row i into a view of `shown` rows from off
def Menu.reveal(+i: Nat, +off: Nat, +shown: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_lt(i, off), i, Bool.pick(Nat, Nat.is_ge(i, Nat.add(off, shown)), Nat.sub(Nat.add(i, 1n), shown), off))

# the menu's width: what its content wants, at most what there is
def Menu.width(+want: Nat, +room: Nat) -> Nat:
  Menu.min(want, room)

# a row's label starts past the name column and a gap
def Menu.label_x(+name_x: Nat, +col: Nat) -> Nat:
  Nat.add(name_x, Nat.add(col, 16n))

# the name column: the widest name, at most half the row
def Menu.col(+widest: Nat, +w: Nat) -> Nat:
  Menu.min(widest, Nat.div(w, 2n))
