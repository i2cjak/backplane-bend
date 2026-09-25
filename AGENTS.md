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
- `src/gfx/mesh.bend`: the 3D viewer's rasterizer and camera. The camera turns freely about the model's centre like SolidWorks (controls in `nui.bend`, `Drag.mode`/`Key3.act`, laws `view_drag_*`, `view_key_*`); edges are watertight (measured from their first end, so no cracks); a view at rest takes four samples a pixel (a drag draws a half-size draft). Tests: `test/cam_test.bend`; `test/native/pcb3d_frame.bend` writes both kinds of frame.
- `src/gfx/tiles.bend`: frames kept as 64 px tiles, each drawn in its own coordinates; the next frame redraws only tiles whose ops or base changed, and a tile the thread scrolled takes the image the last frame drew where it came from (`Past`, `Tiles.seek`; the shift hint is nui.bend's `Hits.slide`, and a wheel notch is one tile, `Nui.notch`) (laws `tiles_again_exact`, `frame_again_exact`, `tile_keep`, `seek_made`). The timeline keeps each entry's laid-out lines the same way (`TL.memo` in `layout.bend`, laws `tl_*`). Both compare with `src/core/eq.bend`/`Eq.*`, exact equalities whose soundness is proven, so nothing stale is reused.
- `src/gfx/bitmap.bend`: raw RGB frames (the browser helper's frame file) as an `Image` quadtree, composited into a frame at a place and size.
- `src/core/svg.bend` (pure: SVG path data parsed, written, flattened; laws `svg_*`) and `src/core/icons.bend` (the icon set, Lucide paths, ISC; laws `icons_*`). The window rasterizes them once into `SMask` bitmaps in the glyph cache (`src/gfx/icon.bend`, `Lay.icon`/`Lay.ibutton`); the web writes them as inline `<svg>` (`src/web/icon.bend`). Test: `test/svg_test.bend`.
- `tools/browser/`: `backplane-browser`, a Bun + playwright-core headless Chromium driven by NDJSON on stdin/stdout; raw frames go to a file. Pages are keyed by an owner (`"page"`: a bot's id for a bot's thread, else the thread's id, `BT.World.page`, so every thread drives its own; `""` is the shared page, which Backplane no longer uses), all in one persistent profile (`<home>/browser-profile`); each page's JPEG frames go to `<home>/shots/<owner>.jpg`. Bend side: `src/server/browser.bend` (`Browser.ask_on`, test `test/browser_test.bend`). Protocol in its README; `bun tools/browser/test/pages.ts` tests it. Built by `scripts/build-browser.sh`.
- `src/core/client.bend`: the client state and actions both UIs share. Each thread (a bot's too) has its own viewer: kind, path, diff and whether the panel is open live under `<key>:<thread>` in the info map (`Viewer.put`, `Ui.reselect` swaps the panel when the selection moves), and the window keeps each thread's camera and scene (`N.Park` in main.bend's `Kept`). The Browser tab shows the thread's own page (`Lay.page`). Test: `test/view_test.bend`; end to end `bun test/tools/viewers_e2e.ts`.
- `src/core/menu.bend` (pure: where a menu's boxes go: stacked rows, a wrapping flow of chips, rows that fit a height, a clamped scroll; laws `menu_*`) and `src/core/badge.bend` (a project's colour and icon from its settings; laws `badge_*`). The model picker (`Lay.picker` in layout.bend) and the badge editor (`Look.*`) place everything with them. Test: `test/menu_test.bend`. `test/native/ui_snap.bend` renders the window from an event log and an info message to a PPM with no window (`build/ui_snap EVENTS INFO THREAD FLAGS OUT [W H]`).
- `src/core/fold.bend`: runs of tool calls folded into one row (pure: groups, labels, per-entry roles; open state is `fold:<first id>` in the Ui info map, the "fold" action; laws `fold_*`). The window applies the roles each frame over the memo (`TL.entries.mr`, kind 14 lines), the web in `View.entries`. Test: `test/fold_test.bend`.
- `src/core/edit.bend`: text editing for the window's fields (word and line motions, ranges, undo history); `nui.bend`'s `Ed` maps keys onto it. Test: `test/edit_test.bend`. Thread text selection is `TSel` in `layout.bend` and `Sel.*` in `nui.bend` (test `test/select_test.bend`).
- `src/core/tailnet.bend` (pure: owner trust from `tailscale whois`, the owner's machines from `tailscale status`) and `src/app/link.bend` (a WebSocket client shaped like a hub, so the native window can switch to another machine's hub). Each hub finds the owner's other hubs (GET /hello) and lists them in the sidebar; `BACKPLANE_PEERS` names hubs off the tailnet.
- `src/core/diff.bend` (pure: unified diff → files, hunks, numbered lines; stats) and `src/server/git.bend` (IO: repo info, porcelain status, worktrees, hidden-ref checkpoints, stacked commit/push/PR). See `docs/git.md`. Native test: `bend test/native/git_test.bend -o build/git_test && build/git_test`.
- `src/core/hier.bend`: hierarchical schematics (pure: the sheets a file lists, paths resolved beside their parent, the tree as pre-order rows, where a row sits, its parent and children; a sheet that includes an ancestor is listed but never expanded; laws `hier_*`). main.bend's `Tree.load` reads every file the root reaches after each schematic read and sends the rows (`Sheets`); the window keeps them in the scratch (`@vw.tree`, `@vw.at`) and shows a trail and the sheet list (`Side.*` in layout.bend; actions `vw-sheet`, `vw-open`, `vw-up`). Test: `test/hier_test.bend`; headless: `test/native/sheet_frame.bend ROOT.kicad_sch`.
- The board viewer keeps its scene in (layer, key) order, which is paint order, so a frame is one pass (`V.Ops.scene`); items off the panel are culled before any geometry is transformed. Layers turn on and off per kind with a flip mask (`@vw.flip.<kind>`, `V.Look.on`; laws `look_flip_*`, `ops_hidden_draws_nothing`, `pick_hidden_skipped`). Bench: `test/native/board_frame.bend BOARD.kicad_pcb`.
- Bots in the window: `src/app/bots.bend` (`Bv`: the sidebar's cats and rooms under the projects, a bot's header and tabs, rooms, remote bots; `Bv.frame` wraps `Lay.frame.x`, whose hooks add to the sidebar and replace the main area), `src/app/space.bend` (`Spv`: a bot's space blocks drawn natively), `src/app/forms.bend` (`Fm`: clipped chips and form fields whose text is the client's `@f.<name>` scratch; nui.bend's `Fld` edits them, focus id `Fld.id(name, enter action, value prefix)`), `src/app/cats.bend` (`Cats`: core/cat.bend's cats flattened once per look+mood into a cache kept in main.bend's `Kept`, posed per frame). Cat frames: 33 ms timer (main.bend's `Shell.cats`) only while `Bv.moving` (a moving mood, window focused: `@blur`, no lightbox). A bot's browser frames load as images keyed `shot:<bot>:<n>` (main.bend's `Shot`). Screens without a window: `build/bots_snap DIR` (`test/native/bots_snap.bend`).
- `src/core/lightbox.bend`: the image lightbox (pure: zoom clamped and eased, cursor-anchored, drag pan, what closes it; laws `lightbox_*`). The web keeps its `Lb` in host.js and calls app.bend's `lb_*`; the window keeps it as text in the Ui scratch (`@lb`, `@lb.v`, nui.bend's `Lbx`) and main.bend's `Lbv` draws it with `Bitmap.view`.
- `src/core/vt.bend`: the terminal emulator (VT100/xterm: bytes in, styled rows, cursor, replies, key and paste bytes out); `src/server/pty.bend` + `effects/pty.c` run a shell on a pty whose master is a `Socket`. See `docs/terminal.md`.
- `src/web/`: the web client for other devices (Tailscale, phone). View logic is Bend; `host.js` only touches the DOM, canvas and socket, and holds no product logic.
- `test/`: Bend test programs (`bend test/x.bend`), run by `scripts/test.sh`.
- `src/mobile/`: the phone apps' client in Bend: `hubs.bend` (every paired hub at once: a `Ui` each, one merged screen, actions routed by the `host:port|id` their value carries; laws `hubs_*`), `screen.bend` (the shared `Ui` → a screen model as JSON), `notify.bend` (turn-end alerts and the Dynamic Island, laws `alert_*`), `picker.bend` (the project picker: one path field from `~/`, a tapped folder fills it in, over core's `Proj`; laws `mpick_*`, test `test/mpicker_test.bend`), `bots.bend` (the cats and rooms in the list, a bot's tabs, a room's posts; a cat is named by its key `look:mood` and the apps ask `Backplane.cat(key)` for each rig once; the bot, room and forms are the focused hub's, left unqualified; test `test/mbots_test.bend`), and `bridge.js`, which carries strings between them and the native app.
- `src/core/plot.bend` (pure: board/schematic items → chunks the phones draw, delta against what a phone holds, the wire and child-process formats; laws `plot_*`), `src/server/plot.bend` (the actor that watches files for phones and parses each in a `--plot` child process), `src/mobile/view.bend` (which source the phone's viewer asks for, and which tapped piece it inspects; laws `view_*`, `pick_*`). The phones draw plots on the GPU (Metal `mobile/ios/Backplane/PlotView.swift`, GLES 3 `.../PlotView.kt`); plot messages bypass the Bend bridge. Tests: `test/plot_test.bend`, `test/tools/plot_e2e.ts` (against a running hub), `test/native/plot_bench.bend`.
- `mobile/`: the phone apps. `ios/` is SwiftUI with a Live Activity widget, running bridge.js in JavaScriptCore; `android/` is Jetpack Compose with a foreground service, running it in QuickJS. `scripts/build-mobile.sh` builds bridge.js and the APK (needs an Android SDK); `scripts/build-ios.sh` builds on a Mac over SSH. Neither runs in CI. See `mobile/README.md`.
- The 3D viewer: `src/gfx/mesh.bend` (the z-buffered rasterizer: a chunk tree projected and binned into 64-px regions in parallel, regions dealt to cores in bit-reversed order, near-plane clipping, per-chunk fade-in), `src/gfx/face.bend` (a board drawn from its own items: the visible face as 2D ops projected through the camera and rasterized per region under the triangles; edge and hole walls as triangles; `Scene3`), `src/core/pcb3d.bend` (pure: stackup colours, thickness, silk text, each footprint's model and KiCad's placement transform, embedded models; laws `pcb3d_*`, `scene3_*`), `src/app/parts3.bend` (IO: model paths resolved, STEP converted once into `$XDG_CACHE_HOME/backplane-bend/models`). A board shows at once; models already converted arrive together; the rest convert on four workers; parts fade in unless they arrive within 350 ms of the board. While dragging, the 3D view draws at half size. Benches: `test/native/mesh_bench.bend` (a GLB), `test/native/pcb3d_frame.bend` (a `.kicad_pcb`).
- `tools/step2glb/`: the one non-Bend helper, a host tool like git or curl. It converts STEP to GLB (OpenCascade WASM via Bun; LGPL-2.1, run as a subprocess, never linked). `scripts/build-step2glb.sh` builds `dist/backplane-step2glb`. The STEP viewer reads its GLB; all viewer logic stays in Bend. See its README.
- `src/core/perf.bend` (pure: readings parsed and diffed, percentiles, the report, the overlay text, log levels; laws `perf_*`), `src/server/perf.bend` + `effects/perf.c` (the counters every process keeps, `Perf.lap`, `Log.*`, the Chrome trace). The window's frames, input-to-pixels and hub messages are timed; ctrl+shift+h shows the overlay; `GET /debug/perf` gives the table. See `docs/perf.md`. Test: `test/perf_test.bend`.
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

Performance: every process keeps counters (`docs/perf.md`). ctrl+shift+h in the window shows the overlay, `curl -s 127.0.0.1:3787/debug/perf` gives the table, `BACKPLANE_TRACE=/tmp/t.json` writes a Perfetto trace, `BACKPLANE_LOG=debug` and `BACKPLANE_SLOW_MS=50` log more.

Typing speed: `scripts/build-app.sh test/native/type_bench.bend build/type_bench && build/type_bench` replays keys through the event, memo, layout and tiles with no window and prints ms per key. Scrolling: `test/native/scroll_bench.bend` the same for wheel notches up and down, and checks each frame against one drawn from scratch.

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
- A recursive call in both branches of a `Bool.pick` (`Bool.pick(L, c, h <> go(t), go(t))`) doubles the work per element: 2^n. It passes a test with a few items and hangs on real data. Match on the Bool in a helper (`Stats.prefix.k` in core/perf.bend).
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
- A multi-match that discards a cons tail with `_` next to another scrutinee fails ("_ consumed more than once"): bind it (`case +h <> +r True{}:`).
- Only tail calls are free: a walk that builds its result outside the recursive call (`String.repeat`, `Utf8.encode_onto`, `Json.items`) overflows the stack around a few hundred thousand steps. For big inputs, push onto a reversed accumulator and reverse once (`Enc.go` in cbor.bend).
- In `win.c`, an Xlib call outside the pump (XPutImage, XFlush...) can pull input into Xlib's queue while the pump sleeps on the socket; call `win_nudge(a)` after it or keys show one keystroke late.
- "Error: an arity over 255" from a C build (never from `--check-only`) came from one expression reusing a `+` binder through nested calls (`Nui.with_ui(Hint.set(n, ""), U.Ui.scratch_set(Nui.ui(Hint.set(n, "")), …))`). Name the step in a helper (`Blur.set(Hint.set(n, ""), "1")`). Bisect with a tiny program that calls the suspect and `bend x.bend -o x.c` (C emission only, ~25 s); JS-only tests like `test/menu_test.bend` fail this way on main too, so don't bisect with them.
- Effect C must not contain the word `undefined`, even in a comment: bend reads it as a missing name and stops with "an unbound name in the emitted C" (vendored code included, e.g. stb_image in `src/app/effects/img.c`).
- `Bool.and`/`Bool.or` are strict: both sides are always computed. An `Eq.*` over a list compares all of it.
- `U32.shr(x)` shifts by one; `U32.shrn(x, n)`/`U32.shln(x, n)` take a Nat count.
- A `+n: Nat` parameter makes the `1n+k` predecessor reusable too; with a plain `n`, `k` may be used once.
- In dash (`/bin/sh`), `${d#~/}` expands the `~` first and strips nothing; use `${d#??}`.
- The glyph cache's string-keyed `Map` is slow per glyph; `Text.get` reads ASCII from the face's `GTab` (filled by `Face.tabled` once warmed).
- A long-lived native process gets slower at the same allocation-heavy work each time it repeats it, memory flat (bendlang/bend#1007: free chains lose address order; a board parse 0.2 s → 1.6 s over six runs). Keep big repeated work out of the hub: parse in a child process (`backplane --plot`, src/server/plot.bend) and keep bulky data out of hub memory (plot info tables live in files). `BACKPLANE_BENCH_RUNS=6 build/plot_bench FILE` shows it.
- "an arity over 255" at `-o` (not at `--check-only`) means a value held in the app's state flattened into too many fields: a deep record type (the board face inside the viewer's `Vx`). Put the deep part behind a `List` (`Scene3.face`).
- `Nat.read` (and `Maybe.map` over it) in anything a law normalizes makes `bend PROOF.bend` crawl for minutes. Parse digits yourself (`Switch.num` in model.bend, `Tag.num` in hub.bend), and time a new law alone before the full run.
- `.` and `_` mangle alike in C: `TL.mine.of` and `TL.mine_of` both become `..._TL_MINE_OF`, and the native build stops with "two names mangle to". `--check-only` does not catch it.
- Launch time: nothing slow may run before the window opens (probes, network, full log copies). Start it after, in the background, and serve the last answer meanwhile (`src/core/boot.bend`). `test/native/boot_bench.bend` times start-up and frames on a real log.
- CPU forks are dealt out once, not stolen: fork over one flat balanced tree of work items (all primitives of all nodes) rather than nesting forks per group; nested forks inside a heavy group barely spread.

## House rules

- Never kill processes by name or pattern; only PIDs you captured.
- Never write to live user data (`~/.backplane-bend/`). Tests use a temp `BACKPLANE_HOME`.
- Persisted events stay decodable forever. Add event variants; never change the meaning of an existing one.
- No continuous repaint loops. The viewer animates only while a fade is in flight, then stops requesting frames.
- The UI is dumb: every decision (order, settle state, fade alpha, what's visible) comes from a Bend def with a law behind it where possible.
- Square corners, minimal copy, no decorative headings.
- Before pushing, verify the GitHub account (`i2cjak`), the remote, and the branch.
