import Base
import ../../src/core/board.bend as B
import ../../src/core/schematic.bend as Sch
import ../../src/app/viewer.bend as V
import ../../src/gfx/raster.bend as R
import ../../src/gfx/draw.bend as D

# Headless schematic render: parse, fit, rasterize, write a PPM.
#   sch_frame FILE.kicad_sch [OUT.ppm] [W H] [x0 y0 x1 y1 (mm, to zoom)]
# Prints parse / ops / raster timings.

def items(m: Maybe<&2, List<&2, B.Item>>) -> List<&2, B.Item>:
  match m:
    case Some{xs}:
      xs
    case None{}:
      Nil{}

def ops.prim(look: U32 & U32, p: B.Prim, +v: V.View, +c: D.Clip) -> List<&2, R.Op>:
  (color, alpha) = look
  V.Ops.prim(p, v, c, color, alpha)

def ops.pick(on: Bool, p: B.Prim, +layer: U32, +v: V.View, +c: D.Clip, rest: List<&2, R.Op>) -> List<&2, R.Op>:
  match on:
    case True{}:
      List.append(&2, R.Op, ops.prim(Sch.Sch.look(layer), p, v, c), rest)
    case False{}:
      rest

def ops.layer(ss: List<&2, V.Seen>, +layer: U32, +v: V.View, +c: D.Clip) -> List<&2, R.Op>:
  match ss:
    case Nil{}:
      Nil{}
    case V.Seen{B.Item{_, _, +l, p, _}, _} <> t:
      ops.pick(U32.is_eq(l, layer), p, layer, v, c, ops.layer(t, layer, v, c))

def ops.layers(n: Nat, +i: U32, +ss: List<&2, V.Seen>, +v: V.View, +c: D.Clip) -> List<&2, R.Op>:
  match n:
    case 0n:
      Nil{}
    case 1n+m:
      List.append(&2, R.Op, ops.layer(ss, i, v, c), ops.layers(m, (i + 1 : U32), ss, v, c))

def arg.f(+xs: List<&2, String>, +i: Nat, +d: F32) -> F32:
  Maybe.default(&2, F32, F32.read(Maybe.default(&2, String, List.get(&2, String, xs, i), "")), d)

def arg.s(+xs: List<&2, String>, +i: Nat, +d: String) -> String:
  Maybe.default(&2, String, List.get(&2, String, xs, i), d)

def view.k(zoom: Bool, +ss: List<&2, V.Seen>, +xs: List<&2, String>, +w: F32, +h: F32) -> V.View:
  match zoom:
    case True{}:
      V.View.fit.k(D.Box{arg.f(xs, 4n, 0.0), arg.f(xs, 5n, 0.0), arg.f(xs, 6n, 100.0), arg.f(xs, 7n, 100.0)}, 0.0, 0.0, w, h)
    case False{}:
      V.View.fit(ss, 0.0, 0.0, w, h)

def go(r: File & Result<&1, &1, U32 & String, List<&2, U32>>, +xs: List<&2, String>) -> IO(Unit):
  (f, res) = r
  do IO<Unit>:
    File.close(f)
    bs : List<&2, U32> <- IO.pass(List<&2, U32>, res)
    +wi : U32 = F32.to_u32(arg.f(xs, 2n, 1400.0))
    +hi : U32 = F32.to_u32(arg.f(xs, 3n, 990.0))
    t0 : Nat <- IO.now()
    +its : List<&2, B.Item> = items(Sch.Sch.items(bs))
    +n : Nat = List.length(&2, B.Item, its)
    +t1 : Nat <- IO.now()
    +ss : List<&2, V.Seen> = V.Scene.update(Nil{}, V.Scene.sort(its), 0n)
    +m : Nat = List.length(&2, V.Seen, ss)
    +t2 : Nat <- IO.now()
    +v : V.View = view.k(Nat.is_ge(List.length(&2, String, xs), 8n), ss, xs, U32.to_f32(wi), U32.to_f32(hi))
    +ops : List<&2, R.Op> = List.reverse(&2, R.Op, ops.layers(List.length(&2, String, Sch.Sch.layer_names()), 0, ss, v, D.Clip{0, 0, wi, hi}))
    +k : Nat = List.length(&2, R.Op, ops)
    +t3 : Nat <- IO.now()
    +img : Image = R.Frame.render(wi, hi, ops, 855826)
    +t4 : Nat <- IO.now()
    IO.print("parse " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms (" ++ Nat.show(n) ++ " items); sort+merge " ++ Nat.show(Nat.sub(t2, t1)) ++ " ms (" ++ Nat.show(m)
      ++ "); ops " ++ Nat.show(Nat.sub(t3, t2)) ++ " ms (" ++ Nat.show(k) ++ "); raster " ++ Nat.show(Nat.sub(t4, t3)) ++ " ms")
    g : File <- IO.try(File, File.open(arg.s(xs, 1n, "/tmp/sch.ppm"), "w"))
    w : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(g, D.Snap.ppm(img, wi, hi))
    return Unit{}

def strs(xs: List<String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      x <> strs(t)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +xs : List<&2, String> = strs(args)
    f : File <- IO.try(File, File.open(arg.s(xs, 0n, "x"), "r"))
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 200000000)
    go(r, xs)
