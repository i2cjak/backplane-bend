import Base

# Each once
# ---------
# A list that shows things (the bots in the sidebar, the room picker, the
# phone's list over every paired hub) keys each item by what it stands for,
# and keeps the first item of each key. Two items whose keys differ are
# never merged; an item whose key was already kept is dropped. Laws
# once_distinct (no key is kept twice) and once_keeps (a list whose keys are
# already distinct comes back whole).

type Ky<-A: Data> is Data:
  Ky{key: String, val: A}

# whether k is among ks (compared as String.eq(k, x))
def Once.in(ks: List<&2, String>, +k: String) -> Bool:
  match ks:
    case Nil{}:
      False{}
    case +x <> t:
      Bool.or(String.eq(k, x), Once.in(t, k))

# whether k appears in ys (compared as String.eq(y, k))
def Once.dup(ys: List<&2, String>, +k: String) -> Bool:
  match ys:
    case Nil{}:
      False{}
    case +y <> t:
      Bool.or(String.eq(y, k), Once.dup(t, k))

# no key appears twice
def Once.distinct(ks: List<&2, String>) -> Bool:
  match ks:
    case Nil{}:
      True{}
    case +k <> +t:
      Bool.and(Bool.not(Once.dup(t, k)), Once.distinct(t))

# none of ys is among seen
def Once.fresh(ys: List<&2, String>, +seen: List<&2, String>) -> Bool:
  match ys:
    case Nil{}:
      True{}
    case +y <> t:
      Bool.and(Bool.not(Once.in(seen, y)), Once.fresh(t, seen))

def Once.keys(-A: Data, xs: List<&2, Ky<A>>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case Ky{k, _} <> t:
      k <> Once.keys(A, t)

def Once.vals(-A: Data, xs: List<&2, Ky<A>>) -> List<&2, A>:
  match xs:
    case Nil{}:
      Nil{}
    case Ky{_, v} <> t:
      v <> Once.vals(A, t)

def Once.step(-A: Data, seen: Bool, +k: String, v: A, rest: List<&2, Ky<A>>) -> List<&2, Ky<A>>:
  match seen:
    case True{}:
      rest
    case False{}:
      Ky{k, v} <> rest

def Once.go(-A: Data, xs: List<&2, Ky<A>>, +seen: List<&2, String>) -> List<&2, Ky<A>>:
  match xs:
    case Nil{}:
      Nil{}
    case Ky{+k, v} <> t:
      Once.step(A, Once.in(seen, k), k, v, Once.go(A, t, k <> seen))

# the first item of each key, in order
def Once.of(-A: Data, xs: List<&2, Ky<A>>) -> List<&2, Ky<A>>:
  Once.go(A, xs, Nil{})
