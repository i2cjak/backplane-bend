import Base
import ./LAWS.bend as Laws
import ./src/core/model.bend as M
import ./src/app/viewer.bend as V
import ./src/core/board.bend as B
import ./src/core/semver.bend as SV
import ./src/app/nui.bend as N
import ./src/core/hub.bend as H
import ./src/core/fuzzy.bend as FZ
import ./src/mobile/notify.bend as Nt
import ./src/core/codec.bend as C
import ./src/core/json.bend as J
import ./src/core/attach.bend as AT
import ./src/core/svg.bend as SVG
import ./src/core/lightbox.bend as LBX
import ./src/core/links.bend as LK
import ./src/core/tailnet.bend as TN
import ./src/gfx/tiles.bend as T
import ./src/gfx/raster.bend as R
import ./src/gfx/font.bend as F
import ./src/app/layout.bend as L
import ./src/core/eq.bend as Q
import ./src/core/gh.bend as GH
import ./src/core/fold.bend as FO
import ./src/core/plot.bend as PL
import ./src/mobile/view.bend as MV
import ./src/core/client.bend as U

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

# x + y is one more than x + z when y is one more than z
law add_lift:
  for x: Nat
  for y: Nat
  for z: Nat
  for h: {y == 1n+z : Nat}
  {Nat.add(x, y) == 1n+Nat.add(x, z) : Nat}

def add_lift(x, y, z, h):
  %Equal.sym(Nat, y, 1n+z, h) : {Nat.add(x, _) == 1n+Nat.add(x, z) : Nat}
  add_succ_r(x, z)

# one put adds exactly one thread to the shelves
law put_count:
  for sh: M.Shelf
  for -t: M.Thread
  for s: M.Shelves
  {M.Shelves.count(M.Shelves.put(sh, t, s)) == 1n+M.Shelves.count(s) : Nat}

def put_count(sh, t, s):
  match sh s:
    case M.Pinned{} M.Shelves{+p, +a, +st, +h, +sn}:
      {==}
    case M.Active{} M.Shelves{+p, +a, +st, +h, +sn}:
      add_lift(List.length(&2, M.Thread, p), Nat.add(1n+List.length(&2, M.Thread, a), Nat.add(List.length(&2, M.Thread, st), Nat.add(List.length(&2, M.Thread, h), List.length(&2, M.Thread, sn)))), Nat.add(List.length(&2, M.Thread, a), Nat.add(List.length(&2, M.Thread, st), Nat.add(List.length(&2, M.Thread, h), List.length(&2, M.Thread, sn)))), {==})
    case M.Settled{} M.Shelves{+p, +a, +st, +h, +sn}:
      add_lift(List.length(&2, M.Thread, p), Nat.add(List.length(&2, M.Thread, a), Nat.add(1n+List.length(&2, M.Thread, st), Nat.add(List.length(&2, M.Thread, h), List.length(&2, M.Thread, sn)))), Nat.add(List.length(&2, M.Thread, a), Nat.add(List.length(&2, M.Thread, st), Nat.add(List.length(&2, M.Thread, h), List.length(&2, M.Thread, sn)))), add_lift(List.length(&2, M.Thread, a), Nat.add(1n+List.length(&2, M.Thread, st), Nat.add(List.length(&2, M.Thread, h), List.length(&2, M.Thread, sn))), Nat.add(List.length(&2, M.Thread, st), Nat.add(List.length(&2, M.Thread, h), List.length(&2, M.Thread, sn))), {==}))
    case M.Hidden{} M.Shelves{+p, +a, +st, +h, +sn}:
      add_lift(List.length(&2, M.Thread, p), Nat.add(List.length(&2, M.Thread, a), Nat.add(List.length(&2, M.Thread, st), Nat.add(1n+List.length(&2, M.Thread, h), List.length(&2, M.Thread, sn)))), Nat.add(List.length(&2, M.Thread, a), Nat.add(List.length(&2, M.Thread, st), Nat.add(List.length(&2, M.Thread, h), List.length(&2, M.Thread, sn)))), add_lift(List.length(&2, M.Thread, a), Nat.add(List.length(&2, M.Thread, st), Nat.add(1n+List.length(&2, M.Thread, h), List.length(&2, M.Thread, sn))), Nat.add(List.length(&2, M.Thread, st), Nat.add(List.length(&2, M.Thread, h), List.length(&2, M.Thread, sn))), add_lift(List.length(&2, M.Thread, st), Nat.add(1n+List.length(&2, M.Thread, h), List.length(&2, M.Thread, sn)), Nat.add(List.length(&2, M.Thread, h), List.length(&2, M.Thread, sn)), {==})))
    case M.Snoozed{} M.Shelves{+p, +a, +st, +h, +sn}:
      add_lift(List.length(&2, M.Thread, p), Nat.add(List.length(&2, M.Thread, a), Nat.add(List.length(&2, M.Thread, st), Nat.add(List.length(&2, M.Thread, h), 1n+List.length(&2, M.Thread, sn)))), Nat.add(List.length(&2, M.Thread, a), Nat.add(List.length(&2, M.Thread, st), Nat.add(List.length(&2, M.Thread, h), List.length(&2, M.Thread, sn)))), add_lift(List.length(&2, M.Thread, a), Nat.add(List.length(&2, M.Thread, st), Nat.add(List.length(&2, M.Thread, h), 1n+List.length(&2, M.Thread, sn))), Nat.add(List.length(&2, M.Thread, st), Nat.add(List.length(&2, M.Thread, h), List.length(&2, M.Thread, sn))), add_lift(List.length(&2, M.Thread, st), Nat.add(List.length(&2, M.Thread, h), 1n+List.length(&2, M.Thread, sn)), Nat.add(List.length(&2, M.Thread, h), List.length(&2, M.Thread, sn)), add_succ_r(List.length(&2, M.Thread, h), List.length(&2, M.Thread, sn)))))

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

def Laws.sidebar_split_at_count(ts, navs, now):
  match ts:
    case Nil{}:
      {==}
    case +t <> +rest:
      Equal.trans(Nat, M.Shelves.count(M.Shelves.put(M.Shelf.at(t, M.Nav.until(M.Nav.get(navs, M.Thread.id(t))), now), t, M.Sidebar.split.at(rest, navs, now))),
        1n+M.Shelves.count(M.Sidebar.split.at(rest, navs, now)), 1n+List.length(&2, M.Thread, rest),
        put_count(M.Shelf.at(t, M.Nav.until(M.Nav.get(navs, M.Thread.id(t))), now), t, M.Sidebar.split.at(rest, navs, now)),
        Equal.cong(Nat, Nat, x => 1n+x, M.Shelves.count(M.Sidebar.split.at(rest, navs, now)), List.length(&2, M.Thread, rest),
          Laws.sidebar_split_at_count(rest, navs, now)))

def Laws.settle_never_snoozed(now, w, t, until, h):
  %Equal.sym(Bool, Nat.is_ge(now, until), False{}, h) : {M.Settle.auto.s(Bool.not(_), now, w, t, until) == False{} : Bool}
  {==}

def Laws.snooze_wakes(now, until, h):
  %Equal.sym(Bool, Nat.is_ge(now, until), True{}, h) : {Bool.not(_) == False{} : Bool}
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
    case SV.Ver{+a, +b, +c, +p, +d, +n}:
      %Equal.sym(Cmp, Nat.cmp(a, a), EQ{}, nat_cmp_refl(a)) : {SV.Ver.then(_, SV.Ver.then(Nat.cmp(b, b), SV.Ver.then(Nat.cmp(c, c), SV.Ver.then(SV.Ver.pre_cmp(p, p), SV.Ver.then(Nat.cmp(d, d), Nat.cmp(n, n)))))) == EQ{} : Cmp}
      %Equal.sym(Cmp, Nat.cmp(b, b), EQ{}, nat_cmp_refl(b)) : {SV.Ver.then(_, SV.Ver.then(Nat.cmp(c, c), SV.Ver.then(SV.Ver.pre_cmp(p, p), SV.Ver.then(Nat.cmp(d, d), Nat.cmp(n, n))))) == EQ{} : Cmp}
      %Equal.sym(Cmp, Nat.cmp(c, c), EQ{}, nat_cmp_refl(c)) : {SV.Ver.then(_, SV.Ver.then(SV.Ver.pre_cmp(p, p), SV.Ver.then(Nat.cmp(d, d), Nat.cmp(n, n)))) == EQ{} : Cmp}
      %Equal.sym(Cmp, SV.Ver.pre_cmp(p, p), EQ{}, pre_cmp_refl(p)) : {SV.Ver.then(_, SV.Ver.then(Nat.cmp(d, d), Nat.cmp(n, n))) == EQ{} : Cmp}
      %Equal.sym(Cmp, Nat.cmp(d, d), EQ{}, nat_cmp_refl(d)) : {SV.Ver.then(_, Nat.cmp(n, n)) == EQ{} : Cmp}
      nat_cmp_refl(n)

def Laws.update_never_same(v):
  %Equal.sym(Cmp, SV.Ver.cmp(v, v), EQ{}, Laws.semver_cmp_refl(v)) : {Cmp.is_gt(_) == False{} : Bool}
  {==}

law nat_cmp_succ:
  for n: Nat
  {Nat.cmp(1n+n, n) == GT{} : Cmp}

def nat_cmp_succ(n):
  match n:
    case 0n:
      {==}
    case 1n+p:
      nat_cmp_succ(p)

def Laws.semver_pre_before_release(a, b, c, d, n):
  %Equal.sym(Cmp, Nat.cmp(a, a), EQ{}, nat_cmp_refl(a)) : {Cmp.is_gt(SV.Ver.then(_, SV.Ver.then(Nat.cmp(b, b), SV.Ver.then(Nat.cmp(c, c), SV.Ver.then(GT{}, SV.Ver.then(Nat.cmp(0n, d), Nat.cmp(0n, n))))))) == True{} : Bool}
  %Equal.sym(Cmp, Nat.cmp(b, b), EQ{}, nat_cmp_refl(b)) : {Cmp.is_gt(SV.Ver.then(_, SV.Ver.then(Nat.cmp(c, c), SV.Ver.then(GT{}, SV.Ver.then(Nat.cmp(0n, d), Nat.cmp(0n, n)))))) == True{} : Bool}
  %Equal.sym(Cmp, Nat.cmp(c, c), EQ{}, nat_cmp_refl(c)) : {Cmp.is_gt(SV.Ver.then(_, SV.Ver.then(GT{}, SV.Ver.then(Nat.cmp(0n, d), Nat.cmp(0n, n))))) == True{} : Bool}
  {==}

def Laws.semver_nightly_later(a, b, c, d, n):
  %Equal.sym(Cmp, Nat.cmp(a, a), EQ{}, nat_cmp_refl(a)) : {Cmp.is_gt(SV.Ver.then(_, SV.Ver.then(Nat.cmp(b, b), SV.Ver.then(Nat.cmp(c, c), SV.Ver.then(EQ{}, SV.Ver.then(Nat.cmp(d, d), Nat.cmp(1n+n, n))))))) == True{} : Bool}
  %Equal.sym(Cmp, Nat.cmp(b, b), EQ{}, nat_cmp_refl(b)) : {Cmp.is_gt(SV.Ver.then(_, SV.Ver.then(Nat.cmp(c, c), SV.Ver.then(EQ{}, SV.Ver.then(Nat.cmp(d, d), Nat.cmp(1n+n, n)))))) == True{} : Bool}
  %Equal.sym(Cmp, Nat.cmp(c, c), EQ{}, nat_cmp_refl(c)) : {Cmp.is_gt(SV.Ver.then(_, SV.Ver.then(EQ{}, SV.Ver.then(Nat.cmp(d, d), Nat.cmp(1n+n, n))))) == True{} : Bool}
  %Equal.sym(Cmp, Nat.cmp(d, d), EQ{}, nat_cmp_refl(d)) : {Cmp.is_gt(SV.Ver.then(EQ{}, SV.Ver.then(_, Nat.cmp(1n+n, n)))) == True{} : Bool}
  %Equal.sym(Cmp, Nat.cmp(1n+n, n), GT{}, nat_cmp_succ(n)) : {Cmp.is_gt(SV.Ver.then(EQ{}, SV.Ver.then(EQ{}, _))) == True{} : Bool}
  {==}

def Laws.semver_nightly_next_day(a, b, c, d, n, m):
  %Equal.sym(Cmp, Nat.cmp(a, a), EQ{}, nat_cmp_refl(a)) : {Cmp.is_gt(SV.Ver.then(_, SV.Ver.then(Nat.cmp(b, b), SV.Ver.then(Nat.cmp(c, c), SV.Ver.then(EQ{}, SV.Ver.then(Nat.cmp(1n+d, d), Nat.cmp(m, n))))))) == True{} : Bool}
  %Equal.sym(Cmp, Nat.cmp(b, b), EQ{}, nat_cmp_refl(b)) : {Cmp.is_gt(SV.Ver.then(_, SV.Ver.then(Nat.cmp(c, c), SV.Ver.then(EQ{}, SV.Ver.then(Nat.cmp(1n+d, d), Nat.cmp(m, n)))))) == True{} : Bool}
  %Equal.sym(Cmp, Nat.cmp(c, c), EQ{}, nat_cmp_refl(c)) : {Cmp.is_gt(SV.Ver.then(_, SV.Ver.then(EQ{}, SV.Ver.then(Nat.cmp(1n+d, d), Nat.cmp(m, n))))) == True{} : Bool}
  %Equal.sym(Cmp, Nat.cmp(1n+d, d), GT{}, nat_cmp_succ(d)) : {Cmp.is_gt(SV.Ver.then(EQ{}, SV.Ver.then(EQ{}, SV.Ver.then(_, Nat.cmp(m, n))))) == True{} : Bool}
  {==}

# Attachment lemmas and laws
# --------------------------

law attach_chr_ok:
  for b: Bool
  for +c: U32
  for e: {AT.Att.ok(c) == b : Bool}
  {AT.Att.ok(AT.Att.chr(b, c)) == True{} : Bool}

def attach_chr_ok(b, c, e):
  match b:
    case True{}:
      e
    case False{}:
      {==}

def Laws.attach_clean_ok(s):
  match s:
    case SNil{}:
      {==}
    case SCon{Chr{+c}, t}:
      %Equal.sym(Bool, AT.Att.ok(AT.Att.chr(AT.Att.ok(c), c)), True{}, attach_chr_ok(AT.Att.ok(c), c, {==})) : {Bool.and(_, AT.Att.all_ok(AT.Att.clean(t))) == True{} : Bool}
      Laws.attach_clean_ok(t)

def Laws.drop_non_file_ignored(c, s, rest, h):
  %Equal.sym(Bool, Char.is_eq(c, 'f'), False{}, h) : {AT.Att.uri.keep(String.starts_with.if(s, "ile:", _), SCon{c, s}, rest) == rest : List<&2, String>}
  {==}

def Laws.drop_uri_list_example():
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


def Laws.resume_is_replay(a, b, s):
  match a:
    case Nil{}:
      {==}
    case h <> t:
      Laws.resume_is_replay(t, b, M.State.apply(s, h))

def Laws.queue_never_concurrent(s, now, th, msg, role, text, h1, h2):
  %Equal.sym(Bool, H.Hub.running(H.Hub.thread(s, th)), True{}, h1) : {H.Step.outs_of(H.Hub.post.w(_, M.Worktree.gone(H.Hub.thread(s, th)), M.Worktree.pending(H.Hub.thread(s, th), now), s, now, th, msg, role, text)) == [] : List<&2, H.Out>}
  %Equal.sym(Bool, String.eq(H.Hub.provider(H.Hub.thread(s, th)), "claude"), False{}, h2) : {H.Step.outs_of(H.Hub.post.go(Bool.or(Bool.and(True{}, Bool.not(_)), M.Worktree.pending(H.Hub.thread(s, th), now)), H.Hub.thread(s, th), H.Hub.cwd(s, H.Hub.thread(s, th)), M.Queue.of(s, th), now, th, msg, role, text)) == [] : List<&2, H.Out>}
  {==}

def Laws.resend_stored_once(s, now, client, id, th, text, msg, h1, h2):
  %Equal.sym(Bool, String.is_empty(msg), False{}, h1) : {H.Queue.changes(H.Hub.turn.m(s, now, client, id, th, text, Bool.pick(String, _, H.Hub.id("m", now, H.Hub.seq(s)), msg), Bool.not(_))) == [] : List<&2, M.Change>}
  %Equal.sym(Bool, H.Hub.has_msg(H.Hub.entries(s), msg), True{}, h2) : {H.Queue.changes(H.Hub.turn.k(Bool.and(True{}, _), s, now, client, id, th, msg, text)) == [] : List<&2, M.Change>}
  {==}

def Laws.inbox_never_interrupts(s, now, from, to, role, text, h):
  %Equal.sym(Bool, H.Hub.running(H.Hub.thread(s, to)), True{}, h) : {H.Step.outs_of(H.Hub.inbox.w(_, M.Worktree.gone(H.Hub.thread(s, to)), M.Worktree.pending(H.Hub.thread(s, to), now), s, now, from, to, role, text)) == [] : List<&2, H.Out>}
  {==}

law or_true_r:
  for b: Bool
  {Bool.or(b, True{}) == True{} : Bool}

def or_true_r(b):
  match b:
    case False{}:
      {==}
    case True{}:
      {==}

law and_false_r:
  for b: Bool
  {Bool.and(b, False{}) == False{} : Bool}

def and_false_r(b):
  match b:
    case False{}:
      {==}
    case True{}:
      {==}

def Laws.worktree_pending_local(wt, c, now):
  {==}

def Laws.worktree_pending_ends(e, wt, c, now, h):
  match e:
    case M.Worktree{}:
      %Equal.sym(Bool, Nat.is_lt(now, Nat.add(c, M.Worktree.wait())), False{}, h) : {Bool.and(_, String.is_empty(wt)) == False{} : Bool}
      {==}
    case M.Local{}:
      {==}

def Laws.worktree_waits(s, now, th, msg, role, text, h):
  %Equal.sym(Bool, M.Worktree.pending(H.Hub.thread(s, th), now), True{}, h) : {H.Step.outs_of(H.Hub.post.w(H.Hub.running(H.Hub.thread(s, th)), M.Worktree.gone(H.Hub.thread(s, th)), _, s, now, th, msg, role, text)) == [] : List<&2, H.Out>}
  %Equal.sym(Bool, Bool.and(M.Worktree.gone(H.Hub.thread(s, th)), False{}), False{}, and_false_r(M.Worktree.gone(H.Hub.thread(s, th)))) : {H.Step.outs_of(H.Hub.post.v(Bool.and(Bool.not(H.Hub.running(H.Hub.thread(s, th))), _), H.Hub.running(H.Hub.thread(s, th)), True{}, s, now, th, msg, role, text)) == [] : List<&2, H.Out>}
  %Equal.sym(Bool, Bool.and(Bool.not(H.Hub.running(H.Hub.thread(s, th))), False{}), False{}, and_false_r(Bool.not(H.Hub.running(H.Hub.thread(s, th))))) : {H.Step.outs_of(H.Hub.post.v(_, H.Hub.running(H.Hub.thread(s, th)), True{}, s, now, th, msg, role, text)) == [] : List<&2, H.Out>}
  %Equal.sym(Bool, Bool.or(Bool.and(H.Hub.running(H.Hub.thread(s, th)), Bool.not(String.eq(H.Hub.provider(H.Hub.thread(s, th)), "claude"))), True{}), True{}, or_true_r(Bool.and(H.Hub.running(H.Hub.thread(s, th)), Bool.not(String.eq(H.Hub.provider(H.Hub.thread(s, th)), "claude"))))) : {H.Step.outs_of(H.Hub.post.go(_, H.Hub.thread(s, th), H.Hub.cwd(s, H.Hub.thread(s, th)), M.Queue.of(s, th), now, th, msg, role, text)) == [] : List<&2, H.Out>}
  {==}

