import Base

# Links in a thread. A web address (http:// or https://) in a message, bare
# or as a markdown link `[label](url)`, is a link both clients draw and open
# (the web in a new tab, the window with the system's opener). What counts
# as a link, and where it ends, is decided here, once, for both.

type Piece is Data:
  PText{text: String}
  PLink{label: String, url: String}

# only web addresses open (never javascript:, file:, ...)
def Link.is_web(+s: String) -> Bool:
  Bool.or(String.starts_with(s, "http://"), String.starts_with(s, "https://"))

# a web address with something after the scheme
def Link.valid(+s: String) -> Bool:
  Bool.and(Link.is_web(s), Bool.not(Bool.or(String.eq(s, "http://"), String.eq(s, "https://"))))

def Link.code(c: Char) -> U32:
  match c:
    case Chr{u}:
      u

# Scanning
# --------
# One pass over the text, char by char. Text so far is kept reversed (acc),
# as is the address or label being read.

type Scan is Data:
  SText{acc: String}
  SUrl{acc: String, u: String}
  SLab{acc: String, l: String}
  SMid{acc: String, l: String}
  SHref{acc: String, l: String, u: String}

type Sc is Data:
  Sc{scan: Scan, out: List<&2, Piece>}

# a finished run of text (acc reversed)
def Link.text(acc: String, out: List<&2, Piece>) -> List<&2, Piece>:
  match acc:
    case SNil{}:
      out
    case SCon{h, t}:
      PText{String.reverse(SCon{h, t})} <> out

# the char before continues a word (so "xhttp://" is not a link)
def Link.word(acc: String) -> Bool:
  match acc:
    case SNil{}:
      False{}
    case SCon{+h, _}:
      Bool.or(Char.is_alpha(h), Char.is_digit(h))

# an address starts here: an "h" (already read) then "ttp://" or "ttps://"
def Link.starts(+acc: String, +t: String) -> Bool:
  Bool.and(Bool.not(Link.word(acc)), Bool.or(String.starts_with(t, "ttp://"), String.starts_with(t, "ttps://")))

def Link.text.k(k: Nat, acc: String, out: List<&2, Piece>, +c: Char) -> Sc:
  match k:
    case 1n:
      Sc{SUrl{acc, SCon{c, SNil{}}}, out}
    case 2n:
      Sc{SLab{acc, SNil{}}, out}
    case _:
      Sc{SText{SCon{c, acc}}, out}

def Link.text.step(+acc: String, out: List<&2, Piece>, +c: Char, +t: String) -> Sc:
  Link.text.k(Bool.pick(Nat, Bool.and(U32.is_eq(Link.code(c), 104), Link.starts(acc, t)), 1n, Bool.pick(Nat, U32.is_eq(Link.code(c), 91), 2n, 0n)), acc, out, c)

# what ends a bare address: space, < > " `
def Link.stops(+c: Char) -> Bool:
  Bool.or(Char.is_space(c), Bool.or(Bool.or(U32.is_eq(Link.code(c), 60), U32.is_eq(Link.code(c), 62)), Bool.or(U32.is_eq(Link.code(c), 34), U32.is_eq(Link.code(c), 96))))

def Link.count(s: String, +x: U32) -> Nat:
  match s:
    case SNil{}:
      0n
    case SCon{+h, t}:
      Nat.add(Bool.pick(Nat, U32.is_eq(Link.code(h), x), 1n, 0n), Link.count(t, x))

# what a sentence puts after an address: . , ; : ! ? ' ] and a ) it did not open
def Link.punct(+c: U32) -> Bool:
  Bool.or(Bool.or(Bool.or(U32.is_eq(c, 46), U32.is_eq(c, 44)), Bool.or(U32.is_eq(c, 59), U32.is_eq(c, 58))),
    Bool.or(Bool.or(U32.is_eq(c, 33), U32.is_eq(c, 63)), Bool.or(U32.is_eq(c, 39), U32.is_eq(c, 93))))

# u: the address up to and including its last char c, reversed
def Link.trims(+c: U32, +u: String) -> Bool:
  Bool.or(Link.punct(c), Bool.and(U32.is_eq(c, 41), Nat.is_gt(Link.count(u, 41), Link.count(u, 40))))

# trimming walks the reversed address from its end: trailing punctuation
# moves to the text after it (kept reversed), the rest is the address
type Tr is Data:
  Tr{done: Bool, keep: String, moved: String}

def Link.tr.done(st: Tr) -> Bool:
  match st:
    case Tr{d, _, _}:
      d

def Link.tr.cut(done: Bool, +h: Char, +u: String) -> Bool:
  match done:
    case True{}:
      False{}
    case False{}:
      Link.trims(Link.code(h), u)

def Link.tr.k(cut: Bool, +h: Char, st: Tr) -> Tr:
  match cut st:
    case True{} Tr{d, k, m}:
      Tr{d, k, String.append(m, SCon{h, SNil{}})}
    case False{} Tr{_, k, m}:
      Tr{True{}, SCon{h, k}, m}

