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
import ./update.bend as UP
import ../core/version.bend as VR

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
  Join{client: U32, out: Chan(Wire)}
  Leave{client: U32}
  Rpc{client: U32, text: String}
  AgentLine{thread: String, line: String}
  AgentGone{thread: String, code: U32}
  Tick{}
  Push{client: U32, text: String}

# remote access: also listen on the tailnet, serve HTTPS through
# `tailscale serve`, and the token remote clients must present
type Net is Data:
  Net{tailnet: Bool, https: Bool, token: String}

type Cfg is Data:
  Cfg{home: String, web: String, host: String, port: U32, prompt: String, dirs: List<&2, String>, version: String, net: Net}

type Client is Data:
  Client{id: U32, out: Chan(Wire)}

type Agent is Data:
  Agent{thread: String, input: Chan(String), pid: U32}

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
    case Agent{t, _, _} <> _:
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
    case Agent{+t, i, p} <> rest:
      Agents.drop.k(String.eq(t, th), Agent{t, i, p}, Agents.drop(rest, th))

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
    ok : Bool <- Chan.send(Msg, inbox, AgentGone{thread, code})
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

def Conn.write(m: Maybe<&1, Wire>, s: Socket, k: Socket -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{WText{t}}:
      IO.bind(Socket, Unit, Conn.send(s, W.Ws.text(t)), k)
    case Some{WPong{p}}:
      IO.bind(Socket, Unit, Conn.send(s, W.Ws.encode(10, p)), k)
    case Some{WClose{}}:
      Conn.finish(s, W.Ws.encode(8, Nil{}))
    case None{}:
      Socket.close(s)

# frames from the hub, until it closes our channel
def Conn.writer(fuel: Nat, s: Socket, +out: Chan(Wire)) -> IO(Unit):
  match fuel:
    case 0n:
      Socket.close(s)
    case 1n+f:
      IO.bind(Maybe<&1, Wire>, Unit, Chan.recv(Wire, out), m => Conn.write(m, s, s2 => Conn.writer(f, s2, out)))

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

# a frame from the browser: text is a request; close ends; ping pongs
def Conn.frame(fr: W.Frame, +id: U32, +inbox: Chan(Msg), +out: Chan(Wire)) -> IO(Bool):
  match fr:
    case W.Frame{_, +op, p}:
      Conn.frame.k(U32.is_eq(op, 1), U32.is_eq(op, 8), U32.is_eq(op, 9), p, id, inbox, out)

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

def Conn.ws.dup(r: Socket & Result<&1, &1, U32 & String, Socket>, rest: List<&2, U32>, +id: U32, +inbox: Chan(Msg)) -> IO(Unit):
  (rd, res) = r
  match res:
    case Done{wr}:
      do IO<Unit>:
        +out : Chan(Wire) <- Chan.new(Wire, 1024)
        IO.spawn(Unit, Conn.writer(Fuel.forever(), wr, out))
        ok : Bool <- Chan.send(Msg, inbox, Join{id, out})
        Conn.reader(Fuel.forever(), rd, rest, id, inbox, out)
    case Fail{_}:
      Socket.close(rd)

def Conn.ws(s: Socket, key: String, rest: List<&2, U32>, +id: U32, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    s2 : Socket <- Conn.send(s, W.Ws.accept(key))
    r : Socket & Result<&1, &1, U32 & String, Socket> <- H.Sock.dup(s2)
    Conn.ws.dup(r, rest, id, inbox)

def Conn.safe(+p: String) -> Bool:
  Bool.and(Bool.not(String.contains(p, "..")), String.starts_with(p, "/"))

def Conn.file(+p: String) -> String:
  Bool.pick(String, String.eq(p, "/"), "/index.html", p)

def Conn.served(s: Socket, +path: String, bs: List<&2, U32>) -> IO(Unit):
  match bs:
    case Nil{}:
      Conn.finish(s, W.Http.text("404 Not Found", "not found"))
    case b <> t:
      Conn.finish(s, W.Http.response("200 OK", W.Http.ctype(path), b <> t, ""))

def Conn.static.k(ok: Bool, s: Socket, +web: String, +path: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.bind(List<&2, U32>, Unit, Files.read(web ++ path), bs => Conn.served(s, path, bs))
    case False{}:
      Conn.finish(s, W.Http.text("400 Bad Request", "bad path"))

def Conn.static(s: Socket, +web: String, +path: String) -> IO(Unit):
  Conn.static.k(Conn.safe(path), s, web, Conn.file(path))

# a websocket from plain loopback is trusted; anything else (the tailnet
# listener, or `tailscale serve` proxying with its identity headers) must
# carry ?token=<the pairing token>
def Conn.allowed(+trusted: Bool, +hs: List<&2, W.Header>, +path: String, +token: String) -> Bool:
  Bool.or(Bool.and(trusted, String.is_empty(W.Http.header_of(hs, "tailscale-user-login"))),
    Bool.and(Bool.not(String.is_empty(token)), String.contains(path, "token=" ++ token)))

def Conn.gate(ok: Bool, s: Socket, +key: String, rest: List<&2, U32>, +id: U32, +inbox: Chan(Msg)) -> IO(Unit):
  match ok:
    case True{}:
      Conn.ws(s, key, rest, id, inbox)
    case False{}:
      Conn.finish(s, W.Http.text("401 Unauthorized", "this Backplane needs its pairing token"))

def Conn.route.k(ws: Bool, s: Socket, req: W.Request, rest: List<&2, U32>, +web: String, +id: U32, +inbox: Chan(Msg), +trusted: Bool, +token: String) -> IO(Unit):
  match ws req:
    case True{} W.Request{_, +p, +hs}:
      Conn.gate(Conn.allowed(trusted, hs, p, token), s, W.Http.header_of(hs, "sec-websocket-key"), rest, id, inbox)
    case False{} W.Request{_, p, _}:
      Conn.static(s, web, W.Http.route(p))

def Conn.is_ws(req: W.Request) -> Bool:
  match req:
    case W.Request{_, p, +hs}:
      Bool.and(String.eq(W.Http.route(p), "/ws"), String.eq(String.to_lower(W.Http.header_of(hs, "upgrade")), "websocket"))

def Conn.route(s: Socket, +req: W.Request, rest: List<&2, U32>, +web: String, +id: U32, +inbox: Chan(Msg), +trusted: Bool, +token: String) -> IO(Unit):
  Conn.route.k(Conn.is_ws(req), s, req, rest, web, id, inbox, trusted, token)

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

def Ticker.loop(fuel: Nat, +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      do IO<Unit>:
        IO.sleep(60000)
        ok : Bool <- Chan.send(Msg, inbox, Tick{})
        Ticker.loop(f, inbox)

# The hub
# -------

type Hub is Type:
  Hub{state: M.State, log: File, lines: List<&2, String>, clients: List<&2, Client>, agents: List<&2, Agent>, inbox: Chan(Msg), cfg: Cfg, note: String}

def Hub.changes_msg(ls: List<&2, String>) -> String:
  "{\"t\":\"changes\",\"items\":[" ++ String.join(ls, ",") ++ "]}"

def Hub.log_msg(+ls: List<&2, String>, version: String) -> String:
  "{\"t\":\"log\",\"version\":" ++ J.Json.show(J.Str{version}) ++ ",\"items\":[" ++ String.join(List.reverse(&2, String, ls), ",") ++ "]}"

def Hub.commit.wrote(r: File & Result<&1, &1, U32 & String, Unit>, st: M.State, +line: String, ls: List<&2, String>, cl: List<&2, Client>,
    as: List<&2, Agent>, +inbox: Chan(Msg), cfg: Cfg, note: String, fresh: List<&2, String>, k: Hub -> List<&2, String> -> IO(Hub & List<&2, String>)) -> IO(Hub & List<&2, String>):
  (f, _) = r
  k(Hub{st, f, line <> ls, cl, as, inbox, cfg, note}, line <> fresh)

def Hub.commit.one(h: Hub, +line: String, c: M.Change, fresh: List<&2, String>, k: Hub -> List<&2, String> -> IO(Hub & List<&2, String>)) -> IO(Hub & List<&2, String>):
  match h:
    case Hub{st, f, ls, cl, as, +inbox, cfg, note}:
      IO.bind(File & Result<&1, &1, U32 & String, Unit>, Hub & List<&2, String>, File.write(f, line ++ "\n"),
        r => Hub.commit.wrote(r, M.State.apply(st, c), line, ls, cl, as, inbox, cfg, note, fresh, k))

def Hub.announce(r: Hub & List<&2, String>) -> IO(Hub):
  (h, fresh) = r
  match h fresh:
    case _ Nil{}:
      IO.pure(Hub, h)
    case Hub{st, f, ls, +cl, as, inbox, cfg, note} l <> t:
      do IO<Hub>:
        Wire.all(cl, Hub.changes_msg(List.reverse(&2, String, l <> t)))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}

# Effects
# -------

def Hub.agent_args(+cfg: Cfg, +model: String, +session: String, r: M.RuntimeMode, i: M.InteractionMode) -> List<&2, String>:
  match cfg:
    case Cfg{_, _, _, _, prompt, dirs, _, _}:
      Q.Claude.args(model, session, r, i, prompt, dirs)

# persist changes, fold them in; answers the hub and the new lines (newest first)
def Hub.commit(cs: List<&2, M.Change>, h: Hub, fresh: List<&2, String>) -> IO(Hub & List<&2, String>):
  match cs:
    case Nil{}:
      IO.pure(Hub & List<&2, String>, (h, fresh))
    case +c <> t:
      Hub.commit.one(h, J.Json.show(C.Change.encode(c)), c, fresh,
        h2 => fr2 => Hub.commit(t, h2, fr2))

def Hub.spawned.fail(e: U32 & String, h: Hub, +thread: String) -> IO(Hub):
  (_, +msg) = e
  do IO<Hub>:
    +now : Nat <- Now.nat()
    Log.info("could not start agent: " ++ msg)
    r : Hub & List<&2, String> <- Hub.commit([M.ActivityLogged{thread, "spawn-" ++ Nat.show(now), "error", "spawn", "could not start claude: " ++ msg, now}, M.TurnChanged{thread, M.Failed{}, now}], h, Nil{})
    Hub.announce(r)

def Hub.spawned.dup(r: Socket & Result<&1, &1, U32 & String, Socket>, +pid: U32, h: Hub, +thread: String) -> IO(Hub):
  (rd, res) = r
  match res h:
    case Done{wr} Hub{st, f, ls, cl, as, +inbox, cfg, note}:
      do IO<Hub>:
        +input : Chan(String) <- Chan.new(String, 256)
        IO.spawn(Unit, Agent.writer(Fuel.forever(), wr, input))
        IO.spawn(Unit, Agent.reader(Fuel.forever(), rd, U.Lines.new(), pid, thread, inbox))
        return Hub{st, f, ls, cl, Agent{thread, input, pid} <> as, inbox, cfg, note}
    case Fail{_} _:
      do IO<Hub>:
        Socket.close(rd)
        return h

def Hub.spawned.ok(started: U32 & Socket, h: Hub, +thread: String) -> IO(Hub):
  (pid, s) = started
  do IO<Hub>:
    r : Socket & Result<&1, &1, U32 & String, Socket> <- H.Sock.dup(s)
    Hub.spawned.dup(r, pid, h, thread)

def Hub.spawned(r: Result<&1, &1, U32 & String, U32 & Socket>, h: Hub, +thread: String) -> IO(Hub):
  match r h:
    case Done{started} Hub{st, f, ls, cl, as, +inbox, cfg, note}:
      Hub.spawned.ok(started, Hub{st, f, ls, cl, as, inbox, cfg, note}, thread)
    case Fail{e} _:
      Hub.spawned.fail(e, h, thread)

def Hub.start.k(m: Maybe<&2, Agent>, h: Hub, +thread: String, +cwd: String, +model: String, +session: String, r: M.RuntimeMode, i: M.InteractionMode) -> IO(Hub):
  match m h:
    case Some{_} _:
      IO.pure(Hub, h)
    case None{} Hub{st, f, ls, cl, as, inbox, +cfg, note}:
      IO.bind(Result<&1, &1, U32 & String, U32 & Socket>, Hub,
        H.Proc.spawn("claude", Hub.agent_args(cfg, model, session, r, i), cwd, 0),
        res => Hub.spawned(res, Hub{st, f, ls, cl, as, inbox, cfg, note}, thread))

def Hub.agent_send(m: Maybe<&2, Agent>, line: String) -> IO(Unit):
  match m:
    case Some{Agent{_, input, _}}:
      do IO<Unit>:
        ok : Bool <- Chan.send(String, input, line)
        return Unit{}
    case None{}:
      IO.pure(Unit, Unit{})

def Hub.agent_stop(m: Maybe<&2, Agent>) -> IO(Unit):
  match m:
    case Some{Agent{_, input, pid}}:
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

def Hub.join(h: Hub, +client: U32, +out: Chan(Wire)) -> IO(Hub):
  match h:
    case Hub{st, f, +ls, cl, as, inbox, +cfg, +note}:
      do IO<Hub>:
        ok : Bool <- Chan.send(Wire, out, WText{Hub.log_msg(ls, Cfg.version(cfg))})
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
    case Net{_, _, t}:
      t

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
    case Net{True{}, https, +token}:
      do IO<Unit>:
        r : P.Ran <- P.Proc.run("tailscale", ["ip", "-4"], "")
        +ip : String = Tailnet.first(r)
        Tailnet.listen.k(String.is_empty(ip), ip, port, web, inbox, token)
        Tailnet.https(https, port, token)
    case Net{False{}, _, _}:
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
    case Cfg{h, w, ho, p, pr, ds, v, Net{tn, hs, _}}:
      Cfg{h, w, ho, p, pr, ds, v, Net{tn, hs, t}}

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

# install the latest release and restart into it
def Upgrade.go(+home: String, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    Upgrade.say(inbox, Upgrade.note([J.KV{"state", J.Str{"updating"}}]))
    exe : String <- H.Sys.exe_dir()
    err : String <- UP.Update.apply(exe, home)
    Upgrade.done(err, inbox)

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

def Hub.gone(h: Hub, +thread: String, +code: U32, +now: Nat) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.step(Hub{st, f, ls, cl, Agents.drop(as, thread), inbox, cfg, note}, B.Hub.agent_gone(st, now, thread, code))

def Hub.tick(h: Hub, +now: Nat) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.step(Hub{st, f, ls, cl, as, inbox, cfg, note}, B.Hub.tick(st, now))

def Hub.handle(h: Hub, m: Msg, +now: Nat) -> IO(Hub):
  match m:
    case Announce{text}:
      Hub.note(h, text)
    case Join{client, out}:
      Hub.join(h, client, out)
    case Leave{client}:
      Hub.leave(h, client)
    case Rpc{client, text}:
      Hub.rpc(h, client, text, now)
    case AgentLine{thread, line}:
      Hub.line(h, thread, line, now)
    case AgentGone{thread, code}:
      Hub.gone(h, thread, code, now)
    case Tick{}:
      Hub.tick(h, now)
    case Push{client, text}:
      Hub.push(h, client, text)

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
      Main.args(t, Cfg{h, w, ho, Maybe.default(&2, U32, U32.read(p), 3773), pr, ds, v, nt})
    case "--host" <> x <> t Cfg{h, w, _, po, pr, ds, v, nt}:
      Main.args(t, Cfg{h, w, x, po, pr, ds, v, nt})
    case "--web" <> x <> t Cfg{h, _, ho, po, pr, ds, v, nt}:
      Main.args(t, Cfg{h, x, ho, po, pr, ds, v, nt})
    case "--home" <> x <> t Cfg{_, w, ho, po, pr, ds, v, nt}:
      Main.args(t, Cfg{x, w, ho, po, pr, ds, v, nt})
    case "--tailscale" <> t Cfg{h, w, ho, po, pr, ds, v, Net{_, https, tok}}:
      Main.args(t, Cfg{h, w, ho, po, pr, ds, v, Net{True{}, https, tok}})
    case "--tailscale-https" <> t Cfg{h, w, ho, po, pr, ds, v, Net{_, _, tok}}:
      Main.args(t, Cfg{h, w, ho, po, pr, ds, v, Net{True{}, True{}, tok}})
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
    case Done{f} Cfg{+home, +web, +host, +port, +pr, +ds, +v, +nt}:
      do IO<Unit>:
        +inbox : Chan(Msg) <- Chan.new(Msg, 4096)
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
        +ls : List<&2, String> = Store.keep(Store.lines(bs), Nil{})
        +st : M.State = M.State.replay(Store.decode(List.reverse(&2, String, ls)), M.State.empty())
        Log.info("replayed " ++ Nat.show(List.length(&2, String, ls)) ++ " changes from " ++ Store.path(home))
        f : Result<&1, &1, U32 & String, File> <- File.open(Store.path(home), "a")
        tok : String <- Token.load(home)
        Main.opened(f, st, ls, Cfg.with_token(Cfg{home, w, h, p, pr, ds, v, nt}, tok), need, front)

def Main.config(+user: String, +exe: String, args: List<String>, ks: String & List<&2, Q.Skill>, kicad: String) -> Cfg:
  (kdir, skills) = ks
  Main.args(args, Cfg{user ++ "/.backplane-bend", exe ++ "/web", "127.0.0.1", 3773,
    Q.Prompt.runtime("Claude Code", kicad, skills), [kdir], Main.version(), Net{False{}, False{}, ""}})

def Sys.exe_dir.io() -> IO(String):
  H.Sys.exe_dir()
