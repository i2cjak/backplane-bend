import Base
import ./LAWS.bend as Laws
import ./src/core/model.bend as M
import ./src/app/viewer.bend as V
import ./src/core/board.bend as B
import ./src/core/semver.bend as SV
import ./src/app/nui.bend as N

# Lemmas
# ------

law bool_cmp_refl:
  for +b: Bool
  {Bool.cmp(b, b) == EQ{} : Cmp}

def bool_cmp_refl(b):
  match b:
    case False{}:
      {==}
    case True{}:
      {==}

law word_cmp_refl:
  for n: Nat
  for +w: Word(n)
  {Word.cmp(n, w, w) == EQ{} : Cmp}

def word_cmp_refl(n, w):
  match n:
    case 0n:
      {==}
    case 1n+p:
      match w:
        case WCon{+b, +t}:
          %Equal.sym(Cmp, Word.cmp(p, t, t), EQ{}, word_cmp_refl(p, t)) : {Word.cmp.fin(b, b, _) == EQ{} : Cmp}
          bool_cmp_refl(b)

law u32_cmp_refl:
  for +x: U32
  {U32.cmp(x, x) == EQ{} : Cmp}

def u32_cmp_refl(x):
  match x:
    case U32{+w}:
      word_cmp_refl(32n, w)

law eq_fin_rec:
  for -h1: Char
  for -h2: Char
  for r: (String & String) & Cmp
  {String.eq.fin(String.cmp.rec(h1, h2, r)) == String.eq.fin(r) : Bool}

def eq_fin_rec(h1, h2, r):
  match r:
    case (ab, c):
      match ab:
        case (a, b):
          {==}

# False is not True
def Bool.disc(b: Bool) -> Type:
  match b:
    case False{}:
      Unit
    case True{}:
      Empty

law false_ne_true:
  for e: {False{} == True{} : Bool}
  Empty

def false_ne_true(e):
  %e : Bool.disc(_)
  Unit{}

# anything is at least zero
law ge_zero:
  for +a: Nat
  {Nat.is_ge(a, 0n) == True{} : Bool}

def ge_zero(a):
  match a:
    case 0n:
      {==}
    case 1n+p:
      {==}

# n is never at least n + 1 + k
law ge_past:
  for n: Nat
  for +k: Nat
  {Nat.is_ge(n, Nat.add(n, 1n+k)) == False{} : Bool}

def ge_past(n, k):
  match n:
    case 0n:
      {==}
    case 1n+p:
      ge_past(p, k)

# moving the left side forward keeps a >= b
law ge_add:
  for a: Nat
  for b: Nat
  for +d: Nat
  for h: {Nat.is_ge(a, b) == True{} : Bool}
  {Nat.is_ge(Nat.add(a, d), b) == True{} : Bool}

def ge_add(a, b, d, h):
  match a b:
    case 0n 0n:
      ge_zero(d)
    case 0n 1n+q:
      Empty.absurd({Nat.is_ge(Nat.add(0n, d), 1n+q) == True{} : Bool}, false_ne_true(h))
    case 1n+p 0n:
      ge_zero(1n+Nat.add(p, d))
    case 1n+p 1n+q:
      ge_add(p, q, d, h)

law add_succ_r:
  for a: Nat
  for -b: Nat
  {Nat.add(a, 1n+b) == 1n+Nat.add(a, b) : Nat}

def add_succ_r(a, b):
  match a:
    case 0n:
      {==}
    case 1n+p:
      %add_succ_r(p, b) : {1n+Nat.add(p, 1n+b) == 1n+_ : Nat}
      {==}

# one put adds exactly one thread to the shelves
law put_count:
  for sh: M.Shelf
  for -t: M.Thread
  for s: M.Shelves
  {M.Shelves.count(M.Shelves.put(sh, t, s)) == 1n+M.Shelves.count(s) : Nat}

