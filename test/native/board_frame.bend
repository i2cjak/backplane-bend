import Base
import ../../src/core/board.bend as B
import ../../src/app/viewer.bend as V
import ../../src/gfx/raster.bend as R
import ../../src/gfx/draw.bend as D

def items(m: Maybe<&2, List<&2, B.Item>>) -> List<&2, B.Item>:
  match m:
    case Some{xs}:
      xs
    case None{}:
      Nil{}

def leaves(i: Image) -> Nat:
  match i:
    case Pix{_}:
      1n
    case Qua{a, b, c, d}:
      Nat.add(Nat.add(leaves(a), leaves(b)), Nat.add(leaves(c), leaves(d)))

def go(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  (f, res) = r
  do IO<Unit>:
    File.close(f)
    bs : List<&2, U32> <- IO.pass(List<&2, U32>, res)
    t0 : Nat <- IO.now()
    +ss : List<&2, V.Seen> = V.Scene.update(Nil{}, V.Scene.sort(items(B.Board.items(bs))), 0n)
    +n : Nat = List.length(&2, V.Seen, ss)
    +t1 : Nat <- IO.now()
    +v : V.View = V.View.fit(ss, 0.0, 0.0, 1400.0, 900.0)
    +ops : List<&2, R.Op> = List.reverse(&2, R.Op, V.Ops.scene(ss, v, D.Clip{0, 0, 1400, 900}, 10000n, 0n, False{}))
    +k : Nat = List.length(&2, R.Op, ops)
    +t2 : Nat <- IO.now()
    +img : Image = R.Frame.render(1400, 900, ops, 526603)
    +t3 : Nat <- IO.now()
    +lv : Nat = leaves(img)
    t4 : Nat <- IO.now()
    IO.print("leaf walk " ++ Nat.show(Nat.sub(t4, t3)) ++ " ms")
    IO.print("parse+sort+merge " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms (" ++ Nat.show(n) ++ " items); ops " ++ Nat.show(Nat.sub(t2, t1)) ++ " ms (" ++ Nat.show(k) ++ "); raster " ++ Nat.show(Nat.sub(t3, t2)) ++ " ms (" ++ Nat.show(lv) ++ " leaves)")
    g : File <- IO.try(File, File.open("/tmp/board.ppm", "w"))
    w : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(g, D.Snap.ppm(img, 1400, 900))
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    f : File <- IO.try(File, File.open(Maybe.default(&1, String, List.head(&1, String, args), "x"), "r"))
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 200000000)
    go(r)
