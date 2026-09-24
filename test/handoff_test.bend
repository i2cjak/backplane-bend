import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/handoff.bend as H

def user(+n: Nat, +text: String) -> M.Entry:
  M.Msg{"u" ++ Nat.show(n), "t1", M.User{}, text, n}

def said(+n: Nat, +text: String) -> M.Entry:
  M.Msg{"a" ++ Nat.show(n), "t1", M.Assistant{}, text, n}

# n user/assistant pairs, newest first (as the state keeps entries), each
# assistant reply `size` characters long
def long.go(+n: Nat, +size: Nat, acc: List<&2, M.Entry>) -> List<&2, M.Entry>:
  match n:
    case 0n:
      acc
    case 1n+k:
      long.go(k, size, user(1n+k, "ask " ++ Nat.show(1n+k)) <> said(1n+k, String.repeat("x", size)) <> acc)

def long(+n: Nat, +size: Nat) -> List<&2, M.Entry>:
  List.reverse(&2, M.Entry, long.go(n, size, Nil{}))

def other() -> M.Entry:
  M.Msg{"o", "t2", M.User{}, "not mine", 1n}

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("short thread goes whole", H.Hand.fork([said(2n, "hello"), user(1n, "hi"), other()], "t1", "Board"),
      "[Backplane] This thread is a fork of \"Board\" (t1). You continue its work from where it stands; its conversation so far, oldest first:\n\nUser: hi\n\nAssistant: hello\n\n[End of the handed-over context. The user's message follows.]")
    +big : String = H.Hand.fork(long(40n, 1000n), "t1", "Big")
    C.Check.str("long thread fits the budget", Bool.show(Nat.is_le(String.length(big), Nat.add(H.Hand.budget(), 2400n))), "True")
    C.Check.str("keeps the first request", Bool.show(String.contains(big, "User: ask 1\n\n[")), "True")
    C.Check.str("says what it left out", Bool.show(String.contains(big, "earlier items left out; thread_read with threadId t1 has them all]")), "True")
    C.Check.str("keeps the newest", Bool.show(String.contains(big, "User: ask 40")), "True")
    C.Check.str("a huge item is cut", Bool.show(String.contains(H.Hand.fork([said(1n, String.repeat("y", 9000n))], "t1", "T"), " ...[5000 more characters]")), "True")
    C.Check.str("tool lines", H.Hand.line(M.Act{"x", "t1", "error", "shell", "make", 1n}), "Tool shell (failed): make")
