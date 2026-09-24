import Base
import ../../src/core/board.bend as B
import ../../src/core/schematic.bend as SC
import ../../src/core/hier.bend as HI
import ../../src/core/client.bend as U
import ../../src/app/nui.bend as S
import ../../src/app/layout.bend as L
import ../../src/app/viewer.bend as V
import ../../src/app/theme.bend as T
import ../../src/app/main.bend as M
import ../../src/server/server.bend as SV
import ../../src/gfx/raster.bend as R
import ../../src/gfx/draw.bend as D

# The viewer on a hierarchical schematic, without a window: load the
# sheet tree as the window does, open the layer and sheet list, go into
# the first child sheet, turn the wires off. Writes a PPM per step.
#   sheet_frame ROOT.kicad_sch

def items(m: Maybe<&2, List<&2, B.Item>>) -> List<&2, B.Item>:
  match m:
    case Some{xs}:
      xs
    case None{}:
      Nil{}

def ui(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}:
      u

def scene(vw: V.Vw) -> List<&2, V.Seen>:
  match vw:
    case V.Vw{ss, _, _, _, _, _, _, _, _, _, _}:
      ss

def view(vw: V.Vw) -> V.View:
  match vw:
    case V.Vw{_, v, _, _, _, _, _, _, _, _, _}:
      v

def outs(o: L.Out) -> List<&2, R.Op>:
  match o:
    case L.Out{os, _}:
      os

def act(+n: S.Nui, +a: String, +v: String) -> S.Nui:
  S.Step.nui(S.Nui.vw_act(n, a, v))

# read the sheet on show into the viewer, as the shell does, and fit it
def load(+n: S.Nui) -> IO(S.Nui):
  do IO<S.Nui>:
    bs : List<&2, U32> <- SV.Files.read(HI.Hier.file(S.Nui.rows(n), S.Nui.sheet.at(n)))
    +n1 : S.Nui = S.Nui.board(S.Nui.asked(n, S.Nui.source(n)), S.Nui.source(n), V.Scene.sort(items(SC.Sch.items(bs))), 0n)
    return S.Nui.with_vw(n1, S.Vw.fit(S.Nui.vw(n1), S.Nui.vx0(n1), 860, 1400))

def snap(+ty: L.Ty, +n: S.Nui, +path: String) -> IO(Unit):
  do IO<Unit>:
    +base : Image = R.Frame.render(1400, 860, List.reverse(&2, R.Op,
      V.Ops.scene(scene(S.Nui.vw(n)), view(S.Nui.vw(n)), D.Clip{S.Nui.vx0(n), 52, 1400, 860}, 100000n, 100000n, True{}, 1, S.Nui.flip(n))), T.Th.bg())
    +img : Image = R.Frame.over(1400, 860, outs(L.Lay.frame(ty, L.TL.memo.none(), n)), base)
    g : File <- IO.try(File, File.open(path, "w"))
    w : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(g, D.Snap.ppm(img, 1400, 860))
    IO.print(path ++ ": at row " ++ Nat.show(S.Nui.sheet.at(n)) ++ " (" ++ HI.Hier.name(S.Nui.rows(n), S.Nui.sheet.at(n)) ++ "), "
      ++ Nat.show(List.length(&2, V.Seen, scene(S.Nui.vw(n)))) ++ " items, flip " ++ U32.show(S.Nui.flip(n)))

def with(+n: S.Nui, +k: String, +v: String) -> S.Nui:
  S.Nui.with_ui(n, U.Ui.scratch_set(S.Nui.ui(n), k, v))

def go(+root: String) -> IO(Unit):
  do IO<Unit>:
    +tab : List<&2, HI.Kids> <- M.Tree.load(64n, [root], Nil{})
    +rows : String = HI.Hier.show(HI.Hier.rows(tab, root))
    IO.print(rows)
    +ty : L.Ty <- L.Ty.load()
    +n0 : S.Nui = with(with(S.Nui.init(ui(U.Ui.act(U.Ui.init(0n), "panel", "")), 1400, 860), "@vw.tree", rows), "@vw.layers", "1")
    +n1 : S.Nui <- load(act(n0, "vw-sheet", "0"))
    snap(ty, n1, "/tmp/sheet-root.ppm")
    +n2 : S.Nui <- load(act(n1, "vw-open", HI.Hier.name(S.Nui.rows(n1), 1n)))
    snap(ty, n2, "/tmp/sheet-child.ppm")
    +n3 : S.Nui = act(n2, "vw-layer", "14")
    snap(ty, n3, "/tmp/sheet-nowires.ppm")
    +n4 : S.Nui <- load(act(n3, "vw-up", ""))
    snap(ty, n4, "/tmp/sheet-up.ppm")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(Maybe.default(&1, String, List.head(&1, String, args), "x"))
