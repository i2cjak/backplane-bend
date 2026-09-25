import Base
import ./svg.bend as S
import ./json.bend as J

# Bot faces: a small sitting kitty, flat colours and a soft outline, drawn
# in a 64 x 64 box. A look (coat, pattern, eyes, collar) comes from a seed;
# a mood (what the bot is doing) picks the pose and how it moves.
#
# One rig feeds three renderers with the same math:
#   - web:    Cat.svg, one animated SVG (SMIL) as an <img> data URI
#   - window: Cat.flat once per (look, mood), then Cat.pose.at per frame
#   - phones: Cat.rig.json, drawn by Canvas code (mobile/*/Cat.*)
#
# A part is path data (absolute M L C Q Z only), a fill and/or an outline,
# an opacity, and a list of animations applied outer first: a point p of
# the part is drawn at A1(A2(...An(p))). Each animation is periodic:
#
#   t = ((ms - delay) mod per) / per             (a non-negative remainder)
#   w(x) = (1 - cos(2 pi x)) / 2
#   io:    e = w(t)                              (from, to, from; eased)
#   blink: e = 0 below t = 0.94, else w((t - 0.94) / 0.06)
#   saw:   e = t                                 (from to to, then jump back)
#   value = from + (to - from) * e
#
# rot turns by value degrees about the pivot (clockwise on screen), tx / ty
# move by value, sx / sy scale about the pivot, op multiplies opacity.
# Fill is even-odd; outlines have round caps and joins.

# Types
# -----

# kind: 1 rot, 2 tx, 3 ty, 4 sx, 5 sy, 6 op; ease: 0 io, 1 blink, 2 saw
type Anim is Data:
  Anim{kind: U32, from: F32, to: F32, px: F32, py: F32, per: U32, delay: U32, ease: U32}

# fill and line are 0xRRGGBB, or Cat.none() for no fill / no outline; lw is
# the outline width in box units; alpha 0..255
type Part is Data:
  Part{name: String, d: String, fill: U32, line: U32, lw: F32, alpha: U32, anims: List<&2, Anim>}

# pattern: 0 solid, 1 tabby, 2 light chest, 3 tuxedo / bicolour, 4 pointed,
# 5 calico
type Look is Data:
  Look{index: Nat, coat: String, pat: U32, fur: U32, fur2: U32, light: U32, ear: U32, nose: U32, eye: U32, eye2: U32, line: U32, whisk: U32, collar: U32}

type Coat is Data:
  Coat{name: String, pat: U32, fur: String, fur2: String, light: String, ear: String, nose: String, eye: String, eye2: String, line: String, whisk: String}

# a subpath flattened to points, in box units
type Ring is Data:
  Ring{pts: List<&2, S.Pt>, closed: Bool}

# a part flattened (untransformed), for the window; rim marks a fill with
# no outline of its own or drawn over it later (the window softens its
# edge)
type FPart is Data:
  FPart{fill: U32, line: U32, lw: F32, alpha: U32, rim: Bool, anims: List<&2, Anim>, rings: List<&2, Ring>}

# a part posed at a time: its rings moved, its opacity applied
type Shape is Data:
  Shape{fill: U32, line: U32, lw: F32, alpha: U32, rim: Bool, rings: List<&2, Ring>}

# Colours
# -------

def Cat.none() -> U32:
  16777216

def Cat.hexd(+c: U32) -> U32:
  Bool.pick(U32, U32.is_le(c, 57), (c - 48 : U32), Bool.pick(U32, U32.is_le(c, 70), (c - 55 : U32), (c - 87 : U32)))

def Cat.hex.go(s: String, +acc: U32) -> U32:
  match s:
    case SNil{}:
      acc
    case SCon{Chr{+c}, t}:
      Cat.hex.go(t, U32.or(U32.shln(acc, 4n), Cat.hexd(c)))

# "F2A65A" as 0xF2A65A
def Cat.hex(s: String) -> U32:
  Cat.hex.go(s, 0)

def Cat.digit(+n: U32) -> String:
  SCon{Chr{Bool.pick(U32, U32.is_lt(n, 10), (n + 48 : U32), (n + 87 : U32))}, ""}

# 0xRRGGBB as "#rrggbb"
def Cat.css(+c: U32) -> String:
  "#" ++ Cat.digit(U32.and(U32.shrn(c, 20n), 15)) ++ Cat.digit(U32.and(U32.shrn(c, 16n), 15)) ++ Cat.digit(U32.and(U32.shrn(c, 12n), 15))
    ++ Cat.digit(U32.and(U32.shrn(c, 8n), 15)) ++ Cat.digit(U32.and(U32.shrn(c, 4n), 15)) ++ Cat.digit(U32.and(c, 15))

# a colour faded to a dim grey (the away look)
def Cat.grey.k(+l: U32) -> U32:
  +g = (44 + ((l * 96 : U32) / 255 : U32) : U32)
  U32.or(U32.or(U32.shln(g, 16n), U32.shln(g, 8n)), (g + 8 : U32))

def Cat.grey(+c: U32) -> U32:
  Bool.pick(U32, U32.is_ge(c, Cat.none()), c,
    Cat.grey.k(U32.shrn(((U32.and(U32.shrn(c, 16n), 255) * 77 : U32) + ((U32.and(U32.shrn(c, 8n), 255) * 150 : U32) + (U32.and(c, 255) * 29 : U32) : U32) : U32), 8n)))

# Looks
# -----

def Cat.coats() -> List<&2, Coat>:
  [Coat{"ginger tabby", 1, "F2A65A", "D2712A", "FFE7C7", "F7B4B4", "F28B9B", "8FD16A", "8FD16A", "6B3A1F", "6B3A1F"},
   Coat{"black", 0, "2F2C3A", "2F2C3A", "2F2C3A", "B8748F", "D98AA3", "F5C943", "F5C943", "7A7594", "D8D4E4"},
   Coat{"blue", 2, "8E9DB5", "6E7C94", "C6CFDD", "E8B2C3", "B98BA2", "9BE07A", "9BE07A", "45506A", "45506A"},
   Coat{"cream", 1, "F6DDB5", "E9BF86", "FFF4E3", "F6B8B8", "F29AAA", "F0A33A", "F0A33A", "8A6340", "8A6340"},
   Coat{"white", 0, "F5F2EC", "F5F2EC", "FFFFFF", "F7B5C0", "F59AAE", "6DB8F2", "F2B53D", "7D7486", "9A93A3"},
   Coat{"chocolate", 2, "7A5238", "5E3D29", "B98C68", "D99C9C", "C98580", "F2B33D", "F2B33D", "3A2418", "F0E0D0"},
   Coat{"calico", 5, "F8F2E8", "EE9645", "3B3542", "F6B5B5", "F29AAA", "A6D65E", "A6D65E", "6E5A4E", "6E5A4E"},
   Coat{"tuxedo", 3, "2E2B38", "2E2B38", "F7F4EE", "C27C94", "E391A6", "96D86A", "96D86A", "7A7594", "E8E4F0"},
   Coat{"siamese", 4, "F3E6D0", "5B4033", "FBF3E6", "C99A8A", "6E4C40", "62B2F0", "62B2F0", "6E5040", "6E5040"},
   Coat{"silver tabby", 1, "C9CCD3", "6F7382", "EEF0F3", "F0B4BE", "E595A7", "8CD470", "8CD470", "4A4E5C", "4A4E5C"},
   Coat{"brown tabby", 1, "B88C60", "5E4130", "EBD8BF", "E9AAA6", "D98A8A", "B8D65A", "B8D65A", "4A3222", "4A3222"},
   Coat{"ginger and white", 3, "F0A052", "D2712A", "FFF6EC", "F7B7B7", "F28B9B", "F2C13D", "F2C13D", "74401F", "74401F"}]

def Cat.collars() -> List<&2, String>:
  ["E5484D", "3E8EF7", "2BB5A0", "9B6BF2", "F06FA8", "5CC45C"]

def Cat.nth(-A: Data, xs: List<&2, A>, +n: Nat, +d: A) -> A:
  match xs n:
    case Nil{} _:
      d
    case h <> _ 0n:
      h
    case _ <> t 1n+k:
      Cat.nth(A, t, k, d)

# how many looks there are (coats x collars)
def Cat.looks() -> Nat:
  72n

