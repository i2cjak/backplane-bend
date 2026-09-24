import Base
import ./src/core/model.bend as M
import ./src/app/viewer.bend as V
import ./src/core/semver.bend as SV
import ./src/app/nui.bend as N
import ./src/core/board.bend as B
import ./src/core/hub.bend as H
import ./src/core/tailnet.bend as TN
import ./src/core/fuzzy.bend as FZ
import ./src/mobile/notify.bend as Nt
import ./src/core/codec.bend as C
import ./src/core/json.bend as J
import ./src/core/attach.bend as AT
import ./src/gfx/tiles.bend as T
import ./src/gfx/raster.bend as R
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
import ./src/core/menu.bend as MN
import ./src/app/win.bend as W
import ./src/core/badge.bend as BG

import ./src/mobile/picker.bend as MP

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

# drawing a frame over the last one's tiles gives exactly the tiles drawn
# from scratch: a kept tile is never stale, whatever changed (ops, base)
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
  {T.Tiles.again(k, e, ops, base1, T.Tiles.make(k, e, old, base0, rx, ry, n), rx, ry, n) == T.Tiles.make(k, e, ops, base1, rx, ry, n) : T.Tiles}

# a tile whose ops and base are unchanged is kept as it is, whatever image
# it holds: it is not drawn again
law tile_keep:
  for +e: Nat
  for +ops: List<&2, R.Op>
  for +base: Image
  for +img: Image
  for +rx: U32
  for +ry: U32
  for +n: U32
  {T.Tile.again(e, ops, base, T.Tile{ops, base, img}, rx, ry, n) == T.Tile{ops, base, img} : T.Tile}

# the same for a whole frame as the window draws it, even when the window
# was resized in between
law frame_again_exact:
  for +w0: U32
  for +h0: U32
  for +w: U32
  for +h: U32
  for +ops: List<&2, R.Op>
  for +old: List<&2, R.Op>
  for +base0: Image
  for +base: Image
  {T.Frame.again(w, h, ops, base, T.FSome{w0, h0, T.Frame.make(w0, h0, old, base0)}) == T.Frame.make(w, h, ops, base) : T.Tiles}

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