def Laws.worktree_by_default():
  {==}

def Laws.worktree_revives(s, now, th, msg, role, text, h1, h2, h3):
  %Equal.sym(Bool, H.Hub.running(H.Hub.thread(s, th)), False{}, h1) : {H.Step.outs_of(H.Hub.post.w(_, M.Worktree.gone(H.Hub.thread(s, th)), M.Worktree.pending(H.Hub.thread(s, th), now), s, now, th, msg, role, text)) == [H.Wt.revive(s, th)] : List<&2, H.Out>}
  %Equal.sym(Bool, M.Worktree.gone(H.Hub.thread(s, th)), True{}, h2) : {H.Step.outs_of(H.Hub.post.w(False{}, _, M.Worktree.pending(H.Hub.thread(s, th), now), s, now, th, msg, role, text)) == [H.Wt.revive(s, th)] : List<&2, H.Out>}
  %Equal.sym(Bool, M.Worktree.pending(H.Hub.thread(s, th), now), False{}, h3) : {H.Step.outs_of(H.Hub.post.w(False{}, True{}, _, s, now, th, msg, role, text)) == [H.Wt.revive(s, th)] : List<&2, H.Out>}
  {==}

def Laws.worktree_kept_while_busy(sh, ours, merged, aged):
  {==}

def Laws.worktree_kept_out(busy, sh, ours, merged, aged, h):
  match busy sh:
    case True{} _:
      {==}
    case False{} M.Settled{}:
      Empty.absurd({M.Worktree.drop.k(False{}, M.Settled{}, ours, merged, aged) == False{} : Bool}, false_ne_true(Equal.sym(Bool, True{}, False{}, h)))
    case False{} M.Hidden{}:
      Empty.absurd({M.Worktree.drop.k(False{}, M.Hidden{}, ours, merged, aged) == False{} : Bool}, false_ne_true(Equal.sym(Bool, True{}, False{}, h)))
    case False{} M.Pinned{}:
      {==}
    case False{} M.Active{}:
      {==}
    case False{} M.Snoozed{}:
      {==}

law worktree_drop_not_ours:
  for busy: Bool
  for sh: M.Shelf
  for merged: Bool
  for aged: Bool
  {M.Worktree.drop.k(busy, sh, False{}, merged, aged) == False{} : Bool}

def worktree_drop_not_ours(busy, sh, merged, aged):
  match busy sh:
    case True{} _:
      {==}
    case False{} M.Settled{}:
      {==}
    case False{} M.Hidden{}:
      {==}
    case False{} M.Pinned{}:
      {==}
    case False{} M.Active{}:
      {==}
    case False{} M.Snoozed{}:
      {==}

def Laws.worktree_kept_unless_ours(busy, sh, wt, merged, aged, h):
  %Equal.sym(Bool, M.Worktree.ours(wt), False{}, h) : {M.Worktree.drop.k(busy, sh, _, merged, aged) == False{} : Bool}
  worktree_drop_not_ours(busy, sh, merged, aged)

def Laws.worktree_kept_fresh(ours):
  and_false_r(ours)

def Laws.worktree_dropped_on_merge(aged):
  {==}

def Laws.worktree_dropped_when_aged(merged):
  or_true_r(merged)

def Laws.worktree_dropped_when_hidden(merged):
  {==}

def Laws.merge_settles(t, at, h):
  match t:
    case M.Thread{id, p, ti, c, a, tu, pe, False{}, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, False{}}:
      {==}
    case M.Thread{id, p, ti, c, a, tu, pe, False{}, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, True{}}:
      Empty.absurd({M.Shelf.of(M.Thread.settled(True{}, at, M.Thread{id, p, ti, c, a, tu, pe, False{}, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, True{}})) == M.Settled{} : M.Shelf},
        false_ne_true(Equal.sym(Bool, True{}, False{}, h)))
    case M.Thread{id, p, ti, c, a, tu, pe, True{}, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de}:
      Empty.absurd({M.Shelf.of(M.Thread.settled(True{}, at, M.Thread{id, p, ti, c, a, tu, pe, True{}, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de})) == M.Settled{} : M.Shelf},
        false_ne_true(Equal.sym(Bool, True{}, False{}, h)))

def Laws.merge_once(sh, branch, url, h):
  match sh:
    case M.Pinned{}:
      %Equal.sym(Bool, String.is_empty(url), False{}, h) : {Bool.and(Bool.not(String.is_empty(branch)), _) == False{} : Bool}
      and_false_r(Bool.not(String.is_empty(branch)))
    case M.Active{}:
      %Equal.sym(Bool, String.is_empty(url), False{}, h) : {Bool.and(Bool.not(String.is_empty(branch)), _) == False{} : Bool}
      and_false_r(Bool.not(String.is_empty(branch)))
    case M.Settled{}:
      {==}
    case M.Hidden{}:
      {==}
    case M.Snoozed{}:
      {==}

def Laws.merge_needs_branch(sh, merged):
  match sh:
    case M.Pinned{}:
      {==}
    case M.Active{}:
      {==}
    case M.Settled{}:
      {==}
    case M.Hidden{}:
      {==}
    case M.Snoozed{}:
      {==}

def Laws.gh_pick_saved(owner_in, saved, owner, active):
  {==}

def Laws.gh_pick_owner(saved, owner, active):
  {==}

def Laws.gh_pick_active(saved, owner, active):
  {==}

def Laws.gh_order_first(first, us):
  {==}

law gh_without_step:
  for b: Bool
  for +h: String
  for +t: List<&2, String>
  for +u: String
  for +e: {String.eq(h, u) == b : Bool}
  for ih: {GH.Gh.has(GH.Gh.without(t, u), u) == False{} : Bool}
  {GH.Gh.has(Bool.pick(List<&2, String>, String.eq(h, u), GH.Gh.without(t, u), h <> GH.Gh.without(t, u)), u) == False{} : Bool}

def gh_without_step(b, h, t, u, e, ih):
  match b:
    case True{}:
      %Equal.sym(Bool, String.eq(h, u), True{}, e) : {GH.Gh.has(Bool.pick(List<&2, String>, _, GH.Gh.without(t, u), h <> GH.Gh.without(t, u)), u) == False{} : Bool}
      ih
    case False{}:
      %Equal.sym(Bool, String.eq(h, u), False{}, e) : {GH.Gh.has(Bool.pick(List<&2, String>, _, GH.Gh.without(t, u), h <> GH.Gh.without(t, u)), u) == False{} : Bool}
      %Equal.sym(Bool, String.eq(h, u), False{}, e) : {Bool.or(_, GH.Gh.has(GH.Gh.without(t, u), u)) == False{} : Bool}
      ih

def Laws.gh_without_drops(us, u):
  match us:
    case Nil{}:
      {==}
    case +h <> +t:
      gh_without_step(String.eq(h, u), h, t, u, {==}, Laws.gh_without_drops(t, u))

def Laws.alert_needs_running(t):
  {==}

def Laws.alert_never_running(b):
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

def Laws.alert_not_on_stop(b):
  match b:
    case True{}:
      {==}
    case False{}:
      {==}

def Laws.alert_none_on_connect(ts, es):
  match ts:
    case Nil{}:
      {==}
    case M.Thread{id, p, ti, c, a, tu, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de} <> t:
      Laws.alert_none_on_connect(t, es)

def Laws.island_idle_empty(ts, es, h):
  match ts:
    case Nil{}:
      {==}
    case M.Thread{id, p, ti, c, a, M.Running{}, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de} <> t:
      Empty.absurd({Nt.Note.lines(M.Thread{id, p, ti, c, a, M.Running{}, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de} <> t, es) == [] : List<&2, J.Json>},
        false_ne_true(Equal.sym(Bool, True{}, False{}, h)))
    case M.Thread{id, p, ti, c, a, M.Idle{}, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de} <> t:
      Laws.island_idle_empty(t, es, h)
    case M.Thread{id, p, ti, c, a, M.Completed{}, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de} <> t:
      Laws.island_idle_empty(t, es, h)
    case M.Thread{id, p, ti, c, a, M.Interrupted{}, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de} <> t:
      Laws.island_idle_empty(t, es, h)
    case M.Thread{id, p, ti, c, a, M.Failed{}, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, de} <> t:
      Laws.island_idle_empty(t, es, h)

# a string compares equal to itself, handing both copies back
law string_cmp_refl:
  for +s: String
  {String.cmp(s, s) == ((s, s), EQ{}) : (String & String) & Cmp}

def string_cmp_refl(s):
  match s:
    case SNil{}:
      {==}
    case SCon{+h, +t}:
      match h:
        case Chr{+x}:
          %Equal.sym(Cmp, U32.cmp(x, x), EQ{}, u32_cmp_refl(x)) : {String.cmp.fin(t, t, ((Chr{x}, Chr{x}), _)) == ((SCon{Chr{x}, t}, SCon{Chr{x}, t}), EQ{}) : (String & String) & Cmp}
          %Equal.sym((String & String) & Cmp, String.cmp(t, t), ((t, t), EQ{}), string_cmp_refl(t)) : {String.cmp.rec(Chr{x}, Chr{x}, _) == ((SCon{Chr{x}, t}, SCon{Chr{x}, t}), EQ{}) : (String & String) & Cmp}
          {==}

def Laws.device_token_never_sent(tok, p, k, th, e, b, at):
  {==}

def Laws.device_drop_never_sent(tok, at):
  {==}

def Laws.device_blank_ignored(s, p, k, th, e, b, at):
  match s:
    case M.State{ps, ts, es, n, tk, sg, qu, ak, dv, nv}:
      {==}

def Laws.device_register_once(tok, h, p, k, th, e, b, at, p2, k2, th2, e2, b2, at2):
  match tok:
    case SNil{}:
      Empty.absurd({Map.size(&2, M.Device, M.State.devices(M.State.apply(M.State.apply(M.State.empty(), M.DeviceRegistered{SNil{}, p, k, th, e, b, at}), M.DeviceRegistered{SNil{}, p2, k2, th2, e2, b2, at2}))) == 1n : Nat},
        false_ne_true(Equal.sym(Bool, True{}, False{}, h)))
    case SCon{+c, +t}:
      %Equal.sym((String & String) & Cmp, String.cmp(SCon{c, t}, SCon{c, t}), ((SCon{c, t}, SCon{c, t}), EQ{}), string_cmp_refl(SCon{c, t})) : {Map.size(&2, M.Device, Map.set.fin.go(&2, M.Device, MLeaf{SCon{c, t}, M.Device{SCon{c, t}, p, k, th, e, b, at}}, SCon{c, t}, M.Device{SCon{c, t}, p2, k2, th2, e2, b2, at2}, _)) == 1n : Nat}
      {==}

# Order keys
# ----------

law cmpz_r_not_lt:
  for s: List<&2, Bool>
  {Cmp.is_lt(M.Key.cmpz_r(s)) == False{} : Bool}

def cmpz_r_not_lt(s):
  match s:
    case Nil{}:
      {==}
    case x <> r:
      match x:
        case False{}:
          cmpz_r_not_lt(r)
        case True{}:
          {==}

def Laws.key_after(s):
  match s:
    case Nil{}:
      {==}
    case x <> r:
      match x:
        case False{}:
          {==}
        case True{}:
          Laws.key_after(r)

law midz_above:
  for t: List<&2, Bool>
  for h: {Cmp.is_lt(M.Key.cmpz(t)) == True{} : Bool}
  {Cmp.is_lt(M.Key.cmpz(M.Key.midz(t))) == True{} : Bool}

def midz_above(t, h):
  match t:
    case Nil{}:
      Empty.absurd({Cmp.is_lt(M.Key.cmpz(M.Key.midz(Nil{}))) == True{} : Bool}, false_ne_true(h))
    case x <> r:
      match x:
        case False{}:
          midz_above(r, h)
        case True{}:
          {==}

law midz_below:
  for t: List<&2, Bool>
  for h: {Cmp.is_lt(M.Key.cmpz(t)) == True{} : Bool}
  {M.Key.lt(M.Key.midz(t), t) == True{} : Bool}

def midz_below(t, h):
  match t:
    case Nil{}:
      Empty.absurd({M.Key.lt(M.Key.midz(Nil{}), Nil{}) == True{} : Bool}, false_ne_true(h))
    case x <> r:
      match x:
        case False{}:
          midz_below(r, h)
        case True{}:
          {==}

def Laws.key_mid_above(a, b, h):
  match a:
    case Nil{}:
      midz_above(b, h)
    case x <> s:
      match x b:
        case False{} Nil{}:
          Empty.absurd({M.Key.lt(False{} <> s, M.Key.mid(False{} <> s, Nil{})) == True{} : Bool},
            false_ne_true(Equal.trans(Bool, False{}, Cmp.is_lt(M.Key.cmpz_r(s)), True{}, Equal.sym(Bool, Cmp.is_lt(M.Key.cmpz_r(s)), False{}, cmpz_r_not_lt(s)), h)))
        case True{} Nil{}:
          Empty.absurd({M.Key.lt(True{} <> s, M.Key.mid(True{} <> s, Nil{})) == True{} : Bool}, false_ne_true(h))
        case False{} y <> t:
          match y:
            case False{}:
              Laws.key_mid_above(s, t, h)
            case True{}:
              Laws.key_after(s)
        case True{} y <> t:
          match y:
            case False{}:
              Empty.absurd({M.Key.lt(True{} <> s, M.Key.mid(True{} <> s, False{} <> t)) == True{} : Bool}, false_ne_true(h))
            case True{}:
              Laws.key_mid_above(s, t, h)

def Laws.key_mid_below(a, b, h):
  match a:
    case Nil{}:
      midz_below(b, h)
    case x <> s:
      match x b:
        case False{} Nil{}:
          Empty.absurd({M.Key.lt(M.Key.mid(False{} <> s, Nil{}), Nil{}) == True{} : Bool},
            false_ne_true(Equal.trans(Bool, False{}, Cmp.is_lt(M.Key.cmpz_r(s)), True{}, Equal.sym(Bool, Cmp.is_lt(M.Key.cmpz_r(s)), False{}, cmpz_r_not_lt(s)), h)))
        case True{} Nil{}:
          Empty.absurd({M.Key.lt(M.Key.mid(True{} <> s, Nil{}), Nil{}) == True{} : Bool}, false_ne_true(h))
        case False{} y <> t:
          match y:
            case False{}:
              Laws.key_mid_below(s, t, h)
            case True{}:
              {==}
        case True{} y <> t:
          match y:
            case False{}:
              Empty.absurd({M.Key.lt(M.Key.mid(True{} <> s, False{} <> t), False{} <> t) == True{} : Bool}, false_ne_true(h))
            case True{}:
              Laws.key_mid_below(s, t, h)

# Sidebar status
# --------------

def Laws.status_approval_first(i, t, q):
  {==}

def Laws.status_input_before_work(t, q):
  {==}

def Laws.status_working_before_queued(q):
  {==}

def Laws.status_failed_before_queued(q):
  {==}

def Laws.status_approval_top(a, i, t, q):
  match a:
    case True{}:
      {==}
    case False{}:
      match i:
        case True{}:
          {==}
        case False{}:
          match t q:
            case M.Running{} _:
              {==}
            case M.Failed{} _:
              {==}
            case M.Idle{} True{}:
              {==}
            case M.Idle{} False{}:
              {==}
            case M.Completed{} True{}:
              {==}
            case M.Completed{} False{}:
              {==}
            case M.Interrupted{} True{}:
              {==}
            case M.Interrupted{} False{}:
              {==}

def Laws.fuzzy_empty_matches(s):
  match s:
    case SNil{}:
      {==}
    case SCon{Chr{c}, t}:
      {==}

def Laws.caret_shows_when_moved():
  {==}

def Laws.tailnet_no_owner_no_trust(login):
  {==}


# Drawing lemmas
# --------------

def Cmp.eqd(c: Cmp) -> Type:
  match c:
    case LT{}:
      Unit
    case EQ{}:
      Empty
    case GT{}:
      Unit

law lt_ne_eq:
  for e: {LT{} == EQ{} : Cmp}
  Empty

def lt_ne_eq(e):
  %e : Cmp.eqd(_)
  Unit{}

law gt_ne_eq:
  for e: {GT{} == EQ{} : Cmp}
  Empty

def gt_ne_eq(e):
  %e : Cmp.eqd(_)
  Unit{}

law and_l:
  for a: Bool
  for -b: Bool
  for h: {Bool.and(a, b) == True{} : Bool}
  {a == True{} : Bool}

def and_l(a, b, h):
  match a:
    case False{}:
      Empty.absurd({False{} == True{} : Bool}, false_ne_true(h))
    case True{}:
      {==}

law and_r:
  for a: Bool
  for -b: Bool
  for h: {Bool.and(a, b) == True{} : Bool}
  {b == True{} : Bool}

def and_r(a, b, h):
  match a:
    case False{}:
      Empty.absurd({b == True{} : Bool}, false_ne_true(h))
    case True{}:
      h

law cmp_is_eq_sound:
  for c: Cmp
  for h: {Cmp.is_eq(c) == True{} : Bool}
  {c == EQ{} : Cmp}

def cmp_is_eq_sound(c, h):
  match c:
    case LT{}:
      Empty.absurd({LT{} == EQ{} : Cmp}, false_ne_true(h))
    case EQ{}:
      {==}
    case GT{}:
      Empty.absurd({GT{} == EQ{} : Cmp}, false_ne_true(h))

law bool_cmp_sound:
  for a: Bool
  for b: Bool
  for h: {Bool.cmp(a, b) == EQ{} : Cmp}
  {a == b : Bool}

def bool_cmp_sound(a, b, h):
  match a b:
    case False{} False{}:
      {==}
    case False{} True{}:
      Empty.absurd({False{} == True{} : Bool}, lt_ne_eq(h))
    case True{} False{}:
      Empty.absurd({True{} == False{} : Bool}, gt_ne_eq(h))
    case True{} True{}:
      {==}

law word_fin_t:
  for -ab: Bool
  for -bb: Bool
  for t: Cmp
  for h: {Word.cmp.fin(ab, bb, t) == EQ{} : Cmp}
  {t == EQ{} : Cmp}

def word_fin_t(ab, bb, t, h):
  match t:
    case LT{}:
      Empty.absurd({LT{} == EQ{} : Cmp}, lt_ne_eq(h))
    case EQ{}:
      {==}
    case GT{}:
      Empty.absurd({GT{} == EQ{} : Cmp}, gt_ne_eq(h))

law word_fin_b:
  for -ab: Bool
  for -bb: Bool
  for t: Cmp
  for h: {Word.cmp.fin(ab, bb, t) == EQ{} : Cmp}
  {Bool.cmp(ab, bb) == EQ{} : Cmp}

def word_fin_b(ab, bb, t, h):
  match t:
    case LT{}:
      Empty.absurd({Bool.cmp(ab, bb) == EQ{} : Cmp}, lt_ne_eq(h))
    case EQ{}:
      h
    case GT{}:
      Empty.absurd({Bool.cmp(ab, bb) == EQ{} : Cmp}, gt_ne_eq(h))

law word_cmp_sound:
  for n: Nat
  for a: Word(n)
  for b: Word(n)
  for +h: {Word.cmp(n, a, b) == EQ{} : Cmp}
  {a == b : Word(n)}

