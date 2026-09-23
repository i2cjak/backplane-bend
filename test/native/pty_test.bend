import Base
import ../../src/core/vt.bend as V
import ../../src/core/utf8.bend as U
import ../../src/server/host.bend as H
import ../../src/server/pty.bend as P

# Real programs on a real pty, read into the emulator. Prints ok / FAIL
# lines and exits non-zero on any failure.
#   bend test/native/pty_test.bend -o build/pty_test && build/pty_test

def runs.text(rs: List<&2, V.VRun>) -> String:
  match rs:
    case Nil{}:
      ""
    case V.VRun{t, _, _, _, _} <> r:
      t ++ runs.text(r)

# the first n rows' text, joined by "|"
def lines.text(n: Nat, ls: List<&2, V.VLine>) -> String:
  match n ls:
    case 0n _:
      ""
    case _ Nil{}:
      ""
    case 1n V.VLine{rs} <> _:
      runs.text(rs)
    case 1n+p V.VLine{rs} <> r:
      runs.text(rs) ++ "|" ++ lines.text(p, r)

def screen(+v: V.Vt, n: Nat) -> String:
  lines.text(n, V.Vt.lines(v, 0n))

def color.pick(rs: List<&2, V.VRun>, hit: Bool, +f: U32, +t: String) -> String:
  match rs hit:
    case _ True{}:
      U32.show(f)
    case Nil{} False{}:
      "(none)"
    case V.VRun{+x, g, _, _, _} <> r False{}:
      color.pick(r, String.eq(x, t), g, t)

# the color of the run holding text t on the first row
def color.of(rs: List<&2, V.VRun>, +t: String) -> String:
  match rs:
    case Nil{}:
      "(none)"
    case V.VRun{+x, f, _, _, _} <> r:
      color.pick(r, String.eq(x, t), f, t)

def color.first(ls: List<&2, V.VLine>, +t: String) -> String:
  match ls:
    case V.VLine{rs} <> _:
      color.of(rs, t)
    case Nil{}:
      "(none)"

def check.k(same: Bool, name: String, got: String, want: String) -> IO(U32):
  match same:
    case True{}:
      do IO<U32>:
        IO.print("ok " ++ name)
        return 0
    case False{}:
      do IO<U32>:
        IO.print("FAIL " ++ name ++ ": got " ++ got ++ " want " ++ want)
        return 1

def check(name: String, +got: String, +want: String) -> IO(U32):
  check.k(String.eq(got, want), name, got, want)

# Reading
# -------

# (socket, terminal, bytes read so far)
type Rd is Data:
  Rd{v: V.Vt, n: U32}

def Rd.fed(v: V.Vt, +n: U32, +bs: List<&2, U32>) -> Rd:
  +k = U32.from_nat(List.length(&2, U32, bs))
  Rd{V.Vt.feed(v, bs), (n + k : U32)}

def Rd.count(+n: U32, +bs: List<&2, U32>) -> U32:
  (n + U32.from_nat(List.length(&2, U32, bs)) : U32)

def Rd.more(enough: Bool, s: Socket, st: Rd, k: Socket -> Rd -> IO(Socket & Rd)) -> IO(Socket & Rd):
  match enough:
    case True{}:
      IO.pure(Socket & Rd, (s, st))
    case False{}:
      k(s, st)

def Rd.data(st: Rd, +bs: List<&2, U32>, s: Socket, +want: U32, k: Socket -> Rd -> IO(Socket & Rd)) -> IO(Socket & Rd):
  match st:
    case Rd{v, +n}:
      Rd.more(U32.is_ge(Rd.count(n, bs), want), s, Rd.fed(v, n, bs), k)

def Rd.got(r: Socket & Result<&1, &1, U32 & String, List<&2, U32>>, st: Rd, +want: U32, k: Socket -> Rd -> IO(Socket & Rd)) -> IO(Socket & Rd):
  (s, res) = r
  match res:
    case Done{Nil{}}:
      IO.pure(Socket & Rd, (s, st))
    case Done{bs}:
      Rd.data(st, bs, s, want, k)
    case Fail{_}:
      IO.pure(Socket & Rd, (s, st))

# read into the terminal until want bytes came, or the pty hung up
def Rd.go(fuel: Nat, s: Socket, st: Rd, +want: U32) -> IO(Socket & Rd):
  match fuel:
    case 0n:
      IO.pure(Socket & Rd, (s, st))
    case 1n+f:
      IO.bind(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, Socket & Rd, H.Sock.recv_bytes(s, 65536),
        r => Rd.got(r, st, want, s2 => st2 => Rd.go(f, s2, st2, want)))

def Rd.vt(st: Rd) -> V.Vt:
  match st:
    case Rd{v, _}:
      v

def Rd.close(r: Socket & Rd) -> IO(V.Vt):
  (s, st) = r
  do IO<V.Vt>:
    Socket.close(s)
    return Rd.vt(st)

def Rd.keep(r: Socket & Rd) -> Socket & V.Vt:
  (s, st) = r
  (s, Rd.vt(st))

# Cases
# -----

def sent(r: Socket & Result<&1, &1, U32 & String, Unit>) -> Socket:
  (s, _) = r
  s

def fail(e: U32 & String) -> IO(U32):
  (code, msg) = e
  do IO<U32>:
    IO.print("FAIL spawn: " ++ U32.show(code) ++ " " ++ msg)
    return 1

# printf with color, then the pty's size, to EOF
def case.print.k(started: U32 & Socket) -> IO(U32):
  (+pid, s) = started
  do IO<U32>:
    +v : V.Vt <- IO.bind(Socket & Rd, V.Vt, Rd.go(1000n, s, Rd{V.Vt.new(80, 24), 0}, 4000000000), Rd.close)
    code : U32 <- H.Proc.wait(pid)
    a : U32 <- check("pty printf text", screen(v, 3n), "hired|24 80|80")
    b : U32 <- check("pty printf color", color.first(V.Vt.lines(v, 0n), "red"), "14707829")
    c : U32 <- check("pty exit code", U32.show(code), "0")
    return (a + b + c : U32)