# the look a seed gets
def Cat.look.index(+seed: Nat) -> Nat:
  Nat.mod(seed, Cat.looks())

def Cat.look.k(+i: Nat, c: Coat, +collar: String) -> Look:
  match c:
    case Coat{name, +pat, fur, fur2, light, ear, nose, eye, eye2, line, whisk}:
      Look{i, name, pat, Cat.hex(fur), Cat.hex(fur2), Cat.hex(light), Cat.hex(ear), Cat.hex(nose), Cat.hex(eye), Cat.hex(eye2), Cat.hex(line), Cat.hex(whisk), Cat.hex(collar)}

def Cat.look(+seed: Nat) -> Look:
  +i = Cat.look.index(seed)
  Cat.look.k(i, Cat.nth(Coat, Cat.coats(), Nat.mod(i, 12n), Coat{"", 0, "", "", "", "", "", "", "", "", ""}),
    Cat.nth(String, Cat.collars(), Nat.div(i, 12n), "E5484D"))

def Cat.seed.go(s: String, +h: U32) -> U32:
  match s:
    case SNil{}:
      h
    case SCon{Chr{+c}, t}:
      Cat.seed.go(t, (U32.xor(h, c) * 16777619 : U32))

# a stable seed for a name (FNV-1a over its characters)
def Cat.seed(s: String) -> Nat:
  U32.to_nat(Cat.seed.go(s, 2166136261))

# Moods
# -----

def Cat.moods() -> List<&2, String>:
  ["sleep", "idle", "work", "think", "wait", "talk", "error", "away"]

# the mood's number (0 sleep, 1 idle, 2 work, 3 think, 4 wait, 5 talk,
# 6 error, 7 away); an unknown mood is idle
def Cat.mood(+s: String) -> U32:
  Bool.pick(U32, String.eq(s, "sleep"), 0, Bool.pick(U32, String.eq(s, "work"), 2, Bool.pick(U32, String.eq(s, "think"), 3,
    Bool.pick(U32, String.eq(s, "wait"), 4, Bool.pick(U32, String.eq(s, "talk"), 5, Bool.pick(U32, String.eq(s, "error"), 6,
      Bool.pick(U32, String.eq(s, "away"), 7, 1)))))))

def Cat.mood.all(ms: List<&2, String>) -> List<&2, U32>:
  match ms:
    case Nil{}:
      Nil{}
    case m <> t:
      Cat.mood(m) <> Cat.mood.all(t)

# does the window animate this mood? A sleeping, failed or unreachable cat
# holds still there, so it never asks for frames (web and phones may still
# let a sleeping cat breathe)
def Cat.moving(+mood: String) -> Bool:
  Bool.or(Bool.or(String.eq(mood, "work"), String.eq(mood, "think")), Bool.or(String.eq(mood, "wait"), String.eq(mood, "talk")))

# Path data
# ---------

def Cat.n(+v: F32) -> String:
  F32.show(F32.div(F32.round(F32.mul(v, 100.0)), 100.0))

def Cat.xy(+x: F32, +y: F32) -> String:
  Cat.n(x) ++ " " ++ Cat.n(y)

# an ellipse as four cubics
def Cat.ell(+cx: F32, +cy: F32, +rx: F32, +ry: F32) -> String:
  +kx = F32.mul(rx, 0.5523)
  +ky = F32.mul(ry, 0.5523)
  +x0 = F32.sub(cx, rx)
  +x1 = F32.add(cx, rx)
  +y0 = F32.sub(cy, ry)
  +y1 = F32.add(cy, ry)
  "M " ++ Cat.xy(x0, cy) ++ " C " ++ Cat.xy(x0, F32.sub(cy, ky)) ++ " " ++ Cat.xy(F32.sub(cx, kx), y0) ++ " " ++ Cat.xy(cx, y0)
    ++ " C " ++ Cat.xy(F32.add(cx, kx), y0) ++ " " ++ Cat.xy(x1, F32.sub(cy, ky)) ++ " " ++ Cat.xy(x1, cy)
    ++ " C " ++ Cat.xy(x1, F32.add(cy, ky)) ++ " " ++ Cat.xy(F32.add(cx, kx), y1) ++ " " ++ Cat.xy(cx, y1)
    ++ " C " ++ Cat.xy(F32.sub(cx, kx), y1) ++ " " ++ Cat.xy(x0, F32.add(cy, ky)) ++ " " ++ Cat.xy(x0, cy) ++ " Z"

def Cat.flip(+x: F32) -> F32:
  F32.sub(64.0, x)

def Cat.mir1(s: S.Seg) -> String:
  match s:
    case S.SM{+x, +y}:
      "M " ++ Cat.xy(Cat.flip(x), y)
    case S.SL{+x, +y}:
      "L " ++ Cat.xy(Cat.flip(x), y)
    case S.SC{+x1, +y1, +x2, +y2, +x, +y}:
      "C " ++ Cat.xy(Cat.flip(x1), y1) ++ " " ++ Cat.xy(Cat.flip(x2), y2) ++ " " ++ Cat.xy(Cat.flip(x), y)
    case S.SQ{+x1, +y1, +x, +y}:
      "Q " ++ Cat.xy(Cat.flip(x1), y1) ++ " " ++ Cat.xy(Cat.flip(x), y)
    case S.SA{_, _, _, _, _, +x, +y}:
      "L " ++ Cat.xy(Cat.flip(x), y)
    case S.SZ{}:
      "Z"

def Cat.mirs(ss: List<&2, S.Seg>) -> List<&2, String>:
  match ss:
    case Nil{}:
      Nil{}
    case s <> t:
      Cat.mir1(s) <> Cat.mirs(t)

# the path mirrored left to right across the box
def Cat.mir(d: String) -> String:
  String.join(Cat.mirs(S.Svg.parse(d)), " ")

# a path and its mirror as one path of two subpaths (they must not overlap)
def Cat.both(+d: String) -> String:
  d ++ " " ++ Cat.mir(d)

# Shapes
# ------

def Cat.d.head() -> String:
  "M 32 13.5 C 41 13.5 47.5 17 49 24 C 50.5 31 49 36.5 45 39 C 41.5 41.3 37 42 32 42 C 27 42 22.5 41.3 19 39 C 15 36.5 13.5 31 15 24 C 16.5 17 23 13.5 32 13.5 Z"

def Cat.d.ear() -> String:
  "M 15.5 23 C 14.4 16.5 14.6 10.8 16 7.6 Q 16.9 5.8 18.6 6.9 C 21.8 9.2 25.2 12.3 28 15.8 Z"

def Cat.d.ear.in() -> String:
  "M 18.2 19.5 C 17.7 15.5 17.8 12 18.7 10 Q 19.2 9.1 20 9.7 C 22 11.3 24 13.5 25.6 15.9 Z"

def Cat.d.body() -> String:
  "M 32 36 C 40.5 36 45 43 45.8 50.5 C 46.6 56.5 44 61 38 61 L 26 61 C 20 61 17.4 56.5 18.2 50.5 C 19 43 23.5 36 32 36 Z"

def Cat.d.chest() -> String:
  "M 32 42 C 36 42 38 46 37.6 51 C 37.2 56 35 58.8 32 58.8 C 29 58.8 26.8 56 26.4 51 C 26 46 28 42 32 42 Z"

def Cat.d.tail() -> String:
  "M 41 58.5 C 48 60.5 54.5 58 55 51 C 55.3 46.5 54 43 56.2 41.3 C 58.3 39.8 60.6 41.5 60.1 44.2 C 59.6 47 59 49 59 52 C 58.8 60 50.5 64 40.5 62 Z"

def Cat.d.tail.tip() -> String:
  "M 54.89 45.1 C 54.88 43.45 55.1 42.15 56.2 41.3 C 58.3 39.8 60.6 41.5 60.1 44.2 C 59.93 45.18 59.74 46.06 59.57 46.9 C 58 46.4 56.2 45.4 54.89 45.1 Z"

def Cat.d.collar() -> String:
  "M 23 40.4 Q 32 45.6 41 40.4 L 41.3 42.6 Q 32 48.2 22.7 42.6 Z"

def Cat.d.nose() -> String:
  "M 30.2 32.8 Q 32 32.2 33.8 32.8 Q 33.4 34.3 32 34.8 Q 30.6 34.3 30.2 32.8 Z"

