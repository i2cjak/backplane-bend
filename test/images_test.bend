import Base
import ./check.bend as C
import ../src/core/images.bend as I
import ../src/core/attach.bend as AT

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("bare path", String.join(I.Img.paths("Rendered to /tmp/board-top.png."), "|"), "/tmp/board-top.png")
    C.Check.str("backticks and markdown", String.join(I.Img.paths("See `/tmp/a.PNG` and ![top](~/renders/b.jpg), not /tmp/c.txt"), "|"), "/tmp/a.PNG|~/renders/b.jpg")
    C.Check.str("each once", String.join(I.Img.paths("/tmp/a.png then /tmp/a.png again"), "|"), "/tmp/a.png")
    C.Check.str("relative is not shown", String.join(I.Img.paths("out/a.png and a.png"), "|"), "")
    C.Check.str("file uri", String.join(I.Img.paths("file:///tmp/x.webp"), "|"), "/tmp/x.webp")
    C.Check.str("url", I.Img.url("/tmp/my board (1).png"), "/img?path=/tmp/my%20board%20%281%29.png")
    C.Check.str("url round trip", AT.Att.from_uri("file://" ++ String.drop(I.Img.url("/tmp/résumé 2.png"), 10n)), "/tmp/résumé 2.png")