def case.print(r: Result<&1, &1, U32 & String, U32 & Socket>) -> IO(U32):
  match r:
    case Done{started}:
      case.print.k(started)
    case Fail{e}:
      fail(e)

def case.cat.echo(r: Socket & V.Vt, +pid: U32) -> IO(U32):
  (s, +v) = r
  do IO<U32>:
    a : U32 <- check("pty cat echo", screen(v, 2n), "abc|abc")
    s2 : Socket <- P.Pty.resize(s, 100, 30)
    s3 : Socket <- IO.bind(Socket & Result<&1, &1, U32 & String, Unit>, Socket, H.Sock.send_bytes(s2, [4]), r2 => IO.pure(Socket, sent(r2)))
    v2 : V.Vt <- IO.bind(Socket & Rd, V.Vt, Rd.go(1000n, s3, Rd{v, 0}, 4000000000), Rd.close)
    code : U32 <- H.Proc.wait(pid)
    b : U32 <- check("pty cat eof exit", U32.show(code), "0")
    return (a + b : U32)

def case.cat.k(started: U32 & Socket) -> IO(U32):
  (+pid, s) = started
  do IO<U32>:
    s2 : Socket <- IO.bind(Socket & Result<&1, &1, U32 & String, Unit>, Socket, H.Sock.send_bytes(s, [97, 98, 99, 10]), r => IO.pure(Socket, sent(r)))
    r1 : Socket & V.Vt <- IO.bind(Socket & Rd, Socket & V.Vt, Rd.go(1000n, s2, Rd{V.Vt.new(80, 24), 0}, 10), r => IO.pure(Socket & V.Vt, Rd.keep(r)))
    a : U32 <- case.cat.echo(r1, pid)
    return a

def case.cat(r: Result<&1, &1, U32 & String, U32 & Socket>) -> IO(U32):
  match r:
    case Done{started}:
      case.cat.k(started)
    case Fail{e}:
      fail(e)

# resized right after start; the child sees the new size
def case.size.k(started: U32 & Socket) -> IO(U32):
  (+pid, s) = started
  do IO<U32>:
    s2 : Socket <- P.Pty.resize(s, 100, 30)
    v : V.Vt <- IO.bind(Socket & Rd, V.Vt, Rd.go(1000n, s2, Rd{V.Vt.new(100, 30), 0}, 4000000000), Rd.close)
    code : U32 <- H.Proc.wait(pid)
    a : U32 <- check("pty resize stty size", screen(v, 1n), "30 100")
    return a

def case.size(r: Result<&1, &1, U32 & String, U32 & Socket>) -> IO(U32):
  match r:
    case Done{started}:
      case.size.k(started)
    case Fail{e}:
      fail(e)

def case.env.k(started: U32 & Socket) -> IO(U32):
  (+pid, s) = started
  do IO<U32>:
    v : V.Vt <- IO.bind(Socket & Rd, V.Vt, Rd.go(1000n, s, Rd{V.Vt.new(80, 24), 0}, 4000000000), Rd.close)
    code : U32 <- H.Proc.wait(pid)
    a : U32 <- check("pty env and cwd", screen(v, 3n), "xterm-256color|/tmp|tty")
    return a

def case.env(r: Result<&1, &1, U32 & String, U32 & Socket>) -> IO(U32):
  match r:
    case Done{started}:
      case.env.k(started)
    case Fail{e}:
      fail(e)

def case.missing.k(started: U32 & Socket) -> IO(U32):
  (pid, s) = started
  do IO<U32>:
    Socket.close(s)
    check("pty missing command fails", "spawned", "ENOENT")

def case.missing.code(e: U32 & String) -> IO(U32):
  (code, _) = e
  check("pty missing command fails", U32.show(code), "2")

def case.missing(r: Result<&1, &1, U32 & String, U32 & Socket>) -> IO(U32):
  match r:
    case Done{started}:
      case.missing.k(started)
    case Fail{e}:
      case.missing.code(e)

def done.k(ok: Bool, +n: U32) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("pty: all ok")
    case False{}:
      IO.die(Unit, 1, "pty: " ++ U32.show(n) ++ " failed")

def done(+n: U32) -> IO(Unit):
  done.k(U32.is_eq(n, 0), n)

def main() -> IO(Unit):
  do IO<Unit>:
    a : U32 <- IO.bind(Result<&1, &1, U32 & String, U32 & Socket>, U32, P.Pty.spawn("/bin/sh", ["-c", "printf 'hi\\033[31mred\\033[0m\\n'; stty size; tput cols"], "", 80, 24), case.print)
    b : U32 <- IO.bind(Result<&1, &1, U32 & String, U32 & Socket>, U32, P.Pty.spawn("cat", [], "", 80, 24), case.cat)
    c : U32 <- IO.bind(Result<&1, &1, U32 & String, U32 & Socket>, U32, P.Pty.spawn("sh", ["-c", "sleep 0.3; stty size"], "", 80, 24), case.size)
    d : U32 <- IO.bind(Result<&1, &1, U32 & String, U32 & Socket>, U32, P.Pty.spawn("sh", ["-c", "echo $TERM; pwd; [ -t 0 ] && echo tty"], "/tmp", 80, 24), case.env)
    e : U32 <- IO.bind(Result<&1, &1, U32 & String, U32 & Socket>, U32, P.Pty.spawn("definitely-not-a-command", [], "", 80, 24), case.missing)
    done((a + b + c + d + e : U32))
