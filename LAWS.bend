import Base
import ./src/core/bothub.bend as BHS
import ./src/core/bot.bend as BOT
import ./src/core/botui.bend as BU
import ./src/core/model.bend as M
import ./src/app/viewer.bend as V
import ./src/core/semver.bend as SV
import ./src/app/nui.bend as N
import ./src/core/board.bend as B
import ./src/core/hub.bend as H
import ./src/core/todo.bend as TD
import ./src/core/acp.bend as AC
import ./src/core/mcp.bend as MC
import ./src/core/handoff.bend as HD
import ./src/core/agent.bend as AG
import ./src/core/tailnet.bend as TN
import ./src/core/fuzzy.bend as FZ
import ./src/mobile/notify.bend as Nt
import ./src/core/codec.bend as C
import ./src/core/json.bend as J
import ./src/core/attach.bend as AT
import ./src/gfx/tiles.bend as T
import ./src/gfx/raster.bend as R
import ./src/gfx/draw.bend as D
import ./src/app/layout.bend as L
import ./src/core/eq.bend as Q
import ./src/core/svg.bend as SVG
import ./src/core/icons.bend as ICO
import ./src/core/lightbox.bend as LBX
import ./src/core/links.bend as LK
import ./src/core/client.bend as U
import ./src/core/gh.bend as GH
import ./src/gfx/text.bend as X
import ./src/core/fold.bend as FO
import ./src/core/http.bend as WS
import ./src/core/plot.bend as PL
import ./src/mobile/view.bend as MV
import ./src/core/pcb3d.bend as P3
import ./src/gfx/mesh.bend as MS
import ./src/gfx/face.bend as FA
import ./src/core/glb.bend as G
import ./src/core/menu.bend as MN
import ./src/app/win.bend as W
import ./src/core/badge.bend as BG

import ./src/mobile/picker.bend as MP
import ./src/mobile/hubs.bend as Hb
import ./src/core/hier.bend as HI

import ./src/core/boot.bend as BT
import ./src/core/store.bend as ST
import ./src/core/sign.bend as SG
import ./src/core/ring.bend as RG
import ./src/core/cron.bend as CR
import ./src/core/space.bend as SPC
import ./src/core/google.bend as GO
import ./src/core/cat.bend as CAT
import ./src/core/perf.bend as PF
import ./src/core/voice.bend as VO
import ./src/core/once.bend as ON

# Backplane's rules, stated over the real code. `bend PROOF.bend` proves each
# one. Humans own this file: an agent may add laws, never weaken or delete
# one without the user's explicit consent.

# Equality
# --------

# a string always equals itself (viewer keys and ids rely on it)
law string_eq_refl:
  for +s: String
  {String.eq(s, s) == True{} : Bool}

# Settling
# --------

# a thread settles once the window has fully passed since its last activity
law settle_at_window:
  for +last: Nat
  for +w: Nat
  {M.Settle.stale(Nat.add(last, w), last, w) == True{} : Bool}

# a thread touched just now never settles, for any non-empty window
law settle_fresh:
  for +now: Nat
  for +w: Nat
  {M.Settle.stale(now, now, 1n+w) == False{} : Bool}

# once stale, a thread stays stale as time moves forward
law settle_monotone:
  for +now: Nat
  for +last: Nat
  for +w: Nat
  for +d: Nat
  for h: {M.Settle.stale(now, last, w) == True{} : Bool}
  {M.Settle.stale(Nat.add(now, d), last, w) == True{} : Bool}

# a running turn never auto-settles
law settle_never_running:
  for +now: Nat
  for +w: Nat
  for pending: Nat
  for archived: Bool
  for o: M.Override
  {M.Settle.auto.k(M.Thread.busy(M.Running{}, pending), archived, o, M.Settle.stale(now, now, w)) == False{} : Bool}

# a thread waiting on the user (approval, question) never auto-settles
law settle_never_pending:
  for t: M.TurnState
  for +p: Nat
  for archived: Bool
  for o: M.Override
  for stale: Bool
  {M.Settle.auto.k(M.Thread.busy(t, 1n+p), archived, o, stale) == False{} : Bool}

# a thread the user brought back stays back: no auto-settle overrides them
law settle_respects_unsettle:
  for busy: Bool
  for archived: Bool
  for stale: Bool
  {M.Settle.auto.k(busy, archived, M.ForcedActive{}, stale) == False{} : Bool}

# Event sourcing
# --------------

# folding one more event equals replaying the longer log: the live read
# model and a cold replay of the database can never disagree
law replay_snoc:
  for es: List<&2, M.Change>
  for s: M.State
  for e: M.Change
  {M.State.replay(List.append(&2, M.Change, es, [e]), s) == M.State.apply(M.State.replay(es, s), e) : M.State}

# Sidebar
# -------

# every thread lands on exactly one shelf: none lost, none duplicated
law sidebar_split_count:
  for ts: List<&2, M.Thread>
  {M.Shelves.count(M.Sidebar.split(ts)) == List.length(&2, M.Thread, ts) : Nat}

# every thread lands on exactly one shelf with snoozes too: none lost,
# none duplicated
law sidebar_split_at_count:
  for ts: List<&2, M.Thread>
  for +navs: Map<&2, M.Nav>
  for +now: Nat
  {M.Shelves.count(M.Sidebar.split.at(ts, navs, now)) == List.length(&2, M.Thread, ts) : Nat}

# Snooze
# ------

# a snoozed thread never auto-settles while its snooze lasts
law settle_never_snoozed:
  for +now: Nat
  for +w: Nat
  for t: M.Thread
  for +until: Nat
  for h: {Nat.is_ge(now, until) == False{} : Bool}
  {M.Settle.auto.at(now, w, t, until) == False{} : Bool}

# a snooze ends by the clock alone: once its time has come the thread is
# awake, with no event needed
law snooze_wakes:
  for +now: Nat
  for +until: Nat
  for h: {Nat.is_ge(now, until) == True{} : Bool}
  {M.Snooze.on(now, until) == False{} : Bool}

# Manual order
# ------------

# past any place on a shelf there is a later one
law key_after:
  for s: List<&2, Bool>
  {M.Key.lt(s, M.Key.after(s)) == True{} : Bool}

# the key made between two places sorts after the first...
law key_mid_above:
  for a: List<&2, Bool>
  for b: List<&2, Bool>
  for h: {M.Key.lt(a, b) == True{} : Bool}
  {M.Key.lt(a, M.Key.mid(a, b)) == True{} : Bool}

# ...and before the second: a dragged thread lands strictly between its
# neighbours, and they keep their keys
law key_mid_below:
  for a: List<&2, Bool>
  for b: List<&2, Bool>
  for h: {M.Key.lt(a, b) == True{} : Bool}
  {M.Key.lt(M.Key.mid(a, b), b) == True{} : Bool}

# a project dragged into place sits above every project never dragged
law project_keyed_first:
  for x: Bool
  for xs: List<&2, Bool>
  for a: U.SRow
  for b: U.SRow
  {U.PSlot.before(U.PSlot{x <> xs, a}, U.PSlot{Nil{}, b}) == True{} : Bool}

# and one never dragged sits below every one that was
law project_unkeyed_below:
  for a: U.SRow
  for y: Bool
  for ys: List<&2, Bool>
  for b: U.SRow
  {U.PSlot.before(U.PSlot{Nil{}, a}, U.PSlot{y <> ys, b}) == False{} : Bool}

# Sidebar status
# --------------

# an approval waiting outranks everything on a thread's dot
law status_approval_first:
  for i: Bool
  for t: M.TurnState
  for q: Bool
  {M.Status.of(True{}, i, t, q) == M.StApproval{} : M.Status}

# then a question or plan waiting, even while a turn runs
law status_input_before_work:
  for t: M.TurnState
  for q: Bool
  {M.Status.of(False{}, True{}, t, q) == M.StInput{} : M.Status}

# then a running turn, even with messages queued
law status_working_before_queued:
  for q: Bool
  {M.Status.of(False{}, False{}, M.Running{}, q) == M.StWorking{} : M.Status}

# a failed turn shows as failed even with messages queued
law status_failed_before_queued:
  for q: Bool
  {M.Status.of(False{}, False{}, M.Failed{}, q) == M.StFailed{} : M.Status}

# nothing on a thread outranks an approval
law status_approval_top:
  for a: Bool
  for i: Bool
  for t: M.TurnState
  for q: Bool
  {Nat.is_ge(M.Status.rank(M.StApproval{}), M.Status.rank(M.Status.of(a, i, t, q))) == True{} : Bool}

# Thread phase
# ------------

# an approval waiting outranks everything on a thread's phase line
law phase_approval_first:
  for i: Bool
  for n: Nat
  for t: M.TurnState
  for q: Bool
  {M.Phase.of(True{}, i, n, t, q) == M.PhApproval{} : M.Phase}

# then a question or plan waiting, even while a turn or tasks run
law phase_input_before_work:
  for n: Nat
  for t: M.TurnState
  for q: Bool
  {M.Phase.of(False{}, True{}, n, t, q) == M.PhInput{} : M.Phase}

# a running turn is working, whatever its child tasks do
law phase_working_before_tasks:
  for n: Nat
  for q: Bool
  {M.Phase.of(False{}, False{}, n, M.Running{}, q) == M.PhWorking{} : M.Phase}

# a finished turn with child tasks still running is monitoring them, not complete
law phase_monitoring_before_complete:
  for n: Nat
  for q: Bool
  {M.Phase.of(False{}, False{}, 1n+n, M.Completed{}, q) == M.PhMonitoring{1n+n} : M.Phase}

# a finished turn with nothing left running or queued is complete
law phase_complete:
  {M.Phase.of(False{}, False{}, 0n, M.Completed{}, False{}) == M.PhComplete{} : M.Phase}

# a failed turn shows as failed even with messages queued
law phase_failed_before_queued:
  {M.Phase.of(False{}, False{}, 0n, M.Failed{}, True{}) == M.PhFailed{} : M.Phase}

# only a thread with nothing yet has no phase line
law phase_silent_only_idle:
  for a: Bool
  for i: Bool
  for n: Nat
  for t: M.TurnState
  for q: Bool
  {String.is_empty(M.Phase.label(M.Phase.of(a, i, n, t, q))) == String.eq(M.Phase.name(M.Phase.of(a, i, n, t, q)), "idle") : Bool}

# Board viewer
# ------------

# re-reading an unchanged board changes nothing: every item keeps its birth
# time, so nothing re-fades or flickers (the viewer's no-jitter promise)
law scene_merge_self:
  for ss: List<&2, V.Seen>
  for +now: Nat
  {V.Scene.update(ss, V.Scene.items(ss), now) == ss : List<&2, V.Seen>}

# a new item starts invisible
law fade_start:
  for +born: Nat
  {V.Fade.alpha(born, born) == 0 : U32}

# and is fully drawn once its fade time has passed, at any later time
law fade_done:
  for +born: Nat
  for +k: Nat
  {V.Fade.alpha(Nat.add(Nat.add(born, V.Fade.ms()), k), born) == 255 : U32}

# Layers the user turns on and off
# --------------------------------

# with nothing flipped every layer looks exactly as by default
law look_flip_none:
  for +kind: U32
  for +layer: U32
  {V.Look.on(kind, layer, 0) == V.Look.of(kind, layer) : U32 & U32}

# flipping a shown layer hides it (F.Cu)...
law look_flip_hides:
  {V.Look.shows(0, 12, V.Look.toggle(0, 12)) == False{} : Bool}

# ...and flipping a hidden one shows it (F.CrtYd)
law look_flip_shows:
  {V.Look.shows(0, 17, V.Look.toggle(0, 17)) == True{} : Bool}

# flipping a layer twice gives it back
law look_flip_twice:
  {V.Look.toggle(V.Look.toggle(4096, 12), 12) == 4096 : U32}

# an item on a hidden layer draws nothing, wherever it is and however new
law ops_hidden_draws_nothing:
  for +p: B.Prim
  for +l: U32
  for +v: V.View
  for +c: D.Clip
  for +now: Nat
  for +born: Nat
  for +kind: U32
  for +flip: U32
  for +rest: List<&2, R.Op>
  for h: {V.Look.shows(kind, l, flip) == False{} : Bool}
  {V.Ops.gate(True{}, p, l, v, c, now, born, kind, flip, rest) == rest : List<&2, R.Op>}

# and a click never picks it: the best pick so far stays
law pick_hidden_skipped:
  for hit: Bool
  for +area: F32
  for +key: String
  for bk: String
  for +ba: F32
  {V.Pick.better((hit, area), False{}, key, (bk, ba)) == (bk, ba) : String & F32}

# Updates
# -------

# a version is equal to itself
law semver_cmp_refl:
  for +v: SV.Ver
  {SV.Ver.cmp(v, v) == EQ{} : Cmp}

# the updater never offers the version already running
law update_never_same:
  for +v: SV.Ver
  {SV.Ver.newer(v, v) == False{} : Bool}

# a prerelease (a nightly) sorts before the release of its version
law semver_pre_before_release:
  for +a: Nat
  for +b: Nat
  for +c: Nat
  for +d: Nat
  for +n: Nat
  {SV.Ver.newer(SV.Ver{a, b, c, False{}, 0n, 0n}, SV.Ver{a, b, c, True{}, d, n}) == True{} : Bool}

