import Base
import ./json.bend as J

# Grok over ACP (Agent Client Protocol: JSON-RPC over stdio), one process
# per turn: initialize, then session/new (or session/load to resume), then
# session/prompt. What the agent says is reported in the same event shapes
# as `codex exec --json` (thread.started, item.completed, turn.completed,
# turn.failed, plus item.delta for streaming), so the hub decodes both
# providers one way.

# what a turn needs: working directory, the thread's MCP endpoint, the
# Backplane instructions, the user's text, the session to resume ("" for
# a new one), and whether the user approves tools (every mode but full
# access)
type AcpTurn is Data:
  AcpTurn{cwd: String, mcp: String, prompt: String, text: String, session: String, ask: Bool}

# the session id once known, the reply text so far, and whether the turn
# has ended (the runner then stops the process)
type Acp is Data:
  Acp{sid: String, buf: String, done: Bool}

# lines to write to the agent, lines to report to the hub, and permission
# requests for the user (each answered later, through the hub's asks)
type AcpOut is Data:
  AcpOut{acp: Acp, send: List<&2, String>, emit: List<&2, String>, asks: List<&2, String>}

def Acp.new() -> Acp:
  Acp{"", "", False{}}

def Acp.rpc(+id: Nat, +method: String, params: J.Json) -> String:
  J.Json.show(J.Json.obj([J.KV{"jsonrpc", J.Str{"2.0"}}, J.KV{"id", J.Num{Nat.show(id)}}, J.KV{"method", J.Str{method}}, J.KV{"params", params}]))

# the first line of every turn
def Acp.init() -> String:
  Acp.rpc(1n, "initialize", J.Json.obj([J.KV{"protocolVersion", J.Num{"1"}},
    J.KV{"clientCapabilities", J.Json.obj([J.KV{"fs", J.Json.obj([J.KV{"readTextFile", J.Flag{False{}}}, J.KV{"writeTextFile", J.Flag{False{}}}])}, J.KV{"terminal", J.Flag{False{}}}])}]))

def Acp.mcp(+url: String) -> J.Json:
  J.Json.arr([J.Json.obj([J.KV{"type", J.Str{"http"}}, J.KV{"name", J.Str{"backplane"}}, J.KV{"url", J.Str{url}}, J.KV{"headers", J.Json.arr(Nil{})}])])

def Acp.open.k(fresh: Bool, t: AcpTurn) -> String:
  match fresh t:
    case True{} AcpTurn{cwd, mcp, _, _, _, _}:
      Acp.rpc(2n, "session/new", J.Json.obj([J.KV{"cwd", J.Str{cwd}}, J.KV{"mcpServers", Acp.mcp(mcp)}]))
    case False{} AcpTurn{cwd, mcp, _, _, sid, _}:
      Acp.rpc(2n, "session/load", J.Json.obj([J.KV{"sessionId", J.Str{sid}}, J.KV{"cwd", J.Str{cwd}}, J.KV{"mcpServers", Acp.mcp(mcp)}]))

def Acp.session(t: AcpTurn) -> String:
  match t:
    case AcpTurn{_, _, _, _, s, _}:
      s

# a new session or the thread's own
def Acp.open(+t: AcpTurn) -> String:
  Acp.open.k(String.is_empty(Acp.session(t)), t)

def Acp.say.rpc(+sid: String, +text: String) -> String:
  Acp.rpc(3n, "session/prompt", J.Json.obj([J.KV{"sessionId", J.Str{sid}}, J.KV{"prompt", J.Json.arr([J.Json.obj([J.KV{"type", J.Str{"text"}}, J.KV{"text", J.Str{text}}])])}]))

# the prompt: a new session gets Backplane's instructions first
def Acp.say.k(fresh: Bool, t: AcpTurn, +sid: String) -> String:
  match fresh t:
    case True{} AcpTurn{_, _, pr, text, _, _}:
      Acp.say.rpc(sid, "<backplane_instructions>\n" ++ pr ++ "\n</backplane_instructions>\n\n" ++ text)
    case False{} AcpTurn{_, _, _, text, _, _}:
      Acp.say.rpc(sid, text)

