import Base
import ./model.bend as M

# Routine schedules
# -----------------
# A bot routine runs on a cron line: five fields (minute, hour, day of
# month, month, day of week), each `*`, `N`, `A-B`, `*/S`, `A-B/S`, `A/S`
# or a comma list of those; months jan..dec and days sun..sat by name; day
# of week 0-7 (0 and 7 are Sunday). Aliases: @hourly, @daily, @midnight,
# @weekly, @monthly, @yearly, @annually; friendly forms: "every 15m",
# "every 2h", "daily 09:30", "weekdays 08:00".
#
# Days follow cron: when both day of month and day of week are restricted a
# day matches either; when one is `*`, only the other counts.
#
# Times are local: UTC shifted `off` seconds east or west, as in
# M.Snooze.local. Cron.next is the first matching minute strictly after a
# time, or 0 when there is none within nine years (law cron_next_after).
# Cron.due fires a routine once for any number of missed times, and never
# twice at the same moment (law cron_due_fires_once).

# each field as its sorted values (no repeats); dom_any / dow_any: the day
# fields were `*`
type Cron is Data:
  Cron{mins: List<&2, Nat>, hours: List<&2, Nat>, doms: List<&2, Nat>, months: List<&2, Nat>, dows: List<&2, Nat>, dom_any: Bool, dow_any: Bool}

# one item of a field: a to b every s
type CRng is Data:
  CRng{a: Nat, b: Nat, s: Nat}

type CKV is Data:
  CKV{k: String, v: String}

type Ymd is Data:
  Ymd{y: Nat, m: Nat, d: Nat}

# a step of the search: found (local seconds), go on at a day, or give up
type CStep is Data:
  CFound{t: Nat}
  CGo{d: Nat}
  CStop{}

# Parsing
# -------

