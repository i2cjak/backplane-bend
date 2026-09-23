import Base
import ./src/core/model.bend as M
import ./src/app/viewer.bend as V
import ./src/core/semver.bend as SV
import ./src/app/nui.bend as N
import ./src/core/board.bend as B
import ./src/core/hub.bend as H
import ./src/core/fuzzy.bend as FZ
import ./src/mobile/notify.bend as Nt
import ./src/core/codec.bend as C
import ./src/core/json.bend as J

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