def word_cmp_sound(n, a, b, h):
  match n:
    case 0n:
      match a b:
        case WNil{} WNil{}:
          {==}
    case 1n+p0:
      match a b:
        case WCon{+ab, +at} WCon{+bb, +bt}:
          +p = p0
          e0 = bool_cmp_sound(ab, bb, word_fin_b(ab, bb, Word.cmp(p, at, bt), h))
          e1 = word_cmp_sound(p, at, bt, word_fin_t(ab, bb, Word.cmp(p, at, bt), h))
          %e0 : {WCon{ab, at} == WCon{_, bt} : Word(1n+p)}
          %e1 : {WCon{ab, at} == WCon{ab, _} : Word(1n+p)}
          {==}

law u32_eq_sound:
  for a: U32
  for b: U32
  for h: {U32.is_eq(a, b) == True{} : Bool}
  {a == b : U32}

def u32_eq_sound(a, b, h):
  match a b:
    case U32{+x} U32{+y}:
      e = word_cmp_sound(32n, x, y, cmp_is_eq_sound(Word.cmp(32n, x, y), h))
      %e : {U32{x} == U32{_} : U32}
      {==}

law f32_eq_sound:
  for a: F32
  for b: F32
  for h: {T.Eq.f32(a, b) == True{} : Bool}
  {a == b : F32}

def f32_eq_sound(a, b, h):
  match a b:
    case F32{+x} F32{+y}:
      e = word_cmp_sound(32n, x, y, cmp_is_eq_sound(Word.cmp(32n, x, y), h))
      %e : {F32{x} == F32{_} : F32}
      {==}

law f32_eq_refl:
  for +a: F32
  {T.Eq.f32(a, a) == True{} : Bool}

def f32_eq_refl(a):
  match a:
    case F32{+x}:
      u32_eq_refl(U32{x})

law nat_eq_sound:
  for a: Nat
  for b: Nat
  for h: {Nat.is_eq(a, b) == True{} : Bool}
  {a == b : Nat}

def nat_eq_sound(a, b, h):
  match a b:
    case 0n 0n:
      {==}
    case 0n 1n+q:
      Empty.absurd({0n == 1n+q : Nat}, false_ne_true(h))
    case 1n+p 0n:
      Empty.absurd({1n+p == 0n : Nat}, false_ne_true(h))
    case 1n+p 1n+q:
      e = nat_eq_sound(p, q, h)
      %e : {1n+p == 1n+_ : Nat}
      {==}

law nat_eq_refl:
  for +a: Nat
  {Nat.is_eq(a, a) == True{} : Bool}

def nat_eq_refl(a):
  %Equal.sym(Cmp, Nat.cmp(a, a), EQ{}, nat_cmp_refl(a)) : {Cmp.is_eq(_) == True{} : Bool}
  {==}

law bool_eq_sound:
  for a: Bool
  for b: Bool
  for h: {Q.Eq.bool(a, b) == True{} : Bool}
  {a == b : Bool}

def bool_eq_sound(a, b, h):
  match a b:
    case False{} False{}:
      {==}
    case False{} True{}:
      Empty.absurd({False{} == True{} : Bool}, false_ne_true(h))
    case True{} False{}:
      Empty.absurd({True{} == False{} : Bool}, false_ne_true(h))
    case True{} True{}:
      {==}

law bool_eq_refl:
  for +a: Bool
  {Q.Eq.bool(a, a) == True{} : Bool}

def bool_eq_refl(a):
  match a:
    case False{}:
      {==}
    case True{}:
      {==}

law eq_edge_sound:
  for a: R.Edge
  for b: R.Edge
  for +h: {T.Eq.edge(a, b) == True{} : Bool}
  {a == b : R.Edge}

def eq_edge_sound(a, b, h):
  match a b:
    case R.Edge{+a0, +a1, +a2, +a3} R.Edge{+b0, +b1, +b2, +b3}:
      +hl0 = and_l(T.Eq.f32(a0, b0), Bool.and(T.Eq.f32(a1, b1), Bool.and(T.Eq.f32(a2, b2), T.Eq.f32(a3, b3))), h)
      +hr0 = and_r(T.Eq.f32(a0, b0), Bool.and(T.Eq.f32(a1, b1), Bool.and(T.Eq.f32(a2, b2), T.Eq.f32(a3, b3))), h)
      e0 = f32_eq_sound(a0, b0, hl0)
      +hl1 = and_l(T.Eq.f32(a1, b1), Bool.and(T.Eq.f32(a2, b2), T.Eq.f32(a3, b3)), hr0)
      +hr1 = and_r(T.Eq.f32(a1, b1), Bool.and(T.Eq.f32(a2, b2), T.Eq.f32(a3, b3)), hr0)
      e1 = f32_eq_sound(a1, b1, hl1)
      +hl2 = and_l(T.Eq.f32(a2, b2), T.Eq.f32(a3, b3), hr1)
      +hr2 = and_r(T.Eq.f32(a2, b2), T.Eq.f32(a3, b3), hr1)
      e2 = f32_eq_sound(a2, b2, hl2)
      e3 = f32_eq_sound(a3, b3, hr2)
      %e0 : {R.Edge{a0, a1, a2, a3} == R.Edge{_, b1, b2, b3} : R.Edge}
      %e1 : {R.Edge{a0, a1, a2, a3} == R.Edge{a0, _, b2, b3} : R.Edge}
      %e2 : {R.Edge{a0, a1, a2, a3} == R.Edge{a0, a1, _, b3} : R.Edge}
      %e3 : {R.Edge{a0, a1, a2, a3} == R.Edge{a0, a1, a2, _} : R.Edge}
      {==}

law eq_edge_refl:
  for +a: R.Edge
  {T.Eq.edge(a, a) == True{} : Bool}

def eq_edge_refl(a):
  match a:
    case R.Edge{+a0, +a1, +a2, +a3}:
      %Equal.sym(Bool, T.Eq.f32(a0, a0), True{}, f32_eq_refl(a0)) : {Bool.and(_, Bool.and(T.Eq.f32(a1, a1), Bool.and(T.Eq.f32(a2, a2), T.Eq.f32(a3, a3)))) == True{} : Bool}
      %Equal.sym(Bool, T.Eq.f32(a1, a1), True{}, f32_eq_refl(a1)) : {Bool.and(True{}, Bool.and(_, Bool.and(T.Eq.f32(a2, a2), T.Eq.f32(a3, a3)))) == True{} : Bool}
      %Equal.sym(Bool, T.Eq.f32(a2, a2), True{}, f32_eq_refl(a2)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(_, T.Eq.f32(a3, a3)))) == True{} : Bool}
      %Equal.sym(Bool, T.Eq.f32(a3, a3), True{}, f32_eq_refl(a3)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, _))) == True{} : Bool}
      {==}

law eq_edges_sound:
  for a: List<&2, R.Edge>
  for b: List<&2, R.Edge>
  for +h: {T.Eq.edges(a, b) == True{} : Bool}
  {a == b : List<&2, R.Edge>}

def eq_edges_sound(a, b, h):
  match a b:
    case Nil{} Nil{}:
      {==}
    case Nil{} +y <> +yt:
      Empty.absurd({Nil{} == y <> yt : List<&2, R.Edge>}, false_ne_true(h))
    case +x <> +xt Nil{}:
      Empty.absurd({x <> xt == Nil{} : List<&2, R.Edge>}, false_ne_true(h))
    case +x <> +xt +y <> +yt:
      e0 = eq_edge_sound(x, y, and_l(T.Eq.edge(x, y), T.Eq.edges(xt, yt), h))
      e1 = eq_edges_sound(xt, yt, and_r(T.Eq.edge(x, y), T.Eq.edges(xt, yt), h))
      %e0 : {x <> xt == _ <> yt : List<&2, R.Edge>}
      %e1 : {x <> xt == x <> _ : List<&2, R.Edge>}
      {==}

law eq_edges_refl:
  for +a: List<&2, R.Edge>
  {T.Eq.edges(a, a) == True{} : Bool}

def eq_edges_refl(a):
  match a:
    case Nil{}:
      {==}
    case +x <> +xt:
      %Equal.sym(Bool, T.Eq.edge(x, x), True{}, eq_edge_refl(x)) : {Bool.and(_, T.Eq.edges(xt, xt)) == True{} : Bool}
      eq_edges_refl(xt)

law eq_mask_sound:
  for a: R.Mask
  for b: R.Mask
  for +h: {T.Eq.mask(a, b) == True{} : Bool}
  {a == b : R.Mask}

def eq_mask_sound(a, b, h):
  match a b:
    case R.MWord{+a0} R.MWord{+b0}:
      e0 = u32_eq_sound(a0, b0, h)
      %e0 : {R.MWord{a0} == R.MWord{_} : R.Mask}
      {==}
    case R.MWord{+a0} R.MPair{+b0, +b1}:
      Empty.absurd({R.MWord{a0} == R.MPair{b0, b1} : R.Mask}, false_ne_true(h))
    case R.MPair{+a0, +a1} R.MWord{+b0}:
      Empty.absurd({R.MPair{a0, a1} == R.MWord{b0} : R.Mask}, false_ne_true(h))
    case R.MPair{+a0, +a1} R.MPair{+b0, +b1}:
      +hl0 = and_l(T.Eq.mask(a0, b0), T.Eq.mask(a1, b1), h)
      +hr0 = and_r(T.Eq.mask(a0, b0), T.Eq.mask(a1, b1), h)
      e0 = eq_mask_sound(a0, b0, hl0)
      e1 = eq_mask_sound(a1, b1, hr0)
      %e0 : {R.MPair{a0, a1} == R.MPair{_, b1} : R.Mask}
      %e1 : {R.MPair{a0, a1} == R.MPair{a0, _} : R.Mask}
      {==}

law eq_mask_refl:
  for +a: R.Mask
  {T.Eq.mask(a, a) == True{} : Bool}

def eq_mask_refl(a):
  match a:
    case R.MWord{+a0}:
      %Equal.sym(Bool, U32.is_eq(a0, a0), True{}, u32_eq_refl(a0)) : {_ == True{} : Bool}
      {==}
    case R.MPair{+a0, +a1}:
      %Equal.sym(Bool, T.Eq.mask(a0, a0), True{}, eq_mask_refl(a0)) : {Bool.and(_, T.Eq.mask(a1, a1)) == True{} : Bool}
      %Equal.sym(Bool, T.Eq.mask(a1, a1), True{}, eq_mask_refl(a1)) : {Bool.and(True{}, _) == True{} : Bool}
      {==}

law eq_glyph_sound:
  for a: F.Glyph
  for b: F.Glyph
  for +h: {T.Eq.glyph(a, b) == True{} : Bool}
  {a == b : F.Glyph}

def eq_glyph_sound(a, b, h):
  match a b:
    case F.Glyph{+a0, +a1, +a2, +a3} F.Glyph{+b0, +b1, +b2, +b3}:
      +hl0 = and_l(U32.is_eq(a0, b0), Bool.and(U32.is_eq(a1, b1), Bool.and(U32.is_eq(a2, b2), U32.is_eq(a3, b3))), h)
      +hr0 = and_r(U32.is_eq(a0, b0), Bool.and(U32.is_eq(a1, b1), Bool.and(U32.is_eq(a2, b2), U32.is_eq(a3, b3))), h)
      e0 = u32_eq_sound(a0, b0, hl0)
      +hl1 = and_l(U32.is_eq(a1, b1), Bool.and(U32.is_eq(a2, b2), U32.is_eq(a3, b3)), hr0)
      +hr1 = and_r(U32.is_eq(a1, b1), Bool.and(U32.is_eq(a2, b2), U32.is_eq(a3, b3)), hr0)
      e1 = u32_eq_sound(a1, b1, hl1)
      +hl2 = and_l(U32.is_eq(a2, b2), U32.is_eq(a3, b3), hr1)
      +hr2 = and_r(U32.is_eq(a2, b2), U32.is_eq(a3, b3), hr1)
      e2 = u32_eq_sound(a2, b2, hl2)
      e3 = u32_eq_sound(a3, b3, hr2)
      %e0 : {F.Glyph{a0, a1, a2, a3} == F.Glyph{_, b1, b2, b3} : F.Glyph}
      %e1 : {F.Glyph{a0, a1, a2, a3} == F.Glyph{a0, _, b2, b3} : F.Glyph}
      %e2 : {F.Glyph{a0, a1, a2, a3} == F.Glyph{a0, a1, _, b3} : F.Glyph}
      %e3 : {F.Glyph{a0, a1, a2, a3} == F.Glyph{a0, a1, a2, _} : F.Glyph}
      {==}

law eq_glyph_refl:
  for +a: F.Glyph
  {T.Eq.glyph(a, a) == True{} : Bool}

def eq_glyph_refl(a):
  match a:
    case F.Glyph{+a0, +a1, +a2, +a3}:
      %Equal.sym(Bool, U32.is_eq(a0, a0), True{}, u32_eq_refl(a0)) : {Bool.and(_, Bool.and(U32.is_eq(a1, a1), Bool.and(U32.is_eq(a2, a2), U32.is_eq(a3, a3)))) == True{} : Bool}
      %Equal.sym(Bool, U32.is_eq(a1, a1), True{}, u32_eq_refl(a1)) : {Bool.and(True{}, Bool.and(_, Bool.and(U32.is_eq(a2, a2), U32.is_eq(a3, a3)))) == True{} : Bool}
      %Equal.sym(Bool, U32.is_eq(a2, a2), True{}, u32_eq_refl(a2)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(_, U32.is_eq(a3, a3)))) == True{} : Bool}
      %Equal.sym(Bool, U32.is_eq(a3, a3), True{}, u32_eq_refl(a3)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, _))) == True{} : Bool}
      {==}

law eq_shape_sound:
  for a: R.Shape
  for b: R.Shape
  for +h: {T.Eq.shape(a, b) == True{} : Bool}
  {a == b : R.Shape}

