import Base
import ./check.bend as C
import ../src/core/voice.bend as V
import ../src/core/json.bend as J

def Show.us(us: List<&2, V.Unsure>) -> String:
  match us:
    case Nil{}:
      ""
    case V.Unsure{w, g} <> t:
      w ++ "=" ++ g ++ ";" ++ Show.us(t)

def dict() -> List<&2, String>:
  ["KiCad", "Pebble Index", "Backplane", "STM32"]

def none() -> List<&2, String>:
  Nil{}

# "key cad " n times
def long.go(n: Nat, acc: String) -> String:
  match n:
    case 0n:
      acc
    case 1n+p:
      long.go(p, String.reverse.go(" dac yek", acc))

def long(n: Nat) -> String:
  long.go(n, SNil{})

def ins(+i: V.Ins) -> String:
  V.Ins.text(i) ++ "|" ++ Nat.show(V.Ins.caret(i))

def put(+d: String, +at: Nat, +t: String) -> String:
  ins(V.Voice.put(False{}, d, at, t))

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("parse", V.Voice.dict.show(V.Voice.dict.parse("  KiCad \r\nPebble Index\n\nkicad\nSTM32\n  \nPEBBLE index\r\n")), "KiCad\nPebble Index\nSTM32")
    C.Check.str("parse empty", V.Voice.dict.show(V.Voice.dict.parse("")), "")
    C.Check.str("has any case", Bool.show(V.Voice.dict.has(dict(), "  pebble INDEX ")), "True")
    C.Check.str("has not", Bool.show(V.Voice.dict.has(dict(), "pebble")), "False")
    C.Check.str("add", V.Voice.dict.show(V.Voice.dict.add(dict(), " Bend ")), "KiCad\nPebble Index\nBackplane\nSTM32\nBend")
    C.Check.str("add again", V.Voice.dict.show(V.Voice.dict.add(dict(), "kicad")), "KiCad\nPebble Index\nBackplane\nSTM32")
    C.Check.str("add blank", V.Voice.dict.show(V.Voice.dict.add(dict(), "  ")), "KiCad\nPebble Index\nBackplane\nSTM32")
    C.Check.str("remove", V.Voice.dict.show(V.Voice.dict.remove(dict(), " backplane")), "KiCad\nPebble Index\nSTM32")
    C.Check.str("keywords", Nat.show(List.length(&2, String, V.Voice.keywords(List.replicate(String, 150n, "x")))), "100")
    C.Check.str("keywords few", V.Voice.dict.show(V.Voice.keywords(dict())), "KiCad\nPebble Index\nBackplane\nSTM32")
    C.Check.str("lev", Nat.show(V.Voice.lev("kitten", "sitting")) ++ " " ++ Nat.show(V.Voice.lev("", "abc")) ++ " " ++ Nat.show(V.Voice.lev("abc", "abc")), "3 3 0")
    C.Check.str("near miss", Show.us(V.Voice.unsure(dict(), none(), "open it in Backplain now")), "Backplain=Backplane;")
    C.Check.str("near miss short", Show.us(V.Voice.unsure(["Bend"], none(), "the bond and the band")), "bond=Bend;band=Bend;")
    C.Check.str("two words", Show.us(V.Voice.unsure(dict(), none(), "open the key cad board")), "key cad=KiCad;")
    C.Check.str("two words multi", Show.us(V.Voice.unsure(dict(), none(), "my pebble indexes ring.")), "pebble indexes=Pebble Index;")
    C.Check.str("two words, not across a comma", Show.us(V.Voice.unsure(dict(), none(), "the key, cad")), "")
    C.Check.str("exact pair", Show.us(V.Voice.unsure(dict(), none(), "the Pebble Index ring")), "")
    C.Check.str("technical", Show.us(V.Voice.unsure(dict(), none(), "the stm32f4 has R12, an iPhone, a USB port; OK I will at 5pm on the 2nd")), "stm32f4=;R12=;iPhone=;USB=;")
    C.Check.str("in dict", Show.us(V.Voice.unsure(dict(), none(), "KiCad and kicad and STM32 in Backplane")), "")
    C.Check.str("ignored", Show.us(V.Voice.unsure(dict(), ["key cad", "R12"], "the key cad has R12 and R13")), "R13=;")
    C.Check.str("no repeats", Show.us(V.Voice.unsure(dict(), none(), "R12 r12 R12 Backplain backplain")), "R12=;Backplain=Backplane;")
    C.Check.str("cap 5", Show.us(V.Voice.unsure(dict(), none(), "A1 B2 C3 D4 E5 F6 G7")), "A1=;B2=;C3=;D4=;E5=;")
    C.Check.str("punctuation", Show.us(V.Voice.unsure(dict(), none(), "(Backplain). it's a v1.2-rc thing...")), "Backplain=Backplane;v1.2-rc=;")
    C.Check.str("fix", V.Voice.fix("open key cad now", "key cad", "KiCad"), "open KiCad now")
    C.Check.str("fix whole words", V.Voice.fix("cad cadence, cad. scad cad", "cad", "CAD"), "CAD cadence, CAD. scad CAD")
    C.Check.str("fix case", V.Voice.fix("Cad cad", "cad", "X"), "Cad X")
    C.Check.str("fix same", V.Voice.fix("a b a", "a", "a"), "a b a")
    C.Check.str("fix empty", V.Voice.fix("a b", "", "z"), "a b")
    C.Check.str("fix long", Nat.show(String.length(V.Voice.fix(long(7000n), "key cad", "KiCad"))), "42000")
    C.Check.str("unsure long", Show.us(V.Voice.unsure(dict(), none(), long(7000n) ++ "R12")), "key cad=KiCad;R12=;")
    C.Check.str("json", J.Json.show(V.Voice.unsure.json([V.Unsure{"key cad", "KiCad"}, V.Unsure{"R12", ""}])), "[{\"word\":\"key cad\",\"guess\":\"KiCad\"},{\"word\":\"R12\",\"guess\":\"\"}]")
    C.Check.str("json roundtrip", Show.us(V.Voice.unsure.parse(V.Voice.unsure.json([V.Unsure{"key cad", "KiCad"}, V.Unsure{"R12", ""}]))), "key cad=KiCad;R12=;")
    C.Check.str("json junk", Show.us(V.Voice.unsure.parse(J.Json.arr([J.Str{"x"}, J.Json.obj([J.KV{"word", J.Str{"a"}}])]))), "a=;")
    C.Check.str("note", V.Voice.note([V.Unsure{"key cad", "KiCad"}, V.Unsure{"stm32f4", ""}]), "Possibly misheard: \"key cad\" (KiCad?), \"stm32f4\". Ask if unsure.")
    C.Check.str("note none", V.Voice.note(Nil{}), "")
    C.Check.str("put: into an empty draft", put("", 0n, " Hello there. "), "Hello there.|12")
    C.Check.str("put: after typed text, mid-sentence", put("fix the regulator", 17n, "Hello from voice."), "fix the regulator hello from voice.|35")
    C.Check.str("put: after a sentence", put("Fix it.", 7n, "Then run DRC."), "Fix it. Then run DRC.|21")
    C.Check.str("put: after a question", put("Why? ", 5n, "Because"), "Why? Because|12")
    C.Check.str("put: after a space", put("fix it ", 7n, "Please"), "fix it please|13")
    C.Check.str("put: after a new line", put("fix\n", 4n, "Hello"), "fix\nHello|9")
    C.Check.str("put: at the caret, before a word", put("open board", 5n, "The KiCad."), "open the KiCad board|14")
    C.Check.str("put: before a space and a word", put("fix the regulator", 7n, "Hello from voice."), "fix the hello from voice regulator|24")
    C.Check.str("put: before a new sentence", put("fix it. Then go", 7n, "Now."), "fix it. Now. Then go|12")
    C.Check.str("put: before punctuation", put("open, then", 4n, "The board"), "open the board, then|14")
    C.Check.str("put: I stays", put("so", 2n, "I think."), "so I think.|11")
    C.Check.str("put: I'm stays", put("so", 2n, "I'm in."), "so I'm in.|10")
    C.Check.str("put: it lowers", put("so", 2n, "It works"), "so it works|11")
    C.Check.str("put: acronym stays", put("check", 5n, "USB power"), "check USB power|15")
    C.Check.str("put: camel case stays", put("open", 4n, "KiCad"), "open KiCad|10")
    C.Check.str("put: a dictionary term stays", ins(V.Voice.put(True{}, "open", 4n, "Backplane now")), "open Backplane now|18")
    C.Check.str("put: blank leaves the draft", put("abc", 1n, "  "), "abc|1")
    C.Check.str("put: past the end is the end", put("abc", 99n, "Go"), "abc go|6")
    C.Check.str("put: after a bracket", put("see (", 5n, "Figure one"), "see (figure one|15")
    C.Check.str("put: an ellipsis stays", put("wait for it", 5n, "Well..."), "wait well... for it|12")
    C.Check.str("firm: a term", Bool.show(V.Voice.firm(dict(), " kicad board")), "True")
    C.Check.str("firm: two words", Bool.show(V.Voice.firm(dict(), "Pebble Index ring")), "True")
    C.Check.str("firm: not", Bool.show(V.Voice.firm(dict(), "Open it")), "False")
