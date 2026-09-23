import Base
import ./check.bend as C
import ../src/core/edit.bend as E
import ../src/app/nui.bend as N
import ../src/gfx/text.bend as X
import ../src/gfx/raster.bend as R

# The window's text fields: word and line motions, selection, cut and
# copy, and the wrap that places the caret (a typed space shows at once)

def show(e: N.Ed) -> String:
  match e:
    case N.Ed{t, c, m, s, ch, +cl, k}:
      t ++ "|" ++ Nat.show(c) ++ "," ++ Nat.show(m) ++ Bool.pick(String, s, " submit", "") ++ Bool.pick(String, String.is_empty(cl), "", " clip=" ++ cl) ++ " k" ++ Nat.show(k)

# one key (X keysym, the code point it types, mods: 1 shift, 2 ctrl)
def key(+code: U32, +text: U32, +mods: U32, +s: String, +i: Nat, +m: Nat) -> String:
  show(N.Ed.key(code, text, mods, s, i, m))

def lines(ls: List<&2, String>) -> String:
  match ls:
    case Nil{}:
      ""
    case l <> t:
      "[" ++ l ++ "]" ++ lines(t)

def wrap(+s: String) -> String:
  lines(X.Text.wrap(Map.new(&2, X.TG), X.Text.bitmap(), s, 400))

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("word right", Nat.show(E.Edit.word_right("foo bar.baz", 0n)), "3")
    C.Check.str("word right over space", Nat.show(E.Edit.word_right("foo bar.baz", 3n)), "7")
    C.Check.str("word right punct", Nat.show(E.Edit.word_right("foo bar.baz", 7n)), "8")
    C.Check.str("word left", Nat.show(E.Edit.word_left("foo bar.baz", 11n)), "8")
    C.Check.str("word left over space", Nat.show(E.Edit.word_left("foo bar", 4n)), "0")
    C.Check.str("line start", Nat.show(E.Edit.line_start("ab\ncde", 5n)), "3")
    C.Check.str("line end", Nat.show(E.Edit.line_end("ab\ncde\nf", 4n)), "6")
    C.Check.str("up keeps column", Nat.show(E.Edit.up("abcd\nxy\nlong line", 11n)), "7")
    C.Check.str("up from first line", Nat.show(E.Edit.up("abc", 2n)), "0")
    C.Check.str("down keeps column", Nat.show(E.Edit.down("abcd\nxy", 1n)), "6")
    C.Check.str("down clamps", Nat.show(E.Edit.down("abcd\nxy", 4n)), "7")
    C.Check.str("down from last line", Nat.show(E.Edit.down("ab\ncd", 3n)), "5")
    C.Check.str("type", key(97, 97, 0, "b", 0n, 0n), "ab|1,1 k1")
    C.Check.str("type space", key(32, 32, 0, "a", 1n, 1n), "a |2,2 k3")
    C.Check.str("type replaces selection", key(120, 120, 0, "hello world", 6n, 11n), "hello x|7,7 k1")
    C.Check.str("backspace", key(65288, 0, 0, "abc", 2n, 2n), "ac|1,1 k2")
    C.Check.str("backspace at start", key(65288, 0, 0, "abc", 0n, 0n), "abc|0,0 k0")
    C.Check.str("ctrl backspace", key(65288, 0, 2, "foo bar", 7n, 7n), "foo |4,4 k2")
    C.Check.str("backspace selection", key(65288, 0, 0, "foo bar", 1n, 5n), "far|1,1 k2")
    C.Check.str("delete", key(65535, 0, 0, "abc", 1n, 1n), "ac|1,1 k2")
    C.Check.str("ctrl delete", key(65535, 0, 2, "foo bar", 0n, 0n), " bar|0,0 k2")
    C.Check.str("left", key(65361, 0, 0, "abc", 2n, 2n), "abc|1,1 k0")
    C.Check.str("left closes selection", key(65361, 0, 0, "abc", 3n, 1n), "abc|1,1 k0")
    C.Check.str("shift left extends", key(65361, 0, 1, "abc", 2n, 3n), "abc|1,3 k0")
    C.Check.str("ctrl left", key(65361, 0, 2, "foo bar", 7n, 7n), "foo bar|4,4 k0")
    C.Check.str("ctrl shift right", key(65363, 0, 3, "foo bar", 0n, 0n), "foo bar|3,0 k0")
    C.Check.str("home is line start", key(65360, 0, 0, "ab\ncd", 4n, 4n), "ab\ncd|3,3 k0")
    C.Check.str("ctrl end", key(65367, 0, 2, "ab\ncd", 0n, 0n), "ab\ncd|5,5 k0")
    C.Check.str("up", key(65362, 0, 0, "ab\ncd", 4n, 4n), "ab\ncd|1,1 k0")
    C.Check.str("select all", key(97, 0, 2, "abc", 1n, 1n), "abc|3,0 k0")
    C.Check.str("copy", key(99, 0, 2, "hello world", 0n, 5n), "hello world|0,5 clip=hello k0")
    C.Check.str("cut", key(120, 0, 2, "hello world", 5n, 11n), "hello|5,5 clip= world k3")
    C.Check.str("cut nothing", key(120, 0, 2, "abc", 1n, 1n), "abc|1,1 k0")
    C.Check.str("undo", key(122, 0, 2, "a", 1n, 1n), "a|1,1 k4")
    C.Check.str("redo", key(122, 0, 3, "a", 1n, 1n), "a|1,1 k5")
    C.Check.str("redo ctrl y", key(121, 0, 2, "a", 1n, 1n), "a|1,1 k5")
    C.Check.str("enter submits", key(65293, 0, 0, "a", 1n, 1n), "a|1,1 submit k0")
    C.Check.str("shift enter", key(65293, 0, 1, "ab", 1n, 1n), "a\nb|2,2 k3")
    C.Check.str("history", E.Edit.top.text(E.Edit.pop(E.Edit.push(E.Edit.push("", 1n, "a"), 2n, "ab"))), "a")
    C.Check.str("history caret", Nat.show(E.Edit.top.caret(E.Edit.push(E.Edit.push("", 1n, "a"), 2n, "ab"))), "2")
    C.Check.str("wrap keeps a last space", wrap("hello "), "[hello ]")
    C.Check.str("wrap keeps runs of spaces", wrap("a  b"), "[a  b]")
    C.Check.str("wrap keeps leading spaces", wrap("  a"), "[  a]")
    C.Check.str("wrap blank line", wrap("a\n\nb"), "[a][][b]")
