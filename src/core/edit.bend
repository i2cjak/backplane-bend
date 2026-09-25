import Base

# Text editing: where the caret goes by word and by line, and ranges of a
# string. A position is a count of characters before it. The window's
# fields (the composer, the path fields) edit with these; the web's
# textarea has the browser's own.

# 0 a space, 1 a word character (letters, digits, _ and anything past
# ASCII), 2 punctuation
def Edit.kind(+cp: U32) -> Nat:
  Bool.pick(Nat, Bool.or(Bool.or(U32.is_eq(cp, 32), U32.is_eq(cp, 9)), Bool.or(U32.is_eq(cp, 10), U32.is_eq(cp, 13))), 0n,
    Bool.pick(Nat, Bool.or(Bool.or(Bool.and(U32.is_ge(cp, 48), U32.is_le(cp, 57)), Bool.and(U32.is_ge(cp, 65), U32.is_le(cp, 90))),
      Bool.or(Bool.or(Bool.and(U32.is_ge(cp, 97), U32.is_le(cp, 122)), U32.is_eq(cp, 95)), U32.is_ge(cp, 128))), 1n, 2n))

def Edit.run.k(same: Bool, rest: Nat) -> Nat:
  match same:
    case True{}:
      1n+rest
    case False{}:
      0n

# how many leading characters of s are of kind k
def Edit.run(s: String, +k: Nat) -> Nat:
  match s:
    case SNil{}:
      0n
    case SCon{Chr{+cp}, t}:
      Edit.run.k(Nat.is_eq(Edit.kind(cp), k), Edit.run(t, k))

# the kind of s's first character (a space when s is empty)
def Edit.head(s: String) -> Nat:
  match s:
    case SNil{}:
      0n
    case SCon{Chr{+cp}, _}:
      Edit.kind(cp)

def Edit.hop.k(+n: Nat, +t: String) -> Nat:
  Nat.add(n, Edit.run(t, Edit.head(t)))

# one word from the front of s: the spaces, then one run of word
# characters or of punctuation
def Edit.hop(+s: String) -> Nat:
  Edit.hop.k(Edit.run(s, 0n), String.drop(s, Edit.run(s, 0n)))

# where ctrl+right and ctrl+left land from i
def Edit.word_right(+s: String, +i: Nat) -> Nat:
  Nat.add(i, Edit.hop(String.drop(s, i)))

def Edit.word_left(+s: String, +i: Nat) -> Nat:
  Nat.sub(i, Edit.hop(String.reverse(String.take(s, i))))

def Edit.nl.k(nl: Bool, rest: Nat) -> Nat:
  match nl:
    case True{}:
      0n
    case False{}:
      1n+rest

# characters before the first newline of s
def Edit.to_nl(s: String) -> Nat:
  match s:
    case SNil{}:
      0n
    case SCon{Chr{+cp}, t}:
      Edit.nl.k(U32.is_eq(cp, 10), Edit.to_nl(t))

# the start and the end of the line i is on
def Edit.line_start(+s: String, +i: Nat) -> Nat:
  Nat.sub(i, Edit.to_nl(String.reverse(String.take(s, i))))

def Edit.line_end(+s: String, +i: Nat) -> Nat:
  Nat.add(i, Edit.to_nl(String.drop(s, i)))

def Edit.col(+s: String, +i: Nat) -> Nat:
  Nat.sub(i, Edit.line_start(s, i))

def Edit.up.k(first: Bool, +s: String, +ls: Nat, +col: Nat) -> Nat:
  match first:
    case True{}:
      0n
    case False{}:
      Nat.min(Nat.add(Edit.line_start(s, Nat.sub(ls, 1n)), col), Nat.sub(ls, 1n))

# the same column a line up (the start of the text from its first line)
def Edit.up(+s: String, +i: Nat) -> Nat:
  Edit.up.k(Nat.is_eq(Edit.line_start(s, i), 0n), s, Edit.line_start(s, i), Edit.col(s, i))

def Edit.down.k(last: Bool, +s: String, +le: Nat, +col: Nat) -> Nat:
  match last:
    case True{}:
      String.length(s)
    case False{}:
      Nat.min(Nat.add(1n+le, col), Edit.line_end(s, 1n+le))

# the same column a line down (the end of the text from its last line)
def Edit.down(+s: String, +i: Nat) -> Nat:
  Edit.down.k(Nat.is_ge(Edit.line_end(s, i), String.length(s)), s, Edit.line_end(s, i), Edit.col(s, i))

