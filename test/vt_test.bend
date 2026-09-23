import Base
import ./check.bend as C
import ../src/core/vt.bend as V
import ../src/core/utf8.bend as U

def feed(v: V.Vt, s: String) -> V.Vt:
  V.Vt.feed(v, U.Utf8.encode(s))

def run(cols: U32, rows: U32, s: String) -> V.Vt:
  feed(V.Vt.new(cols, rows), s)

def runs.text(rs: List<&2, V.VRun>) -> String:
  match rs:
    case Nil{}:
      ""
    case V.VRun{t, _, _, _, _} <> r:
      t ++ runs.text(r)

def lines.text(ls: List<&2, V.VLine>) -> String:
  match ls:
    case Nil{}:
      ""
    case V.VLine{rs} <> Nil{}:
      runs.text(rs)
    case V.VLine{rs} <> r:
      runs.text(rs) ++ "|" ++ lines.text(r)

# the screen's text, rows joined by "|"
def screen(+v: V.Vt) -> String:
  lines.text(V.Vt.lines(v, 0n))

def scrolled(+v: V.Vt, n: Nat) -> String:
  lines.text(V.Vt.lines(v, n))

def b2s(b: Bool) -> String:
  match b:
    case True{}:
      "1"
    case False{}:
      "0"

# every run of the screen: text/fg/bg/bold/underline
def runs.show(rs: List<&2, V.VRun>) -> String:
  match rs:
    case Nil{}:
      ""
    case V.VRun{t, f, b, bo, u} <> r:
      "[" ++ t ++ " " ++ U32.show(f) ++ " " ++ U32.show(b) ++ " " ++ b2s(bo) ++ b2s(u) ++ "]" ++ runs.show(r)

def row.show.k(m: Maybe<&2, V.VLine>) -> String:
  match m:
    case Some{V.VLine{rs}}:
      runs.show(rs)
    case None{}:
      "(none)"

def row0(+v: V.Vt) -> String:
  row.show.k(List.head(&2, V.VLine, V.Vt.lines(v, 0n)))

def cur.k(c: V.VCur) -> String:
  match c:
    case V.VCur{x, y, s}:
      U32.show(x) ++ "," ++ U32.show(y) ++ b2s(s)

def cur(+v: V.Vt) -> String:
  cur.k(V.Vt.cursor(v))

def bytes.plain(ctl: Bool, +b: U32) -> String:
  match ctl:
    case True{}:
      "<" ++ U32.show(b) ++ ">"
    case False{}:
      SCon{Chr{b}, SNil{}}

def bytes.one(esc: Bool, +b: U32) -> String:
  match esc:
    case True{}:
      "^["
    case False{}:
      bytes.plain(U32.is_lt(b, 32) || U32.is_ge(b, 127), b)

# bytes shown with ESC as "^["
def bytes(bs: List<&2, U32>) -> String:
  match bs:
    case Nil{}:
      ""
    case +b <> t:
      bytes.one(U32.is_eq(b, 27), b) ++ bytes(t)