def Cat.d.mouth() -> String:
  "M 32 34.8 L 32 35.6 M 29.3 35.4 Q 30.7 37.2 32 35.6 Q 33.3 37.2 34.7 35.4"

def Cat.d.whiskers() -> String:
  Cat.both("M 14.6 31.2 L 8.4 29.8 M 14.8 33.6 L 8.8 34.4")

def Cat.d.muzzle() -> String:
  "M 32 31.2 C 35.2 30.8 38.8 32 39 35.2 C 39.2 38.4 35.6 40.4 32 40.4 C 28.4 40.4 24.8 38.4 25 35.2 C 25.2 32 28.8 30.8 32 31.2 Z"

def Cat.d.blaze() -> String:
  "M 30.4 31.6 C 30.8 27 31.2 23.5 32 20.5 C 32.8 23.5 33.2 27 33.6 31.6 Z"

def Cat.d.mask() -> String:
  "M 32 30 C 36.6 30 40 32.4 40 35.8 C 40 39.2 36.4 41.2 32 41.2 C 27.6 41.2 24 39.2 24 35.8 C 24 32.4 27.4 30 32 30 Z"

def Cat.d.bridge() -> String:
  "M 29.8 30 C 30.4 26 31 23.4 32 22 C 33 23.4 33.6 26 34.2 30 Z"

def Cat.d.tabby.head() -> String:
  "M 30.9 13.6 L 33.1 13.6 L 32.6 19.2 Q 32 20.3 31.4 19.2 Z "
    ++ Cat.both("M 25.4 14.6 L 27.8 14 L 28.8 18.6 Q 28.5 19.6 27.7 19 Z M 14.1 27.2 L 19.4 28.3 Q 19.9 29 19.2 29.3 L 14.1 29.6 Z M 14.4 31.2 L 18.6 31.6 Q 19.2 32.2 18.5 32.5 L 14.9 33.6 Z")

def Cat.d.tabby.body() -> String:
  Cat.both("M 18.6 46.3 L 23 47.5 Q 23.6 48.3 22.8 48.6 L 18.4 49.3 Z M 18.2 52 L 22.2 52.8 Q 22.8 53.6 22 53.9 L 18.3 55 Z")

def Cat.d.calico.a() -> String:
  "M 15 24 C 16.5 17 23 13.5 32 13.5 C 31 18 28 22.5 23.5 24.5 C 20 26 17 27.2 14.65 26 L 15 24 Z"

def Cat.d.calico.b() -> String:
  "M 39.36 14.45 C 44.45 15.92 47.95 19.1 49 24 C 46 26 41.5 25.5 39.5 22 C 38.5 20 38.6 16.5 39.36 14.45 Z"

def Cat.d.calico.body() -> String:
  "M 18.2 50.5 C 19 43 23.5 36 32 36 C 29 39 27.5 42 26.5 46 C 25.5 50 22.5 53 18.07 52.25 L 18.2 50.5 Z"

# Parts
# -----

def Cat.when(-A: Data, b: Bool, xs: List<&2, A>) -> List<&2, A>:
  match b:
    case True{}:
      xs
    case False{}:
      Nil{}

def Cat.either(-A: Data, b: Bool, xs: List<&2, A>, ys: List<&2, A>) -> List<&2, A>:
  match b:
    case True{}:
      xs
    case False{}:
      ys

def Cat.fill(name: String, d: String, +fill: U32, +alpha: U32, anims: List<&2, Anim>) -> Part:
  Part{name, d, fill, Cat.none(), 0.0, alpha, anims}

def Cat.solid(name: String, d: String, +fill: U32, +line: U32, +lw: F32, anims: List<&2, Anim>) -> Part:
  Part{name, d, fill, line, lw, 255, anims}

def Cat.line(name: String, d: String, +line: U32, +lw: F32, +alpha: U32, anims: List<&2, Anim>) -> Part:
  Part{name, d, Cat.none(), line, lw, alpha, anims}

def Cat.lw() -> F32:
  1.4

# colour a when the pattern is k, else b
def Cat.pc(+pat: U32, +k: U32, +a: U32, +b: U32) -> U32:
  Bool.pick(U32, U32.is_eq(pat, k), a, b)

def Cat.ext(-A: Data, xs: List<&2, A>, ys: List<&2, A>) -> List<&2, A>:
  List.append(&2, A, xs, ys)

# Animations by mood
# ------------------

def Cat.a(+kind: U32, +from: F32, +to: F32, +px: F32, +py: F32, +per: U32, +delay: U32, +ease: U32) -> List<&2, Anim>:
  [Anim{kind, from, to, px, py, per, delay, ease}]

def Cat.pick(+m: U32, +k: U32, xs: List<&2, Anim>, ys: List<&2, Anim>) -> List<&2, Anim>:
  Cat.either(Anim, U32.is_eq(m, k), xs, ys)

# the whole cat (waiting: a bounce)
def Cat.g.all(+m: U32) -> List<&2, Anim>:
  Cat.pick(m, 4, Cat.a(3, 0.0, F32.neg(1.6), 32.0, 60.0, 760, 0, 0), Nil{})

# the head, ears and face
def Cat.g.head(+m: U32) -> List<&2, Anim>:
  Cat.pick(m, 0, Cat.a(3, 1.4, 2.0, 32.0, 42.0, 3600, 0, 0),
    Cat.pick(m, 1, Cat.a(3, 0.0, 0.5, 32.0, 42.0, 3200, 0, 0),
      Cat.pick(m, 2, Cat.a(3, 0.3, 0.8, 32.0, 42.0, 1400, 0, 0),
        Cat.pick(m, 3, Cat.a(1, F32.neg(3.0), 7.0, 32.0, 42.0, 3200, 0, 0),
          Cat.pick(m, 5, Cat.a(1, F32.neg(2.5), 2.5, 32.0, 42.0, 1600, 0, 0),
            Cat.pick(m, 6, Cat.a(3, 1.2, 1.2, 32.0, 42.0, 1000, 0, 0), Nil{}))))))

# the eyes (a blink)
def Cat.g.eyes(+m: U32) -> List<&2, Anim>:
  Cat.pick(m, 1, Cat.a(5, 1.0, 0.1, 32.0, 28.4, 4200, 1200, 1),
    Cat.pick(m, 2, Cat.a(5, 1.0, 0.1, 32.0, 28.4, 3400, 600, 1),
      Cat.pick(m, 3, Cat.a(5, 1.0, 0.1, 32.0, 28.4, 5000, 1800, 1),
        Cat.pick(m, 4, Cat.a(5, 1.0, 0.1, 32.0, 28.4, 6000, 900, 1),
          Cat.pick(m, 5, Cat.a(5, 1.0, 0.1, 32.0, 28.4, 3800, 1500, 1), Nil{})))))

def Cat.g.tail(+m: U32) -> List<&2, Anim>:
  Cat.pick(m, 1, Cat.a(1, F32.neg(4.0), 10.0, 42.5, 60.0, 3000, 0, 0),
    Cat.pick(m, 2, Cat.a(1, F32.neg(5.0), 5.0, 42.5, 60.0, 1400, 0, 0),
      Cat.pick(m, 3, Cat.a(1, 0.0, 16.0, 42.5, 60.0, 2200, 400, 1),
        Cat.pick(m, 4, Cat.a(1, F32.neg(8.0), 8.0, 42.5, 60.0, 760, 190, 0),
          Cat.pick(m, 5, Cat.a(1, F32.neg(3.0), 8.0, 42.5, 60.0, 2400, 0, 0), Nil{})))))

def Cat.g.body(+m: U32) -> List<&2, Anim>:
  Cat.pick(m, 0, Cat.a(5, 1.0, 1.035, 32.0, 61.0, 3600, 0, 0), Nil{})

