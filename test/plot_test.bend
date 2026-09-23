import Base
import ./check.bend as C
import ../src/core/board.bend as B
import ../src/core/plot.bend as P
import ../src/core/utf8.bend as U

def board(+seg: String) -> String:
  "(kicad_pcb (version 20240108)
  (segment (start 10 10) (end 20 10) (width 0.25) (layer \"F.Cu\") (net 1) (uuid \"s1\"))
  (segment (start " ++ seg ++ ") (end 30 30) (width 0.25) (layer \"F.Cu\") (net 1) (uuid \"s2\"))
  (segment (start 5 5) (end 6 6) (width 0.5) (layer \"B.Cu\") (net 1) (uuid \"s3\"))
  (via (at 20 10) (size 0.6) (drill 0.3) (layers \"F.Cu\" \"B.Cu\") (net 1) (uuid \"v1\"))
  (gr_rect (start 0 0) (end 40 40) (stroke (width 0.1) (type default)) (fill none) (layer \"Edge.Cuts\") (uuid \"e1\"))
  (gr_line (start 1 1) (end 2 2) (stroke (width 0.1) (type default)) (layer \"F.CrtYd\") (uuid \"hidden\"))
  (zone (net 1) (net_name \"GND\") (layer \"F.Cu\") (uuid \"z1\")
    (filled_polygon (layer \"F.Cu\") (pts (xy 1 1) (xy 9 1) (xy 9 -4) (xy 1 -4))))
)"

def items(m: Maybe<&2, List<&2, B.Item>>) -> List<&2, B.Item>:
  match m:
    case Some{xs}:
      xs
    case None{}:
      Nil{}

def plot(+seg: String) -> P.Plot:
  P.Plot.of(items(B.Board.items(U.Utf8.encode(board(seg)))), 0)

def chunks(+seg: String) -> List<&2, P.Chunk>:
  P.Plot.chunks(plot(seg))

def strs(xs: List<&2, U32>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      U32.show(x) <> strs(t)

def nums(xs: List<&2, U32>) -> String:
  String.join(strs(xs), ",")

def box(b: P.Box) -> String:
  match b:
    case P.Box{x0, y0, x1, y1}:
      nums([x0, y0, x1, y1])

def eqs(xs: List<&2, P.Chunk>, ys: List<&2, P.Chunk>) -> Bool:
  match xs ys:
    case Nil{} Nil{}:
      True{}
    case +x <> xt +y <> yt:
      Bool.and(P.Eq.chunk(x, y), eqs(xt, yt))
    case _ _:
      False{}

def desc(c: P.Chunk) -> String:
  match c:
    case P.Chunk{_, l, _, a, m, w, d}:
      U32.show(l) ++ "/" ++ U32.show(m) ++ "/" ++ U32.show(w) ++ ":" ++ nums(P.Dec.nums(String.reverse(d)))

def descs(cs: List<&2, P.Chunk>) -> List<&2, String>:
  match cs:
    case Nil{}:
      Nil{}
    case c <> t:
      desc(c) <> descs(t)

def main() -> IO(Unit):
  do IO<Unit>:
    +ns : List<&2, U32> = [0, 1, 31, 32, 1023, 1024, 123456789, 4294967295]
    C.Check.str("numbers round trip", nums(P.Dec.nums(P.Enc.text(ns))), nums(ns))
    C.Check.str("zigzag", nums([P.Num.zig(0), P.Num.zig(4294967295), P.Num.zig(1), P.Num.zig(4294967294)]), "0,1,2,3")
    C.Check.str("unzig", nums([P.Num.unzig(3), P.Num.unzig(4)]), "4294967294,2")
    C.Check.str("digits", P.Enc.text([0, 25, 26, 51, 52, 61, 62, 63]), "AZazB0B9B-B_B")
    +a : List<&2, P.Chunk> = chunks("20 10")
    # paint order: B.Cu (5), then F.Cu (12) fill before strokes (the two
    # tracks in two buckets), Edge.Cuts (22), vias (23), holes (24); the
    # courtyard is hidden, so not there. Numbers: a path's point count,
    # then zigzag deltas of micrometres; a dot is its point
    C.Check.str("chunks", String.join(descs(a), " | "),
      "5/1/500:2,10000,10000,2000,2000 | 12/0/0:4,2000,2000,16000,0,0,9999,15999,0 | 12/1/250:2,40000,20000,20000,40000 | 12/1/250:2,20000,20000,20000,0 | 22/1/100:5,0,0,80000,0,0,80000,79999,0,0,79999 | 23/2/600:40000,20000 | 24/2/300:40000,20000")
    C.Check.str("unchanged sends nothing", Nat.show(P.Plot.fresh(P.Plot.delta(a, a))), "0")
    C.Check.str("first plot sends all", Nat.show(P.Plot.fresh(P.Plot.delta(a, Nil{}))), Nat.show(List.length(&2, P.Chunk, a)))
    +b : List<&2, P.Chunk> = chunks("21 10")
    C.Check.str("one edit, one chunk", Nat.show(P.Plot.fresh(P.Plot.delta(b, a))), "1")
    C.Check.str("delta rebuilds", Bool.show(eqs(P.Plot.apply(P.Plot.delta(b, a), a), b)), "True")
    C.Check.str("message", P.Plot.msg("0|/p|", P.Box{0, 4294967295, 7, 8}, [P.Keep{2n}, P.Fresh{P.Chunk{0, 12, 5, 200, 1, 250, "BA"}}]),
      "{\"t\":\"plot\",\"key\":\"0|/p|\",\"box\":[0,-1,7,8],\"cs\":[2,{\"l\":12,\"c\":5,\"a\":200,\"m\":1,\"w\":250,\"d\":\"AB\"}]}")
    # what a child process prints, scanned back by the hub, is the plot
    +pl : P.Plot = plot("20 10")
    +back : P.Plot = P.Scan.plot(P.Line.plot(pl))
    C.Check.str("lines round trip", Bool.show(eqs(P.Plot.chunks(back), P.Plot.chunks(pl))), "True")
    C.Check.str("lines keep the box", box(P.Plot.box(back)), box(P.Plot.box(pl)))
    C.Check.str("box", box(P.Plot.box(pl)), "0,4294963296,40000,40000")
