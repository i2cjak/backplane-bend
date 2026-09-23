import Base
import ./font.bend as F
import ./raster.bend as R
import ./draw.bend as D
import ./fontfx.bend as FX

# System-font text: faces found by fontconfig and rasterized by FreeType
# (fontfx.bend), glyphs cached in Bend state, and draw ops for anti-aliased
# glyph bitmaps (R.SMask). A face that cannot load falls back to the
# Spleen 8x16 bitmap font, so text always draws.
#
# The effect runs only for glyphs missing from the cache: Text.warm fills
# ASCII once per face, Text.ensure fills whatever a new string needs.
# Measuring, wrapping and drawing are pure and read the cache; a glyph
# still missing measures as half an em and draws nothing.

# a cached glyph: advance (26.6), bitmap left / top (+ 32768), size, and
# its coverage as a tree of 2^d words
type TG is Data:
  TG{adv: U32, left: U32, top: U32, w: U32, h: U32, d: Nat, m: R.Mask}

# the face's ASCII glyphs (code points 0-127) as a tree of 2^7 leaves, so
# the glyphs text draws most are found without the cache's string keys; a
# leaf not filled (ok False) is looked up in the cache
type GTab is Data:
  GLeaf{ok: Bool, g: TG}
  GNode{lo: GTab, hi: GTab}

# A face: `ft` says FreeType (else the bitmap font); asc / desc / lh are
# the font's own pixel metrics; miss is the advance (26.6) of a glyph not
# in the cache; name is the family fontconfig chose.
type Face is Data:
  Face{id: U32, ft: Bool, px: U32, asc: U32, desc: U32, lh: U32, miss: U32, name: String, tab: GTab}

type FileIx is Data:
  FileIx{family: String, file: String, index: U32}

def Text.px(+v: U32) -> U32:
  ((v + 32 : U32) / 64 : U32)

# generic names accept whatever fontconfig picks for them
def Text.generic(+name: String) -> Bool:
  Bool.or(Bool.or(String.eq(name, "monospace"), String.eq(name, "sans-serif")),
    Bool.or(Bool.or(String.eq(name, "serif"), String.eq(name, "system-ui")), String.eq(name, "sans")))

# the family part of a pattern ("DejaVu Sans:weight=bold" -> "dejavu sans")
def Text.family(+pat: String) -> String:
  String.to_lower(Maybe.default(&2, String, List.head(&2, String, String.split(pat, ':')), ""))

def Text.accept(+pat: String, +fam: String) -> Bool:
  Bool.or(Text.generic(Text.family(pat)), String.eq(Text.family(pat), String.to_lower(fam)))

def Text.found.k(ok: Bool, fam: String, file: String, +index: U32) -> Maybe<&2, FileIx>:
  match ok:
    case True{}:
      Some{FileIx{fam, file, index}}
    case False{}:
      None{}

def Text.found(+pat: String, r: String & String & U32) -> Maybe<&2, FileIx>:
  (+fam, rest) = r
  (file, index) = rest
  Text.found.k(Text.accept(pat, fam), fam, file, index)

def Text.hit(+pat: String, r: Result<&1, &1, U32 & String, String & String & U32>) -> Maybe<&2, FileIx>:
  match r:
    case Done{v}:
      Text.found(pat, v)
    case Fail{_}:
      None{}

def Text.pick.k(m: Maybe<&2, FileIx>, next: IO(Maybe<&2, FileIx>)) -> IO(Maybe<&2, FileIx>):
  match m:
    case Some{f}:
      IO.pure(Maybe<&2, FileIx>, Some{f})
    case None{}:
      next

# the first family of a CSS-like stack that the system really has
# ("Berkeley Mono" only if installed; generic names always resolve)
def Text.pick(stack: List<&2, String>) -> IO(Maybe<&2, FileIx>):
  match stack:
    case Nil{}:
      IO.pure(Maybe<&2, FileIx>, None{})
    case +pat <> t:
      IO.bind(Result<&1, &1, U32 & String, String & String & U32>, Maybe<&2, FileIx>, FX.Font.find(pat),
        r => Text.pick.k(Text.hit(pat, r), Text.pick(t)))

# Glyphs
# ------

def Mask.depth(+n: U32) -> Nat:
  Bool.pick(Nat, U32.is_le(n, 1), 0n, 1n+U32.log2((n - 1 : U32)))

def Mask.word(xs: List<&2, U32>) -> R.Mask:
  match xs:
    case Nil{}:
      R.MWord{0}
    case h <> _:
      R.MWord{h}

