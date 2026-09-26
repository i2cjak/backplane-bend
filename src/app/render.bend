import Base
import ../server/server.bend as S
import ../server/kicad.bend as K
import ../server/proc.bend as P
import ../core/glb.bend as G
import ../core/mech.bend as MC
import ../core/png.bend as PN
import ../gfx/mesh.bend as MS
import ../gfx/draw.bend as D
import ./parts3.bend as PT

# `backplane --render MODEL [--size WxH]`: a part's standard views as PNG
# files, for agents to check their work and the Mechanical page to show.
# A STEP is converted once (the models cache, as a board's parts are) and
# stood Z up; a GLB is read as it is. Each view (core/mech.bend's
# Mech.views) is fitted to the whole part, drawn by the 3D viewer's own
# rasterizer and written to renders/<stem>.<view>.png beside the model.
# Prints each file's path; nothing is installed or needed besides
# Backplane.

def Render.ground() -> U32:
  2105384

def Render.num(+s: String, +i: Nat, +d: U32) -> U32:
  Maybe.default(&2, U32, U32.read(Maybe.default(&2, String, List.get(&2, String, String.split(s, 'x'), i), "")), d)

# the value after a flag ("" without one)
def Render.opt(xs: List<&2, String>, +flag: String) -> String:
  match xs:
    case +k <> +v <> +t:
      Bool.pick(String, String.eq(k, flag), v, Render.opt(v <> t, flag))
    case _:
      ""

def Render.wrote(r: File & Result<&1, &1, U32 & String, Unit>) -> Bool:
  (_, res) = r
  match res:
    case Done{_}:
      True{}
    case Fail{_}:
      False{}

def Render.write.k(f: Result<&1, &1, U32 & String, File>, bs: List<&2, U32>) -> IO(Bool):
  match f:
    case Done{h}:
      do IO<Bool>:
        r : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(h, bs)
        return Render.wrote(r)
    case Fail{_}:
      IO.pure(Bool, False{})

def Render.write(+path: String, bs: List<&2, U32>) -> IO(Bool):
  do IO<Bool>:
    f : Result<&1, &1, U32 & String, File> <- File.open(path ++ ".part", "w")
    ok : Bool <- Render.write.k(f, bs)
    mv : P.Ran <- P.Proc.run("mv", ["-f", path ++ ".part", path], "/")
    return ok

def Render.said(ok: Bool, +out: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.print(out)
    case False{}:
      IO.print_err("backplane --render: could not write " ++ out)

def Render.view(vs: List<&2, MC.MView>, +m: MS.Model, +c: MS.Cam, +model: String, +w: U32, +h: U32) -> IO(Unit):
  match vs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case MC.MView{+name, +yaw, +pitch} <> t:
      do IO<Unit>:
        +out : String = MC.Mech.render(model, name)
        ok : Bool <- Render.write(out, PN.Png.rgb(D.Snap.rgb(MS.Mesh.render(w, h, m, MS.Cam.face(c, yaw, pitch), Render.ground()), w, h), w, h))
        Render.said(ok, out)
        Render.view(t, m, c, model, w, h)

def Render.tris.k(step: Bool, ts: List<&2, G.Tri3>) -> List<&2, G.Tri3>:
  match step:
    case True{}:
      MC.Mech.upright(ts)
    case False{}:
      ts

def Render.tris(+step: Bool, bs: List<&2, U32>) -> List<&2, G.Tri3>:
  Render.tris.k(step, G.Mesh.tris(G.Glb.parse(bs)))

def Render.go.k(none: Bool, +model: String, +glb: String, +w: U32, +h: U32) -> IO(Unit):
  match none:
    case True{}:
      IO.die(Unit, 1, "backplane --render: could not read " ++ model ++ " (a STEP or GLB file)")
    case False{}:
      do IO<Unit>:
        bs : List<&2, U32> <- K.Io.bytes(glb)
        +m : MS.Model = MS.Model.of(Render.tris(MC.Mech.is_step(model), bs))
        r : P.Ran <- P.Proc.run("mkdir", ["-p", MC.Mech.parent(MC.Mech.render(model, "iso"))], "/")
        Render.view(MC.Mech.views(), m, MS.Model.fit(m), model, w, h)

def Render.go(+model: String, +glb: String, +w: U32, +h: U32) -> IO(Unit):
  Render.go.k(String.is_empty(glb), model, glb, w, h)

def Render.abs(+cwd: String, +p: String) -> String:
  Bool.pick(String, String.starts_with(p, "/"), p, cwd ++ "/" ++ p)

# the working directory (pwd run in "."; $PWD can be stale in a child)
def Render.cwd(r: P.Ran) -> String:
  match r:
    case P.Ran{0, +out}:
      String.trim(out)
    case _:
      "/"

def Render.run(+model: String, +size: String) -> IO(Unit):
  do IO<Unit>:
    here : P.Ran <- P.Proc.run("pwd", ["-P"], ".")
    +path : String = Render.abs(Render.cwd(here), model)
    +step : String <- PT.Parts.step2glb()
    +cache : String <- PT.Parts.cache()
    mk : P.Ran <- P.Proc.run("mkdir", ["-p", cache], "/")
    +glb : String <- PT.Parts.glb(path, cache, step)
    Render.go(path, glb, Render.num(size, 0n, 1200), Render.num(size, 1n, 900))

def Render.usage() -> IO(Unit):
  IO.die(Unit, 2, "usage: backplane --render MODEL.step [--size WxH]  (writes renders/<name>.<view>.png beside it)")

def Render.main(xs: List<&2, String>) -> IO(Unit):
  match xs:
    case _ <> +model <> +rest:
      Bool.pick(IO(Unit), String.starts_with(model, "--"), Render.usage(), Render.run(model, Render.opt(rest, "--size")))
    case _:
      Render.usage()

# whether the program was started to render
def Render.wants(xs: List<&2, String>) -> Bool:
  match xs:
    case +a <> _:
      String.eq(a, "--render")
    case _:
      False{}