def put_count(sh, t, s):
  match sh s:
    case M.Pinned{} M.Shelves{p, a, st, h}:
      {==}
    case M.Active{} M.Shelves{p, a, st, h}:
      add_succ_r(List.length(&2, M.Thread, p), Nat.add(List.length(&2, M.Thread, a), Nat.add(List.length(&2, M.Thread, st), List.length(&2, M.Thread, h))))
    case M.Settled{} M.Shelves{p, a, st, h}:
      %Equal.sym(Nat, Nat.add(List.length(&2, M.Thread, a), 1n+Nat.add(List.length(&2, M.Thread, st), List.length(&2, M.Thread, h))), 1n+Nat.add(List.length(&2, M.Thread, a), Nat.add(List.length(&2, M.Thread, st), List.length(&2, M.Thread, h))), add_succ_r(List.length(&2, M.Thread, a), Nat.add(List.length(&2, M.Thread, st), List.length(&2, M.Thread, h)))) : {Nat.add(List.length(&2, M.Thread, p), _) == 1n+Nat.add(List.length(&2, M.Thread, p), Nat.add(List.length(&2, M.Thread, a), Nat.add(List.length(&2, M.Thread, st), List.length(&2, M.Thread, h)))) : Nat}
      add_succ_r(List.length(&2, M.Thread, p), Nat.add(List.length(&2, M.Thread, a), Nat.add(List.length(&2, M.Thread, st), List.length(&2, M.Thread, h))))
    case M.Hidden{} M.Shelves{p, a, st, h}:
      %Equal.sym(Nat, Nat.add(List.length(&2, M.Thread, st), 1n+List.length(&2, M.Thread, h)), 1n+Nat.add(List.length(&2, M.Thread, st), List.length(&2, M.Thread, h)), add_succ_r(List.length(&2, M.Thread, st), List.length(&2, M.Thread, h))) : {Nat.add(List.length(&2, M.Thread, p), Nat.add(List.length(&2, M.Thread, a), _)) == 1n+Nat.add(List.length(&2, M.Thread, p), Nat.add(List.length(&2, M.Thread, a), Nat.add(List.length(&2, M.Thread, st), List.length(&2, M.Thread, h)))) : Nat}
      %Equal.sym(Nat, Nat.add(List.length(&2, M.Thread, a), 1n+Nat.add(List.length(&2, M.Thread, st), List.length(&2, M.Thread, h))), 1n+Nat.add(List.length(&2, M.Thread, a), Nat.add(List.length(&2, M.Thread, st), List.length(&2, M.Thread, h))), add_succ_r(List.length(&2, M.Thread, a), Nat.add(List.length(&2, M.Thread, st), List.length(&2, M.Thread, h)))) : {Nat.add(List.length(&2, M.Thread, p), _) == 1n+Nat.add(List.length(&2, M.Thread, p), Nat.add(List.length(&2, M.Thread, a), Nat.add(List.length(&2, M.Thread, st), List.length(&2, M.Thread, h)))) : Nat}
      add_succ_r(List.length(&2, M.Thread, p), Nat.add(List.length(&2, M.Thread, a), Nat.add(List.length(&2, M.Thread, st), List.length(&2, M.Thread, h))))

# Laws
# ----

def Laws.string_eq_refl(s):
  match s:
    case SNil{}:
      {==}
    case SCon{+h, +t}:
      match h:
        case Chr{+x}:
          %Equal.sym(Cmp, U32.cmp(x, x), EQ{}, u32_cmp_refl(x)) : {String.eq.fin(String.cmp.fin(t, t, ((Chr{x}, Chr{x}), _))) == True{} : Bool}
          Equal.trans(Bool, String.eq.fin(String.cmp.rec(Chr{x}, Chr{x}, String.cmp(t, t))),
            String.eq.fin(String.cmp(t, t)), True{},
            eq_fin_rec(Chr{x}, Chr{x}, String.cmp(t, t)), Laws.string_eq_refl(t))

def Laws.settle_at_window(last, w):
  Nat.ge_refl(Nat.add(last, w))

def Laws.settle_fresh(now, w):
  ge_past(now, w)

def Laws.settle_monotone(now, last, w, d, h):
  ge_add(now, Nat.add(last, w), d, h)

def Laws.settle_never_running(now, w, pending, archived, o):
  {==}

def Laws.settle_never_pending(t, p, archived, o, stale):
  match t:
    case M.Idle{}:
      {==}
    case M.Running{}:
      {==}
    case M.Completed{}:
      {==}
    case M.Interrupted{}:
      {==}
    case M.Failed{}:
      {==}

def Laws.settle_respects_unsettle(busy, archived, stale):
  match busy archived:
    case False{} False{}:
      {==}
    case False{} True{}:
      {==}
    case True{} False{}:
      {==}
    case True{} True{}:
      {==}

def Laws.replay_snoc(es, s, e):
  match es:
    case Nil{}:
      {==}
    case h <> t:
      Laws.replay_snoc(t, M.State.apply(s, h), e)

