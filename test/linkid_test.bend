import Base
import ./check.bend as C
import ../src/core/model.bend as M

# M.Link.from scans an id from the front; it answers what the ':'-fields
# of the id say (the second, when the first is "t" and a third follows)

def old.k(ps: List<&2, String>) -> String:
  match ps:
    case "t" <> f <> _ <> _:
      f
    case _:
      ""

def old(+id: String) -> String:
  old.k(String.split(id, ':'))

def same(ids: List<&2, String>) -> IO(Unit):
  match ids:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case +id <> t:
      do IO<Unit>:
        C.Check.str("link from [" ++ id ++ "]", M.Link.from(id), old(id))
        same(t)

def main() -> IO(Unit):
  do IO<Unit>:
    same(["", "t", "t:", "t:a", "t:a:", "t:a:b", "t:a:b:c", "t::", "t::x", "tx:a:b", ":t:a:b", "m1790-4", "t1790175755-9",
      "T:a:b", "t:t1790175755-9:m1790175800-12", "t:a:b:"])
    C.Check.str("link id", M.Link.id("t17-9", "m18-2"), "t:t17-9:m18-2")
    C.Check.str("link round trip", M.Link.from(M.Link.id("t17-9", "m18-2")), "t17-9")
