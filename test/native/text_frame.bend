import Base
import ../../src/gfx/draw.bend as D
import ../../src/gfx/raster.bend as R
import ../../src/gfx/text.bend as X
import ../../src/app/theme.bend as T

# A mock of the Backplane sidebar, a chat exchange and a code block in
# system fonts, written to /tmp/text.ppm (1400 x 900) with timings.
#   bend test/native/text_frame.bend -o build/text_frame && build/text_frame
#   scripts/ppm-to-png.py /tmp/text.ppm /tmp/text.png

# the faces the reference web app asks for: --font-sans for the interface,
# --font-mono for code
type Fs is Data:
  Fs{title: X.Face, meta: X.Face, body: X.Face, bold: X.Face, code: X.Face, prop: X.Face, bmp: X.Face}

def Sans() -> List<&2, String>:
  ["Berkeley Mono", "monospace"]

def SansBold() -> List<&2, String>:
  ["Berkeley Mono:weight=bold", "monospace:weight=bold"]

def Mono() -> List<&2, String>:
  ["Berkeley Mono", "SF Mono", "SFMono-Regular", "Menlo", "Consolas", "Liberation Mono", "monospace"]

def Para() -> String:
  "The native window now draws text with the system's fonts. Glyphs come from FreeType, anti-aliased in grayscale with light hinting, and are cached in Bend state, so a frame only asks the effect for glyphs it has never seen. Lines wrap by measured pixel width — long identifiers like Region.keep.op_with_a_very_long_name_indeed break between characters."

def Para2() -> String:
  "Build it natively and render a frame:"

def User() -> String:
  "Can we get real fonts in the native UI? The 8x16 bitmap looks rough next to the web app."

def Code() -> List<&2, String>:
  ["bend test/native/text_frame.bend -o build/text_frame",
   "./build/text_frame            # writes /tmp/text.ppm",
   "scripts/ppm-to-png.py /tmp/text.ppm /tmp/text.png",
   "",
   "def Text.width(+cache: Map<&2, TG>, +f: Face, s: String) -> U32:",
   "  Text.width.k(Face.ft(f), cache, f, s)  // {} [] () <> != -> => ~"]

def Prop() -> String:
  "Proportional faces wrap by measured width too: Wavy AVATAR kerning-free text, and a_very_long_identifier_that_cannot_fit breaks between characters."

def All() -> String:
  Para() ++ Para2() ++ User() ++ String.join(Code(), "\n") ++ "·…—→✓•"

def mix(+fg: U32, +bg: U32, +pct: U32) -> U32:
  R.Rgb.mix(fg, bg, ((pct * 255 : U32) / 100 : U32))

def lines(ls: List<&2, String>, +cache: Map<&2, X.TG>, +f: X.Face, +c: D.Clip, +x: U32, +y: U32, +lh: U32, +color: U32) -> List<&2, R.Op>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> t:
      List.append(&2, R.Op, X.Text.line(cache, f, l, c, x, y, lh, color), lines(t, cache, f, c, x, (y + lh : U32), lh, color))

type Row is Data:
  Row{title: String, ago: String, sel: Bool, dot: U32}

def row(r: Row, +cache: Map<&2, X.TG>, +fs: Fs, +y: U32) -> List<&2, R.Op>:
  match r fs:
    case Row{title, +ago, +sel, +dot} Fs{+ti, +me, _, _, _, _, _}:
      +c = {D.Clip{0, 0, 263, 900} : D.Clip}
      List.concat(&2, R.Op, [
        [D.Draw.disc(c, 21.0, U32.to_f32((y + 16 : U32)), 3.0, dot, 255)],
        X.Text.line(cache, ti, X.Text.fit(cache, ti, title, (252 - 32 - 10 - X.Text.width(cache, me, ago) : U32)), c, 32, (y + 6 : U32), 20, Bool.pick(U32, sel, T.Th.text(), mix(T.Th.text(), T.Th.panel(), 80))),
        X.Text.line(cache, me, ago, c, (252 - X.Text.width(cache, me, ago) : U32), (y + 8 : U32), 16, T.Th.faint()),
        Bool.pick(List<&2, R.Op>, sel, [D.Draw.rect(c, 6, y, 252, 32, T.Th.raise(), 255)], Nil{})])

def rows(rs: List<&2, Row>, +cache: Map<&2, X.TG>, +fs: Fs, +y: U32) -> List<&2, R.Op>:
  match rs:
    case Nil{}:
      Nil{}
    case r <> t:
      List.append(&2, R.Op, row(r, cache, fs, y), rows(t, cache, fs, (y + 32 : U32)))

