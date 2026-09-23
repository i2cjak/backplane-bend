import Base

# SVG path data (the `d` attribute): parsed to absolute segments, written
# back out, and flattened to line segments for the rasterizer. Commands
# M L H V C S Q T A Z, absolute and relative, with implicit repeats (extra
# pairs after a moveto are linetos) and compact numbers ("1-2.5.5" is 1,
# -2.5, .5). The lexer and parser decide on characters only, never on the
# numbers, so the checker can run them (laws svg_*).

# Tokens
# ------

type Tok is Data:
  TNum{v: F32}
  TCmd{c: U32}

# a character's class
type Ch is Data:
  CDig{d: U32}
  CDot{}
  CSign{neg: Bool}
  CExp{}
  CCmd{c: U32}
  CSep{}

def Svg.cmd_letter(+c: U32) -> Bool:
  +u = U32.and(c, 223)
  Bool.or(Bool.or(Bool.or(U32.is_eq(u, 77), U32.is_eq(u, 76)), Bool.or(U32.is_eq(u, 72), U32.is_eq(u, 86))),
    Bool.or(Bool.or(Bool.or(U32.is_eq(u, 67), U32.is_eq(u, 83)), Bool.or(U32.is_eq(u, 81), U32.is_eq(u, 84))), Bool.or(U32.is_eq(u, 65), U32.is_eq(u, 90))))

def Ch.of(+c: U32) -> Ch:
  Bool.pick(Ch, Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57)), CDig{(c - 48 : U32)},
    Bool.pick(Ch, U32.is_eq(c, 46), CDot{},
      Bool.pick(Ch, U32.is_eq(c, 45), CSign{True{}},
        Bool.pick(Ch, U32.is_eq(c, 43), CSign{False{}},
          Bool.pick(Ch, Bool.or(U32.is_eq(c, 101), U32.is_eq(c, 69)), CExp{},
            Bool.pick(Ch, Svg.cmd_letter(c), CCmd{c}, CSep{}))))))

# a number being read: phase 0 none, 1 sign, 2 integer digits, 3 fraction
# digits, 4 after "e", 5 after the exponent's sign, 6 exponent digits; its
# characters so far, newest first (F32.read turns them into the nearest
# float, so a number written by Svg.show reads back the same)
type Num is Data:
  Num{ph: U32, cs: String}

def Num.none() -> Num:
  Num{0, ""}

def Num.value(n: Num) -> F32:
  match n:
    case Num{_, cs}:
      Maybe.default(&2, F32, F32.read(String.reverse(cs)), 0.0)

def Num.flush.k(has: Bool, +n: Num, out: List<&2, Tok>) -> List<&2, Tok>:
  match has:
    case True{}:
      TNum{Num.value(n)} <> out
    case False{}:
      out

# a finished number onto the tokens (a lone sign is no number)
def Num.flush(+n: Num, out: List<&2, Tok>) -> List<&2, Tok>:
  match n:
    case Num{+ph, _}:
      Num.flush.k(U32.is_ge(ph, 2), n, out)

type Lex is Data:
  Lex{n: Num, out: List<&2, Tok>}

def Lex.digit(int: Bool, frac: Bool, +c: U32, n: Num, out: List<&2, Tok>) -> Lex:
  match int frac n:
    case True{} _ Num{_, cs}:
      Lex{Num{2, SCon{Chr{c}, cs}}, out}
    case False{} True{} Num{_, cs}:
      Lex{Num{3, SCon{Chr{c}, cs}}, out}
    case False{} False{} Num{_, cs}:
      Lex{Num{6, SCon{Chr{c}, cs}}, out}

def Lex.dot(int: Bool, +n: Num, out: List<&2, Tok>) -> Lex:
  match int n:
    case True{} Num{_, cs}:
      Lex{Num{3, SCon{Chr{46}, cs}}, out}
    case False{} _:
      Lex{Num{3, "."}, Num.flush(n, out)}

