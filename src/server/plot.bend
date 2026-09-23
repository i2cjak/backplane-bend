import Base
import ./host.bend as H
import ./kicad.bend as K
import ./proc.bend as PR
import ../core/board.bend as B
import ../core/schematic.bend as SC
import ../core/plot.bend as P

# The phones' viewer. One actor owns every board or schematic a phone
# watches and what each phone holds of it. It polls the files (every
# 150 ms, and only while one is watched), parses a changed one off the
# actor (in parallel, core/plot.bend), and sends each phone watching it the
# delta against what that phone holds: an unchanged file sends nothing.
# Messages leave through `out`; the server hands them to the hub, which
# writes them to the phone's socket.

type PMsg is Data:
  # show a phone the board (kind 0) or schematic (1) of a project, or the
  # file at path when set
  PWatch{client: U32, kind: U32, root: String, path: String}
  PStop{client: U32}
  PPoll{}
  # a file read: its size and mtime then, and its plot (None while it is
  # half written)
  PGot{key: String, sz: U32, mt: U32, plot: Maybe<&2, P.Plot>}

type POut is Data:
  POut{client: U32, text: String}

# a watched file: the size and mtime last read, a countdown to one more
# read after a change (a second save within the same second), whether a
# read is under way, and its latest plot
type Src is Data:
  Src{key: String, kind: U32, path: String, sz: U32, mt: U32, re: Nat, busy: Bool, plot: Maybe<&2, P.Plot>}

# a phone's view: the source it watches and the chunks it holds
type Sub is Data:
  Sub{client: U32, key: String, sent: List<&2, P.Chunk>}

type PSt is Data:
  PSt{srcs: List<&2, Src>, subs: List<&2, Sub>, polling: Bool}

def Pv.fuel() -> Nat:
  U32.to_nat(4294967295)

def Pv.say(+out: Chan(POut), +client: U32, text: String) -> IO(Unit):
  do IO<Unit>:
    ok : Bool <- Chan.send(POut, out, POut{client, text})
    return Unit{}

# Sources
# -------

def Src.key(+kind: U32, +root: String, +path: String) -> String:
  U32.show(kind) ++ "|" ++ root ++ "|" ++ path

def Src.is(s: Src, +key: String) -> Bool:
  match s:
    case Src{k, _, _, _, _, _, _, _}:
      String.eq(k, key)

def Src.has(ss: List<&2, Src>, +key: String) -> Bool:
  match ss:
    case Nil{}:
      False{}
    case +s <> t:
      Bool.or(Src.is(s, key), Src.has(t, key))

def Src.plot.k(hit: Bool, s: Src, rest: Maybe<&2, P.Plot>) -> Maybe<&2, P.Plot>:
  match hit s:
    case True{} Src{_, _, _, _, _, _, _, p}:
      p
    case False{} _:
      rest

# the latest plot of a source, when it has one
def Src.plot(ss: List<&2, Src>, +key: String) -> Maybe<&2, P.Plot>:
  match ss:
    case Nil{}:
      None{}
    case +s <> t:
      Src.plot.k(Src.is(s, key), s, Src.plot(t, key))

def Src.add(has: Bool, +key: String, +kind: U32, +path: String, ss: List<&2, Src>) -> List<&2, Src>:
  match has:
    case True{}:
      ss
    case False{}:
      Src{key, kind, path, 0, 0, 0n, False{}, None{}} <> ss

def Sub.watched(ss: List<&2, Sub>, +key: String) -> Bool:
  match ss:
    case Nil{}:
      False{}
    case Sub{_, +k, _} <> t:
      Bool.or(String.eq(k, key), Sub.watched(t, key))

def Src.keep(keep: Bool, s: Src, rest: List<&2, Src>) -> List<&2, Src>:
  match keep:
    case True{}:
      s <> rest
    case False{}:
      rest

def Src.key.of(s: Src) -> String:
  match s:
    case Src{k, _, _, _, _, _, _, _}:
      k

# the sources some phone still watches
def Src.gc(ss: List<&2, Src>, +subs: List<&2, Sub>) -> List<&2, Src>:
  match ss:
    case Nil{}:
      Nil{}
    case +s <> t:
      Src.keep(Sub.watched(subs, Src.key.of(s)), s, Src.gc(t, subs))

def Sub.keep(drop: Bool, s: Sub, rest: List<&2, Sub>) -> List<&2, Sub>:
  match drop:
    case True{}:
      rest
    case False{}:
      s <> rest

def Sub.client(s: Sub) -> U32:
  match s:
    case Sub{c, _, _}:
      c

