import Base
import ./json.bend as J
import ./model.bend as M
import ./client.bend as U
import ./bot.bend as BT
import ./space.bend as SP

# What the bots' screens show, for every client (the window, the web and
# the phones draw from these; docs/bots.md). The sidebar's cats with their
# moods, the rooms, and the parts of a bot's view.

# Moods
# -----
# A cat's mood comes from its thread's status: it waits for you (ears up)
# before anything else, works or talks while its turn runs, thinks while
# something is queued, looks unwell after a failure, and falls asleep
# after a quarter hour of rest (laws bot_mood_wait, bot_mood_sleep_still).

def Mood.of.r(idle: Bool) -> String:
  match idle:
    case True{}:
      "sleep"
    case False{}:
      "idle"

def Mood.of(s: M.Status, talked: Bool, idle: Bool) -> String:
  match s:
    case M.StApproval{}:
      "wait"
    case M.StInput{}:
      "wait"
    case M.StWorking{}:
      Bool.pick(String, talked, "talk", "work")
    case M.StQueued{}:
      "think"
    case M.StFailed{}:
      "error"
    case M.StReady{}:
      Mood.of.r(idle)

# a bot on another machine, from the state its hub reports
def Mood.of.name(+state: String) -> String:
  Bool.pick(String, Bool.or(String.eq(state, "approval"), String.eq(state, "input")), "wait",
    Bool.pick(String, String.eq(state, "working"), "work",
      Bool.pick(String, String.eq(state, "queued"), "think",
        Bool.pick(String, String.eq(state, "failed"), "error",
          Bool.pick(String, String.eq(state, "ready"), "idle", "away")))))

# whether a mood moves in the window: only a cat doing something (working,
# thinking, waiting for you, talking). A ready, sleeping, sick or absent
# cat holds still, so a window of resting bots never repaints (each cat
# frame lays out the window: 27 ms on a real log; law bot_mood_idle_still).
# The web and the phones animate every awake cat on the GPU.
def Mood.moving(+m: String) -> Bool:
  Bool.or(Bool.or(String.eq(m, "work"), String.eq(m, "think")), Bool.or(String.eq(m, "wait"), String.eq(m, "talk")))

def Mood.note(+m: String) -> String:
  Bool.pick(String, String.eq(m, "sleep"), "asleep",
    Bool.pick(String, String.eq(m, "idle"), "ready",
      Bool.pick(String, String.eq(m, "work"), "working",
        Bool.pick(String, String.eq(m, "think"), "queued",
          Bool.pick(String, String.eq(m, "wait"), "needs you",
            Bool.pick(String, String.eq(m, "talk"), "talking",
              Bool.pick(String, String.eq(m, "error"), "failed", "away")))))))

def Mood.rest() -> Nat:
  900n

def Mood.talk() -> Nat:
  60n

# Sidebar
# -------

type BRow is Data:
  BRow{id: String, name: String, thread: String, look: Nat, mood: String, note: String, sel: Bool, remote: Bool, peer: String}

type RRow is Data:
  RRow{id: String, name: String, members: Nat, sel: Bool}

def BU.bot.sel(+u: U.Ui) -> String:
  U.Ui.scratch(u, "@bot")

def BU.room.sel(+u: U.Ui) -> String:
  U.Ui.scratch(u, "@room")

def BU.remote.sel(+u: U.Ui) -> String:
  U.Ui.scratch(u, "@remote")

def BU.row.m(+mood: String, i: String, n: String, th: String, lk: Nat, sel: Bool) -> BRow:
  BRow{i, n, th, lk, mood, Mood.note(mood), sel, False{}, ""}

def BU.far.k(+id: String, +o: J.Json, +sel: String) -> BRow:
  BRow{id, J.Json.get_str(o, "name", ""), "", J.Json.get_nat(o, "look", 0n), Mood.of.name(J.Json.get_str(o, "state", "")),
    Mood.note(Mood.of.name(J.Json.get_str(o, "state", ""))), String.eq(id, sel), True{}, J.Json.get_str(o, "peerName", J.Json.get_str(o, "peer", ""))}