def Acp.event(+ty: String, kvs: List<&2, J.KV>) -> String:
  J.Json.show(J.Json.obj(J.KV{"type", J.Str{ty}} <> kvs))

def Acp.failed(+msg: String) -> String:
  Acp.event("turn.failed", [J.KV{"message", J.Str{msg}}])

def Acp.error(o: J.Json) -> String:
  J.Json.get_str(J.Json.get_obj(o, "error"), "message", "grok failed")

# a sign-in problem says how to fix it
def Acp.hint(+msg: String) -> String:
  Bool.pick(String, Bool.or(String.contains(String.to_lower(msg), "auth"), String.contains(String.to_lower(msg), "login")),
    msg ++ " (sign in once with `grok login`)", msg)

def Acp.fail(a: Acp, +msg: String) -> AcpOut:
  match a:
    case Acp{s, b, _}:
      AcpOut{Acp{s, b, True{}}, Nil{}, [Acp.failed(Acp.hint(msg))], Nil{}}

# Replies to our requests (by id)
# -------------------------------

def Acp.opened(a: Acp, +t: AcpTurn, +sid: String) -> AcpOut:
  match a:
    case Acp{_, b, d}:
      AcpOut{Acp{sid, b, d}, [Acp.say.k(String.is_empty(Acp.session(t)), t, sid)], [Acp.event("thread.started", [J.KV{"thread_id", J.Str{sid}}])], Nil{}}

def Acp.finished(a: Acp) -> AcpOut:
  match a:
    case Acp{s, +b, _}:
      AcpOut{Acp{s, b, True{}}, Nil{},
        List.append(&2, String, Bool.pick(List<&2, String>, String.is_empty(b), Nil{}, [Acp.event("item.completed", [J.KV{"item", J.Json.obj([J.KV{"type", J.Str{"agent_message"}}, J.KV{"text", J.Str{b}}])}])]),
          [Acp.event("turn.completed", Nil{})]), Nil{}}

def Acp.reply.k(id: Nat, ok: Bool, a: Acp, +t: AcpTurn, +o: J.Json) -> AcpOut:
  match id ok:
    case _ False{}:
      Acp.fail(a, Acp.error(o))
    case 1n True{}:
      AcpOut{a, [Acp.open(t)], Nil{}, Nil{}}
    case 2n True{}:
      Acp.opened(a, t, J.Json.get_str(J.Json.get_obj(o, "result"), "sessionId", Acp.session(t)))
    case 3n True{}:
      Acp.finished(a)
    case _ True{}:
      AcpOut{a, Nil{}, Nil{}, Nil{}}

# Agent → client: updates and permission requests
# -----------------------------------------------

# an ACP plan's entries ({content, priority, status}) as todo items
def Acp.plan(es: List<&2, J.Json>) -> List<&2, J.Json>:
  match es:
    case Nil{}:
      Nil{}
    case +e <> t:
      J.Json.obj([J.KV{"text", J.Str{J.Json.get_str(e, "content", "")}}, J.KV{"status", J.Str{J.Json.get_str(e, "status", "pending")}}]) <> Acp.plan(t)

def Acp.update.k(i: Nat, a: Acp, +u: J.Json) -> AcpOut:
  match i a:
    case 0n Acp{s, b, d}:
      AcpOut{Acp{s, b ++ J.Json.get_str(J.Json.get_obj(u, "content"), "text", ""), d}, Nil{},
        [Acp.event("item.delta", [J.KV{"text", J.Str{J.Json.get_str(J.Json.get_obj(u, "content"), "text", "")}}])], Nil{}}
    case 1n _:
      AcpOut{a, Nil{}, [Acp.event("item.completed", [J.KV{"item", J.Json.obj([J.KV{"type", J.Str{"command_execution"}}, J.KV{"id", J.Str{J.Json.get_str(u, "toolCallId", "")}},
        J.KV{"command", J.Str{J.Json.get_str(u, "title", J.Json.get_str(u, "kind", "tool"))}}])}])], Nil{}}
    case 2n _:
      AcpOut{a, Nil{}, [Acp.event("item.updated", [J.KV{"item", J.Json.obj([J.KV{"type", J.Str{"todo_list"}}, J.KV{"items", J.Json.arr(Acp.plan(J.Json.elems(J.Json.get_obj(u, "entries"))))}])}])], Nil{}}
    case _ _:
      AcpOut{a, Nil{}, Nil{}, Nil{}}

