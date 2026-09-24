import Base
import ./sha256.bend as S
import ./utf8.bend as U

# Signed requests: webhooks and hub-to-hub peer calls (docs/bots.md).
#
#   X-Backplane-Timestamp: <unix seconds>
#   X-Backplane-Signature: sha256=<hex HMAC-SHA256(secret, ts + "." + body)>
#
# A secret is 32 random bytes, handed out as 64 hex digits. It keys our own
# signatures as those 32 bytes. GitHub (X-Hub-Signature-256) keys with the
# text pasted into its form, so there the key is the hex string's own bytes.

# how far a timestamp may sit from the hub's clock, in seconds
def Sign.window() -> Nat:
  300n

# UTF-8 bytes by a tail call per character: the text is walked from its end,
# each character's bytes put in front of what follows (bodies reach 256 KB)
def Sign.utf8.go(rs: String, acc: List<&2, U32>) -> List<&2, U32>:
  match rs:
    case SNil{}:
      acc
    case SCon{Chr{c}, t}:
      Sign.utf8.go(t, U.Utf8.put(c, acc))

def Sign.utf8(s: String) -> List<&2, U32>:
  Sign.utf8.go(String.reverse(s), Nil{})

def Sign.key.k(m: Maybe<&2, List<&2, U32>>, s: String) -> List<&2, U32>:
  match m:
    case Some{bs}:
      bs
    case None{}:
      Sign.utf8(s)

# the secret's bytes: its hex, or its text when it is not hex
def Sign.key(+secret_hex: String) -> List<&2, U32>:
  Sign.key.k(S.Hex.decode(secret_hex), secret_hex)

# the signature header's value for a body sent at ts
def Sign.header(secret_hex: String, ts: Nat, body: String) -> String:
  "sha256=" ++ S.Hex.encode(S.Hmac.sha256(Sign.key(secret_hex), Sign.utf8(Nat.show(ts) ++ "." ++ body)))

# |now - ts| <= window
def Sign.fresh(+now: Nat, +ts: Nat) -> Bool:
  Nat.is_le(Nat.add(Nat.sub(now, ts), Nat.sub(ts, now)), Sign.window())

def Sign.check.k(fresh: Bool, secret_hex: String, ts: Nat, body: String, sig: String) -> Bool:
  match fresh:
    case False{}:
      False{}
    case True{}:
      S.Ct.eq(Sign.utf8(sig), Sign.utf8(Sign.header(secret_hex, ts, body)))

# a request is genuine when it is fresh and its signature matches, compared
# in constant time
def Sign.check(secret_hex: String, +now: Nat, +ts: Nat, body: String, sig: String) -> Bool:
  Sign.check.k(Sign.fresh(now, ts), secret_hex, ts, body, sig)

# GitHub's X-Hub-Signature-256: sha256=<hex HMAC(secret, body)>, keyed with
# the secret's text (what the user pasted into GitHub), no timestamp
def Sign.github(secret_hex: String, body: String, sig: String) -> Bool:
  S.Ct.eq(Sign.utf8(sig), Sign.utf8("sha256=" ++ S.Hex.encode(S.Hmac.sha256(Sign.utf8(secret_hex), Sign.utf8(body)))))

# The Pebble Index ring's webhook (its app's INDEX_WEBHOOK_API.md, version
# 1): X-Index-Signature is the lowercase hex HMAC-SHA256, keyed with the
# secret's text as entered, of "v1\n<ts>\n<delivery>\n<trigger>\n<0|1>\n"
# followed by the raw multipart body. Stale timestamps fail like ours.
def Sign.index.bytes(+ts: Nat, delivery: String, trigger: String, test: Bool, body: String) -> List<&2, U32>:
  Sign.utf8("v1\n" ++ Nat.show(ts) ++ "\n" ++ delivery ++ "\n" ++ trigger ++ "\n" ++ Bool.pick(String, test, "1", "0") ++ "\n" ++ body)

