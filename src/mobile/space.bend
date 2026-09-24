import Base
import ../core/json.bend as J
import ../core/space.bend as SP

# A bot's space for the phones: Space.json, plus the bot's name and, on
# each button and input, the value it sends ("send"), so the apps only
# pass it on: a button sends ("space", send), an input sends
# ("space-input", send + "\x1f" + text), the same values the web sends.

def MSpace.sep() -> String:
  SCon{Chr{31}, SNil{}}

# an object with one more field in front
def MSpace.with(j: J.Json, +send: String) -> J.Json:
  match j:
    case J.Obj{fs}:
      J.Obj{J.Field{"send", J.Str{send}, fs}}
    case _:
      j

def MSpace.leaf(b: SP.Block, +bot: String) -> J.Json:
  match b:
    case SP.BButton{l, +a}:
      MSpace.with(SP.Sp.leaf.json(SP.BButton{l, a}), bot ++ MSpace.sep() ++ a)
    case SP.BInput{l, +a, p}:
      MSpace.with(SP.Sp.leaf.json(SP.BInput{l, a, p}), bot ++ MSpace.sep() ++ a)
    case _:
      SP.Sp.leaf.json(b)

def MSpace.leaves(bs: List<&2, SP.Block>, +bot: String) -> List<&2, J.Json>:
  match bs:
    case Nil{}:
      Nil{}
    case b <> t:
      MSpace.leaf(b, bot) <> MSpace.leaves(t, bot)

def MSpace.block(b: SP.Block, +bot: String) -> J.Json:
  match b:
    case SP.BRow{kids}:
      J.Json.obj([J.KV{"type", J.Json.str("row")}, J.KV{"blocks", J.Json.arr(MSpace.leaves(kids, bot))}])
    case _:
      MSpace.leaf(b, bot)

def MSpace.blocks(bs: List<&2, SP.Block>, +bot: String) -> List<&2, J.Json>:
  match bs:
    case Nil{}:
      Nil{}
    case b <> t:
      MSpace.block(b, bot) <> MSpace.blocks(t, bot)

# the space the phone draws for bot
def MSpace.json(sp: SP.Space, +bot: String) -> J.Json:
  match sp:
    case SP.Space{t, bs}:
      J.Json.obj([J.KV{"bot", J.Json.str(bot)}, J.KV{"title", J.Json.str(t)}, J.KV{"blocks", J.Json.arr(MSpace.blocks(bs, bot))}])
