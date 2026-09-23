import Base
import ./model.bend as M

# Tool calls folded
# -----------------
# A run of consecutive tool calls (Act entries of tone "tool") shows as one
# row, "6 tool calls · shell, edit, read"; a click opens it. Errors,
# messages and any other activity are never folded and end a run.
# Grouping loses no entry and keeps the order (law fold_keeps_entries), and
# a run holds only tool calls (law fold_runs_only_tools).
#
# A run is open when the user opened it ("fold:<first id>" is "1" in the
# client's info map), shut when they shut it ("0"), and otherwise open only
# while it is the live one: the last thing in a thread whose turn runs.

type Grp is Data:
  GOne{e: M.Entry}
  GRun{es: List<&2, M.Entry>}

def Fold.tool(e: M.Entry) -> Bool:
  match e:
    case M.Act{_, _, tone, _, _, _}:
      String.eq(tone, "tool")
    case M.Msg{_, _, _, _, _}:
      False{}

# an entry in front of the groups after it: a tool call joins the run that
# starts there
def Fold.push.k(b: Bool, e: M.Entry, gs: List<&2, Grp>) -> List<&2, Grp>:
  match b gs:
    case True{} GRun{xs} <> t:
      GRun{e <> xs} <> t
    case True{} _:
      GRun{[e]} <> gs
    case False{} _:
      GOne{e} <> gs

def Fold.push(+e: M.Entry, gs: List<&2, Grp>) -> List<&2, Grp>:
  Fold.push.k(Fold.tool(e), e, gs)

# a thread's entries (oldest first) as groups
def Fold.groups(es: List<&2, M.Entry>) -> List<&2, Grp>:
  match es:
    case Nil{}:
      Nil{}
    case +e <> t:
      Fold.push(e, Fold.groups(t))

# the entries back, in order
def Fold.flat(gs: List<&2, Grp>) -> List<&2, M.Entry>:
  match gs:
    case Nil{}:
      Nil{}
    case GOne{e} <> t:
      e <> Fold.flat(t)
    case GRun{xs} <> t:
      List.append(&2, M.Entry, xs, Fold.flat(t))

# how many entries the groups hold
def Fold.count(gs: List<&2, Grp>) -> Nat:
  List.length(&2, M.Entry, Fold.flat(gs))

# every entry that sits in a run
def Fold.runs(gs: List<&2, Grp>) -> List<&2, M.Entry>:
  match gs:
    case Nil{}:
      Nil{}
    case GOne{_} <> t:
      Fold.runs(t)
    case GRun{xs} <> t:
      List.append(&2, M.Entry, xs, Fold.runs(t))

def Fold.all.and(b: Bool, rest: Bool) -> Bool:
  match b:
    case True{}:
      rest
    case False{}:
      False{}

# whether every entry is a tool call
def Fold.all(es: List<&2, M.Entry>) -> Bool:
  match es:
    case Nil{}:
      True{}
    case +e <> t:
      Fold.all.and(Fold.tool(e), Fold.all(t))

# Labels
# ------

def Fold.id(e: M.Entry) -> String:
  match e:
    case M.Msg{i, _, _, _, _}:
      i
    case M.Act{i, _, _, _, _, _}:
      i

def Fold.kind(e: M.Entry) -> String:
  match e:
    case M.Msg{_, _, _, _, _}:
      ""
    case M.Act{_, _, _, k, _, _}:
      k

def Fold.has(xs: List<&2, String>, +k: String) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case +x <> t:
      Bool.or(String.eq(x, k), Fold.has(t, k))

def Fold.add.k(has: Bool, +k: String, acc: List<&2, String>) -> List<&2, String>:
  match has:
    case True{}:
      acc
    case False{}:
      List.append(&2, String, acc, [k])

# the distinct kinds, in the order first seen
def Fold.kinds(es: List<&2, M.Entry>, +acc: List<&2, String>) -> List<&2, String>:
  match es:
    case Nil{}:
      acc
    case +e <> t:
      Fold.kinds(t, Fold.add.k(Fold.has(acc, Fold.kind(e)), Fold.kind(e), acc))

