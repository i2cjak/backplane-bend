import Base
import ../../src/gfx/raster.bend as R
import ../../src/gfx/draw.bend as D
import ../../src/gfx/bitmap.bend as B

# A browser frame file (tools/browser, --frames FILE) in a 1400 x 900 frame:
# 1:1 in a panel on the right, half size on the left, UI chrome around and
# over it. Writes /tmp/bitmap.ppm.
#   bend test/native/bitmap_frame.bend -o build/bitmap_frame
#   build/bitmap_frame /tmp/frame.rgb

def leaves(i: Image) -> Nat:
  match i:
    case Pix{_}:
      1n
    case Qua{a, b, c, d}:
      Nat.add(Nat.add(leaves(a), leaves(b)), Nat.add(leaves(c), leaves(d)))

def tree(b: B.Bitmap) -> Image:
  match b:
    case B.Bitmap{_, _, _, t, _, _, _, _}:
      t

def head(h: B.BmHead) -> String:
  match h:
    case B.BmHead{w, hh, seq}:
      "frame " ++ U32.show(w) ++ "x" ++ U32.show(hh) ++ " seq " ++ U32.show(seq)

def chrome() -> List<&2, R.Op>:
  +c = D.Clip.all()
  List.concat(&2, R.Op, [
    D.Draw.text("Preview", c, 668, 38, 14277092),
    D.Draw.text("half size", c, 40, 278, 9081763),
    D.Draw.frame(c, 659, 59, 702, 802, 4210752),
    D.Draw.frame(c, 39, 299, 352, 402, 4210752),
    [D.Draw.rect(c, 0, 0, 1400, 28, 1515051, 255),
     D.Draw.rect(c, 648, 28, 724, 872, 1250331, 255)]])

# a translucent cursor-ish overlay drawn on top of the page
def overlay() -> List<&2, R.Op>:
  +c = D.Clip.all()
  [D.Draw.disc(c, 900.0, 300.0, 10.0, 15039084, 160), D.Draw.rect(c, 660, 840, 700, 20, 855826, 200)]

def go(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Unit):
  (f, res) = r
  do IO<Unit>:
    File.close(f)
    +bs : List<&2, U32> <- IO.pass(List<&2, U32>, res)
    +hd : B.BmHead = B.Bitmap.head(bs)
    t0 : Nat <- IO.now()
    +bm : B.Bitmap = B.Bitmap.load(bs, 660, 60, 700, 800)
    +n0 : Nat = leaves(tree(bm))
    +t1 : Nat <- IO.now()
    +base : Image = R.Frame.render(1400, 900, chrome(), 855826)
    +n1 : Nat = leaves(base)
    +t2 : Nat <- IO.now()
    +img : Image = B.Bitmap.over(1400, 900, bm, base)
    +n2 : Nat = leaves(img)
    +t3 : Nat <- IO.now()
    +img2 : Image = B.Bitmap.over(1400, 900, B.Bitmap.move(bm, 40, 300, 350, 400), img)
    +img3 : Image = R.Frame.over(1400, 900, overlay(), img2)
    +n3 : Nat = leaves(img3)
    t4 : Nat <- IO.now()
    IO.print(head(hd))
    IO.print("decode+quadtree " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms (" ++ Nat.show(n0) ++ " leaves)")
    IO.print("chrome raster " ++ Nat.show(Nat.sub(t2, t1)) ++ " ms (" ++ Nat.show(n1) ++ " leaves)")
    IO.print("composite 1:1 " ++ Nat.show(Nat.sub(t3, t2)) ++ " ms (" ++ Nat.show(n2) ++ " leaves)")
    IO.print("half-size + overlay " ++ Nat.show(Nat.sub(t4, t3)) ++ " ms (" ++ Nat.show(n3) ++ " leaves)")
    g : File <- IO.try(File, File.open("/tmp/bitmap.ppm", "w"))
    w : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(g, D.Snap.ppm(img3, 1400, 900))
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    f : File <- IO.try(File, File.open(Maybe.default(&1, String, List.head(&1, String, args), "/tmp/frame.rgb"), "r"))
    t0 : Nat <- IO.now()
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 100000000)
    t1 : Nat <- IO.now()
    IO.print("read " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms")
    go(r)
