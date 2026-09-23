import Base
import ./host.bend as H
import ./pty.bend as PT
import ../core/utf8.bend as U

# Terminals: one shell per thread in a pty, started in the thread's
# directory. One actor owns them all; what a shell prints goes out through
# `out` (the server broadcasts it); input and resizes come in as messages.

type TMsg is Data:
  TOpen{thread: String, cwd: String, cols: U32, rows: U32}
  TIn{thread: String, data: List<&2, U32>}
  TSize{thread: String, cols: U32, rows: U32}
  TGone{thread: String, pid: U32}

# what a shell printed (the server forwards it to the hub)
type TOut is Data:
  TOut{thread: String, data: List<&2, U32>}

def Term.emit(+out: Chan(TOut), +thread: String, bs: List<&2, U32>) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(TOut, out, TOut{thread, bs})
    return Unit{}

type Term is Data:
  Term{thread: String, input: Chan(List<&2, U32>), pid: U32, cols: U32, rows: U32}

def Term.fuel() -> Nat:
  U32.to_nat(4294967295)

def Term.end(s: Socket, +thread: String, +pid: U32, +q: Chan(TMsg), +out: Chan(TOut)) -> IO(Unit):
  do IO<Unit>:
    Socket.close(s)
    code : U32 <- H.Proc.wait(pid)
    Term.emit(out, thread, U.Utf8.encode("\r\n[process exited " ++ U32.show(code) ++ "]\r\n"))
    ok : Bool <- Chan.send(TMsg, q, TGone{thread, pid})
    return Unit{}

# Reading a shell
# ---------------

def Term.got(r: Socket & Result<&1, &1, U32 & String, List<&2, U32>>, +thread: String, +pid: U32, +q: Chan(TMsg),
    +out: Chan(TOut), k: Socket -> IO(Unit)) -> IO(Unit):
  (s, res) = r
  match res:
    case Done{Nil{}}:
      Term.end(s, thread, pid, q, out)
    case Done{bs}:
      IO.bind(Unit, Unit, Term.emit(out, thread, bs), u => k(s))
    case Fail{_}:
      Term.end(s, thread, pid, q, out)

def Term.reader(fuel: Nat, s: Socket, +thread: String, +pid: U32, +q: Chan(TMsg), +out: Chan(TOut)) -> IO(Unit):
  match fuel:
    case 0n:
      Term.end(s, thread, pid, q, out)
    case 1n+f:
      IO.bind(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, Unit, H.Sock.recv_bytes(s, 65536),
        r => Term.got(r, thread, pid, q, out, s2 => Term.reader(f, s2, thread, pid, q, out)))

# Writing to a shell (keys, pastes) and resizing it
# -------------------------------------------------

type TW is Data:
  TWrite{data: List<&2, U32>}
  TResize{cols: U32, rows: U32}

def Term.w.wrote(r: Socket & Result<&1, &1, U32 & String, Unit>, k: Socket -> IO(Unit)) -> IO(Unit):
  (s, _) = r
  k(s)

# bytes from the actor; a resize travels as [0xFF 0xFE cols rows] framing
# (never a real keystroke sequence: 0xFF 0xFE is not valid UTF-8)
def Term.w.data(bs: List<&2, U32>, s: Socket, k: Socket -> IO(Unit)) -> IO(Unit):
  match bs:
    case 255 <> 254 <> c <> r <> Nil{}:
      IO.bind(Socket, Unit, PT.Pty.resize(s, c, r), k)
    case _:
      IO.bind(Socket & Result<&1, &1, U32 & String, Unit>, Unit, H.Sock.send_bytes(s, bs), r => Term.w.wrote(r, k))

