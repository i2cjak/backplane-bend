import Base

# Release versions: "v1.2.3" or "1.2.3", an optional "-pre" suffix. The
# updater installs a release only when it is newer than the running one
# (laws update_never_same, semver_cmp_refl).

type Ver is Data:
  Ver{major: Nat, minor: Nat, patch: Nat, pre: Bool}

def Ver.num(+s: String) -> Nat:
  Maybe.default(&2, Nat, Nat.read(s), 0n)

def Ver.core(parts: List<&2, String>, +pre: Bool) -> Ver:
  match parts:
    case a <> b <> c <> _:
      Ver{Ver.num(a), Ver.num(b), Ver.num(c), pre}
    case a <> b <> Nil{}:
      Ver{Ver.num(a), Ver.num(b), 0n, pre}
    case a <> Nil{}:
      Ver{Ver.num(a), 0n, 0n, pre}
    case Nil{}:
      Ver{0n, 0n, 0n, pre}

def Ver.split(parts: List<&2, String>) -> Ver:
  match parts:
    case main <> Nil{}:
      Ver.core(String.split(main, '.'), False{})
    case main <> _ <> _:
      Ver.core(String.split(main, '.'), True{})
    case Nil{}:
      Ver{0n, 0n, 0n, False{}}

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
    case Ver{a1, a2, a3, ap} Ver{b1, b2, b3, bp}:
      Ver.then(Nat.cmp(a1, b1), Ver.then(Nat.cmp(a2, b2), Ver.then(Nat.cmp(a3, b3), Ver.pre_cmp(ap, bp))))

# whether `latest` should replace `current`
def Ver.newer(+latest: Ver, +current: Ver) -> Bool:
  Cmp.is_gt(Ver.cmp(latest, current))
