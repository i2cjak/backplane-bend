import Base
import ./bot.bend as BT

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

# one item of a thread's timeline: a message, or a tool call / approval /
# error. Entries keep log order, so a timeline never needs re-sorting.
type Entry is Data:
  Msg{id: String, thread: String, role: Role, text: String, at: Nat}
  Act{id: String, thread: String, tone: String, kind: String, summary: String, at: Nat}

# Events
# ------

# Delegated tasks
# ---------------
# A thread (the parent) may delegate a task to a child thread that runs on
# any provider and model. A task's state only moves forward: once done,
# failed or cancelled it never changes again (law task_terminal_absorbing),
# its result reaches the parent exactly once (law task_delivered_once), and
# delegation stops at a fixed depth (law delegation_bounded), so models
# cannot spawn each other without end.

type TaskState is Data:
  TaskQueued{}
  TaskRunning{}
  TaskDone{}
  TaskFailed{}
  TaskCancelled{}

type Task is Data:
  Task{id: String, parent: String, child: String, depth: Nat, state: TaskState, summary: String, delivered: Bool, provider: String, model: String}

def TaskState.terminal(s: TaskState) -> Bool:
  match s:
    case TaskDone{}:
      True{}
    case TaskFailed{}:
      True{}
    case TaskCancelled{}:
      True{}
    case _:
      False{}

# the state after asking for `want`: terminal states stay; a running task
# never goes back to queued
def TaskState.next(cur: TaskState, want: TaskState) -> TaskState:
  match cur want:
    case TaskDone{} _:
      TaskDone{}
    case TaskFailed{} _:
      TaskFailed{}
    case TaskCancelled{} _:
      TaskCancelled{}
    case TaskRunning{} TaskQueued{}:
      TaskRunning{}
    case _ _:
      want

def Task.max_depth() -> Nat:
  3n

# whether a thread at this depth (0 for a top-level thread) may delegate
def Task.may_delegate(+depth: Nat) -> Bool:
  Nat.is_lt(depth, Task.max_depth())

def Task.step(t: Task, want: TaskState, summary: String) -> Task:
  match t:
    case Task{i, p, c, d, cur, _, dl, pr, mo}:
      Task{i, p, c, d, TaskState.next(cur, want), summary, dl, pr, mo}

def Task.delivered_set(t: Task) -> Task:
  match t:
    case Task{i, p, c, d, st, su, _, pr, mo}:
      Task{i, p, c, d, st, su, True{}, pr, mo}

# a finished task whose result the parent has not received yet
def Task.pending(t: Task) -> Bool:
  match t:
    case Task{_, _, _, _, st, _, dl, _, _}:
      Bool.and(TaskState.terminal(st), Bool.not(dl))

def Task.blank(id: String) -> Task:
  Task{id, "", "", 0n, TaskCancelled{}, "", True{}, "", ""}

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
  TaskDelegated{task: String, parent: String, child: String, depth: Nat, provider: String, model: String, at: Nat}
  TaskStateSet{task: String, state: TaskState, summary: String, at: Nat}
  TaskDelivered{task: String, at: Nat}
  SettingSet{key: String, value: String, at: Nat}
  TurnQueued{thread: String, msg: String, text: String, at: Nat}
  QueueTaken{thread: String, at: Nat}
  AskOpened{id: String, thread: String, kind: String, tool: String, detail: String, options: String, at: Nat}
  AskClosed{id: String, answer: String, at: Nat}
  # a phone asks for pushes (APNs/FCM); keyed by token, never sent to clients
  DeviceRegistered{token: String, platform: String, kind: String, thread: String, env: String, bundle: String, at: Nat}
  DeviceDropped{token: String, at: Nat}
  # snoozed until a time (0: awake again); see Snooze below
  ThreadSnoozed{id: String, until: Nat, at: Nat}
  # a manual place on the "pinned" or "active" shelf: an order key (Key
  # below, shown as hex); "" drops it
  ThreadOrdered{id: String, section: String, key: String, at: Nat}
  # a new thread's worktree could not be made (not a git repository, no
  # commit yet): it works in the project folder
  WorktreeSkipped{id: String, at: Nat}
  # the thread's branch was merged (a GitHub pull request, seen by gh): it
  # settles, and the merge is kept as the setting merged.<id>
  ThreadMerged{id: String, url: String, at: Nat}
  # the thread's worktree was removed (settled long enough, or merged); its
  # branch stays, and its last state is a checkpoint
  WorktreeRemoved{id: String, at: Nat}
  # a project's manual place in the sidebar: an order key (Key below, as
  # hex); "" drops it
  ProjectOrdered{id: String, key: String, at: Nat}
  # a queued message's text changed before it was sent
  QueueEdited{thread: String, msg: String, text: String, at: Nat}
  # a queued message dropped before it was sent
  QueueRemoved{thread: String, msg: String, at: Nat}
  # a queued message moved to place `to` (0 is next) in its thread's queue
  QueueMoved{thread: String, msg: String, to: Nat, at: Nat}
  # one queued message taken out to be sent now (a steer)
  QueueTakenOne{thread: String, msg: String, at: Nat}
  # a thread made as a fork of `source`: it starts with the source's
  # conversation as handed-over context, and in a worktree from the
  # source's last checkpoint
  ThreadForked{id: String, source: String, at: Nat}
  # the thread goes on with another provider (and model) from its next turn:
  # the provider left keeps its session and how much of the thread it saw;
  # the one taken up gets back its own session, if it had one
  ProviderSet{id: String, provider: String, model: String, at: Nat}
  # an agent's todo list for its thread, as JSON [{text, status}] (todo.bend)
  TodosSet{thread: String, todos: String, at: Nat}
  # how much of its model's context a thread's session holds (tokens), and\nthe model's window; 0 keeps what was known
  UsageSet{thread: String, used: Nat, window: Nat, at: Nat}
  # Bots (bot.bend, docs/bots.md). Secrets (webhooks, peers) never enter
  # the log. A BotSet with an empty thread keeps the one the bot has;
  # room members are one per line; BotWoke records the conversation depth
  # of the message that started a bot's turn
  BotSet{id: String, name: String, thread: String, look: Nat, persona: String, at: Nat}
  BotDeleted{id: String, at: Nat}
  RoomSet{id: String, name: String, members: String, at: Nat}
  RoomDeleted{id: String, at: Nat}
  RoomPosted{id: String, room: String, from: String, text: String, hop: Nat, at: Nat}
  HookSet{id: String, bot: String, name: String, revoked: Bool, at: Nat}
  HookHit{id: String, at: Nat}
  RoutineSet{id: String, bot: String, name: String, cron: String, prompt: String, on: Bool, at: Nat}
  RoutineDeleted{id: String, at: Nat}
  RoutineFired{id: String, at: Nat}
  MemorySaved{bot: String, key: String, kind: String, text: String, tags: String, at: Nat}
  MemoryForgot{bot: String, key: String, at: Nat}
  SpaceSet{bot: String, spec: String, at: Nat}
  PeerSet{id: String, name: String, url: String, revoked: Bool, at: Nat}
  BotWoke{bot: String, hop: Nat, at: Nat}
  # a bot's space as a web page ("" takes it away)
  SpacePageSet{bot: String, html: String, at: Nat}

# the later of two times. Base's Nat.max recurses once per unit and
# overflows at epoch scale; Nat.is_ge compiles to a machine comparison.
def Time.max(+a: Nat, +b: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_ge(a, b), a, b)

def Time.ago.k(m: Bool, h: Bool, d: Bool, +s: Nat) -> String:
  match m h d:
    case True{} _ _:
      "now"
    case False{} True{} _:
      Nat.show(Nat.div(s, 60n)) ++ "m"
    case False{} False{} True{}:
      Nat.show(Nat.div(s, 3600n)) ++ "h"
    case False{} False{} False{}:
      Nat.show(Nat.div(s, 86400n)) ++ "d"

# "now", "5m", "3h", "2d"
def Time.ago(+now: Nat, +at: Nat) -> String:
  +s = Nat.sub(now, at)
  Time.ago.k(Nat.is_lt(s, 60n), Nat.is_lt(s, 3600n), Nat.is_lt(s, 86400n), s)

def Time.took.k(m: Bool, h: Bool, +s: Nat) -> String:
  match m h:
    case True{} _:
      Nat.show(s) ++ "s"
    case False{} True{}:
      Nat.show(Nat.div(s, 60n)) ++ "m " ++ Nat.show(Nat.mod(s, 60n)) ++ "s"
    case False{} False{}:
      Nat.show(Nat.div(s, 3600n)) ++ "h " ++ Nat.show(Nat.div(Nat.mod(s, 3600n), 60n)) ++ "m"