# every view but the client's
def Sub.drop(ss: List<&2, Sub>, +client: U32) -> List<&2, Sub>:
  match ss:
    case Nil{}:
      Nil{}
    case +s <> t:
      Sub.keep(U32.is_eq(Sub.client(s), client), s, Sub.drop(t, client))

# Sending
# -------

def Pv.send.k(quiet: Bool, +out: Chan(POut), +client: U32, +key: String, +pl: P.Plot, rs: List<&2, P.Ref>) -> IO(Unit):
  match quiet:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      Pv.say(out, client, P.Plot.msg(key, P.Plot.box(pl), rs))

# a phone's view brought up to a plot: the delta goes out unless it would
# change nothing; the phone now holds the plot's chunks
def Pv.send(s: Sub, +pl: P.Plot, +out: Chan(POut)) -> IO(Sub):
  match s:
    case Sub{+client, +key, +sent}:
      do IO<Sub>:
        +rs : List<&2, P.Ref> = P.Plot.delta(P.Plot.chunks(pl), sent)
        Pv.send.k(P.Plot.quiet(rs, 0n, List.length(&2, P.Chunk, sent)), out, client, key, pl, rs)
        return Sub{client, key, P.Plot.chunks(pl)}

def Pv.send.if(hit: Bool, s: Sub, m: Maybe<&2, P.Plot>, +out: Chan(POut)) -> IO(Sub):
  match hit m:
    case True{} Some{+pl}:
      Pv.send(s, pl, out)
    case _ _:
      IO.pure(Sub, s)

def Sub.is(s: Sub, +key: String) -> Bool:
  match s:
    case Sub{_, k, _}:
      String.eq(k, key)

# every phone watching key, brought up to its plot
def Pv.fan(ss: List<&2, Sub>, +key: String, +m: Maybe<&2, P.Plot>, +out: Chan(POut)) -> IO(List<&2, Sub>):
  match ss:
    case Nil{}:
      IO.pure(List<&2, Sub>, Nil{})
    case +s <> t:
      do IO<List<&2, Sub>>:
        s2 : Sub <- Pv.send.if(Sub.is(s, key), s, m, out)
        t2 : List<&2, Sub> <- Pv.fan(t, key, m, out)
        return s2 <> t2

# Reading
# -------

def Pv.parse.k(sch: Bool, bs: List<&2, U32>) -> Maybe<&2, List<&2, B.Item>>:
  match sch:
    case True{}:
      SC.Sch.items(bs)
    case False{}:
      B.Board.items(bs)

def Pv.plot(m: Maybe<&2, List<&2, B.Item>>, +kind: U32) -> Maybe<&2, P.Plot>:
  match m:
    case Some{its}:
      Some{P.Plot.of(its, kind)}
    case None{}:
      None{}

def Pv.stamp.k(v: U32 & U32 & U32) -> U32 & U32:
  (_, sm) = v
  sm

def Pv.stamp(r: Result<&1, &1, U32 & String, U32 & U32 & U32>) -> U32 & U32:
  match r:
    case Done{v}:
      Pv.stamp.k(v)
    case Fail{_}:
      (0, 0)

# The child
# ---------
# `backplane --plot KIND FILE` reads one file and prints its plot as lines
# (Line.plot), exiting 2 while the file is half written. The hub runs one
# per read: each parse starts on a fresh heap (the runtime slows as a long
# process allocates and frees big structures), its memory goes back when
# it exits, and a pathological file cannot stall the hub.

def Pv.child.k(m: Maybe<&2, P.Plot>) -> IO(Unit):
  match m:
    case Some{pl}:
      IO.print(P.Line.plot(pl))
    case None{}:
      IO.die(Unit, 2, "")

def Pv.child(+kind: U32, +path: String) -> IO(Unit):
  do IO<Unit>:
    bs : List<&2, U32> <- K.Io.bytes(path)
    Pv.child.k(Pv.plot(Pv.parse.k(U32.is_eq(kind, 1), bs), kind))