# the first option that allows, else the first one
def Acp.allow(os: List<&2, J.Json>, +first: String) -> String:
  match os:
    case Nil{}:
      first
    case +o <> t:
      Bool.pick(String, String.starts_with(J.Json.get_str(o, "kind", ""), "allow"), J.Json.get_str(o, "optionId", first), Acp.allow(t, first))

def Acp.first(os: List<&2, J.Json>) -> String:
  match os:
    case o <> _:
      J.Json.get_str(o, "optionId", "")
    case Nil{}:
      ""

# the agent asks before a tool runs: in full access, allow at once
def Acp.permit(+id: String, +params: J.Json) -> String:
  "{\"jsonrpc\":\"2.0\",\"id\":" ++ id ++ ",\"result\":{\"outcome\":{\"outcome\":\"selected\",\"optionId\":"
    ++ J.Json.show(J.Str{Acp.allow(J.Json.elems(J.Json.get_obj(params, "options")), Acp.first(J.Json.elems(J.Json.get_obj(params, "options"))))}) ++ "}}}"

def Acp.pos(xs: List<&2, String>, +x: String, +i: Nat) -> Nat:
  match xs:
    case Nil{}:
      i
    case +h <> t:
      Bool.pick(Nat, String.eq(h, x), i, Acp.pos(t, x, 1n+i))

def Acp.open_now(a: Acp) -> Bool:
  match a:
    case Acp{s, _, _}:
      Bool.not(String.is_empty(s))

# session/load replays the old conversation as updates before it answers:
# only updates after the session is open belong to this turn
def Acp.update.live(open: Bool, a: Acp, +o: J.Json) -> AcpOut:
  match open:
    case True{}:
      Acp.update.k(Acp.pos(["agent_message_chunk", "tool_call", "plan"], J.Json.get_str(J.Json.get_obj(J.Json.get_obj(o, "params"), "update"), "sessionUpdate", ""), 0n), a,
        J.Json.get_obj(J.Json.get_obj(o, "params"), "update"))
    case False{}:
      AcpOut{a, Nil{}, Nil{}, Nil{}}

# otherwise the request goes to the user as an approval, and the runner
# writes the answer back when it comes (Acp.permit.answer)
def Acp.permit.route(ask: Bool, a: Acp, +id: String, +o: J.Json) -> AcpOut:
  match ask:
    case True{}:
      AcpOut{a, Nil{}, Nil{}, [J.Json.show(o)]}
    case False{}:
      AcpOut{a, [Acp.permit(id, J.Json.get_obj(o, "params"))], Nil{}, Nil{}}

def Acp.ask_of(t: AcpTurn) -> Bool:
  match t:
    case AcpTurn{_, _, _, _, _, k}:
      k

def Acp.request.k(i: Nat, ask: Bool, +a: Acp, +id: String, +o: J.Json) -> AcpOut:
  match i:
    case 0n:
      Acp.update.live(Acp.open_now(a), a, o)
    case 1n:
      Acp.permit.route(ask, a, id, o)
    case _:
      AcpOut{a, Bool.pick(List<&2, String>, String.is_empty(id), Nil{},
        ["{\"jsonrpc\":\"2.0\",\"id\":" ++ id ++ ",\"error\":{\"code\":-32601,\"message\":\"not supported\"}}"]), Nil{}, Nil{}}

# a request's id as JSON (numbers and strings alike), "" for a notification
def Acp.id(m: Maybe<&2, J.Json>) -> String:
  match m:
    case Some{v}:
      J.Json.show(v)
    case None{}:
      ""

def Acp.line.k(req: Bool, a: Acp, +t: AcpTurn, +o: J.Json) -> AcpOut:
  match req:
    case True{}:
      Acp.request.k(Acp.pos(["session/update", "session/request_permission"], J.Json.get_str(o, "method", ""), 0n), Acp.ask_of(t), a, Acp.id(J.Json.get(o, "id")), o)
    case False{}:
      Acp.reply.k(Maybe.default(&2, Nat, Nat.read(J.Json.as_raw(J.Json.get(o, "id"), "0")), 0n), String.eq(J.Json.show(J.Json.get_obj(o, "error")), "null"), a, t, o)