def eq_shape_sound(a, b, h):
  match a b:
    case R.SRect{} R.SRect{}:
      {==}
    case R.SRect{} R.SPoly{+b0, +b1}:
      Empty.absurd({R.SRect{} == R.SPoly{b0, b1} : R.Shape}, false_ne_true(h))
    case R.SRect{} R.SGlyph{+b0, +b1, +b2}:
      Empty.absurd({R.SRect{} == R.SGlyph{b0, b1, b2} : R.Shape}, false_ne_true(h))
    case R.SRect{} R.SSeg{+b0, +b1, +b2, +b3, +b4}:
      Empty.absurd({R.SRect{} == R.SSeg{b0, b1, b2, b3, b4} : R.Shape}, false_ne_true(h))
    case R.SRect{} R.SDisc{+b0, +b1, +b2}:
      Empty.absurd({R.SRect{} == R.SDisc{b0, b1, b2} : R.Shape}, false_ne_true(h))
    case R.SRect{} R.STri{+b0, +b1, +b2, +b3, +b4, +b5}:
      Empty.absurd({R.SRect{} == R.STri{b0, b1, b2, b3, b4, b5} : R.Shape}, false_ne_true(h))
    case R.SRect{} R.SMask{+b0, +b1, +b2, +b3, +b4}:
      Empty.absurd({R.SRect{} == R.SMask{b0, b1, b2, b3, b4} : R.Shape}, false_ne_true(h))
    case R.SPoly{+a0, +a1} R.SRect{}:
      Empty.absurd({R.SPoly{a0, a1} == R.SRect{} : R.Shape}, false_ne_true(h))
    case R.SPoly{+a0, +a1} R.SPoly{+b0, +b1}:
      +hl0 = and_l(Q.Eq.bool(a0, b0), T.Eq.edges(a1, b1), h)
      +hr0 = and_r(Q.Eq.bool(a0, b0), T.Eq.edges(a1, b1), h)
      e0 = bool_eq_sound(a0, b0, hl0)
      e1 = eq_edges_sound(a1, b1, hr0)
      %e0 : {R.SPoly{a0, a1} == R.SPoly{_, b1} : R.Shape}
      %e1 : {R.SPoly{a0, a1} == R.SPoly{a0, _} : R.Shape}
      {==}
    case R.SPoly{+a0, +a1} R.SGlyph{+b0, +b1, +b2}:
      Empty.absurd({R.SPoly{a0, a1} == R.SGlyph{b0, b1, b2} : R.Shape}, false_ne_true(h))
    case R.SPoly{+a0, +a1} R.SSeg{+b0, +b1, +b2, +b3, +b4}:
      Empty.absurd({R.SPoly{a0, a1} == R.SSeg{b0, b1, b2, b3, b4} : R.Shape}, false_ne_true(h))
    case R.SPoly{+a0, +a1} R.SDisc{+b0, +b1, +b2}:
      Empty.absurd({R.SPoly{a0, a1} == R.SDisc{b0, b1, b2} : R.Shape}, false_ne_true(h))
    case R.SPoly{+a0, +a1} R.STri{+b0, +b1, +b2, +b3, +b4, +b5}:
      Empty.absurd({R.SPoly{a0, a1} == R.STri{b0, b1, b2, b3, b4, b5} : R.Shape}, false_ne_true(h))
    case R.SPoly{+a0, +a1} R.SMask{+b0, +b1, +b2, +b3, +b4}:
      Empty.absurd({R.SPoly{a0, a1} == R.SMask{b0, b1, b2, b3, b4} : R.Shape}, false_ne_true(h))
    case R.SGlyph{+a0, +a1, +a2} R.SRect{}:
      Empty.absurd({R.SGlyph{a0, a1, a2} == R.SRect{} : R.Shape}, false_ne_true(h))
    case R.SGlyph{+a0, +a1, +a2} R.SPoly{+b0, +b1}:
      Empty.absurd({R.SGlyph{a0, a1, a2} == R.SPoly{b0, b1} : R.Shape}, false_ne_true(h))
    case R.SGlyph{+a0, +a1, +a2} R.SGlyph{+b0, +b1, +b2}:
      +hl0 = and_l(U32.is_eq(a0, b0), Bool.and(U32.is_eq(a1, b1), T.Eq.glyph(a2, b2)), h)
      +hr0 = and_r(U32.is_eq(a0, b0), Bool.and(U32.is_eq(a1, b1), T.Eq.glyph(a2, b2)), h)
      e0 = u32_eq_sound(a0, b0, hl0)
      +hl1 = and_l(U32.is_eq(a1, b1), T.Eq.glyph(a2, b2), hr0)
      +hr1 = and_r(U32.is_eq(a1, b1), T.Eq.glyph(a2, b2), hr0)
      e1 = u32_eq_sound(a1, b1, hl1)
      e2 = eq_glyph_sound(a2, b2, hr1)
      %e0 : {R.SGlyph{a0, a1, a2} == R.SGlyph{_, b1, b2} : R.Shape}
      %e1 : {R.SGlyph{a0, a1, a2} == R.SGlyph{a0, _, b2} : R.Shape}
      %e2 : {R.SGlyph{a0, a1, a2} == R.SGlyph{a0, a1, _} : R.Shape}
      {==}
    case R.SGlyph{+a0, +a1, +a2} R.SSeg{+b0, +b1, +b2, +b3, +b4}:
      Empty.absurd({R.SGlyph{a0, a1, a2} == R.SSeg{b0, b1, b2, b3, b4} : R.Shape}, false_ne_true(h))
    case R.SGlyph{+a0, +a1, +a2} R.SDisc{+b0, +b1, +b2}:
      Empty.absurd({R.SGlyph{a0, a1, a2} == R.SDisc{b0, b1, b2} : R.Shape}, false_ne_true(h))
    case R.SGlyph{+a0, +a1, +a2} R.STri{+b0, +b1, +b2, +b3, +b4, +b5}:
      Empty.absurd({R.SGlyph{a0, a1, a2} == R.STri{b0, b1, b2, b3, b4, b5} : R.Shape}, false_ne_true(h))
    case R.SGlyph{+a0, +a1, +a2} R.SMask{+b0, +b1, +b2, +b3, +b4}:
      Empty.absurd({R.SGlyph{a0, a1, a2} == R.SMask{b0, b1, b2, b3, b4} : R.Shape}, false_ne_true(h))
    case R.SSeg{+a0, +a1, +a2, +a3, +a4} R.SRect{}:
      Empty.absurd({R.SSeg{a0, a1, a2, a3, a4} == R.SRect{} : R.Shape}, false_ne_true(h))
    case R.SSeg{+a0, +a1, +a2, +a3, +a4} R.SPoly{+b0, +b1}:
      Empty.absurd({R.SSeg{a0, a1, a2, a3, a4} == R.SPoly{b0, b1} : R.Shape}, false_ne_true(h))
    case R.SSeg{+a0, +a1, +a2, +a3, +a4} R.SGlyph{+b0, +b1, +b2}:
      Empty.absurd({R.SSeg{a0, a1, a2, a3, a4} == R.SGlyph{b0, b1, b2} : R.Shape}, false_ne_true(h))
    case R.SSeg{+a0, +a1, +a2, +a3, +a4} R.SSeg{+b0, +b1, +b2, +b3, +b4}:
      +hl0 = and_l(T.Eq.f32(a0, b0), Bool.and(T.Eq.f32(a1, b1), Bool.and(T.Eq.f32(a2, b2), Bool.and(T.Eq.f32(a3, b3), T.Eq.f32(a4, b4)))), h)
      +hr0 = and_r(T.Eq.f32(a0, b0), Bool.and(T.Eq.f32(a1, b1), Bool.and(T.Eq.f32(a2, b2), Bool.and(T.Eq.f32(a3, b3), T.Eq.f32(a4, b4)))), h)
      e0 = f32_eq_sound(a0, b0, hl0)
      +hl1 = and_l(T.Eq.f32(a1, b1), Bool.and(T.Eq.f32(a2, b2), Bool.and(T.Eq.f32(a3, b3), T.Eq.f32(a4, b4))), hr0)
      +hr1 = and_r(T.Eq.f32(a1, b1), Bool.and(T.Eq.f32(a2, b2), Bool.and(T.Eq.f32(a3, b3), T.Eq.f32(a4, b4))), hr0)
      e1 = f32_eq_sound(a1, b1, hl1)
      +hl2 = and_l(T.Eq.f32(a2, b2), Bool.and(T.Eq.f32(a3, b3), T.Eq.f32(a4, b4)), hr1)
      +hr2 = and_r(T.Eq.f32(a2, b2), Bool.and(T.Eq.f32(a3, b3), T.Eq.f32(a4, b4)), hr1)
      e2 = f32_eq_sound(a2, b2, hl2)
      +hl3 = and_l(T.Eq.f32(a3, b3), T.Eq.f32(a4, b4), hr2)
      +hr3 = and_r(T.Eq.f32(a3, b3), T.Eq.f32(a4, b4), hr2)
      e3 = f32_eq_sound(a3, b3, hl3)
      e4 = f32_eq_sound(a4, b4, hr3)
      %e0 : {R.SSeg{a0, a1, a2, a3, a4} == R.SSeg{_, b1, b2, b3, b4} : R.Shape}
      %e1 : {R.SSeg{a0, a1, a2, a3, a4} == R.SSeg{a0, _, b2, b3, b4} : R.Shape}
      %e2 : {R.SSeg{a0, a1, a2, a3, a4} == R.SSeg{a0, a1, _, b3, b4} : R.Shape}
      %e3 : {R.SSeg{a0, a1, a2, a3, a4} == R.SSeg{a0, a1, a2, _, b4} : R.Shape}
      %e4 : {R.SSeg{a0, a1, a2, a3, a4} == R.SSeg{a0, a1, a2, a3, _} : R.Shape}
      {==}
    case R.SSeg{+a0, +a1, +a2, +a3, +a4} R.SDisc{+b0, +b1, +b2}:
      Empty.absurd({R.SSeg{a0, a1, a2, a3, a4} == R.SDisc{b0, b1, b2} : R.Shape}, false_ne_true(h))
    case R.SSeg{+a0, +a1, +a2, +a3, +a4} R.STri{+b0, +b1, +b2, +b3, +b4, +b5}:
      Empty.absurd({R.SSeg{a0, a1, a2, a3, a4} == R.STri{b0, b1, b2, b3, b4, b5} : R.Shape}, false_ne_true(h))
    case R.SSeg{+a0, +a1, +a2, +a3, +a4} R.SMask{+b0, +b1, +b2, +b3, +b4}:
      Empty.absurd({R.SSeg{a0, a1, a2, a3, a4} == R.SMask{b0, b1, b2, b3, b4} : R.Shape}, false_ne_true(h))
    case R.SDisc{+a0, +a1, +a2} R.SRect{}:
      Empty.absurd({R.SDisc{a0, a1, a2} == R.SRect{} : R.Shape}, false_ne_true(h))
    case R.SDisc{+a0, +a1, +a2} R.SPoly{+b0, +b1}:
      Empty.absurd({R.SDisc{a0, a1, a2} == R.SPoly{b0, b1} : R.Shape}, false_ne_true(h))
    case R.SDisc{+a0, +a1, +a2} R.SGlyph{+b0, +b1, +b2}:
      Empty.absurd({R.SDisc{a0, a1, a2} == R.SGlyph{b0, b1, b2} : R.Shape}, false_ne_true(h))
    case R.SDisc{+a0, +a1, +a2} R.SSeg{+b0, +b1, +b2, +b3, +b4}:
      Empty.absurd({R.SDisc{a0, a1, a2} == R.SSeg{b0, b1, b2, b3, b4} : R.Shape}, false_ne_true(h))
    case R.SDisc{+a0, +a1, +a2} R.SDisc{+b0, +b1, +b2}:
      +hl0 = and_l(T.Eq.f32(a0, b0), Bool.and(T.Eq.f32(a1, b1), T.Eq.f32(a2, b2)), h)
      +hr0 = and_r(T.Eq.f32(a0, b0), Bool.and(T.Eq.f32(a1, b1), T.Eq.f32(a2, b2)), h)
      e0 = f32_eq_sound(a0, b0, hl0)
      +hl1 = and_l(T.Eq.f32(a1, b1), T.Eq.f32(a2, b2), hr0)
      +hr1 = and_r(T.Eq.f32(a1, b1), T.Eq.f32(a2, b2), hr0)
      e1 = f32_eq_sound(a1, b1, hl1)
      e2 = f32_eq_sound(a2, b2, hr1)
      %e0 : {R.SDisc{a0, a1, a2} == R.SDisc{_, b1, b2} : R.Shape}
      %e1 : {R.SDisc{a0, a1, a2} == R.SDisc{a0, _, b2} : R.Shape}
      %e2 : {R.SDisc{a0, a1, a2} == R.SDisc{a0, a1, _} : R.Shape}
      {==}
    case R.SDisc{+a0, +a1, +a2} R.STri{+b0, +b1, +b2, +b3, +b4, +b5}:
      Empty.absurd({R.SDisc{a0, a1, a2} == R.STri{b0, b1, b2, b3, b4, b5} : R.Shape}, false_ne_true(h))
    case R.SDisc{+a0, +a1, +a2} R.SMask{+b0, +b1, +b2, +b3, +b4}:
      Empty.absurd({R.SDisc{a0, a1, a2} == R.SMask{b0, b1, b2, b3, b4} : R.Shape}, false_ne_true(h))
    case R.STri{+a0, +a1, +a2, +a3, +a4, +a5} R.SRect{}:
      Empty.absurd({R.STri{a0, a1, a2, a3, a4, a5} == R.SRect{} : R.Shape}, false_ne_true(h))
    case R.STri{+a0, +a1, +a2, +a3, +a4, +a5} R.SPoly{+b0, +b1}:
      Empty.absurd({R.STri{a0, a1, a2, a3, a4, a5} == R.SPoly{b0, b1} : R.Shape}, false_ne_true(h))
    case R.STri{+a0, +a1, +a2, +a3, +a4, +a5} R.SGlyph{+b0, +b1, +b2}:
      Empty.absurd({R.STri{a0, a1, a2, a3, a4, a5} == R.SGlyph{b0, b1, b2} : R.Shape}, false_ne_true(h))
    case R.STri{+a0, +a1, +a2, +a3, +a4, +a5} R.SSeg{+b0, +b1, +b2, +b3, +b4}:
      Empty.absurd({R.STri{a0, a1, a2, a3, a4, a5} == R.SSeg{b0, b1, b2, b3, b4} : R.Shape}, false_ne_true(h))
    case R.STri{+a0, +a1, +a2, +a3, +a4, +a5} R.SDisc{+b0, +b1, +b2}:
      Empty.absurd({R.STri{a0, a1, a2, a3, a4, a5} == R.SDisc{b0, b1, b2} : R.Shape}, false_ne_true(h))
    case R.STri{+a0, +a1, +a2, +a3, +a4, +a5} R.STri{+b0, +b1, +b2, +b3, +b4, +b5}:
      +hl0 = and_l(T.Eq.f32(a0, b0), Bool.and(T.Eq.f32(a1, b1), Bool.and(T.Eq.f32(a2, b2), Bool.and(T.Eq.f32(a3, b3), Bool.and(T.Eq.f32(a4, b4), T.Eq.f32(a5, b5))))), h)
      +hr0 = and_r(T.Eq.f32(a0, b0), Bool.and(T.Eq.f32(a1, b1), Bool.and(T.Eq.f32(a2, b2), Bool.and(T.Eq.f32(a3, b3), Bool.and(T.Eq.f32(a4, b4), T.Eq.f32(a5, b5))))), h)
      e0 = f32_eq_sound(a0, b0, hl0)
      +hl1 = and_l(T.Eq.f32(a1, b1), Bool.and(T.Eq.f32(a2, b2), Bool.and(T.Eq.f32(a3, b3), Bool.and(T.Eq.f32(a4, b4), T.Eq.f32(a5, b5)))), hr0)
      +hr1 = and_r(T.Eq.f32(a1, b1), Bool.and(T.Eq.f32(a2, b2), Bool.and(T.Eq.f32(a3, b3), Bool.and(T.Eq.f32(a4, b4), T.Eq.f32(a5, b5)))), hr0)
      e1 = f32_eq_sound(a1, b1, hl1)
      +hl2 = and_l(T.Eq.f32(a2, b2), Bool.and(T.Eq.f32(a3, b3), Bool.and(T.Eq.f32(a4, b4), T.Eq.f32(a5, b5))), hr1)
      +hr2 = and_r(T.Eq.f32(a2, b2), Bool.and(T.Eq.f32(a3, b3), Bool.and(T.Eq.f32(a4, b4), T.Eq.f32(a5, b5))), hr1)
      e2 = f32_eq_sound(a2, b2, hl2)
      +hl3 = and_l(T.Eq.f32(a3, b3), Bool.and(T.Eq.f32(a4, b4), T.Eq.f32(a5, b5)), hr2)
      +hr3 = and_r(T.Eq.f32(a3, b3), Bool.and(T.Eq.f32(a4, b4), T.Eq.f32(a5, b5)), hr2)
      e3 = f32_eq_sound(a3, b3, hl3)
      +hl4 = and_l(T.Eq.f32(a4, b4), T.Eq.f32(a5, b5), hr3)
      +hr4 = and_r(T.Eq.f32(a4, b4), T.Eq.f32(a5, b5), hr3)
      e4 = f32_eq_sound(a4, b4, hl4)
      e5 = f32_eq_sound(a5, b5, hr4)
      %e0 : {R.STri{a0, a1, a2, a3, a4, a5} == R.STri{_, b1, b2, b3, b4, b5} : R.Shape}
      %e1 : {R.STri{a0, a1, a2, a3, a4, a5} == R.STri{a0, _, b2, b3, b4, b5} : R.Shape}
      %e2 : {R.STri{a0, a1, a2, a3, a4, a5} == R.STri{a0, a1, _, b3, b4, b5} : R.Shape}
      %e3 : {R.STri{a0, a1, a2, a3, a4, a5} == R.STri{a0, a1, a2, _, b4, b5} : R.Shape}
      %e4 : {R.STri{a0, a1, a2, a3, a4, a5} == R.STri{a0, a1, a2, a3, _, b5} : R.Shape}
      %e5 : {R.STri{a0, a1, a2, a3, a4, a5} == R.STri{a0, a1, a2, a3, a4, _} : R.Shape}
      {==}
    case R.STri{+a0, +a1, +a2, +a3, +a4, +a5} R.SMask{+b0, +b1, +b2, +b3, +b4}:
      Empty.absurd({R.STri{a0, a1, a2, a3, a4, a5} == R.SMask{b0, b1, b2, b3, b4} : R.Shape}, false_ne_true(h))
    case R.SMask{+a0, +a1, +a2, +a3, +a4} R.SRect{}:
      Empty.absurd({R.SMask{a0, a1, a2, a3, a4} == R.SRect{} : R.Shape}, false_ne_true(h))
    case R.SMask{+a0, +a1, +a2, +a3, +a4} R.SPoly{+b0, +b1}:
      Empty.absurd({R.SMask{a0, a1, a2, a3, a4} == R.SPoly{b0, b1} : R.Shape}, false_ne_true(h))
    case R.SMask{+a0, +a1, +a2, +a3, +a4} R.SGlyph{+b0, +b1, +b2}:
      Empty.absurd({R.SMask{a0, a1, a2, a3, a4} == R.SGlyph{b0, b1, b2} : R.Shape}, false_ne_true(h))
    case R.SMask{+a0, +a1, +a2, +a3, +a4} R.SSeg{+b0, +b1, +b2, +b3, +b4}:
      Empty.absurd({R.SMask{a0, a1, a2, a3, a4} == R.SSeg{b0, b1, b2, b3, b4} : R.Shape}, false_ne_true(h))
    case R.SMask{+a0, +a1, +a2, +a3, +a4} R.SDisc{+b0, +b1, +b2}:
      Empty.absurd({R.SMask{a0, a1, a2, a3, a4} == R.SDisc{b0, b1, b2} : R.Shape}, false_ne_true(h))
    case R.SMask{+a0, +a1, +a2, +a3, +a4} R.STri{+b0, +b1, +b2, +b3, +b4, +b5}:
      Empty.absurd({R.SMask{a0, a1, a2, a3, a4} == R.STri{b0, b1, b2, b3, b4, b5} : R.Shape}, false_ne_true(h))
    case R.SMask{+a0, +a1, +a2, +a3, +a4} R.SMask{+b0, +b1, +b2, +b3, +b4}:
      +hl0 = and_l(U32.is_eq(a0, b0), Bool.and(U32.is_eq(a1, b1), Bool.and(U32.is_eq(a2, b2), Bool.and(Nat.is_eq(a3, b3), T.Eq.mask(a4, b4)))), h)
      +hr0 = and_r(U32.is_eq(a0, b0), Bool.and(U32.is_eq(a1, b1), Bool.and(U32.is_eq(a2, b2), Bool.and(Nat.is_eq(a3, b3), T.Eq.mask(a4, b4)))), h)
      e0 = u32_eq_sound(a0, b0, hl0)
      +hl1 = and_l(U32.is_eq(a1, b1), Bool.and(U32.is_eq(a2, b2), Bool.and(Nat.is_eq(a3, b3), T.Eq.mask(a4, b4))), hr0)
      +hr1 = and_r(U32.is_eq(a1, b1), Bool.and(U32.is_eq(a2, b2), Bool.and(Nat.is_eq(a3, b3), T.Eq.mask(a4, b4))), hr0)
      e1 = u32_eq_sound(a1, b1, hl1)
      +hl2 = and_l(U32.is_eq(a2, b2), Bool.and(Nat.is_eq(a3, b3), T.Eq.mask(a4, b4)), hr1)
      +hr2 = and_r(U32.is_eq(a2, b2), Bool.and(Nat.is_eq(a3, b3), T.Eq.mask(a4, b4)), hr1)
      e2 = u32_eq_sound(a2, b2, hl2)
      +hl3 = and_l(Nat.is_eq(a3, b3), T.Eq.mask(a4, b4), hr2)
      +hr3 = and_r(Nat.is_eq(a3, b3), T.Eq.mask(a4, b4), hr2)
      e3 = nat_eq_sound(a3, b3, hl3)
      e4 = eq_mask_sound(a4, b4, hr3)
      %e0 : {R.SMask{a0, a1, a2, a3, a4} == R.SMask{_, b1, b2, b3, b4} : R.Shape}
      %e1 : {R.SMask{a0, a1, a2, a3, a4} == R.SMask{a0, _, b2, b3, b4} : R.Shape}
      %e2 : {R.SMask{a0, a1, a2, a3, a4} == R.SMask{a0, a1, _, b3, b4} : R.Shape}
      %e3 : {R.SMask{a0, a1, a2, a3, a4} == R.SMask{a0, a1, a2, _, b4} : R.Shape}
      %e4 : {R.SMask{a0, a1, a2, a3, a4} == R.SMask{a0, a1, a2, a3, _} : R.Shape}
      {==}

law eq_shape_refl:
  for +a: R.Shape
  {T.Eq.shape(a, a) == True{} : Bool}

