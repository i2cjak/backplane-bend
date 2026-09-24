import Base
import ./json.bend as J
import ./model.bend as M
import ./codec.bend as C

# The event log read at start-up in one pass: each line is parsed once,
# folded into the read model and kept (as clients may see it) for the
# log sent to them. Laws store_state_is_replay (the state is the replay
# of the log's changes) and store_load_append (a log read in two parts
# is the log read whole).

type Loaded is Data:
  Loaded{st: M.State, wire: List<&2, String>}

def Loaded.st(a: Loaded) -> M.State:
  match a:
    case Loaded{st, _}:
      st

# the lines clients may see, newest first
def Loaded.wire(a: Loaded) -> List<&2, String>:
  match a:
    case Loaded{_, ws}:
      ws

def Store.apply(m: Maybe<&2, M.Change>, st: M.State) -> M.State:
  match m:
    case Some{c}:
      M.State.apply(st, c)
    case None{}:
      st

# one line, parsed as m: a line that does not parse is left out
def Store.step(m: Maybe<&2, J.Json>, l: String, a: Loaded) -> Loaded:
  match m a:
    case Some{+o} Loaded{st, ws}:
      Loaded{Store.apply(C.Change.decode(o), st), C.Change.wire_line(o, l) <> ws}
    case None{} _:
      a

def Store.load(ls: List<&2, String>, a: Loaded) -> Loaded:
  match ls:
    case Nil{}:
      a
    case +l <> t:
      Store.load(t, Store.step(J.Json.parse(l), l, a))

# The log's changes in order (what Store.load folds; for the laws)
# ----------------------------------------------------------------

def Store.put(m: Maybe<&2, M.Change>, rest: List<&2, M.Change>) -> List<&2, M.Change>:
  match m:
    case Some{c}:
      c <> rest
    case None{}:
      rest

def Store.change(m: Maybe<&2, J.Json>, rest: List<&2, M.Change>) -> List<&2, M.Change>:
  match m:
    case Some{+o}:
      Store.put(C.Change.decode(o), rest)
    case None{}:
      rest

def Store.changes(ls: List<&2, String>) -> List<&2, M.Change>:
  match ls:
    case Nil{}:
      Nil{}
    case +l <> t:
      Store.change(J.Json.parse(l), Store.changes(t))
