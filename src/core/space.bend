import Base
import ./json.bend as J

# A bot's space: the UI it writes for itself (docs/bots.md, "Space"), as
# blocks. Parsing keeps what it understands, skips unknown blocks and caps
# every size, so a spec can never make a client do much work. The spec is
# data, never code: a button only sends the bot a message.

# a key/value row
type Cell is Data:
  Cell{key: String, val: String}

type Block is Data:
  BHeading{text: String}
  BText{text: String}
  BStat{label: String, value: String, hint: String}
  BProgress{label: String, permille: Nat}
  BList{items: List<&2, String>}
  BKv{rows: List<&2, Cell>}
  BTable{head: List<&2, String>, rows: List<&2, List<&2, String>>}
  BButton{label: String, action: String}
  BInput{label: String, action: String, placeholder: String}
  BDivider{}
  BBadge{text: String, tone: String}
  BCode{text: String}
  BRow{blocks: List<&2, Block>}

type Space is Data:
  Space{title: String, blocks: List<&2, Block>}

# Caps
# ----

def Space.max_blocks() -> Nat:
  200n

def Space.max_text() -> Nat:
  U32.to_nat(2000)

def Space.max_rows() -> Nat:
  200n

def Space.max_cols() -> Nat:
  8n

def Space.max_kids() -> Nat:
  6n

def Space.max_action() -> Nat:
  200n

def Space.blocks(sp: Space) -> List<&2, Block>:
  match sp:
    case Space{_, bs}:
      bs

def Space.title(sp: Space) -> String:
  match sp:
    case Space{t, _}:
      t

def Space.count(sp: Space) -> Nat:
  List.length(&2, Block, Space.blocks(sp))

# Reading values
# --------------

# a scalar as text: strings as they are, numbers as written, flags as words
def Sp.text.of(m: Maybe<&2, J.Json>) -> String:
  match m:
    case Some{J.Str{s}}:
      s
    case Some{J.Num{r}}:
      r
    case Some{J.Flag{True{}}}:
      "true"
    case Some{J.Flag{False{}}}:
      "false"
    case _:
      ""

def Sp.scalar(j: J.Json) -> String:
  String.take(Sp.text.of(Some{j}), Space.max_text())

# the text at key, capped
def Sp.str(o: J.Json, +key: String) -> String:
  String.take(Sp.text.of(J.Json.get(o, key)), Space.max_text())

def Sp.act(o: J.Json, +key: String) -> String:
  String.take(Sp.text.of(J.Json.get(o, key)), Space.max_action())