def eq_shape_refl(a):
  match a:
    case R.SRect{}:
      {==}
    case R.SPoly{+a0, +a1}:
      %Equal.sym(Bool, Q.Eq.bool(a0, a0), True{}, bool_eq_refl(a0)) : {Bool.and(_, T.Eq.edges(a1, a1)) == True{} : Bool}
      %Equal.sym(Bool, T.Eq.edges(a1, a1), True{}, eq_edges_refl(a1)) : {Bool.and(True{}, _) == True{} : Bool}
      {==}
    case R.SGlyph{+a0, +a1, +a2}:
      %Equal.sym(Bool, U32.is_eq(a0, a0), True{}, u32_eq_refl(a0)) : {Bool.and(_, Bool.and(U32.is_eq(a1, a1), T.Eq.glyph(a2, a2))) == True{} : Bool}
      %Equal.sym(Bool, U32.is_eq(a1, a1), True{}, u32_eq_refl(a1)) : {Bool.and(True{}, Bool.and(_, T.Eq.glyph(a2, a2))) == True{} : Bool}
      %Equal.sym(Bool, T.Eq.glyph(a2, a2), True{}, eq_glyph_refl(a2)) : {Bool.and(True{}, Bool.and(True{}, _)) == True{} : Bool}
      {==}
    case R.SSeg{+a0, +a1, +a2, +a3, +a4}:
      %Equal.sym(Bool, T.Eq.f32(a0, a0), True{}, f32_eq_refl(a0)) : {Bool.and(_, Bool.and(T.Eq.f32(a1, a1), Bool.and(T.Eq.f32(a2, a2), Bool.and(T.Eq.f32(a3, a3), T.Eq.f32(a4, a4))))) == True{} : Bool}
      %Equal.sym(Bool, T.Eq.f32(a1, a1), True{}, f32_eq_refl(a1)) : {Bool.and(True{}, Bool.and(_, Bool.and(T.Eq.f32(a2, a2), Bool.and(T.Eq.f32(a3, a3), T.Eq.f32(a4, a4))))) == True{} : Bool}
      %Equal.sym(Bool, T.Eq.f32(a2, a2), True{}, f32_eq_refl(a2)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(_, Bool.and(T.Eq.f32(a3, a3), T.Eq.f32(a4, a4))))) == True{} : Bool}
      %Equal.sym(Bool, T.Eq.f32(a3, a3), True{}, f32_eq_refl(a3)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, Bool.and(_, T.Eq.f32(a4, a4))))) == True{} : Bool}
      %Equal.sym(Bool, T.Eq.f32(a4, a4), True{}, f32_eq_refl(a4)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, _)))) == True{} : Bool}
      {==}
    case R.SDisc{+a0, +a1, +a2}:
      %Equal.sym(Bool, T.Eq.f32(a0, a0), True{}, f32_eq_refl(a0)) : {Bool.and(_, Bool.and(T.Eq.f32(a1, a1), T.Eq.f32(a2, a2))) == True{} : Bool}
      %Equal.sym(Bool, T.Eq.f32(a1, a1), True{}, f32_eq_refl(a1)) : {Bool.and(True{}, Bool.and(_, T.Eq.f32(a2, a2))) == True{} : Bool}
      %Equal.sym(Bool, T.Eq.f32(a2, a2), True{}, f32_eq_refl(a2)) : {Bool.and(True{}, Bool.and(True{}, _)) == True{} : Bool}
      {==}
    case R.STri{+a0, +a1, +a2, +a3, +a4, +a5}:
      %Equal.sym(Bool, T.Eq.f32(a0, a0), True{}, f32_eq_refl(a0)) : {Bool.and(_, Bool.and(T.Eq.f32(a1, a1), Bool.and(T.Eq.f32(a2, a2), Bool.and(T.Eq.f32(a3, a3), Bool.and(T.Eq.f32(a4, a4), T.Eq.f32(a5, a5)))))) == True{} : Bool}
      %Equal.sym(Bool, T.Eq.f32(a1, a1), True{}, f32_eq_refl(a1)) : {Bool.and(True{}, Bool.and(_, Bool.and(T.Eq.f32(a2, a2), Bool.and(T.Eq.f32(a3, a3), Bool.and(T.Eq.f32(a4, a4), T.Eq.f32(a5, a5)))))) == True{} : Bool}
      %Equal.sym(Bool, T.Eq.f32(a2, a2), True{}, f32_eq_refl(a2)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(_, Bool.and(T.Eq.f32(a3, a3), Bool.and(T.Eq.f32(a4, a4), T.Eq.f32(a5, a5)))))) == True{} : Bool}
      %Equal.sym(Bool, T.Eq.f32(a3, a3), True{}, f32_eq_refl(a3)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, Bool.and(_, Bool.and(T.Eq.f32(a4, a4), T.Eq.f32(a5, a5)))))) == True{} : Bool}
      %Equal.sym(Bool, T.Eq.f32(a4, a4), True{}, f32_eq_refl(a4)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, Bool.and(_, T.Eq.f32(a5, a5)))))) == True{} : Bool}
      %Equal.sym(Bool, T.Eq.f32(a5, a5), True{}, f32_eq_refl(a5)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, _))))) == True{} : Bool}
      {==}
    case R.SMask{+a0, +a1, +a2, +a3, +a4}:
      %Equal.sym(Bool, U32.is_eq(a0, a0), True{}, u32_eq_refl(a0)) : {Bool.and(_, Bool.and(U32.is_eq(a1, a1), Bool.and(U32.is_eq(a2, a2), Bool.and(Nat.is_eq(a3, a3), T.Eq.mask(a4, a4))))) == True{} : Bool}
      %Equal.sym(Bool, U32.is_eq(a1, a1), True{}, u32_eq_refl(a1)) : {Bool.and(True{}, Bool.and(_, Bool.and(U32.is_eq(a2, a2), Bool.and(Nat.is_eq(a3, a3), T.Eq.mask(a4, a4))))) == True{} : Bool}
      %Equal.sym(Bool, U32.is_eq(a2, a2), True{}, u32_eq_refl(a2)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(_, Bool.and(Nat.is_eq(a3, a3), T.Eq.mask(a4, a4))))) == True{} : Bool}
      %Equal.sym(Bool, Nat.is_eq(a3, a3), True{}, nat_eq_refl(a3)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, Bool.and(_, T.Eq.mask(a4, a4))))) == True{} : Bool}
      %Equal.sym(Bool, T.Eq.mask(a4, a4), True{}, eq_mask_refl(a4)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, _)))) == True{} : Bool}
      {==}

law eq_op_sound:
  for a: R.Op
  for b: R.Op
  for +h: {T.Eq.op(a, b) == True{} : Bool}
  {a == b : R.Op}

def eq_op_sound(a, b, h):
  match a b:
    case R.Op{+a0, +a1, +a2, +a3, +a4, +a5, +a6} R.Op{+b0, +b1, +b2, +b3, +b4, +b5, +b6}:
      +hl0 = and_l(U32.is_eq(a0, b0), Bool.and(U32.is_eq(a1, b1), Bool.and(U32.is_eq(a2, b2), Bool.and(U32.is_eq(a3, b3), Bool.and(U32.is_eq(a4, b4), Bool.and(U32.is_eq(a5, b5), T.Eq.shape(a6, b6)))))), h)
      +hr0 = and_r(U32.is_eq(a0, b0), Bool.and(U32.is_eq(a1, b1), Bool.and(U32.is_eq(a2, b2), Bool.and(U32.is_eq(a3, b3), Bool.and(U32.is_eq(a4, b4), Bool.and(U32.is_eq(a5, b5), T.Eq.shape(a6, b6)))))), h)
      e0 = u32_eq_sound(a0, b0, hl0)
      +hl1 = and_l(U32.is_eq(a1, b1), Bool.and(U32.is_eq(a2, b2), Bool.and(U32.is_eq(a3, b3), Bool.and(U32.is_eq(a4, b4), Bool.and(U32.is_eq(a5, b5), T.Eq.shape(a6, b6))))), hr0)
      +hr1 = and_r(U32.is_eq(a1, b1), Bool.and(U32.is_eq(a2, b2), Bool.and(U32.is_eq(a3, b3), Bool.and(U32.is_eq(a4, b4), Bool.and(U32.is_eq(a5, b5), T.Eq.shape(a6, b6))))), hr0)
      e1 = u32_eq_sound(a1, b1, hl1)
      +hl2 = and_l(U32.is_eq(a2, b2), Bool.and(U32.is_eq(a3, b3), Bool.and(U32.is_eq(a4, b4), Bool.and(U32.is_eq(a5, b5), T.Eq.shape(a6, b6)))), hr1)
      +hr2 = and_r(U32.is_eq(a2, b2), Bool.and(U32.is_eq(a3, b3), Bool.and(U32.is_eq(a4, b4), Bool.and(U32.is_eq(a5, b5), T.Eq.shape(a6, b6)))), hr1)
      e2 = u32_eq_sound(a2, b2, hl2)
      +hl3 = and_l(U32.is_eq(a3, b3), Bool.and(U32.is_eq(a4, b4), Bool.and(U32.is_eq(a5, b5), T.Eq.shape(a6, b6))), hr2)
      +hr3 = and_r(U32.is_eq(a3, b3), Bool.and(U32.is_eq(a4, b4), Bool.and(U32.is_eq(a5, b5), T.Eq.shape(a6, b6))), hr2)
      e3 = u32_eq_sound(a3, b3, hl3)
      +hl4 = and_l(U32.is_eq(a4, b4), Bool.and(U32.is_eq(a5, b5), T.Eq.shape(a6, b6)), hr3)
      +hr4 = and_r(U32.is_eq(a4, b4), Bool.and(U32.is_eq(a5, b5), T.Eq.shape(a6, b6)), hr3)
      e4 = u32_eq_sound(a4, b4, hl4)
      +hl5 = and_l(U32.is_eq(a5, b5), T.Eq.shape(a6, b6), hr4)
      +hr5 = and_r(U32.is_eq(a5, b5), T.Eq.shape(a6, b6), hr4)
      e5 = u32_eq_sound(a5, b5, hl5)
      e6 = eq_shape_sound(a6, b6, hr5)
      %e0 : {R.Op{a0, a1, a2, a3, a4, a5, a6} == R.Op{_, b1, b2, b3, b4, b5, b6} : R.Op}
      %e1 : {R.Op{a0, a1, a2, a3, a4, a5, a6} == R.Op{a0, _, b2, b3, b4, b5, b6} : R.Op}
      %e2 : {R.Op{a0, a1, a2, a3, a4, a5, a6} == R.Op{a0, a1, _, b3, b4, b5, b6} : R.Op}
      %e3 : {R.Op{a0, a1, a2, a3, a4, a5, a6} == R.Op{a0, a1, a2, _, b4, b5, b6} : R.Op}
      %e4 : {R.Op{a0, a1, a2, a3, a4, a5, a6} == R.Op{a0, a1, a2, a3, _, b5, b6} : R.Op}
      %e5 : {R.Op{a0, a1, a2, a3, a4, a5, a6} == R.Op{a0, a1, a2, a3, a4, _, b6} : R.Op}
      %e6 : {R.Op{a0, a1, a2, a3, a4, a5, a6} == R.Op{a0, a1, a2, a3, a4, a5, _} : R.Op}
      {==}

law eq_op_refl:
  for +a: R.Op
  {T.Eq.op(a, a) == True{} : Bool}

def eq_op_refl(a):
  match a:
    case R.Op{+a0, +a1, +a2, +a3, +a4, +a5, +a6}:
      %Equal.sym(Bool, U32.is_eq(a0, a0), True{}, u32_eq_refl(a0)) : {Bool.and(_, Bool.and(U32.is_eq(a1, a1), Bool.and(U32.is_eq(a2, a2), Bool.and(U32.is_eq(a3, a3), Bool.and(U32.is_eq(a4, a4), Bool.and(U32.is_eq(a5, a5), T.Eq.shape(a6, a6))))))) == True{} : Bool}
      %Equal.sym(Bool, U32.is_eq(a1, a1), True{}, u32_eq_refl(a1)) : {Bool.and(True{}, Bool.and(_, Bool.and(U32.is_eq(a2, a2), Bool.and(U32.is_eq(a3, a3), Bool.and(U32.is_eq(a4, a4), Bool.and(U32.is_eq(a5, a5), T.Eq.shape(a6, a6))))))) == True{} : Bool}
      %Equal.sym(Bool, U32.is_eq(a2, a2), True{}, u32_eq_refl(a2)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(_, Bool.and(U32.is_eq(a3, a3), Bool.and(U32.is_eq(a4, a4), Bool.and(U32.is_eq(a5, a5), T.Eq.shape(a6, a6))))))) == True{} : Bool}
      %Equal.sym(Bool, U32.is_eq(a3, a3), True{}, u32_eq_refl(a3)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, Bool.and(_, Bool.and(U32.is_eq(a4, a4), Bool.and(U32.is_eq(a5, a5), T.Eq.shape(a6, a6))))))) == True{} : Bool}
      %Equal.sym(Bool, U32.is_eq(a4, a4), True{}, u32_eq_refl(a4)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, Bool.and(_, Bool.and(U32.is_eq(a5, a5), T.Eq.shape(a6, a6))))))) == True{} : Bool}
      %Equal.sym(Bool, U32.is_eq(a5, a5), True{}, u32_eq_refl(a5)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, Bool.and(_, T.Eq.shape(a6, a6))))))) == True{} : Bool}
      %Equal.sym(Bool, T.Eq.shape(a6, a6), True{}, eq_shape_refl(a6)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, _)))))) == True{} : Bool}
      {==}

law eq_ops_sound:
  for a: List<&2, R.Op>
  for b: List<&2, R.Op>
  for +h: {T.Eq.ops(a, b) == True{} : Bool}
  {a == b : List<&2, R.Op>}

def eq_ops_sound(a, b, h):
  match a b:
    case Nil{} Nil{}:
      {==}
    case Nil{} +y <> +yt:
      Empty.absurd({Nil{} == y <> yt : List<&2, R.Op>}, false_ne_true(h))
    case +x <> +xt Nil{}:
      Empty.absurd({x <> xt == Nil{} : List<&2, R.Op>}, false_ne_true(h))
    case +x <> +xt +y <> +yt:
      e0 = eq_op_sound(x, y, and_l(T.Eq.op(x, y), T.Eq.ops(xt, yt), h))
      e1 = eq_ops_sound(xt, yt, and_r(T.Eq.op(x, y), T.Eq.ops(xt, yt), h))
      %e0 : {x <> xt == _ <> yt : List<&2, R.Op>}
      %e1 : {x <> xt == x <> _ : List<&2, R.Op>}
      {==}

law eq_ops_refl:
  for +a: List<&2, R.Op>
  {T.Eq.ops(a, a) == True{} : Bool}

def eq_ops_refl(a):
  match a:
    case Nil{}:
      {==}
    case +x <> +xt:
      %Equal.sym(Bool, T.Eq.op(x, x), True{}, eq_op_refl(x)) : {Bool.and(_, T.Eq.ops(xt, xt)) == True{} : Bool}
      eq_ops_refl(xt)

law eq_image_sound:
  for a: Image
  for b: Image
  for +h: {T.Eq.image(a, b) == True{} : Bool}
  {a == b : Image}

def eq_image_sound(a, b, h):
  match a b:
    case Pix{+a0} Pix{+b0}:
      e0 = u32_eq_sound(a0, b0, h)
      %e0 : {Pix{a0} == Pix{_} : Image}
      {==}
    case Pix{+a0} Qua{+b0, +b1, +b2, +b3}:
      Empty.absurd({Pix{a0} == Qua{b0, b1, b2, b3} : Image}, false_ne_true(h))
    case Qua{+a0, +a1, +a2, +a3} Pix{+b0}:
      Empty.absurd({Qua{a0, a1, a2, a3} == Pix{b0} : Image}, false_ne_true(h))
    case Qua{+a0, +a1, +a2, +a3} Qua{+b0, +b1, +b2, +b3}:
      +hl0 = and_l(T.Eq.image(a0, b0), Bool.and(T.Eq.image(a1, b1), Bool.and(T.Eq.image(a2, b2), T.Eq.image(a3, b3))), h)
      +hr0 = and_r(T.Eq.image(a0, b0), Bool.and(T.Eq.image(a1, b1), Bool.and(T.Eq.image(a2, b2), T.Eq.image(a3, b3))), h)
      e0 = eq_image_sound(a0, b0, hl0)
      +hl1 = and_l(T.Eq.image(a1, b1), Bool.and(T.Eq.image(a2, b2), T.Eq.image(a3, b3)), hr0)
      +hr1 = and_r(T.Eq.image(a1, b1), Bool.and(T.Eq.image(a2, b2), T.Eq.image(a3, b3)), hr0)
      e1 = eq_image_sound(a1, b1, hl1)
      +hl2 = and_l(T.Eq.image(a2, b2), T.Eq.image(a3, b3), hr1)
      +hr2 = and_r(T.Eq.image(a2, b2), T.Eq.image(a3, b3), hr1)
      e2 = eq_image_sound(a2, b2, hl2)
      e3 = eq_image_sound(a3, b3, hr2)
      %e0 : {Qua{a0, a1, a2, a3} == Qua{_, b1, b2, b3} : Image}
      %e1 : {Qua{a0, a1, a2, a3} == Qua{a0, _, b2, b3} : Image}
      %e2 : {Qua{a0, a1, a2, a3} == Qua{a0, a1, _, b3} : Image}
      %e3 : {Qua{a0, a1, a2, a3} == Qua{a0, a1, a2, _} : Image}
      {==}

law eq_image_refl:
  for +a: Image
  {T.Eq.image(a, a) == True{} : Bool}

def eq_image_refl(a):
  match a:
    case Pix{+a0}:
      %Equal.sym(Bool, U32.is_eq(a0, a0), True{}, u32_eq_refl(a0)) : {_ == True{} : Bool}
      {==}
    case Qua{+a0, +a1, +a2, +a3}:
      %Equal.sym(Bool, T.Eq.image(a0, a0), True{}, eq_image_refl(a0)) : {Bool.and(_, Bool.and(T.Eq.image(a1, a1), Bool.and(T.Eq.image(a2, a2), T.Eq.image(a3, a3)))) == True{} : Bool}
      %Equal.sym(Bool, T.Eq.image(a1, a1), True{}, eq_image_refl(a1)) : {Bool.and(True{}, Bool.and(_, Bool.and(T.Eq.image(a2, a2), T.Eq.image(a3, a3)))) == True{} : Bool}
      %Equal.sym(Bool, T.Eq.image(a2, a2), True{}, eq_image_refl(a2)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(_, T.Eq.image(a3, a3)))) == True{} : Bool}
      %Equal.sym(Bool, T.Eq.image(a3, a3), True{}, eq_image_refl(a3)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, _))) == True{} : Bool}
      {==}

law eq_chr_sound:
  for a: Char
  for b: Char
  for +h: {Q.Eq.chr(a, b) == True{} : Bool}
  {a == b : Char}

def eq_chr_sound(a, b, h):
  match a b:
    case Chr{+a0} Chr{+b0}:
      e0 = u32_eq_sound(a0, b0, h)
      %e0 : {Chr{a0} == Chr{_} : Char}
      {==}

law eq_chr_refl:
  for +a: Char
  {Q.Eq.chr(a, a) == True{} : Bool}

def eq_chr_refl(a):
  match a:
    case Chr{+a0}:
      %Equal.sym(Bool, U32.is_eq(a0, a0), True{}, u32_eq_refl(a0)) : {_ == True{} : Bool}
      {==}

law eq_str_sound:
  for a: String
  for b: String
  for +h: {Q.Eq.str(a, b) == True{} : Bool}
  {a == b : String}

def eq_str_sound(a, b, h):
  match a b:
    case SNil{} SNil{}:
      {==}
    case SNil{} SCon{+y, +yt}:
      Empty.absurd({SNil{} == SCon{y, yt} : String}, false_ne_true(h))
    case SCon{+x, +xt} SNil{}:
      Empty.absurd({SCon{x, xt} == SNil{} : String}, false_ne_true(h))
    case SCon{+x, +xt} SCon{+y, +yt}:
      e0 = eq_chr_sound(x, y, and_l(Q.Eq.chr(x, y), Q.Eq.str(xt, yt), h))
      e1 = eq_str_sound(xt, yt, and_r(Q.Eq.chr(x, y), Q.Eq.str(xt, yt), h))
      %e0 : {SCon{x, xt} == SCon{_, yt} : String}
      %e1 : {SCon{x, xt} == SCon{x, _} : String}
      {==}

law eq_str_refl:
  for +a: String
  {Q.Eq.str(a, a) == True{} : Bool}

def eq_str_refl(a):
  match a:
    case SNil{}:
      {==}
    case SCon{+x, +xt}:
      %Equal.sym(Bool, Q.Eq.chr(x, x), True{}, eq_chr_refl(x)) : {Bool.and(_, Q.Eq.str(xt, xt)) == True{} : Bool}
      eq_str_refl(xt)

law eq_role_sound:
  for a: M.Role
  for b: M.Role
  for +h: {Q.Eq.role(a, b) == True{} : Bool}
  {a == b : M.Role}

def eq_role_sound(a, b, h):
  match a b:
    case M.User{} M.User{}:
      {==}
    case M.User{} M.Assistant{}:
      Empty.absurd({M.User{} == M.Assistant{} : M.Role}, false_ne_true(h))
    case M.User{} M.System{}:
      Empty.absurd({M.User{} == M.System{} : M.Role}, false_ne_true(h))
    case M.Assistant{} M.User{}:
      Empty.absurd({M.Assistant{} == M.User{} : M.Role}, false_ne_true(h))
    case M.Assistant{} M.Assistant{}:
      {==}
    case M.Assistant{} M.System{}:
      Empty.absurd({M.Assistant{} == M.System{} : M.Role}, false_ne_true(h))
    case M.System{} M.User{}:
      Empty.absurd({M.System{} == M.User{} : M.Role}, false_ne_true(h))
    case M.System{} M.Assistant{}:
      Empty.absurd({M.System{} == M.Assistant{} : M.Role}, false_ne_true(h))
    case M.System{} M.System{}:
      {==}

