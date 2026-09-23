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
- `src/app/`: the native app (the default `backplane`). A Bend window client in the same process as the hub: `nui.bend` (input → state, pure), `layout.bend` (state → draw ops + hit regions), `main.bend` (event loop), `effects/win.c` (X11 window, dlopen'd libX11).
- `src/gfx/`: the rasterizer. Draw ops become Base's `Image` quadtree in parallel (`raster.bend`); `draw.bend` builds ops; `font.bend` is generated from Spleen 8x16. `text.bend` is system-font text (fontconfig + FreeType via `effects/font.c`, dlopen'd): faces, a glyph cache in Bend state, measure/wrap/draw; `patches/raster-bitmap-shape.patch` adds the `SMask` coverage shape it draws with.
- `src/gfx/tiles.bend`: frames kept as 32 px tiles; the next frame redraws only tiles whose ops or base changed (laws `tiles_again_exact`, `frame_again_exact`, `tile_keep`). The timeline keeps each entry's laid-out lines the same way (`TL.memo` in `layout.bend`, laws `tl_*`). Both compare with `src/core/eq.bend`/`Eq.*`, exact equalities whose soundness is proven, so nothing stale is reused.
- `src/gfx/bitmap.bend`: raw RGB frames (the browser helper's frame file) as an `Image` quadtree, composited into a frame at a place and size.
- `src/core/svg.bend` (pure: SVG path data parsed, written, flattened; laws `svg_*`) and `src/core/icons.bend` (the icon set, Lucide paths, ISC; laws `icons_*`). The window rasterizes them once into `SMask` bitmaps in the glyph cache (`src/gfx/icon.bend`, `Lay.icon`/`Lay.ibutton`); the web writes them as inline `<svg>` (`src/web/icon.bend`). Test: `test/svg_test.bend`.
- `tools/browser/`: `backplane-browser`, a Bun + playwright-core headless Chromium driven by NDJSON on stdin/stdout; raw frames go to a file. Protocol in its README. Built by `scripts/build-browser.sh`.
- `src/core/client.bend`: the client state and actions both UIs share.
- `src/core/tailnet.bend` (pure: owner trust from `tailscale whois`, the owner's machines from `tailscale status`) and `src/app/link.bend` (a WebSocket client shaped like a hub, so the native window can switch to another machine's hub). Each hub finds the owner's other hubs (GET /hello) and lists them in the sidebar; `BACKPLANE_PEERS` names hubs off the tailnet.
- `src/core/diff.bend` (pure: unified diff → files, hunks, numbered lines; stats) and `src/server/git.bend` (IO: repo info, porcelain status, worktrees, hidden-ref checkpoints, stacked commit/push/PR). See `docs/git.md`. Native test: `bend test/native/git_test.bend -o build/git_test && build/git_test`.
- `src/core/lightbox.bend`: the image lightbox (pure: zoom clamped and eased, cursor-anchored, drag pan, what closes it; laws `lightbox_*`). The web keeps its `Lb` in host.js and calls app.bend's `lb_*`; the window keeps it as text in the Ui scratch (`@lb`, `@lb.v`, nui.bend's `Lbx`) and main.bend's `Lbv` draws it with `Bitmap.view`.
- `src/core/vt.bend`: the terminal emulator (VT100/xterm: bytes in, styled rows, cursor, replies, key and paste bytes out); `src/server/pty.bend` + `effects/pty.c` run a shell on a pty whose master is a `Socket`. See `docs/terminal.md`.
- `src/web/`: the web client for other devices (Tailscale, phone). View logic is Bend; `host.js` only touches the DOM, canvas and socket, and holds no product logic.
- `test/`: Bend test programs (`bend test/x.bend`), run by `scripts/test.sh`.
- `src/mobile/`: the phone apps' client in Bend: `screen.bend` (the shared `Ui` → a screen model as JSON), `notify.bend` (turn-end alerts and the Dynamic Island, laws `alert_*`), and `bridge.js`, which carries strings between them and the native app.
- `mobile/`: the phone apps. `ios/` is SwiftUI with a Live Activity widget, running bridge.js in JavaScriptCore; `android/` is Jetpack Compose with a foreground service, running it in QuickJS. `scripts/build-mobile.sh` builds bridge.js and the APK (needs an Android SDK); `scripts/build-ios.sh` builds on a Mac over SSH. Neither runs in CI. See `mobile/README.md`.
- `tools/step2glb/`: the one non-Bend helper, a host tool like git or curl. It converts STEP to GLB (OpenCascade WASM via Bun; LGPL-2.1, run as a subprocess, never linked). `scripts/build-step2glb.sh` builds `dist/backplane-step2glb`. The STEP viewer reads its GLB; all viewer logic stays in Bend. See its README.
- `docs/reference/t3code-parity.md`: what the TS product did; `docs/parity.md`: what we match so far.

## Commands

```sh
scripts/check.sh      # --check-only every .bend file, then bend PROOF.bend
scripts/test.sh       # run every test/*_test.bend (JS target, via bun)
scripts/build.sh      # native server binary + web bundle into dist/
scripts/build-app.sh src/app/main.bend build/backplane   # one native binary, compiled in parallel
dist/backplane        # run it (opens http://127.0.0.1:3787)
```