def Sign.index.k(fresh: Bool, secret: String, ts: Nat, delivery: String, trigger: String, test: Bool, body: String, sig: String) -> Bool:
  match fresh:
    case False{}:
      False{}
    case True{}:
      S.Ct.eq(Sign.utf8(sig), Sign.utf8(S.Hex.encode(S.Hmac.sha256(Sign.utf8(secret), Sign.index.bytes(ts, delivery, trigger, test, body)))))

def Sign.index(secret: String, +now: Nat, +ts: Nat, delivery: String, trigger: String, test: Bool, body: String, sig: String) -> Bool:
  Sign.index.k(Sign.fresh(now, ts), secret, ts, delivery, trigger, test, body, sig)

# Replay cache
# ------------

# signatures (or GitHub delivery ids) accepted within the window; a key is
# accepted once
type SeenItem is Data:
  SeenItem{key: String, at: Nat}

type Seen is Data:
  Seen{items: List<&2, SeenItem>}

def Seen.empty() -> Seen:
  Seen{Nil{}}

def Seen.any(items: List<&2, SeenItem>, +key: String) -> Bool:
  match items:
    case Nil{}:
      False{}
    case SeenItem{k, at} <> t:
      Bool.or(String.eq(k, key), Seen.any(t, key))

def Seen.has(+s: Seen, +key: String) -> Bool:
  match s:
    case Seen{items}:
      Seen.any(items, key)

def Seen.keep(fresh: Bool, it: SeenItem, rest: List<&2, SeenItem>) -> List<&2, SeenItem>:
  match fresh:
    case True{}:
      it <> rest
    case False{}:
      rest

def Seen.prune(items: List<&2, SeenItem>, +now: Nat) -> List<&2, SeenItem>:
  match items:
    case Nil{}:
      Nil{}
    case SeenItem{k, +at} <> t:
      Seen.keep(Sign.fresh(now, at), SeenItem{k, at}, Seen.prune(t, now))

# remember key at now, forgetting what has left the window
def Seen.add(s: Seen, key: String, +now: Nat) -> Seen:
  match s:
    case Seen{items}:
      Seen{SeenItem{key, now} <> Seen.prune(items, now)}

# Peer invites
# ------------

# bp1:<url>:<peer id>:<secret hex>; the url has colons of its own, so the id
# and secret are the last two fields
type Inv is Data:
  Inv{url: String, id: String, secret: String}

def Invite.make(url: String, id: String, secret: String) -> String:
  "bp1:" ++ url ++ ":" ++ id ++ ":" ++ secret

def Invite.hexok(m: Maybe<&2, List<&2, U32>>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{bs}:
      True{}

def Invite.mk.k(ok: Bool, url: String, id: String, secret: String) -> Maybe<&2, Inv>:
  match ok:
    case True{}:
      Some{Inv{url, id, secret}}
    case False{}:
      None{}

def Invite.mk(+url: String, +id: String, +secret: String) -> Maybe<&2, Inv>:
  Invite.mk.k(Bool.and(Bool.not(String.is_empty(url)), Bool.and(Bool.not(String.is_empty(id)),
    Bool.and(Nat.is_eq(String.length(secret), 64n), Invite.hexok(S.Hex.decode(secret))))), url, id, secret)

# the fields last first
def Invite.fields(ps: List<&2, String>) -> Maybe<&2, Inv>:
  match ps:
    case sec <> id <> u <> us:
      Invite.mk(String.join(List.reverse(&2, String, u <> us), ":"), id, sec)
    case _:
      None{}

def Invite.parse.k(ok: Bool, s: String) -> Maybe<&2, Inv>:
  match ok:
    case True{}:
      Invite.fields(List.reverse(&2, String, String.split(String.drop(s, 4n), ':')))
    case False{}:
      None{}

# an invite as pasted (surrounding space ignored); None when malformed
def Invite.parse(s: String) -> Maybe<&2, Inv>:
  +t = String.trim(s)
  Invite.parse.k(String.starts_with(t, "bp1:"), t)
