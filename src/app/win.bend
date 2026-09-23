import Base

# The app's window (effects/win.c): resizable, with text, wheel, resize
# and clipboard events. Frames are Base's Image quadtree.

# mods: 1 shift, 2 ctrl, 4 alt, 8 super. code is the X keysym; text is the
# code point the key typed (0 for none). Wheel dir: 0 up, 1 down, 2 left,
# 3 right.
type WinEv is Data:
  WKey{code: U32, text: U32, mods: U32, down: Bool}
  WButton{x: U32, y: U32, button: U32, down: Bool}
  WMove{x: U32, y: U32}
  WWheel{x: U32, y: U32, dir: U32}
  WSize{w: U32, h: U32}
  WExpose{}
  WQuit{}
  WPaste{text: String}
  WDragOver{x: U32, y: U32}
  WDragLeave{}
  WDrop{text: String}
  # the window lost the keyboard (keys held then are let go unseen)
  WBlur{}

def Win.open(title: String, w: U32, h: U32) -> IO(Result<&1, &1, U32 & String, Window>):
  import "./effects/win.c"
  import "./effects/win.js"

# the events since the last call, five words each; parks until there is
# at least one (Win.decode reads them)
def Win.words(win: Window) -> IO(Window & List<&2, U32>):
  import "./effects/win.c"
  import "./effects/win.js"

# show a frame; the image comes back so the caller can free it
def Win.present(win: Window, image: Image) -> IO(Window & Image):
  import "./effects/win.c"
  import "./effects/win.js"

def Win.copy(win: Window, text: String) -> IO(Window):
  import "./effects/win.c"
  import "./effects/win.js"

# request the clipboard; it arrives as a WPaste event
def Win.paste(win: Window) -> IO(Window):
  import "./effects/win.c"
  import "./effects/win.js"

def Win.pasted(win: Window) -> IO(Window & String):
  import "./effects/win.c"
  import "./effects/win.js"

# the text/uri-list of the last WDrop (files dragged in from outside)
def Win.dropped(win: Window) -> IO(Window & String):
  import "./effects/win.c"
  import "./effects/win.js"

def Win.size(win: Window) -> IO(Window & U32 & U32):
  import "./effects/win.c"
  import "./effects/win.js"

# a second handle: one computation waits on events, another presents
def Win.twin(win: Window) -> IO(Window & Window):
  import "./effects/win.c"
  import "./effects/win.js"

def Win.title(win: Window, title: String) -> IO(Window):
  import "./effects/win.c"
  import "./effects/win.js"

def Win.ev.k(k: Nat, +a: U32, +b: U32, +c: U32, +d: U32) -> WinEv:
  match k:
    case 0n:
      WKey{a, b, c, U32.is_ne(d, 0)}
    case 1n:
      WButton{a, b, c, U32.is_ne(d, 0)}
    case 2n:
      WMove{a, b}
    case 3n:
      WWheel{a, b, c}
    case 4n:
      WSize{a, b}
    case 5n:
      WExpose{}
    case 7n:
      WPaste{""}
    case 8n:
      WDragOver{a, b}
    case 9n:
      WDragLeave{}
    case 10n:
      WDrop{""}
    case 11n:
      WBlur{}
    case _:
      WQuit{}

def Win.ev(+k: U32, +a: U32, +b: U32, +c: U32, +d: U32) -> WinEv:
  Win.ev.k(U32.to_nat(k), a, b, c, d)

# five words per event
def Win.decode(ws: List<&2, U32>) -> List<&2, WinEv>:
  match ws:
    case +k <> +a <> +b <> +c <> +d <> t:
      Win.ev(k, a, b, c, d) <> Win.decode(t)
    case _:
      Nil{}