# one bot reported by a linked machine
def BU.far(+o: J.Json, +sel: String) -> BRow:
  BU.far.k(J.Json.get_str(o, "name", "") ++ "@" ++ J.Json.get_str(o, "peerName", J.Json.get_str(o, "peer", "")), o, sel)

def BU.fars(os: List<&2, J.Json>, +sel: String) -> List<&2, BRow>:
  match os:
    case Nil{}:
      Nil{}
    case +o <> t:
      BU.far(o, sel) <> BU.fars(t, sel)

def BU.remote(+u: U.Ui) -> List<&2, BRow>:
  BU.fars(J.Json.elems(Maybe.default(&2, J.Json, J.Json.parse(U.Ui.info(u, "bots.remote")), J.Json.arr(Nil{}))), BU.remote.sel(u))

def BU.rooms.go(rs: List<&2, BT.Room>, +sel: String) -> List<&2, RRow>:
  match rs:
    case Nil{}:
      Nil{}
    case BT.Room{+i, n, m, _, _} <> t:
      RRow{i, n, List.length(&2, String, m), String.eq(i, sel)} <> BU.rooms.go(t, sel)

def BU.rooms(+u: U.Ui) -> List<&2, RRow>:
  BU.rooms.go(BT.World.rooms(M.State.bots(U.Ui.state(u))), BU.room.sel(u))

def BRow.moving(r: BRow) -> Bool:
  match r:
    case BRow{_, _, _, _, +m, _, _, _, _}:
      Mood.moving(m)

def BU.moving.go(rs: List<&2, BRow>) -> Bool:
  match rs:
    case Nil{}:
      False{}
    case r <> t:
      Bool.or(BRow.moving(r), BU.moving.go(t))

# The main area
# -------------

type View is Data:
  VThread{}
  VBot{bot: BT.Bot}
  VRoom{room: BT.Room}
  VRemote{id: String}

def BU.view.bot.k(same: Bool, b: BT.Bot) -> View:
  match same:
    case True{}:
      VBot{b}
    case False{}:
      VThread{}

def BU.view.bot(m: Maybe<&2, BT.Bot>, +sel: String) -> View:
  match m:
    case Some{+b}:
      BU.view.bot.k(String.eq(BT.Bot.thread(b), sel), b)
    case None{}:
      VThread{}

def BU.view.far(none: Bool, +u: U.Ui) -> View:
  match none:
    case True{}:
      BU.view.bot(BT.World.find.id(BT.World.bot(M.State.bots(U.Ui.state(u)), BU.bot.sel(u))), U.Ui.sel(u))
    case False{}:
      VRemote{BU.remote.sel(u)}

def BU.view.room(m: Maybe<&2, BT.Room>, +u: U.Ui) -> View:
  match m:
    case Some{r}:
      VRoom{r}
    case None{}:
      BU.view.far(String.is_empty(BU.remote.sel(u)), u)

def BU.room.get(r: BT.Room) -> Maybe<&2, BT.Room>:
  match r:
    case BT.Room{i, n, m, c, +d}:
      Bool.pick(Maybe<&2, BT.Room>, d, None{}, Some{BT.Room{i, n, m, c, d}})

# what the main area shows: a room, a remote bot, a bot, or the thread
def BU.view(+u: U.Ui) -> View:
  BU.view.room(BU.room.get(BT.World.room(M.State.bots(U.Ui.state(u)), BU.room.sel(u))), u)

def BU.tabs() -> List<&2, String>:
  ["chat", "space", "browser", "memory", "routines", "hooks", "settings"]

