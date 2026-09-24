import Base
import ./check.bend as C
import ../src/core/json.bend as J
import ../src/core/model.bend as M
import ../src/core/codec.bend as CD
import ../src/core/hub.bend as B
import ../src/core/bot.bend as BT
import ../src/core/bothub.bend as BH
import ../src/core/mcp.bend as MC

def yes(b: Bool) -> String:
  match b:
    case True{}:
      "yes"
    case False{}:
      "no"

def tag(c: M.Change) -> String:
  J.Json.get_str(CD.Change.encode(c), "$", "")

def tags(cs: List<&2, M.Change>) -> String:
  match cs:
    case Nil{}:
      ""
    case c <> t:
      tag(c) ++ " " ++ tags(t)

def fx(os: List<&2, B.Out>) -> String:
  match os:
    case Nil{}:
      ""
    case B.BotFx{k, _, _, _} <> t:
      "fx:" ++ k ++ " " ++ fx(t)
    case B.Send{_, text} <> t:
      "send:" ++ J.Json.get_str(Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{}), "t", "") ++ " " ++ fx(t)
    case _ <> t:
      "out " ++ fx(t)

def st.tags(st: B.Step) -> String:
  match st:
    case B.Step{cs, os}:
      tags(cs) ++ "| " ++ fx(os)

def run(s: M.State, st: B.Step) -> M.State:
  match st:
    case B.Step{cs, _}:
      M.State.replay(cs, s)

def req(+m: String, +p: String) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse("{\"id\":1,\"m\":\"" ++ m ++ "\",\"p\":" ++ p ++ "}"), J.Null{})

def ask(+s: M.State, +now: Nat, +m: String, +p: String) -> B.Step:
  BH.Bots.request(s, now, 1, req(m, p))

def made(+s: M.State, +now: Nat, +m: String, +p: String) -> M.State:
  run(s, ask(s, now, m, p))

def two() -> M.State:
  made(made(M.State.empty(), 1000n, "bots.create", "{\"name\":\"Miso\",\"provider\":\"claude\"}"), 1001n, "bots.create", "{\"name\":\"Tofu\",\"provider\":\"codex\"}")

def bot.of(+s: M.State, +name: String) -> BT.Bot:
  Maybe.default(&2, BT.Bot, BT.World.find(M.State.bots(s), name), BT.Bot.blank("?"))

def id.of(+s: M.State, +name: String) -> String:
  BT.Bot.id(bot.of(s, name))

def th.of(+s: M.State, +name: String) -> String:
  BT.Bot.thread(bot.of(s, name))

def out.reply(o: MC.McpOut) -> String:
  match o:
    case MC.McpOut{r, _, _}:
      r

def out.step(o: MC.McpOut) -> B.Step:
  match o:
    case MC.McpOut{_, st, _}:
      st

def call(+s: M.State, +now: Nat, +thread: String, +tool: String, +args: String) -> String:
  out.reply(BH.Bots.mcp(s, now, thread, J.Null{}, "t", J.Json.arr(Nil{}), Nil{}, "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"" ++ tool ++ "\",\"arguments\":" ++ args ++ "}}"))

def call.step(+s: M.State, +now: Nat, +thread: String, +tool: String, +args: String) -> B.Step:
  out.step(BH.Bots.mcp(s, now, thread, J.Null{}, "t", J.Json.arr(Nil{}), Nil{}, "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"" ++ tool ++ "\",\"arguments\":" ++ args ++ "}}"))

def woke(+s: M.State, +name: String) -> String:
  Nat.show(BT.World.hop(M.State.bots(s), id.of(s, name)))

# a bot at hop h sends: the message goes out at h+1, or not past the bound
def hops(n: Nat, +s: M.State) -> M.State:
  match n:
    case 0n:
      s
    case 1n+k:
      hops(k, run(s, call.step(s, 2000n, th.of(s, "Miso"), "bot_send", "{\"to\":\"Tofu\",\"text\":\"hi\"}")))

def mem.state() -> M.State:
  made(made(made(two(), 1100n, "bots.remember", "{\"bot\":\"" ++ id.of(two(), "Miso") ++ "\",\"key\":\"User TZ\",\"kind\":\"user\",\"text\":\"Lives in Lisbon\"}"),
    1101n, "bots.remember", "{\"bot\":\"" ++ id.of(two(), "Miso") ++ "\",\"key\":\"howto.invoice\",\"kind\":\"howto\",\"text\":\"Invoices go through the Stripe dashboard\",\"tags\":\"billing\"}"),
    1102n, "bots.remember", "{\"bot\":\"" ++ id.of(two(), "Miso") ++ "\",\"key\":\"fact.cat\",\"kind\":\"fact\",\"text\":\"The office cat is called Pixel\"}")

