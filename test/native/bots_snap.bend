import Base
import ../../src/core/client.bend as U
import ../../src/core/model.bend as M
import ../../src/app/nui.bend as N
import ../../src/app/layout.bend as L
import ../../src/app/bots.bend as BV
import ../../src/app/cats.bend as CA
import ../../src/app/theme.bend as T
import ../../src/gfx/raster.bend as R
import ../../src/gfx/draw.bend as D

# The bots' screens with no window: a made-up log (a project, four bots,
# two rooms, posts, memory, routines, webhooks, a space), each screen as a
# PPM in DIR (default /tmp): bots-<name>.ppm. Also times a cat frame.
#   scripts/build-app.sh test/native/bots_snap.bend build/bots_snap
#   build/bots_snap [DIR]

def at() -> Nat:
  1790000000n

def bot(+i: Nat, +name: String, +look: Nat, +persona: String) -> List<&2, M.Change>:
  [M.ThreadCreated{"bt" ++ Nat.show(i), "", name, M.Local{}, "", "", "claude", "", at()},
   M.BotSet{"b" ++ Nat.show(i), name, "bt" ++ Nat.show(i), look, persona, at()}]

def space() -> String:
  "{\"title\":\"Mochi's desk\",\"blocks\":[{\"type\":\"heading\",\"text\":\"Today\"},{\"type\":\"row\",\"blocks\":[{\"type\":\"stat\",\"label\":\"Open PRs\",\"value\":\"3\",\"hint\":\"2 need review\"},{\"type\":\"stat\",\"label\":\"Build\",\"value\":\"green\"},{\"type\":\"stat\",\"label\":\"Boards\",\"value\":\"12\",\"hint\":\"+2 this week\"}]},{\"type\":\"progress\",\"label\":\"Release 0.9\",\"value\":0.64},{\"type\":\"text\",\"text\":\"I watch the repo and the fab queue. Ask me for a summary any time.\"},{\"type\":\"list\",\"items\":[\"Review power board rev C\",\"Order stencils\",\"Reply to JLC about the panel\"]},{\"type\":\"kv\",\"rows\":[[\"Fab\",\"JLCPCB\"],[\"Next check\",\"09:00\"]]},{\"type\":\"table\",\"head\":[\"Board\",\"Rev\",\"State\"],\"rows\":[[\"power\",\"C\",\"fab\"],[\"sensor\",\"B\",\"layout\"]]},{\"type\":\"divider\"},{\"type\":\"row\",\"blocks\":[{\"type\":\"button\",\"label\":\"Summarize\",\"action\":\"summary\"},{\"type\":\"button\",\"label\":\"Check fab\",\"action\":\"fab\"}]},{\"type\":\"input\",\"label\":\"Ask Mochi\",\"action\":\"ask\",\"placeholder\":\"What should I look at?\"},{\"type\":\"badge\",\"text\":\"all good\",\"tone\":\"ok\"},{\"type\":\"code\",\"text\":\"make fab\\nmake check\"}]}"

def log() -> List<&2, M.Change>:
  List.concat(&2, M.Change, [
    [M.ProjectCreated{"p1", "board", "/tmp/board", at()}, M.ThreadCreated{"t0", "p1", "Power sequencing", M.Local{}, "", "", "claude", "", at()},
     M.MessagePosted{"t0", "m0", M.User{}, "Check the regulator's enable pin.", at()}],
    bot(0n, "Mochi", 3n, "Watches the repo and the fab queue."), bot(1n, "Biscuit", 20n, "Keeps the calendar."),
    bot(2n, "Tofu", 41n, "Reviews schematics."), bot(3n, "Pixel", 58n, "Draws renders."),
    [M.RoomSet{"r0", "general", "b0\nb1\nb2", at()}, M.RoomSet{"r1", "boards", "b1\nb3", at()},
     M.RoomPosted{"p0", "r0", "b0", "Fab queue is clear, the power board ships Friday.", 0n, Nat.add(at(), 10n)},
     M.RoomPosted{"p1", "r0", "b1", "Noted. I moved the design review to Thursday 10:00 so it lands before the ship date.", 1n, Nat.add(at(), 40n)},
     M.RoomPosted{"p2", "r0", "you", "Thanks both.", 0n, Nat.add(at(), 60n)},
     M.MemorySaved{"b0", "fab", "fact", "Boards go to JLCPCB; stencils from OSH Stencils.", "fab,vendors", at()},
     M.MemorySaved{"b0", "reviews", "pref", "Wants a summary of open PRs every morning, short, no emoji.", "", at()},
     M.RoutineSet{"o0", "b0", "Morning summary", "0 9 * * 1-5", "Summarize open PRs and the fab queue.", True{}, at()},
     M.RoutineSet{"o1", "b0", "Weekly cleanup", "@weekly", "Close stale branches.", False{}, at()},
     M.HookSet{"h0", "b0", "GitHub pushes", False{}, at()},
     M.SpaceSet{"b0", space(), at()}]])

def act.k(a: U.Act) -> U.Ui:
  match a:
    case U.Act{u, _}:
      u

def acts(ps: List<&2, String>, u: U.Ui) -> U.Ui:
  match ps:
    case Nil{}:
      u
    case +p <> t:
      acts(t, act.k(U.Ui.act(u, String.join(List.take(&2, String, String.split(p, '='), 1n), ""), String.join(List.drop(&2, String, String.split(p, '='), 1n), "="))))