def BU.tab.label(+t: String) -> String:
  Bool.pick(String, String.eq(t, "chat"), "Chat",
    Bool.pick(String, String.eq(t, "space"), "Space",
      Bool.pick(String, String.eq(t, "browser"), "Browser",
        Bool.pick(String, String.eq(t, "memory"), "Memory",
          Bool.pick(String, String.eq(t, "routines"), "Routines",
            Bool.pick(String, String.eq(t, "hooks"), "Webhooks", "Settings"))))))

# the bot's tab ("chat" until one is picked)
def BU.tab(+u: U.Ui) -> String:
  Bool.pick(String, String.is_empty(U.Ui.scratch(u, "@btab")), "chat", U.Ui.scratch(u, "@btab"))

# a bot's space: what it wrote, or a friendly empty one
def BU.space.k(+spec: String, +name: String) -> SP.Space:
  Bool.pick(SP.Space, String.is_empty(spec), SP.Space.empty(name), SP.Space.read(spec))

def BU.space(+u: U.Ui, b: BT.Bot) -> SP.Space:
  match b:
    case BT.Bot{+i, +n, _, _, _, _, _}:
      BU.space.k(BT.World.space(M.State.bots(U.Ui.state(u)), i), n)

def BU.mems(+u: U.Ui, +bot: String) -> List<&2, BT.Mem>:
  BT.World.mems(M.State.bots(U.Ui.state(u)), bot)

def BU.routines(+u: U.Ui, +bot: String) -> List<&2, BT.Routine>:
  BT.World.routines(M.State.bots(U.Ui.state(u)), bot)

def BU.hooks(+u: U.Ui, +bot: String) -> List<&2, BT.Hook>:
  BT.World.hooks(M.State.bots(U.Ui.state(u)), bot)

def BU.peers(+u: U.Ui) -> List<&2, BT.Peer>:
  BT.World.peers(M.State.bots(U.Ui.state(u)))

# a room's recent posts, oldest first
def BU.posts(+u: U.Ui, +room: String) -> List<&2, BT.Post>:
  BT.World.posts(M.State.bots(U.Ui.state(u)), room, 200n)

# the person's conversation with a bot elsewhere
def BU.remote.posts(+u: U.Ui, +id: String) -> List<&2, BT.Post>:
  BU.posts(u, BT.Room.dm("you", id))

# a bot's conversations with other bots, newest last
def BU.talk(+u: U.Ui, b: BT.Bot) -> List<&2, BT.Post>:
  match b:
    case BT.Bot{_, +n, _, _, _, _, _}:
      BT.World.posts_of(M.State.bots(U.Ui.state(u)), n, 100n)

# the bots a room form can pick from, and whether each is picked
type Pick is Data:
  Pick{id: String, name: String, on: Bool}

def BU.picks.go(bs: List<&2, BT.Bot>, +ms: List<&2, String>) -> List<&2, Pick>:
  match bs:
    case Nil{}:
      Nil{}
    case BT.Bot{+i, n, _, _, _, _, _} <> t:
      Pick{i, n, BT.Room.has(ms, i)} <> BU.picks.go(t, ms)

# bots on linked machines, by the name@machine rooms and bot_send take
def BU.picks.far(rs: List<&2, BRow>, +ms: List<&2, String>) -> List<&2, Pick>:
  match rs:
    case Nil{}:
      Nil{}
    case BRow{+i, _, _, _, _, _, _, _, _} <> t:
      Pick{i, i, BT.Room.has(ms, i)} <> BU.picks.far(t, ms)

def BU.picks.ids(ps: List<&2, Pick>) -> List<&2, String>:
  match ps:
    case Nil{}:
      Nil{}
    case Pick{i, _, _} <> t:
      i <> BU.picks.ids(t)

# members elsewhere no linked machine lists now (one offline or unlinked),
# kept picked so they can be dropped
def BU.picks.gone(ms: List<&2, String>, +ids: List<&2, String>) -> List<&2, Pick>:
  match ms:
    case Nil{}:
      Nil{}
    case +m <> t:
      BT.Post.keep(Pick, Bool.and(String.contains(m, "@"), Bool.not(BT.Room.has(ids, m))), Pick{m, m, True{}}, BU.picks.gone(t, ids))

