import Base

# The Pebble Index ring's webhook body (docs/bots.md, "Webhooks"): a
# multipart/form-data body with a `transcription` part (the voice note as
# text), `recordedAt`, `client` and, for the app's test button, `test`.
# A part's value is the text between the blank line after its headers and
# the next boundary. Walks are tail calls (bodies run to 256 KB).

type Cut is Data:
  Cut{hit: Bool, rest: String}

def Ring.after.k(here: Bool, +s: String, +pat: String) -> Cut:
  match here:
    case True{}:
      Cut{True{}, String.drop(s, String.length(pat))}
    case False{}:
      Cut{False{}, s}

def Ring.after.go(s: String, +pat: String, c: Cut) -> Cut:
  match s c:
    case _ Cut{True{}, r}:
      Cut{True{}, r}
    case SNil{} Cut{False{}, _}:
      Cut{False{}, SNil{}}
    case SCon{_, +t} Cut{False{}, _}:
      Ring.after.go(t, pat, Ring.after.k(String.starts_with(t, pat), t, pat))

# what follows the first `pat` in s
def Ring.after(+s: String, +pat: String) -> Cut:
  Ring.after.go(s, pat, Ring.after.k(String.starts_with(s, pat), s, pat))

# the text read so far, and whether `pat` has come (the walk goes on to
# the end, a tail call each step, keeping nothing more)
type Us is Data:
  Us{done: Bool, acc: String}

def Ring.until.step(stop: Bool, +c: Char, u: Us) -> Us:
  match stop u:
    case _ Us{True{}, a}:
      Us{True{}, a}
    case True{} Us{False{}, a}:
      Us{True{}, a}
    case False{} Us{False{}, a}:
      Us{False{}, SCon{c, a}}

def Ring.until.go(s: String, +pat: String, u: Us) -> String:
  match s u:
    case SNil{} Us{_, a}:
      String.reverse(a)
    case SCon{+c, +t} _:
      Ring.until.go(t, pat, Ring.until.step(String.starts_with(SCon{c, t}, pat), c, u))

# the text of s up to `pat` (all of it when pat never comes)
def Ring.until(s: String, +pat: String) -> String:
  Ring.until.go(s, pat, Us{False{}, SNil{}})

def Ring.value(c: Cut) -> String:
  match c:
    case Cut{True{}, r}:
      Ring.until(r, "\r\n--")
    case Cut{False{}, _}:
      ""

def Ring.body(c: Cut) -> String:
  match c:
    case Cut{True{}, r}:
      Ring.value(Ring.after(r, "\r\n\r\n"))
    case Cut{False{}, _}:
      ""

# a part's text ("" when the body has no such part)
def Ring.part(+body: String, +name: String) -> String:
  Ring.body(Ring.after(body, "name=\"" ++ name ++ "\""))

# the voice note's words
def Ring.text(+body: String) -> String:
  String.trim(Ring.part(body, "transcription"))

# the app's "Send test event"
def Ring.test(+body: String) -> Bool:
  String.eq(String.trim(Ring.part(body, "test")), "true")
