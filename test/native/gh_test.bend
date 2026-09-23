import Base
import ../check.bend as C
import ../../src/server/proc.bend as P
import ../../src/server/gh.bend as GH

# gh with several accounts, against a fake gh (fake) or the real one
# (real, read-only: lists this repository's merged pull requests).
#   PATH=/tmp/bp-gh/fakebin:$PATH build/gh_test fake /tmp/bp-gh
#   build/gh_test real <a clone with a GitHub remote>

def sh(cwd: String, script: String) -> IO(P.Ran):
  P.Proc.run("sh", ["-c", script], cwd)

def out(r: P.Ran) -> String:
  match r:
    case P.Ran{_, o}:
      String.trim(o)

def code(r: P.Ran) -> String:
  match r:
    case P.Ran{c, _}:
      U32.show(c)

def chk(name: String, +got: String, +want: String) -> IO(Bool):
  do IO<Bool>:
    IO.print(C.Check.pick(String.eq(got, want), name, got, want))
    return String.eq(got, want)

def all(bs: List<&2, Bool>) -> Bool:
  match bs:
    case Nil{}:
      True{}
    case b <> t:
      Bool.and(b, all(t))

def finish(ok: Bool) -> IO(Unit):
  match ok:
    case True{}:
      IO.print("all ok")
    case False{}:
      IO.print("gh_test failed")

def fake(+dir: String) -> IO(Bool):
  +repo = dir ++ "/repo"
  do IO<Bool>:
    s : P.Ran <- sh(dir, "rm -rf repo calls && mkdir repo && cd repo && git init -q && git remote add origin https://github.com/acme/widget.git")
    +r1 : P.Ran <- GH.GhRun.gh(repo, ["pr", "list", "--json", "url"])
    a1 : Bool <- chk("falls through to the account that can", code(r1) ++ " " ++ out(r1), "0 []")
    sv : P.Ran <- sh(repo, "git config --get backplane.ghuser")
    a2 : Bool <- chk("remembers it", out(sv), "bob")
    c1 : P.Ran <- sh(dir, "grep 'pr list' calls | cut -d'|' -f1 | tr '\\n' ' '")
    a3 : Bool <- chk("tried in order", out(c1), "tok-alice tok-bob")
    r2 : P.Ran <- GH.GhRun.gh(repo, ["pr", "list", "--json", "url"])
    c2 : P.Ran <- sh(dir, "grep 'pr list' calls | cut -d'|' -f1 | tr '\\n' ' '")
    a4 : Bool <- chk("remembered one first", out(c2), "tok-alice tok-bob tok-bob")
    +r3 : P.Ran <- GH.GhRun.gh(repo, ["pr", "create", "--fill"])
    c3 : P.Ran <- sh(dir, "grep -c 'pr create' calls")
    a5 : Bool <- chk("a real error is the answer", code(r3) ++ " " ++ out(c3), "1 1")
    c4 : P.Ran <- sh(dir, "grep -c 'tok-' calls | head -1; grep 'tok-' calls | grep -v '^tok-' | wc -l")
    a6 : Bool <- chk("no token on a command line", out(c4), "4\n0")
    s2 : P.Ran <- sh(dir, "git -C repo config --unset backplane.ghuser; git -C repo remote set-url origin https://github.com/bob/widget.git; : > calls")
    r4 : P.Ran <- GH.GhRun.gh(repo, ["pr", "list", "--json", "url"])
    c5 : P.Ran <- sh(dir, "grep 'pr list' calls | cut -d'|' -f1 | tr '\\n' ' '")
    a7 : Bool <- chk("owner's account first", out(c5), "tok-bob")
    s3 : P.Ran <- sh(dir, "git -C repo remote set-url origin /srv/nowhere.git; : > calls")
    r5 : P.Ran <- GH.GhRun.gh(repo, ["pr", "list", "--json", "url"])
    c6 : P.Ran <- sh(dir, "cut -d'|' -f1 calls | tr '\\n' ' '")
    a8 : Bool <- chk("no GitHub remote: gh as it is", out(c6), "none")
    return all([a1, a2, a3, a4, a5, a6, a7, a8])

def real(+repo: String) -> IO(Bool):
  do IO<Bool>:
    +r : P.Ran <- GH.GhRun.gh(repo, ["pr", "list", "--state", "merged", "--limit", "1", "--json", "url"])
    IO.print("  (real gh: " ++ out(r) ++ ")")
    chk("real gh answers", code(r), "0")

def go(args: List<&1, String>) -> IO(Bool):
  match args:
    case "fake" <> d <> _:
      fake(d)
    case "real" <> d <> _:
      real(d)
    case _:
      do IO<Bool>:
        IO.print("usage: gh_test fake DIR | real REPO")
        return False{}

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<&1, String> <- IO.args()
    ok : Bool <- go(args)
    finish(ok)
