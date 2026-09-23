import Base
import ./server.bend as S
import ../core/prompt.bend as Q
import ./plot.bend as PV

# `backplane serve`: the hub and the web server, no window.

def start(args: List<String>) -> IO(Unit):
  do IO<Unit>:
    +user : String <- S.Env.get("HOME", "/tmp")
    +exe : String <- S.Sys.exe_dir.io()
    b : S.Boot <- S.Main.prepare(user, exe)
    S.Main.boot(S.Main.config(user, exe, args, b), True{}, i => IO.pure(Unit, Unit{}))

# (`--plot KIND FILE` is the hub's own board reader, src/server/plot.bend)
def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    PV.Pv.main(args, a => start(a))
