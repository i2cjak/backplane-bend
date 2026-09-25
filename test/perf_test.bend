import Base
import ./check.bend as C
import ../src/core/perf.bend as PF
import ../src/server/perf.bend as PS

# rows as perf.c writes them: a span stream and a gauge
def rows0() -> String:
  "ui.frame\t0\t4\t10000\t6000\t1000\t0,0,0,0,0,0,0,0,0,0,2,1,0,1\nproc.rss_kb\t1\t1\t2048\t2048\t2048\t0\n"

def rows1() -> String:
  "ui.frame\t0\t10\t40000\t9000\t2000\t0,0,0,0,0,0,0,0,0,0,5,4,0,1\nproc.rss_kb\t1\t1\t4096\t4096\t4096\t0\nbad line\n"

# many rows, as a busy process has (a walk that doubles per row hangs here)
def many(+n: Nat) -> String:
  match n:
    case 0n:
      ""
    case 1n+k:
      "hub.k" ++ Nat.show(k) ++ "\t0\t2\t3000\t2000\t1000\t0,0,0,0,0,0,0,0,0,0,1,1\n" ++ many(k)

def frame(+t: String) -> PF.Stat:
  PF.Stats.find(PF.Stats.parse(t), "ui.frame")

def win() -> PF.Stat:
  PF.Stats.find(PF.Stats.since(PF.Stats.parse(rows1()), PF.Stats.parse(rows0())), "ui.frame")

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("parse skips bad lines", Nat.show(List.length(&2, PF.Stat, PF.Stats.parse(rows1()))), "2")
    C.Check.str("fields", Nat.show(PF.Stat.n(frame(rows0()))) ++ " " ++ Nat.show(PF.Stat.sum(frame(rows0()))) ++ " " ++ Nat.show(PF.Stat.max(frame(rows0()))), "4 10000 6000")
    C.Check.str("mean", Nat.show(PF.Stat.mean(frame(rows0()))), "2500")
    C.Check.str("p50 is a bucket top", Nat.show(PF.Stat.pct(frame(rows0()), 500n)), "1023")
    C.Check.str("p99 capped by max", Nat.show(PF.Stat.pct(frame(rows0()), 990n)), "6000")
    C.Check.str("window n and sum", Nat.show(PF.Stat.n(win())) ++ " " ++ Nat.show(PF.Stat.sum(win())), "6 30000")
    C.Check.str("window p50", Nat.show(PF.Stat.pct(win(), 500n)), "1023")
    C.Check.str("gauge keeps its reading", Nat.show(PF.Stat.last(PF.Stats.find(PF.Stats.since(PF.Stats.parse(rows1()), PF.Stats.parse(rows0())), "proc.rss_kb"))), "4096")
    C.Check.str("empty pct", Nat.show(PF.Stat.pct(PF.Stat.none("x"), 500n)), "0")
    C.Check.str("ms", PF.Perf.ms(1234n) ++ " " ++ PF.Perf.ms(56n), "1.2 0.0")
    C.Check.str("levels", Nat.show(PF.Log.level("warn")) ++ Nat.show(PF.Log.level("")) ++ Nat.show(PF.Log.level("trace")), "124")
    C.Check.str("debug hidden at info", Bool.show(PF.Log.on(3n, PF.Log.level("info"))), "False")
    C.Check.str("clock", PF.Log.clock(90061n), "01:01:01")
    C.Check.str("line", PF.Log.line(1n, 0n, "hub", "x"), "backplane 00:00:00 warn hub: x")
    C.Check.str("slow", Bool.show(PF.Perf.slow(150000n, 100n)) ++ Bool.show(PF.Perf.slow(90000n, 100n)), "TrueFalse")
    C.Check.str("hud frame row", Maybe.default(&2, String, List.head(&2, String, List.drop(&2, String, PF.Hud.lines(PF.Stats.since(PF.Stats.parse(rows1()), PF.Stats.parse(rows0())), 3000n), 1n)), ""), "frame        6    5.0    1.0    2.0")
    C.Check.str("hud with many rows", Nat.show(List.length(&2, String, String.lines(PF.Hud.text(many(60n), many(59n), 0n, 3000n)))), "12")
    # the effects: a span, a value and a gauge come back in a reading
    t0 : U32 <- PS.Perf.us()
    t1 : U32 <- PS.Perf.span("test.span", t0)
    PS.Perf.add("test.value", 5)
    PS.Perf.add("test.value", 7)
    PS.Perf.set("test.gauge", 9)
    PS.Perf.mark("test.mark")
    PS.Perf.done("test.mark")
    PS.Perf.done("test.mark")
    +r : String <- PS.Perf.take()
    C.Check.str("take: value", Nat.show(PF.Stat.n(PF.Stats.find(PF.Stats.parse(r), "test.value"))) ++ " " ++ Nat.show(PF.Stat.sum(PF.Stats.find(PF.Stats.parse(r), "test.value"))), "2 12")
    C.Check.str("take: span", Nat.show(PF.Stat.n(PF.Stats.find(PF.Stats.parse(r), "test.span"))), "1")
    C.Check.str("take: mark once", Nat.show(PF.Stat.n(PF.Stats.find(PF.Stats.parse(r), "test.mark"))), "1")
    C.Check.str("take: gauge", Bool.show(PF.Stat.gauge(PF.Stats.find(PF.Stats.parse(r), "test.gauge"))) ++ " " ++ Nat.show(PF.Stat.last(PF.Stats.find(PF.Stats.parse(r), "test.gauge"))), "True 9")
    PS.Log.at(4n, "test", "hidden at the default level")
    +logs : String <- PS.Perf.logs()
    C.Check.str("trace hidden", logs, "")
    IO.print(PF.Stats.table(PF.Stats.parse(r)))
