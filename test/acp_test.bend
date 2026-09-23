import Base
import ./check.bend as C
import ../src/core/acp.bend as A
import ../src/core/json.bend as J

# The Grok ACP translator: a scripted exchange, checked line by line.

def turn(+sid: String) -> A.AcpTurn:
  A.AcpTurn{"/tmp/p", "http://127.0.0.1:1/mcp/t?token=x", "RULES", "hello", sid}

def outs(o: A.AcpOut) -> String:
  match o:
    case A.AcpOut{_, send, emit}:
      String.join(List.append(&2, String, send, emit), " | ")

def st(o: A.AcpOut) -> A.Acp:
  match o:
    case A.AcpOut{a, _, _}:
      a

def method(+line: String) -> String:
  J.Json.get_str(Maybe.default(&2, J.Json, J.Json.parse(line), J.Null{}), "method", "")

def done(a: A.Acp) -> String:
  match a:
    case A.Acp{_, _, True{}}:
      "done"
    case A.Acp{_, _, False{}}:
      "open"

def main() -> IO(Unit):
  +t = turn("")
  +a0 = A.Acp.new()
  +o1 = A.Acp.line(a0, t, "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"protocolVersion\":1}}")
  +o2 = A.Acp.line(st(o1), t, "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"sessionId\":\"S1\"}}")
  +o3 = A.Acp.line(st(o2), t, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"S1\",\"update\":{\"sessionUpdate\":\"agent_message_chunk\",\"content\":{\"type\":\"text\",\"text\":\"Hi \"}}}}")
  +o4 = A.Acp.line(st(o3), t, "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"S1\",\"update\":{\"sessionUpdate\":\"agent_message_chunk\",\"content\":{\"type\":\"text\",\"text\":\"there\"}}}}")
  +o5 = A.Acp.line(st(o4), t, "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":{\"stopReason\":\"end_turn\"}}")
  +ob = A.Acp.line(a0, turn("OLD"), "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{}}")
  +orp = A.Acp.line(a0, turn("OLD"), "{\"jsonrpc\":\"2.0\",\"method\":\"session/update\",\"params\":{\"sessionId\":\"OLD\",\"update\":{\"sessionUpdate\":\"agent_message_chunk\",\"content\":{\"type\":\"text\",\"text\":\"old\"}}}}")
  +oe = A.Acp.line(a0, t, "{\"jsonrpc\":\"2.0\",\"id\":2,\"error\":{\"code\":-32000,\"message\":\"Authentication required\"}}")
  +op = A.Acp.line(a0, t, "{\"jsonrpc\":\"2.0\",\"id\":\"p9\",\"method\":\"session/request_permission\",\"params\":{\"options\":[{\"optionId\":\"no\",\"kind\":\"reject_once\"},{\"optionId\":\"yes\",\"kind\":\"allow_once\"}]}}")
  do IO<Unit>:
    C.Check.str("acp init method", method(A.Acp.init()), "initialize")
    C.Check.str("acp new session", method(outs(o1)), "session/new")
    C.Check.str("acp resume", method(outs(ob)), "session/load")
    C.Check.str("acp replay ignored", outs(orp), "")
    C.Check.str("acp opened", Bool.pick(String, String.contains(outs(o2), "session/prompt"), "yes", "no"), "yes")
    C.Check.str("acp rules first", Bool.pick(String, String.contains(outs(o2), "<backplane_instructions>\\nRULES"), "yes", "no"), "yes")
    C.Check.str("acp started", Bool.pick(String, String.contains(outs(o2), "{\"type\":\"thread.started\",\"thread_id\":\"S1\"}"), "yes", "no"), "yes")
    C.Check.str("acp delta", outs(o3), "{\"type\":\"item.delta\",\"text\":\"Hi \"}")
    C.Check.str("acp finished", outs(o5), "{\"type\":\"item.completed\",\"item\":{\"type\":\"agent_message\",\"text\":\"Hi there\"}} | {\"type\":\"turn.completed\"}")
    C.Check.str("acp finished state", done(st(o5)), "done")
    C.Check.str("acp auth", outs(oe), "{\"type\":\"turn.failed\",\"message\":\"Authentication required (sign in once with `grok login`)\"}")
    C.Check.str("acp permit", outs(op), "{\"jsonrpc\":\"2.0\",\"id\":\"p9\",\"result\":{\"outcome\":{\"outcome\":\"selected\",\"optionId\":\"yes\"}}}")
