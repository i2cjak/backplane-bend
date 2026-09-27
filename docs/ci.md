# CI

`.github/workflows/ci.yml` runs on pushes to main and on PRs. Pushes and
same-repo PRs run on self-hosted runners on the dev machine; fork PRs run on
GitHub's runners. Releases and nightlies (`release.yml`, `nightly.yml`) always
build on GitHub's runners: they publish with a write token, and a release
should come from a clean machine.

## The pipeline

| job | runs when | where |
| --- | --- | --- |
| Plan | always (a few seconds) | GitHub (`ubuntu-24.04`) |
| Check and prove (`scripts/check.sh`) | any Bend, script or workflow change | light slot |
| Tests (`scripts/test.sh`) | same | light slot |
| Build linux-x64 (`scripts/ci/build.sh`, smoke, artifact) | anything a binary is built from | heavy slot |
| Build linux-arm64 | main, the `arm64` label, a manual run, or C / build-script changes | GitHub (`ubuntu-24.04-arm`) |

- **Plan** lists the changed files (the PR's files, or the push's compare).
  Docs, `*.md`, `mobile/` (the phone apps are built by `scripts/build-*.sh`,
  not CI), `deploy/aur`, `deploy/ci` alone: nothing else runs. Bend no binary
  includes (`src/mobile/`, `test/*_test.bend`, `test/tools/`, `LAWS.bend`,
  `PROOF.bend`): checks and tests, no build. A new branch, a manual run or a
  compare over 300 files: everything. Its summary says what it chose and why.
- The build no longer waits for the checks: they run side by side.
- `check.sh` and `test.sh` run their files side by side (`BEND_JOBS`, default
  half the cores); the proof runs beside the checks. Output and exit status
  are as before.
