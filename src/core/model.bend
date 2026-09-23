import Base

# The product's state, event-sourced. Every change is a Change appended to
# the log; the read model is `replay(log)`. Events are persisted forever:
# add variants, never change what an existing one means.
#
# Times are Nat seconds since the Unix epoch.

# Enums
# -----

type Role is Data:
  User{}
  Assistant{}
  System{}

type TurnState is Data:
  Idle{}
  Running{}
  Completed{}
  Interrupted{}
  Failed{}

# A manual settle/unsettle pins the thread's shelf until the other is chosen.
type Override is Data:
  NoOverride{}
  ForcedSettled{}
  ForcedActive{}

type EnvMode is Data:
  Local{}
  Worktree{}

type RuntimeMode is Data:
  Supervised{}
  AcceptEdits{}
  AutoMode{}
  FullAccess{}

type InteractionMode is Data:
  DefaultMode{}
  PlanMode{}

# Entities
# --------

type Project is Data:
  Project{id: String, title: String, root: String, created: Nat, removed: Bool}

type Thread is Data:
  Thread{
    id: String,
    project: String,
    title: String,
    created: Nat,
    activity: Nat,
    turn: TurnState,
    pending: Nat,
    archived: Bool,
    override: Override,
    settled_at: Nat,
    unsettled_at: Nat,
    pinned: Bool,
    env: EnvMode,
    branch: String,
    worktree: String,
    provider: String,
    model: String,
    runtime: RuntimeMode,
    interaction: InteractionMode,
    session: String,
    deleted: Bool
  }

type Message is Data:
  Message{id: String, thread: String, role: Role, text: String, at: Nat}

# one tool call, approval, or error in a thread's timeline
type Activity is Data:
  Activity{id: String, thread: String, tone: String, kind: String, summary: String, at: Nat}

# Events
# ------

type Change is Data:
  ProjectCreated{id: String, title: String, root: String, at: Nat}
  ProjectRemoved{id: String, at: Nat}
  ThreadCreated{id: String, project: String, title: String, env: EnvMode, branch: String, worktree: String, provider: String, model: String, at: Nat}
  ThreadRenamed{id: String, title: String, at: Nat}
  MessagePosted{thread: String, msg: String, role: Role, text: String, at: Nat}
  TurnChanged{thread: String, state: TurnState, at: Nat}
  PendingChanged{thread: String, count: Nat, at: Nat}
  ActivityLogged{thread: String, act: String, tone: String, kind: String, summary: String, at: Nat}
  ThreadSettled{id: String, manual: Bool, at: Nat}
  ThreadUnsettled{id: String, at: Nat}
  ThreadArchived{id: String, archived: Bool, at: Nat}
  ThreadPinned{id: String, pinned: Bool, at: Nat}
  ThreadDeleted{id: String, at: Nat}
  WorktreeSet{id: String, branch: String, worktree: String, at: Nat}
  SessionSet{id: String, session: String, at: Nat}
  ModesSet{id: String, runtime: RuntimeMode, interaction: InteractionMode, model: String, at: Nat}

# the later of two times. Base's Nat.max recurses once per unit and
# overflows at epoch scale; Nat.is_ge compiles to a machine comparison.
def Time.max(+a: Nat, +b: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_ge(a, b), a, b)

# Settle rule
# -----------

# three days, the default of `sidebarAutoSettleAfterDays`
def Settle.window() -> Nat:
  259200n

# a thread is busy while a turn runs or something waits on the user
def Thread.busy(t: TurnState, +pending: Nat) -> Bool:
  match t:
    case Running{}:
      True{}
    case _:
      Nat.is_gt(pending, 0n)

# whether inactivity alone settles a thread whose last activity was at `last`
def Settle.stale(+now: Nat, +last: Nat, +window: Nat) -> Bool:
  Nat.is_ge(now, Nat.add(last, window))

def Settle.auto.k(busy: Bool, archived: Bool, o: Override, stale: Bool) -> Bool:
  match busy archived o:
    case False{} False{} NoOverride{}:
      stale
    case _ _ _:
      False{}

# whether the server's settle tick settles this thread now
def Settle.auto(+now: Nat, +window: Nat, t: Thread) -> Bool:
  Thread{_, _, _, _, +activity, turn, +pending, archived, override, _, _, _, _, _, _, _, _, _, _, _, _} = t
  Settle.auto.k(Thread.busy(turn, pending), archived, override, Settle.stale(now, activity, window))

# the shelf a thread sits on right now
type Shelf is Data:
  Pinned{}
  Active{}
  Settled{}
  Hidden{}

