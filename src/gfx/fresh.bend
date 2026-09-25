import Base
import ./raster.bend as R

# A frame drawn from scratch over every core: a viewer's base, redrawn on
# each pan and zoom. R.Frame.render forks by quadrant, and a fork's work
# stays on the core it was dealt to, so a panel in one corner of the
# quadtree ran on a core or two. Here the ops are split down to 64-px
# blocks first (the same cuts R.Frame.render makes), the blocks that any
# op reaches are dealt round robin into a balanced tree and drawn in
# parallel, each as R.Frame.render draws that region, and the frame is put
# together from them; a block no op reaches is the background.

# a block's size, as a power of two
def Fresh.e() -> Nat:
  6n

# the frame cut into blocks: background, a block to draw (its ops and
# corner), or four quarters (n: blocks to draw under it)
type FPlan is Data:
  FBg{}
  FBlock{ops: List<&2, R.Op>, rx: U32, ry: U32}
  FNode{n: Nat, a: FPlan, b: FPlan, c: FPlan, d: FPlan}

def FPlan.count(p: FPlan) -> Nat:
  match p:
    case FBg{}:
      0n
    case FBlock{_, _, _}:
      1n
    case FNode{n, _, _, _, _}:
      n

def FPlan.node(+a: FPlan, +b: FPlan, +c: FPlan, +d: FPlan) -> FPlan:
  FNode{Nat.add(Nat.add(FPlan.count(a), FPlan.count(b)), Nat.add(FPlan.count(c), FPlan.count(d))), a, b, c, d}

def Fresh.split(f: R.Four, k: List<&2, R.Op> -> List<&2, R.Op> -> List<&2, R.Op> -> List<&2, R.Op> -> FPlan) -> FPlan:
  match f:
    case R.Four{a, b, c, d}:
      k(a, b, c, d)

# the region at (rx, ry), 2^k blocks wide (n pixels), of ops that reach it;
# none: no op does
def FPlan.of(k: Nat, none: Bool, +ops: List<&2, R.Op>, +rx: U32, +ry: U32, +n: U32) -> FPlan:
  match k none:
    case _ True{}:
      FBg{}
    case 0n False{}:
      FBlock{ops, rx, ry}
    case 1n+j0 False{}:
      +j = j0
      +h = U32.shr(n)
      Fresh.split(R.Four.go(ops, rx, ry, h), +a => +b => +c => +d =>
        FPlan.node(FPlan.of(j, List.is_empty(&2, R.Op, a), a, rx, ry, h), FPlan.of(j, List.is_empty(&2, R.Op, b), b, (rx + h : U32), ry, h),
          FPlan.of(j, List.is_empty(&2, R.Op, c), c, rx, (ry + h : U32), h), FPlan.of(j, List.is_empty(&2, R.Op, d), d, (rx + h : U32), (ry + h : U32), h)))

# a block to draw
type FJob is Data:
  FJob{ops: List<&2, R.Op>, rx: U32, ry: U32}

# the blocks to draw, in the plan's order
def FPlan.jobs(p: FPlan, acc: List<&2, FJob>) -> List<&2, FJob>:
  match p:
    case FBg{}:
      acc
    case FBlock{o, x, y}:
      FJob{o, x, y} <> acc
    case FNode{_, a, b, c, d}:
      FPlan.jobs(a, FPlan.jobs(b, FPlan.jobs(c, FPlan.jobs(d, acc))))

# jobs dealt into a balanced tree: the i-th is found by i's bits, lowest
# first (as tiles.bend deals its tiles)
type FJobs is Data:
  FJNone{}
  FJOne{j: FJob}
  FJTwo{a: FJobs, b: FJobs}

type FHalves is Data:
  FHalves{even: List<&2, FJob>, odd: List<&2, FJob>}

def FHalves.cons(x: FJob, h: FHalves) -> FHalves:
  match h:
    case FHalves{a, b}:
      FHalves{x <> b, a}

