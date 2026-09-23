import Base
import ./proc.bend as P
import ./gh.bend as GH
import ../core/sha1.bend as S
import ../core/utf8.bend as U
import ../core/diff.bend as D

# Git, run as a subprocess with an argv list (never a shell line). Every
# action answers text: the result, "" when there is nothing to say, or
# "error: <git's output>" so the hub can show it. docs/git.md has the API and
# the checkpoint ref layout.

# Running git
# -----------

def Git.run(cwd: String, args: List<&2, String>) -> IO(P.Ran):
  P.Proc.run("git", args, cwd)

# git with a private index file (GIT_INDEX_FILE), through env(1)
def Git.run.idx(cwd: String, idx: String, args: List<&2, String>) -> IO(P.Ran):
  P.Proc.run("env", ("GIT_INDEX_FILE=" ++ idx) <> "git" <> args, cwd)

def Git.is_error(+s: String) -> Bool:
  String.starts_with(s, "error: ")

def Git.then.k(ok: Bool, raw: Bool, out: String, k: String -> IO(String)) -> IO(String):
  match ok raw:
    case True{} True{}:
      k(out)
    case True{} False{}:
      k(String.trim(out))
    case False{} _:
      IO.pure(String, "error: " ++ String.trim(out))

def Git.then(raw: Bool, r: P.Ran, k: String -> IO(String)) -> IO(String):
  match r:
    case P.Ran{code, out}:
      Git.then.k(U32.is_eq(code, 0), raw, out, k)

# run, then continue with the trimmed output; a non-zero exit ends the chain
# with "error: <output>"
def Git.seq(m: IO(P.Ran), k: String -> IO(String)) -> IO(String):
  IO.bind(P.Ran, String, m, r => Git.then(False{}, r, k))

# the same with the output untouched (diffs)
def Git.seq.raw(m: IO(P.Ran), k: String -> IO(String)) -> IO(String):
  IO.bind(P.Ran, String, m, r => Git.then(True{}, r, k))

def Git.and.k(bad: Bool, +s: String, k: String -> IO(String)) -> IO(String):
  match bad:
    case True{}:
      IO.pure(String, s)
    case False{}:
      k(s)

# continue after a step that answers text, unless it answered an error
def Git.and(m: IO(String), k: String -> IO(String)) -> IO(String):
  IO.bind(String, String, m, +s => Git.and.k(Git.is_error(s), s, k))

def Git.done(s: String) -> IO(String):
  IO.pure(String, s)

def Git.code(r: P.Ran) -> U32:
  match r:
    case P.Ran{code, _}:
      code

def Git.text(r: P.Ran) -> String:
  match r:
    case P.Ran{_, out}:
      String.trim(out)

# Repository
# ----------

def Git.is_repo.k(r: P.Ran) -> Bool:
  match r:
    case P.Ran{code, out}:
      Bool.and(U32.is_eq(code, 0), String.eq(String.trim(out), "true"))

def Git.is_repo(cwd: String) -> IO(Bool):
  IO.bind(P.Ran, Bool, Git.run(cwd, ["rev-parse", "--is-inside-work-tree"]), r => IO.pure(Bool, Git.is_repo.k(r)))

def Git.or_empty(+s: String) -> String:
  Bool.pick(String, Git.is_error(s), "", s)

# the top of the work tree, or "" outside a repository
def Git.root(cwd: String) -> IO(String):
  IO.bind(String, String, Git.seq(Git.run(cwd, ["rev-parse", "--show-toplevel"]), Git.done), s => IO.pure(String, Git.or_empty(s)))

# the current branch (also on an unborn one), or "" when detached
def Git.branch(cwd: String) -> IO(String):
  IO.bind(String, String, Git.seq(Git.run(cwd, ["symbolic-ref", "--short", "-q", "HEAD"]), Git.done), s => IO.pure(String, Git.or_empty(s)))

# `git status --porcelain=v1 --branch -uall` text, or "error: ..."
def Git.status(cwd: String) -> IO(String):
  Git.seq.raw(Git.run(cwd, ["-c", "core.quotepath=false", "status", "--porcelain=v1", "--branch", "-uall"]), Git.done)

# Status parsing
# --------------

type GStatus is Data:
  GStatus{branch: String, ahead: Nat, behind: Nat, changed: Nat, files: List<&2, String>}