def Shelf.of.k(deleted: Bool, archived: Bool, pinned: Bool, o: Override, settled: Bool) -> Shelf:
  match deleted archived pinned o settled:
    case True{} _ _ _ _:
      Hidden{}
    case False{} True{} _ _ _:
      Hidden{}
    case False{} False{} _ ForcedSettled{} _:
      Settled{}
    case False{} False{} True{} _ _:
      Pinned{}
    case False{} False{} False{} ForcedActive{} _:
      Active{}
    case False{} False{} False{} NoOverride{} True{}:
      Settled{}
    case False{} False{} False{} NoOverride{} False{}:
      Active{}

# settled_at > 0 marks an auto-settle recorded by the tick
def Shelf.of(t: Thread) -> Shelf:
  Thread{_, _, _, _, _, _, _, archived, override, +settled_at, +unsettled_at, pinned, _, _, _, _, _, _, _, _, deleted} = t
  Shelf.of.k(deleted, archived, pinned, override, Nat.is_gt(settled_at, unsettled_at))

# Projection
# ----------

type State is Data:
  State{
    projects: Map<&2, Project>,
    threads: Map<&2, Thread>,
    messages: List<&2, Message>,
    activities: List<&2, Activity>,
    seq: Nat
  }

def State.empty() -> State:
  State{Map.new(&2, Project), Map.new(&2, Thread), Nil{}, Nil{}, 0n}

def Thread.blank(id: String) -> Thread:
  Thread{id, "", "", 0n, 0n, Idle{}, 0n, True{}, NoOverride{}, 0n, 0n, False{}, Local{}, "", "", "", "", FullAccess{}, DefaultMode{}, "", True{}}

def Project.blank(id: String) -> Project:
  Project{id, "", "", 0n, True{}}

# apply f to the thread at `id` (a blank, hidden thread when absent)
def State.thread.fin(f: Thread -> Thread, ps: Map<&2, Project>, ms: List<&2, Message>, as: List<&2, Activity>, n: Nat, id: String, r: Map<&2, Thread> & Thread) -> State:
  (ts, t) = r
  State{ps, Map.set(&2, Thread, ts, id, f(t)), ms, as, n}

def State.thread(f: Thread -> Thread, s: State, +id: String) -> State:
  State{ps, ts, ms, as, n} = s
  State.thread.fin(f, ps, ms, as, n, id, Map.get(Thread, Thread.blank(id), ts, id))

def Thread.renamed(+title: String, t: Thread) -> Thread:
  Thread{id, p, _, c, a, tu, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de} = t
  Thread{id, p, title, c, a, tu, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de}

# a user message is activity, and it wakes an auto-settled thread
def Thread.touched(+at: Nat, t: Thread) -> Thread:
  Thread{id, p, ti, c, _, tu, pe, ar, o, sa, _, pi, en, br, wt, pr, mo, rm, im, se, de} = t
  Thread{id, p, ti, c, at, tu, pe, ar, o, sa, at, pi, en, br, wt, pr, mo, rm, im, se, de}

def Thread.turned(st: TurnState, +at: Nat, t: Thread) -> Thread:
  Thread{id, p, ti, c, a, _, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de} = t
  Thread{id, p, ti, c, Time.max(a, at), st, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de}

def Thread.pending_set(n: Nat, t: Thread) -> Thread:
  Thread{id, p, ti, c, a, tu, _, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de} = t
  Thread{id, p, ti, c, a, tu, n, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de}

def Thread.settle.o(manual: Bool, o: Override) -> Override:
  match manual:
    case True{}:
      ForcedSettled{}
    case False{}:
      o

# settling clears the pin
def Thread.settled(manual: Bool, +at: Nat, t: Thread) -> Thread:
  Thread{id, p, ti, c, a, tu, pe, ar, o, _, ua, _, en, br, wt, pr, mo, rm, im, se, de} = t
  Thread{id, p, ti, c, a, tu, pe, ar, Thread.settle.o(manual, o), at, ua, False{}, en, br, wt, pr, mo, rm, im, se, de}

# unsettling puts the thread back on top of the active shelf
def Thread.unsettled(+at: Nat, t: Thread) -> Thread:
  Thread{id, p, ti, c, a, tu, pe, ar, _, +sa, _, pi, en, br, wt, pr, mo, rm, im, se, de} = t
  Thread{id, p, ti, c, Time.max(a, at), tu, pe, ar, ForcedActive{}, sa, Time.max(sa, at), pi, en, br, wt, pr, mo, rm, im, se, de}

def Thread.archived_set(b: Bool, t: Thread) -> Thread:
  Thread{id, p, ti, c, a, tu, pe, _, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de} = t
  Thread{id, p, ti, c, a, tu, pe, b, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de}

