import Base
import ./host.bend as H
import ./proc.bend as P
import ../core/json.bend as J
import ../core/utf8.bend as U
import ../core/http.bend as W
import ../core/model.bend as M
import ../core/codec.bend as C
import ../core/hub.bend as B
import ../core/prompt.bend as Q
import ../core/mcp.bend as MC
import ./update.bend as UP
import ../core/version.bend as VR
import ./kicad.bend as K
import ./browser.bend as BR
import ../core/acp.bend as AC
import ../core/cbor.bend as CB
import ./push.bend as PU
import ./park.bend as PK
import ./git.bend as GT
import ./term.bend as TM

# The server. One hub computation owns the read model and the event log;
# every connection and agent process is its own computation and talks to
# the hub over channels. The hub runs the pure decider (core/hub.bend) and
# carries out the effects it answers.

# what a connection's writer sends
type Wire is Data:
  WText{text: String}
  WPong{payload: List<&2, U32>}
  WClose{}

type Msg is Data:
  Announce{text: String}
  Mcp{thread: String, body: String, reply: Chan(String)}
  Join{client: U32, out: Chan(Wire), since: Nat, origin: String}
  Leave{client: U32}
  Rpc{client: U32, text: String}
  AgentLine{thread: String, line: String}
  AgentGone{thread: String, code: U32, pid: U32}
  Tick{}
  Push{client: U32, text: String}
  TermOut{thread: String, data: List<&2, U32>}

# remote access: also listen on the tailnet, serve HTTPS through
# `tailscale serve`, and the token remote clients must present
type Net is Data:
  Net{tailnet: Bool, https: Bool, token: String, models: String, mtext: String, rt: K.Rt, br: Maybe<&2, Chan(BR.BMsg)>, pk: Maybe<&2, Chan(PK.PMsg)>, tm: Maybe<&2, Chan(TM.TMsg)>}

type Cfg is Data:
  Cfg{home: String, web: String, host: String, port: U32, prompt: String, dirs: List<&2, String>, version: String, net: Net}

type Client is Data:
  Client{id: U32, out: Chan(Wire)}

type Agent is Data:
  Agent{thread: String, input: Chan(String), pid: U32, key: String}

def Fuel.forever() -> Nat:
  U32.to_nat(4294967295)

def Log.info(s: String) -> IO(Unit):
  IO.print_err("backplane: " ++ s)

def Now.nat() -> IO(Nat):
  do IO<Nat>:
    t : U32 <- H.Clock.epoch()
    return U32.to_nat(t)

# Files
# -----