# the text after the first `key` in s, or "" when absent
def Git.after.go(s: String, hit: Bool, +key: String) -> String:
  match s hit:
    case SNil{} _:
      ""
    case +x True{}:
      String.drop(x, String.length(key))
    case SCon{_, +t} False{}:
      Git.after.go(t, String.starts_with(t, key), key)

def Git.after(+s: String, +key: String) -> String:
  Git.after.go(s, String.starts_with(s, key), key)

def Git.digit_stop(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{c, _}:
      Bool.not(Char.is_digit(c))

def Git.digits.take.go(s: String, stop: Bool, acc: String) -> String:
  match s stop:
    case _ True{}:
      String.reverse(acc)
    case SNil{} False{}:
      String.reverse(acc)
    case SCon{c, +t} False{}:
      Git.digits.take.go(t, Git.digit_stop(t), SCon{c, acc})

def Git.digits.take(+s: String, acc: String) -> String:
  Git.digits.take.go(s, Git.digit_stop(s), acc)

# a leading run of digits as a Nat (0 when none)
def Git.lead_num(s: String) -> Nat:
  Maybe.default(&2, Nat, Nat.read(Git.digits.take(s, SNil{})), 0n)

def Git.name_stop(+s: String) -> Bool:
  Bool.or(String.starts_with(s, "..."), String.starts_with(s, " "))

def Git.name.go(s: String, stop: Bool, acc: String) -> String:
  match s stop:
    case _ True{}:
      String.reverse(acc)
    case SNil{} False{}:
      String.reverse(acc)
    case SCon{c, +t} False{}:
      Git.name.go(t, Git.name_stop(t), SCon{c, acc})

# "main...origin/main [ahead 1]" -> "main"
def Git.name(+s: String) -> String:
  Git.name.go(s, Git.name_stop(s), "")

def Git.head.branch(+h: String) -> String:
  Bool.pick(String, Bool.or(String.starts_with(h, "No commits yet on "), String.starts_with(h, "Initial commit on ")), String.drop(h, 18n), Git.name(h))

def Git.head.num(+h: String, +key: String) -> Nat:
  Bool.pick(Nat, String.contains(h, key), Git.lead_num(Git.after(h, key)), 0n)

type SAcc is Data:
  SAcc{branch: String, ahead: Nat, behind: Nat, changed: Nat, files: List<&2, String>}

def Git.status.head(+h: String, acc: SAcc) -> SAcc:
  match acc:
    case SAcc{_, _, _, c, fs}:
      SAcc{Git.head.branch(h), Git.head.num(h, "ahead "), Git.head.num(h, "behind "), c, fs}

def Git.status.file(l: String, acc: SAcc) -> SAcc:
  match acc:
    case SAcc{b, a, d, c, fs}:
      SAcc{b, a, d, 1n+c, String.drop(l, 3n) <> fs}

def Git.status.line.k(hd: Bool, empty: Bool, +l: String, acc: SAcc) -> SAcc:
  match hd empty:
    case True{} _:
      Git.status.head(String.drop(l, 3n), acc)
    case False{} True{}:
      acc
    case False{} False{}:
      Git.status.file(l, acc)

def Git.status.line(+l: String, acc: SAcc) -> SAcc:
  Git.status.line.k(String.starts_with(l, "## "), String.is_empty(String.trim(l)), l, acc)

def Git.status.go(ls: List<&2, String>, acc: SAcc) -> SAcc:
  match ls:
    case Nil{}:
      acc
    case l <> t:
      Git.status.go(t, Git.status.line(l, acc))

def Git.status.fin(acc: SAcc) -> GStatus:
  match acc:
    case SAcc{b, a, d, c, fs}:
      GStatus{b, a, d, c, List.reverse(&2, String, fs)}

# lines of a text (tail-recursive)
def Git.lines(s: String) -> List<&2, String>:
  D.Diff.lines(s)

# `git status --porcelain=v1 --branch` text as a record; files keep the
# porcelain path text ("old -> new" for a rename)
def Git.Status.parse(text: String) -> GStatus:
  Git.status.fin(Git.status.go(Git.lines(text), SAcc{"", 0n, 0n, 0n, Nil{}}))

# Branch names
# ------------

# 0 a kept character, 1 '.', 2 '-' (and anything not allowed), 3 '/'
def Git.cls.k(keep: Bool, dot: Bool, slash: Bool) -> U32:
  match keep dot slash:
    case True{} _ _:
      0
    case False{} True{} _:
      1
    case False{} False{} True{}:
      3
    case False{} False{} False{}:
      2

def Git.cls(+c: Char) -> U32:
  Git.cls.k(Bool.or(Bool.or(Char.is_digit(c), Bool.and(U32.is_ge(Char.to_u32(c), 97), U32.is_le(Char.to_u32(c), 122))), Char.is_eq(c, '_')), Char.is_eq(c, '.'), Char.is_eq(c, '/'))

def Git.sep_chr(+k: U32) -> Char:
  Chr{Bool.pick(U32, U32.is_eq(k, 3), 47, Bool.pick(U32, U32.is_eq(k, 2), 45, 46))}

# the reversed output, the strongest separator waiting, whether anything was kept
type SZ is Data:
  SZ{out: String, pend: U32, started: Bool}

def Git.sz.emit(started: Bool, +pend: U32, +out: String) -> String:
  match started:
    case True{}:
      Bool.pick(String, U32.is_eq(pend, 0), out, SCon{Git.sep_chr(pend), out})
    case False{}:
      out

def Git.sz.put.k(keep: Bool, +k: U32, c: Char, out: String, +pend: U32, started: Bool) -> SZ:
  match keep:
    case True{}:
      SZ{SCon{c, Git.sz.emit(started, pend, out)}, 0, True{}}
    case False{}:
      SZ{out, U32.max(pend, k), started}

def Git.sz.put(+k: U32, +c: Char, st: SZ) -> SZ:
  match st:
    case SZ{out, +pend, started}:
      Git.sz.put.k(U32.is_eq(k, 0), k, c, out, pend, started)

def Git.sz.go(s: String, st: SZ) -> SZ:
  match s:
    case SNil{}:
      st
    case SCon{+c, t}:
      Git.sz.go(t, Git.sz.put(Git.cls(Char.to_lower(c)), Char.to_lower(c), st))

def Git.sz.fin(st: SZ) -> String:
  match st:
    case SZ{out, _, _}:
      String.reverse(out)

def Git.is_sep(s: String) -> Bool:
  match s:
    case SNil{}:
      False{}
    case SCon{c, _}:
      U32.is_ne(Git.cls(c), 0)

def Git.drop_seps.go(s: String, sep: Bool) -> String:
  match s sep:
    case SCon{_, +t} True{}:
      Git.drop_seps.go(t, Git.is_sep(t))
    case x _:
      x

def Git.drop_seps(+s: String) -> String:
  Git.drop_seps.go(s, Git.is_sep(s))

def Git.trim_end_seps(s: String) -> String:
  String.reverse(Git.drop_seps(String.reverse(s)))

# a safe branch name: lowercase [a-z0-9._/-], each run of separators becomes
# one ('/' over '-' over '.'), none leading or trailing, at most 64 chars;
# "" when nothing is left
def Git.branch.sanitize(s: String) -> String:
  Git.trim_end_seps(String.take(Git.sz.fin(Git.sz.go(s, SZ{SNil{}, 0, False{}})), 64n))

def Git.hex.chr(+n: U32) -> Char:
  Chr{Bool.pick(U32, U32.is_lt(n, 10), (n + 48 : U32), (n + 87 : U32))}

def Git.hex.go(n: Nat, +x: U32, acc: String) -> String:
  match n:
    case 0n:
      acc
    case 1n+p:
      Git.hex.go(p, U32.shrn(x, 4n), SCon{Git.hex.chr(U32.and(x, 15)), acc})

def Git.mix.c(+h: U32) -> U32:
  U32.xor(h, U32.shrn(h, 16n))

def Git.mix.b(+h: U32) -> U32:
  Git.mix.c(U32.mul(U32.xor(h, U32.shrn(h, 13n)), 3266489909))

# murmur3's 32-bit finalizer
def Git.mix(+h: U32) -> U32:
  Git.mix.b(U32.mul(U32.xor(h, U32.shrn(h, 16n)), 2246822507))

# 8 hex digits from a seed
def Git.hex8(seed: Nat) -> String:
  Git.hex.go(8n, Git.mix(U32.from_nat(Nat.mod(seed, Nat.mul(65536n, 65536n)))), "")

# a temporary branch name: backplane/<8 hex>
def Git.branch.temp(seed: Nat) -> String:
  "backplane/" ++ Git.hex8(seed)

def Git.slash_dash.go(s: String, acc: String) -> String:
  match s:
    case SNil{}:
      String.reverse(acc)
    case SCon{+c, t}:
      Git.slash_dash.go(t, SCon{Bool.pick(Char, Char.is_eq(c, '/'), '-', c), acc})

# <base_dir>/worktrees/<repo_name>/<branch with '/' as '-'>
def Git.worktree.path(base_dir: String, repo_name: String, branch: String) -> String:
  base_dir ++ "/worktrees/" ++ repo_name ++ "/" ++ Git.slash_dash.go(branch, "")

# k(v), or msg when bad
def Git.guard(bad: Bool, msg: String, v: String, k: String -> IO(String)) -> IO(String):
  match bad:
    case True{}:
      IO.pure(String, msg)
    case False{}:
      k(v)

def Git.named(+b: String, k: String -> IO(String)) -> IO(String):
  Git.guard(String.is_empty(b), "error: empty branch name", b, k)

def Git.branch.rename.k(cwd: String, old: String, +b: String) -> IO(String):
  Git.named(b, _ => Git.seq(Git.run(cwd, ["branch", "-m", old, b]), _ => Git.done(b)))

# rename a branch; answers the new (sanitized) name
def Git.branch.rename(cwd: String, old: String, new: String) -> IO(String):
  Git.branch.rename.k(cwd, old, Git.branch.sanitize(new))

# Worktrees
# ---------

def Git.base_args(+base: String) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.is_empty(base), Nil{}, [base])