# a later nightly build of the same day is newer
law semver_nightly_later:
  for +a: Nat
  for +b: Nat
  for +c: Nat
  for +d: Nat
  for +n: Nat
  {SV.Ver.newer(SV.Ver{a, b, c, True{}, d, 1n+n}, SV.Ver{a, b, c, True{}, d, n}) == True{} : Bool}

# a nightly from a later day is newer, whatever its build number
law semver_nightly_next_day:
  for +a: Nat
  for +b: Nat
  for +c: Nat
  for +d: Nat
  for +n: Nat
  for +m: Nat
  {SV.Ver.newer(SV.Ver{a, b, c, True{}, 1n+d, m}, SV.Ver{a, b, c, True{}, d, n}) == True{} : Bool}

# Attachments
# -----------

# a stored attachment's name uses only letters, digits, '.', '_' and '-',
# so no name can reach outside its thread's directory
law attach_clean_ok:
  for s: String
  {AT.Att.all_ok(AT.Att.clean(s)) == True{} : Bool}

# a dropped uri-list line that is not a file: URI (http:, a '#' comment,
# anything not starting with 'f') attaches nothing
law drop_non_file_ignored:
  for c: Char
  for s: String
  for rest: List<&2, String>
  for h: {Char.is_eq(c, 'f') == False{} : Bool}
  {AT.Att.uri.one(SCon{c, s}, rest) == rest : List<&2, String>}

# a file manager's drop: file: URIs (any host) come back as their decoded
# paths, in order; comments and other schemes are dropped
law drop_uri_list_example:
  {AT.Att.uri_list("# nautilus\r\nfile:///home/me/My%20Board%C3%A9.png\r\nhttps://x.org/a.png\r\nfile://localhost/tmp/b%25.txt\r\n") == ["/home/me/My Boardé.png", "/tmp/b%.txt"] : List<&2, String>}

# Models working together
# -----------------------

# a finished, failed or cancelled task never changes state again
law task_terminal_absorbing:
  for cur: M.TaskState
  for want: M.TaskState
  for h: {M.TaskState.terminal(cur) == True{} : Bool}
  {M.TaskState.next(cur, want) == cur : M.TaskState}

# a running task never goes back to the queue
law task_never_requeued:
  {M.TaskState.next(M.TaskRunning{}, M.TaskQueued{}) == M.TaskRunning{} : M.TaskState}

# once delivered to its parent, a task's result is never delivered again
law task_delivered_once:
  for t: M.Task
  {M.Task.pending(M.Task.delivered_set(t)) == False{} : Bool}

# delegation stops at the depth limit: no chain of models spawning models
# grows without end
law delegation_bounded:
  for +k: Nat
  {M.Task.may_delegate(Nat.add(M.Task.max_depth(), k)) == False{} : Bool}

# Settings
# --------

# a setting never set reads as its default (settings are events, so a
# fresh or replayed store agrees on every unset key)
law setting_default:
  for +k: String
  for +d: String
  {M.Setting.get(M.State.empty(), k, d) == d : String}

# Viewer sources
# --------------

# giving the window back its own viewer changes nothing
law nui_with_own_vw:
  for n: N.Nui
  {N.Nui.with_vw(n, N.Nui.vw(n)) == n : N.Nui}

# a scene read for a source the viewer no longer shows changes nothing:
# switching views or projects can never show a stale file
law stale_board_ignored:
  for n: N.Nui
  for +key: String
  for items: List<&2, B.Item>
  for +now: Nat
  for h: {N.Vw.fresh_for(N.Nui.vw(n), key) == False{} : Bool}
  {N.Nui.board(n, key, items, now) == n : N.Nui}

# Delivery
# --------

# a client that reconnects with the first changes already folded, and
# folds only what it missed, holds exactly what a cold replay gives
law resume_is_replay:
  for a: List<&2, M.Change>
  for b: List<&2, M.Change>
  for s: M.State
  {M.State.replay(List.append(&2, M.Change, a, b), s) == M.State.replay(b, M.State.replay(a, s)) : M.State}

# a message for a Codex or Grok thread whose turn is running starts no
# agent: it is stored and waits (one turn at a time per session)
law queue_never_concurrent:
  for +s: M.State
  for +now: Nat
  for +th: String
  for +msg: String
  for role: M.Role
  for +text: String
  for h1: {H.Hub.running(H.Hub.thread(s, th)) == True{} : Bool}
  for h2: {String.eq(H.Hub.provider(H.Hub.thread(s, th)), "claude") == False{} : Bool}
  {H.Step.outs_of(H.Hub.post(s, now, th, msg, role, text)) == [] : List<&2, H.Out>}

# a message the server already stored (resent after a dropped link) is not
# stored again, and starts nothing
law resend_stored_once:
  for +s: M.State
  for +now: Nat
  for +client: U32
  for +id: String
  for +th: String
  for +text: String
  for +msg: String
  for h1: {String.is_empty(msg) == False{} : Bool}
  for h2: {H.Hub.has_msg(H.Hub.entries(s), msg) == True{} : Bool}
  {H.Queue.changes(H.Hub.turn(s, now, client, id, th, text, msg)) == [] : List<&2, M.Change>}

# a message from another thread never interrupts the target's running turn,
# whatever its provider: it waits in the target's inbox
law inbox_never_interrupts:
  for +s: M.State
  for +now: Nat
  for +from: String
  for +to: String
  for role: M.Role
  for +text: String
  for h: {H.Hub.running(H.Hub.thread(s, to)) == True{} : Bool}
  {H.Step.outs_of(H.Hub.inbox(s, now, from, to, role, text)) == [] : List<&2, H.Out>}
# Worktrees
# ---------

# a thread in the project folder never waits for a worktree
law worktree_pending_local:
  for +wt: String
  for +c: Nat
  for +now: Nat
  {M.Worktree.pending.k(M.Local{}, wt, c, now) == False{} : Bool}

# no thread waits for its worktree past the wait: its messages then run in
# the project folder
law worktree_pending_ends:
  for e: M.EnvMode
  for +wt: String
  for +c: Nat
  for +now: Nat
  for h: {Nat.is_lt(now, Nat.add(c, M.Worktree.wait())) == False{} : Bool}
  {M.Worktree.pending.k(e, wt, c, now) == False{} : Bool}

# a message to a thread whose worktree is still being made starts nothing:
# it waits in the thread's queue
law worktree_waits:
  for +s: M.State
  for +now: Nat
  for +th: String
  for +msg: String
  for role: M.Role
  for +text: String
  for h: {M.Worktree.pending(H.Hub.thread(s, th), now) == True{} : Bool}
  {H.Step.outs_of(H.Hub.post(s, now, th, msg, role, text)) == [] : List<&2, H.Out>}

# only "local" asks for the project folder; every other mode (the default
# "auto" included) asks for a worktree
law worktree_by_default:
  {H.Hub.env.of("auto") == M.Worktree{} : M.EnvMode}

# a message to a thread whose worktree was removed makes it again from the
# kept branch, and does nothing else: the turn waits for the worktree and
# never runs in the project folder
law worktree_revives:
  for +s: M.State
  for +now: Nat
  for +th: String
  for +msg: String
  for role: M.Role
  for +text: String
  for h1: {H.Hub.running(H.Hub.thread(s, th)) == False{} : Bool}
  for h2: {M.Worktree.gone(H.Hub.thread(s, th)) == True{} : Bool}
  for h3: {M.Worktree.pending(H.Hub.thread(s, th), now) == False{} : Bool}
  {H.Step.outs_of(H.Hub.post(s, now, th, msg, role, text)) == [H.Wt.revive(s, th)] : List<&2, H.Out>}

# a worktree is never removed while its thread works or waits on the user
law worktree_kept_while_busy:
  for sh: M.Shelf
  for +ours: Bool
  for merged: Bool
  for aged: Bool
  {M.Worktree.drop.k(True{}, sh, ours, merged, aged) == False{} : Bool}

# a worktree is never removed while its thread is out (active, pinned,
# snoozed): only settled or hidden threads lose theirs
law worktree_kept_out:
  for busy: Bool
  for sh: M.Shelf
  for +ours: Bool
  for merged: Bool
  for aged: Bool
  for h: {M.Worktree.parked(sh) == False{} : Bool}
  {M.Worktree.drop.k(busy, sh, ours, merged, aged) == False{} : Bool}

# only a directory Backplane made (under .backplane/worktrees) is removed
law worktree_kept_unless_ours:
  for busy: Bool
  for sh: M.Shelf
  for +wt: String
  for merged: Bool
  for aged: Bool
  for h: {M.Worktree.ours(wt) == False{} : Bool}
  {M.Worktree.drop.k(busy, sh, M.Worktree.ours(wt), merged, aged) == False{} : Bool}

# a settled thread that was not merged keeps its worktree for the window
law worktree_kept_fresh:
  for +ours: Bool
  {M.Worktree.drop.k(False{}, M.Settled{}, ours, False{}, False{}) == False{} : Bool}

# a merged (so settled) idle thread's worktree goes at once
law worktree_dropped_on_merge:
  for aged: Bool
  {M.Worktree.drop.k(False{}, M.Settled{}, True{}, True{}, aged) == True{} : Bool}

# a settled idle thread's worktree goes once the window has passed
law worktree_dropped_when_aged:
  for merged: Bool
  {M.Worktree.drop.k(False{}, M.Settled{}, True{}, merged, True{}) == True{} : Bool}

# so does a hidden (archived or deleted) thread's
law worktree_dropped_when_hidden:
  for merged: Bool
  {M.Worktree.drop.k(False{}, M.Hidden{}, True{}, merged, True{}) == True{} : Bool}

# Merges
# ------

# a merged thread settles, pinned or brought back before or not
law merge_settles:
  for t: M.Thread
  for +at: Nat
  for h: {M.Thread.hidden(t) == False{} : Bool}
  {M.Shelf.of(M.Thread.settled(True{}, at, t)) == M.Settled{} : M.Shelf}

# a recorded merge is never due again, so it settles a thread once
law merge_once:
  for sh: M.Shelf
  for +branch: String
  for +url: String
  for h: {String.is_empty(url) == False{} : Bool}
  {M.Merge.due.k(sh, branch, url) == False{} : Bool}

# a thread without a branch is never merged
law merge_needs_branch:
  for sh: M.Shelf
  for +merged: String
  {M.Merge.due.k(sh, "", merged) == False{} : Bool}

# GitHub accounts
# ---------------

# the account a repository worked with before is tried first
law gh_pick_saved:
  for owner_in: Bool
  for +saved: String
  for +owner: String
  for +active: String
  {GH.Gh.pick(True{}, saved, owner_in, owner, active) == saved : String}

# else the account named like the remote's owner
law gh_pick_owner:
  for +saved: String
  for +owner: String
  for +active: String
  {GH.Gh.pick(False{}, saved, True{}, owner, active) == owner : String}

# else gh's active account: Backplane never switches it
law gh_pick_active:
  for +saved: String
  for +owner: String
  for +active: String
  {GH.Gh.pick(False{}, saved, False{}, owner, active) == active : String}

# the first choice is tried first
law gh_order_first:
  for +first: String
  for us: List<&2, String>
  {List.head(&2, String, GH.Gh.order.k(first, us)) == Some{first} : Maybe<&2, String>}

# and never again: the rest leaves it out
law gh_without_drops:
  for us: List<&2, String>
  for +u: String
  {GH.Gh.has(GH.Gh.without(us, u), u) == False{} : Bool}

# Phone alerts
# ------------

# a phone alerts only for a turn it saw running: connecting, or a thread
# that never ran, raises nothing
law alert_needs_running:
  for t: M.TurnState
  {Nt.Note.kind(False{}, t) == "" : String}

# a turn still running never alerts
law alert_never_running:
  for b: Bool
  {Nt.Note.kind(b, M.Running{}) == "" : String}

# a stop the user asked for is not news
law alert_not_on_stop:
  for b: Bool
  {Nt.Note.kind(b, M.Interrupted{}) == "" : String}

# connecting (no turn seen running yet) raises no alerts, however many
# threads and finished turns the log holds
law alert_none_on_connect:
  for ts: List<&2, M.Thread>
  for +es: List<&2, M.Entry>
  {Nt.Note.alerts(ts, [], es) == [] : List<&2, J.Json>}

# a phone paired with several hubs names every thread and project by its
# hub ("key|id"), but "nothing selected" stays nothing, on any hub
law hubs_no_id:
  for +k: String
  {Hb.Hubs.id(k, "") == "" : String}

# a phone paired with no hub sends nothing, however time passes
law hubs_unpaired_quiet:
  for +cid: String
  for now: Nat
  for cur: String
  for +t: Nat
  {Hb.Hubs.cmds(Hb.Hubs.tick(Hb.Hubs{cid, now, cur, []}, t)) == [] : List<&2, Hb.HCmd>}

# with no thread running the island is empty, so the Live Activity (iOS)
# ends and the live service (Android) stops
law island_idle_empty:
  for ts: List<&2, M.Thread>
  for +es: List<&2, M.Entry>
  for h: {Nt.Note.busy(ts) == False{} : Bool}
  {Nt.Note.lines(ts, es) == [] : List<&2, J.Json>}

# Phone pushes
# ------------

# a push token never goes to clients: what they get of a registration is
# the same whatever the token (and the rest of the registration) was
law device_token_never_sent:
  for tok: String
  for p: String
  for k: String
  for th: String
  for e: String
  for b: String
  for +at: Nat
  {C.Change.wire(M.DeviceRegistered{tok, p, k, th, e, b, at}) == C.Change.wire(M.DeviceRegistered{"", "", "", "", "", "", at}) : J.Json}