def Link.tr(u: String, +st: Tr) -> Tr:
  match u:
    case SNil{}:
      st
    case SCon{+h, +t}:
      Link.tr(t, Link.tr.k(Link.tr.cut(Link.tr.done(st), h, SCon{h, t}), h, st))

def Link.url_end.v(ok: Bool, +url: String, acc: String, moved: String, out: List<&2, Piece>) -> Sc:
  match ok:
    case True{}:
      Sc{SText{moved}, PLink{url, url} <> Link.text(acc, out)}
    case False{}:
      Sc{SText{String.append(moved, String.append(String.reverse(url), acc))}, out}

def Link.url_end.k(tr: Tr, acc: String, out: List<&2, Piece>) -> Sc:
  match tr:
    case Tr{_, +url, moved}:
      Link.url_end.v(Link.valid(url), url, acc, moved, out)

# a bare address ended (u reversed)
def Link.url_end(acc: String, u: String, out: List<&2, Piece>) -> Sc:
  Link.url_end.k(Link.tr(u, Tr{False{}, SNil{}, SNil{}}), acc, out)

# the text step after an address ended at c
def Link.again(sc: Sc, +c: Char, +t: String) -> Sc:
  match sc:
    case Sc{SText{+acc}, out}:
      Link.text.step(acc, out, c, t)
    case Sc{s, out}:
      Sc{s, out}

def Link.url.k(stop: Bool, acc: String, u: String, out: List<&2, Piece>, +c: Char, +t: String) -> Sc:
  match stop:
    case True{}:
      Link.again(Link.url_end(acc, u, out), c, t)
    case False{}:
      Sc{SUrl{acc, SCon{c, u}}, out}

# a [label that went nowhere, back to text
def Link.lab.raw(l: String, acc: String) -> String:
  String.append(l, SCon{'[', acc})

def Link.lab.k(k: Nat, +acc: String, +l: String, out: List<&2, Piece>, +c: Char, +t: String) -> Sc:
  match k:
    case 1n:
      Sc{SMid{acc, l}, out}
    case 2n:
      Link.text.step(Link.lab.raw(l, acc), out, c, t)
    case _:
      Sc{SLab{acc, SCon{c, l}}, out}

def Link.mid.k(open: Bool, +acc: String, +l: String, out: List<&2, Piece>, +c: Char, +t: String) -> Sc:
  match open:
    case True{}:
      Sc{SHref{acc, l, SNil{}}, out}
    case False{}:
      Link.text.step(SCon{']', Link.lab.raw(l, acc)}, out, c, t)

# [label](u that went nowhere, back to text
def Link.href.raw(acc: String, l: String, u: String) -> String:
  String.append(u, SCon{'(', SCon{']', Link.lab.raw(l, acc)}})

def Link.label(+l: String, +u: String) -> String:
  Bool.pick(String, String.is_empty(l), String.reverse(u), String.reverse(l))

def Link.close(ok: Bool, +acc: String, +l: String, +u: String, out: List<&2, Piece>) -> Sc:
  match ok:
    case True{}:
      Sc{SText{SNil{}}, PLink{Link.label(l, u), String.reverse(u)} <> Link.text(acc, out)}
    case False{}:
      Sc{SText{SCon{')', Link.href.raw(acc, l, u)}}, out}

def Link.href.k(k: Nat, +acc: String, +l: String, +u: String, out: List<&2, Piece>, +c: Char, +t: String) -> Sc:
  match k:
    case 1n:
      Link.close(Link.valid(String.reverse(u)), acc, l, u, out)
    case 2n:
      Link.text.step(Link.href.raw(acc, l, u), out, c, t)
    case _:
      Sc{SHref{acc, l, SCon{c, u}}, out}

def Link.step(sc: Sc, +c: Char, +t: String) -> Sc:
  match sc:
    case Sc{SText{+acc}, out}:
      Link.text.step(acc, out, c, t)
    case Sc{SUrl{acc, u}, out}:
      Link.url.k(Link.stops(c), acc, u, out, c, t)
    case Sc{SLab{acc, l}, out}:
      Link.lab.k(Bool.pick(Nat, U32.is_eq(Link.code(c), 93), 1n, Bool.pick(Nat, Bool.or(U32.is_eq(Link.code(c), 10), U32.is_eq(Link.code(c), 91)), 2n, 0n)), acc, l, out, c, t)
    case Sc{SMid{acc, l}, out}:
      Link.mid.k(U32.is_eq(Link.code(c), 40), acc, l, out, c, t)
    case Sc{SHref{acc, l, u}, out}:
      Link.href.k(Bool.pick(Nat, U32.is_eq(Link.code(c), 41), 1n, Bool.pick(Nat, Link.stops(c), 2n, 0n)), acc, l, u, out, c, t)

def Link.fin.text(sc: Sc) -> List<&2, Piece>:
  match sc:
    case Sc{SText{acc}, out}:
      List.reverse(&2, Piece, Link.text(acc, out))
    case Sc{_, out}:
      List.reverse(&2, Piece, out)