def Git.worktree.create.k(+cwd: String, +path: String, +b: String, base: String) -> IO(String):
  Git.named(b, _ => Git.seq(Git.run(cwd, List.append(&2, String, ["worktree", "add", "-b", b, path], Git.base_args(base))), _ => Git.done(path)))

def Git.worktree.create.b(repo_cwd: String, base_dir: String, repo_name: String, +b: String, base_branch: String) -> IO(String):
  Git.worktree.create.k(repo_cwd, Git.worktree.path(base_dir, repo_name, b), b, base_branch)

# a new worktree on a new branch from base_branch ("" = HEAD); answers its
# path. branch is sanitized; pass Git.branch.temp(seed) for a fresh one.
def Git.worktree.create(repo_cwd: String, base_dir: String, repo_name: String, branch: String, base_branch: String) -> IO(String):
  Git.worktree.create.b(repo_cwd, base_dir, repo_name, Git.branch.sanitize(branch), base_branch)

# remove a clean worktree (git refuses one with changes); "" when done
def Git.worktree.remove(repo_cwd: String, path: String) -> IO(String):
  Git.seq(Git.run(repo_cwd, ["worktree", "remove", path]), _ => Git.done(""))

# remove a worktree even with changes (they are lost)
def Git.worktree.remove_force(repo_cwd: String, path: String) -> IO(String):
  Git.seq(Git.run(repo_cwd, ["worktree", "remove", "--force", path]), _ => Git.done(""))

