import Base
import ./check.bend as C
import ../src/core/attach.bend as A
import ../src/core/client.bend as U

def show.list(xs: List<&2, String>) -> String:
  "[" ++ String.join(xs, "|") ++ "]"

def act.ui(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}:
      u

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("uri-list", show.list(A.Att.uri_list("file:///home/me/My%20Board%C3%A9.png\r\nfile:///tmp/b.txt\r\n")), "[/home/me/My Boardé.png|/tmp/b.txt]")
    C.Check.str("localhost", show.list(A.Att.uri_list("file://localhost/etc/hosts\n")), "[/etc/hosts]")
    C.Check.str("host", show.list(A.Att.uri_list("file://box/a/b c.kicad_pcb")), "[/a/b c.kicad_pcb]")
    C.Check.str("one slash", show.list(A.Att.uri_list("file:/x/y")), "[/x/y]")
    C.Check.str("comments", show.list(A.Att.uri_list("# from nautilus\r\nfile:///a\r\n")), "[/a]")
    C.Check.str("non-file", show.list(A.Att.uri_list("https://example.com/a.png\r\nfile:///b\r\nmailto:x@y\r\n")), "[/b]")
    C.Check.str("relative", show.list(A.Att.uri_list("file:rel/path\nfile://host\n")), "[]")
    C.Check.str("blank", show.list(A.Att.uri_list("\r\n\r\n")), "[]")
    C.Check.str("bad escape", show.list(A.Att.uri_list("file:///100%25%zz")), "[/100%%zz]")
    C.Check.str("hover on", Bool.show(U.Ui.flag(act.ui(U.Ui.act(U.Ui.init(0n), "drop-hover", "1")), "drop")), "True")
    C.Check.str("hover off", Bool.show(U.Ui.flag(act.ui(U.Ui.act(act.ui(U.Ui.act(U.Ui.init(0n), "drop-hover", "1")), "drop-hover", "")), "drop")), "False")
