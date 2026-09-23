import Base
import ../../src/core/board.bend as B
import ../../src/core/strokefont.bend as ST
import ../../src/app/viewer.bend as V
import ../../src/gfx/raster.bend as R
import ../../src/gfx/draw.bend as D

# Renders sample stroke-font text to /tmp/stroke.ppm (a visual check).

def prims(ps: List<&2, B.Prim>, +v: V.View) -> List<&2, R.Op>:
  match ps:
    case Nil{}:
      Nil{}
    case p <> t:
      List.append(&2, R.Op, V.Ops.prim(p, v, D.Clip{0, 0, 1000, 600}, 15263976, 255), prims(t, v))

def sample() -> List<&2, B.Prim>:
  +pi = F32.pi()
  List.append(&2, B.Prim, ST.Stroke.text("The quick brown fox jumps over 0123456789", 5.0, 10.0, 4.0, 0.0, 0, 2, False{}),
  List.append(&2, B.Prim, ST.Stroke.text("~{RESET} 10µF 4.7kΩ ±5% 25°C [a+b]*{c}/d_{x}", 5.0, 20.0, 4.0, 0.0, 0, 2, False{}),
  List.append(&2, B.Prim, ST.Stroke.text("centre\nmulti line", 100.0, 40.0, 3.0, 0.0, 1, 1, False{}),
  List.append(&2, B.Prim, ST.Stroke.text("rotated 90", 20.0, 90.0, 3.0, F32.div(pi, 2.0), 0, 2, False{}),
  List.append(&2, B.Prim, ST.Stroke.text("mirrored", 150.0, 70.0, 3.0, 0.0, 0, 2, True{}),
  List.append(&2, B.Prim, ST.Stroke.text.full("italic VPP{slash}MCLR {brl}x{brr} {unknown}", 60.0, 110.0, 4.0, 4.0, 0.5, 0.0, 0, 2, False{}, True{}),
    ST.Stroke.text("ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz !\"#$%&'()<>=?@\\^`|~", 5.0, 30.0, 2.5, 0.0, 0, 2, False{})))))))

def main() -> IO(Unit):
  do IO<Unit>:
    +ops : List<&2, R.Op> = List.reverse(&2, R.Op, prims(sample(), V.View{5.0, 0.0, 0.0}))
    +img : Image = R.Frame.render(1000, 600, ops, 855826)
    g : File <- IO.try(File, File.open("/tmp/stroke.ppm", "w"))
    w : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(g, D.Snap.ppm(img, 1000, 600))
    return Unit{}
