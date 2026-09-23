import Base
import ../core/json.bend as J
import ./dom.bend as D
import ../core/client.bend as U
import ./view.bend as V
import ../core/cbor.bend as C
import ../core/attach.bend as AT
import ../core/lightbox.bend as LB

# What host.js calls. Everything the page decides happens behind these.

def init(now: Nat, cid: String) -> U.Ui:
  U.Ui.set_cid(U.Ui.init(now), cid)

def recv(u: U.Ui, o: J.Json) -> U.Act:
  U.Ui.recv_act(u, o)

def act(u: U.Ui, action: String, value: String) -> U.Act:
  U.Ui.act(u, action, value)

def view(u: U.Ui) -> D.Node:
  V.View.page(u)

def online(u: U.Ui, b: Bool) -> U.Ui:
  U.Ui.online(u, b)

def tick(u: U.Ui, now: Nat) -> U.Ui:
  U.Ui.tick(u, now)

# how many changes this page holds and which log they came from (a
# reconnect asks the server for the rest)
def seq(u: U.Ui) -> String:
  Nat.show(U.Ui.seq(u))

def origin(u: U.Ui) -> String:
  U.Ui.info(u, "origin")

# The wire: CBOR bytes in and out (the host only moves them)
def wire_in(bs: List<&2, U32>) -> J.Json:
  Maybe.default(&2, J.Json, C.Cbor.decode(bs), J.Null{})

def wire_out(text: String) -> List<&2, U32>:
  C.Cbor.encode(Maybe.default(&2, J.Json, J.Json.parse(text), J.Null{}))

def show(j: J.Json) -> String:
  J.Json.show(j)

# how many bytes of a file go in one upload piece
def chunk() -> String:
  Nat.show(AT.Att.chunk())

# the shortcuts the page takes for itself, comma-separated (in the
# terminal, and elsewhere)
def keys_term() -> String:
  String.join(U.Ui.keys(True{}), ",")

def keys_page() -> String:
  String.join(U.Ui.keys(False{}), ",")

# The image lightbox (core/lightbox.bend decides the zoom, the pan, the
# easing and what closes it; host.js feeds it pointer events and sets the
# style it answers on the picture)

def lb_node(url: String) -> D.Node:
  D.El{"div", "", [D.At{"class", "lightbox"}], [
    D.El{"img", "", [D.At{"class", "lb-img"}, D.At{"src", url}, D.At{"alt", ""}, D.At{"draggable", "false"}], Nil{}},
    D.El{"button", "", [D.At{"class", "lb-close"}, D.At{"title", "Close"}, D.At{"data-lb-close", "1"}], [D.Txt{"×"}]}]}

def lb_open() -> LB.Lb:
  LB.Lb.open()

def lb_box(iw: Nat, ih: Nat, vw: Nat, vh: Nat) -> LB.LbBox:
  LB.LbBox{iw, ih, vw, vh}

# a wheel turn (dy > 0 zooms out); a trackpad pinch comes as a ctrl wheel
# with small steps, applied at once and made larger
def lb_wheel(lb: LB.Lb, down: Bool, +mag: Nat, +pinch: Bool, cx: Nat, cy: Nat, b: LB.LbBox, now: Nat) -> LB.Lb:
  LB.Lb.wheel(lb, Bool.not(down), Bool.pick(Nat, pinch, Nat.mul(mag, 4n), mag), Bool.not(pinch), cx, cy, b, now)

def lb_pinch(lb: LB.Lb, d0: Nat, d1: Nat, cx: Nat, cy: Nat, b: LB.LbBox, now: Nat) -> LB.Lb:
  LB.Lb.pinch(lb, d0, d1, cx, cy, b, now)

def lb_press(lb: LB.Lb, x: Nat, y: Nat, b: LB.LbBox, now: Nat) -> LB.Lb:
  LB.Lb.press(lb, x, y, b, now)

def lb_move(lb: LB.Lb, x: Nat, y: Nat, b: LB.LbBox, now: Nat) -> LB.Lb:
  LB.Lb.move(lb, x, y, b, now)

def lb_release(lb: LB.Lb, x: Nat, y: Nat, b: LB.LbBox, now: Nat) -> LB.Lb:
  LB.Lb.release(lb, x, y, b, now)

def lb_closes(lb: LB.Lb, x: Nat, y: Nat) -> Bool:
  LB.Lb.closes(lb, x, y)

def lb_key(k: String) -> Bool:
  String.eq(k, "Escape")

def lb_stamp(lb: LB.Lb, now: Nat) -> LB.Lb:
  LB.Lb.stamp(lb, now)

def lb_busy(lb: LB.Lb, now: Nat) -> Bool:
  LB.Lb.busy(lb, now)

def lb_css(lb: LB.Lb, b: LB.LbBox, now: Nat) -> String:
  LB.Lb.css(lb, b, now)
