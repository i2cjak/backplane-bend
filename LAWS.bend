import Base
import ./src/core/model.bend as M
import ./src/app/viewer.bend as V
import ./src/core/semver.bend as SV

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
