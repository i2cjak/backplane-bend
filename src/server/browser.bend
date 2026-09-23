import Base
import ./host.bend as H
import ../core/json.bend as J
import ../core/utf8.bend as U

# The browser Backplane hosts for its agents: one backplane-browser helper
# (headless Chromium, tools/browser), started on the first request and
# spoken to in JSON lines. Requests carry ids; a reply goes back to the
# channel its request came with. The helper writes frames to a file the
# native Browser tab shows.

type BMsg is Data:
  BCall{op: String, args: J.Json, reply: Chan(String)}
  BLine{text: String}
  BDead{}

type Pend is Data:
  Pend{id: String, reply: Chan(String)}

# the helper's input (None until it runs), the requests waiting for a
# reply, the next id, the helper's path and its frame file
type Br is Data:
  Br{input: Maybe<&2, Chan(String)>, pend: List<&2, Pend>, next: Nat, exe: String, frames: String}

def Br.new(+exe: String, +frames: String) -> Br:
  Br{None{}, Nil{}, 1n, exe, frames}

def Browser.forever() -> Nat:
  4000000000n

def Browser.fail(+error: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"ok", J.Flag{False{}}}, J.KV{"error", J.Str{error}}]))

def Browser.say(+reply: Chan(String), +text: String) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(String, reply, text)
    return Unit{}

# Reading the helper
# ------------------

def Browser.lines(ls: List<&2, String>, +q: Chan(BMsg)) -> IO(Unit):
  match ls:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case l <> t:
      do IO<Unit>:
        ok : Bool <- Chan.send(BMsg, q, BLine{l})
        Browser.lines(t, q)

def Browser.end(s: Socket, +pid: U32, +q: Chan(BMsg)) -> IO(Unit):
  do IO<Unit>:
    Socket.close(s)
    code : U32 <- H.Proc.wait(pid)
    ok : Bool <- Chan.send(BMsg, q, BDead{})
    return Unit{}

def Browser.fed(r: U.Lines & List<&2, String>, s: Socket, +q: Chan(BMsg), k: Socket -> U.Lines -> IO(Unit)) -> IO(Unit):
  (carry, ls) = r
  do IO<Unit>:
    Browser.lines(ls, q)
    k(s, carry)

def Browser.got(r: Socket & Result<&1, &1, U32 & String, List<&2, U32>>, carry: U.Lines, +pid: U32, +q: Chan(BMsg), k: Socket -> U.Lines -> IO(Unit)) -> IO(Unit):
  (s, res) = r
  match res:
    case Done{Nil{}}:
      Browser.end(s, pid, q)
    case Done{bs}:
      Browser.fed(U.Lines.feed(carry, bs), s, q, k)
    case Fail{_}:
      Browser.end(s, pid, q)

def Browser.reader(fuel: Nat, s: Socket, carry: U.Lines, +pid: U32, +q: Chan(BMsg)) -> IO(Unit):
  match fuel:
    case 0n:
      Browser.end(s, pid, q)
    case 1n+f:
      IO.bind(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, Unit, H.Sock.recv_bytes(s, 65536),
        r => Browser.got(r, carry, pid, q, s2 => c2 => Browser.reader(f, s2, c2, pid, q)))

def Browser.wrote(r: Socket & Result<&1, &1, U32 & String, Unit>, k: Socket -> IO(Unit)) -> IO(Unit):
  (s, _) = r
  k(s)

