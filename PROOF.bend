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
  %Equal.sym(Bool, H.Hub.running(H.Hub.thread(s, th)), True{}, h1) : {H.Step.outs_of(H.Hub.post.go(Bool.and(_, Bool.not(String.eq(H.Hub.provider(H.Hub.thread(s, th)), "claude"))), H.Hub.thread(s, th), H.Hub.cwd(s, H.Hub.thread(s, th)), M.Queue.of(s, th), now, th, msg, role, text)) == [] : List<&2, H.Out>}
  %Equal.sym(Bool, String.eq(H.Hub.provider(H.Hub.thread(s, th)), "claude"), False{}, h2) : {H.Step.outs_of(H.Hub.post.go(Bool.and(True{}, Bool.not(_)), H.Hub.thread(s, th), H.Hub.cwd(s, H.Hub.thread(s, th)), M.Queue.of(s, th), now, th, msg, role, text)) == [] : List<&2, H.Out>}
  {==}

def Laws.resend_stored_once(s, now, client, id, th, text, msg, h1, h2):
  %Equal.sym(Bool, String.is_empty(msg), False{}, h1) : {H.Queue.changes(H.Hub.turn.m(s, now, client, id, th, text, Bool.pick(String, _, H.Hub.id("m", now, H.Hub.seq(s)), msg), Bool.not(_))) == [] : List<&2, M.Change>}
  %Equal.sym(Bool, H.Hub.has_msg(H.Hub.entries(s), msg), True{}, h2) : {H.Queue.changes(H.Hub.turn.k(Bool.and(True{}, _), s, now, client, id, th, msg, text)) == [] : List<&2, M.Change>}
  {==}

def Laws.inbox_never_interrupts(s, now, from, to, role, text, h):
  %Equal.sym(Bool, H.Hub.running(H.Hub.thread(s, to)), True{}, h) : {H.Step.outs_of(H.Hub.post.go(_, H.Hub.thread(s, to), H.Hub.cwd(s, H.Hub.thread(s, to)), M.Queue.of(s, to), now, to, M.Link.id(from, H.Hub.id("m", now, H.Hub.seq(s))), role, text)) == [] : List<&2, H.Out>}
  {==}
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
