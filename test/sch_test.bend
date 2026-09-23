import Base
import ./check.bend as C
import ../src/core/board.bend as B
import ../src/core/schematic.bend as Sch
import ../src/core/strokefont.bend as ST
import ../src/core/utf8.bend as U

def sheet() -> String:
  "(kicad_sch (version 20250114)
  (lib_symbols
    (symbol \"Device:R\" (pin_numbers (hide yes)) (pin_names (offset 0))
      (property \"Reference\" \"R\" (at 2 0 90) (effects (font (size 1.27 1.27))))
      (symbol \"R_0_1\" (rectangle (start -1 2.5) (end 1 -2.5) (stroke (width 0.254)) (fill (type none))))
      (symbol \"R_1_1\"
        (pin passive line (at 0 3.81 270) (length 1.27) (name \"A\" (effects (font (size 1.27 1.27)))) (number \"1\" (effects (font (size 1.27 1.27)))))
        (pin passive line (at 0 -3.81 90) (length 1.27) (name \"~\" (effects (font (size 1.27 1.27)))) (number \"2\" (effects (font (size 1.27 1.27))))))))
  (wire (pts (xy 10 10) (xy 20 10)) (stroke (width 0) (type default)) (uuid \"w1\"))
  (junction (at 20 10) (diameter 0) (color 0 0 0 0) (uuid \"j1\"))
  (label \"SDA\" (at 10 10 0) (effects (font (size 1.27 1.27)) (justify left bottom)) (uuid \"l1\"))
  (symbol (lib_id \"Device:R\") (at 100 50 90) (unit 1) (uuid \"s1\")
    (property \"Reference\" \"R1\" (at 100 47 0) (effects (font (size 1.27 1.27))))
    (property \"Value\" \"10k\" (at 100 53 0) (effects (font (size 1.27 1.27))))
    (property \"Footprint\" \"\" (at 100 50 0) (effects (font (size 1.27 1.27)) (hide yes))))
)"

def items(m: Maybe<&2, List<&2, B.Item>>) -> List<&2, B.Item>:
  match m:
    case Some{xs}:
      xs
    case None{}:
      Nil{}

def some(m: Maybe<&2, List<&2, B.Item>>) -> String:
  match m:
    case Some{_}:
      "some"
    case None{}:
      "none"

def hit(xs: List<&2, B.Item>, +k: String) -> Bool:
  match xs:
    case B.Item{key, _, _, _, _} <> _:
      String.eq(key, k)
    case Nil{}:
      False{}

def find.go(xs: List<&2, B.Item>, h: Bool, +k: String) -> Maybe<&2, B.Item>:
  match xs h:
    case i <> _ True{}:
      Some{i}
    case _ <> +t False{}:
      find.go(t, hit(t, k), k)
    case Nil{} _:
      None{}

def find(+xs: List<&2, B.Item>, +k: String) -> Maybe<&2, B.Item>:
  find.go(xs, hit(xs, k), k)

def info(m: Maybe<&2, B.Item>) -> String:
  match m:
    case Some{B.Item{_, _, _, _, i}}:
      i
    case None{}:
      "(missing)"

def rnd(+f: F32) -> String:
  Nat.show(F32.to_nat(F32.round(f)))

# where a pin's line starts (its connection point), rounded to mm
def start(m: Maybe<&2, B.Item>) -> String:
  match m:
    case Some{B.Item{_, _, _, B.PSeg{B.Pt{x, y}, _, _}, _}}:
      rnd(x) ++ "," ++ rnd(y)
    case _:
      "(not a segment)"

def layer(m: Maybe<&2, B.Item>) -> String:
  match m:
    case Some{B.Item{_, _, l, _, _}}:
      U32.show(l)
    case None{}:
      "(missing)"

def main() -> IO(Unit):
  +xs = items(Sch.Sch.items(U.Utf8.encode(sheet())))
  do IO<Unit>:
    C.Check.str("sch incomplete", some(Sch.Sch.items(U.Utf8.encode("(kicad_sch (wire (pts (xy 0 0)"))), "none")
    C.Check.str("sch complete", some(Sch.Sch.items(U.Utf8.encode(sheet()))), "some")
    C.Check.str("sch wire", info(find(xs, "w1")), "wire")
    C.Check.str("sch wire layer", layer(find(xs, "w1")), "14")
    C.Check.str("sch junction", info(find(xs, "j1")), "junction")
    C.Check.str("sch label", info(find(xs, "l1/0")), "label;text=SDA")
    C.Check.str("sch body", info(find(xs, "s1/g1001")), "symbol;ref=R1;value=10k;lib=Device:R")
    C.Check.str("sch pin", info(find(xs, "s1/pin/1")), "pin 1;name=A;type=passive;symbol=R1")
    C.Check.str("sch pin placed", start(find(xs, "s1/pin/1")), "96,50")
    C.Check.str("sch pin 2 placed", start(find(xs, "s1/pin/2")), "104,50")
    C.Check.str("sch pin name", layer(find(xs, "s1/pin/1/n/0")), "8")
    C.Check.str("sch no hidden number", info(find(xs, "s1/pin/1/#/0")), "(missing)")
    C.Check.str("sch value", layer(find(xs, "s1/f/Value/0")), "10")
    C.Check.str("sch hidden field", info(find(xs, "s1/f/Footprint/0")), "(missing)")
    C.Check.str("stroke width", rnd(ST.Stroke.width("H", 21.0)), "22")
    C.Check.str("stroke wrap", ST.Stroke.wrap("aa bb cc", 21.0, 100.0), "aa bb\ncc")