# nor when a token is dropped
law device_drop_never_sent:
  for tok: String
  for +at: Nat
  {C.Change.wire(M.DeviceDropped{tok, at}) == C.Change.wire(M.DeviceDropped{"", at}) : J.Json}

# a registration without a token (what clients fold) registers nothing
law device_blank_ignored:
  for s: M.State
  for p: String
  for k: String
  for th: String
  for e: String
  for b: String
  for at: Nat
  {M.State.devices(M.State.apply(s, M.DeviceRegistered{"", p, k, th, e, b, at})) == M.State.devices(s) : Map<&2, M.Device>}

# registering the same token twice leaves one device: the second
# registration replaces the first
law device_register_once:
  for +tok: String
  for h: {String.is_empty(tok) == False{} : Bool}
  for p: String
  for k: String
  for th: String
  for e: String
  for b: String
  for at: Nat
  for p2: String
  for k2: String
  for th2: String
  for e2: String
  for b2: String
  for at2: Nat
  {Map.size(&2, M.Device, M.State.devices(M.State.apply(M.State.apply(M.State.empty(), M.DeviceRegistered{tok, p, k, th, e, b, at}), M.DeviceRegistered{tok, p2, k2, th2, e2, b2, at2}))) == 1n : Nat}

# Pickers
# -------

# an empty query matches every candidate (a picker shows everything
# before you type)
law fuzzy_empty_matches:
  for s: String
  {Nat.is_gt(FZ.Fuzzy.score(s, ""), 0n) == True{} : Bool}

# the sidebar's project search: an empty query keeps every project, in
# order, and a shut search shows the sidebar as it is
law find_empty_keeps:
  for rs: List<&2, U.SRow>
  {U.Find.rows(rs, "") == rs : List<&2, U.SRow>}

law find_shut_shows_all:
  for st: M.State
  for now: Nat
  for dr: Map<&2, String>
  {U.Side.shown(st, now, U.Find.q.k(False{}, dr)) == U.Side.rows(st, now) : List<&2, U.SRow>}

# a caret that just moved (or a field just focused) is shown
law caret_shows_when_moved:
  {N.Blink.shown(0n) == True{} : Bool}

# a hub that does not know its owner lets no tailnet device in without the
# pairing token
law tailnet_no_owner_no_trust:
  for login: String
  {TN.Tailnet.trusts("", login) == False{} : Bool}

# Drawing only what changed
# ------------------------
# A frame is kept as tiles and the timeline as per-entry parts; the next
# frame reuses exactly what is equal and draws the rest.

# a tile looked up in any drawn tiles, wherever the lookup lands, is
# exactly the tile drawn from scratch: an old image is taken only when it
# drew the same local ops over the same base
law seek_made:
  for k: Nat
  for +e: Nat
  for +old: List<&2, R.Op>
  for +b0: Image
  for +mx: U32
  for +my: U32
  for +mn: U32
  for +x: U32
  for +y: U32
  for +rx: U32
  for +ry: U32
  for +n: U32
  for +l: List<&2, R.Op>
  for +base: Image
  {T.Tiles.seek(k, T.Tiles.make(k, e, old, b0, mx, my, mn), x, y, rx, ry, n, e, l, base) == T.Tile.draw(e, l, base) : Image}

# drawing a frame over the last one's tiles gives exactly the tiles drawn
# from scratch: a kept tile is never stale, whatever changed (ops, base),
# and neither is one taken from where a scroll moved it (any past tiles,
# any shift)
law tiles_again_exact:
  for k: Nat
  for +e: Nat
  for +ops: List<&2, R.Op>
  for +old: List<&2, R.Op>
  for +base0: Image
  for +base1: Image
  for +rx: U32
  for +ry: U32
  for +n: U32
  for +pk: Nat
  for +old2: List<&2, R.Op>
  for +base2: Image
  for +prx: U32
  for +pry: U32
  for +pn: U32
  for +qn: U32
  for +dy: U32
  {T.Tiles.again(k, e, ops, base1, T.Tiles.make(k, e, old, base0, rx, ry, n), T.Past{pk, T.Tiles.make(pk, e, old2, base2, prx, pry, pn), qn, dy}, rx, ry, n) == T.Tiles.make(k, e, ops, base1, rx, ry, n) : T.Tiles}

# a tile whose ops and base are unchanged is kept as it is, whatever image
# it holds: it is not drawn again
law tile_keep:
  for +e: Nat
  for +ops: List<&2, R.Op>
  for +l: List<&2, R.Op>
  for +base: Image
  for +img: Image
  for +p: T.Past
  for +rx: U32
  for +ry: U32
  for +n: U32
  {T.Tile.again(e, ops, base, T.Tile{ops, l, base, img}, p, rx, ry, n) == T.Tile{ops, l, base, img} : T.Tile}

# the same for a whole frame as the window draws it, even when the window
# was resized in between, for any scroll hint
law frame_again_exact:
  for +w0: U32
  for +h0: U32
  for +w: U32
  for +h: U32
  for +ops: List<&2, R.Op>
  for +old: List<&2, R.Op>
  for +base0: Image
  for +base: Image
  for +dy: U32
  {T.Frame.again(w, h, ops, base, T.FSome{w0, h0, T.Frame.make(w0, h0, old, base0)}, dy) == T.Frame.make(w, h, ops, base) : T.Tiles}

# a tile's image taken from what the parallel jobs drew is the tile drawn
# here, wherever its path leads in whatever jobs ran
law drawn_get_run:
  for t: T.Jobs
  for path: List<&2, Bool>
  for +e: Nat
  for +l: List<&2, R.Op>
  for +base: Image
  {T.Drawn.get(T.Jobs.run(t, e), path, e, l, base) == T.Tile.draw(e, l, base) : Image}

# a plan filled from any jobs drawn in parallel is exactly the tiles
# Tiles.again gives, over any last tiles, with any scroll
law plan_fill_again:
  for k: Nat
  for +e: Nat
  for +ops: List<&2, R.Op>
  for +base: Image
  for prev: T.Tiles
  for +p: T.Past
  for +rx: U32
  for +ry: U32
  for +n: U32
  for +off: Nat
  for +t: T.Jobs
  {T.Plan.fill(T.Tiles.plan(k, e, ops, base, prev, p, rx, ry, n), e, off, T.Jobs.run(t, e)) == T.Tiles.again(k, e, ops, base, prev, p, rx, ry, n) : T.Tiles}

# the window's frame drawn in parallel is exactly Frame.again's (and so,
# by frame_again_exact, the frame drawn from scratch)
law frame_par_exact:
  for +w: U32
  for +h: U32
  for +ops: List<&2, R.Op>
  for +base: Image
  for prev: T.Frames
  for +dy: U32
  {T.Frame.par(w, h, ops, base, prev, dy) == T.Frame.again(w, h, ops, base, prev, dy) : T.Tiles}

# the timeline's memo brought up to date is exactly the memo made from
# scratch, for any earlier entries
law tl_again_exact:
  for es: List<&2, M.Entry>
  for +ty: L.Ty
  for +old: List<&2, M.Entry>
  for +px: U32
  for +sel: String
  {L.TL.memo.again(es, ty, px, sel, L.TL.memo.make(ty, old, px, sel)) == L.TL.memo.make(ty, es, px, sel) : List<&2, L.TLE>}

# an entry equal to the one its memo item was made for keeps the item:
# its markdown is not laid out again
law tl_keep:
  for +ty: L.Ty
  for +e: M.Entry
  for +px: U32
  for +sel: String
  for +p: L.TLPart
  {L.TL.memo.one(ty, e, px, sel, L.TLE{e, p}) == L.TLE{e, p} : L.TLE}

# the same for the whole memo, whatever width and thread it was made for
law tl_memo_exact:
  for +ty: L.Ty
  for +es: List<&2, M.Entry>
  for +old: List<&2, M.Entry>
  for +px0: U32
  for +sel0: String
  for +px: U32
  for +sel: String
  {L.TL.memo.of(ty, es, px, sel, L.TLMemo{px0, sel0, L.TL.memo.make(ty, old, px0, sel0)}) == L.TLMemo{px, sel, L.TL.memo.make(ty, es, px, sel)} : L.TLMemo}

# the timeline drawn from a memo is the timeline drawn from scratch
law tl_lines_exact:
  for +ty: L.Ty
  for +es: List<&2, M.Entry>
  for +old: List<&2, M.Entry>
  for +px0: U32
  for +sel0: String
  for +st: M.State
  for +sel: String
  for +px: U32
  for +pics: Map<&2, String>
  {L.TL.memo.lines(ty, L.TLMemo{px0, sel0, L.TL.memo.make(ty, old, px0, sel0)}, es, st, sel, px, pics) == L.TL.entries(ty, es, st, sel, px, pics) : List<&2, L.TLine>}
# Links
# -----

# only web addresses open: a link never runs script or reads a file
law link_no_script:
  for s: String
  {LK.Link.is_web("javascript:" ++ s) == False{} : Bool}

law link_no_file:
  for s: String
  {LK.Link.is_web("file:" ++ s) == False{} : Bool}

# a line with no links is drawn as it is, one run of text
law link_plain_line:
  for s: String
  {LK.Link.cut(s, Nil{}) == [LK.PText{s}] : List<&2, LK.Piece>}

# Image lightbox
# --------------

# the lightbox never zooms out past the fitted picture
law lightbox_zoom_min:
  for +z: Nat
  {Nat.is_ge(LBX.Lb.clamp(z), LBX.Lb.zmin()) == True{} : Bool}

# nor in past its most
law lightbox_zoom_max:
  for +z: Nat
  {Nat.is_le(LBX.Lb.clamp(z), LBX.Lb.zmax()) == True{} : Bool}

# a zoomed picture is never scrolled past its far edge: it keeps covering
# the window
law lightbox_scroll_max:
  for +a: Nat
  for +m: Nat
  for +d: Nat
  for +v: Nat
  {Nat.is_le(LBX.Lb.scroll(a, m, d, v), Nat.mul(Nat.sub(d, v), LBX.Lb.sub())) == True{} : Bool}

# a zoom ease starts where the zoom was
law lightbox_ease_start:
  for +z0: Nat
  for +z1: Nat
  for +t0: Nat
  {LBX.Lb.ease.at(z0, z1, t0, t0) == z0 : Nat}

# and lands on its target once its time has passed, at any later time
law lightbox_ease_done:
  for +z0: Nat
  for +z1: Nat
  for +t0: Nat
  for +k: Nat
  {LBX.Lb.ease.at(z0, z1, t0, Nat.add(Nat.add(t0, LBX.Lb.ms()), k)) == z1 : Nat}

# after which it asks for no more frames (no repaint loop)
law lightbox_idle:
  for +t0: Nat
  for +k: Nat
  {LBX.Lb.easing(t0, Nat.add(Nat.add(t0, LBX.Lb.ms()), k)) == False{} : Bool}

# a picture just opened is still: nothing animates
law lightbox_opens_still:
  for +now: Nat
  {LBX.Lb.busy(LBX.Lb.open(), now) == False{} : Bool}

# Icons
# -----

# closepath takes the pen back to where its subpath began
law svg_close_returns:
  for p: SVG.Pen
  {SVG.Pen.cur(SVG.Pen.close(p)) == SVG.Pen.start(p) : SVG.Pt}

# a moveto starts a new subpath where it lands
law svg_move_starts:
  for p: SVG.Pen
  for +x: F32
  for +y: F32
  {SVG.Pen.start(SVG.Pen.move(p, x, y)) == SVG.Pt{x, y} : SVG.Pt}

# an absolute coordinate ignores the pen
law svg_absolute_ignores_pen:
  for +p: F32
  for +v: F32
  {SVG.Svg.at(False{}, p, v) == v : F32}

# extra pairs after a moveto are linetos
law svg_implicit_lineto:
  {SVG.Svg.kinds(SVG.Svg.parse("m1 2 3 4 5 6z")) == [77, 76, 76, 90] : List<&2, U32>}

# compact numbers split where SVG says: "1-2.5.5e1" is 1, -2.5, .5e1
law svg_numbers_split:
  {List.length(&2, SVG.Tok, SVG.Svg.lex("M1-2.5.5e1")) == 4n : Nat}

# every icon the UIs draw is in the set
law icons_used_exist:
  {ICO.Icon.missing(ICO.Icon.used()) == Nil{} : List<&2, String>}

# every path of every icon parses and begins with a moveto
law icons_all_draw:
  {ICO.Icon.bad(ICO.Icon.all()) == Nil{} : List<&2, String>}

# Hotkeys
# -------

# alt+1..9 picks a project everywhere, the terminal included
law hotkey_alt_digit:
  {N.Keys.name(49, 4, True{}) == "project" : String}

# ctrl+1..9 picks a thread of this project
law hotkey_ctrl_digit:
  {N.Keys.name(57, 2, False{}) == "jump" : String}

# pressing alt shows the project numbers, whatever was shown before
law hint_alt_starts:
  for +h: String
  for +mods: U32
  {N.Hint.down(h, 65513, mods) == "alt" : String}

# a key pressed with the hint's modifier up ends the hint (its release was
# missed), so numbers never stick
law hint_missed_release_ends:
  {N.Hint.down("ctrl", 97, 0) == "" : String}

