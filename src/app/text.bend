import Base

# Wrapping monospace text into lines of at most `cols` characters: greedy
# by words, a word longer than a line broken into pieces.

# s in pieces of cols characters (n bounds the count; `empty` is s's)
def Wrap.chunk(n: Nat, empty: Bool, +s: String, +cols: Nat) -> List<&2, String>:
  match n empty:
    case 1n+m False{}:
      String.take(s, cols) <> Wrap.chunk(m, String.is_empty(String.drop(s, cols)), String.drop(s, cols), cols)
    case _ _:
      Nil{}

# the lines so far (newest first), the line being filled, and its length
type Acc is Data:
  Acc{lines: List<&2, String>, cur: String, len: Nat}

def Wrap.put.k(first: Bool, fits: Bool, a: Acc, +w: String, +wl: Nat) -> Acc:
  match first fits a:
    case True{} _ Acc{ls, _, _}:
      Acc{ls, w, wl}
    case False{} True{} Acc{ls, cur, +len}:
      Acc{ls, cur ++ " " ++ w, Nat.add(len, 1n+wl)}
    case False{} False{} Acc{ls, cur, _}:
      Acc{cur <> ls, w, wl}

# add one word (no longer than a line)
def Wrap.put(a: Acc, +w: String, +cols: Nat) -> Acc:
  match a:
    case Acc{ls, cur, +len}:
      Wrap.put.k(Nat.is_eq(len, 0n), Nat.is_le(Nat.add(len, 1n+String.length(w)), cols), Acc{ls, cur, len}, w, String.length(w))

def Wrap.pieces(ps: List<&2, String>, a: Acc, +cols: Nat) -> Acc:
  match ps:
    case Nil{}:
      a
    case +p <> t:
      Wrap.pieces(t, Wrap.put(a, p, cols), cols)

def Wrap.words(ws: List<&2, String>, a: Acc, +cols: Nat) -> Acc:
  match ws:
    case Nil{}:
      a
    case +w <> t:
      Wrap.words(t, Wrap.pieces(Wrap.chunk(1n+Nat.div(String.length(w), Nat.max(cols, 1n)), String.is_empty(w), w, cols), a, cols), cols)

def Wrap.fin(a: Acc) -> List<&2, String>:
  match a:
    case Acc{ls, cur, _}:
      List.reverse(&2, String, cur <> ls)

# one paragraph line (no newlines) as wrapped lines; "" stays one blank line
def Wrap.line(s: String, +cols: Nat) -> List<&2, String>:
  Wrap.fin(Wrap.words(String.split(s, ' '), Acc{Nil{}, "", 0n}, cols))

def Wrap.lines(ls: List<&2, String>, +cols: Nat) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> t:
      List.append(&2, String, Wrap.line(l, cols), Wrap.lines(t, cols))

# text with newlines, wrapped to cols
def Wrap.text(s: String, +cols: Nat) -> List<&2, String>:
  Wrap.lines(String.split(s, '\n'), cols)
