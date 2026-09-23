import Base
import ../core/links.bend as LK

# A view is a tree of Nodes; the host patches the DOM to match it. Events
# carry an action name back to Ui.act together with a value: the element's
# `data-value` (literal, or "#id" for the value of the element with that
# id), else the element's own value.

type Attr is Data:
  At{name: String, value: String}
  On{event: String, action: String}

type Node is Data:
  El{tag: String, key: String, attrs: List<&2, Attr>, kids: List<&2, Node>}
  Txt{text: String}

def Dom.el(tag: String, attrs: List<&2, Attr>, kids: List<&2, Node>) -> Node:
  El{tag, "", attrs, kids}

def Dom.div(cls: String, kids: List<&2, Node>) -> Node:
  El{"div", "", [At{"class", cls}], kids}

def Dom.span(cls: String, text: String) -> Node:
  El{"span", "", [At{"class", cls}], [Txt{text}]}

# a button that sends `action` with `value`
def Dom.button(cls: String, action: String, value: String, title: String, label: String) -> Node:
  El{"button", "", [At{"class", cls}, At{"title", title}, At{"data-value", value}, On{"click", action}], [Txt{label}]}

def Dom.copy(text: String) -> Node:
  El{"button", "", [At{"class", "copy"}, At{"title", "Copy"}, At{"data-value", text}, On{"click", "copy"}], [Txt{"Copy"}]}

def Dom.when(b: Bool, n: Node) -> List<&2, Node>:
  match b:
    case True{}:
      [n]
    case False{}:
      Nil{}

def Dom.cat(a: List<&2, Node>, b: List<&2, Node>) -> List<&2, Node>:
  List.append(&2, Node, a, b)

# Inline markdown
# ---------------

type Inl is Data:
  IText{acc: String}
  IStar{acc: String}
  ICode{acc: String}
  IBold{acc: String}
  IBoldStar{acc: String}

type Glyph is Data:
  KTick{}
  KStar{}
  KOther{}

def Md.glyph.k(tick: Bool, star: Bool) -> Glyph:
  match tick star:
    case True{} _:
      KTick{}
    case False{} True{}:
      KStar{}
    case False{} False{}:
      KOther{}

def Md.glyph(c: Char) -> Glyph:
  match c:
    case Chr{+u}:
      Md.glyph.k(U32.is_eq(u, 96), U32.is_eq(u, 42))

# a web link, opening in a new tab
def Dom.link(+label: String, +url: String) -> Node:
  El{"a", "", [At{"class", "link"}, At{"href", url}, At{"target", "_blank"}, At{"rel", "noopener noreferrer"}, At{"title", url}], [Txt{label}]}

# text with its links (LK.Link.pieces) as nodes, onto out (reversed)
def Dom.pieces(ps: List<&2, LK.Piece>, out: List<&2, Node>) -> List<&2, Node>:
  match ps:
    case Nil{}:
      out
    case LK.PText{s} <> t:
      Dom.pieces(t, Txt{s} <> out)
    case LK.PLink{l, u} <> t:
      Dom.pieces(t, Dom.link(l, u) <> out)

# text as nodes, its links clickable
def Dom.linked(+s: String) -> List<&2, Node>:
  List.reverse(&2, Node, Dom.pieces(LK.Link.pieces(s), Nil{}))

# a finished run of plain text (acc is reversed); its links become <a>
def Md.text(acc: String, out: List<&2, Node>) -> List<&2, Node>:
  match acc:
    case SNil{}:
      out
    case SCon{h, t}:
      Dom.pieces(LK.Link.pieces(String.reverse(SCon{h, t})), out)

def Md.code(acc: String) -> Node:
  El{"code", "", Nil{}, [Txt{String.reverse(acc)}]}

def Md.bold(acc: String) -> Node:
  El{"strong", "", Nil{}, [Txt{String.reverse(acc)}]}

def Md.istep(st: Inl, k: Glyph, c: Char, out: List<&2, Node>) -> Inl & List<&2, Node>:
  match st k:
    case IText{acc} KTick{}:
      (ICode{SNil{}}, Md.text(acc, out))
    case IText{acc} KStar{}:
      (IStar{acc}, out)
    case IText{acc} KOther{}:
      (IText{SCon{c, acc}}, out)
    case IStar{acc} KStar{}:
      (IBold{SNil{}}, Md.text(acc, out))
    case IStar{acc} _:
      (IText{SCon{c, SCon{'*', acc}}}, out)
    case ICode{acc} KTick{}:
      (IText{SNil{}}, Md.code(acc) <> out)
    case ICode{acc} _:
      (ICode{SCon{c, acc}}, out)
    case IBold{acc} KStar{}:
      (IBoldStar{acc}, out)
    case IBold{acc} _:
      (IBold{SCon{c, acc}}, out)
    case IBoldStar{acc} KStar{}:
      (IText{SNil{}}, Md.bold(acc) <> out)
    case IBoldStar{acc} _:
      (IBold{SCon{c, SCon{'*', acc}}}, out)

def Md.istep.pair(+c: Char, r: Inl & List<&2, Node>) -> Inl & List<&2, Node>:
  (st, out) = r
  Md.istep(st, Md.glyph(c), c, out)