# the first 2^d words of xs as a tree (zeros past the end)
def Mask.of(d: Nat, +xs: List<&2, U32>) -> R.Mask:
  match d:
    case 0n:
      Mask.word(xs)
    case 1n+k0:
      +k = k0
      +half = U32.to_nat(U32.shln(1, k))
      lo hi = Mask.of(k, List.take(&2, U32, xs, half)) Mask.of(k, List.drop(&2, U32, xs, half))
      R.MPair{lo, hi}

def TG.blank(+miss: U32) -> TG:
  TG{miss, 32768, 32768, 0, 0, 0n, R.MWord{0}}

# Font.glyph's words as a glyph
def TG.decode(ws: List<&2, U32>, +miss: U32) -> TG:
  match ws:
    case _ <> +adv <> +l <> +t <> +w <> +h <> cov:
      +d = Mask.depth((((w * h : U32) + 3 : U32) / 4 : U32))
      TG{adv, l, t, w, h, d, Mask.of(d, cov)}
    case _:
      TG.blank(miss)

def Text.key(+id: U32, +cp: U32) -> String:
  U32.show(id) ++ "/" ++ U32.show(cp)

def Text.got(r: Map<&2, TG> & TG) -> TG:
  (_, g) = r
  g

def Text.get.map(+cache: Map<&2, TG>, +id: U32, +cp: U32, +miss: U32) -> TG:
  Text.got(Map.get(TG, TG.blank(miss), cache, Text.key(id, cp)))

def GTab.leaf(g: GTab, +cache: Map<&2, TG>, +id: U32, +cp: U32, +miss: U32) -> TG:
  match g:
    case GLeaf{True{}, g}:
      g
    case _:
      Text.get.map(cache, id, cp, miss)

def GTab.half(hi: Bool, lo: GTab, h: GTab) -> GTab:
  match hi:
    case True{}:
      h
    case False{}:
      lo

# the leaf for cp, d levels down (bit d-1 picks the half)
def GTab.at(+d: Nat, t: GTab, +cp: U32, +bit: U32) -> GTab:
  match d t:
    case 1n+k GNode{lo, hi}:
      GTab.at(k, GTab.half(U32.is_ne(U32.and(cp, bit), 0), lo, hi), cp, U32.shr(bit))
    case _ _:
      t

def Text.get.k(ascii: Bool, +cache: Map<&2, TG>, +id: U32, +cp: U32, +miss: U32, +tab: GTab) -> TG:
  match ascii:
    case True{}:
      GTab.leaf(GTab.at(7n, tab, cp, 64), cache, id, cp, miss)
    case False{}:
      Text.get.map(cache, id, cp, miss)

# an empty table, d levels deep
def GTab.none(+d: Nat) -> GTab:
  match d:
    case 0n:
      GLeaf{False{}, TG.blank(0)}
    case 1n+k:
      GNode{GTab.none(k), GTab.none(k)}

# Faces
# -----

def Text.bitmap() -> Face:
  Face{0, False{}, 16, 12, 4, 16, 512, "Spleen 8x16", GTab.none(7n)}

def Text.face.m(+id: U32, +px: U32, ms: List<&2, U32>, +name: String) -> Face:
  match ms:
    case +a <> +d <> +h <> _:
      Face{id, True{}, px, Text.px(a), Text.px(d), Text.px(h), (px * 32 : U32), name, GTab.none(7n)}
    case _:
      Text.bitmap()

def Text.face.o(r: Result<&1, &1, U32 & String, U32>, +px: U32, +name: String) -> IO(Face):
  match r:
    case Done{+id}:
      IO.bind(List<&2, U32>, Face, FX.Font.metrics(id), ms => IO.pure(Face, Text.face.m(id, px, ms, name)))
    case Fail{_}:
      IO.pure(Face, Text.bitmap())

def Text.face.f(m: Maybe<&2, FileIx>, +px: U32) -> IO(Face):
  match m:
    case Some{FileIx{+fam, +file, +index}}:
      IO.bind(Result<&1, &1, U32 & String, U32>, Face, FX.Font.open(file, index, px), r => Text.face.o(r, px, fam))
    case None{}:
      IO.pure(Face, Text.bitmap())

# a face for the first available family of the stack at px pixels per em;
# the bitmap font when none loads (no fontconfig / FreeType)
def Text.face(stack: List<&2, String>, +px: U32) -> IO(Face):
  IO.bind(Maybe<&2, FileIx>, Face, Text.pick(stack), m => Text.face.f(m, px))

def GTab.one(m: Maybe<&2, TG>) -> GTab:
  match m:
    case Some{g}:
      GLeaf{True{}, g}
    case None{}:
      GLeaf{False{}, TG.blank(0)}

