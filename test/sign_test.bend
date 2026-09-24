import Base
import ./check.bend as C
import ../src/core/sha256.bend as S
import ../src/core/sign.bend as G
import ../src/core/utf8.bend as U

def rep(n: Nat, +b: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+m:
      rep(m, b, b <> acc)

def upto(+n: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+m:
      upto(m, U32.from_nat(1n+m) <> acc)

def yn(b: Bool) -> String:
  match b:
    case True{}:
      "yes"
    case False{}:
      "no"

def sha(s: String) -> String:
  S.Hex.encode(S.Sha256.hash(U.Utf8.encode(s)))

def mac(k: List<&2, U32>, m: List<&2, U32>) -> String:
  S.Hex.encode(S.Hmac.sha256(k, m))

def dec(m: Maybe<&2, List<&2, U32>>) -> String:
  match m:
    case None{}:
      "none"
    case Some{bs}:
      S.Hex.encode(bs)

def inv(m: Maybe<&2, G.Inv>) -> String:
  match m:
    case None{}:
      "none"
    case Some{G.Inv{u, i, s}}:
      u ++ " | " ++ i ++ " | " ++ s

def key() -> String:
  "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"

def other() -> String:
  "ff112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"

def ring.body() -> String:
  "--x\r\nContent-Disposition: form-data; name=\"transcription\"\r\n\r\nremind me to order stencils\r\n--x\r\nContent-Disposition: form-data; name=\"recordedAt\"\r\n\r\n1790000000000\r\n--x\r\nContent-Disposition: form-data; name=\"client\"\r\n\r\nring\r\n--x--\r\n"

def ring.secret() -> String:
  "354af29fd1b4fe9426d7f3a9a6fcbf9488a222cbaaee101128eb2e8e4c5bef35"

def ring.sig() -> String:
  "b892f374c0eae593c14cf99c4c9ef193d83d7da991555ee9dae592d5f05dc6e3"

def main() -> IO(Unit):
  do IO<Unit>:
    C.Check.str("sha256 empty", sha(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    C.Check.str("sha256 abc", sha("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    C.Check.str("sha256 56", sha("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"), "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    C.Check.str("sha256 100k", S.Hex.encode(S.Sha256.hash(rep(100000n, 97, Nil{}))), "6d1cf22d7cc09b085dfc25ee1a1f3ae0265804c607bc2074ad253bcc82fd81ee")
    C.Check.str("hmac rfc4231 1", mac(rep(20n, 11, Nil{}), U.Utf8.encode("Hi There")), "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7")
    C.Check.str("hmac rfc4231 2", mac(U.Utf8.encode("Jefe"), U.Utf8.encode("what do ya want for nothing?")), "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
    C.Check.str("hmac rfc4231 4", mac(upto(25n, Nil{}), rep(50n, 205, Nil{})), "82558a389a443c0ea4cc819899f2083a85f0faa3e578f8077a2e3ff46729665b")
    C.Check.str("hmac rfc4231 6", mac(rep(131n, 170, Nil{}), U.Utf8.encode("Test Using Larger Than Block-Size Key - Hash Key First")), "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54")
    C.Check.str("hex round trip", dec(S.Hex.decode(key())), key())
    C.Check.str("hex upper", dec(S.Hex.decode("0aFf")), "0aff")
    C.Check.str("hex odd", dec(S.Hex.decode("abc")), "none")
    C.Check.str("hex bad digit", dec(S.Hex.decode("zz")), "none")
    C.Check.str("hex empty", dec(S.Hex.decode("")), "")
    C.Check.str("ct equal", yn(S.Ct.eq([1, 2, 3], [1, 2, 3])), "yes")
    C.Check.str("ct differ", yn(S.Ct.eq([1, 2, 3], [1, 2, 4])), "no")
    C.Check.str("ct shorter", yn(S.Ct.eq([1, 2], [1, 2, 3])), "no")
    C.Check.str("ct longer", yn(S.Ct.eq([1, 2, 3], [1, 2])), "no")
    C.Check.str("ct empty", yn(S.Ct.eq([], [])), "yes")
    C.Check.str("sign header", G.Sign.header(key(), 1700000000n, "hello"), "sha256=cc79f14ab4039fa7da631c611ed7804596d5440447fcca722d82cafb71363dbc")
    C.Check.str("sign accepts", yn(G.Sign.check(key(), 1700000100n, 1700000000n, "hello", G.Sign.header(key(), 1700000000n, "hello"))), "yes")
    C.Check.str("sign window edge", yn(G.Sign.check(key(), 1700000300n, 1700000000n, "hello", G.Sign.header(key(), 1700000000n, "hello"))), "yes")
    C.Check.str("sign stale", yn(G.Sign.check(key(), 1700000301n, 1700000000n, "hello", G.Sign.header(key(), 1700000000n, "hello"))), "no")
    C.Check.str("sign future", yn(G.Sign.check(key(), 1699999699n, 1700000000n, "hello", G.Sign.header(key(), 1700000000n, "hello"))), "no")
    C.Check.str("sign tampered", yn(G.Sign.check(key(), 1700000000n, 1700000000n, "hellO", G.Sign.header(key(), 1700000000n, "hello"))), "no")
    C.Check.str("sign wrong secret", yn(G.Sign.check(other(), 1700000000n, 1700000000n, "hello", G.Sign.header(key(), 1700000000n, "hello"))), "no")
    C.Check.str("sign other ts", yn(G.Sign.check(key(), 1700000000n, 1700000001n, "hello", G.Sign.header(key(), 1700000000n, "hello"))), "no")
    C.Check.str("github accepts", yn(G.Sign.github(key(), "{\"a\":1}", "sha256=97f7ed552fdaf78dfb8fbac26e17691e93595099016967e528185ae2da24e365")), "yes")
    C.Check.str("github tampered", yn(G.Sign.github(key(), "{\"a\":2}", "sha256=97f7ed552fdaf78dfb8fbac26e17691e93595099016967e528185ae2da24e365")), "no")
    C.Check.str("github wrong secret", yn(G.Sign.github(other(), "{\"a\":1}", "sha256=97f7ed552fdaf78dfb8fbac26e17691e93595099016967e528185ae2da24e365")), "no")
    C.Check.str("seen new", yn(G.Seen.has(G.Seen.empty(), "x")), "no")
    C.Check.str("seen added", yn(G.Seen.has(G.Seen.add(G.Seen.empty(), "x", 1000n), "x")), "yes")
    C.Check.str("seen other", yn(G.Seen.has(G.Seen.add(G.Seen.empty(), "x", 1000n), "y")), "no")
    C.Check.str("seen kept", yn(G.Seen.has(G.Seen.add(G.Seen.add(G.Seen.empty(), "x", 1000n), "y", 1300n), "x")), "yes")
    C.Check.str("seen expired", yn(G.Seen.has(G.Seen.add(G.Seen.add(G.Seen.empty(), "x", 1000n), "y", 1301n), "x")), "no")
    C.Check.str("invite make", G.Invite.make("http://host:3787", "p1", key()), "bp1:http://host:3787:p1:" ++ key())
    C.Check.str("invite round trip", inv(G.Invite.parse(G.Invite.make("http://host:3787", "p1", key()))), "http://host:3787 | p1 | " ++ key())
    C.Check.str("invite pasted", inv(G.Invite.parse(" bp1:https://a.b.ts.net:443/x:peer-9:" ++ key() ++ "\n")), "https://a.b.ts.net:443/x | peer-9 | " ++ key())
    C.Check.str("invite no prefix", inv(G.Invite.parse("bp2:http://host:3787:p1:" ++ key())), "none")
    C.Check.str("invite empty id", inv(G.Invite.parse("bp1:http://host:3787::" ++ key())), "none")
    C.Check.str("invite empty url", inv(G.Invite.parse("bp1::p1:" ++ key())), "none")
    C.Check.str("invite no url", inv(G.Invite.parse("bp1:p1:" ++ key())), "none")
    C.Check.str("invite short secret", inv(G.Invite.parse("bp1:http://host:3787:p1:0011")), "none")
    C.Check.str("invite bad secret", inv(G.Invite.parse("bp1:http://host:3787:p1:zz112233445566778899aabbccddeeff00112233445566778899aabbccddeeff")), "none")
    C.Check.str("invite empty", inv(G.Invite.parse("")), "none")
    C.Check.str("ring signature (python hmac)", yn(G.Sign.index(ring.secret(), 1790000100n, 1790000000n, "rec-42", "single-click-hold", False{}, ring.body(), ring.sig())), "yes")
    C.Check.str("ring stale", yn(G.Sign.index(ring.secret(), 1790000301n, 1790000000n, "rec-42", "single-click-hold", False{}, ring.body(), ring.sig())), "no")
    C.Check.str("ring other gesture", yn(G.Sign.index(ring.secret(), 1790000100n, 1790000000n, "rec-42", "double-click-hold", False{}, ring.body(), ring.sig())), "no")
    C.Check.str("ring other delivery", yn(G.Sign.index(ring.secret(), 1790000100n, 1790000000n, "rec-43", "single-click-hold", False{}, ring.body(), ring.sig())), "no")
    C.Check.str("ring as a test", yn(G.Sign.index(ring.secret(), 1790000100n, 1790000000n, "rec-42", "single-click-hold", True{}, ring.body(), ring.sig())), "no")
    C.Check.str("ring tampered", yn(G.Sign.index(ring.secret(), 1790000100n, 1790000000n, "rec-42", "single-click-hold", False{}, ring.body() ++ " ", ring.sig())), "no")
    C.Check.str("ring wrong secret", yn(G.Sign.index("00" ++ ring.secret(), 1790000100n, 1790000000n, "rec-42", "single-click-hold", False{}, ring.body(), ring.sig())), "no")