def BU.picks.all(+ps: List<&2, Pick>, +ms: List<&2, String>) -> List<&2, Pick>:
  List.append(&2, Pick, ps, BU.picks.gone(ms, BU.picks.ids(ps)))

# this machine's bots, then those on linked machines ("name@machine")
def BU.picks.of(+u: U.Ui, +ms: List<&2, String>) -> List<&2, Pick>:
  BU.picks.all(List.append(&2, Pick, BU.picks.go(BT.World.bots(M.State.bots(U.Ui.state(u))), ms), BU.picks.far(BU.remote(u), ms)), ms)

def BU.picks(+u: U.Ui) -> List<&2, Pick>:
  BU.picks.of(u, BT.Room.members.of(U.Ui.scratch(u, "@f.rmembers")))

# a member's name as people read it (a bot id here becomes its name)
def BU.member.k(m: Maybe<&2, BT.Bot>, +x: String) -> String:
  match m:
    case Some{b}:
      BT.Bot.name(b)
    case None{}:
      x

def BU.member(+u: U.Ui, +x: String) -> String:
  BU.member.k(BT.World.find.id(BT.World.bot(M.State.bots(U.Ui.state(u)), x)), x)

def BU.members.go(ms: List<&2, String>, +u: U.Ui) -> List<&2, String>:
  match ms:
    case Nil{}:
      Nil{}
    case +m <> t:
      BU.member(u, m) <> BU.members.go(t, u)

def BU.members(+u: U.Ui, r: BT.Room) -> String:
  String.join(BU.members.go(BT.Room.members(r), u), ", ")

# a form field's text
def BU.field(+u: U.Ui, +k: String) -> String:
  U.Ui.scratch(u, "@f." ++ k)

# whether a form is open ("@bnew", "@rnew", "@onew")
def BU.open(+u: U.Ui, +k: String) -> Bool:
  String.eq(U.Ui.scratch(u, k), "1")

def Thread.activity(t: M.Thread) -> Nat:
  match t:
    case M.Thread{_, _, _, _, a, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      a

def Mood.bot.t(+t: M.Thread, +st: M.State, +now: Nat, +talked: Nat) -> String:
  Mood.of(U.Side.status(st, t), Nat.is_le(now, Nat.add(talked, Mood.talk())), Nat.is_gt(now, Nat.add(Thread.activity(t), Mood.rest())))

def Mood.bot(+st: M.State, +now: Nat, b: BT.Bot) -> String:
  match b:
    case BT.Bot{+i, _, +th, _, _, _, _}:
      Mood.bot.t(U.Ui.thread(st, th), st, now, BT.World.talked_at(M.State.bots(st), i))

def BU.row(+st: M.State, +now: Nat, +sel: String, b: BT.Bot) -> BRow:
  match b:
    case BT.Bot{+i, +n, +th, +lk, pe, c, d}:
      BU.row.m(Mood.bot(st, now, BT.Bot{i, n, th, lk, pe, c, d}), i, n, th, lk, String.eq(i, sel))

def BU.rows.go(bs: List<&2, BT.Bot>, +st: M.State, +now: Nat, +sel: String) -> List<&2, BRow>:
  match bs:
    case Nil{}:
      Nil{}
    case b <> t:
      BU.row(st, now, sel, b) <> BU.rows.go(t, st, now, sel)

# the sidebar's cats: this machine's bots (oldest first), then linked ones
def BU.rows(+u: U.Ui) -> List<&2, BRow>:
  List.append(&2, BRow, BU.rows.go(BT.World.bots(M.State.bots(U.Ui.state(u))), U.Ui.state(u), U.Side.now(u), BU.bot.sel(u)), BU.remote(u))

# whether any cat in the sidebar moves (the window keeps drawing frames
# only while one does)
def BU.moving(+u: U.Ui) -> Bool:
  BU.moving.go(BU.rows(u))
