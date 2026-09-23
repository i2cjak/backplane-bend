import Base
import ./server.bend as S
import ../core/prompt.bend as Q

# `backplane serve`: the hub and the web server, no window.

def main() -> IO(Unit):
  do IO<Unit>:
    +user : String <- S.Env.get("HOME", "/tmp")
    +exe : String <- S.Sys.exe_dir.io()
    args : List<String> <- IO.args()
    b : S.Boot <- S.Main.prepare(user, exe)
    S.Main.boot(S.Main.config(user, exe, args, b), True{}, i => IO.pure(Unit, Unit{}))
