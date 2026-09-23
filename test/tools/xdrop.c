// xdrop: act as an XDND drag source over the Backplane window (tests only).
//   xdrop hover X Y         drag a file over (X, Y) and stay there
//   xdrop leave             the drag leaves again
//   xdrop drop X Y URI...   drag the URIs (text/uri-list) to (X, Y) and drop
// Prints the target's XdndStatus accept bit and, for a drop, XdndFinished.
// XPOKE_WIN=<id> picks one window when several Backplanes share a display.
// Build: cc -I<x11 include> test/tools/xdrop.c -o build/xdrop -lX11
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static Window find(Display* d, Window w, const char* name) {
  char* n = NULL;
  if (XFetchName(d, w, &n) && n) {
    int hit = strcmp(n, name) == 0;
    XFree(n);
    if (hit) return w;
  }
  Window root, parent, *kids = NULL;
  unsigned nk = 0;
  if (!XQueryTree(d, w, &root, &parent, &kids, &nk)) return 0;
  Window got = 0;
  for (unsigned i = 0; i < nk && !got; i++) got = find(d, kids[i], name);
  if (kids) XFree(kids);
  return got;
}

static Display* d;
static Window src, dst;

static Atom A(const char* n) { return XInternAtom(d, n, False); }

static void msg(const char* type, long l1, long l2, long l3, long l4) {
  XEvent e = { 0 };
  e.xclient.type = ClientMessage;
  e.xclient.window = dst;
  e.xclient.message_type = A(type);
  e.xclient.format = 32;
  e.xclient.data.l[0] = (long)src;
  e.xclient.data.l[1] = l1;
  e.xclient.data.l[2] = l2;
  e.xclient.data.l[3] = l3;
  e.xclient.data.l[4] = l4;
  XSendEvent(d, dst, False, NoEventMask, &e);
  XFlush(d);
}

// wait up to two seconds for a client message of this type, answering
// selection requests for the uri-list meanwhile
static int wait_for(const char* type, const char* uris, XClientMessageEvent* out) {
  Atom want = A(type);
  time_t end = time(NULL) + 2;
  while (time(NULL) <= end) {
    while (XPending(d)) {
      XEvent e;
      XNextEvent(d, &e);
      if (e.type == ClientMessage && e.xclient.message_type == want) {
        *out = e.xclient;
        return 1;
      }
      if (e.type == SelectionRequest) {
        XSelectionRequestEvent* rq = &e.xselectionrequest;
        XEvent r = { 0 };
        r.xselection.type = SelectionNotify;
        r.xselection.requestor = rq->requestor;
        r.xselection.selection = rq->selection;
        r.xselection.target = rq->target;
        r.xselection.time = rq->time;
        r.xselection.property = None;
        if (rq->target == A("text/uri-list") && uris) {
          XChangeProperty(d, rq->requestor, rq->property, rq->target, 8, PropModeReplace,
            (const unsigned char*)uris, (int)strlen(uris));
          r.xselection.property = rq->property;
        }
        XSendEvent(d, rq->requestor, False, 0, &r);
        XFlush(d);
      }
    }
    struct timespec ts = { 0, 10000000 };
    nanosleep(&ts, NULL);
  }
  return 0;
}

static int over(int x, int y) {
  msg("XdndEnter", 5L << 24, (long)A("text/uri-list"), 0, 0);
  Window child;
  int rx = 0, ry = 0;
  XTranslateCoordinates(d, dst, DefaultRootWindow(d), x, y, &rx, &ry, &child);
  msg("XdndPosition", 0, ((long)rx << 16) | ry, CurrentTime, (long)A("XdndActionCopy"));
  XClientMessageEvent st;
  if (!wait_for("XdndStatus", NULL, &st)) {
    printf("no status\n");
    return 0;
  }
  printf("status accept=%ld\n", st.data.l[1] & 1);
  return (int)(st.data.l[1] & 1);
}

int main(int argc, char** argv) {
  if (argc < 2) return 2;
  d = XOpenDisplay(NULL);
  if (!d) { fprintf(stderr, "no display\n"); return 1; }
  const char* pick = getenv("XPOKE_WIN");
  dst = pick && *pick ? (Window)strtoul(pick, NULL, 0) : find(d, DefaultRootWindow(d), "Backplane");
  if (!dst) { fprintf(stderr, "no Backplane window\n"); return 1; }
  src = XCreateSimpleWindow(d, DefaultRootWindow(d), 0, 0, 1, 1, 0, 0, 0);
  if (!strcmp(argv[1], "hover") && argc == 4) {
    return over(atoi(argv[2]), atoi(argv[3])) ? 0 : 1;
  }
  if (!strcmp(argv[1], "leave")) {
    msg("XdndLeave", 0, 0, 0, 0);
    return 0;
  }
  if (!strcmp(argv[1], "drop") && argc >= 5) {
    size_t n = 1;
    for (int i = 4; i < argc; i++) n += strlen(argv[i]) + 2;
    char* uris = calloc(n, 1);
    for (int i = 4; i < argc; i++) { strcat(uris, argv[i]); strcat(uris, "\r\n"); }
    XSetSelectionOwner(d, A("XdndSelection"), src, CurrentTime);
    if (!over(atoi(argv[2]), atoi(argv[3]))) return 1;
    msg("XdndDrop", 0, CurrentTime, 0, 0);
    XClientMessageEvent fin;
    if (!wait_for("XdndFinished", uris, &fin)) { printf("no finished\n"); return 1; }
    printf("finished accepted=%ld\n", fin.data.l[1] & 1);
    return 0;
  }
  return 2;
}