law eq_role_refl:
  for +a: M.Role
  {Q.Eq.role(a, a) == True{} : Bool}

def eq_role_refl(a):
  match a:
    case M.User{}:
      {==}
    case M.Assistant{}:
      {==}
    case M.System{}:
      {==}

law eq_entry_sound:
  for a: M.Entry
  for b: M.Entry
  for +h: {Q.Eq.entry(a, b) == True{} : Bool}
  {a == b : M.Entry}

def eq_entry_sound(a, b, h):
  match a b:
    case M.Msg{+a0, +a1, +a2, +a3, +a4} M.Msg{+b0, +b1, +b2, +b3, +b4}:
      +hl0 = and_l(Q.Eq.str(a0, b0), Bool.and(Q.Eq.str(a1, b1), Bool.and(Q.Eq.role(a2, b2), Bool.and(Q.Eq.str(a3, b3), Nat.is_eq(a4, b4)))), h)
      +hr0 = and_r(Q.Eq.str(a0, b0), Bool.and(Q.Eq.str(a1, b1), Bool.and(Q.Eq.role(a2, b2), Bool.and(Q.Eq.str(a3, b3), Nat.is_eq(a4, b4)))), h)
      e0 = eq_str_sound(a0, b0, hl0)
      +hl1 = and_l(Q.Eq.str(a1, b1), Bool.and(Q.Eq.role(a2, b2), Bool.and(Q.Eq.str(a3, b3), Nat.is_eq(a4, b4))), hr0)
      +hr1 = and_r(Q.Eq.str(a1, b1), Bool.and(Q.Eq.role(a2, b2), Bool.and(Q.Eq.str(a3, b3), Nat.is_eq(a4, b4))), hr0)
      e1 = eq_str_sound(a1, b1, hl1)
      +hl2 = and_l(Q.Eq.role(a2, b2), Bool.and(Q.Eq.str(a3, b3), Nat.is_eq(a4, b4)), hr1)
      +hr2 = and_r(Q.Eq.role(a2, b2), Bool.and(Q.Eq.str(a3, b3), Nat.is_eq(a4, b4)), hr1)
      e2 = eq_role_sound(a2, b2, hl2)
      +hl3 = and_l(Q.Eq.str(a3, b3), Nat.is_eq(a4, b4), hr2)
      +hr3 = and_r(Q.Eq.str(a3, b3), Nat.is_eq(a4, b4), hr2)
      e3 = eq_str_sound(a3, b3, hl3)
      e4 = nat_eq_sound(a4, b4, hr3)
      %e0 : {M.Msg{a0, a1, a2, a3, a4} == M.Msg{_, b1, b2, b3, b4} : M.Entry}
      %e1 : {M.Msg{a0, a1, a2, a3, a4} == M.Msg{a0, _, b2, b3, b4} : M.Entry}
      %e2 : {M.Msg{a0, a1, a2, a3, a4} == M.Msg{a0, a1, _, b3, b4} : M.Entry}
      %e3 : {M.Msg{a0, a1, a2, a3, a4} == M.Msg{a0, a1, a2, _, b4} : M.Entry}
      %e4 : {M.Msg{a0, a1, a2, a3, a4} == M.Msg{a0, a1, a2, a3, _} : M.Entry}
      {==}
    case M.Msg{+a0, +a1, +a2, +a3, +a4} M.Act{+b0, +b1, +b2, +b3, +b4, +b5}:
      Empty.absurd({M.Msg{a0, a1, a2, a3, a4} == M.Act{b0, b1, b2, b3, b4, b5} : M.Entry}, false_ne_true(h))
    case M.Act{+a0, +a1, +a2, +a3, +a4, +a5} M.Msg{+b0, +b1, +b2, +b3, +b4}:
      Empty.absurd({M.Act{a0, a1, a2, a3, a4, a5} == M.Msg{b0, b1, b2, b3, b4} : M.Entry}, false_ne_true(h))
    case M.Act{+a0, +a1, +a2, +a3, +a4, +a5} M.Act{+b0, +b1, +b2, +b3, +b4, +b5}:
      +hl0 = and_l(Q.Eq.str(a0, b0), Bool.and(Q.Eq.str(a1, b1), Bool.and(Q.Eq.str(a2, b2), Bool.and(Q.Eq.str(a3, b3), Bool.and(Q.Eq.str(a4, b4), Nat.is_eq(a5, b5))))), h)
      +hr0 = and_r(Q.Eq.str(a0, b0), Bool.and(Q.Eq.str(a1, b1), Bool.and(Q.Eq.str(a2, b2), Bool.and(Q.Eq.str(a3, b3), Bool.and(Q.Eq.str(a4, b4), Nat.is_eq(a5, b5))))), h)
      e0 = eq_str_sound(a0, b0, hl0)
      +hl1 = and_l(Q.Eq.str(a1, b1), Bool.and(Q.Eq.str(a2, b2), Bool.and(Q.Eq.str(a3, b3), Bool.and(Q.Eq.str(a4, b4), Nat.is_eq(a5, b5)))), hr0)
      +hr1 = and_r(Q.Eq.str(a1, b1), Bool.and(Q.Eq.str(a2, b2), Bool.and(Q.Eq.str(a3, b3), Bool.and(Q.Eq.str(a4, b4), Nat.is_eq(a5, b5)))), hr0)
      e1 = eq_str_sound(a1, b1, hl1)
      +hl2 = and_l(Q.Eq.str(a2, b2), Bool.and(Q.Eq.str(a3, b3), Bool.and(Q.Eq.str(a4, b4), Nat.is_eq(a5, b5))), hr1)
      +hr2 = and_r(Q.Eq.str(a2, b2), Bool.and(Q.Eq.str(a3, b3), Bool.and(Q.Eq.str(a4, b4), Nat.is_eq(a5, b5))), hr1)
      e2 = eq_str_sound(a2, b2, hl2)
      +hl3 = and_l(Q.Eq.str(a3, b3), Bool.and(Q.Eq.str(a4, b4), Nat.is_eq(a5, b5)), hr2)
      +hr3 = and_r(Q.Eq.str(a3, b3), Bool.and(Q.Eq.str(a4, b4), Nat.is_eq(a5, b5)), hr2)
      e3 = eq_str_sound(a3, b3, hl3)
      +hl4 = and_l(Q.Eq.str(a4, b4), Nat.is_eq(a5, b5), hr3)
      +hr4 = and_r(Q.Eq.str(a4, b4), Nat.is_eq(a5, b5), hr3)
      e4 = eq_str_sound(a4, b4, hl4)
      e5 = nat_eq_sound(a5, b5, hr4)
      %e0 : {M.Act{a0, a1, a2, a3, a4, a5} == M.Act{_, b1, b2, b3, b4, b5} : M.Entry}
      %e1 : {M.Act{a0, a1, a2, a3, a4, a5} == M.Act{a0, _, b2, b3, b4, b5} : M.Entry}
      %e2 : {M.Act{a0, a1, a2, a3, a4, a5} == M.Act{a0, a1, _, b3, b4, b5} : M.Entry}
      %e3 : {M.Act{a0, a1, a2, a3, a4, a5} == M.Act{a0, a1, a2, _, b4, b5} : M.Entry}
      %e4 : {M.Act{a0, a1, a2, a3, a4, a5} == M.Act{a0, a1, a2, a3, _, b5} : M.Entry}
      %e5 : {M.Act{a0, a1, a2, a3, a4, a5} == M.Act{a0, a1, a2, a3, a4, _} : M.Entry}
      {==}

law eq_entry_refl:
  for +a: M.Entry
  {Q.Eq.entry(a, a) == True{} : Bool}

def eq_entry_refl(a):
  match a:
    case M.Msg{+a0, +a1, +a2, +a3, +a4}:
      %Equal.sym(Bool, Q.Eq.str(a0, a0), True{}, eq_str_refl(a0)) : {Bool.and(_, Bool.and(Q.Eq.str(a1, a1), Bool.and(Q.Eq.role(a2, a2), Bool.and(Q.Eq.str(a3, a3), Nat.is_eq(a4, a4))))) == True{} : Bool}
      %Equal.sym(Bool, Q.Eq.str(a1, a1), True{}, eq_str_refl(a1)) : {Bool.and(True{}, Bool.and(_, Bool.and(Q.Eq.role(a2, a2), Bool.and(Q.Eq.str(a3, a3), Nat.is_eq(a4, a4))))) == True{} : Bool}
      %Equal.sym(Bool, Q.Eq.role(a2, a2), True{}, eq_role_refl(a2)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(_, Bool.and(Q.Eq.str(a3, a3), Nat.is_eq(a4, a4))))) == True{} : Bool}
      %Equal.sym(Bool, Q.Eq.str(a3, a3), True{}, eq_str_refl(a3)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, Bool.and(_, Nat.is_eq(a4, a4))))) == True{} : Bool}
      %Equal.sym(Bool, Nat.is_eq(a4, a4), True{}, nat_eq_refl(a4)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, _)))) == True{} : Bool}
      {==}
    case M.Act{+a0, +a1, +a2, +a3, +a4, +a5}:
      %Equal.sym(Bool, Q.Eq.str(a0, a0), True{}, eq_str_refl(a0)) : {Bool.and(_, Bool.and(Q.Eq.str(a1, a1), Bool.and(Q.Eq.str(a2, a2), Bool.and(Q.Eq.str(a3, a3), Bool.and(Q.Eq.str(a4, a4), Nat.is_eq(a5, a5)))))) == True{} : Bool}
      %Equal.sym(Bool, Q.Eq.str(a1, a1), True{}, eq_str_refl(a1)) : {Bool.and(True{}, Bool.and(_, Bool.and(Q.Eq.str(a2, a2), Bool.and(Q.Eq.str(a3, a3), Bool.and(Q.Eq.str(a4, a4), Nat.is_eq(a5, a5)))))) == True{} : Bool}
      %Equal.sym(Bool, Q.Eq.str(a2, a2), True{}, eq_str_refl(a2)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(_, Bool.and(Q.Eq.str(a3, a3), Bool.and(Q.Eq.str(a4, a4), Nat.is_eq(a5, a5)))))) == True{} : Bool}
      %Equal.sym(Bool, Q.Eq.str(a3, a3), True{}, eq_str_refl(a3)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, Bool.and(_, Bool.and(Q.Eq.str(a4, a4), Nat.is_eq(a5, a5)))))) == True{} : Bool}
      %Equal.sym(Bool, Q.Eq.str(a4, a4), True{}, eq_str_refl(a4)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, Bool.and(_, Nat.is_eq(a5, a5)))))) == True{} : Bool}
      %Equal.sym(Bool, Nat.is_eq(a5, a5), True{}, nat_eq_refl(a5)) : {Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, Bool.and(True{}, _))))) == True{} : Bool}
      {==}

# Drawing laws
# ------------

law tile_again_k:
  for s: Bool
  for +e: Nat
  for +ops: List<&2, R.Op>
  for +old: List<&2, R.Op>
  for +base0: Image
  for +base1: Image
  for +rx: U32
  for +ry: U32
  for +n: U32
  for +h: {Bool.and(T.Eq.ops(ops, old), T.Eq.image(base1, base0)) == s : Bool}
  {T.Tile.again.k(s, e, ops, base1, T.Tile.make(e, old, base0, rx, ry, n), rx, ry, n) == T.Tile.make(e, ops, base1, rx, ry, n) : T.Tile}

def tile_again_k(s, e, ops, old, base0, base1, rx, ry, n, h):
  match s:
    case False{}:
      {==}
    case True{}:
      eo = eq_ops_sound(ops, old, and_l(T.Eq.ops(ops, old), T.Eq.image(base1, base0), h))
      eb = eq_image_sound(base1, base0, and_r(T.Eq.ops(ops, old), T.Eq.image(base1, base0), h))
      %Equal.sym(List<&2, R.Op>, ops, old, eo) : {T.Tile.make(e, old, base0, rx, ry, n) == T.Tile.make(e, _, base1, rx, ry, n) : T.Tile}
      %Equal.sym(Image, base1, base0, eb) : {T.Tile.make(e, old, base0, rx, ry, n) == T.Tile.make(e, old, _, rx, ry, n) : T.Tile}
      {==}

law tnode_cong:
  for -a1: T.Tiles
  for -a2: T.Tiles
  for -b1: T.Tiles
  for -b2: T.Tiles
  for -c1: T.Tiles
  for -c2: T.Tiles
  for -d1: T.Tiles
  for -d2: T.Tiles
  for ea: {a1 == a2 : T.Tiles}
  for eb: {b1 == b2 : T.Tiles}
  for ec: {c1 == c2 : T.Tiles}
  for ed: {d1 == d2 : T.Tiles}
  {T.TNode{a1, b1, c1, d1} == T.TNode{a2, b2, c2, d2} : T.Tiles}

def tnode_cong(a1, a2, b1, b2, c1, c2, d1, d2, ea, eb, ec, ed):
  %ea : {T.TNode{a1, b1, c1, d1} == T.TNode{_, b2, c2, d2} : T.Tiles}
  %eb : {T.TNode{a1, b1, c1, d1} == T.TNode{a1, _, c2, d2} : T.Tiles}
  %ec : {T.TNode{a1, b1, c1, d1} == T.TNode{a1, b1, _, d2} : T.Tiles}
  %ed : {T.TNode{a1, b1, c1, d1} == T.TNode{a1, b1, c1, _} : T.Tiles}
  {==}

def Laws.tiles_again_exact(k, e, ops, old, base0, base1, rx, ry, n):
  match k:
    case 0n:
      Equal.cong(T.Tile, T.Tiles, t => T.TLeaf{t}, T.Tile.again(e, ops, base1, T.Tile.make(e, old, base0, rx, ry, n), rx, ry, n), T.Tile.make(e, ops, base1, rx, ry, n),
        tile_again_k(Bool.and(T.Eq.ops(ops, old), T.Eq.image(base1, base0)), e, ops, old, base0, base1, rx, ry, n, {==}))
    case 1n+j0:
      +j = j0
      tnode_cong(T.Tiles.again(j, e, R.Region.keep(ops, rx, ry, rx, ry, U32.shr(n)), T.Img.q(base1, 0n), T.Tiles.make(j, e, R.Region.keep(old, rx, ry, rx, ry, U32.shr(n)), T.Img.q(base0, 0n), rx, ry, U32.shr(n)), rx, ry, U32.shr(n)),
        T.Tiles.make(j, e, R.Region.keep(ops, rx, ry, rx, ry, U32.shr(n)), T.Img.q(base1, 0n), rx, ry, U32.shr(n)),
        T.Tiles.again(j, e, R.Region.keep(ops, rx, ry, (rx + U32.shr(n) : U32), ry, U32.shr(n)), T.Img.q(base1, 1n), T.Tiles.make(j, e, R.Region.keep(old, rx, ry, (rx + U32.shr(n) : U32), ry, U32.shr(n)), T.Img.q(base0, 1n), (rx + U32.shr(n) : U32), ry, U32.shr(n)), (rx + U32.shr(n) : U32), ry, U32.shr(n)),
        T.Tiles.make(j, e, R.Region.keep(ops, rx, ry, (rx + U32.shr(n) : U32), ry, U32.shr(n)), T.Img.q(base1, 1n), (rx + U32.shr(n) : U32), ry, U32.shr(n)),
        T.Tiles.again(j, e, R.Region.keep(ops, rx, ry, rx, (ry + U32.shr(n) : U32), U32.shr(n)), T.Img.q(base1, 2n), T.Tiles.make(j, e, R.Region.keep(old, rx, ry, rx, (ry + U32.shr(n) : U32), U32.shr(n)), T.Img.q(base0, 2n), rx, (ry + U32.shr(n) : U32), U32.shr(n)), rx, (ry + U32.shr(n) : U32), U32.shr(n)),
        T.Tiles.make(j, e, R.Region.keep(ops, rx, ry, rx, (ry + U32.shr(n) : U32), U32.shr(n)), T.Img.q(base1, 2n), rx, (ry + U32.shr(n) : U32), U32.shr(n)),
        T.Tiles.again(j, e, R.Region.keep(ops, rx, ry, (rx + U32.shr(n) : U32), (ry + U32.shr(n) : U32), U32.shr(n)), T.Img.q(base1, 3n), T.Tiles.make(j, e, R.Region.keep(old, rx, ry, (rx + U32.shr(n) : U32), (ry + U32.shr(n) : U32), U32.shr(n)), T.Img.q(base0, 3n), (rx + U32.shr(n) : U32), (ry + U32.shr(n) : U32), U32.shr(n)), (rx + U32.shr(n) : U32), (ry + U32.shr(n) : U32), U32.shr(n)),
        T.Tiles.make(j, e, R.Region.keep(ops, rx, ry, (rx + U32.shr(n) : U32), (ry + U32.shr(n) : U32), U32.shr(n)), T.Img.q(base1, 3n), (rx + U32.shr(n) : U32), (ry + U32.shr(n) : U32), U32.shr(n)),
        Laws.tiles_again_exact(j, e, R.Region.keep(ops, rx, ry, rx, ry, U32.shr(n)), R.Region.keep(old, rx, ry, rx, ry, U32.shr(n)), T.Img.q(base0, 0n), T.Img.q(base1, 0n), rx, ry, U32.shr(n)),
        Laws.tiles_again_exact(j, e, R.Region.keep(ops, rx, ry, (rx + U32.shr(n) : U32), ry, U32.shr(n)), R.Region.keep(old, rx, ry, (rx + U32.shr(n) : U32), ry, U32.shr(n)), T.Img.q(base0, 1n), T.Img.q(base1, 1n), (rx + U32.shr(n) : U32), ry, U32.shr(n)),
        Laws.tiles_again_exact(j, e, R.Region.keep(ops, rx, ry, rx, (ry + U32.shr(n) : U32), U32.shr(n)), R.Region.keep(old, rx, ry, rx, (ry + U32.shr(n) : U32), U32.shr(n)), T.Img.q(base0, 2n), T.Img.q(base1, 2n), rx, (ry + U32.shr(n) : U32), U32.shr(n)),
        Laws.tiles_again_exact(j, e, R.Region.keep(ops, rx, ry, (rx + U32.shr(n) : U32), (ry + U32.shr(n) : U32), U32.shr(n)), R.Region.keep(old, rx, ry, (rx + U32.shr(n) : U32), (ry + U32.shr(n) : U32), U32.shr(n)), T.Img.q(base0, 3n), T.Img.q(base1, 3n), (rx + U32.shr(n) : U32), (ry + U32.shr(n) : U32), U32.shr(n)))

def Laws.tile_keep(e, ops, base, img, rx, ry, n):
  %Equal.sym(Bool, T.Eq.ops(ops, ops), True{}, eq_ops_refl(ops)) : {T.Tile.again.k(Bool.and(_, T.Eq.image(base, base)), e, ops, base, T.Tile{ops, base, img}, rx, ry, n) == T.Tile{ops, base, img} : T.Tile}
  %Equal.sym(Bool, T.Eq.image(base, base), True{}, eq_image_refl(base)) : {T.Tile.again.k(Bool.and(True{}, _), e, ops, base, T.Tile{ops, base, img}, rx, ry, n) == T.Tile{ops, base, img} : T.Tile}
  {==}

law frame_again_k:
  for s: Bool
  for +w0: U32
  for +h0: U32
  for +w: U32
  for +h: U32
  for +ops: List<&2, R.Op>
  for +old: List<&2, R.Op>
  for +base0: Image
  for +base: Image
  for +hs: {Bool.and(U32.is_eq(w0, w), U32.is_eq(h0, h)) == s : Bool}
  {T.Frame.again.k(s, w, h, ops, base, T.Frame.make(w0, h0, old, base0)) == T.Frame.make(w, h, ops, base) : T.Tiles}