def Acp.line.parsed(m: Maybe<&2, J.Json>, a: Acp, +t: AcpTurn) -> AcpOut:
  match m:
    case Some{+o}:
      Acp.line.k(Bool.not(String.is_empty(J.Json.get_str(o, "method", ""))), a, t, o)
    case None{}:
      AcpOut{a, Nil{}, Nil{}, Nil{}}

# one line from the agent
def Acp.line(a: Acp, +t: AcpTurn, line: String) -> AcpOut:
  Acp.line.parsed(J.Json.parse(line), a, t)

# Permission answers
# ------------------
# A request_permission the user answers: "accept" picks the allow-once
# option, "session" the allow-always one (Allow for session), anything else
# a reject option; with no option of that kind the request is cancelled.

def Acp.kind.find(os: List<&2, J.Json>, +kind: String) -> String:
  match os:
    case Nil{}:
      ""
    case +o <> t:
      Bool.pick(String, String.eq(J.Json.get_str(o, "kind", ""), kind), J.Json.get_str(o, "optionId", ""), Acp.kind.find(t, kind))

def Acp.or(+a: String, +b: String) -> String:
  Bool.pick(String, String.is_empty(a), b, a)

# the option the user's answer selects ("" for none)
def Acp.choose(+answer: String, +os: List<&2, J.Json>) -> String:
  Bool.pick(String, String.eq(answer, "accept"), Acp.or(Acp.kind.find(os, "allow_once"), Acp.kind.find(os, "allow_always")),
    Bool.pick(String, String.eq(answer, "session"), Acp.or(Acp.kind.find(os, "allow_always"), Acp.kind.find(os, "allow_once")),
      Acp.or(Acp.kind.find(os, "reject_once"), Acp.kind.find(os, "reject_always"))))

def Acp.outcome(+opt: String) -> J.Json:
  Bool.pick(J.Json, String.is_empty(opt), J.Json.obj([J.KV{"outcome", J.Str{"cancelled"}}]),
    J.Json.obj([J.KV{"outcome", J.Str{"selected"}}, J.KV{"optionId", J.Str{opt}}]))

# the response line for a permission request (id as JSON text)
def Acp.permit.reply(+id: String, +params: J.Json, +answer: String) -> String:
  "{\"jsonrpc\":\"2.0\",\"id\":" ++ id ++ ",\"result\":" ++ J.Json.show(J.Json.obj([J.KV{"outcome", Acp.outcome(Acp.choose(answer, J.Json.elems(J.Json.get_obj(params, "options"))))}])) ++ "}"

def Acp.permit.answer.k(+o: J.Json, +answer: String) -> String:
  Acp.permit.reply(Acp.id(J.Json.get(o, "id")), J.Json.get_obj(o, "params"), answer)

# the response for a parked request line, once the user answered
def Acp.permit.answer(+body: String, +answer: String) -> String:
  Acp.permit.answer.k(Maybe.default(&2, J.Json, J.Json.parse(body), J.Null{}), answer)

# what a request asks to run: the tool (its kind, else its title; what
# "Allow for session" remembers) and a line for the approval card
def Acp.tool(+params: J.Json) -> String:
  Acp.or(J.Json.get_str(J.Json.get_obj(params, "toolCall"), "kind", ""), J.Json.get_str(J.Json.get_obj(params, "toolCall"), "title", "tool"))

def Acp.detail.k(+tc: J.Json, +raw: J.Json) -> String:
  Acp.or(J.Json.get_str(raw, "command", J.Json.get_str(raw, "path", J.Json.get_str(raw, "file_path", ""))),
    Acp.or(J.Json.get_str(tc, "title", ""), String.take(J.Json.show(raw), 400n)))

def Acp.detail(+params: J.Json) -> String:
  Acp.detail.k(J.Json.get_obj(params, "toolCall"), J.Json.get_obj(J.Json.get_obj(params, "toolCall"), "rawInput"))
