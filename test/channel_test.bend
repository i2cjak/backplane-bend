import Base
import ./check.bend as C
import ../src/core/semver.bend as SV

def yes(b: Bool) -> String:
  match b:
    case True{}:
      "yes"
    case False{}:
      "no"

# GitHub lists releases newest first by date, which need not be version order
def rels() -> List<&2, SV.Rel>:
  [SV.Rel{"v0.4.1-nightly.20260923.2", True{}},
   SV.Rel{"v0.4.1-nightly.20260923.1", True{}},
   SV.Rel{"v0.4.0", False{}},
   SV.Rel{"v0.4.1-nightly.20260922.7", True{}},
   SV.Rel{"v0.4.0-rc.1", True{}},
   SV.Rel{"v0.3.9", False{}}]

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("stable", SV.Chan.pick("stable", rels()), "v0.4.0")
    C.Check.str("nightly", SV.Chan.pick("nightly", rels()), "v0.4.1-nightly.20260923.2")
    C.Check.str("nightly after release", SV.Chan.pick("nightly", SV.Rel{"v0.4.1", False{}} <> rels()), "v0.4.1")
    C.Check.str("nightly skips rc", SV.Chan.pick("nightly", [SV.Rel{"v0.5.0-rc.1", True{}}, SV.Rel{"v0.4.0", False{}}]), "v0.4.0")
    C.Check.str("stable skips a pre tag not flagged", SV.Chan.pick("stable", [SV.Rel{"v0.5.0-nightly.20260101.1", False{}}, SV.Rel{"v0.4.0", False{}}]), "v0.4.0")
    C.Check.str("none", SV.Chan.pick("stable", [SV.Rel{"v0.5.0-rc.1", True{}}]), "")
    C.Check.str("empty", SV.Chan.pick("nightly", []), "")
    C.Check.str("of", SV.Chan.of("weird"), "stable")
    C.Check.str("newer day", yes(SV.Ver.newer(SV.Ver.parse("v0.4.1-nightly.20260924.1"), SV.Ver.parse("v0.4.1-nightly.20260923.9"))), "yes")
    C.Check.str("newer build", yes(SV.Ver.newer(SV.Ver.parse("v0.4.1-nightly.20260923.10"), SV.Ver.parse("v0.4.1-nightly.20260923.9"))), "yes")
    C.Check.str("release after nightly", yes(SV.Ver.newer(SV.Ver.parse("v0.4.1"), SV.Ver.parse("v0.4.1-nightly.20260923.9"))), "yes")
    C.Check.str("nightly after last release", yes(SV.Ver.newer(SV.Ver.parse("v0.4.1-nightly.20260923.1"), SV.Ver.parse("v0.4.0"))), "yes")
    C.Check.str("same", yes(SV.Ver.newer(SV.Ver.parse("v0.4.1-nightly.20260923.1"), SV.Ver.parse("0.4.1-nightly.20260923.1"))), "no")
    C.Check.str("older", yes(SV.Ver.newer(SV.Ver.parse("v0.3.9"), SV.Ver.parse("v0.4.0"))), "no")
