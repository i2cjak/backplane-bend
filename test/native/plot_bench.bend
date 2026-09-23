import Base
import ../../src/core/board.bend as B
import ../../src/core/schematic.bend as SC
import ../../src/core/plot.bend as P

# plot_bench FILE: how long a board (or .kicad_sch) takes to become the
# phone's first message, by stage, and how big that message is

def items.k(sch: Bool, bs: List<&2, U32>) -> Maybe<&2, List<&2, B.Item>>:
  match sch:
    case True{}:
      SC.Sch.items(bs)
    case False{}:
      B.Board.items(bs)

def items(m: Maybe<&2, List<&2, B.Item>>) -> List<&2, B.Item>:
  match m:
    case Some{xs}:
      xs
    case None{}:
      Nil{}

def go(r: File & Result<&1, &1, U32 & String, List<&2, U32>>, +sch: Bool) -> IO(Unit):
  (f, res) = r
  do IO<Unit>:
    File.close(f)
    bs : List<&2, U32> <- IO.pass(List<&2, U32>, res)
    +t0 : Nat <- IO.now()
    +its : List<&2, B.Item> = items(items.k(sch, bs))
    +n : Nat = List.length(&2, B.Item, its)
    +t1 : Nat <- IO.now()
    +pl : P.Plot = P.Plot.of(its, Bool.pick(U32, sch, 1, 0))
    +cs : List<&2, P.Chunk> = P.Plot.chunks(pl)
    +m : Nat = List.length(&2, P.Chunk, cs)
    +t2 : Nat <- IO.now()
    +msg : List<&2, U32> = P.Plot.msg("k", P.Plot.box(pl), P.Plot.thick(pl), P.Plot.delta(cs, Nil{}))
    +len : Nat = List.length(&2, U32, msg)
    +t3 : Nat <- IO.now()
    +again : Nat = P.Plot.fresh(P.Plot.delta(cs, cs))
    t4 : Nat <- IO.now()
    IO.print(Nat.show(n) ++ " items " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms, " ++ Nat.show(m) ++ " chunks " ++ Nat.show(Nat.sub(t2, t1)) ++ " ms, message "
      ++ Nat.show(len) ++ " bytes " ++ Nat.show(Nat.sub(t3, t2)) ++ " ms, unchanged delta " ++ Nat.show(again) ++ " fresh " ++ Nat.show(Nat.sub(t4, t3)) ++ " ms")

def once(+path: String) -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open(path, "r"))
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 200000000)
    go(r, String.ends_with(path, ".kicad_sch"))

# BACKPLANE_BENCH_RUNS times over (default once): the runtime's cost for
# the same work should not grow with the runs
def runs(n: Nat, +path: String) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+m:
      IO.bind(Unit, Unit, once(path), u => runs(m, path))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +path : String = Maybe.default(&1, String, List.head(&1, String, args), "x")
    n : Result<&1, &1, U32 & String, String> <- IO.get_env("BACKPLANE_BENCH_RUNS")
    runs(Maybe.default(&2, Nat, Nat.read(Result.default(&1, &1, U32 & String, String, n, "1")), 1n), path)