def Thread.pinned_set(b: Bool, t: Thread) -> Thread:
  Thread{id, p, ti, c, a, tu, pe, ar, o, sa, ua, _, en, br, wt, pr, mo, rm, im, se, de} = t
  Thread{id, p, ti, c, a, tu, pe, ar, o, sa, ua, b, en, br, wt, pr, mo, rm, im, se, de}

def Thread.deleted_set(t: Thread) -> Thread:
  Thread{id, p, ti, c, a, tu, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, _} = t
  Thread{id, p, ti, c, a, tu, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, True{}}

def Thread.worktree_set(b: String, w: String, t: Thread) -> Thread:
  Thread{id, p, ti, c, a, tu, pe, ar, o, sa, ua, pi, en, _, _, pr, mo, rm, im, se, de} = t
  Thread{id, p, ti, c, a, tu, pe, ar, o, sa, ua, pi, Worktree{}, b, w, pr, mo, rm, im, se, de}

def Thread.session_set(s: String, t: Thread) -> Thread:
  Thread{id, p, ti, c, a, tu, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, _, de} = t
  Thread{id, p, ti, c, a, tu, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, s, de}

def Thread.modes_set(r: RuntimeMode, i: InteractionMode, m: String, t: Thread) -> Thread:
  Thread{id, p, ti, c, a, tu, pe, ar, o, sa, ua, pi, en, br, wt, pr, _, _, _, se, de} = t
  Thread{id, p, ti, c, a, tu, pe, ar, o, sa, ua, pi, en, br, wt, pr, m, r, i, se, de}

def State.put_thread(s: State, t: Thread) -> State:
  State{ps, ts, ms, as, n} = s
  Thread{+id, p, ti, c, a, tu, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de} = t
  State{ps, Map.set(&2, Thread, ts, id, Thread{id, p, ti, c, a, tu, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de}), ms, as, n}

def State.put_project(s: State, p: Project) -> State:
  State{ps, ts, ms, as, n} = s
  Project{+id, ti, r, c, rm} = p
  State{Map.set(&2, Project, ps, id, Project{id, ti, r, c, rm}), ts, ms, as, n}

def State.remove_project.fin(ts: Map<&2, Thread>, ms: List<&2, Message>, as: List<&2, Activity>, n: Nat, id: String, r: Map<&2, Project> & Project) -> State:
  (ps, p) = r
  Project{i, ti, rt, c, _} = p
  State{Map.set(&2, Project, ps, id, Project{i, ti, rt, c, True{}}), ts, ms, as, n}

def State.remove_project(s: State, +id: String) -> State:
  State{ps, ts, ms, as, n} = s
  State.remove_project.fin(ts, ms, as, n, id, Map.get(Project, Project.blank(id), ps, id))

def State.post(s: State, m: Message) -> State:
  State{ps, ts, ms, as, n} = s
  State{ps, ts, m <> ms, as, n}

def State.log_activity(s: State, a: Activity) -> State:
  State{ps, ts, ms, as, n} = s
  State{ps, ts, ms, a <> as, n}

def State.tick(s: State) -> State:
  State{ps, ts, ms, as, n} = s
  State{ps, ts, ms, as, 1n+n}

def State.message(s: State, +thread: String, msg: String, role: Role, text: String, +at: Nat) -> State:
  match role:
    case User{}:
      State.post(State.thread((t => Thread.touched(at, t)), s, thread), Message{msg, thread, User{}, text, at})
    case _:
      State.post(s, Message{msg, thread, role, text, at})