def Files.read.done(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(List<&2, U32>):
  (f, res) = r
  do IO<List<&2, U32>>:
    File.close(f)
    return Result.default(&1, &1, U32 & String, List<&2, U32>, res, Nil{})

def Files.read.sized(r: File & Result<&1, &1, U32 & String, U32>) -> IO(List<&2, U32>):
  (f, res) = r
  IO.bind(File & Result<&1, &1, U32 & String, List<&2, U32>>, List<&2, U32>,
    File.read_bytes(f, U32.max(Result.default(&1, &1, U32 & String, U32, res, 0), 1)), Files.read.done)

def Files.read.opened(r: Result<&1, &1, U32 & String, File>) -> IO(List<&2, U32>):
  match r:
    case Done{f}:
      IO.bind(File & Result<&1, &1, U32 & String, U32>, List<&2, U32>, File.size(f), Files.read.sized)
    case Fail{_}:
      IO.pure(List<&2, U32>, Nil{})

# a whole file's bytes, or [] when it cannot be read
def Files.read(path: String) -> IO(List<&2, U32>):
  IO.bind(Result<&1, &1, U32 & String, File>, List<&2, U32>, File.open(path, "r"), Files.read.opened)

def Files.text(path: String) -> IO(String):
  do IO<String>:
    bs : List<&2, U32> <- Files.read(path)
    return U.Utf8.decode(bs)

# Event log
# ---------

def Store.put(m: Maybe<&2, M.Change>, rest: List<&2, M.Change>) -> List<&2, M.Change>:
  match m:
    case Some{c}:
      c <> rest
    case None{}:
      rest

def Store.one(m: Maybe<&2, J.Json>, rest: List<&2, M.Change>) -> List<&2, M.Change>:
  match m:
    case Some{+o}:
      Store.put(C.Change.decode(o), rest)
    case None{}:
      rest

def Store.decode(ls: List<&2, String>) -> List<&2, M.Change>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> t:
      Store.one(J.Json.parse(l), Store.decode(t))

def Store.lines.k(r: U.Lines & List<&2, String>) -> List<&2, String>:
  (_, ls) = r
  ls

def Store.lines(bs: List<&2, U32>) -> List<&2, String>:
  Store.lines.k(U.Lines.feed(U.Lines.new(), bs))

# only lines that decode are kept (and re-sent to clients)
def Store.keep.k(m: Maybe<&2, J.Json>, +l: String, rest: List<&2, String>) -> List<&2, String>:
  match m:
    case Some{_}:
      l <> rest
    case None{}:
      rest

def Store.wire.k(m: Maybe<&2, J.Json>, +l: String) -> String:
  match m:
    case Some{+o}:
      C.Change.wire_line(o, l)
    case None{}:
      l

# the log as clients may see it: device tokens left out
def Store.wire(ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      Store.wire.k(J.Json.parse(l), l) <> Store.wire(t)

def Store.keep(ls: List<&2, String>, acc: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      acc
    case +l <> t:
      Store.keep(t, Store.keep.k(J.Json.parse(l), l, acc))

def Store.path(+home: String) -> String:
  home ++ "/events.jsonl"

# Clients and agents
# ------------------

def Clients.hit(cs: List<&2, Client>, +id: U32) -> Bool:
  match cs:
    case Client{i, _} <> _:
      U32.is_eq(i, id)
    case Nil{}:
      False{}

def Clients.find(cs: List<&2, Client>, hit: Bool, +id: U32) -> Maybe<&2, Chan(Wire)>:
  match cs hit:
    case Client{_, o} <> _ True{}:
      Some{o}
    case _ <> +t False{}:
      Clients.find(t, Clients.hit(t, id), id)
    case _ _:
      None{}

def Clients.get(+cs: List<&2, Client>, +id: U32) -> Maybe<&2, Chan(Wire)>:
  Clients.find(cs, Clients.hit(cs, id), id)

def Clients.drop.k(same: Bool, c: Client, rest: List<&2, Client>) -> List<&2, Client>:
  match same:
    case True{}:
      rest
    case False{}:
      c <> rest

def Clients.drop(cs: List<&2, Client>, +id: U32) -> List<&2, Client>:
  match cs:
    case Nil{}:
      Nil{}
    case Client{+i, o} <> t:
      Clients.drop.k(U32.is_eq(i, id), Client{i, o}, Clients.drop(t, id))

def Agents.hit(as: List<&2, Agent>, +th: String) -> Bool:
  match as:
    case Agent{t, _, _, _} <> _:
      String.eq(t, th)
    case Nil{}:
      False{}

def Agents.find(as: List<&2, Agent>, hit: Bool, +th: String) -> Maybe<&2, Agent>:
  match as hit:
    case a <> _ True{}:
      Some{a}
    case _ <> +t False{}:
      Agents.find(t, Agents.hit(t, th), th)
    case _ _:
      None{}

def Agents.get(+as: List<&2, Agent>, +th: String) -> Maybe<&2, Agent>:
  Agents.find(as, Agents.hit(as, th), th)

def Agents.drop.k(same: Bool, a: Agent, rest: List<&2, Agent>) -> List<&2, Agent>:
  match same:
    case True{}:
      rest
    case False{}:
      a <> rest

def Agents.drop(as: List<&2, Agent>, +th: String) -> List<&2, Agent>:
  match as:
    case Nil{}:
      Nil{}
    case Agent{+t, i, p, k} <> rest:
      Agents.drop.k(String.eq(t, th), Agent{t, i, p, k}, Agents.drop(rest, th))

def Wire.send(m: Maybe<&2, Chan(Wire)>, w: Wire) -> IO(Unit):
  match m:
    case Some{c}:
      do IO<Unit>:
        ok : Bool <- Chan.send(Wire, c, w)
        return Unit{}
    case None{}:
      IO.pure(Unit, Unit{})

def Wire.all(cs: List<&2, Client>, +text: String) -> IO(Unit):
  match cs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Client{_, o} <> t:
      do IO<Unit>:
        ok : Bool <- Chan.send(Wire, o, WText{text})
        Wire.all(t, text)

# Agent processes
# ---------------

# lines from the agent's stdout go to the hub; EOF reports the exit
def Agent.lines(ls: List<&2, String>, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  match ls:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case l <> t:
      do IO<Unit>:
        ok : Bool <- Chan.send(Msg, inbox, AgentLine{thread, l})
        Agent.lines(t, thread, inbox)

def Agent.end(s: Socket, +pid: U32, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    Socket.close(s)
    code : U32 <- H.Proc.wait(pid)
    ok : Bool <- Chan.send(Msg, inbox, AgentGone{thread, code, pid})
    return Unit{}

def Agent.fed(r: U.Lines & List<&2, String>, s: Socket, +thread: String, +inbox: Chan(Msg), k: Socket -> U.Lines -> IO(Unit)) -> IO(Unit):
  (carry, ls) = r
  do IO<Unit>:
    Agent.lines(ls, thread, inbox)
    k(s, carry)

def Agent.got(r: Socket & Result<&1, &1, U32 & String, List<&2, U32>>, carry: U.Lines, +pid: U32, +thread: String, +inbox: Chan(Msg),
    k: Socket -> U.Lines -> IO(Unit)) -> IO(Unit):
  (s, res) = r
  match res:
    case Done{Nil{}}:
      Agent.end(s, pid, thread, inbox)
    case Done{bs}:
      Agent.fed(U.Lines.feed(carry, bs), s, thread, inbox, k)
    case Fail{_}:
      Agent.end(s, pid, thread, inbox)

def Agent.reader(fuel: Nat, s: Socket, carry: U.Lines, +pid: U32, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      Agent.end(s, pid, thread, inbox)
    case 1n+f:
      IO.bind(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, Unit, H.Sock.recv_bytes(s, 65536),
        r => Agent.got(r, carry, pid, thread, inbox, s2 => c2 => Agent.reader(f, s2, c2, pid, thread, inbox)))

def Agent.wrote(r: Socket & Result<&1, &1, U32 & String, Unit>, k: Socket -> IO(Unit)) -> IO(Unit):
  (s, _) = r
  k(s)

def Agent.write(m: Maybe<&1, String>, s: Socket, k: Socket -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{line}:
      IO.bind(Socket & Result<&1, &1, U32 & String, Unit>, Unit, H.Sock.send_text(s, line ++ "\n"), r => Agent.wrote(r, k))
    case None{}:
      Socket.close(s)

# lines from the hub go to the agent's stdin until the channel closes
def Agent.writer(fuel: Nat, s: Socket, +input: Chan(String)) -> IO(Unit):
  match fuel:
    case 0n:
      Socket.close(s)
    case 1n+f:
      IO.bind(Maybe<&1, String>, Unit, Chan.recv(String, input),
        m => Agent.write(m, s, s2 => Agent.writer(f, s2, input)))

# Connections
# -----------

def Conn.sent(r: Socket & Result<&1, &1, U32 & String, Unit>) -> IO(Socket):
  (s, _) = r
  IO.pure(Socket, s)

def Conn.send(s: Socket, bs: List<&2, U32>) -> IO(Socket):
  IO.bind(Socket & Result<&1, &1, U32 & String, Unit>, Socket, H.Sock.send_bytes(s, bs), Conn.sent)

def Conn.finish(s: Socket, bs: List<&2, U32>) -> IO(Unit):
  do IO<Unit>:
    s2 : Socket <- Conn.send(s, bs)
    Socket.close(s2)

# a message as a frame: JSON text, or, for a client that asked for it
# (enc=cbor), one binary CBOR frame (about 40% fewer bytes on the air)
def Conn.frame.out(cbor: Bool, t: String) -> List<&2, U32>:
  match cbor:
    case True{}:
      W.Ws.encode(2, CB.Cbor.encode(Maybe.default(&2, J.Json, J.Json.parse(t), J.Null{})))
    case False{}:
      W.Ws.text(t)

def Conn.write(m: Maybe<&1, Wire>, s: Socket, +cbor: Bool, k: Socket -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{WText{t}}:
      IO.bind(Socket, Unit, Conn.send(s, Conn.frame.out(cbor, t)), k)
    case Some{WPong{p}}:
      IO.bind(Socket, Unit, Conn.send(s, W.Ws.encode(10, p)), k)
    case Some{WClose{}}:
      Conn.finish(s, W.Ws.encode(8, Nil{}))
    case None{}:
      Socket.close(s)

# frames from the hub, until it closes our channel
def Conn.writer(fuel: Nat, s: Socket, +out: Chan(Wire), +cbor: Bool) -> IO(Unit):
  match fuel:
    case 0n:
      Socket.close(s)
    case 1n+f:
      IO.bind(Maybe<&1, Wire>, Unit, Chan.recv(Wire, out), m => Conn.write(m, s, cbor, s2 => Conn.writer(f, s2, out, cbor)))

def Conn.leave(s: Socket, +id: U32, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    Socket.close(s)
    ok : Bool <- Chan.send(Msg, inbox, Leave{id})
    return Unit{}

def Conn.frame.k(text: Bool, close: Bool, ping: Bool, p: List<&2, U32>, +id: U32, +inbox: Chan(Msg), +out: Chan(Wire)) -> IO(Bool):
  match text close ping:
    case True{} _ _:
      do IO<Bool>:
        ok : Bool <- Chan.send(Msg, inbox, Rpc{id, U.Utf8.decode(p)})
        return True{}
    case False{} True{} _:
      IO.pure(Bool, False{})
    case False{} False{} True{}:
      do IO<Bool>:
        ok : Bool <- Chan.send(Wire, out, WPong{p})
        return True{}
    case False{} False{} False{}:
      IO.pure(Bool, True{})

def Conn.cbor.json(m: Maybe<&2, J.Json>) -> String:
  match m:
    case Some{j}:
      J.Json.show(j)
    case None{}:
      ""

# a frame from the browser: text is a request; close ends; ping pongs
# an incoming request as JSON text: a binary frame is CBOR
def Conn.frame.text(bin: Bool, p: List<&2, U32>) -> List<&2, U32>:
  match bin:
    case True{}:
      U.Utf8.encode(Conn.cbor.json(CB.Cbor.decode(p)))
    case False{}:
      p

def Conn.frame(fr: W.Frame, +id: U32, +inbox: Chan(Msg), +out: Chan(Wire)) -> IO(Bool):
  match fr:
    case W.Frame{_, +op, p}:
      Conn.frame.k(Bool.or(U32.is_eq(op, 1), U32.is_eq(op, 2)), U32.is_eq(op, 8), U32.is_eq(op, 9), Conn.frame.text(U32.is_eq(op, 2), p), id, inbox, out)

def Conn.more(r: Socket & Result<&1, &1, U32 & String, List<&2, U32>>, buf: List<&2, U32>, +id: U32, +inbox: Chan(Msg),
    k: Socket -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  (s, res) = r
  match res:
    case Done{Nil{}}:
      Conn.leave(s, id, inbox)
    case Done{bs}:
      k(s, List.append(&2, U32, buf, bs))
    case Fail{_}:
      Conn.leave(s, id, inbox)

def Conn.after(go: Bool, s: Socket, rest: List<&2, U32>, +id: U32, +inbox: Chan(Msg), k: Socket -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match go:
    case True{}:
      k(s, rest)
    case False{}:
      Conn.leave(s, id, inbox)

def Conn.decoded(m: Maybe<&2, W.Got>, s: Socket, +buf: List<&2, U32>, +id: U32, +inbox: Chan(Msg), +out: Chan(Wire),
    k: Socket -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{W.Got{fr, rest}}:
      IO.bind(Bool, Unit, Conn.frame(fr, id, inbox, out), go => Conn.after(go, s, rest, id, inbox, k))
    case None{}:
      IO.bind(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, Unit, H.Sock.recv_bytes(s, 65536),
        r => Conn.more(r, buf, id, inbox, k))

# decode frames from buf; read more when a frame is incomplete
def Conn.reader(fuel: Nat, s: Socket, +buf: List<&2, U32>, +id: U32, +inbox: Chan(Msg), +out: Chan(Wire)) -> IO(Unit):
  match fuel:
    case 0n:
      Conn.leave(s, id, inbox)
    case 1n+f:
      Conn.decoded(W.Ws.decode(buf), s, buf, id, inbox, out,
        s2 => b2 => Conn.reader(f, s2, b2, id, inbox, out))

def Conn.ws.dup(r: Socket & Result<&1, &1, U32 & String, Socket>, rest: List<&2, U32>, +id: U32, +inbox: Chan(Msg), +since: Nat, +origin: String, +cbor: Bool) -> IO(Unit):
  (rd, res) = r
  match res:
    case Done{wr}:
      do IO<Unit>:
        +out : Chan(Wire) <- Chan.new(Wire, 1024)
        IO.spawn(Unit, Conn.writer(Fuel.forever(), wr, out, cbor))
        ok : Bool <- Chan.send(Msg, inbox, Join{id, out, since, origin})
        Conn.reader(Fuel.forever(), rd, rest, id, inbox, out)
    case Fail{_}:
      Socket.close(rd)

def Conn.ws(s: Socket, key: String, rest: List<&2, U32>, +id: U32, +inbox: Chan(Msg), +since: Nat, +origin: String, +cbor: Bool) -> IO(Unit):
  do IO<Unit>:
    s2 : Socket <- Conn.send(s, W.Ws.accept(key))
    r : Socket & Result<&1, &1, U32 & String, Socket> <- H.Sock.dup(s2)
    Conn.ws.dup(r, rest, id, inbox, since, origin, cbor)

def Conn.safe(+p: String) -> Bool:
  Bool.and(Bool.not(String.contains(p, "..")), String.starts_with(p, "/"))

def Conn.file(+p: String) -> String:
  Bool.pick(String, String.eq(p, "/"), "/index.html", p)

# hashed bundle chunks never change under their name; the page and the
# service worker are checked every time
def Conn.cache(+path: String) -> String:
  Bool.pick(String, String.starts_with(path, "/chunk-"), "public, max-age=31536000, immutable", "no-cache")

def Conn.served(s: Socket, +path: String, +gz: Bool, bs: List<&2, U32>) -> IO(Unit):
  match bs:
    case Nil{}:
      Conn.finish(s, W.Http.text("404 Not Found", "not found"))
    case b <> t:
      Conn.finish(s, W.Http.response.c("200 OK", W.Http.ctype(path), b <> t, Conn.cache(path), Bool.pick(String, gz, "Content-Encoding: gzip\r\nVary: Accept-Encoding\r\n", "Vary: Accept-Encoding\r\n")))

# a precompressed .gz beside the file when the browser takes gzip
def Conn.gz(bs: List<&2, U32>, s: Socket, +web: String, +path: String) -> IO(Unit):
  match bs:
    case Nil{}:
      IO.bind(List<&2, U32>, Unit, Files.read(web ++ path), plain => Conn.served(s, path, False{}, plain))
    case b <> t:
      Conn.served(s, path, True{}, b <> t)

def Conn.static.go(gz: Bool, s: Socket, +web: String, +path: String) -> IO(Unit):
  match gz:
    case True{}:
      IO.bind(List<&2, U32>, Unit, Files.read(web ++ path ++ ".gz"), bs => Conn.gz(bs, s, web, path))
    case False{}:
      IO.bind(List<&2, U32>, Unit, Files.read(web ++ path), bs => Conn.served(s, path, False{}, bs))

def Conn.static.k(ok: Bool, s: Socket, +web: String, +path: String, gz: Bool) -> IO(Unit):
  match ok:
    case True{}:
      Conn.static.go(gz, s, web, path)
    case False{}:
      Conn.finish(s, W.Http.text("400 Bad Request", "bad path"))

def Conn.static(s: Socket, +web: String, +path: String, gz: Bool) -> IO(Unit):
  Conn.static.k(Conn.safe(path), s, web, Conn.file(path), gz)

# a websocket from plain loopback is trusted; anything else (the tailnet
# listener, or `tailscale serve` proxying with its identity headers) must
# carry ?token=<the pairing token>
def Conn.allowed(+trusted: Bool, +hs: List<&2, W.Header>, +path: String, +token: String) -> Bool:
  Bool.or(Bool.and(trusted, String.is_empty(W.Http.header_of(hs, "tailscale-user-login"))),
    Bool.and(Bool.not(String.is_empty(token)), String.contains(path, "token=" ++ token)))

def Conn.gate(ok: Bool, s: Socket, +key: String, rest: List<&2, U32>, +id: U32, +inbox: Chan(Msg), +since: Nat, +origin: String, +cbor: Bool) -> IO(Unit):
  match ok:
    case True{}:
      Conn.ws(s, key, rest, id, inbox, since, origin, cbor)
    case False{}:
      Conn.finish(s, W.Http.text("401 Unauthorized", "this Backplane needs its pairing token"))

def Conn.route.k(ws: Bool, s: Socket, req: W.Request, rest: List<&2, U32>, +web: String, +id: U32, +inbox: Chan(Msg), +trusted: Bool, +token: String) -> IO(Unit):
  match ws req:
    case True{} W.Request{_, +p, +hs}:
      Conn.gate(Conn.allowed(trusted, hs, p, token), s, W.Http.header_of(hs, "sec-websocket-key"), rest, id, inbox,
        Maybe.default(&2, Nat, Nat.read(W.Http.param(p, "since")), 0n), W.Http.param(p, "origin"), String.eq(W.Http.param(p, "enc"), "cbor"))
    case False{} W.Request{_, p, +hs}:
      Conn.static(s, web, W.Http.route(p), String.contains(W.Http.header_of(hs, "accept-encoding"), "gzip"))

def Conn.is_ws(req: W.Request) -> Bool:
  match req:
    case W.Request{_, p, +hs}:
      Bool.and(String.eq(W.Http.route(p), "/ws"), String.eq(String.to_lower(W.Http.header_of(hs, "upgrade")), "websocket"))

def Conn.is_mcp(req: W.Request) -> Bool:
  match req:
    case W.Request{m, p, _}:
      Bool.and(String.eq(m, "POST"), String.starts_with(W.Http.route(p), "/mcp/"))

def Mcp.got(r: Socket & Result<&1, &1, U32 & String, List<&2, U32>>, buf: List<&2, U32>, k: Socket -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  (s, res) = r
  match res:
    case Done{Nil{}}:
      Socket.close(s)
    case Done{bs}:
      k(s, List.append(&2, U32, buf, bs))
    case Fail{_}:
      Socket.close(s)

def Mcp.answer.k(empty: Bool, s: Socket, text: String) -> IO(Unit):
  match empty:
    case True{}:
      Conn.finish(s, W.Http.response("202 Accepted", "application/json", Nil{}, ""))
    case False{}:
      Conn.finish(s, W.Http.response("200 OK", "application/json", U.Utf8.encode(text), ""))

def Mcp.answer(m: Maybe<&1, String>, s: Socket) -> IO(Unit):
  match m:
    case Some{+text}:
      Mcp.answer.k(String.is_empty(text), s, text)
    case None{}:
      Conn.finish(s, W.Http.text("503 Service Unavailable", "the hub is gone"))

def Mcp.ask(s: Socket, +body: String, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    +reply : Chan(String) <- Chan.new(String, 1)
    ok : Bool <- Chan.send(Msg, inbox, Mcp{thread, body, reply})
    m : Maybe<&1, String> <- Chan.recv(String, reply)
    Mcp.answer(m, s)

def Mcp.body.k(full: Bool, s: Socket, +buf: List<&2, U32>, +thread: String, +inbox: Chan(Msg), k: Socket -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match full:
    case True{}:
      Mcp.ask(s, U.Utf8.decode(buf), thread, inbox)
    case False{}:
      IO.bind(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, Unit, H.Sock.recv_bytes(s, 65536), r => Mcp.got(r, buf, k))

# read until the body is complete
def Mcp.body(fuel: Nat, s: Socket, +buf: List<&2, U32>, +len: Nat, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      Conn.finish(s, W.Http.text("413 Payload Too Large", "too large"))
    case 1n+f:
      Mcp.body.k(Nat.is_ge(List.length(&2, U32, buf), len), s, buf, thread, inbox, s2 => b2 => Mcp.body(f, s2, b2, len, thread, inbox))

# MCP over HTTP
# -------------
# One POST per JSON-RPC message; the reply is JSON (or 202 for a
# notification). The hub answers on a channel made for this request.

def Mcp.gate(ok: Bool, s: Socket, +thread: String, +len: Nat, rest: List<&2, U32>, +inbox: Chan(Msg)) -> IO(Unit):
  match ok:
    case True{}:
      Mcp.body(64n, s, rest, len, thread, inbox)
    case False{}:
      Conn.finish(s, W.Http.text("401 Unauthorized", "this Backplane needs its pairing token"))

def Conn.route.mcp(mcp: Bool, s: Socket, +req: W.Request, rest: List<&2, U32>, +web: String, +id: U32, +inbox: Chan(Msg), +trusted: Bool, +token: String) -> IO(Unit):
  match mcp req:
    case True{} W.Request{_, +p, +hs}:
      Mcp.gate(Conn.allowed(trusted, hs, p, token), s, String.drop(W.Http.route(p), 5n),
        Maybe.default(&2, Nat, Nat.read(W.Http.header_of(hs, "content-length")), 0n), rest, inbox)
    case False{} _:
      Conn.route.k(Conn.is_ws(req), s, req, rest, web, id, inbox, trusted, token)

def Conn.route(s: Socket, +req: W.Request, rest: List<&2, U32>, +web: String, +id: U32, +inbox: Chan(Msg), +trusted: Bool, +token: String) -> IO(Unit):
  Conn.route.mcp(Conn.is_mcp(req), s, req, rest, web, id, inbox, trusted, token)

def Conn.head.got(r: Socket & Result<&1, &1, U32 & String, List<&2, U32>>, buf: List<&2, U32>, k: Socket -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  (s, res) = r
  match res:
    case Done{Nil{}}:
      Socket.close(s)
    case Done{bs}:
      k(s, List.append(&2, U32, buf, bs))
    case Fail{_}:
      Socket.close(s)

def Conn.head.k(m: Maybe<&2, W.Split>, s: Socket, buf: List<&2, U32>, +web: String, +id: U32, +inbox: Chan(Msg),
    +trusted: Bool, +token: String, k: Socket -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{W.Split{head, rest}}:
      Conn.route(s, W.Http.request(head), rest, web, id, inbox, trusted, token)
    case None{}:
      IO.bind(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, Unit, H.Sock.recv_bytes(s, 65536), r => Conn.head.got(r, buf, k))

# read until the request head is complete (at most 64 reads)
def Conn.head(fuel: Nat, s: Socket, +buf: List<&2, U32>, +web: String, +id: U32, +inbox: Chan(Msg), +trusted: Bool, +token: String) -> IO(Unit):
  match fuel:
    case 0n:
      Conn.finish(s, W.Http.text("431 Request Header Fields Too Large", "too large"))
    case 1n+f:
      Conn.head.k(W.Http.split(buf), s, buf, web, id, inbox, trusted, token, s2 => b2 => Conn.head(f, s2, b2, web, id, inbox, trusted, token))

# Accepting
# ---------

def Accept.got(r: Listener & Result<&1, &1, U32 & String, Socket>, +id: U32, +web: String, +inbox: Chan(Msg), +trusted: Bool, +token: String, k: Listener -> IO(Unit)) -> IO(Unit):
  (l, res) = r
  match res:
    case Done{s}:
      do IO<Unit>:
        IO.spawn(Unit, Conn.head(64n, s, Nil{}, web, id, inbox, trusted, token))
        k(l)
    case Fail{_}:
      k(l)

# connections from one listener; ids count up from `id` (loopback from 1,
# the tailnet from 2^31, so they never meet)
def Accept.loop(fuel: Nat, l: Listener, +id: U32, +web: String, +inbox: Chan(Msg), +trusted: Bool, +token: String) -> IO(Unit):
  match fuel:
    case 0n:
      Listener.close(l)
    case 1n+f:
      IO.bind(Listener & Result<&1, &1, U32 & String, Socket>, Unit, TCP.accept(l),
        r => Accept.got(r, id, web, inbox, trusted, token, l2 => Accept.loop(f, l2, (id + 1 : U32), web, inbox, trusted, token)))

# a tick at start (threads idle past the window settle at once), then
# every minute
def Ticker.loop(fuel: Nat, +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      do IO<Unit>:
        ok : Bool <- Chan.send(Msg, inbox, Tick{})
        IO.sleep(60000)
        Ticker.loop(f, inbox)

# The hub
# -------

type Hub is Type:
  Hub{state: M.State, log: File, lines: List<&2, String>, clients: List<&2, Client>, agents: List<&2, Agent>, inbox: Chan(Msg), cfg: Cfg, note: String}

def Hub.changes_msg(ls: List<&2, String>) -> String:
  "{\"t\":\"changes\",\"items\":[" ++ String.join(ls, ",") ++ "]}"

def Info.kicad(rt: K.Rt) -> List<&2, J.KV>:
  match rt:
    case K.Rt{cli, fork, v, c}:
      [J.KV{"kicad.cli", J.Str{cli}}, J.KV{"kicad.fork", J.Str{Bool.pick(String, fork, v, "")}}, J.KV{"kicad.commit", J.Str{c}}]

def Info.net(n: Net) -> List<&2, J.KV>:
  match n:
    case Net{tn, hs, _, ms, _, rt, brx, pkx, tmx}:
      List.append(&2, J.KV, [J.KV{"models", J.Str{ms}}, J.KV{"tailnet", J.Str{Bool.pick(String, tn, Bool.pick(String, hs, "https", "on"), "off")}}], Info.kicad(rt))

# what this machine runs, for the settings screen and the model picker
def Hub.info(c: Cfg) -> J.Json:
  match c:
    case Cfg{+home, _, host, port, _, _, _, net}:
      J.Json.obj(List.append(&2, J.KV, [J.KV{"home", J.Str{home}}, J.KV{"browser.frames", J.Str{home ++ "/browser.rgb"}}, J.KV{"listen", J.Str{host ++ ":" ++ U32.show(port)}}], Info.net(net)))

def Hub.commit.wrote(r: File & Result<&1, &1, U32 & String, Unit>, st: M.State, +line: String, ls: List<&2, String>, cl: List<&2, Client>,
    as: List<&2, Agent>, +inbox: Chan(Msg), cfg: Cfg, note: String, fresh: List<&2, String>, k: Hub -> List<&2, String> -> IO(Hub & List<&2, String>)) -> IO(Hub & List<&2, String>):
  (f, _) = r
  k(Hub{st, f, line <> ls, cl, as, inbox, cfg, note}, line <> fresh)

# the full line goes to disk; `wire`, its copy for clients, to the log
def Hub.commit.one(h: Hub, line: String, +wire: String, c: M.Change, fresh: List<&2, String>, k: Hub -> List<&2, String> -> IO(Hub & List<&2, String>)) -> IO(Hub & List<&2, String>):
  match h:
    case Hub{st, f, ls, cl, as, +inbox, cfg, note}:
      IO.bind(File & Result<&1, &1, U32 & String, Unit>, Hub & List<&2, String>, File.write(f, line ++ "\n"),
        r => Hub.commit.wrote(r, M.State.apply(st, c), wire, ls, cl, as, inbox, cfg, note, fresh, k))

def Hub.announce(r: Hub & List<&2, String>) -> IO(Hub):
  (h, fresh) = r
  match h fresh:
    case _ Nil{}:
      IO.pure(Hub, h)
    case Hub{st, f, ls, +cl, as, inbox, cfg, note} l <> t:
      do IO<Hub>:
        Wire.all(cl, Hub.changes_msg(List.reverse(&2, String, l <> t)))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}

# persist changes, fold them in; answers the hub and the new lines (newest first)
def Hub.commit(cs: List<&2, M.Change>, h: Hub, fresh: List<&2, String>) -> IO(Hub & List<&2, String>):
  match cs:
    case Nil{}:
      IO.pure(Hub & List<&2, String>, (h, fresh))
    case +c <> t:
      Hub.commit.one(h, J.Json.show(C.Change.encode(c)), J.Json.show(C.Change.wire(c)), c, fresh,
        h2 => fr2 => Hub.commit(t, h2, fr2))

def Hub.spawned.fail(e: U32 & String, h: Hub, +thread: String) -> IO(Hub):
  (_, +msg) = e
  do IO<Hub>:
    +now : Nat <- Now.nat()
    Log.info("could not start agent: " ++ msg)
    r : Hub & List<&2, String> <- Hub.commit([M.ActivityLogged{thread, "spawn-" ++ Nat.show(now), "error", "spawn", "could not start claude: " ++ msg, now}, M.TurnChanged{thread, M.Failed{}, now}], h, Nil{})
    Hub.announce(r)

def Hub.spawned.dup(r: Socket & Result<&1, &1, U32 & String, Socket>, +pid: U32, h: Hub, +thread: String, +key: String) -> IO(Hub):
  (rd, res) = r
  match res h:
    case Done{wr} Hub{st, f, ls, cl, as, +inbox, cfg, note}:
      do IO<Hub>:
        +input : Chan(String) <- Chan.new(String, 256)
        IO.spawn(Unit, Agent.writer(Fuel.forever(), wr, input))
        IO.spawn(Unit, Agent.reader(Fuel.forever(), rd, U.Lines.new(), pid, thread, inbox))
        return Hub{st, f, ls, cl, Agent{thread, input, pid, key} <> as, inbox, cfg, note}
    case Fail{_} _:
      do IO<Hub>:
        Socket.close(rd)
        return h

def Hub.spawned.ok(started: U32 & Socket, h: Hub, +thread: String, +key: String) -> IO(Hub):
  (pid, s) = started
  do IO<Hub>:
    r : Socket & Result<&1, &1, U32 & String, Socket> <- H.Sock.dup(s)
    Hub.spawned.dup(r, pid, h, thread, key)

def Hub.spawned(r: Result<&1, &1, U32 & String, U32 & Socket>, h: Hub, +thread: String, +key: String) -> IO(Hub):
  match r h:
    case Done{started} Hub{st, f, ls, cl, as, +inbox, cfg, note}:
      Hub.spawned.ok(started, Hub{st, f, ls, cl, as, inbox, cfg, note}, thread, key)
    case Fail{e} _:
      Hub.spawned.fail(e, h, thread)

def Hub.agent_send(m: Maybe<&2, Agent>, line: String) -> IO(Unit):
  match m:
    case Some{Agent{_, input, _, _}}:
      do IO<Unit>:
        ok : Bool <- Chan.send(String, input, line)
        return Unit{}
    case None{}:
      IO.pure(Unit, Unit{})

def Hub.agent_stop(m: Maybe<&2, Agent>) -> IO(Unit):
  match m:
    case Some{Agent{_, input, pid, _}}:
      do IO<Unit>:
        Chan.close(String, input)
        H.Proc.kill(pid, 15)
    case None{}:
      IO.pure(Unit, Unit{})

def Hub.state(h: Hub) -> M.State & Hub:
  match h:
    case Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      (st, Hub{st, f, ls, cl, as, inbox, cfg, note})

def Cfg.version(c: Cfg) -> String:
  match c:
    case Cfg{_, _, _, _, _, _, v, nt}:
      v

# which log this is: the time of its first change (a client resumes only
# into the log it came from)
def Hub.origin(+ls: List<&2, String>) -> String:
  Nat.show(J.Json.get_nat(Maybe.default(&2, J.Json, J.Json.parse(Maybe.default(&2, String, List.last(&2, String, ls), "")), J.Null{}), "at", 0n))

def Hub.log_msg.k(+n: Nat, +ls: List<&2, String>, +cfg: Cfg, +since: Nat) -> String:
  "{\"t\":\"log\",\"since\":" ++ Nat.show(since) ++ ",\"origin\":\"" ++ Hub.origin(ls) ++ "\",\"version\":" ++ J.Json.show(J.Str{Cfg.version(cfg)}) ++ ",\"info\":" ++ J.Json.show(Hub.info(cfg))
    ++ ",\"items\":[" ++ String.join(List.reverse(&2, String, List.take(&2, String, ls, Nat.sub(n, since))), ",") ++ "]}"

# the log for a client that has the first `since` changes already (a
# reconnect sends only what it missed; a client ahead of the log, as after
# a server reset, gets everything, since 0)
def Hub.log_msg(+ls: List<&2, String>, +cfg: Cfg, +since: Nat) -> String:
  Hub.log_msg.k(List.length(&2, String, ls), ls, cfg, Bool.pick(Nat, Nat.is_le(since, List.length(&2, String, ls)), since, 0n))

def Hub.join.note.k(empty: Bool, +out: Chan(Wire), +note: String) -> IO(Unit):
  match empty:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        ok : Bool <- Chan.send(Wire, out, WText{note})
        return Unit{}

def Hub.join.note(+out: Chan(Wire), +note: String) -> IO(Unit):
  Hub.join.note.k(String.is_empty(note), out, note)

def Hub.join(h: Hub, +client: U32, +out: Chan(Wire), +since: Nat, +origin: String) -> IO(Hub):
  match h:
    case Hub{st, f, +ls, cl, as, inbox, +cfg, +note}:
      do IO<Hub>:
        ok : Bool <- Chan.send(Wire, out, WText{Hub.log_msg(ls, cfg, Bool.pick(Nat, String.eq(origin, Hub.origin(ls)), since, 0n))})
        Hub.join.note(out, note)
        return Hub{st, f, ls, Client{client, out} <> cl, as, inbox, cfg, note}

def Hub.leave.close(m: Maybe<&2, Chan(Wire)>) -> IO(Unit):
  match m:
    case Some{c}:
      Chan.close(Wire, c)
    case None{}:
      IO.pure(Unit, Unit{})

def Hub.leave(h: Hub, +client: U32) -> IO(Hub):
  match h:
    case Hub{st, f, ls, +cl, as, inbox, cfg, note}:
      do IO<Hub>:
        Hub.leave.close(Clients.get(cl, client))
        return Hub{st, f, ls, Clients.drop(cl, client), as, inbox, cfg, note}

def Hub.push(h: Hub, +client: U32, text: String) -> IO(Hub):
  match h:
    case Hub{st, f, ls, +cl, as, inbox, cfg, note}:
      do IO<Hub>:
        Wire.send(Clients.get(cl, client), WText{text})
        return Hub{st, f, ls, cl, as, inbox, cfg, note}

def Hub.note(h: Hub, +text: String) -> IO(Hub):
  match h:
    case Hub{st, f, ls, +cl, as, inbox, cfg, _}:
      do IO<Hub>:
        Wire.all(cl, text)
        return Hub{st, f, ls, cl, as, inbox, cfg, text}

def Hub.close(h: Hub) -> IO(Unit):
  match h:
    case Hub{_, f, _, _, _, _, _, _}:
      File.close(f)

# the hub's inbox, handed to k beside the hub
def Hub.inbox(h: Hub, k: Chan(Msg) -> Hub -> IO(Unit)) -> IO(Unit):
  match h:
    case Hub{st, f, ls, cl, as, +inbox, cfg, note}:
      k(inbox, Hub{st, f, ls, cl, as, inbox, cfg, note})

# Codex
# -----

def Codex.sandbox(r: M.RuntimeMode) -> List<&2, String>:
  match r:
    case M.FullAccess{}:
      ["--dangerously-bypass-approvals-and-sandbox"]
    case M.Supervised{}:
      ["-s", "read-only"]
    case _:
      ["-s", "workspace-write"]

def Codex.opt.k(empty: Bool, flag: String, v: String) -> List<&2, String>:
  match empty:
    case True{}:
      Nil{}
    case False{}:
      [flag, v]

def Codex.opt(flag: String, +v: String) -> List<&2, String>:
  Codex.opt.k(String.is_empty(v), flag, v)

def Codex.head.k(fresh: Bool, +session: String) -> List<&2, String>:
  match fresh:
    case True{}:
      ["exec", "--json", "--skip-git-repo-check"]
    case False{}:
      ["exec", "resume", session, "--json", "--skip-git-repo-check"]

def Cfg.prompt(c: Cfg) -> String:
  match c:
    case Cfg{_, _, _, _, pr, _, _, _}:
      pr

def Codex.failed(e: U32 & String, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  (_, msg) = e
  do IO<Unit>:
    ok : Bool <- Chan.send(Msg, inbox, AgentLine{thread, "{\"type\":\"turn.failed\",\"message\":" ++ J.Json.show(J.Str{"could not start codex: " ++ msg}) ++ "}"})
    return Unit{}

# whether a Codex event line ends the turn
def Codex.ends(+l: String) -> Bool:
  Bool.or(String.contains(l, "\"type\":\"turn.completed\""), String.contains(l, "\"type\":\"turn.failed\""))

def Codex.lines(ls: List<&2, String>, +ended: Bool, +thread: String, +inbox: Chan(Msg)) -> IO(Bool):
  match ls:
    case Nil{}:
      IO.pure(Bool, ended)
    case +l <> t:
      do IO<Bool>:
        ok : Bool <- Chan.send(Msg, inbox, AgentLine{thread, l})
        Codex.lines(t, Bool.or(ended, Codex.ends(l)), thread, inbox)

def Codex.fed(r: U.Lines & List<&2, String>, s: Socket, +ended: Bool, +thread: String, +inbox: Chan(Msg), k: Socket -> U.Lines -> Bool -> IO(Unit)) -> IO(Unit):
  (carry, ls) = r
  IO.bind(Bool, Unit, Codex.lines(ls, ended, thread, inbox), e2 => k(s, carry, e2))

# Folders for the project picker
# ------------------------------
# The path is always an argument ($1), never part of a script.

def FsJob.list.sh() -> String:
  "exec 2>&1; set -e; d=\"$1\"; case \"$d\" in ''|'~') d=\"$HOME\";; '~/'*) d=\"$HOME/${d#~/}\";; esac; d=$(realpath -e -- \"$d\"); [ -d \"$d\" ] || { echo \"not a folder: $d\"; exit 2; }; echo \"$d\"; find \"$d\" -mindepth 1 -maxdepth 1 -type d -printf '%f\\n' 2>/dev/null | LC_ALL=C sort | head -n 5000"

def FsJob.mkdir.sh() -> String:
  "exec 2>&1; set -e; d=\"$1\"; case \"$d\" in '~/'*) d=\"$HOME/${d#~/}\";; esac; if [ -e \"$d\" ]; then echo \"already exists: $d\"; exit 3; fi; mkdir -- \"$d\"; d=$(realpath -e -- \"$d\"); echo \"$d\""

def FsJob.strs(ls: List<&2, String>) -> List<&2, J.Json>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> t:
      J.Str{l} <> FsJob.strs(t)

def FsJob.listed.k(ls: List<&2, String>) -> J.Json:
  match ls:
    case d <> t:
      J.Json.obj([J.KV{"dir", J.Str{d}}, J.KV{"entries", J.Json.arr(FsJob.strs(t))}])
    case Nil{}:
      J.Json.obj([J.KV{"error", J.Str{"not a folder"}}])

def FsJob.listed(r: P.Ran) -> J.Json:
  match r:
    case P.Ran{0, out}:
      FsJob.listed.k(String.lines(String.trim(out)))
    case P.Ran{_, out}:
      J.Json.obj([J.KV{"error", J.Str{String.trim(out)}}])

def FsJob.ok(+r: J.Json) -> Bool:
  String.eq(J.Json.show(Maybe.default(&2, J.Json, J.Json.get(r, "error"), J.Null{})), "null")

# Git jobs
# --------
# The hub asks; git runs here off the hub's thread; results go back as a
# reply to the asking client, and as thread notes/events through the hub.

def GitJob.say(+inbox: Chan(Msg), +m: String, p: List<&2, J.KV>) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(Msg, inbox, Rpc{0, J.Json.show(J.Json.obj([J.KV{"id", J.Num{"0"}}, J.KV{"m", J.Str{m}}, J.KV{"p", J.Json.obj(p)}]))})
    return Unit{}

def GitJob.note(+inbox: Chan(Msg), +thread: String, +tone: String, +summary: String) -> IO(Unit):
  GitJob.say(inbox, "thread.note", [J.KV{"thread", J.Str{thread}}, J.KV{"tone", J.Str{tone}}, J.KV{"kind", J.Str{"git"}}, J.KV{"summary", J.Str{summary}}])

def GitJob.reply(+inbox: Chan(Msg), +client: U32, +id: String, +ok: Bool, r: J.Json) -> IO(Unit):
  do IO<Unit>:
    sent : Bool <- Chan.send(Msg, inbox, Push{client, J.Json.show(J.Json.obj([J.KV{"t", J.Str{"reply"}}, J.KV{"id", J.Num{id}}, J.KV{"ok", J.Flag{ok}}, J.KV{"result", r}]))})
    return Unit{}

def FsJob.answer(+inbox: Chan(Msg), +client: U32, +id: String, +r: J.Json) -> IO(Unit):
  GitJob.reply(inbox, client, id, FsJob.ok(r), r)

def FsJob.list(+inbox: Chan(Msg), +client: U32, +id: String, +path: String) -> IO(Unit):
  IO.bind(P.Ran, Unit, P.Proc.run("sh", ["-c", FsJob.list.sh(), "sh", path], "/"), r => FsJob.answer(inbox, client, id, FsJob.listed(r)))

def FsJob.made(r: P.Ran, +inbox: Chan(Msg), +client: U32, +id: String) -> IO(Unit):
  match r:
    case P.Ran{0, out}:
      FsJob.list(inbox, client, id, String.trim(out))
    case P.Ran{_, out}:
      FsJob.answer(inbox, client, id, J.Json.obj([J.KV{"error", J.Str{String.trim(out)}}]))

def FsJob.run(+op: String, +inbox: Chan(Msg), +client: U32, +id: String, +path: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.eq(op, "mkdir"),
    IO.bind(P.Ran, Unit, P.Proc.run("sh", ["-c", FsJob.mkdir.sh(), "sh", path], "/"), r => FsJob.made(r, inbox, client, id)),
    FsJob.list(inbox, client, id, path))

def GitJob.nonblank(ls: List<&2, String>, +n: Nat) -> Nat:
  match ls:
    case Nil{}:
      n
    case l <> t:
      GitJob.nonblank(t, Bool.pick(Nat, String.is_empty(String.trim(l)), n, 1n+n))

def GitJob.count.k(r: P.Ran) -> Nat:
  match r:
    case P.Ran{0, out}:
      GitJob.nonblank(String.lines(out), 0n)
    case _:
      0n

# how many checkpoints a thread has (its next turn number)
def GitJob.count(+cwd: String, +thread: String) -> IO(Nat):
  IO.bind(P.Ran, Nat, P.Proc.run("git", ["for-each-ref", "--format=%(refname)", "refs/backplane/checkpoints/" ++ GT.Git.b64url(thread) ++ "/turn/"], cwd),
    r => IO.pure(Nat, GitJob.count.k(r)))

def GitJob.cp0.k(n: Nat, +cwd: String, +thread: String) -> IO(Unit):
  match n:
    case 0n:
      IO.bind(String, Unit, GT.Git.checkpoint.capture(cwd, thread, 0n), r => IO.pure(Unit, Unit{}))
    case _:
      IO.pure(Unit, Unit{})

def GitJob.worktree.k(+r: String, +inbox: Chan(Msg), +thread: String, +branch: String) -> IO(Unit):
  Bool.pick(IO(Unit), GT.Git.failed(r), GitJob.note(inbox, thread, "error", "worktree: " ++ r),
    GitJob.say(inbox, "thread.worktree", [J.KV{"thread", J.Str{thread}}, J.KV{"branch", J.Str{branch}}, J.KV{"path", J.Str{r}}]))

def GitJob.text.k(+inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +what: String, +r: String) -> IO(Unit):
  do IO<Unit>:
    GitJob.reply(inbox, client, id, Bool.not(GT.Git.failed(r)), J.Json.obj([J.KV{"text", J.Str{r}}, J.KV{"thread", J.Str{thread}}]))
    GitJob.note(inbox, thread, Bool.pick(String, GT.Git.failed(r), "error", "info"), what ++ Bool.pick(String, String.is_empty(r), "", ": " ++ String.trim(r)))

def GitJob.diff.k(+inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +r: String) -> IO(Unit):
  GitJob.reply(inbox, client, id, Bool.not(GT.Git.failed(r)), J.Json.obj([J.KV{"diff", J.Str{r}}, J.KV{"thread", J.Str{thread}}]))

def GitJob.diff(+cwd: String, +thread: String, +a: String, +b: String) -> IO(String):
  Bool.pick(IO(String), String.eq(b, "-1"), GT.Git.checkpoint.diff_worktree(cwd, thread, Maybe.default(&2, Nat, Nat.read(a), 0n)),
    GT.Git.checkpoint.diff(cwd, thread, Maybe.default(&2, Nat, Nat.read(a), 0n), Maybe.default(&2, Nat, Nat.read(b), 0n)))

def GitJob.go(i: Nat, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String, +a: String, +b: String, +home: String, +seed: Nat) -> IO(Unit):
  match i:
    case 0n:
      IO.bind(String, Unit, GT.Git.worktree.create(cwd, home, a, GT.Git.branch.temp(seed), ""), r => GitJob.worktree.k(r, inbox, thread, GT.Git.branch.temp(seed)))
    case 1n:
      IO.bind(Nat, Unit, GitJob.count(cwd, thread), n => GitJob.cp0.k(n, cwd, thread))
    case 2n:
      IO.bind(Nat, Unit, GitJob.count(cwd, thread), n => IO.bind(String, Unit, GT.Git.checkpoint.capture(cwd, thread, n), r => IO.pure(Unit, Unit{})))
    case 3n:
      IO.bind(String, Unit, GitJob.diff(cwd, thread, a, b), r => GitJob.diff.k(inbox, client, id, thread, r))
    case 4n:
      IO.bind(String, Unit, GT.Git.checkpoint.revert(cwd, thread, Maybe.default(&2, Nat, Nat.read(a), 0n)), r => GitJob.text.k(inbox, client, id, thread, "reverted to turn " ++ a, r))
    case 5n:
      IO.bind(String, Unit, GT.Git.act(cwd, a, Bool.pick(String, String.is_empty(b), "Backplane: changes from this thread", b), "", ""), r => GitJob.text.k(inbox, client, id, thread, a, r))
    case 6n:
      IO.bind(String, Unit, GT.Git.status(cwd), r => GitJob.reply(inbox, client, id, True{}, J.Json.obj([J.KV{"status", J.Str{r}}, J.KV{"thread", J.Str{thread}}])))
    case _:
      IO.pure(Unit, Unit{})

def GitJob.repo(ok: Bool, +job: String, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String, +a: String, +b: String, +home: String, +seed: Nat) -> IO(Unit):
  match ok:
    case True{}:
      GitJob.go(C.Codec.pos(["worktree", "checkpoint0", "checkpoint", "diff", "revert", "act", "status"], job), inbox, client, id, thread, cwd, a, b, home, seed)
    case False{}:
      Bool.pick(IO(Unit), String.is_empty(id), IO.pure(Unit, Unit{}), GitJob.reply(inbox, client, id, False{}, J.Json.obj([J.KV{"text", J.Str{"not a git repository: " ++ cwd}}])))

# one git job; nothing happens outside a git repository (checkpoints are
# skipped, requests answer why)
def GitJob.run(+job: String, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String, +a: String, +b: String, +home: String) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- GT.Git.is_repo(cwd)
    t : U32 <- H.Clock.epoch()
    GitJob.repo(ok, job, inbox, client, id, thread, cwd, a, b, home, U32.to_nat(t))

# Grok (grok agent stdio, ACP)
# ----------------------------
# One process per turn. Acp.line decides what to write back and what to
# report; the reports are Codex-shaped lines for the hub.

def Grok.perm(r: M.RuntimeMode) -> List<&2, String>:
  match r:
    case M.Supervised{}:
      ["--permission-mode", "default", "agent"]
    case M.AcceptEdits{}:
      ["--permission-mode", "acceptEdits", "agent"]
    case M.AutoMode{}:
      ["--permission-mode", "auto", "agent"]
    case M.FullAccess{}:
      ["agent", "--always-approve"]

def Grok.args(r: M.RuntimeMode, +model: String) -> List<&2, String>:
  List.concat(&2, String, [Grok.perm(r), Codex.opt("-m", model), ["stdio"]])

def Grok.report(ls: List<&2, String>, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  match ls:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case l <> t:
      do IO<Unit>:
        ok : Bool <- Chan.send(Msg, inbox, AgentLine{thread, l})
        Grok.report(t, thread, inbox)

def Grok.write(ls: List<&2, String>, +input: Chan(String)) -> IO(Unit):
  match ls:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case l <> t:
      do IO<Unit>:
        ok : Bool <- Chan.send(String, input, l)
        Grok.write(t, input)

def Grok.acp(o: AC.AcpOut) -> AC.Acp:
  match o:
    case AC.AcpOut{a, _, _}:
      a

def Grok.done(a: AC.Acp) -> Bool:
  match a:
    case AC.Acp{_, _, d}:
      d

def Grok.out(o: AC.AcpOut, +thread: String, +input: Chan(String), +inbox: Chan(Msg)) -> IO(AC.Acp):
  match o:
    case AC.AcpOut{a, send, emit}:
      do IO<AC.Acp>:
        Grok.write(send, input)
        Grok.report(emit, thread, inbox)
        return a

# every line of a chunk, in order, through the ACP state
def Grok.lines(ls: List<&2, String>, a: AC.Acp, +t: AC.AcpTurn, +thread: String, +input: Chan(String), +inbox: Chan(Msg)) -> IO(AC.Acp):
  match ls:
    case Nil{}:
      IO.pure(AC.Acp, a)
    case l <> rest:
      IO.bind(AC.Acp, AC.Acp, Grok.out(AC.Acp.line(a, t, l), thread, input, inbox), a2 => Grok.lines(rest, a2, t, thread, input, inbox))

# a per-turn process is done: its turn already ended through its own
# events, so its exit tells the hub nothing (a queued turn may be running)
def Turn.end(s: Socket, +pid: U32) -> IO(Unit):
  do IO<Unit>:
    Socket.close(s)
    code : U32 <- H.Proc.wait(pid)
    return Unit{}

# output closed: a turn that never ended fails; the exit itself is not news
def Codex.end(s: Socket, +pid: U32, ended: Bool, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  match ended:
    case True{}:
      Turn.end(s, pid)
    case False{}:
      do IO<Unit>:
        ok : Bool <- Chan.send(Msg, inbox, AgentLine{thread, AC.Acp.failed("codex exited before the turn ended")})
        Turn.end(s, pid)

def Codex.got(r: Socket & Result<&1, &1, U32 & String, List<&2, U32>>, carry: U.Lines, +ended: Bool, +pid: U32, +thread: String, +inbox: Chan(Msg), k: Socket -> U.Lines -> Bool -> IO(Unit)) -> IO(Unit):
  (s, res) = r
  match res:
    case Done{Nil{}}:
      Codex.end(s, pid, ended, thread, inbox)
    case Done{bs}:
      Codex.fed(U.Lines.feed(carry, bs), s, ended, thread, inbox, k)
    case Fail{_}:
      Codex.end(s, pid, ended, thread, inbox)

def Codex.reader(fuel: Nat, s: Socket, carry: U.Lines, +ended: Bool, +pid: U32, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      Codex.end(s, pid, ended, thread, inbox)
    case 1n+f:
      IO.bind(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, Unit, H.Sock.recv_bytes(s, 65536),
        r => Codex.got(r, carry, ended, pid, thread, inbox, s2 => c2 => e2 => Codex.reader(f, s2, c2, e2, pid, thread, inbox)))

def Codex.read(started: U32 & Socket, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  (+pid, s) = started
  do IO<Unit>:
    s2 : Socket <- H.Sock.shutdown(s)
    Codex.reader(Fuel.forever(), s2, U.Lines.new(), False{}, pid, thread, inbox)

def Codex.started(r: Result<&1, &1, U32 & String, U32 & Socket>, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  match r:
    case Done{started}:
      Codex.read(started, thread, inbox)
    case Fail{e}:
      Codex.failed(e, thread, inbox)

def Codex.run(+args: List<&2, String>, +cwd: String, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  IO.bind(Result<&1, &1, U32 & String, U32 & Socket>, Unit, H.Proc.spawn("codex", args, cwd, 0), r => Codex.started(r, thread, inbox))

def Grok.stop(s: Socket, +pid: U32, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    H.Proc.kill(pid, 15)
    Turn.end(s, pid)

def Grok.next(done: Bool, s: Socket, carry: U.Lines, a: AC.Acp, +pid: U32, +thread: String, +inbox: Chan(Msg), k: Socket -> U.Lines -> AC.Acp -> IO(Unit)) -> IO(Unit):
  match done:
    case True{}:
      Grok.stop(s, pid, thread, inbox)
    case False{}:
      k(s, carry, a)

def Grok.after(+a: AC.Acp, s: Socket, carry: U.Lines, +pid: U32, +thread: String, +inbox: Chan(Msg), k: Socket -> U.Lines -> AC.Acp -> IO(Unit)) -> IO(Unit):
  Grok.next(Grok.done(a), s, carry, a, pid, thread, inbox, k)

def Grok.fed(r: U.Lines & List<&2, String>, s: Socket, a: AC.Acp, +t: AC.AcpTurn, +pid: U32, +thread: String, +input: Chan(String), +inbox: Chan(Msg),
    k: Socket -> U.Lines -> AC.Acp -> IO(Unit)) -> IO(Unit):
  (carry, ls) = r
  IO.bind(AC.Acp, Unit, Grok.lines(ls, a, t, thread, input, inbox), a2 => Grok.after(a2, s, carry, pid, thread, inbox, k))

# the agent closed its output before the turn ended
def Grok.gone(s: Socket, +pid: U32, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    Grok.report([AC.Acp.failed("grok exited before the turn ended (is it signed in? run `grok login`)")], thread, inbox)
    Turn.end(s, pid)

def Grok.got(r: Socket & Result<&1, &1, U32 & String, List<&2, U32>>, carry: U.Lines, a: AC.Acp, +t: AC.AcpTurn, +pid: U32, +thread: String, +input: Chan(String), +inbox: Chan(Msg),
    k: Socket -> U.Lines -> AC.Acp -> IO(Unit)) -> IO(Unit):
  (s, res) = r
  match res:
    case Done{Nil{}}:
      Grok.gone(s, pid, thread, inbox)
    case Done{bs}:
      Grok.fed(U.Lines.feed(carry, bs), s, a, t, pid, thread, input, inbox, k)
    case Fail{_}:
      Grok.gone(s, pid, thread, inbox)

def Grok.reader(fuel: Nat, s: Socket, carry: U.Lines, a: AC.Acp, +t: AC.AcpTurn, +pid: U32, +thread: String, +input: Chan(String), +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      Agent.end(s, pid, thread, inbox)
    case 1n+f:
      IO.bind(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, Unit, H.Sock.recv_bytes(s, 65536),
        r => Grok.got(r, carry, a, t, pid, thread, input, inbox, s2 => c2 => a2 => Grok.reader(f, s2, c2, a2, t, pid, thread, input, inbox)))

def Grok.duped(r: Socket & Result<&1, &1, U32 & String, Socket>, +pid: U32, +t: AC.AcpTurn, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  (rd, res) = r
  match res:
    case Done{wr}:
      do IO<Unit>:
        +input : Chan(String) <- Chan.new(String, 64)
        IO.spawn(Unit, Agent.writer(Fuel.forever(), wr, input))
        ok : Bool <- Chan.send(String, input, AC.Acp.init())
        Grok.reader(Fuel.forever(), rd, U.Lines.new(), AC.Acp.new(), t, pid, thread, input, inbox)
    case Fail{_}:
      Socket.close(rd)

def Grok.started.ok(started: U32 & Socket, +t: AC.AcpTurn, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  (+pid, s) = started
  IO.bind(Socket & Result<&1, &1, U32 & String, Socket>, Unit, H.Sock.dup(s), r => Grok.duped(r, pid, t, thread, inbox))

def Grok.failed(e: U32 & String, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  (_, msg) = e
  Grok.report([AC.Acp.failed("could not start grok: " ++ msg ++ ". Install Grok Build with `curl -fsSL https://x.ai/cli/install.sh | bash`, then `grok login`.")], thread, inbox)

def Grok.started(r: Result<&1, &1, U32 & String, U32 & Socket>, +t: AC.AcpTurn, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  match r:
    case Done{started}:
      Grok.started.ok(started, t, thread, inbox)
    case Fail{e}:
      Grok.failed(e, thread, inbox)

def Grok.run(+args: List<&2, String>, +t: AC.AcpTurn, +cwd: String, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  IO.bind(Result<&1, &1, U32 & String, U32 & Socket>, Unit, H.Proc.spawn("grok", args, cwd, 0), r => Grok.started(r, t, thread, inbox))

# Updates
# -------

def Cfg.home(c: Cfg) -> String:
  match c:
    case Cfg{h, _, _, _, _, _, _, _}:
      h

def Upgrade.note(kvs: List<&2, J.KV>) -> String:
  J.Json.show(J.Json.obj(J.KV{"t", J.Str{"update"}} <> kvs))

def Upgrade.say(+inbox: Chan(Msg), text: String) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(Msg, inbox, Announce{text})
    return Unit{}

def Upgrade.exec.fail(e: U32 & String, +inbox: Chan(Msg)) -> IO(Unit):
  (_, m) = e
  Upgrade.say(inbox, Upgrade.note([J.KV{"error", J.Str{"restart failed: " ++ m}}]))

def Upgrade.exec(r: Result<&1, &1, U32 & String, Unit>, +inbox: Chan(Msg)) -> IO(Unit):
  match r:
    case Done{_}:
      IO.pure(Unit, Unit{})
    case Fail{e}:
      Upgrade.exec.fail(e, inbox)

def Upgrade.found.k(none: Bool, +tag: String, +inbox: Chan(Msg)) -> IO(Unit):
  match none:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      Upgrade.say(inbox, Upgrade.note([J.KV{"version", J.Str{tag}}]))

def Upgrade.found(+tag: String, +inbox: Chan(Msg)) -> IO(Unit):
  Upgrade.found.k(String.is_empty(tag), tag, inbox)

# 15 s after start, then hourly: announce a newer release
def Upgrade.check(fuel: Nat, +wait: U32, +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      do IO<Unit>:
        IO.sleep(wait)
        r : Maybe<&2, UP.Release> <- UP.Update.latest()
        Upgrade.found(UP.Update.newer(r), inbox)
        Upgrade.check(f, 3600000, inbox)

def Upgrade.start.go(on: Bool, +inbox: Chan(Msg)) -> IO(Unit):
  match on:
    case True{}:
      IO.spawn(Unit, Upgrade.check(Fuel.forever(), 15000, inbox))
    case False{}:
      IO.pure(Unit, Unit{})

def Upgrade.start.k(+off: String, +inbox: Chan(Msg)) -> IO(Unit):
  Upgrade.start.go(String.is_empty(off), inbox)

# Remote access (Tailscale)
# ------------------------

def Cfg.net(c: Cfg) -> Net:
  match c:
    case Cfg{_, _, _, _, _, _, _, n}:
      n

def Cfg.port(c: Cfg) -> U32:
  match c:
    case Cfg{_, _, _, p, _, _, _, _}:
      p

def Net.token(n: Net) -> String:
  match n:
    case Net{_, _, t, _, _, _, brx, pkx, tmx}:
      t

# Effects
# -------

# the MCP endpoint of one thread's agent (token included, so the tailnet
# rules never lock an agent out)
def Hub.mcp_url(+cfg: Cfg, +thread: String) -> String:
  "http://127.0.0.1:" ++ U32.show(Cfg.port(cfg)) ++ "/mcp/" ++ thread ++ "?token=" ++ Net.token(Cfg.net(cfg))

def Cfg.mtext(c: Cfg) -> String:
  match c:
    case Cfg{_, _, _, _, _, _, _, Net{_, _, _, _, mt, _, brx, pkx, tmx}}:
      mt

def Cfg.rt(c: Cfg) -> K.Rt:
  match c:
    case Cfg{_, _, _, _, _, _, _, Net{_, _, _, _, _, rt, brx, pkx, tmx}}:
      rt

def Hub.prompt.kicad(rt: K.Rt, ipc: Bool) -> String:
  match rt:
    case K.Rt{+cli, fork, +v, +c}:
      Q.Prompt.kicad(cli, fork, v, c, ipc)

def Hub.prompt.files(+cwd: String, fs: K.Files) -> String:
  match fs:
    case K.Files{+pro, +pcb, +sch}:
      Q.Prompt.project(cwd, pro, pcb, sch)

# one thread's instructions: the shared runtime and skills, then this
# machine's KiCad, the project's canonical files, and what it may delegate
def Hub.prompt(+cfg: Cfg, +st: M.State, +thread: String, +cwd: String, fs: K.Files) -> String:
  String.join([Cfg.prompt(cfg),
    Hub.prompt.kicad(Cfg.rt(cfg), Bool.not(String.eq(M.Setting.get(st, "kicad.ipc", "on"), "off"))),
    Hub.prompt.files(cwd, fs),
    Q.Prompt.orchestration(M.Task.may_delegate(B.Task.depth(st, thread)), Cfg.mtext(cfg))], "\n\n")

def Hub.agent_args(+cfg: Cfg, +thread: String, +model: String, +session: String, +r: M.RuntimeMode, +i: M.InteractionMode, prompt: String) -> List<&2, String>:
  match cfg:
    case Cfg{_, _, _, _, _, dirs, _, _}:
      List.append(&2, String, Q.Claude.args(model, session, r, i, prompt, dirs),
        ["--mcp-config", "{\"mcpServers\":{\"backplane\":{\"type\":\"http\",\"url\":\"" ++ Hub.mcp_url(cfg, thread) ++ "\"}}}"])

# what a Claude process was started with; a turn asking for something else
# (another model or mode) restarts it
def Agent.key(+model: String, r: M.RuntimeMode, i: M.InteractionMode) -> String:
  model ++ "|" ++ C.Runtime.name(r) ++ "|" ++ C.Interaction.name(i)

def Agent.same(m: Maybe<&2, Agent>, +key: String) -> Bool:
  match m:
    case Some{Agent{_, _, _, k}}:
      String.eq(k, key)
    case None{}:
      False{}

def Hub.start.go(same: Bool, m: Maybe<&2, Agent>, h: Hub, +thread: String, +cwd: String, +model: String, +session: String, +r: M.RuntimeMode, +i: M.InteractionMode) -> IO(Hub):
  match same h:
    case True{} _:
      IO.pure(Hub, h)
    case False{} Hub{+st, f, ls, cl, +as, inbox, +cfg, note}:
      do IO<Hub>:
        Hub.agent_stop(m)
        fs : K.Files <- K.Files.read(cwd)
        res : Result<&1, &1, U32 & String, U32 & Socket> <- H.Proc.spawn("env", "MCP_TOOL_TIMEOUT=86400000" <> "claude" <> Hub.agent_args(cfg, thread, model, session, r, i, Hub.prompt(cfg, st, thread, cwd, fs)), cwd, 0)
        Hub.spawned(res, Hub{st, f, ls, cl, Agents.drop(as, thread), inbox, cfg, note}, thread, Agent.key(model, r, i))

def Hub.start.k(+m: Maybe<&2, Agent>, h: Hub, +thread: String, +cwd: String, +model: String, +session: String, +r: M.RuntimeMode, +i: M.InteractionMode) -> IO(Hub):
  Hub.start.go(Agent.same(m, Agent.key(model, r, i)), m, h, thread, cwd, model, session, r, i)

# `codex exec` for one turn, with this thread's MCP endpoint and the
# Backplane instructions (the same runtime block Claude gets)
def Codex.args(+cfg: Cfg, +thread: String, +model: String, +session: String, r: M.RuntimeMode, +text: String, prompt: String) -> List<&2, String>:
  List.concat(&2, String, [Codex.head.k(String.is_empty(session), session), Codex.sandbox(r), Codex.opt("-m", model),
    ["-c", "mcp_servers.backplane.url=\"" ++ Hub.mcp_url(cfg, thread) ++ "\"",
     "-c", "developer_instructions=" ++ J.Json.show(J.Str{prompt}), text]])

def Tailnet.first(r: P.Ran) -> String:
  match r:
    case P.Ran{0, out}:
      String.trim(Maybe.default(&2, String, List.head(&2, String, String.lines(out)), ""))
    case _:
      ""

def Tailnet.dns.k(+name: String) -> String:
  Bool.pick(String, String.ends_with(name, "."), String.take(name, Nat.sub(String.length(name), 1n)), name)

def Tailnet.dns(r: P.Ran) -> String:
  match r:
    case P.Ran{0, out}:
      Tailnet.dns.k(J.Json.get_str(J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(out), J.Null{}), "Self"), "DNSName", ""))
    case _:
      ""

def Tailnet.listened(r: Result<&1, &1, U32 & String, Listener>, +ip: String, +port: U32, +web: String, +inbox: Chan(Msg), +token: String) -> IO(Unit):
  match r:
    case Done{l}:
      do IO<Unit>:
        IO.print("Backplane on your tailnet: http://" ++ ip ++ ":" ++ U32.show(port) ++ "/#token=" ++ token)
        IO.spawn(Unit, Accept.loop(Fuel.forever(), l, 2147483648, web, inbox, False{}, token))
    case Fail{_}:
      Log.info("could not listen on the tailnet address " ++ ip)

def Tailnet.listen.k(none: Bool, +ip: String, +port: U32, +web: String, +inbox: Chan(Msg), +token: String) -> IO(Unit):
  match none:
    case True{}:
      Log.info("tailscale is not up (tailscale ip -4 gave nothing)")
    case False{}:
      IO.bind(Result<&1, &1, U32 & String, Listener>, Unit, H.Net.listen(ip, port), r => Tailnet.listened(r, ip, port, web, inbox, token))

def Tailnet.https.k(none: Bool, +name: String, +token: String) -> IO(Unit):
  match none:
    case True{}:
      Log.info("tailscale serve did not report a DNS name")
    case False{}:
      IO.print("Backplane over HTTPS on your tailnet: https://" ++ name ++ "/#token=" ++ token)

def Tailnet.https(on: Bool, +port: U32, +token: String) -> IO(Unit):
  match on:
    case True{}:
      do IO<Unit>:
        s : P.Ran <- P.Proc.run("tailscale", ["serve", "--bg", "--https=443", "http://127.0.0.1:" ++ U32.show(port)], "")
        st : P.Ran <- P.Proc.run("tailscale", ["status", "--json"], "")
        +name : String = Tailnet.dns(st)
        Tailnet.https.k(String.is_empty(name), name, token)
    case False{}:
      IO.pure(Unit, Unit{})

# listen on the tailnet address too (clients there need the token), and
# serve HTTPS through `tailscale serve` when asked
def Tailnet.start(n: Net, +port: U32, +web: String, +inbox: Chan(Msg)) -> IO(Unit):
  match n:
    case Net{True{}, https, +token, _, _, _, brx, pkx, tmx}:
      do IO<Unit>:
        r : P.Ran <- P.Proc.run("tailscale", ["ip", "-4"], "")
        +ip : String = Tailnet.first(r)
        Tailnet.listen.k(String.is_empty(ip), ip, port, web, inbox, token)
        Tailnet.https(https, port, token)
    case Net{False{}, _, _, _, _, _, brx, pkx, tmx}:
      IO.pure(Unit, Unit{})

def Token.digit(+d: U32) -> Char:
  Chr{U32.add(d, Bool.pick(U32, U32.is_lt(d, 10), 48, 87))}

def Token.hex.go(n: Nat, +x: U32, acc: String) -> String:
  match n:
    case 0n:
      acc
    case 1n+m:
      Token.hex.go(m, U32.shrn(x, 4n), SCon{Token.digit(U32.and(x, 15)), acc})

# the pairing token: made once (128 random bits, hex), kept in the home
def Token.hex(+x: U32) -> String:
  Token.hex.go(8n, x, "")

def Token.fresh() -> IO(String):
  do IO<String>:
    a : U32 <- IO.try(U32, IO.random_u32())
    b : U32 <- IO.try(U32, IO.random_u32())
    c : U32 <- IO.try(U32, IO.random_u32())
    d : U32 <- IO.try(U32, IO.random_u32())
    return Token.hex(a) ++ Token.hex(b) ++ Token.hex(c) ++ Token.hex(d)

def Token.closed(w: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, _) = w
  File.close(f)

def Token.write(r: Result<&1, &1, U32 & String, File>, +t: String) -> IO(Unit):
  match r:
    case Done{f}:
      IO.bind(File & Result<&1, &1, U32 & String, Unit>, Unit, File.write(f, t), w => Token.closed(w))
    case Fail{_}:
      IO.pure(Unit, Unit{})

def Token.save(+path: String, +t: String) -> IO(String):
  do IO<String>:
    f : Result<&1, &1, U32 & String, File> <- File.open(path, "w")
    Token.write(f, t)
    m : Result<&1, &1, U32 & String, Unit> <- H.FS.chmod(path, 384)
    return t

def Token.load.k(none: Bool, +path: String, +have: String) -> IO(String):
  match none:
    case True{}:
      IO.bind(String, String, Token.fresh(), t => Token.save(path, t))
    case False{}:
      IO.pure(String, have)

def Token.load(+home: String) -> IO(String):
  do IO<String>:
    +have : String <- Files.text(home ++ "/token")
    Token.load.k(String.is_empty(String.trim(have)), home ++ "/token", String.trim(have))

def Cfg.with_token(c: Cfg, +t: String) -> Cfg:
  match c:
    case Cfg{h, w, ho, p, pr, ds, v, Net{tn, hs, _, ms, mt, rt, brx, pkx, tmx}}:
      Cfg{h, w, ho, p, pr, ds, v, Net{tn, hs, t, ms, mt, rt, brx, pkx, tmx}}

# Startup
# -------

def Env.or(r: Result<&1, &1, U32 & String, String>, d: String) -> String:
  match r:
    case Done{+v}:
      Bool.pick(String, String.is_empty(v), d, v)
    case Fail{_}:
      d

def Env.get(name: String, d: String) -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env(name)
    return Env.or(r, d)

def Upgrade.start(+inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    +off : String <- Env.get("BACKPLANE_NO_UPDATE", "")
    Upgrade.start.k(off, inbox)

def Names.copy(xs: List<String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      x <> Names.copy(t)

def Upgrade.done.k(ok: Bool, +err: String, +inbox: Chan(Msg)) -> IO(Unit):
  match ok:
    case True{}:
      do IO<Unit>:
        Upgrade.say(inbox, Upgrade.note([J.KV{"state", J.Str{"restarting"}}]))
        path : String <- H.Sys.exe_path()
        args : List<String> <- IO.args()
        r : Result<&1, &1, U32 & String, Unit> <- H.Sys.exec(path, Names.copy(args))
        Upgrade.exec(r, inbox)
    case False{}:
      Upgrade.say(inbox, Upgrade.note([J.KV{"error", J.Str{err}}]))

def Upgrade.done(+err: String, +inbox: Chan(Msg)) -> IO(Unit):
  Upgrade.done.k(String.is_empty(err), err, inbox)

# install Backplane KiCad beside our data and restart to pick it up
def Install.go(+home: String, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    Upgrade.say(inbox, Upgrade.note([J.KV{"state", J.Str{"installing Backplane KiCad"}}]))
    err : String <- K.KiCad.install(home)
    Upgrade.done(err, inbox)

# install the latest release and restart into it
def Upgrade.go(+home: String, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    Upgrade.say(inbox, Upgrade.note([J.KV{"state", J.Str{"updating"}}]))
    exe : String <- H.Sys.exe_dir()
    err : String <- UP.Update.apply(exe, home)
    Upgrade.done(err, inbox)

def Agent.pid_is(m: Maybe<&2, Agent>, +pid: U32) -> Bool:
  match m:
    case Some{Agent{_, _, p, _}}:
      U32.is_eq(p, pid)
    case None{}:
      False{}

def Cfg.models(c: Cfg) -> String:
  match c:
    case Cfg{_, _, _, _, _, _, _, Net{_, _, _, ms, _, _, brx, pkx, tmx}}:
      ms

def Cfg.pk(c: Cfg) -> Maybe<&2, Chan(PK.PMsg)>:
  match c:
    case Cfg{_, _, _, _, _, _, _, Net{_, _, _, _, _, _, _, pk, tmx}}:
      pk

def Park.put(m: Maybe<&2, Chan(PK.PMsg)>, +msg: PK.PMsg) -> IO(Unit):
  match m:
    case Some{q}:
      do IO<Unit>:
        ok : Bool <- Chan.send(PK.PMsg, q, msg)
        return Unit{}
    case None{}:
      IO.pure(Unit, Unit{})

# a phone push for an ended turn, off the hub loop; the tokens APNs calls
# dead come back as device.drop requests, as if a client had sent them
def Hub.drop_dead(ts: List<&2, String>, +inbox: Chan(Msg)) -> IO(Unit):
  match ts:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case t <> rest:
      IO.bind(Bool, Unit, Chan.send(Msg, inbox, Rpc{0, PU.Push.drop_request(t)}), _ => Hub.drop_dead(rest, inbox))

def Hub.phone(+home: String, st: M.State, +thread: String, +state: String, +inbox: Chan(Msg)) -> IO(Unit):
  IO.bind(List<&2, String>, Unit, PU.Push.turn_ended.dead(home, st, thread, state), ds => Hub.drop_dead(ds, inbox))

# the reply now, or (for a request that waits on the user) parked until
# the ask it opened is answered
def Hub.mcp.send(later: Bool, +park: String, +body: String, +text: String, +reply: Chan(String), +cfg: Cfg) -> IO(Unit):
  match later:
    case True{}:
      Park.put(Cfg.pk(cfg), PK.PPark{park, body, reply})
    case False{}:
      do IO<Unit>:
        ok : Bool <- Chan.send(String, reply, text)
        return Unit{}

def Net.with_br(n: Net, q: Chan(BR.BMsg)) -> Net:
  match n:
    case Net{a, b, c, d, e, f, _, g, i}:
      Net{a, b, c, d, e, f, Some{q}, g, i}

def Net.with_tm(n: Net, q: Chan(TM.TMsg)) -> Net:
  match n:
    case Net{a, b, c, d, e, f, g, h, _}:
      Net{a, b, c, d, e, f, g, h, Some{q}}

def Cfg.tm(c: Cfg) -> Maybe<&2, Chan(TM.TMsg)>:
  match c:
    case Cfg{_, _, _, _, _, _, _, Net{_, _, _, _, _, _, _, _, tm}}:
      tm

# a shell's output, to the hub (which sends it to every client)
def Term.fwd.got(m: Maybe<&1, TM.TOut>, +inbox: Chan(Msg), k: Unit -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{TM.TOut{th, bs}}:
      do IO<Unit>:
        ok : Bool <- Chan.send(Msg, inbox, TermOut{th, bs})
        k(Unit{})
    case None{}:
      IO.pure(Unit, Unit{})

def Term.fwd(fuel: Nat, +out: Chan(TM.TOut), +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      IO.bind(Maybe<&1, TM.TOut>, Unit, Chan.recv(TM.TOut, out), m => Term.fwd.got(m, inbox, u => Term.fwd(f, out, inbox)))

def Term.put(m: Maybe<&2, Chan(TM.TMsg)>, +msg: TM.TMsg) -> IO(Unit):
  match m:
    case Some{q}:
      do IO<Unit>:
        ok : Bool <- Chan.send(TM.TMsg, q, msg)
        return Unit{}
    case None{}:
      IO.pure(Unit, Unit{})

def Term.msg(+op: String, +thread: String, +cwd: String, data: List<&2, U32>, +cols: U32, +rows: U32) -> TM.TMsg:
  Bool.pick(TM.TMsg, String.eq(op, "open"), TM.TOpen{thread, cwd, cols, rows},
    Bool.pick(TM.TMsg, String.eq(op, "resize"), TM.TSize{thread, cols, rows}, TM.TIn{thread, data}))

def Hub.out(h: Hub, o: B.Out) -> IO(Hub):
  match h o:
    case Hub{st, f, ls, +cl, as, inbox, cfg, note} B.Send{+client, text}:
      do IO<Hub>:
        Wire.send(Clients.get(cl, client), WText{text})
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{st, f, ls, +cl, as, inbox, cfg, note} B.Broadcast{+text}:
      do IO<Hub>:
        Wire.all(cl, text)
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{st, f, ls, cl, +as, inbox, cfg, note} B.AgentStart{+thread, +cwd, _, +model, +session, r, i}:
      Hub.start.k(Agents.get(as, thread), Hub{st, f, ls, cl, as, inbox, cfg, note}, thread, cwd, model, session, r, i)
    case Hub{st, f, ls, cl, +as, inbox, cfg, note} B.AgentSend{+thread, line}:
      do IO<Hub>:
        Hub.agent_send(Agents.get(as, thread), line)
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{st, f, ls, cl, +as, inbox, cfg, note} B.AgentStop{+thread}:
      do IO<Hub>:
        Hub.agent_stop(Agents.get(as, thread))
        return Hub{st, f, ls, cl, Agents.drop(as, thread), inbox, cfg, note}
    case _ B.Watch{_, _}:
      IO.pure(Hub, h)
    case Hub{+st, f, ls, cl, as, +inbox, +cfg, note} B.CodexTurn{+thread, +cwd, +model, +session, r, text}:
      do IO<Hub>:
        fs : K.Files <- K.Files.read(cwd)
        IO.spawn(Unit, Codex.run(Codex.args(cfg, thread, model, session, r, text, Hub.prompt(cfg, st, thread, cwd, fs)), cwd, thread, inbox))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{st, f, ls, cl, as, +inbox, +cfg, note} B.KiCadInstall{}:
      do IO<Hub>:
        IO.spawn(Unit, Install.go(Cfg.home(cfg), inbox))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{+st, f, ls, cl, as, +inbox, +cfg, note} B.GrokTurn{+thread, +cwd, +model, +session, r, +text}:
      do IO<Hub>:
        fs : K.Files <- K.Files.read(cwd)
        IO.spawn(Unit, Grok.run(Grok.args(r, model), AC.AcpTurn{cwd, Hub.mcp_url(cfg, thread), Hub.prompt(cfg, st, thread, cwd, fs), text, session}, cwd, thread, inbox))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{+st, f, ls, cl, as, +inbox, +cfg, note} B.TurnEnded{+thread, +state}:
      do IO<Hub>:
        IO.spawn(Unit, Hub.phone(Cfg.home(cfg), st, thread, state, inbox))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{st, f, ls, cl, as, +inbox, cfg, note} B.Fs{+client, +id, +op, +path}:
      do IO<Hub>:
        IO.spawn(Unit, FsJob.run(op, inbox, client, id, path))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{st, f, ls, cl, as, inbox, +cfg, note} B.TermOp{+op, +thread, +cwd, data, +cols, +rows}:
      do IO<Hub>:
        Term.put(Cfg.tm(cfg), Term.msg(op, thread, cwd, data, cols, rows))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{st, f, ls, cl, as, +inbox, +cfg, note} B.Git{+client, +id, +job, +thread, +cwd, +a, +b}:
      do IO<Hub>:
        IO.spawn(Unit, GitJob.run(job, inbox, client, id, thread, cwd, a, b, Cfg.home(cfg)))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{st, f, ls, cl, as, inbox, +cfg, note} B.AskAnswered{+ask, +answer}:
      do IO<Hub>:
        Park.put(Cfg.pk(cfg), PK.PAnswer{ask, answer})
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{st, f, ls, cl, as, +inbox, +cfg, note} B.Upgrade{}:
      do IO<Hub>:
        IO.spawn(Unit, Upgrade.go(Cfg.home(cfg), inbox))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}

def Hub.outs(os: List<&2, B.Out>, h: Hub) -> IO(Hub):
  match os:
    case Nil{}:
      IO.pure(Hub, h)
    case o <> t:
      IO.bind(Hub, Hub, Hub.out(h, o), h2 => Hub.outs(t, h2))

def Hub.step(h: Hub, s: B.Step) -> IO(Hub):
  match s:
    case B.Step{cs, os}:
      do IO<Hub>:
        r : Hub & List<&2, String> <- Hub.commit(cs, h, Nil{})
        h2 : Hub <- Hub.announce(r)
        Hub.outs(os, h2)

def Hub.rpc.k(p: M.State & Hub, +client: U32, +text: String, +now: Nat) -> IO(Hub):
  (st, h) = p
  Hub.step(h, B.Hub.request_text(st, now, client, text))

def Hub.rpc(h: Hub, +client: U32, +text: String, +now: Nat) -> IO(Hub):
  Hub.rpc.k(Hub.state(h), client, text, now)

def Hub.line.k(p: M.State & Hub, +thread: String, +line: String, +now: Nat) -> IO(Hub):
  (st, h) = p
  Hub.step(h, B.Hub.agent_line(st, now, thread, line))

def Hub.line(h: Hub, +thread: String, +line: String, +now: Nat) -> IO(Hub):
  Hub.line.k(Hub.state(h), thread, line, now)

def Hub.gone.k(current: Bool, h: Hub, +thread: String, +code: U32, +now: Nat) -> IO(Hub):
  match current h:
    case True{} Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.step(Hub{st, f, ls, cl, Agents.drop(as, thread), inbox, cfg, note}, B.Hub.agent_gone(st, now, thread, code))
    case False{} _:
      IO.pure(Hub, h)

# a process exited; one already replaced (a restart for a new model or
# mode) is old news
def Hub.gone(h: Hub, +thread: String, +code: U32, +pid: U32, +now: Nat) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, +as, inbox, cfg, note}:
      Hub.gone.k(Agent.pid_is(Agents.get(as, thread), pid), Hub{st, f, ls, cl, as, inbox, cfg, note}, thread, code, now)

def Hub.tick(h: Hub, +now: Nat) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.step(Hub{st, f, ls, cl, as, inbox, cfg, note}, B.Hub.tick(st, now))

def Hub.mcp.k(o: MC.McpOut, h: Hub, +reply: Chan(String), +body: String) -> IO(Hub):
  match o h:
    case MC.McpOut{+text, st, +park} Hub{hs, f, ls, cl, as, inbox, +cfg, note}:
      do IO<Hub>:
        Hub.mcp.send(Bool.not(String.is_empty(park)), park, body, text, reply, cfg)
        Hub.step(Hub{hs, f, ls, cl, as, inbox, cfg, note}, st)

def Term.nums(bs: List<&2, U32>) -> List<&2, String>:
  match bs:
    case Nil{}:
      Nil{}
    case b <> t:
      U32.show(b) <> Term.nums(t)

def Term.json(+thread: String, bs: List<&2, U32>) -> String:
  "{\"t\":\"term\",\"thread\":" ++ J.Json.show(J.Str{thread}) ++ ",\"b\":[" ++ String.join(Term.nums(bs), ",") ++ "]}"

def Net.with_pk(n: Net, q: Chan(PK.PMsg)) -> Net:
  match n:
    case Net{a, b, c, d, e, f, g, _, i}:
      Net{a, b, c, d, e, f, g, Some{q}, i}

def Browser.exe() -> IO(String):
  do IO<String>:
    +d : String <- H.Sys.exe_dir()
    ok : Bool <- K.Io.is_file(d ++ "/backplane-browser")
    return Bool.pick(String, ok, d ++ "/backplane-browser", "backplane-browser")

def Cfg.br(c: Cfg) -> Maybe<&2, Chan(BR.BMsg)>:
  match c:
    case Cfg{_, _, _, _, _, _, _, Net{_, _, _, _, _, _, br, pkx, tmx}}:
      br

def Preview.shot(+o: J.Json) -> List<&2, J.Json>:
  Bool.pick(List<&2, J.Json>, String.is_empty(J.Json.get_str(o, "data", "")), Nil{},
    [J.Json.obj([J.KV{"type", J.Str{"image"}}, J.KV{"data", J.Str{J.Json.get_str(o, "data", "")}}, J.KV{"mimeType", J.Str{J.Json.get_str(o, "mimeType", "image/png")}}])])

def Preview.drop.fs(fs: J.Json) -> J.Json:
  match fs:
    case J.Field{"screenshot", _, t}:
      Preview.drop.fs(t)
    case J.Field{k, v, t}:
      J.Field{k, v, Preview.drop.fs(t)}
    case _:
      fs

def Preview.drop_shot(o: J.Json) -> J.Json:
  match o:
    case J.Obj{fs}:
      J.Obj{Preview.drop.fs(fs)}
    case _:
      o

def Preview.blocks(+r: J.Json) -> List<&2, J.Json>:
  J.Json.obj([J.KV{"type", J.Str{"text"}}, J.KV{"text", J.Str{J.Json.show(Preview.drop_shot(r))}}])
    <> Preview.shot(J.Json.get_obj(r, "screenshot"))

def Preview.content.k(ok: Bool, r: J.Json, +err: String) -> J.Json:
  match ok:
    case True{}:
      J.Json.obj([J.KV{"content", J.Json.arr(Preview.blocks(r))}, J.KV{"isError", J.Flag{False{}}}])
    case False{}:
      J.Json.obj([J.KV{"content", J.Json.arr([J.Json.obj([J.KV{"type", J.Str{"text"}}, J.KV{"text", J.Str{err}}])])}, J.KV{"isError", J.Flag{True{}}}])

# a browser tool's reply as an MCP result: the helper's result as text,
# a screenshot as an image block, an error flagged
def Preview.content(+o: J.Json) -> J.Json:
  Preview.content.k(J.Json.get_bool(o, "ok", False{}), J.Json.get_obj(o, "result"), J.Json.get_str(o, "error", "browser error"))

def Preview.answer(+id: String, +line: String) -> String:
  "{\"jsonrpc\":\"2.0\",\"id\":" ++ id ++ ",\"result\":" ++ J.Json.show(Preview.content(Maybe.default(&2, J.Json, J.Json.parse(line), J.Null{}))) ++ "}"

def Preview.run.k(m: Maybe<&2, Chan(BR.BMsg)>, +id: String, +op: String, args: J.Json, +reply: Chan(String)) -> IO(Unit):
  match m:
    case Some{q}:
      do IO<Unit>:
        line : String <- BR.Browser.ask(q, op, args)
        ok : Bool <- Chan.send(String, reply, Preview.answer(id, line))
        return Unit{}
    case None{}:
      do IO<Unit>:
        ok : Bool <- Chan.send(String, reply, Preview.answer(id, BR.Browser.fail("no browser in this Backplane")))
        return Unit{}

# a preview_* tool call, answered by the browser off the hub's thread
def Preview.run(+cfg: Cfg, +o: J.Json, +reply: Chan(String)) -> IO(Unit):
  Preview.run.k(Cfg.br(cfg), J.Json.as_raw(J.Json.get(o, "id"), "null"), String.drop(J.Json.get_str(J.Json.get_obj(o, "params"), "name", ""), 8n),
    J.Json.get_obj(J.Json.get_obj(o, "params"), "arguments"), reply)

def Preview.is(+o: J.Json) -> Bool:
  Bool.and(String.eq(J.Json.get_str(o, "method", ""), "tools/call"), String.starts_with(J.Json.get_str(J.Json.get_obj(o, "params"), "name", ""), "preview_"))

# opening or navigating brings the Browser tab forward in every window
def Preview.shows(+o: J.Json) -> Bool:
  Bool.or(String.eq(J.Json.get_str(J.Json.get_obj(o, "params"), "name", ""), "preview_open"), String.eq(J.Json.get_str(J.Json.get_obj(o, "params"), "name", ""), "preview_navigate"))

def Hub.preview(h: Hub, +o: J.Json, +reply: Chan(String)) -> IO(Hub):
  match h:
    case Hub{st, f, ls, +cl, as, inbox, +cfg, note}:
      do IO<Hub>:
        IO.spawn(Unit, Preview.run(cfg, o, reply))
        Bool.pick(IO(Unit), Preview.shows(o), Wire.all(cl, "{\"t\":\"view\",\"kind\":\"browser\",\"path\":\"\"}"), IO.pure(Unit, Unit{}))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}

def Hub.mcp.hub(h: Hub, +thread: String, +body: String, +reply: Chan(String), +now: Nat) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, inbox, +cfg, note}:
      Hub.mcp.k(MC.Mcp.text(st, now, thread, Maybe.default(&2, J.Json, J.Json.parse(Cfg.models(cfg)), J.Null{}), Cfg.version(cfg), body),
        Hub{st, f, ls, cl, as, inbox, cfg, note}, reply, body)

def Hub.mcp.route(pv: Bool, h: Hub, +thread: String, +o: J.Json, body: String, +reply: Chan(String), +now: Nat) -> IO(Hub):
  match pv:
    case True{}:
      Hub.preview(h, o, reply)
    case False{}:
      Hub.mcp.hub(h, thread, body, reply, now)

def Hub.mcp(h: Hub, +thread: String, +body: String, +reply: Chan(String), +now: Nat) -> IO(Hub):
  Hub.mcp.route(Preview.is(Maybe.default(&2, J.Json, J.Json.parse(body), J.Null{})), h, thread, Maybe.default(&2, J.Json, J.Json.parse(body), J.Null{}), body, reply, now)

# a shell's output goes to every client (each keeps its own screen)
def Hub.term_out(h: Hub, +thread: String, data: List<&2, U32>) -> IO(Hub):
  match h:
    case Hub{st, f, ls, +cl, as, inbox, cfg, note}:
      do IO<Hub>:
        Wire.all(cl, Term.json(thread, data))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}

def Hub.handle(h: Hub, m: Msg, +now: Nat) -> IO(Hub):
  match m:
    case Mcp{thread, body, reply}:
      Hub.mcp(h, thread, body, reply, now)
    case Announce{text}:
      Hub.note(h, text)
    case Join{client, out, since, origin}:
      Hub.join(h, client, out, since, origin)
    case Leave{client}:
      Hub.leave(h, client)
    case Rpc{client, text}:
      Hub.rpc(h, client, text, now)
    case AgentLine{thread, line}:
      Hub.line(h, thread, line, now)
    case AgentGone{thread, code, pid}:
      Hub.gone(h, thread, code, pid, now)
    case Tick{}:
      Hub.tick(h, now)
    case Push{client, text}:
      Hub.push(h, client, text)
    case TermOut{thread, data}:
      Hub.term_out(h, thread, data)

def Hub.got(m: Maybe<&1, Msg>, h: Hub, k: Hub -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{msg}:
      do IO<Unit>:
        now : Nat <- Now.nat()
        h2 : Hub <- Hub.handle(h, msg, now)
        k(h2)
    case None{}:
      Hub.close(h)

def Hub.loop(fuel: Nat, h: Hub) -> IO(Unit):
  match fuel:
    case 0n:
      Hub.close(h)
    case 1n+f:
      Hub.inbox(h, inbox => h2 =>
        IO.bind(Maybe<&1, Msg>, Unit, Chan.recv(Msg, inbox), m => Hub.got(m, h2, h3 => Hub.loop(f, h3))))

def Names.list(r: Result<&1, &1, U32 & String, List<String>>) -> List<&2, String>:
  match r:
    case Done{xs}:
      Names.copy(xs)
    case Fail{_}:
      Nil{}

def Names.of(path: String) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    r : Result<&1, &1, U32 & String, List<String>> <- H.FS.list(path)
    return List.sort(~String, ~String.is_le, Names.list(r))

def Skills.keep(empty: Bool, s: Q.Skill, rest: List<&2, Q.Skill>) -> List<&2, Q.Skill>:
  match empty:
    case True{}:
      rest
    case False{}:
      s <> rest

# the SKILL.md of every skill dir under root, parsed
def Skills.read(ds: List<&2, String>, +root: String) -> IO(List<&2, Q.Skill>):
  match ds:
    case Nil{}:
      IO.pure(List<&2, Q.Skill>, Nil{})
    case +d <> t:
      do IO<List<&2, Q.Skill>>:
        +path : String = root ++ "/" ++ d ++ "/SKILL.md"
        +text : String <- Files.text(path)
        rest : List<&2, Q.Skill> <- Skills.read(t, root)
        return Skills.keep(String.is_empty(text), Q.Skill.parse(text, d, path), rest)

def Skills.kistack.dir(+dir: String) -> IO(String & List<&2, Q.Skill>):
  do IO<String & List<&2, Q.Skill>>:
    ds : List<&2, String> <- Names.of(dir ++ "/skills")
    ss : List<&2, Q.Skill> <- Skills.read(ds, dir ++ "/skills")
    return (dir, ss)

# KiStack lives at <cache>/backplane/kistack/<revision>/skills; the newest
# revision directory wins
def Skills.kistack.k(m: Maybe<&2, String>, +base: String) -> IO(String & List<&2, Q.Skill>):
  match m:
    case Some{+rev}:
      Skills.kistack.dir(base ++ "/" ++ rev)
    case None{}:
      IO.pure(String & List<&2, Q.Skill>, ("", Nil{}))

def Skills.kistack(+home: String) -> IO(String & List<&2, Q.Skill>):
  do IO<String & List<&2, Q.Skill>>:
    +base : String = home ++ "/.cache/backplane/kistack"
    revs : List<&2, String> <- Names.of(base)
    Skills.kistack.k(List.last(&2, String, revs), base)

def Main.args(xs: List<String>, c: Cfg) -> Cfg:
  match xs c:
    case "--port" <> p <> t Cfg{h, w, ho, _, pr, ds, v, nt}:
      Main.args(t, Cfg{h, w, ho, Maybe.default(&2, U32, U32.read(p), 3787), pr, ds, v, nt})
    case "--host" <> x <> t Cfg{h, w, _, po, pr, ds, v, nt}:
      Main.args(t, Cfg{h, w, x, po, pr, ds, v, nt})
    case "--web" <> x <> t Cfg{h, _, ho, po, pr, ds, v, nt}:
      Main.args(t, Cfg{h, x, ho, po, pr, ds, v, nt})
    case "--home" <> x <> t Cfg{_, w, ho, po, pr, ds, v, nt}:
      Main.args(t, Cfg{x, w, ho, po, pr, ds, v, nt})
    case "--tailscale" <> t Cfg{h, w, ho, po, pr, ds, v, Net{_, https, tok, ms, mt, rt, brx, pkx, tmx}}:
      Main.args(t, Cfg{h, w, ho, po, pr, ds, v, Net{True{}, https, tok, ms, mt, rt, brx, pkx, tmx}})
    case "--tailscale-https" <> t Cfg{h, w, ho, po, pr, ds, v, Net{_, _, tok, ms, mt, rt, brx, pkx, tmx}}:
      Main.args(t, Cfg{h, w, ho, po, pr, ds, v, Net{True{}, True{}, tok, ms, mt, rt, brx, pkx, tmx}})
    case _ <> t _:
      Main.args(t, c)
    case Nil{} _:
      c

def Main.version() -> String:
  VR.Version.current()

def Main.serve(l: Listener, h: Hub, +web: String, +inbox: Chan(Msg), +cfg: Cfg, front: Chan(Msg) -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    IO.spawn(Unit, Accept.loop(Fuel.forever(), l, 1, web, inbox, True{}, Net.token(Cfg.net(cfg))))
    Tailnet.start(Cfg.net(cfg), Cfg.port(cfg), web, inbox)
    IO.spawn(Unit, Ticker.loop(Fuel.forever(), inbox))
    IO.spawn(Unit, Hub.loop(Fuel.forever(), h))
    Upgrade.start(inbox)
    front(inbox)

# without the web server (its port was taken): hub and ticker only
def Main.headless(h: Hub, +inbox: Chan(Msg), front: Chan(Msg) -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    IO.spawn(Unit, Ticker.loop(Fuel.forever(), inbox))
    IO.spawn(Unit, Hub.loop(Fuel.forever(), h))
    Upgrade.start(inbox)
    front(inbox)

def Main.failed(e: U32 & String, h: Hub, addr: String) -> IO(Unit):
  (_, msg) = e
  do IO<Unit>:
    Hub.close(h)
    IO.die(Unit, 1, "backplane: cannot listen on " ++ addr ++ ": " ++ msg)

def Main.listened(r: Result<&1, &1, U32 & String, Listener>, h: Hub, +web: String, +inbox: Chan(Msg), +addr: String, need: Bool, +cfg: Cfg, front: Chan(Msg) -> IO(Unit)) -> IO(Unit):
  match r need:
    case Done{l} _:
      do IO<Unit>:
        IO.print("Backplane listening on http://" ++ addr)
        Main.serve(l, h, web, inbox, cfg, front)
    case Fail{e} True{}:
      Main.failed(e, h, addr)
    case Fail{_} False{}:
      do IO<Unit>:
        Log.info("web server off: " ++ addr ++ " is taken")
        Main.headless(h, inbox, front)

def Main.nolog(e: U32 & String) -> IO(Unit):
  (_, msg) = e
  IO.die(Unit, 1, "backplane: cannot open the event log: " ++ msg)

def Main.opened(r: Result<&1, &1, U32 & String, File>, st: M.State, ls: List<&2, String>, cfg: Cfg, need: Bool, front: Chan(Msg) -> IO(Unit)) -> IO(Unit):
  match r cfg:
    case Done{f} Cfg{+home, +web, +host, +port, +pr, +ds, +v, nt0}:
      do IO<Unit>:
        +inbox : Chan(Msg) <- Chan.new(Msg, 4096)
        +bq : Chan(BR.BMsg) <- Chan.new(BR.BMsg, 256)
        bexe : String <- Browser.exe()
        IO.spawn(Unit, BR.Browser.loop(Fuel.forever(), bq, BR.Br.new(bexe, home ++ "/browser.rgb")))
        +pq : Chan(PK.PMsg) <- Chan.new(PK.PMsg, 256)
        IO.spawn(Unit, PK.Park.loop(Fuel.forever(), pq, Nil{}))
        +tq : Chan(TM.TMsg) <- Chan.new(TM.TMsg, 1024)
        +to : Chan(TM.TOut) <- Chan.new(TM.TOut, 4096)
        shell : String <- Env.get("SHELL", "/bin/bash")
        IO.spawn(Unit, TM.Term.loop(Fuel.forever(), tq, Nil{}, shell, to))
        IO.spawn(Unit, Term.fwd(Fuel.forever(), to, inbox))
        +nt : Net = Net.with_tm(Net.with_pk(Net.with_br(nt0, bq), pq), tq)
        l : Result<&1, &1, U32 & String, Listener> <- H.Net.listen(host, port)
        Main.listened(l, Hub{st, f, ls, Nil{}, Nil{}, inbox, Cfg{home, web, host, port, pr, ds, v, nt}, ""}, web, inbox, host ++ ":" ++ U32.show(port), need, Cfg{home, web, host, port, pr, ds, v, nt}, front)
    case Fail{e} _:
      Main.nolog(e)

# replay the log, start the hub (and the web server), then run front
# with the hub's inbox; `need` makes a taken web port fatal
def Main.boot(cfg: Cfg, need: Bool, front: Chan(Msg) -> IO(Unit)) -> IO(Unit):
  match cfg:
    case Cfg{+home, w, h, p, pr, ds, v, nt}:
      do IO<Unit>:
        mk : Result<&1, &1, U32 & String, Unit> <- H.FS.mkdirs(home)
        bs : List<&2, U32> <- Files.read(Store.path(home))
        +full : List<&2, String> = Store.keep(Store.lines(bs), Nil{})
        +st : M.State = M.State.replay(Store.decode(List.reverse(&2, String, full)), M.State.empty())
        +ls : List<&2, String> = Store.wire(full)
        Log.info("replayed " ++ Nat.show(List.length(&2, String, ls)) ++ " changes from " ++ Store.path(home))
        f : Result<&1, &1, U32 & String, File> <- File.open(Store.path(home), "a")
        tok : String <- Token.load(home)
        Main.opened(f, st, ls, Cfg.with_token(Cfg{home, w, h, p, pr, ds, v, nt}, tok), need, front)

# what the machine offers, found once at start
type Boot is Data:
  Boot{kdir: String, skills: List<&2, Q.Skill>, rt: K.Rt, models: String, mtext: String}

def Models.strs.go(xs: List<&2, String>) -> List<&2, J.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      J.Str{x} <> Models.strs.go(t)

def Models.strs(xs: List<&2, String>) -> J.Json:
  J.Json.arr(Models.strs.go(xs))

def Models.listed(o: J.Json) -> Bool:
  String.eq(J.Json.get_str(o, "visibility", "list"), "list")

def Models.slugs.k(keep: Bool, +slug: String, rest: List<&2, String>) -> List<&2, String>:
  match keep:
    case True{}:
      slug <> rest
    case False{}:
      rest

def Models.slugs(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case +o <> t:
      Models.slugs.k(Bool.and(Models.listed(o), Bool.not(String.is_empty(J.Json.get_str(o, "slug", "")))), J.Json.get_str(o, "slug", ""), Models.slugs(t))

# Codex's cached model list ({"models": [{"slug", "visibility"}]})
def Models.codex(+text: String) -> List<&2, String>:
  Models.slugs(J.Json.elems(J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{}), "models")))

def Models.claude() -> List<&2, String>:
  ["fable", "opus", "sonnet", "haiku"]

def Models.on(has: Bool, +xs: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, has, xs, Nil{})

def Models.line(+name: String, +xs: List<&2, String>) -> String:
  Bool.pick(String, List.is_empty(&2, String, xs), "", name ++ " (" ++ String.join(xs, ", ") ++ ")")

def Models.join(+a: String, +b: String) -> String:
  Bool.pick(String, String.is_empty(a), b, Bool.pick(String, String.is_empty(b), a, a ++ "; " ++ b))

def Models.text(+cl: List<&2, String>, +cx: List<&2, String>) -> String:
  Models.join(Models.line("claude", cl), Models.line("codex", cx))

def Models.text3(+cl: List<&2, String>, +cx: List<&2, String>, +gk: List<&2, String>) -> String:
  Models.join(Models.text(cl, cx), Models.line("grok", gk))

def Models.boot(ks: String & List<&2, Q.Skill>, +rt: K.Rt, +cl: List<&2, String>, +cx: List<&2, String>, +gk: List<&2, String>, about: J.Json) -> Boot:
  (kdir, skills) = ks
  Boot{kdir, skills, rt, J.Json.show(J.Json.obj([J.KV{"claude", Models.strs(cl)}, J.KV{"codex", Models.strs(cx)}, J.KV{"grok", Models.strs(gk)}, J.KV{"about", about}])), Models.text3(cl, cx, gk)}

def Models.grok.k(bullet: Bool, +l: String, rest: List<&2, String>) -> List<&2, String>:
  match bullet:
    case True{}:
      Maybe.default(&2, String, List.head(&2, String, String.split(String.drop(String.trim(l), 2n), ' ')), "") <> rest
    case False{}:
      rest

def Models.grok.line(+l: String, rest: List<&2, String>) -> List<&2, String>:
  Models.grok.k(Bool.or(String.starts_with(String.trim(l), "* "), String.starts_with(String.trim(l), "- ")), l, rest)

def Models.grok.go(ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> t:
      Models.grok.line(l, Models.grok.go(t))

# `grok models`: "  * grok-4.6 (default)" / "  - grok-4.5" lines
def Models.grok(r: P.Ran) -> List<&2, String>:
  match r:
    case P.Ran{0, out}:
      Models.grok.go(String.lines(out))
    case _:
      Nil{}

def Main.has(r: P.Ran) -> Bool:
  match r:
    case P.Ran{0, _}:
      True{}
    case _:
      False{}

# KiStack at its pinned revision (fetched when missing), the KiCad CLI,
# and which providers and models are installed
# What each provider is: its CLI's version, and a label per model. Claude's
# aliases name the newest model of a family; the CLI does not report which,
# so this table says (update it when the families move).
def About.claude() -> List<&2, J.KV>:
  [J.KV{"default", J.Str{"Claude Code's own default"}}, J.KV{"fable", J.Str{"Fable 5.1 · claude-fable-5-1"}},
   J.KV{"opus", J.Str{"Opus 5.5 · claude-opus-5-5"}}, J.KV{"sonnet", J.Str{"Sonnet 5 · claude-sonnet-5"}},
   J.KV{"haiku", J.Str{"Haiku 4.5 · claude-haiku-4-5"}}]

def About.codex.go(xs: List<&2, J.Json>) -> List<&2, J.KV>:
  match xs:
    case Nil{}:
      Nil{}
    case +o <> t:
      J.KV{J.Json.get_str(o, "slug", ""), J.Str{J.Json.get_str(o, "display_name", "") ++ " · " ++ J.Json.get_str(o, "description", "")}} <> About.codex.go(t)

def About.codex(+text: String) -> List<&2, J.KV>:
  J.KV{"default", J.Str{"Codex's configured default"}} <> About.codex.go(J.Json.elems(J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{}), "models")))

def About.grok.k(dflt: Bool, +slug: String, rest: List<&2, J.KV>, bullet: Bool) -> List<&2, J.KV>:
  match bullet:
    case True{}:
      J.KV{slug, J.Str{Bool.pick(String, dflt, "Grok's default model", "Grok")}} <> rest
    case False{}:
      rest

def About.grok.go(ls: List<&2, String>) -> List<&2, J.KV>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      About.grok.k(String.contains(l, "(default)"), Maybe.default(&2, String, List.head(&2, String, String.split(String.drop(String.trim(l), 2n), ' ')), ""), About.grok.go(t), Bool.or(String.starts_with(String.trim(l), "* "), String.starts_with(String.trim(l), "- ")))

def About.grok(r: P.Ran) -> List<&2, J.KV>:
  match r:
    case P.Ran{0, out}:
      J.KV{"default", J.Str{"Grok's own default"}} <> About.grok.go(String.lines(out))
    case _:
      Nil{}

def About.cli(r: P.Ran) -> String:
  match r:
    case P.Ran{0, out}:
      String.trim(Maybe.default(&2, String, List.head(&2, String, String.lines(out)), ""))
    case _:
      ""

def About.one(+cli: String, labels: List<&2, J.KV>) -> J.Json:
  J.Json.obj([J.KV{"cli", J.Str{cli}}, J.KV{"labels", J.Json.obj(labels)}])

def Main.prepare(+user: String, +exe: String) -> IO(Boot):
  do IO<Boot>:
    K.KiStack.ensure(user)
    ks : String & List<&2, Q.Skill> <- Skills.kistack.dir(user ++ "/.cache/backplane/kistack/" ++ K.KiStack.revision())
    explicit : String <- Env.get("BACKPLANE_KICAD_CLI", "")
    rt : K.Rt <- K.Rt.resolve(explicit, exe, user ++ "/.backplane-bend")
    cl : P.Ran <- P.Proc.run("sh", ["-c", "command -v claude"], "/")
    cx : P.Ran <- P.Proc.run("sh", ["-c", "command -v codex"], "/")
    +cache : String <- K.Io.text(user ++ "/.codex/models_cache.json")
    +gk : P.Ran <- P.Proc.run("sh", ["-c", "command -v grok >/dev/null && timeout 15 grok models"], "/")
    vc : P.Ran <- P.Proc.run("sh", ["-c", "timeout 10 claude --version"], "/")
    vx : P.Ran <- P.Proc.run("sh", ["-c", "timeout 10 codex --version"], "/")
    vg : P.Ran <- P.Proc.run("sh", ["-c", "timeout 10 grok --version"], "/")
    return Models.boot(ks, rt, Models.on(Main.has(cl), Models.claude()), Models.on(Main.has(cx), Models.codex(cache)), Models.grok(gk),
      J.Json.obj([J.KV{"claude", About.one(About.cli(vc), About.claude())}, J.KV{"codex", About.one(About.cli(vx), About.codex(cache))}, J.KV{"grok", About.one(About.cli(vg), About.grok(gk))}]))

def Main.config(+user: String, +exe: String, args: List<String>, b: Boot) -> Cfg:
  Boot{kdir, skills, rt, ms, mt} = b
  Main.args(args, Cfg{user ++ "/.backplane-bend", exe ++ "/web", "127.0.0.1", 3787,
    Q.Prompt.runtime("Backplane", skills), [kdir], Main.version(), Net{False{}, False{}, "", ms, mt, rt, None{}, None{}, None{}}})

def Sys.exe_dir.io() -> IO(String):
  H.Sys.exe_dir()