def Link.fin(sc: Sc) -> List<&2, Piece>:
  match sc:
    case Sc{SText{acc}, out}:
      List.reverse(&2, Piece, Link.text(acc, out))
    case Sc{SUrl{acc, u}, out}:
      Link.fin.text(Link.url_end(acc, u, out))
    case Sc{SLab{acc, l}, out}:
      List.reverse(&2, Piece, Link.text(Link.lab.raw(l, acc), out))
    case Sc{SMid{acc, l}, out}:
      List.reverse(&2, Piece, Link.text(SCon{']', Link.lab.raw(l, acc)}, out))
    case Sc{SHref{acc, l, u}, out}:
      List.reverse(&2, Piece, Link.text(Link.href.raw(acc, l, u), out))

def Link.go(s: String, sc: Sc) -> List<&2, Piece>:
  match s:
    case SNil{}:
      Link.fin(sc)
    case SCon{+c, +t}:
      Link.go(t, Link.step(sc, c, t))

# text as runs of plain text and links, in order
def Link.pieces(+s: String) -> List<&2, Piece>:
  Link.go(s, Sc{SText{SNil{}}, Nil{}})

# the text a reader sees (a link shows its label)
def Link.plain(ps: List<&2, Piece>) -> String:
  match ps:
    case Nil{}:
      ""
    case PText{s} <> t:
      s ++ Link.plain(t)
    case PLink{l, _} <> t:
      l ++ Link.plain(t)

# the addresses, in order
def Link.urls(ps: List<&2, Piece>) -> List<&2, String>:
  match ps:
    case Nil{}:
      Nil{}
    case PText{_} <> t:
      Link.urls(t)
    case PLink{_, u} <> t:
      u <> Link.urls(t)

# Lines
# -----
# The window wraps a paragraph's text into lines first, then finds in each
# line the labels of the paragraph's links. A label cut by a wrap is not a
# link on either line.

# the first link whose label starts s
def Link.at(ls: List<&2, Piece>, +s: String) -> Maybe<&2, Piece>:
  match ls:
    case Nil{}:
      None{}
    case PText{_} <> t:
      Link.at(t, s)
    case PLink{+l, +u} <> t:
      Bool.pick(Maybe<&2, Piece>, Bool.and(Bool.not(String.is_empty(l)), String.starts_with(s, l)), Some{PLink{l, u}}, Link.at(t, s))

type Ct is Data:
  Ct{acc: String, skip: Nat, out: List<&2, Piece>}

def Link.cut.hit(m: Maybe<&2, Piece>, +c: Char, st: Ct) -> Ct:
  match m st:
    case Some{PLink{+l, u}} Ct{acc, _, out}:
      Ct{SNil{}, Nat.sub(String.length(l), 1n), PLink{l, u} <> Link.text(acc, out)}
    case _ Ct{acc, k, out}:
      Ct{SCon{c, acc}, k, out}

def Link.cut.step(skip: Nat, +ls: List<&2, Piece>, +c: Char, +s: String, st: Ct) -> Ct:
  match skip st:
    case 1n+k Ct{acc, _, out}:
      Ct{acc, k, out}
    case 0n _:
      Link.cut.hit(Link.at(ls, s), c, st)

def Link.cut.skip(st: Ct) -> Nat:
  match st:
    case Ct{_, k, _}:
      k

def Link.cut.fin(st: Ct) -> List<&2, Piece>:
  match st:
    case Ct{acc, _, out}:
      List.reverse(&2, Piece, Link.text(acc, out))

def Link.cut.go(s: String, +ls: List<&2, Piece>, +st: Ct) -> List<&2, Piece>:
  match s:
    case SNil{}:
      Link.cut.fin(st)
    case SCon{+c, +t}:
      Link.cut.go(t, ls, Link.cut.step(Link.cut.skip(st), ls, c, SCon{c, t}, st))

# a drawn line as runs of text and the links whose labels it shows
def Link.cut(+line: String, ls: List<&2, Piece>) -> List<&2, Piece>:
  match ls:
    case Nil{}:
      [PText{line}]
    case +h <> t:
      Link.cut.go(line, h <> t, Ct{SNil{}, 0n, Nil{}})

# links carried in a string (a laid-out line's spare field): label US url,
# joined by RS
def Link.enc(ls: List<&2, Piece>) -> String:
  match ls:
    case Nil{}:
      ""
    case PText{_} <> t:
      Link.enc(t)
    case PLink{l, u} <> t:
      l ++ SCon{Chr{31}, u} ++ SCon{Chr{30}, Link.enc(t)}

def Link.dec.one(+s: String) -> List<&2, Piece>:
  Bool.pick(List<&2, Piece>, String.is_empty(s), Nil{},
    [PLink{Maybe.default(&2, String, List.get(&2, String, String.split(s, Chr{31}), 0n), ""), Maybe.default(&2, String, List.get(&2, String, String.split(s, Chr{31}), 1n), "")}])

def Link.dec.all(xs: List<&2, String>) -> List<&2, Piece>:
  match xs:
    case Nil{}:
      Nil{}
    case +x <> t:
      List.append(&2, Piece, Link.dec.one(x), Link.dec.all(t))

def Link.dec(+s: String) -> List<&2, Piece>:
  Link.dec.all(String.split(s, Chr{30}))