# Thread worktrees
# ----------------
# A new thread gets a worktree inside its repository, at
# <top>/.backplane/worktrees/<branch with / as ->. The repository's
# info/exclude lists /.backplane/, so neither git status nor a checkpoint of
# the main folder ever sees them. The thread works at the project's place
# in the worktree (a project may be a folder inside a bigger repository).

def Git.thread_wt.path(+top: String, branch: String) -> String:
  top ++ "/.backplane/worktrees/" ++ Git.slash_dash.go(branch, "")

def Git.thread_wt.sub(+prefix: String) -> String:
  Bool.pick(String, String.ends_with(prefix, "/"), String.take(prefix, Nat.sub(String.length(prefix), 1n)), prefix)

# where the thread works: the worktree, plus the project's place in the
# repository (git rev-parse --show-prefix of the project folder)
def Git.thread_wt.cwd(+path: String, +prefix: String) -> String:
  Bool.pick(String, String.is_empty(prefix), path, path ++ "/" ++ Git.thread_wt.sub(prefix))

def Git.exclude.sh() -> String:
  "f=\"$1/info/exclude\"; mkdir -p \"$1/info\" && { grep -qxF '/.backplane/' \"$f\" 2>/dev/null || printf '\\n# Backplane thread worktrees\\n/.backplane/\\n' >> \"$f\"; }"

