import Base
import ../../src/core/json.bend as J
import ../../src/core/utf8.bend as U8
import ../../src/core/client.bend as U
import ../../src/app/nui.bend as S
import ../../src/app/layout.bend as L
import ../../src/gfx/raster.bend as R
import ../../src/gfx/draw.bend as D
import ../../src/app/theme.bend as T

def items(ls: List<&2, String>) -> List<&2, J.Json>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> t:
      Maybe.default(&2, J.Json, J.Json.parse(l), J.Null{}) <> items(t)

def lines(r: U8.Lines & List<&2, String>) -> List<&2, String>:
  (_, ls) = r
  ls

def ui_sel.k(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u2, _}:
      u2

def ui_sel(u: U.Ui, +sel: String) -> U.Ui:
  ui_sel.k(U.Ui.act(u, "select", sel))

def ui_of(bs: List<&2, U32>, +sel: String) -> U.Ui:
  ui_sel(U.Ui.recv(U.Ui.init(U32.to_nat(1790130000)), J.Json.obj([J.KV{"t", J.Str{"log"}}, J.KV{"version", J.Str{"0.1.0"}},
    J.KV{"items", J.Json.arr(items(lines(U8.Lines.feed(U8.Lines.new(), bs))))}])), sel)

def ops(o: L.Out) -> List<&2, R.Op>:
  match o:
    case L.Out{os, _}:
      os

def go(r: File & Result<&1, &1, U32 & String, List<&2, U32>>, +sel: String, +path: String) -> IO(Unit):
  (f, res) = r
  do IO<Unit>:
    File.close(f)
    bs : List<&2, U32> <- IO.pass(List<&2, U32>, res)
    +n : S.Nui = S.Nui.init(ui_of(bs, sel), 1400, 860)
    +img : Image = R.Frame.render(1400, 860, ops(L.Lay.frame(n)), T.Th.bg())
    g : File <- IO.try(File, File.open(path, "w"))
    w : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(g, D.Snap.ppm(img, 1400, 860))
    IO.print("wrote " ++ path)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    f : File <- IO.try(File, File.open("/tmp/bp-home/events.jsonl", "r"))
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 100000000)
    go(r, Maybe.default(&1, String, List.head(&1, String, args), ""), "/tmp/ui.ppm")
