import Base

# GitHub CLI accounts. gh keeps several accounts per host, one of them
# active. Backplane never switches the active account: each gh call (and a
# push through gh's credential helper) gets the chosen account's token in
# its own environment. Which account: the one this repository worked with
# before (git config backplane.ghuser, which a user may set), else the
# account named like the remote's owner, else the active one; the others
# follow, tried only when GitHub refuses the call as unauthorized (laws
# gh_*). Pure: src/server/gh.bend runs gh.

type GhAcct is Data:
  GhAcct{user: String, active: Bool}

type GhRemote is Data:
  GhRemote{host: String, owner: String}

# Remotes
# -------

def Gh.words(+s: String) -> List<&2, String>:
  List.filter(~String, ~(w => Bool.not(String.is_empty(w))), String.split(s, ' '))

def Gh.remote.parts(ps: List<&2, String>) -> GhRemote:
  match ps:
    case +h <> +o <> _ <> _:
      GhRemote{h, o}
    case _:
      GhRemote{"", ""}

# "host/owner/repo..." (a scheme and any user@ already dropped)
def Gh.remote.path(+s: String) -> GhRemote:
  Gh.remote.parts(String.split(s, '/'))

def Gh.remote.user(+s: String) -> String:
  Maybe.default(&2, String, List.last(&2, String, String.split(s, '@')), "")

def Gh.remote.scp.k(ps: List<&2, String>) -> GhRemote:
  match ps:
    case +h <> +rest <> Nil{}:
      Gh.remote.path(Gh.remote.user(h) ++ "/" ++ rest)
    case _:
      GhRemote{"", ""}

def Gh.remote.host.k(ps: List<&2, String>, +rest: String) -> String:
  match ps:
    case +h <> _:
      h ++ rest
    case Nil{}:
      rest

def Gh.remote.slash.k(ps: List<&2, String>) -> String:
  match ps:
    case +h <> +t:
      Gh.remote.host.k(String.split(h, ':'), "/" ++ String.join(t, "/"))
    case Nil{}:
      ""

# "host:port/owner/repo" -> "host/owner/repo"
def Gh.remote.host_port(+s: String) -> String:
  Gh.remote.slash.k(String.split(s, '/'))

# a remote url's host and owner: https://host/owner/repo(.git),
# ssh://git@host[:port]/owner/repo, git@host:owner/repo. ("", "") when
# it is none of these (a path, a file:// url)
def Gh.remote(+url: String) -> GhRemote:
  Bool.pick(GhRemote, String.starts_with(url, "https://"), Gh.remote.path(Gh.remote.user(String.drop(url, 8n))),
    Bool.pick(GhRemote, String.starts_with(url, "http://"), Gh.remote.path(Gh.remote.user(String.drop(url, 7n))),
      Bool.pick(GhRemote, String.starts_with(url, "ssh://"), Gh.remote.path(Gh.remote.host_port(Gh.remote.user(String.drop(url, 6n)))),
        Bool.pick(GhRemote, Bool.or(String.contains(url, "://"), Bool.not(String.contains(url, ":"))), GhRemote{"", ""},
          Gh.remote.scp.k(String.split(url, ':'))))))

def Gh.remote.host(r: GhRemote) -> String:
  match r:
    case GhRemote{h, _}:
      h

def Gh.remote.owner(r: GhRemote) -> String:
  match r:
    case GhRemote{_, o}:
      o

# Accounts
# --------
# `gh auth status --hostname H` prints one block per account:
#   ✓ Logged in to github.com account alice (keyring)
#   - Active account: true
# and gh before 2.40 prints one account: "Logged in to github.com as alice".
# An account gh failed to log in with is not listed. Another host's
# accounts are read as blanks (so their "Active account" lines land on
# them) and dropped.

def Gh.acct.of(ws: List<&2, String>, +host: String) -> List<&2, GhAcct>:
  match ws:
    case "Logged" <> "in" <> "to" <> +h <> "account" <> +u <> _:
      [GhAcct{Bool.pick(String, String.eq(h, host), u, ""), False{}}]
    case "Logged" <> "in" <> "to" <> +h <> "as" <> +u <> _:
      [GhAcct{Bool.pick(String, String.eq(h, host), u, ""), True{}}]
    case _ <> +t:
      Gh.acct.of(t, host)
    case Nil{}:
      Nil{}