# one ear: side 0 left, 1 right (the pivot is the ear's base)
def Cat.g.ear(+m: U32, +right: Bool) -> List<&2, Anim>:
  +px = Bool.pick(F32, right, 43.0, 21.0)
  +sg = Bool.pick(F32, right, 1.0, F32.neg(1.0))
  Cat.pick(m, 0, Cat.a(1, F32.mul(sg, 8.0), F32.mul(sg, 8.0), px, 18.0, 1000, 0, 0),
    Cat.pick(m, 1, Cat.a(1, 0.0, F32.mul(sg, 14.0), px, 18.0, Bool.pick(U32, right, 7100, 5300), Bool.pick(U32, right, 2000, 0), 1),
      Cat.pick(m, 2, Cat.a(1, 0.0, F32.mul(sg, 10.0), px, 18.0, Bool.pick(U32, right, 6300, 4100), 0, 1),
        Cat.pick(m, 4, Cat.a(5, 1.04, 1.14, px, 20.0, 760, 0, 0),
          Cat.pick(m, 6, Cat.a(1, F32.mul(sg, 30.0), F32.mul(sg, 30.0), px, 19.0, 1000, 0, 0), Nil{})))))

# Building
# --------

def Cat.tail(+pat: U32, +fur: U32, +fur2: U32, +light: U32, +line: U32, +an: List<&2, Anim>) -> List<&2, Part>:
  +tc = Cat.pc(pat, 4, fur2, Cat.pc(pat, 5, fur2, fur))
  Cat.ext(Part, [Cat.fill("tail", Cat.d.tail(), tc, 255, an)],
    Cat.ext(Part, Cat.when(Part, Bool.or(U32.is_eq(pat, 1), U32.is_eq(pat, 5)), [Cat.fill("tail tip", Cat.d.tail.tip(), Cat.pc(pat, 5, light, fur2), 255, an)]),
      [Cat.line("tail line", Cat.d.tail(), line, Cat.lw(), 255, an)]))

def Cat.body(+pat: U32, +fur: U32, +fur2: U32, +light: U32, +line: U32, +an: List<&2, Anim>) -> List<&2, Part>:
  List.concat(&2, Part, [
    [Cat.fill("body", Cat.d.body(), fur, 255, an)],
    Cat.when(Part, Bool.or(U32.is_eq(pat, 1), Bool.or(U32.is_eq(pat, 2), U32.is_eq(pat, 3))), [Cat.fill("chest", Cat.d.chest(), light, 255, an)]),
    Cat.when(Part, U32.is_eq(pat, 1), [Cat.fill("stripes", Cat.d.tabby.body(), fur2, 255, an)]),
    Cat.when(Part, U32.is_eq(pat, 5), [Cat.fill("patch", Cat.d.calico.body(), fur2, 255, an), Cat.fill("spot", Cat.ell(40.5, 52.0, 2.6, 2.2), light, 255, an)]),
    [Cat.line("body line", Cat.d.body(), line, Cat.lw(), 255, an)]])

def Cat.collar(+collar: U32, +line: U32, +an: List<&2, Anim>) -> List<&2, Part>:
  [Cat.solid("collar", Cat.d.collar(), collar, line, 0.9, an),
   Cat.solid("bell", Cat.ell(32.0, 46.6, 1.9, 1.9), Cat.hex("F6C544"), Cat.hex("9A6B12"), 0.7, an)]

def Cat.paws(+pc: U32, +line: U32, +an: List<&2, Anim>) -> List<&2, Part>:
  [Cat.solid("paws", Cat.ell(26.8, 60.3, 4.1, 2.7) ++ " " ++ Cat.ell(37.2, 60.3, 4.1, 2.7), pc, line, 1.2, an),
   Cat.line("toes", "M 25.9 59.6 L 25.9 61.3 M 27.9 59.6 L 27.9 61.3 M 36.1 59.6 L 36.1 61.3 M 38.1 59.6 L 38.1 61.3", line, 0.6, 200, an)]

def Cat.ear(+name: String, +d: String, +din: String, +fc: U32, +ear: U32, +line: U32, +an: List<&2, Anim>) -> List<&2, Part>:
  [Cat.solid(name, d, fc, line, Cat.lw(), an), Cat.fill(name ++ " inside", din, ear, 255, an)]

def Cat.ears(+m: U32, +pat: U32, +fur: U32, +fur2: U32, +light: U32, +ear: U32, +line: U32, +an: List<&2, Anim>) -> List<&2, Part>:
  +lc = Cat.pc(pat, 4, fur2, Cat.pc(pat, 5, fur2, fur))
  +rc = Cat.pc(pat, 4, fur2, Cat.pc(pat, 5, light, fur))
  Cat.ext(Part, Cat.ear("left ear", Cat.d.ear(), Cat.d.ear.in(), lc, ear, line, Cat.ext(Anim, an, Cat.g.ear(m, False{}))),
    Cat.ear("right ear", Cat.mir(Cat.d.ear()), Cat.mir(Cat.d.ear.in()), rc, ear, line, Cat.ext(Anim, an, Cat.g.ear(m, True{}))))

def Cat.head(+pat: U32, +fur: U32, +fur2: U32, +light: U32, +line: U32, +an: List<&2, Anim>) -> List<&2, Part>:
  List.concat(&2, Part, [
    [Cat.fill("head", Cat.d.head(), fur, 255, an)],
    Cat.when(Part, U32.is_eq(pat, 1), [Cat.fill("head stripes", Cat.d.tabby.head(), fur2, 255, an)]),
    Cat.when(Part, U32.is_eq(pat, 3), [Cat.fill("blaze", Cat.d.blaze(), light, 255, an), Cat.fill("muzzle", Cat.d.muzzle(), light, 255, an)]),
    Cat.when(Part, U32.is_eq(pat, 4), [Cat.fill("mask", Cat.d.mask(), fur2, 150, an), Cat.fill("bridge", Cat.d.bridge(), fur2, 130, an)]),
    Cat.when(Part, U32.is_eq(pat, 5), [Cat.fill("patch", Cat.d.calico.a(), fur2, 255, an), Cat.fill("patch 2", Cat.d.calico.b(), light, 255, an)]),
    [Cat.line("head line", Cat.d.head(), line, Cat.lw(), 255, an)]])

# open eyes; (dx, dy) moves the pupils, big widens them
def Cat.eye(+name: String, +cx: F32, +iris: U32, +dx: F32, +dy: F32, +big: Bool, +an: List<&2, Anim>) -> List<&2, Part>:
  +px = F32.add(cx, dx)
  [Cat.solid(name, Cat.ell(cx, 28.4, 4.2, 4.6), iris, Cat.hex("1B1722"), 0.6, an),
   Cat.fill(name ++ " pupil", Cat.ell(px, F32.add(27.9, dy), Bool.pick(F32, big, 3.2, 2.8), Bool.pick(F32, big, 3.6, 3.3)), Cat.hex("1B1722"), 255, an),
   Cat.fill(name ++ " shine", Cat.ell(F32.add(px, 1.2), F32.add(26.4, dy), 1.2, 1.2) ++ " " ++ Cat.ell(F32.sub(px, 1.3), F32.add(30.2, dy), 0.6, 0.6), Cat.hex("FFFFFF"), 255, an)]

def Cat.eyes.open(+eye: U32, +eye2: U32, +dx: F32, +dy: F32, +big: Bool, +an: List<&2, Anim>) -> List<&2, Part>:
  Cat.ext(Part, Cat.eye("left eye", 24.5, eye, dx, dy, big, an), Cat.eye("right eye", 39.5, eye2, dx, dy, big, an))

def Cat.eyes(+m: U32, +eye: U32, +eye2: U32, +line: U32, +an: List<&2, Anim>) -> List<&2, Part>:
  Cat.either(Part, U32.is_eq(m, 0), [Cat.line("eyes", Cat.both("M 21.2 28.4 Q 24.5 31.6 27.8 28.4"), line, 1.3, 255, an)],
    Cat.either(Part, U32.is_eq(m, 6), [Cat.line("eyes", Cat.both("M 22.3 26.3 L 26.7 30.7 M 26.7 26.3 L 22.3 30.7"), line, 1.4, 255, an)],
      Cat.either(Part, U32.is_eq(m, 7), [Cat.line("eyes", Cat.both("M 21.4 29.2 Q 24.5 30.4 27.6 29.2"), line, 1.3, 255, an)],
        Cat.eyes.open(eye, eye2, Bool.pick(F32, U32.is_eq(m, 3), 0.7, 0.0), Bool.pick(F32, U32.is_eq(m, 2), 1.0, Bool.pick(F32, U32.is_eq(m, 3), F32.neg(0.9), 0.0)),
          U32.is_eq(m, 4), Cat.ext(Anim, an, Cat.g.eyes(m))))))

