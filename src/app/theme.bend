import Base

# The palette (the web stylesheet's, as 0xRRGGBB).

def Th.bg() -> U32:
  855826

def Th.panel() -> U32:
  1250843

def Th.raise() -> U32:
  1711653

def Th.line() -> U32:
  2501428

def Th.text() -> U32:
  14277092

def Th.dim() -> U32:
  9081763

def Th.faint() -> U32:
  6054003

def Th.accent() -> U32:
  6271999

def Th.ok() -> U32:
  5816970

def Th.warn() -> U32:
  14922561

def Th.bad() -> U32:
  15755882

# a thread waiting on a question or plan (the sidebar's dot)
def Th.input() -> U32:
  11832575

# a thread with messages queued
def Th.queued() -> U32:
  5226953

# body text (the web's text at 80% over the background)
def Th.soft() -> U32:
  11579834

# a selected chip or menu row
def Th.sel() -> U32:
  1847880

# a focused field's border
def Th.focus() -> U32:
  4160432

def Th.code() -> U32:
  1052174

# The light theme (Settings, Appearance): each colour of the palette above
# has a light twin, swapped into every op a frame draws (layout.bend's
# Theme.ops); the diff's row grounds too. Colours not in the palette (a
# project's badge, a picture, the board viewer's scene) are left alone.

def Th.swap.to(same: Bool, +to: U32, rest: U32) -> U32:
  match same:
    case True{}:
      to
    case False{}:
      rest

def Th.light(+c: U32) -> U32:
  Th.swap.to(U32.is_eq(c, Th.bg()), 16448248,
  Th.swap.to(U32.is_eq(c, Th.panel()), 15855852,
  Th.swap.to(U32.is_eq(c, Th.raise()), 15263714,
  Th.swap.to(U32.is_eq(c, Th.line()), 13881802,
  Th.swap.to(U32.is_eq(c, Th.text()), 1776929,
  Th.swap.to(U32.is_eq(c, Th.dim()), 5988456,
  Th.swap.to(U32.is_eq(c, Th.faint()), 9080726,
  Th.swap.to(U32.is_eq(c, Th.accent()), 2060241,
  Th.swap.to(U32.is_eq(c, Th.ok()), 1869136,
  Th.swap.to(U32.is_eq(c, Th.warn()), 10118912,
  Th.swap.to(U32.is_eq(c, Th.bad()), 13186100,
  Th.swap.to(U32.is_eq(c, Th.input()), 7620304,
  Th.swap.to(U32.is_eq(c, Th.queued()), 1211524,
  Th.swap.to(U32.is_eq(c, Th.soft()), 3619393,
  Th.swap.to(U32.is_eq(c, Th.sel()), 14083575,
  Th.swap.to(U32.is_eq(c, Th.focus()), 7053274,
  Th.swap.to(U32.is_eq(c, Th.code()), 15658472,
  Th.swap.to(U32.is_eq(c, 1127459), 14676964,
  Th.swap.to(U32.is_eq(c, 3279380), 16508134, c)))))))))))))))))))

# a colour in the theme asked for
def Th.of(light: Bool, +c: U32) -> U32:
  match light:
    case True{}:
      Th.light(c)
    case False{}:
      c

# Metrics (pixels): the font cell is 8 x 16
def Th.cw() -> U32:
  8

def Th.lh() -> U32:
  16

def Th.side() -> U32:
  264