def sidebar(+cache: Map<&2, X.TG>, +fs: Fs) -> List<&2, R.Op>:
  match fs:
    case Fs{+ti, +me, _, +bo, _, _, _}:
      +c = {D.Clip{0, 0, 263, 900} : D.Clip}
      List.concat(&2, R.Op, [
        [D.Draw.disc(c, 21.0, 26.0, 4.0, T.Th.ok(), 255)],
        X.Text.line(cache, bo, "Backplane", c, 32, 16, 20, T.Th.text()),
        X.Text.line(cache, me, "v0.4.2", c, (40 + X.Text.width(cache, bo, "Backplane") : U32), 18, 16, T.Th.faint()),
        X.Text.line(cache, me, "backplane", c, 16, 64, 16, T.Th.dim()),
        X.Text.line(cache, me, "+", c, 240, 64, 16, T.Th.dim()),
        rows([Row{"Port typography to FreeType", "now", True{}, T.Th.accent()},
              Row{"Board viewer: fade settled nets", "12m", False{}, T.Th.warn()},
              Row{"KiCad 9 schematic parser", "3h", False{}, T.Th.faint()},
              Row{"Tailscale pairing token", "2d", False{}, T.Th.faint()}], cache, fs, 88),
        X.Text.line(cache, me, "kistack", c, 16, 228, 16, T.Th.dim()),
        rows([Row{"STEP model importer", "5d", False{}, T.Th.faint()},
              Row{"Footprint pad inspector", "1w", False{}, T.Th.bad()}], cache, fs, 252),
        X.Text.line(cache, me, "Settings", c, 16, 868, 16, T.Th.dim()),
        [D.Draw.rect(c, 0, 52, 264, 1, T.Th.line(), 255), D.Draw.rect(D.Clip.all(), 263, 0, 1, 900, T.Th.line(), 255),
         D.Draw.rect(c, 0, 0, 264, 900, T.Th.panel(), 255)]])

def codeblock(+cache: Map<&2, X.TG>, +fs: Fs, +x: U32, +y: U32, +w: U32) -> List<&2, R.Op>:
  match fs:
    case Fs{_, +me, _, _, +co, _, _}:
      +c = {D.Clip{x, y, (x + w : U32), (y + 170 : U32)} : D.Clip}
      List.concat(&2, R.Op, [
        X.Text.line(cache, me, "bash", c, (x + 12 : U32), (y + 8 : U32), 16, mix(T.Th.text(), T.Th.code(), 72)),
        X.Text.line(cache, me, "Copy", c, (x + w - 12 - X.Text.width(cache, me, "Copy") : U32), (y + 8 : U32), 16, mix(T.Th.text(), T.Th.code(), 72)),
        lines(Code(), cache, co, c, (x + 12 : U32), (y + 36 : U32), 21, T.Th.text()),
        [D.Draw.rect(c, x, (y + 31 : U32), w, 1, T.Th.line(), 255)],
        D.Draw.frame(c, x, y, w, 170, T.Th.line()),
        [D.Draw.rect(c, x, y, w, 170, T.Th.code(), 255)]])

def chat(+cache: Map<&2, X.TG>, +fs: Fs) -> List<&2, R.Op>:
  match fs:
    case Fs{+ti, +me, +bo, _, _, +pr, +bm}:
      +c = {D.Clip{264, 0, 1400, 900} : D.Clip}
      +x = {340 : U32}
      +w = {760 : U32}
      +ul = X.Text.wrap(cache, bo, User(), 440)
      +uh = ((U32.from_nat(List.length(&2, String, ul)) * 23 : U32) + 20 : U32)
      +pl = X.Text.wrap(cache, bo, Para(), w)
      +py = (100 + uh + 28 : U32)
      +cy = (py + (U32.from_nat(List.length(&2, String, pl)) * 23 : U32) + 14 + 23 + 14 : U32)
      List.concat(&2, R.Op, [
        X.Text.line(cache, ti, "Port typography to FreeType", c, 288, 16, 20, T.Th.text()),
        X.Text.line(cache, me, "main", c, (300 + X.Text.width(cache, ti, "Port typography to FreeType") : U32), 18, 16, T.Th.dim()),
        [D.Draw.rect(c, 264, 52, 1136, 1, T.Th.line(), 255)],
        lines(ul, cache, bo, c, (x + w - 460 : U32), 110, 23, T.Th.text()),
        [D.Draw.rect(c, (x + w - 480 : U32), 100, 480, uh, T.Th.raise(), 255)],
        lines(pl, cache, bo, c, x, py, 23, mix(T.Th.text(), T.Th.bg(), 80)),
        X.Text.line(cache, bo, Para2(), c, x, (py + (U32.from_nat(List.length(&2, String, pl)) * 23 : U32) + 14 : U32), 23, mix(T.Th.text(), T.Th.bg(), 80)),
        codeblock(cache, fs, x, cy, w),
        lines(X.Text.wrap(cache, pr, Prop(), 220), cache, pr, c, 1136, 100, 20, mix(T.Th.text(), T.Th.bg(), 80)),
        X.Text.line(cache, bm, "fallback: Spleen 8x16", c, 1136, 300, 16, T.Th.dim()),
        X.Text.line(cache, bo, "Ask anything, @tag files/folders, or use / to show available commands", c, (x + 16 : U32), 784, 23, T.Th.faint()),
        X.Text.line(cache, me, "claude-opus · high", c, (x + 16 : U32), 830, 16, T.Th.dim()),
        D.Draw.frame(c, x, 768, w, 90, T.Th.line()),
        [D.Draw.rect(c, x, 768, w, 90, T.Th.panel(), 255)]])

