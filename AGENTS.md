# Backplane (Bend)

An agentic hardware development environment: an agent harness with
deterministic viewers for KiCad boards, schematics, and STEP models. It is a
ground-up rewrite of Backplane (a T3Code fork, `i2cjak/Backplane`) in
[Bend](https://bend-lang.com), so the rules that matter are laws the compiler
checks.

When using Bend:
- run `bend guide` to learn it
- use `LAWS.bend` to keep important rules
- run `bend PROOF.bend` before committing
- parallelize the code whenever possible

## Layout

- `LAWS.bend`: the rules, stated as laws over the real code. Humans own it. An agent may add laws, but never weaken or delete one without the user's explicit consent.
- `PROOF.bend`: a proof of every law. `bend PROOF.bend` must print "All terms check."
- `src/core/`: pure Bend. JSON, S-expressions, the event-sourced thread model, the settle rule, sidebar order, KiCad parsing, scene diff and fade, semver, and the prompt/skills logic. No IO here.
- `src/server/`: the Bend program that owns IO: HTTP/WebSocket, the event store, agent processes, git, file watching, and updates. Custom effects (`*.c` + `*.js` twins) are in `src/server/effects/`.
- `src/web/`: the browser UI. View logic is Bend (`*.bend`); `host.js` only touches the DOM, canvas, and socket, and holds no product logic.
- `test/`: Bend test programs (`bend test/x.bend`), run by `scripts/test.sh`.
- `docs/reference/t3code-parity.md`: what the TS product did; `docs/parity.md`: what we match so far.

## Commands

```sh
scripts/check.sh      # --check-only every .bend file, then bend PROOF.bend
scripts/test.sh       # run every test/*_test.bend (JS target, via bun)
scripts/build.sh      # native server binary + web bundle into dist/
dist/backplane        # run it (opens http://127.0.0.1:3773)
```

Native builds need clang 19+. On a machine without it, `~/.local/bin/clang` may be a `zig cc` shim.

## Bend traps (learned here, keep adding)

- A `match` scrutinee must be a parameter or pattern-bound variable, even in a multi-match. Pass computed values (`String.eq(a, b)`) to a helper def that matches on its parameters.
- A def must be defined above its uses. Forward `law` declarations don't help: live code can't call an unfilled law.
- No mutual recursion. When a recursive walk needs a per-element decision, compute it in a non-recursive step and recurse on the tail: `go(t, step(h, st))`. For look-ahead, pass the head's precomputed flag as a parameter: `go(t, hit(t, k), k)`.
- In a recursive call the shrinking argument comes first. Arguments before it must be passed unchanged.
- Operators need a type: `(a + b : U32)`. Division too: `((x * 255 : U32) / 200 : U32)`.
- Inside `do`, only `x : T <- m`, `x : T = v`, and steps are allowed. Destructure in a helper def.
- `A & B` is affine. For a reusable pair in a `List<&2, …>`, declare a small `is Data` type (like `KV`).
- Multi-arg calls on List/Maybe take the quantity first: `List.head(&1, String, xs)`, `Maybe.default(&2, U32, m, d)`.
- `bend page.html -o dist` writes an empty chunk when a .bend file fails to check. Always `--check-only` first (`scripts/check.sh` does).
- `Nat.max`/`Nat.min` recurse once per unit: at epoch-second scale they overflow the stack. Use `Time.max` (model.bend) or `Bool.pick(Nat, Nat.is_ge(a, b), a, b)`. `Nat.add/sub/mul/div/mod/cmp/is_*` are native and safe.
- `Bool.pick(T, c, a, b)` evaluates both branches, so each variable in them counts as used twice (mark it `+`). When a branch consumes something affine, match on the Bool in a helper instead.
- Multi-match scrutinees must follow binder order: parameters in declaration order, then pattern-bound names in binding order.
- `List.map` and `List.filter` accept only `List<&1, _>` or need `~` templates with closed arguments. For `List<&2, _>`, write the recursion.
- IO loops: a looping def passes a continuation lambda that calls itself with less fuel (`r => Helper(r, x2 => Loop(f, x2))`). The helper must never name the loop, or the two become mutually recursive.
- Put the shrinking argument first even in IO loops (`Hub.commit(cs, h, …)`, not `(h, cs, …)`).
- `where` is a keyword.
- Rewrites: `%e : P` with `e : {a == b}` turns a goal `P[_ := b]` into `P[_ := a]`. Use `Equal.sym` to flip direction and `Equal.trans` to chain.

## House rules

- Never kill processes by name or pattern; only PIDs you captured.
- Never write to live user data (`~/.backplane-bend/`). Tests use a temp `BACKPLANE_HOME`.
- Persisted events stay decodable forever. Add event variants; never change the meaning of an existing one.
- No continuous repaint loops. The viewer animates only while a fade is in flight, then stops requesting frames.
- The UI is dumb: every decision (order, settle state, fade alpha, what's visible) comes from a Bend def with a law behind it where possible.
- Square corners, minimal copy, no decorative headings.
- Before pushing, verify the GitHub account (`i2cjak`), the remote, and the branch.