def Md.ifin(r: Inl & List<&2, Node>) -> List<&2, Node>:
  (st, out) = r
  match st:
    case IText{acc}:
      List.reverse(&2, Node, Md.text(acc, out))
    case IStar{acc}:
      List.reverse(&2, Node, Md.text(SCon{'*', acc}, out))
    case ICode{acc}:
      List.reverse(&2, Node, Md.text(String.append(acc, "`"), out))
    case IBold{acc}:
      List.reverse(&2, Node, Md.text(String.append(acc, "**"), out))
    case IBoldStar{acc}:
      List.reverse(&2, Node, Md.text(String.append(SCon{'*', acc}, "**"), out))

def Md.igo(s: String, r: Inl & List<&2, Node>) -> List<&2, Node>:
  match s:
    case SNil{}:
      Md.ifin(r)
    case SCon{+c, t}:
      Md.igo(t, Md.istep.pair(c, r))

# inline nodes of one line or paragraph
def Md.inline(s: String) -> List<&2, Node>:
  Md.igo(s, (IText{SNil{}}, Nil{}))

# Blocks
# ------

type Blk is Data:
  BNone{}
  BPara{lines: List<&2, String>}
  BCode{lines: List<&2, String>}
  BList{items: List<&2, String>}

type Line is Data:
  LFence{}
  LHead{level: Nat, text: String}
  LItem{text: String}
  LBlank{}
  LText{text: String}

def Md.line.k(fence: Bool, h3: Bool, h2: Bool, h1: Bool, item: Bool, blank: Bool, +t: String, l: String) -> Line:
  match fence h3 h2 h1 item blank:
    case True{} _ _ _ _ _:
      LFence{}
    case _ True{} _ _ _ _:
      LHead{3n, String.drop(t, 4n)}
    case _ _ True{} _ _ _:
      LHead{2n, String.drop(t, 3n)}
    case _ _ _ True{} _ _:
      LHead{1n, String.drop(t, 2n)}
    case _ _ _ _ True{} _:
      LItem{String.drop(t, 2n)}
    case _ _ _ _ _ True{}:
      LBlank{}
    case _ _ _ _ _ _:
      LText{l}

def Md.line(+l: String) -> Line:
  +t = String.trim_start(l)
  Md.line.k(String.starts_with(t, "```"), String.starts_with(t, "### "), String.starts_with(t, "## "),
    String.starts_with(t, "# "), Bool.or(String.starts_with(t, "- "), String.starts_with(t, "* ")),
    String.is_empty(String.trim(t)), t, l)

def Md.para(ls: List<&2, String>) -> Node:
  El{"p", "", Nil{}, Md.inline(String.join(List.reverse(&2, String, ls), "\n"))}

def Md.li(s: String) -> Node:
  El{"li", "", Nil{}, Md.inline(s)}

def Md.lis(xs: List<&2, String>) -> List<&2, Node>:
  match xs:
    case Nil{}:
      Nil{}
    case x <> t:
      Md.li(x) <> Md.lis(t)

def Md.codeblock(ls: List<&2, String>) -> Node:
  +text = String.join(List.reverse(&2, String, ls), "\n")
  El{"div", "", [At{"class", "codeblock"}], [Dom.copy(text), El{"pre", "", Nil{}, [El{"code", "", Nil{}, [Txt{text}]}]}]}

# the node a finished block contributes
def Md.close(b: Blk, out: List<&2, Node>) -> List<&2, Node>:
  match b:
    case BNone{}:
      out
    case BPara{ls}:
      Md.para(ls) <> out
    case BCode{ls}:
      Md.codeblock(ls) <> out
    case BList{xs}:
      El{"ul", "", Nil{}, Md.lis(List.reverse(&2, String, xs))} <> out

def Md.head(n: Nat, t: String) -> Node:
  match n:
    case 1n:
      El{"h3", "", Nil{}, Md.inline(t)}
    case 2n:
      El{"h4", "", Nil{}, Md.inline(t)}
    case _:
      El{"h5", "", Nil{}, Md.inline(t)}

def Md.bstep(b: Blk, ln: Line, +raw: String, out: List<&2, Node>) -> Blk & List<&2, Node>:
  match b ln:
    case BCode{ls} LFence{}:
      (BNone{}, Md.codeblock(ls) <> out)
    case BCode{ls} _:
      (BCode{raw <> ls}, out)
    case _ LFence{}:
      (BCode{Nil{}}, Md.close(b, out))
    case _ LHead{n, t}:
      (BNone{}, Md.head(n, t) <> Md.close(b, out))
    case BList{xs} LItem{t}:
      (BList{t <> xs}, out)
    case _ LItem{t}:
      (BList{[t]}, Md.close(b, out))
    case _ LBlank{}:
      (BNone{}, Md.close(b, out))
    case BPara{ls} LText{t}:
      (BPara{t <> ls}, out)
    case _ LText{t}:
      (BPara{[t]}, Md.close(b, out))

def Md.bstep.pair(+l: String, r: Blk & List<&2, Node>) -> Blk & List<&2, Node>:
  (b, out) = r
  Md.bstep(b, Md.line(l), l, out)

def Md.bfin(r: Blk & List<&2, Node>) -> List<&2, Node>:
  (b, out) = r
  List.reverse(&2, Node, Md.close(b, out))

def Md.bgo(ls: List<&2, String>, r: Blk & List<&2, Node>) -> List<&2, Node>:
  match ls:
    case Nil{}:
      Md.bfin(r)
    case +l <> t:
      Md.bgo(t, Md.bstep.pair(l, r))

# markdown text as nodes
def Md.render(s: String) -> List<&2, Node>:
  Md.bgo(String.lines(s), (BNone{}, Nil{}))