def Laws.sidebar_split_count(ts):
  match ts:
    case Nil{}:
      {==}
    case +t <> +rest:
      Equal.trans(Nat, M.Shelves.count(M.Shelves.put(M.Shelf.of(t), t, M.Sidebar.split(rest))),
        1n+M.Shelves.count(M.Sidebar.split(rest)), 1n+List.length(&2, M.Thread, rest),
        put_count(M.Shelf.of(t), t, M.Sidebar.split(rest)),
        Equal.cong(Nat, Nat, x => 1n+x, M.Shelves.count(M.Sidebar.split(rest)), List.length(&2, M.Thread, rest),
          Laws.sidebar_split_count(rest)))

# Viewer lemmas
# -------------

law sub_self:
  for a: Nat
  {Nat.sub(a, a) == 0n : Nat}

def sub_self(a):
  match a:
    case 0n:
      {==}
    case 1n+p:
      sub_self(p)

law key_fin_rec:
  for -h1: Char
  for -h2: Char
  for r: (String & String) & Cmp
  {V.Key.cmp.fin(String.cmp.rec(h1, h2, r)) == V.Key.cmp.fin(r) : Cmp}

def key_fin_rec(h1, h2, r):
  match r:
    case (ab, c):
      match ab:
        case (a, b):
          {==}

# a key is in order with itself
law key_cmp_refl:
  for +s: String
  {V.Key.cmp(s, s) == EQ{} : Cmp}

def key_cmp_refl(s):
  match s:
    case SNil{}:
      {==}
    case SCon{+h, +t}:
      match h:
        case Chr{+x}:
          %Equal.sym(Cmp, U32.cmp(x, x), EQ{}, u32_cmp_refl(x)) : {V.Key.cmp.fin(String.cmp.fin(t, t, ((Chr{x}, Chr{x}), _))) == EQ{} : Cmp}
          Equal.trans(Cmp, V.Key.cmp.fin(String.cmp.rec(Chr{x}, Chr{x}, String.cmp(t, t))),
            V.Key.cmp.fin(String.cmp(t, t)), EQ{},
            key_fin_rec(Chr{x}, Chr{x}, String.cmp(t, t)), key_cmp_refl(t))

law u32_eq_refl:
  for +x: U32
  {U32.is_eq(x, x) == True{} : Bool}

def u32_eq_refl(x):
  %Equal.sym(Cmp, U32.cmp(x, x), EQ{}, u32_cmp_refl(x)) : {Cmp.is_eq(_) == True{} : Bool}
  {==}

# Viewer laws
# -----------

def Laws.fade_done(born, k):
  %Equal.sym(Bool, Nat.is_ge(Nat.add(Nat.add(born, V.Fade.ms()), k), Nat.add(born, V.Fade.ms())), True{},
    ge_add(Nat.add(born, V.Fade.ms()), Nat.add(born, V.Fade.ms()), k, Nat.ge_refl(Nat.add(born, V.Fade.ms()))))
    : {V.Fade.alpha.k(_, Nat.sub(Nat.add(Nat.add(born, V.Fade.ms()), k), born)) == 255 : U32}
  {==}

def Laws.fade_start(born):
  %Equal.sym(Bool, Nat.is_ge(born, Nat.add(born, V.Fade.ms())), False{}, ge_past(born, 219n))
    : {V.Fade.alpha.k(_, Nat.sub(born, born)) == 0 : U32}
  %Equal.sym(Nat, Nat.sub(born, born), 0n, sub_self(born)) : {V.Fade.alpha.k(False{}, _) == 0 : U32}
  {==}

def Laws.scene_merge_self(ss, now):
  match ss:
    case Nil{}:
      {==}
    case V.Seen{B.Item{+k, +s, +l, +p, +i}, +b} <> +t:
      %Equal.sym(Cmp, V.Key.cmp(k, k), EQ{}, key_cmp_refl(k))
        : {V.Scene.merge(V.Seen{B.Item{k, s, l, p, i}, b} <> t, B.Item{k, s, l, p, i} <> V.Scene.items(t), _, now) == V.Seen{B.Item{k, s, l, p, i}, b} <> t : List<&2, V.Seen>}
      %Equal.sym(Bool, U32.is_eq(s, s), True{}, u32_eq_refl(s))
        : {V.Scene.keep(_, B.Item{k, s, l, p, i}, b, now) <> V.Scene.merge(t, V.Scene.items(t), V.Scene.heads(t, V.Scene.items(t)), now) == V.Seen{B.Item{k, s, l, p, i}, b} <> t : List<&2, V.Seen>}
      Equal.cong(List<&2, V.Seen>, List<&2, V.Seen>, xs => V.Seen{B.Item{k, s, l, p, i}, b} <> xs,
        V.Scene.merge(t, V.Scene.items(t), V.Scene.heads(t, V.Scene.items(t)), now), t, Laws.scene_merge_self(t, now))