# Editing and threads
# -------------------

# a space typed at the end of the composer stays on its line, so the caret
# moves past it at once (not only once the next character comes)
law wrap_keeps_last_space:
  {X.Text.wrap(Map.new(&2, X.TG), X.Text.bitmap(), "hello ", 400) == ["hello "] : List<&2, String>}

# ctrl+a selects the whole text: the caret at its end, the other end at 0
law edit_select_all:
  {N.Ed.key(97, 0, 2, "abc", 1n, 1n) == N.Ed{"abc", 3n, 0n, False{}, False{}, "", 0n} : N.Ed}

# typing over a selection replaces it
law edit_type_replaces:
  {N.Ed.key(120, 120, 0, "hello world", 6n, 11n) == N.Ed{"hello x", 7n, 7n, False{}, True{}, "", 1n} : N.Ed}

# a first Delete only asks: nothing reaches the hub until it is confirmed
law delete_asks_first:
  for u: U.Ui
  {U.Act.cmds(U.Ui.delete.k(False{}, u)) == Nil{} : List<&2, U.Cmd>}

# deleting from a row (a swipe on the phone) asks first too
law row_delete_asks_first:
  for u: U.Ui
  for +id: String
  {U.Act.cmds(U.Ui.row_delete.k(False{}, u, id)) == Nil{} : List<&2, U.Cmd>}

# a right-click on a row the user settled brings it back
law row_toggle_unsettles:
  for t: M.Thread
  for +at: Nat
  for h: {M.Thread.hidden(t) == False{} : Bool}
  {U.Ui.row_toggle.m(M.Shelf.of(M.Thread.settled(True{}, at, t))) == "thread.unsettle" : String}

# and on a row the user brought back it settles it again
law row_toggle_settles:
  for +at: Nat
  for t: M.Thread
  {U.Ui.row_toggle.m(M.Shelf.of(M.Thread.unsettled(at, t))) == "thread.settle" : String}

# an answer to anything but the project picker's newest request leaves the
# client as it was (a late listing never replaces a newer one)
law picker_drops_stale:
  for u: U.Ui
  for +o: J.Json
  {U.Proj.reply.k(0n, u, o) == u : U.Ui}

# the timeline a frame draws, from the memo the window brings up to date
# before it (Lay.memo), is the timeline drawn from scratch
law tl_frame_exact:
  for +ty: L.Ty
  for +es: List<&2, M.Entry>
  for +old: List<&2, M.Entry>
  for +px0: U32
  for +sel0: String
  for +st: M.State
  for +sel: String
  for +px: U32
  for +pics: Map<&2, String>
  {L.TL.memo.shown(ty, L.TL.memo.of(ty, es, px, sel, L.TLMemo{px0, sel0, L.TL.memo.make(ty, old, px0, sel0)}), st, sel, px, pics) == L.TL.entries(ty, es, st, sel, px, pics) : List<&2, L.TLine>}

# Tool calls folded
# -----------------

# folding a thread's tool calls into runs loses no entry and keeps the order
law fold_keeps_entries:
  for es: List<&2, M.Entry>
  {FO.Fold.flat(FO.Fold.groups(es)) == es : List<&2, M.Entry>}

# so the groups hold exactly as many entries as the thread
law fold_count:
  for es: List<&2, M.Entry>
  {FO.Fold.count(FO.Fold.groups(es)) == List.length(&2, M.Entry, es) : Nat}

# a folded run only ever holds tool calls
law fold_runs_only_tools:
  for es: List<&2, M.Entry>
  {FO.Fold.all(FO.Fold.runs(FO.Fold.groups(es))) == True{} : Bool}

# errors and messages are never folded
law fold_never_error:
  for +i: String
  for +t: String
  for +k: String
  for +s: String
  for +a: Nat
  {FO.Fold.tool(M.Act{i, t, "error", k, s, a}) == False{} : Bool}

law fold_never_message:
  for +i: String
  for +t: String
  for +r: M.Role
  for +x: String
  for +a: Nat
  {FO.Fold.tool(M.Msg{i, t, r, x, a}) == False{} : Bool}

# a run the user opened stays open and one they shut stays shut, live or
# not; one nobody touched is open only while live (the last thing in a
# thread whose turn runs), so it shuts once the turn ends
law fold_user_opened:
  for +live: Bool
  {FO.Fold.open("1", live) == True{} : Bool}

law fold_user_shut:
  for +live: Bool
  {FO.Fold.open("0", live) == False{} : Bool}

law fold_default_live:
  for +live: Bool
  {FO.Fold.open("", live) == live : Bool}

# every frame the hub sends is binary (opcode 2, final): CBOR, never text
law hub_frames_cbor:
  for +t: String
  {List.head(&2, U32, WS.Ws.cbor(t)) == Some{130} : Maybe<&2, U32>}

# a plot for a phone goes as a binary frame too, never text
law hub_plot_frames_binary:
  for s: String
  {List.head(&2, U32, WS.Ws.bin(s)) == Some{130} : Maybe<&2, U32>}

# The phones' board viewer
# ------------------------
# The hub sends a phone a board or schematic as chunks of geometry, and
# each later version only as a delta against what that phone holds.

# what a phone rebuilds from a delta against the chunks it holds is
# exactly the new plot, whatever it held before
law plot_delta_exact:
  for ns: List<&2, PL.Chunk>
  for +old: List<&2, PL.Chunk>
  {PL.Plot.apply(PL.Plot.delta(ns, old), old) == ns : List<&2, PL.Chunk>}

# re-reading an unchanged board sends no geometry: every chunk goes as the
# index of one the phone holds (and so nothing fades in again)
law plot_unchanged_sends_nothing:
  for +cs: List<&2, PL.Chunk>
  {PL.Plot.fresh(PL.Plot.delta(cs, cs)) == 0n : Nat}

# an item on a layer the viewers hide is never sent
law plot_hidden_not_sent:
  for +key: String
  for +sig: U32
  for +layer: U32
  for +p: B.Prim
  for +info: String
  for +kind: U32
  for +acc: List<&2, PL.Piece>
  for h: {PL.Piece.alpha(kind, layer) == 0 : U32}
  {PL.Piece.put(B.Item{key, sig, layer, p, info}, kind, acc) == acc : List<&2, PL.Piece>}

# the courtyards are such a layer on a board
law plot_courtyard_hidden:
  {PL.Piece.alpha(0, 17) == 0 : U32}

# numbers survive the wire exactly: small and large, and negatives as
# two's complement
law plot_numbers_exact:
  {PL.Dec.nums(PL.Enc.text([0, 1, 31, 32, 1024, 123456789, 4294967295])) == [0, 1, 31, 32, 1024, 123456789, 4294967295] : List<&2, U32>}

# a closed viewer wants no source, in any project
law view_closed_wants_nothing:
  for +root: String
  {MV.View.key("", root) == "" : String}

# a viewer the hub is already showing its source asks the hub nothing
law view_asks_once:
  for +u: U.Ui
  for +cmds: List<&2, U.Cmd>
  for h: {String.eq(MV.View.want(u), U.Ui.scratch(u, "@view.at")) == True{} : Bool}
  {MV.View.sync.u(u, cmds) == U.Act{u, cmds} : U.Act}

# a plot goes to a phone as one binary frame, as every hub frame, whatever
# its bytes (the hub never parses it again)
law plot_frames_binary:
  for +bs: List<&2, U32>
  {List.head(&2, U32, WS.Ws.encode(2, bs)) == Some{130} : Maybe<&2, U32>}

# Inspecting on a phone
# ---------------------

# a tap on nothing asks the hub nothing (and closes any card)
law pick_nothing_there:
  for +u: U.Ui
  {U.Act.cmds(MV.View.pick(u, "[]")) == Nil{} : List<&2, U.Cmd>}

# with no pick waiting, an answer changes nothing: a late one never shows
# a stale card
law pick_late_ignored:
  for +u: U.Ui
  for +o: J.Json
  for h: {String.is_empty(U.Ui.scratch(u, "@pick.rid")) == True{} : Bool}
  {MV.View.picked(u, o) == u : U.Ui}

# a pad wins over the zone it sits in, whichever the phone found first
law pick_pad_over_zone:
  {MV.Pick.best([MV.Cand{"zone", 900, 12}, MV.Cand{"pad 1", 4, 12}], None{}) == Some{MV.Cand{"pad 1", 4, 12}} : Maybe<&2, MV.Cand>}

law pick_pad_over_zone_after:
  {MV.Pick.best([MV.Cand{"pad 1", 4, 12}, MV.Cand{"zone", 900, 12}], None{}) == Some{MV.Cand{"pad 1", 4, 12}} : Maybe<&2, MV.Cand>}

# of two the same size, the one drawn on top wins
law pick_top_on_tie:
  {MV.Pick.best([MV.Cand{"F", 4, 12}, MV.Cand{"B", 4, 5}], None{}) == Some{MV.Cand{"F", 4, 12}} : Maybe<&2, MV.Cand>}

# The 3D view
# -----------

# a 3D view lays the project's own board plot on the board's faces
law view_3d_draws_board:
  for +root: String
  {MV.View.layers("3d", root) == MV.View.key("board", root) : String}

law view_3d_key:
  {MV.View.key("3d", "/p") == "2|/p|" : String}

# 3D boards
# ---------

# a model path's ${VARS} come from the board's variables
law pcb3d_path_vars:
  {P3.Env.sub("${KICAD10_3DMODEL_DIR}/R.3dshapes/R_0402.step", [P3.KV{"KIPRJMOD", "/b"}, P3.KV{"KICAD10_3DMODEL_DIR", "/lib"}])
    == "/lib/R.3dshapes/R_0402.step" : String}

# a variable the board does not know stays as written (the file is then
# not found, rather than found in the wrong place)
law pcb3d_path_unknown_kept:
  {P3.Env.sub("${NOPE}/x.step", [P3.KV{"KIPRJMOD", "/b"}]) == "${NOPE}/x.step" : String}

# triangles there from the start never fade
law mesh_first_never_fades:
  for +now: Nat
  {MS.Fade.alpha(0n, now) == 255 : U32}

# parts that arrive with the board (within 350 ms) do not fade in
law scene3_prompt_parts_no_fade:
  {FA.Scene3.fading(FA.Scene3.add(FA.Scene3.board(FA.FNone{}, 5000n), [G.Tri3{0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 255}], 5100n), 5101n)
    == False{} : Bool}

# parts that arrive late fade in
law scene3_late_parts_fade:
  {FA.Scene3.fading(FA.Scene3.add(FA.Scene3.board(FA.FNone{}, 5000n), [G.Tri3{0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 255}], 7000n), 7001n)
    == True{} : Bool}

# and the fade ends
law scene3_fade_ends:
  {FA.Scene3.fading(FA.Scene3.add(FA.Scene3.board(FA.FNone{}, 5000n), [G.Tri3{0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 255}], 7000n), 7450n)
    == False{} : Bool}

# parts from an older read of the board are dropped
law scene3_stale_parts_dropped:
  {MS.Model.size(FA.Scene3.model(FA.Scene3.add_if(FA.Scene3.board(FA.FNone{}, 5000n), 4000n, [G.Tri3{0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 255}], 7000n)))
    == 0n : Nat}
# The model picker
# ----------------
# Its pieces come from core/menu.bend for whatever models and effort
# levels the CLIs report, so a new model can never make two collide.

# model rows stack: each starts where the one above it ends
law menu_rows_apart:
  for n: Nat
  for +x: Nat
  for +y: Nat
  for +w: Nat
  {MN.Boxes.apart(MN.Menu.rows(n, x, y, w)) == True{} : Bool}

# effort chips never overlap, however many and however wide, in a menu of
# any width: each is right of the one before it or on a line below
law menu_chips_apart:
  for ws: List<&2, Nat>
  for +left: Nat
  for +right: Nat
  for +x: Nat
  for +y: Nat
  for +h: Nat
  for +gap: Nat
  {MN.Boxes.apart(MN.Flow.place(ws, left, right, x, y, h, gap)) == True{} : Bool}

# and all of them end above the first model row
law menu_chips_above_rows:
  for ws: List<&2, Nat>
  for +left: Nat
  for +right: Nat
  for +x: Nat
  for +y: Nat
  for +h: Nat
  for +gap: Nat
  {MN.Boxes.above(MN.Flow.place(ws, left, right, x, y, h, gap), MN.Flow.under(ws, left, right, x, y, h, gap)) == True{} : Bool}

# the rows shown take no more height than there is (the menu never covers
# the thread's header; the rest scroll)
law menu_rows_fit:
  for +n: Nat
  for +room: Nat
  {Nat.is_ge(room, MN.Menu.span(n, room)) == True{} : Bool}

# scrolled, the rows shown never run past the last model
law menu_scroll_in_list:
  for +off: Nat
  for +n: Nat
  for +shown: Nat
  for h: {Nat.is_ge(n, shown) == True{} : Bool}
  {Nat.is_ge(n, Nat.add(shown, MN.Menu.off(off, n, shown))) == True{} : Bool}

# the menu is never wider than the room it opens in
law menu_width_fits:
  for +want: Nat
  for +room: Nat
  {Nat.is_ge(room, MN.Menu.width(want, room)) == True{} : Bool}

