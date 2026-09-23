import Base
import ./check.bend as C
import ../src/core/svg.bend as S
import ../src/core/icons.bend as I

# the path parser (absolute and relative commands, implicit linetos,
# compact numbers, S / T reflection, arcs), its writer, and the icon set

def chars(cs: List<&2, U32>) -> String:
  match cs:
    case Nil{}:
      ""
    case c <> t:
      SCon{Chr{c}, chars(t)}

def kinds(d: String) -> String:
  chars(S.Svg.kinds(S.Svg.parse(d)))

def norm(d: String) -> String:
  S.Svg.show(S.Svg.parse(d))

def nums(ts: List<&2, S.Tok>) -> String:
  match ts:
    case Nil{}:
      ""
    case S.TNum{v} <> t:
      "," ++ F32.show(v) ++ nums(t)
    case S.TCmd{c} <> t:
      "," ++ SCon{Chr{c}, ""} ++ nums(t)

# how far each flattened point is from (12, 12), off by more than e from r
def off(ls: List<&2, S.Ln>, +r: F32, +e: F32) -> Nat:
  match ls:
    case Nil{}:
      0n
    case S.Ln{+ax, +ay, _, _, _} <> t:
      Nat.add(Bool.pick(Nat, F32.is_gt(F32.abs(F32.sub(F32.hypot(F32.sub(ax, 12.0), F32.sub(ay, 12.0)), r)), e), 1n, 0n), off(t, r, e))

def bad.k(ok: Bool, +d: String, rest: List<&2, String>) -> List<&2, String>:
  match ok:
    case True{}:
      rest
    case False{}:
      d <> rest

def good(+d: String) -> Bool:
  +once = norm(d)
  Bool.and(String.eq(norm(once), once), S.Svg.inside(S.Svg.flat(S.Svg.parse(d)), F32.neg(0.01), 24.01))

def layers.bad(ls: List<&2, I.Layer>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case I.Layer{+d, _} <> t:
      bad.k(good(d), d, layers.bad(t))

# the icons whose path does not round-trip through Svg.show, or strays
# outside the 24 x 24 box once flattened
def named(+n: String, ds: List<&2, String>) -> List<&2, String>:
  match ds:
    case Nil{}:
      Nil{}
    case d <> t:
      (n ++ ": " ++ d) <> named(n, t)

def icons.bad(ds: List<&2, I.IDef>) -> List<&2, String>:
  match ds:
    case Nil{}:
      Nil{}
    case I.IDef{n, ls} <> t:
      List.append(&2, String, named(n, layers.bad(ls)), icons.bad(t))

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("numbers split compactly", nums(S.Svg.lex("M1-2.5.5e1,3E-1 -.25")), ",M,1,-2.5,5,0.3,-0.25")
    C.Check.str("pairs after a moveto are linetos", kinds("m1 2 3 4 5 6z"), "MLLZ")
    C.Check.str("relative commands count from the pen", norm("m1 2l3 4h1v-1z"), "M 1 2 L 4 6 L 5 6 L 5 5 Z")
    C.Check.str("a relative moveto after close starts at the subpath start", norm("M2 3l1 1zm1 1l1 0"), "M 2 3 L 3 4 Z M 3 4 L 4 4")
    C.Check.str("S reflects the last cubic control", norm("M0 0C0 10 10 10 10 0S20-10 20 0"), "M 0 0 C 0 10 10 10 10 0 C 10 -10 20 -10 20 0")
    C.Check.str("T reflects the last quadratic control", norm("M0 0Q5 5 10 0T20 0"), "M 0 0 Q 5 5 10 0 Q 15 -5 20 0")
    C.Check.str("S after a line uses the pen", norm("M0 0L4 0S8 4 8 0"), "M 0 0 L 4 0 C 4 0 8 4 8 0")
    C.Check.str("arc flags and relative end", norm("M2 2a3 4 10 1 0 5-6"), "M 2 2 A 3 4 10 1 0 7 -4")
    C.Check.str("a short tail is dropped", kinds("M1 2L3"), "M")
    C.Check.str("round trip", norm(norm("M.5.5c1 1 2 2 3 3q1 1 2 0t2 0a1 1 0 0 1 2 0Z")), norm("M.5.5c1 1 2 2 3 3q1 1 2 0t2 0a1 1 0 0 1 2 0Z"))
    C.Check.str("a circle as two arcs stays on its radius", Nat.show(off(S.Svg.flat(S.Svg.parse("M9 12a3 3 0 1 0 6 0a3 3 0 1 0-6 0")), 3.0, 0.01)), "1")
    C.Check.str("arc pieces", Nat.show(List.length(&2, S.Ln, S.Svg.flat(S.Svg.parse("M9 12a3 3 0 1 0 6 0a3 3 0 1 0-6 0")))), "26")
    C.Check.str("icons round-trip and stay in the box", String.join(icons.bad(I.Icon.all()), " | "), "")
    C.Check.str("the icons the UIs use exist", String.join(I.Icon.missing(I.Icon.used()), ","), "")