def Lex.sign(exp: Bool, +c: U32, +n: Num, out: List<&2, Tok>) -> Lex:
  match exp n:
    case True{} Num{_, cs}:
      Lex{Num{5, SCon{Chr{c}, cs}}, out}
    case False{} _:
      Lex{Num{1, SCon{Chr{c}, ""}}, Num.flush(n, out)}

def Lex.exp(mant: Bool, +n: Num, out: List<&2, Tok>) -> Lex:
  match mant n:
    case True{} Num{_, cs}:
      Lex{Num{4, SCon{Chr{101}, cs}}, out}
    case False{} _:
      Lex{n, out}

def Lex.k(c: Ch, +u: U32, +n: Num, out: List<&2, Tok>) -> Lex:
  match c n:
    case CDig{_} Num{+ph, _}:
      Lex.digit(U32.is_le(ph, 2), U32.is_eq(ph, 3), u, n, out)
    case CDot{} Num{+ph, _}:
      Lex.dot(U32.is_le(ph, 2), n, out)
    case CSign{_} Num{+ph, _}:
      Lex.sign(U32.is_eq(ph, 4), u, n, out)
    case CExp{} Num{+ph, _}:
      Lex.exp(Bool.or(U32.is_eq(ph, 2), U32.is_eq(ph, 3)), n, out)
    case CCmd{+cc} _:
      Lex{Num.none(), TCmd{cc} <> Num.flush(n, out)}
    case CSep{} _:
      Lex{Num.none(), Num.flush(n, out)}

def Lex.step(l: Lex, +c: U32) -> Lex:
  match l:
    case Lex{+n, out}:
      Lex.k(Ch.of(c), c, n, out)

def Lex.go(s: String, l: Lex) -> Lex:
  match s:
    case SNil{}:
      l
    case SCon{Chr{+c}, t}:
      Lex.go(t, Lex.step(l, c))

def Lex.fin(l: Lex) -> List<&2, Tok>:
  match l:
    case Lex{+n, out}:
      Num.flush(n, out)

# the tokens of path data, newest first
def Svg.lex.rev(s: String) -> List<&2, Tok>:
  Lex.fin(Lex.go(s, Lex{Num.none(), Nil{}}))

# the tokens of path data, in order
def Svg.lex(s: String) -> List<&2, Tok>:
  List.reverse(&2, Tok, Svg.lex.rev(s))

# Commands and their numbers
# --------------------------

type Grp is Data:
  Grp{c: U32, args: List<&2, F32>}

# from the newest token back: numbers gather until their command (numbers
# before the first command are dropped)
def Grp.go(ts: List<&2, Tok>, args: List<&2, F32>, gs: List<&2, Grp>) -> List<&2, Grp>:
  match ts:
    case Nil{}:
      gs
    case TNum{+v} <> t:
      Grp.go(t, v <> args, gs)
    case TCmd{+c} <> t:
      Grp.go(t, Nil{}, Grp{c, args} <> gs)

type Cmd is Data:
  KM{}
  KL{}
  KH{}
  KV{}
  KC{}
  KS{}
  KQ{}
  KT{}
  KA{}
  KZ{}

def Cmd.of(+c: U32) -> Cmd:
  +u = U32.and(c, 223)
  Bool.pick(Cmd, U32.is_eq(u, 77), KM{}, Bool.pick(Cmd, U32.is_eq(u, 76), KL{}, Bool.pick(Cmd, U32.is_eq(u, 72), KH{},
    Bool.pick(Cmd, U32.is_eq(u, 86), KV{}, Bool.pick(Cmd, U32.is_eq(u, 67), KC{}, Bool.pick(Cmd, U32.is_eq(u, 83), KS{},
      Bool.pick(Cmd, U32.is_eq(u, 81), KQ{}, Bool.pick(Cmd, U32.is_eq(u, 84), KT{}, Bool.pick(Cmd, U32.is_eq(u, 65), KA{}, KZ{})))))))))

# Segments
# --------

# an absolute segment
type Seg is Data:
  SM{x: F32, y: F32}
  SL{x: F32, y: F32}
  SC{x1: F32, y1: F32, x2: F32, y2: F32, x: F32, y: F32}
  SQ{x1: F32, y1: F32, x: F32, y: F32}
  SA{rx: F32, ry: F32, rot: F32, large: Bool, sweep: Bool, x: F32, y: F32}
  SZ{}