# how long something took: "45s", "2m 13s", "1h 5m"
def Time.took(+s: Nat) -> String:
  Time.took.k(Nat.is_lt(s, 60n), Nat.is_lt(s, 3600n), s)

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

# Snooze
# ------
# A thread snoozed until a time sits on its own shelf until then and never
# auto-settles meanwhile (law settle_never_snoozed). It wakes by the clock
# alone: no event is needed (law snooze_wakes), and its settle window
# starts over from the wake time.

def Snooze.on(+now: Nat, +until: Nat) -> Bool:
  Bool.not(Nat.is_ge(now, until))

def Settle.auto.s(snoozed: Bool, +now: Nat, +window: Nat, t: Thread, +until: Nat) -> Bool:
  match snoozed:
    case True{}:
      False{}
    case False{}:
      Bool.and(Settle.stale(now, until, window), Settle.auto(now, window, t))

# the settle tick's rule with the thread's snooze (until 0: never snoozed)
def Settle.auto.at(+now: Nat, +window: Nat, t: Thread, +until: Nat) -> Bool:
  Settle.auto.s(Snooze.on(now, until), now, window, t, until)

def Snooze.hour() -> Nat:
  3600n

def Snooze.week() -> Nat:
  604800n

# "+0200" / "-0530" (date +%z) as whether local time is east of UTC and
# by how many seconds
def Snooze.tz.secs(+s: String) -> Nat:
  +n = Maybe.default(&2, Nat, Nat.read(String.drop(s, 1n)), 0n)
  Nat.add(Nat.mul(Nat.div(n, 100n), 3600n), Nat.mul(Nat.mod(n, 100n), 60n))

def Snooze.tz.east(+s: String) -> Bool:
  Bool.not(String.starts_with(s, "-"))

def Snooze.local(east: Bool, +now: Nat, +off: Nat) -> Nat:
  match east:
    case True{}:
      Nat.add(now, off)
    case False{}:
      Nat.sub(now, off)

def Snooze.utc(east: Bool, +t: Nat, +off: Nat) -> Nat:
  match east:
    case True{}:
      Nat.sub(t, off)
    case False{}:
      Nat.add(t, off)

# 9:00 local time tomorrow, as epoch seconds
def Snooze.tomorrow(+now: Nat, +tz: String) -> Nat:
  +off = Snooze.tz.secs(tz)
  +day = Nat.div(Snooze.local(Snooze.tz.east(tz), now, off), 86400n)
  Snooze.utc(Snooze.tz.east(tz), Nat.add(Nat.mul(1n+day, 86400n), 32400n), off)

# the shelf a thread sits on right now
type Shelf is Data:
  Pinned{}
  Active{}
  Settled{}
  Hidden{}
  Snoozed{}

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

def Thread.blank(id: String) -> Thread:
  Thread{id, "", "", 0n, 0n, Idle{}, 0n, True{}, NoOverride{}, 0n, 0n, False{}, Local{}, "", "", "", "", FullAccess{}, DefaultMode{}, "", True{}}

def Project.blank(id: String) -> Project:
  Project{id, "", "", 0n, True{}}

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

def Thread.local(t: Thread) -> Thread:
  Thread{id, p, ti, c, a, tu, pe, ar, o, sa, ua, pi, _, _, _, pr, mo, rm, im, se, de} = t
  Thread{id, p, ti, c, a, tu, pe, ar, o, sa, ua, pi, Local{}, "", "", pr, mo, rm, im, se, de}

def Thread.unrooted(t: Thread) -> Thread:
  Thread{id, p, ti, c, a, tu, pe, ar, o, sa, ua, pi, en, br, _, pr, mo, rm, im, se, de} = t
  Thread{id, p, ti, c, a, tu, pe, ar, o, sa, ua, pi, en, br, "", pr, mo, rm, im, se, de}

def Thread.session_set(s: String, t: Thread) -> Thread:
  Thread{id, p, ti, c, a, tu, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, _, de} = t
  Thread{id, p, ti, c, a, tu, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, s, de}

def Thread.modes_set(r: RuntimeMode, i: InteractionMode, m: String, t: Thread) -> Thread:
  Thread{id, p, ti, c, a, tu, pe, ar, o, sa, ua, pi, en, br, wt, pr, _, _, _, se, de} = t
  Thread{id, p, ti, c, a, tu, pe, ar, o, sa, ua, pi, en, br, wt, pr, m, r, i, se, de}

# Asks
# ----
# What an agent waits on the user for: a tool approval ("approval"), a
# question ("input", options one per line) or a proposed plan ("plan").
# Opened by the agent, closed once by the user's answer.

# a phone's push registration. kind is "alert" (notifications), "activity"
# (a Live Activity's update token; thread "" is the all-agents island) or
# "start" (push-to-start). The token is a secret: it stays on the server.
type Device is Data:
  Device{token: String, platform: String, kind: String, thread: String, env: String, bundle: String, at: Nat}

type Ask is Data:
  Ask{id: String, thread: String, kind: String, tool: String, detail: String, options: String, open: Bool, answer: String}

# Sidebar extensions
# ------------------
# What the sidebar knows of a thread beyond the Thread itself: when a snooze
# ends (0: not snoozed) and its manual order keys on the pinned and active
# shelves ("": none).

type Nav is Data:
  Nav{until: Nat, pin: String, act: String}

def Nav.blank() -> Nav:
  Nav{0n, "", ""}

def Nav.get.k(r: Map<&2, Nav> & Nav) -> Nav:
  (_, v) = r
  v

def Nav.get(+m: Map<&2, Nav>, +id: String) -> Nav:
  Nav.get.k(Map.get(Nav, Nav.blank(), m, id))

def Nav.until(n: Nav) -> Nat:
  match n:
    case Nav{u, _, _}:
      u

def Nav.snoozed(n: Nav, +until: Nat) -> Nav:
  match n:
    case Nav{_, p, a}:
      Nav{until, p, a}

# the key of a section ("pinned" or "active")
def Nav.key(n: Nav, +section: String) -> String:
  match n:
    case Nav{_, p, a}:
      Bool.pick(String, String.eq(section, "pinned"), p, a)

def Nav.keyed(n: Nav, +section: String, +key: String) -> Nav:
  match n:
    case Nav{+u, +p, +a}:
      Bool.pick(Nav, String.eq(section, "pinned"), Nav{u, key, a}, Nav{u, p, key})

# A project's order key lives in the same map under "project:<id>" (its
# "active" key), a name no thread id takes
def Nav.project(+id: String) -> String:
  "project:" ++ id

# a project's order key ("": none)
def Nav.project_key(+m: Map<&2, Nav>, +id: String) -> String:
  Nav.key(Nav.get(m, Nav.project(id)), "active")

# Worktrees
# ---------
# A new thread gets its own worktree of the project's repository (made by
# the server under <repo>/.backplane/worktrees). Until it exists the
# thread's messages wait in its queue, for at most Worktree.wait() seconds
# after the thread was made; past that (or once skipped: no repository) the
# thread works in the project folder (laws worktree_pending_*).
#
# A worktree is removed once its thread is idle and put away: settled or
# hidden for Worktree days (the "worktree.days" setting), or settled by a
# merge, at once. Only worktrees Backplane made (under .backplane/worktrees)
# are ever removed, and the branch stays (laws worktree_kept_*,
# worktree_dropped_*). A message to a thread whose worktree is gone makes
# it again from the branch, and waits for it like a new thread's first
# message (law worktree_revives).

def Worktree.wait() -> Nat:
  120n

def Worktree.pending.k(env: EnvMode, +wt: String, +since: Nat, +now: Nat) -> Bool:
  match env:
    case Worktree{}:
      Bool.and(Nat.is_lt(now, Nat.add(since, Worktree.wait())), String.is_empty(wt))
    case Local{}:
      False{}

# when the wait started: a new thread's creation, or, for a thread whose
# worktree is being made again, the message that asked for it
def Worktree.since(+branch: String, +created: Nat, +activity: Nat) -> Nat:
  Bool.pick(Nat, String.is_empty(branch), created, activity)

# whether a thread still waits for its worktree
def Worktree.pending(t: Thread, +now: Nat) -> Bool:
  Thread{_, _, _, +c, +a, _, _, _, _, _, _, _, en, +br, +wt, _, _, _, _, _, _} = t
  Worktree.pending.k(en, wt, Worktree.since(br, c, a), now)

def Worktree.gone.k(env: EnvMode, +wt: String, +branch: String) -> Bool:
  match env:
    case Worktree{}:
      Bool.and(String.is_empty(wt), Bool.not(String.is_empty(branch)))
    case Local{}:
      False{}

# a worktree thread whose worktree was removed (its branch is kept)
def Worktree.gone(t: Thread) -> Bool:
  Thread{_, _, _, _, _, _, _, _, _, _, _, _, en, +br, +wt, _, _, _, _, _, _} = t
  Worktree.gone.k(en, wt, br)