# list /.backplane/ in the repository's info/exclude (once)
def Git.exclude(+cwd: String) -> IO(String):
  Git.seq(Git.run(cwd, ["rev-parse", "--path-format=absolute", "--git-common-dir"]),
    dir => Git.seq(P.Proc.run("sh", ["-c", Git.exclude.sh(), "sh", dir], cwd), _ => Git.done("")))

# Copy the folder's uncommitted work (changed and untracked files, not
# ignored ones) into a new worktree, and delete there what is deleted here.
# KiCad's own droppings (backups, locks, autosaves, the footprint cache)
# stay behind.
def Git.carry.sh() -> String:
  "cd \"$1\" || exit 1; git ls-files -z -m -o --exclude-standard | grep -zv -e '-backups/' -e '\\.lck$' -e 'fp-info-cache$' -e '_autosave-' | tar -c --null -T - -f - 2>/dev/null | tar -x -f - -C \"$2\" 2>/dev/null; git ls-files -z -d | (cd \"$2\" && xargs -0 -r rm -f --); exit 0"

def Git.carry(+top: String, +path: String) -> IO(String):
  Git.seq(P.Proc.run("sh", ["-c", Git.carry.sh(), "sh", top, path], top), _ => Git.done(""))

def Git.thread_wt.carry(carry: Bool, +top: String, +path: String, +cwd: String) -> IO(String):
  match carry:
    case True{}:
      Git.and(Git.carry(top, path), _ => Git.done(cwd))
    case False{}:
      Git.done(cwd)

def Git.thread_wt.made(+carry: Bool, +top: String, +prefix: String, +b: String) -> IO(String):
  Git.and(Git.exclude(top), _ =>
    Git.seq(Git.run(top, ["worktree", "add", "-b", b, Git.thread_wt.path(top, b)]),
      _ => Git.thread_wt.carry(carry, top, Git.thread_wt.path(top, b), Git.thread_wt.cwd(Git.thread_wt.path(top, b), prefix))))

def Git.thread_wt.head(r: P.Ran, +carry: Bool, +top: String, +prefix: String, +b: String) -> IO(String):
  match r:
    case P.Ran{0, _}:
      Git.thread_wt.made(carry, top, prefix, b)
    case _:
      IO.pure(String, "skip: no commit yet")

def Git.thread_wt.top(+top: String, +cwd: String, +carry: Bool, +b: String) -> IO(String):
  Bool.pick(IO(String), String.is_empty(top), IO.pure(String, "skip: not a git repository"),
    Git.and(Git.seq.raw(Git.run(cwd, ["rev-parse", "--show-prefix"]), p => Git.done(String.trim(p))),
      +prefix => IO.bind(P.Ran, String, Git.run(cwd, ["rev-parse", "--verify", "-q", "HEAD"]), r => Git.thread_wt.head(r, carry, top, prefix, b))))

# a new thread's worktree on a new branch from HEAD, for the project folder
# cwd; carry: bring the folder's uncommitted work along. Answers the
# thread's directory, "skip: <why>" when there is no repository to branch
# (the thread then works in the folder), or "error: ...".
def Git.thread_wt(+cwd: String, +carry: Bool, branch: String) -> IO(String):
  IO.bind(String, String, Git.root(cwd), top => Git.thread_wt.top(top, cwd, carry, Git.branch.sanitize(branch)))

def Git.thread_wt.again.top(+top: String, +cwd: String, +b: String) -> IO(String):
  Bool.pick(IO(String), String.is_empty(top), IO.pure(String, "skip: not a git repository"),
    Git.and(Git.seq.raw(Git.run(cwd, ["rev-parse", "--show-prefix"]), p => Git.done(String.trim(p))),
      +prefix => Git.and(Git.exclude(top), _ =>
        IO.bind(P.Ran, String, Git.run(top, ["worktree", "prune"]),
          _ => Git.seq(Git.run(top, ["worktree", "add", Git.thread_wt.path(top, b), b]), _ => Git.done(Git.thread_wt.cwd(Git.thread_wt.path(top, b), prefix)))))))