# Update lemmas and laws
# ----------------------

law nat_cmp_refl:
  for a: Nat
  {Nat.cmp(a, a) == EQ{} : Cmp}

def nat_cmp_refl(a):
  match a:
    case 0n:
      {==}
    case 1n+p:
      nat_cmp_refl(p)

law pre_cmp_refl:
  for b: Bool
  {SV.Ver.pre_cmp(b, b) == EQ{} : Cmp}

def pre_cmp_refl(b):
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

def Laws.semver_cmp_refl(v):
  match v:
    case SV.Ver{+a, +b, +c, +p}:
      %Equal.sym(Cmp, Nat.cmp(a, a), EQ{}, nat_cmp_refl(a)) : {SV.Ver.then(_, SV.Ver.then(Nat.cmp(b, b), SV.Ver.then(Nat.cmp(c, c), SV.Ver.pre_cmp(p, p)))) == EQ{} : Cmp}
      %Equal.sym(Cmp, Nat.cmp(b, b), EQ{}, nat_cmp_refl(b)) : {SV.Ver.then(_, SV.Ver.then(Nat.cmp(c, c), SV.Ver.pre_cmp(p, p))) == EQ{} : Cmp}
      %Equal.sym(Cmp, Nat.cmp(c, c), EQ{}, nat_cmp_refl(c)) : {SV.Ver.then(_, SV.Ver.pre_cmp(p, p)) == EQ{} : Cmp}
      pre_cmp_refl(p)

def Laws.update_never_same(v):
  %Equal.sym(Cmp, SV.Ver.cmp(v, v), EQ{}, Laws.semver_cmp_refl(v)) : {Cmp.is_gt(_) == False{} : Bool}
  {==}

# Orchestration laws
# ------------------

def Laws.task_terminal_absorbing(cur, want, h):
  match cur:
    case M.TaskQueued{}:
      Empty.absurd({M.TaskState.next(M.TaskQueued{}, want) == M.TaskQueued{} : M.TaskState}, false_ne_true(h))
    case M.TaskRunning{}:
      Empty.absurd({M.TaskState.next(M.TaskRunning{}, want) == M.TaskRunning{} : M.TaskState}, false_ne_true(h))
    case M.TaskDone{}:
      {==}
    case M.TaskFailed{}:
      {==}
    case M.TaskCancelled{}:
      {==}

def Laws.task_never_requeued():
  {==}

def Laws.task_delivered_once(t):
  match t:
    case M.Task{_, _, _, _, st, _, _, _, _}:
      match st:
        case M.TaskQueued{}:
          {==}
        case M.TaskRunning{}:
          {==}
        case M.TaskDone{}:
          {==}
        case M.TaskFailed{}:
          {==}
        case M.TaskCancelled{}:
          {==}

# n + k is never less than n
law lt_add_self:
  for n: Nat
  for +k: Nat
  {Nat.is_lt(Nat.add(n, k), n) == False{} : Bool}

def lt_add_self(n, k):
  match n:
    case 0n:
      match k:
        case 0n:
          {==}
        case 1n+p:
          {==}
    case 1n+p:
      lt_add_self(p, k)

def Laws.delegation_bounded(k):
  lt_add_self(M.Task.max_depth(), k)

def Laws.setting_default(k, d):
  {==}

def Laws.nui_with_own_vw(n):
  match n:
    case N.Nui{u, w, hh, mx, my, sd, sc, ca, fo, pa, hi, ms, vw}:
      {==}

def Laws.stale_board_ignored(n, key, items, now, h):
  %Equal.sym(Bool, N.Vw.fresh_for(N.Nui.vw(n), key), False{}, h) : {N.Nui.with_vw(n, N.Vw.if(_, N.Nui.vw(n), v => N.Vw.board.same(v, key, items, now))) == n : N.Nui}
  Laws.nui_with_own_vw(n)