def Cat.mouth(+m: U32, +line: U32, +an: List<&2, Anim>) -> List<&2, Part>:
  Cat.either(Part, U32.is_eq(m, 5),
    [Cat.line("mouth", "M 32 34.8 L 32 35.4", line, 0.9, 255, an),
     Cat.fill("open mouth", "M 30 35.4 Q 32 34.9 34 35.4 Q 34 38.6 32 38.8 Q 30 38.6 30 35.4 Z", Cat.hex("3A1E28"), 255, Cat.ext(Anim, an, Cat.a(5, 0.35, 1.0, 32.0, 35.2, 440, 0, 0))),
     Cat.fill("tongue", "M 30.9 37.6 Q 32 36.9 33.1 37.6 Q 32.8 38.6 32 38.7 Q 31.2 38.6 30.9 37.6 Z", Cat.hex("F07A8C"), 255, Cat.ext(Anim, an, Cat.a(5, 0.35, 1.0, 32.0, 35.2, 440, 0, 0)))],
    Cat.either(Part, U32.is_eq(m, 6), [Cat.line("mouth", "M 29.6 36.8 Q 32 34.6 34.4 36.8", line, 0.9, 255, an)],
      Cat.either(Part, U32.is_eq(m, 4), [Cat.line("mouth", "M 32 34.8 L 32 35.3", line, 0.9, 255, an), Cat.fill("open mouth", Cat.ell(32.0, 36.7, 1.1, 1.3), Cat.hex("3A1E28"), 255, an)],
        [Cat.line("mouth", Cat.d.mouth(), line, 0.9, 255, an)])))

def Cat.face(+m: U32, +eye: U32, +eye2: U32, +nose: U32, +line: U32, +whisk: U32, +an: List<&2, Anim>) -> List<&2, Part>:
  List.concat(&2, Part, [
    Cat.when(Part, Bool.not(U32.is_eq(m, 7)), [Cat.fill("blush", Cat.ell(19.6, 33.8, 2.5, 1.4) ++ " " ++ Cat.ell(44.4, 33.8, 2.5, 1.4), Cat.hex("FF8FA3"), 90, an)]),
    Cat.eyes(m, eye, eye2, line, an),
    [Cat.fill("nose", Cat.d.nose(), nose, 255, an)],
    Cat.mouth(m, line, an),
    [Cat.line("whiskers", Cat.d.whiskers(), whisk, 0.6, 170, an)]])

# the laptop a working cat types on
def Cat.laptop(+pc: U32, +line: U32, +an: List<&2, Anim>) -> List<&2, Part>:
  [Cat.solid("laptop", "M 19.5 45 L 44.5 45 Q 45.5 45 45.5 46 L 45.5 56.5 L 18.5 56.5 L 18.5 46 Q 18.5 45 19.5 45 Z", Cat.hex("3B4150"), Cat.hex("1E222B"), 1.0, an),
   Cat.fill("logo", Cat.ell(32.0, 50.7, 1.8, 1.8), Cat.hex("9FE3FF"), 255, Cat.ext(Anim, an, Cat.a(6, 0.55, 1.0, 32.0, 50.7, 2000, 0, 0))),
   Cat.solid("keyboard", "M 14 56.5 L 50 56.5 L 51.5 59.5 L 12.5 59.5 Z", Cat.hex("A7B0BF"), Cat.hex("5B6272"), 0.8, an),
   Cat.solid("left paw", Cat.ell(26.5, 45.4, 3.7, 2.6), pc, line, 1.2, Cat.ext(Anim, an, Cat.a(3, 0.0, F32.neg(1.8), 26.5, 45.4, 380, 0, 0))),
   Cat.solid("right paw", Cat.ell(37.5, 45.4, 3.7, 2.6), pc, line, 1.2, Cat.ext(Anim, an, Cat.a(3, 0.0, F32.neg(1.8), 37.5, 45.4, 380, 190, 0)))]

def Cat.zs() -> List<&2, Part>:
  [Cat.line("z", "M 50.5 15 L 54.5 15 L 50.5 19 L 54.5 19", Cat.hex("C9D2E6"), 1.3, 255,
     [Anim{3, 0.0, F32.neg(4.0), 52.5, 17.0, 3200, 2080, 2}, Anim{6, 0.0, 1.0, 52.5, 17.0, 3200, 2080, 0}]),
   Cat.line("z 2", "M 55.5 5 L 60.5 5 L 55.5 10 L 60.5 10", Cat.hex("C9D2E6"), 1.5, 255,
     [Anim{3, 0.0, F32.neg(4.0), 58.0, 7.5, 3200, 480, 2}, Anim{6, 0.0, 1.0, 58.0, 7.5, 3200, 480, 0}])]

def Cat.alert() -> List<&2, Part>:
  +an = {[Anim{4, 1.0, 1.12, 56.5, 9.0, 760, 0, 0}, Anim{5, 1.0, 1.12, 56.5, 9.0, 760, 0, 0}] : List<&2, Anim>}
  [Cat.fill("bubble tail", "M 52 12.5 L 49.6 18.2 L 55.4 14.4 Z", Cat.hex("FFB224"), 255, an),
   Cat.fill("bubble", Cat.ell(56.5, 9.0, 6.6, 6.6), Cat.hex("FFB224"), 255, an),
   Cat.fill("mark", "M 55.3 4.2 Q 56.5 3.6 57.7 4.2 L 57.1 10.6 Q 56.5 11.1 55.9 10.6 Z " ++ Cat.ell(56.5, 13.0, 1.1, 1.1), Cat.hex("3A2200"), 255, an)]

def Cat.speech() -> List<&2, Part>:
  [Cat.fill("bubble", "M 52.5 2 L 61 2 Q 63.5 2 63.5 4.5 L 63.5 10.5 Q 63.5 13 61 13 L 55.5 13 L 50.8 16.8 L 52.4 13 Q 50 13 50 10.5 L 50 4.5 Q 50 2 52.5 2 Z", Cat.hex("F4F1EA"), 255, Nil{}),
   Cat.fill("dot", Cat.ell(53.4, 7.5, 1.1, 1.1), Cat.hex("3B3747"), 255, Cat.a(6, 0.25, 1.0, 53.4, 7.5, 900, 0, 0)),
   Cat.fill("dot 2", Cat.ell(56.75, 7.5, 1.1, 1.1), Cat.hex("3B3747"), 255, Cat.a(6, 0.25, 1.0, 56.75, 7.5, 900, 150, 0)),
   Cat.fill("dot 3", Cat.ell(60.1, 7.5, 1.1, 1.1), Cat.hex("3B3747"), 255, Cat.a(6, 0.25, 1.0, 60.1, 7.5, 900, 300, 0))]

def Cat.thought() -> List<&2, Part>:
  [Cat.fill("thought", Cat.ell(51.5, 17.5, 1.3, 1.3), Cat.hex("E9E6F0"), 255, Cat.a(6, 0.3, 1.0, 51.5, 17.5, 1500, 0, 0)),
   Cat.fill("thought 2", Cat.ell(54.8, 12.2, 1.9, 1.9), Cat.hex("E9E6F0"), 255, Cat.a(6, 0.3, 1.0, 54.8, 12.2, 1500, 250, 0)),
   Cat.fill("thought 3", Cat.ell(59.3, 5.8, 2.8, 2.8), Cat.hex("E9E6F0"), 255, Cat.a(6, 0.3, 1.0, 59.3, 5.8, 1500, 500, 0))]

def Cat.cloud() -> List<&2, Part>:
  +an = Cat.a(3, 0.0, F32.neg(1.0), 56.0, 8.0, 2000, 0, 0)
  [Cat.fill("bolt", "M 56.5 11.5 L 54.6 15.6 L 56.3 15.6 L 55.1 18.8 L 58.4 14.3 L 56.7 14.3 L 57.9 11.5 Z", Cat.hex("FFD23F"), 255, an),
   Cat.fill("cloud", "M 52 12 Q 49 12 49 9.5 Q 49 7 51.8 7 Q 52.5 3.5 56 3.5 Q 59.5 3.5 60.2 6.8 Q 63 7 63 9.5 Q 63 12 60 12 Z", Cat.hex("8A93A6"), 255, an)]