def ops(o: L.Out) -> List<&2, R.Op>:
  match o:
    case L.Out{os, _}:
      os

def with_ms(n: N.Nui, +ms: Nat) -> N.Nui:
  match n:
    case N.Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, hi, _, vw}:
      N.Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, hi, ms, vw}

def with_focus(n: N.Nui, fo: String) -> N.Nui:
  match n:
    case N.Nui{u, w, h, mx, my, sd, sc, ca, _, pa, hi, ms, vw}:
      N.Nui{u, w, h, mx, my, sd, sc, ca, fo, pa, hi, ms, vw}

def info(u: U.Ui) -> U.Ui:
  U.Ui.info_set(U.Ui.info_set(u, "shot.ok.b0", "shot:b0:3"), "img:shot:b0:3", "1280x800")

def base() -> U.Ui:
  info(act.k(U.Ui.act(U.Ui.fold(log(), U.Ui.init(Nat.add(at(), 100n))), "select", "t0")))

def write.k(r: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, _) = r
  File.close(f)

def write(+path: String, +img: Image) -> IO(Unit):
  do IO<Unit>:
    g : File <- IO.try(File, File.open(path, "w"))
    w : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(g, D.Snap.ppm(img, 1400, 900))
    write.k(w)

# a screen after the steps ("action=value" apart by ;), with a field focused
def shot(+ty: L.Ty, +dir: String, +name: String, +steps: String, +focus: String) -> IO(Unit):
  +u = acts(String.split(steps, ';'), base())
  +n = with_focus(with_ms(N.Nui.init(u, 1400, 900), 1234n), focus)
  +os = ops(BV.Bv.frame(ty, L.Lay.memo(ty, n, L.TL.memo.none()), BV.Bv.warm(u, CA.Cats.none(), 1234n), n))
  do IO<Unit>:
    write(dir ++ "/bots-" ++ name ++ ".ppm", R.Frame.render(1400, 900, os, T.Th.bg()))
    IO.print(dir ++ "/bots-" ++ name ++ ".ppm")

def arg(xs: List<&2, String>, +i: Nat, d: String) -> String:
  match xs i:
    case Nil{} _:
      d
    case h <> _ 0n:
      h
    case _ <> t 1n+k:
      arg(t, k, d)

def copy(xs: List<&1, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case h <> t:
      String.append(h, "") <> copy(t)

def sep() -> String:
  SCon{Chr{31}, SNil{}}

# frames of one cat, timed: pose and ops, then the frame's layout
def bench(+k: Nat, +ty: L.Ty, +cats: Map<&2, CA.CatF>, +n: N.Nui, +acc: Nat) -> Nat:
  match k:
    case 0n:
      acc
    case 1n+j:
      bench(j, ty, cats, n, Nat.add(acc, List.length(&2, R.Op, ops(BV.Bv.frame(ty, L.TL.memo.none(), cats, with_ms(n, Nat.mul(j, 33n)))))))

def cats1(+k: Nat, +cats: Map<&2, CA.CatF>, +acc: Nat) -> Nat:
  match k:
    case 0n:
      acc
    case 1n+j:
      cats1(j, cats, Nat.add(acc, List.length(&2, R.Op, CA.Cats.draw(cats, 3n, "idle", Nat.mul(j, 33n), D.Clip.all(), 14, 40, 28))))

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    +as : List<&2, String> = copy(args)
    +dir : String = arg(as, 0n, "/tmp")
    +ty : L.Ty <- L.Ty.load()
    shot(ty, dir, "side", "", "composer")
    shot(ty, dir, "bform", "bot-new=;bfield=name" ++ sep() ++ "Nori;bfield=persona" ++ sep() ++ "Keeps an eye on the fab queue and the parts on order.", N.Fld.id("name", "bot-create", ""))
    shot(ty, dir, "chat", "bot=b0", "composer")
    shot(ty, dir, "space", "bot=b0;bot-tab=space", "")
    shot(ty, dir, "browser", "bot=b0;bot-tab=browser", "")
    shot(ty, dir, "memory", "bot=b0;bot-tab=memory", "")
    shot(ty, dir, "routines", "bot=b0;bot-tab=routines", "")
    shot(ty, dir, "hooks", "bot=b0;bot-tab=hooks", "")
    shot(ty, dir, "settings", "bot=b0;bot-tab=settings;bfield=persona" ++ sep() ++ "Watches the repo and the fab queue.", "")
    shot(ty, dir, "room", "room=r0", N.Fld.id("rpost", "room-post", ""))
    shot(ty, dir, "rform", "room-new=;bfield=rname" ++ sep() ++ "night shift;room-pick=b0;room-pick=b2", "")
    +u : U.Ui = base()
    +cats : Map<&2, CA.CatF> = BV.Bv.warm(u, CA.Cats.none(), 1234n)
    +n : N.Nui = N.Nui.init(u, 1400, 900)
    +t0 : Nat <- IO.now()
    +c : Nat = cats1(100n, cats, 0n)
    +t1 : Nat <- IO.now()
    +k : Nat = bench(30n, ty, cats, n, 0n)
    +t2 : Nat <- IO.now()
    IO.print("one 28 px cat posed and drawn: " ++ Nat.show(Nat.div(Nat.mul(Nat.sub(t1, t0), 10n), 100n)) ++ "/10 ms (" ++ Nat.show(c) ++ " ops); frame layout with 4 cats: " ++ Nat.show(Nat.div(Nat.sub(t2, t1), 30n)) ++ " ms (" ++ Nat.show(k) ++ ")")