def frame(+cache: Map<&2, X.TG>, +fs: Fs) -> List<&2, R.Op>:
  List.append(&2, R.Op, sidebar(cache, fs), chat(cache, fs))

def warm(fs: Fs, c: Map<&2, X.TG>) -> IO(Map<&2, X.TG>):
  match fs:
    case Fs{+ti, +me, +bo, +bb, +co, +pr, _}:
      do IO<Map<&2, X.TG>>:
        c1 : Map<&2, X.TG> <- X.Text.warm(c, ti)
        c2 : Map<&2, X.TG> <- X.Text.warm(c1, me)
        c3 : Map<&2, X.TG> <- X.Text.warm(c2, bo)
        c4 : Map<&2, X.TG> <- X.Text.warm(c3, bb)
        c5 : Map<&2, X.TG> <- X.Text.warm(c4, co)
        c6a : Map<&2, X.TG> <- X.Text.ensure(c5, bo, All())
        c6 : Map<&2, X.TG> <- X.Text.ensure(c6a, me, All())
        c7 : Map<&2, X.TG> <- X.Text.warm(c6, pr)
        c8 : Map<&2, X.TG> <- X.Text.ensure(c7, pr, Prop())
        X.Text.ensure(c8, co, All())

def bench(n: Nat, +cache: Map<&2, X.TG>, +f: X.Face, +acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+k:
      bench(k, cache, f, (acc + X.Text.width(cache, f, Para()) : U32))

def ms(+a: Nat, +b: Nat) -> String:
  Nat.show(Nat.sub(b, a)) ++ " ms"

def names(fs: Fs) -> String:
  match fs:
    case Fs{ti, _, _, bb, co, pr, bm}:
      "ui: " ++ X.Face.name(ti) ++ "\nbold: " ++ X.Face.name(bb) ++ "\ncode: " ++ X.Face.name(co) ++ "\nproportional: " ++ X.Face.name(pr) ++ "\nmissing family: " ++ X.Face.name(bm)

def main() -> IO(Unit):
  do IO<Unit>:
    t0 : Nat <- IO.now()
    +ti : X.Face <- X.Text.face(Sans(), 14)
    +me : X.Face <- X.Text.face(Sans(), 12)
    +bb : X.Face <- X.Text.face(SansBold(), 14)
    +co : X.Face <- X.Text.face(Mono(), 13)
    +pr : X.Face <- X.Text.face(["Inter", "sans-serif"], 14)
    +bm : X.Face <- X.Text.face(["No Such Font"], 14)
    +fs : Fs = Fs{ti, me, ti, bb, co, pr, bm}
    +t1 : Nat <- IO.now()
    +cache : Map<&2, X.TG> <- warm(fs, Map.new(&2, X.TG))
    +t2 : Nat <- IO.now()
    +wsum : U32 = bench(100n, cache, ti, 0)
    +t3 : Nat <- IO.now()
    +os : List<&2, R.Op> = frame(cache, fs)
    +nops : Nat = List.length(&2, R.Op, os)
    +t4 : Nat <- IO.now()
    +img : Image = R.Frame.render(1400, 900, os, T.Th.bg())
    +probe : U32 = R.Img.at(R.Frame.depth(1400, 900), img, 700, 450)
    +t5 : Nat <- IO.now()
    f : File <- IO.try(File, File.open("/tmp/text.ppm", "w"))
    r : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(f, D.Snap.ppm(img, 1400, 900))
    t6 : Nat <- IO.now()
    IO.print(names(fs))
    IO.print("faces: " ++ ms(t0, t1) ++ "\nwarm-up (5 faces, ASCII + extras): " ++ ms(t1, t2))
    IO.print("measure 100 x paragraph (" ++ U32.show((wsum / 100 : U32)) ++ " px): " ++ ms(t2, t3))
    IO.print("layout (" ++ Nat.show(nops) ++ " ops): " ++ ms(t3, t4) ++ "\nraster 1400x900: " ++ ms(t4, t5) ++ " (probe " ++ U32.show(probe) ++ ")\nppm: " ++ ms(t5, t6))