def Term.w.one(m: Maybe<&1, List<&2, U32>>, s: Socket, k: Socket -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{bs}:
      Term.w.data(bs, s, k)
    case None{}:
      Socket.close(s)

def Term.writer(fuel: Nat, s: Socket, +input: Chan(List<&2, U32>)) -> IO(Unit):
  match fuel:
    case 0n:
      Socket.close(s)
    case 1n+f:
      IO.bind(Maybe<&1, List<&2, U32>>, Unit, Chan.recv(List<&2, U32>, input), m => Term.w.one(m, s, s2 => Term.writer(f, s2, input)))

# Starting
# --------

def Term.duped(r: Socket & Result<&1, &1, U32 & String, Socket>, +thread: String, +pid: U32, +cols: U32, +rows: U32, +q: Chan(TMsg),
    +out: Chan(TOut)) -> IO(Maybe<&2, Term>):
  (rd, res) = r
  match res:
    case Done{wr}:
      do IO<Maybe<&2, Term>>:
        +input : Chan(List<&2, U32>) <- Chan.new(List<&2, U32>, 256)
        IO.spawn(Unit, Term.writer(Term.fuel(), wr, input))
        IO.spawn(Unit, Term.reader(Term.fuel(), rd, thread, pid, q, out))
        return Some{Term{thread, input, pid, cols, rows}}
    case Fail{_}:
      do IO<Maybe<&2, Term>>:
        Socket.close(rd)
        return None{}

def Term.spawned.fail(e: U32 & String, +thread: String, +out: Chan(TOut)) -> IO(Maybe<&2, Term>):
  (_, msg) = e
  IO.bind(Unit, Maybe<&2, Term>, Term.emit(out, thread, U.Utf8.encode("[could not start a shell: " ++ msg ++ "]\r\n")), u => IO.pure(Maybe<&2, Term>, None{}))

def Term.spawned.ok(started: U32 & Socket, +thread: String, +cols: U32, +rows: U32, +q: Chan(TMsg), +out: Chan(TOut)) -> IO(Maybe<&2, Term>):
  (+pid, s) = started
  IO.bind(Socket & Result<&1, &1, U32 & String, Socket>, Maybe<&2, Term>, H.Sock.dup(s), r => Term.duped(r, thread, pid, cols, rows, q, out))

def Term.spawned(r: Result<&1, &1, U32 & String, U32 & Socket>, +thread: String, +cols: U32, +rows: U32, +q: Chan(TMsg),
    +out: Chan(TOut)) -> IO(Maybe<&2, Term>):
  match r:
    case Done{started}:
      Term.spawned.ok(started, thread, cols, rows, q, out)
    case Fail{e}:
      Term.spawned.fail(e, thread, out)

# The actor
# ---------

def Term.has(ts: List<&2, Term>, +thread: String) -> Bool:
  match ts:
    case Nil{}:
      False{}
    case Term{t, _, _, _, _} <> rest:
      Bool.or(String.eq(t, thread), Term.has(rest, thread))

def Term.hit(ts: List<&2, Term>, +thread: String) -> Bool:
  match ts:
    case Term{t, _, _, _, _} <> _:
      String.eq(t, thread)
    case Nil{}:
      False{}

def Term.send.go(ts: List<&2, Term>, hit: Bool, +thread: String, bs: List<&2, U32>) -> IO(Unit):
  match ts hit:
    case Term{_, i, _, _, _} <> _ True{}:
      do IO<Unit>:
        ok : Bool <- Chan.send(List<&2, U32>, i, bs)
        return Unit{}
    case _ <> +rest False{}:
      Term.send.go(rest, Term.hit(rest, thread), thread, bs)
    case Nil{} _:
      IO.pure(Unit, Unit{})

# bytes to a thread's shell (nothing when it has none)
def Term.send(+ts: List<&2, Term>, +thread: String, bs: List<&2, U32>) -> IO(Unit):
  Term.send.go(ts, Term.hit(ts, thread), thread, bs)

def Term.drop.k(gone: Bool, t: Term, rest: List<&2, Term>) -> List<&2, Term>:
  match gone:
    case True{}:
      rest
    case False{}:
      t <> rest

def Term.drop(ts: List<&2, Term>, +thread: String, +pid: U32) -> List<&2, Term>:
  match ts:
    case Nil{}:
      Nil{}
    case Term{+t, i, +p, c, r} <> rest:
      Term.drop.k(Bool.and(String.eq(t, thread), U32.is_eq(p, pid)), Term{t, i, p, c, r}, Term.drop(rest, thread, pid))

def Term.add(m: Maybe<&2, Term>, ts: List<&2, Term>) -> List<&2, Term>:
  match m:
    case Some{t}:
      t <> ts
    case None{}:
      ts

# a new shell unless the thread has one (then it only takes the new size)
def Term.open(has: Bool, +ts: List<&2, Term>, +thread: String, +cwd: String, +cols: U32, +rows: U32, +shell: String, +q: Chan(TMsg),
    +out: Chan(TOut)) -> IO(List<&2, Term>):
  match has:
    case True{}:
      IO.bind(Unit, List<&2, Term>, Term.send(ts, thread, [255, 254, cols, rows]), u => IO.pure(List<&2, Term>, ts))
    case False{}:
      IO.bind(Result<&1, &1, U32 & String, U32 & Socket>, List<&2, Term>, PT.Pty.spawn(shell, ["-l"], cwd, cols, rows),
        r => IO.bind(Maybe<&2, Term>, List<&2, Term>, Term.spawned(r, thread, cols, rows, q, out), m => IO.pure(List<&2, Term>, Term.add(m, ts))))

def Term.step(m: Maybe<&1, TMsg>, +ts: List<&2, Term>, +shell: String, +q: Chan(TMsg), +out: Chan(TOut), k: List<&2, Term> -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{TOpen{+th, cwd, c, r}}:
      IO.bind(List<&2, Term>, Unit, Term.open(Term.has(ts, th), ts, th, cwd, c, r, shell, q, out), k)
    case Some{TIn{+th, bs}}:
      IO.bind(Unit, Unit, Term.send(ts, th, bs), u => k(ts))
    case Some{TSize{+th, c, r}}:
      IO.bind(Unit, Unit, Term.send(ts, th, [255, 254, c, r]), u => k(ts))
    case Some{TGone{+th, +pid}}:
      k(Term.drop(ts, th, pid))
    case None{}:
      IO.pure(Unit, Unit{})

def Term.loop(fuel: Nat, +q: Chan(TMsg), ts: List<&2, Term>, +shell: String, +out: Chan(TOut)) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      IO.bind(Maybe<&1, TMsg>, Unit, Chan.recv(TMsg, q), m => Term.step(m, ts, shell, q, out, t2 => Term.loop(f, q, t2, shell, out)))