def Edit.lo(+a: Nat, +b: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_le(a, b), a, b)

def Edit.hi(+a: Nat, +b: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_le(a, b), b, a)

# the text between a and b (either order)
def Edit.slice(+s: String, +a: Nat, +b: Nat) -> String:
  String.take(String.drop(s, Edit.lo(a, b)), Nat.sub(Edit.hi(a, b), Edit.lo(a, b)))

# s with the text between a and b replaced by x
def Edit.splice(+s: String, +a: Nat, +b: Nat, +x: String) -> String:
  String.take(s, Edit.lo(a, b)) ++ x ++ String.drop(s, Edit.hi(a, b))

# Undo history
# ------------
# A field's past states, newest first, as one string: each is the caret,
# \1, the text; states are joined by \0. Kept to Edit.depth() states.

def Edit.depth() -> Nat:
  100n

def Edit.sep() -> String:
  SCon{Chr{0}, SNil{}}

def Edit.state(+c: Nat, +s: String) -> String:
  Nat.show(c) ++ SCon{Chr{1}, SNil{}} ++ s

def Edit.states(+h: String) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.is_empty(h), Nil{}, String.split(h, Chr{0}))

# h with the state (c, s) pushed on
def Edit.push(+h: String, +c: Nat, +s: String) -> String:
  String.join(List.take(&2, String, Edit.state(c, s) <> Edit.states(h), Edit.depth()), Edit.sep())

# the newest state's caret and text, and the rest
def Edit.top(+h: String) -> String:
  Maybe.default(&2, String, List.head(&2, String, Edit.states(h)), "")

def Edit.pop(+h: String) -> String:
  String.join(List.drop(&2, String, Edit.states(h), 1n), Edit.sep())

def Edit.top.caret(+h: String) -> Nat:
  Maybe.default(&2, Nat, Nat.read(Maybe.default(&2, String, List.head(&2, String, String.split(Edit.top(h), Chr{1})), "")), 0n)

def Edit.top.text(+h: String) -> String:
  String.join(List.drop(&2, String, String.split(Edit.top(h), Chr{1}), 1n), SCon{Chr{1}, SNil{}})

# Wrapped lines
# -------------
# A field that wraps shows its text as lines ls (text.bend's Text.wrap:
# greedy by words, a word wider than a line broken between characters).
# Where a line breaks at a space or a newline the wrap drops that one
# character; anywhere else the next line starts right after it. These
# find, from the lines, the position each starts at, so the caret can
# move by the lines the field shows.

# 1 when s starts with a space or a newline (a character the wrap drops)
def Edit.gap(s: String) -> Nat:
  match s:
    case SNil{}:
      0n
    case SCon{Chr{+cp}, _}:
      Bool.pick(Nat, Bool.or(U32.is_eq(cp, 32), U32.is_eq(cp, 10)), 1n, 0n)

def Edit.starts.go(ls: List<&2, String>, +s: String, +at: Nat) -> List<&2, Nat>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      +r = String.drop(s, String.length(l))
      +g = Edit.gap(r)
      at <> Edit.starts.go(t, String.drop(r, g), Nat.add(Nat.add(at, String.length(l)), g))

# where each of the lines s wraps into (ls) starts in s
def Edit.starts(ls: List<&2, String>, +s: String) -> List<&2, Nat>:
  Edit.starts.go(ls, s, 0n)

def Edit.row.n(ss: List<&2, Nat>, +p: Nat) -> Nat:
  match ss:
    case Nil{}:
      0n
    case +h <> t:
      Nat.add(Bool.pick(Nat, Nat.is_le(h, p), 1n, 0n), Edit.row.n(t, p))

# the line position p is on (starts ss): the last one starting at or
# before it, so a position where a broken word goes on is the next line's
def Edit.row(+ss: List<&2, Nat>, +p: Nat) -> Nat:
  Nat.sub(Edit.row.n(ss, p), 1n)

# where line r starts (0 past the last)
def Edit.start(+ss: List<&2, Nat>, +r: Nat) -> Nat:
  Maybe.default(&2, Nat, List.get(&2, Nat, ss, r), 0n)

# the characters of line r before position p
def Edit.before(+ss: List<&2, Nat>, +s: String, +p: Nat) -> String:
  Edit.slice(s, Edit.start(ss, Edit.row(ss, p)), p)
