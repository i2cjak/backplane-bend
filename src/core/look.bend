import Base
import ./schematic.bend as SC

# How the viewers colour each layer: colour and opacity per layer index
# (board.bend's Layer.names, or a schematic's), 0 opacity hiding it. The
# window and the phones draw with this one table.

def Look.board(i: Nat) -> U32 & U32:
  match i:
    case 0n:
      (5791108, 0)
    case 1n:
      (2549247, 0)
    case 2n:
      (49858, 0)
    case 3n:
      (15250087, 200)
    case 4n:
      (196590, 0)
    case 5n:
      (5078980, 190)
    case 6n:
      (8421631, 150)
    case 7n:
      (13148979, 150)
    case 8n:
      (12900552, 150)
    case 9n:
      (8374015, 150)
    case 10n:
      (13532460, 160)
    case 11n:
      (8340095, 160)
    case 12n:
      (13120564, 210)
    case 13n:
      (13148212, 220)
    case 14n:
      (14045866, 0)
    case 15n:
      (11513775, 0)
    case 16n:
      (15920545, 230)
    case 17n:
      (16721634, 0)
    case 18n:
      (11513775, 0)
    case 22n:
      (13685453, 255)
    case 23n:
      (11842740, 255)
    case 24n:
      (526603, 255)
    case _:
      (10000536, 90)

def Look.of.k(sch: Bool, +layer: U32) -> U32 & U32:
  match sch:
    case True{}:
      SC.Sch.look(layer)
    case False{}:
      Look.board(U32.to_nat(layer))

# a layer's colour and opacity in a board (kind 0) or a schematic (kind 1)
def Look.of(+kind: U32, +layer: U32) -> U32 & U32:
  Look.of.k(U32.is_eq(kind, 1), layer)

# how many layers a board or schematic paints
def Look.count(+kind: U32) -> Nat:
  Bool.pick(Nat, U32.is_eq(kind, 1), 24n, 25n)
