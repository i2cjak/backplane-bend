import Base
import ./check.bend as C
import ../src/core/json.bend as J
import ../src/core/model.bend as M
import ../src/core/client.bend as U

# n entries of a thread, oldest first
def es(n: Nat, +k: Nat) -> List<&2, M.Entry>:
  match n:
    case 0n:
      Nil{}
    case 1n+j:
      M.Msg{"m" ++ Nat.show(k), "t1", M.User{}, "hi", k} <> es(j, 1n+k)

def first(w: U.Win) -> String:
  match w:
    case U.Win{_, M.Msg{i, _, _, _, _} <> _}:
      i
    case _:
      "-"

def len(w: U.Win) -> String:
  Nat.show(List.length(&2, M.Entry, U.Win.shown(w)))

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("page size", Nat.show(U.Page.count(0n)), "60")
    C.Check.str("earlier adds a page", Nat.show(U.Page.count(2n)), "180")
    C.Check.str("short thread shown whole", len(U.Page.window(es(10n, 0n), 60n)), "10")
    C.Check.str("short thread hides none", Nat.show(U.Win.hidden(U.Page.window(es(10n, 0n), 60n))), "0")
    C.Check.str("long thread newest page", len(U.Page.window(es(250n, 0n), 60n)), "60")
    C.Check.str("long thread hides the rest", Nat.show(U.Win.hidden(U.Page.window(es(250n, 0n), 60n))), "190")
    C.Check.str("window starts at the right entry", first(U.Page.window(es(250n, 0n), 60n)), "m190")
    C.Check.str("exact fit", Nat.show(U.Win.hidden(U.Page.window(es(60n, 0n), 60n))), "0")

