import Base
import ../core/json.bend as J
import ../core/model.bend as M
import ../core/client.bend as U
import ../core/codec.bend as C
import ../core/bot.bend as BT
import ../core/botui.bend as B
import ../core/cron.bend as CR
import ../core/cat.bend as CT
import ./space.bend as MS

# Bots on the phones (docs/bots.md): the cats in the list with their
# moods, the rooms, the new bot and room forms, and what a bot, a room or
# a bot on a linked machine shows, as JSON. Each tab's content is made
# only while that tab is shown. The apps draw it and send actions back.

# a cat's rig (parts with path data, fill, one animation each). Several KB
# each, so the screen names a cat by its key ("look:mood") and the apps
# ask the bridge for each rig once (app.bend's cat)
def MBots.rig(+look: Nat, +mood: String) -> J.Json:
  CT.Cat.rig.json(look, mood)

def MBots.cat(+look: Nat, +mood: String) -> J.Json:
  J.Json.str(Nat.show(look) ++ ":" ++ mood)

# since when ("" for never)
def MBots.ago(none: Bool, +now: Nat, +at: Nat) -> String:
  match none:
    case True{}:
      ""
    case False{}:
      U.Time.ago(now, at)

# The list
# --------

def MBots.row(r: B.BRow) -> J.Json:
  match r:
    case B.BRow{i, n, _, +lk, +m, note, sel, rem, peer}:
      J.Json.obj([J.KV{"id", J.Json.str(i)}, J.KV{"name", J.Json.str(n)}, J.KV{"look", J.Json.nat(lk)},
        J.KV{"mood", J.Json.str(m)}, J.KV{"note", J.Json.str(note)}, J.KV{"sel", J.Json.bool(sel)},
        J.KV{"remote", J.Json.bool(rem)}, J.KV{"peer", J.Json.str(peer)}, J.KV{"cat", MBots.cat(lk, m)}])

def MBots.rows(rs: List<&2, B.BRow>) -> List<&2, J.Json>:
  match rs:
    case Nil{}:
      Nil{}
    case r <> t:
      MBots.row(r) <> MBots.rows(t)

def MBots.room(r: B.RRow) -> J.Json:
  match r:
    case B.RRow{i, n, m, sel}:
      J.Json.obj([J.KV{"id", J.Json.str(i)}, J.KV{"name", J.Json.str(n)}, J.KV{"members", J.Json.nat(m)}, J.KV{"sel", J.Json.bool(sel)}])

def MBots.rooms(rs: List<&2, B.RRow>) -> List<&2, J.Json>:
  match rs:
    case Nil{}:
      Nil{}
    case r <> t:
      MBots.room(r) <> MBots.rooms(t)

# Forms
# -----

def MBots.providers(ps: List<&2, String>, +cur: String) -> List<&2, J.Json>:
  match ps:
    case Nil{}:
      Nil{}
    case +p <> t:
      J.Json.obj([J.KV{"label", J.Json.str(U.Chip.name(p))}, J.KV{"provider", J.Json.str(U.Chip.name(p))},
        J.KV{"on", J.Json.bool(String.eq(U.Chip.name(p), cur))}]) <> MBots.providers(t, cur)

# the provider a new bot gets: the one picked, else the hub's default
def MBots.provider(+u: U.Ui) -> String:
  Bool.pick(String, String.is_empty(B.BU.field(u, "provider")), M.Setting.get(U.Ui.state(u), "agent.provider", "claude"), B.BU.field(u, "provider"))

def MBots.new.k(open: Bool, +u: U.Ui) -> J.Json:
  match open:
    case False{}:
      J.Null{}
    case True{}:
      J.Json.obj([J.KV{"name", J.Json.str(B.BU.field(u, "name"))}, J.KV{"persona", J.Json.str(B.BU.field(u, "persona"))},
        J.KV{"provider", J.Json.str(MBots.provider(u))}, J.KV{"providers", J.Json.arr(MBots.providers(U.Chip.providers(), MBots.provider(u)))}])

# the new bot form ("bot-new" opens it, "bfield" fills it, "bot-create"),
# or null
def MBots.new(+u: U.Ui) -> J.Json:
  MBots.new.k(B.BU.open(u, "@bnew"), u)

def MBots.picks(ps: List<&2, B.Pick>) -> List<&2, J.Json>:
  match ps:
    case Nil{}:
      Nil{}
    case B.Pick{i, n, on} <> t:
      J.Json.obj([J.KV{"id", J.Json.str(i)}, J.KV{"name", J.Json.str(n)}, J.KV{"on", J.Json.bool(on)}]) <> MBots.picks(t)

