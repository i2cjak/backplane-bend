import Base
import ../src/server/server.bend as S
import ../src/server/kicad.bend as K
import ../src/core/model.bend as M

# prints the instructions a thread in the given directory would get
def main() -> IO(Unit):
  do IO<Unit>:
    +user : String <- S.Env.get("HOME", "/tmp")
    +exe : String <- S.Sys.exe_dir.io()
    +dir : String <- S.Env.get("PROMPT_DIR", ".")
    b : S.Boot <- S.Main.prepare(user, exe)
    fs : K.Files <- K.Files.read(dir)
    IO.print(S.Hub.prompt(S.Main.config(user, exe, Nil{}, b), M.State.empty(), "t1", dir, fs))