def Cat.extras(+m: U32) -> List<&2, Part>:
  Cat.either(Part, U32.is_eq(m, 0), Cat.zs(),
    Cat.either(Part, U32.is_eq(m, 3), Cat.thought(),
      Cat.either(Part, U32.is_eq(m, 4), Cat.alert(),
        Cat.either(Part, U32.is_eq(m, 5), Cat.speech(),
          Cat.either(Part, U32.is_eq(m, 6), Cat.cloud(), Nil{})))))

def Cat.rig.k(lk: Look, +m: U32) -> List<&2, Part>:
  match lk:
    case Look{_, _, +pat, +fur, +fur2, +light, +ear, +nose, +eye, +eye2, +line, +whisk, +collar}:
      +all = Cat.g.all(m)
      +head = Cat.ext(Anim, all, Cat.g.head(m))
      +pc = Cat.pc(pat, 3, light, Cat.pc(pat, 4, fur2, fur))
      List.concat(&2, Part, [
        Cat.tail(pat, fur, fur2, light, line, Cat.ext(Anim, all, Cat.g.tail(m))),
        Cat.body(pat, fur, fur2, light, line, Cat.ext(Anim, all, Cat.g.body(m))),
        Cat.collar(collar, line, all),
        Cat.when(Part, Bool.not(U32.is_eq(m, 2)), Cat.paws(pc, line, all)),
        Cat.ears(m, pat, fur, fur2, light, ear, line, head),
        Cat.head(pat, fur, fur2, light, line, head),
        Cat.face(m, eye, eye2, nose, line, whisk, head),
        Cat.when(Part, U32.is_eq(m, 2), Cat.laptop(pc, line, all)),
        Cat.extras(m)])

# how many animations the parts carry
def Cat.anims.count(ps: List<&2, Part>) -> Nat:
  match ps:
    case Nil{}:
      0n
    case Part{_, _, _, _, _, _, as} <> t:
      Nat.add(List.length(&2, Anim, as), Cat.anims.count(t))

def Cat.grey.part(p: Part) -> Part:
  match p:
    case Part{name, d, +fill, +line, lw, alpha, _}:
      Part{name, d, Cat.grey(fill), Cat.grey(line), lw, alpha, Nil{}}

def Cat.grey.all(ps: List<&2, Part>) -> List<&2, Part>:
  match ps:
    case Nil{}:
      Nil{}
    case p <> t:
      Cat.grey.part(p) <> Cat.grey.all(t)

def Cat.rig.m(+look: Nat, +m: U32) -> List<&2, Part>:
  Cat.either(Part, U32.is_eq(m, 7), Cat.grey.all(Cat.rig.k(Cat.look(look), m)), Cat.rig.k(Cat.look(look), m))

# the cat's parts, back to front, for a look seed and a mood
def Cat.rig(+look: Nat, +mood: String) -> List<&2, Part>:
  Cat.rig.m(look, Cat.mood(mood))

# JSON (phones)
# -------------

def Cat.kind.name(+k: U32) -> String:
  Bool.pick(String, U32.is_eq(k, 1), "rot", Bool.pick(String, U32.is_eq(k, 2), "tx", Bool.pick(String, U32.is_eq(k, 3), "ty",
    Bool.pick(String, U32.is_eq(k, 4), "sx", Bool.pick(String, U32.is_eq(k, 5), "sy", "op")))))

def Cat.ease.name(+e: U32) -> String:
  Bool.pick(String, U32.is_eq(e, 1), "blink", Bool.pick(String, U32.is_eq(e, 2), "saw", "io"))

def Cat.jn(+v: F32) -> J.Json:
  J.Num{Cat.n(v)}

def Cat.jc(+c: U32) -> J.Json:
  Bool.pick(J.Json, U32.is_ge(c, Cat.none()), J.Null{}, J.Json.u32(c))

def Cat.anim.json(a: Anim) -> J.Json:
  match a:
    case Anim{+k, +from, +to, +px, +py, +per, +delay, +ease}:
      J.Json.obj([J.KV{"k", J.Str{Cat.kind.name(k)}}, J.KV{"from", Cat.jn(from)}, J.KV{"to", Cat.jn(to)},
        J.KV{"px", Cat.jn(px)}, J.KV{"py", Cat.jn(py)}, J.KV{"per", J.Json.u32(per)}, J.KV{"delay", J.Json.u32(delay)},
        J.KV{"ease", J.Str{Cat.ease.name(ease)}}])

def Cat.anims.json(as: List<&2, Anim>) -> List<&2, J.Json>:
  match as:
    case Nil{}:
      Nil{}
    case a <> t:
      Cat.anim.json(a) <> Cat.anims.json(t)

def Cat.part.json(p: Part) -> J.Json:
  match p:
    case Part{name, d, +fill, +line, +lw, +alpha, anims}:
      J.Json.obj([J.KV{"name", J.Str{name}}, J.KV{"d", J.Str{d}}, J.KV{"fill", Cat.jc(fill)}, J.KV{"stroke", Cat.jc(line)},
        J.KV{"sw", Cat.jn(lw)}, J.KV{"alpha", J.Json.u32(alpha)}, J.KV{"anims", J.Json.arr(Cat.anims.json(anims))}])

def Cat.parts.json(ps: List<&2, Part>) -> List<&2, J.Json>:
  match ps:
    case Nil{}:
      Nil{}
    case p <> t:
      Cat.part.json(p) <> Cat.parts.json(t)

# the rig as a JSON array of parts:
#   {"name", "d", "fill": 0xRRGGBB | null, "stroke": 0xRRGGBB | null,
#    "sw": width, "alpha": 0..255,
#    "anims": [{"k": "rot"|"tx"|"ty"|"sx"|"sy"|"op", "from", "to", "px",
#               "py", "per": ms, "delay": ms, "ease": "io"|"blink"|"saw"}]}
def Cat.rig.json(+look: Nat, +mood: String) -> J.Json:
  J.Json.arr(Cat.parts.json(Cat.rig(look, mood)))

# SVG (web)
# ---------

def Cat.anim.off(+per: U32, +delay: U32) -> U32:
  +p = U32.max(per, 1)
  U32.mod((p - U32.mod(delay, p) : U32), p)

def Cat.svg.val(+k: U32, +v: F32, +px: F32, +py: F32) -> String:
  Bool.pick(String, U32.is_eq(k, 1), Cat.n(v) ++ " " ++ Cat.xy(px, py), Bool.pick(String, U32.is_eq(k, 2), Cat.n(v) ++ " 0",
    Bool.pick(String, U32.is_eq(k, 3), "0 " ++ Cat.n(v), Bool.pick(String, U32.is_eq(k, 4), Cat.n(v) ++ " 1",
      Bool.pick(String, U32.is_eq(k, 5), "1 " ++ Cat.n(v), Cat.n(v))))))

def Cat.svg.ease(+e: U32, +a: String, +b: String) -> String:
  Bool.pick(String, U32.is_eq(e, 1), "values='" ++ a ++ ";" ++ a ++ ";" ++ b ++ ";" ++ a ++ "' keyTimes='0;0.94;0.97;1' calcMode='spline' keySplines='0 0 1 1;0.37 0 0.63 1;0.37 0 0.63 1'",
    Bool.pick(String, U32.is_eq(e, 2), "values='" ++ a ++ ";" ++ b ++ "' keyTimes='0;1' calcMode='linear'",
      "values='" ++ a ++ ";" ++ b ++ ";" ++ a ++ "' keyTimes='0;0.5;1' calcMode='spline' keySplines='0.37 0 0.63 1;0.37 0 0.63 1'"))

def Cat.svg.timing(+k: U32, +from: F32, +to: F32, +px: F32, +py: F32, +per: U32, +delay: U32, +e: U32) -> String:
  Cat.svg.ease(e, Cat.svg.val(k, from, px, py), Cat.svg.val(k, to, px, py)) ++ " dur='" ++ U32.show(U32.max(per, 1)) ++ "ms' begin='-"
    ++ U32.show(Cat.anim.off(per, delay)) ++ "ms' repeatCount='indefinite'"

def Cat.svg.type(+k: U32) -> String:
  Bool.pick(String, U32.is_eq(k, 1), "rotate", Bool.pick(String, Bool.or(U32.is_eq(k, 2), U32.is_eq(k, 3)), "translate", "scale"))