# a directory Backplane made for a thread, the only kind it removes
def Worktree.ours(+wt: String) -> Bool:
  String.contains(wt, "/.backplane/worktrees/")

# the shelves a thread is put away on
def Worktree.parked(sh: Shelf) -> Bool:
  match sh:
    case Settled{}:
      True{}
    case Hidden{}:
      True{}
    case _:
      False{}

def Worktree.drop.s(sh: Shelf, +ours: Bool, merged: Bool, aged: Bool) -> Bool:
  match sh:
    case Settled{}:
      Bool.and(ours, Bool.or(merged, aged))
    case Hidden{}:
      Bool.and(ours, aged)
    case _:
      False{}

# whether a worktree goes now: never while its thread is busy
def Worktree.drop.k(busy: Bool, sh: Shelf, +ours: Bool, merged: Bool, aged: Bool) -> Bool:
  match busy:
    case True{}:
      False{}
    case False{}:
      Worktree.drop.s(sh, ours, merged, aged)

# Merges
# ------
# A thread whose branch is merged settles by itself, once: the merge is
# recorded (merged.<id>), and a recorded merge is never due again, so a
# thread the user brings back stays back (laws merge_*).

def Merge.key(+id: String) -> String:
  "merged." ++ id

def Merge.due.k(sh: Shelf, +branch: String, +merged: String) -> Bool:
  match sh:
    case Pinned{}:
      Bool.and(Bool.not(String.is_empty(branch)), String.is_empty(merged))
    case Active{}:
      Bool.and(Bool.not(String.is_empty(branch)), String.is_empty(merged))
    case _:
      False{}

# Projection
# ----------

# a message waiting in a thread's queue: its id and text
type QItem is Data:
  QItem{msg: String, text: String}

type State is Data:
  State{
    projects: Map<&2, Project>,
    threads: Map<&2, Thread>,
    entries: List<&2, Entry>,
    seq: Nat,
    tasks: Map<&2, Task>,
    settings: Map<&2, String>,
    queued: Map<&2, List<&2, QItem>>,
    asks: Map<&2, Ask>,
    devices: Map<&2, Device>,
    nav: Map<&2, Nav>,
    # behind a List: the native window holds the State in its own, and a
    # World record flattened into it passes the C emitter's 255 arguments
    bots: List<&2, BT.World>
  }

def State.empty() -> State:
  State{Map.new(&2, Project), Map.new(&2, Thread), Nil{}, 0n, Map.new(&2, Task), Map.new(&2, String), Map.new(&2, List<&2, QItem>), Map.new(&2, Ask), Map.new(&2, Device), Map.new(&2, Nav), [BT.World.empty()]}

# apply f to the thread at `id` (a blank, hidden thread when absent)
def State.thread.fin(f: Thread -> Thread, ps: Map<&2, Project>, es: List<&2, Entry>, n: Nat, tk: Map<&2, Task>, sg: Map<&2, String>, qu: Map<&2, List<&2, QItem>>, ak: Map<&2, Ask>, dv: Map<&2, Device>, nv: Map<&2, Nav>, bw: List<&2, BT.World>, id: String, r: Map<&2, Thread> & Thread) -> State:
  (ts, t) = r
  State{ps, Map.set(&2, Thread, ts, id, f(t)), es, n, tk, sg, qu, ak, dv, nv, bw}

def State.thread(f: Thread -> Thread, s: State, +id: String) -> State:
  State{ps, ts, es, n, tk, sg, qu, ak, dv, nv, bw} = s
  State.thread.fin(f, ps, es, n, tk, sg, qu, ak, dv, nv, bw, id, Map.get(Thread, Thread.blank(id), ts, id))

def State.put_thread(s: State, t: Thread) -> State:
  State{ps, ts, es, n, tk, sg, qu, ak, dv, nv, bw} = s
  Thread{+id, p, ti, c, a, tu, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de} = t
  State{ps, Map.set(&2, Thread, ts, id, Thread{id, p, ti, c, a, tu, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de}), es, n, tk, sg, qu, ak, dv, nv, bw}

def State.put_project(s: State, p: Project) -> State:
  State{ps, ts, es, n, tk, sg, qu, ak, dv, nv, bw} = s
  Project{+id, ti, r, c, rm} = p
  State{Map.set(&2, Project, ps, id, Project{id, ti, r, c, rm}), ts, es, n, tk, sg, qu, ak, dv, nv, bw}

def State.remove_project.fin(ts: Map<&2, Thread>, es: List<&2, Entry>, n: Nat, tk: Map<&2, Task>, sg: Map<&2, String>, qu: Map<&2, List<&2, QItem>>, ak: Map<&2, Ask>, dv: Map<&2, Device>, nv: Map<&2, Nav>, bw: List<&2, BT.World>, id: String, r: Map<&2, Project> & Project) -> State:
  (ps, p) = r
  Project{i, ti, rt, c, _} = p
  State{Map.set(&2, Project, ps, id, Project{i, ti, rt, c, True{}}), ts, es, n, tk, sg, qu, ak, dv, nv, bw}

def State.remove_project(s: State, +id: String) -> State:
  State{ps, ts, es, n, tk, sg, qu, ak, dv, nv, bw} = s
  State.remove_project.fin(ts, es, n, tk, sg, qu, ak, dv, nv, bw, id, Map.get(Project, Project.blank(id), ps, id))

def State.post(s: State, e: Entry) -> State:
  State{ps, ts, es, n, tk, sg, qu, ak, dv, nv, bw} = s
  State{ps, ts, e <> es, n, tk, sg, qu, ak, dv, nv, bw}

def State.tick(s: State) -> State:
  State{ps, ts, es, n, tk, sg, qu, ak, dv, nv, bw} = s
  State{ps, ts, es, 1n+n, tk, sg, qu, ak, dv, nv, bw}

def State.message(s: State, +thread: String, msg: String, role: Role, text: String, +at: Nat) -> State:
  match role:
    case User{}:
      State.post(State.thread((t => Thread.touched(at, t)), s, thread), Msg{msg, thread, User{}, text, at})
    case _:
      State.post(s, Msg{msg, thread, role, text, at})

def State.task.fin(f: Task -> Task, ps: Map<&2, Project>, ts: Map<&2, Thread>, es: List<&2, Entry>, n: Nat, sg: Map<&2, String>, qu: Map<&2, List<&2, QItem>>, ak: Map<&2, Ask>, dv: Map<&2, Device>, nv: Map<&2, Nav>, bw: List<&2, BT.World>, id: String, r: Map<&2, Task> & Task) -> State:
  (tk, t) = r
  State{ps, ts, es, n, Map.set(&2, Task, tk, id, f(t)), sg, qu, ak, dv, nv, bw}

# apply f to the task at `id` (a blank, settled task when absent)
def State.task(f: Task -> Task, s: State, +id: String) -> State:
  State{ps, ts, es, n, tk, sg, qu, ak, dv, nv, bw} = s
  State.task.fin(f, ps, ts, es, n, sg, qu, ak, dv, nv, bw, id, Map.get(Task, Task.blank(id), tk, id))

def State.put_task(s: State, t: Task) -> State:
  State{ps, ts, es, n, tk, sg, qu, ak, dv, nv, bw} = s
  Task{+id, p, c, d, st, su, dl, pr, mo} = t
  State{ps, ts, es, n, Map.set(&2, Task, tk, id, Task{id, p, c, d, st, su, dl, pr, mo}), sg, qu, ak, dv, nv, bw}

def State.setting(s: State, k: String, v: String) -> State:
  State{ps, ts, es, n, tk, sg, qu, ak, dv, nv, bw} = s
  State{ps, ts, es, n, tk, Map.set(&2, String, sg, k, v), qu, ak, dv, nv, bw}

def Ask.blank(id: String) -> Ask:
  Ask{id, "", "", "", "", "", False{}, ""}

def State.ask(s: State, a: Ask) -> State:
  State{ps, ts, es, n, tk, sg, qu, ak, dv, nv, bw} = s
  Ask{+id, th, k, tool, d, o, op, an} = a
  State{ps, ts, es, n, tk, sg, qu, Map.set(&2, Ask, ak, id, Ask{id, th, k, tool, d, o, op, an}), dv, nv, bw}

def Ask.close.set(m: Map<&2, Ask>, +id: String, x: Ask, a: String) -> Map<&2, Ask>:
  match x:
    case Ask{i, th, k, tool, d, o, True{}, _}:
      Map.set(&2, Ask, m, id, Ask{i, th, k, tool, d, o, False{}, a})
    case Ask{_, _, _, _, _, _, False{}, _}:
      m