type Pt is Data:
  Pt{x: F32, y: F32}

# the pen: where it is, where its subpath began, and the last control
# point with its kind (0 none, 1 cubic, 2 quadratic) for S and T
type Pen is Data:
  Pen{x: F32, y: F32, sx: F32, sy: F32, cx: F32, cy: F32, ck: U32}

def Pen.origin() -> Pen:
  Pen{0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0}

def Pen.cur(p: Pen) -> Pt:
  match p:
    case Pen{x, y, _, _, _, _, _}:
      Pt{x, y}

def Pen.start(p: Pen) -> Pt:
  match p:
    case Pen{_, _, sx, sy, _, _, _}:
      Pt{sx, sy}

# a moveto starts a subpath where it lands
def Pen.move(p: Pen, +x: F32, +y: F32) -> Pen:
  match p:
    case Pen{_, _, _, _, _, _, _}:
      Pen{x, y, x, y, x, y, 0}

def Pen.line(p: Pen, +x: F32, +y: F32) -> Pen:
  match p:
    case Pen{_, _, sx, sy, _, _, _}:
      Pen{x, y, sx, sy, x, y, 0}

def Pen.curve(p: Pen, +cx: F32, +cy: F32, +ck: U32, +x: F32, +y: F32) -> Pen:
  match p:
    case Pen{_, _, sx, sy, _, _, _}:
      Pen{x, y, sx, sy, cx, cy, ck}

# closepath takes the pen back to its subpath's start
def Pen.close(p: Pen) -> Pen:
  match p:
    case Pen{_, _, +sx, +sy, _, _, _}:
      Pen{sx, sy, sx, sy, sx, sy, 0}

# a coordinate: relative ones count from the pen
def Svg.at(rel: Bool, +p: F32, +v: F32) -> F32:
  match rel:
    case True{}:
      F32.add(p, v)
    case False{}:
      v

# the reflection of the last control point of kind k through the pen (the
# pen itself after any other segment)
def Svg.mirror(+ck: U32, +k: U32, +p: F32, +c: F32) -> F32:
  Bool.pick(F32, U32.is_eq(ck, k), F32.sub(F32.mul(2.0, p), c), p)

type Acc is Data:
  Acc{pen: Pen, out: List<&2, Seg>}

def Run.m(+rel: Bool, +x: F32, +y: F32, a: Acc) -> Acc:
  match a:
    case Acc{Pen{+px, +py, sx, sy, cx, cy, ck}, out}:
      +ax = Svg.at(rel, px, x)
      +ay = Svg.at(rel, py, y)
      Acc{Pen.move(Pen{px, py, sx, sy, cx, cy, ck}, ax, ay), SM{ax, ay} <> out}

def Run.l(+ax: F32, +ay: F32, a: Acc) -> Acc:
  match a:
    case Acc{p, out}:
      Acc{Pen.line(p, ax, ay), SL{ax, ay} <> out}

def Run.xy(+rel: Bool, +x: F32, +y: F32, a: Acc) -> Acc:
  match a:
    case Acc{Pen{+px, +py, sx, sy, cx, cy, ck}, out}:
      Run.l(Svg.at(rel, px, x), Svg.at(rel, py, y), Acc{Pen{px, py, sx, sy, cx, cy, ck}, out})

def Run.h(+rel: Bool, +x: F32, a: Acc) -> Acc:
  match a:
    case Acc{Pen{+px, +py, sx, sy, cx, cy, ck}, out}:
      Run.l(Svg.at(rel, px, x), py, Acc{Pen{px, py, sx, sy, cx, cy, ck}, out})

def Run.v(+rel: Bool, +y: F32, a: Acc) -> Acc:
  match a:
    case Acc{Pen{+px, +py, sx, sy, cx, cy, ck}, out}:
      Run.l(px, Svg.at(rel, py, y), Acc{Pen{px, py, sx, sy, cx, cy, ck}, out})