def MBots.rnew.k(open: Bool, +u: U.Ui) -> J.Json:
  match open:
    case False{}:
      J.Null{}
    case True{}:
      J.Json.obj([J.KV{"name", J.Json.str(B.BU.field(u, "rname"))}, J.KV{"picks", J.Json.arr(MBots.picks(B.BU.picks(u)))}])

# the new room form ("room-new", "bfield" rname, "room-pick" a bot id,
# "room-save"), or null
def MBots.rnew(+u: U.Ui) -> J.Json:
  MBots.rnew.k(B.BU.open(u, "@rnew"), u)

# A bot's tabs
# ------------

def MBots.tabs(ts: List<&2, String>) -> List<&2, J.Json>:
  match ts:
    case Nil{}:
      Nil{}
    case +t <> r:
      J.Json.obj([J.KV{"id", J.Json.str(t)}, J.KV{"label", J.Json.str(B.BU.tab.label(t))}]) <> MBots.tabs(r)

def MBots.mem(m: BT.Mem, +now: Nat) -> J.Json:
  match m:
    case BT.Mem{_, k, kind, text, tags, _, +up}:
      J.Json.obj([J.KV{"key", J.Json.str(k)}, J.KV{"kind", J.Json.str(kind)}, J.KV{"text", J.Json.str(text)},
        J.KV{"tags", J.Json.str(tags)}, J.KV{"updated", J.Json.str(U.Time.ago(now, up))}])

def MBots.mems(ms: List<&2, BT.Mem>, +now: Nat) -> List<&2, J.Json>:
  match ms:
    case Nil{}:
      Nil{}
    case m <> t:
      MBots.mem(m, now) <> MBots.mems(t, now)

def MBots.routine(r: BT.Routine, +now: Nat) -> J.Json:
  match r:
    case BT.Routine{i, _, n, +c, p, on, +last, _, _}:
      J.Json.obj([J.KV{"id", J.Json.str(i)}, J.KV{"name", J.Json.str(n)}, J.KV{"cron", J.Json.str(c)},
        J.KV{"when", J.Json.str(CR.Cron.describe(c))}, J.KV{"prompt", J.Json.str(p)}, J.KV{"on", J.Json.bool(on)},
        J.KV{"last", J.Json.str(MBots.ago(Nat.is_eq(last, 0n), now, last))}])

def MBots.routines(rs: List<&2, BT.Routine>, +now: Nat) -> List<&2, J.Json>:
  match rs:
    case Nil{}:
      Nil{}
    case r <> t:
      MBots.routine(r, now) <> MBots.routines(t, now)

# the routine form: open ("routine-edit" fills it, "routine-save"), its
# fields ("bfield" oname, ocron, oprompt); id is "" for a new one
def MBots.routine.form(+u: U.Ui) -> J.Json:
  J.Json.obj([J.KV{"open", J.Json.bool(B.BU.open(u, "@onew"))}, J.KV{"id", J.Json.str(B.BU.field(u, "oid"))},
    J.KV{"name", J.Json.str(B.BU.field(u, "oname"))}, J.KV{"cron", J.Json.str(B.BU.field(u, "ocron"))},
    J.KV{"prompt", J.Json.str(B.BU.field(u, "oprompt"))}])

def MBots.hook(h: BT.Hook, +now: Nat) -> J.Json:
  match h:
    case BT.Hook{+i, _, n, _, _, +last, c}:
      J.Json.obj([J.KV{"id", J.Json.str(i)}, J.KV{"name", J.Json.str(n)}, J.KV{"path", J.Json.str("/hook/" ++ i)},
        J.KV{"count", J.Json.nat(c)}, J.KV{"last", J.Json.str(MBots.ago(Nat.is_eq(last, 0n), now, last))}])

def MBots.hooks(hs: List<&2, BT.Hook>, +now: Nat) -> List<&2, J.Json>:
  match hs:
    case Nil{}:
      Nil{}
    case h <> t:
      MBots.hook(h, now) <> MBots.hooks(t, now)

def MBots.peer(p: BT.Peer) -> J.Json:
  match p:
    case BT.Peer{i, n, url, _, _}:
      J.Json.obj([J.KV{"id", J.Json.str(i)}, J.KV{"name", J.Json.str(n)}, J.KV{"url", J.Json.str(url)}])

def MBots.peers(ps: List<&2, BT.Peer>) -> List<&2, J.Json>:
  match ps:
    case Nil{}:
      Nil{}
    case p <> t:
      MBots.peer(p) <> MBots.peers(t)