# a model's label starts past the name column (names are clipped to it)
law menu_label_clear:
  for +name_x: Nat
  for +widest: Nat
  for +w: Nat
  {Nat.is_ge(MN.Menu.label_x(name_x, MN.Menu.col(widest, w)), Nat.add(name_x, MN.Menu.col(widest, w))) == True{} : Bool}

# every press in the window first closes a menu it lands outside of
law menu_press_first:
  for +n: N.Nui
  for +x: U32
  for +y: U32
  {N.Nui.event(n, W.WButton{x, y, 1, True{}}) == N.Nui.press(N.Nui.in_viewer(n, x), N.Menu.press(N.Hit.find(N.Nui.hits(n), x, y), n), x, y) : N.Step}

# a right-click too
law menu_right_press_first:
  for +n: N.Nui
  for +x: U32
  for +y: U32
  {N.Nui.event(n, W.WButton{x, y, 3, True{}}) == N.Row.menu(N.Hit.find(N.Nui.hits(n), x, y), N.Menu.press(N.Hit.find(N.Nui.hits(n), x, y), n), x) : N.Step}

# a press on nothing is outside
law menu_press_nothing:
  {N.Menu.inside(None{}) == False{} : Bool}

# so is a press on anything that is not the menu's own
law menu_press_elsewhere:
  for +x0: U32
  for +y0: U32
  for +x1: U32
  for +y1: U32
  for +a: String
  for +v: String
  for h: {N.Menu.own(a, v) == False{} : Bool}
  {N.Menu.inside(Some{N.Hit{x0, y0, x1, y1, a, v}}) == False{} : Bool}

# the picker's own pieces keep it open: any model row, effort chip, or its box
law menu_press_rows_inside:
  for +x0: U32
  for +y0: U32
  for +x1: U32
  for +y1: U32
  for +v: String
  {N.Menu.inside(Some{N.Hit{x0, y0, x1, y1, "model", v}}) == True{} : Bool}

law menu_press_box_inside:
  for +x0: U32
  for +y0: U32
  for +x1: U32
  for +y1: U32
  for +v: String
  {N.Menu.inside(Some{N.Hit{x0, y0, x1, y1, "menu", v}}) == True{} : Bool}

law menu_press_chips_inside:
  for +x0: U32
  for +y0: U32
  for +x1: U32
  for +y1: U32
  for +v: String
  {N.Menu.inside(Some{N.Hit{x0, y0, x1, y1, "effort", v}}) == True{} : Bool}

# Project badges
# --------------

# every icon a project may take is in the set (and so draws: icons_all_draw)
law badge_icons_exist:
  {ICO.Icon.missing(BG.Badge.icons()) == Nil{} : List<&2, String>}

# a project with no colour set gets one of the tints, whatever its id
law badge_auto_tint:
  for +k: Nat
  {BG.Badge.has(BG.Badge.colors(), BG.Badge.nth(k)) == True{} : Bool}

# a colour that is not a tint falls back to the project's own
law badge_unknown_color:
  for +id: String
  {BG.Badge.color.of("mauve", id) == BG.Badge.auto(id) : String}

# a set tint wins
law badge_set_color:
  for +id: String
  {BG.Badge.color.of("teal", id) == "teal" : String}

# no icon set, or one not in the set, is the folder
law badge_default_icon:
  {BG.Badge.icon.of("") == "folder" : String}

law badge_unknown_icon:
  {BG.Badge.icon.of("rocket-ship") == "folder" : String}

# The project picker on a phone
# ------------------------------

# a closed picker draws nothing
law mpick_closed_draws_nothing:
  for +u: U.Ui
  for h: {U.Ui.flag(u, "proj") == False{} : Bool}
  {MP.MPick.json(u) == J.Null{} : J.Json}

# typing within the folder already asked for only filters: the hub is
# asked nothing
law mpick_filter_asks_nothing:
  for +u: U.Ui
  for +text: String
  for h: {String.eq(MP.MPick.dir(text), U.Ui.scratch(u, "@mpick.asked")) == True{} : Bool}
  {MP.MPick.type(u, text) == U.Act{U.Ui.scratch_set(u, "@mpick", text), Nil{}} : U.Act}

# it opens at home, and a folder under home shows as ~
law mpick_opens_home:
  {MP.MPick.dir("~/") == "~/" : String}

law mpick_tilde:
  {MP.MPick.field("/home/h", "/home/h/docs") == "~/docs/" : String}

# Thread titles
# -------------

# a written title never replaces a title the user gave the thread meanwhile
law title_user_rename_wins:
  for +current: String
  for +placeholder: String
  for +answer: String
  for +thread: String
  for +now: Nat
  for h: {String.eq(current, placeholder) == False{} : Bool}
  {H.Title.changes(current, placeholder, answer, thread, now) == [] : List<&2, M.Change>}

# while the first message's placeholder stands, the cleaned answer is the title
law title_applies_when_placeholder:
  for +current: String
  for +placeholder: String
  for +answer: String
  for +thread: String
  for +now: Nat
  for same: {String.eq(current, placeholder) == True{} : Bool}
  for set: {String.is_empty(placeholder) == False{} : Bool}
  for some: {String.is_empty(AG.Title.clean(answer)) == False{} : Bool}
  {H.Title.changes(current, placeholder, answer, thread, now) == [M.ThreadRenamed{thread, AG.Title.clean(answer), now}] : List<&2, M.Change>}

# an empty answer (the writer failed) changes nothing
law title_empty_keeps:
  for +current: String
  for +placeholder: String
  for +thread: String
  for +now: Nat
  {H.Title.changes(current, placeholder, "", thread, now) == [] : List<&2, M.Change>}

# no text generation settings: Claude's haiku writes
law text_model_default:
  {AG.Text.of(M.State.empty()) == AG.Tx{"claude", "haiku"} : AG.Tx}

# an unknown provider is claude; an empty model is the provider's light one
law text_model_unknown_provider:
  {AG.Text.pick("gemini", "") == AG.Tx{"claude", "haiku"} : AG.Tx}

law text_model_light:
  {AG.Text.pick("codex", " ") == AG.Tx{"codex", "gpt-6-luna"} : AG.Tx}

# a text.model left over from another provider gives way to the chosen
# provider's light model
law text_model_mismatch:
  for +provider: String
  for +model: String
  for h: {AG.Text.fits(AG.Text.norm(String.trim(provider)), String.trim(model)) == False{} : Bool}
  {AG.Text.pick(provider, model) == AG.Tx{AG.Text.norm(String.trim(provider)), AG.Text.light(AG.Text.norm(String.trim(provider)))} : AG.Tx}

law text_model_mismatch_codex:
  {AG.Text.pick("codex", "haiku") == AG.Tx{"codex", "gpt-6-luna"} : AG.Tx}

law text_model_mismatch_claude:
  {AG.Text.pick("claude", "gpt-6-luna") == AG.Tx{"claude", "haiku"} : AG.Tx}

# a model the provider owns, or one no provider is known to own, is kept
law text_model_kept:
  {AG.Text.pick("claude", "claude-sonnet-5") == AG.Tx{"claude", "claude-sonnet-5"} : AG.Tx}

# an agent's viewer_show opens the viewer only from the thread on screen:
# another thread's request waits in that thread's view
law view_other_stays_shut:
  for u: U.Ui
  for +th: String
  for +o: J.Json
  for p: {U.Ui.panel(u) == False{} : Bool}
  for h: {String.eq(th, U.Ui.sel(u)) == False{} : Bool}
  {U.Ui.panel(U.Ui.view.k(u, th, o)) == False{} : Bool}

# no two threads share a browser page: a thread no bot owns drives the
# page named by the thread
law browser_page_own:
  for +th: String
  {BOT.World.page(BOT.World.empty(), th) == th : String}

# Hierarchical schematics
# -----------------------
# The window reads the sheet tree from the root schematic; these hold for
# every tree it builds.

# a sheet file written as an absolute path is used as written
law hier_resolve_absolute:
  for +parent: String
  for +file: String
  for h: {String.starts_with(file, "/") == True{} : Bool}
  {HI.Hier.resolve(parent, file) == file : String}

# any other is beside its parent
law hier_resolve_beside:
  {HI.Hier.resolve("/p/io/io.kicad_sch", "adc.kicad_sch") == "/p/io/adc.kicad_sch" : String}

# a sheet that includes an ancestor is listed once, marked, and never
# expanded, so a recursive design still gives a finite tree
law hier_loop_listed_once:
  {HI.Hier.rows([HI.Kids{"/p/a", [HI.Sheet{"b", "/p/b"}]}, HI.Kids{"/p/b", [HI.Sheet{"a", "/p/a"}]}], "/p/a")
    == [HI.Row{0n, "a", "/p/a", False{}}, HI.Row{1n, "b", "/p/b", False{}}, HI.Row{2n, "a", "/p/a", True{}}] : List<&2, HI.Row>}

# going up from the root stays at the root, in any tree
law hier_root_is_top:
  for +rs: List<&2, HI.Row>
  {HI.Hier.parent(rs, 0n) == 0n : Nat}

# opening a sheet and going up returns to where it was opened
law hier_up_after_open:
  {HI.Hier.parent([HI.Row{0n, "top", "/p/top", False{}}, HI.Row{1n, "power", "/p/power", False{}}, HI.Row{1n, "io", "/p/io", False{}}, HI.Row{2n, "adc", "/p/adc", False{}}],
      Maybe.default(&2, Nat, HI.Hier.child([HI.Row{0n, "top", "/p/top", False{}}, HI.Row{1n, "power", "/p/power", False{}}, HI.Row{1n, "io", "/p/io", False{}}, HI.Row{2n, "adc", "/p/adc", False{}}], 2n, "adc"), 0n))
    == 2n : Nat}

# Drafts kept
# -----------

# every change to a thread's draft asks the host to write it down at once
law draft_kept:
  for u: U.Ui
  for +text: String
  {U.Act.cmds(U.Ui.draft.set(u, text)) == U.Draft.keep(U.Ui.sel(u), text) : List<&2, U.Cmd>}

# a thread's id is kept, word for word
law draft_keep_thread:
  for +text: String
  {U.Draft.keep("t1790175755-9", text) == [U.Keep{"t1790175755-9", text}] : List<&2, U.Cmd>}

# no thread, a scratch key or anything path-like is never written
law draft_keep_no_thread:
  for +text: String
  {U.Draft.keep("", text) == Nil{} : List<&2, U.Cmd>}

law draft_keep_no_scratch:
  for +text: String
  {U.Draft.keep("@del", text) == Nil{} : List<&2, U.Cmd>}

law draft_keep_no_path:
  for +text: String
  {U.Draft.keep("../x", text) == Nil{} : List<&2, U.Cmd>}

# a draft read back after a restart fills an empty composer and never
# replaces what is typed there
law draft_restore_fills:
  for +saved: String
  {U.Draft.pick("", saved) == saved : String}

law draft_restore_keeps_typing:
  for +c: Char
  for +t: String
  for +saved: String
  {U.Draft.pick(SCon{c, t}, saved) == SCon{c, t} : String}

# Restarts, stops and waiting asks
# --------------------------------

# a stop reaches only a running turn
law interrupt_idle_nothing:
  for s: M.State
  for now: Nat
  for +client: U32
  for +id: String
  for thread: String
  {H.Hub.interrupt.k(False{}, s, now, client, id, thread) == H.Step{[], [H.Reply.ok(client, id)]} : H.Step}

# Claude takes the interrupt on its input; a Codex or Grok turn's process
# is stopped
law interrupt_claude_input:
  for +th: String
  for +r: String
  {H.Stop.outs("claude", th, r) == [H.AgentSend{th, H.Claude.interrupt(r)}] : List<&2, H.Out>}

law interrupt_codex_stops:
  for +th: String
  for r: String
  {H.Stop.outs("codex", th, r) == [H.AgentStop{th}] : List<&2, H.Out>}

law interrupt_grok_stops:
  for +th: String
  for r: String
  {H.Stop.outs("grok", th, r) == [H.AgentStop{th}] : List<&2, H.Out>}

# what a stopped turn's process still says changes nothing
law stopped_turn_quiet:
  for s: M.State
  for now: Nat
  for thread: String
  for line: String
  {H.Hub.agent_line.c(False{}, s, now, thread, line) == H.Step{[], []} : H.Step}

# after a restart a turn left running is interrupted, and an open ask is
# closed, so nothing waits on what died with the old process
law recover_interrupts_running:
  {H.Hub.running(H.Hub.thread(H.Rec.after(H.Rec.demo(M.Running{}), 10n), "t1")) == False{} : Bool}

law recover_closes_asks:
  {H.Pend.open(M.Asks.all(H.Rec.after(H.Rec.demo(M.Running{}), 10n)), "t1") == 0n : Nat}

# a thread that was not running is left as it was
law recover_leaves_idle:
  {H.Hub.running(H.Hub.thread(H.Rec.after(H.Rec.demo(M.Completed{}), 10n), "t1")) == False{} : Bool}

law recover_empty_nothing:
  for now: Nat
  {H.Hub.recover(M.State.empty(), now) == H.Step{[], []} : H.Step}

# an open ask makes its thread pending (so it never auto-settles); the
# answer clears it
law ask_makes_pending:
  {H.Hub.pending(H.Hub.thread(M.State.replay(H.Pend.fix(M.State.replay(H.Rec.demo.base(), M.State.empty()), [M.AskOpened{"a1", "t1", "approval", "Bash", "ls", "", 3n}]), M.State.replay(H.Rec.demo.base(), M.State.empty())), "t1")) == 1n : Nat}

