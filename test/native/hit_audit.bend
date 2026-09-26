import Base
import ../../src/core/json.bend as J
import ../../src/core/utf8.bend as U8
import ../../src/core/client.bend as U
import ../../src/app/nui.bend as S
import ../../src/app/layout.bend as L

# Hit regions another one covers: lays a frame out from an event log (as
# ui_snap does, with the timeline's memo) and samples every region on a
# 4 px grid; a region the pointer reaches on less than 70% of its area is
# printed with what wins the rest. A click there does something else (the
# "Show earlier" label once lost to the timeline's lines this way).
#   hit_audit EVENTS THREAD FLAGS [W H]   (FLAGS as ui_snap's; "-" none)

def items(ls: List<&2, String>) -> List<&2, J.Json>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> t:
      Maybe.default(&2, J.Json, J.Json.parse(l), J.Null{}) <> items(t)

def lines(r: U8.Lines & List<&2, String>) -> List<&2, String>:
  (_, ls) = r
  ls

def act.k(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u2, _}:
      u2

def flag.k(ps: List<&2, String>, u: U.Ui) -> U.Ui:
  match ps:
    case +a <> +v <> _:
      act.k(U.Ui.act(u, a, v))
    case +f <> Nil{}:
      act.k(U.Ui.act(u, "flag", f))
    case Nil{}:
      u

def flag(skip: Bool, u: U.Ui, +f: String) -> U.Ui:
  match skip:
    case True{}:
      u
    case False{}:
      flag.k(String.split(f, ':'), u)

def flags(fs: List<&2, String>, u: U.Ui) -> U.Ui:
  match fs:
    case Nil{}:
      u
    case +f <> t:
      flags(t, flag(String.eq(f, "-"), u, f))

def ui_of(bs: List<&2, U32>, +sel: String, +fl: String) -> U.Ui:
  flags(String.split(fl, ','), act.k(U.Ui.act(U.Ui.recv(U.Ui.init(U32.to_nat(1790180000)), J.Json.obj([J.KV{"t", J.Str{"log"}}, J.KV{"version", J.Str{"0.1.0"}},
    J.KV{"items", J.Json.arr(items(lines(U8.Lines.feed(U8.Lines.new(), bs))))}])), "select", sel)))

def hits(o: L.Out) -> List<&2, S.Hit>:
  match o:
    case L.Out{_, hs}:
      hs

def same(a: S.Hit, b: S.Hit) -> Bool:
  match a b:
    case S.Hit{ax0, ay0, ax1, ay1, aa, av} S.Hit{bx0, by0, bx1, by1, ba, bv}:
      Bool.and(Bool.and(Bool.and(U32.is_eq(ax0, bx0), U32.is_eq(ay0, by0)), Bool.and(U32.is_eq(ax1, bx1), U32.is_eq(ay1, by1))),
        Bool.and(String.eq(aa, ba), String.eq(av, bv)))

def name(h: S.Hit) -> String:
  match h:
    case S.Hit{+x0, +y0, x1, y1, a, v}:
      a ++ "(" ++ v ++ ") " ++ U32.show(x0) ++ "," ++ U32.show(y0) ++ " " ++ U32.show((x1 - x0 : U32)) ++ "x" ++ U32.show((y1 - y0 : U32))

# a sample's verdict: 1 when h itself is on top there, else what is
type Top is Data:
  Top{mine: Nat, other: String}

def top.k(m: Maybe<&2, S.Hit>, +h: S.Hit, t: Top) -> Top:
  match m t:
    case Some{+g} Top{+n, +o}:
      Bool.pick(Top, same(g, h), Top{1n+n, o}, Top{n, Bool.pick(String, String.is_empty(o), name(g), o)})
    case None{} Top{n, o}:
      Top{n, o}

def row(k: Nat, +hs: List<&2, S.Hit>, +h: S.Hit, +x: U32, +y: U32, t: Top) -> Top:
  match k:
    case 0n:
      t
    case 1n+r:
      row(r, hs, h, (x + 4 : U32), y, top.k(S.Hit.find(hs, x, y), h, t))

def rows(k: Nat, +cols: Nat, +hs: List<&2, S.Hit>, +h: S.Hit, +x: U32, +y: U32, t: Top) -> Top:
  match k:
    case 0n:
      t
    case 1n+r:
      rows(r, cols, hs, h, x, (y + 4 : U32), row(cols, hs, h, x, y, t))