def Gh.acct.activate(acc: List<&2, GhAcct>) -> List<&2, GhAcct>:
  match acc:
    case GhAcct{u, _} <> t:
      GhAcct{u, True{}} <> t
    case Nil{}:
      Nil{}

def Gh.acct.line(+l: String, +host: String, +acc: List<&2, GhAcct>) -> List<&2, GhAcct>:
  Bool.pick(List<&2, GhAcct>, String.contains(l, "Active account: true"), Gh.acct.activate(acc),
    List.append(&2, GhAcct, Gh.acct.of(Gh.words(l), host), acc))

def Gh.named(as: List<&2, GhAcct>) -> List<&2, GhAcct>:
  match as:
    case Nil{}:
      Nil{}
    case GhAcct{+u, a} <> +t:
      Bool.pick(List<&2, GhAcct>, String.is_empty(u), Gh.named(t), GhAcct{u, a} <> Gh.named(t))

def Gh.accounts.go(ls: List<&2, String>, +host: String, acc: List<&2, GhAcct>) -> List<&2, GhAcct>:
  match ls:
    case Nil{}:
      Gh.named(List.reverse(&2, GhAcct, acc))
    case +l <> t:
      Gh.accounts.go(t, host, Gh.acct.line(l, host, acc))

# the accounts gh is logged in with on a host, in its order
def Gh.accounts(+text: String, +host: String) -> List<&2, GhAcct>:
  Gh.accounts.go(String.lines(text), host, Nil{})

def Gh.users(as: List<&2, GhAcct>) -> List<&2, String>:
  match as:
    case Nil{}:
      Nil{}
    case GhAcct{u, _} <> t:
      u <> Gh.users(t)

def Gh.active(as: List<&2, GhAcct>) -> String:
  match as:
    case Nil{}:
      ""
    case GhAcct{+u, a} <> t:
      Bool.pick(String, a, u, Gh.active(t))

def Gh.has(us: List<&2, String>, +u: String) -> Bool:
  match us:
    case Nil{}:
      False{}
    case +h <> t:
      Bool.or(String.eq(h, u), Gh.has(t, u))

# Choosing
# --------

def Gh.pick.o(owner_in: Bool, +owner: String, +active: String) -> String:
  match owner_in:
    case True{}:
      owner
    case False{}:
      active

# the account tried first: the one remembered for the repository, else the
# one named like the owner, else the active one
def Gh.pick(saved_in: Bool, +saved: String, owner_in: Bool, +owner: String, +active: String) -> String:
  match saved_in:
    case True{}:
      saved
    case False{}:
      Gh.pick.o(owner_in, owner, active)

def Gh.without(us: List<&2, String>, +u: String) -> List<&2, String>:
  match us:
    case Nil{}:
      Nil{}
    case +h <> +t:
      Bool.pick(List<&2, String>, String.eq(h, u), Gh.without(t, u), h <> Gh.without(t, u))

# the accounts to try, in order: the first choice, then the rest
def Gh.order.k(+first: String, us: List<&2, String>) -> List<&2, String>:
  first <> Gh.without(us, first)

def Gh.order(+as: List<&2, GhAcct>, +saved: String, +owner: String) -> List<&2, String>:
  Gh.order.k(Gh.pick(Gh.has(Gh.users(as), saved), saved, Gh.has(Gh.users(as), owner), owner, Gh.active(as)), Gh.users(as))

# Refusals
# --------

def Gh.any(ms: List<&2, String>, +out: String) -> Bool:
  match ms:
    case Nil{}:
      False{}
    case +m <> t:
      Bool.or(String.contains(out, m), Gh.any(t, out))

# whether GitHub refused a gh call or a push for the account (so another
# account may do better); any other failure is the answer
def Gh.refused(+out: String) -> Bool:
  Gh.any(["HTTP 401", "HTTP 403", "HTTP 404", "Bad credentials", "Could not resolve to a Repository", "Resource not accessible",
    "must have push access", "must be a collaborator", "Authentication failed", "Permission to ", "Repository not found",
    "could not read Username", "returned error: 403", "returned error: 401"], out)

# the environment variable gh (and its credential helper) read a token from
def Gh.token_var(+host: String) -> String:
  Bool.pick(String, String.eq(host, "github.com"), "GH_TOKEN", "GH_ENTERPRISE_TOKEN")