# a removed thread worktree made again on its kept branch; answers like
# Git.thread_wt
def Git.thread_wt.again(+cwd: String, +branch: String) -> IO(String):
  IO.bind(String, String, Git.root(cwd), top => Git.thread_wt.again.top(top, cwd, branch))

def Git.skipped(+s: String) -> Bool:
  String.starts_with(s, "skip: ")

def Git.b64url.map(+c: Char) -> U32:
  Bool.pick(U32, Char.is_eq(c, '+'), 45, Bool.pick(U32, Char.is_eq(c, '/'), 95, Bool.pick(U32, Char.is_eq(c, '='), 0, Char.to_u32(c))))

def Git.b64url.put(+u: U32, +acc: String) -> String:
  Bool.pick(String, U32.is_eq(u, 0), acc, SCon{Chr{u}, acc})

# Checkpoints
# -----------

def Git.b64url.go(s: String, acc: String) -> String:
  match s:
    case SNil{}:
      String.reverse(acc)
    case SCon{+c, t}:
      Git.b64url.go(t, Git.b64url.put(Git.b64url.map(c), acc))

# base64url (RFC 4648 section 5) of the UTF-8 bytes, without padding
def Git.b64url(s: String) -> String:
  Git.b64url.go(S.B64.encode(U.Utf8.encode(s)), "")

# refs/backplane/checkpoints/<b64url(thread_id)>/turn/<n>
def Git.checkpoint.ref(thread_id: String, n: Nat) -> String:
  "refs/backplane/checkpoints/" ++ Git.b64url(thread_id) ++ "/turn/" ++ Nat.show(n)

def Git.checkpoint.prev(thread_id: String, n: Nat) -> String:
  match n:
    case 0n:
      "refs/backplane/none"
    case 1n+p:
      Git.checkpoint.ref(thread_id, p)

def Git.index_path(gd: String, thread_id: String) -> String:
  gd ++ "/backplane-" ++ Git.b64url(thread_id) ++ ".index"

# the whole work tree (tracked and untracked, less ignored files) as a tree
# object, staged through the thread's own index file; answers the tree id
def Git.snapshot.k(+cwd: String, +idx: String) -> IO(String):
  Git.seq(Git.run.idx(cwd, idx, ["add", "-A"]), _ =>
    Git.seq(Git.run.idx(cwd, idx, ["write-tree"]), Git.done))

def Git.snapshot(+cwd: String, thread_id: String) -> IO(String):
  Git.seq(Git.run(cwd, ["rev-parse", "--absolute-git-dir"]), gd => Git.snapshot.k(cwd, Git.index_path(gd, thread_id)))

def Git.parents(r: P.Ran) -> List<&2, String>:
  match r:
    case P.Ran{+code, out}:
      Bool.pick(List<&2, String>, U32.is_eq(code, 0), ["-p", String.trim(out)], Nil{})

def Git.commit_tree(cwd: String, tree: String, parents: List<&2, String>, msg: String) -> IO(P.Ran):
  P.Proc.run("env", List.append(&2, String,
    ["GIT_AUTHOR_NAME=Backplane", "GIT_AUTHOR_EMAIL=backplane@localhost",
     "GIT_COMMITTER_NAME=Backplane", "GIT_COMMITTER_EMAIL=backplane@localhost",
     "git", "commit-tree", "--no-gpg-sign", "-m", msg, tree], parents), cwd)

def Git.capture.k(+cwd: String, +r: String, +tree: String, prev: P.Ran, msg: String) -> IO(String):
  Git.seq(Git.commit_tree(cwd, tree, Git.parents(prev), msg), +sha =>
    Git.seq(Git.run(cwd, ["update-ref", r, sha]), _ => Git.done(sha)))

# capture the work tree as turn n of a thread (n = 0 at thread start, before
# the first turn); no commit lands on any branch. Answers the commit id.
def Git.checkpoint.capture(+cwd: String, +thread_id: String, +n: Nat) -> IO(String):
  Git.and(Git.snapshot(cwd, thread_id), tree =>
    IO.bind(P.Ran, String, Git.run(cwd, ["rev-parse", "--verify", "-q", Git.checkpoint.prev(thread_id, n)]), prev =>
      Git.capture.k(cwd, Git.checkpoint.ref(thread_id, n), tree, prev, "backplane checkpoint " ++ thread_id ++ " turn " ++ Nat.show(n))))

