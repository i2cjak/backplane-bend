# Git

Two modules:
- `src/core/diff.bend` (pure): parses unified diffs.
- `src/server/git.bend` (IO): runs git as a subprocess. Arguments are always an argv list, never a shell line.

Every IO action returns text:
- the result, or
- `""` when there is nothing to report, or
- `error: <git output>`.

`Git.failed(s)` tells whether an answer reports an error. That includes a failed step inside a multi-line stacked action.

## Diffs (`src/core/diff.bend`)

```
DLine{kind: U32, text, old_no: Nat, new_no: Nat}   kind: 0 context, 1 add, 2 del, 3 meta
DHunk{header, lines: List<&2, DLine>}
DFile{old, new, status, hunks: List<&2, DHunk>}   status: modified | added | deleted | renamed | copied
DStats{files, adds, dels}

Diff.parse(text) -> List<&2, DFile>
Diff.stats(fs) -> DStats
Diff.summary(fs) -> String       "3 files, +12 −4"
Diff.binary(f) -> Bool
Diff.lines(text) -> List<&2, String>
```

- Paths drop the `a/` and `b/` prefixes. `old` and `new` both hold a path, even for an added or deleted file; `status` says which case it is.
- Line numbers:
  - Context lines carry both numbers.
  - Added lines have `old_no = 0`.
  - Deleted lines have `new_no = 0`.
- `\ No newline at end of file` becomes a meta line.
- A binary file has a single hunk with an empty header, whose meta line is git's `Binary files ...` line.
- The parser counts the lines each hunk header promises, so a deleted line that starts with `-- ` is not mistaken for a file header.
- Parsing makes one tail-recursive pass over the lines.

## Repository

```
Git.is_repo(cwd) -> IO(Bool)
Git.root(cwd) -> IO(String)          "" outside a repository
Git.branch(cwd) -> IO(String)        "" when HEAD is detached; works on an unborn branch
Git.status(cwd) -> IO(String)        git status --porcelain=v1 --branch -uall
Git.Status.parse(text) -> GStatus{branch, ahead: Nat, behind: Nat, changed: Nat, files: List<&2, String>}
```

## Branches and worktrees

```
Git.branch.sanitize(s) -> String
Git.branch.temp(seed: Nat) -> String                   backplane/<8 hex>
Git.worktree.path(base_dir, repo_name, branch) -> String
Git.worktree.create(repo_cwd, base_dir, repo_name, branch, base_branch) -> IO(String)
Git.branch.rename(cwd, old, new) -> IO(String)
Git.worktree.remove(repo_cwd, path) -> IO(String)
Git.worktree.remove_force(repo_cwd, path) -> IO(String)
```

- `Git.branch.sanitize(s)` gives a lowercase name built from `[a-z0-9._/-]`. Any other character becomes `-`. Each run of separators collapses to one: `/` wins over `-`, and `-` wins over `.`. So `..`, `//`, `/.` and `-/` cannot appear. The name has no leading or trailing separator and is at most 64 characters. The result is `""` when nothing is left.
- `Git.branch.temp(seed)` hashes the seed with murmur3's 32-bit finalizer.
- `Git.worktree.path` answers `<base_dir>/worktrees/<repo_name>/<branch with / as ->`.
- `Git.worktree.create` runs `git worktree add -b <sanitized branch> <path> [base_branch]` and answers the path. To get a fresh branch, pass `Git.branch.temp(seed)`.
- `Git.branch.rename` sanitizes `new` and answers the new name.
- `Git.worktree.remove` answers `""`. Git refuses to remove a worktree that has changes.
- `Git.worktree.remove_force` removes the worktree even when it has changes.

## Checkpoints

```
Git.checkpoint.ref(thread_id, n) -> String
Git.checkpoint.capture(cwd, thread_id, n) -> IO(String)        the commit id
Git.checkpoint.diff(cwd, thread_id, from_n, to_n) -> IO(String) unified diff text
Git.checkpoint.diff_worktree(cwd, thread_id, n) -> IO(String)   checkpoint n vs the files now
Git.checkpoint.revert(cwd, thread_id, n) -> IO(String)          "" when done
Git.b64url(s) -> String                                         base64url, no padding
```

Ref layout:

```
refs/backplane/checkpoints/<b64url(thread_id)>/turn/<n>
```

- Turn 0 is the state before the first turn. Capture it when the thread starts, then capture turn n after each turn.
- Each checkpoint is a commit object:
  - authored by `Backplane <backplane@localhost>` and unsigned;
  - its parent is turn n−1 when that checkpoint exists;
  - it is pointed to only by its hidden ref, so no branch moves and no commit lands on the user's branch.

How a capture works:
- The work tree is staged into the thread's own index file, `<git-dir>/backplane-<b64url(thread_id)>.index`. Git runs as `env GIT_INDEX_FILE=<idx> git add -A`, which picks up tracked and untracked files but respects `.gitignore`.
- `git write-tree` turns that index into a tree.
- `git commit-tree` makes the commit, and `git update-ref` points the hidden ref at it.
- In a worktree, `<git-dir>` is that worktree's private git directory.

`diff_worktree` snapshots the current files the same way and diffs the checkpoint against that tree, so untracked new files show up.

How a revert works:
1. It syncs the thread index with the current files (`add -A`).
2. It runs `read-tree -u --reset <checkpoint tree>`. Files that differ are restored. Files the checkpoint lacks are deleted if they are tracked, or untracked and not ignored.
- Ignored files are never in that index, so they are never touched.
- HEAD, the branch and the real index do not move.

All diffs use `-c core.quotepath=false diff --no-color --no-ext-diff --src-prefix=a/ --dst-prefix=b/ -M`.

## Stacked actions

```
Git.act(cwd, action, message, title, body) -> IO(String)
```

`action` is one of `commit`, `push`, `create_pr`, `commit_push` or `commit_push_pr`. The answer has one line per step. The first failing step ends the chain with `error: <step>: ...`.

- **commit**: runs `git add -A`, then `git commit -m <message>`. The default message is "Update from Backplane". The step answers `commit: <short sha> <subject>`, or `commit: nothing to commit`. Nothing to commit is not a failure, so a later push still runs.
- **push**: runs `git push` when the branch has an upstream. Otherwise it runs `git push -u origin <branch>`. It answers `push: <branch>[ -> origin/<branch>]`. A detached HEAD is an error.
- **create_pr**: runs `gh pr create --title T --body B --head <branch>`, or `--fill` when the title is empty. It answers `pr: <url>`, taken from the last line of gh's output.
