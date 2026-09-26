import Base
import ./check.bend as C
import ../src/core/client.bend as U
import ../src/core/json.bend as J
import ../src/app/nui.bend as N

# Dictation in the window (nui.bend's Nui.hear): a segment for the
# selected thread goes in at the composer's caret, the caret moves past
# it, undo takes it back out, and the draft is written down.

def nui(s: N.Step) -> N.Nui:
  match s:
    case N.Step{n, _, _}:
      n

def kept.go(cs: List<&2, N.NCmd>) -> String:
  match cs:
    case Nil{}:
      ""
    case N.NKeep{th, t} <> r:
      th ++ "=" ++ t ++ ";" ++ kept.go(r)
    case _ <> r:
      kept.go(r)

def kept(s: N.Step) -> String:
  match s:
    case N.Step{_, cs, _}:
      kept.go(cs)

def key(+n: N.Nui, +c: U32) -> N.Nui:
  nui(N.Nui.key(n, c, c, 0))

def ctrl(+n: N.Nui, +c: U32) -> N.Nui:
  nui(N.Nui.key(n, c, 0, 2))

def left(+n: N.Nui) -> N.Nui:
  nui(N.Nui.key(n, 65361, 0, 0))

def hear(+n: N.Nui, +t: String) -> N.Step:
  N.Nui.hear(n, Maybe.default(&2, J.Json, J.Json.parse(t), J.Null{}))

def text(+th: String, +t: String) -> String:
  "{\"t\":\"voice\",\"thread\":\"" ++ th ++ "\",\"ev\":\"text\",\"text\":\"" ++ t ++ "\",\"unsure\":[]}"

def start() -> N.Nui:
  N.Nui.init(U.Ui.select.k(U.Ui.init(0n), "t1"), 800, 600)

# "abc", then the caret moved one left: "ab|c"
def typed() -> N.Nui:
  left(key(key(key(start(), 97), 98), 99))

def draft(+n: N.Nui) -> String:
  U.Ui.draft_text(N.Nui.ui(n))

def main() -> IO(Unit):
  +s1 = hear(typed(), text("t1", "Hello"))
  +s2 = hear(key(key(key(start(), 97), 98), 99), text("t1", "Hello there."))
  +s3 = hear(typed(), text("t2", "Elsewhere"))
  do IO<Unit>:
    C.Check.str("at the caret", draft(nui(s1)), "ab hello c")
    C.Check.str("caret after it", Nat.show(N.Nui.caret_of(nui(s1))), "8")
    C.Check.str("typing goes on after it", draft(key(nui(s1), 33)), "ab hello! c")
    C.Check.str("written down", kept(s1), "t1=ab hello c;")
    C.Check.str("at the end", draft(nui(s2)), "abc hello there.")
    C.Check.str("caret at the end", Nat.show(N.Nui.caret_of(nui(s2))), "16")
    C.Check.str("undo takes it out", draft(ctrl(nui(s2), 122)), "abc")
    C.Check.str("another thread's draft", U.Ui.scratch(N.Nui.ui(nui(s3)), "t2"), "Elsewhere")
    C.Check.str("another thread: this draft and caret stay", draft(nui(s3)) ++ "|" ++ Nat.show(N.Nui.caret_of(nui(s3))), "abc|2")
    C.Check.str("another thread written down", kept(s3), "t2=Elsewhere;")
