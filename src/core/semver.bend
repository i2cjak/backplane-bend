import Base

# Release versions: "v1.2.3" or "1.2.3", an optional "-pre" suffix. The
# updater installs a release only when it is newer than the running one
# (laws update_never_same, semver_cmp_refl). A prerelease sorts before its
# release (semver_pre_before_release); prereleases of one version sort by
# their first two numbers, so "-nightly.20260923.2" follows
# "-nightly.20260923.1" and precedes "-nightly.20260924.1"
# (semver_nightly_later, semver_nightly_next_day).

type Ver is Data:
  Ver{major: Nat, minor: Nat, patch: Nat, pre: Bool, pd: Nat, pn: Nat}

def Ver.num(+s: String) -> Nat:
  Maybe.default(&2, Nat, Nat.read(s), 0n)

# the numeric identifiers of a prerelease ("nightly.20260923.1" -> [20260923, 1])
def Ver.nums.k(m: Maybe<&2, Nat>, rest: List<&2, Nat>) -> List<&2, Nat>:
  match m:
    case Some{n}:
      n <> rest
    case None{}:
      rest

def Ver.nums(ids: List<&2, String>) -> List<&2, Nat>:
  match ids:
    case Nil{}:
      Nil{}
    case +i <> t:
      Ver.nums.k(Nat.read(i), Ver.nums(t))

def Ver.at(ns: List<&2, Nat>, i: Nat) -> Nat:
  match ns i:
    case n <> _ 0n:
      n
    case _ <> t 1n+j:
      Ver.at(t, j)
    case Nil{} _:
      0n

def Ver.core(parts: List<&2, String>, +pre: Bool, +ns: List<&2, Nat>) -> Ver:
  match parts:
    case a <> b <> c <> _:
      Ver{Ver.num(a), Ver.num(b), Ver.num(c), pre, Ver.at(ns, 0n), Ver.at(ns, 1n)}
    case a <> b <> Nil{}:
      Ver{Ver.num(a), Ver.num(b), 0n, pre, Ver.at(ns, 0n), Ver.at(ns, 1n)}
    case a <> Nil{}:
      Ver{Ver.num(a), 0n, 0n, pre, Ver.at(ns, 0n), Ver.at(ns, 1n)}
    case Nil{}:
      Ver{0n, 0n, 0n, pre, Ver.at(ns, 0n), Ver.at(ns, 1n)}

def Ver.split(parts: List<&2, String>) -> Ver:
  match parts:
    case main <> Nil{}:
      Ver.core(String.split(main, '.'), False{}, Nil{})
    case main <> +p <> +t:
      Ver.core(String.split(main, '.'), True{}, Ver.nums(String.split(String.join(p <> t, "-"), '.')))
    case Nil{}:
      Ver{0n, 0n, 0n, False{}, 0n, 0n}

def Ver.strip(+s: String) -> String:
  Bool.pick(String, String.starts_with(s, "v"), String.drop(s, 1n), s)

def Ver.parse(+s: String) -> Ver:
  Ver.split(String.split(Ver.strip(String.trim(s)), '-'))

# a prerelease sorts before its release
def Ver.pre_cmp(a: Bool, b: Bool) -> Cmp:
  match a b:
    case True{} False{}:
      LT{}
    case False{} True{}:
      GT{}
    case _ _:
      EQ{}

def Ver.then(c: Cmp, rest: Cmp) -> Cmp:
  match c:
    case EQ{}:
      rest
    case _:
      c

def Ver.cmp(a: Ver, b: Ver) -> Cmp:
  match a b:
    case Ver{a1, a2, a3, ap, ad, an} Ver{b1, b2, b3, bp, bd, bn}:
      Ver.then(Nat.cmp(a1, b1), Ver.then(Nat.cmp(a2, b2), Ver.then(Nat.cmp(a3, b3),
        Ver.then(Ver.pre_cmp(ap, bp), Ver.then(Nat.cmp(ad, bd), Nat.cmp(an, bn))))))

# whether `latest` should replace `current`
def Ver.newer(+latest: Ver, +current: Ver) -> Bool:
  Cmp.is_gt(Ver.cmp(latest, current))

def Ver.is_pre(v: Ver) -> Bool:
  match v:
    case Ver{_, _, _, p, _, _}:
      p

# Update channels
# ---------------
# `stable` takes only full releases; `nightly` also takes the prereleases
# the nightly workflow publishes (tags like v0.3.1-nightly.20260923.1). Each
# takes the newest by version, whatever order GitHub lists them in.

type Rel is Data:
  Rel{tag: String, pre: Bool}

def Chan.nightly(+tag: String) -> Bool:
  String.contains(tag, "-nightly.")

# whether a channel takes a release
def Chan.wants(+channel: String, r: Rel) -> Bool:
  match r:
    case Rel{+tag, +pre}:
      Bool.or(Bool.and(Bool.not(pre), Bool.not(Ver.is_pre(Ver.parse(tag)))),
        Bool.and(String.eq(channel, "nightly"), Chan.nightly(tag)))

def Chan.tag(r: Rel) -> String:
  match r:
    case Rel{t, _}:
      t

def Chan.keep(take: Bool, +tag: String, +best: String) -> String:
  match take:
    case True{}:
      tag
    case False{}:
      best

# the newest release a channel takes ("" when none)
def Chan.best(rs: List<&2, Rel>, +channel: String, +best: String) -> String:
  match rs:
    case Nil{}:
      best
    case +r <> t:
      Chan.best(t, channel, Chan.keep(Bool.and(Chan.wants(channel, r),
        Bool.or(String.is_empty(best), Ver.newer(Ver.parse(Chan.tag(r)), Ver.parse(best)))), Chan.tag(r), best))

def Chan.pick(+channel: String, rs: List<&2, Rel>) -> String:
  Chan.best(rs, channel, "")

# the channel a setting names (anything else is stable)
def Chan.of(+s: String) -> String:
  Bool.pick(String, String.eq(s, "nightly"), "nightly", "stable")