def frame_again_k(s, w0, h0, w, h, ops, old, base0, base, hs):
  match s:
    case False{}:
      {==}
    case True{}:
      ew = u32_eq_sound(w0, w, and_l(U32.is_eq(w0, w), U32.is_eq(h0, h), hs))
      eh = u32_eq_sound(h0, h, and_r(U32.is_eq(w0, w), U32.is_eq(h0, h), hs))
      %ew : {T.Tiles.again(T.Frame.levels(_, h), T.Frame.edge(_, h), ops, base, T.Frame.make(w0, h0, old, base0), 0, 0, U32.shln(1, R.Frame.depth(_, h))) == T.Frame.make(_, h, ops, base) : T.Tiles}
      %eh : {T.Tiles.again(T.Frame.levels(w0, _), T.Frame.edge(w0, _), ops, base, T.Frame.make(w0, h0, old, base0), 0, 0, U32.shln(1, R.Frame.depth(w0, _))) == T.Frame.make(w0, _, ops, base) : T.Tiles}
      Laws.tiles_again_exact(T.Frame.levels(w0, h0), T.Frame.edge(w0, h0), ops, old, base0, base, 0, 0, U32.shln(1, R.Frame.depth(w0, h0)))

def Laws.frame_again_exact(w0, h0, w, h, ops, old, base0, base):
  frame_again_k(Bool.and(U32.is_eq(w0, w), U32.is_eq(h0, h)), w0, h0, w, h, ops, old, base0, base, {==})

law tl_one_k:
  for s: Bool
  for +ty: L.Ty
  for +e: M.Entry
  for +o: M.Entry
  for +px: U32
  for +sel: String
  for +h: {Q.Eq.entry(e, o) == s : Bool}
  {L.TL.memo.one.k(s, ty, e, px, sel, L.TL.memo.item(ty, o, px, sel)) == L.TL.memo.item(ty, e, px, sel) : L.TLE}

def tl_one_k(s, ty, e, o, px, sel, h):
  match s:
    case False{}:
      {==}
    case True{}:
      eo = eq_entry_sound(e, o, h)
      %eo : {L.TL.memo.item(ty, _, px, sel) == L.TL.memo.item(ty, e, px, sel) : L.TLE}
      {==}

def Laws.tl_again_exact(es, ty, old, px, sel):
  match es:
    case Nil{}:
      {==}
    case +e <> +t:
      match old:
        case Nil{}:
          {==}
        case +o <> +ot:
          e1 = Equal.sym(L.TLE, L.TL.memo.one.k(Q.Eq.entry(e, o), ty, e, px, sel, L.TL.memo.item(ty, o, px, sel)), L.TL.memo.item(ty, e, px, sel), tl_one_k(Q.Eq.entry(e, o), ty, e, o, px, sel, {==}))
          e2 = Equal.sym(List<&2, L.TLE>, L.TL.memo.again(t, ty, px, sel, L.TL.memo.make(ty, ot, px, sel)), L.TL.memo.make(ty, t, px, sel), Laws.tl_again_exact(t, ty, ot, px, sel))
          %e1 : {_ <> L.TL.memo.again(t, ty, px, sel, L.TL.memo.make(ty, ot, px, sel)) == L.TL.memo.item(ty, e, px, sel) <> L.TL.memo.make(ty, t, px, sel) : List<&2, L.TLE>}
          %e2 : {L.TL.memo.item(ty, e, px, sel) <> _ == L.TL.memo.item(ty, e, px, sel) <> L.TL.memo.make(ty, t, px, sel) : List<&2, L.TLE>}
          {==}

def Laws.tl_keep(ty, e, px, sel, p):
  %Equal.sym(Bool, Q.Eq.entry(e, e), True{}, eq_entry_refl(e)) : {L.TL.memo.one.k(_, ty, e, px, sel, L.TLE{e, p}) == L.TLE{e, p} : L.TLE}
  {==}

law tl_of_k:
  for s: Bool
  for +ty: L.Ty
  for +es: List<&2, M.Entry>
  for +old: List<&2, M.Entry>
  for +px0: U32
  for +sel0: String
  for +px: U32
  for +sel: String
  for +h: {Bool.and(U32.is_eq(px0, px), Q.Eq.str(sel0, sel)) == s : Bool}
  {L.TL.memo.of.k(s, ty, es, px, sel, L.TL.memo.make(ty, old, px0, sel0)) == L.TLMemo{px, sel, L.TL.memo.make(ty, es, px, sel)} : L.TLMemo}

def tl_of_k(s, ty, es, old, px0, sel0, px, sel, h):
  match s:
    case False{}:
      {==}
    case True{}:
      ep = u32_eq_sound(px0, px, and_l(U32.is_eq(px0, px), Q.Eq.str(sel0, sel), h))
      el = eq_str_sound(sel0, sel, and_r(U32.is_eq(px0, px), Q.Eq.str(sel0, sel), h))
      %Equal.sym(U32, px0, px, ep) : {L.TLMemo{px, sel, L.TL.memo.again(es, ty, px, sel, L.TL.memo.make(ty, old, _, sel0))} == L.TLMemo{px, sel, L.TL.memo.make(ty, es, px, sel)} : L.TLMemo}
      %Equal.sym(String, sel0, sel, el) : {L.TLMemo{px, sel, L.TL.memo.again(es, ty, px, sel, L.TL.memo.make(ty, old, px, _))} == L.TLMemo{px, sel, L.TL.memo.make(ty, es, px, sel)} : L.TLMemo}
      Equal.cong(List<&2, L.TLE>, L.TLMemo, x => L.TLMemo{px, sel, x}, L.TL.memo.again(es, ty, px, sel, L.TL.memo.make(ty, old, px, sel)), L.TL.memo.make(ty, es, px, sel), Laws.tl_again_exact(es, ty, old, px, sel))

def Laws.tl_memo_exact(ty, es, old, px0, sel0, px, sel):
  tl_of_k(Bool.and(U32.is_eq(px0, px), Q.Eq.str(sel0, sel)), ty, es, old, px0, sel0, px, sel, {==})

law tl_entries_memo:
  for +ty: L.Ty
  for +es: List<&2, M.Entry>
  for +st: M.State
  for +sel: String
  for +px: U32
  for +pics: Map<&2, String>
  {L.TL.entries.m(ty, L.TL.memo.make(ty, es, px, sel), st, sel, px, pics) == L.TL.entries(ty, es, st, sel, px, pics) : List<&2, L.TLine>}

# the memo's items were made for exactly the entries
law tl_memo_es:
  for +ty: L.Ty
  for es: List<&2, M.Entry>
  for +px: U32
  for +sel: String
  {L.TL.memo.es(L.TL.memo.make(ty, es, px, sel)) == es : List<&2, M.Entry>}

def tl_memo_es(ty, es, px, sel):
  match es:
    case Nil{}:
      {==}
    case +e <> +t:
      Equal.cong(List<&2, M.Entry>, List<&2, M.Entry>, x => e <> x, L.TL.memo.es(L.TL.memo.make(ty, t, px, sel)), t, tl_memo_es(ty, t, px, sel))

# under the same roles, the memo's items show as the entries do
law tl_entries_roles:
  for +ty: L.Ty
  for es: List<&2, M.Entry>
  for rs: List<&2, FO.Role>
  for +st: M.State
  for +sel: String
  for +px: U32
  for +pics: Map<&2, String>
  {L.TL.entries.mr(ty, L.TL.memo.make(ty, es, px, sel), rs, st, sel, px, pics) == L.TL.entries.r(ty, es, rs, st, sel, px, pics) : List<&2, L.TLine>}

def tl_entries_roles(ty, es, rs, st, sel, px, pics):
  match es:
    case Nil{}:
      {==}
    case +e <> +t:
      match rs:
        case Nil{}:
          Equal.cong(List<&2, L.TLine>, List<&2, L.TLine>, x => List.append(&2, L.TLine, L.TL.entry(ty, e, st, sel, px, pics), x),
            L.TL.entries.mr(ty, L.TL.memo.make(ty, t, px, sel), Nil{}, st, sel, px, pics), L.TL.entries.r(ty, t, Nil{}, st, sel, px, pics), tl_entries_roles(ty, t, Nil{}, st, sel, px, pics))
        case +r <> +rt:
          Equal.cong(List<&2, L.TLine>, List<&2, L.TLine>, x => List.append(&2, L.TLine, L.TL.role(r, ty, L.TL.entry(ty, e, st, sel, px, pics), px), x),
            L.TL.entries.mr(ty, L.TL.memo.make(ty, t, px, sel), rt, st, sel, px, pics), L.TL.entries.r(ty, t, rt, st, sel, px, pics), tl_entries_roles(ty, t, rt, st, sel, px, pics))

def tl_entries_memo(ty, es, st, sel, px, pics):
  %Equal.sym(List<&2, M.Entry>, L.TL.memo.es(L.TL.memo.make(ty, es, px, sel)), es, tl_memo_es(ty, es, px, sel))
    : {L.TL.entries.mr(ty, L.TL.memo.make(ty, es, px, sel), L.TL.roles(_, st, sel, pics), st, sel, px, pics) == L.TL.entries(ty, es, st, sel, px, pics) : List<&2, L.TLine>}
  tl_entries_roles(ty, es, L.TL.roles(es, st, sel, pics), st, sel, px, pics)

law tl_lines_k:
  for s: Bool
  for +ty: L.Ty
  for +es: List<&2, M.Entry>
  for +old: List<&2, M.Entry>
  for +px0: U32
  for +sel0: String
  for +st: M.State
  for +sel: String
  for +px: U32
  for +pics: Map<&2, String>
  for +h: {Bool.and(U32.is_eq(px0, px), Q.Eq.str(sel0, sel)) == s : Bool}
  {L.TL.memo.lines.k(s, ty, L.TLMemo{px0, sel0, L.TL.memo.make(ty, old, px0, sel0)}, es, st, sel, px, pics) == L.TL.entries(ty, es, st, sel, px, pics) : List<&2, L.TLine>}

def tl_lines_k(s, ty, es, old, px0, sel0, st, sel, px, pics, h):
  match s:
    case False{}:
      {==}
    case True{}:
      ep = u32_eq_sound(px0, px, and_l(U32.is_eq(px0, px), Q.Eq.str(sel0, sel), h))
      el = eq_str_sound(sel0, sel, and_r(U32.is_eq(px0, px), Q.Eq.str(sel0, sel), h))
      %Equal.sym(U32, px0, px, ep) : {L.TL.entries.m(ty, L.TL.memo.again(es, ty, px, sel, L.TL.memo.make(ty, old, _, sel0)), st, sel, px, pics) == L.TL.entries(ty, es, st, sel, px, pics) : List<&2, L.TLine>}
      %Equal.sym(String, sel0, sel, el) : {L.TL.entries.m(ty, L.TL.memo.again(es, ty, px, sel, L.TL.memo.make(ty, old, px, _)), st, sel, px, pics) == L.TL.entries(ty, es, st, sel, px, pics) : List<&2, L.TLine>}
      %Equal.sym(List<&2, L.TLE>, L.TL.memo.again(es, ty, px, sel, L.TL.memo.make(ty, old, px, sel)), L.TL.memo.make(ty, es, px, sel), Laws.tl_again_exact(es, ty, old, px, sel)) : {L.TL.entries.m(ty, _, st, sel, px, pics) == L.TL.entries(ty, es, st, sel, px, pics) : List<&2, L.TLine>}
      tl_entries_memo(ty, es, st, sel, px, pics)

def Laws.tl_lines_exact(ty, es, old, px0, sel0, st, sel, px, pics):
  tl_lines_k(Bool.and(U32.is_eq(px0, px), Q.Eq.str(sel0, sel)), ty, es, old, px0, sel0, st, sel, px, pics, {==})
def Laws.link_no_script(s):
  {==}

def Laws.link_no_file(s):
  {==}

def Laws.link_plain_line(s):
  {==}

# Image lightbox
# --------------

# a is at most a
law le_refl:
  for a: Nat
  {Nat.is_le(a, a) == True{} : Bool}

def le_refl(a):
  match a:
    case 0n:
      {==}
    case 1n+p:
      le_refl(p)

# not a >= b means b >= a
law ge_flip:
  for a: Nat
  for b: Nat
  for h: {Nat.is_ge(a, b) == False{} : Bool}
  {Nat.is_ge(b, a) == True{} : Bool}

def ge_flip(a, b, h):
  match a b:
    case 0n 0n:
      Empty.absurd({Nat.is_ge(0n, 0n) == True{} : Bool}, false_ne_true(Equal.sym(Bool, True{}, False{}, h)))
    case 0n 1n+q:
      {==}
    case 1n+p 0n:
      Empty.absurd({Nat.is_ge(0n, 1n+p) == True{} : Bool}, false_ne_true(Equal.sym(Bool, True{}, False{}, h)))
    case 1n+p 1n+q:
      ge_flip(p, q, h)

# either of two numbers at most hi is at most hi
law pick_le:
  for c: Bool
  for a: Nat
  for b: Nat
  for -hi: Nat
  for ha: {Nat.is_le(a, hi) == True{} : Bool}
  for hb: {Nat.is_le(b, hi) == True{} : Bool}
  {Nat.is_le(Bool.pick(Nat, c, a, b), hi) == True{} : Bool}

def pick_le(c, a, b, hi, ha, hb):
  match c:
    case True{}:
      ha
    case False{}:
      hb

law min_le_k:
  for c: Bool
  for +a: Nat
  for +b: Nat
  for h: {Nat.is_le(a, b) == c : Bool}
  {Nat.is_le(Bool.pick(Nat, c, a, b), b) == True{} : Bool}

def min_le_k(c, a, b, h):
  match c:
    case True{}:
      h
    case False{}:
      le_refl(b)

# the lesser of a and b is at most b
law lb_min_le:
  for +a: Nat
  for +b: Nat
  {Nat.is_le(LBX.Lb.min(a, b), b) == True{} : Bool}

def lb_min_le(a, b):
  min_le_k(Nat.is_le(a, b), a, b, {==})

law max_ge_k:
  for c: Bool
  for +a: Nat
  for +b: Nat
  for h: {Nat.is_ge(a, b) == c : Bool}
  {Nat.is_ge(Bool.pick(Nat, c, a, b), a) == True{} : Bool}

def max_ge_k(c, a, b, h):
  match c:
    case True{}:
      Nat.ge_refl(a)
    case False{}:
      ge_flip(a, b, h)

# the greater of a and b is at least a
law lb_max_ge:
  for +a: Nat
  for +b: Nat
  {Nat.is_ge(LBX.Lb.max(a, b), a) == True{} : Bool}

def lb_max_ge(a, b):
  max_ge_k(Nat.is_ge(a, b), a, b, {==})

def Laws.lightbox_zoom_min(z):
  lb_max_ge(LBX.Lb.zmin(), LBX.Lb.min(z, LBX.Lb.zmax()))

def Laws.lightbox_zoom_max(z):
  pick_le(Nat.is_ge(LBX.Lb.zmin(), LBX.Lb.min(z, LBX.Lb.zmax())), LBX.Lb.zmin(), LBX.Lb.min(z, LBX.Lb.zmax()), LBX.Lb.zmax(), {==}, lb_min_le(z, LBX.Lb.zmax()))

def Laws.lightbox_scroll_max(a, m, d, v):
  lb_min_le(Nat.sub(Nat.add(Nat.div(Nat.mul(Nat.mul(a, d), LBX.Lb.sub()), LBX.Lb.one()), Nat.mul(Nat.add(LBX.Lb.pad(d, v), LBX.Lb.bias()), LBX.Lb.sub())),
    Nat.mul(Nat.add(m, Nat.div(v, 2n)), LBX.Lb.sub())), Nat.mul(Nat.sub(d, v), LBX.Lb.sub()))

def Laws.lightbox_ease_start(z0, z1, t0):
  %Equal.sym(Bool, Nat.is_ge(t0, Nat.add(t0, LBX.Lb.ms())), False{}, ge_past(t0, 179n))
    : {LBX.Lb.ease(_, Nat.sub(t0, t0), z0, z1) == z0 : Nat}
  %Equal.sym(Nat, Nat.sub(t0, t0), 0n, sub_self(t0)) : {LBX.Lb.ease(False{}, _, z0, z1) == z0 : Nat}
  {==}

def Laws.lightbox_ease_done(z0, z1, t0, k):
  %Equal.sym(Bool, Nat.is_ge(Nat.add(Nat.add(t0, LBX.Lb.ms()), k), Nat.add(t0, LBX.Lb.ms())), True{},
    ge_add(Nat.add(t0, LBX.Lb.ms()), Nat.add(t0, LBX.Lb.ms()), k, Nat.ge_refl(Nat.add(t0, LBX.Lb.ms()))))
    : {LBX.Lb.ease(_, Nat.sub(Nat.add(Nat.add(t0, LBX.Lb.ms()), k), t0), z0, z1) == z1 : Nat}
  {==}

def Laws.lightbox_idle(t0, k):
  %Equal.sym(Bool, Nat.is_ge(Nat.add(Nat.add(t0, LBX.Lb.ms()), k), Nat.add(t0, LBX.Lb.ms())), True{},
    ge_add(Nat.add(t0, LBX.Lb.ms()), Nat.add(t0, LBX.Lb.ms()), k, Nat.ge_refl(Nat.add(t0, LBX.Lb.ms()))))
    : {Bool.not(_) == False{} : Bool}
  {==}

def Laws.lightbox_opens_still(now):
  {==}

def Laws.svg_close_returns(p):
  match p:
    case SVG.Pen{x, y, sx, sy, cx, cy, ck}:
      {==}

def Laws.svg_move_starts(p, x, y):
  match p:
    case SVG.Pen{a, b, c, d, e, f, g}:
      {==}

def Laws.svg_absolute_ignores_pen(p, v):
  {==}

def Laws.svg_implicit_lineto():
  {==}

def Laws.svg_numbers_split():
  {==}

def Laws.icons_used_exist():
  {==}

def Laws.icons_all_draw():
  {==}

def Laws.hotkey_alt_digit():
  {==}

def Laws.hotkey_ctrl_digit():
  {==}

def Laws.hint_alt_starts(h, mods):
  {==}

def Laws.hint_missed_release_ends():
  {==}

def Laws.wrap_keeps_last_space():
  {==}

def Laws.edit_select_all():
  {==}

def Laws.edit_type_replaces():
  {==}

def Laws.delete_asks_first(u):
  {==}

def Laws.row_delete_asks_first(u, id):
  {==}

def Laws.row_toggle_unsettles(t, at, h):
  %Equal.sym(M.Shelf, M.Shelf.of(M.Thread.settled(True{}, at, t)), M.Settled{}, Laws.merge_settles(t, at, h)) : {U.Ui.row_toggle.m(_) == "thread.unsettle" : String}
  {==}

def Laws.row_toggle_settles(at, t):
  match t:
    case M.Thread{id, p, ti, c, a, tu, pe, ar, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, True{}}:
      {==}
    case M.Thread{id, p, ti, c, a, tu, pe, True{}, o, sa, ua, pi, en, br, wt, pr, mo, rm, im, se, False{}}:
      {==}
    case M.Thread{id, p, ti, c, a, tu, pe, False{}, o, sa, ua, True{}, en, br, wt, pr, mo, rm, im, se, False{}}:
      {==}
    case M.Thread{id, p, ti, c, a, tu, pe, False{}, o, sa, ua, False{}, en, br, wt, pr, mo, rm, im, se, False{}}:
      {==}

def Laws.picker_drops_stale(u, o):
  {==}