Native builds go through `scripts/build-app.sh`: bend emits the C, `scripts/cc-split.py` splits it into units, and clang compiles them at nice 19 on cores 0-3 (`BACKPLANE_JOBS`, `BACKPLANE_CPUS`), one build at a time machine-wide (`/tmp/bp-wt-build.lock`). About 2 minutes instead of 4+, and far less memory than one 30 MB file. Never run a bare `bend src/app/main.bend -o ...` on a machine someone is using.

Native builds need clang 19+ and X11 headers (`libx11-dev`). Without root, `~/.local/bin/clang` may be a `zig cc` shim, and `BACKPLANE_X11=~/.local/x11` points the build at headers extracted from the .deb.

Headless UI checks: start Xvfb on `:77`, run `DISPLAY=:77 BACKPLANE_SNAP=/tmp/snap.ppm build/backplane --home /tmp/bp-x`, drive it with `build/xpoke` (`test/tools/xpoke.c`: click/type/key/wheel), and view frames with `scripts/ppm-to-png.py`.

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
- Never choose between screens, overlays or lists with `Bool.pick` or `Out.when`: every hidden screen gets laid out each frame (the thread view cost 70 ms that way). Match on the Bool in a helper (`Lay.main.k`, `Lay.proj.if`, `Proj.items.q`, `Ops.picked.k`).
- `Bool.pick(T, c, a, b)` evaluates both branches, so each variable in them counts as used twice (mark it `+`). When a branch consumes something affine, match on the Bool in a helper instead.
- Multi-match scrutinees must follow binder order: parameters in declaration order, then pattern-bound names in binding order.
- `List.map` and `List.filter` accept only `List<&1, _>` or need `~` templates with closed arguments. For `List<&2, _>`, write the recursion.
- IO loops: a looping def passes a continuation lambda that calls itself with less fuel (`r => Helper(r, x2 => Loop(f, x2))`). The helper must never name the loop, or the two become mutually recursive.
- Put the shrinking argument first even in IO loops (`Hub.commit(cs, h, …)`, not `(h, cs, …)`).
- `where` is a keyword.
- A let (`+x = …`) may not come before a `match` on a parameter. Put the lets inside the case, or compute them in a wrapper def and pass them in.
- `++` joins Strings only. Lists join with `List.append(&2, T, a, b)`; for many, a small concat over a list of lists.
- A float literal bound by a let needs a type: `+d = {0.635 : F32}`.
- `IO.args()` gives a `List<&1, String>`; copy it into a `List<&2, String>` with a small recursion to use it more than once.
- Constructor ids of module types are path-qualified in C (`CID__HOME_..._WKEY`), so an effect cannot build them. Effects return Base types (lists of U32, strings, tuples) and Bend decodes them (`Win.decode`).
- Names Base already uses (`Event`, `App`, `Kind`) cannot be redeclared.
- `Tools`: `scripts/bend-order.py FILE` fixes def order (and reports mutual-recursion cycles); `scripts/bend-reuse.sh FILE` marks binders reported as consumed twice.
- Rewrites: `%e : P` with `e : {a == b}` turns a goal `P[_ := b]` into `P[_ := a]`. Use `Equal.sym` to flip direction and `Equal.trans` to chain.
- A destructuring let of a call (`K{a, b} = f(x)`) is a match on a computed value and is rejected. Build trees bottom-up (pair a list level by level, `Tab.up` in glb.bend) instead of returning `(tree, rest)` pairs.
- `is` is a keyword too: a parameter named `is` fails to parse.
- Bits to float: `match u: case U32{w}: F32{w}` reinterprets a U32 as F32 at no cost (`Glb.f32`); `F32.bits` goes the other way.
- `IO.args()` answers `List<&1, String>`; copy it into a `List<&2, String>` by recursion before reading it twice.
- Random access into big byte lists: turn them into a balanced `Data` tree once and walk ranges (`Words.range`), never `drop` per lookup.
- Only tail calls are free: a walk that builds its result outside the recursive call (`String.repeat`, `Utf8.encode_onto`, `Json.items`) overflows the stack around a few hundred thousand steps. For big inputs, push onto a reversed accumulator and reverse once (`Enc.go` in cbor.bend).
- In `win.c`, an Xlib call outside the pump (XPutImage, XFlush...) can pull input into Xlib's queue while the pump sleeps on the socket; call `win_nudge(a)` after it or keys show one keystroke late.
- Effect C must not contain the word `undefined`, even in a comment: bend reads it as a missing name and stops with "an unbound name in the emitted C" (vendored code included, e.g. stb_image in `src/app/effects/img.c`).
- CPU forks are dealt out once, not stolen: fork over one flat balanced tree of work items (all primitives of all nodes) rather than nesting forks per group; nested forks inside a heavy group barely spread.

## House rules

- Never kill processes by name or pattern; only PIDs you captured.
- Never write to live user data (`~/.backplane-bend/`). Tests use a temp `BACKPLANE_HOME`.
- Persisted events stay decodable forever. Add event variants; never change the meaning of an existing one.
- No continuous repaint loops. The viewer animates only while a fade is in flight, then stops requesting frames.
- The UI is dumb: every decision (order, settle state, fade alpha, what's visible) comes from a Bend def with a law behind it where possible.
- Square corners, minimal copy, no decorative headings.
- Before pushing, verify the GitHub account (`i2cjak`), the remote, and the branch.
