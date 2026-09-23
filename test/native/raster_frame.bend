import Base
import ../../src/gfx/draw.bend as D
import ../../src/gfx/raster.bend as R

def ops() -> List<&2, R.Op>:
  +c = D.Clip.all()
  List.concat(&2, R.Op, [
    D.Draw.text("Backplane in Bend - native frame. {}[]()<>=+*/!? 0123456789", c, 24, 20, 14277092),
    D.Draw.text("Settled threads fade in; nothing pops.", c, 24, 44, 9081763),
    [D.Draw.seg(c, 40.0, 120.0, 300.0, 180.0, 6.0, 14123594, 255),
     D.Draw.seg(c, 40.0, 180.0, 300.0, 120.0, 2.0, 6271999, 160),
     D.Draw.disc(c, 400.0, 150.0, 30.0, 15039084, 255),
     D.Draw.disc(c, 400.0, 150.0, 12.0, 460303, 255),
     D.Draw.tri(c, 480.0, 190.0, 560.0, 100.0, 620.0, 200.0, 5816458, 200),
     D.Draw.rect(c, 20, 90, 600, 130, 1515051, 255),
     D.Draw.rect(c, 0, 0, 264, 360, 1250331, 255)]])

def main() -> IO(Unit):
  do IO<Unit>:
    t0 : Nat <- IO.now()
    +img : Image = R.Frame.render(640, 360, ops(), 855826)
    t1 : Nat <- IO.now()
    f : File <- IO.try(File, File.open("/tmp/frame.ppm", "w"))
    r : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(f, D.Snap.ppm(img, 640, 360))
    IO.print("rendered in " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms")
