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
import ./gh.bend as GH
import ./term.bend as TM
import ./plot.bend as PV
import ../core/agent.bend as AG
import ../core/tailnet.bend as TN
import ../core/images.bend as IM
import ../core/attach.bend as ATT
import ../core/attach.bend as AT
import ../core/sha1.bend as SH
import ../core/boot.bend as BT
import ../core/store.bend as ST
import ./botnet.bend as BN
import ../core/bothub.bend as BH
import ../core/bot.bend as BO
import ../core/sign.bend as SG
import ./google.bend as GS
import ../core/google.bend as GG
import ../core/ring.bend as RG
import ./voice.bend as VO
import ./perf.bend as PS
import ../core/perf.bend as PF

# The server. One hub computation owns the read model and the event log;
# every connection and agent process is its own computation and talks to
# the hub over channels. The hub runs the pure decider (core/hub.bend) and
# carries out the effects it answers.

# what a connection's writer sends
type Wire is Data:
  WText{text: String}
  WPong{payload: List<&2, U32>}
  # a message already encoded (a board's plot: never parsed again)
  WBin{cbor: List<&2, U32>}
  WClose{}
  # the hub's own window: the read model itself, with the log message's
  # head (no items), in place of the log as text
  WState{st: M.State, head: String}

type Msg is Data:
  Announce{text: String}
  Mcp{thread: String, body: String, reply: Chan(String)}
  Join{client: U32, out: Chan(Wire), since: Nat, origin: String}
  # the window in this process: it takes the read model, not the log
  JoinHere{client: U32, out: Chan(Wire)}
  Leave{client: U32}
  Rpc{client: U32, text: String}
  AgentLine{thread: String, line: String}
  AgentGone{thread: String, code: U32, pid: U32}
  Tick{}
  Push{client: U32, text: String}
  # a message for one client, already CBOR
  PushBin{client: U32, cbor: List<&2, U32>}
  TermOut{thread: String, data: List<&2, U32>}
  # a line for a thread's agent built off the hub (a message with images)
  AgentWrite{thread: String, line: String}
  # time to look for a release on the update channel
  UpdateCheck{}
  ModelsFound{models: String, text: String}
  MachinesFound{machines: String}
  # a Codex or Grok turn's process started: the one the hub now hears (and
  # stops) for the thread; its lines come tagged (B.Tag)
  TurnPid{thread: String, pid: U32, input: Chan(String)}
  # a turn's process exited (tagged)
  TurnDone{tag: String}
  # the hub just started from its log (B.Hub.recover)
  Recover{}
  # changes a job off the hub made (a bot's home folder, a linked machine)
  Commit{changes: List<&2, M.Change>}
  # the minute tick for bots: routines and the linked machines' bots, with
  # this machine's UTC offset as `date +%z` prints it
  BotTick{tz: String}
  # the bots on linked machines (a JSON array)
  BotsFound{dir: String}
  # a request for bots' routes (a webhook, a linked machine, a bot's
  # screen, Google's sign-in redirect); the reply is the whole response
  # (`ct` its content type; `raw` its bytes, kept only for a form with a
  # recording, which is not text)
  BotHttp{kind: String, arg: String, peer: String, ts: String, sig: String, gh: String, delivery: String, body: String, ct: String, raw: List<&2, U32>, reply: Chan(List<&2, U32>)}
  # the same, its signature checked off the hub: `key` is its replay key
  # ("" when it is not genuine); `me` is this machine's name
  BotVerified{kind: String, arg: String, key: String, body: String, me: String, reply: Chan(List<&2, U32>)}
  # a browser page has a new frame: {"t":"shot",...} for every client
  Shot{text: String}

# remote access: also listen on the tailnet, serve HTTPS through
# `tailscale serve`, and the token remote clients must present
type Net is Data:
  Net{tailnet: Bool, https: Bool, token: String, models: String, mtext: String, rt: K.Rt, br: Maybe<&2, Chan(BR.BMsg)>, pk: Maybe<&2, Chan(PK.PMsg)>, tm: Maybe<&2, Chan(TM.TMsg)>, machines: String, pv: Maybe<&2, Chan(PV.PMsg)>, bn: BN.Bn}

type Cfg is Data:
  Cfg{home: String, web: String, host: String, port: U32, prompt: String, dirs: List<&2, String>, version: String, net: Net}

type Client is Data:
  Client{id: U32, out: Chan(Wire)}

type Agent is Data:
  Agent{thread: String, input: Chan(String), pid: U32, key: String}

def Fuel.forever() -> Nat:
  U32.to_nat(4294967295)

def Log.info(+s: String) -> IO(Unit):
  PS.Log.info("hub", s)

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

# read in one pass by src/core/store.bend (ST.Store.load)
def Store.lines.k(r: U.Lines & List<&2, String>) -> List<&2, String>:
  (_, ls) = r
  ls

def Store.lines(bs: List<&2, U32>) -> List<&2, String>:
  Store.lines.k(U.Lines.feed(U.Lines.new(), bs))

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

# a message as a frame: always one binary CBOR frame (about 40% fewer
# bytes on the air than JSON text; every client speaks it). A phone's plot
# is CBOR already and goes as WBin, never through here
def Conn.frame.out(t: String) -> List<&2, U32>:
  W.Ws.cbor(t)

