import Base
import ../../src/core/vt.bend as V
import ../../src/core/utf8.bend as U

# Feeds about 1 MB of colored test-runner output (and 1 MB of plain text)
# through the emulator and prints the time each took.
#   bend test/native/vt_bench.bend -o build/vt_bench && build/vt_bench

def line(+i: U32) -> String:
  "\u{1b}[32mPASS\u{1b}[0m test/case_" ++ U32.show(i) ++ " \u{1b}[2m.........\u{1b}[22m ok \u{1b}[1;33m(12ms)\u{1b}[0m\r\n"

def plain(+i: U32) -> String:
  "plain output line " ++ U32.show(i) ++ " lorem ipsum dolor sit amet consectetur\r\n"

def gen.one(color: Bool, +i: U32) -> String:
  match color:
    case True{}:
      line(i)
    case False{}:
      plain(i)

# k lines, reversed onto acc
def gen(k: Nat, +i: U32, acc: List<&2, U32>, +color: Bool) -> List<&2, U32>:
  match k:
    case 0n:
      acc
    case 1n+p:
      gen(p, (i + 1 : U32), V.Vt.onto(U.Utf8.encode(gen.one(color, i)), acc), color)

def input(n: Nat, color: Bool) -> List<&2, U32>:
  List.reverse(&2, U32, gen(n, 0, Nil{}, color))

def count(xs: List<&2, U32>, +n: U32) -> U32:
  match xs:
    case Nil{}:
      n
    case _ <> t:
      count(t, (n + 1 : U32))

def cur(c: V.VCur) -> String:
  match c:
    case V.VCur{x, y, _}:
      U32.show(x) ++ "," ++ U32.show(y)

def bench(name: String, +bs: List<&2, U32>) -> IO(Unit):
  +n = count(bs, 0)
  do IO<Unit>:
    IO.print(name ++ ": " ++ U32.show(n) ++ " bytes")
    t1 : Nat <- IO.now()
    +v : V.Vt = V.Vt.feed(V.Vt.new(120, 40), bs)
    IO.print("  cursor " ++ cur(V.Vt.cursor(v)) ++ " history " ++ U32.show(V.Vt.history(v)))
    +t2 : Nat <- IO.now()
    IO.print("  feed " ++ Nat.show(Nat.sub(t2, t1)) ++ " ms")
    IO.print("  lines " ++ Nat.show(List.length(&2, V.VLine, V.Vt.lines(v, 0n))))
    t3 : Nat <- IO.now()
    IO.print("  view " ++ Nat.show(Nat.sub(t3, t2)) ++ " ms")

def main() -> IO(Unit):
  do IO<Unit>:
    bench("colored", input(15000n, True{}))
    bench("plain", input(16000n, False{}))