def Browser.write(m: Maybe<&1, String>, s: Socket, k: Socket -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{line}:
      IO.bind(Socket & Result<&1, &1, U32 & String, Unit>, Unit, H.Sock.send_text(s, line ++ "\n"), r => Browser.wrote(r, k))
    case None{}:
      Socket.close(s)

def Browser.writer(fuel: Nat, s: Socket, +input: Chan(String)) -> IO(Unit):
  match fuel:
    case 0n:
      Socket.close(s)
    case 1n+f:
      IO.bind(Maybe<&1, String>, Unit, Chan.recv(String, input), m => Browser.write(m, s, s2 => Browser.writer(f, s2, input)))

# Starting the helper
# -------------------

def Browser.duped(r: Socket & Result<&1, &1, U32 & String, Socket>, +pid: U32, +q: Chan(BMsg)) -> IO(Maybe<&2, Chan(String)>):
  (rd, res) = r
  match res:
    case Done{wr}:
      do IO<Maybe<&2, Chan(String)>>:
        +input : Chan(String) <- Chan.new(String, 256)
        IO.spawn(Unit, Browser.writer(Browser.forever(), wr, input))
        IO.spawn(Unit, Browser.reader(Browser.forever(), rd, U.Lines.new(), pid, q))
        ok : Bool <- Chan.send(String, input, "{\"id\":\"frames\",\"op\":\"frames\",\"on\":true,\"maxFps\":8}")
        return Some{input}
    case Fail{_}:
      do IO<Maybe<&2, Chan(String)>>:
        Socket.close(rd)
        return None{}

def Browser.spawned.ok(started: U32 & Socket, +q: Chan(BMsg)) -> IO(Maybe<&2, Chan(String)>):
  (+pid, s) = started
  IO.bind(Socket & Result<&1, &1, U32 & String, Socket>, Maybe<&2, Chan(String)>, H.Sock.dup(s), r => Browser.duped(r, pid, q))

def Browser.spawned(r: Result<&1, &1, U32 & String, U32 & Socket>, +q: Chan(BMsg)) -> IO(Maybe<&2, Chan(String)>):
  match r:
    case Done{started}:
      Browser.spawned.ok(started, q)
    case Fail{_}:
      IO.pure(Maybe<&2, Chan(String)>, None{})

# the running helper's input, starting it if needed
def Browser.ensure(m: Maybe<&2, Chan(String)>, +exe: String, +frames: String, +q: Chan(BMsg)) -> IO(Maybe<&2, Chan(String)>):
  match m:
    case Some{c}:
      IO.pure(Maybe<&2, Chan(String)>, Some{c})
    case None{}:
      IO.bind(Result<&1, &1, U32 & String, U32 & Socket>, Maybe<&2, Chan(String)>, H.Proc.spawn(exe, ["--frames", frames], "/", 0), r => Browser.spawned(r, q))

# The actor
# ---------

# the request line: the tool's arguments with the id and op beside them
def Browser.request(+id: Nat, +op: String, args: J.Json) -> String:
  match args:
    case J.Obj{fs}:
      J.Json.show(J.Obj{J.Field{"id", J.Num{Nat.show(id)}, J.Field{"op", J.Str{op}, fs}}})
    case _:
      J.Json.show(J.Obj{J.Field{"id", J.Num{Nat.show(id)}, J.Field{"op", J.Str{op}, J.End{}}}})

def Browser.sent(m: Maybe<&2, Chan(String)>, +line: String, +id: Nat, +reply: Chan(String), b: Br) -> IO(Br):
  match m b:
    case Some{+c} Br{_, ps, n, exe, fr}:
      do IO<Br>:
        ok : Bool <- Chan.send(String, c, line)
        return Br{Some{c}, Pend{Nat.show(id), reply} <> ps, n, exe, fr}
    case None{} Br{_, ps, n, exe, fr}:
      do IO<Br>:
        Browser.say(reply, Browser.fail("the Backplane browser could not start (is backplane-browser installed next to Backplane?)"))
        return Br{None{}, ps, n, exe, fr}

def Browser.call(b: Br, +q: Chan(BMsg), +op: String, args: J.Json, +reply: Chan(String)) -> IO(Br):
  match b:
    case Br{m, ps, +n, +exe, +fr}:
      IO.bind(Maybe<&2, Chan(String)>, Br, Browser.ensure(m, exe, fr, q),
        m2 => Browser.sent(m2, Browser.request(n, op, args), n, reply, Br{None{}, ps, 1n+n, exe, fr}))

type Took is Data:
  Took{reply: Maybe<&2, Chan(String)>, rest: List<&2, Pend>}

def Took.keep(p: Pend, t: Took) -> Took:
  match t:
    case Took{r, ps}:
      Took{r, p <> ps}

def Pend.hit(ps: List<&2, Pend>, +id: String) -> Bool:
  match ps:
    case Pend{pid, _} <> _:
      String.eq(pid, id)
    case Nil{}:
      False{}

# the waiting request with this id, taken out of the list
def Pend.take(ps: List<&2, Pend>, hit: Bool, +id: String) -> Took:
  match ps hit:
    case Pend{_, reply} <> t True{}:
      Took{Some{reply}, t}
    case p <> +t False{}:
      Took.keep(p, Pend.take(t, Pend.hit(t, id), id))
    case Nil{} _:
      Took{None{}, Nil{}}

def Browser.deliver.k(t: Took, +text: String) -> IO(List<&2, Pend>):
  match t:
    case Took{Some{reply}, rest}:
      do IO<List<&2, Pend>>:
        Browser.say(reply, text)
        return rest
    case Took{None{}, rest}:
      IO.pure(List<&2, Pend>, rest)

# answer the request with this id; the rest keep waiting
def Browser.deliver(+ps: List<&2, Pend>, +id: String, +text: String) -> IO(List<&2, Pend>):
  Browser.deliver.k(Pend.take(ps, Pend.hit(ps, id), id), text)

# a line from the helper: a reply (by id) or an event (ignored here)
def Browser.line(b: Br, +text: String) -> IO(Br):
  match b:
    case Br{m, ps, n, exe, fr}:
      IO.bind(List<&2, Pend>, Br, Browser.deliver(ps, J.Json.as_raw(J.Json.get(Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{}), "id"), ""), text),
        ps2 => IO.pure(Br, Br{m, ps2, n, exe, fr}))

def Browser.fail_all(ps: List<&2, Pend>) -> IO(Unit):
  match ps:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Pend{_, reply} <> t:
      do IO<Unit>:
        Browser.say(reply, Browser.fail("the browser exited"))
        Browser.fail_all(t)

# the helper went away: fail what waits; the next request starts it again
def Browser.dead(b: Br) -> IO(Br):
  match b:
    case Br{_, ps, n, exe, fr}:
      do IO<Br>:
        Browser.fail_all(ps)
        return Br{None{}, Nil{}, n, exe, fr}

def Browser.step(m: Maybe<&1, BMsg>, b: Br, +q: Chan(BMsg), k: Br -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{BCall{op, args, reply}}:
      IO.bind(Br, Unit, Browser.call(b, q, op, args, reply), k)
    case Some{BLine{t}}:
      IO.bind(Br, Unit, Browser.line(b, t), k)
    case Some{BDead{}}:
      IO.bind(Br, Unit, Browser.dead(b), k)
    case None{}:
      IO.pure(Unit, Unit{})

def Browser.loop(fuel: Nat, +q: Chan(BMsg), b: Br) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      IO.bind(Maybe<&1, BMsg>, Unit, Chan.recv(BMsg, q), m => Browser.step(m, b, q, b2 => Browser.loop(f, q, b2)))

# ask the browser; answers the helper's reply line
def Browser.ask(+q: Chan(BMsg), +op: String, args: J.Json) -> IO(String):
  do IO<String>:
    +reply : Chan(String) <- Chan.new(String, 1)
    ok : Bool <- Chan.send(BMsg, q, BCall{op, args, reply})
    m : Maybe<&1, String> <- Chan.recv(String, reply)
    return Maybe.default(&1, String, m, Browser.fail("no reply"))
