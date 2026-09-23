import Base
import ../../src/core/glb.bend as G
import ../../src/gfx/mesh.bend as M
import ../../src/gfx/draw.bend as D
import ../../src/server/proc.bend as P

# A KiCad board (or any GLB) through the 3D viewer core, to /tmp/glb.ppm.
#   bend test/native/glb_frame.bend -o build/glb_frame
#   build/glb_frame BOARD.kicad_pcb   # exports /tmp/glb.glb with kicad-cli
#   build/glb_frame MODEL.glb [yaw pitch]
# kicad-cli is $BACKPLANE_KICAD_CLI, else kicad-cli on PATH.

def W() -> U32:
  700

def H() -> U32:
  800

def env(r: Result<&1, &1, U32 & String, String>, d: String) -> String:
  match r:
    case Done{+v}:
      Bool.pick(String, String.is_empty(v), d, v)
    case Fail{_}:
      d

def ends(+s: String, +suf: String) -> Bool:
  String.eq(String.drop(s, Nat.sub(String.length(s), String.length(suf))), suf)

def many(xs: List<&1, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      x <> many(t)

def f32(m: Maybe<&2, String>, d: F32) -> F32:
  match m:
    case Some{s}:
      Maybe.default(&2, F32, F32.read(s), d)
    case None{}:
      d

# the recommended export: models, copper (tracks, pads, zones), soldermask
# and silkscreen; substitute STEP models; skip DNP parts
def export(+kicad: String, +pcb: String) -> IO(String):
  do IO<String>:
    r : P.Ran <- P.Proc.run(kicad, ["pcb", "export", "glb", "-f", "--subst-models", "--no-dnp", "--include-tracks", "--include-pads",
      "--include-zones", "--include-soldermask", "--include-silkscreen", "-o", "/tmp/glb.glb", pcb], "")
    return "/tmp/glb.glb"

def source(is_pcb: Bool, +path: String) -> IO(String):
  match is_pcb:
    case True{}:
      do IO<String>:
        e : Result<&1, &1, U32 & String, String> <- IO.get_env("BACKPLANE_KICAD_CLI")
        t0 : Nat <- IO.now()
        out : String <- export(env(e, "kicad-cli"), path)
        t1 : Nat <- IO.now()
        IO.print("kicad-cli export " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms")
        return out
    case False{}:
      IO.pure(String, path)

def cam(+c: M.Cam, +yaw: F32, +pitch: F32) -> M.Cam:
  match c:
    case M.Cam{_, _, d, tx, ty, tz, fov}:
      M.Cam{yaw, pitch, d, tx, ty, tz, fov}

def go(r: File & Result<&1, &1, U32 & String, List<&2, U32>>, +yaw: F32, +pitch: F32, +tr: Nat) -> IO(Unit):
  (f, res) = r
  do IO<Unit>:
    File.close(f)
    bs : List<&2, U32> <- IO.pass(List<&2, U32>, res)
    +t0 : Nat <- IO.now()
    +mesh : G.Mesh = G.Glb.parse(bs)
    +ts : List<&2, G.Tri3> = G.Mesh.tris(mesh)
    +n : Nat = List.length(&2, G.Tri3, ts)
    +t1 : Nat <- IO.now()
    +c : M.Cam = cam(M.Cam.fit(ts), yaw, pitch)
    +st : List<&2, M.STri> = M.Mesh.project(W(), H(), ts, c, True{})
    +k : Nat = List.length(&2, M.STri, st)
    +t2 : Nat <- IO.now()
    +img : Image = M.Mesh.raster(W(), H(), st, 2105384)
    +t3 : Nat <- IO.now()
    +img2 : Image = M.Mesh.render(W(), H(), ts, M.Cam.orbit(M.Cam.zoom(c, 0.9), 0.2, 0.0), 2105384)
    t4 : Nat <- IO.now()
    IO.print("read " ++ Nat.show(Nat.sub(t0, tr)) ++ " ms; parse " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms (" ++ Nat.show(n) ++ " tris, " ++ Nat.show(List.length(&2, String, G.Mesh.parts(mesh))) ++ " parts); project "
      ++ Nat.show(Nat.sub(t2, t1)) ++ " ms (" ++ Nat.show(k) ++ " on screen); raster " ++ Nat.show(Nat.sub(t3, t2)) ++ " ms; render again " ++ Nat.show(Nat.sub(t4, t3)) ++ " ms")
    g : File <- IO.try(File, File.open("/tmp/glb.ppm", "w"))
    w : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(g, D.Snap.ppm(img, W(), H()))
    g2 : File <- IO.try(File, File.open("/tmp/glb2.ppm", "w"))
    w2 : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(g2, D.Snap.ppm(img2, W(), H()))
    return Unit{}

def main() -> IO(Unit):
  do IO<Unit>:
    as : List<&1, String> <- IO.args()
    +args : List<&2, String> = many(as)
    +arg : String = Maybe.default(&2, String, List.head(&2, String, args), "/tmp/glb.glb")
    path : String <- source(ends(arg, ".kicad_pcb"), arg)
    +yaw : F32 = f32(List.get(&2, String, args, 1n), 0.3)
    +pitch : F32 = f32(List.get(&2, String, args, 2n), 0.95)
    f : File <- IO.try(File, File.open(path, "r"))
    +tr : Nat <- IO.now()
    r : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(f, 400000000)
    go(r, yaw, pitch, tr)
