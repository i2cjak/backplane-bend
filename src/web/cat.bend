import Base
import ./dom.bend as D
import ../core/cat.bend as C

# A bot's cat on the web: an <img> showing core/cat.bend's animated SVG
# (SMIL) as a data URI (host.js makes only svg/path elements, and an <img>
# animates off the main thread). A cat's SVG is ~13 KB, so the view names
# it by data-cat="<look>:<mood>:<px>" and host.js asks app.bend's `cat`
# once per name, keeping the answer; the node is keyed so the patch leaves
# it alone while its look and mood stay the same.

# how many looks the settings offer
def WCat.looks() -> Nat:
  C.Cat.looks()

def WCat.name(+look: Nat, +mood: String, +px: U32) -> String:
  Nat.show(C.Cat.look.index(look)) ++ ":" ++ mood ++ ":" ++ U32.show(px)

# the cat, px square
def WCat.img(+look: Nat, +mood: String, +px: U32) -> D.Node:
  D.El{"img", "cat:" ++ WCat.name(look, mood, px), [D.At{"class", "cat " ++ mood}, D.At{"data-cat", WCat.name(look, mood, px)},
    D.At{"width", U32.show(px)}, D.At{"height", U32.show(px)}, D.At{"alt", ""}, D.At{"draggable", "false"}], Nil{}}

def WCat.uri.k(ps: List<&2, String>) -> String:
  match ps:
    case l <> m <> p <> _:
      C.Cat.data_uri(Maybe.default(&2, Nat, Nat.read(l), 0n), m, U32.from_nat(Maybe.default(&2, Nat, Nat.read(p), 28n)))
    case _:
      ""

# the data URI a data-cat name stands for
def WCat.uri(s: String) -> String:
  WCat.uri.k(String.split(s, ':'))