def Run.cub(+x1: F32, +y1: F32, +x2: F32, +y2: F32, +x: F32, +y: F32, a: Acc) -> Acc:
  match a:
    case Acc{p, out}:
      Acc{Pen.curve(p, x2, y2, 1, x, y), SC{x1, y1, x2, y2, x, y} <> out}

def Run.quad(+x1: F32, +y1: F32, +x: F32, +y: F32, a: Acc) -> Acc:
  match a:
    case Acc{p, out}:
      Acc{Pen.curve(p, x1, y1, 2, x, y), SQ{x1, y1, x, y} <> out}

def Run.c(+rel: Bool, +x1: F32, +y1: F32, +x2: F32, +y2: F32, +x: F32, +y: F32, a: Acc) -> Acc:
  match a:
    case Acc{Pen{+px, +py, sx, sy, cx, cy, ck}, out}:
      Run.cub(Svg.at(rel, px, x1), Svg.at(rel, py, y1), Svg.at(rel, px, x2), Svg.at(rel, py, y2), Svg.at(rel, px, x), Svg.at(rel, py, y),
        Acc{Pen{px, py, sx, sy, cx, cy, ck}, out})

def Run.s(+rel: Bool, +x2: F32, +y2: F32, +x: F32, +y: F32, a: Acc) -> Acc:
  match a:
    case Acc{Pen{+px, +py, sx, sy, +cx, +cy, +ck}, out}:
      Run.cub(Svg.mirror(ck, 1, px, cx), Svg.mirror(ck, 1, py, cy), Svg.at(rel, px, x2), Svg.at(rel, py, y2), Svg.at(rel, px, x), Svg.at(rel, py, y),
        Acc{Pen{px, py, sx, sy, cx, cy, ck}, out})

def Run.q(+rel: Bool, +x1: F32, +y1: F32, +x: F32, +y: F32, a: Acc) -> Acc:
  match a:
    case Acc{Pen{+px, +py, sx, sy, cx, cy, ck}, out}:
      Run.quad(Svg.at(rel, px, x1), Svg.at(rel, py, y1), Svg.at(rel, px, x), Svg.at(rel, py, y), Acc{Pen{px, py, sx, sy, cx, cy, ck}, out})

def Run.t(+rel: Bool, +x: F32, +y: F32, a: Acc) -> Acc:
  match a:
    case Acc{Pen{+px, +py, sx, sy, +cx, +cy, +ck}, out}:
      Run.quad(Svg.mirror(ck, 2, px, cx), Svg.mirror(ck, 2, py, cy), Svg.at(rel, px, x), Svg.at(rel, py, y), Acc{Pen{px, py, sx, sy, cx, cy, ck}, out})

def Run.arc(+rx: F32, +ry: F32, +rot: F32, +fa: F32, +fs: F32, +x: F32, +y: F32, a: Acc) -> Acc:
  match a:
    case Acc{p, out}:
      Acc{Pen.line(p, x, y), SA{F32.abs(rx), F32.abs(ry), rot, F32.is_ne(fa, 0.0), F32.is_ne(fs, 0.0), x, y} <> out}

def Run.a(+rel: Bool, +rx: F32, +ry: F32, +rot: F32, +fa: F32, +fs: F32, +x: F32, +y: F32, a: Acc) -> Acc:
  match a:
    case Acc{Pen{+px, +py, sx, sy, cx, cy, ck}, out}:
      Run.arc(rx, ry, rot, fa, fs, Svg.at(rel, px, x), Svg.at(rel, py, y), Acc{Pen{px, py, sx, sy, cx, cy, ck}, out})

def Run.z(a: Acc) -> Acc:
  match a:
    case Acc{p, out}:
      Acc{Pen.close(p), SZ{} <> out}