def Ask.close.k(r: Map<&2, Ask> & Ask, +id: String, a: String) -> Map<&2, Ask>:
  (m, x) = r
  Ask.close.set(m, id, x, a)

# the answer closes an ask for good (a second answer changes nothing)
def State.ask.close(s: State, +id: String, a: String) -> State:
  State{ps, ts, es, n, tk, sg, qu, ak, dv, nv, bw} = s
  State{ps, ts, es, n, tk, sg, qu, Ask.close.k(Map.get(Ask, Ask.blank(id), ak, id), id, a), dv, nv, bw}

def Asks.all(s: State) -> List<&2, Ask>:
  match s:
    case State{_, _, _, _, _, _, _, ak, _, _, _}:
      Map.values(&2, Ask, ak)

# Links between threads
# ---------------------
# A message one thread sends another carries the sender in its id:
# "t:<from>:<n>". Thread ids hold no ':'.

def Link.id(+from: String, +n: String) -> String:
  SCon{Chr{116}, SCon{Chr{58}, String.append(from, SCon{Chr{58}, n})}}

# Link.from is read for every entry of every frame, so it looks at an id
# once, from the front, and gives up at the first character of any id
# that is not a link (laws link_from_id, link_from_plain). It answers what
# the ':'-fields do: the second when the first is "t" and a third follows.

def Link.colon() -> Char:
  Chr{58}

def Link.field.k(colon: Bool, +c: Char, rest: String) -> String:
  match colon:
    case True{}:
      SNil{}
    case False{}:
      SCon{c, rest}

# the text before the first ':'
def Link.field(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+c, t}:
      Link.field.k(Char.is_eq(c, Link.colon()), c, Link.field(t))

def Link.more.k(colon: Bool, rest: Bool) -> Bool:
  match colon:
    case True{}:
      True{}
    case False{}:
      rest