def Cat.svg.open(a: Anim) -> String:
  match a:
    case Anim{+k, +from, +to, +px, +py, +per, +delay, +e}:
      +tm = Cat.svg.timing(k, from, to, px, py, per, delay, e)
      Bool.pick(String, U32.is_eq(k, 6), "<g><animate attributeName='opacity' " ++ tm ++ "/>",
        Bool.pick(String, Bool.or(U32.is_eq(k, 4), U32.is_eq(k, 5)),
          "<g transform='translate(" ++ Cat.xy(px, py) ++ ")'><g><animateTransform attributeName='transform' type='scale' " ++ tm ++ "/><g transform='translate(" ++ Cat.xy(F32.neg(px), F32.neg(py)) ++ ")'>",
          "<g><animateTransform attributeName='transform' type='" ++ Cat.svg.type(k) ++ "' " ++ tm ++ "/>"))

def Cat.svg.close(a: Anim) -> String:
  match a:
    case Anim{+k, _, _, _, _, _, _, _}:
      Bool.pick(String, Bool.or(U32.is_eq(k, 4), U32.is_eq(k, 5)), "</g></g></g>", "</g>")

def Cat.svg.wrap(as: List<&2, Anim>, inner: String) -> String:
  match as:
    case Nil{}:
      inner
    case +a <> t:
      Cat.svg.open(a) ++ Cat.svg.wrap(t, inner) ++ Cat.svg.close(a)

def Cat.svg.path(d: String, +fill: U32, +line: U32, +lw: F32, +alpha: U32) -> String:
  "<path d='" ++ d ++ "'"
    ++ Bool.pick(String, U32.is_ge(fill, Cat.none()), " fill='none'", " fill='" ++ Cat.css(fill) ++ "' fill-rule='evenodd'")
    ++ Bool.pick(String, U32.is_ge(line, Cat.none()), "", " stroke='" ++ Cat.css(line) ++ "' stroke-width='" ++ Cat.n(lw) ++ "' stroke-linecap='round' stroke-linejoin='round'")
    ++ Bool.pick(String, U32.is_ge(alpha, 255), "", " opacity='" ++ Cat.n(F32.div(U32.to_f32(alpha), 255.0)) ++ "'")
    ++ "/>"

def Cat.svg.part(p: Part) -> String:
  match p:
    case Part{_, d, +fill, +line, +lw, +alpha, anims}:
      Cat.svg.wrap(anims, Cat.svg.path(d, fill, line, lw, alpha))

def Cat.svg.parts(ps: List<&2, Part>) -> List<&2, String>:
  match ps:
    case Nil{}:
      Nil{}
    case p <> t:
      Cat.svg.part(p) <> Cat.svg.parts(t)

# one animated SVG document of px x px
def Cat.svg(+look: Nat, +mood: String, +px: U32) -> String:
  "<svg xmlns='http://www.w3.org/2000/svg' width='" ++ U32.show(px) ++ "' height='" ++ U32.show(px) ++ "' viewBox='0 0 64 64'>"
    ++ String.concat(Cat.svg.parts(Cat.rig(look, mood))) ++ "</svg>"

# a character as it goes into a data: URI, written backwards
def Cat.uri.chr(+c: U32) -> String:
  Bool.pick(String, U32.is_eq(c, 35), "32%", Bool.pick(String, U32.is_eq(c, 60), "C3%",
    Bool.pick(String, U32.is_eq(c, 62), "E3%", Bool.pick(String, U32.is_eq(c, 34), "22%",
      Bool.pick(String, U32.is_eq(c, 37), "52%", Bool.pick(String, U32.is_eq(c, 10), "A0%", SCon{Chr{c}, ""}))))))

def Cat.uri.rev(s: String, acc: String) -> String:
  match s:
    case SNil{}:
      acc
    case SCon{Chr{+c}, t}:
      Cat.uri.rev(t, Cat.uri.chr(c) ++ acc)

# text escaped for a data: URI (# < > " % and newlines)
def Cat.uri(s: String) -> String:
  String.reverse(Cat.uri.rev(s, ""))

def Cat.data_uri(+look: Nat, +mood: String, +px: U32) -> String:
  "data:image/svg+xml;utf8," ++ Cat.uri(Cat.svg(look, mood, px))

# Flattening (window)
# -------------------

def Cat.steps() -> Nat:
  6n

# the pen, where its subpath began, the subpath's points (newest first) and
# the finished rings
type Fz is Data:
  Fz{x: F32, y: F32, sx: F32, sy: F32, cur: List<&2, S.Pt>, out: List<&2, Ring>}

def Fz.ring(+cur: List<&2, S.Pt>, +closed: Bool, out: List<&2, Ring>) -> List<&2, Ring>:
  match cur:
    case _ <> _ <> _:
      Ring{List.reverse(&2, S.Pt, cur), closed} <> out
    case _:
      out

def Fz.cub(i: Nat, +n: F32, +x0: F32, +y0: F32, +x1: F32, +y1: F32, +x2: F32, +y2: F32, +x3: F32, +y3: F32, acc: List<&2, S.Pt>) -> List<&2, S.Pt>:
  match i:
    case 0n:
      acc
    case 1n+j0:
      +j = j0
      +t = F32.div(F32.from_nat(1n+j), n)
      S.Pt{S.Bez.c1(t, x0, x1, x2, x3), S.Bez.c1(t, y0, y1, y2, y3)} <> Fz.cub(j, n, x0, y0, x1, y1, x2, y2, x3, y3, acc)

def Fz.quad(i: Nat, +n: F32, +x0: F32, +y0: F32, +x1: F32, +y1: F32, +x2: F32, +y2: F32, acc: List<&2, S.Pt>) -> List<&2, S.Pt>:
  match i:
    case 0n:
      acc
    case 1n+j0:
      +j = j0
      +t = F32.div(F32.from_nat(1n+j), n)
      S.Pt{S.Bez.q1(t, x0, x1, x2), S.Bez.q1(t, y0, y1, y2)} <> Fz.quad(j, n, x0, y0, x1, y1, x2, y2, acc)

def Fz.seg(f: Fz, s: S.Seg) -> Fz:
  match f s:
    case Fz{_, _, _, _, +cur, out} S.SM{+x, +y}:
      Fz{x, y, x, y, [S.Pt{x, y}], Fz.ring(cur, False{}, out)}
    case Fz{_, _, sx, sy, cur, out} S.SL{+x, +y}:
      Fz{x, y, sx, sy, S.Pt{x, y} <> cur, out}
    case Fz{+px, +py, sx, sy, cur, out} S.SC{+x1, +y1, +x2, +y2, +x, +y}:
      Fz{x, y, sx, sy, Fz.cub(Cat.steps(), F32.from_nat(Cat.steps()), px, py, x1, y1, x2, y2, x, y, cur), out}
    case Fz{+px, +py, sx, sy, cur, out} S.SQ{+x1, +y1, +x, +y}:
      Fz{x, y, sx, sy, Fz.quad(Cat.steps(), F32.from_nat(Cat.steps()), px, py, x1, y1, x, y, cur), out}
    case Fz{_, _, sx, sy, cur, out} S.SA{_, _, _, _, _, +x, +y}:
      Fz{x, y, sx, sy, S.Pt{x, y} <> cur, out}
    case Fz{_, _, +sx, +sy, +cur, out} S.SZ{}:
      Fz{sx, sy, sx, sy, [S.Pt{sx, sy}], Fz.ring(cur, True{}, out)}

def Fz.go(ss: List<&2, S.Seg>, f: Fz) -> Fz:
  match ss:
    case Nil{}:
      f
    case s <> t:
      Fz.go(t, Fz.seg(f, s))

def Fz.fin(f: Fz) -> List<&2, Ring>:
  match f:
    case Fz{_, _, _, _, +cur, out}:
      List.reverse(&2, Ring, Fz.ring(cur, False{}, out))

# path data as rings of points (a closing point that repeats the start is
# kept; it adds a zero-length edge)
def Cat.rings(d: String) -> List<&2, Ring>:
  Fz.fin(Fz.go(S.Svg.parse(d), Fz{0.0, 0.0, 0.0, 0.0, Nil{}, Nil{}}))