def Laws.tl_frame_exact(ty, es, old, px0, sel0, st, sel, px, pics):
  %Equal.sym(L.TLMemo, L.TL.memo.of(ty, es, px, sel, L.TLMemo{px0, sel0, L.TL.memo.make(ty, old, px0, sel0)}), L.TLMemo{px, sel, L.TL.memo.make(ty, es, px, sel)},
    Laws.tl_memo_exact(ty, es, old, px0, sel0, px, sel))
    : {L.TL.memo.shown(ty, _, st, sel, px, pics) == L.TL.entries(ty, es, st, sel, px, pics) : List<&2, L.TLine>}
  tl_entries_memo(ty, es, st, sel, px, pics)

# Tool calls folded
# -----------------

law fold_flat_push:
  for b: Bool
  for +e: M.Entry
  for gs: List<&2, FO.Grp>
  {FO.Fold.flat(FO.Fold.push.k(b, e, gs)) == e <> FO.Fold.flat(gs) : List<&2, M.Entry>}

def fold_flat_push(b, e, gs):
  match b:
    case False{}:
      {==}
    case True{}:
      match gs:
        case Nil{}:
          {==}
        case +g <> +t:
          match g:
            case FO.GOne{+x}:
              {==}
            case FO.GRun{+xs}:
              {==}

def Laws.fold_keeps_entries(es):
  match es:
    case Nil{}:
      {==}
    case +e <> +t:
      Equal.trans(List<&2, M.Entry>, FO.Fold.flat(FO.Fold.push.k(FO.Fold.tool(e), e, FO.Fold.groups(t))), e <> FO.Fold.flat(FO.Fold.groups(t)), e <> t,
        fold_flat_push(FO.Fold.tool(e), e, FO.Fold.groups(t)),
        Equal.cong(List<&2, M.Entry>, List<&2, M.Entry>, x => e <> x, FO.Fold.flat(FO.Fold.groups(t)), t, Laws.fold_keeps_entries(t)))

def Laws.fold_count(es):
  %Equal.sym(List<&2, M.Entry>, FO.Fold.flat(FO.Fold.groups(es)), es, Laws.fold_keeps_entries(es))
    : {List.length(&2, M.Entry, _) == List.length(&2, M.Entry, es) : Nat}
  {==}

law fold_runs_push:
  for b: Bool
  for +e: M.Entry
  for gs: List<&2, FO.Grp>
  for h: {FO.Fold.tool(e) == b : Bool}
  for ih: {FO.Fold.all(FO.Fold.runs(gs)) == True{} : Bool}
  {FO.Fold.all(FO.Fold.runs(FO.Fold.push.k(b, e, gs))) == True{} : Bool}

def fold_runs_push(b, e, gs, h, ih):
  match b:
    case False{}:
      ih
    case True{}:
      match gs:
        case Nil{}:
          %Equal.sym(Bool, FO.Fold.tool(e), True{}, h) : {FO.Fold.all.and(_, True{}) == True{} : Bool}
          {==}
        case +g <> +t:
          match g:
            case FO.GOne{+x}:
              %Equal.sym(Bool, FO.Fold.tool(e), True{}, h) : {FO.Fold.all.and(_, FO.Fold.all(FO.Fold.runs(t))) == True{} : Bool}
              ih
            case FO.GRun{+xs}:
              %Equal.sym(Bool, FO.Fold.tool(e), True{}, h) : {FO.Fold.all.and(_, FO.Fold.all(List.append(&2, M.Entry, xs, FO.Fold.runs(t)))) == True{} : Bool}
              ih

def Laws.fold_runs_only_tools(es):
  match es:
    case Nil{}:
      {==}
    case +e <> +t:
      fold_runs_push(FO.Fold.tool(e), e, FO.Fold.groups(t), {==}, Laws.fold_runs_only_tools(t))

def Laws.fold_never_error(i, t, k, s, a):
  {==}

def Laws.fold_never_message(i, t, r, x, a):
  {==}

def Laws.fold_user_opened(live):
  {==}

def Laws.fold_user_shut(live):
  {==}

def Laws.fold_default_live(live):
  {==}

def Laws.hub_frames_cbor(t):
  {==}

def Laws.hub_plot_frames_binary(s):
  {==}

# The phones' board viewer
# ------------------------

law eq_chunk_k_sound:
  for s: Bool
  for a: PL.Chunk
  for b: PL.Chunk
  for hs: {PL.Eq.sig(a, b) == s : Bool}
  for +h: {PL.Eq.chunk.k(s, a, b) == True{} : Bool}
  {a == b : PL.Chunk}

def eq_chunk_k_sound(s, a, b, hs, h):
  match s:
    case False{}:
      Empty.absurd({a == b : PL.Chunk}, false_ne_true(h))
    case True{}:
      match a b:
        case PL.Chunk{+s1, +l1, +c1, +a1, +m1, +w1, +d1, +i1} PL.Chunk{+s2, +l2, +c2, +a2, +m2, +w2, +d2, +i2}:
          +r6 = Bool.and(Q.Eq.str(d1, d2), Q.Eq.str(i1, i2))
          +r5 = Bool.and(U32.is_eq(w1, w2), r6)
          +r4 = Bool.and(U32.is_eq(m1, m2), r5)
          +r3 = Bool.and(U32.is_eq(a1, a2), r4)
          +r2 = Bool.and(U32.is_eq(c1, c2), r3)
          +h1 = and_r(U32.is_eq(l1, l2), r2, h)
          +h2 = and_r(U32.is_eq(c1, c2), r3, h1)
          +h3 = and_r(U32.is_eq(a1, a2), r4, h2)
          +h4 = and_r(U32.is_eq(m1, m2), r5, h3)
          +h5 = and_r(U32.is_eq(w1, w2), r6, h4)
          e0 = u32_eq_sound(s1, s2, hs)
          el = u32_eq_sound(l1, l2, and_l(U32.is_eq(l1, l2), r2, h))
          ec = u32_eq_sound(c1, c2, and_l(U32.is_eq(c1, c2), r3, h1))
          ea = u32_eq_sound(a1, a2, and_l(U32.is_eq(a1, a2), r4, h2))
          em = u32_eq_sound(m1, m2, and_l(U32.is_eq(m1, m2), r5, h3))
          ew = u32_eq_sound(w1, w2, and_l(U32.is_eq(w1, w2), r6, h4))
          ed = eq_str_sound(d1, d2, and_l(Q.Eq.str(d1, d2), Q.Eq.str(i1, i2), h5))
          ei = eq_str_sound(i1, i2, and_r(Q.Eq.str(d1, d2), Q.Eq.str(i1, i2), h5))
          %e0 : {PL.Chunk{s1, l1, c1, a1, m1, w1, d1, i1} == PL.Chunk{_, l2, c2, a2, m2, w2, d2, i2} : PL.Chunk}
          %el : {PL.Chunk{s1, l1, c1, a1, m1, w1, d1, i1} == PL.Chunk{s1, _, c2, a2, m2, w2, d2, i2} : PL.Chunk}
          %ec : {PL.Chunk{s1, l1, c1, a1, m1, w1, d1, i1} == PL.Chunk{s1, l1, _, a2, m2, w2, d2, i2} : PL.Chunk}
          %ea : {PL.Chunk{s1, l1, c1, a1, m1, w1, d1, i1} == PL.Chunk{s1, l1, c1, _, m2, w2, d2, i2} : PL.Chunk}
          %em : {PL.Chunk{s1, l1, c1, a1, m1, w1, d1, i1} == PL.Chunk{s1, l1, c1, a1, _, w2, d2, i2} : PL.Chunk}
          %ew : {PL.Chunk{s1, l1, c1, a1, m1, w1, d1, i1} == PL.Chunk{s1, l1, c1, a1, m1, _, d2, i2} : PL.Chunk}
          %ed : {PL.Chunk{s1, l1, c1, a1, m1, w1, d1, i1} == PL.Chunk{s1, l1, c1, a1, m1, w1, _, i2} : PL.Chunk}
          %ei : {PL.Chunk{s1, l1, c1, a1, m1, w1, d1, i1} == PL.Chunk{s1, l1, c1, a1, m1, w1, d1, _} : PL.Chunk}
          {==}

# chunks compared equal are equal
law eq_chunk_sound:
  for a: PL.Chunk
  for b: PL.Chunk
  for h: {PL.Eq.chunk(a, b) == True{} : Bool}
  {a == b : PL.Chunk}

def eq_chunk_sound(a, b, h):
  match a b:
    case PL.Chunk{+s1, l1, c1, a1, m1, w1, d1, i1} PL.Chunk{+s2, l2, c2, a2, m2, w2, d2, i2}:
      eq_chunk_k_sound(U32.is_eq(s1, s2), PL.Chunk{s1, l1, c1, a1, m1, w1, d1, i1}, PL.Chunk{s2, l2, c2, a2, m2, w2, d2, i2}, {==}, h)

law eq_chunk_refl:
  for +x: PL.Chunk
  {PL.Eq.chunk(x, x) == True{} : Bool}

def eq_chunk_refl(x):
  match x:
    case PL.Chunk{+s, +l, +c, +a, +m, +w, +d, +i}:
      %Equal.sym(Bool, U32.is_eq(s, s), True{}, u32_eq_refl(s)) : {PL.Eq.chunk.k(_, PL.Chunk{s, l, c, a, m, w, d, i}, PL.Chunk{s, l, c, a, m, w, d, i}) == True{} : Bool}
      %Equal.sym(Bool, U32.is_eq(l, l), True{}, u32_eq_refl(l)) : {Bool.and(_, Bool.and(U32.is_eq(c, c), Bool.and(U32.is_eq(a, a), Bool.and(U32.is_eq(m, m), Bool.and(U32.is_eq(w, w), Bool.and(Q.Eq.str(d, d), Q.Eq.str(i, i))))))) == True{} : Bool}
      %Equal.sym(Bool, U32.is_eq(c, c), True{}, u32_eq_refl(c)) : {Bool.and(_, Bool.and(U32.is_eq(a, a), Bool.and(U32.is_eq(m, m), Bool.and(U32.is_eq(w, w), Bool.and(Q.Eq.str(d, d), Q.Eq.str(i, i)))))) == True{} : Bool}
      %Equal.sym(Bool, U32.is_eq(a, a), True{}, u32_eq_refl(a)) : {Bool.and(_, Bool.and(U32.is_eq(m, m), Bool.and(U32.is_eq(w, w), Bool.and(Q.Eq.str(d, d), Q.Eq.str(i, i))))) == True{} : Bool}
      %Equal.sym(Bool, U32.is_eq(m, m), True{}, u32_eq_refl(m)) : {Bool.and(_, Bool.and(U32.is_eq(w, w), Bool.and(Q.Eq.str(d, d), Q.Eq.str(i, i)))) == True{} : Bool}
      %Equal.sym(Bool, U32.is_eq(w, w), True{}, u32_eq_refl(w)) : {Bool.and(_, Bool.and(Q.Eq.str(d, d), Q.Eq.str(i, i))) == True{} : Bool}
      %Equal.sym(Bool, Q.Eq.str(d, d), True{}, eq_str_refl(d)) : {Bool.and(_, Q.Eq.str(i, i)) == True{} : Bool}
      eq_str_refl(i)

law ref_next_get:
  for r: PL.Ref
  for +o: PL.Chunk
  for +ot: List<&2, PL.Chunk>
  {PL.Ref.get(PL.Ref.next(r), o <> ot) == PL.Ref.get(r, ot) : PL.Chunk}

def ref_next_get(r, o, ot):
  match r:
    case PL.Keep{i}:
      {==}
    case PL.Fresh{c}:
      {==}

law ref_next_fresh:
  for r: PL.Ref
  {PL.Ref.fresh(PL.Ref.next(r)) == PL.Ref.fresh(r) : Nat}

def ref_next_fresh(r):
  match r:
    case PL.Keep{i}:
      {==}
    case PL.Fresh{c}:
      {==}

# the chunk a phone looks up for c is c
law plot_find_get_k:
  for os: List<&2, PL.Chunk>
  for s: Bool
  for +c: PL.Chunk
  for h: {PL.Plot.hit(os, c) == s : Bool}
  {PL.Ref.get(PL.Plot.find(os, s, c), os) == c : PL.Chunk}

def plot_find_get_k(os, s, c, h):
  match os:
    case Nil{}:
      {==}
    case +o <> +ot:
      match s:
        case True{}:
          Equal.sym(PL.Chunk, c, o, eq_chunk_sound(c, o, h))
        case False{}:
          Equal.trans(PL.Chunk, PL.Ref.get(PL.Ref.next(PL.Plot.find(ot, PL.Plot.hit(ot, c), c)), o <> ot), PL.Ref.get(PL.Plot.find(ot, PL.Plot.hit(ot, c), c), ot), c,
            ref_next_get(PL.Plot.find(ot, PL.Plot.hit(ot, c), c), o, ot), plot_find_get_k(ot, PL.Plot.hit(ot, c), c, {==}))

def Laws.plot_delta_exact(ns, old):
  match ns:
    case Nil{}:
      {==}
    case +n <> +t:
      e1 = Equal.sym(PL.Chunk, PL.Ref.get(PL.Plot.find(old, PL.Plot.hit(old, n), n), old), n, plot_find_get_k(old, PL.Plot.hit(old, n), n, {==}))
      e2 = Equal.sym(List<&2, PL.Chunk>, PL.Plot.apply(PL.Plot.delta(t, old), old), t, Laws.plot_delta_exact(t, old))
      %e1 : {_ <> PL.Plot.apply(PL.Plot.delta(t, old), old) == n <> t : List<&2, PL.Chunk>}
      %e2 : {n <> _ == n <> t : List<&2, PL.Chunk>}
      {==}

law append_snoc:
  for pre: List<&2, PL.Chunk>
  for +x: PL.Chunk
  for +t: List<&2, PL.Chunk>
  {List.append(&2, PL.Chunk, pre, x <> t) == List.append(&2, PL.Chunk, List.append(&2, PL.Chunk, pre, [x]), t) : List<&2, PL.Chunk>}

def append_snoc(pre, x, t):
  match pre:
    case Nil{}:
      {==}
    case +p <> +pt:
      Equal.cong(List<&2, PL.Chunk>, List<&2, PL.Chunk>, l => p <> l, List.append(&2, PL.Chunk, pt, x <> t),
        List.append(&2, PL.Chunk, List.append(&2, PL.Chunk, pt, [x]), t), append_snoc(pt, x, t))

# a chunk the phone holds (somewhere after pre) is found, so kept
law plot_find_keeps_k:
  for pre: List<&2, PL.Chunk>
  for s: Bool
  for +x: PL.Chunk
  for +t: List<&2, PL.Chunk>
  for h: {PL.Plot.hit(List.append(&2, PL.Chunk, pre, x <> t), x) == s : Bool}
  {PL.Ref.fresh(PL.Plot.find(List.append(&2, PL.Chunk, pre, x <> t), s, x)) == 0n : Nat}

def plot_find_keeps_k(pre, s, x, t, h):
  match pre:
    case Nil{}:
      match s:
        case True{}:
          {==}
        case False{}:
          Empty.absurd({PL.Ref.fresh(PL.Ref.next(PL.Plot.find(t, PL.Plot.hit(t, x), x))) == 0n : Nat}, false_ne_true(Equal.trans(Bool, False{}, PL.Eq.chunk(x, x), True{}, Equal.sym(Bool, PL.Eq.chunk(x, x), False{}, h), eq_chunk_refl(x))))
    case +p <> +pt:
      match s:
        case True{}:
          {==}
        case False{}:
          Equal.trans(Nat, PL.Ref.fresh(PL.Ref.next(PL.Plot.find(List.append(&2, PL.Chunk, pt, x <> t), PL.Plot.hit(List.append(&2, PL.Chunk, pt, x <> t), x), x))),
            PL.Ref.fresh(PL.Plot.find(List.append(&2, PL.Chunk, pt, x <> t), PL.Plot.hit(List.append(&2, PL.Chunk, pt, x <> t), x), x)), 0n,
            ref_next_fresh(PL.Plot.find(List.append(&2, PL.Chunk, pt, x <> t), PL.Plot.hit(List.append(&2, PL.Chunk, pt, x <> t), x), x)),
            plot_find_keeps_k(pt, PL.Plot.hit(List.append(&2, PL.Chunk, pt, x <> t), x), x, t, {==}))

# every chunk of xs is kept by a phone holding pre ++ xs
law plot_kept_all:
  for xs: List<&2, PL.Chunk>
  for +pre: List<&2, PL.Chunk>
  {PL.Plot.fresh(PL.Plot.delta(xs, List.append(&2, PL.Chunk, pre, xs))) == 0n : Nat}

def plot_kept_all(xs, pre):
  match xs:
    case Nil{}:
      {==}
    case +x <> +t:
      ef = Equal.sym(Nat, PL.Ref.fresh(PL.Plot.find(List.append(&2, PL.Chunk, pre, x <> t), PL.Plot.hit(List.append(&2, PL.Chunk, pre, x <> t), x), x)), 0n,
        plot_find_keeps_k(pre, PL.Plot.hit(List.append(&2, PL.Chunk, pre, x <> t), x), x, t, {==}))
      ea = Equal.sym(List<&2, PL.Chunk>, List.append(&2, PL.Chunk, pre, x <> t), List.append(&2, PL.Chunk, List.append(&2, PL.Chunk, pre, [x]), t), append_snoc(pre, x, t))
      %ef : {Nat.add(_, PL.Plot.fresh(PL.Plot.delta(t, List.append(&2, PL.Chunk, pre, x <> t)))) == 0n : Nat}
      %ea : {PL.Plot.fresh(PL.Plot.delta(t, _)) == 0n : Nat}
      plot_kept_all(t, List.append(&2, PL.Chunk, pre, [x]))

def Laws.plot_unchanged_sends_nothing(cs):
  plot_kept_all(cs, Nil{})

def Laws.plot_hidden_not_sent(key, sig, layer, p, info, kind, acc, h):
  %Equal.sym(U32, PL.Piece.alpha(kind, layer), 0, h) : {PL.Piece.put.k(PL.Piece.shown(_), B.Item{key, sig, layer, p, info}, acc) == acc : List<&2, PL.Piece>}
  {==}

def Laws.plot_courtyard_hidden():
  {==}

def Laws.plot_numbers_exact():
  {==}

def Laws.view_closed_wants_nothing(root):
  match root:
    case SNil{}:
      {==}
    case SCon{h, t}:
      {==}

def Laws.view_asks_once(u, cmds, h):
  %Equal.sym(Bool, String.eq(MV.View.want(u), U.Ui.scratch(u, "@view.at")), True{}, h) : {MV.View.sync.k(_, u, MV.View.want(u), MV.View.kind(u), U.Ui.root(u), cmds) == U.Act{u, cmds} : U.Act}
  {==}

def Laws.plot_frames_binary(bs):
  {==}

def Laws.pick_nothing_there(u):
  {==}

def Laws.pick_late_ignored(u, o, h):
  %Equal.sym(Bool, String.is_empty(U.Ui.scratch(u, "@pick.rid")), True{}, h) : {MV.View.picked.k(Bool.and(Bool.and(Bool.not(_), String.eq(J.Json.as_raw(J.Json.get(o, "id"), ""), U.Ui.scratch(u, "@pick.rid"))), String.eq(J.Json.get_str(o, "t", ""), "reply")), u, o) == u : U.Ui}
  {==}

def Laws.pick_pad_over_zone():
  {==}

def Laws.pick_pad_over_zone_after():
  {==}

def Laws.pick_top_on_tie():
  {==}

def Laws.view_3d_draws_board(root):
  {==}

def Laws.view_3d_key():
  {==}
