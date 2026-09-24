import Base
import ./check.bend as C
import ../src/core/cron.bend as K

def Show.ns.go(xs: List<&2, Nat>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      Nat.show(x) <> Show.ns.go(t)

def Show.ns(xs: List<&2, Nat>) -> String:
  String.join(Show.ns.go(xs), ",")

def Show.cron.m(m: Maybe<&2, K.Cron>) -> String:
  match m:
    case None{}:
      "none"
    case Some{K.Cron{mi, ho, dm, mo, dw, da, wa}}:
      Show.ns(mi) ++ " | " ++ Show.ns(ho) ++ " | " ++ Show.ns(dm) ++ " | " ++ Show.ns(mo) ++ " | " ++ Show.ns(dw) ++ " | " ++ Bool.show(da) ++ " " ++ Bool.show(wa)

def Show.cron(s: String) -> String:
  Show.cron.m(K.Cron.parse(s))

def Show.ok.m(m: Maybe<&2, K.Cron>) -> String:
  match m:
    case None{}:
      "none"
    case Some{_}:
      "some"

def Show.ok(s: String) -> String:
  Show.ok.m(K.Cron.parse(s))

def nx.m(m: Maybe<&2, K.Cron>, +after: Nat, +off: Nat, +east: Bool) -> String:
  match m:
    case None{}:
      "invalid"
    case Some{c}:
      Nat.show(K.Cron.next(c, after, off, east))

# the next time as epoch seconds
def nx(s: String, +after: Nat, +off: Nat, +east: Bool) -> String:
  nx.m(K.Cron.parse(s), after, off, east)

# 2026-09-24 10:07 UTC, a Thursday
def now() -> Nat:
  1790244420n

def due.m(m: Maybe<&2, K.Cron>, +last: Nat, +now: Nat) -> String:
  match m:
    case None{}:
      "invalid"
    case Some{c}:
      Bool.show(K.Cron.due(c, last, now, 0n, True{}))

def due(s: String, +last: Nat, +now: Nat) -> String:
  due.m(K.Cron.parse(s), last, now)

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("parse star", Show.cron("* * * * *"), "0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59 | 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23 | 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31 | 1,2,3,4,5,6,7,8,9,10,11,12 | 0,1,2,3,4,5,6 | True True")
    C.Check.str("parse lists ranges steps", Show.cron("*/15 9-17/4 1,15 */3 1-5"), "0,15,30,45 | 9,13,17 | 1,15 | 1,4,7,10 | 1,2,3,4,5 | False False")
    C.Check.str("parse sorted once", Show.cron("30,5,5,10-12 0 * * *"), "5,10,11,12,30 | 0 | 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31 | 1,2,3,4,5,6,7,8,9,10,11,12 | 0,1,2,3,4,5,6 | True True")
    C.Check.str("parse names", Show.cron("0 0 * JAN,mar-may Mon-Fri"), "0 | 0 | 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31 | 1,3,4,5 | 1,2,3,4,5 | True False")
    C.Check.str("parse dow 7 is sunday", Show.cron("0 0 * * 7"), "0 | 0 | 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31 | 1,2,3,4,5,6,7,8,9,10,11,12 | 0 | True False")
    C.Check.str("parse A/S", Show.cron("50/5 0 1 1 *"), "50,55 | 0 | 1 | 1 | 0,1,2,3,4,5,6 | False True")
    C.Check.str("text @hourly", K.Cron.text("@hourly"), "0 * * * *")
    C.Check.str("text @daily", K.Cron.text("@daily"), "0 0 * * *")
    C.Check.str("text @midnight", K.Cron.text("@Midnight"), "0 0 * * *")
    C.Check.str("text @weekly", K.Cron.text("@weekly"), "0 0 * * 0")
    C.Check.str("text @monthly", K.Cron.text("@monthly"), "0 0 1 * *")
    C.Check.str("text @yearly", K.Cron.text("@yearly"), "0 0 1 1 *")
    C.Check.str("text @annually", K.Cron.text("@annually"), "0 0 1 1 *")
    C.Check.str("text every 15m", K.Cron.text("every 15m"), "*/15 * * * *")
    C.Check.str("text every 2h", K.Cron.text("Every 2h"), "0 */2 * * *")
    C.Check.str("text daily", K.Cron.text("daily 09:30"), "30 9 * * *")
    C.Check.str("text weekdays", K.Cron.text("weekdays 08:00"), "0 8 * * 1-5")
    C.Check.str("text spaces", K.Cron.text("  0   5 * *  *  "), "0 5 * * *")
    C.Check.str("text invalid", K.Cron.text("61 * * * *"), "")
    C.Check.str("reject minute 60", Show.ok("60 * * * *"), "none")
    C.Check.str("reject hour 24", Show.ok("0 24 * * *"), "none")
    C.Check.str("reject dom 0", Show.ok("0 0 0 * *"), "none")
    C.Check.str("reject dom 32", Show.ok("0 0 32 * *"), "none")
    C.Check.str("reject month 13", Show.ok("0 0 * 13 *"), "none")
    C.Check.str("reject dow 8", Show.ok("0 0 * * 8"), "none")
    C.Check.str("reject four fields", Show.ok("0 0 * *"), "none")
    C.Check.str("reject six fields", Show.ok("0 0 * * * *"), "none")
    C.Check.str("reject step 0", Show.ok("*/0 * * * *"), "none")
    C.Check.str("reject backwards range", Show.ok("5-1 * * * *"), "none")
    C.Check.str("reject junk", Show.ok("a b c d e"), "none")
    C.Check.str("reject empty item", Show.ok("1,,2 * * * *"), "none")
    C.Check.str("reject bad name", Show.ok("0 0 * foo *"), "none")
    C.Check.str("reject empty", Show.ok(""), "none")
    C.Check.str("reject unknown alias", Show.ok("@often"), "none")
    C.Check.str("reject every 0m", Show.ok("every 0m"), "none")
    C.Check.str("reject every 60m", Show.ok("every 60m"), "none")
    C.Check.str("reject every 24h", Show.ok("every 24h"), "none")
    C.Check.str("reject daily 25:00", Show.ok("daily 25:00"), "none")
    C.Check.str("reject daily 9", Show.ok("daily 9"), "none")
    C.Check.str("accept impossible date", Show.ok("0 0 31 2 *"), "some")
    C.Check.str("next every 15m", nx("every 15m", now(), 0n, True{}), "1790244900")
    C.Check.str("next every 15m on the boundary", nx("every 15m", 1790244900n, 0n, True{}), "1790245800")
    C.Check.str("next every minute", nx("* * * * *", now(), 0n, True{}), "1790244480")
    C.Check.str("next mid-minute", nx("* * * * *", 1790244450n, 0n, True{}), "1790244480")
    C.Check.str("next hourly", nx("@hourly", now(), 0n, True{}), "1790247600")
    C.Check.str("next every 2h", nx("every 2h", now(), 0n, True{}), "1790251200")
    C.Check.str("next daily UTC", nx("daily 09:30", now(), 0n, True{}), "1790328600")
    C.Check.str("next daily +05:30", nx("daily 09:30", now(), 19800n, True{}), "1790308800")
    C.Check.str("next daily -07:00", nx("daily 09:30", now(), 25200n, False{}), "1790267400")
    C.Check.str("next weekdays skips weekend", nx("weekdays 08:00", 1790328600n, 0n, True{}), "1790582400")
    C.Check.str("next weekdays from saturday", nx("weekdays 08:00", 1790424000n, 0n, True{}), "1790582400")
    C.Check.str("next monthly 31st skips september", nx("0 0 31 * *", now(), 0n, True{}), "1793404800")
    C.Check.str("next monthly 31st skips november", nx("0 0 31 * *", 1793404800n, 0n, True{}), "1798675200")
    C.Check.str("next leap day", nx("0 0 29 2 *", now(), 0n, True{}), "1835395200")
    C.Check.str("next @yearly", nx("@yearly", now(), 0n, True{}), "1798761600")
    C.Check.str("next sunday as 7", nx("0 0 * * 7", now(), 0n, True{}), "1790467200")
    C.Check.str("next sunday by name", nx("0 0 * * SUN", now(), 0n, True{}), "1790467200")
    C.Check.str("next dom or dow: friday first", nx("0 0 13 * 5", now(), 0n, True{}), "1790294400")
    C.Check.str("next dom or dow: 13th first", nx("0 0 13 * 5", 1791590400n, 0n, True{}), "1791849600")
    C.Check.str("next dom only", nx("0 0 13 * *", now(), 0n, True{}), "1791849600")
    C.Check.str("next dow only", nx("0 0 * * fri", 1791590400n, 0n, True{}), "1792108800")
    C.Check.str("next months and dow", nx("0 9 * jan mon", now(), 0n, True{}), "1799053200")
    C.Check.str("next impossible", nx("0 0 31 2 *", now(), 0n, True{}), "0")
    C.Check.str("next impossible april 31", nx("0 0 31 4 *", now(), 0n, True{}), "0")
    C.Check.str("due not yet", due("every 15m", now(), 1790244600n), "False")
    C.Check.str("due at the time", due("every 15m", now(), 1790244900n), "True")
    C.Check.str("due once after downtime", due("every 15m", now(), 1790254800n), "True")
    C.Check.str("not due again at once", due("every 15m", 1790254800n, 1790254800n), "False")
    C.Check.str("not due before the next", due("every 15m", 1790254800n, 1790255000n), "False")
    C.Check.str("due never when impossible", due("0 0 31 2 *", now(), 1835395200n), "False")
    C.Check.str("describe every 15m", K.Cron.describe("every 15m"), "every 15 minutes")
    C.Check.str("describe every minute", K.Cron.describe("* * * * *"), "every minute")
    C.Check.str("describe hourly", K.Cron.describe("@hourly"), "hourly")
    C.Check.str("describe hourly at", K.Cron.describe("5 * * * *"), "hourly at :05")
    C.Check.str("describe every 2h", K.Cron.describe("every 2h"), "every 2 hours")
    C.Check.str("describe daily", K.Cron.describe("daily 09:30"), "daily at 09:30")
    C.Check.str("describe midnight", K.Cron.describe("@daily"), "daily at 00:00")
    C.Check.str("describe weekdays", K.Cron.describe("weekdays 08:00"), "weekdays at 08:00")
    C.Check.str("describe other", K.Cron.describe("0 0 1 * *"), "0 0 1 * *")
    C.Check.str("describe every 7m", K.Cron.describe("every 7m"), "*/7 * * * *")
    C.Check.str("describe invalid", K.Cron.describe("nope"), "")