def Text.cached.k(r: Map<&2, TG> & Bool, +id: U32, +cp: U32) -> Maybe<&2, TG>:
  match r:
    case (+c, True{}):
      Some{Text.got(Map.get(TG, TG.blank(0), c, Text.key(id, cp)))}
    case (_, False{}):
      None{}

def Text.cached(+cache: Map<&2, TG>, +id: U32, +cp: U32) -> Maybe<&2, TG>:
  Text.cached.k(Map.has(&2, TG, cache, Text.key(id, cp)), id, cp)

# the table of the cache's glyphs for face id, code points from cp, 2^d of them
def GTab.of(+d: Nat, +cache: Map<&2, TG>, +id: U32, +cp: U32) -> GTab:
  match d:
    case 0n:
      GTab.one(Text.cached(cache, id, cp))
    case 1n+k:
      GNode{GTab.of(k, cache, id, cp), GTab.of(k, cache, id, (cp + U32.shln(1, k) : U32))}

# the face with its ASCII table filled from the cache (once warmed)
def Face.tabled(f: Face, +cache: Map<&2, TG>) -> Face:
  match f:
    case Face{+id, ft, px, asc, desc, lh, miss, name, _}:
      Face{id, ft, px, asc, desc, lh, miss, name, GTab.of(7n, cache, id, 0)}

def Text.get(+cache: Map<&2, TG>, +f: Face, +cp: U32) -> TG:
  match f:
    case Face{+id, _, _, _, _, _, +miss, _, +tab}:
      Text.get.k(U32.is_lt(cp, 128), cache, id, cp, miss, tab)

def Text.fetch(+cache: Map<&2, TG>, +id: U32, +cp: U32, +miss: U32) -> IO(Map<&2, TG>):
  IO.bind(List<&2, U32>, Map<&2, TG>, FX.Font.glyph(id, cp), ws => IO.pure(Map<&2, TG>, Map.set(&2, TG, cache, Text.key(id, cp), TG.decode(ws, miss))))

def Text.one.k(r: Map<&2, TG> & Bool, +id: U32, +cp: U32, +miss: U32) -> IO(Map<&2, TG>):
  match r:
    case (+cache, True{}):
      IO.pure(Map<&2, TG>, cache)
    case (+cache, False{}):
      Text.fetch(cache, id, cp, miss)

def Text.one(cache: Map<&2, TG>, +id: U32, +cp: U32, +miss: U32) -> IO(Map<&2, TG>):
  Text.one.k(Map.has(&2, TG, cache, Text.key(id, cp)), id, cp, miss)

def Text.ensure.go(s: String, cache: Map<&2, TG>, +id: U32, +miss: U32) -> IO(Map<&2, TG>):
  match s:
    case SNil{}:
      IO.pure(Map<&2, TG>, cache)
    case SCon{Chr{+cp}, t}:
      IO.bind(Map<&2, TG>, Map<&2, TG>, Text.one(cache, id, cp, miss), c2 => Text.ensure.go(t, c2, id, miss))

# the cache with every glyph of s for the face (the effect runs only for
# the missing ones; the bitmap face needs none)
def Text.ensure(cache: Map<&2, TG>, f: Face, s: String) -> IO(Map<&2, TG>):
  match f:
    case Face{+id, True{}, _, _, _, _, +miss, _, _}:
      Text.ensure.go(s, cache, id, miss)
    case Face{_, False{}, _, _, _, _, _, _, _}:
      IO.pure(Map<&2, TG>, cache)

def Text.ascii.go(n: Nat, acc: String) -> String:
  match n:
    case 0n:
      acc
    case 1n+i0:
      +i = i0
      Text.ascii.go(i, SCon{Chr{U32.from_nat(Nat.add(i, 32n))}, acc})

# printable ASCII, " " to "~", and the punctuation the UI draws
def Text.ascii() -> String:
  Text.ascii.go(95n, "…·—–•→✓")

# warm-up: ASCII (and the UI's punctuation) for the face
def Text.warm(cache: Map<&2, TG>, f: Face) -> IO(Map<&2, TG>):
  Text.ensure(cache, f, Text.ascii())

# Measuring
# ---------

def TG.adv(g: TG) -> U32:
  match g:
    case TG{adv, _, _, _, _, _, _}:
      adv

# the advance of s in 26.6 pixels, added to acc
def Text.adv(s: String, +cache: Map<&2, TG>, +f: Face, acc: U32) -> U32:
  match s:
    case SNil{}:
      acc
    case SCon{Chr{+cp}, t}:
      Text.adv(t, cache, f, (acc + TG.adv(Text.get(cache, f, cp)) : U32))