def Git.diff.args(a: String, b: String) -> List<&2, String>:
  ["-c", "core.quotepath=false", "diff", "--no-color", "--no-ext-diff", "--src-prefix=a/", "--dst-prefix=b/", "-M", a, b, "--"]

# unified diff text from checkpoint a to checkpoint b ("" when equal)
def Git.checkpoint.diff(cwd: String, +thread_id: String, +from_n: Nat, +to_n: Nat) -> IO(String):
  Git.seq.raw(Git.run(cwd, Git.diff.args(Git.checkpoint.ref(thread_id, from_n), Git.checkpoint.ref(thread_id, to_n))), Git.done)

# unified diff text from checkpoint n to the files as they are now
def Git.checkpoint.diff_worktree(+cwd: String, +thread_id: String, n: Nat) -> IO(String):
  Git.and(Git.snapshot(cwd, thread_id), tree =>
    Git.seq.raw(Git.run(cwd, Git.diff.args(Git.checkpoint.ref(thread_id, n), tree)), Git.done))

def Git.revert.k(+cwd: String, +idx: String, r: String) -> IO(String):
  Git.seq(Git.run(cwd, ["rev-parse", "--verify", r ++ "^{tree}"]), tree =>
    Git.seq(Git.run.idx(cwd, idx, ["add", "-A"]), _ =>
      Git.seq(Git.run.idx(cwd, idx, ["read-tree", "-u", "--reset", tree]), _ => Git.done(""))))

# put the work tree back exactly as checkpoint n had it: changed files are
# restored, files it did not have are removed, ignored files are left alone.
# HEAD, the branch and the real index do not move. "" when done.
def Git.checkpoint.revert(+cwd: String, +thread_id: String, n: Nat) -> IO(String):
  Git.seq(Git.run(cwd, ["rev-parse", "--absolute-git-dir"]), gd =>
    Git.revert.k(cwd, Git.index_path(gd, thread_id), Git.checkpoint.ref(thread_id, n)))

# Stacked actions
# ---------------

type AStep is Data:
  ACommit{}
  APush{}
  APr{}

def Git.act.steps(+a: String) -> Maybe<&2, List<&2, AStep>>:
  Bool.pick(Maybe<&2, List<&2, AStep>>, String.eq(a, "commit"), Some{[ACommit{}]},
  Bool.pick(Maybe<&2, List<&2, AStep>>, String.eq(a, "push"), Some{[APush{}]},
  Bool.pick(Maybe<&2, List<&2, AStep>>, String.eq(a, "create_pr"), Some{[APr{}]},
  Bool.pick(Maybe<&2, List<&2, AStep>>, String.eq(a, "commit_push"), Some{[ACommit{}, APush{}]},
  Bool.pick(Maybe<&2, List<&2, AStep>>, String.eq(a, "commit_push_pr"), Some{[ACommit{}, APush{}, APr{}]}, None{})))))

# "error: x" -> "error: <step>: x"
def Git.label.k(bad: Bool, name: String, +s: String) -> String:
  match bad:
    case True{}:
      "error: " ++ name ++ ": " ++ String.drop(s, 7n)
    case False{}:
      s

def Git.label(name: String, m: IO(String)) -> IO(String):
  IO.bind(String, String, m, +s => IO.pure(String, Git.label.k(Git.is_error(s), name, s)))

def Git.commit.go(clean: Bool, +cwd: String, msg: String) -> IO(String):
  match clean:
    case True{}:
      Git.done("commit: nothing to commit")
    case False{}:
      Git.seq(Git.run(cwd, ["commit", "-m", msg]), _ =>
        Git.seq(Git.run(cwd, ["log", "-1", "--format=%h %s"]), s => Git.done("commit: " ++ s)))

def Git.commit.k(+cwd: String, r: P.Ran, msg: String) -> IO(String):
  match r:
    case P.Ran{code, _}:
      Git.commit.go(U32.is_eq(code, 0), cwd, msg)

def Git.message(+m: String) -> String:
  Bool.pick(String, String.is_empty(String.trim(m)), "Update from Backplane", m)