def MBots.str(+u: U.Ui, +k: String) -> J.KV:
  J.KV{k, J.Json.str(B.BU.field(u, k))}

# Google's sign-in: its state as the hub said it, the link to open, the
# OAuth client's fields ("bfield" gid, gsecret) and the pasted redirect
# (gpaste); "google" sends an op (status, configure, begin, finish,
# disconnect)
def MBots.google(+u: U.Ui) -> J.Json:
  J.Json.obj([J.KV{"status", J.Json.str(U.Ui.scratch(u, "@google"))}, J.KV{"url", J.Json.str(U.Ui.scratch(u, "@google.url"))},
    MBots.str(u, "gid"), MBots.str(u, "gsecret"), MBots.str(u, "gpaste")])

# the persona (and the field that changes it, "bfield" persona then
# "bot-edit"), Google, and the linked machines ("peer-invite" with purl,
# "peer-join" with invite, "peer-revoke" id)
def MBots.settings(+u: U.Ui, +persona: String) -> J.Json:
  J.Json.obj([J.KV{"persona", J.Json.str(persona)}, J.KV{"personaField", J.Json.str(B.BU.field(u, "persona"))},
    J.KV{"google", MBots.google(u)}, J.KV{"peers", J.Json.arr(MBots.peers(B.BU.peers(u)))},
    J.KV{"invite", J.Json.str(U.Ui.scratch(u, "@peer.invite"))}, MBots.str(u, "purl"), J.KV{"join", J.Json.str(B.BU.field(u, "invite"))}])

# the browser's frame: where the hub serves it, and how many it has sent
# (a new n is a new frame)
def MBots.browser(+u: U.Ui, +id: String) -> J.Json:
  J.Json.obj([J.KV{"url", J.Json.str("/bots/" ++ id ++ "/screen.jpg")},
    J.KV{"n", J.Json.str(Bool.pick(String, String.is_empty(U.Ui.info(u, "shot." ++ id)), "0", U.Ui.info(u, "shot." ++ id)))}])

# what tab i (in B.BU.tabs order) adds; the chat is the screen's thread
def MBots.tab.k(i: Nat, +u: U.Ui, b: BT.Bot, +id: String, +persona: String, +now: Nat) -> List<&2, J.KV>:
  match i:
    case 1n:
      [J.KV{"space", MS.MSpace.json(B.BU.space(u, b), id)}]
    case 2n:
      [J.KV{"browser", MBots.browser(u, id)}]
    case 3n:
      [J.KV{"memory", J.Json.arr(MBots.mems(B.BU.mems(u, id), now))}]
    case 4n:
      [J.KV{"routines", J.Json.arr(MBots.routines(B.BU.routines(u, id), now))}, J.KV{"routine", MBots.routine.form(u)}]
    case 5n:
      [J.KV{"hooks", J.Json.arr(MBots.hooks(B.BU.hooks(u, id), now))}, J.KV{"secret", J.Json.str(U.Ui.scratch(u, "@hook.secret"))},
       J.KV{"secretFor", J.Json.str(U.Ui.scratch(u, "@hook.id"))}, J.KV{"token", J.Json.str(U.Ui.scratch(u, "@hook.token"))},
       J.KV{"tokenFor", J.Json.str(U.Ui.scratch(u, "@hook.tokfor"))}, J.KV{"tokenUrl", J.Json.str(U.Ui.scratch(u, "@hook.tokurl"))}, MBots.str(u, "hname")]
    case 6n:
      [J.KV{"settings", MBots.settings(u, persona)}]
    case _:
      Nil{}

def MBots.bot.m(+u: U.Ui, b: BT.Bot, +id: String, +name: String, +lk: Nat, +persona: String, +mood: String, +tab: String) -> J.Json:
  J.Json.obj(List.append(&2, J.KV,
    [J.KV{"kind", J.Json.str("bot")}, J.KV{"id", J.Json.str(id)}, J.KV{"name", J.Json.str(name)}, J.KV{"mood", J.Json.str(mood)},
     J.KV{"note", J.Json.str(B.Mood.note(mood))}, J.KV{"look", J.Json.nat(lk)}, J.KV{"cat", MBots.cat(lk, mood)},
     J.KV{"tab", J.Json.str(tab)}, J.KV{"tabs", J.Json.arr(MBots.tabs(B.BU.tabs()))}],
    MBots.tab.k(C.Codec.pos(B.BU.tabs(), tab), u, b, id, persona, U.Side.now(u))))