def Text.width.k(ft: Bool, +cache: Map<&2, TG>, +f: Face, s: String) -> U32:
  match ft:
    case True{}:
      Text.px(Text.adv(s, cache, f, 0))
    case False{}:
      (U32.from_nat(String.length(s)) * 8 : U32)

def Face.ft(f: Face) -> Bool:
  match f:
    case Face{_, ft, _, _, _, _, _, _, _}:
      ft

def Face.asc(f: Face) -> U32:
  match f:
    case Face{_, _, _, asc, _, _, _, _, _}:
      asc

def Face.lh(f: Face) -> U32:
  match f:
    case Face{_, _, _, _, _, lh, _, _, _}:
      lh

def Face.name(f: Face) -> String:
  match f:
    case Face{_, _, _, _, _, _, _, name, _}:
      name

# the width of s in pixels
def Text.width(+cache: Map<&2, TG>, +f: Face, s: String) -> U32:
  Text.width.k(Face.ft(f), cache, f, s)

# the baseline of a line box of height lh whose top is y (CSS half-leading)
def Text.baseline(+f: Face, +y: U32, +lh: U32) -> U32:
  match f:
    case Face{_, _, _, +asc, +desc, _, _, _, _}:
      (y + ((lh - (asc + desc : U32) : U32) / 2 : U32) + asc : U32)

# Wrapping (proportional)
# -----------------------

def Fit.count.k(ok: Bool, rest: Nat) -> Nat:
  match ok:
    case True{}:
      1n+rest
    case False{}:
      0n

# how many leading characters of s fit in max (26.6) after used
def Fit.count(s: String, +cache: Map<&2, TG>, +f: Face, +max: U32, +used: U32) -> Nat:
  match s:
    case SNil{}:
      0n
    case SCon{Chr{+cp}, t}:
      +u2 = (used + TG.adv(Text.get(cache, f, cp)) : U32)
      Fit.count.k(U32.is_le(u2, max), Fit.count(t, cache, f, max, u2))

# s in pieces that each fit in max (at least one character each)
def Fit.chunk(n: Nat, empty: Bool, +s: String, +cache: Map<&2, TG>, +f: Face, +max: U32) -> List<&2, String>:
  match n empty:
    case 1n+m False{}:
      +k = Bool.pick(Nat, Nat.is_eq(Fit.count(s, cache, f, max, 0), 0n), 1n, Fit.count(s, cache, f, max, 0))
      String.take(s, k) <> Fit.chunk(m, String.is_empty(String.drop(s, k)), String.drop(s, k), cache, f, max)
    case _ _:
      Nil{}

# lines so far (newest first), the line being filled, and its advance
type PAcc is Data:
  PAcc{lines: List<&2, String>, cur: String, len: U32, first: Bool}

def PWrap.put.k(first: Bool, fits: Bool, a: PAcc, +w: String, +ww: U32, +sp: U32) -> PAcc:
  match first fits a:
    case True{} _ PAcc{ls, _, _, _}:
      PAcc{ls, w, ww, False{}}
    case False{} True{} PAcc{ls, cur, +len, _}:
      PAcc{ls, cur ++ " " ++ w, (len + sp + ww : U32), False{}}
    case False{} False{} PAcc{ls, cur, _, _}:
      PAcc{cur <> ls, w, ww, False{}}

def PWrap.put(a: PAcc, +w: String, +ww: U32, +sp: U32, +max: U32) -> PAcc:
  match a:
    case PAcc{ls, cur, +len, +first}:
      PWrap.put.k(first, U32.is_le((len + sp + ww : U32), max), PAcc{ls, cur, len, first}, w, ww, sp)

def PWrap.pieces(ps: List<&2, String>, a: PAcc, +cache: Map<&2, TG>, +f: Face, +sp: U32, +max: U32) -> PAcc:
  match ps:
    case Nil{}:
      a
    case +p <> t:
      PWrap.pieces(t, PWrap.put(a, p, Text.adv(p, cache, f, 0), sp, max), cache, f, sp, max)

# a word's pieces; an empty word (between two spaces, or after a last
# one) is kept, so every space the text has is on a line (the caret after
# a typed space moves at once, runs of spaces show)
def PWrap.chunks(empty: Bool, +w: String, +cache: Map<&2, TG>, +f: Face, +max: U32) -> List<&2, String>:
  match empty:
    case True{}:
      [""]
    case False{}:
      Fit.chunk(1n+String.length(w), False{}, w, cache, f, max)