- **Concurrency**: one run per PR, and a new push cancels the one in flight.
  On main a run in flight finishes (its build is that merge's artifact) and
  pushes that arrive meanwhile collapse into one pending run. Before, each
  push to main cancelled the last, so in a burst of merges most were never
  built.

### Timings

Before (GitHub's runners, the last runs on main and PRs): 25-27 min, the x64
build (17 min) waiting on the checks (5-8 min). After, on PR #75:

| | before | self-hosted, cold | same tree again |
| --- | --- | --- | --- |
| Check and prove | 5.2-8.1 min | 2.7 min | 2.5 min |
| Tests | 2.8-3.3 min | 1.9 min | 1.7 min |
| Build linux-x64 | 16.9-18.2 min | 13.2 min | 0.8 min |
| whole run | 25-27 min | 13.4 min | ~2.5 min without arm64 |

A cold build is bend's emit (about 3 min for the app) and clang; the tree
cache makes the push to main after a merge a copy. Docs-only and
`mobile/`-only changes run only the plan job (seconds).

### Native compile on the slots

`build-app.sh` splits the emitted C into units; each unit carries the
prelude (~10 MB of tables) and its share of the segments, and a unit's
clang peak follows the segment code in it: 16 units take ~62 s and 4.5 GB
each, 48 take ~24 s and 2 GB. Eight 16-unit compiles thrashed the slice;
the slots use 48 units and 6 jobs (`BACKPLANE_UNITS`, `BACKPLANE_JOBS`).
They compile with zig's clang, which adds DWARF by default (a 115 MB
server), so `BACKPLANE_CFLAGS=-O3 -g0` (about 20% faster, 16 MB).

### Caches (self-hosted only)

Everything lives in `~/.cache/bp-ci/shared`, outside the job's sandbox home,
so it survives the per-job wipe:

- `toolcache/bend/`: the Bend archive (`setup-bend` checks its pinned sha256
  on every use), and bun (`oven-sh/setup-bun`).
- `build/dist/<key>`: a whole `dist/`, keyed by the git tree of `src scripts
  tools patches assets`, bend, clang and bun versions (`scripts/ci/build.sh`).
  A merge to main builds the tree its PR already built, so that build is a
  copy. The newest 8 are kept (~300 MB each).
- `build/cc/<key>`: each native binary keyed by the C bend emitted for it
  (`BACKPLANE_CC_CACHE` in `scripts/build-app.sh`). A change that leaves a
  binary's C alone (web only, or the app but not the server) skips its clang
  run. Per-unit ccache would not help: every unit carries the prelude's
  tables, which change with any def.
- `zig/`: zig's own cache (its compiler-rt and libc stubs).
- `bun/`: bun's install cache for `tools/*`.

## The runners

`deploy/ci/` holds everything; `deploy/ci/bp-ci install` sets it up for the
user running it (no root):

- `~/.local/share/bp-ci/`: the manager (`bp-ci`, linked into `~/.local/bin`),
  the slot script, the official `actions/runner` (latest release, checked
  against its published sha256, re-checked every 12 hours).
- `~/.config/bp-ci/`: `config` (repo, zig path) and one `slots/<name>.env`
  per slot.
- `~/.config/systemd/user/`: `bpci.slice`, `bp-ci.target`,
  `bp-ci-runner@.service`.

Default slots: `heavy1` (native builds), `light1`, `light2` (checks, tests),
`prio1` (the priority queue). Labels: every slot has `self-hosted, linux,
x64, backplane-local`; heavy adds `backplane-heavy`, light `backplane-light`,
and both also `backplane-priority`; `prio1` has only `backplane-priority`.

```sh
bp-ci stop        # stop every slot; CI routes to GitHub's runners
bp-ci start       # start them; CI routes here again
bp-ci status      # slots, the slice's memory, the runners GitHub sees
bp-ci add light3 light
bp-ci remove light3
bp-ci uninstall   # everything but ~/.cache/bp-ci/shared
```

`stop` and `start` also set the repo variable `BP_CI_LOCAL` (off / on); the
plan job routes on it, so jobs never queue for runners that are down.
`systemctl --user stop bp-ci.target` alone stops the slots but leaves the
variable on (jobs would then wait for them). A stopped slot unregisters its
runner (`bp-ci forget`, the unit's `ExecStopPost`): GitHub otherwise keeps
a killed runner "online" for minutes and hands it jobs that never start.

### One job per runner, in a sandbox

Each slot (`bp-ci-slot`) asks GitHub for a just-in-time runner config (a
single-job registration; the admin `gh` token that asks never enters the
sandbox), wipes and recreates its directory, and starts the runner in
`bwrap`:

- the machine read-only; `/home` replaced, so the job sees none of the real
  home (`~/.config/gh`, `~/.ssh`, `~/.backplane-bend`, the projects); its home
  is a fresh directory, with zig, the X11 headers and the shared cache bound in;
- its own `/tmp` (on disk; the machine's `/tmp` is RAM), except the
  machine-wide build lock `/tmp/bp-wt-build.lock`;
- `/run/user` empty: no systemd or D-Bus socket, so a job cannot
  `systemctl --user stop backplane-bend`;
- its own PID namespace: it cannot see or signal the hub or anything else;
- the network is shared (it needs GitHub).

After the job the runner exits, GitHub drops the registration, and systemd
starts the slot again from scratch.

### Keeping the hub safe

- `bpci.slice` sits beside `app.slice` (where `backplane-bend.service` runs):
  `CPUWeight=20` against the hub's 100, `MemoryHigh=20G`, `MemoryMax=22G`,
  `MemorySwapMax=2G`. A runaway compile is reclaimed and then killed inside
  the slice. (Named without a dash on purpose: `bp-ci.slice` would nest under
  `bp.slice`, and weights only compare siblings.)
- One native build at a time, machine-wide: `scripts/build-app.sh` holds
  `/tmp/bp-wt-build.lock`, which the sandbox shares, so CI builds also queue
  behind (and ahead of) the agents' dev builds. A build peaks near 14 GB
  (bend's emit, heap capped at 12 GB).
- Light slots tell bend's Bun heap the machine has 6 GB
  (`BUN_JSC_forceRAMSize`); the build step sets it back to 12 GB.
- The units never touch `backplane-bend.service`.

## Priority

A PR labelled `priority`, or a manual run (`gh workflow run ci.yml -f
priority=true --ref BRANCH`), sends every job to `backplane-priority`. The
`prio1` slot takes nothing else, so one is always free; the other slots take
priority jobs too, so a priority run uses them when they are idle.

The label is read when the run starts (from the API, so a re-run sees it):
add it, then push or re-run. CI does not trigger on `labeled`: a run for
every label would cancel the real run, and its skipped jobs would stand in
for the real checks.

Trade-offs: `prio1` sits idle most of the time (a job slot's worth of
capacity, no compute cost). A priority build still waits for a native build
already holding the build lock (at most one build, ~5 min); preempting it
would mean cancelling someone's run. Anything cleverer (a dispatcher that
pauses low-priority runners) buys little on one machine.

## Scaling

Recommendation: a fixed pool of ephemeral slots, sized by memory, on this
machine; no autoscaler.

- An idle slot is one runner process (~100 MB) long-polling GitHub; it costs
  nothing to keep. Capacity is bounded by RAM and the one-build lock, not by
  how many runners are registered, so scaling runner count up and down on
  one box saves nothing.
- `bp-ci add` / `remove` is the knob. Four slots are about the limit: a
  build overlapping checks and tests peaked at 20.4 GB, at the slice's
  `MemoryHigh` (reclaim, not a kill; the hard cap is 22 GB). More slots
  would mean throttled jobs, not more throughput.
- **actions-runner-controller** (ARC, on k3s): the standard for autoscaling
  (scale sets, ephemeral pods, webhook- or listener-driven). It needs
  Kubernetes and a container runtime (root to install), and the build would
  run in containers without the toolchain and caches on this host. Worth it
  once there are several machines or a cloud pool, not for one box.
- **Webhook/poll autoscaler** (a `workflow_job` webhook or a poll of queued
  jobs starting `bp-ci-runner@N` up to a cap): about 50 lines, but it only
  adds value when capacity costs money (cloud VMs that can be stopped), e.g.
  a spot instance for arm64 or a second x64 builder. If that day comes,
  start there, or use a hosted autoscaler (RunsOn, Ubicloud) rather than ARC.
- arm64 stays on GitHub's runners (this machine is x64). Free for a public
  repo, and now only on main or when asked.

## Security

The repo is public, so a runner here would run whatever a PR's author
writes. What bounds it:

1. Only pushes to main and PRs from branches of this repo (people with
   write access) route here; fork PRs go to GitHub's runners (the plan
   job's `TRUSTED`). A fork cannot change that: the workflow of a
   `pull_request` run comes from the PR, but only same-repo PRs pass the
   check, and fork PRs from outside collaborators wait for approval
   (the repo requires approval for all outside collaborators).
2. The job runs as `h` but in the sandbox above: no real home, no systemd
   bus, no host PIDs, a single-job registration.
3. Resource limits keep a job from starving the hub.

What remains:

- The network is shared: a job can reach services on localhost, the hub on
  `:3787` included, and the tailnet.
- The shared caches are writable by jobs, so a job could poison a later
  job's cached `dist/` or tools. Only trusted code runs here, and releases
  never use these caches.
- Everything outside `/home` is readable (as it is to any local program run
  as `h`).
- Anyone with write access effectively runs code on this machine; that was
  already true through the agents.

Stricter isolation would need root: a separate `ci` user, or rootful
containers/VMs per job (e.g. ARC or Firecracker-based runners).

## Other CI/CD systems

For this project (one maintainer, GitHub-hosted repo and PRs, one dev
machine, a heavy native build, a public repo that wants free arm64) GitHub
Actions plus self-hosted runners is the best fit today. When each
alternative would beat it:

- **Forgejo / Gitea Actions**: GitHub-Actions-compatible YAML run by
  `act_runner`, on a self-hosted forge. Wins if the code moves off GitHub
  (self-hosting everything, or GitHub's limits). Most of `ci.yml` would
  carry over; the phone-app and release flows that use GitHub releases
  would not.
- **Woodpecker** (a Drone fork, Apache-2.0): small, container-per-step,
  simple YAML, works with GitHub. Wins if every step should run in a
  container with a cleaner isolation story than bwrap and there is Docker
  or Podman to run it. Weaker at caching the host's toolchain.
- **Buildkite** (the agent is OSS; the control plane is SaaS): the best
  queue and priority model of the lot (queues, job priorities, dynamic
  pipelines, agents anywhere). Wins if priority queues and many machines
  matter more than staying in GitHub's UI; free tier for open source.
- **Drone**: the upstream of Woodpecker, now Harness-owned with a
  restrictive license for the enterprise parts. Choose Woodpecker instead.
- **Jenkins**: runs anything with plugins, heavy to keep up (JVM, plugin
  upgrades, security). Only if an organisation already runs one.
- **Dagger**: not a CI system but a way to write the pipeline once (in Go,
  Python or TS) and run it identically on a laptop and in any CI. Wins if
  "works locally, fails in CI" becomes a problem; the caches become Dagger
  cache volumes. Needs a container engine.

None changes the main cost: the native build. The wins here came from
caching, not rebuilding what did not change, and running jobs side by side.