# one command over its numbers, as many times as they fill it (extra pairs
# after a moveto are linetos); a short tail is dropped
def Run.go(args: List<&2, F32>, k: Cmd, +rel: Bool, a: Acc) -> Acc:
  match args k:
    case +x <> +y <> t KM{}:
      Run.go(t, KL{}, rel, Run.m(rel, x, y, a))
    case +x <> +y <> t KL{}:
      Run.go(t, KL{}, rel, Run.xy(rel, x, y, a))
    case +x <> t KH{}:
      Run.go(t, KH{}, rel, Run.h(rel, x, a))
    case +y <> t KV{}:
      Run.go(t, KV{}, rel, Run.v(rel, y, a))
    case +x1 <> +y1 <> +x2 <> +y2 <> +x <> +y <> t KC{}:
      Run.go(t, KC{}, rel, Run.c(rel, x1, y1, x2, y2, x, y, a))
    case +x2 <> +y2 <> +x <> +y <> t KS{}:
      Run.go(t, KS{}, rel, Run.s(rel, x2, y2, x, y, a))
    case +x1 <> +y1 <> +x <> +y <> t KQ{}:
      Run.go(t, KQ{}, rel, Run.q(rel, x1, y1, x, y, a))
    case +x <> +y <> t KT{}:
      Run.go(t, KT{}, rel, Run.t(rel, x, y, a))
    case +rx <> +ry <> +rot <> +fa <> +fs <> +x <> +y <> t KA{}:
      Run.go(t, KA{}, rel, Run.a(rel, rx, ry, rot, fa, fs, x, y, a))
    case _ KZ{}:
      Run.z(a)
    case _ _:
      a

def Grp.run(g: Grp, a: Acc) -> Acc:
  match g:
    case Grp{+c, args}:
      Run.go(args, Cmd.of(c), U32.is_ge(c, 97), a)

def Grp.all(gs: List<&2, Grp>, a: Acc) -> Acc:
  match gs:
    case Nil{}:
      a
    case g <> t:
      Grp.all(t, Grp.run(g, a))

def Acc.segs(a: Acc) -> List<&2, Seg>:
  match a:
    case Acc{_, out}:
      List.reverse(&2, Seg, out)

# path data as absolute segments
def Svg.parse(d: String) -> List<&2, Seg>:
  Acc.segs(Grp.all(Grp.go(Svg.lex.rev(d), Nil{}, Nil{}), Acc{Pen.origin(), Nil{}}))

# each segment's command letter (M L C Q A Z)
def Svg.kinds(ss: List<&2, Seg>) -> List<&2, U32>:
  match ss:
    case Nil{}:
      Nil{}
    case SM{_, _} <> t:
      77 <> Svg.kinds(t)
    case SL{_, _} <> t:
      76 <> Svg.kinds(t)
    case SC{_, _, _, _, _, _} <> t:
      67 <> Svg.kinds(t)
    case SQ{_, _, _, _} <> t:
      81 <> Svg.kinds(t)
    case SA{_, _, _, _, _, _, _} <> t:
      65 <> Svg.kinds(t)
    case SZ{} <> t:
      90 <> Svg.kinds(t)

# Writing
# -------

def Svg.num(+v: F32) -> String:
  F32.show(v)

def Svg.nums(vs: List<&2, F32>) -> String:
  match vs:
    case Nil{}:
      ""
    case v <> t:
      " " ++ Svg.num(v) ++ Svg.nums(t)

def Svg.flag(b: Bool) -> F32:
  match b:
    case True{}:
      1.0
    case False{}:
      0.0

def Svg.show1(s: Seg) -> String:
  match s:
    case SM{x, y}:
      "M" ++ Svg.nums([x, y])
    case SL{x, y}:
      "L" ++ Svg.nums([x, y])
    case SC{x1, y1, x2, y2, x, y}:
      "C" ++ Svg.nums([x1, y1, x2, y2, x, y])
    case SQ{x1, y1, x, y}:
      "Q" ++ Svg.nums([x1, y1, x, y])
    case SA{rx, ry, rot, la, sw, x, y}:
      "A" ++ Svg.nums([rx, ry, rot, Svg.flag(la), Svg.flag(sw), x, y])
    case SZ{}:
      "Z"

def Svg.shows(ss: List<&2, Seg>) -> List<&2, String>:
  match ss:
    case Nil{}:
      Nil{}
    case s <> t:
      Svg.show1(s) <> Svg.shows(t)

