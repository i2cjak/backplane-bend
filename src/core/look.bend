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

# The light ground
# ----------------
# The viewer's own light or dark ground, apart from the app's theme: a
# layer keeps its opacity (so what shows and what hides is the same) and
# takes a colour meant for #f5f4ef.

def Look.ground(light: Bool) -> U32:
  match light:
    case True{}:
      16119023
    case False{}:
      526603

# a board's layers on the light ground (KiCad has no light board theme:
# the dark table's hues, darkened; holes are the ground)
def Look.board.light(i: Nat) -> U32:
  match i:
    case 0n:
      4935546
    case 1n:
      7039851
    case 2n:
      38580
    case 3n:
      10506797
    case 4n:
      1731435
    case 5n:
      3104680
    case 6n:
      5921224
    case 7n:
      10123792
    case 8n:
      5143127
    case 9n:
      3835840
    case 10n:
      10770960
    case 11n:
      6958698
    case 12n:
      11542560
    case 13n:
      10122256
    case 14n:
      8007290
    case 15n:
      9211020
    case 16n:
      3947580
    case 17n:
      12583080
    case 18n:
      7039851
    case 22n:
      5263440
    case 23n:
      8421504
    case 24n:
      16119023
    case _:
      7237230

# a schematic's layers on the light ground: KiCad's default schematic
# theme, which is light
def Look.sch.light(i: Nat) -> U32:
  match i:
    case 0n:
      10526617
    case 1n:
      15131862
    case 2n:
      16777154
    case 3n:
      8650752
    case 4n:
      194
    case 5n:
      194
    case 6n:
      8650752
    case 7n:
      8650752
    case 8n:
      25700
    case 9n:
      11075584
    case 10n:
      25700
    case 11n:
      8650884
    case 12n:
      194
    case 13n:
      194
    case 14n:
      38400
    case 15n:
      194
    case 16n:
      38400
    case 17n:
      986895
    case 18n:
      8650752
    case 19n:
      7226368
    case 20n:
      25700
    case 21n:
      7489578
    case 22n:
      7226368
    case 23n:
      13107200
    case _:
      7697781

def Look.light.k(sch: Bool, +layer: U32) -> U32:
  match sch:
    case True{}:
      Look.sch.light(U32.to_nat(layer))
    case False{}:
      Look.board.light(U32.to_nat(layer))

def Look.lit(l: U32 & U32, +kind: U32, +layer: U32) -> U32 & U32:
  (_, a) = l
  (Look.light.k(U32.is_eq(kind, 1), layer), a)

# a layer's colour and opacity on the light ground or the dark one
def Look.of.t(light: Bool, +kind: U32, +layer: U32) -> U32 & U32:
  match light:
    case True{}:
      Look.lit(Look.of(kind, layer), kind, layer)
    case False{}:
      Look.of(kind, layer)

# how many layers a board or schematic paints
def Look.count(+kind: U32) -> Nat:
  Bool.pick(Nat, U32.is_eq(kind, 1), 24n, 25n)
