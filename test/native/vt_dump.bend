import Base
import ../../src/core/vt.bend as V
import ../../src/server/host.bend as H
import ../../src/server/pty.bend as P

# Runs a command on an 80x24 pty for a moment (then SIGKILL), feeds what it
# drew into the emulator, and prints the screen: a quick look at how real
# programs (vim, less, htop, git) come out.
#   bend test/native/vt_dump.bend -o build/vt_dump && build/vt_dump -- vim -u NONE file

def args.copy(xs: List<&1, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      x <> args.copy(t)

def runs.show(rs: List<&2, V.VRun>) -> String:
  match rs:
    case Nil{}:
      ""
    case V.VRun{t, _, _, _, _} <> r:
      t ++ runs.show(r)

def show(ls: List<&2, V.VLine>) -> IO(Unit):
  match ls:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case V.VLine{rs} <> t:
      do IO<Unit>:
        IO.print("|" ++ runs.show(rs))
        show(t)

def got(r: Socket & Result<&1, &1, U32 & String, List<&2, U32>>, v: V.Vt, k: Socket -> V.Vt -> IO(Socket & V.Vt)) -> IO(Socket & V.Vt):
  (s, res) = r
  match res:
    case Done{Nil{}}:
      IO.pure(Socket & V.Vt, (s, v))
    case Done{bs}:
      k(s, V.Vt.feed(v, bs))
    case Fail{_}:
      IO.pure(Socket & V.Vt, (s, v))

def read(fuel: Nat, s: Socket, v: V.Vt) -> IO(Socket & V.Vt):
  match fuel:
    case 0n:
      IO.pure(Socket & V.Vt, (s, v))
    case 1n+f:
      IO.bind(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, Socket & V.Vt, H.Sock.recv_bytes(s, 65536),
        r => got(r, v, s2 => v2 => read(f, s2, v2)))

def killer(+pid: U32) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(1500)
    H.Proc.kill(pid, 9)

def fin(r: Socket & V.Vt) -> IO(Unit):
  (s, +v) = r
  do IO<Unit>:
    Socket.close(s)
    IO.print("title: " ++ V.Vt.title(v))
    show(V.Vt.lines(v, 0n))

def started.k(st: U32 & Socket) -> IO(Unit):
  (+pid, s) = st
  do IO<Unit>:
    IO.spawn(Unit, killer(pid))
    r : Socket & V.Vt <- read(100000n, s, V.Vt.new(80, 24))
    fin(r)

def started(r: Result<&1, &1, U32 & String, U32 & Socket>) -> IO(Unit):
  match r:
    case Done{st}:
      started.k(st)
    case Fail{e}:
      IO.print("spawn failed")

def run(xs: List<&2, String>) -> IO(Unit):
  match xs:
    case Nil{}:
      IO.print("usage: vt_dump -- CMD ARGS...")
    case c <> t:
      IO.bind(Result<&1, &1, U32 & String, U32 & Socket>, Unit, P.Pty.spawn(c, t, "", 80, 24), started)

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<String> <- IO.args()
    run(args.copy(xs))