# whether a ':' is in s
def Link.more(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{+c, t}:
      Link.more.k(Char.is_eq(c, Link.colon()), Link.more(t))

def Link.from.e(third: Bool, +r: String) -> String:
  match third:
    case True{}:
      Link.field(r)
    case False{}:
      ""

def Link.from.d(colon: Bool, +r: String) -> String:
  match colon:
    case True{}:
      Link.from.e(Link.more(r), r)
    case False{}:
      ""

def Link.from.c(s: String) -> String:
  match s:
    case SNil{}:
      ""
    case SCon{+c, +r}:
      Link.from.d(Char.is_eq(c, Link.colon()), r)

def Link.from.b(tee: Bool, s: String) -> String:
  match tee:
    case True{}:
      Link.from.c(s)
    case False{}:
      ""

# the thread a message came from ("" for the user's own)
def Link.from(id: String) -> String:
  match id:
    case SNil{}:
      ""
    case SCon{+c, t}:
      Link.from.b(Char.is_eq(c, Chr{116}), t)

# a thread id as a link carries it (with no ':')
def Link.bare.k(colon: Bool, +c: Char, rest: String) -> String:
  match colon:
    case True{}:
      rest
    case False{}:
      SCon{c, rest}

def Link.bare(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{+c, t}:
      Link.bare.k(Char.is_eq(c, Link.colon()), c, Link.bare(t))

# Queued turns
# ------------
# A message sent while its thread's turn is running is stored at once (the
# client never holds it) and waits here, per thread, until the turn ends.

def Queue.join(+a: String, +b: String) -> String:
  Bool.pick(String, String.is_empty(a), b, a ++ "\n\n" ++ b)

def Queue.text(q: QItem) -> String:
  match q:
    case QItem{_, t}:
      t

def Queue.msg(q: QItem) -> String:
  match q:
    case QItem{m, _}:
      m

# the waiting messages as one text, oldest first, a blank line between
def Queue.texts.go(qs: List<&2, QItem>, +acc: String) -> String:
  match qs:
    case Nil{}:
      acc
    case QItem{_, t} <> rest:
      Queue.texts.go(rest, Queue.join(acc, t))

def Queue.texts(qs: List<&2, QItem>) -> String:
  Queue.texts.go(qs, "")

def Queue.edit.k(same: Bool, q: QItem, +text: String) -> QItem:
  match same q:
    case True{} QItem{m, _}:
      QItem{m, text}
    case False{} _:
      q

# the message `msg` with a new text; the rest as they were
def Queue.edit(qs: List<&2, QItem>, +msg: String, +text: String) -> List<&2, QItem>:
  match qs:
    case Nil{}:
      Nil{}
    case QItem{+m, t} <> rest:
      Queue.edit.k(String.eq(m, msg), QItem{m, t}, text) <> Queue.edit(rest, msg, text)

def Queue.drop.k(same: Bool, q: QItem, rest: List<&2, QItem>) -> List<&2, QItem>:
  match same:
    case True{}:
      rest
    case False{}:
      q <> rest

# without the message `msg`
def Queue.drop(qs: List<&2, QItem>, +msg: String) -> List<&2, QItem>:
  match qs:
    case Nil{}:
      Nil{}
    case QItem{+m, t} <> rest:
      Queue.drop.k(String.eq(m, msg), QItem{m, t}, Queue.drop(rest, msg))

def Queue.find.k(same: Bool, q: QItem, rest: Maybe<&2, QItem>) -> Maybe<&2, QItem>:
  match same:
    case True{}:
      Some{q}
    case False{}:
      rest

def Queue.find(qs: List<&2, QItem>, +msg: String) -> Maybe<&2, QItem>:
  match qs:
    case Nil{}:
      None{}
    case QItem{+m, t} <> rest:
      Queue.find.k(String.eq(m, msg), QItem{m, t}, Queue.find(rest, msg))

# q put at place i (past the end: last)
def Queue.insert(i: Nat, qs: List<&2, QItem>, q: QItem) -> List<&2, QItem>:
  match i qs:
    case 0n _:
      q <> qs
    case _ Nil{}:
      [q]
    case 1n+j x <> rest:
      x <> Queue.insert(j, rest, q)

def Queue.move.k(m: Maybe<&2, QItem>, +qs: List<&2, QItem>, +msg: String, to: Nat) -> List<&2, QItem>:
  match m:
    case Some{q}:
      Queue.insert(to, Queue.drop(qs, msg), q)
    case None{}:
      qs

# the message `msg` moved to place `to`; an unknown message moves nothing
def Queue.move(+qs: List<&2, QItem>, +msg: String, to: Nat) -> List<&2, QItem>:
  Queue.move.k(Queue.find(qs, msg), qs, msg, to)

def State.queue.k(f: List<&2, QItem> -> List<&2, QItem>, r: Map<&2, List<&2, QItem>> & List<&2, QItem>, +th: String) -> Map<&2, List<&2, QItem>>:
  (m, cur) = r
  Map.set(&2, List<&2, QItem>, m, th, f(cur))

# apply f to a thread's queue
def State.queue(f: List<&2, QItem> -> List<&2, QItem>, s: State, +th: String) -> State:
  State{ps, ts, es, n, tk, sg, qu, ak, dv, nv, bw} = s
  State{ps, ts, es, n, tk, sg, State.queue.k(f, Map.get(List<&2, QItem>, Nil{}, qu, th), th), ak, dv, nv, bw}

def State.enqueue(s: State, +th: String, +msg: String, +text: String) -> State:
  State.queue((qs => List.append(&2, QItem, qs, [QItem{msg, text}])), s, th)

def State.take(s: State, +th: String) -> State:
  State.queue((qs => Nil{}), s, th)

def Queue.items.k(r: Map<&2, List<&2, QItem>> & List<&2, QItem>) -> List<&2, QItem>:
  (_, v) = r
  v

# a thread's waiting messages, next first
def Queue.items(s: State, +th: String) -> List<&2, QItem>:
  match s:
    case State{_, _, _, _, _, _, qu, _, _, _, _}:
      Queue.items.k(Map.get(List<&2, QItem>, Nil{}, qu, th))

# a setting's value, or d when unset
def State.get.k(r: Map<&2, String> & String) -> String:
  (_, v) = r
  v

# what waits to be sent in a thread ("" for nothing)
def Queue.real(qs: List<&2, QItem>) -> Bool:
  match qs:
    case Nil{}:
      False{}
    case QItem{+m, _} <> t:
      Bool.or(Bool.not(String.starts_with(m, "handoff:")), Queue.real(t))

# whether a thread has a message waiting (handed-over context alone waits
# for a message to go with: it never starts a turn by itself, law
# handoff_never_runs_alone)
def Queue.waiting(s: State, +th: String) -> Bool:
  Queue.real(Queue.items(s, th))

def Queue.of(s: State, +th: String) -> String:
  Queue.texts(Queue.items(s, th))

def Setting.get(s: State, +k: String, d: String) -> String:
  match s:
    case State{_, _, _, _, _, sg, qu, ak, _, _, _}:
      State.get.k(Map.get(String, d, sg, k))

# Providers in turn
# -----------------
# A thread may go on with another provider between turns (V2's provider
# switch). Each provider keeps its own session of the thread (the setting
# session.<thread>.<provider>) and how many of the thread's entries it had
# seen when it was left (seen.<thread>.<provider>), so coming back resumes
# its own conversation and it is handed only what it missed (laws
# switch_*).

def Switch.session.key(+th: String, +p: String) -> String:
  "session." ++ th ++ "." ++ p

def Switch.seen.key(+th: String, +p: String) -> String:
  "seen." ++ th ++ "." ++ p

def Switch.count.k(hit: Bool, n: Nat) -> Nat:
  match hit:
    case True{}:
      1n+n
    case False{}:
      n

def Switch.of(e: Entry) -> String:
  match e:
    case Msg{_, t, _, _, _}:
      t
    case Act{_, t, _, _, _, _}:
      t

# how many entries a thread has
def Switch.count(es: List<&2, Entry>, +th: String) -> Nat:
  match es:
    case Nil{}:
      0n
    case +e <> t:
      Switch.count.k(String.eq(Switch.of(e), th), Switch.count(t, th))

def Switch.prov(t: Thread) -> String:
  match t:
    case Thread{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, pr, _, _, _, _, _}:
      pr

def Switch.sess(t: Thread) -> String:
  match t:
    case Thread{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, se, _}:
      se

def Switch.set(p: String, m: String, se: String, t: Thread) -> Thread:
  Thread{id, pj, ti, c, a, tu, pe, ar, o, sa, ua, pi, en, br, wt, _, _, rm, im, _, de} = t
  Thread{id, pj, ti, c, a, tu, pe, ar, o, sa, ua, pi, en, br, wt, p, m, rm, im, se, de}

def State.entries.all(s: State) -> List<&2, Entry>:
  match s:
    case State{_, _, es, _, _, _, _, _, _, _, _}:
      es

def State.thread.get.k(r: Map<&2, Thread> & Thread) -> Thread:
  (_, t) = r
  t

def State.thread.get(s: State, +id: String) -> Thread:
  match s:
    case State{_, ts, _, _, _, _, _, _, _, _, _}:
      State.thread.get.k(Map.get(Thread, Thread.blank(id), ts, id))

def State.switch.k(+s: State, +th: String, +old: String, +oldse: String, +p: String, m: String) -> State:
  +s1 = State.setting(State.setting(s, Switch.session.key(th, old), oldse), Switch.seen.key(th, old), Nat.show(Switch.count(State.entries.all(s), th)))
  State.thread((t => Switch.set(p, m, Setting.get(s1, Switch.session.key(th, p), ""), t)), s1, th)

def State.switch(+s: State, +th: String, +p: String, m: String) -> State:
  State.switch.k(s, th, Switch.prov(State.thread.get(s, th)), Switch.sess(State.thread.get(s, th)), p, m)

# how many of a thread's entries a provider had seen when it was left
# (0: it never took part)
# a count written in decimal (Nat.read is slow to check in laws)
def Switch.num(s: String, +acc: Nat) -> Nat:
  match s:
    case SNil{}:
      acc
    case SCon{Chr{+c}, t}:
      Switch.num(t, Nat.add(Nat.mul(acc, 10n), U32.to_nat((c - 48 : U32))))

def Switch.seen(s: State, +th: String, +p: String) -> Nat:
  Switch.num(Setting.get(s, Switch.seen.key(th, p), "0"), 0n)

# Context usage
# -------------
# How much of its model's context window a thread's session holds, as
# "<used>/<window>" in the setting usage.<thread> (laws usage_*).

def Usage.key(+th: String) -> String:
  "usage." ++ th

def Usage.part(ps: List<&2, String>, +i: Nat) -> Nat:
  Switch.num(Maybe.default(&2, String, List.head(&2, String, List.drop(&2, String, ps, i)), "0"), 0n)

def Usage.used(+v: String) -> Nat:
  Usage.part(String.split(v, '/'), 0n)

def Usage.window(+v: String) -> Nat:
  Usage.part(String.split(v, '/'), 1n)

def Usage.keep(+new: Nat, +old: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_eq(new, 0n), old, new)

# a new reading over the old one (0 keeps the old part)
def Usage.merge(+old: String, +used: Nat, +window: Nat) -> String:
  Nat.show(Usage.keep(used, Usage.used(old))) ++ "/" ++ Nat.show(Usage.keep(window, Usage.window(old)))

def State.usage(+s: State, +th: String, +used: Nat, +window: Nat) -> State:
  State.setting(s, Usage.key(th), Usage.merge(Setting.get(s, Usage.key(th), ""), used, window))

# Forks
# -----
# A fork remembers its source thread (the setting fork.<id>).

def Fork.key(+id: String) -> String:
  "fork." ++ id

# the thread a fork was made from ("" for a thread that is no fork)
def Fork.source(s: State, +id: String) -> String:
  Setting.get(s, Fork.key(id), "")

def Merge.branch(t: Thread) -> String:
  match t:
    case Thread{_, _, _, _, _, _, _, _, _, _, _, _, _, br, _, _, _, _, _, _, _}:
      br

def Merge.id(t: Thread) -> String:
  match t:
    case Thread{i, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      i

# whether a merge of this thread's branch should still settle it: it has a
# branch, sits on the pinned or active shelf, and no merge is recorded
def Merge.due(+s: State, +t: Thread) -> Bool:
  Merge.due.k(Shelf.of(t), Merge.branch(t), Setting.get(s, Merge.key(Merge.id(t)), ""))

def Worktree.clock(sh: Shelf, +settled_at: Nat, +activity: Nat) -> Nat:
  match sh:
    case Settled{}:
      settled_at
    case _:
      activity

def Worktree.drop.t(t: Thread, +now: Nat, +window: Nat, +merged: String, +sh: Shelf) -> Bool:
  match t:
    case Thread{_, _, _, _, +a, tu, +pe, _, _, +sa, _, _, _, _, +wt, _, _, _, _, _, _}:
      Worktree.drop.k(Thread.busy(tu, pe), sh, Worktree.ours(wt), Bool.not(String.is_empty(merged)), Settle.stale(now, Worktree.clock(sh, sa, a), window))

# whether this thread's worktree is removed now: put away for the window
# (settled: since it settled; hidden: since its last activity), or merged
def Worktree.drop(+s: State, +t: Thread, +now: Nat, +window: Nat) -> Bool:
  Worktree.drop.t(t, now, window, Setting.get(s, Merge.key(Merge.id(t)), ""), Shelf.of(t))

# Devices
# -------
# Push registrations, keyed by token: registering a token again replaces
# it (law device_register_once). An empty token is not a device: that is
# what clients fold, since the server sends them device events without it.

def State.register.k(empty: Bool, s: State, +tok: String, p: String, k: String, th: String, e: String, b: String, at: Nat) -> State:
  match empty:
    case True{}:
      s
    case False{}:
      State{ps, ts, es, n, tk, sg, qu, ak, dv, nv, bw} = s
      State{ps, ts, es, n, tk, sg, qu, ak, Map.set(&2, Device, dv, tok, Device{tok, p, k, th, e, b, at}), nv, bw}

def State.register(s: State, +tok: String, p: String, k: String, th: String, e: String, b: String, at: Nat) -> State:
  State.register.k(String.is_empty(tok), s, tok, p, k, th, e, b, at)

def State.unregister(s: State, tok: String) -> State:
  State{ps, ts, es, n, tk, sg, qu, ak, dv, nv, bw} = s
  State{ps, ts, es, n, tk, sg, qu, ak, Map.del(&2, Device, dv, tok), nv, bw}

# every registered device
# the read model as the window may hold it: no devices (their tokens stay
# in the hub, as the wire leaves them out; law window_state_private)
def State.private(s: State) -> State:
  State{ps, ts, es, n, tk, sg, qu, ak, _, nv, bw} = s
  State{ps, ts, es, n, tk, sg, qu, ak, Map.new(&2, Device), nv, bw}

def State.devices(s: State) -> Map<&2, Device>:
  match s:
    case State{_, _, _, _, _, _, _, _, dv, _, _}:
      dv

def State.nav.k(f: Nav -> Nav, r: Map<&2, Nav> & Nav, +id: String) -> Map<&2, Nav>:
  (m, n) = r
  Map.set(&2, Nav, m, id, f(n))

# apply f to a thread's sidebar extension
def State.nav(f: Nav -> Nav, s: State, +id: String) -> State:
  State{ps, ts, es, n, tk, sg, qu, ak, dv, nv, bw} = s
  State{ps, ts, es, n, tk, sg, qu, ak, dv, State.nav.k(f, Map.get(Nav, Nav.blank(), nv, id), id), bw}

# every thread's sidebar extension
def State.navs(s: State) -> Map<&2, Nav>:
  match s:
    case State{_, _, _, _, _, _, _, _, _, nv, bw}:
      nv

def State.bots.k(bw: List<&2, BT.World>) -> BT.World:
  Maybe.default(&2, BT.World, List.head(&2, BT.World, bw), BT.World.empty())

def State.world(f: BT.World -> BT.World, s: State) -> State:
  match s:
    case State{ps, ts, es, n, tk, sg, qu, ak, dv, nv, bw}:
      State{ps, ts, es, n, tk, sg, qu, ak, dv, nv, [f(State.bots.k(bw))]}

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
      State.post(s, Act{act, thread, tone, kind, summary, at})
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
    case TaskDelegated{id, parent, child, depth, provider, model, _}:
      State.put_task(s, Task{id, parent, child, depth, TaskQueued{}, "", False{}, provider, model})
    case TaskStateSet{+id, st, summary, _}:
      State.task((t => Task.step(t, st, summary)), s, id)
    case TaskDelivered{+id, _}:
      State.task((t => Task.delivered_set(t)), s, id)
    case SettingSet{k, v, _}:
      State.setting(s, k, v)
    case TurnQueued{th, msg, text, _}:
      State.enqueue(s, th, msg, text)
    case QueueTaken{th, _}:
      State.take(s, th)
    case AskOpened{id, th, k, tool, d, o, _}:
      State.ask(s, Ask{id, th, k, tool, d, o, True{}, ""})
    case AskClosed{+id, a, _}:
      State.ask.close(s, id, a)
    case DeviceRegistered{+tok, p, k, th, e, b, at}:
      State.register(s, tok, p, k, th, e, b, at)
    case DeviceDropped{tok, _}:
      State.unregister(s, tok)
    case ThreadSnoozed{+id, +until, _}:
      State.nav((x => Nav.snoozed(x, until)), s, id)
    case ThreadOrdered{+id, +section, +key, _}:
      State.nav((x => Nav.keyed(x, section, key)), s, id)
    case WorktreeSkipped{+id, _}:
      State.thread((t => Thread.local(t)), s, id)
    case ThreadMerged{+id, url, +at}:
      State.setting(State.thread((t => Thread.settled(True{}, at, t)), s, id), Merge.key(id), url)
    case WorktreeRemoved{+id, _}:
      State.thread((t => Thread.unrooted(t)), s, id)
    case UsageSet{+th, used, window, _}:
      State.usage(s, th, used, window)
    case BotSet{id, name, thread, look, persona, at}:
      State.world((w => BT.World.bot_set(w, id, name, thread, look, persona, at)), s)
    case BotDeleted{id, _}:
      State.world((w => BT.World.bot_deleted(w, id)), s)
    case RoomSet{id, name, members, at}:
      State.world((w => BT.World.room_set(w, id, name, members, at)), s)
    case RoomDeleted{id, _}:
      State.world((w => BT.World.room_deleted(w, id)), s)
    case RoomPosted{id, room, from, text, hop, at}:
      State.world((w => BT.World.posted(w, BT.Post{id, room, from, text, hop, at})), s)
    case HookSet{id, bot, name, revoked, at}:
      State.world((w => BT.World.hook_set(w, id, bot, name, revoked, at)), s)
    case HookHit{id, at}:
      State.world((w => BT.World.hook_hit(w, id, at)), s)
    case RoutineSet{id, bot, name, cron, prompt, on, at}:
      State.world((w => BT.World.routine_set(w, id, bot, name, cron, prompt, on, at)), s)
    case RoutineDeleted{id, _}:
      State.world((w => BT.World.routine_deleted(w, id)), s)
    case RoutineFired{id, at}:
      State.world((w => BT.World.routine_fired(w, id, at)), s)
    case MemorySaved{bot, key, kind, text, tags, at}:
      State.world((w => BT.World.mem_saved(w, bot, key, kind, text, tags, at)), s)
    case MemoryForgot{bot, key, _}:
      State.world((w => BT.World.mem_forgot(w, bot, key)), s)
    case SpaceSet{bot, spec, _}:
      State.world((w => BT.World.space_set(w, bot, spec)), s)
    case PeerSet{id, name, url, revoked, at}:
      State.world((w => BT.World.peer_set(w, id, name, url, revoked, at)), s)
    case BotWoke{bot, hop, _}:
      State.world((w => BT.World.woke(w, bot, hop)), s)
    case SpacePageSet{bot, html, at}:
      State.world((w => BT.World.spage_set(w, bot, html, at)), s)
    case TodosSet{+th, todos, _}:
      State.setting(s, "todos." ++ th, todos)
    case ProviderSet{+id, +p, m, _}:
      State.switch(s, id, p, m)
    case ThreadForked{+id, +src, _}:
      State.setting(s, Fork.key(id), src)
    case QueueEdited{+th, +msg, +text, _}:
      State.queue((qs => Queue.edit(qs, msg, text)), s, th)
    case QueueRemoved{+th, +msg, _}:
      State.queue((qs => Queue.drop(qs, msg)), s, th)
    case QueueMoved{+th, +msg, to, _}:
      State.queue((qs => Queue.move(qs, msg, to)), s, th)
    case QueueTakenOne{+th, +msg, _}:
      State.queue((qs => Queue.drop(qs, msg)), s, th)
    case ProjectOrdered{+id, +key, _}:
      State.nav((x => Nav.keyed(x, "active", key)), s, Nav.project(id))

def State.bots(s: State) -> BT.World:
  match s:
    case State{_, _, _, _, _, _, _, _, _, _, bw}:
      State.bots.k(bw)

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
  Shelves{pinned: List<&2, Thread>, active: List<&2, Thread>, settled: List<&2, Thread>, hidden: List<&2, Thread>, snoozed: List<&2, Thread>}

def Shelves.put(sh: Shelf, t: Thread, s: Shelves) -> Shelves:
  match sh s:
    case Pinned{} Shelves{p, a, st, h, sn}:
      Shelves{t <> p, a, st, h, sn}
    case Active{} Shelves{p, a, st, h, sn}:
      Shelves{p, t <> a, st, h, sn}
    case Settled{} Shelves{p, a, st, h, sn}:
      Shelves{p, a, t <> st, h, sn}
    case Hidden{} Shelves{p, a, st, h, sn}:
      Shelves{p, a, st, t <> h, sn}
    case Snoozed{} Shelves{p, a, st, h, sn}:
      Shelves{p, a, st, h, t <> sn}

# every thread lands on exactly one shelf (law Sidebar.split_count)
def Sidebar.split(ts: List<&2, Thread>) -> Shelves:
  match ts:
    case Nil{}:
      Shelves{Nil{}, Nil{}, Nil{}, Nil{}, Nil{}}
    case +t <> rest:
      Shelves.put(Shelf.of(t), t, Sidebar.split(rest))

def Shelves.count(s: Shelves) -> Nat:
  Shelves{p, a, st, h, sn} = s
  Nat.add(List.length(&2, Thread, p), Nat.add(List.length(&2, Thread, a), Nat.add(List.length(&2, Thread, st), Nat.add(List.length(&2, Thread, h), List.length(&2, Thread, sn)))))

def Thread.turn(t: Thread) -> TurnState:
  match t:
    case Thread{_, _, _, _, _, tu, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      tu

def Thread.provider(t: Thread) -> String:
  match t:
    case Thread{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, pr, _, _, _, _, _}:
      pr

def Thread.id(t: Thread) -> String:
  match t:
    case Thread{i, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      i

def Thread.hidden(t: Thread) -> Bool:
  match t:
    case Thread{_, _, _, _, _, _, _, ar, _, _, _, _, _, _, _, _, _, _, _, _, de}:
      Bool.or(ar, de)

def Shelf.at.k(hidden: Bool, snoozed: Bool, sh: Shelf) -> Shelf:
  match hidden snoozed:
    case False{} True{}:
      Snoozed{}
    case _ _:
      sh

# the shelf with the snooze: a thread snoozed past now sits on Snoozed
# (above settled, whatever its pin or settle state); it goes back where it
# was when the snooze ends
def Shelf.at(+t: Thread, +until: Nat, +now: Nat) -> Shelf:
  Shelf.at.k(Thread.hidden(t), Snooze.on(now, until), Shelf.of(t))

# every thread lands on exactly one shelf, snoozed ones included (law
# sidebar_split_at_count)
def Sidebar.split.at(ts: List<&2, Thread>, +navs: Map<&2, Nav>, +now: Nat) -> Shelves:
  match ts:
    case Nil{}:
      Shelves{Nil{}, Nil{}, Nil{}, Nil{}, Nil{}}
    case +t <> rest:
      Shelves.put(Shelf.at(t, Nav.until(Nav.get(navs, Thread.id(t))), now), t, Sidebar.split.at(rest, navs, now))

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
  Shelves{p, a, st, h, sn} = s
  Shelves{List.sort(~Thread, ~Thread.before, p), List.sort(~Thread, ~Thread.before, a), List.sort(~Thread, ~Thread.settled_before, st), h, sn}

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

# how many changes have been folded in
def State.seq(s: State) -> Nat:
  match s:
    case State{_, _, _, n, _, _, _, ak, _, _, _}:
      n

# Order keys
# ----------
# A manual place on a shelf is a key: a binary fraction 0.b1b2b3... read
# with zeros after its last digit (so "1" and "10" are the same place).
# Between any two different places there is another (laws key_mid_above,
# key_mid_below), and past any place there is a later one (law key_after),
# so dragging a thread never renumbers its neighbours. Keys travel as hex,
# four digits a character.

def Key.cmpz(t: List<&2, Bool>) -> Cmp:
  match t:
    case Nil{}:
      EQ{}
    case False{} <> r:
      Key.cmpz(r)
    case True{} <> _:
      LT{}

def Key.cmpz_r(s: List<&2, Bool>) -> Cmp:
  match s:
    case Nil{}:
      EQ{}
    case False{} <> r:
      Key.cmpz_r(r)
    case True{} <> _:
      GT{}

# two places in order
def Key.cmp(a: List<&2, Bool>, b: List<&2, Bool>) -> Cmp:
  match a:
    case Nil{}:
      Key.cmpz(b)
    case x <> s:
      match x b:
        case False{} Nil{}:
          Key.cmpz_r(s)
        case True{} Nil{}:
          GT{}
        case False{} False{} <> t:
          Key.cmp(s, t)
        case False{} True{} <> _:
          LT{}
        case True{} False{} <> _:
          GT{}
        case True{} True{} <> t:
          Key.cmp(s, t)

def Key.lt(a: List<&2, Bool>, b: List<&2, Bool>) -> Bool:
  Cmp.is_lt(Key.cmp(a, b))

# a place after s
def Key.after(s: List<&2, Bool>) -> List<&2, Bool>:
  match s:
    case Nil{}:
      [True{}]
    case False{} <> _:
      [True{}]
    case True{} <> r:
      True{} <> Key.after(r)

# a place between 0 and t
def Key.midz(t: List<&2, Bool>) -> List<&2, Bool>:
  match t:
    case Nil{}:
      [True{}]
    case False{} <> r:
      False{} <> Key.midz(r)
    case True{} <> _:
      [False{}, True{}]

# a place between a and b (when a is before b)
def Key.mid(a: List<&2, Bool>, b: List<&2, Bool>) -> List<&2, Bool>:
  match a:
    case Nil{}:
      Key.midz(b)
    case x <> s:
      match x b:
        case _ Nil{}:
          [True{}]
        case False{} False{} <> t:
          False{} <> Key.mid(s, t)
        case False{} True{} <> _:
          False{} <> Key.after(s)
        case True{} False{} <> _:
          [True{}]
        case True{} True{} <> t:
          True{} <> Key.mid(s, t)

def Key.bit(+v: U32, +m: U32) -> Bool:
  U32.is_ne(U32.and(v, m), 0)

def Key.hexval(+c: U32) -> U32:
  Bool.pick(U32, Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57)), (c - 48 : U32),
    Bool.pick(U32, Bool.and(U32.is_ge(c, 97), U32.is_le(c, 102)), (c - 87 : U32), 0))

def Key.nibble(+v: U32, rest: List<&2, Bool>) -> List<&2, Bool>:
  Key.bit(v, 8) <> Key.bit(v, 4) <> Key.bit(v, 2) <> Key.bit(v, 1) <> rest

# a key from its hex ("" is no key)
def Key.read(s: String) -> List<&2, Bool>:
  match s:
    case SNil{}:
      Nil{}
    case SCon{Chr{+c}, t}:
      Key.nibble(Key.hexval(c), Key.read(t))

def Key.b(b: Bool, +v: U32) -> U32:
  match b:
    case True{}:
      v
    case False{}:
      0

def Key.hex(a: Bool, b: Bool, c: Bool, d: Bool) -> Char:
  +v = {(Key.b(a, 8) + Key.b(b, 4) + Key.b(c, 2) + Key.b(d, 1) : U32) : U32}
  Chr{Bool.pick(U32, U32.is_lt(v, 10), (v + 48 : U32), (v + 87 : U32))}

def Key.show(bs: List<&2, Bool>) -> String:
  match bs:
    case Nil{}:
      SNil{}
    case a <> Nil{}:
      SCon{Key.hex(a, False{}, False{}, False{}), SNil{}}
    case a <> b <> Nil{}:
      SCon{Key.hex(a, b, False{}, False{}), SNil{}}
    case a <> b <> c <> Nil{}:
      SCon{Key.hex(a, b, c, False{}), SNil{}}
    case a <> b <> c <> d <> t:
      SCon{Key.hex(a, b, c, d), Key.show(t)}

# Manual order
# ------------
# Dragging a thread gives the hub the shelf's new order. Threads keep their
# keys where these already fall in order; the rest get a key between their
# neighbours (or after the one above). Threads past the moved one that have
# no key, with none below them keyed either, keep none: they already sit
# below the keyed ones, by recency.

type OKey is Data:
  OKey{id: String, key: String}

def Order.unkeyed(xs: List<&2, OKey>) -> Bool:
  match xs:
    case Nil{}:
      True{}
    case OKey{_, +k} <> t:
      Bool.and(String.is_empty(k), Order.unkeyed(t))

def Order.next(xs: List<&2, OKey>) -> List<&2, Bool>:
  match xs:
    case Nil{}:
      Nil{}
    case OKey{_, k} <> _:
      Key.read(k)

# what one thread's key becomes: skipped, kept, or the new key
type OStep is Data:
  OStep{skip: Bool, keep: Bool, key: List<&2, Bool>}

def Order.fresh(usable: Bool, +prev: List<&2, Bool>, +nxt: List<&2, Bool>) -> List<&2, Bool>:
  match usable:
    case True{}:
      Key.mid(prev, nxt)
    case False{}:
      Key.after(prev)

def Order.step(+k: List<&2, Bool>, +nxt: List<&2, Bool>, +prev: List<&2, Bool>, +skip: Bool) -> OStep:
  +keyed = Bool.not(List.is_empty(&2, Bool, k))
  +nkeyed = Bool.not(List.is_empty(&2, Bool, nxt))
  OStep{skip, Bool.and(Bool.and(keyed, Key.lt(prev, k)), Bool.or(Bool.not(nkeyed), Key.lt(k, nxt))),
    Order.fresh(Bool.and(nkeyed, Key.lt(prev, nxt)), prev, nxt)}

def Order.prev(o: OStep, +k: List<&2, Bool>, +prev: List<&2, Bool>) -> List<&2, Bool>:
  match o:
    case OStep{True{}, _, _}:
      prev
    case OStep{False{}, True{}, _}:
      k
    case OStep{False{}, False{}, n}:
      n

def Order.emit(o: OStep, +id: String, rest: List<&2, OKey>) -> List<&2, OKey>:
  match o:
    case OStep{False{}, False{}, n}:
      OKey{id, Key.show(n)} <> rest
    case _:
      rest

def Order.go(xs: List<&2, OKey>, +moved: String, +prev: List<&2, Bool>, +past: Bool) -> List<&2, OKey>:
  match xs:
    case Nil{}:
      Nil{}
    case OKey{+id, +k} <> +rest:
      +o = Order.step(Key.read(k), Order.next(rest), prev, Bool.and(Bool.and(past, String.is_empty(k)), Order.unkeyed(rest)))
      Order.emit(o, id, Order.go(rest, moved, Order.prev(o, Key.read(k), prev), Bool.or(past, String.eq(id, moved))))

# the key changes that put a shelf in this order (xs: its threads in the new
# order with their keys now; moved: the thread dragged)
def Order.plan(+xs: List<&2, OKey>, +moved: String) -> List<&2, OKey>:
  Order.go(xs, moved, Nil{}, False{})

def Order.remove(xs: List<&2, String>, +x: String) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case +h <> +t:
      Bool.pick(List<&2, String>, String.eq(h, x), t, h <> Order.remove(t, x))

def Order.insert(i: Nat, xs: List<&2, String>, +x: String) -> List<&2, String>:
  match i xs:
    case 0n _:
      x <> xs
    case 1n+j h <> t:
      h <> Order.insert(j, t, x)
    case 1n+j Nil{}:
      [x]

def Order.index(xs: List<&2, String>, +x: String, +i: Nat) -> Nat:
  match xs:
    case Nil{}:
      i
    case +h <> t:
      Bool.pick(Nat, String.eq(h, x), i, Order.index(t, x, 1n+i))

# a shelf's ids with x moved to where the thread at index `to` was
def Order.move(+xs: List<&2, String>, +x: String, +to: Nat) -> List<&2, String>:
  Order.insert(to, Order.remove(xs, x), x)

# Sidebar order with keys and snoozes
# -----------------------------------
# Pinned and active: threads with a key first, by key; the rest by
# max(created, unsettled), newest first. Snoozed: the soonest to wake
# first. Settled: by settle time, newest first.

type Slot is Data:
  Slot{keyed: Bool, key: List<&2, Bool>, rank: Nat, t: Thread}

def Slot.before(a: Slot, b: Slot) -> Bool:
  match a b:
    case Slot{True{}, ka, _, _} Slot{True{}, kb, _, _}:
      Cmp.is_le(Key.cmp(ka, kb))
    case Slot{True{}, _, _, _} Slot{False{}, _, _, _}:
      True{}
    case Slot{False{}, _, _, _} Slot{True{}, _, _, _}:
      False{}
    case Slot{False{}, _, +ra, _} Slot{False{}, _, +rb, _}:
      Nat.is_ge(ra, rb)

def Slot.soon(a: Slot, b: Slot) -> Bool:
  match a b:
    case Slot{_, _, +ra, _} Slot{_, _, +rb, _}:
      Nat.is_le(ra, rb)

def Slot.keyed(+k: List<&2, Bool>, +rank: Nat, t: Thread) -> Slot:
  Slot{Bool.not(List.is_empty(&2, Bool, k)), k, rank, t}

def Slots.of(ts: List<&2, Thread>, +navs: Map<&2, Nav>, +section: String) -> List<&2, Slot>:
  match ts:
    case Nil{}:
      Nil{}
    case +t <> rest:
      Slot.keyed(Key.read(Nav.key(Nav.get(navs, Thread.id(t)), section)), Thread.rank(t), t) <> Slots.of(rest, navs, section)

def Slots.wake(ts: List<&2, Thread>, +navs: Map<&2, Nav>) -> List<&2, Slot>:
  match ts:
    case Nil{}:
      Nil{}
    case +t <> rest:
      Slot{False{}, Nil{}, Nav.until(Nav.get(navs, Thread.id(t))), t} <> Slots.wake(rest, navs)

def Slots.threads(xs: List<&2, Slot>) -> List<&2, Thread>:
  match xs:
    case Nil{}:
      Nil{}
    case Slot{_, _, _, t} <> rest:
      t <> Slots.threads(rest)

def Sidebar.order.at(s: Shelves, +navs: Map<&2, Nav>) -> Shelves:
  Shelves{p, a, st, h, sn} = s
  Shelves{Slots.threads(List.sort(~Slot, ~Slot.before, Slots.of(p, navs, "pinned"))),
    Slots.threads(List.sort(~Slot, ~Slot.before, Slots.of(a, navs, "active"))),
    List.sort(~Thread, ~Thread.settled_before, st), h,
    Slots.threads(List.sort(~Slot, ~Slot.soon, Slots.wake(sn, navs)))}

# a project's threads on their shelves, in sidebar order, at time now
def Sidebar.at(ts: List<&2, Thread>, +navs: Map<&2, Nav>, +now: Nat) -> Shelves:
  Sidebar.order.at(Sidebar.split.at(ts, navs, now), navs)

def Archive.keep(keep: Bool, t: Thread, rest: List<&2, Thread>) -> List<&2, Thread>:
  match keep:
    case True{}:
      t <> rest
    case False{}:
      rest

def Archive.go(ts: List<&2, Thread>) -> List<&2, Thread>:
  match ts:
    case Nil{}:
      Nil{}
    case Thread{id, p, ti, c, a, tu, pe, +ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, +de} <> rest:
      Archive.keep(Bool.and(ar, Bool.not(de)), Thread{id, p, ti, c, a, tu, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de}, Archive.go(rest))

# the archived (not deleted) threads of a hidden shelf, newest first
def Archive.of(hidden: List<&2, Thread>) -> List<&2, Thread>:
  List.sort(~Thread, ~Thread.before, Archive.go(hidden))

# Sidebar status
# --------------
# The dot on a thread's row says the most urgent thing about it: an
# approval waiting > a question or plan waiting > a turn working > a failed
# turn > queued messages > ready (laws status_*).

type Status is Data:
  StApproval{}
  StInput{}
  StWorking{}
  StFailed{}
  StQueued{}
  StReady{}

def Status.of.q(queued: Bool) -> Status:
  match queued:
    case True{}:
      StQueued{}
    case False{}:
      StReady{}

def Status.of.t(t: TurnState, queued: Bool) -> Status:
  match t:
    case Running{}:
      StWorking{}
    case Failed{}:
      StFailed{}
    case _:
      Status.of.q(queued)

def Status.of.i(input: Bool, t: TurnState, queued: Bool) -> Status:
  match input:
    case True{}:
      StInput{}
    case False{}:
      Status.of.t(t, queued)

def Status.of(approval: Bool, input: Bool, t: TurnState, queued: Bool) -> Status:
  match approval:
    case True{}:
      StApproval{}
    case False{}:
      Status.of.i(input, t, queued)

# how urgent a status is (5: most)
def Status.rank(s: Status) -> Nat:
  match s:
    case StApproval{}:
      5n
    case StInput{}:
      4n
    case StWorking{}:
      3n
    case StFailed{}:
      2n
    case StQueued{}:
      1n
    case StReady{}:
      0n

def Status.name(s: Status) -> String:
  match s:
    case StApproval{}:
      "approval"
    case StInput{}:
      "input"
    case StWorking{}:
      "working"
    case StFailed{}:
      "failed"
    case StQueued{}:
      "queued"
    case StReady{}:
      "ready"

# Thread phase
# ------------
# The line at the end of a thread's timeline says what the thread is doing
# now: an approval waiting > a question or plan waiting > a turn working >
# child tasks still running after the turn (monitoring) > a failed turn >
# messages queued > a finished turn > a stopped turn > nothing yet (laws
# phase_*).

type Phase is Data:
  PhApproval{}
  PhInput{}
  PhWorking{}
  PhMonitoring{n: Nat}
  PhFailed{}
  PhQueued{}
  PhComplete{}
  PhStopped{}
  PhIdle{}

def Phase.of.t(t: TurnState, queued: Bool) -> Phase:
  match t queued:
    case Failed{} _:
      PhFailed{}
    case _ True{}:
      PhQueued{}
    case Completed{} False{}:
      PhComplete{}
    case Interrupted{} False{}:
      PhStopped{}
    case _ False{}:
      PhIdle{}

def Phase.of.w(+tasks: Nat, t: TurnState, queued: Bool) -> Phase:
  match t:
    case Running{}:
      PhWorking{}
    case _:
      Bool.pick(Phase, Nat.is_gt(tasks, 0n), PhMonitoring{tasks}, Phase.of.t(t, queued))

def Phase.of.i(input: Bool, +tasks: Nat, t: TurnState, queued: Bool) -> Phase:
  match input:
    case True{}:
      PhInput{}
    case False{}:
      Phase.of.w(tasks, t, queued)

# tasks: the thread's child tasks not yet finished
def Phase.of(approval: Bool, input: Bool, +tasks: Nat, t: TurnState, queued: Bool) -> Phase:
  match approval:
    case True{}:
      PhApproval{}
    case False{}:
      Phase.of.i(input, tasks, t, queued)

# the word for a phase (the web's class, the color's key)
def Phase.name(p: Phase) -> String:
  match p:
    case PhApproval{}:
      "approval"
    case PhInput{}:
      "input"
    case PhWorking{}:
      "working"
    case PhMonitoring{_}:
      "monitoring"
    case PhFailed{}:
      "failed"
    case PhQueued{}:
      "queued"
    case PhComplete{}:
      "complete"
    case PhStopped{}:
      "stopped"
    case PhIdle{}:
      "idle"

def Phase.tasks(+n: Nat) -> String:
  Nat.show(n) ++ Bool.pick(String, Nat.is_eq(n, 1n), " task", " tasks")

# what the line says ("" for a thread with nothing to say)
def Phase.label(p: Phase) -> String:
  match p:
    case PhApproval{}:
      "Waiting for approval"
    case PhInput{}:
      "Waiting for input"
    case PhWorking{}:
      "Working…"
    case PhMonitoring{+n}:
      "Monitoring " ++ Phase.tasks(n)
    case PhFailed{}:
      "Failed"
    case PhQueued{}:
      "Queued"
    case PhComplete{}:
      "Complete"
    case PhStopped{}:
      "Stopped"
    case PhIdle{}:
      ""
