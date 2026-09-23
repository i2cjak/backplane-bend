import Base
import ./server.bend as S
import ../core/prompt.bend as Q

# `backplane serve`: the hub and the web server, no window.

def main() -> IO(Unit):
  do IO<Unit>:
    +user : String <- S.Env.get("HOME", "/tmp")
    exe : String <- S.Sys.exe_dir.io()
    args : List<String> <- IO.args()
    ks : String & List<&2, Q.Skill> <- S.Skills.kistack(user)
    kicad : String <- S.Env.get("BACKPLANE_KICAD_CLI", "kicad-cli")
    S.Main.boot(S.Main.config(user, exe, args, ks, kicad), True{}, i => IO.pure(Unit, Unit{}))