# the path data of outline-only parts
def Cat.lined(ps: List<&2, Part>) -> List<&2, String>:
  match ps:
    case Nil{}:
      Nil{}
    case Part{_, +d, +fill, +line, _, _, _} <> t:
      List.append(&2, String, Cat.either(String, Bool.and(U32.is_ge(fill, Cat.none()), U32.is_lt(line, Cat.none())), [d], Nil{}), Cat.lined(t))

def Cat.has(xs: List<&2, String>, +d: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case x <> t:
      Bool.or(String.eq(x, d), Cat.has(t, d))

def Cat.flat.part(p: Part, +lined: List<&2, String>) -> FPart:
  match p:
    case Part{_, +d, +fill, +line, lw, +alpha, anims}:
      FPart{fill, line, lw, alpha,
        Bool.and(Bool.and(U32.is_lt(fill, Cat.none()), U32.is_ge(line, Cat.none())), Bool.not(Cat.has(lined, d))),
        anims, Cat.rings(d)}

def Cat.flat.all(ps: List<&2, Part>, +lined: List<&2, String>) -> List<&2, FPart>:
  match ps:
    case Nil{}:
      Nil{}
    case p <> t:
      Cat.flat.part(p, lined) <> Cat.flat.all(t, lined)

def Cat.flat.k(+ps: List<&2, Part>) -> List<&2, FPart>:
  Cat.flat.all(ps, Cat.lined(ps))

# the rig flattened once, for Cat.pose.at
def Cat.flat(+look: Nat, +mood: String) -> List<&2, FPart>:
  Cat.flat.k(Cat.rig(look, mood))

# Posing
# ------

# an affine map: x' = a x + c y + e, y' = b x + d y + f
type Mx is Data:
  Mx{a: F32, b: F32, c: F32, d: F32, e: F32, f: F32}

def Mx.id() -> Mx:
  Mx{1.0, 0.0, 0.0, 1.0, 0.0, 0.0}

# m then n applied first: (m . n)(p) = m(n(p))
def Mx.then(m: Mx, n: Mx) -> Mx:
  match m n:
    case Mx{+a1, +b1, +c1, +d1, +e1, +f1} Mx{+a2, +b2, +c2, +d2, +e2, +f2}:
      Mx{F32.add(F32.mul(a1, a2), F32.mul(c1, b2)), F32.add(F32.mul(b1, a2), F32.mul(d1, b2)),
        F32.add(F32.mul(a1, c2), F32.mul(c1, d2)), F32.add(F32.mul(b1, c2), F32.mul(d1, d2)),
        F32.add(F32.add(F32.mul(a1, e2), F32.mul(c1, f2)), e1), F32.add(F32.add(F32.mul(b1, e2), F32.mul(d1, f2)), f1)}

def Cat.wave(+t: F32) -> F32:
  F32.div(F32.sub(1.0, F32.cos(F32.mul(F32.mul(2.0, F32.pi()), t))), 2.0)

def Cat.eased(+e: U32, +t: F32) -> F32:
  Bool.pick(F32, U32.is_eq(e, 2), t,
    Bool.pick(F32, U32.is_eq(e, 1), Bool.pick(F32, F32.is_lt(t, 0.94), 0.0, Cat.wave(F32.div(F32.sub(t, 0.94), 0.06))), Cat.wave(t)))

# how far through its period an animation is at ms (0 <= t < 1)
def Cat.phase(+ms: Nat, +per: U32, +delay: U32) -> F32:
  +p = U32.to_nat(U32.max(per, 1))
  F32.div(F32.from_nat(Nat.mod(Nat.add(ms, U32.to_nat(Cat.anim.off(per, delay))), p)), F32.from_nat(p))

# an animation's value at ms
def Cat.value(a: Anim, +ms: Nat) -> F32:
  match a:
    case Anim{_, +from, +to, _, _, +per, +delay, +e}:
      F32.add(from, F32.mul(F32.sub(to, from), Cat.eased(e, Cat.phase(ms, per, delay))))

def Cat.mx.k(+k: U32, +v: F32, +px: F32, +py: F32) -> Mx:
  +r = F32.div(F32.mul(v, F32.pi()), 180.0)
  +cs = F32.cos(r)
  +sn = F32.sin(r)
  Bool.pick(Mx, U32.is_eq(k, 1), Mx{cs, sn, F32.neg(sn), cs, F32.add(F32.sub(px, F32.mul(cs, px)), F32.mul(sn, py)), F32.sub(F32.sub(py, F32.mul(sn, px)), F32.mul(cs, py))},
    Bool.pick(Mx, U32.is_eq(k, 2), Mx{1.0, 0.0, 0.0, 1.0, v, 0.0},
      Bool.pick(Mx, U32.is_eq(k, 3), Mx{1.0, 0.0, 0.0, 1.0, 0.0, v},
        Bool.pick(Mx, U32.is_eq(k, 4), Mx{v, 0.0, 0.0, 1.0, F32.sub(px, F32.mul(v, px)), 0.0},
          Bool.pick(Mx, U32.is_eq(k, 5), Mx{1.0, 0.0, 0.0, v, 0.0, F32.sub(py, F32.mul(v, py))}, Mx.id())))))

# an animation's map at ms
def Cat.mx(+a: Anim, +ms: Nat) -> Mx:
  match a:
    case Anim{+k, _, _, +px, +py, _, _, _}:
      Cat.mx.k(k, Cat.value(a, ms), px, py)

# an animation's opacity factor at ms
def Cat.op(+a: Anim, +ms: Nat) -> F32:
  match a:
    case Anim{+k, _, _, _, _, _, _, _}:
      Bool.pick(F32, U32.is_eq(k, 6), Cat.value(a, ms), 1.0)

type Tr is Data:
  Tr{m: Mx, op: F32}

def Tr.go(as: List<&2, Anim>, +ms: Nat, t: Tr) -> Tr:
  match as t:
    case Nil{} _:
      t
    case +a <> rest Tr{m, +op}:
      Tr.go(rest, ms, Tr{Mx.then(m, Cat.mx(a, ms)), F32.mul(op, Cat.op(a, ms))})

def Cat.pt(+m: Mx, p: S.Pt) -> S.Pt:
  match m p:
    case Mx{+a, +b, +c, +d, +e, +f} S.Pt{+x, +y}:
      S.Pt{F32.add(F32.add(F32.mul(a, x), F32.mul(c, y)), e), F32.add(F32.add(F32.mul(b, x), F32.mul(d, y)), f)}

def Cat.pts(ps: List<&2, S.Pt>, +m: Mx) -> List<&2, S.Pt>:
  match ps:
    case Nil{}:
      Nil{}
    case p <> t:
      Cat.pt(m, p) <> Cat.pts(t, m)

def Cat.rings.at(rs: List<&2, Ring>, +m: Mx) -> List<&2, Ring>:
  match rs:
    case Nil{}:
      Nil{}
    case Ring{ps, closed} <> t:
      Ring{Cat.pts(ps, m), closed} <> Cat.rings.at(t, m)

def Cat.shape(+t: Tr, fp: FPart) -> Shape:
  match t fp:
    case Tr{+m, +op} FPart{fill, line, lw, +alpha, rim, _, rs}:
      Shape{fill, line, lw, F32.to_u32(F32.round(F32.mul(U32.to_f32(alpha), F32.clamp(op, 0.0, 1.0)))), rim, Cat.rings.at(rs, m)}

def Cat.pose.part(fp: FPart, +ms: Nat) -> Shape:
  match fp:
    case FPart{fill, line, lw, alpha, rim, +anims, rs}:
      Cat.shape(Tr.go(anims, ms, Tr{Mx.id(), 1.0}), FPart{fill, line, lw, alpha, rim, anims, rs})

# the flattened rig posed at ms (only affine maps: no path work)
def Cat.pose.at(fs: List<&2, FPart>, +ms: Nat) -> List<&2, Shape>:
  match fs:
    case Nil{}:
      Nil{}
    case f <> t:
      Cat.pose.part(f, ms) <> Cat.pose.at(t, ms)

# the cat at ms, as polygons back to front in box units
def Cat.pose(+look: Nat, +mood: String, +ms: Nat) -> List<&2, Shape>:
  Cat.pose.at(Cat.flat(look, mood), ms)