def Pv.args.copy(xs: List<String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      x <> Pv.args.copy(t)

def Pv.args.back(xs: List<&2, String>) -> List<String>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      x <> Pv.args.back(t)

def Pv.main.k(xs: List<&2, String>, go: List<String> -> IO(Unit)) -> IO(Unit):
  match xs:
    case "--plot" <> k <> f <> _:
      Pv.child(Maybe.default(&2, U32, U32.read(k), 0), f)
    case +a:
      go(Pv.args.back(a))

# the program's arguments: a --plot child's, or the program's own (go)
def Pv.main(xs: List<String>, go: List<String> -> IO(Unit)) -> IO(Unit):
  Pv.main.k(Pv.args.copy(xs), go)

def Pv.got.ran(r: PR.Ran, +kind: U32) -> Maybe<&2, P.Plot>:
  match r:
    case PR.Ran{0, out}:
      Some{P.Scan.plot(out)}
    case _:
      None{}

def Pv.read.k(sm: U32 & U32, +r: PR.Ran, +key: String, +kind: U32, +q: Chan(PMsg)) -> IO(Unit):
  (sz, mt) = sm
  do IO<Unit>:
    ok : Bool <- Chan.send(PMsg, q, PGot{key, sz, mt, Pv.got.ran(r, kind)})
    return Unit{}

# read and plot a file in a child process (the stamp is taken first, so a
# save during the read is seen by the next poll)
def Pv.read(+key: String, +kind: U32, +path: String, +q: Chan(PMsg)) -> IO(Unit):
  do IO<Unit>:
    st : Result<&1, &1, U32 & String, U32 & U32 & U32> <- H.FS.stat(path)
    exe : String <- H.Sys.exe_path()
    r : PR.Ran <- PR.Proc.run(exe, ["--plot", U32.show(kind), path], "/")
    Pv.read.k(Pv.stamp(st), r, key, kind, q)

# Polling
# -------

def Pv.poll.go(changed: Bool, re: Nat, s: Src, +q: Chan(PMsg)) -> IO(Src):
  match changed re s:
    case True{} _ Src{+k, +kd, +p, sz, mt, _, _, pl}:
      do IO<Src>:
        IO.spawn(Unit, Pv.read(k, kd, p, q))
        return Src{k, kd, p, sz, mt, 7n, True{}, pl}
    case False{} 1n Src{+k, +kd, +p, sz, mt, _, _, pl}:
      do IO<Src>:
        IO.spawn(Unit, Pv.read(k, kd, p, q))
        return Src{k, kd, p, sz, mt, 0n, True{}, pl}
    case False{} 1n+r Src{k, kd, p, sz, mt, _, b, pl}:
      IO.pure(Src, Src{k, kd, p, sz, mt, r, b, pl})
    case False{} 0n _:
      IO.pure(Src, s)

def Pv.poll.st(sm: U32 & U32, s: Src, +q: Chan(PMsg)) -> IO(Src):
  (+s2, +m2) = sm
  match s:
    case Src{k, kd, p, +sz, +mt, +re, b, pl}:
      Pv.poll.go(Bool.or(U32.is_ne(s2, sz), U32.is_ne(m2, mt)), re, Src{k, kd, p, sz, mt, re, b, pl}, q)

# one source's turn: a changed size or mtime reads it again (not while a
# read is under way)
def Pv.poll.one(busy: Bool, s: Src, +q: Chan(PMsg)) -> IO(Src):
  match busy s:
    case True{} _:
      IO.pure(Src, s)
    case False{} Src{k, kd, +p, sz, mt, re, b, pl}:
      do IO<Src>:
        st : Result<&1, &1, U32 & String, U32 & U32 & U32> <- H.FS.stat(p)
        Pv.poll.st(Pv.stamp(st), Src{k, kd, p, sz, mt, re, b, pl}, q)

def Src.busy(s: Src) -> Bool:
  match s:
    case Src{_, _, _, _, _, _, b, _}:
      b

def Pv.poll(ss: List<&2, Src>, +q: Chan(PMsg)) -> IO(List<&2, Src>):
  match ss:
    case Nil{}:
      IO.pure(List<&2, Src>, Nil{})
    case +s <> t:
      do IO<List<&2, Src>>:
        s2 : Src <- Pv.poll.one(Src.busy(s), s, q)
        t2 : List<&2, Src> <- Pv.poll(t, q)
        return s2 <> t2

def Pv.later(+q: Chan(PMsg)) -> IO(Unit):
  do IO<Unit>:
    IO.sleep(150)
    ok : Bool <- Chan.send(PMsg, q, PPoll{})
    return Unit{}

# the next poll, while anything is watched
def Pv.next(any: Bool, +q: Chan(PMsg)) -> IO(Bool):
  match any:
    case True{}:
      do IO<Bool>:
        IO.spawn(Unit, Pv.later(q))
        return True{}
    case False{}:
      IO.pure(Bool, False{})

# Messages
# --------

def Pv.got.src(hit: Bool, s: Src, +sz: U32, +mt: U32, +m: Maybe<&2, P.Plot>) -> Src:
  match hit s m:
    case True{} Src{k, kd, p, _, _, re, _, _} Some{pl}:
      Src{k, kd, p, sz, mt, re, False{}, Some{pl}}
    case True{} Src{k, kd, p, _, _, re, _, pl} None{}:
      Src{k, kd, p, sz, mt, re, False{}, pl}
    case False{} _ _:
      s

def Pv.got.srcs(ss: List<&2, Src>, +key: String, +sz: U32, +mt: U32, +m: Maybe<&2, P.Plot>) -> List<&2, Src>:
  match ss:
    case Nil{}:
      Nil{}
    case +s <> t:
      Pv.got.src(Src.is(s, key), s, sz, mt, m) <> Pv.got.srcs(t, key, sz, mt, m)

def Pv.start(polling: Bool, +q: Chan(PMsg)) -> IO(Bool):
  match polling:
    case True{}:
      IO.pure(Bool, True{})
    case False{}:
      do IO<Bool>:
        ok : Bool <- Chan.send(PMsg, q, PPoll{})
        return True{}

def Pv.none(+kind: U32) -> String:
  Bool.pick(String, U32.is_eq(kind, 1), "No schematic in this project yet", "No board in this project yet")

def Pv.file.k(f: K.Files, +kind: U32) -> String:
  match f:
    case K.Files{_, pcb, sch}:
      Bool.pick(String, U32.is_eq(kind, 1), sch, pcb)

# the file a phone asked for: the explicit path, else the project's
def Pv.file(+kind: U32, +root: String, +path: String) -> IO(String):
  Bool.pick(IO(String), String.is_empty(path), IO.bind(K.Files, String, K.Files.read(root), f => IO.pure(String, Pv.file.k(f, kind))), IO.pure(String, path))

# a phone's view of a source that has a plot: all of it goes out now
def Pv.watch.now(m: Maybe<&2, P.Plot>, s: Sub, +out: Chan(POut)) -> IO(Sub):
  match m:
    case Some{+pl}:
      Pv.send(s, pl, out)
    case None{}:
      IO.pure(Sub, s)

def Pv.watch.k(none: Bool, st: PSt, +client: U32, +kind: U32, +key: String, +file: String, +q: Chan(PMsg), +out: Chan(POut)) -> IO(PSt):
  match none st:
    case True{} PSt{ss, +subs, polling}:
      do IO<PSt>:
        Pv.say(out, client, P.Plot.none(key, Pv.none(kind)))
        +subs2 : List<&2, Sub> = Sub.drop(subs, client)
        return PSt{Src.gc(ss, subs2), subs2, polling}
    case False{} PSt{+ss, subs, polling}:
      do IO<PSt>:
        +ss2 : List<&2, Src> = Src.add(Src.has(ss, key), key, kind, file, ss)
        sub : Sub <- Pv.watch.now(Src.plot(ss2, key), Sub{client, key, Nil{}}, out)
        +subs2 : List<&2, Sub> = sub <> Sub.drop(subs, client)
        p2 : Bool <- Pv.start(polling, q)
        return PSt{Src.gc(ss2, subs2), subs2, p2}

def Pv.handle(st: PSt, m: PMsg, +q: Chan(PMsg), +out: Chan(POut)) -> IO(PSt):
  match st m:
    case _ PWatch{+client, +kind, +root, +path}:
      do IO<PSt>:
        +file : String <- Pv.file(kind, root, path)
        Pv.watch.k(String.is_empty(file), st, client, kind, Src.key(kind, root, path), file, q, out)
    case PSt{ss, +subs, polling} PStop{+client}:
      do IO<PSt>:
        +subs2 : List<&2, Sub> = Sub.drop(subs, client)
        return PSt{Src.gc(ss, subs2), subs2, polling}
    case PSt{ss, subs, _} PPoll{}:
      do IO<PSt>:
        +ss2 : List<&2, Src> <- Pv.poll(ss, q)
        p2 : Bool <- Pv.next(Bool.not(List.is_empty(&2, Src, ss2)), q)
        return PSt{ss2, subs, p2}
    case PSt{ss, subs, polling} PGot{+key, +sz, +mt, +pl}:
      do IO<PSt>:
        subs2 : List<&2, Sub> <- Pv.fan(subs, key, pl, out)
        return PSt{Pv.got.srcs(ss, key, sz, mt, pl), subs2, polling}

def Pv.got(m: Maybe<&1, PMsg>, st: PSt, +q: Chan(PMsg), +out: Chan(POut), k: PSt -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{msg}:
      IO.bind(PSt, Unit, Pv.handle(st, msg, q, out), k)
    case None{}:
      IO.pure(Unit, Unit{})

def Pv.loop(fuel: Nat, +q: Chan(PMsg), st: PSt, +out: Chan(POut)) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      IO.bind(Maybe<&1, PMsg>, Unit, Chan.recv(PMsg, q), m => Pv.got(m, st, q, out, st2 => Pv.loop(f, q, st2, out)))

def Pv.empty() -> PSt:
  PSt{Nil{}, Nil{}, False{}}
