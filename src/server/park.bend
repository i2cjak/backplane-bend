import Base
import ../core/mcp.bend as MC

# Agent requests waiting on the user: an MCP permission prompt (Claude)
# holds its HTTP reply here until the ask it opened is answered. One actor
# owns the list; answers arrive by ask id, each at most once.

type PMsg is Data:
  PPark{ask: String, body: String, reply: Chan(String)}
  PAnswer{ask: String, answer: String}

type Parked is Data:
  Parked{ask: String, body: String, reply: Chan(String)}

type Taken is Data:
  Taken{hit: Maybe<&2, Parked>, rest: List<&2, Parked>}

def Taken.keep(p: Parked, t: Taken) -> Taken:
  match t:
    case Taken{h, r}:
      Taken{h, p <> r}

def Park.hit(ps: List<&2, Parked>, +ask: String) -> Bool:
  match ps:
    case Parked{a, _, _} <> _:
      String.eq(a, ask)
    case Nil{}:
      False{}

def Park.take(ps: List<&2, Parked>, hit: Bool, +ask: String) -> Taken:
  match ps hit:
    case p <> t True{}:
      Taken{Some{p}, t}
    case p <> +t False{}:
      Taken.keep(p, Park.take(t, Park.hit(t, ask), ask))
    case Nil{} _:
      Taken{None{}, Nil{}}

def Park.send(t: Taken, +answer: String) -> IO(List<&2, Parked>):
  match t:
    case Taken{Some{Parked{_, body, reply}}, rest}:
      do IO<List<&2, Parked>>:
        ok : Bool <- Chan.send(String, reply, MC.Mcp.permission.reply(body, answer))
        return rest
    case Taken{None{}, rest}:
      IO.pure(List<&2, Parked>, rest)

def Park.step(m: Maybe<&1, PMsg>, +ps: List<&2, Parked>, k: List<&2, Parked> -> IO(Unit)) -> IO(Unit):
  match m:
    case Some{PPark{a, b, r}}:
      k(Parked{a, b, r} <> ps)
    case Some{PAnswer{+a, +an}}:
      IO.bind(List<&2, Parked>, Unit, Park.send(Park.take(ps, Park.hit(ps, a), a), an), k)
    case None{}:
      IO.pure(Unit, Unit{})

def Park.loop(fuel: Nat, +q: Chan(PMsg), ps: List<&2, Parked>) -> IO(Unit):
  match fuel:
    case 0n:
      IO.pure(Unit, Unit{})
    case 1n+f:
      IO.bind(Maybe<&1, PMsg>, Unit, Chan.recv(PMsg, q), m => Park.step(m, ps, p2 => Park.loop(f, q, p2)))