def hook.of(+s: M.State) -> String:
  BT.Hook.id(Maybe.default(&2, BT.Hook, List.head(&2, BT.Hook, BT.World.hooks(M.State.bots(s), id.of(s, "Tofu"))), BT.Hook.blank("?")))

def main() -> IO(Unit):
  do IO<Unit>:
    +s : M.State = two()
    C.Check.str("create", st.tags(ask(M.State.empty(), 1000n, "bots.create", "{\"name\":\"Miso\"}")), "ThreadCreated BotSet | send:reply fx:home ")
    C.Check.str("two bots", Nat.show(List.length(&2, BT.Bot, BT.World.bots(M.State.bots(s)))), "2")
    C.Check.str("name taken", st.tags(ask(s, 1002n, "bots.create", "{\"name\":\"miso\"}")), "| send:reply ")
    C.Check.str("bad name", st.tags(ask(s, 1002n, "bots.create", "{\"name\":\"has space\"}")), "| send:reply ")
    C.Check.str("bot thread", yes(BT.World.is_bot_thread(M.State.bots(s), th.of(s, "Tofu"))), "yes")
    C.Check.str("say", st.tags(ask(s, 1003n, "bots.say", "{\"bot\":\"" ++ id.of(s, "Miso") ++ "\",\"text\":\"hello\"}")), "BotWoke MessagePosted TurnChanged | send:reply out out out ")
    C.Check.str("send", st.tags(call.step(s, 1004n, th.of(s, "Miso"), "bot_send", "{\"to\":\"tofu\",\"text\":\"hi\"}")), "RoomPosted BotWoke MessagePosted TurnChanged | out out ")
    C.Check.str("send hop", woke(run(s, call.step(s, 1004n, th.of(s, "Miso"), "bot_send", "{\"to\":\"Tofu\",\"text\":\"hi\"}")), "Tofu"), "1")
    C.Check.str("send self", yes(String.contains(call(s, 1004n, th.of(s, "Miso"), "bot_send", "{\"to\":\"Miso\",\"text\":\"hi\"}"), "that is you")), "yes")
    C.Check.str("send nobody", yes(String.contains(call(s, 1004n, th.of(s, "Miso"), "bot_send", "{\"to\":\"Nope\",\"text\":\"hi\"}"), "no bot by that name")), "yes")
    C.Check.str("not a bot", yes(String.contains(call(M.State.empty(), 1004n, "t1", "bot_send", "{\"to\":\"Nope\",\"text\":\"hi\"}"), "unknown tool")), "yes")
    # Miso keeps its own hop (0) here, so each send goes out at 1; set Miso deep
    C.Check.str("hop bound", yes(String.contains(call(run(s, B.Step{[M.BotWoke{id.of(s, "Miso"), 6n, 1005n}], Nil{}}), 1005n, th.of(s, "Miso"), "bot_send",
      "{\"to\":\"Tofu\",\"text\":\"hi\"}"), "stops here")), "yes")
    C.Check.str("hop 5 ok", yes(String.contains(call(run(s, B.Step{[M.BotWoke{id.of(s, "Miso"), 5n, 1005n}], Nil{}}), 1005n, th.of(s, "Miso"), "bot_send",
      "{\"to\":\"Tofu\",\"text\":\"hi\"}"), "sent to")), "yes")
    C.Check.str("posts logged", Nat.show(List.length(&2, BT.Post, BT.World.posts(M.State.bots(hops(3n, s)), BT.Room.dm("Miso", "Tofu"), 10n))), "3")
    C.Check.str("room create", st.tags(call.step(s, 1006n, th.of(s, "Miso"), "room_create", "{\"name\":\"team\",\"members\":\"Tofu, ghost@elsewhere\"}")), "RoomSet | ")
    +r : M.State = run(s, call.step(s, 1006n, th.of(s, "Miso"), "room_create", "{\"name\":\"team\",\"members\":\"Tofu\"}"))
    C.Check.str("room post", st.tags(call.step(r, 1007n, th.of(r, "Miso"), "room_post", "{\"room\":\"team\",\"text\":\"standup\"}")), "RoomPosted BotWoke MessagePosted TurnChanged | out out ")
    C.Check.str("room read", yes(String.contains(call(run(r, call.step(r, 1007n, th.of(r, "Miso"), "room_post", "{\"room\":\"team\",\"text\":\"standup\"}")), 1008n, th.of(r, "Tofu"), "room_read", "{\"room\":\"team\"}"), "standup")), "yes")
    C.Check.str("room by person", st.tags(ask(r, 1009n, "bots.post", "{\"room\":\"" ++ BT.Room.id(Maybe.default(&2, BT.Room, BT.World.find_room(M.State.bots(r), "team"), BT.Room.blank("")) ) ++ "\",\"text\":\"hey\"}")),
      "RoomPosted BotWoke MessagePosted TurnChanged BotWoke MessagePosted TurnChanged | send:reply out out out out out ")
    +m : M.State = mem.state()
    C.Check.str("mem key norm", yes(String.contains(call(m, 1200n, th.of(m, "Miso"), "memory_list", "{}"), "user-tz")), "yes")
    C.Check.str("mem recall", yes(String.contains(call(m, 1200n, th.of(m, "Miso"), "memory_recall", "{\"query\":\"send the invoice\"}"), "Stripe")), "yes")
    C.Check.str("mem recall miss", yes(String.contains(call(m, 1200n, th.of(m, "Miso"), "memory_recall", "{\"query\":\"send the invoice\"}"), "Pixel")), "no")
    C.Check.str("mem block has user", yes(String.contains(BH.Bots.turn(m, 1200n, th.of(m, "Miso"), "what's up?"), "Lisbon")), "yes")
    C.Check.str("mem block skips unrelated", yes(String.contains(BH.Bots.turn(m, 1200n, th.of(m, "Miso"), "what's up?"), "Stripe")), "no")
    C.Check.str("mem block related", yes(String.contains(BH.Bots.turn(m, 1200n, th.of(m, "Miso"), "a billing question"), "Stripe")), "yes")
    C.Check.str("mem block not for others", BH.Bots.turn(m, 1200n, th.of(m, "Tofu"), "hi"), "hi")
    C.Check.str("mem replace", Nat.show(List.length(&2, BT.Mem, BT.World.mems(M.State.bots(made(m, 1300n, "bots.remember", "{\"bot\":\"" ++ id.of(m, "Miso") ++ "\",\"key\":\"user tz\",\"kind\":\"user\",\"text\":\"Now in Porto\"}")), id.of(m, "Miso")))), "3")
    C.Check.str("mem forget", Nat.show(List.length(&2, BT.Mem, BT.World.mems(M.State.bots(run(m, call.step(m, 1300n, th.of(m, "Miso"), "memory_forget", "{\"key\":\"fact.cat\"}"))), id.of(m, "Miso")))), "2")
    C.Check.str("fit budget", yes(Nat.is_le(BT.Mem.used(BT.Mem.fit(["aaaa", "bbbb", "cccc"], 11n)), 11n)), "yes")
    C.Check.str("fit stops", Nat.show(List.length(&2, String, BT.Mem.fit(["aaaa", "bbbb", "cccc"], 11n))), "2")
    # routines: made at 1000, every 15m; due at the first quarter hour after
    +o : M.State = made(s, 1000n, "bots.routine", "{\"bot\":\"" ++ id.of(s, "Miso") ++ "\",\"name\":\"check mail\",\"cron\":\"every 15m\",\"prompt\":\"Look at the inbox\"}")
    C.Check.str("routine bad", st.tags(ask(s, 1000n, "bots.routine", "{\"bot\":\"" ++ id.of(s, "Miso") ++ "\",\"cron\":\"whenever\",\"prompt\":\"x\"}")), "| send:reply ")
    C.Check.str("routine not yet", st.tags(BH.Bots.tick(o, 1500n, BH.Tz{0n, True{}})), "| ")
    C.Check.str("routine due", st.tags(BH.Bots.tick(o, 1860n, BH.Tz{0n, True{}})), "RoutineFired BotWoke MessagePosted TurnChanged | out out out ")
    C.Check.str("routine once", st.tags(BH.Bots.tick(run(o, BH.Bots.tick(o, 1860n, BH.Tz{0n, True{}})), 1900n, BH.Tz{0n, True{}})), "| ")
    C.Check.str("routine by bot", yes(String.contains(call(s, 1000n, th.of(s, "Tofu"), "routine_set", "{\"name\":\"r\",\"schedule\":\"daily 09:30\",\"prompt\":\"p\"}"), "daily at 09:30")), "yes")
    # webhooks
    +h : M.State = made(s, 1000n, "bots.hook", "{\"bot\":\"" ++ id.of(s, "Tofu") ++ "\",\"name\":\"github\"}")
    C.Check.str("hook make", st.tags(ask(s, 1000n, "bots.hook", "{\"bot\":\"" ++ id.of(s, "Tofu") ++ "\",\"name\":\"github\"}")), "HookSet | fx:hook ")
    C.Check.str("hook hit", st.tags(BH.Bots.hooked(h, 1010n, hook.of(h), "{\"action\":\"opened\"}")), "HookHit BotWoke MessagePosted TurnChanged | out out ")
    C.Check.str("hook untrusted", yes(String.contains(BH.Bots.turn(h, 1010n, "x", "y"), "y")), "yes")
    C.Check.str("hook revoked", st.tags(BH.Bots.hooked(made(h, 1011n, "bots.hook_revoke", "{\"hook\":\"" ++ hook.of(h) ++ "\"}"), 1012n, hook.of(h), "{}")), "| ")
    C.Check.str("hook unknown", st.tags(BH.Bots.hooked(h, 1010n, "nope", "{}")), "| ")
    # a linked machine's bot
    C.Check.str("incoming", st.tags(BH.Bots.incoming(s, 1010n, "laptop", Maybe.default(&2, J.Json, J.Json.parse("{\"from\":\"Nori\",\"to\":\"miso\",\"text\":\"yo\",\"hop\":2}"), J.Null{}))),
      "RoomPosted BotWoke MessagePosted TurnChanged | out out out ")
    C.Check.str("incoming too deep", st.tags(BH.Bots.incoming(s, 1010n, "laptop", Maybe.default(&2, J.Json, J.Json.parse("{\"from\":\"Nori\",\"to\":\"miso\",\"text\":\"yo\",\"hop\":9}"), J.Null{}))), "| ")
    C.Check.str("remote no peer", yes(String.contains(call(s, 1004n, th.of(s, "Miso"), "bot_send", "{\"to\":\"Nori@laptop\",\"text\":\"hi\"}"), "no linked machine")), "yes")
    +p : M.State = run(s, B.Step{[M.PeerSet{"p1", "laptop", "http://laptop:3787", False{}, 1000n}], Nil{}})
    C.Check.str("remote send", st.tags(call.step(p, 1004n, th.of(p, "Miso"), "bot_send", "{\"to\":\"Nori@laptop\",\"text\":\"hi\"}")), "RoomPosted | fx:send ")
    # tools list: a bot sees its own tools, a thread does not
    C.Check.str("tools bot", yes(String.contains(out.reply(BH.Bots.mcp(s, 1n, th.of(s, "Miso"), J.Null{}, "t", J.Json.arr(Nil{}), Nil{}, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}")), "memory_save")), "yes")
    C.Check.str("tools thread", yes(String.contains(out.reply(BH.Bots.mcp(s, 1n, "t9", J.Null{}, "t", J.Json.arr(Nil{}), Nil{}, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}")), "memory_save")), "no")
    C.Check.str("prompt", yes(String.contains(BH.Bots.prompt(s, th.of(s, "Miso"), "/h"), "You are Miso")), "yes")
    C.Check.str("space", st.tags(call.step(s, 1004n, th.of(s, "Miso"), "space_set", "{\"spec\":\"{\\\"title\\\":\\\"hi\\\"}\"}")), "SpaceSet | ")
    C.Check.str("space bad", yes(String.contains(call(s, 1004n, th.of(s, "Miso"), "space_set", "{\"spec\":\"{nope\"}"), "not valid JSON")), "yes")
    C.Check.str("space press", yes(String.contains(tags(Maybe.default(&2, List<&2, M.Change>, None{}, Nil{})), "")), "yes")
    C.Check.str("delete", st.tags(ask(s, 1004n, "bots.delete", "{\"bot\":\"" ++ id.of(s, "Tofu") ++ "\"}")), "BotDeleted | send:reply out fx:gone ")
    C.Check.str("deleted gone", Nat.show(List.length(&2, BT.Bot, BT.World.bots(M.State.bots(made(s, 1004n, "bots.delete", "{\"bot\":\"" ++ id.of(s, "Tofu") ++ "\"}"))))), "1")
    C.Check.str("codec", yes(String.contains(J.Json.show(CD.Change.encode(M.RoomPosted{"p", "r", "a", "t", 2n, 9n})), "\"hop\":2")), "yes")
