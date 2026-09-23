import Base
import ../../src/core/board.bend as B

def count(m: Maybe<&2, List<&2, B.Item>>) -> String:
  match m:
    case None{}:
      "incomplete"
    case Some{+xs}:
      Nat.show(List.length(&2, B.Item, xs)) ++ " items"

def go(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  (f, res) = r
  do IO<Unit>:
    File.close(f)
    bs : List<&2, U32> <- IO.pass(List<&2, U32>, res)
    t0 : Nat <- IO.now()
    +s : String = count(B.Board.items(bs))
    t1 : Nat <- IO.now()
    IO.print(s ++ " in " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    f : File <- IO.try(File, File.open(Maybe.default(&1, String, List.head(&1, String, args), "x"), "r"))
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 200000000)
    go(r)