def MBots.bot(+u: U.Ui, b: BT.Bot) -> J.Json:
  match b:
    case BT.Bot{+i, +n, +th, +lk, +pe, +c, +d}:
      MBots.bot.m(u, BT.Bot{i, n, th, lk, pe, c, d}, i, n, lk, pe, B.Mood.bot(U.Ui.state(u), U.Side.now(u), BT.Bot{i, n, th, lk, pe, c, d}), B.BU.tab(u))

# Rooms and bots elsewhere
# ------------------------

def MBots.post(p: BT.Post, +u: U.Ui, +now: Nat) -> J.Json:
  match p:
    case BT.Post{i, _, +f, text, _, +at}:
      J.Json.obj([J.KV{"id", J.Json.str(i)}, J.KV{"from", J.Json.str(B.BU.member(u, f))}, J.KV{"text", J.Json.str(text)},
        J.KV{"ago", J.Json.str(U.Time.ago(now, at))}, J.KV{"mine", J.Json.bool(String.eq(f, "you"))}])

def MBots.posts(ps: List<&2, BT.Post>, +u: U.Ui, +now: Nat) -> List<&2, J.Json>:
  match ps:
    case Nil{}:
      Nil{}
    case p <> t:
      MBots.post(p, u, now) <> MBots.posts(t, u, now)

# a room: who is in it, its posts, the composer ("bfield" rpost, "room-post")
def MBots.room.view(+u: U.Ui, r: BT.Room) -> J.Json:
  match r:
    case BT.Room{+i, +n, +m, +c, +d}:
      J.Json.obj([J.KV{"kind", J.Json.str("room")}, J.KV{"id", J.Json.str(i)}, J.KV{"name", J.Json.str(n)},
        J.KV{"members", J.Json.str(B.BU.members(u, BT.Room{i, n, m, c, d}))},
        J.KV{"posts", J.Json.arr(MBots.posts(B.BU.posts(u, i), u, U.Side.now(u)))},
        J.KV{"draft", J.Json.str(B.BU.field(u, "rpost"))}])

def MBots.far.o(+u: U.Ui, +id: String, name: String, +mood: String, note: String, +lk: Nat, peer: String) -> J.Json:
  J.Json.obj([J.KV{"kind", J.Json.str("remote")}, J.KV{"id", J.Json.str(id)}, J.KV{"name", J.Json.str(name)},
    J.KV{"mood", J.Json.str(mood)}, J.KV{"note", J.Json.str(note)}, J.KV{"look", J.Json.nat(lk)}, J.KV{"cat", MBots.cat(lk, mood)},
    J.KV{"peer", J.Json.str(peer)}, J.KV{"posts", J.Json.arr(MBots.posts(B.BU.remote.posts(u, id), u, U.Side.now(u)))},
    J.KV{"draft", J.Json.str(B.BU.field(u, "rtext"))}])

def MBots.far.m(m: Maybe<&2, B.BRow>, +u: U.Ui, +id: String) -> J.Json:
  match m:
    case Some{B.BRow{_, n, _, lk, mo, note, _, _, peer}}:
      MBots.far.o(u, id, n, mo, note, lk, peer)
    case None{}:
      MBots.far.o(u, id, id, "away", B.Mood.note("away"), 0n, "")

def MBots.rid(r: B.BRow) -> String:
  match r:
    case B.BRow{i, _, _, _, _, _, _, _, _}:
      i

def MBots.far.find(rs: List<&2, B.BRow>, +id: String) -> Maybe<&2, B.BRow>:
  match rs:
    case Nil{}:
      None{}
    case +r <> t:
      Bool.pick(Maybe<&2, B.BRow>, String.eq(MBots.rid(r), id), Some{r}, MBots.far.find(t, id))

# a bot on a linked machine: its cat and the person's conversation with
# it ("bfield" rtext, "remote-send")
def MBots.far(+u: U.Ui, +id: String) -> J.Json:
  MBots.far.m(MBots.far.find(B.BU.remote(u), id), u, id)

def MBots.view(v: B.View, +u: U.Ui) -> J.Json:
  match v:
    case B.VThread{}:
      J.Null{}
    case B.VBot{b}:
      MBots.bot(u, b)
    case B.VRoom{r}:
      MBots.room.view(u, r)
    case B.VRemote{id}:
      MBots.far(u, id)

# what the main area shows when it is a bot ("kind" bot), a room or a bot
# elsewhere ("remote"); null for a thread
def MBots.json(+u: U.Ui) -> J.Json:
  MBots.view(B.BU.view(u), u)