def FHalves.of(xs: List<&2, FJob>) -> FHalves:
  match xs:
    case Nil{}:
      FHalves{Nil{}, Nil{}}
    case x <> t:
      FHalves.cons(x, FHalves.of(t))

def FJobs.deal(+d: Nat, h: FHalves) -> FJobs:
  match d h:
    case _ FHalves{Nil{}, Nil{}}:
      FJNone{}
    case _ FHalves{x <> Nil{}, Nil{}}:
      FJOne{x}
    case 0n _:
      FJNone{}
    case 1n+k FHalves{a, b}:
      FJTwo{FJobs.deal(k, FHalves.of(a)), FJobs.deal(k, FHalves.of(b))}

# what the jobs drew, in the same tree
type FDrawn is Data:
  FDNone{}
  FDOne{img: Image}
  FDTwo{a: FDrawn, b: FDrawn}

# a block drawn as R.Frame.render draws its region
def FJob.draw(j: FJob, +bg: U32) -> Image:
  match j:
    case FJob{+o, +x, +y}:
      R.Region.node(Fresh.e(), R.Region.leaf(o, x, y, U32.shln(1, Fresh.e())), o, x, y, U32.shln(1, Fresh.e()), Pix{bg})

def FJobs.run(t: FJobs, +bg: U32) -> FDrawn:
  match t:
    case FJNone{}:
      FDNone{}
    case FJOne{j}:
      FDOne{FJob.draw(j, bg)}
    case FJTwo{a, b}:
      x y = FJobs.run(a, bg) FJobs.run(b, bg)
      FDTwo{x, y}

# the bits of i, lowest first
def Fresh.path(+d: Nat, +i: Nat) -> List<&2, Bool>:
  match d:
    case 0n:
      Nil{}
    case 1n+k:
      Nat.is_eq(Nat.mod(i, 2n), 1n) <> Fresh.path(k, Nat.div(i, 2n))

def FDrawn.get(t: FDrawn, path: List<&2, Bool>, +bg: U32) -> Image:
  match t path:
    case FDOne{img} _:
      img
    case FDTwo{a, _} False{} <> r:
      FDrawn.get(a, r, bg)
    case FDTwo{_, b} True{} <> r:
      FDrawn.get(b, r, bg)
    case _ _:
      Pix{bg}

# the plan's image, its blocks taken from what was drawn (the first under
# p is the off-th job)
def FPlan.fill(p: FPlan, +off: Nat, +d: FDrawn, +bg: U32) -> Image:
  match p:
    case FBg{}:
      Pix{bg}
    case FBlock{_, _, _}:
      FDrawn.get(d, Fresh.path(24n, off), bg)
    case FNode{_, +a, +b, +c, +dd}:
      Qua{FPlan.fill(a, off, d, bg), FPlan.fill(b, Nat.add(off, FPlan.count(a)), d, bg),
        FPlan.fill(c, Nat.add(Nat.add(off, FPlan.count(a)), FPlan.count(b)), d, bg),
        FPlan.fill(dd, Nat.add(Nat.add(Nat.add(off, FPlan.count(a)), FPlan.count(b)), FPlan.count(c)), d, bg)}

def Fresh.fill(+p: FPlan, +d: FDrawn, +bg: U32) -> Image:
  FPlan.fill(p, 0n, d, bg)

# the w x h frame of ops (topmost first) over a solid background: the
# image R.Frame.render(w, h, ops, bg) draws, drawn over every core
def Fresh.frame(+w: U32, +h: U32, +ops: List<&2, R.Op>, +bg: U32) -> Image:
  +p = FPlan.of(Nat.sub(R.Frame.depth(w, h), Fresh.e()), List.is_empty(&2, R.Op, ops), ops, 0, 0, U32.shln(1, R.Frame.depth(w, h)))
  Fresh.fill(p, FJobs.run(FJobs.deal(24n, FHalves.of(FPlan.jobs(p, Nil{}))), bg), bg)
