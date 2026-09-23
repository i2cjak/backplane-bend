# Backplane (Bend)

An agentic hardware development environment, written in
[Bend](https://bend-lang.com). It pairs agent threads (Claude Code) with a
live KiCad board viewer, in a native window drawn entirely by Bend.

- **Threads** per project, as in T3Code. They go *Settled* after three days of inactivity, and everything is kept in a local event log.
- **A deterministic board viewer.** It always shows the file as it is now, never a half-written save. When the file changes, only what changed fades in, and an unchanged board never flickers. That last property is a proven law, not a hope.
- **Laws.** The rules that matter are stated in [`LAWS.bend`](LAWS.bend) and proven in [`PROOF.bend`](PROOF.bend). `bend PROOF.bend` checks every one.

![Backplane](docs/media/native-viewer.png)

## Install

```sh
curl -fsSL https://github.com/i2cjak/backplane-bend/releases/latest/download/install.sh | sh
backplane
```

This installs into `~/.local/share/backplane` and links the binaries into `~/.local/bin`.

- The installer checks the sha256 of what it downloads.
- Backplane updates itself from GitHub releases. Set `BACKPLANE_NO_UPDATE=1` to turn that off.
- `backplane` opens the window. Without a display it keeps serving the web client on `127.0.0.1:3773`.
- `backplane-serve` runs headless.

## Build

You need [Bend](https://bend-lang.com), clang 19+, X11 headers (`libx11-dev`), and bun for the tests.

```sh
scripts/check.sh   # type-check everything, prove every law
scripts/test.sh    # unit tests
scripts/build.sh   # dist/backplane, dist/backplane-serve, dist/web
scripts/smoke.sh   # start the built server and poke it
```

[AGENTS.md](AGENTS.md) describes the layout and the Bend traps worth knowing.

## Laws

| Law | Promise |
|---|---|
| `settle_*` | A thread settles after its window, stays settled as time passes, and never while running, waiting on you, or brought back by hand. |
| `replay_snoc` | The live view and a cold replay of the log never disagree. |
| `sidebar_split_count` | Every thread is on exactly one sidebar shelf. |
| `scene_merge_self` | Re-reading an unchanged board re-fades nothing. |
| `fade_start`, `fade_done` | Fades start invisible and always finish. |
| `update_never_same` | The updater never offers the version already running. |