law answer_clears_pending:
  {H.Hub.pending(H.Hub.thread(M.State.replay(H.Pend.fix(H.Rec.demo(M.Completed{}), [M.AskClosed{"a1", "allow", 4n}]), H.Rec.demo(M.Completed{})), "t1")) == 0n : Nat}

# a parent whose delegated task still works does not settle
law settle_waits_for_children:
  {H.Kids.busy([M.Task{"k1", "t1", "t2", 1n, M.TaskRunning{}, "", False{}, "codex", ""}], "t1") == True{} : Bool}

law settle_children_done:
  {H.Kids.busy([M.Task{"k1", "t1", "t2", 1n, M.TaskDone{}, "", False{}, "codex", ""}], "t1") == False{} : Bool}

# a turn process's tag names its thread and process; only the process the
# hub runs for the thread is heard, and an untagged line always is
law tag_thread:
  {H.Tag.thread(H.Tag.of("t1790175755-9", 4242)) == "t1790175755-9" : String}

law tag_pid:
  {H.Tag.pid(H.Tag.of("t1790175755-9", 4242)) == Some{4242} : Maybe<&2, U32>}

law tag_untagged:
  {H.Tag.pid("t1790175755-9") == None{} : Maybe<&2, U32>}

law tag_old_process_unheard:
  {H.Tag.heard(Some{41}, Some{42}) == False{} : Bool}

law tag_untagged_heard:
  for r: Maybe<&2, U32>
  {H.Tag.heard(None{}, r) == True{} : Bool}

# Follow-ups: queue or steer
# --------------------------

# unset, Claude steers and the others queue; a setting wins; ctrl+Enter
# does the other
law follow_default_claude:
  {U.Follow.mode("", "claude", False{}) == "steer" : String}

law follow_default_codex:
  {U.Follow.mode("", "codex", False{}) == "queue" : String}

law follow_setting_queue:
  for +p: String
  {U.Follow.mode("queue", p, False{}) == "queue" : String}

law follow_setting_steer:
  for +p: String
  {U.Follow.mode("steer", p, False{}) == "steer" : String}

law follow_alt_flips:
  for +s: String
  for +p: String
  {U.Follow.mode(s, p, True{}) == U.Follow.flip(U.Follow.mode(s, p, False{})) : String}

# with a turn running, "queue" stores the message for later and runs
# nothing, even for Claude, which would take it in place
law queue_mode_waits:
  {H.Hub.post.mode("queue", H.Demo.state("claude", M.Running{}), 5n, "t1", "m1", M.User{}, "hi")
    == H.Step{[M.MessagePosted{"t1", "m1", M.User{}, "hi", 5n}, M.TurnQueued{"t1", "m1", "hi", 5n}], []} : H.Step}

# steering Claude sends into its running process; a Codex or Grok turn is
# stopped and starts again with the message
law steer_claude_in_place:
  for +th: String
  {H.Steer.stop("claude", th) == [] : List<&2, H.Out>}

law steer_codex_restarts:
  {List.head(&2, H.Out, H.Step.outs_of(H.Hub.post.mode("steer", H.Demo.state("codex", M.Running{}), 5n, "t1", "m1", M.User{}, "hi"))) == Some{H.AgentStop{"t1"}} : Maybe<&2, H.Out>}

# the queue, message by message: joined as it always was, edited in
# place, removed, moved
law queue_joined:
  {M.Queue.texts([M.QItem{"a", "x"}, M.QItem{"b", "y"}]) == "x\n\ny" : String}

law queue_edit_in_place:
  {M.Queue.edit([M.QItem{"a", "x"}, M.QItem{"b", "y"}], "b", "z") == [M.QItem{"a", "x"}, M.QItem{"b", "z"}] : List<&2, M.QItem>}

law queue_remove_one:
  {M.Queue.drop([M.QItem{"a", "x"}, M.QItem{"b", "y"}], "a") == [M.QItem{"b", "y"}] : List<&2, M.QItem>}

law queue_move_first:
  {M.Queue.move([M.QItem{"a", "x"}, M.QItem{"b", "y"}, M.QItem{"c", "z"}], "c", 0n) == [M.QItem{"c", "z"}, M.QItem{"a", "x"}, M.QItem{"b", "y"}] : List<&2, M.QItem>}

law queue_move_unknown:
  {M.Queue.move([M.QItem{"a", "x"}], "q", 0n) == [M.QItem{"a", "x"}] : List<&2, M.QItem>}

# steering one queued message leaves the others waiting, in order
law queue_steer_one_leaves_rest:
  {M.Queue.items(M.State.replay([M.TurnQueued{"t1", "a", "x", 1n}, M.TurnQueued{"t1", "b", "y", 1n}, M.TurnQueued{"t1", "c", "z", 1n}, M.QueueTakenOne{"t1", "b", 2n}], M.State.empty()), "t1")
    == [M.QItem{"a", "x"}, M.QItem{"c", "z"}] : List<&2, M.QItem>}

# a row's first button steers while a turn runs; with none running the
# first row can resume the held queue
law queue_row_running:
  for +m: String
  {List.head(&2, U.QBtn, U.Qu.buttons(True{}, True{}, m)) == Some{U.QBtn{"Steer", "q-steer", m}} : Maybe<&2, U.QBtn>}

law queue_row_held:
  for +m: String
  {List.head(&2, U.QBtn, U.Qu.buttons(False{}, True{}, m)) == Some{U.QBtn{"Resume", "q-resume", ""}} : Maybe<&2, U.QBtn>}

# Handed-over context and forks
# -----------------------------

# the newest entries that fit the budget are kept, oldest first; what does
# not fit is counted as left out
law hand_newest_fit:
  {HD.Hand.go([M.Msg{"3", "t1", M.User{}, "c", 3n}, M.Msg{"2", "t1", M.User{}, "b", 2n}, M.Msg{"1", "t1", M.User{}, "a", 1n}], HD.Sel{17n, [], False{}, 0n})
    == HD.Sel{1n, ["User: b", "User: c"], True{}, 1n} : HD.Sel}

# once one entry is left out, every older one is too: the kept history
# has no holes
law hand_no_holes:
  for fits: Bool
  for +line: String
  for +left: Nat
  for ls: List<&2, String>
  for +om: Nat
  {HD.Hand.put(True{}, fits, line, left, ls, om) == HD.Sel{left, ls, True{}, 1n+om} : HD.Sel}

# a long item is cut and says by how much
law hand_cut_says:
  {HD.Hand.cut("abcdef", 2n) == "ab ...[4 more characters]" : String}

# context waiting alone never starts a turn: it goes with a message
law handoff_never_runs_alone:
  {M.Queue.real([M.QItem{"handoff:t1", "ctx"}]) == False{} : Bool}

law handoff_with_message_runs:
  {M.Queue.real([M.QItem{"handoff:t1", "ctx"}, M.QItem{"m1", "hi"}]) == True{} : Bool}

# and it goes first, ahead of the user's words, which are never cut
law handoff_goes_first:
  {M.Queue.texts([M.QItem{"handoff:t1", "ctx"}, M.QItem{"m1", "hi"}]) == "ctx\n\nhi" : String}

# a fork remembers its source and waits with the source's context queued
law fork_records_source:
  {M.Fork.source(M.State.replay(H.Queue.changes(H.Hub.fork(H.Demo.state("claude", M.Completed{}), 5n, 0, "1", "t1")), H.Demo.state("claude", M.Completed{})), "t5-3") == "t1" : String}

law fork_waits_with_context:
  {M.Queue.waiting(M.State.replay(H.Queue.changes(H.Hub.fork(H.Demo.state("claude", M.Completed{}), 5n, 0, "1", "t1")), H.Demo.state("claude", M.Completed{})), "t5-3") == False{} : Bool}

# only a fork can be brought back
law back_needs_fork:
  {H.Queue.changes(H.Hub.back(H.Demo.state("claude", M.Completed{}), 5n, 0, "1", "t1")) == [] : List<&2, M.Change>}

# Switching providers
# -------------------

# a running turn is never switched, and switching to the same provider
# changes nothing
law switch_between_turns:
  {H.Queue.changes(H.Hub.switch(H.Demo.state("claude", M.Running{}), 5n, 0, "1", "t1", "codex")) == [] : List<&2, M.Change>}

law switch_same_nothing:
  {H.Queue.changes(H.Hub.switch(H.Demo.state("claude", M.Completed{}), 5n, 0, "1", "t1", "claude")) == [] : List<&2, M.Change>}

# each provider keeps its own session: a new one starts fresh, and coming
# back resumes the one it had
law switch_new_session:
  {M.Switch.sess(M.State.thread.get(M.State.replay([M.SessionSet{"t1", "S1", 3n}, M.ProviderSet{"t1", "codex", "", 4n}], H.Demo.state("claude", M.Completed{})), "t1")) == "" : String}

law switch_keeps_sessions:
  {M.Switch.sess(M.State.thread.get(M.State.replay([M.ProviderSet{"t1", "claude", "", 6n}], H.Demo.switched()), "t1")) == "S1" : String}

law switch_keeps_sessions_both:
  {M.Switch.sess(M.State.thread.get(M.State.replay([M.ProviderSet{"t1", "claude", "", 6n}, M.ProviderSet{"t1", "codex", "", 7n}], H.Demo.switched()), "t1")) == "S2" : String}

# a provider new to a thread is handed it all; one coming back that
# missed nothing is handed nothing
law switch_hands_new_provider:
  {List.length(&2, M.QItem, M.Queue.items(M.State.replay(H.Queue.changes(H.Hub.switch(H.Demo.switched(), 6n, 0, "1", "t1", "grok")), H.Demo.switched()), "t1")) == 1n : Nat}

law switch_back_missed_nothing:
  {List.length(&2, M.QItem, M.Queue.items(M.State.replay(H.Queue.changes(H.Hub.switch(H.Demo.switched(), 6n, 0, "1", "t1", "claude")), H.Demo.switched()), "t1")) == 0n : Nat}

# The orchestrator's thread tools
# -------------------------------

# thread_launch makes an ordinary thread in the caller's project
law mcp_launch_in_project:
  {List.head(&2, M.Change, MC.Res.changes(MC.Mcp.launch(H.Demo.state("claude", M.Completed{}), 5n, "t1", J.Json.obj([J.KV{"prompt", J.Str{"hi"}}]))))
    == Some{M.ThreadCreated{"t5-3", "p1", "hi", M.Worktree{}, "", "", "claude", "", 5n}} : Maybe<&2, M.Change>}

# a thread of another project is out of reach
law mcp_other_project_refused:
  for run: Bool
  for s: M.State
  for now: Nat
  for +t: String
  {MC.Res.good(MC.Mcp.interrupt.k(False{}, run, s, now, t)) == False{} : Bool}

# thread_interrupt stops only a running turn
law mcp_interrupt_idle_nothing:
  for s: M.State
  for now: Nat
  for +t: String
  {MC.Res.changes(MC.Mcp.interrupt.k(True{}, False{}, s, now, t)) == [] : List<&2, M.Change>}

# a thread is done once no turn runs and nothing waits to run
law mcp_done_idle:
  {MC.Mcp.done(H.Demo.state("claude", M.Completed{}), "t1") == True{} : Bool}

law mcp_not_done_running:
  {MC.Mcp.done(H.Demo.state("codex", M.Running{}), "t1") == False{} : Bool}

# a wait lasts between one second and ten minutes
law wait_at_least_a_second:
  {MC.Wait.clamp(0n) == 1n : Nat}

law wait_at_most_ten_minutes:
  {MC.Wait.clamp(9000000n) == 600n : Nat}
# Start-up
# --------
# The window opens before the providers are probed; until they answer,
# the hub serves the model list it found last time.

# the cached list reads back as it was written
law models_cache_json:
  for +ms: String
  for +mt: String
  {BT.Cache.json(BT.Cache.of(ms, mt)) == BT.Cache.one(ms) : String}

# and so does the prompt's text after it
law models_cache_text:
  for +ms: String
  for +mt: String
  {BT.Cache.text(BT.Cache.of(ms, mt)) == mt : String}

# a probe that finds the list clients already have tells no one
law models_quiet:
  for +ms: String
  {BT.Models.news(ms, ms) == False{} : Bool}

# the log is read in one pass, each line parsed once: the state it gives
# is exactly the replay of the log's changes
law store_state_is_replay:
  for ls: List<&2, String>
  for +a: ST.Loaded
  {ST.Loaded.st(ST.Store.load(ls, a)) == M.State.replay(ST.Store.changes(ls), ST.Loaded.st(a)) : M.State}

# and a log read in two parts is the log read whole
law store_load_append:
  for xs: List<&2, String>
  for +ys: List<&2, String>
  for +a: ST.Loaded
  {ST.Store.load(List.append(&2, String, xs, ys), a) == ST.Store.load(ys, ST.Store.load(xs, a)) : ST.Loaded}

# Frames
# ------

# a link's id names the thread it came from
law link_from_id:
  for +from: String
  for +n: String
  {M.Link.from(M.Link.id(M.Link.bare(from), n)) == M.Link.bare(from) : String}

# and any id not starting with 't' is the user's own, told at its first
# character (the timeline asks this of every entry, every frame)
law link_from_plain:
  for +c: Char
  for t: String
  for e: {Char.is_eq(c, Chr{116}) == False{} : Bool}
  {M.Link.from(SCon{c, t}) == "" : String}