def Fold.first(k: Nat, xs: List<&2, String>) -> List<&2, String>:
  match k xs:
    case 0n _:
      Nil{}
    case 1n+j x <> t:
      x <> Fold.first(j, t)
    case 1n+j Nil{}:
      Nil{}

# "6 tool calls · shell, edit, read" (three kinds at most)
def Fold.label(+es: List<&2, M.Entry>) -> String:
  +n = List.length(&2, M.Entry, es)
  +ks = Fold.kinds(es, Nil{})
  Nat.show(n) ++ Bool.pick(String, Nat.is_eq(n, 1n), " tool call", " tool calls")
    ++ Bool.pick(String, List.is_empty(&2, String, ks), "", " · " ++ String.join(Fold.first(3n, ks), ", ")
    ++ Bool.pick(String, Nat.is_gt(List.length(&2, String, ks), 3n), ", …", ""))

# the run's id: its first entry's
def Fold.run_id(es: List<&2, M.Entry>) -> String:
  match es:
    case Nil{}:
      ""
    case e <> _:
      Fold.id(e)

# Open or shut
# ------------

def Fold.key(+id: String) -> String:
  "fold:" ++ id

def Fold.user.k(r: Map<&2, String> & String) -> String:
  (_, v) = r
  v

# what the user chose for a run ("" for nothing yet)
def Fold.user(m: Map<&2, String>, +id: String) -> String:
  Fold.user.k(Map.get(String, "", m, Fold.key(id)))

# the user's choice ("1" open, "0" shut) or, with none, whether it is live
def Fold.open(+user: String, live: Bool) -> Bool:
  Bool.pick(Bool, String.eq(user, "1"), True{}, Bool.pick(Bool, String.eq(user, "0"), False{}, live))

# a click's value: the state it asks for, then the run's id
def Fold.ask(+open: Bool, +id: String) -> String:
  Bool.pick(String, open, "0", "1") ++ id

# Roles
# -----
# What each entry shows as, one role per entry in order (Fold.flat), for a
# UI that walks its entries: as it is, as the first of a run (the run's
# row, then the entry itself when open) or as a later one (itself when
# open).

type Role is Data:
  RShow{}
  RHead{id: String, label: String, open: Bool}
  RIn{open: Bool}

def Fold.ins(es: List<&2, M.Entry>, +open: Bool) -> List<&2, Role>:
  match es:
    case Nil{}:
      Nil{}
    case _ <> t:
      RIn{open} <> Fold.ins(t, open)

def Fold.run.roles(+es: List<&2, M.Entry>, +open: Bool) -> List<&2, Role>:
  match es:
    case Nil{}:
      Nil{}
    case _ <> t:
      RHead{Fold.run_id(es), Fold.label(es), open} <> Fold.ins(t, open)

def Fold.last(gs: List<&2, Grp>) -> Bool:
  match gs:
    case Nil{}:
      True{}
    case _ <> _:
      False{}

def Fold.grp.roles(g: Grp, last: Bool, +info: Map<&2, String>, +running: Bool) -> List<&2, Role>:
  match g:
    case GOne{_}:
      [RShow{}]
    case GRun{+xs}:
      Fold.run.roles(xs, Fold.open(Fold.user(info, Fold.run_id(xs)), Bool.and(last, running)))

def Fold.roles.go(gs: List<&2, Grp>, +info: Map<&2, String>, +running: Bool) -> List<&2, Role>:
  match gs:
    case Nil{}:
      Nil{}
    case g <> +t:
      List.append(&2, Role, Fold.grp.roles(g, Fold.last(t), info, running), Fold.roles.go(t, info, running))

# the roles of a thread's entries, with the client's info map and whether
# its turn runs
def Fold.roles(es: List<&2, M.Entry>, +info: Map<&2, String>, +running: Bool) -> List<&2, Role>:
  Fold.roles.go(Fold.groups(es), info, running)