def PWrap.words(ws: List<&2, String>, a: PAcc, +cache: Map<&2, TG>, +f: Face, +sp: U32, +max: U32) -> PAcc:
  match ws:
    case Nil{}:
      a
    case +w <> t:
      PWrap.words(t, PWrap.pieces(PWrap.chunks(String.is_empty(w), w, cache, f, max), a, cache, f, sp, max), cache, f, sp, max)

def PWrap.fin(a: PAcc) -> List<&2, String>:
  match a:
    case PAcc{ls, cur, _, _}:
      List.reverse(&2, String, cur <> ls)

# one paragraph line (no newlines) wrapped to px pixels; "" stays one
# blank line
def Text.wrap.line(s: String, +cache: Map<&2, TG>, +f: Face, +px: U32) -> List<&2, String>:
  PWrap.fin(PWrap.words(String.split(s, ' '), PAcc{Nil{}, "", 0, True{}}, cache, f, TG.adv(Text.get(cache, f, 32)), (px * 64 : U32)))

def Text.wrap.lines(ls: List<&2, String>, +cache: Map<&2, TG>, +f: Face, +px: U32) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> t:
      List.append(&2, String, Text.wrap.line(l, cache, f, px), Text.wrap.lines(t, cache, f, px))

# text with newlines, wrapped greedily by words to px pixels (a word
# wider than a line is broken between characters)
def Text.wrap(+cache: Map<&2, TG>, +f: Face, s: String, +px: U32) -> List<&2, String>:
  Text.wrap.lines(String.split(s, '\n'), cache, f, px)

def Text.fit.k(fits: Bool, +cache: Map<&2, TG>, +f: Face, +s: String, +px: U32) -> String:
  match fits:
    case True{}:
      s
    case False{}:
      String.take(s, Fit.count(s, cache, f, ((px * 64 : U32) - TG.adv(Text.get(cache, f, 8230)) : U32), 0)) ++ "…"

# s cut with an ellipsis to fit px pixels
def Text.fit(+cache: Map<&2, TG>, +f: Face, +s: String, +px: U32) -> String:
  Text.fit.k(U32.is_le(Text.width(cache, f, s), px), cache, f, s, px)

# Drawing
# -------

def Text.op.k(empty: Bool, +c: D.Clip, +gx: U32, +gy: U32, +w: U32, +h: U32, d: Nat, m: R.Mask, +color: U32, rest: List<&2, R.Op>) -> List<&2, R.Op>:
  match empty:
    case True{}:
      rest
    case False{}:
      D.Clip.cut(c, gx, gy, (gx + w : U32), (gy + h : U32), color, 255, R.SMask{gx, gy, w, d, m}) <> rest

# one glyph with its pen at pixel x on the baseline
def Text.op(g: TG, +c: D.Clip, +x: U32, +base: U32, +color: U32, rest: List<&2, R.Op>) -> List<&2, R.Op>:
  match g:
    case TG{_, +l, +t, +w, +h, d, m}:
      Text.op.k(Bool.or(U32.is_eq((w * h : U32), 0), U32.is_lt((x + l : U32), 32768)), c, (x + l - 32768 : U32), (base + 32768 - t : U32), w, h, d, m, color, rest)

def Text.run(s: String, +cache: Map<&2, TG>, +f: Face, +c: D.Clip, +x: U32, +pen: U32, +base: U32, +color: U32) -> List<&2, R.Op>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{Chr{+cp}, t}:
      +g = Text.get(cache, f, cp)
      Text.op(g, c, (x + Text.px(pen) : U32), base, color, Text.run(t, cache, f, c, x, (pen + TG.adv(g) : U32), base, color))

def Text.draw.k(ft: Bool, s: String, +cache: Map<&2, TG>, +f: Face, +c: D.Clip, +x: U32, +base: U32, +color: U32) -> List<&2, R.Op>:
  match ft:
    case True{}:
      Text.run(s, cache, f, c, x, 0, base, color)
    case False{}:
      D.Draw.text(s, c, x, (base - 12 : U32), color)

# one line of text, pen starting at x on the given baseline
def Text.draw(+cache: Map<&2, TG>, +f: Face, s: String, +c: D.Clip, +x: U32, +base: U32, +color: U32) -> List<&2, R.Op>:
  Text.draw.k(Face.ft(f), s, cache, f, c, x, base, color)

# one line of text in a line box of height lh whose top is y
def Text.line(+cache: Map<&2, TG>, +f: Face, s: String, +c: D.Clip, +x: U32, +y: U32, +lh: U32, +color: U32) -> List<&2, R.Op>:
  Text.draw(cache, f, s, c, x, Text.baseline(f, y, lh), color)