# segments as path data (all absolute; Svg.parse reads it back)
def Svg.show(ss: List<&2, Seg>) -> String:
  String.join(Svg.shows(ss), " ")

# Flattening
# ----------

# a line segment of the flattened path; `fill` marks the edge that closes
# an open subpath, which a fill uses and a stroke does not draw
type Ln is Data:
  Ln{ax: F32, ay: F32, bx: F32, by: F32, fill: Bool}

type Fl is Data:
  Fl{x: F32, y: F32, sx: F32, sy: F32, out: List<&2, Ln>}

# point t of a cubic / quadratic
def Bez.c1(+t: F32, +a: F32, +b: F32, +c: F32, +d: F32) -> F32:
  +u = F32.sub(1.0, t)
  F32.add(F32.add(F32.mul(F32.mul(u, F32.mul(u, u)), a), F32.mul(F32.mul(3.0, F32.mul(u, F32.mul(u, t))), b)),
    F32.add(F32.mul(F32.mul(3.0, F32.mul(u, F32.mul(t, t))), c), F32.mul(F32.mul(t, F32.mul(t, t)), d)))

def Bez.q1(+t: F32, +a: F32, +b: F32, +c: F32) -> F32:
  +u = F32.sub(1.0, t)
  F32.add(F32.add(F32.mul(F32.mul(u, u), a), F32.mul(F32.mul(2.0, F32.mul(u, t)), b)), F32.mul(F32.mul(t, t), c))

def Bez.steps() -> Nat:
  12n

# the curve's pieces from t = i/n down to t = 0
def Bez.cub(i: Nat, +n: F32, +x0: F32, +y0: F32, +x1: F32, +y1: F32, +x2: F32, +y2: F32, +x3: F32, +y3: F32, out: List<&2, Ln>) -> List<&2, Ln>:
  match i:
    case 0n:
      out
    case 1n+j0:
      +j = j0
      +ta = F32.div(F32.from_nat(j), n)
      +tb = F32.div(F32.from_nat(1n+j), n)
      Bez.cub(j, n, x0, y0, x1, y1, x2, y2, x3, y3,
        Ln{Bez.c1(ta, x0, x1, x2, x3), Bez.c1(ta, y0, y1, y2, y3), Bez.c1(tb, x0, x1, x2, x3), Bez.c1(tb, y0, y1, y2, y3), False{}} <> out)

def Bez.quad(i: Nat, +n: F32, +x0: F32, +y0: F32, +x1: F32, +y1: F32, +x2: F32, +y2: F32, out: List<&2, Ln>) -> List<&2, Ln>:
  match i:
    case 0n:
      out
    case 1n+j0:
      +j = j0
      +ta = F32.div(F32.from_nat(j), n)
      +tb = F32.div(F32.from_nat(1n+j), n)
      Bez.quad(j, n, x0, y0, x1, y1, x2, y2,
        Ln{Bez.q1(ta, x0, x1, x2), Bez.q1(ta, y0, y1, y2), Bez.q1(tb, x0, x1, x2), Bez.q1(tb, y0, y1, y2), False{}} <> out)

# Arcs (SVG's endpoint form to centre form, then pieces of at most 15
# degrees)

type Arc is Data:
  Arc{cx: F32, cy: F32, rx: F32, ry: F32, cs: F32, sn: F32, t0: F32, dt: F32}

def Arc.pt.x(a: Arc, +t: F32) -> F32:
  match a:
    case Arc{+cx, _, +rx, +ry, +cs, +sn, _, _}:
      F32.add(cx, F32.sub(F32.mul(F32.mul(rx, cs), F32.cos(t)), F32.mul(F32.mul(ry, sn), F32.sin(t))))

def Arc.pt.y(a: Arc, +t: F32) -> F32:
  match a:
    case Arc{_, +cy, +rx, +ry, +cs, +sn, _, _}:
      F32.add(cy, F32.add(F32.mul(F32.mul(rx, sn), F32.cos(t)), F32.mul(F32.mul(ry, cs), F32.sin(t))))