# going back to a thread finds the memo it left: only what changed in it
# is laid out again (any memo is a sound start, tl_memo_exact)
law tl_memos_hit:
  for +px: U32
  for +sel: String
  for +its: List<&2, L.TLE>
  for ms: List<&2, L.TLMemo>
  {L.TL.memos.pick(L.TL.memos.keep(L.TLMemo{px, sel, its}, ms), sel) == L.TLMemo{px, sel, its} : L.TLMemo}

# and the memos kept stay few
law tl_memos_bounded:
  for +m: L.TLMemo
  for ms: List<&2, L.TLMemo>
  {Nat.is_le(List.length(&2, L.TLMemo, L.TL.memos.keep(m, ms)), L.TL.memos.max()) == True{} : Bool}

# The hub's own window takes the read model itself, not the log as text
# (nothing to build, parse or replay at start-up). It never holds a
# device or its token, as the wire never carries them
law window_state_private:
  for s: M.State
  {M.State.devices(M.State.private(s)) == Map.new(&2, M.Device) : Map<&2, M.Device>}

# and it counts the same changes the hub does, so a reconnect asks for
# exactly what it missed
law window_state_seq:
  for s: M.State
  {M.State.seq(M.State.private(s)) == M.State.seq(s) : Nat}

# the model handed over is the one the window holds
law window_adopt:
  for u: U.Ui
  for st: M.State
  {U.Ui.state(U.Ui.adopt(u, st)) == st : M.State}

# Todo lists
# ----------

# TodoWrite sets the whole list; a step being done reads as its active form
law todo_write_whole_list:
  {TD.Todo.write(J.Json.obj([J.KV{"todos", J.Json.arr([J.Json.obj([J.KV{"content", J.Str{"Run tests"}}, J.KV{"status", J.Str{"in_progress"}}, J.KV{"activeForm", J.Str{"Running tests"}}])])}]))
    == [TD.Todo{"1", "Run tests", "Running tests", "in_progress"}] : List<&2, TD.Todo>}

law todo_line_active_form:
  {TD.Todo.line(TD.Todo{"1", "Run tests", "Running tests", "in_progress"}) == "[>] Running tests" : String}

# TaskCreate adds a step under its call's id until the result names it;
# TaskUpdate changes it, or drops it when deleted
law todo_task_created:
  {TD.Todo.named(TD.Todo.create([], "u1", J.Json.obj([J.KV{"subject", J.Str{"a"}}])), "u1", "3") == [TD.Todo{"3", "a", "", "pending"}] : List<&2, TD.Todo>}

law todo_task_result_number:
  {TD.Todo.result("Task #12 created successfully: a") == "12" : String}

law todo_task_update:
  {TD.Todo.update([TD.Todo{"3", "a", "", "pending"}], J.Json.obj([J.KV{"taskId", J.Str{"3"}}, J.KV{"status", J.Str{"completed"}}])) == [TD.Todo{"3", "a", "", "completed"}] : List<&2, TD.Todo>}

law todo_task_delete:
  {TD.Todo.update([TD.Todo{"3", "a", "", "pending"}], J.Json.obj([J.KV{"taskId", J.Str{"3"}}, J.KV{"status", J.Str{"deleted"}}])) == [] : List<&2, TD.Todo>}

# a Codex item's completed flag, and an ACP plan's status, become the step's status
law todo_codex_completed:
  {TD.Todo.codex(J.Json.obj([J.KV{"items", J.Json.arr([J.Json.obj([J.KV{"text", J.Str{"a"}}, J.KV{"completed", J.Flag{True{}}}]), J.Json.obj([J.KV{"text", J.Str{"b"}}, J.KV{"completed", J.Flag{False{}}}])])}]))
    == [TD.Todo{"1", "a", "", "completed"}, TD.Todo{"2", "b", "", "pending"}] : List<&2, TD.Todo>}

law todo_acp_plan:
  {TD.Todo.codex(J.Json.obj([J.KV{"items", J.Json.arr(AC.Acp.plan([J.Json.obj([J.KV{"content", J.Str{"x"}}, J.KV{"priority", J.Str{"high"}}, J.KV{"status", J.Str{"in_progress"}}])]))}]))
    == [TD.Todo{"1", "x", "", "in_progress"}] : List<&2, TD.Todo>}

# the list shows while the turn runs or a step is left, and is gone once
# all is done and the turn has ended
law todo_shown_while_running:
  {TD.Todo.shown([TD.Todo{"1", "a", "", "completed"}], True{}) == True{} : Bool}

law todo_shown_while_left:
  for run: Bool
  {TD.Todo.shown([TD.Todo{"1", "a", "", "pending"}], run) == True{} : Bool}

law todo_hidden_when_done:
  {TD.Todo.shown([TD.Todo{"1", "a", "", "completed"}], False{}) == False{} : Bool}

# an assistant message with a todo tool sets the thread's list, once
law todo_write_sets_list:
  {List.length(&2, M.Change, H.Claude.todos(M.State.empty(), "t1", 5n, [J.Json.obj([J.KV{"type", J.Str{"tool_use"}}, J.KV{"name", J.Str{"TodoWrite"}}, J.KV{"input", J.Json.obj([J.KV{"todos", J.Json.arr([])}])}])])) == 1n : Nat}

# Context usage
# -------------

# a reading keeps the part it does not know (0) from the last one
law usage_keeps_window:
  {M.Usage.merge("10/200", 5n, 0n) == "5/200" : String}

law usage_keeps_used:
  {M.Usage.merge("10/200", 0n, 400n) == "10/400" : String}

# the chip says the share of the window, tokens alone without a window,
# and nothing before the first reading
law usage_text_share:
  {U.Usage.text(50n, 200n) == " · ctx 25% of 200" : String}

law usage_text_tokens:
  {U.Usage.text(5000n, 0n) == " · ctx 5k" : String}

law usage_nothing_yet:
  for +w: Nat
  {U.Usage.text(0n, w) == "" : String}

# a reading goes to the log only when it changes
law usage_same_nothing:
  {H.Usage.used.k(M.State.replay([M.UsageSet{"t1", 7n, 0n, 1n}], M.State.empty()), "t1", 2n, 7n) == [] : List<&2, M.Change>}

law usage_change_logged:
  {H.Usage.used.k(M.State.replay([M.UsageSet{"t1", 7n, 0n, 1n}], M.State.empty()), "t1", 2n, 8n) == [M.UsageSet{"t1", 8n, 0n, 2n}] : List<&2, M.Change>}

# The 3D viewer's controls (SolidWorks)
# -------------------------------------

# a drag rotates; with ctrl it pans, with shift zooms, with alt rolls
law view_drag_rotates:
  {N.Drag.mode(0) == 0 : U32}

law view_drag_ctrl_pans:
  {N.Drag.mode(2) == 1 : U32}

law view_drag_shift_zooms:
  {N.Drag.mode(1) == 2 : U32}

law view_drag_alt_rolls:
  {N.Drag.mode(4) == 3 : U32}

# 1-7 are the standard views (5 top, 7 isometric); ctrl+digit stays the
# thread switch
law view_key_top:
  {N.Key3.act(53, 0) == 5 : U32}

law view_key_iso:
  {N.Key3.act(55, 0) == 7 : U32}

law view_key_ctrl_digit_free:
  {N.Key3.act(49, 2) == 0 : U32}

# arrows turn 15 degrees, 90 with shift; alt rolls, ctrl pans
law view_key_arrow_turns:
  {N.Key3.act(65361, 0) == 10 : U32}

law view_key_shift_arrow_quarter:
  {N.Key3.act(65361, 1) == 14 : U32}

law view_key_alt_arrow_rolls:
  {N.Key3.act(65363, 4) == 19 : U32}

law view_key_ctrl_arrow_pans:
  {N.Key3.act(65364, 2) == 23 : U32}

# z zooms out, shift+z in; other letters do nothing
law view_key_z_out:
  {N.Key3.act(122, 0) == 8 : U32}

law view_key_shift_z_in:
  {N.Key3.act(90, 1) == 9 : U32}

law view_key_other_none:
  {N.Key3.act(97, 0) == 0 : U32}
# Signed requests
# ---------------

# a webhook or peer request outside the clock window is refused, whatever
# its signature
law sign_stale_rejected:
  for secret: String
  for +now: Nat
  for +ts: Nat
  for body: String
  for sig: String
  for h: {SG.Sign.fresh(now, ts) == False{} : Bool}
  {SG.Sign.check(secret, now, ts, body, sig) == False{} : Bool}

# the window is five minutes
law sign_window_300:
  {SG.Sign.window() == 300n : Nat}

# a key just accepted is in the replay cache, so it is refused next time
law seen_add_has:
  for s: SG.Seen
  for +k: String
  for +now: Nat
  {SG.Seen.has(SG.Seen.add(s, k, now), k) == True{} : Bool}

# an invite reads back as what made it, colons in its url and all
law invite_roundtrip:
  {SG.Invite.parse(SG.Invite.make("http://host:3787", "p1", "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"))
    == Some{SG.Inv{"http://host:3787", "p1", "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff"}} : Maybe<&2, SG.Inv>}
# Routine schedules
# -----------------

# a routine's next time is after the time asked about, or 0 (never)
law cron_next_after:
  for +c: CR.Cron
  for +after: Nat
  for +off: Nat
  for +east: Bool
  {CR.Cron.ok(after, CR.Cron.next(c, after, off, east)) == True{} : Bool}

# once a routine fires at now (last := now) it is not due again at now
law cron_due_fires_once:
  for +c: CR.Cron
  for +now: Nat
  for +off: Nat
  for +east: Bool
  {CR.Cron.due(c, now, now, off, east) == False{} : Bool}
# Bot spaces
# ----------

# a parsed space never holds more than 200 blocks, whatever a bot writes
law space_caps:
  for +j: J.Json
  {Nat.is_le(SPC.Space.count(SPC.Space.parse(j)), 200n) == True{} : Bool}

# a progress bar never runs past full
law space_progress_max:
  for +p: Nat
  {Nat.is_le(SPC.Space.clamp(p), 1000n) == True{} : Bool}

# what a space's button or input sends the bot is always marked as coming
# from the space
law space_message_prefix:
  for +action: String
  for +value: String
  {String.starts_with(SPC.Space.message(action, value), "[space] ") == True{} : Bool}
# Google (bots' Gmail and Calendar)
# ---------------------------------

# the sign-in asks for access at all (openid, email, Gmail, Calendar)
law google_scopes_nonempty:
  {List.is_empty(&2, String, GO.Google.scopes()) == False{} : Bool}

# base64url undoes itself on bytes that need both '-' and '_'
law google_b64url_roundtrip_example:
  {GO.Gb64.decode(GO.Gb64.encode_url([251, 255, 0, 104])) == [251, 255, 0, 104] : List<&2, U32>}

# a pasted redirect gives its code and state, decoded
law google_code_of_example:
  {GO.Google.code_of("http://127.0.0.1:3787/oauth/google?state=st8&code=4%2F0Ab&scope=email") == Some{GO.CodeState{"4/0Ab", "st8", False{}}} : Maybe<&2, GO.CodeState>}

# a redirect without a code (the user said no) is no code
law google_denied_no_code:
  {GO.Google.code_of("http://127.0.0.1:3787/oauth/google?error=access_denied&state=st8") == None{} : Maybe<&2, GO.CodeState>}

# a To, Cc or Subject cannot start a header of its own
law google_header_no_newline_example:
  {GO.Mail.clean("a@x.org\r\nBcc: e@x.org") == "a@x.org  Bcc: e@x.org" : String}

# sending mail and creating events ask the user first
law google_send_asks:
  {GO.Google.asks("gmail_send") == True{} : Bool}

law google_create_asks:
  {GO.Google.asks("calendar_create") == True{} : Bool}

# an access token is never used in its last minute
law google_expiring_not_fresh:
  for +now: Nat
  {GO.Google.fresh(now, now) == False{} : Bool}

# Bots
# ----

# the step behind bot_hop_bounded: a message goes out only within the bound
law bot_hop_step:
  for ok: Bool
  for +n: Nat
  for h: {Nat.is_le(n, BOT.Hop.max()) == ok : Bool}
  {BOT.Hop.bound(BOT.Hop.send.k(ok, n)) == True{} : Bool}

# a message between bots never goes out deeper than the bound, so two bots
# cannot keep each other talking forever
law bot_hop_bounded:
  for +h: Nat
  {BOT.Hop.bound(BOT.Hop.next(h)) == True{} : Bool}

# a linked machine never takes over a live room here with no member on it
law bot_room_no_takeover:
  for +i: String
  for +n: String
  for +c: Nat
  for +s: M.State
  for +pid: String
  {BHS.Bots.room.open(BOT.Room{i, n, Nil{}, 1n+c, False{}}, s, pid) == False{} : Bool}

# nor opens a room the person deleted
law bot_room_deleted_stays:
  for +i: String
  for +n: String
  for +ms: List<&2, String>
  for +c: Nat
  for +s: M.State
  for +pid: String
  {BHS.Bots.room.open(BOT.Room{i, n, ms, 1n+c, True{}}, s, pid) == False{} : Bool}

# each room is listed once: the rooms here (the window's sidebar, the web,
# each hub's list on a phone) never name one room id twice
law rooms_listed_once:
  for +u: U.Ui
  {BU.BU.once.distinct(BU.RRow, BU.BU.rooms.keyed(u)) == True{} : Bool}

