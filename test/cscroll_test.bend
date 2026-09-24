import Base
import ./check.bend as C
import ../src/app/nui.bend as N

# The window's composer: how many lines it shows for a draft, which line
# comes first (the caret's, or the wheel's choice), and a wheel notch.

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("empty shows two", Nat.show(N.Cs.rows(0n)), "2")
    C.Check.str("grows with the draft", Nat.show(N.Cs.rows(5n)), "5")
    C.Check.str("stops at most", Nat.show(N.Cs.rows(40n)), "8")
    C.Check.str("short draft never scrolls", Nat.show(N.Cs.top("", 5n, 4n)), "0")
    C.Check.str("caret at start shows the start", Nat.show(N.Cs.top("", 20n, 0n)), "0")
    C.Check.str("caret at the end shows the end", Nat.show(N.Cs.top("", 20n, 19n)), "12")
    C.Check.str("caret mid-way is the last line shown", Nat.show(N.Cs.top("", 20n, 10n)), "3")
    C.Check.str("wheel choice holds", Nat.show(N.Cs.top("5", 20n, 19n)), "5")
    C.Check.str("wheel choice clamps", Nat.show(N.Cs.top("30", 20n, 0n)), "12")
    C.Check.str("wheel up", Nat.show(N.Cs.wheel(True{}, 5n, 12n)), "2")
    C.Check.str("wheel up stops at 0", Nat.show(N.Cs.wheel(True{}, 1n, 12n)), "0")
    C.Check.str("wheel down", Nat.show(N.Cs.wheel(False{}, 5n, 12n)), "8")
    C.Check.str("wheel down stops at max", Nat.show(N.Cs.wheel(False{}, 11n, 12n)), "12")
