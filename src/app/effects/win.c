// Backplane window (X11)
// ======================
//
// Base's Window is fixed-size and reports no text, wheel, resize or
// clipboard, so the app has its own. libX11 is opened at run time (no link
// flags, and a machine without X still runs the server). A frame is the
// Bend Image quadtree; present() fills each solid region as one rectangle.
//
// Events are five words (kind, a, b, c, d):
//   0 key (keysym, code point typed, mods, down)   1 button (x, y, button, down)
//   2 move (x, y)   3 wheel (x, y, dir)   4 size (w, h)   5 expose
//   6 quit   7 paste (text via Win.pasted)
// mods: 1 shift, 2 ctrl, 4 alt, 8 super.

#if defined(__linux__)

#include <dlfcn.h>
#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/Xatom.h>
#include <X11/keysym.h>

#define WIN_FNS(X) \
  X(XOpenDisplay, Display*, (const char*)) \
  X(XCloseDisplay, int, (Display*)) \
  X(XCreateSimpleWindow, Window, (Display*, Window, int, int, unsigned, unsigned, unsigned, unsigned long, unsigned long)) \
  X(XInternAtom, Atom, (Display*, const char*, Bool)) \
  X(XSetWMProtocols, Status, (Display*, Window, Atom*, int)) \
  X(XStoreName, int, (Display*, Window, const char*)) \
  X(XSelectInput, int, (Display*, Window, long)) \
  X(XMapRaised, int, (Display*, Window)) \
  X(XFlush, int, (Display*)) \
  X(XPending, int, (Display*)) \
  X(XEventsQueued, int, (Display*, int)) \
  X(XNextEvent, int, (Display*, XEvent*)) \
  X(XLookupString, int, (XKeyEvent*, char*, int, KeySym*, XComposeStatus*)) \
  X(XCreateImage, XImage*, (Display*, Visual*, unsigned, int, int, char*, unsigned, unsigned, int, int)) \
  X(XPutImage, int, (Display*, Drawable, GC, XImage*, int, int, int, int, unsigned, unsigned)) \
  X(XSetSelectionOwner, int, (Display*, Atom, Window, Time)) \
  X(XConvertSelection, int, (Display*, Atom, Atom, Atom, Window, Time)) \
  X(XGetWindowProperty, int, (Display*, Window, Atom, long, long, Bool, Atom, Atom*, int*, unsigned long*, unsigned long*, unsigned char**)) \
  X(XChangeProperty, int, (Display*, Window, Atom, Atom, int, int, const unsigned char*, int)) \
  X(XSendEvent, Status, (Display*, Window, Bool, long, XEvent*)) \
  X(XFree, int, (void*)) \
  X(XDeleteProperty, int, (Display*, Window, Atom))

#define WIN_PTR(name, ret, args) static ret (*x_##name) args;
WIN_FNS(WIN_PTR)