def Arc.go(i: Nat, +n: F32, +a: Arc, +t0: F32, +dt: F32, out: List<&2, Ln>) -> List<&2, Ln>:
  match i:
    case 0n:
      out
    case 1n+j0:
      +j = j0
      +ta = F32.add(t0, F32.mul(dt, F32.div(F32.from_nat(j), n)))
      +tb = F32.add(t0, F32.mul(dt, F32.div(F32.from_nat(1n+j), n)))
      Arc.go(j, n, a, t0, dt, Ln{Arc.pt.x(a, ta), Arc.pt.y(a, ta), Arc.pt.x(a, tb), Arc.pt.y(a, tb), False{}} <> out)

def Arc.pieces(+a: Arc, out: List<&2, Ln>) -> List<&2, Ln>:
  match a:
    case Arc{_, _, _, _, _, _, +t0, +dt}:
      +n = F32.max(F32.ceil(F32.div(F32.abs(dt), F32.div(F32.pi(), 12.0))), 1.0)
      Arc.go(F32.to_nat(n), n, a, t0, dt, out)

# the sweep turned the way the flag says
def Arc.dt(+sweep: Bool, +d: F32) -> F32:
  +tau = F32.mul(2.0, F32.pi())
  Bool.pick(F32, Bool.and(Bool.not(sweep), F32.is_gt(d, 0.0)), F32.sub(d, tau),
    Bool.pick(F32, Bool.and(sweep, F32.is_lt(d, 0.0)), F32.add(d, tau), d))

def Arc.of(+x1: F32, +y1: F32, +rx0: F32, +ry0: F32, +rot: F32, +large: Bool, +sweep: Bool, +x2: F32, +y2: F32) -> Arc:
  +phi = F32.div(F32.mul(rot, F32.pi()), 180.0)
  +cs = F32.cos(phi)
  +sn = F32.sin(phi)
  +dx = F32.div(F32.sub(x1, x2), 2.0)
  +dy = F32.div(F32.sub(y1, y2), 2.0)
  +xp = F32.add(F32.mul(cs, dx), F32.mul(sn, dy))
  +yp = F32.sub(F32.mul(cs, dy), F32.mul(sn, dx))
  +lam = F32.add(F32.div(F32.mul(xp, xp), F32.mul(rx0, rx0)), F32.div(F32.mul(yp, yp), F32.mul(ry0, ry0)))
  +grow = F32.max(F32.sqrt(lam), 1.0)
  +rx = F32.mul(rx0, grow)
  +ry = F32.mul(ry0, grow)
  +num = F32.sub(F32.sub(F32.mul(F32.mul(rx, rx), F32.mul(ry, ry)), F32.mul(F32.mul(rx, rx), F32.mul(yp, yp))), F32.mul(F32.mul(ry, ry), F32.mul(xp, xp)))
  +den = F32.add(F32.mul(F32.mul(rx, rx), F32.mul(yp, yp)), F32.mul(F32.mul(ry, ry), F32.mul(xp, xp)))
  +co = F32.mul(Bool.pick(F32, Bool.xor(large, sweep), 1.0, F32.neg(1.0)), F32.sqrt(F32.max(F32.div(num, F32.max(den, 0.000001)), 0.0)))
  +cxp = F32.div(F32.mul(co, F32.mul(rx, yp)), ry)
  +cyp = F32.neg(F32.div(F32.mul(co, F32.mul(ry, xp)), rx))
  +t0 = F32.atan2(F32.div(F32.sub(yp, cyp), ry), F32.div(F32.sub(xp, cxp), rx))
  +t1 = F32.atan2(F32.div(F32.sub(F32.neg(yp), cyp), ry), F32.div(F32.sub(F32.neg(xp), cxp), rx))
  Arc{F32.add(F32.sub(F32.mul(cs, cxp), F32.mul(sn, cyp)), F32.div(F32.add(x1, x2), 2.0)),
    F32.add(F32.add(F32.mul(sn, cxp), F32.mul(cs, cyp)), F32.div(F32.add(y1, y2), 2.0)),
    rx, ry, cs, sn, t0, Arc.dt(sweep, F32.sub(t1, t0))}

