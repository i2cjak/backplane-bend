import Base
import ./check.bend as C
import ../src/core/sha1.bend as S
import ../src/core/utf8.bend as U

def hex.d(+n: U32) -> Char:
  Chr{U32.add(n, Bool.pick(U32, U32.is_lt(n, 10), 48, 87))}

def hex(bs: List<&2, U32>) -> String:
  match bs:
    case Nil{}:
      ""
    case +b <> t:
      SCon{hex.d(U32.shrn(b, 4n)), SCon{hex.d(U32.and(b, 15)), hex(t)}}

def accept(key: String) -> String:
  S.B64.encode(S.Sha1.hash(U.Utf8.encode(key ++ "258EAFA5-E914-47DA-95CA-C5AB0DC85B11")))

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("sha1 abc", hex(S.Sha1.hash(U.Utf8.encode("abc"))), "a9993e364706816aba3e25717850c26c9cd0d89d")
    C.Check.str("sha1 empty", hex(S.Sha1.hash(Nil{})), "da39a3ee5e6b4b0d3255bfef95601890afd80709")
    C.Check.str("sha1 56", hex(S.Sha1.hash(U.Utf8.encode("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"))), "84983e441c3bd26ebaae4aa1f95129e5e54670f1")
    C.Check.str("b64 hello", S.B64.encode(U.Utf8.encode("hello")), "aGVsbG8=")
    C.Check.str("b64 hi", S.B64.encode(U.Utf8.encode("hi?>")), "aGk/Pg==")
    C.Check.str("ws accept", accept("dGhlIHNhbXBsZSBub25jZQ=="), "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    C.Check.str("utf8 rt", U.Utf8.decode(U.Utf8.encode("héllo ✓ 𝄞")), "héllo ✓ 𝄞")
    C.Check.str("utf8 bad", U.Utf8.decode([104, 255, 105]), "h\u{FFFD}i")