def Git.step.commit(+cwd: String, msg: String) -> IO(String):
  Git.label("commit", Git.seq(Git.run(cwd, ["add", "-A"]), _ =>
    IO.bind(P.Ran, String, Git.run(cwd, ["diff", "--cached", "--quiet"]), r => Git.commit.k(cwd, r, Git.message(msg)))))

def Git.push.go(has_up: Bool, +cwd: String, +b: String) -> IO(String):
  match has_up:
    case True{}:
      Git.seq(GH.GhRun.push(cwd, ["push"]), _ => Git.done("push: " ++ b))
    case False{}:
      Git.seq(GH.GhRun.push(cwd, ["push", "-u", "origin", b]), _ => Git.done("push: " ++ b ++ " -> origin/" ++ b))

def Git.push.k(+cwd: String, +b: String, up: P.Ran) -> IO(String):
  match up:
    case P.Ran{code, _}:
      Git.push.go(U32.is_eq(code, 0), cwd, b)

def Git.need_branch(+b: String, k: String -> IO(String)) -> IO(String):
  Git.guard(String.is_empty(b), "error: detached HEAD", b, k)

def Git.step.push(+cwd: String) -> IO(String):
  Git.label("push", IO.bind(String, String, Git.branch(cwd), b =>
    Git.need_branch(b, b2 =>
      IO.bind(P.Ran, String, Git.run(cwd, ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"]), up => Git.push.k(cwd, b2, up)))))

def Git.last_line.go(ls: List<&2, String>, last: String) -> String:
  match ls:
    case Nil{}:
      last
    case +l <> t:
      Git.last_line.go(t, Bool.pick(String, String.is_empty(String.trim(l)), last, String.trim(l)))

# the last non-blank line of a text
def Git.last_line(s: String) -> String:
  Git.last_line.go(Git.lines(s), "")

def Git.pr.args(+b: String, +title: String, body: String) -> List<&2, String>:
  Bool.pick(List<&2, String>, String.is_empty(String.trim(title)),
    ["pr", "create", "--fill", "--head", b],
    ["pr", "create", "--title", title, "--body", body, "--head", b])

def Git.step.pr(+cwd: String, title: String, body: String) -> IO(String):
  Git.label("pr", IO.bind(String, String, Git.branch(cwd), b =>
    Git.need_branch(b, b2 =>
      Git.seq(GH.GhRun.gh(cwd, Git.pr.args(b2, title, body)), out => Git.done("pr: " ++ Git.last_line(out))))))

def Git.act.step(s: AStep, +cwd: String, +message: String, +title: String, +body: String) -> IO(String):
  match s:
    case ACommit{}:
      Git.step.commit(cwd, message)
    case APush{}:
      Git.step.push(cwd)
    case APr{}:
      Git.step.pr(cwd, title, body)

def Git.join(+log: String, +line: String) -> String:
  Bool.pick(String, String.is_empty(log), line, log ++ "\n" ++ line)

def Git.act.next(+line: String, log: String, k: String -> IO(String)) -> IO(String):
  Git.and.k(Git.is_error(line), Git.join(log, line), k)

def Git.act.go(steps: List<&2, AStep>, +cwd: String, +message: String, +title: String, +body: String, log: String) -> IO(String):
  match steps:
    case Nil{}:
      Git.done(log)
    case s <> t:
      IO.bind(String, String, Git.act.step(s, cwd, message, title, body), line =>
        Git.act.next(line, log, l2 => Git.act.go(t, cwd, message, title, body, l2)))

def Git.act.k(m: Maybe<&2, List<&2, AStep>>, +action: String, cwd: String, message: String, title: String, body: String) -> IO(String):
  match m:
    case None{}:
      Git.done("error: unknown action " ++ action)
    case Some{steps}:
      Git.act.go(steps, cwd, message, title, body, "")

# a stacked action: commit | push | create_pr | commit_push | commit_push_pr.
# One line per step ("commit: <sha> <subject>", "push: <branch>",
# "pr: <url>"); the first failing step ends it with "error: <step>: ...".
def Git.act(cwd: String, +action: String, message: String, title: String, body: String) -> IO(String):
  Git.act.k(Git.act.steps(action), action, cwd, message, title, body)

# whether an answer (from any action here) reports a failure
def Git.failed(+s: String) -> Bool:
  Bool.or(Git.is_error(s), String.contains(s, "\nerror: "))