def main() -> IO(Unit):
  +e = {"\u{1b}" : String}
  +d40 = {"0123456789012345678901234567890123456789" : String}
  +d100 = d40 ++ d40 ++ "01234567890123456789"
  +wrap = run(10, 3, "hello world!")
  +alt1 = run(10, 3, "main" ++ e ++ "[?1049h" ++ e ++ "[2;2Halt")
  +alt2 = feed(alt1, e ++ "[?1049l")
  +split = V.Vt.feed(V.Vt.feed(V.Vt.new(10, 2), [97, 226, 156]), [147, 98])
  +dsr = run(10, 5, e ++ "[3;4H" ++ e ++ "[6n")
  +sb = run(6, 3, "1\r\n2\r\n3\r\n4\r\n5")
  +app = run(10, 2, e ++ "[?1h" ++ e ++ "[?2004h")
  +plain = V.Vt.new(10, 2)
  +top = run(5, 4, e ++ "[1;3ra\r\nb\r\nc\r\nd")
  +rs = run(10, 5, "a\r\nb\r\nc\r\nd\r\ne" ++ e ++ "[2;4r" ++ e ++ "[4;1H\n\nX")
  do IO<Unit>:
    C.Check.str("vt text", screen(run(10, 3, "hi")), "hi||")
    C.Check.str("vt wrap", screen(wrap), "hello worl|d!|")
    C.Check.str("vt wrap cursor", cur(wrap), "2,11")
    C.Check.str("vt pending wrap", cur(run(5, 2, "abcde")), "4,01")
    C.Check.str("vt pending wrap cr", screen(run(5, 2, "abcde\r\nf")), "abcde|f")
    C.Check.str("vt long wrap", screen(run(40, 3, d100)), "0123456789012345678901234567890123456789|0123456789012345678901234567890123456789|01234567890123456789")
    C.Check.str("vt long wrap cursor", cur(run(40, 3, d100)), "20,21")
    C.Check.str("vt long scroll", screen(run(40, 2, d100)), "0123456789012345678901234567890123456789|01234567890123456789")
    C.Check.str("vt long after wrap", screen(feed(run(40, 2, d40), d40)), "0123456789012345678901234567890123456789|0123456789012345678901234567890123456789")
    C.Check.str("vt long nowrap", screen(run(40, 2, e ++ "[?7l" ++ d40 ++ "abcdefghij")), "012345678901234567890123456789012345678j|")
    C.Check.str("vt long insert", screen(run(40, 1, "abc\r" ++ e ++ "[4h" ++ d40)), "0123456789012345678901234567890123456789")
    C.Check.str("vt long insert keeps", screen(run(40, 1, "abc\r" ++ e ++ "[4h" ++ "0123456789012345678901234567890123")), "0123456789012345678901234567890123abc")
    C.Check.str("vt long mid row", screen(run(40, 2, "ab" ++ e ++ "[31m" ++ d40)), "ab01234567890123456789012345678901234567|89")
    C.Check.str("vt crlf", screen(run(10, 3, "ab\r\ncd")), "ab|cd|")
    C.Check.str("vt lf keeps column", screen(run(10, 3, "ab\ncd")), "ab|  cd|")
    C.Check.str("vt backspace", screen(run(10, 1, "abc\u{8}\u{8}X")), "aXc")
    C.Check.str("vt tab", screen(run(20, 1, "a\tb")), "a       b")
    C.Check.str("vt cup", screen(run(5, 3, e ++ "[2;3HX")), "|  X|")
    C.Check.str("vt cursor moves", screen(run(6, 3, e ++ "[3;3H" ++ e ++ "[AU" ++ e ++ "[2DL" ++ e ++ "[BD" ++ e ++ "[CR")), "| LU|  D R")
    C.Check.str("vt cha vpa", screen(run(6, 3, e ++ "[4GA" ++ e ++ "[3dB")), "   A||    B")
    C.Check.str("vt cursor clamps", cur(run(5, 3, e ++ "[99;99H")), "4,21")
    C.Check.str("vt el 0", screen(run(10, 1, "abcdef" ++ e ++ "[1;3H" ++ e ++ "[K")), "ab")
    C.Check.str("vt el 1", screen(run(10, 1, "abcdef" ++ e ++ "[1;3H" ++ e ++ "[1K")), "   def")
    C.Check.str("vt el 2", screen(run(10, 1, "abcdef" ++ e ++ "[2K")), "")
    C.Check.str("vt ed 0", screen(run(5, 3, "aaa\r\nbbb\r\nccc" ++ e ++ "[2;2H" ++ e ++ "[J")), "aaa|b|")
    C.Check.str("vt ed 1", screen(run(5, 3, "aaa\r\nbbb\r\nccc" ++ e ++ "[2;2H" ++ e ++ "[1J")), "|  b|ccc")
    C.Check.str("vt ed 2", screen(run(5, 3, "aaa\r\nbbb" ++ e ++ "[2J")), "||")
    C.Check.str("vt ich", screen(run(10, 1, "abcdef\r" ++ e ++ "[2@")), "  abcdef")
    C.Check.str("vt dch", screen(run(10, 1, "abcdef\r" ++ e ++ "[2P")), "cdef")
    C.Check.str("vt ech", screen(run(10, 1, "abcdef\r" ++ e ++ "[2X")), "  cdef")
    C.Check.str("vt il", screen(run(5, 3, "a\r\nb\r\nc" ++ e ++ "[2;1H" ++ e ++ "[L")), "a||b")
    C.Check.str("vt dl", screen(run(5, 3, "a\r\nb\r\nc" ++ e ++ "[1;1H" ++ e ++ "[M")), "b|c|")
    C.Check.str("vt scroll", screen(run(5, 3, "1\r\n2\r\n3\r\n4")), "2|3|4")
    C.Check.str("vt ri", screen(run(5, 3, "1\r\n2" ++ e ++ "[H" ++ e ++ "M0")), "0|1|2")
    C.Check.str("vt sgr red", row0(run(10, 1, e ++ "[31mR" ++ e ++ "[0mn")), "[R 14707829 855826 00][n 14277092 855826 00]")
    C.Check.str("vt sgr bold underline", row0(run(10, 1, e ++ "[1;4mB")), "[B 14277092 855826 11]")
    C.Check.str("vt sgr bright bg", row0(run(10, 1, e ++ "[92;104mG")), "[G 11921552 8570111 00]")
    C.Check.str("vt sgr 256", row0(run(10, 1, e ++ "[38;5;196;48;5;244mX")), "[X 16711680 8421504 00]")
    C.Check.str("vt sgr truecolor", row0(run(10, 1, e ++ "[38;2;1;2;3;48;2;255;128;0mT")), "[T 66051 16744448 00]")
    C.Check.str("vt sgr inverse", row0(run(10, 1, e ++ "[7mI" ++ e ++ "[27mJ")), "[I 855826 14277092 00][J 14277092 855826 00]")
    C.Check.str("vt sgr default", row0(run(10, 1, e ++ "[31;42mA" ++ e ++ "[39mB" ++ e ++ "[49mC")), "[A 14707829 10011513 00][B 14277092 10011513 00][C 14277092 855826 00]")
    C.Check.str("vt erase uses bg", row0(run(4, 1, e ++ "[41m" ++ e ++ "[2K")), "[     14277092 14707829 00]")
    C.Check.str("vt scroll region", screen(rs), "a|d||X|e")
    C.Check.str("vt su", screen(run(5, 3, "1\r\n2\r\n3" ++ e ++ "[S")), "2|3|")
    C.Check.str("vt sd", screen(run(5, 3, "1\r\n2\r\n3" ++ e ++ "[T")), "|1|2")
    C.Check.str("vt region at top", screen(top), "b|c|d|")
    C.Check.str("vt region at top history", U32.show(V.Vt.history(top)), "1")
    C.Check.str("vt origin mode", screen(run(5, 4, e ++ "[2;3r" ++ e ++ "[?6h" ++ e ++ "[1;1HX")), "|X||")
    C.Check.str("vt cnl", screen(run(5, 2, "ab" ++ e ++ "[Ec")), "ab|c")
    C.Check.str("vt alt 47", screen(run(5, 1, "m" ++ e ++ "[?47hx" ++ e ++ "[?47l")), "m")
    C.Check.str("vt da2", bytes(V.Vt.replies(run(10, 1, e ++ "[>c"))), "^[[>1;10;0c")
    C.Check.str("vt key kp enter", bytes(V.Vt.key(plain, 65421, 13, 0)), "<13>")
    C.Check.str("vt alt screen", screen(alt1), "| alt|")
    C.Check.str("vt alt restore", screen(alt2), "main||")
    C.Check.str("vt alt cursor", cur(alt2), "4,01")
    C.Check.str("vt alt flag", b2s(V.Vt.alt(alt1)), "1")
    C.Check.str("vt utf8 split", screen(split), "a✓b|")
    C.Check.str("vt utf8 bad", screen(V.Vt.feed(V.Vt.new(5, 1), [97, 255, 98])), "a\u{FFFD}b")
    C.Check.str("vt wide", cur(run(10, 1, "中a")), "3,01")
    C.Check.str("vt wide text", screen(run(10, 1, "中a")), "中a")
    C.Check.str("vt dec graphics", screen(run(10, 1, e ++ "(0lqk" ++ e ++ "(Bq")), "┌─┐q")
    C.Check.str("vt dsr", bytes(V.Vt.replies(dsr)), "^[[3;4R")
    C.Check.str("vt drain", bytes(V.Vt.replies(V.Vt.drain(dsr))), "")
    C.Check.str("vt da", bytes(V.Vt.replies(run(10, 1, e ++ "[c"))), "^[[?1;2c")
    C.Check.str("vt title bel", V.Vt.title(run(10, 1, e ++ "]0;hello\u{7}x")), "hello")
    C.Check.str("vt title st", V.Vt.title(run(10, 1, e ++ "]2;wörld" ++ e ++ "\\x")), "wörld")
    C.Check.str("vt title text", screen(run(10, 1, e ++ "]2;t" ++ e ++ "\\x")), "x")
    C.Check.str("vt osc split", V.Vt.title(feed(run(10, 1, e ++ "]0;ab"), "c\u{7}")), "abc")
    C.Check.str("vt unknown csi", screen(run(10, 1, "a" ++ e ++ "[?1000;1006h" ++ e ++ "[>4;1m" ++ e ++ "[5 qb")), "ab")
    C.Check.str("vt dcs skipped", screen(run(10, 1, "a" ++ e ++ "P+q544e" ++ e ++ "\\b")), "ab")
    C.Check.str("vt cursor hide", cur(run(10, 1, e ++ "[?25l")), "0,00")
    C.Check.str("vt save restore", cur(run(10, 3, e ++ "[2;5H" ++ e ++ "7" ++ e ++ "[H" ++ e ++ "8")), "4,11")
    C.Check.str("vt reset", screen(run(10, 2, "abc" ++ e ++ "c")), "|")
    C.Check.str("vt scrollback", scrolled(sb, 1n), "2|3|4")
    C.Check.str("vt scrollback all", scrolled(sb, 9n), "1|2|3")
    C.Check.str("vt history", U32.show(V.Vt.history(sb)), "2")
    C.Check.str("vt resize narrow", screen(V.Vt.resize(run(10, 2, "abcdefgh"), 4, 2)), "abcd|")
    C.Check.str("vt resize short", screen(V.Vt.resize(run(4, 3, "a\r\nb\r\nc"), 4, 2)), "b|c")
    C.Check.str("vt resize short history", scrolled(V.Vt.resize(run(4, 3, "a\r\nb\r\nc"), 4, 2), 1n), "a|b")
    C.Check.str("vt resize grow", screen(V.Vt.resize(run(4, 2, "ab"), 6, 3)), "ab||")
    C.Check.str("vt key return", bytes(V.Vt.key(plain, 65293, 13, 0)), "<13>")
    C.Check.str("vt key backspace", bytes(V.Vt.key(plain, 65288, 8, 0)), "<127>")
    C.Check.str("vt key up", bytes(V.Vt.key(plain, 65362, 0, 0)), "^[[A")
    C.Check.str("vt key up app", bytes(V.Vt.key(app, 65362, 0, 0)), "^[OA")
    C.Check.str("vt key shift up", bytes(V.Vt.key(plain, 65362, 0, 1)), "^[[1;2A")
    C.Check.str("vt key ctrl right", bytes(V.Vt.key(plain, 65363, 0, 4)), "^[[1;5C")
    C.Check.str("vt key ctrl c", bytes(V.Vt.key(plain, 99, 99, 4)), "<3>")
    C.Check.str("vt key ctrl c text", bytes(V.Vt.key(plain, 99, 3, 4)), "<3>")
    C.Check.str("vt key alt x", bytes(V.Vt.key(plain, 120, 120, 8)), "^[x")
    C.Check.str("vt key text", bytes(V.Vt.key(plain, 233, 233, 0)), "<195><169>")
    C.Check.str("vt key f1", bytes(V.Vt.key(plain, 65470, 0, 0)), "^[OP")
    C.Check.str("vt key f5", bytes(V.Vt.key(plain, 65474, 0, 0)), "^[[15~")
    C.Check.str("vt key delete", bytes(V.Vt.key(plain, 65535, 0, 0)), "^[[3~")
    C.Check.str("vt key pgup ctrl", bytes(V.Vt.key(plain, 65365, 0, 4)), "^[[5;5~")
    C.Check.str("vt key backtab", bytes(V.Vt.key(plain, 65056, 0, 1)), "^[[Z")
    C.Check.str("vt key tab", bytes(V.Vt.key(plain, 65289, 9, 0)), "<9>")
    C.Check.str("vt key escape", bytes(V.Vt.key(plain, 65307, 27, 0)), "^[")
    C.Check.str("vt key shift", bytes(V.Vt.key(plain, 65505, 0, 1)), "")
    C.Check.str("vt paste", bytes(V.Vt.paste(plain, "a\nb\r\nc")), "a<13>b<13>c")
    C.Check.str("vt paste bracketed", bytes(V.Vt.paste(app, "x" ++ e ++ "y")), "^[[200~xy^[[201~")