# nor does a phone's one list over every paired hub, where a room shared
# by two machines is reported by both
law hubs_rooms_listed_once:
  for ss: List<&2, Hb.Shown>
  for +many: Bool
  {BU.BU.once.distinct(J.Json, Hb.Hubs.rooms.keyed(ss, many)) == True{} : Bool}

# one room reported twice is listed once; two rooms are two, whatever
# their names
law rooms_same_id_once:
  {BU.BU.once.of(String, [BU.RK{"r1", "den"}, BU.RK{"r1", "den"}]) == [BU.RK{"r1", "den"}] : List<&2, BU.RK<String>>}

law rooms_same_name_both:
  {BU.BU.once.of(String, [BU.RK{"r1", "den"}, BU.RK{"r2", "den"}]) == [BU.RK{"r1", "den"}, BU.RK{"r2", "den"}] : List<&2, BU.RK<String>>}

# a cat waits for you (ears up) whenever its thread needs an approval
law bot_mood_wait:
  for talked: Bool
  for idle: Bool
  {BU.Mood.of(M.StApproval{}, talked, idle) == "wait" : String}

# ... or an answer
law bot_mood_input:
  for talked: Bool
  for idle: Bool
  {BU.Mood.of(M.StInput{}, talked, idle) == "wait" : String}

# a sleeping cat holds still: a window of resting bots never repaints
law bot_mood_sleep_still:
  {BU.Mood.moving("sleep") == False{} : Bool}

# a bot at rest for a quarter hour is asleep
law bot_mood_rest:
  for talked: Bool
  {BU.Mood.of(M.StReady{}, talked, True{}) == "sleep" : String}
# Cats
# ----

# a sleeping, failed or unreachable cat holds still in the window: it never
# asks for frames
law cat_sleep_still:
  {CAT.Cat.moving("sleep") == False{} : Bool}

law cat_error_still:
  {CAT.Cat.moving("error") == False{} : Bool}

law cat_away_still:
  {CAT.Cat.moving("away") == False{} : Bool}

# an unreachable cat carries no animation at all, on any client
law cat_away_holds_still:
  for +look: Nat
  {CAT.Cat.anims.count(CAT.Cat.rig(look, "away")) == 0n : Nat}

# each mood has its own pose (none falls back to idle but idle)
law cat_moods_known:
  {CAT.Cat.mood.all(CAT.Cat.moods()) == [0, 1, 2, 3, 4, 5, 6, 7] : List<&2, U32>}

# every seed has a look: its index is one of the looks
law cat_look_total:
  for +s: Nat
  {Nat.is_lt(CAT.Cat.look.index(s), CAT.Cat.looks()) == True{} : Bool}

# a Pebble ring's webhook that is not fresh is never accepted, whatever it
# carries or claims to be signed with
law index_stale_rejected:
  for secret: String
  for +now: Nat
  for +ts: Nat
  for delivery: String
  for trigger: String
  for test: Bool
  for body: String
  for sig: String
  for h: {SG.Sign.fresh(now, ts) == False{} : Bool}
  {SG.Sign.index(secret, now, ts, delivery, trigger, test, body, sig) == False{} : Bool}

# a webhook with no bearer token lets no bearer in, whatever is sent
law bearer_needs_token:
  for +given: String
  {SG.Sign.bearer("", given) == False{} : Bool}

# a form under a bearer token reaches the bot as JSON: its words, and a
# note in place of the recording (a fuller example, with recordedAt and
# client, is in test/bots_test.bend: normalizing it here takes too long)
law ring_form_json:
  {RG.Ring.form("--b\r\nContent-Disposition: form-data; name=\"transcription\"\r\n\r\nhi\r\n--b\r\nContent-Disposition: form-data; name=\"audio\"\r\n\r\nxx\r\n--b--\r\n", "2")
    == "{\"source\":\"form-data\",\"transcription\":\"hi\",\"audio\":\"omitted, 2 bytes\"}" : String}

# a phone reaches the hub's webhooks at the HTTPS address `tailscale
# serve` gives the hub's own port, not another service's
law tailnet_serve_https:
  {TN.Tailnet.serve("{\"Web\":{\"a.ts.net:443\":{\"Handlers\":{\"/\":{\"Proxy\":\"http://127.0.0.1:3773\"}}},\"a.ts.net:8443\":{\"Handlers\":{\"/\":{\"Proxy\":\"http://127.0.0.1:3787\"}}}}}", "3787")
    == "https://a.ts.net:8443" : String}

# the step behind bot_spawn_bounded
law bot_spawn_step:
  for ok: Bool
  for +n: Nat
  for h: {Nat.is_le(n, BHS.Spawn.max()) == ok : Bool}
  {BHS.Spawn.bound(BOT.Hop.send.k(ok, n)) == True{} : Bool}

# a sub-bot is never made deeper than the bound below a person's bot, so
# bots cannot make bots without end
law bot_spawn_bounded:
  for +d: Nat
  {BHS.Spawn.bound(BHS.Spawn.next(d)) == True{} : Bool}

# the step behind bot_request_in_room
law bot_request_keep:
  for dm: Bool
  for r: BOT.Room
  for +i: String
  for +n: String
  for +ms: List<&2, String>
  for +now: Nat
  for h: {String.starts_with(i, "dm:") == False{} : Bool}
  for e: {BOT.Room.is_dm(r) == dm : Bool}
  {BHS.Req.ok(Some{BHS.Req.target(BHS.Req.keep.k(dm, r), i, n, ms, now)}) == True{} : Bool}

# a request from one bot to another is posted in a room, never a direct
# message, so the person can follow it: a room found is used only when it
# is not a dm: one, and a new one's id (bot_request_fresh_id) is not either
law bot_request_in_room:
  for m: Maybe<&2, BOT.Room>
  for +i: String
  for +n: String
  for +ms: List<&2, String>
  for +now: Nat
  for h: {String.starts_with(i, "dm:") == False{} : Bool}
  {BHS.Req.ok(Some{BHS.Req.target(BHS.Req.keep(m), i, n, ms, now)}) == True{} : Bool}

# a new request room's id is never a direct message's
law bot_request_fresh_id:
  for +now: Nat
  for +seq: Nat
  {String.starts_with(H.Hub.id("r", now, seq), "dm:") == False{} : Bool}

# a bot that names no project may not delegate: its work would run where
# the person cannot see it
law bot_delegate_needs_project:
  for +s: M.State
  for +now: Nat
  for +t: String
  for +proj: String
  for +p: J.Json
  {MC.Res.good(MC.Mcp.delegate.b(True{}, True{}, s, now, t, proj, p)) == False{} : Bool}

# a bot's delegated child is never hidden under the bot: it shows in the
# sidebar of the project it runs in
law kids_bot_child_shown:
  for m: Map<&2, Bool>
  for +c: String
  {U.Kids.add(True{}, m, c) == m : Map<&2, Bool>}

# a cat at rest (ready) holds still in the window: resting bots never keep
# the window drawing frames
law bot_mood_idle_still:
  {BU.Mood.moving("idle") == False{} : Bool}
# Performance numbers
# -------------------

# an error is logged whatever BACKPLANE_LOG says
law perf_errors_always_logged:
  for +th: Nat
  {PF.Log.on(0n, th) == True{} : Bool}

# debug lines stay quiet unless asked for
law perf_debug_quiet_by_default:
  {PF.Log.on(3n, PF.Log.level("")) == False{} : Bool}

# a gauge's window is its latest reading, whatever came before
law perf_gauge_window_is_reading:
  for +name: String
  for +n: Nat
  for +sum: Nat
  for +max: Nat
  for +last: Nat
  for +bs: List<&2, Nat>
  for +old: PF.Stat
  {PF.Stat.since(PF.Stat{name, 1, n, sum, max, last, bs}, old) == PF.Stat{name, 1, n, sum, max, last, bs} : PF.Stat}

# a row with no values has no percentiles
law perf_pct_empty:
  for +name: String
  for +per: Nat
  {PF.Stat.pct(PF.Stat.none(name), per) == 0n : Nat}

# a percentile is the top of its bucket, never above the max
law perf_pct_bucket_top:
  {PF.Stat.pct(PF.Stat{"x", 0, 4n, 10000n, 6000n, 1000n, [0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 2n, 1n, 0n, 1n]}, 500n) == 1023n : Nat}

law perf_pct_capped_by_max:
  {PF.Stat.pct(PF.Stat{"x", 0, 4n, 10000n, 6000n, 1000n, [0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 0n, 2n, 1n, 0n, 1n]}, 990n) == 6000n : Nat}

# the overlay's first frame has no window yet to compare against
law perf_hud_first_frame:
  for +cur: String
  for +at: Nat
  for +now: Nat
  {PF.Hud.text(cur, "", at, now) == "measuring (ctrl+shift+h hides this)" : String}

# the overlay off lays nothing out (no cost in a frame)
law perf_hud_off_draws_nothing:
  for +ty: L.Ty
  for +text: String
  for +w: U32
  {L.Lay.perf.if(False{}, ty, text, w) == L.Out.none() : L.Out}

# Dictation
# ---------

# a term already in the dictionary adds nothing
law voice_add_idem:
  for +ds: List<&2, String>
  for +term: String
  for h: {VO.Voice.dict.has(ds, term) == True{} : Bool}
  {VO.Voice.dict.add(ds, term) == ds : List<&2, String>}

# a term that is not blank, once added, is in the dictionary
law voice_add_has:
  for +ds: List<&2, String>
  for +term: String
  for h: {String.is_empty(String.trim(term)) == False{} : Bool}
  {VO.Voice.dict.has(VO.Voice.dict.add(ds, term), term) == True{} : Bool}

# replacing a word with itself, or an empty word, leaves the text as it is
law voice_fix_same:
  for +t: String
  for +w: String
  {VO.Voice.fix(t, w, w) == t : String}

law voice_fix_empty:
  for +t: String
  for +r: String
  {VO.Voice.fix(t, "", r) == t : String}

# never more than five words to ask about, nor more keywords than the
# transcriber takes
law voice_unsure_bounded:
  for +ds: List<&2, String>
  for +ig: List<&2, String>
  for +text: String
  {Nat.is_le(List.length(&2, VO.Unsure, VO.Voice.unsure(ds, ig, text)), VO.Voice.max_unsure()) == True{} : Bool}

law voice_keywords_bounded:
  for +ds: List<&2, String>
  {Nat.is_le(List.length(&2, String, VO.Voice.keywords(ds)), VO.Voice.max_keywords()) == True{} : Bool}

# Each bot once
# -------------
# Every list of bots keys each bot by what it stands for (a bot here by its
# id, a bot elsewhere by its name, any case, at its machine's link id) and
# keeps the first of each key (src/core/once.bend).

# a list kept once holds no key twice
law once_distinct:
  for -A: Data
  for xs: List<&2, ON.Ky<A>>
  {ON.Once.distinct(ON.Once.keys(A, ON.Once.of(A, xs))) == True{} : Bool}

# and when no key repeats it keeps everything, in order: two things with
# different keys are never merged
law once_keeps:
  for -A: Data
  for +xs: List<&2, ON.Ky<A>>
  for hx: {ON.Once.distinct(ON.Once.keys(A, xs)) == True{} : Bool}
  {ON.Once.of(A, xs) == xs : List<&2, ON.Ky<A>>}

# each bot appears once in the bot list: this machine's bots and those the
# linked machines report (bots.remote), however often one is reported
law bot_rows_once:
  for +u: U.Ui
  {ON.Once.distinct(ON.Once.keys(BU.BRow, BU.BU.rows.keyed(u))) == True{} : Bool}

# the list shown is exactly that keyed list
law bot_rows_shown:
  for +u: U.Ui
  {BU.BU.rows(u) == ON.Once.vals(BU.BRow, BU.BU.rows.keyed(u)) : List<&2, BU.BRow>}

# distinct bots all stay listed
law bot_rows_keep:
  for +u: U.Ui
  for hx: {ON.Once.distinct(ON.Once.keys(BU.BRow, BU.BU.rows.all(u))) == True{} : Bool}
  {BU.BU.rows.keyed(u) == BU.BU.rows.all(u) : List<&2, ON.Ky<BU.BRow>>}

# the room picker lists each bot once too, here or elsewhere, however a
# member names it
law bot_picks_once:
  for +u: U.Ui
  {ON.Once.distinct(ON.Once.keys(BU.Pick, BU.BU.picks.keyed(u))) == True{} : Bool}

law bot_picks_shown:
  for +u: U.Ui
  {BU.BU.picks(u) == ON.Once.vals(BU.Pick, BU.BU.picks.keyed(u)) : List<&2, BU.Pick>}

# a phone paired with several hubs lists each bot once, though linked hubs
# each report the other's bots
law hubs_bots_once:
  for +ss: List<&2, Hb.Shown>
  for +hs: List<&2, Hb.Hub>
  for +many: Bool
  {ON.Once.distinct(ON.Once.keys(J.Json, Hb.Hubs.bots.keyed(ss, hs, many))) == True{} : Bool}

law hubs_bots_shown:
  for +ss: List<&2, Hb.Shown>
  for +hs: List<&2, Hb.Hub>
  for +many: Bool
  {Hb.Hubs.bots(ss, hs, many) == ON.Once.vals(J.Json, Hb.Hubs.bots.keyed(ss, hs, many)) : List<&2, J.Json>}
