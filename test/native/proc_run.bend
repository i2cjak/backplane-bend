import Base
import ../../src/server/proc.bend as P
import ../../src/server/host.bend as H

def show(r: P.Ran) -> String:
  match r:
    case P.Ran{code, out}:
      "code=" ++ U32.show(code) ++ " out=" ++ out

def main() -> IO(Unit):
  do IO<Unit>:
    a : P.Ran <- P.Proc.run("echo", ["héllo", "wörld ✓"], "")
    IO.print(show(a))
    b : P.Ran <- P.Proc.run("git", ["--version"], "/tmp")
    IO.print(show(b))
    c : P.Ran <- P.Proc.run("sh", ["-c", "exit 3"], "")
    IO.print(show(c))
    d : P.Ran <- P.Proc.run("definitely-not-a-cmd", [], "")
    IO.print(show(d))
    t : U32 <- H.Clock.epoch()
    IO.print("epoch " ++ U32.show(t))
