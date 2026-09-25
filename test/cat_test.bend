import Base
import ./check.bend as K
import ../src/core/cat.bend as C
import ../src/core/svg.bend as S
import ../src/core/json.bend as J

# the cats: every mood of several looks has parts; path data is absolute
# M L C Q Z only and stays in the box; the SVG is one animated document; a
# data URI has nothing raw a URI must escape; a pose loops seamlessly

def looks() -> List<&2, Nat>:
  [0n, 13n, 6n, 19n, 32n, 45n, 58n, 71n, 100n]

def moods() -> List<&2, String>:
  C.Cat.moods()

def only.k(+c: U32) -> Bool:
  Bool.or(Bool.or(Bool.or(U32.is_eq(c, 77), U32.is_eq(c, 76)), Bool.or(U32.is_eq(c, 67), U32.is_eq(c, 81))),
    Bool.or(Bool.or(U32.is_eq(c, 90), U32.is_eq(c, 32)), Bool.or(Bool.or(U32.is_eq(c, 46), U32.is_eq(c, 45)), Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57)))))

# only the characters of absolute M L C Q Z path data
def only(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{Chr{+c}, t}:
      Bool.and(only.k(c), only(t))

def good(+d: String) -> Bool:
  Bool.and(Bool.and(only(d), String.starts_with(d, "M")), S.Svg.inside(S.Svg.flat(S.Svg.parse(d)), F32.neg(0.01), 64.01))

def parts.bad(ps: List<&2, C.Part>, +tag: String) -> List<&2, String>:
  match ps:
    case Nil{}:
      Nil{}
    case C.Part{n, +d, _, _, _, _, _} <> t:
      List.append(&2, String, C.Cat.either(String, good(d), Nil{}, [tag ++ "/" ++ n ++ ": " ++ d]), parts.bad(t, tag))

def count.bad(+n: Nat, +tag: String) -> List<&2, String>:
  C.Cat.either(String, Nat.is_ge(n, 16n), Nil{}, [tag ++ " has " ++ Nat.show(n) ++ " parts"])

def rig.bad(ms: List<&2, String>, +look: Nat) -> List<&2, String>:
  match ms:
    case Nil{}:
      Nil{}
    case +m <> t:
      +ps = C.Cat.rig(look, m)
      +tag = Nat.show(look) ++ "/" ++ m
      List.concat(&2, String, [count.bad(List.length(&2, C.Part, ps), tag), parts.bad(ps, tag), rig.bad(t, look)])

def all.bad(ls: List<&2, Nat>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      List.append(&2, String, rig.bad(moods(), l), all.bad(t))

# SVG documents
def svg.bad.k(+m: String, +s: String) -> List<&2, String>:
  +animated = String.contains(s, "animateTransform")
  +want = Bool.not(String.eq(m, "away"))
  List.concat(&2, String, [
    C.Cat.either(String, Bool.and(String.starts_with(s, "<svg "), String.ends_with(s, "</svg>")), Nil{}, [m ++ ": not one svg element"]),
    C.Cat.either(String, Bool.not(Bool.xor(animated, want)), Nil{}, [m ++ ": animated is " ++ Bool.show(animated)]),
    C.Cat.either(String, String.contains(s, "viewBox='0 0 64 64'"), Nil{}, [m ++ ": no 64 box"])])

def svg.bad(ms: List<&2, String>, +look: Nat) -> List<&2, String>:
  match ms:
    case Nil{}:
      Nil{}
    case +m <> t:
      List.append(&2, String, svg.bad.k(m, C.Cat.svg(look, m, 32)), svg.bad(t, look))

def raw.k(+c: U32) -> Bool:
  Bool.or(Bool.or(U32.is_eq(c, 35), U32.is_eq(c, 60)), Bool.or(Bool.or(U32.is_eq(c, 62), U32.is_eq(c, 34)), U32.is_eq(c, 10)))

# characters a data: URI must not hold raw
def raw(s: String, +acc: Nat) -> Nat:
  match s:
    case SNil{}:
      acc
    case SCon{Chr{+c}, t}:
      raw(t, Nat.add(Bool.pick(Nat, raw.k(c), 1n, 0n), acc))

def uri.bad(ms: List<&2, String>, +look: Nat) -> Nat:
  match ms:
    case Nil{}:
      0n
    case +m <> t:
      Nat.add(raw(C.Cat.data_uri(look, m, 96), 0n), uri.bad(t, look))

# Loops
# -----

def gcd(fuel: Nat, +a: Nat, +b: Nat) -> Nat:
  match fuel:
    case 0n:
      a
    case 1n+k:
      Bool.pick(Nat, Nat.is_eq(b, 0n), a, gcd(k, b, Nat.mod(a, b)))

def lcm(+a: Nat, +b: Nat) -> Nat:
  Nat.div(Nat.mul(a, b), gcd(64n, a, b))

def anims.lcm(as: List<&2, C.Anim>, +acc: Nat) -> Nat:
  match as:
    case Nil{}:
      acc
    case C.Anim{_, _, _, _, _, +per, _, _} <> t:
      anims.lcm(t, lcm(acc, U32.to_nat(per)))

def period(fs: List<&2, C.FPart>, +acc: Nat) -> Nat:
  match fs:
    case Nil{}:
      acc
    case C.FPart{_, _, _, _, _, as, _} <> t:
      period(t, anims.lcm(as, acc))

def pts.nums(ps: List<&2, S.Pt>, acc: List<&2, F32>) -> List<&2, F32>:
  match ps:
    case Nil{}:
      acc
    case S.Pt{x, y} <> t:
      pts.nums(t, x <> y <> acc)

def rings.nums(rs: List<&2, C.Ring>, acc: List<&2, F32>) -> List<&2, F32>:
  match rs:
    case Nil{}:
      acc
    case C.Ring{ps, _} <> t:
      rings.nums(t, pts.nums(ps, acc))

# a pose's numbers: every point, and each shape's opacity
def nums(ss: List<&2, C.Shape>, acc: List<&2, F32>) -> List<&2, F32>:
  match ss:
    case Nil{}:
      acc
    case C.Shape{_, _, _, a, _, rs} <> t:
      nums(t, rings.nums(rs, U32.to_f32(a) <> acc))

def same(xs: List<&2, F32>, ys: List<&2, F32>) -> Bool:
  match xs ys:
    case Nil{} Nil{}:
      True{}
    case +x <> xt +y <> yt:
      Bool.and(F32.is_eq(x, y), same(xt, yt))
    case _ _:
      False{}

def poses.same(+a: List<&2, C.Shape>, +b: List<&2, C.Shape>) -> Bool:
  same(nums(a, Nil{}), nums(b, Nil{}))

# the moods whose pose at a whole number of periods differs from the start
def loops.bad(ms: List<&2, String>, +look: Nat) -> List<&2, String>:
  match ms:
    case Nil{}:
      Nil{}
    case +m <> t:
      +fs = C.Cat.flat(look, m)
      +p = period(fs, 1n)
      List.append(&2, String, C.Cat.either(String, poses.same(C.Cat.pose.at(fs, 0n), C.Cat.pose.at(fs, p)), Nil{}, [m ++ " @" ++ Nat.show(p)]),
        loops.bad(t, look))

# the moods whose pose half a period on is the same as at the start
def still.bad(ms: List<&2, String>, +look: Nat) -> List<&2, String>:
  match ms:
    case Nil{}:
      Nil{}
    case +m <> t:
      +fs = C.Cat.flat(look, m)
      +same = poses.same(C.Cat.pose.at(fs, 0n), C.Cat.pose.at(fs, 380n))
      List.append(&2, String, C.Cat.either(String, Bool.not(Bool.xor(same, String.eq(m, "away"))), Nil{}, [m]), still.bad(t, look))

def values.as(as: List<&2, C.Anim>, +ms: Nat) -> String:
  match as:
    case Nil{}:
      ""
    case +a <> t:
      C.Cat.n(C.Cat.value(a, ms)) ++ " " ++ values.as(t, ms)

def values(fs: List<&2, C.FPart>, +ms: Nat) -> String:
  match fs:
    case Nil{}:
      ""
    case C.FPart{_, _, _, _, _, as, _} <> t:
      values.as(as, ms) ++ values(t, ms)

def coat(l: C.Look) -> String:
  match l:
    case C.Look{_, n, _, _, _, _, _, _, _, _, _, _, _}:
      n

def index(l: C.Look) -> Nat:
  match l:
    case C.Look{i, _, _, _, _, _, _, _, _, _, _, _, _}:
      i

def main() -> IO(Unit):
  do IO<Unit>:
    K.Check.str("every mood of every look has its parts, drawn with M L C Q Z inside the box", String.join(all.bad(looks()), " | "), "")
    K.Check.str("one animated svg per mood (away holds still)", String.join(List.concat(&2, String, [svg.bad(moods(), 0n), svg.bad(moods(), 19n), svg.bad(moods(), 32n)]), " | "), "")
    K.Check.str("data URIs escape # < > \" and newlines", Nat.show(Nat.add(uri.bad(moods(), 6n), uri.bad(moods(), 45n))), "0")
    K.Check.str("data URI prefix", String.take(C.Cat.data_uri(0n, "idle", 32), 24n), "data:image/svg+xml;utf8,")
    K.Check.str("poses loop seamlessly", String.join(List.append(&2, String, loops.bad(moods(), 0n), loops.bad(moods(), 58n)), " | "), "")
    K.Check.str("every mood but away moves on the web", String.join(still.bad(moods(), 13n), " | "), "")
    K.Check.str("the window animates only cats doing something", String.join([Bool.show(C.Cat.moving("sleep")), Bool.show(C.Cat.moving("idle")), Bool.show(C.Cat.moving("work")),
      Bool.show(C.Cat.moving("think")), Bool.show(C.Cat.moving("wait")), Bool.show(C.Cat.moving("talk")), Bool.show(C.Cat.moving("error")), Bool.show(C.Cat.moving("away"))], ","),
      "False,False,True,True,True,True,False,False")
    K.Check.str("an unknown mood is idle", Nat.show(List.length(&2, C.Part, C.Cat.rig(3n, "zzz"))), Nat.show(List.length(&2, C.Part, C.Cat.rig(3n, "idle"))))
    K.Check.str("easing: io, blink, saw", values([C.FPart{0, 0, 0.0, 255, False{}, [C.Anim{3, 0.0, 10.0, 0.0, 0.0, 1000, 0, 0}, C.Anim{5, 1.0, 0.0, 0.0, 0.0, 1000, 0, 1}, C.Anim{3, 0.0, 10.0, 0.0, 0.0, 1000, 250, 2}], Nil{}}], 500n)
      ++ "/" ++ values([C.FPart{0, 0, 0.0, 255, False{}, [C.Anim{3, 0.0, 10.0, 0.0, 0.0, 1000, 0, 0}, C.Anim{5, 1.0, 0.0, 0.0, 0.0, 1000, 0, 1}, C.Anim{3, 0.0, 10.0, 0.0, 0.0, 1000, 250, 2}], Nil{}}], 970n),
      "10 1 2.5 /0.09 0 7.2 ")
    K.Check.str("looks: coats x collars, from a seed", Nat.show(C.Cat.looks()) ++ " " ++ coat(C.Cat.look(6n)) ++ " " ++ coat(C.Cat.look(78n)) ++ " " ++ Nat.show(index(C.Cat.look(150n))), "72 calico calico 6")
    K.Check.str("a name's seed is stable", Nat.show(C.Cat.seed("Ada")) ++ " " ++ Nat.show(C.Cat.seed("")), "2596513115 2166136261")
    K.Check.str("rig json", String.take(J.Json.show(C.Cat.rig.json(0n, "wait")), 35n), "[{\"name\":\"tail\",\"d\":\"M 41 58.5 C 48")
    K.Check.str("rig json keeps every part", Nat.show(List.length(&2, J.Json, J.Json.elems(C.Cat.rig.json(7n, "talk")))), Nat.show(List.length(&2, C.Part, C.Cat.rig(7n, "talk"))))
    K.Check.str("css colour", C.Cat.css(C.Cat.hex("F2A65A")) ++ " " ++ C.Cat.css(0), "#f2a65a #000000")