# a degenerate arc (a zero radius) is a straight line
def Arc.flat(line: Bool, +x1: F32, +y1: F32, +rx: F32, +ry: F32, +rot: F32, +large: Bool, +sweep: Bool, +x2: F32, +y2: F32, out: List<&2, Ln>) -> List<&2, Ln>:
  match line:
    case True{}:
      Ln{x1, y1, x2, y2, False{}} <> out
    case False{}:
      Arc.pieces(Arc.of(x1, y1, rx, ry, rot, large, sweep, x2, y2), out)

def Fl.to(f: Fl, +x: F32, +y: F32, k: F32 -> F32 -> List<&2, Ln> -> List<&2, Ln>) -> Fl:
  match f:
    case Fl{+px, +py, sx, sy, out}:
      Fl{x, y, sx, sy, k(px, py, out)}

def Fl.mv(f: Fl, +x: F32, +y: F32) -> Fl:
  match f:
    case Fl{+px, +py, +sx, +sy, out}:
      Fl{x, y, x, y, Ln{px, py, sx, sy, True{}} <> out}

def Fl.close(f: Fl) -> Fl:
  match f:
    case Fl{+px, +py, +sx, +sy, out}:
      Fl{sx, sy, sx, sy, Ln{px, py, sx, sy, False{}} <> out}

def Fl.seg(f: Fl, s: Seg) -> Fl:
  match s:
    case SM{+x, +y}:
      Fl.mv(f, x, y)
    case SL{+x, +y}:
      Fl.to(f, x, y, +px => +py => out => Ln{px, py, x, y, False{}} <> out)
    case SC{+x1, +y1, +x2, +y2, +x, +y}:
      Fl.to(f, x, y, +px => +py => out => Bez.cub(Bez.steps(), F32.from_nat(Bez.steps()), px, py, x1, y1, x2, y2, x, y, out))
    case SQ{+x1, +y1, +x, +y}:
      Fl.to(f, x, y, +px => +py => out => Bez.quad(Bez.steps(), F32.from_nat(Bez.steps()), px, py, x1, y1, x, y, out))
    case SA{+rx, +ry, +rot, +la, +sw, +x, +y}:
      Fl.to(f, x, y, +px => +py => out => Arc.flat(Bool.or(F32.is_le(rx, 0.0), F32.is_le(ry, 0.0)), px, py, rx, ry, rot, la, sw, x, y, out))
    case SZ{}:
      Fl.close(f)

def Fl.go(ss: List<&2, Seg>, f: Fl) -> Fl:
  match ss:
    case Nil{}:
      f
    case s <> t:
      Fl.go(t, Fl.seg(f, s))

def Fl.fin(f: Fl) -> List<&2, Ln>:
  match f:
    case Fl{+px, +py, +sx, +sy, out}:
      Ln{px, py, sx, sy, True{}} <> out

# the path as line segments, in path units (order not kept)
def Svg.flat(ss: List<&2, Seg>) -> List<&2, Ln>:
  Fl.fin(Fl.go(ss, Fl{0.0, 0.0, 0.0, 0.0, Nil{}}))

def Svg.within(+v: F32, +lo: F32, +hi: F32) -> Bool:
  Bool.and(F32.is_ge(v, lo), F32.is_le(v, hi))

def Svg.in1(l: Ln, +lo: F32, +hi: F32) -> Bool:
  match l:
    case Ln{+ax, +ay, +bx, +by, _}:
      Bool.and(Bool.and(Svg.within(ax, lo, hi), Svg.within(ay, lo, hi)), Bool.and(Svg.within(bx, lo, hi), Svg.within(by, lo, hi)))

# every point of the lines lies in the square [lo, hi]^2
def Svg.inside(ls: List<&2, Ln>, +lo: F32, +hi: F32) -> Bool:
  match ls:
    case Nil{}:
      True{}
    case l <> t:
      Bool.and(Svg.in1(l, lo, hi), Svg.inside(t, lo, hi))