def Conn.write(m: Maybe<&1, Wire>, s: Socket, k: Socket -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{WText{t}}:
      IO.bind(Socket, Unit, Conn.send(s, Conn.frame.out(t)), k)
    case Some{WPong{p}}:
      IO.bind(Socket, Unit, Conn.send(s, W.Ws.encode(10, p)), k)
    case Some{WBin{bs}}:
      IO.bind(Socket, Unit, Conn.send(s, W.Ws.encode(2, bs)), k)
    case Some{WClose{}}:
      Conn.finish(s, W.Ws.encode(8, Nil{}))
    case Some{WState{_, _}}:
      k(s)
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

# a request's CBOR as the JSON text the hub reads
def Conn.cbor.json(m: Maybe<&2, J.Json>) -> String:
  match m:
    case Some{j}:
      J.Json.show(j)
    case None{}:
      ""

def Conn.frame.k(bin: Bool, close: Bool, ping: Bool, p: List<&2, U32>, +id: U32, +inbox: Chan(Msg), +out: Chan(Wire)) -> IO(Bool):
  match bin close ping:
    case True{} _ _:
      do IO<Bool>:
        ok : Bool <- Chan.send(Msg, inbox, Rpc{id, Conn.cbor.json(CB.Cbor.decode(p))})
        return True{}
    case False{} True{} _:
      IO.pure(Bool, False{})
    case False{} False{} True{}:
      do IO<Bool>:
        ok : Bool <- Chan.send(Wire, out, WPong{p})
        return True{}
    case False{} False{} False{}:
      IO.pure(Bool, True{})

# a frame from a client: a binary frame is a request (CBOR, read here as
# JSON text for the hub); close ends; ping pongs; text frames are ignored
def Conn.frame(fr: W.Frame, +id: U32, +inbox: Chan(Msg), +out: Chan(Wire)) -> IO(Bool):
  match fr:
    case W.Frame{_, +op, p}:
      Conn.frame.k(U32.is_eq(op, 2), U32.is_eq(op, 8), U32.is_eq(op, 9), p, id, inbox, out)

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

def Conn.ws.dup(r: Socket & Result<&1, &1, U32 & String, Socket>, rest: List<&2, U32>, +id: U32, +inbox: Chan(Msg), +since: Nat, +origin: String) -> IO(Unit):
  (rd, res) = r
  match res:
    case Done{wr}:
      do IO<Unit>:
        +out : Chan(Wire) <- Chan.new(Wire, 1024)
        IO.spawn(Unit, Conn.writer(Fuel.forever(), wr, out))
        ok : Bool <- Chan.send(Msg, inbox, Join{id, out, since, origin})
        Conn.reader(Fuel.forever(), rd, rest, id, inbox, out)
    case Fail{_}:
      Socket.close(rd)

def Conn.ws(s: Socket, key: String, rest: List<&2, U32>, +id: U32, +inbox: Chan(Msg), +since: Nat, +origin: String) -> IO(Unit):
  do IO<Unit>:
    s2 : Socket <- Conn.send(s, W.Ws.accept(key))
    r : Socket & Result<&1, &1, U32 & String, Socket> <- H.Sock.dup(s2)
    Conn.ws.dup(r, rest, id, inbox, since, origin)

def Conn.safe(+p: String) -> Bool:
  Bool.and(Bool.not(String.contains(p, "..")), String.starts_with(p, "/"))

def Conn.file(+p: String) -> String:
  Bool.pick(String, String.eq(p, "/"), "/index.html", p)

# hashed bundle chunks never change under their name; the page and the
# service worker are checked every time
def Conn.cache(+path: String) -> String:
  Bool.pick(String, String.starts_with(path, "/chunk-"), "public, max-age=31536000, immutable", "no-cache")

# a websocket from plain loopback is trusted; anything else (the tailnet
# listener, or `tailscale serve` proxying with its identity headers) must
# carry ?token=<the pairing token>
def Conn.allowed(+trusted: Bool, +hs: List<&2, W.Header>, +path: String, +token: String) -> Bool:
  Bool.or(Bool.and(trusted, String.is_empty(W.Http.header_of(hs, "tailscale-user-login"))),
    Bool.and(Bool.not(String.is_empty(token)), Bool.or(String.contains(path, "token=" ++ token), String.contains(W.Http.header_of(hs, "cookie"), "bp_token=" ++ token))))

def Conn.gate(ok: Bool, s: Socket, +key: String, rest: List<&2, U32>, +id: U32, +inbox: Chan(Msg), +since: Nat, +origin: String) -> IO(Unit):
  match ok:
    case True{}:
      Conn.ws(s, key, rest, id, inbox, since, origin)
    case False{}:
      Conn.finish(s, W.Http.text("401 Unauthorized", "this Backplane needs its pairing token"))

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

def Conn.head.got(r: Socket & Result<&1, &1, U32 & String, List<&2, U32>>, buf: List<&2, U32>, k: Socket -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  (s, res) = r
  match res:
    case Done{Nil{}}:
      Socket.close(s)
    case Done{bs}:
      k(s, List.append(&2, U32, buf, bs))
    case Fail{_}:
      Socket.close(s)

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
    case Net{tn, hs, _, ms, _, rt, brx, pkx, tmx, mc, pvx, bnx}:
      List.append(&2, J.KV, [J.KV{"models", J.Str{ms}}, J.KV{"machines", J.Str{mc}}, J.KV{"bots.remote", J.Str{BN.Bn.dir(bnx)}}, J.KV{"tailnet", J.Str{Bool.pick(String, tn, Bool.pick(String, hs, "https", "on"), "off")}}], Info.kicad(rt))

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

# the window in this process: the read model (devices left out, as the
# wire leaves them) and the log message with no items
def Hub.join.here(h: Hub, +client: U32, +out: Chan(Wire)) -> IO(Hub):
  match h:
    case Hub{+st, f, +ls, cl, as, inbox, +cfg, +note}:
      do IO<Hub>:
        ok : Bool <- Chan.send(Wire, out, WState{M.State.private(st), Hub.log_msg.k(0n, ls, cfg, 0n)})
        Hub.join.note(out, note)
        return Hub{st, f, ls, Client{client, out} <> cl, as, inbox, cfg, note}

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

def Hub.push(h: Hub, +client: U32, text: String) -> IO(Hub):
  match h:
    case Hub{st, f, ls, +cl, as, inbox, cfg, note}:
      do IO<Hub>:
        Wire.send(Clients.get(cl, client), WText{text})
        return Hub{st, f, ls, cl, as, inbox, cfg, note}

def Hub.push.bin(h: Hub, +client: U32, bs: List<&2, U32>) -> IO(Hub):
  match h:
    case Hub{st, f, ls, +cl, as, inbox, cfg, note}:
      do IO<Hub>:
        Wire.send(Clients.get(cl, client), WBin{bs})
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

# $d from $1: "" and ~ are home, ~/x and relative paths are under home
def FsJob.path.sh() -> String:
  "d=\"$1\"; case \"$d\" in ''|'~') d=\"$HOME\";; '~/'*) d=\"$HOME/${d#??}\";; /*) ;; *) d=\"$HOME/$d\";; esac; "

# a folder that exists and can be opened, printed resolved (symlinks too)
def FsJob.dir.sh() -> String:
  "[ -e \"$d\" ] || { echo \"no such folder: $d\"; exit 2; }; d=$(realpath -e -- \"$d\"); [ -d \"$d\" ] || { echo \"not a folder: $d\"; exit 2; }; [ -r \"$d\" ] && [ -x \"$d\" ] || { echo \"cannot open: $d\"; exit 2; }; "

def FsJob.list.sh() -> String:
  "exec 2>&1; set -e; " ++ FsJob.path.sh() ++ FsJob.dir.sh() ++ "echo \"$d\"; find \"$d\" -mindepth 1 -maxdepth 1 -type d -printf '%f\\n' 2>/dev/null | LC_ALL=C sort | head -n 5000"

# a new folder (and any missing parents); an existing one is refused
def FsJob.mkdir.sh() -> String:
  "exec 2>&1; set -e; " ++ FsJob.path.sh() ++ "if [ -e \"$d\" ] || [ -L \"$d\" ]; then echo \"already exists: $d\"; exit 3; fi; mkdir -p -- \"$d\"; " ++ FsJob.dir.sh() ++ "echo \"$d\""

# the folder a project would have
def FsJob.resolve.sh() -> String:
  "exec 2>&1; set -e; " ++ FsJob.path.sh() ++ FsJob.dir.sh() ++ "echo \"$d\""

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

def FsJob.last(ls: List<&2, String>) -> String:
  Maybe.default(&2, String, List.last(&2, String, ls), "")

def FsJob.made(r: P.Ran, +inbox: Chan(Msg), +client: U32, +id: String) -> IO(Unit):
  match r:
    case P.Ran{0, out}:
      FsJob.list(inbox, client, id, FsJob.last(String.lines(String.trim(out))))
    case P.Ran{_, out}:
      FsJob.answer(inbox, client, id, J.Json.obj([J.KV{"error", J.Str{String.trim(out)}}]))

# a resolved folder becomes a project: the hub gets project.create as if
# the asking client sent it, so the answer (or "already a project") is its
def FsJob.create(r: P.Ran, +inbox: Chan(Msg), +client: U32, +id: String) -> IO(Unit):
  match r:
    case P.Ran{0, out}:
      do IO<Unit>:
        ok : Bool <- Chan.send(Msg, inbox, Rpc{client, J.Json.show(J.Json.obj([J.KV{"id", J.Num{id}}, J.KV{"m", J.Str{"project.create"}},
          J.KV{"p", J.Json.obj([J.KV{"path", J.Str{FsJob.last(String.lines(String.trim(out)))}}])}]))})
        return Unit{}
    case P.Ran{_, out}:
      FsJob.answer(inbox, client, id, J.Json.obj([J.KV{"error", J.Str{String.trim(out)}}]))

def FsJob.sh(+sh: String, +path: String) -> IO(P.Ran):
  P.Proc.run("sh", ["-c", sh, "sh", path], "/")

# list, mkdir (then list it), add (resolve, then create), new (mkdir,
# then create)
def FsJob.run.k(i: Nat, +inbox: Chan(Msg), +client: U32, +id: String, +path: String) -> IO(Unit):
  match i:
    case 1n:
      IO.bind(P.Ran, Unit, FsJob.sh(FsJob.mkdir.sh(), path), r => FsJob.made(r, inbox, client, id))
    case 2n:
      IO.bind(P.Ran, Unit, FsJob.sh(FsJob.resolve.sh(), path), r => FsJob.create(r, inbox, client, id))
    case 3n:
      IO.bind(P.Ran, Unit, FsJob.sh(FsJob.mkdir.sh(), path), r => FsJob.create(r, inbox, client, id))
    case _:
      FsJob.list(inbox, client, id, path)

def FsJob.run(+op: String, +inbox: Chan(Msg), +client: U32, +id: String, +path: String) -> IO(Unit):
  FsJob.run.k(C.Codec.pos(["list", "mkdir", "add", "new"], op), inbox, client, id, path)

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

# A new thread's worktree (Git.thread_wt, in <repo>/.backplane/worktrees).
# When there is no repository to branch, or git fails, the thread works in
# the project folder (thread.local); only a worktree asked for by name
# ("worktree" rather than the default "auto") reports that as an error.

def WtJob.skip(+inbox: Chan(Msg), +thread: String, +tone: String, +why: String) -> IO(Unit):
  do IO<Unit>:
    GitJob.note(inbox, thread, tone, "working in the project folder: " ++ why)
    GitJob.say(inbox, "thread.local", [J.KV{"thread", J.Str{thread}}])

def WtJob.made(+inbox: Chan(Msg), +thread: String, +branch: String, +path: String, carried: Bool) -> IO(Unit):
  do IO<Unit>:
    GitJob.say(inbox, "thread.worktree", [J.KV{"thread", J.Str{thread}}, J.KV{"branch", J.Str{branch}}, J.KV{"path", J.Str{path}}])
    GitJob.note(inbox, thread, "info", "worktree " ++ path ++ Bool.pick(String, carried, " (with the folder's uncommitted work)", ""))

def WtJob.done(+r: String, +inbox: Chan(Msg), +thread: String, +mode: String, +branch: String, +carried: Bool) -> IO(Unit):
  Bool.pick(IO(Unit), GT.Git.skipped(r), WtJob.skip(inbox, thread, Bool.pick(String, String.eq(mode, "worktree"), "error", "info"), String.drop(r, 6n)),
    Bool.pick(IO(Unit), GT.Git.failed(r), WtJob.skip(inbox, thread, "error", String.trim(r)),
      WtJob.made(inbox, thread, branch, r, carried)))

def WtJob.go(+hw: Bool, +inbox: Chan(Msg), +thread: String, +root: String, +mode: String) -> IO(Unit):
  IO.bind(String, Unit, GT.Git.thread_wt(root, hw, GT.Git.branch.temp(B.Wt.seed(thread))),
    r => WtJob.done(r, inbox, thread, mode, GT.Git.branch.sanitize(GT.Git.branch.temp(B.Wt.seed(thread))), hw))

def WtJob.restore.k(n: Nat, +inbox: Chan(Msg), +thread: String, +path: String) -> IO(Unit):
  match n:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+last:
      IO.bind(String, Unit, GT.Git.checkpoint.revert(path, thread, last), r => IO.pure(Unit, Unit{}))

# a worktree made again gets back what it held when it was removed (the
# checkpoint taken then), before anything that waited for it runs
def WtJob.again.k(+r: String, +inbox: Chan(Msg), +thread: String, +branch: String) -> IO(Unit):
  Bool.pick(IO(Unit), Bool.or(GT.Git.failed(r), GT.Git.skipped(r)), WtJob.done(r, inbox, thread, "worktree", branch, False{}),
    IO.bind(Nat, Unit, GitJob.count(r, thread), n => IO.bind(Unit, Unit, WtJob.restore.k(n, inbox, thread, r), _ => WtJob.done(r, inbox, thread, "worktree", branch, False{}))))

# a fork's worktree: a new branch like any thread's, then the source
# thread's last checkpoint restored into it, so the fork starts from the
# files as the source left them
def WtJob.fork.k(+r: String, +inbox: Chan(Msg), +thread: String, +src: String, +branch: String) -> IO(Unit):
  Bool.pick(IO(Unit), Bool.or(GT.Git.failed(r), GT.Git.skipped(r)), WtJob.done(r, inbox, thread, "fork", branch, False{}),
    IO.bind(Nat, Unit, GitJob.count(r, src), n => IO.bind(Unit, Unit, WtJob.restore.k(n, inbox, src, r), _ => WtJob.done(r, inbox, thread, "fork", branch, False{}))))

def WtJob.fork(+inbox: Chan(Msg), +thread: String, +root: String, +src: String) -> IO(Unit):
  IO.bind(String, Unit, GT.Git.thread_wt(root, False{}, GT.Git.branch.temp(B.Wt.seed(thread))),
    r => WtJob.fork.k(r, inbox, thread, src, GT.Git.branch.sanitize(GT.Git.branch.temp(B.Wt.seed(thread)))))

def WtJob.run(+inbox: Chan(Msg), +thread: String, +root: String, +mode: String, +branch: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.eq(mode, "again"),
    IO.bind(String, Unit, GT.Git.thread_wt.again(root, branch), r => WtJob.again.k(r, inbox, thread, branch)),
    Bool.pick(IO(Unit), String.eq(mode, "fork"), WtJob.fork(inbox, thread, root, branch),
      IO.bind(List<&2, String>, Unit, K.Io.names(root), ns => WtJob.go(B.Wt.hardware(ns), inbox, thread, root, mode))))

# Removing a thread's worktree (M.Worktree.drop): its state is kept first as
# a checkpoint (a hidden ref, so nothing is lost; the branch stays too),
# then the worktree goes. Only a directory under .backplane/worktrees is
# ever removed. A worktree already gone is reported gone.

def RmJob.done(+r: String, +inbox: Chan(Msg), +thread: String, +branch: String) -> IO(Unit):
  Bool.pick(IO(Unit), GT.Git.failed(r), Log.info("worktree not removed: " ++ r),
    do IO<Unit>:
      GitJob.say(inbox, "thread.unrooted", [J.KV{"thread", J.Str{thread}}])
      GitJob.note(inbox, thread, "info", "worktree removed; branch " ++ branch ++ " and its last state are kept"))

def RmJob.top(+top: String, +inbox: Chan(Msg), +thread: String, +root: String, +branch: String) -> IO(Unit):
  Bool.pick(IO(Unit), Bool.not(M.Worktree.ours(top ++ "/")), Log.info("worktree not ours, kept: " ++ top),
    IO.bind(String, Unit, GT.Git.worktree.remove_force(root, top), r => RmJob.done(r, inbox, thread, branch)))

def RmJob.saved(+cp: String, +inbox: Chan(Msg), +thread: String, +wt: String, +root: String, +branch: String) -> IO(Unit):
  Bool.pick(IO(Unit), GT.Git.failed(cp), Log.info("worktree kept, no checkpoint: " ++ cp),
    IO.bind(String, Unit, GT.Git.root(wt), top => RmJob.top(top, inbox, thread, root, branch)))

def RmJob.there(r: P.Ran, +inbox: Chan(Msg), +thread: String, +wt: String, +root: String, +branch: String) -> IO(Unit):
  match r:
    case P.Ran{0, _}:
      IO.bind(Nat, Unit, GitJob.count(wt, thread), n => IO.bind(String, Unit, GT.Git.checkpoint.capture(wt, thread, n), cp => RmJob.saved(cp, inbox, thread, wt, root, branch)))
    case _:
      GitJob.say(inbox, "thread.unrooted", [J.KV{"thread", J.Str{thread}}])

def RmJob.run(+inbox: Chan(Msg), +thread: String, +wt: String, +root: String, +branch: String) -> IO(Unit):
  IO.bind(P.Ran, Unit, P.Proc.run("test", ["-d", wt], "/"), r => RmJob.there(r, inbox, thread, wt, root, branch))

# Merges: which of a project's due branches gh reports merged (one call per
# project per tick; nothing happens without gh, auth or a GitHub remote)

def MergeJob.tell(hs: List<&2, J.KV>, +inbox: Chan(Msg)) -> IO(Unit):
  match hs:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case J.KV{th, u} <> t:
      IO.bind(Unit, Unit, GitJob.say(inbox, "thread.merged", [J.KV{"thread", J.Str{th}}, J.KV{"url", u}]), _ => MergeJob.tell(t, inbox))

def MergeJob.got(r: P.Ran, +inbox: Chan(Msg), +lines: String) -> IO(Unit):
  match r:
    case P.Ran{0, out}:
      MergeJob.tell(B.Merge.hits(out, lines), inbox)
    case _:
      IO.pure(Unit, Unit{})

def MergeJob.run(+inbox: Chan(Msg), +root: String, +lines: String) -> IO(Unit):
  IO.bind(P.Ran, Unit, GH.GhRun.run(root, "timeout", ["30", "gh", "pr", "list", "--state", "merged", "--limit", "100", "--json", "headRefName,url"], ["30", "gh", "pr", "list", "--state", "merged", "--limit", "100", "--json", "headRefName,url"]),
    r => MergeJob.got(r, inbox, lines))

def GitJob.text.k(+inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +what: String, +r: String) -> IO(Unit):
  do IO<Unit>:
    GitJob.reply(inbox, client, id, Bool.not(GT.Git.failed(r)), J.Json.obj([J.KV{"text", J.Str{r}}, J.KV{"thread", J.Str{thread}}]))
    GitJob.note(inbox, thread, Bool.pick(String, GT.Git.failed(r), "error", "info"), what ++ Bool.pick(String, String.is_empty(r), "", ": " ++ String.trim(r)))

def GitJob.diff.k(+inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +r: String) -> IO(Unit):
  GitJob.reply(inbox, client, id, Bool.not(GT.Git.failed(r)), J.Json.obj([J.KV{"diff", J.Str{r}}, J.KV{"thread", J.Str{thread}}]))

def GitJob.diff(+cwd: String, +thread: String, +a: String, +b: String) -> IO(String):
  Bool.pick(IO(String), String.eq(b, "-1"), GT.Git.checkpoint.diff_worktree(cwd, thread, Maybe.default(&2, Nat, Nat.read(a), 0n)),
    GT.Git.checkpoint.diff(cwd, thread, Maybe.default(&2, Nat, Nat.read(a), 0n), Maybe.default(&2, Nat, Nat.read(b), 0n)))

# One-shot writing (thread titles, branch names, commit messages)
# ----------------------------------------------------------------
# The text generation model (AG.Text.of: text.provider, text.model) run by
# AG.OneShot.args under timeout(1); the text goes on stdin
# (AG.OneShot.input). "" when the CLI is missing, fails, or takes longer
# than a minute; callers fall back.

def OneShot.out(r: P.Ran, +provider: String) -> String:
  match r:
    case P.Ran{0, out}:
      AG.OneShot.answer(provider, out)
    case _:
      ""

def OneShot.done(r: Socket & Result<&1, &1, U32 & String, Unit>, +pid: U32, +provider: String) -> IO(String):
  (s, _) = r
  do IO<String>:
    s2 : Socket <- H.Sock.shutdown(s)
    d : Socket & List<&2, U32> <- P.Proc.drain(1000000n, s2, P.Chunks{Nil{}})
    ran : P.Ran <- P.Proc.finish(pid, d)
    return OneShot.out(ran, provider)

def OneShot.started(started: U32 & Socket, +input: String, +provider: String) -> IO(String):
  (+pid, s) = started
  IO.bind(Socket & Result<&1, &1, U32 & String, Unit>, String, H.Sock.send_text(s, input), r => OneShot.done(r, pid, provider))

def OneShot.spawned(r: Result<&1, &1, U32 & String, U32 & Socket>, +input: String, +provider: String) -> IO(String):
  match r:
    case Done{started}:
      OneShot.started(started, input, provider)
    case Fail{_}:
      IO.pure(String, "")

# the writer's answer to one text under a system prompt, in /tmp
def OneShot.run(+tx: AG.Tx, +system: String, +input: String) -> IO(String):
  IO.bind(Result<&1, &1, U32 & String, U32 & Socket>, String, H.Proc.spawn("timeout", AG.OneShot.args(tx, system), "/tmp", 0),
    r => OneShot.spawned(r, AG.OneShot.input(AG.Tx.provider(tx), system, input), AG.Tx.provider(tx)))

# a thread's first message: the writer titles it, and the hub keeps the
# title only while the thread still has the placeholder (thread.titled)
def TitleJob.run(+tx: AG.Tx, +inbox: Chan(Msg), +thread: String, +placeholder: String, +text: String) -> IO(Unit):
  IO.bind(String, Unit, OneShot.run(tx, AG.Title.system(), text), a =>
    GitJob.say(inbox, "thread.titled", [J.KV{"thread", J.Str{thread}}, J.KV{"placeholder", J.Str{placeholder}}, J.KV{"title", J.Str{a}}]))

def AgentJob.named(+r: String, +inbox: Chan(Msg), +thread: String) -> IO(Unit):
  Bool.pick(IO(Unit), GT.Git.failed(r), GitJob.note(inbox, thread, "error", "branch name: " ++ r),
    GitJob.say(inbox, "thread.branch", [J.KV{"thread", J.Str{thread}}, J.KV{"branch", J.Str{r}}]))

# a name another branch has already gets the temporary one's hex
def AgentJob.renamed(+r: String, +cwd: String, +old: String, +frag: String, +inbox: Chan(Msg), +thread: String) -> IO(Unit):
  Bool.pick(IO(Unit), GT.Git.failed(r),
    IO.bind(String, Unit, GT.Git.branch.rename(cwd, old, AG.Name.branch(frag) ++ "-" ++ String.drop(old, 10n)), r2 => AgentJob.named(r2, inbox, thread)),
    AgentJob.named(r, inbox, thread))

def AgentJob.rename(+frag: String, +cwd: String, +old: String, +inbox: Chan(Msg), +thread: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.is_empty(frag), IO.pure(Unit, Unit{}),
    IO.bind(String, Unit, GT.Git.branch.rename(cwd, old, AG.Name.branch(frag)), r => AgentJob.renamed(r, cwd, old, frag, inbox, thread)))

# a worktree thread's first message names its branch; without an answer
# the temporary name stays
def AgentJob.name(+tx: AG.Tx, +inbox: Chan(Msg), +thread: String, +cwd: String, +old: String, +text: String) -> IO(Unit):
  IO.bind(String, Unit, OneShot.run(tx, AG.Name.system(), String.take(text, 4000n)), a => AgentJob.rename(AG.Name.fragment(a), cwd, old, inbox, thread))

def AgentJob.write(+tx: AG.Tx, +d: String, +title: String) -> IO(String):
  Bool.pick(IO(String), Bool.or(String.is_empty(String.trim(d)), GT.Git.failed(d)), IO.pure(String, title),
    IO.bind(String, String, OneShot.run(tx, AG.Commit.system(), AG.Commit.input(title, d)), a => IO.pure(String, AG.Commit.message(a, title))))

def AgentJob.commit(+msg: String, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String, +action: String) -> IO(Unit):
  IO.bind(String, Unit, GT.Git.act(cwd, action, msg, "", ""), r => GitJob.text.k(inbox, client, id, thread, action, r))

# Commit & push / Open PR with a message written from the thread's diff
# (checkpoint 0 against the work tree); the thread's title when there is
# no diff or no answer
def AgentJob.act(+tx: AG.Tx, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String, +action: String, +title: String) -> IO(Unit):
  do IO<Unit>:
    d : String <- GT.Git.checkpoint.diff_worktree(cwd, thread, 0n)
    msg : String <- AgentJob.write(tx, d, Bool.pick(String, String.is_empty(title), "Backplane: changes from this thread", title))
    AgentJob.commit(msg, inbox, client, id, thread, cwd, action)

def GitJob.go(i: Nat, +tx: AG.Tx, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String, +a: String, +b: String, +home: String, +seed: Nat) -> IO(Unit):
  match i:
    case 0n:
      WtJob.run(inbox, thread, cwd, a, b)
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
    case 7n:
      AgentJob.name(tx, inbox, thread, cwd, a, b)
    case 8n:
      AgentJob.act(tx, inbox, client, id, thread, cwd, a, b)
    case _:
      IO.pure(Unit, Unit{})

def GitJob.repo(ok: Bool, +tx: AG.Tx, +job: String, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String, +a: String, +b: String, +home: String, +seed: Nat) -> IO(Unit):
  match ok:
    case True{}:
      GitJob.go(C.Codec.pos(["worktree", "checkpoint0", "checkpoint", "diff", "revert", "act", "status", "name", "act_gen"], job), tx, inbox, client, id, thread, cwd, a, b, home, seed)
    case False{}:
      Bool.pick(IO(Unit), String.is_empty(id), IO.pure(Unit, Unit{}), GitJob.reply(inbox, client, id, False{}, J.Json.obj([J.KV{"text", J.Str{"not a git repository: " ++ cwd}}])))

# one git job; nothing happens outside a git repository (checkpoints are
# skipped, requests answer why)
def GitJob.run.git(+tx: AG.Tx, +job: String, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String, +a: String, +b: String, +home: String) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- GT.Git.is_repo(cwd)
    t : U32 <- H.Clock.epoch()
    GitJob.repo(ok, tx, job, inbox, client, id, thread, cwd, a, b, home, U32.to_nat(t))

# Sidebar jobs
# ------------
# A thread's files for the file picker (git's view of the tree in a
# repository, else a bounded walk; at most 3000), and 9:00 tomorrow in the
# machine's time zone for a snooze.

def Files.limit() -> String:
  "3000"

def Files.cmd(repo: Bool) -> String:
  match repo:
    case True{}:
      "git ls-files --cached --others --exclude-standard | head -n " ++ Files.limit()
    case False{}:
      "find . -maxdepth 8 -type f -not -path '*/.*' -not -path '*/node_modules/*' 2>/dev/null | head -n " ++ Files.limit() ++ " | sed 's|^\\./||'"

def Files.str(blank: Bool, l: String, rest: List<&2, J.Json>) -> List<&2, J.Json>:
  match blank:
    case True{}:
      rest
    case False{}:
      J.Str{l} <> rest

def Files.strs(ls: List<&2, String>) -> List<&2, J.Json>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      Files.str(String.is_empty(String.trim(l)), l, Files.strs(t))

def Files.sent(r: P.Ran, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String) -> IO(Unit):
  match r:
    case P.Ran{0, out}:
      GitJob.reply(inbox, client, id, True{}, J.Json.obj([J.KV{"files", J.Json.arr(Files.strs(String.lines(out)))}, J.KV{"thread", J.Str{thread}}]))
    case P.Ran{_, out}:
      GitJob.reply(inbox, client, id, False{}, J.Json.obj([J.KV{"text", J.Str{out}}]))

def Files.list(+inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String) -> IO(Unit):
  do IO<Unit>:
    repo : Bool <- GT.Git.is_repo(cwd)
    r : P.Ran <- P.Proc.run("sh", ["-c", Files.cmd(repo)], cwd)
    Files.sent(r, inbox, client, id, thread)

def Snooze.tz(r: P.Ran) -> String:
  match r:
    case P.Ran{0, out}:
      String.trim(out)
    case _:
      "+0000"

# a tick at start (threads idle past the window settle at once), then
# every minute
def Ticker.loop(fuel: Nat, +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      do IO<Unit>:
        ok : Bool <- Chan.send(Msg, inbox, Tick{})
        tz : P.Ran <- P.Proc.run("date", ["+%z"], "/")
        ok2 : Bool <- Chan.send(Msg, inbox, BotTick{Snooze.tz(tz)})
        IO.sleep(60000)
        Ticker.loop(f, inbox)

# snooze until 9:00 tomorrow here: the hub hears the time as thread.snooze
def Snooze.tomorrow(+inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +now: String) -> IO(Unit):
  do IO<Unit>:
    r : P.Ran <- P.Proc.run("date", ["+%z"], "/")
    GitJob.say(inbox, "thread.snooze", [J.KV{"thread", J.Str{thread}}, J.KV{"until", J.Num{Nat.show(M.Snooze.tomorrow(Maybe.default(&2, Nat, Nat.read(now), 0n), Snooze.tz(r)))}}])
    GitJob.reply(inbox, client, id, True{}, J.Json.obj([J.KV{"thread", J.Str{thread}}]))

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

# open the thread's KiCad project in the bundled KiCad
def KiCadJob.run(+inbox: Chan(Msg), +client: U32, +id: String, +cwd: String, +home: String) -> IO(Unit):
  do IO<Unit>:
    explicit : String <- Env.get("BACKPLANE_KICAD_CLI", "")
    exe : String <- H.Sys.exe_dir()
    rt : K.Rt <- K.Rt.resolve(explicit, exe, home)
    fs : K.Files <- K.Files.read(cwd)
    +err : String <- K.KiCad.open(rt, fs)
    GitJob.reply(inbox, client, id, String.is_empty(err), J.Json.obj([J.KV{"text", J.Str{err}}]))

def GitJob.run.k(i: Nat, +tx: AG.Tx, +job: String, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String, +a: String, +b: String, +home: String) -> IO(Unit):
  match i:
    case 0n:
      Files.list(inbox, client, id, thread, cwd)
    case 1n:
      Snooze.tomorrow(inbox, client, id, thread, a)
    case 2n:
      WtJob.run(inbox, thread, cwd, a, b)
    case 3n:
      MergeJob.run(inbox, cwd, a)
    case 4n:
      RmJob.run(inbox, thread, cwd, a, b)
    case 5n:
      KiCadJob.run(inbox, client, id, cwd, home)
    case 6n:
      TitleJob.run(tx, inbox, thread, a, b)
    case _:
      GitJob.run.git(tx, job, inbox, client, id, thread, cwd, a, b, home)

# a job the hub asked for: a git job, or one of the sidebar's
def GitJob.run(+tx: AG.Tx, +job: String, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String, +a: String, +b: String, +home: String) -> IO(Unit):
  GitJob.run.k(C.Codec.pos(["files", "snooze", "worktree", "merged", "wt_remove", "kicad", "title"], job), tx, job, inbox, client, id, thread, cwd, a, b, home)

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

def Grok.args(r: M.RuntimeMode, +model: String, +effort: String) -> List<&2, String>:
  List.concat(&2, String, [Grok.perm(r), Codex.opt("-m", model), AG.Effort.args("grok", effort), ["stdio"]])

# whether Grok's tool requests go to the user (all modes but full access)
def Grok.asks(r: M.RuntimeMode) -> Bool:
  match r:
    case M.FullAccess{}:
      False{}
    case _:
      True{}

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
    case AC.AcpOut{a, _, _, _}:
      a

def Grok.done(a: AC.Acp) -> Bool:
  match a:
    case AC.Acp{_, _, d}:
      d

def Grok.answered(m: Maybe<&1, String>, +input: Chan(String)) -> IO(Unit):
  match m:
    case Some{+line}:
      Bool.pick(IO(Unit), String.is_empty(line), IO.pure(Unit, Unit{}), Grok.write([line], input))
    case None{}:
      IO.pure(Unit, Unit{})

# a permission request waits off the reader: the hub allows a tool already
# allowed for the session, or opens an approval and parks the request;
# the ACP answer then goes to grok
def Grok.ask.one(+line: String, +thread: String, +input: Chan(String), +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    +reply : Chan(String) <- Chan.new(String, 1)
    ok : Bool <- Chan.send(Msg, inbox, Mcp{thread, line, reply})
    m : Maybe<&1, String> <- Chan.recv(String, reply)
    Grok.answered(m, input)

def Grok.ask(ls: List<&2, String>, +thread: String, +input: Chan(String), +inbox: Chan(Msg)) -> IO(Unit):
  match ls:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case l <> t:
      do IO<Unit>:
        IO.spawn(Unit, Grok.ask.one(l, thread, input, inbox))
        Grok.ask(t, thread, input, inbox)

def Grok.out(o: AC.AcpOut, +thread: String, +input: Chan(String), +inbox: Chan(Msg)) -> IO(AC.Acp):
  match o:
    case AC.AcpOut{a, send, emit, asks}:
      do IO<AC.Acp>:
        Grok.write(send, input)
        Grok.report(emit, thread, inbox)
        Grok.ask(asks, thread, input, inbox)
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
def Turn.end(s: Socket, +pid: U32, +tag: String, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    Socket.close(s)
    code : U32 <- H.Proc.wait(pid)
    ok : Bool <- Chan.send(Msg, inbox, TurnDone{tag})
    return Unit{}

# output closed: a turn that never ended fails; the exit itself is not news
def Codex.end(s: Socket, +pid: U32, ended: Bool, +thread: String, +inbox: Chan(Msg)) -> IO(Unit):
  match ended:
    case True{}:
      Turn.end(s, pid, thread, inbox)
    case False{}:
      do IO<Unit>:
        ok : Bool <- Chan.send(Msg, inbox, AgentLine{thread, AC.Acp.failed("codex exited before the turn ended")})
        Turn.end(s, pid, thread, inbox)

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
    +input : Chan(String) <- Chan.new(String, 1)
    ok : Bool <- Chan.send(Msg, inbox, TurnPid{thread, pid, input})
    Codex.reader(Fuel.forever(), s2, U.Lines.new(), False{}, pid, B.Tag.of(thread, pid), inbox)

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
    Turn.end(s, pid, thread, inbox)

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
    Turn.end(s, pid, thread, inbox)

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
        ok : Bool <- Chan.send(Msg, inbox, TurnPid{thread, pid, input})
        ok2 : Bool <- Chan.send(String, input, AC.Acp.init())
        Grok.reader(Fuel.forever(), rd, U.Lines.new(), AC.Acp.new(), t, pid, B.Tag.of(thread, pid), input, inbox)
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

# 15 s after start, then hourly: the hub looks for a newer release on the
# update channel (it holds the setting)
def Upgrade.check(fuel: Nat, +wait: U32, +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      do IO<Unit>:
        IO.sleep(wait)
        ok : Bool <- Chan.send(Msg, inbox, UpdateCheck{})
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
    case Net{_, _, t, _, _, _, brx, pkx, tmx, mc, pvx, bnx}:
      t

# Effects
# -------

# the MCP endpoint of one thread's agent (token included, so the tailnet
# rules never lock an agent out)
def Hub.mcp_url(+cfg: Cfg, +thread: String) -> String:
  "http://127.0.0.1:" ++ U32.show(Cfg.port(cfg)) ++ "/mcp/" ++ thread ++ "?token=" ++ Net.token(Cfg.net(cfg))

def Cfg.mtext(c: Cfg) -> String:
  match c:
    case Cfg{_, _, _, _, _, _, _, Net{_, _, _, _, mt, _, brx, pkx, tmx, mc, pvx, bnx}}:
      mt

def Cfg.rt(c: Cfg) -> K.Rt:
  match c:
    case Cfg{_, _, _, _, _, _, _, Net{_, _, _, _, _, rt, brx, pkx, tmx, mc, pvx, bnx}}:
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
    Q.Prompt.orchestration(M.Task.may_delegate(B.Task.depth(st, thread)), Cfg.mtext(cfg))], "\n\n") ++ BH.Bots.prompt(st, thread, Cfg.home(cfg))

def Hub.agent_args(+cfg: Cfg, +thread: String, +model: String, +session: String, +r: M.RuntimeMode, +i: M.InteractionMode, prompt: String, +effort: String) -> List<&2, String>:
  match cfg:
    case Cfg{+home, _, _, _, _, dirs, _, _}:
      List.append(&2, String, Q.Claude.args(model, session, r, i, prompt, List.append(&2, String, dirs, [home ++ "/attachments"])), List.append(&2, String, AG.Effort.args("claude", effort),
        ["--mcp-config", "{\"mcpServers\":{\"backplane\":{\"type\":\"http\",\"url\":\"" ++ Hub.mcp_url(cfg, thread) ++ "\"}}}"]))

# what a Claude process was started with; a turn asking for something else
# (another model, mode or effort) restarts it
def Agent.key(+model: String, r: M.RuntimeMode, i: M.InteractionMode, +effort: String) -> String:
  model ++ "|" ++ C.Runtime.name(r) ++ "|" ++ C.Interaction.name(i) ++ "|" ++ AG.Effort.of("claude", effort)

def Agent.same(m: Maybe<&2, Agent>, +key: String) -> Bool:
  match m:
    case Some{Agent{_, _, _, k}}:
      String.eq(k, key)
    case None{}:
      False{}

def Hub.start.go(same: Bool, m: Maybe<&2, Agent>, h: Hub, +thread: String, +cwd: String, +model: String, +session: String, +r: M.RuntimeMode, +i: M.InteractionMode, +effort: String) -> IO(Hub):
  match same h:
    case True{} _:
      IO.pure(Hub, h)
    case False{} Hub{+st, f, ls, cl, +as, inbox, +cfg, note}:
      do IO<Hub>:
        Hub.agent_stop(m)
        fs : K.Files <- K.Files.read(cwd)
        res : Result<&1, &1, U32 & String, U32 & Socket> <- H.Proc.spawn("env", "MCP_TOOL_TIMEOUT=86400000" <> "CLAUDE_CODE_ENABLE_TODO_TOOLS=1" <> "claude" <> Hub.agent_args(cfg, thread, model, session, r, i, Hub.prompt(cfg, st, thread, cwd, fs), effort), cwd, 0)
        Hub.spawned(res, Hub{st, f, ls, cl, Agents.drop(as, thread), inbox, cfg, note}, thread, Agent.key(model, r, i, effort))

def Hub.start.k(+m: Maybe<&2, Agent>, h: Hub, +thread: String, +cwd: String, +model: String, +session: String, +r: M.RuntimeMode, +i: M.InteractionMode, +effort: String) -> IO(Hub):
  Hub.start.go(Agent.same(m, Agent.key(model, r, i, effort)), m, h, thread, cwd, model, session, r, i, effort)

# `codex exec` for one turn, with this thread's MCP endpoint and the
# Backplane instructions (the same runtime block Claude gets)
def Codex.args(+cfg: Cfg, +thread: String, +model: String, +session: String, r: M.RuntimeMode, +text: String, prompt: String, +effort: String) -> List<&2, String>:
  List.concat(&2, String, [Codex.head.k(String.is_empty(session), session), Codex.sandbox(r), Codex.opt("-m", model), AG.Effort.args("codex", effort), AT.Att.codex(text),
    ["-c", "mcp_servers.backplane.url=\"" ++ Hub.mcp_url(cfg, thread) ++ "\"",
     "-c", "developer_instructions=" ++ J.Json.show(J.Str{prompt}), text]])

# what a tailscale command printed ("" when it failed)
def Tailnet.out(r: P.Ran) -> String:
  match r:
    case P.Ran{0, out}:
      out
    case _:
      ""

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
    case Cfg{h, w, ho, p, pr, ds, v, Net{tn, hs, _, ms, mt, rt, brx, pkx, tmx, mc, pvx, bnx}}:
      Cfg{h, w, ho, p, pr, ds, v, Net{tn, hs, t, ms, mt, rt, brx, pkx, tmx, mc, pvx, bnx}}

# Startup
# -------

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

# install the channel's newest release and restart into it
def Upgrade.go(+home: String, +channel: String, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    Upgrade.say(inbox, Upgrade.note([J.KV{"state", J.Str{"updating"}}]))
    exe : String <- H.Sys.exe_dir()
    err : String <- UP.Update.apply(channel, exe, home)
    Upgrade.done(err, inbox)

def Agent.pid_is(m: Maybe<&2, Agent>, +pid: U32) -> Bool:
  match m:
    case Some{Agent{_, _, p, _}}:
      U32.is_eq(p, pid)
    case None{}:
      False{}

def Cfg.models(c: Cfg) -> String:
  match c:
    case Cfg{_, _, _, _, _, _, _, Net{_, _, _, ms, _, _, brx, pkx, tmx, mc, pvx, bnx}}:
      ms

def Cfg.pk(c: Cfg) -> Maybe<&2, Chan(PK.PMsg)>:
  match c:
    case Cfg{_, _, _, _, _, _, _, Net{_, _, _, _, _, _, _, pk, tmx, mc, pvx, bnx}}:
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
    case Net{a, b, c, d, e, f, _, g, i, mc, pvx, bnx}:
      Net{a, b, c, d, e, f, Some{q}, g, i, mc, pvx, bnx}

def Net.with_tm(n: Net, q: Chan(TM.TMsg)) -> Net:
  match n:
    case Net{a, b, c, d, e, f, g, h, _, mc, pvx, bnx}:
      Net{a, b, c, d, e, f, g, h, Some{q}, mc, pvx, bnx}

def Net.with_pv(n: Net, q: Chan(PV.PMsg)) -> Net:
  match n:
    case Net{a, b, c, d, e, f, g, h, i, mc, _, bnx}:
      Net{a, b, c, d, e, f, g, h, i, mc, Some{q}, bnx}

def Cfg.pv(c: Cfg) -> Maybe<&2, Chan(PV.PMsg)>:
  match c:
    case Cfg{_, _, _, _, _, _, _, Net{_, _, _, _, _, _, _, _, _, _, pv, bnx}}:
      pv

def Cfg.tm(c: Cfg) -> Maybe<&2, Chan(TM.TMsg)>:
  match c:
    case Cfg{_, _, _, _, _, _, _, Net{_, _, _, _, _, _, _, _, tm, mc, pvx, bnx}}:
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

# The phones' viewer
# ------------------

# a plot for a phone, to the hub (which writes it to that phone's socket)
def Plot.fwd.got(m: Maybe<&1, PV.POut>, +inbox: Chan(Msg), k: Unit -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{PV.POut{client, text}}:
      do IO<Unit>:
        ok : Bool <- Chan.send(Msg, inbox, Push{client, text})
        k(Unit{})
    case Some{PV.PBin{client, bs}}:
      do IO<Unit>:
        ok : Bool <- Chan.send(Msg, inbox, PushBin{client, bs})
        k(Unit{})
    case None{}:
      IO.pure(Unit, Unit{})

def Plot.fwd(fuel: Nat, +out: Chan(PV.POut), +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      IO.bind(Maybe<&1, PV.POut>, Unit, Chan.recv(PV.POut, out), m => Plot.fwd.got(m, inbox, u => Plot.fwd(f, out, inbox)))

def Plot.put(m: Maybe<&2, Chan(PV.PMsg)>, +msg: PV.PMsg) -> IO(Unit):
  match m:
    case Some{q}:
      do IO<Unit>:
        ok : Bool <- Chan.send(PV.PMsg, q, msg)
        return Unit{}
    case None{}:
      IO.pure(Unit, Unit{})

def Hub.leave(h: Hub, +client: U32) -> IO(Hub):
  match h:
    case Hub{st, f, ls, +cl, as, inbox, +cfg, note}:
      do IO<Hub>:
        Hub.leave.close(Clients.get(cl, client))
        Plot.put(Cfg.pv(cfg), PV.PStop{client})
        return Hub{st, f, ls, Clients.drop(cl, client), as, inbox, cfg, note}

# kicad.watch: kind "board", "schematic" or "3d" shows it, anything else stops
def Plot.watch(+client: U32, +kind: String, +root: String, +path: String) -> PV.PMsg:
  Bool.pick(PV.PMsg, String.eq(kind, "board"), PV.PWatch{client, 0, root, path},
    Bool.pick(PV.PMsg, String.eq(kind, "schematic"), PV.PWatch{client, 1, root, path},
      Bool.pick(PV.PMsg, String.eq(kind, "3d"), PV.PWatch{client, 2, root, path}, PV.PStop{client})))

def Term.msg(+op: String, +thread: String, +cwd: String, data: List<&2, U32>, +cols: U32, +rows: U32) -> TM.TMsg:
  Bool.pick(TM.TMsg, String.eq(op, "open"), TM.TOpen{thread, cwd, cols, rows},
    Bool.pick(TM.TMsg, String.eq(op, "resize"), TM.TSize{thread, cols, rows}, TM.TIn{thread, data}))

# User and project skills
# -----------------------

def Skills.ukeep(empty: Bool, s: AG.USkill, rest: List<&2, AG.USkill>) -> List<&2, AG.USkill>:
  match empty:
    case True{}:
      rest
    case False{}:
      s <> rest

def Skills.uread(ds: List<&2, String>, +root: String) -> IO(List<&2, AG.USkill>):
  match ds:
    case Nil{}:
      IO.pure(List<&2, AG.USkill>, Nil{})
    case +d <> t:
      do IO<List<&2, AG.USkill>>:
        +path : String = root ++ "/" ++ d ++ "/SKILL.md"
        +text : String <- Files.text(path)
        rest : List<&2, AG.USkill> <- Skills.uread(t, root)
        return Skills.ukeep(String.is_empty(text), AG.USkill.parse(text, d, path), rest)

def Skills.names(r: Result<&1, &1, U32 & String, List<String>>) -> List<&2, String>:
  match r:
    case Done{xs}:
      Names.copy(xs)
    case Fail{_}:
      Nil{}

def Skills.dir(+root: String) -> IO(List<&2, AG.USkill>):
  IO.bind(Result<&1, &1, U32 & String, List<String>>, List<&2, AG.USkill>, H.FS.list(root), r => Skills.uread(Skills.names(r), root))

def Skills.scan.k(+home: String, +cwd: String) -> IO(List<&2, AG.USkill>):
  do IO<List<&2, AG.USkill>>:
    us : List<&2, AG.USkill> <- Skills.dir(home ++ "/.claude/skills")
    ps : List<&2, AG.USkill> <- Skills.dir(cwd ++ "/.claude/skills")
    return AG.USkill.merge(us, ps)

# ~/.claude/skills, then <cwd>/.claude/skills (the user's win a clash)
def Skills.scan(+cwd: String) -> IO(List<&2, AG.USkill>):
  IO.bind(String, List<&2, AG.USkill>, Env.get("HOME", "/nonexistent"), home => Skills.scan.k(home, cwd))

def AgentJob.skills(+inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String) -> IO(Unit):
  IO.bind(List<&2, AG.USkill>, Unit, Skills.scan(cwd), ss =>
    GitJob.reply(inbox, client, id, True{}, J.Json.obj([J.KV{"skills", AG.USkill.json(ss)}, J.KV{"thread", J.Str{thread}}])))

# a job for the hub's Git effect: the skills a composer offers (anywhere),
# or a git job (in a repository)
def Jobs.run(+tx: AG.Tx, +job: String, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String, +a: String, +b: String, +home: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.eq(job, "skills"), AgentJob.skills(inbox, client, id, thread, cwd), GitJob.run(tx, job, inbox, client, id, thread, cwd, a, b, home))

# a thread's reasoning effort setting ("" for the provider's default)
def Hub.effort_of(+st: M.State, +thread: String) -> String:
  M.Setting.get(st, AG.Effort.key(thread), "")

def Mention.user_text(+o: J.Json) -> String:
  J.Json.get_str(Maybe.default(&2, J.Json, List.head(&2, J.Json, J.Json.elems(J.Json.get_obj(J.Json.get_obj(o, "message"), "content"))), J.Null{}), "text", "")

def Mention.line.k(m: Maybe<&2, J.Json>, +line: String, +ss: List<&2, AG.USkill>) -> String:
  match m:
    case Some{+o}:
      Bool.pick(String, String.eq(J.Json.get_str(o, "type", ""), "user"), B.Claude.user(AG.Mention.expand("claude", Mention.user_text(o), ss)), line)
    case None{}:
      line

# a Claude stream-json user line with its `$skill` mentions as `/skill`
def Mention.line(+line: String, +ss: List<&2, AG.USkill>) -> String:
  Mention.line.k(J.Json.parse(line), line, ss)

def Hub.agent_send.k(has: Bool, m: Maybe<&2, Agent>, +line: String, +cwd: String) -> IO(Unit):
  match has:
    case True{}:
      IO.bind(List<&2, AG.USkill>, Unit, Skills.scan(cwd), ss => Hub.agent_send(m, Mention.line(line, ss)))
    case False{}:
      Hub.agent_send(m, line)

# one Codex turn: the thread's skills join its instructions and its
# `$skill` mentions become instructions to read them
def Codex.go(+cfg: Cfg, +st: M.State, +thread: String, +cwd: String, +model: String, +session: String, r: M.RuntimeMode, +text: String, fs: K.Files, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    +ss : List<&2, AG.USkill> <- Skills.scan(cwd)
    Codex.run(Codex.args(cfg, thread, model, session, r, AG.Mention.expand("codex", text, ss), Hub.prompt(cfg, st, thread, cwd, fs) ++ AG.USkill.prompt(ss), Hub.effort_of(st, thread)), cwd, thread, inbox)

def Grok.go(+cfg: Cfg, +st: M.State, +thread: String, +cwd: String, +model: String, +session: String, +r: M.RuntimeMode, +text: String, fs: K.Files, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    +ss : List<&2, AG.USkill> <- Skills.scan(cwd)
    Grok.run(Grok.args(r, model, Hub.effort_of(st, thread)),
      AC.AcpTurn{cwd, Hub.mcp_url(cfg, thread), Hub.prompt(cfg, st, thread, cwd, fs) ++ AG.USkill.prompt(ss), AG.Mention.expand("grok", text, ss), session, Grok.asks(r)}, cwd, thread, inbox)

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
    case Net{a, b, c, d, e, f, g, _, i, mc, pvx, bnx}:
      Net{a, b, c, d, e, f, g, Some{q}, i, mc, pvx, bnx}

def Browser.exe() -> IO(String):
  do IO<String>:
    +d : String <- H.Sys.exe_dir()
    ok : Bool <- K.Io.is_file(d ++ "/backplane-browser")
    return Bool.pick(String, ok, d ++ "/backplane-browser", "backplane-browser")

def Cfg.br(c: Cfg) -> Maybe<&2, Chan(BR.BMsg)>:
  match c:
    case Cfg{_, _, _, _, _, _, _, Net{_, _, _, _, _, _, br, pkx, tmx, mc, pvx, bnx}}:
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

def Preview.run.k(m: Maybe<&2, Chan(BR.BMsg)>, +page: String, +id: String, +op: String, args: J.Json, +reply: Chan(String)) -> IO(Unit):
  match m:
    case Some{q}:
      do IO<Unit>:
        line : String <- BR.Browser.ask_on(q, page, op, args)
        ok : Bool <- Chan.send(String, reply, Preview.answer(id, line))
        return Unit{}
    case None{}:
      do IO<Unit>:
        ok : Bool <- Chan.send(String, reply, Preview.answer(id, BR.Browser.fail("no browser in this Backplane")))
        return Unit{}

# a preview_* tool call, answered by the browser off the hub's thread, on
# the page of `page` (a bot's own; "" is the shared page)
def Preview.run(+cfg: Cfg, +page: String, +o: J.Json, +reply: Chan(String)) -> IO(Unit):
  Preview.run.k(Cfg.br(cfg), page, J.Json.as_raw(J.Json.get(o, "id"), "null"), String.drop(J.Json.get_str(J.Json.get_obj(o, "params"), "name", ""), 8n),
    J.Json.get_obj(J.Json.get_obj(o, "params"), "arguments"), reply)

def Preview.is(+o: J.Json) -> Bool:
  Bool.and(String.eq(J.Json.get_str(o, "method", ""), "tools/call"), String.starts_with(J.Json.get_str(J.Json.get_obj(o, "params"), "name", ""), "preview_"))

# opening or navigating brings the Browser tab forward in every window
def Preview.shows(+o: J.Json) -> Bool:
  Bool.or(String.eq(J.Json.get_str(J.Json.get_obj(o, "params"), "name", ""), "preview_open"), String.eq(J.Json.get_str(J.Json.get_obj(o, "params"), "name", ""), "preview_navigate"))

# a shell's output goes to every client (each keeps its own screen)
def Hub.term_out(h: Hub, +thread: String, data: List<&2, U32>) -> IO(Hub):
  match h:
    case Hub{st, f, ls, +cl, as, inbox, cfg, note}:
      do IO<Hub>:
        Wire.all(cl, Term.json(thread, data))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}

def Cfg.with_models(c: Cfg, +ms: String, +mt: String) -> Cfg:
  match c:
    case Cfg{h, w, ho, p, pr, ds, v, Net{tn, hs, t, _, _, rt, brx, pkx, tmx, mc, pvx, bnx}}:
      Cfg{h, w, ho, p, pr, ds, v, Net{tn, hs, t, ms, mt, rt, brx, pkx, tmx, mc, pvx, bnx}}

def Hub.models.k(h: Hub) -> IO(Hub):
  match h:
    case Hub{st, f, ls, +cl, as, inbox, +cfg, note}:
      do IO<Hub>:
        Wire.all(cl, "{\"t\":\"info\",\"info\":" ++ J.Json.show(Hub.info(cfg)) ++ "}")
        return Hub{st, f, ls, cl, as, inbox, cfg, note}

def Cfg.with_machines(c: Cfg, +mc: String) -> Cfg:
  match c:
    case Cfg{h, w, ho, p, pr, ds, v, Net{tn, hs, t, ms, mt, rt, brx, pkx, tmx, _, pvx, bnx}}:
      Cfg{h, w, ho, p, pr, ds, v, Net{tn, hs, t, ms, mt, rt, brx, pkx, tmx, mc, pvx, bnx}}

# the owner's other machines changed: every client hears
def Hub.machines(h: Hub, +mc: String) -> IO(Hub):
  match h:
    case Hub{st, f, ls, +cl, as, inbox, cfg, note}:
      Hub.models.k(Hub{st, f, ls, cl, as, inbox, Cfg.with_machines(cfg, mc), note})

# the providers' models changed: new threads' prompts and every client see
# the new list
def Hub.models(h: Hub, +ms: String, +mt: String) -> IO(Hub):
  match h:
    case Hub{st, f, ls, +cl, as, inbox, cfg, note}:
      Hub.models.k(Hub{st, f, ls, cl, as, inbox, Cfg.with_models(cfg, ms, mt), note})

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
    case "--no-tailscale" <> t Cfg{h, w, ho, po, pr, ds, v, Net{_, _, tok, ms, mt, rt, brx, pkx, tmx, mc, pvx, bnx}}:
      Main.args(t, Cfg{h, w, ho, po, pr, ds, v, Net{False{}, False{}, tok, ms, mt, rt, brx, pkx, tmx, mc, pvx, bnx}})
    case "--tailscale" <> t Cfg{h, w, ho, po, pr, ds, v, Net{_, https, tok, ms, mt, rt, brx, pkx, tmx, mc, pvx, bnx}}:
      Main.args(t, Cfg{h, w, ho, po, pr, ds, v, Net{True{}, https, tok, ms, mt, rt, brx, pkx, tmx, mc, pvx, bnx}})
    case "--tailscale-https" <> t Cfg{h, w, ho, po, pr, ds, v, Net{_, _, tok, ms, mt, rt, brx, pkx, tmx, mc, pvx, bnx}}:
      Main.args(t, Cfg{h, w, ho, po, pr, ds, v, Net{True{}, True{}, tok, ms, mt, rt, brx, pkx, tmx, mc, pvx, bnx}})
    case _ <> t _:
      Main.args(t, c)
    case Nil{} _:
      c

# Model refresh
# -------------
# The providers' model lists are read again every Models.every() ms; a
# list that changed goes to the hub, which tells every client.

def Models.every() -> U32:
  900000

# the last model list found (src/core/boot.bend)
def Models.cache(+home: String) -> String:
  home ++ "/models.cache"

def Net.models(n: Net) -> String:
  match n:
    case Net{_, _, _, ms, _, _, brx, pkx, tmx, mc, pvx, bnx}:
      ms

# Machines
# --------
# Every Machines.every() ms: the owner's online tailnet peers (tailscale
# status) and any hubs named in BACKPLANE_PEERS, each asked GET /hello;
# those that answer run Backplane. The list goes to every client.

def Machines.every() -> U32:
  120000

# a hub that may be there: a name and its base URL
type Cand is Data:
  Cand{name: String, url: String}

def Machines.cands(ms: List<&2, TN.Machine>, +port: U32) -> List<&2, Cand>:
  match ms:
    case Nil{}:
      Nil{}
    case TN.Machine{n, ip, _} <> t:
      Cand{n, "http://" ++ ip ++ ":" ++ U32.show(port)} <> Machines.cands(t, port)

def Machines.name(+url: String) -> String:
  Maybe.default(&2, String, List.head(&2, String, String.split(Bool.pick(String, String.starts_with(url, "http://"), String.drop(url, 7n), url), ':')), url)

def Machines.static.k(blank: Bool, +u: String, rest: List<&2, Cand>) -> List<&2, Cand>:
  match blank:
    case True{}:
      rest
    case False{}:
      Cand{Machines.name(u), u} <> rest

# hubs named in BACKPLANE_PEERS ("http://host:port,..."), for machines
# that are not on the tailnet
def Machines.static(us: List<&2, String>) -> List<&2, Cand>:
  match us:
    case Nil{}:
      Nil{}
    case +u <> t:
      Machines.static.k(String.is_empty(String.trim(u)), String.trim(u), Machines.static(t))

def Machines.urls(cs: List<&2, Cand>) -> List<&2, String>:
  match cs:
    case Nil{}:
      Nil{}
    case Cand{_, u} <> t:
      ("'" ++ u ++ "'") <> Machines.urls(t)

# ask every hub at once; each answer is "<url> <byte> <byte> ...": /hello
# answers CBOR, so od writes its bytes out as decimal numbers
def Machines.probe.sh(+urls: List<&2, String>) -> String:
  "for u in " ++ String.join(urls, " ") ++ "; do (r=$(curl -s -m 3 \"$u/hello\" | od -An -tu1 -v | tr -s ' \\n' '  '); [ -n \"${r# }\" ] && echo \"$u $r\") & done; wait"

def Machines.answer(ls: List<&2, String>, +url: String) -> String:
  match ls:
    case Nil{}:
      ""
    case +l <> t:
      Bool.pick(String, String.starts_with(l, url ++ " "), String.drop(l, Nat.add(String.length(url), 1n)), Machines.answer(t, url))

def Machines.keep(+v: String, +n: String, +url: String, +rest: List<&2, J.Json>) -> List<&2, J.Json>:
  Bool.pick(List<&2, J.Json>, String.is_empty(v), rest,
    J.Json.obj([J.KV{"name", J.Str{n}}, J.KV{"url", J.Str{url}}, J.KV{"version", J.Str{v}}]) <> rest)

def Machines.one(+c: Cand, +ls: List<&2, String>, rest: List<&2, J.Json>) -> List<&2, J.Json>:
  match c:
    case Cand{+n, +u}:
      Machines.keep(TN.Hello.version(TN.Hello.bytes(Machines.answer(ls, u))), n, u, rest)

def Machines.list(cs: List<&2, Cand>, +ls: List<&2, String>) -> List<&2, J.Json>:
  match cs:
    case Nil{}:
      Nil{}
    case +c <> t:
      Machines.one(c, ls, Machines.list(t, ls))

def Machines.found(cs: List<&2, Cand>, r: P.Ran) -> J.Json:
  J.Json.arr(Machines.list(cs, String.lines(Tailnet.out(r))))

# the hubs that answer /hello
def Machines.peers(+cs: List<&2, Cand>) -> IO(J.Json):
  Bool.pick(IO(J.Json), List.is_empty(&2, Cand, cs), IO.pure(J.Json, J.Json.arr(Nil{})),
    IO.bind(P.Ran, J.Json, P.Proc.run("sh", ["-c", Machines.probe.sh(Machines.urls(cs))], "/"), r => IO.pure(J.Json, Machines.found(cs, r))))

def Machines.me(m: TN.Machine, +port: U32) -> J.Json:
  match m:
    case TN.Machine{n, +ip, _}:
      J.Json.obj([J.KV{"name", J.Str{n}}, J.KV{"url", J.Str{Bool.pick(String, String.is_empty(ip), "", "http://" ++ ip ++ ":" ++ U32.show(port))}}])

# {"self": {"name", "url"}, "peers": [{"name", "url", "version"}]}
def Machines.ask(+status: String, +port: U32, +extra: String) -> IO(String):
  IO.bind(J.Json, String, Machines.peers(List.append(&2, Cand, Machines.cands(TN.Tailnet.online(TN.Tailnet.peers(status)), port), Machines.static(String.split(extra, ',')))),
    ps => IO.pure(String, J.Json.show(J.Json.obj([J.KV{"self", Machines.me(TN.Tailnet.self(status), port)}, J.KV{"peers", ps}]))))

def Machines.tell(+inbox: Chan(Msg), +now: String, +last: String) -> IO(String):
  Bool.pick(IO(String), String.eq(now, last), IO.pure(String, last),
    IO.bind(Bool, String, Chan.send(Msg, inbox, MachinesFound{now}), ok => IO.pure(String, now)))

def Machines.loop(fuel: Nat, +inbox: Chan(Msg), +port: U32, +extra: String, +last: String) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      do IO<Unit>:
        st : P.Ran <- P.Proc.run("sh", ["-c", "command -v tailscale >/dev/null && timeout 10 tailscale status --json"], "/")
        found : String <- Machines.ask(Tailnet.out(st), port, extra)
        now : String <- Machines.tell(inbox, found, last)
        IO.sleep(Machines.every())
        Machines.loop(f, inbox, port, extra, now)

def Machines.start(+inbox: Chan(Msg), +port: U32) -> IO(Unit):
  do IO<Unit>:
    extra : String <- Env.get("BACKPLANE_PEERS", "")
    IO.spawn(Unit, Machines.loop(Fuel.forever(), inbox, port, extra, ""))

def Main.version() -> String:
  VR.Version.current()

def Main.failed(e: U32 & String, h: Hub, addr: String) -> IO(Unit):
  (_, msg) = e
  do IO<Unit>:
    Hub.close(h)
    IO.die(Unit, 1, "backplane: cannot listen on " ++ addr ++ ": " ++ msg)

def Main.nolog(e: U32 & String) -> IO(Unit):
  (_, msg) = e
  IO.die(Unit, 1, "backplane: cannot open the event log: " ++ msg)

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

# Claude Code's own model list (what its /model picker offers): asked with
# an `initialize` control request, answered before any model is called
def Claude.probe.sh() -> String:
  "command -v claude >/dev/null || exit 1; printf '%s\\n' '{\"type\":\"control_request\",\"request_id\":\"models\",\"request\":{\"subtype\":\"initialize\"}}' | timeout 30 claude -p --input-format stream-json --output-format stream-json --verbose 2>/dev/null | grep -m1 '\"control_response\"'"

# the models in a probe's answer ([] when it failed or is too old)
def Claude.listed(r: P.Ran) -> List<&2, J.Json>:
  match r:
    case P.Ran{0, out}:
      J.Json.elems(J.Json.get_obj(J.Json.get_obj(J.Json.get_obj(Maybe.default(&2, J.Json, J.Json.parse(String.trim(out)), J.Null{}), "response"), "response"), "models"))
    case _:
      Nil{}

def Claude.values.k(keep: Bool, +v: String, rest: List<&2, String>) -> List<&2, String>:
  match keep:
    case True{}:
      v <> rest
    case False{}:
      rest

# what a thread may pick ("default" is the picker's own first row)
def Claude.values(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case +o <> t:
      Claude.values.k(Bool.not(Bool.or(String.is_empty(J.Json.get_str(o, "value", "")), String.eq(J.Json.get_str(o, "value", ""), "default"))), J.Json.get_str(o, "value", ""), Claude.values(t))

# "Opus 5.5 · claude-opus-5-5"; a full model name gets its description instead
def Claude.label(+o: J.Json) -> String:
  J.Json.get_str(o, "displayName", J.Json.get_str(o, "value", "")) ++ " · "
    ++ Bool.pick(String, String.eq(J.Json.get_str(o, "value", ""), J.Json.get_str(o, "resolvedModel", "")), J.Json.get_str(o, "description", ""), J.Json.get_str(o, "resolvedModel", ""))

def Claude.labels(xs: List<&2, J.Json>) -> List<&2, J.KV>:
  match xs:
    case Nil{}:
      Nil{}
    case +o <> t:
      J.KV{J.Json.get_str(o, "value", ""), J.Str{Claude.label(o)}} <> Claude.labels(t)

# the effort levels each model takes (none for a model without effort)
def Claude.efforts(xs: List<&2, J.Json>) -> List<&2, J.KV>:
  match xs:
    case Nil{}:
      Nil{}
    case +o <> t:
      J.KV{J.Json.get_str(o, "value", ""), J.Json.get_obj(o, "supportedEffortLevels")} <> Claude.efforts(t)

def Claude.models.k(none: Bool, +xs: List<&2, J.Json>) -> List<&2, String>:
  Bool.pick(List<&2, String>, none, Models.claude(), Claude.values(xs))

def Models.on(has: Bool, +xs: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, has, xs, Nil{})

# the probe's list, or the known aliases when the CLI cannot say
def Claude.models(+has: Bool, +xs: List<&2, J.Json>) -> List<&2, String>:
  Models.on(has, Claude.models.k(List.is_empty(&2, J.Json, xs), xs))

def Models.line(+name: String, +xs: List<&2, String>) -> String:
  Bool.pick(String, List.is_empty(&2, String, xs), "", name ++ " (" ++ String.join(xs, ", ") ++ ")")

def Models.join(+a: String, +b: String) -> String:
  Bool.pick(String, String.is_empty(a), b, Bool.pick(String, String.is_empty(b), a, a ++ "; " ++ b))

def Models.text(+cl: List<&2, String>, +cx: List<&2, String>) -> String:
  Models.join(Models.line("claude", cl), Models.line("codex", cx))

def Models.text3(+cl: List<&2, String>, +cx: List<&2, String>, +gk: List<&2, String>) -> String:
  Models.join(Models.text(cl, cx), Models.line("grok", gk))

# what the providers offer: the models JSON clients read, and a line for
# the agents' prompt
type Found is Data:
  Found{models: String, text: String}

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

def Conn.pos(xs: List<&2, String>, +x: String, +i: Nat) -> Nat:
  match xs:
    case Nil{}:
      i
    case +h <> t:
      Bool.pick(Nat, String.eq(h, x), i, Conn.pos(t, x, 1n+i))

# Images in threads
# -----------------
# GET /img?path=<an image an agent named>: the file itself, to a client
# the hub already lets in (it could read the file through a terminal as
# well); only image files, at most IM.Img.cap() bytes.

def Img.sent(bs: List<&2, U32>, s: Socket, +path: String) -> IO(Unit):
  match bs:
    case Nil{}:
      Conn.finish(s, W.Http.text("404 Not Found", "not found"))
    case b <> t:
      Conn.finish(s, W.Http.response.c("200 OK", IM.Img.ctype(path), b <> t, "no-cache", ""))

def Img.read(ok: Bool, s: Socket, +path: String) -> IO(Unit):
  match ok:
    case True{}:
      IO.bind(List<&2, U32>, Unit, Files.read(path), bs => Img.sent(bs, s, path))
    case False{}:
      Conn.finish(s, W.Http.text("404 Not Found", "not an image, or too large"))

def Img.stat.k(st: U32 & U32 & U32, s: Socket, +path: String) -> IO(Unit):
  (kind, rest) = st
  (size, _) = rest
  Img.read(Bool.and(U32.is_eq(kind, 0), U32.is_le(size, IM.Img.cap())), s, path)

def Img.stat(r: Result<&1, &1, U32 & String, U32 & U32 & U32>, s: Socket, +path: String) -> IO(Unit):
  match r:
    case Done{st}:
      Img.stat.k(st, s, path)
    case Fail{_}:
      Conn.finish(s, W.Http.text("404 Not Found", "not found"))

def Img.found(+path: String, s: Socket) -> IO(Unit):
  IO.bind(Result<&1, &1, U32 & String, U32 & U32 & U32>, Unit, H.FS.stat(path), r => Img.stat(r, s, path))

def Img.serve.k(image: Bool, s: Socket, +path: String) -> IO(Unit):
  match image:
    case True{}:
      IO.bind(String, Unit, Env.get("HOME", ""), home => Img.found(Bool.pick(String, String.starts_with(path, "~/"), home ++ String.drop(path, 1n), path), s))
    case False{}:
      Conn.finish(s, W.Http.text("404 Not Found", "not an image"))

def Img.serve(allowed: Bool, s: Socket, +path: String) -> IO(Unit):
  match allowed:
    case True{}:
      Img.serve.k(IM.Img.is_image(path), s, path)
    case False{}:
      Conn.finish(s, W.Http.text("401 Unauthorized", "this Backplane needs its pairing token"))

# GET /hello says a Backplane hub runs here (and which version), so other
# machines of the owner can find it; it needs no token and tells nothing more
def Conn.get(hello: Bool, s: Socket, +web: String, +path: String, gz: Bool) -> IO(Unit):
  match hello:
    case True{}:
      Conn.finish(s, W.Http.response("200 OK", "application/cbor", TN.Hello.answer(Main.version()), ""))
    case False{}:
      Conn.static(s, web, path, gz)

# GET /debug/perf (a table), /debug/perf.json and /debug/log (the last
# log lines): what this process measured since it started (docs/perf.md),
# for a client the hub lets in
def Debug.answer(+i: Nat, +r: String) -> List<&2, U32>:
  match i:
    case 2n:
      W.Http.text("200 OK", PF.Stats.table(PF.Stats.parse(r)))
    case 3n:
      W.Http.response("200 OK", "application/json", U.Utf8.encode(J.Json.show(PF.Stats.json(PF.Stats.parse(r)))), "")
    case _:
      W.Http.text("200 OK", r)

def Debug.read(+i: Nat) -> IO(String):
  match i:
    case 4n:
      PS.Perf.logs()
    case _:
      PS.Perf.take()

def Debug.serve(allowed: Bool, +i: Nat, s: Socket) -> IO(Unit):
  match allowed:
    case True{}:
      IO.bind(String, Unit, Debug.read(i), r => Conn.finish(s, Debug.answer(i, r)))
    case False{}:
      Conn.finish(s, W.Http.text("401 Unauthorized", "this Backplane needs its pairing token"))

def Conn.get.k(i: Nat, s: Socket, +web: String, +p: String, gz: Bool, +allowed: Bool) -> IO(Unit):
  match i:
    case 0n:
      Conn.get(True{}, s, web, W.Http.route(p), gz)
    case 1n:
      Img.serve(allowed, s, ATT.Att.from_uri("file://" ++ W.Http.param(p, "path")))
    case 2n:
      Debug.serve(allowed, 2n, s)
    case 3n:
      Debug.serve(allowed, 3n, s)
    case 4n:
      Debug.serve(allowed, 4n, s)
    case _:
      Conn.get(False{}, s, web, W.Http.route(p), gz)

def Conn.route.k(ws: Bool, s: Socket, req: W.Request, rest: List<&2, U32>, +web: String, +id: U32, +inbox: Chan(Msg), +trusted: Bool, +token: String) -> IO(Unit):
  match ws req:
    case True{} W.Request{_, +p, +hs}:
      Conn.gate(Conn.allowed(trusted, hs, p, token), s, W.Http.header_of(hs, "sec-websocket-key"), rest, id, inbox,
        Maybe.default(&2, Nat, Nat.read(W.Http.param(p, "since")), 0n), W.Http.param(p, "origin"))
    case False{} W.Request{_, +p, +hs}:
      Conn.get.k(Conn.pos(["/hello", "/img", "/debug/perf", "/debug/perf.json", "/debug/log"], W.Http.route(p), 0n), s, web, p, String.contains(W.Http.header_of(hs, "accept-encoding"), "gzip"), Conn.allowed(trusted, hs, p, token))

def Conn.route.mcp(mcp: Bool, s: Socket, +req: W.Request, rest: List<&2, U32>, +web: String, +id: U32, +inbox: Chan(Msg), +trusted: Bool, +token: String) -> IO(Unit):
  match mcp req:
    case True{} W.Request{_, +p, +hs}:
      Mcp.gate(Conn.allowed(trusted, hs, p, token), s, String.drop(W.Http.route(p), 5n),
        Maybe.default(&2, Nat, Nat.read(W.Http.header_of(hs, "content-length")), 0n), rest, inbox)
    case False{} _:
      Conn.route.k(Conn.is_ws(req), s, req, rest, web, id, inbox, trusted, token)

def Refresh.news(news: Bool, +ms: String, +mt: String, +inbox: Chan(Msg), +cache: String, +last: String) -> IO(String):
  match news:
    case True{}:
      do IO<String>:
        ok : Bool <- Chan.send(Msg, inbox, ModelsFound{ms, mt})
        w : String <- Token.save(cache, BT.Cache.of(ms, mt))
        return ms
    case False{}:
      IO.pure(String, last)

# a probe's list goes to clients and the cache when it is news
def Refresh.found(fd: Found, +inbox: Chan(Msg), +cache: String, +last: String) -> IO(String):
  match fd:
    case Found{+ms, +mt}:
      Refresh.news(BT.Models.news(ms, last), ms, mt, inbox, cache, last)

def Models.found(+cl: List<&2, String>, +cx: List<&2, String>, +gk: List<&2, String>, about: J.Json) -> Found:
  Found{J.Json.show(J.Json.obj([J.KV{"claude", Models.strs(cl)}, J.KV{"codex", Models.strs(cx)}, J.KV{"grok", Models.strs(gk)}, J.KV{"about", about}])), Models.text3(cl, cx, gk)}

def Models.boot(ks: String & List<&2, Q.Skill>, +rt: K.Rt, fd: Found) -> Boot:
  (kdir, skills) = ks
  match fd:
    case Found{ms, mt}:
      Boot{kdir, skills, rt, ms, mt}

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
# What each provider is: its CLI's version, and a label per model. This
# table is only for a Claude CLI too old to answer the probe.
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

def Claude.about(+cli: String, +xs: List<&2, J.Json>) -> J.Json:
  Bool.pick(J.Json, List.is_empty(&2, J.Json, xs), About.one(cli, About.claude()),
    J.Json.obj([J.KV{"cli", J.Str{cli}}, J.KV{"labels", J.Json.obj(Claude.labels(xs))}, J.KV{"efforts", J.Json.obj(Claude.efforts(xs))}]))

# which providers are installed and what models they offer (at start, and
# again every Models.every() ms: new models appear without a restart)
def Models.detect(+user: String) -> IO(Found):
  do IO<Found>:
    cl : P.Ran <- P.Proc.run("sh", ["-c", "command -v claude"], "/")
    cx : P.Ran <- P.Proc.run("sh", ["-c", "command -v codex"], "/")
    +cache : String <- K.Io.text(user ++ "/.codex/models_cache.json")
    +gk : P.Ran <- P.Proc.run("sh", ["-c", "command -v grok >/dev/null && timeout 15 grok models"], "/")
    pc : P.Ran <- P.Proc.run("sh", ["-c", Claude.probe.sh()], "/")
    vc : P.Ran <- P.Proc.run("sh", ["-c", "timeout 10 claude --version"], "/")
    vx : P.Ran <- P.Proc.run("sh", ["-c", "timeout 10 codex --version"], "/")
    vg : P.Ran <- P.Proc.run("sh", ["-c", "timeout 10 grok --version"], "/")
    +xs : List<&2, J.Json> = Claude.listed(pc)
    return Models.found(Claude.models(Main.has(cl), xs), Models.on(Main.has(cx), Models.codex(cache)), Models.grok(gk),
      J.Json.obj([J.KV{"claude", Claude.about(About.cli(vc), xs)}, J.KV{"codex", About.one(About.cli(vx), About.codex(cache))}, J.KV{"grok", About.one(About.cli(vg), About.grok(gk))}]))

# the first probe runs at once (the window is up by then), the next ones
# every Models.every() ms
def Refresh.loop(fuel: Nat, +inbox: Chan(Msg), +user: String, +cache: String, +last: String) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      do IO<Unit>:
        fd : Found <- Models.detect(user)
        now : String <- Refresh.found(fd, inbox, cache, last)
        IO.sleep(Models.every())
        Refresh.loop(f, inbox, user, cache, now)

def Refresh.start(+inbox: Chan(Msg), +cfg: Cfg) -> IO(Unit):
  do IO<Unit>:
    user : String <- Env.get("HOME", "")
    IO.spawn(Unit, Refresh.loop(Fuel.forever(), inbox, user, Models.cache(Cfg.home(cfg)), Net.models(Cfg.net(cfg))))

def Main.prepare(+user: String, +exe: String) -> IO(Boot):
  do IO<Boot>:
    K.KiStack.ensure(user)
    ks : String & List<&2, Q.Skill> <- Skills.kistack.dir(user ++ "/.cache/backplane/kistack/" ++ K.KiStack.revision())
    explicit : String <- Env.get("BACKPLANE_KICAD_CLI", "")
    rt : K.Rt <- K.Rt.resolve(explicit, exe, user ++ "/.backplane-bend")
    return Models.boot(ks, rt, Found{"", ""})

def Main.config(+user: String, +exe: String, args: List<String>, b: Boot) -> Cfg:
  Boot{kdir, skills, rt, ms, mt} = b
  Main.args(args, Cfg{user ++ "/.backplane-bend", exe ++ "/web", "127.0.0.1", 3787,
    Q.Prompt.runtime("Backplane", skills), [kdir], Main.version(), Net{True{}, False{}, "", ms, mt, rt, None{}, None{}, None{}, "", None{}, BN.Bn.empty()}})

def Sys.exe_dir.io() -> IO(String):
  H.Sys.exe_dir()

# Media jobs (Hub.media): attachments and update checks
# -----------------------------------------------------

def Media.fail(+inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +msg: String) -> IO(Unit):
  GitJob.reply(inbox, client, id, False{}, J.Json.obj([J.KV{"text", J.Str{msg}}, J.KV{"thread", J.Str{thread}}, J.KV{"upload", J.Flag{True{}}}]))

def Media.attached(+inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +path: String) -> IO(Unit):
  GitJob.reply(inbox, client, id, True{}, J.Json.obj([J.KV{"attached", J.Str{path}}, J.KV{"thread", J.Str{thread}}]))

def Media.wrote.k(res: Result<&1, &1, U32 & String, Unit>) -> String:
  match res:
    case Done{_}:
      ""
    case Fail{_}:
      "cannot write the attachment"

def Media.wrote(r: File & Result<&1, &1, U32 & String, Unit>) -> IO(String):
  (f, res) = r
  do IO<String>:
    File.close(f)
    return Media.wrote.k(res)

def Media.opened(r: Result<&1, &1, U32 & String, File>, bs: List<&2, U32>) -> IO(String):
  match r:
    case Done{f}:
      IO.bind(File & Result<&1, &1, U32 & String, Unit>, String, File.write_bytes(f, bs), Media.wrote)
    case Fail{_}:
      IO.pure(String, "cannot open the attachment file")

# write (mode "w") or append ("a") bytes; "" or what went wrong
def Media.put.file(+path: String, +mode: String, bs: List<&2, U32>) -> IO(String):
  IO.bind(Result<&1, &1, U32 & String, File>, String, File.open(path, mode), r => Media.opened(r, bs))

def Media.size(r: Result<&1, &1, U32 & String, U32 & U32 & U32>) -> Nat:
  match r:
    case Done{(0, (sz, _))}:
      U32.to_nat(sz)
    case _:
      0n

# a regular file's size (None for anything else)
def Media.stat(r: Result<&1, &1, U32 & String, U32 & U32 & U32>) -> Maybe<&2, Nat>:
  match r:
    case Done{(0, (sz, _))}:
      Some{U32.to_nat(sz)}
    case _:
      None{}

def Media.put.done(+err: String, +last: Bool, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +path: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.is_empty(err),
    Bool.pick(IO(Unit), last, Media.attached(inbox, client, id, thread, path), GitJob.reply(inbox, client, id, True{}, J.Json.obj(Nil{}))),
    Media.fail(inbox, client, id, thread, err))

def Media.put.k(over: Bool, +first: Bool, +last: Bool, bs: List<&2, U32>, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +path: String) -> IO(Unit):
  match over:
    case True{}:
      do IO<Unit>:
        rm : Result<&1, &1, U32 & String, Unit> <- H.FS.remove(path)
        Media.fail(inbox, client, id, thread, "attachments are limited to " ++ Nat.show(Nat.div(AT.Att.cap(), 1048576n)) ++ " MB")
    case False{}:
      IO.bind(String, Unit, Media.put.file(path, Bool.pick(String, first, "w", "a"), bs), e => Media.put.done(e, last, inbox, client, id, thread, path))

def Media.put.go(+have: Nat, +first: Bool, +last: Bool, +bs: List<&2, U32>, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +path: String) -> IO(Unit):
  Media.put.k(Nat.is_gt(Nat.add(have, List.length(&2, U32, bs)), AT.Att.cap()), first, last, bs, inbox, client, id, thread, path)

def Media.put.parts(ps: List<&2, String>, +b: String, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +home: String) -> IO(Unit):
  match ps:
    case +i <> +l <> +name <> _:
      do IO<Unit>:
        mk : Result<&1, &1, U32 & String, Unit> <- H.FS.mkdirs(AT.Att.dir(home, thread))
        st : Result<&1, &1, U32 & String, U32 & U32 & U32> <- H.FS.stat(AT.Att.dir(home, thread) ++ "/" ++ AT.Att.safe(name))
        Media.put.go(Bool.pick(Nat, String.eq(i, "0"), 0n, Media.size(st)), String.eq(i, "0"), String.eq(l, "1"), AT.Att.b64(b),
          inbox, client, id, thread, AT.Att.dir(home, thread) ++ "/" ++ AT.Att.safe(name))
    case _:
      Media.fail(inbox, client, id, thread, "bad upload")

# one piece of an upload (a = "<index>|<last>|<name>", b = base64); the
# first piece starts the file, the rest append; a file never passes the cap
# and never lands outside <home>/attachments/<thread>/
def Media.put(+inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +a: String, +b: String, +home: String) -> IO(Unit):
  Media.put.parts(String.split(a, '|'), b, inbox, client, id, thread, home)

def Media.copy.k(ok: Bool, fits: Bool, +src: String, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +dest: String) -> IO(Unit):
  match ok fits:
    case True{} True{}:
      do IO<Unit>:
        bs : List<&2, U32> <- Files.read(src)
        Media.put.go(0n, True{}, True{}, bs, inbox, client, id, thread, dest)
    case True{} False{}:
      Media.fail(inbox, client, id, thread, "attachments are limited to " ++ Nat.show(Nat.div(AT.Att.cap(), 1048576n)) ++ " MB")
    case False{} _:
      Media.fail(inbox, client, id, thread, "not a file: " ++ src)

def Media.copy.m(m: Maybe<&2, Nat>, +src: String, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +dest: String) -> IO(Unit):
  match m:
    case Some{+n}:
      Media.copy.k(True{}, Nat.is_le(n, AT.Att.cap()), src, inbox, client, id, thread, dest)
    case None{}:
      Media.copy.k(False{}, True{}, src, inbox, client, id, thread, dest)

# a file on this machine (the native window's paste or path), copied in
def Media.file(+inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +src: String, +name: String, +home: String) -> IO(Unit):
  do IO<Unit>:
    mk : Result<&1, &1, U32 & String, Unit> <- H.FS.mkdirs(AT.Att.dir(home, thread))
    st : Result<&1, &1, U32 & String, U32 & U32 & U32> <- H.FS.stat(src)
    Media.copy.m(Media.stat(st), src, inbox, client, id, thread, AT.Att.dir(home, thread) ++ "/" ++ AT.Att.safe(name))

def Media.img.k(ok: Bool, +path: String) -> IO(Maybe<&2, AT.Img>):
  match ok:
    case True{}:
      IO.bind(List<&2, U32>, Maybe<&2, AT.Img>, Files.read(path), bs => IO.pure(Maybe<&2, AT.Img>, Some{AT.Img{AT.Att.mime(path), SH.B64.encode(bs)}}))
    case False{}:
      IO.pure(Maybe<&2, AT.Img>, None{})

def Media.img.m(m: Maybe<&2, Nat>, +path: String) -> IO(Maybe<&2, AT.Img>):
  match m:
    case Some{+n}:
      Media.img.k(Bool.and(Nat.is_gt(n, 0n), Nat.is_le(n, U32.to_nat(AT.Att.inline_max()))), path)
    case None{}:
      IO.pure(Maybe<&2, AT.Img>, None{})

# an attached image small enough to send inline
def Media.img(+path: String) -> IO(Maybe<&2, AT.Img>):
  do IO<Maybe<&2, AT.Img>>:
    st : Result<&1, &1, U32 & String, U32 & U32 & U32> <- H.FS.stat(path)
    Media.img.m(Media.stat(st), path)

def Media.imgs.add(m: Maybe<&2, AT.Img>, acc: List<&2, AT.Img>) -> List<&2, AT.Img>:
  match m:
    case Some{i}:
      i <> acc
    case None{}:
      acc

def Media.imgs(ps: List<&2, String>, acc: List<&2, AT.Img>) -> IO(List<&2, AT.Img>):
  match ps:
    case Nil{}:
      IO.pure(List<&2, AT.Img>, List.reverse(&2, AT.Img, acc))
    case +p <> t:
      IO.bind(Maybe<&2, AT.Img>, List<&2, AT.Img>, Media.img(p), m => Media.imgs(t, Media.imgs.add(m, acc)))

# look for a release on a channel now (announced like the hourly check)
def Media.check(+channel: String, +inbox: Chan(Msg), +client: U32, +id: String) -> IO(Unit):
  do IO<Unit>:
    r : Maybe<&2, UP.Release> <- UP.Update.latest(channel)
    +tag : String = UP.Update.newer(r)
    Upgrade.found(tag, inbox)
    Bool.pick(IO(Unit), String.is_empty(id), IO.pure(Unit, Unit{}), GitJob.reply(inbox, client, id, True{}, J.Json.obj([J.KV{"version", J.Str{tag}}, J.KV{"channel", J.Str{channel}}])))

# a Claude message with images: read them, then hand the stream-json line
# (image blocks, then the text) to the thread's agent
def Media.claude(+inbox: Chan(Msg), +thread: String, +cwd: String, +text: String) -> IO(Unit):
  do IO<Unit>:
    ims : List<&2, AT.Img> <- Media.imgs(AT.Att.images(text), Nil{})
    +ss : List<&2, AG.USkill> <- Skills.scan(cwd)
    ok : Bool <- Chan.send(Msg, inbox, AgentWrite{thread, AT.Att.claude(AG.Mention.expand("claude", text, ss), ims)})
    return Unit{}

# a Git out: the media jobs here (an upload piece runs on the hub, so the
# pieces of a file land in order), git jobs off the hub
def Media.run.k(i: Nat, +tx: AG.Tx, +job: String, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String, +a: String, +b: String, +home: String) -> IO(Unit):
  match i:
    case 0n:
      Media.put(inbox, client, id, thread, a, b, home)
    case 1n:
      IO.spawn(Unit, Media.file(inbox, client, id, thread, a, b, home))
    case 2n:
      IO.spawn(Unit, Media.claude(inbox, thread, cwd, a))
    case 3n:
      IO.spawn(Unit, Media.check(a, inbox, client, id))
    case _:
      IO.spawn(Unit, Jobs.run(tx, job, inbox, client, id, thread, cwd, a, b, home))

def Media.run(+tx: AG.Tx, +job: String, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String, +cwd: String, +a: String, +b: String, +home: String) -> IO(Unit):
  Media.run.k(C.Codec.pos(["attach.put", "attach.file", "attach.claude", "update.check"], job), tx, job, inbox, client, id, thread, cwd, a, b, home)

# thread_wait: the check (MC.Wait.now) goes through the hub each second,
# off the hub, until the thread is done or the time is up; its last answer
# is the reply
def Wait.next(stop: Bool, text: String, +reply: Chan(String), k: Unit -> IO(Unit)) -> IO(Unit):
  match stop:
    case True{}:
      IO.bind(Bool, Unit, Chan.send(String, reply, text), ok => IO.pure(Unit, Unit{}))
    case False{}:
      IO.bind(Unit, Unit, IO.sleep(1000), k)

def Wait.got(m: Maybe<&1, String>, +left: Nat, +reply: Chan(String), k: Unit -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{+text}:
      Wait.next(Bool.or(MC.Wait.done(text), Nat.is_eq(left, 0n)), text, reply, k)
    case None{}:
      IO.pure(Unit, Unit{})

def Wait.loop(+fuel: Nat, +thread: String, +check: String, +reply: Chan(String), +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      do IO<Unit>:
        +r2 : Chan(String) <- Chan.new(String, 1)
        ok : Bool <- Chan.send(Msg, inbox, Mcp{thread, check, r2})
        m : Maybe<&1, String> <- Chan.recv(String, r2)
        Wait.got(m, f, reply, _ => Wait.loop(f, thread, check, reply, inbox))

def Hub.agent_write(h: Hub, +thread: String, line: String) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, +as, inbox, cfg, note}:
      do IO<Hub>:
        Hub.agent_send(Agents.get(as, thread), line)
        return Hub{st, f, ls, cl, as, inbox, cfg, note}

def Hub.update_check(h: Hub) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, +inbox, cfg, note}:
      do IO<Hub>:
        IO.spawn(Unit, Media.check(M.Setting.get(st, "update.channel", "stable"), inbox, 0, ""))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}

def Agent.pid_of(m: Maybe<&2, Agent>) -> Maybe<&2, U32>:
  match m:
    case Some{Agent{_, _, p, _}}:
      Some{p}
    case None{}:
      None{}

def Hub.turn_pid.k(run: Bool, h: Hub, +thread: String, +pid: U32, input: Chan(String)) -> IO(Hub):
  match run h:
    case True{} Hub{st, f, ls, cl, +as, inbox, cfg, note}:
      do IO<Hub>:
        Hub.agent_stop(Agents.get(as, thread))
        return Hub{st, f, ls, cl, Agent{thread, input, pid, "turn"} <> Agents.drop(as, thread), inbox, cfg, note}
    case False{} _:
      do IO<Hub>:
        Chan.close(String, input)
        H.Proc.kill(pid, 15)
        return h

# a turn process started: it replaces whatever ran for the thread before;
# one whose turn was stopped before it came up is stopped at once
def Hub.turn_pid(h: Hub, +thread: String, +pid: U32, input: Chan(String)) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.turn_pid.k(B.Hub.running(B.Hub.thread(st, thread)), Hub{st, f, ls, cl, as, inbox, cfg, note}, thread, pid, input)

def Hub.turn_done.k(same: Bool, h: Hub, +thread: String) -> Hub:
  match same h:
    case True{} Hub{st, f, ls, cl, as, inbox, cfg, note}:
      Hub{st, f, ls, cl, Agents.drop(as, thread), inbox, cfg, note}
    case False{} _:
      h

# a turn process exited: forgotten, unless another replaced it already
def Hub.turn_done(h: Hub, +tag: String) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, +as, inbox, cfg, note}:
      IO.pure(Hub, Hub.turn_done.k(B.Tag.heard(B.Tag.pid(tag), Agent.pid_of(Agents.get(as, B.Tag.thread(tag)))), Hub{st, f, ls, cl, as, inbox, cfg, note}, B.Tag.thread(tag)))

# Bots
# ----
# The IO of docs/bots.md around the pure decider (core/bothub.bend):
# effects (B.BotFx), signed requests from webhooks and linked machines,
# Google's tools, a bot's own browser page. Secrets are handled by
# botnet.bend and never reach the log, the event log or a broadcast.

def Cfg.bn(c: Cfg) -> BN.Bn:
  match c:
    case Cfg{_, _, _, _, _, _, _, Net{_, _, _, _, _, _, brx, pkx, tmx, mc, pvx, bnx}}:
      bnx

def Cfg.with_bn(c: Cfg, b: BN.Bn) -> Cfg:
  match c:
    case Cfg{h, w, ho, p, pr, ds, v, Net{tn, hs, t, ms, mt, rt, brx, pkx, tmx, mc, pvx, _}}:
      Cfg{h, w, ho, p, pr, ds, v, Net{tn, hs, t, ms, mt, rt, brx, pkx, tmx, mc, pvx, b}}

def Cfg.host(c: Cfg) -> String:
  match c:
    case Cfg{_, _, ho, _, _, _, _, _}:
      ho

def Cfg.tailnet(c: Cfg) -> Bool:
  match c:
    case Cfg{_, _, _, _, _, _, _, Net{tn, _, _, _, _, _, brx, pkx, tmx, mc, pvx, bnx}}:
      tn

def Hub.broadcast(h: Hub, +text: String) -> IO(Hub):
  match h:
    case Hub{st, f, ls, +cl, as, inbox, cfg, note}:
      do IO<Hub>:
        Wire.all(cl, text)
        return Hub{st, f, ls, cl, as, inbox, cfg, note}

# a thread's browser page: a bot's is named by the bot, any other
# thread's by the thread (BO.World.page)
def Bot.page(+st: M.State, +thread: String) -> String:
  BO.World.page(M.State.bots(st), thread)

def Bot.is_bot(m: Maybe<&2, BO.Bot>) -> Bool:
  match m:
    case Some{_}:
      True{}
    case None{}:
      False{}

# opening or navigating brings the Browser tab forward in the viewer of
# the thread that asked (a bot shows its page in its own Browser tab)
def Preview.view(+thread: String) -> String:
  J.Json.show(J.Json.obj([J.KV{"t", J.Str{"view"}}, J.KV{"thread", J.Str{thread}}, J.KV{"kind", J.Str{"browser"}}, J.KV{"path", J.Str{""}}]))

def Hub.preview(h: Hub, +thread: String, +o: J.Json, +reply: Chan(String)) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, +cl, as, inbox, +cfg, note}:
      do IO<Hub>:
        IO.spawn(Unit, Preview.run(cfg, Bot.page(st, thread), o, reply))
        Bool.pick(IO(Unit), Bool.and(Bool.not(Bot.is_bot(BO.World.of_thread(M.State.bots(st), thread))), Preview.shows(o)), Wire.all(cl, Preview.view(thread)), IO.pure(Unit, Unit{}))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}

# requests: "bots.*" to the bots' decider, the rest to the hub's
def Bot.request.k(bots: Bool, +o: J.Json, +st: M.State, +now: Nat, +client: U32) -> B.Step:
  match bots:
    case True{}:
      BH.Bots.request(st, now, client, o)
    case False{}:
      B.Hub.request(st, now, client, o)

def Bot.request(m: Maybe<&2, J.Json>, +st: M.State, +now: Nat, +client: U32, +text: String) -> B.Step:
  match m:
    case Some{+o}:
      Bot.request.k(BH.Bots.is(J.Json.get_str(o, "m", "")), o, st, now, client)
    case None{}:
      B.Hub.request_text(st, now, client, text)

# Memory reaches only the agent: a bot's turn text gets its <memory>
# block here, after the timeline kept the text as it was sent

def Bot.line.k(m: Maybe<&2, J.Json>, +st: M.State, +now: Nat, +thread: String, +line: String) -> String:
  match m:
    case Some{+o}:
      Bool.pick(String, String.eq(J.Json.get_str(o, "type", ""), "user"), B.Claude.user(BH.Bots.turn(st, now, thread, Mention.user_text(o))), line)
    case None{}:
      line

# a Claude stream-json line for a bot's thread: a user message gets the memory
def Bot.line(bot: Bool, +st: M.State, +now: Nat, +thread: String, +line: String) -> String:
  match bot:
    case True{}:
      Bot.line.k(J.Json.parse(line), st, now, thread, line)
    case False{}:
      line

# a Claude message with images carries its text in the job's `a`
def Bot.attach(claude: Bool, +st: M.State, +now: Nat, +thread: String, +a: String) -> String:
  match claude:
    case True{}:
      BH.Bots.turn(st, now, thread, a)
    case False{}:
      a

# Effects
# -------

def BotJob.reply(+inbox: Chan(Msg), +client: U32, +id: String, +ok: Bool, kvs: List<&2, J.KV>) -> IO(Unit):
  do IO<Unit>:
    sent : Bool <- Chan.send(Msg, inbox, Push{client, J.Json.show(J.Json.obj(List.append(&2, J.KV, [J.KV{"t", J.Str{"reply"}}, J.KV{"id", J.Num{id}}, J.KV{"ok", J.Flag{ok}}], kvs)))})
    return Unit{}

def BotJob.fail(+inbox: Chan(Msg), +client: U32, +id: String, msg: String) -> IO(Unit):
  BotJob.reply(inbox, client, id, False{}, [J.KV{"error", J.Str{msg}}])

def BotJob.client(+b: String) -> U32:
  Maybe.default(&2, U32, U32.read(b), 0)

def BotJob.id(+c: String) -> String:
  Bool.pick(String, String.is_empty(c), "0", c)

# a bot's home folder, a git repository (so its turns get checkpoints),
# becomes its thread's folder
def BotJob.home.k(safe: Bool, +inbox: Chan(Msg), +home: String, +bot: String, +thread: String) -> IO(Unit):
  match safe:
    case True{}:
      do IO<Unit>:
        +path : String = home ++ "/bots/" ++ bot
        mk : Result<&1, &1, U32 & String, Unit> <- H.FS.mkdirs(path)
        r : P.Ran <- P.Proc.run("git", ["init", "-q"], path)
        +now : Nat <- Now.nat()
        ok : Bool <- Chan.send(Msg, inbox, Commit{[M.WorktreeSet{thread, "", path, now}]})
        return Unit{}
    case False{}:
      Log.info("bots: not a folder name: " ++ bot)

def BotJob.hooked(+secret: String, +inbox: Chan(Msg), +client: U32, +id: String, +hook: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.is_empty(secret), BotJob.fail(inbox, client, id, "could not keep the webhook's secret"),
    BotJob.reply(inbox, client, id, True{}, [J.KV{"hook", J.Str{hook}}, J.KV{"secret", J.Str{secret}}, J.KV{"path", J.Str{"/hook/" ++ hook}}]))

# a webhook's secret: made and kept here, shown once to the client that asked
def BotJob.hook(+inbox: Chan(Msg), +home: String, +hook: String, +client: U32, +id: String) -> IO(Unit):
  IO.bind(String, Unit, BN.Bn.hook.make(home, hook), s => BotJob.hooked(s, inbox, client, id, hook))

def BotJob.sent(r: BN.Resp, +peer: String, +path: String) -> IO(Unit):
  match r:
    case BN.Resp{+code, _}:
      Bool.pick(IO(Unit), Bool.and(Nat.is_ge(code, 200n), Nat.is_lt(code, 300n)), IO.pure(Unit, Unit{}),
        Log.info("bots: " ++ path ++ " to " ++ peer ++ " failed (" ++ Nat.show(code) ++ ")"))

# a signed POST to a linked machine
def BotJob.send(+home: String, +url: String, +peer: String, +path: String, +body: String) -> IO(Unit):
  do IO<Unit>:
    +now : Nat <- Now.nat()
    r : BN.Resp <- BN.Bn.to_peer(home, url, peer, now, path, True{}, body)
    BotJob.sent(r, peer, path)

def BotJob.invited(ok: Bool, +inbox: Chan(Msg), +client: U32, +id: String, +url: String, +peer: String, +secret: String) -> IO(Unit):
  match ok:
    case True{}:
      BotJob.reply(inbox, client, id, True{}, [J.KV{"invite", J.Str{SG.Invite.make(url, peer, secret)}}, J.KV{"peer", J.Str{peer}}])
    case False{}:
      BotJob.fail(inbox, client, id, "could not keep the invite's secret")

# an invite: a new peer id and secret, kept here; the other machine links
# with it (POST /bots/link) and both keep the secret
def BotJob.invite(+inbox: Chan(Msg), +home: String, +tailnet: Bool, +host: String, +port: U32, +given: String, +client: U32, +id: String) -> IO(Unit):
  do IO<Unit>:
    +here : String <- BN.Bn.url.here(tailnet, host, port)
    +r : String <- BN.Bn.random(2n)
    +peer : String = "p" ++ r
    +secret : String <- BN.Bn.secret.fresh()
    ok : Bool <- BN.Bn.peer.save(home, peer, secret)
    BotJob.invited(ok, inbox, client, id, Bool.pick(String, String.is_empty(String.trim(given)), here, String.trim(given)), peer, secret)

def BotJob.linked.k(ok: Bool, +name: String, +code: Nat, +body: String, +inbox: Chan(Msg), +home: String, +url: String, +peer: String, +client: U32, +id: String, +now: Nat) -> IO(Unit):
  match ok:
    case True{}:
      do IO<Unit>:
        +shown : String = Bool.pick(String, String.is_empty(name), peer, name)
        sent : Bool <- Chan.send(Msg, inbox, Commit{[M.PeerSet{peer, shown, url, False{}, now}]})
        BotJob.reply(inbox, client, id, True{}, [J.KV{"peer", J.Str{peer}}, J.KV{"name", J.Str{shown}}])
    case False{}:
      do IO<Unit>:
        BN.Bn.peer.forget(home, peer)
        BotJob.fail(inbox, client, id, "the other machine did not link (" ++ Nat.show(code) ++ ") " ++ String.take(String.trim(body), 200n))

def BotJob.linked(r: BN.Resp, +inbox: Chan(Msg), +home: String, +url: String, +peer: String, +client: U32, +id: String, +now: Nat) -> IO(Unit):
  match r:
    case BN.Resp{+code, +body}:
      BotJob.linked.k(Nat.is_eq(code, 200n), BN.Bn.clean(J.Json.get_str(Maybe.default(&2, J.Json, J.Json.parse(body), J.Null{}), "name", "")), code, body,
        inbox, home, url, peer, client, id, now)

# joining with an invite: keep its secret, tell the inviter where we are
# (signed POST /bots/link), and link once it answers with its name
def BotJob.join(+inbox: Chan(Msg), +home: String, +tailnet: Bool, +host: String, +port: U32, +url: String, +peer: String, +secret: String, +client: U32, +id: String) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- BN.Bn.peer.save(home, peer, secret)
    +here : String <- BN.Bn.url.here(tailnet, host, port)
    +me : String <- BN.Bn.name()
    +now : Nat <- Now.nat()
    r : BN.Resp <- BN.Bn.signed(home, url, peer, secret, now, "/bots/link", True{}, J.Json.show(J.Json.obj([J.KV{"url", J.Str{here}}, J.KV{"name", J.Str{me}}])))
    BotJob.linked(r, inbox, home, url, peer, client, id, now)

def BotJob.join.go(ok: Bool, linked: Bool, +inbox: Chan(Msg), +cfg: Cfg, +url: String, +peer: String, +secret: String, +client: U32, +id: String) -> IO(Unit):
  match ok linked:
    case True{} False{}:
      IO.spawn(Unit, BotJob.join(inbox, Cfg.home(cfg), Cfg.tailnet(cfg), Cfg.host(cfg), Cfg.port(cfg), url, peer, secret, client, id))
    case True{} True{}:
      BotJob.fail(inbox, client, id, "already linked to that machine")
    case False{} _:
      BotJob.fail(inbox, client, id, "not a usable invite")

def Bot.peer.live.k(p: BO.Peer) -> Bool:
  match p:
    case BO.Peer{_, _, _, _, revoked}:
      Bool.not(revoked)

def Bot.peer.live(+st: M.State, +id: String) -> Bool:
  Bot.peer.live.k(BO.World.peer(M.State.bots(st), id))

def Bot.peer.url.k(p: BO.Peer) -> String:
  match p:
    case BO.Peer{_, _, u, _, revoked}:
      Bool.pick(String, revoked, "", u)

# a live peer's address ("" for none)
def Bot.peer.url(+st: M.State, +id: String) -> String:
  Bot.peer.url.k(BO.World.peer(M.State.bots(st), id))

def Bot.peer.name.k(p: BO.Peer, +id: String) -> String:
  match p:
    case BO.Peer{_, +n, _, _, _}:
      Bool.pick(String, String.is_empty(n), id, n)

# what bots here call a peer ("name@<this>")
def Bot.peer.name(+st: M.State, +id: String) -> String:
  Bot.peer.name.k(BO.World.peer(M.State.bots(st), id), id)

def BotJob.join.k(m: Maybe<&2, SG.Inv>, +st: M.State, +inbox: Chan(Msg), +cfg: Cfg, +client: U32, +id: String) -> IO(Unit):
  match m:
    case Some{SG.Inv{+url, +peer, +secret}}:
      BotJob.join.go(Bool.and(BN.Bn.url.ok(url), BN.Bn.safe(peer)), Bot.peer.live(st, peer), inbox, cfg, url, peer, secret, client, id)
    case None{}:
      BotJob.fail(inbox, client, id, "not an invite")

def BotJob.send.k(+url: String, +cfg: Cfg, +peer: String, +path: String, +body: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.is_empty(url), Log.info("bots: no linked machine " ++ peer),
    IO.spawn(Unit, BotJob.send(Cfg.home(cfg), url, peer, path, body)))

def BotJob.close(m: Maybe<&2, Chan(BR.BMsg)>, +bot: String) -> IO(Unit):
  match m:
    case Some{q}:
      IO.bind(String, Unit, BR.Browser.ask_on(q, bot, "close", J.Json.obj(Nil{})), r => IO.pure(Unit, Unit{}))
    case None{}:
      IO.pure(Unit, Unit{})

def Bot.redirect(+port: U32) -> String:
  "http://127.0.0.1:" ++ U32.show(port) ++ "/oauth/google"

# "configure" (phones) and "config" are the same op
def BotJob.google.pos(+op: String) -> Nat:
  Bool.pick(Nat, String.eq(op, "configure"), 0n, C.Codec.pos(["config", "begin", "finish", "status", "disconnect"], op))

def BotJob.google.op(i: Nat, +home: String, +p: J.Json, +redirect: String) -> IO(String):
  match i:
    case 0n:
      GS.Google.configure(home, J.Json.get_str(p, "clientId", ""), J.Json.get_str(p, "clientSecret", ""))
    case 1n:
      GS.Google.begin(home, redirect)
    case 2n:
      GS.Google.finish(home, J.Json.get_str(p, "pasted", ""), redirect)
    case 3n:
      GS.Google.status(home)
    case 4n:
      GS.Google.disconnect(home)
    case _:
      IO.pure(String, "error: unknown Google request")

def BotJob.google.done(+text: String, +begin: Bool, +inbox: Chan(Msg), +client: U32, +id: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.starts_with(text, "error"), BotJob.fail(inbox, client, id, Bool.pick(String, String.starts_with(text, "error: "), String.drop(text, 7n), text)),
    BotJob.reply(inbox, client, id, True{}, [J.KV{Bool.pick(String, begin, "googleUrl", "google"), J.Str{text}}]))

# Google's setup and sign-in (src/server/google.bend), off the hub
def BotJob.google(+inbox: Chan(Msg), +home: String, +port: U32, +params: String, +client: U32, +id: String) -> IO(Unit):
  do IO<Unit>:
    +p : J.Json = Maybe.default(&2, J.Json, J.Json.parse(params), J.Null{})
    +i : Nat = BotJob.google.pos(J.Json.get_str(p, "op", ""))
    +text : String <- BotJob.google.op(i, home, p, Bot.redirect(port))
    BotJob.google.done(text, Nat.is_eq(i, 1n), inbox, client, id)

def Bot.ran(r: P.Ran) -> String:
  match r:
    case P.Ran{0, out}:
      out
    case _:
      ""

def Bot.serve(on: Bool) -> IO(P.Ran):
  match on:
    case True{}:
      P.Proc.run("sh", ["-c", "command -v tailscale >/dev/null && timeout 5 tailscale serve status --json"], "/")
    case False{}:
      IO.pure(P.Ran, P.Ran{1, ""})

def Bot.hook.base.k(+env: String, +serve: String, +here: String) -> String:
  Bool.pick(String, String.is_empty(env), Bool.pick(String, String.is_empty(serve), here, serve),
    Bool.pick(String, String.ends_with(env, "/"), String.take(env, Nat.sub(String.length(env), 1n)), env))

# where a phone reaches this hub's webhooks: BACKPLANE_HOOK_URL (a
# funnel, a relay), else the HTTPS address `tailscale serve` gives the
# hub's port, else its tailnet address (plain HTTP)
def Bot.hook.base(+tailnet: Bool, +host: String, +port: U32) -> IO(String):
  do IO<String>:
    +env : String <- BN.Bf.env("BACKPLANE_HOOK_URL")
    r : P.Ran <- Bot.serve(tailnet)
    +here : String <- BN.Bn.url.here(tailnet, host, port)
    return Bot.hook.base.k(String.trim(env), TN.Tailnet.serve(Bot.ran(r), U32.show(port)), here)

def BotJob.token.or(none: Bool, +t: String, +home: String, +hook: String) -> IO(String):
  match none:
    case True{}:
      BN.Bn.token.make(home, hook)
    case False{}:
      IO.pure(String, t)

def BotJob.token.got(+t: String, +home: String, +hook: String) -> IO(String):
  BotJob.token.or(String.is_empty(t), t, home, hook)

# 0: the hook's token (made the first time), 1: a new one, 2: none
def BotJob.token.tok(op: Nat, +home: String, +hook: String) -> IO(String):
  match op:
    case 0n:
      IO.bind(String, String, BN.Bn.token.of(home, hook), t => BotJob.token.got(t, home, hook))
    case 1n:
      BN.Bn.token.make(home, hook)
    case _:
      IO.bind(Unit, String, BN.Bn.token.forget(home, hook), u => IO.pure(String, ""))

def BotJob.token.done(bad: Bool, +tok: String, +url: String, +inbox: Chan(Msg), +client: U32, +id: String, +hook: String) -> IO(Unit):
  match bad:
    case True{}:
      BotJob.fail(inbox, client, id, "could not keep the webhook's token")
    case False{}:
      BotJob.reply(inbox, client, id, True{}, [J.KV{"tokenHook", J.Str{hook}}, J.KV{"token", J.Str{tok}}, J.KV{"tokenUrl", J.Str{url ++ "/hook/" ++ hook}}])

# a webhook's bearer token, shown to the client that asked (only clients
# the server lets in reach this), with the URL a phone posts to
def BotJob.token(+op: Nat, +inbox: Chan(Msg), +home: String, +tailnet: Bool, +host: String, +port: U32, +hook: String, +client: U32, +id: String) -> IO(Unit):
  do IO<Unit>:
    +tok : String <- BotJob.token.tok(op, home, hook)
    +url : String <- Bot.hook.base(tailnet, host, port)
    BotJob.token.done(Bool.and(String.is_empty(tok), Nat.is_lt(op, 2n)), tok, url, inbox, client, id, hook)

# Dictation (server/voice.bend): the key, the dictionary, and live sessions
# of this machine's microphone, whose messages go to the client that
# started them. "add" also comes from a bot's voice_dictionary_add (client
# 0: no one hears the answer).

# the key (masked), the dictionary and the microphones
def VoiceJob.status(+inbox: Chan(Msg), +home: String, +client: U32, +id: String) -> IO(Unit):
  do IO<Unit>:
    kvs : List<&2, J.KV> <- VO.Vo.status(home)
    +d : String <- VO.Vo.devices()
    BotJob.reply(inbox, client, id, True{}, List.append(&2, J.KV, kvs, [J.KV{"voiceDevices", J.Str{d}}]))

# "" when done (then the status goes back), else "error: why"
def VoiceJob.done(+err: String, +inbox: Chan(Msg), +home: String, +client: U32, +id: String) -> IO(Unit):
  Bool.pick(IO(Unit), String.is_empty(err), VoiceJob.status(inbox, home, client, id), BotJob.fail(inbox, client, id, String.drop(err, 7n)))

def VoiceJob.fwd.k(end: Bool, k: Unit -> IO(Unit)) -> IO(Unit):
  match end:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      k(Unit{})

def VoiceJob.fwd(m: Maybe<&1, String>, +inbox: Chan(Msg), +client: U32, k: Unit -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{+text}:
      do IO<Unit>:
        sent : Bool <- Chan.send(Msg, inbox, Push{client, text})
        VoiceJob.fwd.k(String.contains(text, "\"ev\":\"idle\""), k)
    case None{}:
      IO.pure(Unit, Unit{})

# a session's messages to its client, until idle
def VoiceJob.forward(fuel: Nat, +out: Chan(String), +inbox: Chan(Msg), +client: U32) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      IO.bind(Maybe<&1, String>, Unit, Chan.recv(String, out), m => VoiceJob.fwd(m, inbox, client, u => VoiceJob.forward(f, out, inbox, client)))

def VoiceJob.live(+inbox: Chan(Msg), +home: String, +client: U32, +id: String, +thread: String, +device: String) -> IO(Unit):
  do IO<Unit>:
    BotJob.reply(inbox, client, id, True{}, Nil{})
    +out : Chan(String) <- Chan.new(String, 256)
    IO.spawn(Unit, VO.Vo.live(home, thread, device, out))
    VoiceJob.forward(Fuel.forever(), out, inbox, client)

def VoiceJob.stopped(on: Bool, +inbox: Chan(Msg), +client: U32, +id: String, +thread: String) -> IO(Unit):
  match on:
    case True{}:
      BotJob.reply(inbox, client, id, True{}, Nil{})
    case False{}:
      do IO<Unit>:
        BotJob.reply(inbox, client, id, True{}, Nil{})
        sent : Bool <- Chan.send(Msg, inbox, Push{client, VO.Vo.msg(thread, "idle", Nil{})})
        return Unit{}

def VoiceJob.op(i: Nat, +inbox: Chan(Msg), +home: String, +p: J.Json, +client: U32, +id: String) -> IO(Unit):
  match i:
    case 0n:
      VoiceJob.status(inbox, home, client, id)
    case 1n:
      IO.bind(String, Unit, VO.Vo.set_key(home, J.Json.get_str(p, "key", "")), e => VoiceJob.done(e, inbox, home, client, id))
    case 2n:
      IO.bind(String, Unit, VO.Vo.unkey(home), e => VoiceJob.done(e, inbox, home, client, id))
    case 3n:
      IO.bind(String, Unit, VO.Vo.set_dict(home, J.Json.get_str(p, "dict", "")), e => VoiceJob.done(e, inbox, home, client, id))
    case 4n:
      IO.bind(String, Unit, VO.Vo.add(home, J.Json.get_str(p, "term", "")), e => VoiceJob.done(e, inbox, home, client, id))
    case 5n:
      VoiceJob.live(inbox, home, client, id, J.Json.get_str(p, "thread", ""), J.Json.get_str(p, "device", ""))
    case 6n:
      IO.bind(Bool, Unit, VO.Vo.stop(home), on => VoiceJob.stopped(on, inbox, client, id, J.Json.get_str(p, "thread", "")))
    case 7n:
      IO.bind(String, Unit, VO.Vo.devices(), d => BotJob.reply(inbox, client, id, True{}, [J.KV{"voiceDevices", J.Str{d}}]))
    case _:
      BotJob.fail(inbox, client, id, "unknown voice request")

def VoiceJob.go(+p: J.Json, +inbox: Chan(Msg), +home: String, +client: U32, +id: String) -> IO(Unit):
  VoiceJob.op(C.Codec.pos(["status", "key", "unkey", "dict", "add", "start", "stop", "devices"], J.Json.get_str(p, "op", "")), inbox, home, p, client, id)

def VoiceJob.run(+inbox: Chan(Msg), +home: String, +params: String, +client: U32, +id: String) -> IO(Unit):
  VoiceJob.go(Maybe.default(&2, J.Json, J.Json.parse(params), J.Null{}), inbox, home, client, id)

# one B.BotFx: home, gone, hook, unhook, send, invite, join, unpeer, google,
# token, retoken, untoken, voice
def Bot.fx(i: Nat, +st: M.State, +inbox: Chan(Msg), +cfg: Cfg, +a: String, +b: String, +c: String) -> IO(Unit):
  match i:
    case 0n:
      IO.spawn(Unit, BotJob.home.k(BN.Bn.safe(a), inbox, Cfg.home(cfg), a, b))
    case 1n:
      IO.spawn(Unit, BotJob.close(Cfg.br(cfg), a))
    case 2n:
      IO.spawn(Unit, BotJob.hook(inbox, Cfg.home(cfg), a, BotJob.client(b), BotJob.id(c)))
    case 3n:
      IO.spawn(Unit, BN.Bn.hook.forget(Cfg.home(cfg), a))
    case 4n:
      BotJob.send.k(Bot.peer.url(st, a), cfg, a, b, c)
    case 5n:
      IO.spawn(Unit, BotJob.invite(inbox, Cfg.home(cfg), Cfg.tailnet(cfg), Cfg.host(cfg), Cfg.port(cfg), a, BotJob.client(b), BotJob.id(c)))
    case 6n:
      BotJob.join.k(SG.Invite.parse(a), st, inbox, cfg, BotJob.client(b), BotJob.id(c))
    case 7n:
      IO.spawn(Unit, BN.Bn.peer.forget(Cfg.home(cfg), a))
    case 8n:
      IO.spawn(Unit, BotJob.google(inbox, Cfg.home(cfg), Cfg.port(cfg), a, BotJob.client(b), BotJob.id(c)))
    case 9n:
      IO.spawn(Unit, BotJob.token(0n, inbox, Cfg.home(cfg), Cfg.tailnet(cfg), Cfg.host(cfg), Cfg.port(cfg), a, BotJob.client(b), BotJob.id(c)))
    case 10n:
      IO.spawn(Unit, BotJob.token(1n, inbox, Cfg.home(cfg), Cfg.tailnet(cfg), Cfg.host(cfg), Cfg.port(cfg), a, BotJob.client(b), BotJob.id(c)))
    case 11n:
      IO.spawn(Unit, BotJob.token(2n, inbox, Cfg.home(cfg), Cfg.tailnet(cfg), Cfg.host(cfg), Cfg.port(cfg), a, BotJob.client(b), BotJob.id(c)))
    case 12n:
      IO.spawn(Unit, VoiceJob.run(inbox, Cfg.home(cfg), a, BotJob.client(b), BotJob.id(c)))
    case _:
      IO.pure(Unit, Unit{})

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
    case Hub{+st, f, ls, cl, +as, inbox, cfg, note} B.AgentStart{+thread, +cwd, _, +model, +session, r, i}:
      Hub.start.k(Agents.get(as, thread), Hub{st, f, ls, cl, as, inbox, cfg, note}, thread, cwd, model, session, r, i, Hub.effort_of(st, thread))
    case Hub{+st, f, ls, cl, +as, inbox, cfg, note} B.AgentSend{+thread, +line}:
      do IO<Hub>:
        +now : Nat <- Now.nat()
        +l2 : String = Bot.line(BO.World.is_bot_thread(M.State.bots(st), thread), st, now, thread, line)
        Hub.agent_send.k(String.contains(l2, "$"), Agents.get(as, thread), l2, B.Hub.cwd(st, B.Hub.thread(st, thread)))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{st, f, ls, cl, +as, inbox, cfg, note} B.AgentStop{+thread}:
      do IO<Hub>:
        Hub.agent_stop(Agents.get(as, thread))
        return Hub{st, f, ls, cl, Agents.drop(as, thread), inbox, cfg, note}
    case Hub{st, f, ls, cl, as, inbox, +cfg, note} B.PlotInfo{+client, +id, +key, +at, +idx}:
      do IO<Hub>:
        Plot.put(Cfg.pv(cfg), PV.PInfo{client, id, key, at, idx})
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{st, f, ls, cl, as, inbox, +cfg, note} B.Watch{+client, +kind, +root, +path}:
      do IO<Hub>:
        Plot.put(Cfg.pv(cfg), Plot.watch(client, kind, root, path))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{+st, f, ls, cl, as, +inbox, +cfg, note} B.CodexTurn{+thread, +cwd, +model, +session, r, text}:
      do IO<Hub>:
        fs : K.Files <- K.Files.read(cwd)
        +now : Nat <- Now.nat()
        IO.spawn(Unit, Codex.go(cfg, st, thread, cwd, model, session, r, BH.Bots.turn(st, now, thread, text), fs, inbox))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{st, f, ls, cl, as, +inbox, +cfg, note} B.KiCadInstall{}:
      do IO<Hub>:
        IO.spawn(Unit, Install.go(Cfg.home(cfg), inbox))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{+st, f, ls, cl, as, +inbox, +cfg, note} B.GrokTurn{+thread, +cwd, +model, +session, r, +text}:
      do IO<Hub>:
        fs : K.Files <- K.Files.read(cwd)
        +now : Nat <- Now.nat()
        IO.spawn(Unit, Grok.go(cfg, st, thread, cwd, model, session, r, BH.Bots.turn(st, now, thread, text), fs, inbox))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{+st, f, ls, cl, as, +inbox, +cfg, note} B.TurnEnded{+thread, +state}:
      do IO<Hub>:
        IO.spawn(Unit, Hub.phone(Cfg.home(cfg), st, thread, state, inbox))
        ok : Bool <- Chan.send(Msg, inbox, Rpc{0, BH.Reply.request(thread, state)})
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{st, f, ls, cl, as, +inbox, cfg, note} B.Fs{+client, +id, +op, +path}:
      do IO<Hub>:
        IO.spawn(Unit, FsJob.run(op, inbox, client, id, path))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{st, f, ls, cl, as, inbox, +cfg, note} B.TermOp{+op, +thread, +cwd, data, +cols, +rows}:
      do IO<Hub>:
        Term.put(Cfg.tm(cfg), Term.msg(op, thread, cwd, data, cols, rows))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{+st, f, ls, cl, as, +inbox, +cfg, note} B.Git{+client, +id, +job, +thread, +cwd, +a, +b}:
      do IO<Hub>:
        +now : Nat <- Now.nat()
        Media.run(AG.Text.of(st), job, inbox, client, id, thread, cwd, Bot.attach(String.eq(job, "attach.claude"), st, now, thread, a), b, Cfg.home(cfg))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{st, f, ls, cl, as, inbox, +cfg, note} B.AskAnswered{+ask, +answer}:
      do IO<Hub>:
        Park.put(Cfg.pk(cfg), PK.PAnswer{ask, answer})
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{+st, f, ls, cl, as, +inbox, +cfg, note} B.Upgrade{}:
      do IO<Hub>:
        IO.spawn(Unit, Upgrade.go(Cfg.home(cfg), M.Setting.get(st, "update.channel", "stable"), inbox))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case Hub{+st, f, ls, cl, as, +inbox, +cfg, note} B.BotFx{+kind, +a, +b, +c}:
      do IO<Hub>:
        Bot.fx(C.Codec.pos(["home", "gone", "hook", "unhook", "send", "invite", "join", "unpeer", "google", "token", "retoken", "untoken", "voice"], kind), st, inbox, cfg, a, b, c)
        return Hub{st, f, ls, cl, as, inbox, cfg, note}

def Hub.outs(os: List<&2, B.Out>, h: Hub) -> IO(Hub):
  match os:
    case Nil{}:
      IO.pure(Hub, h)
    case o <> t:
      IO.bind(Hub, Hub, Hub.out(h, o), h2 => Hub.outs(t, h2))

def Hub.step.k(p: M.State & Hub, cs: List<&2, M.Change>, os: List<&2, B.Out>) -> IO(Hub):
  (st, h) = p
  do IO<Hub>:
    r : Hub & List<&2, String> <- Hub.commit(B.Pend.fix(st, cs), h, Nil{})
    h2 : Hub <- Hub.announce(r)
    Hub.outs(os, h2)

# a step's changes are stored (with the pending counts they move), then
# its effects run
def Hub.step(h: Hub, s: B.Step) -> IO(Hub):
  match s:
    case B.Step{cs, os}:
      Hub.step.k(Hub.state(h), cs, os)

def Hub.rpc.k(p: M.State & Hub, +client: U32, +text: String, +now: Nat) -> IO(Hub):
  (st, h) = p
  Hub.step(h, Bot.request(J.Json.parse(text), st, now, client, text))

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

# each minute the hub's size goes into the gauges
def Hub.tick(h: Hub, +now: Nat) -> IO(Hub):
  match h:
    case Hub{+st, f, +ls, +cl, +as, inbox, cfg, note}:
      do IO<Hub>:
        PS.Perf.set("hub.clients", U32.from_nat(List.length(&2, Client, cl)))
        PS.Perf.set("hub.agents", U32.from_nat(List.length(&2, Agent, as)))
        PS.Perf.set("hub.changes", U32.from_nat(List.length(&2, String, ls)))
        Hub.step(Hub{st, f, ls, cl, as, inbox, cfg, note}, B.Hub.tick(st, now))

def Hub.mcp.k(o: MC.McpOut, h: Hub, +reply: Chan(String), +body: String) -> IO(Hub):
  match o h:
    case MC.McpOut{+text, st, +park} Hub{hs, f, ls, cl, as, inbox, +cfg, note}:
      do IO<Hub>:
        Hub.mcp.send(Bool.not(String.is_empty(park)), park, body, text, reply, cfg)
        Hub.step(Hub{hs, f, ls, cl, as, inbox, cfg, note}, st)

def Hub.mcp.hub(h: Hub, +thread: String, +body: String, +reply: Chan(String), +now: Nat) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, inbox, +cfg, note}:
      Hub.mcp.k(BH.Bots.mcp(st, now, thread, Maybe.default(&2, J.Json, J.Json.parse(Cfg.models(cfg)), J.Null{}), Cfg.version(cfg),
          Maybe.default(&2, J.Json, J.Json.parse(BN.Bn.dir(Cfg.bn(cfg))), J.Json.arr(Nil{})), GG.Google.tool_defs(), body),
        Hub{st, f, ls, cl, as, inbox, cfg, note}, reply, body)

def Hub.mcp.w(secs: Nat, h: Hub, +thread: String, +o: J.Json, body: String, +reply: Chan(String), +now: Nat) -> IO(Hub):
  match secs h:
    case 0n _:
      Hub.mcp.hub(h, thread, body, reply, now)
    case 1n+k Hub{st, f, ls, cl, as, +inbox, cfg, note}:
      do IO<Hub>:
        IO.spawn(Unit, Wait.loop(1n+k, thread, MC.Wait.now(o), reply, inbox))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}

# a line from an agent: a turn process's only while it is the one the hub
# runs for its thread (B.Tag.heard)
def Hub.tagged.k(heard: Bool, h: Hub, +thread: String, line: String, +now: Nat) -> IO(Hub):
  match heard:
    case True{}:
      Hub.line(h, thread, line, now)
    case False{}:
      IO.pure(Hub, h)

def Hub.tagged(h: Hub, +tag: String, line: String, +now: Nat) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, +as, inbox, cfg, note}:
      Hub.tagged.k(B.Tag.heard(B.Tag.pid(tag), Agent.pid_of(Agents.get(as, B.Tag.thread(tag)))), Hub{st, f, ls, cl, as, inbox, cfg, note}, B.Tag.thread(tag), line, now)

def Hub.recover(h: Hub, +now: Nat) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.step(Hub{st, f, ls, cl, as, inbox, cfg, note}, B.Hub.recover(st, now))

# The minute
# ----------

def Bot.dir.job(ps: List<&2, BO.Peer>, +home: String, +now: Nat, +prev: String, +inbox: Chan(Msg)) -> IO(Unit):
  IO.bind(String, Unit, BN.Bn.dir.fetch(ps, home, now, prev), d => IO.bind(Bool, Unit, Chan.send(Msg, inbox, BotsFound{d}), ok => IO.pure(Unit, Unit{})))

# routines that are due run, and the linked machines are asked for their bots
def Hub.bot_tick(h: Hub, +tz: String, +now: Nat) -> IO(Hub):
  match h:
    case Hub{+st, f, ls, cl, as, +inbox, +cfg, note}:
      do IO<Hub>:
        IO.spawn(Unit, Bot.dir.job(BO.World.peers(M.State.bots(st)), Cfg.home(cfg), now, BN.Bn.dir(Cfg.bn(cfg)), inbox))
        Hub.step(Hub{st, f, ls, cl, as, inbox, cfg, note}, BH.Bots.tick(st, now, BH.Tz{M.Snooze.tz.secs(tz), M.Snooze.tz.east(tz)}))

def Hub.bots_found.k(same: Bool, h: Hub, d: String) -> IO(Hub):
  match same h:
    case True{} _:
      IO.pure(Hub, h)
    case False{} Hub{st, f, ls, cl, as, inbox, +cfg, note}:
      Hub.models.k(Hub{st, f, ls, cl, as, inbox, Cfg.with_bn(cfg, BN.Bn.with_dir(Cfg.bn(cfg), d)), note})

# the linked machines' bots changed: every client hears (info "bots.remote")
def Hub.bots_found(h: Hub, +d: String) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, as, inbox, +cfg, note}:
      Hub.bots_found.k(String.eq(BN.Bn.dir(Cfg.bn(cfg)), d), Hub{st, f, ls, cl, as, inbox, cfg, note}, d)

# Requests from outside
# ---------------------
# A webhook (POST /hook/<id>) or a linked machine (POST /bots/deliver,
# POST /bots/link, GET /bots/dir) is checked off the hub: its secret read,
# its signature compared (Sign.check: fresh, constant time). Back on the
# hub the replay cache accepts its key once, and only then does anything
# change. A bot's screen (GET /bots/<id>/screen.jpg) and Google's redirect
# (GET /oauth/google) come from clients the server already lets in.

def Bot.cap() -> Nat:
  262144n

# a form may carry a recording (a Pebble ring's voice note, M4A): 2 MB,
# a few minutes of it
def Bot.cap.form() -> Nat:
  2097152n

def Bot.cap.of(+ct: String) -> Nat:
  Bool.pick(Nat, RG.Ring.is_form(ct), Bot.cap.form(), Bot.cap())

def Bot.answer(+reply: Chan(List<&2, U32>), bs: List<&2, U32>) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(List<&2, U32>, reply, bs)
    return Unit{}

def Hub.answer(h: Hub, +reply: Chan(List<&2, U32>), bs: List<&2, U32>) -> IO(Hub):
  do IO<Hub>:
    Bot.answer(reply, bs)
    return h

def Bot.json(+status: String, +text: String) -> List<&2, U32>:
  W.Http.response(status, "application/json", U.Utf8.encode(text), "")

def Bot.shot.sent(bs: List<&2, U32>, +reply: Chan(List<&2, U32>)) -> IO(Unit):
  match bs:
    case Nil{}:
      Bot.answer(reply, W.Http.text("404 Not Found", "no screen yet"))
    case b <> t:
      Bot.answer(reply, W.Http.response.c("200 OK", "image/jpeg", b <> t, "no-store", ""))

# a bot's newest browser frame, as the helper wrote it
def Bot.shot(+home: String, +bot: String, +reply: Chan(List<&2, U32>)) -> IO(Unit):
  Bool.pick(IO(Unit), String.is_empty(bot), Bot.answer(reply, W.Http.text("404 Not Found", "no such bot")),
    IO.bind(List<&2, U32>, Unit, Files.read(BR.Br.shot_file(home, bot)), bs => Bot.shot.sent(bs, reply)))

def Bot.oauth.page(+text: String) -> String:
  GG.Google.page(Bool.pick(String, String.starts_with(text, "error"), text, "Google is connected to Backplane. You can close this tab."))

# Google sent the browser back with a code: finish signing in
def Bot.oauth(+home: String, +port: U32, +path: String, +reply: Chan(List<&2, U32>)) -> IO(Unit):
  IO.bind(String, Unit, GS.Google.finish(home, path, Bot.redirect(port)),
    t => Bot.answer(reply, W.Http.response("200 OK", "text/html; charset=utf-8", U.Utf8.encode(Bot.oauth.page(t)), "")))

def Bot.me(+link: Bool) -> IO(String):
  Bool.pick(IO(String), link, BN.Bn.name(), IO.pure(String, ""))

# the secret of the hook or the peer, the signature against it, and the
# replay key (or "") back to the hub
def Bot.refuse(+id: String, +key: String, body: String, +reply: Chan(List<&2, U32>), +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(Msg, inbox, BotVerified{"hook", id, key, body, "", reply})
    return Unit{}

# a form (the Pebble Index ring's) becomes a JSON object; any other body
# goes as it came. Only a call let in is read.
def Bot.bearer.body(form: Bool, +body: String, +size: String) -> String:
  match form:
    case True{}:
      RG.Ring.form(body, size)
    case False{}:
      body

# A ring's recording, let in, is heard here before the bot gets the form
# (VO.Vo.ring: GPT-Live-Transcribe with the dictionary): the phone gets its
# 202 at once, and the form, with the words heard, goes on when they are
# (the hub's own answer then goes nowhere). A form under a bearer token
# becomes JSON as usual.
def Bot.heard(+home: String, +kind: String, +id: String, +key: String, +ct: String, +body: String, raw: List<&2, U32>, +me: String, form: Bool, +size: String,
    +reply: Chan(List<&2, U32>), +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    Bot.answer(reply, W.Http.text("202 Accepted", "accepted"))
    +nonce : String <- BN.Bn.random(6n)
    +heard : String <- VO.Vo.ring(home, nonce, ct, body, raw)
    +none : Chan(List<&2, U32>) <- Chan.new(List<&2, U32>, 1)
    ok : Bool <- Chan.send(Msg, inbox, BotVerified{kind, id, key, Bot.bearer.body(form, heard, size), me, none})
    return Unit{}

def Bot.verify.go(heard: Bool, +home: String, +kind: String, +id: String, +key: String, +ct: String, +body: String, raw: List<&2, U32>, +me: String,
    +reply: Chan(List<&2, U32>), +inbox: Chan(Msg)) -> IO(Unit):
  match heard:
    case True{}:
      Bot.heard(home, kind, id, key, ct, body, raw, me, False{}, "", reply, inbox)
    case False{}:
      do IO<Unit>:
        ok : Bool <- Chan.send(Msg, inbox, BotVerified{kind, id, key, body, me, reply})
        return Unit{}

# the replay key: a form with a recording is checked over its bytes (the
# ring signs those; the recording is not text)
def Bot.verify.key(text: Bool, +hook: Bool, +secret: String, +now: Nat, +key: String, +ts: String, +sig: String, +gh: String, +dl: String, +body: String,
    raw: List<&2, U32>) -> String:
  match text:
    case True{}:
      BN.Bn.check(hook, secret, now, key, ts, sig, gh, dl, body)
    case False{}:
      BN.Bn.check.raw(secret, now, key, gh, raw)

# the secret of the hook or the peer, the signature against it, and the
# replay key (or "") back to the hub
def Bot.verify(+hook: Bool, +home: String, +kind: String, +id: String, +ts: String, +sig: String, +gh: String, +dl: String, +body: String,
    +ct: String, +raw: List<&2, U32>, +reply: Chan(List<&2, U32>), +now: Nat, +inbox: Chan(Msg)) -> IO(Unit):
  do IO<Unit>:
    +secret : String <- BN.Bn.secret.of(hook, home, id)
    +me : String <- Bot.me(String.eq(kind, "link"))
    +key : String = Bot.verify.key(List.is_empty(&2, U32, raw), hook, secret, now, kind ++ ":" ++ id, ts, sig, gh, dl, body, raw)
    Bot.verify.go(Bool.and(Bool.not(List.is_empty(&2, U32, raw)), Bool.not(String.is_empty(key))), home, kind, id, key, ct, body, raw,
      Bool.pick(String, String.contains(key, ":i:"), "ring", me), reply, inbox)

def Bot.bearer.go(heard: Bool, form: Bool, +home: String, +key: String, +ct: String, +size: String, +id: String, +body: String, raw: List<&2, U32>,
    +reply: Chan(List<&2, U32>), +inbox: Chan(Msg)) -> IO(Unit):
  match heard:
    case True{}:
      Bot.heard(home, "hook", id, key, ct, body, raw, "", True{}, size, reply, inbox)
    case False{}:
      Bot.refuse(id, key, Bot.bearer.body(form, body, size), reply, inbox)

def Bot.bearer.k(+home: String, +key: String, +ct: String, +size: String, +id: String, +body: String, +raw: List<&2, U32>,
    +reply: Chan(List<&2, U32>), +inbox: Chan(Msg)) -> IO(Unit):
  Bot.bearer.go(Bool.and(Bool.and(Bool.not(BN.Bn.refused(key)), RG.Ring.is_form(ct)), Bool.not(List.is_empty(&2, U32, raw))),
    Bool.and(Bool.not(BN.Bn.refused(key)), RG.Ring.is_form(ct)), home, key, ct, size, id, body, raw, reply, inbox)

# a webhook called with a bearer token (packed by Bot.gh as
# "bearer\n<token>\n<content type>\n<X-Audio-Size>"): the token compared
# with the hook's own off the hub
def Bot.bearer(fs: List<&2, String>, +home: String, +id: String, +body: String, +full: String, +raw: List<&2, U32>, +reply: Chan(List<&2, U32>), +now: Nat, +inbox: Chan(Msg)) -> IO(Unit):
  match fs:
    case _ <> +tok <> +ct <> +size <> _:
      do IO<Unit>:
        +kept : String <- BN.Bn.token.of(home, id)
        +nonce : String <- BN.Bn.random(2n)
        Bot.bearer.k(home, BN.Bn.bearer(kept, tok, "hook:" ++ id, Nat.show(now) ++ "." ++ nonce), Bool.pick(String, String.is_empty(full), ct, full), size, id, body, raw, reply, inbox)
    case _:
      Bot.refuse(id, "!bearer", body, reply, inbox)

# how a webhook call proves itself: 0 not at all, 1 a bearer token, 2 a
# signature (ours, GitHub's, the ring's). A signature wins over a token.
def Bot.hook.how(+sig: String, +gh: String) -> Nat:
  Bool.pick(Nat, Bool.not(String.is_empty(sig)), 2n,
    Bool.pick(Nat, String.starts_with(gh, "bearer\n"), 1n, Bool.pick(Nat, String.is_empty(gh), 0n, 2n)))

def Bot.hook.in(i: Nat, +home: String, +id: String, +ts: String, +sig: String, +gh: String, +dl: String, +body: String, +ct: String, +raw: List<&2, U32>,
    +reply: Chan(List<&2, U32>), +now: Nat, +inbox: Chan(Msg)) -> IO(Unit):
  match i:
    case 0n:
      Bot.refuse(id, "!none", body, reply, inbox)
    case 1n:
      Bot.bearer(String.split(gh, '\n'), home, id, body, ct, raw, reply, now, inbox)
    case _:
      Bot.verify(True{}, home, "hook", id, ts, sig, gh, dl, body, ct, raw, reply, now, inbox)

def Bot.http.job(i: Nat, +home: String, +port: U32, +kind: String, +arg: String, +peer: String, +ts: String, +sig: String, +gh: String, +dl: String,
    +body: String, +ct: String, +raw: List<&2, U32>, +reply: Chan(List<&2, U32>), +now: Nat, +inbox: Chan(Msg)) -> IO(Unit):
  match i:
    case 0n:
      Bot.shot(home, arg, reply)
    case 1n:
      Bot.oauth(home, port, arg, reply)
    case 2n:
      Bot.hook.in(Bot.hook.how(sig, gh), home, arg, ts, sig, gh, dl, body, ct, raw, reply, now, inbox)
    case _:
      Bot.verify(False{}, home, kind, peer, ts, sig, gh, dl, body, "", Nil{}, reply, now, inbox)

def Hub.bot_http(h: Hub, +kind: String, +arg: String, +peer: String, +ts: String, +sig: String, +gh: String, +dl: String, +body: String,
    +ct: String, +raw: List<&2, U32>, +reply: Chan(List<&2, U32>), +now: Nat) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, as, +inbox, +cfg, note}:
      do IO<Hub>:
        IO.spawn(Unit, Bot.http.job(C.Codec.pos(["shot", "oauth", "hook"], kind), Cfg.home(cfg), Cfg.port(cfg), kind, arg, peer, ts, sig, gh, dl, body, ct, raw, reply, now, inbox))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}

def Bot.hook.live.k(hk: BO.Hook, +st: M.State) -> Bool:
  match hk:
    case BO.Hook{_, +bot, _, _, revoked, _, _}:
      Bool.and(Bool.not(revoked), BH.Bots.live(st, bot))

def Bot.hook.live(+st: M.State, +id: String) -> Bool:
  Bot.hook.live.k(BO.World.hook(M.State.bots(st), id), st)

# a ring's voice note reaches the bot as the person's words (Bots.ring);
# any other webhook's body as untrusted data (Bots.hooked)
def Bot.hook.step(ring: Bool, +st: M.State, +now: Nat, +hook: String, +body: String) -> B.Step:
  match ring:
    case True{}:
      BH.Bots.ring(st, now, hook, body)
    case False{}:
      BH.Bots.hooked(st, now, hook, body)

def Hub.bot.hook(live: Bool, h: Hub, +hook: String, +body: String, ring: Bool, +reply: Chan(List<&2, U32>), +now: Nat) -> IO(Hub):
  match live h:
    case True{} Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      do IO<Hub>:
        Bot.answer(reply, W.Http.text("202 Accepted", "accepted"))
        Hub.step(Hub{st, f, ls, cl, as, inbox, cfg, note}, Bot.hook.step(ring, st, now, hook, body))
    case False{} _:
      Hub.answer(h, reply, W.Http.text("401 Unauthorized", "no such webhook"))

def Hub.bot.deliver(live: Bool, m: Maybe<&2, J.Json>, h: Hub, +peer: String, +reply: Chan(List<&2, U32>), +now: Nat) -> IO(Hub):
  match live m h:
    case True{} Some{+o} Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      do IO<Hub>:
        Bot.answer(reply, Bot.json("200 OK", "{\"ok\":true}"))
        Hub.step(Hub{st, f, ls, cl, as, inbox, cfg, note}, BH.Bots.incoming(st, now, Bot.peer.name(st, peer), o))
    case True{} None{} _:
      Hub.answer(h, reply, W.Http.text("400 Bad Request", "not JSON"))
    case False{} _ _:
      Hub.answer(h, reply, W.Http.text("401 Unauthorized", "not a linked machine"))

def Hub.bot.link.k(ok: Bool, h: Hub, +url: String, +name: String, +peer: String, +me: String, +reply: Chan(List<&2, U32>), +now: Nat) -> IO(Hub):
  match ok:
    case True{}:
      do IO<Hub>:
        Bot.answer(reply, Bot.json("200 OK", J.Json.show(J.Json.obj([J.KV{"name", J.Str{me}}]))))
        Hub.step(h, B.Step{[M.PeerSet{peer, Bool.pick(String, String.is_empty(name), peer, name), url, False{}, now}], Nil{}})
    case False{}:
      Hub.answer(h, reply, W.Http.text("400 Bad Request", "no http address"))

# an invite used: the machine that holds it says where it is; once only
def Hub.bot.link(fresh: Bool, m: Maybe<&2, J.Json>, h: Hub, +peer: String, +me: String, +reply: Chan(List<&2, U32>), +now: Nat) -> IO(Hub):
  match fresh m:
    case True{} Some{+o}:
      Hub.bot.link.k(BN.Bn.url.ok(J.Json.get_str(o, "url", "")), h, J.Json.get_str(o, "url", ""), BN.Bn.clean(J.Json.get_str(o, "name", "")), peer, me, reply, now)
    case True{} None{}:
      Hub.answer(h, reply, W.Http.text("400 Bad Request", "not JSON"))
    case False{} _:
      Hub.answer(h, reply, W.Http.text("409 Conflict", "already linked"))

def Hub.bot.dir(live: Bool, h: Hub, +reply: Chan(List<&2, U32>)) -> IO(Hub):
  match live h:
    case True{} Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.answer(Hub{st, f, ls, cl, as, inbox, cfg, note}, reply, Bot.json("200 OK", BN.Bn.mine(st)))
    case False{} _:
      Hub.answer(h, reply, W.Http.text("401 Unauthorized", "not a linked machine"))

def Hub.bot.act(i: Nat, h: Hub, +arg: String, body: String, +me: String, +reply: Chan(List<&2, U32>), +now: Nat) -> IO(Hub):
  match i h:
    case 0n Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.bot.hook(Bot.hook.live(st, arg), Hub{st, f, ls, cl, as, inbox, cfg, note}, arg, body, String.eq(me, "ring"), reply, now)
    case 1n Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.bot.deliver(Bot.peer.live(st, arg), J.Json.parse(body), Hub{st, f, ls, cl, as, inbox, cfg, note}, arg, reply, now)
    case 2n Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.bot.link(Bool.not(Bot.peer.live(st, arg)), J.Json.parse(body), Hub{st, f, ls, cl, as, inbox, cfg, note}, arg, me, reply, now)
    case 3n Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.bot.dir(Bot.peer.live(st, arg), Hub{st, f, ls, cl, as, inbox, cfg, note}, reply)
    case _ _:
      Hub.answer(h, reply, W.Http.text("404 Not Found", "not found"))

def Hub.bot.seen(bad: Bool, m: Maybe<&2, SG.Seen>, h: Hub, +why: String, +kind: String, +arg: String, body: String, +me: String, +reply: Chan(List<&2, U32>), +now: Nat) -> IO(Hub):
  match bad m h:
    case True{} _ _:
      Hub.answer(h, reply, W.Http.text("401 Unauthorized", why))
    case False{} None{} _:
      Hub.answer(h, reply, W.Http.text("401 Unauthorized", "already seen"))
    case False{} Some{s} Hub{st, f, ls, cl, as, inbox, +cfg, note}:
      Hub.bot.act(C.Codec.pos(["hook", "deliver", "link", "dir"], kind), Hub{st, f, ls, cl, as, inbox, Cfg.with_bn(cfg, BN.Bn.with_seen(Cfg.bn(cfg), s)), note},
        arg, body, me, reply, now)

# a signed request (or a webhook's bearer token), checked: genuine (key),
# not seen before, then acted on; a refusal says why
def Hub.bot_verified(h: Hub, +kind: String, +arg: String, +key: String, body: String, +me: String, +reply: Chan(List<&2, U32>), +now: Nat) -> IO(Hub):
  match h:
    case Hub{st, f, ls, cl, as, inbox, +cfg, note}:
      Hub.bot.seen(BN.Bn.refused(key), BN.Bn.accept(Cfg.bn(cfg), key, now), Hub{st, f, ls, cl, as, inbox, cfg, note}, BN.Bn.denied(key), kind, arg, body, me, reply, now)

# Connections for bots' routes
# ----------------------------

type BotReq is Data:
  BotReq{kind: String, arg: String, peer: String, ts: String, sig: String, gh: String, delivery: String}

def Conn.bot.kind.k(+post: Bool, +get: Bool, +r: String) -> Nat:
  Bool.pick(Nat, Bool.and(post, String.starts_with(r, "/hook/")), 1n,
    Bool.pick(Nat, Bool.and(post, String.eq(r, "/bots/deliver")), 2n,
      Bool.pick(Nat, Bool.and(post, String.eq(r, "/bots/link")), 3n,
        Bool.pick(Nat, Bool.and(get, String.eq(r, "/bots/dir")), 4n,
          Bool.pick(Nat, Bool.and(get, Bool.and(String.starts_with(r, "/bots/"), String.ends_with(r, "/screen.jpg"))), 5n,
            Bool.pick(Nat, Bool.and(get, String.eq(r, "/oauth/google")), 6n, 0n))))))

# which bots' route a request is (0: none)
def Conn.bot.kind(req: W.Request) -> Nat:
  match req:
    case W.Request{+m, +p, _}:
      Conn.bot.kind.k(String.eq(m, "POST"), String.eq(m, "GET"), W.Http.route(p))

# /bots/<id>/screen.jpg: the id ("" when it is not a plain id)
def Conn.bot.shot_id(+r: String) -> String:
  Bool.pick(String, BN.Bn.safe(String.take(String.drop(r, 6n), Nat.sub(String.length(r), 17n))), String.take(String.drop(r, 6n), Nat.sub(String.length(r), 17n)), "")

def Conn.bot.answer(m: Maybe<&1, List<&2, U32>>, s: Socket) -> IO(Unit):
  match m:
    case Some{bs}:
      Conn.finish(s, bs)
    case None{}:
      Conn.finish(s, W.Http.text("503 Service Unavailable", "the hub is gone"))

# the hub answers the whole response on a channel made for this request
def Conn.bot.ask(s: Socket, rq: BotReq, body: String, +ct: String, raw: List<&2, U32>, +inbox: Chan(Msg)) -> IO(Unit):
  match rq:
    case BotReq{k, a, p, t, sg, g, d}:
      do IO<Unit>:
        +reply : Chan(List<&2, U32>) <- Chan.new(List<&2, U32>, 1)
        ok : Bool <- Chan.send(Msg, inbox, BotHttp{k, a, p, t, sg, g, d, body, ct, raw, reply})
        m : Maybe<&1, List<&2, U32>> <- Chan.recv(List<&2, U32>, reply)
        Conn.bot.answer(m, s)

# the body as text, and its bytes too when it is a form with a recording
def Conn.bot.bytes(s: Socket, +rq: BotReq, +bs: List<&2, U32>, +text: String, +ct: String, +inbox: Chan(Msg)) -> IO(Unit):
  Conn.bot.ask(s, rq, text, ct, Bool.pick(List<&2, U32>, Bool.and(RG.Ring.is_form(ct), String.contains(text, "name=\"audio\"")), bs, Nil{}), inbox)

def Conn.bot.body.k(full: Bool, s: Socket, +buf: List<&2, U32>, +len: Nat, +rq: BotReq, +ct: String, +inbox: Chan(Msg), k: Socket -> List<&2, U32> -> IO(Unit)) -> IO(Unit):
  match full:
    case True{}:
      Conn.bot.bytes(s, rq, List.take(&2, U32, buf, len), U.Utf8.decode(List.take(&2, U32, buf, len)), ct, inbox)
    case False{}:
      IO.bind(Socket & Result<&1, &1, U32 & String, List<&2, U32>>, Unit, H.Sock.recv_bytes(s, 65536), r => Mcp.got(r, buf, k))

# read the body (Content-Length bytes, capped before reading)
def Conn.bot.body(fuel: Nat, s: Socket, +buf: List<&2, U32>, +len: Nat, +rq: BotReq, +ct: String, +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      Conn.finish(s, W.Http.text("408 Request Timeout", "the body did not arrive"))
    case 1n+f:
      Conn.bot.body.k(Nat.is_ge(List.length(&2, U32, buf), len), s, buf, len, rq, ct, inbox, s2 => b2 => Conn.bot.body(f, s2, b2, len, rq, ct, inbox))

def Conn.bot.signed.k(ok: Bool, big: Bool, s: Socket, rest: List<&2, U32>, +len: Nat, +rq: BotReq, +ct: String, +inbox: Chan(Msg)) -> IO(Unit):
  match ok big:
    case False{} _:
      Conn.finish(s, W.Http.text("401 Unauthorized", "unknown sender"))
    case True{} True{}:
      Conn.finish(s, W.Http.text("413 Payload Too Large", "at most 256 KB, or 2 MB for a form"))
    case True{} False{}:
      Conn.bot.body(4096n, s, rest, len, rq, ct, inbox)

def Conn.bot.len(+hs: List<&2, W.Header>) -> Nat:
  Maybe.default(&2, Nat, Nat.read(W.Http.header_of(hs, "content-length")), 0n)

def Bot.bearer.of(+auth: String) -> String:
  Bool.pick(String, Bool.or(String.starts_with(auth, "Bearer "), String.starts_with(auth, "bearer ")), String.trim(String.drop(auth, 7n)), "")

# Authorization: Bearer <token>, with what reading the body needs, packed
# after "bearer\n" ("" when there is no token)
def Bot.gh.bearer(+tok: String, +hs: List<&2, W.Header>) -> String:
  Bool.pick(String, String.is_empty(tok), "",
    "bearer\n" ++ tok ++ "\n" ++ W.Http.header_of(hs, "content-type") ++ "\n" ++ W.Http.header_of(hs, "x-audio-size"))

def Bot.gh.hub(+g: String, +hs: List<&2, W.Header>) -> String:
  Bool.pick(String, String.is_empty(g), Bot.gh.bearer(Bot.bearer.of(W.Http.header_of(hs, "authorization")), hs), g)

# a third party's signature: the Pebble Index ring's (its X-Index-*
# headers, packed after "index\n" for BN.Bn.check), else GitHub's, else a
# bearer token
def Bot.gh.k(ring: Bool, +hs: List<&2, W.Header>) -> String:
  match ring:
    case True{}:
      "index\n" ++ String.join([W.Http.header_of(hs, "x-index-webhook-version"), W.Http.header_of(hs, "x-index-timestamp"),
        W.Http.header_of(hs, "x-index-delivery"), W.Http.header_of(hs, "x-index-trigger"), W.Http.header_of(hs, "x-index-test"),
        W.Http.header_of(hs, "x-index-signature")], "\n")
    case False{}:
      Bot.gh.hub(W.Http.header_of(hs, "x-hub-signature-256"), hs)

def Bot.gh(+hs: List<&2, W.Header>) -> String:
  Bot.gh.k(Bool.not(String.is_empty(W.Http.header_of(hs, "x-index-signature"))), hs)

# a signed request (no token: webhooks come from outside; peers sign)
def Conn.bot.signed(+kind: String, +arg: String, s: Socket, +hs: List<&2, W.Header>, rest: List<&2, U32>, +inbox: Chan(Msg)) -> IO(Unit):
  Conn.bot.signed.k(BN.Bn.safe(arg), Nat.is_gt(Conn.bot.len(hs), Bot.cap.of(W.Http.header_of(hs, "content-type"))), s, rest, Conn.bot.len(hs),
    BotReq{kind, arg, W.Http.header_of(hs, "x-backplane-peer"), W.Http.header_of(hs, "x-backplane-timestamp"), W.Http.header_of(hs, "x-backplane-signature"),
      Bot.gh(hs), W.Http.header_of(hs, "x-github-delivery")}, W.Http.header_of(hs, "content-type"), inbox)

# a client's own route (a bot's screen, Google's redirect): the same
# authorisation as the websocket's
def Conn.bot.own(ok: Bool, s: Socket, rq: BotReq, +inbox: Chan(Msg)) -> IO(Unit):
  match ok:
    case True{}:
      Conn.bot.ask(s, rq, "", "", Nil{}, inbox)
    case False{}:
      Conn.finish(s, W.Http.text("401 Unauthorized", "this Backplane needs its pairing token"))

def Conn.route.bot(k: Nat, s: Socket, +req: W.Request, rest: List<&2, U32>, +web: String, +id: U32, +inbox: Chan(Msg), +trusted: Bool, +token: String) -> IO(Unit):
  match k req:
    case 1n W.Request{_, +p, +hs}:
      Conn.bot.signed("hook", String.drop(W.Http.route(p), 6n), s, hs, rest, inbox)
    case 2n W.Request{_, _, +hs}:
      Conn.bot.signed("deliver", W.Http.header_of(hs, "x-backplane-peer"), s, hs, rest, inbox)
    case 3n W.Request{_, _, +hs}:
      Conn.bot.signed("link", W.Http.header_of(hs, "x-backplane-peer"), s, hs, rest, inbox)
    case 4n W.Request{_, _, +hs}:
      Conn.bot.signed("dir", W.Http.header_of(hs, "x-backplane-peer"), s, hs, rest, inbox)
    case 5n W.Request{_, +p, +hs}:
      Conn.bot.own(Conn.allowed(trusted, hs, p, token), s, BotReq{"shot", Conn.bot.shot_id(W.Http.route(p)), "", "", "", "", ""}, inbox)
    case 6n W.Request{_, +p, +hs}:
      Conn.bot.own(Conn.allowed(trusted, hs, p, token), s, BotReq{"oauth", p, "", "", "", "", ""}, inbox)
    case _ _:
      Conn.route.mcp(Conn.is_mcp(req), s, req, rest, web, id, inbox, trusted, token)

def Conn.route(s: Socket, +req: W.Request, rest: List<&2, U32>, +web: String, +id: U32, +inbox: Chan(Msg), +trusted: Bool, +token: String) -> IO(Unit):
  Conn.route.bot(Conn.bot.kind(req), s, req, rest, web, id, inbox, trusted, token)

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

# a tailnet connection from a device its owner also owns is trusted like
# loopback (Tailscale vouches for it); others still need the token
def Accept.whois(r: Socket & String, +owner: String, +id: U32, +web: String, +inbox: Chan(Msg), +token: String) -> IO(Unit):
  (s, ip) = r
  do IO<Unit>:
    w : P.Ran <- P.Proc.run("tailscale", ["whois", "--json", ip], "/")
    Conn.head(64n, s, Nil{}, web, id, inbox, TN.Tailnet.trusts(owner, TN.Tailnet.login(Tailnet.out(w))), token)

def Accept.trust(ask: Bool, s: Socket, +owner: String, +id: U32, +web: String, +inbox: Chan(Msg), +trusted: Bool, +token: String) -> IO(Unit):
  match ask:
    case True{}:
      IO.bind(Socket & String, Unit, H.Sock.peer(s), r => Accept.whois(r, owner, id, web, inbox, token))
    case False{}:
      Conn.head(64n, s, Nil{}, web, id, inbox, trusted, token)

def Accept.got(r: Listener & Result<&1, &1, U32 & String, Socket>, +id: U32, +web: String, +inbox: Chan(Msg), +trusted: Bool, +token: String, +owner: String, k: Listener -> IO(Unit)) -> IO(Unit):
  (l, res) = r
  match res:
    case Done{s}:
      do IO<Unit>:
        IO.spawn(Unit, Accept.trust(Bool.and(Bool.not(trusted), Bool.not(String.is_empty(owner))), s, owner, id, web, inbox, trusted, token))
        k(l)
    case Fail{_}:
      k(l)

# connections from one listener; ids count up from `id` (loopback from 1,
# the tailnet from 2^31, so they never meet)
def Accept.loop(fuel: Nat, l: Listener, +id: U32, +web: String, +inbox: Chan(Msg), +trusted: Bool, +token: String, +owner: String) -> IO(Unit):
  match fuel:
    case 0n:
      Listener.close(l)
    case 1n+f:
      IO.bind(Listener & Result<&1, &1, U32 & String, Socket>, Unit, TCP.accept(l),
        r => Accept.got(r, id, web, inbox, trusted, token, owner, l2 => Accept.loop(f, l2, (id + 1 : U32), web, inbox, trusted, token, owner)))

def Tailnet.listened(r: Result<&1, &1, U32 & String, Listener>, +ip: String, +port: U32, +web: String, +inbox: Chan(Msg), +token: String) -> IO(Unit):
  match r:
    case Done{l}:
      do IO<Unit>:
        w : P.Ran <- P.Proc.run("tailscale", ["whois", "--json", ip], "/")
        +owner : String = TN.Tailnet.login(Tailnet.out(w))
        IO.print("Backplane on your tailnet: http://" ++ ip ++ ":" ++ U32.show(port) ++ "/ (" ++ Bool.pick(String, String.is_empty(owner), "pairing token " ++ token, owner ++ "'s devices, or pairing token " ++ token) ++ ")")
        IO.spawn(Unit, Accept.loop(Fuel.forever(), l, 2147483648, web, inbox, False{}, token, owner))
    case Fail{_}:
      Log.info("could not listen on the tailnet address " ++ ip)

def Tailnet.listen.k(none: Bool, +ip: String, +port: U32, +web: String, +inbox: Chan(Msg), +token: String) -> IO(Unit):
  match none:
    case True{}:
      Log.info("tailscale is not up (tailscale ip -4 gave nothing)")
    case False{}:
      IO.bind(Result<&1, &1, U32 & String, Listener>, Unit, H.Net.listen(ip, port), r => Tailnet.listened(r, ip, port, web, inbox, token))

# listen on the tailnet address too (clients there need the token), and
# serve HTTPS through `tailscale serve` when asked
def Tailnet.start(n: Net, +port: U32, +web: String, +inbox: Chan(Msg)) -> IO(Unit):
  match n:
    case Net{True{}, https, +token, _, _, _, brx, pkx, tmx, mc, pvx, bnx}:
      do IO<Unit>:
        r : P.Ran <- P.Proc.run("tailscale", ["ip", "-4"], "")
        +ip : String = Tailnet.first(r)
        Tailnet.listen.k(String.is_empty(ip), ip, port, web, inbox, token)
        Tailnet.https(https, port, token)
    case Net{False{}, _, _, _, _, _, brx, pkx, tmx, mc, pvx, bnx}:
      IO.pure(Unit, Unit{})

# Google's tools for bots
# -----------------------
# gmail_search, gmail_read, calendar_events run at once, off the hub;
# gmail_send and calendar_create first open an approval ask (the reply
# waits in the park until the user answers).

def Gg.is(+o: J.Json) -> Bool:
  Bool.and(String.eq(J.Json.get_str(o, "method", ""), "tools/call"),
    Nat.is_lt(C.Codec.pos(["gmail_search", "gmail_read", "gmail_send", "calendar_events", "calendar_create"], J.Json.get_str(J.Json.get_obj(o, "params"), "name", "")), 5n))

def Gg.tool(+o: J.Json) -> String:
  J.Json.get_str(J.Json.get_obj(o, "params"), "name", "")

def Gg.args(+o: J.Json) -> J.Json:
  J.Json.get_obj(J.Json.get_obj(o, "params"), "arguments")

def Gg.say(+reply: Chan(String), +id: J.Json, +ok: Bool, text: String) -> IO(Unit):
  do IO<Unit>:
    sent : Bool <- Chan.send(String, reply, MC.Mcp.result(id, J.Json.obj([J.KV{"content", J.Json.arr([J.Json.obj([J.KV{"type", J.Str{"text"}}, J.KV{"text", J.Str{text}}])])},
      J.KV{"isError", J.Flag{Bool.not(ok)}}])))
    return Unit{}

def Gg.said(+t: String, +id: J.Json, +reply: Chan(String)) -> IO(Unit):
  Gg.say(reply, id, Bool.not(String.starts_with(t, "error")), t)

def Gg.call(+home: String, +tool: String, +args: J.Json, +id: J.Json, +reply: Chan(String)) -> IO(Unit):
  IO.bind(String, Unit, GS.Google.call(home, tool, args), t => Gg.said(t, id, reply))

def Gg.wait.k(m: Maybe<&1, String>, +home: String, +tool: String, +args: J.Json, +id: J.Json, +reply: Chan(String)) -> IO(Unit):
  match m:
    case Some{+answer}:
      Bool.pick(IO(Unit), Bool.or(String.eq(answer, "accept"), String.eq(answer, "session")), Gg.call(home, tool, args, id, reply),
        Gg.say(reply, id, False{}, "The user declined this."))
    case None{}:
      IO.pure(Unit, Unit{})

# the user's answer (raw from the park), then the call or a refusal
def Gg.wait(+r2: Chan(String), +home: String, +tool: String, +args: J.Json, +id: J.Json, +reply: Chan(String)) -> IO(Unit):
  IO.bind(Maybe<&1, String>, Unit, Chan.recv(String, r2), m => Gg.wait.k(m, home, tool, args, id, reply))

def Gg.detail.k(send: Bool, +a: J.Json) -> String:
  match send:
    case True{}:
      "To: " ++ J.Json.get_str(a, "to", "") ++ Bool.pick(String, String.is_empty(J.Json.get_str(a, "cc", "")), "", "\nCc: " ++ J.Json.get_str(a, "cc", "")) ++
        "\nSubject: " ++ J.Json.get_str(a, "subject", "") ++ "\n\n" ++ String.take(J.Json.get_str(a, "body", ""), 1500n)
    case False{}:
      J.Json.get_str(a, "summary", "") ++ "\n" ++ J.Json.get_str(a, "start", "") ++ " to " ++ J.Json.get_str(a, "end", "") ++
        Bool.pick(String, List.is_empty(&2, J.Json, J.Json.elems(J.Json.get_obj(a, "attendees"))), "", "\nInvites: " ++ J.Json.show(J.Json.get_obj(a, "attendees")))

# what the user approves: the mail's recipients, subject and text, or the event
def Gg.detail(+o: J.Json) -> String:
  Gg.detail.k(String.eq(Gg.tool(o), "gmail_send"), Gg.args(o))

def Hub.google.k(ask: Bool, h: Hub, +thread: String, +o: J.Json, +reply: Chan(String), +now: Nat) -> IO(Hub):
  match ask h:
    case False{} Hub{st, f, ls, cl, as, inbox, +cfg, note}:
      do IO<Hub>:
        IO.spawn(Unit, Gg.call(Cfg.home(cfg), Gg.tool(o), Gg.args(o), J.Json.get_obj(o, "id"), reply))
        return Hub{st, f, ls, cl, as, inbox, cfg, note}
    case True{} Hub{+st, f, ls, cl, as, inbox, +cfg, note}:
      do IO<Hub>:
        +ask : String = B.Hub.id("q", now, B.Hub.seq(st))
        +r2 : Chan(String) <- Chan.new(String, 1)
        Park.put(Cfg.pk(cfg), PK.PPark{ask, "", r2})
        IO.spawn(Unit, Gg.wait(r2, Cfg.home(cfg), Gg.tool(o), Gg.args(o), J.Json.get_obj(o, "id"), reply))
        Hub.step(Hub{st, f, ls, cl, as, inbox, cfg, note}, B.Step{[M.AskOpened{ask, thread, "approval", Gg.tool(o), Gg.detail(o), "", now}], Nil{}})

def Hub.google(bot: Bool, h: Hub, +thread: String, +o: J.Json, +reply: Chan(String), +now: Nat) -> IO(Hub):
  match bot h:
    case True{} Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.google.k(Bool.and(GG.Google.asks(Gg.tool(o)), Bool.not(MC.Perm.session_ok(M.Asks.all(st), thread, Gg.tool(o)))), Hub{st, f, ls, cl, as, inbox, cfg, note}, thread, o, reply, now)
    case False{} _:
      do IO<Hub>:
        Gg.say(reply, J.Json.get_obj(o, "id"), False{}, "only bots have this tool")
        return h

def Hub.mcp.gg(g: Bool, h: Hub, +thread: String, +o: J.Json, body: String, +reply: Chan(String), +now: Nat) -> IO(Hub):
  match g h:
    case True{} Hub{+st, f, ls, cl, as, inbox, cfg, note}:
      Hub.google(BO.World.is_bot_thread(M.State.bots(st), thread), Hub{st, f, ls, cl, as, inbox, cfg, note}, thread, o, reply, now)
    case False{} _:
      Hub.mcp.w(MC.Wait.secs(o), h, thread, o, body, reply, now)

def Hub.mcp.route(pv: Bool, h: Hub, +thread: String, +o: J.Json, body: String, +reply: Chan(String), +now: Nat) -> IO(Hub):
  match pv:
    case True{}:
      Hub.preview(h, thread, o, reply)
    case False{}:
      Hub.mcp.gg(Gg.is(o), h, thread, o, body, reply, now)

def Hub.mcp(h: Hub, +thread: String, +body: String, +reply: Chan(String), +now: Nat) -> IO(Hub):
  Hub.mcp.route(Preview.is(Maybe.default(&2, J.Json, J.Json.parse(body), J.Null{})), h, thread, Maybe.default(&2, J.Json, J.Json.parse(body), J.Null{}), body, reply, now)

def Msg.kind(m: Msg) -> String:
  match m:
    case AgentWrite{_, _}:
      "agent_write"
    case UpdateCheck{}:
      "update_check"
    case Mcp{_, _, _}:
      "mcp"
    case Announce{_}:
      "announce"
    case Join{_, _, _, _}:
      "join"
    case JoinHere{_, _}:
      "join_here"
    case Leave{_}:
      "leave"
    case Rpc{_, _}:
      "rpc"
    case AgentLine{_, _}:
      "agent_line"
    case AgentGone{_, _, _}:
      "agent_gone"
    case Tick{}:
      "tick"
    case Push{_, _}:
      "push"
    case PushBin{_, _}:
      "push_bin"
    case TermOut{_, _}:
      "term_out"
    case ModelsFound{_, _}:
      "models"
    case MachinesFound{_}:
      "machines"
    case TurnPid{_, _, _}:
      "turn_pid"
    case TurnDone{_}:
      "turn_done"
    case Recover{}:
      "recover"
    case Commit{_}:
      "commit"
    case BotTick{_}:
      "bot_tick"
    case BotsFound{_}:
      "bots_found"
    case BotHttp{_, _, _, _, _, _, _, _, _, _, _}:
      "bot_http"
    case BotVerified{_, _, _, _, _, _}:
      "bot_verified"
    case Shot{_}:
      "shot"

def Hub.handle(h: Hub, m: Msg, +now: Nat) -> IO(Hub):
  match m:
    case AgentWrite{thread, line}:
      Hub.agent_write(h, thread, line)
    case UpdateCheck{}:
      Hub.update_check(h)
    case Mcp{thread, body, reply}:
      Hub.mcp(h, B.Tag.thread(thread), body, reply, now)
    case Announce{text}:
      Hub.note(h, text)
    case Join{client, out, since, origin}:
      Hub.join(h, client, out, since, origin)
    case JoinHere{client, out}:
      Hub.join.here(h, client, out)
    case Leave{client}:
      Hub.leave(h, client)
    case Rpc{client, text}:
      Hub.rpc(h, client, text, now)
    case AgentLine{tag, line}:
      Hub.tagged(h, tag, line, now)
    case TurnPid{thread, pid, input}:
      Hub.turn_pid(h, thread, pid, input)
    case TurnDone{tag}:
      Hub.turn_done(h, tag)
    case Recover{}:
      Hub.recover(h, now)
    case AgentGone{thread, code, pid}:
      Hub.gone(h, thread, code, pid, now)
    case Tick{}:
      Hub.tick(h, now)
    case Push{client, text}:
      Hub.push(h, client, text)
    case PushBin{client, bs}:
      Hub.push.bin(h, client, bs)
    case TermOut{thread, data}:
      Hub.term_out(h, thread, data)
    case ModelsFound{ms, mt}:
      Hub.models(h, ms, mt)
    case MachinesFound{mc}:
      Hub.machines(h, mc)
    case Commit{cs}:
      Hub.step(h, B.Step{cs, Nil{}})
    case BotTick{tz}:
      Hub.bot_tick(h, tz, now)
    case BotsFound{d}:
      Hub.bots_found(h, d)
    case BotHttp{kind, arg, peer, ts, sig, gh, dl, body, ct, raw, reply}:
      Hub.bot_http(h, kind, arg, peer, ts, sig, gh, dl, body, ct, raw, reply, now)
    case BotVerified{kind, arg, key, body, me, reply}:
      Hub.bot_verified(h, kind, arg, key, body, me, reply, now)
    case Shot{text}:
      Hub.broadcast(h, text)

# each message's handling is timed as hub.<kind> (docs/perf.md)
def Hub.got(m: Maybe<&1, Msg>, h: Hub, k: Hub -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{+msg}:
      do IO<Unit>:
        now : Nat <- Now.nat()
        t0 : U32 <- PS.Perf.us()
        h2 : Hub <- Hub.handle(h, msg, now)
        t1 : U32 <- PS.Perf.lap("hub." ++ Msg.kind(msg), t0)
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

# without the web server (its port was taken): hub and ticker only
def Main.headless(h: Hub, +inbox: Chan(Msg), +cfg: Cfg, front: Chan(Msg) -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    IO.spawn(Unit, Ticker.loop(Fuel.forever(), inbox))
    Refresh.start(inbox, cfg)
    IO.spawn(Unit, Hub.loop(Fuel.forever(), h))
    Upgrade.start(inbox)
    front(inbox)

def Main.serve(l: Listener, h: Hub, +web: String, +inbox: Chan(Msg), +cfg: Cfg, front: Chan(Msg) -> IO(Unit)) -> IO(Unit):
  do IO<Unit>:
    IO.spawn(Unit, Accept.loop(Fuel.forever(), l, 1, web, inbox, True{}, Net.token(Cfg.net(cfg)), ""))
    Tailnet.start(Cfg.net(cfg), Cfg.port(cfg), web, inbox)
    IO.spawn(Unit, Ticker.loop(Fuel.forever(), inbox))
    Refresh.start(inbox, cfg)
    Machines.start(inbox, Cfg.port(cfg))
    IO.spawn(Unit, Hub.loop(Fuel.forever(), h))
    Upgrade.start(inbox)
    front(inbox)

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
        Main.headless(h, inbox, cfg, front)

# Browser frames
# --------------

def Shot.fwd.got(m: Maybe<&1, String>, +inbox: Chan(Msg), k: Unit -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{+line}:
      do IO<Unit>:
        ok : Bool <- Chan.send(Msg, inbox, Shot{BR.Browser.shot(line)})
        k(Unit{})
    case None{}:
      IO.pure(Unit, Unit{})

# page-frame events from the browser, to the hub
def Shot.fwd(fuel: Nat, +ev: Chan(String), +inbox: Chan(Msg)) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      IO.bind(Maybe<&1, String>, Unit, Chan.recv(String, ev), m => Shot.fwd.got(m, inbox, u => Shot.fwd(f, ev, inbox)))

def Main.opened(r: Result<&1, &1, U32 & String, File>, st: M.State, ls: List<&2, String>, cfg: Cfg, need: Bool, front: Chan(Msg) -> IO(Unit)) -> IO(Unit):
  match r cfg:
    case Done{f} Cfg{+home, +web, +host, +port, +pr, +ds, +v, nt0}:
      do IO<Unit>:
        +inbox : Chan(Msg) <- Chan.new(Msg, 4096)
        rc : Bool <- Chan.send(Msg, inbox, Recover{})
        +bq : Chan(BR.BMsg) <- Chan.new(BR.BMsg, 256)
        bexe : String <- Browser.exe()
        # page-frame events from the browser, broadcast by the hub as {"t":"shot",...}
        +bev : Chan(String) <- Chan.new(String, 256)
        IO.spawn(Unit, Shot.fwd(Fuel.forever(), bev, inbox))
        IO.spawn(Unit, BR.Browser.loop(Fuel.forever(), bq, bev, BR.Br.at(bexe, home)))
        +pq : Chan(PK.PMsg) <- Chan.new(PK.PMsg, 256)
        IO.spawn(Unit, PK.Park.loop(Fuel.forever(), pq, Nil{}))
        +tq : Chan(TM.TMsg) <- Chan.new(TM.TMsg, 1024)
        +to : Chan(TM.TOut) <- Chan.new(TM.TOut, 4096)
        shell : String <- Env.get("SHELL", "/bin/bash")
        IO.spawn(Unit, TM.Term.loop(Fuel.forever(), tq, Nil{}, shell, to))
        IO.spawn(Unit, Term.fwd(Fuel.forever(), to, inbox))
        +vq : Chan(PV.PMsg) <- Chan.new(PV.PMsg, 1024)
        +vo : Chan(PV.POut) <- Chan.new(PV.POut, 1024)
        IO.spawn(Unit, PV.Pv.loop(Fuel.forever(), vq, PV.Pv.empty(), vo, home ++ "/plot"))
        IO.spawn(Unit, Plot.fwd(Fuel.forever(), vo, inbox))
        +nt : Net = Net.with_pv(Net.with_tm(Net.with_pk(Net.with_br(nt0, bq), pq), tq), vq)
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
        t0 : U32 <- PS.Perf.us()
        bs : List<&2, U32> <- Files.read(Store.path(home))
        t1 : U32 <- PS.Perf.span("boot.read", t0)
        +ld : ST.Loaded = ST.Store.load(Store.lines(bs), ST.Loaded{M.State.empty(), Nil{}})
        +st : M.State = ST.Loaded.st(ld)
        +ls : List<&2, String> = ST.Loaded.wire(ld)
        t2 : U32 <- PS.Perf.span("boot.replay", t1)
        Log.info("replayed " ++ Nat.show(List.length(&2, String, ls)) ++ " changes from " ++ Store.path(home))
        f : Result<&1, &1, U32 & String, File> <- File.open(Store.path(home), "a")
        tok : String <- Token.load(home)
        +mc : String <- Files.text(Models.cache(home))
        Main.opened(f, st, ls, Cfg.with_models(Cfg.with_token(Cfg{home, w, h, p, pr, ds, v, nt}, tok), BT.Cache.json(mc), BT.Cache.text(mc)), need, front)