static int win_load(void) {
  static int state = 0;
  if (state != 0) {
    return state > 0;
  }
  void* lib = dlopen("libX11.so.6", RTLD_NOW | RTLD_LOCAL);
  state = -1;
  if (lib == NULL) {
    return 0;
  }
#define WIN_SYM(name, ret, args) \
  if ((x_##name = (ret (*) args)dlsym(lib, #name)) == NULL) { return 0; }
  WIN_FNS(WIN_SYM)
  state = 1;
  return 1;
}

typedef struct {
  Display*  dpy;
  Window    win;
  Atom      del, clip, utf8, targets, prop;
  XImage*   img;
  u32       w, h;
  u32       n, cap;
  u32*      evs;
  char*     copy;
  u64       copy_len;
  char*     paste;
  u64       paste_len;
} AppWin;

static void win_push(AppWin* a, u32 kind, u32 p, u32 q, u32 r, u32 s) {
  if (a->n == a->cap) {
    a->cap = a->cap == 0 ? 64 : a->cap * 2;
    a->evs = io_mem(realloc(a->evs, (size_t)a->cap * 20));
  }
  u32 ev[5] = { kind, p, q, r, s };
  memcpy(a->evs + (size_t)a->n * 5, ev, sizeof ev);
  a->n += 1;
}

static u32 win_mods(unsigned state) {
  return (state & ShiftMask ? 1u : 0) | (state & ControlMask ? 2u : 0)
    | (state & Mod1Mask ? 4u : 0) | (state & Mod4Mask ? 8u : 0);
}

// the code point a key types, or 0 (keysyms name Latin-1 directly and
// the rest of Unicode as 0x01000000 + code point)
static u32 win_text(XKeyEvent* ev, KeySym* sym) {
  char buf[16];
  XKeyEvent copy = *ev;
  copy.state &= ~(ControlMask | Mod1Mask | Mod4Mask);
  int n = x_XLookupString(&copy, buf, sizeof buf, sym, NULL);
  KeySym ks = *sym;
  if (ks >= 0x20 && ks <= 0xff) {
    return (u32)ks;
  }
  if (ks >= 0x01000100 && ks <= 0x0110ffff) {
    return (u32)(ks - 0x01000000);
  }
  if (n == 1 && (unsigned char)buf[0] >= 32 && buf[0] != 127) {
    return (unsigned char)buf[0];
  }
  return 0;
}

static void win_answer(AppWin* a, XSelectionRequestEvent* rq) {
  XEvent ev;
  memset(&ev, 0, sizeof ev);
  ev.xselection.type      = SelectionNotify;
  ev.xselection.requestor = rq->requestor;
  ev.xselection.selection = rq->selection;
  ev.xselection.target    = rq->target;
  ev.xselection.time      = rq->time;
  ev.xselection.property  = None;
  if (rq->target == a->targets) {
    Atom ok[2] = { a->utf8, XA_STRING };
    x_XChangeProperty(a->dpy, rq->requestor, rq->property, XA_ATOM, 32,
      PropModeReplace, (unsigned char*)ok, 2);
    ev.xselection.property = rq->property;
  } else if ((rq->target == a->utf8 || rq->target == XA_STRING) && a->copy) {
    x_XChangeProperty(a->dpy, rq->requestor, rq->property, rq->target, 8,
      PropModeReplace, (unsigned char*)a->copy, (int)a->copy_len);
    ev.xselection.property = rq->property;
  }
  x_XSendEvent(a->dpy, rq->requestor, False, 0, &ev);
}

static void win_pasted(AppWin* a) {
  Atom type;
  int fmt;
  unsigned long n = 0, left = 0;
  unsigned char* data = NULL;
  if (x_XGetWindowProperty(a->dpy, a->win, a->prop, 0, 1 << 24, True,
    AnyPropertyType, &type, &fmt, &n, &left, &data) == Success && data) {
    free(a->paste);
    a->paste = io_mem(malloc(n + 1));
    memcpy(a->paste, data, n);
    a->paste_len = n;
    x_XFree(data);
    win_push(a, 7, 0, 0, 0, 0);
  }
}

static void win_pump(AppWin* a) {
  while (x_XPending(a->dpy) > 0) {
    XEvent ev;
    x_XNextEvent(a->dpy, &ev);
    switch (ev.type) {
      case KeyPress:
      case KeyRelease: {
        KeySym sym = 0;
        u32 text = win_text(&ev.xkey, &sym);
        win_push(a, 0, (u32)sym, ev.type == KeyPress ? text : 0,
          win_mods(ev.xkey.state), ev.type == KeyPress);
        break;
      }
      case ButtonPress:
      case ButtonRelease: {
        u32 b = ev.xbutton.button;
        u32 x = ev.xbutton.x < 0 ? 0 : (u32)ev.xbutton.x;
        u32 y = ev.xbutton.y < 0 ? 0 : (u32)ev.xbutton.y;
        if (b >= 4 && b <= 7) {
          if (ev.type == ButtonPress) {
            win_push(a, 3, x, y, b - 4, 0);
          }
        } else {
          win_push(a, 1, x, y, b, ev.type == ButtonPress);
        }
        break;
      }
      case MotionNotify:
        win_push(a, 2, ev.xmotion.x < 0 ? 0 : (u32)ev.xmotion.x,
          ev.xmotion.y < 0 ? 0 : (u32)ev.xmotion.y, 0, 0);
        break;
      case ConfigureNotify:
        if ((u32)ev.xconfigure.width != a->w || (u32)ev.xconfigure.height != a->h) {
          a->w = (u32)ev.xconfigure.width;
          a->h = (u32)ev.xconfigure.height;
          win_push(a, 4, a->w, a->h, 0, 0);
        }
        break;
      case Expose:
        if (ev.xexpose.count == 0) {
          win_push(a, 5, 0, 0, 0, 0);
        }
        break;
      case ClientMessage:
        if ((Atom)ev.xclient.data.l[0] == a->del) {
          win_push(a, 6, 0, 0, 0, 0);
        }
        break;
      case SelectionRequest:
        win_answer(a, &ev.xselectionrequest);
        break;
      case SelectionNotify:
        if (ev.xselection.property != None) {
          win_pasted(a);
        }
        break;
    }
  }
}

// Any Xlib call off the pump (XPutImage, XFlush...) may read waiting
// input into Xlib's own queue; the pump sleeps on the socket, which is
// then empty, so those events would wait for the next one to arrive (a
// key typed would show only on the key after it). After such a call,
// queued events make the window send itself a no-op ClientMessage: the
// socket wakes the pump, which drains the queue.
static void win_nudge(AppWin* a) {
  if (x_XEventsQueued(a->dpy, QueuedAlready) == 0) {
    return;
  }
  XEvent ev;
  memset(&ev, 0, sizeof ev);
  ev.xclient.type = ClientMessage;
  ev.xclient.window = a->win;
  ev.xclient.message_type = a->prop;
  ev.xclient.format = 32;
  x_XSendEvent(a->dpy, a->win, False, NoEventMask, &ev);
  x_XFlush(a->dpy);
}

// the pending events as a flat list of words, five per event (kind, a,
// b, c, d); Bend's Win.decode turns them into WinEv (a module's
// constructor ids depend on its path, so C only speaks words)
#ifdef CID_WIN_WORDS
static Term win_list(Env e, AppWin* a) {
  Term list = term_pak(CID_NIL, 0);
  for (u64 i = (u64)a->n * 5; i > 0;) {
    i -= 1;
    list = io_node(e, CID_CON, (Term)a->evs[i], list);
  }
  a->n = 0;
  return list;
}
#endif

#ifdef CID_WIN_OPEN

Term win_open_run(Env e, Term* f, IoWork* w) {
  u64 n = 0;
  char* title = io_cstr(e, f[0], &n);
  u32 ww = (u32)f[1], hh = (u32)f[2];
  const char* why = NULL;
  int code = 0;
  AppWin* a = NULL;
  Display* dpy = NULL;
  if (!win_load()) {
    code = ENOTSUP;
    why = "the window needs libX11 (install libx11-6)";
  } else if ((dpy = x_XOpenDisplay(NULL)) == NULL) {
    code = ENOTSUP;
    why = "no display: run Backplane from a desktop session, or use `backplane serve`";
  } else {
    int scr = DefaultScreen(dpy);
    a = io_mem(calloc(1, sizeof *a));
    a->dpy = dpy;
    a->w = ww;
    a->h = hh;
    a->win = x_XCreateSimpleWindow(dpy, RootWindow(dpy, scr), 0, 0, ww, hh, 0, 0,
      BlackPixel(dpy, scr));
    a->del     = x_XInternAtom(dpy, "WM_DELETE_WINDOW", False);
    a->clip    = x_XInternAtom(dpy, "CLIPBOARD", False);
    a->utf8    = x_XInternAtom(dpy, "UTF8_STRING", False);
    a->targets = x_XInternAtom(dpy, "TARGETS", False);
    a->prop    = x_XInternAtom(dpy, "BACKPLANE_PASTE", False);
    x_XSetWMProtocols(dpy, a->win, &a->del, 1);
    x_XStoreName(dpy, a->win, title);
    x_XSelectInput(dpy, a->win, KeyPressMask | KeyReleaseMask | ButtonPressMask
      | ButtonReleaseMask | PointerMotionMask | StructureNotifyMask | ExposureMask);
    x_XMapRaised(dpy, a->win);
    x_XFlush(dpy);
  }
  free(title);
  if (code) {
    return io_fail(e, code, why);
  }
  return io_done(e, io_hand((intptr_t)a));
}

static void __attribute__((constructor)) win_open_use(void) {
  io_eff(CID_WIN_OPEN, win_open_run, 0);
}

#endif

#ifdef CID_WIN_WORDS

static Term win_words_more(Env e, IoWork* w) {
  AppWin* a = (AppWin*)w->hand;
  win_pump(a);
  if (a->n == 0) {
    // the nudge can still lose a race with the presenting thread (an event
    // read into Xlib's queue after it looked); a short deadline re-checks
    // the queue, so no key waits for the next one to show
    return io_wait_on(w, ConnectionNumber(a->dpy), POLLIN, io_tick() + 30000000ull, win_words_more);
  }
  return io_tup(e, io_hand(w->hand), win_list(e, a));
}

// the events since the last call; waits (parked) until there is one
Term win_words_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  return win_words_more(e, w);
}

static void __attribute__((constructor)) win_words_use(void) {
  io_eff(CID_WIN_WORDS, win_words_run, 0);
}

#endif

#ifdef CID_WIN_PRESENT

// fill the part of an n x n region at (x, y) that lies in the w x h frame
static void win_fill(Corpus H, u32* pix, u32 w, u32 h, Term t, u32 x, u32 y, u32 n) {
  if (x >= w || y >= h) {
    return;
  }
  if (term_tag(t) == TAG_CTR && n > 1) {
    Loc l = term_rfc(t) ? H[term_loc(t)] >> 24 : term_loc(t);
    u32 m = n / 2;
    win_fill(H, pix, w, h, H[l + 0], x, y, m);
    win_fill(H, pix, w, h, H[l + 1], x + m, y, m);
    win_fill(H, pix, w, h, H[l + 2], x, y + m, m);
    win_fill(H, pix, w, h, H[l + 3], x + m, y + m, m);
    return;
  }
  while (term_tag(t) == TAG_CTR) {
    Loc l = term_rfc(t) ? H[term_loc(t)] >> 24 : term_loc(t);
    t = H[l];
  }
  u32 c  = (u32)term_loc(t) & 0xFFFFFF;
  u32 x1 = x + n < w ? x + n : w;
  u32 y1 = y + n < h ? y + n : h;
  for (u32 yy = y; yy < y1; yy += 1) {
    u32* row = pix + (size_t)yy * w;
    for (u32 xx = x; xx < x1; xx += 1) {
      row[xx] = c;
    }
  }
}

// BACKPLANE_SNAP=<path>: every presented frame is also written there as
// a PPM (tests and bug reports; off unless set)
static void win_snap(AppWin* a) {
  const char* path = getenv("BACKPLANE_SNAP");
  if (path == NULL || *path == 0) {
    return;
  }
  FILE* out = fopen(path, "wb");
  if (out == NULL) {
    return;
  }
  fprintf(out, "P6\n%u %u\n255\n", a->w, a->h);
  u32* pix = (u32*)a->img->data;
  for (u64 i = 0; i < (u64)a->w * a->h; i += 1) {
    unsigned char rgb[3] = { (pix[i] >> 16) & 255, (pix[i] >> 8) & 255, pix[i] & 255 };
    fwrite(rgb, 1, 3, out);
  }
  fclose(out);
}

Term win_present_run(Env e, Term* f, IoWork* w) {
  AppWin* a = (AppWin*)io_hand_v(f[0]);
  Term image = f[1];
  io_sync();
  if (a->img == NULL || (u32)a->img->width != a->w || (u32)a->img->height != a->h) {
    if (a->img) {
      XDestroyImage(a->img);
    }
    int scr = DefaultScreen(a->dpy);
    a->img = x_XCreateImage(a->dpy, DefaultVisual(a->dpy, scr), DefaultDepth(a->dpy, scr),
      ZPixmap, 0, io_mem(calloc((size_t)a->w * a->h, 4)), a->w, a->h, 32, (int)a->w * 4);
    a->img->byte_order = LSBFirst;
  }
  u32 n = 1;
  while (n < a->w || n < a->h) {
    n *= 2;
  }
  win_fill(e.mem, (u32*)a->img->data, a->w, a->h, image, 0, 0, n);
  x_XPutImage(a->dpy, a->win, DefaultGC(a->dpy, DefaultScreen(a->dpy)), a->img,
    0, 0, 0, 0, a->w, a->h);
  x_XFlush(a->dpy);
  win_nudge(a);
  win_snap(a);
  return io_tup(e, f[0], image);
}

static void __attribute__((constructor)) win_present_use(void) {
  io_eff(CID_WIN_PRESENT, win_present_run, 0);
}

#endif

#ifdef CID_WIN_COPY

// own the clipboard with this text
Term win_copy_run(Env e, Term* f, IoWork* w) {
  AppWin* a = (AppWin*)io_hand_v(f[0]);
  free(a->copy);
  a->copy = io_cstr(e, f[1], &a->copy_len);
  x_XSetSelectionOwner(a->dpy, a->clip, a->win, CurrentTime);
  x_XFlush(a->dpy);
  win_nudge(a);
  return f[0];
}

static void __attribute__((constructor)) win_copy_use(void) {
  io_eff(CID_WIN_COPY, win_copy_run, 0);
}

#endif

#ifdef CID_WIN_PASTE

// ask for the clipboard; it arrives later as WPaste
Term win_paste_run(Env e, Term* f, IoWork* w) {
  AppWin* a = (AppWin*)io_hand_v(f[0]);
  if (a->copy != NULL) {
    free(a->paste);
    a->paste = io_mem(malloc(a->copy_len + 1));
    memcpy(a->paste, a->copy, a->copy_len);
    a->paste_len = a->copy_len;
    win_push(a, 7, 0, 0, 0, 0);
  } else {
    x_XConvertSelection(a->dpy, a->clip, a->utf8, a->prop, a->win, CurrentTime);
    x_XFlush(a->dpy);
    win_nudge(a);
  }
  return f[0];
}

static void __attribute__((constructor)) win_paste_use(void) {
  io_eff(CID_WIN_PASTE, win_paste_run, 0);
}

#endif

#ifdef CID_WIN_PASTED

// the text of the last paste event
Term win_pasted_run(Env e, Term* f, IoWork* w) {
  AppWin* a = (AppWin*)io_hand_v(f[0]);
  return io_tup(e, f[0], io_str(e, a->paste ? a->paste : "", a->paste ? a->paste_len : 0));
}

static void __attribute__((constructor)) win_pasted_use(void) {
  io_eff(CID_WIN_PASTED, win_pasted_run, 0);
}

#endif

#ifdef CID_WIN_SIZE

Term win_size_run(Env e, Term* f, IoWork* w) {
  AppWin* a = (AppWin*)io_hand_v(f[0]);
  return io_tup(e, f[0], io_tup(e, (Term)a->w, (Term)a->h));
}

static void __attribute__((constructor)) win_size_use(void) {
  io_eff(CID_WIN_SIZE, win_size_run, 0);
}

#endif

#ifdef CID_WIN_TWIN

// a second handle on the same window: one computation waits for events
// while another presents frames
Term win_twin_run(Env e, Term* f, IoWork* w) {
  return io_tup(e, f[0], f[0]);
}

static void __attribute__((constructor)) win_twin_use(void) {
  io_eff(CID_WIN_TWIN, win_twin_run, 0);
}

#endif

#ifdef CID_WIN_TITLE

Term win_title_run(Env e, Term* f, IoWork* w) {
  AppWin* a = (AppWin*)io_hand_v(f[0]);
  u64 n = 0;
  char* t = io_cstr(e, f[1], &n);
  x_XStoreName(a->dpy, a->win, t);
  x_XFlush(a->dpy);
  win_nudge(a);
  free(t);
  return f[0];
}

static void __attribute__((constructor)) win_title_use(void) {
  io_eff(CID_WIN_TITLE, win_title_run, 0);
}

#endif

#else

// No window on this platform yet (macOS gets its own AppKit twin).

#ifdef CID_WIN_OPEN
Term win_open_run(Env e, Term* f, IoWork* w) {
  return io_fail(e, ENOTSUP, "the native window is Linux-only for now; run `backplane serve`");
}
static void __attribute__((constructor)) win_open_use(void) {
  io_eff(CID_WIN_OPEN, win_open_run, 0);
}
#endif

#endif
