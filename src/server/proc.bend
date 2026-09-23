import Base
import ./host.bend as H
import ../core/utf8.bend as U

# Running commands to completion. Loops that wait on the outside world count
# down a Nat fuel (Bend requires every loop to end).

type Chunks is Data:
  Chunks{rev: List<&2, List<&2, U32>>}

def Chunks.bytes(c: Chunks) -> List<&2, U32>:
  match c:
    case Chunks{rev}:
      List.concat(&2, U32, List.reverse(&2, List<&2, U32>, rev))

def Proc.drain.got(r: Socket & Result<&1, &1, U32 & String, List<&2, U32>>, acc: Chunks,
    k: Socket -> Chunks -> IO(Socket & List<&2, U32>)) -> IO(Socket & List<&2, U32>):
  (s, res) = r
  match res acc:
    case Done{Nil{}} _:
      IO.pure(Socket & List<&2, U32>, (s, Chunks.bytes(acc)))
    case Done{bs} Chunks{rev}:
      k(s, Chunks{bs <> rev})
    case Fail{_} _:
      IO.pure(Socket & List<&2, U32>, (s, Chunks.bytes(acc)))

# every byte until the peer closes its side
def Proc.drain(fuel: Nat, s: Socket, acc: Chunks) -> IO(Socket & List<&2, U32>):
  match fuel:
    case 0n:
      IO.pure(Socket & List<&2, U32>, (s, Chunks.bytes(acc)))
    case 1n+f:
      IO.bind(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, Socket & List<&2, U32>,
        H.Sock.recv_bytes(s, 65536),
        r => Proc.drain.got(r, acc, s2 => a2 => Proc.drain(f, s2, a2)))

# the result of a finished command
type Ran is Data:
  Ran{code: U32, out: String}

def Proc.finish(pid: U32, r: Socket & List<&2, U32>) -> IO(Ran):
  (s, bs) = r
  do IO<Ran>:
    Socket.close(s)
    code : U32 <- H.Proc.wait(pid)
    return Ran{code, U.Utf8.decode(bs)}

def Proc.collect(started: U32 & Socket) -> IO(Ran):
  (pid, s) = started
  do IO<Ran>:
    s2 : Socket <- H.Sock.shutdown(s)
    r : Socket & List<&2, U32> <- Proc.drain(1000000n, s2, Chunks{Nil{}})
    Proc.finish(pid, r)

def Proc.run.fail(e: U32 & String) -> IO(Ran):
  (code, msg) = e
  IO.pure(Ran, Ran{127, msg})

def Proc.run.k(r: Result<&1, &1, U32 & String, U32 & Socket>) -> IO(Ran):
  match r:
    case Fail{e}:
      Proc.run.fail(e)
    case Done{started}:
      Proc.collect(started)

# run cmd with args in cwd; stdout and stderr together, stdin closed
def Proc.run(cmd: String, args: List<&2, String>, cwd: String) -> IO(Ran):
  IO.bind(Result<&1, &1, U32 & String, U32 & Socket>, Ran, H.Proc.spawn(cmd, args, cwd, 1), Proc.run.k)