def State.apply.go(s: State, e: Change) -> State:
  match e:
    case ProjectCreated{id, title, root, at}:
      State.put_project(s, Project{id, title, root, at, False{}})
    case ProjectRemoved{+id, _}:
      State.remove_project(s, id)
    case ThreadCreated{id, project, title, env, branch, worktree, provider, model, +at}:
      State.put_thread(s, Thread{id, project, title, at, at, Idle{}, 0n, False{}, NoOverride{}, 0n, 0n, False{}, env, branch, worktree, provider, model, FullAccess{}, DefaultMode{}, "", False{}})
    case ThreadRenamed{+id, +title, _}:
      State.thread((t => Thread.renamed(title, t)), s, id)
    case MessagePosted{+thread, msg, role, text, +at}:
      State.message(s, thread, msg, role, text, at)
    case TurnChanged{+thread, state, +at}:
      State.thread((t => Thread.turned(state, at, t)), s, thread)
    case PendingChanged{+thread, count, _}:
      State.thread((t => Thread.pending_set(count, t)), s, thread)
    case ActivityLogged{thread, act, tone, kind, summary, at}:
      State.log_activity(s, Activity{act, thread, tone, kind, summary, at})
    case ThreadSettled{+id, manual, +at}:
      State.thread((t => Thread.settled(manual, at, t)), s, id)
    case ThreadUnsettled{+id, +at}:
      State.thread((t => Thread.unsettled(at, t)), s, id)
    case ThreadArchived{+id, b, _}:
      State.thread((t => Thread.archived_set(b, t)), s, id)
    case ThreadPinned{+id, b, _}:
      State.thread((t => Thread.pinned_set(b, t)), s, id)
    case ThreadDeleted{+id, _}:
      State.thread((t => Thread.deleted_set(t)), s, id)
    case WorktreeSet{+id, b, w, _}:
      State.thread((t => Thread.worktree_set(b, w, t)), s, id)
    case SessionSet{+id, se, _}:
      State.thread((t => Thread.session_set(se, t)), s, id)
    case ModesSet{+id, r, i, m, _}:
      State.thread((t => Thread.modes_set(r, i, m, t)), s, id)

# one event folded into the read model; every event bumps the sequence
def State.apply(s: State, e: Change) -> State:
  State.tick(State.apply.go(s, e))

# the read model after a log, oldest event first
def State.replay(es: List<&2, Change>, s: State) -> State:
  match es:
    case Nil{}:
      s
    case e <> t:
      State.replay(t, State.apply(s, e))

# Sidebar
# -------

# a project's threads split by shelf, each list in display order
type Shelves is Data:
  Shelves{pinned: List<&2, Thread>, active: List<&2, Thread>, settled: List<&2, Thread>, hidden: List<&2, Thread>}

def Shelves.put(sh: Shelf, t: Thread, s: Shelves) -> Shelves:
  match sh s:
    case Pinned{} Shelves{p, a, st, h}:
      Shelves{t <> p, a, st, h}
    case Active{} Shelves{p, a, st, h}:
      Shelves{p, t <> a, st, h}
    case Settled{} Shelves{p, a, st, h}:
      Shelves{p, a, t <> st, h}
    case Hidden{} Shelves{p, a, st, h}:
      Shelves{p, a, st, t <> h}

# every thread lands on exactly one shelf (law Sidebar.split_count)
def Sidebar.split(ts: List<&2, Thread>) -> Shelves:
  match ts:
    case Nil{}:
      Shelves{Nil{}, Nil{}, Nil{}, Nil{}}
    case +t <> rest:
      Shelves.put(Shelf.of(t), t, Sidebar.split(rest))

def Shelves.count(s: Shelves) -> Nat:
  Shelves{p, a, st, h} = s
  Nat.add(List.length(&2, Thread, p), Nat.add(List.length(&2, Thread, a), Nat.add(List.length(&2, Thread, st), List.length(&2, Thread, h))))

# where a thread sorts on the active shelf: created, or brought back
def Thread.rank(t: Thread) -> Nat:
  Thread{_, _, _, +c, _, _, _, _, _, _, +ua, _, _, _, _, _, _, _, _, _, _} = t
  Time.max(c, ua)

def Thread.settled_rank(t: Thread) -> Nat:
  Thread{_, _, _, _, _, _, _, _, _, +sa, _, _, _, _, _, _, _, _, _, _, _} = t
  sa

# newest first; activity does not reorder a shelf
def Thread.before(a: Thread, b: Thread) -> Bool:
  Nat.is_ge(Thread.rank(a), Thread.rank(b))

def Thread.settled_before(a: Thread, b: Thread) -> Bool:
  Nat.is_ge(Thread.settled_rank(a), Thread.settled_rank(b))

def Sidebar.order(s: Shelves) -> Shelves:
  Shelves{p, a, st, h} = s
  Shelves{List.sort(~Thread, ~Thread.before, p), List.sort(~Thread, ~Thread.before, a), List.sort(~Thread, ~Thread.settled_before, st), h}

def Thread.in_project(+pid: String, t: Thread) -> Bool:
  Thread{_, +p, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} = t
  String.eq(p, pid)

def Thread.filter_project.pick(keep: Bool, t: Thread, rest: List<&2, Thread>) -> List<&2, Thread>:
  match keep:
    case True{}:
      t <> rest
    case False{}:
      rest

def Thread.filter_project(ts: List<&2, Thread>, +pid: String) -> List<&2, Thread>:
  match ts:
    case Nil{}:
      Nil{}
    case +t <> rest:
      Thread.filter_project.pick(Thread.in_project(pid, t), t, Thread.filter_project(rest, pid))