def steps(+a: U32, +b: U32) -> Nat:
  U32.to_nat(((b - a + 3 : U32) / 4 : U32))

def report(t: Top, +h: S.Hit, +total: Nat) -> List<&2, String>:
  match t:
    case Top{+n, +o}:
      Bool.pick(List<&2, String>, Bool.or(Bool.or(Nat.is_eq(total, 0n), Nat.is_ge(Nat.mul(n, 10n), Nat.mul(total, 7n))), String.starts_with(o, "menu(")), Nil{},
        ["covered " ++ Nat.show(Nat.div(Nat.mul(Nat.sub(total, n), 100n), total)) ++ "%: " ++ name(h) ++ " under " ++ o])

# timeline lines are the ground everything sits on, an open menu's box
# and a dialog's ("") the ground under their rows: their own cover is fine
def audit.k(+hs: List<&2, S.Hit>, h: S.Hit) -> List<&2, String>:
  match h:
    case S.Hit{+x0, +y0, +x1, +y1, +a, +v}:
      Bool.pick(List<&2, String>, Bool.or(Bool.or(String.eq(a, "tl-line"), String.eq(a, "menu")), String.is_empty(a)), Nil{},
        report(rows(steps(y0, y1), steps(x0, x1), hs, S.Hit{x0, y0, x1, y1, a, v}, x0, y0, Top{0n, ""}), S.Hit{x0, y0, x1, y1, a, v}, Nat.mul(steps(y0, y1), steps(x0, x1))))

# a region over the whole window is a modal's scrim: what lies under it
# is meant to be out of reach, so the audit stops there
def whole(h: S.Hit, +w: U32, +hh: U32) -> Bool:
  match h:
    case S.Hit{x0, y0, x1, y1, _, _}:
      Bool.and(Bool.and(U32.is_eq(x0, 0), U32.is_eq(y0, 0)), Bool.and(U32.is_ge(x1, w), U32.is_ge(y1, hh)))

def audit.step(stop: Bool, rest: List<&2, String>, h: S.Hit, +hs: List<&2, S.Hit>) -> List<&2, String>:
  match stop:
    case True{}:
      Nil{}
    case False{}:
      List.append(&2, String, audit.k(hs, h), rest)

def audit(xs: List<&2, S.Hit>, +hs: List<&2, S.Hit>, +w: U32, +hh: U32) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case +h <> t:
      audit.step(whole(h, w, hh), audit(t, hs, w, hh), h, hs)

def say(ls: List<&2, String>) -> IO(Unit):
  match ls:
    case Nil{}:
      IO.print("ok hit audit: nothing covered")
    case _:
      IO.print(String.join(ls, "\n"))

def arg(+xs: List<&2, String>, +i: Nat) -> String:
  Maybe.default(&2, String, List.head(&2, String, List.drop(&2, String, xs, i)), "")

def copy(xs: List<&1, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      x <> copy(t)

def read.k(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(List<&2, U32>):
  (f, res) = r
  do IO<List<&2, U32>>:
    File.close(f)
    bs : List<&2, U32> <- IO.pass(List<&2, U32>, res)
    return bs

def read(+path: String) -> IO(List<&2, U32>):
  do IO<List<&2, U32>>:
    f : File <- IO.try(File, File.open(path, "r"))
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 100000000)
    read.k(r)

def go(+as: List<&2, String>) -> IO(Unit):
  do IO<Unit>:
    bs : List<&2, U32> <- read(arg(as, 0n))
    +ty : L.Ty <- L.Ty.load()
    +ww : U32 = Maybe.default(&2, U32, U32.read(arg(as, 3n)), 1400)
    +hh : U32 = Maybe.default(&2, U32, U32.read(arg(as, 4n)), 860)
    +n : S.Nui = S.Nui.init(ui_of(bs, arg(as, 1n), arg(as, 2n)), ww, hh)
    +hs : List<&2, S.Hit> = hits(L.Lay.frame(ty, L.TL.memos.now(L.Lay.memos(ty, n, Nil{})), n))
    IO.print(Nat.show(List.length(&2, S.Hit, hs)) ++ " hit regions")
    say(audit(hs, hs, ww, hh))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    go(copy(args))