def Cron.dig.k(ok: Bool, c: Char, acc: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match ok acc:
    case True{} Some{n}:
      Some{Nat.add(Nat.mul(n, 10n), U32.to_nat((Char.to_u32(c) - 48 : U32)))}
    case True{} None{}:
      None{}
    case False{} _:
      None{}

def Cron.dig(+c: Char, acc: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  Cron.dig.k(Char.is_digit(c), c, acc)

def Cron.digits(s: String, acc: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match s:
    case SNil{}:
      acc
    case SCon{+c, t}:
      Cron.digits(t, Cron.dig(c, acc))

# a decimal number, at least one digit
def Cron.num(s: String) -> Maybe<&2, Nat>:
  match s:
    case SNil{}:
      None{}
    case SCon{+c, t}:
      Cron.digits(t, Cron.dig(c, Some{0n}))

def Cron.mnames() -> List<&2, String>:
  ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

def Cron.dnames() -> List<&2, String>:
  ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]

def Cron.name.k(hit: Bool, +i: Nat, rest: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match hit:
    case True{}:
      Some{i}
    case False{}:
      rest

# where s sits in names, counting from i
def Cron.name(xs: List<&2, String>, +s: String, +i: Nat) -> Maybe<&2, Nat>:
  match xs:
    case Nil{}:
      None{}
    case x <> t:
      Cron.name.k(String.eq(x, s), i, Cron.name(t, s, 1n+i))

def Cron.val.k(m: Maybe<&2, Nat>, +s: String, +names: List<&2, String>, +base: Nat) -> Maybe<&2, Nat>:
  match m:
    case Some{n}:
      Some{n}
    case None{}:
      Cron.name(names, s, base)

# a number or a name
def Cron.val(+s: String, +names: List<&2, String>, +base: Nat) -> Maybe<&2, Nat>:
  Cron.val.k(Cron.num(s), s, names, base)

def Cron.mk.k(ok: Bool, r: CRng) -> Maybe<&2, CRng>:
  match ok:
    case True{}:
      Some{r}
    case False{}:
      None{}

# a to b every s, within lo..hi
def Cron.mk(+a: Nat, +b: Nat, +s: Nat, +lo: Nat, +hi: Nat) -> Maybe<&2, CRng>:
  Cron.mk.k(Bool.and(Bool.and(Nat.is_ge(a, lo), Nat.is_le(a, b)), Bool.and(Nat.is_le(b, hi), Nat.is_ge(s, 1n))), CRng{a, b, s})

def Cron.one.v(m: Maybe<&2, Nat>, stepped: Bool, +s: Nat, +lo: Nat, +hi: Nat) -> Maybe<&2, CRng>:
  match m stepped:
    case None{} _:
      None{}
    case Some{+x} True{}:
      Cron.mk(x, hi, s, lo, hi)
    case Some{+x} False{}:
      Cron.mk(x, x, s, lo, hi)

# one value: `*`, or N (N/S runs to the end)
def Cron.one(star: Bool, stepped: Bool, +a: String, +s: Nat, +lo: Nat, +hi: Nat, +names: List<&2, String>, +base: Nat) -> Maybe<&2, CRng>:
  match star:
    case True{}:
      Cron.mk(lo, hi, s, lo, hi)
    case False{}:
      Cron.one.v(Cron.val(a, names, base), stepped, s, lo, hi)

def Cron.two.v(x: Maybe<&2, Nat>, y: Maybe<&2, Nat>, +s: Nat, +lo: Nat, +hi: Nat) -> Maybe<&2, CRng>:
  match x y:
    case Some{+a} Some{+b}:
      Cron.mk(a, b, s, lo, hi)
    case _ _:
      None{}

def Cron.rng(ps: List<&2, String>, stepped: Bool, +s: Nat, +lo: Nat, +hi: Nat, +names: List<&2, String>, +base: Nat) -> Maybe<&2, CRng>:
  match ps:
    case +a <> Nil{}:
      Cron.one(String.eq(a, "*"), stepped, a, s, lo, hi, names, base)
    case +a <> +b <> Nil{}:
      Cron.two.v(Cron.val(a, names, base), Cron.val(b, names, base), s, lo, hi)
    case _:
      None{}

def Cron.rng.s(m: Maybe<&2, Nat>, +r: String, +lo: Nat, +hi: Nat, +names: List<&2, String>, +base: Nat) -> Maybe<&2, CRng>:
  match m:
    case None{}:
      None{}
    case Some{+s}:
      Cron.rng(String.split(r, '-'), True{}, s, lo, hi, names, base)

def Cron.item.k(ps: List<&2, String>, +lo: Nat, +hi: Nat, +names: List<&2, String>, +base: Nat) -> Maybe<&2, CRng>:
  match ps:
    case +r <> Nil{}:
      Cron.rng(String.split(r, '-'), False{}, 1n, lo, hi, names, base)
    case +r <> +st <> Nil{}:
      Cron.rng.s(Cron.num(st), r, lo, hi, names, base)
    case _:
      None{}

# one comma-separated item
def Cron.item(+s: String, +lo: Nat, +hi: Nat, +names: List<&2, String>, +base: Nat) -> Maybe<&2, CRng>:
  Cron.item.k(String.split(s, '/'), lo, hi, names, base)

def Cron.items.k(a: Maybe<&2, CRng>, b: Maybe<&2, List<&2, CRng>>) -> Maybe<&2, List<&2, CRng>>:
  match a b:
    case Some{r} Some{rs}:
      Some{r <> rs}
    case _ _:
      None{}

def Cron.items(ps: List<&2, String>, +lo: Nat, +hi: Nat, +names: List<&2, String>, +base: Nat) -> Maybe<&2, List<&2, CRng>>:
  match ps:
    case Nil{}:
      Some{[]}
    case +p <> t:
      Cron.items.k(Cron.item(p, lo, hi, names, base), Cron.items(t, lo, hi, names, base))

# a field as its items; None when any item is malformed or out of range
def Cron.rngs(+s: String, +lo: Nat, +hi: Nat, +names: List<&2, String>, +base: Nat) -> Maybe<&2, List<&2, CRng>>:
  Cron.items(String.split(s, ','), lo, hi, names, base)

def Cron.covers(r: CRng, +v: Nat) -> Bool:
  match r:
    case CRng{+a, +b, +s}:
      Bool.and(Bool.and(Nat.is_ge(v, a), Nat.is_le(v, b)), Nat.is_eq(Nat.mod(Nat.sub(v, a), s), 0n))

def Cron.hit(rs: List<&2, CRng>, +v: Nat) -> Bool:
  match rs:
    case Nil{}:
      False{}
    case r <> t:
      Bool.or(Cron.covers(r, v), Cron.hit(t, v))

def Cron.keep(b: Bool, +v: Nat, rest: List<&2, Nat>) -> List<&2, Nat>:
  match b:
    case True{}:
      v <> rest
    case False{}:
      rest

def Cron.vals.go(k: Nat, +v: Nat, +rs: List<&2, CRng>) -> List<&2, Nat>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      Cron.keep(Cron.hit(rs, v), v, Cron.vals.go(p, 1n+v, rs))

# the values lo..hi the items cover, in order, once each
def Cron.vals(+rs: List<&2, CRng>, +lo: Nat, +hi: Nat) -> List<&2, Nat>:
  Cron.vals.go(1n+Nat.sub(hi, lo), lo, rs)

def Cron.dvals.go(k: Nat, +v: Nat, +rs: List<&2, CRng>) -> List<&2, Nat>:
  match k:
    case 0n:
      Nil{}
    case 1n+p:
      Cron.keep(Bool.or(Cron.hit(rs, v), Bool.and(Nat.is_eq(v, 0n), Cron.hit(rs, 7n))), v, Cron.dvals.go(p, 1n+v, rs))

# days of the week 0..6, with 7 counted as Sunday
def Cron.dvals(+rs: List<&2, CRng>) -> List<&2, Nat>:
  Cron.dvals.go(7n, 0n, rs)

def Cron.build(mi: Maybe<&2, List<&2, CRng>>, ho: Maybe<&2, List<&2, CRng>>, dm: Maybe<&2, List<&2, CRng>>, mo: Maybe<&2, List<&2, CRng>>, dw: Maybe<&2, List<&2, CRng>>, da: Bool, wa: Bool) -> Maybe<&2, Cron>:
  match mi ho dm mo dw:
    case Some{+a} Some{+b} Some{+c} Some{+d} Some{+e}:
      Some{Cron{Cron.vals(a, 0n, 59n), Cron.vals(b, 0n, 23n), Cron.vals(c, 1n, 31n), Cron.vals(d, 1n, 12n), Cron.dvals(e), da, wa}}
    case _ _ _ _ _:
      None{}

def Cron.keep.s(empty: Bool, w: String, rest: List<&2, String>) -> List<&2, String>:
  match empty:
    case True{}:
      rest
    case False{}:
      w <> rest

# Aliases and friendly forms
# --------------------------

def Cron.nonempty(ws: List<&2, String>) -> List<&2, String>:
  match ws:
    case Nil{}:
      Nil{}
    case +w <> t:
      Cron.keep.s(String.is_empty(w), w, Cron.nonempty(t))

def Cron.words(s: String) -> List<&2, String>:
  Cron.nonempty(String.split(String.trim(s), ' '))

def Cron.aliases() -> List<&2, CKV>:
  [CKV{"@hourly", "0 * * * *"}, CKV{"@daily", "0 0 * * *"}, CKV{"@midnight", "0 0 * * *"}, CKV{"@weekly", "0 0 * * 0"}, CKV{"@monthly", "0 0 1 * *"}, CKV{"@yearly", "0 0 1 1 *"}, CKV{"@annually", "0 0 1 1 *"}]

def Cron.look.k(hit: Bool, v: String, rest: String) -> String:
  match hit:
    case True{}:
      v
    case False{}:
      rest

def Cron.look(xs: List<&2, CKV>, +k: String) -> String:
  match xs:
    case Nil{}:
      ""
    case CKV{a, v} <> t:
      Cron.look.k(String.eq(a, k), v, Cron.look(t, k))

def Cron.within.k(ok: Bool, n: Nat) -> Maybe<&2, Nat>:
  match ok:
    case True{}:
      Some{n}
    case False{}:
      None{}

def Cron.within(m: Maybe<&2, Nat>, +lo: Nat, +hi: Nat) -> Maybe<&2, Nat>:
  match m:
    case None{}:
      None{}
    case Some{+n}:
      Cron.within.k(Bool.and(Nat.is_ge(n, lo), Nat.is_le(n, hi)), n)

def Cron.every.line(m: Maybe<&2, Nat>, +pre: String, +post: String) -> String:
  match m:
    case None{}:
      ""
    case Some{+n}:
      pre ++ Nat.show(n) ++ post

def Cron.every.min(+n: Maybe<&2, Nat>) -> String:
  Cron.every.line(Cron.within(n, 1n, 59n), "*/", " * * * *")

def Cron.every.k(m: Bool, h: Bool, +n: Maybe<&2, Nat>) -> String:
  match m h:
    case True{} _:
      Cron.every.min(n)
    case False{} True{}:
      Cron.every.line(Cron.within(n, 1n, 23n), "0 */", " * * *")
    case False{} False{}:
      ""

# "every 15m" / "every 2h"
def Cron.every(+w: String) -> String:
  Cron.every.k(String.ends_with(w, "m"), String.ends_with(w, "h"), Cron.num(String.take(w, Nat.sub(String.length(w), 1n))))

def Cron.at.k(h: Maybe<&2, Nat>, m: Maybe<&2, Nat>, +dw: String) -> String:
  match h m:
    case Some{+a} Some{+b}:
      Nat.show(b) ++ " " ++ Nat.show(a) ++ " * * " ++ dw
    case _ _:
      ""

def Cron.at.ps(ps: List<&2, String>, +dw: String) -> String:
  match ps:
    case +h <> +m <> Nil{}:
      Cron.at.k(Cron.within(Cron.num(h), 0n, 23n), Cron.within(Cron.num(m), 0n, 59n), dw)
    case _:
      ""

# "HH:MM" on the given days of the week
def Cron.at(+t: String, +dw: String) -> String:
  Cron.at.ps(String.split(t, ':'), dw)

def Cron.two.k(ev: Bool, dy: Bool, wd: Bool, +b: String) -> String:
  match ev dy wd:
    case True{} _ _:
      Cron.every(b)
    case False{} True{} _:
      Cron.at(b, "*")
    case False{} False{} True{}:
      Cron.at(b, "1-5")
    case False{} False{} False{}:
      ""

def Cron.two(+a: String, +b: String) -> String:
  Cron.two.k(String.eq(a, "every"), String.eq(a, "daily"), String.eq(a, "weekdays"), b)

def Cron.fields.ws(ws: List<&2, String>) -> List<&2, String>:
  match ws:
    case Nil{}:
      Nil{}
    case +a <> Nil{}:
      Cron.words(Cron.look(Cron.aliases(), a))
    case +a <> +b <> Nil{}:
      Cron.words(Cron.two(a, b))
    case a <> b <> c <> t:
      a <> b <> c <> t

# the five fields of a schedule, aliases and friendly forms expanded
def Cron.fields(s: String) -> List<&2, String>:
  Cron.fields.ws(Cron.words(String.to_lower(s)))

def Cron.parse.fs(ws: List<&2, String>) -> Maybe<&2, Cron>:
  match ws:
    case +mi <> +ho <> +dm <> +mo <> +dw <> Nil{}:
      Cron.build(Cron.rngs(mi, 0n, 59n, [], 0n), Cron.rngs(ho, 0n, 23n, [], 0n), Cron.rngs(dm, 1n, 31n, [], 0n), Cron.rngs(mo, 1n, 12n, Cron.mnames(), 1n), Cron.rngs(dw, 0n, 7n, Cron.dnames(), 0n), String.eq(dm, "*"), String.eq(dw, "*"))
    case _:
      None{}

# a schedule, or None when it is malformed or out of range
def Cron.parse(s: String) -> Maybe<&2, Cron>:
  Cron.parse.fs(Cron.fields(s))

def Cron.text.k(m: Maybe<&2, Cron>, +fs: List<&2, String>) -> String:
  match m:
    case None{}:
      ""
    case Some{_}:
      String.join(fs, " ")

# the normalised cron line ("daily 09:30" is "30 9 * * *"); "" when invalid
def Cron.text(+s: String) -> String:
  Cron.text.k(Cron.parse(s), Cron.fields(s))

# Dates
# -----

def Cron.civil.k(early: Bool, +y: Nat, +mp: Nat, +d: Nat) -> Ymd:
  match early:
    case True{}:
      Ymd{y, Nat.add(mp, 3n), d}
    case False{}:
      Ymd{1n+y, Nat.sub(mp, 9n), d}

def Cron.civil.mp(+y: Nat, +mp: Nat, +doy: Nat) -> Ymd:
  Cron.civil.k(Nat.is_lt(mp, 10n), y, mp, Nat.add(Nat.sub(doy, Nat.div(Nat.add(Nat.mul(153n, mp), 2n), 5n)), 1n))

# day of the year from March (doy) in year-of-era yoe of era
def Cron.civil.doy(+era: Nat, +yoe: Nat, +doy: Nat) -> Ymd:
  Cron.civil.mp(Nat.add(yoe, Nat.mul(era, 400n)), Nat.div(Nat.add(Nat.mul(5n, doy), 2n), 153n), doy)

def Cron.civil.yoe(+era: Nat, +doe: Nat, +yoe: Nat) -> Ymd:
  Cron.civil.doy(era, yoe, Nat.sub(doe, Nat.sub(Nat.add(Nat.mul(365n, yoe), Nat.div(yoe, 4n)), Nat.div(yoe, 100n))))

def Cron.civil.doe(+era: Nat, +doe: Nat) -> Ymd:
  Cron.civil.yoe(era, doe, Nat.div(Nat.sub(Nat.add(doe, Nat.div(doe, 36524n)), Nat.add(Nat.div(doe, 1460n), Nat.div(doe, 146096n))), 365n))

def Cron.civil.z(+z: Nat, +era: Nat) -> Ymd:
  Cron.civil.doe(era, Nat.sub(z, Nat.mul(era, 146097n)))

def Cron.civil.at(+z: Nat) -> Ymd:
  Cron.civil.z(z, Nat.div(z, 146097n))

# the date of a day counted from 1970-01-01 (Hinnant's civil_from_days)
def Cron.civil(+days: Nat) -> Ymd:
  Cron.civil.at(Nat.add(days, 719468n))

def Cron.days.doe(+era: Nat, +doe: Nat) -> Nat:
  Nat.sub(Nat.add(Nat.mul(era, 146097n), doe), 719468n)

def Cron.days.yoe(+era: Nat, +yoe: Nat, +doy: Nat) -> Nat:
  Cron.days.doe(era, Nat.add(Nat.sub(Nat.add(Nat.mul(yoe, 365n), Nat.div(yoe, 4n)), Nat.div(yoe, 100n)), doy))

def Cron.days.era(+y: Nat, +era: Nat, +doy: Nat) -> Nat:
  Cron.days.yoe(era, Nat.sub(y, Nat.mul(era, 400n)), doy)

def Cron.days.go(+y: Nat, +mp: Nat, +d: Nat) -> Nat:
  Cron.days.era(y, Nat.div(y, 400n), Nat.add(Nat.div(Nat.add(Nat.mul(153n, mp), 2n), 5n), Nat.sub(d, 1n)))

def Cron.days.k(early: Bool, +y: Nat, +m: Nat, +d: Nat) -> Nat:
  match early:
    case True{}:
      Cron.days.go(Nat.sub(y, 1n), Nat.add(m, 9n), d)
    case False{}:
      Cron.days.go(y, Nat.sub(m, 3n), d)

# the day number of a date (Hinnant's days_from_civil)
def Cron.days(+y: Nat, +m: Nat, +d: Nat) -> Nat:
  Cron.days.k(Nat.is_le(m, 2n), y, m, d)

# Search
# ------

def Cron.pick(b: Bool, +x: Nat, rest: Maybe<&2, Nat>) -> Maybe<&2, Nat>:
  match b:
    case True{}:
      Some{x}
    case False{}:
      rest

# the first value at least v
def Cron.first(xs: List<&2, Nat>, +v: Nat) -> Maybe<&2, Nat>:
  match xs:
    case Nil{}:
      None{}
    case +x <> t:
      Cron.pick(Nat.is_ge(x, v), x, Cron.first(t, v))

def Cron.has(xs: List<&2, Nat>, +v: Nat) -> Bool:
  match xs:
    case Nil{}:
      False{}
    case +x <> t:
      Bool.or(Nat.is_eq(x, v), Cron.has(t, v))

def Cron.head(xs: List<&2, Nat>) -> Nat:
  Maybe.default(&2, Nat, List.head(&2, Nat, xs), 0n)

# cron's day rule: both restricted, either will do
def Cron.day.ok(da: Bool, wa: Bool, dm: Bool, dw: Bool) -> Bool:
  match da wa:
    case True{} True{}:
      True{}
    case True{} False{}:
      dw
    case False{} True{}:
      dm
    case False{} False{}:
      Bool.or(dm, dw)

def Cron.clock.n(m: Maybe<&2, Nat>, +mins: List<&2, Nat>) -> Maybe<&2, Nat>:
  match m:
    case None{}:
      None{}
    case Some{+h}:
      Some{Nat.add(Nat.mul(h, 60n), Cron.head(mins))}

def Cron.clock.m(m: Maybe<&2, Nat>, +h: Nat, +hours: List<&2, Nat>, +mins: List<&2, Nat>) -> Maybe<&2, Nat>:
  match m:
    case Some{+x}:
      Some{Nat.add(Nat.mul(h, 60n), x)}
    case None{}:
      Cron.clock.n(Cron.first(hours, 1n+h), mins)

def Cron.clock.h(same: Bool, +h: Nat, +hours: List<&2, Nat>, +mins: List<&2, Nat>, +mm: Nat) -> Maybe<&2, Nat>:
  match same:
    case True{}:
      Cron.clock.m(Cron.first(mins, mm), h, hours, mins)
    case False{}:
      Some{Nat.add(Nat.mul(h, 60n), Cron.head(mins))}

def Cron.clock.k(m: Maybe<&2, Nat>, +h0: Nat, +hours: List<&2, Nat>, +mins: List<&2, Nat>, +mm: Nat) -> Maybe<&2, Nat>:
  match m:
    case None{}:
      None{}
    case Some{+h}:
      Cron.clock.h(Nat.is_eq(h, h0), h, hours, mins, mm)

# the first matching minute of the day at or after minute m0
def Cron.clock(+hours: List<&2, Nat>, +mins: List<&2, Nat>, +m0: Nat) -> Maybe<&2, Nat>:
  Cron.clock.k(Cron.first(hours, Nat.div(m0, 60n)), Nat.div(m0, 60n), hours, mins, Nat.mod(m0, 60n))

def Cron.step.time(m: Maybe<&2, Nat>, +d: Nat) -> CStep:
  match m:
    case None{}:
      CGo{1n+d}
    case Some{+t}:
      CFound{Nat.add(Nat.mul(d, 86400n), Nat.mul(t, 60n))}

def Cron.step.dom(hit: Bool, +hours: List<&2, Nat>, +mins: List<&2, Nat>, +d: Nat, +m0: Nat) -> CStep:
  match hit:
    case True{}:
      Cron.step.time(Cron.clock(hours, mins, m0), d)
    case False{}:
      CGo{1n+d}

# the first day of the next month in the list, this year or the next
def Cron.month.next(m: Maybe<&2, Nat>, +y: Nat, +months: List<&2, Nat>) -> Nat:
  match m:
    case Some{+x}:
      Cron.days(y, x, 1n)
    case None{}:
      Cron.days(1n+y, Cron.head(months), 1n)

def Cron.step.mon(inm: Bool, +c: Cron, +d: Nat, +m0: Nat, +ymd: Ymd) -> CStep:
  match inm c ymd:
    case True{} Cron{+mi, +ho, +dm, _, +dw, +da, +wa} Ymd{_, _, +dd}:
      Cron.step.dom(Cron.day.ok(da, wa, Cron.has(dm, dd), Cron.has(dw, Nat.mod(Nat.add(d, 4n), 7n))), ho, mi, d, m0)
    case False{} Cron{_, _, _, +mo, _, _, _} Ymd{+y, +m, _}:
      CGo{Cron.month.next(Cron.first(mo, 1n+m), y, mo)}

def Cron.step.in(+c: Cron, +ymd: Ymd) -> Bool:
  match c ymd:
    case Cron{_, _, _, +mo, _, _, _} Ymd{_, +m, _}:
      Cron.has(mo, m)

def Cron.step.k(past: Bool, +c: Cron, +d: Nat, +m0: Nat) -> CStep:
  match past:
    case True{}:
      CStop{}
    case False{}:
      Cron.step.mon(Cron.step.in(c, Cron.civil(d)), c, d, m0, Cron.civil(d))

# one day of the search: from minute m0 of day d, up to day end
def Cron.step(+c: Cron, +d: Nat, +m0: Nat, +end: Nat) -> CStep:
  Cron.step.k(Nat.is_gt(d, end), c, d, m0)

# each step moves a day or more, so the fuel outlasts the span
def Cron.scan(fuel: Nat, +c: Cron, st: CStep, +end: Nat) -> Nat:
  match fuel st:
    case 0n _:
      0n
    case 1n+f CFound{t}:
      t
    case 1n+f CStop{}:
      0n
    case 1n+f CGo{+d}:
      Cron.scan(f, c, Cron.step(c, d, 0n, end), end)

# how many days ahead the search looks (nine years: past any leap day)
def Cron.span() -> Nat:
  3300n

def Cron.utc(t: Nat, +off: Nat, +east: Bool) -> Nat:
  match t:
    case 0n:
      0n
    case 1n+k:
      M.Snooze.utc(east, 1n+k, off)

def Cron.raw.at(+loc: Nat, +c: Cron, +off: Nat, +east: Bool) -> Nat:
  +d = Nat.div(loc, 86400n)
  +end = Nat.add(d, Cron.span())
  Cron.utc(Cron.scan(4000n, c, Cron.step(c, d, Nat.div(Nat.mod(loc, 86400n), 60n), end), end), off, east)

# the search's answer, unchecked
def Cron.raw(+c: Cron, +after: Nat, +off: Nat, +east: Bool) -> Nat:
  Cron.raw.at(Nat.add(Nat.mul(Nat.div(M.Snooze.local(east, after, off), 60n), 60n), 60n), c, off, east)

def Cron.guard.k(b: Bool, x: Nat) -> Nat:
  match b:
    case True{}:
      x
    case False{}:
      0n

# x when it is after `after`, else 0
def Cron.guard(+after: Nat, +x: Nat) -> Nat:
  Cron.guard.k(Nat.is_gt(x, after), x)

# the next time (epoch seconds) the schedule matches, strictly after
# `after`, local time being UTC shifted off seconds east (or west); 0: never
def Cron.next(+c: Cron, +after: Nat, +off: Nat, +east: Bool) -> Nat:
  Cron.guard(after, Cron.raw(c, after, off, east))

# 0 (never) or after `after`: what law cron_next_after asks of Cron.next
def Cron.ok(+after: Nat, x: Nat) -> Bool:
  match x:
    case 0n:
      True{}
    case 1n+k:
      Nat.is_gt(1n+k, after)

def Cron.due.x(x: Nat, +now: Nat) -> Bool:
  match x:
    case 0n:
      False{}
    case 1n+k:
      Nat.is_ge(now, 1n+k)

def Cron.due.k(o: Cmp, x: Nat, +now: Nat) -> Bool:
  match o:
    case GT{}:
      Cron.due.x(x, now)
    case EQ{}:
      False{}
    case LT{}:
      False{}

# a routine that last fired (or was made) at `last` is due at `now` when its
# next time after last has come; the caller then records last := now, so a
# long gap gives one catch-up run, never a burst. (now > last is implied by
# next > last; it is tested first so a routine never fires twice at once.)
def Cron.due(+c: Cron, +last: Nat, +now: Nat, +off: Nat, +east: Bool) -> Bool:
  Cron.due.k(Nat.cmp(now, last), Cron.next(c, last, off, east), now)

# Description
# -----------

def Cron.same(xs: List<&2, Nat>, ys: List<&2, Nat>) -> Bool:
  match xs ys:
    case Nil{} Nil{}:
      True{}
    case +x <> xt +y <> yt:
      Bool.and(Nat.is_eq(x, y), Cron.same(xt, yt))
    case _ _:
      False{}

def Cron.gap.k(zero: Bool, b: Nat) -> Nat:
  match zero:
    case True{}:
      b
    case False{}:
      1n

# the step of a list 0, N, 2N...: N (1 when it has another shape)
def Cron.gap(xs: List<&2, Nat>) -> Nat:
  match xs:
    case +a <> +b <> _:
      Cron.gap.k(Nat.is_eq(a, 0n), b)
    case _:
      1n

def Cron.pad2(+n: Nat) -> String:
  Bool.pick(String, Nat.is_lt(n, 10n), "0" ++ Nat.show(n), Nat.show(n))

def Cron.hm(+h: Nat, +m: Nat) -> String:
  Cron.pad2(h) ++ ":" ++ Cron.pad2(m)

def Cron.when(b: Bool, s: String) -> Maybe<&2, String>:
  match b:
    case True{}:
      Some{s}
    case False{}:
      None{}

def Cron.or(a: Maybe<&2, String>, b: Maybe<&2, String>) -> Maybe<&2, String>:
  match a:
    case Some{x}:
      Some{x}
    case None{}:
      b

def Cron.one.of(xs: List<&2, Nat>) -> Bool:
  Nat.is_eq(List.length(&2, Nat, xs), 1n)

def Cron.plural(+n: Nat, +one: String, +many: String) -> String:
  Bool.pick(String, Nat.is_eq(n, 1n), "every " ++ one, "every " ++ Nat.show(n) ++ " " ++ many)

def Cron.hourly(+m: Nat) -> String:
  Bool.pick(String, Nat.is_eq(m, 0n), "hourly", "hourly at :" ++ Cron.pad2(m))

def Cron.describe.c(c: Cron) -> Maybe<&2, String>:
  match c:
    case Cron{+mi, +ho, +dm, +mo, +dw, +da, +wa}:
      +all = Bool.and(Bool.and(da, wa), Nat.is_eq(List.length(&2, Nat, mo), 12n))
      +allh = Nat.is_eq(List.length(&2, Nat, ho), 24n)
      +n = Cron.gap(mi)
      +k = Cron.gap(ho)
      +m = Cron.head(mi)
      +h = Cron.head(ho)
      Cron.or(Cron.when(Bool.and(Bool.and(all, allh), Bool.and(Nat.is_eq(Nat.mod(60n, n), 0n), Cron.same(mi, Cron.vals([CRng{0n, 59n, n}], 0n, 59n)))), Cron.plural(n, "minute", "minutes")),
        Cron.or(Cron.when(Bool.and(Bool.and(all, allh), Cron.one.of(mi)), Cron.hourly(m)),
          Cron.or(Cron.when(Bool.and(Bool.and(all, Cron.same(mi, [0n])), Bool.and(Nat.is_eq(Nat.mod(24n, k), 0n), Cron.same(ho, Cron.vals([CRng{0n, 23n, k}], 0n, 23n)))), Cron.plural(k, "hour", "hours")),
            Cron.or(Cron.when(Bool.and(all, Bool.and(Cron.one.of(mi), Cron.one.of(ho))), "daily at " ++ Cron.hm(h, m)),
              Cron.when(Bool.and(Bool.and(Bool.and(da, Bool.not(wa)), Nat.is_eq(List.length(&2, Nat, mo), 12n)), Bool.and(Cron.same(dw, [1n, 2n, 3n, 4n, 5n]), Bool.and(Cron.one.of(mi), Cron.one.of(ho)))), "weekdays at " ++ Cron.hm(h, m))))))

def Cron.describe.k(m: Maybe<&2, Cron>, +line: String) -> String:
  match m:
    case None{}:
      ""
    case Some{c}:
      Maybe.default(&2, String, Cron.describe.c(c), line)

# short words for a schedule ("every 15 minutes", "daily at 09:30",
# "weekdays at 08:00"), else its cron line; "" when invalid
def Cron.describe(+s: String) -> String:
  Cron.describe.k(Cron.parse(s), Cron.text(s))