# a list of scalars, at most n
def Sp.strs.go(xs: List<&2, J.Json>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case h <> t:
      Sp.scalar(h) <> Sp.strs.go(t)

def Sp.strs(a: J.Json, n: Nat) -> List<&2, String>:
  Sp.strs.go(List.take(&2, J.Json, J.Json.elems(a), n))

# Progress
# --------

# at most 1000
def Space.clamp(+p: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_le(p, 1000n), p, 1000n)

def Sp.nat(+s: String) -> Nat:
  Maybe.default(&2, Nat, Nat.read(s), 0n)

# the fraction digits of a decimal as thousandths ("4" -> 400, "125" -> 125)
def Sp.thou(+f: String) -> Nat:
  Sp.nat(String.take(f ++ "000", 3n))

def Sp.milli.parts(ps: List<&2, String>) -> Nat:
  match ps:
    case Nil{}:
      0n
    case +i <> Nil{}:
      Nat.mul(Sp.nat(i), 1000n)
    case +i <> +f <> _:
      Nat.add(Nat.mul(Sp.nat(i), 1000n), Sp.thou(f))

# a non-negative decimal times 1000 ("0.4" -> 400, "40" -> 40000); a
# negative or unreadable one is 0
def Sp.milli.k(neg: Bool, +s: String) -> Nat:
  match neg:
    case True{}:
      0n
    case False{}:
      Sp.milli.parts(String.split(s, '.'))

def Sp.milli(+s: String) -> Nat:
  Sp.milli.k(String.starts_with(s, "-"), s)

# plain numbers up to 1 are fractions, larger ones percentages
def Sp.permille.plain(small: Bool, +m: Nat) -> Nat:
  match small:
    case True{}:
      m
    case False{}:
      Nat.div(m, 100n)

def Sp.permille.k(pct: Bool, +s: String) -> Nat:
  match pct:
    case True{}:
      Nat.div(Sp.milli(String.trim(String.take(s, Nat.sub(String.length(s), 1n)))), 100n)
    case False{}:
      Sp.permille.plain(Nat.is_le(Sp.milli(s), 1000n), Sp.milli(s))

# a progress value, 0..1000: 0..1 (0.4), or a percentage ("40%", or 40)
def Space.permille(+s: String) -> Nat:
  +t = String.trim(s)
  Space.clamp(Sp.permille.k(String.ends_with(t, "%"), t))

# 400 -> "0.400"
def Sp.pad3(+n: Nat) -> String:
  String.reverse(String.take(String.reverse("00" ++ Nat.show(n)), 3n))

def Space.fraction(+p: Nat) -> String:
  Nat.show(Nat.div(p, 1000n)) ++ "." ++ Sp.pad3(Nat.mod(p, 1000n))

def Sp.pct.k(whole: Bool, +p: Nat) -> String:
  match whole:
    case True{}:
      Nat.show(Nat.div(p, 10n)) ++ "%"
    case False{}:
      Nat.show(Nat.div(p, 10n)) ++ "." ++ Nat.show(Nat.mod(p, 10n)) ++ "%"

# how a progress value reads: 400 -> "40%", 125 -> "12.5%"
def Space.pct(+p: Nat) -> String:
  Sp.pct.k(Nat.is_eq(Nat.mod(p, 10n), 0n), p)

# Blocks
# ------

def Sp.kinds() -> List<&2, String>:
  ["heading", "text", "stat", "progress", "list", "kv", "table", "button", "input", "divider", "badge", "code", "row"]

def Sp.index.hit(names: List<&2, String>, +s: String) -> Bool:
  match names:
    case n <> _:
      String.eq(n, s)
    case Nil{}:
      False{}

def Sp.index.go(names: List<&2, String>, hit: Bool, +i: Nat, +s: String) -> Nat:
  match names hit:
    case _ <> _ True{}:
      i
    case _ <> +t False{}:
      Sp.index.go(t, Sp.index.hit(t, s), 1n+i, s)
    case Nil{} _:
      i

# a block type's number (13 when unknown)
def Sp.kind(+s: String) -> Nat:
  Sp.index.go(Sp.kinds(), Sp.index.hit(Sp.kinds(), s), 0n, s)

# a kv row: ["k", "v"] or {"key"|"label": .., "value": ..}
def Sp.cell.arr(xs: List<&2, J.Json>) -> Cell:
  match xs:
    case Nil{}:
      Cell{"", ""}
    case k <> Nil{}:
      Cell{Sp.scalar(k), ""}
    case k <> v <> _:
      Cell{Sp.scalar(k), Sp.scalar(v)}

def Sp.cell.named(+k: String, +o: J.Json) -> Cell:
  Cell{String.take(Bool.pick(String, String.is_empty(k), Sp.text.of(J.Json.get(o, "label")), k), Space.max_text()), Sp.str(o, "value")}

def Sp.cell(+j: J.Json) -> Cell:
  match j:
    case J.Arr{xs}:
      Sp.cell.arr(J.Json.to_list(xs))
    case _:
      Sp.cell.named(Sp.text.of(J.Json.get(j, "key")), j)

def Sp.cells(xs: List<&2, J.Json>) -> List<&2, Cell>:
  match xs:
    case Nil{}:
      Nil{}
    case +h <> t:
      Sp.cell(h) <> Sp.cells(t)

def Sp.trows(xs: List<&2, J.Json>) -> List<&2, List<&2, String>>:
  match xs:
    case Nil{}:
      Nil{}
    case h <> t:
      Sp.strs(h, Space.max_cols()) <> Sp.trows(t)

def Sp.rows(+o: J.Json) -> List<&2, J.Json>:
  List.take(&2, J.Json, J.Json.elems(J.Json.get_obj(o, "rows")), Space.max_rows())

# a button needs a label or an action; either stands in for the other
def Sp.button.k(le: Bool, ae: Bool, +l: String, +a: String) -> Maybe<&2, Block>:
  match le ae:
    case True{} True{}:
      None{}
    case True{} False{}:
      Some{BButton{a, a}}
    case False{} True{}:
      Some{BButton{l, String.take(l, Space.max_action())}}
    case False{} False{}:
      Some{BButton{l, a}}

def Sp.button(+l: String, +a: String) -> Maybe<&2, Block>:
  Sp.button.k(String.is_empty(l), String.is_empty(a), l, a)

def Sp.input.k(ae: Bool, +l: String, +a: String, +p: String) -> Maybe<&2, Block>:
  match ae:
    case True{}:
      None{}
    case False{}:
      Some{BInput{l, a, p}}

def Sp.tone.k(ok: Bool, warn: Bool, bad: Bool) -> String:
  match ok warn bad:
    case True{} _ _:
      "ok"
    case _ True{} _:
      "warn"
    case _ _ True{}:
      "bad"
    case _ _ _:
      ""

# a badge's tone: ok, warn, bad, or none
def Space.tone(+t: String) -> String:
  Sp.tone.k(String.eq(t, "ok"), String.eq(t, "warn"), String.eq(t, "bad"))

# a block other than a row, or None (unknown type, or a row)
def Sp.leaf.k(k: Nat, +o: J.Json) -> Maybe<&2, Block>:
  match k:
    case 0n:
      Some{BHeading{Sp.str(o, "text")}}
    case 1n:
      Some{BText{Sp.str(o, "text")}}
    case 2n:
      Some{BStat{Sp.str(o, "label"), Sp.str(o, "value"), Sp.str(o, "hint")}}
    case 3n:
      Some{BProgress{Sp.str(o, "label"), Space.permille(Sp.text.of(J.Json.get(o, "value")))}}
    case 4n:
      Some{BList{Sp.strs(J.Json.get_obj(o, "items"), Space.max_rows())}}
    case 5n:
      Some{BKv{Sp.cells(Sp.rows(o))}}
    case 6n:
      Some{BTable{Sp.strs(J.Json.get_obj(o, "head"), Space.max_cols()), Sp.trows(Sp.rows(o))}}
    case 7n:
      Sp.button(Sp.str(o, "label"), Sp.act(o, "action"))
    case 8n:
      Sp.input.k(String.is_empty(Sp.act(o, "action")), Sp.str(o, "label"), Sp.act(o, "action"), Sp.str(o, "placeholder"))
    case 9n:
      Some{BDivider{}}
    case 10n:
      Some{BBadge{Sp.str(o, "text"), Space.tone(Sp.str(o, "tone"))}}
    case 11n:
      Some{BCode{Sp.str(o, "text")}}
    case _:
      None{}

def Sp.leaf(+o: J.Json) -> Maybe<&2, Block>:
  Sp.leaf.k(Sp.kind(J.Json.get_str(o, "type", "")), o)

def Sp.put(m: Maybe<&2, Block>, rest: List<&2, Block>) -> List<&2, Block>:
  match m:
    case Some{b}:
      b <> rest
    case None{}:
      rest

def Sp.leaves(xs: List<&2, J.Json>) -> List<&2, Block>:
  match xs:
    case Nil{}:
      Nil{}
    case +h <> t:
      Sp.put(Sp.leaf(h), Sp.leaves(t))

# a row holds up to 6 blocks, none of them rows; an empty row is dropped
def Sp.row.k(kids: List<&2, Block>) -> Maybe<&2, Block>:
  match kids:
    case Nil{}:
      None{}
    case h <> t:
      Some{BRow{h <> t}}

def Sp.row(+o: J.Json) -> Maybe<&2, Block>:
  Sp.row.k(List.take(&2, Block, Sp.leaves(List.take(&2, J.Json, J.Json.elems(J.Json.get_obj(o, "blocks")), Space.max_rows())), Space.max_kids()))

def Sp.block.k(row: Bool, +o: J.Json) -> Maybe<&2, Block>:
  match row:
    case True{}:
      Sp.row(o)
    case False{}:
      Sp.leaf(o)

def Sp.block(+o: J.Json) -> Maybe<&2, Block>:
  Sp.block.k(String.eq(J.Json.get_str(o, "type", ""), "row"), o)

def Sp.all.go(xs: List<&2, J.Json>) -> List<&2, Block>:
  match xs:
    case Nil{}:
      Nil{}
    case +h <> t:
      Sp.put(Sp.block(h), Sp.all.go(t))

# every block of a spec that parses, looking at no more than 400 entries
def Sp.all(+j: J.Json) -> List<&2, Block>:
  Sp.all.go(List.take(&2, J.Json, J.Json.elems(J.Json.get_obj(j, "blocks")), 400n))

# a spec as a space: at most 200 blocks (law space_caps)
def Space.parse(+j: J.Json) -> Space:
  Space{String.take(Sp.str(j, "title"), 200n), List.take(&2, Block, Sp.all(j), Space.max_blocks())}

def Space.unread() -> Space:
  Space{"", [BText{"The space spec could not be read: it is not valid JSON."}]}

def Sp.read.k(m: Maybe<&2, J.Json>) -> Space:
  match m:
    case Some{+j}:
      Space.parse(j)
    case None{}:
      Space.unread()

# a spec's JSON text as a space
def Space.read(s: String) -> Space:
  Sp.read.k(J.Json.parse(s))

# what a bot without a space shows
def Space.empty(+name: String) -> Space:
  Space{name, [BText{name ++ " hasn't built a space yet."},
    BText{"Ask it to make one: a dashboard of what it watches, a checklist, buttons for what you ask it often."}]}

def Sp.msg.k(none: Bool, +action: String, +value: String) -> String:
  match none:
    case True{}:
      action
    case False{}:
      action ++ ": " ++ value

# what a button (no value) or an input sends the bot (law space_message_prefix)
def Space.message(+action: String, +value: String) -> String:
  "[space] " ++ Sp.msg.k(String.is_empty(value), action, value)

# Writing
# -------

def Sp.o(+t: String, kvs: List<&2, J.KV>) -> J.Json:
  J.Json.obj(J.KV{"type", J.Json.str(t)} <> kvs)

def Sp.jstrs(xs: List<&2, String>) -> List<&2, J.Json>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      J.Json.str(x) <> Sp.jstrs(t)

def Sp.jarr(xs: List<&2, String>) -> J.Json:
  J.Json.arr(Sp.jstrs(xs))

def Sp.jcells(cs: List<&2, Cell>) -> List<&2, J.Json>:
  match cs:
    case Nil{}:
      Nil{}
    case Cell{k, v} <> t:
      J.Json.arr([J.Json.str(k), J.Json.str(v)]) <> Sp.jcells(t)

def Sp.jrows(rs: List<&2, List<&2, String>>) -> List<&2, J.Json>:
  match rs:
    case Nil{}:
      Nil{}
    case r <> t:
      Sp.jarr(r) <> Sp.jrows(t)

def Sp.leaf.json(b: Block) -> J.Json:
  match b:
    case BHeading{s}:
      Sp.o("heading", [J.KV{"text", J.Json.str(s)}])
    case BText{s}:
      Sp.o("text", [J.KV{"text", J.Json.str(s)}])
    case BStat{l, v, h}:
      Sp.o("stat", [J.KV{"label", J.Json.str(l)}, J.KV{"value", J.Json.str(v)}, J.KV{"hint", J.Json.str(h)}])
    case BProgress{l, +p}:
      Sp.o("progress", [J.KV{"label", J.Json.str(l)}, J.KV{"value", J.Num{Space.fraction(p)}},
        J.KV{"permille", J.Json.nat(p)}, J.KV{"pct", J.Json.str(Space.pct(p))}])
    case BList{xs}:
      Sp.o("list", [J.KV{"items", Sp.jarr(xs)}])
    case BKv{rs}:
      Sp.o("kv", [J.KV{"rows", J.Json.arr(Sp.jcells(rs))}])
    case BTable{h, rs}:
      Sp.o("table", [J.KV{"head", Sp.jarr(h)}, J.KV{"rows", J.Json.arr(Sp.jrows(rs))}])
    case BButton{l, a}:
      Sp.o("button", [J.KV{"label", J.Json.str(l)}, J.KV{"action", J.Json.str(a)}])
    case BInput{l, a, p}:
      Sp.o("input", [J.KV{"label", J.Json.str(l)}, J.KV{"action", J.Json.str(a)}, J.KV{"placeholder", J.Json.str(p)}])
    case BDivider{}:
      Sp.o("divider", Nil{})
    case BBadge{s, t}:
      Sp.o("badge", [J.KV{"text", J.Json.str(s)}, J.KV{"tone", J.Json.str(t)}])
    case BCode{s}:
      Sp.o("code", [J.KV{"text", J.Json.str(s)}])
    case BRow{_}:
      J.Null{}

def Sp.leaves.json(bs: List<&2, Block>) -> List<&2, J.Json>:
  match bs:
    case Nil{}:
      Nil{}
    case b <> t:
      Sp.leaf.json(b) <> Sp.leaves.json(t)

def Sp.block.json(b: Block) -> J.Json:
  match b:
    case BRow{kids}:
      Sp.o("row", [J.KV{"blocks", J.Json.arr(Sp.leaves.json(kids))}])
    case _:
      Sp.leaf.json(b)

def Sp.blocks.json(bs: List<&2, Block>) -> List<&2, J.Json>:
  match bs:
    case Nil{}:
      Nil{}
    case b <> t:
      Sp.block.json(b) <> Sp.blocks.json(t)

# the normalized spec clients and phones draw; Space.parse reads it back
# to the same space
def Space.json(sp: Space) -> J.Json:
  match sp:
    case Space{t, bs}:
      J.Json.obj([J.KV{"title", J.Json.str(t)}, J.KV{"blocks", J.Json.arr(Sp.blocks.json(bs))}])

def Space.show(sp: Space) -> String:
  J.Json.show(Space.json(sp))
