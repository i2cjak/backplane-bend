import Base
import ./check.bend as C
import ../src/core/links.bend as L
import ../src/web/dom.bend as D

def Web.attrs(xs: List<&2, D.Attr>) -> String:
  match xs:
    case Nil{}:
      ""
    case D.At{n, v} <> t:
      " " ++ n ++ "=" ++ v ++ Web.attrs(t)
    case D.On{e, a} <> t:
      " on" ++ e ++ "=" ++ a ++ Web.attrs(t)

def Web.shows(ns: List<&2, D.Node>) -> String:
  match ns:
    case Nil{}:
      ""
    case D.Txt{s} <> t:
      s ++ Web.shows(t)
    case D.El{+tag, _, xs, ks} <> t:
      "<" ++ tag ++ Web.attrs(xs) ++ ">" ++ Web.shows(ks) ++ "</" ++ tag ++ ">" ++ Web.shows(t)

# pieces shown as text: links as <label|url>
def Show.go(ps: List<&2, L.Piece>) -> String:
  match ps:
    case Nil{}:
      ""
    case L.PText{s} <> t:
      s ++ Show.go(t)
    case L.PLink{l, u} <> t:
      "<" ++ l ++ "|" ++ u ++ ">" ++ Show.go(t)

def Show(+s: String) -> String:
  Show.go(L.Link.pieces(s))

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("bare", Show("see https://example.com/a?b=1 now"), "see <https://example.com/a?b=1|https://example.com/a?b=1> now")
    C.Check.str("sentence end", Show("Docs: http://x.io/docs."), "Docs: <http://x.io/docs|http://x.io/docs>.")
    C.Check.str("in parens", Show("(https://a.b/c), then"), "(<https://a.b/c|https://a.b/c>), then")
    C.Check.str("balanced parens", Show("https://en.wikipedia.org/wiki/Foo_(bar)"), "<https://en.wikipedia.org/wiki/Foo_(bar)|https://en.wikipedia.org/wiki/Foo_(bar)>")
    C.Check.str("markdown", Show("read [the guide](https://bend-lang.com/guide) first"), "read <the guide|https://bend-lang.com/guide> first")
    C.Check.str("markdown not web", Show("[x](javascript:alert(1)) and ![img](/tmp/a.png)"), "[x](javascript:alert(1)) and ![img](/tmp/a.png)")
    C.Check.str("brackets alone", Show("a [note] here [b"), "a [note] here [b")
    C.Check.str("scheme only", Show("http:// and https://"), "http:// and https://")
    C.Check.str("inside a word", Show("xhttp://a.b"), "xhttp://a.b")
    C.Check.str("angle", Show("<https://a.b/x>"), "<<https://a.b/x|https://a.b/x>>")
    C.Check.str("two", String.join(L.Link.urls(L.Link.pieces("https://a.b and [c](http://c.d)")), " "), "https://a.b http://c.d")
    C.Check.str("plain keeps text", L.Link.plain(L.Link.pieces("go to [site](https://s.t), ok")), "go to site, ok")
    C.Check.str("cut", Show.go(L.Link.cut("open site or https://a.b now", L.Link.dec(L.Link.enc(L.Link.pieces("[site](https://s.t) https://a.b"))))), "open <site|https://s.t> or <https://a.b|https://a.b> now")
    C.Check.str("cut none", Show.go(L.Link.cut("plain line", Nil{})), "plain line")
    C.Check.str("web only", String.join([Bool.show(L.Link.is_web("https://x")), Bool.show(L.Link.is_web("javascript:x")), Bool.show(L.Link.is_web("file:///etc"))], " "), "True False False")
    C.Check.str("web reply", Web.shows(D.Md.render("See **this** at https://a.b/c. Or `https://no.link`")), "<p>See <strong>this</strong> at <a class=link href=https://a.b/c target=_blank rel=noopener noreferrer title=https://a.b/c>https://a.b/c</a>. Or <code>https://no.link</code></p>")
    C.Check.str("web markdown link", Web.shows(D.Md.render("- [docs](https://d.e)")), "<ul><li><a class=link href=https://d.e target=_blank rel=noopener noreferrer title=https://d.e>docs</a></li></ul>")
