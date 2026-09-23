import Base
import ./check.bend as C
import ../src/core/model.bend as M
import ../src/core/fold.bend as F
import ../src/core/client.bend as U
import ../src/web/view.bend as V
import ../src/web/dom.bend as D

def tool(+id: String, +kind: String) -> M.Entry:
  M.Act{id, "t", "tool", kind, "x", 0n}

def msg(+id: String) -> M.Entry:
  M.Msg{id, "t", M.Assistant{}, "hi", 0n}

def err(+id: String) -> M.Entry:
  M.Act{id, "t", "error", "exit", "boom", 0n}

def Show.idl(es: List<&2, M.Entry>) -> List<&2, String>:
  match es:
    case Nil{}:
      Nil{}
    case e <> t:
      F.Fold.id(e) <> Show.idl(t)

# groups as text: m for a single entry, [ids] for a run
def Show.ids(es: List<&2, M.Entry>) -> String:
  String.join(Show.idl(es), ",")

def Show.gs(gs: List<&2, F.Grp>) -> String:
  match gs:
    case Nil{}:
      ""
    case F.GOne{e} <> t:
      F.Fold.id(e) ++ " " ++ Show.gs(t)
    case F.GRun{xs} <> t:
      "[" ++ Show.ids(xs) ++ "] " ++ Show.gs(t)

def Show.roles(rs: List<&2, F.Role>) -> String:
  match rs:
    case Nil{}:
      ""
    case F.RShow{} <> t:
      "s " ++ Show.roles(t)
    case F.RHead{id, label, open} <> t:
      "h(" ++ id ++ "|" ++ label ++ "|" ++ Bool.show(open) ++ ") " ++ Show.roles(t)
    case F.RIn{open} <> t:
      "i(" ++ Bool.show(open) ++ ") " ++ Show.roles(t)

def es1() -> List<&2, M.Entry>:
  [msg("m1"), tool("a", "shell"), tool("b", "edit"), tool("c", "shell"), err("e"), tool("d", "read"), msg("m2"), tool("f", "shell")]

def none() -> Map<&2, String>:
  Map.new(&2, String)

# the web's nodes as tags and text (of the attributes, class and data-value)
def Web.attrs(xs: List<&2, D.Attr>) -> String:
  match xs:
    case Nil{}:
      ""
    case D.At{"class", v} <> t:
      "." ++ v ++ Web.attrs(t)
    case D.At{"data-value", v} <> t:
      "=" ++ v ++ Web.attrs(t)
    case _ <> t:
      Web.attrs(t)

def Web.shows(ns: List<&2, D.Node>) -> String:
  match ns:
    case Nil{}:
      ""
    case D.Txt{s} <> t:
      s ++ Web.shows(t)
    case D.El{"svg", _, _, _} <> t:
      "^" ++ Web.shows(t)
    case D.El{+tag, _, xs, ks} <> t:
      "<" ++ tag ++ Web.attrs(xs) ++ ">" ++ Web.shows(ks) ++ "</" ++ tag ++ ">" ++ Web.shows(t)

def after(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}:
      u

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("groups", Show.gs(F.Fold.groups(es1())), "m1 [a,b,c] e [d] m2 [f] ")
    C.Check.str("flat keeps all", Show.ids(F.Fold.flat(F.Fold.groups(es1()))), Show.ids(es1()))
    C.Check.str("count", Nat.show(F.Fold.count(F.Fold.groups(es1()))), "8")
    C.Check.str("runs only tools", Bool.show(F.Fold.all(F.Fold.runs(F.Fold.groups(es1())))), "True")
    C.Check.str("empty", Show.gs(F.Fold.groups(Nil{})), "")
    C.Check.str("label", F.Fold.label([tool("a", "shell"), tool("b", "edit"), tool("c", "shell"), tool("d", "read")]), "4 tool calls · shell, edit, read")
    C.Check.str("label one", F.Fold.label([tool("a", "shell")]), "1 tool call · shell")
    C.Check.str("label many kinds", F.Fold.label([tool("a", "a"), tool("b", "b"), tool("c", "c"), tool("d", "d")]), "4 tool calls · a, b, c, …")
    C.Check.str("roles idle", Show.roles(F.Fold.roles(es1(), none(), False{})),
      "s h(a|3 tool calls · shell, edit|False) i(False) i(False) s h(d|1 tool call · read|False) s h(f|1 tool call · shell|False) ")
    C.Check.str("roles running: last run open", Show.roles(F.Fold.roles(es1(), none(), True{})),
      "s h(a|3 tool calls · shell, edit|False) i(False) i(False) s h(d|1 tool call · read|False) s h(f|1 tool call · shell|True) ")
    C.Check.str("roles running: not at the bottom", Show.roles(F.Fold.roles([tool("a", "x"), msg("m")], none(), True{})), "h(a|1 tool call · x|False) s ")
    C.Check.str("user opened", Show.roles(F.Fold.roles([tool("a", "x"), tool("b", "x")], Map.set(&2, String, none(), "fold:a", "1"), False{})), "h(a|2 tool calls · x|True) i(True) ")
    C.Check.str("user shut the live one", Show.roles(F.Fold.roles([tool("a", "x")], Map.set(&2, String, none(), "fold:a", "0"), True{})), "h(a|1 tool call · x|False) ")
    C.Check.str("ask", F.Fold.ask(True{}, "a") ++ " " ++ F.Fold.ask(False{}, "a"), "0a 1a")
    C.Check.str("click opens", U.Ui.info(after(U.Ui.act(U.Ui.init(0n), "fold", "1a")), "fold:a"), "1")
    C.Check.str("click shuts", U.Ui.info(after(U.Ui.act(after(U.Ui.act(U.Ui.init(0n), "fold", "1a")), "fold", "0a")), "fold:a"), "0")
    C.Check.str("web folded", Web.shows(V.View.entries([tool("a", "shell"), tool("b", "edit"), err("e")], M.State.empty(), "t", none(), False{})),
      "<button.fold=1a>^<span>2 tool calls · shell, edit</span></button><div.act error><span.kind>exit</span><span.summary>boom</span></div>")
    C.Check.str("web live open", Web.shows(V.View.entries([msg("m"), tool("a", "shell")], M.State.empty(), "t", none(), True{})),
      "<div.msg assistant><div.body><p>hi</p></div><button.copy=hi>Copy</button></div><button.fold=0a>^<span>1 tool call · shell</span></button><div.act tool><span.kind>shell</span><span.summary>x</span></div>")
