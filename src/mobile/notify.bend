import Base
import ../core/json.bend as J
import ../core/model.bend as M

# What the phone tells its owner: an alert when a turn ends, and the
# Dynamic Island (iOS Live Activity, Android promoted notification) while
# turns run. The apps only post what these defs return.

# the kind of alert a turn's end raises: "done", "fail", or "" for none.
# Only a turn seen running can alert (law alert_needs_running), a running
# turn never does (law alert_never_running), and a stop the user asked for
# is not news.
def Note.kind(was: Bool, now: M.TurnState) -> String:
  match was now:
    case False{} _:
      ""
    case True{} M.Completed{}:
      "done"
    case True{} M.Idle{}:
      "done"
    case True{} M.Failed{}:
      "fail"
    case True{} _:
      ""

def Note.running(t: M.TurnState) -> Bool:
  match t:
    case M.Running{}:
      True{}
    case _:
      False{}

# is any thread running (the island shows, and the Live Activity lives,
# exactly while one is: law island_idle_empty)
def Note.busy(ts: List<&2, M.Thread>) -> Bool:
  match ts:
    case Nil{}:
      False{}
    case M.Thread{_, _, _, _, _, turn, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} <> t:
      Bool.or(Note.running(turn), Note.busy(t))

# which threads were running, taken before a server message is folded in
type Seen is Data:
  Seen{id: String, running: Bool}

def Note.seen(ts: List<&2, M.Thread>) -> List<&2, Seen>:
  match ts:
    case Nil{}:
      Nil{}
    case M.Thread{id, _, _, _, _, turn, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} <> t:
      Seen{id, Note.running(turn)} <> Note.seen(t)

def Note.was.k(hit: Bool, r: Bool, acc: Bool) -> Bool:
  match hit:
    case True{}:
      r
    case False{}:
      acc

def Note.was(ss: List<&2, Seen>, +id: String) -> Bool:
  match ss:
    case Nil{}:
      False{}
    case Seen{i, r} <> t:
      Note.was.k(String.eq(i, id), r, Note.was(t, id))

# the newest entry text of a thread (entries are kept newest first):
# its last assistant message, or its last tool action
def Note.pick(hit: Bool, +text: String, +acc: String) -> String:
  match hit:
    case True{}:
      Bool.pick(String, String.is_empty(acc), text, acc)
    case False{}:
      acc

def Note.said(es: List<&2, M.Entry>, +id: String, +acc: String) -> String:
  match es:
    case Nil{}:
      acc
    case M.Msg{_, th, M.Assistant{}, +text, _} <> t:
      Note.said(t, id, Note.pick(String.eq(th, id), text, acc))
    case _ <> t:
      Note.said(t, id, acc)

def Note.doing(es: List<&2, M.Entry>, +id: String, +acc: String) -> String:
  match es:
    case Nil{}:
      acc
    case M.Act{_, th, _, kind, summary, _} <> t:
      Note.doing(t, id, Note.pick(String.eq(th, id), kind ++ " " ++ summary, acc))
    case _ <> t:
      Note.doing(t, id, acc)

def Note.clip(+s: String, +n: Nat) -> String:
  Bool.pick(String, Nat.is_gt(String.length(s), n), String.take(s, n) ++ "…", s)

# the rest after c: nothing once the line ends
def Note.cut(c: Char, t: String) -> String:
  Bool.pick(String, Char.is_eq(c, '\n'), SNil{}, t)

# the first line, at most n characters of it, reversed. It reads only
# those, never the whole text: a reply can be megabytes long, and
# splitting it into lines recursed once per character (the phone's
# JavaScriptCore ran out of stack on a real log)
def Note.upto(n: Nat, s: String, acc: String) -> String:
  match n s:
    case 0n _:
      acc
    case 1n+_ SNil{}:
      acc
    case 1n+m SCon{+h, t}:
      Note.upto(m, Note.cut(h, t), SCon{h, acc})

# one line of at most n characters, for a banner or the island
def Note.line(s: String, +n: Nat) -> String:
  Note.clip(String.trim(String.reverse(Note.upto(Nat.add(n, 1n), String.trim_start(s), SNil{}))), n)

def Note.body(+kind: String, +said: String) -> String:
  Bool.pick(String, String.eq(kind, "fail"), "Failed", Bool.pick(String, String.is_empty(said), "Finished", Note.line(said, 180n)))

def Note.alert.k(+kind: String, +id: String, +title: String, +said: String, +rest: List<&2, J.Json>) -> List<&2, J.Json>:
  Bool.pick(List<&2, J.Json>, String.is_empty(kind), rest,
    J.Json.obj([J.KV{"thread", J.Json.str(id)}, J.KV{"title", J.Json.str(title)}, J.KV{"kind", J.Json.str(kind)},
      J.KV{"body", J.Json.str(Note.body(kind, said))}]) <> rest)

# the alerts a server message raised: every thread seen running before it
# that has now finished or failed
def Note.alerts(ts: List<&2, M.Thread>, +seen: List<&2, Seen>, +es: List<&2, M.Entry>) -> List<&2, J.Json>:
  match ts:
    case Nil{}:
      Nil{}
    case M.Thread{+id, _, title, _, _, turn, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} <> t:
      Note.alert.k(Note.kind(Note.was(seen, id), turn), id, title, Note.said(es, id, ""), Note.alerts(t, seen, es))

# the island: every running thread with what it is doing now
def Note.lines(ts: List<&2, M.Thread>, +es: List<&2, M.Entry>) -> List<&2, J.Json>:
  match ts:
    case Nil{}:
      Nil{}
    case M.Thread{+id, _, title, _, _, turn, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _} <> t:
      List.append(&2, J.Json, Bool.pick(List<&2, J.Json>, Note.running(turn),
        [J.Json.obj([J.KV{"thread", J.Json.str(id)}, J.KV{"title", J.Json.str(Note.line(title, 60n))},
          J.KV{"doing", J.Json.str(Note.line(Bool.pick(String, String.is_empty(Note.doing(es, id, "")), "Working", Note.doing(es, id, "")), 80n))}])],
        Nil{}), Note.lines(t, es))

def Note.headline(n: Nat, +first: String) -> String:
  match n:
    case 0n:
      "All agents idle"
    case 1n:
      first
    case _:
      Nat.show(n) ++ " agents working"

def Note.first(+ls: List<&2, J.Json>) -> String:
  J.Json.get_str(Maybe.default(&2, J.Json, List.head(&2, J.Json, ls), J.Null{}), "title", "")

def Note.island.k(+ls: List<&2, J.Json>) -> J.Json:
  J.Json.obj([J.KV{"running", J.Json.nat(List.length(&2, J.Json, ls))},
    J.KV{"headline", J.Json.str(Note.headline(List.length(&2, J.Json, ls), Note.first(ls)))},
    J.KV{"lines", J.Json.arr(ls)}])

def Note.island(ts: List<&2, M.Thread>, +es: List<&2, M.Entry>) -> J.Json:
  Note.island.k(Note.lines(ts, es))
