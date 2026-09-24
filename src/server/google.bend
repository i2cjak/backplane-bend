import Base
import ../core/google.bend as G
import ../core/json.bend as J
import ../core/utf8.bend as U
import ./host.bend as H
import ./proc.bend as P

# Gmail and Google Calendar for bots: the IO half (src/core/google.bend is
# the pure one). Secrets live in <home>/secrets/google.json (directory
# 0700, file 0600) and never leave it: requests go through `curl`, whose
# URL, headers (the bearer token) and bodies (the client secret, codes,
# refresh tokens) come from a config file (-K) and data files in that
# directory, never its command line. Base URLs can be moved for tests with
# BACKPLANE_GOOGLE_OAUTH (token and revoke endpoints) and
# BACKPLANE_GOOGLE_API (Gmail and Calendar).

# Files
# -----

def Gf.read.done(r: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(List<&2, U32>):
  (f, res) = r
  do IO<List<&2, U32>>:
    File.close(f)
    return Result.default(&1, &1, U32 & String, List<&2, U32>, res, Nil{})

def Gf.read.sized(r: File & Result<&1, &1, U32 & String, U32>) -> IO(List<&2, U32>):
  (f, res) = r
  IO.bind(File & Result<&1, &1, U32 & String, List<&2, U32>>, List<&2, U32>,
    File.read_bytes(f, U32.max(Result.default(&1, &1, U32 & String, U32, res, 0), 1)), Gf.read.done)

def Gf.read.opened(r: Result<&1, &1, U32 & String, File>) -> IO(List<&2, U32>):
  match r:
    case Done{f}:
      IO.bind(File & Result<&1, &1, U32 & String, U32>, List<&2, U32>, File.size(f), Gf.read.sized)
    case Fail{_}:
      IO.pure(List<&2, U32>, Nil{})

# a whole file as UTF-8 text, "" when it cannot be read
def Gf.text(path: String) -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    bs : List<&2, U32> <- Gf.read.opened(r)
    return U.Utf8.decode(bs)

def Gf.write.done(r: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, _) = r
  File.close(f)

def Gf.write.opened(r: Result<&1, &1, U32 & String, File>, bs: List<&2, U32>) -> IO(Unit):
  match r:
    case Done{f}:
      IO.bind(File & Result<&1, &1, U32 & String, Unit>, Unit, File.write_bytes(f, bs), Gf.write.done)
    case Fail{_}:
      IO.pure(Unit, Unit{})

# a file, mode 0600 before anything is in it, holding text as UTF-8
def Gf.write(+path: String, text: String) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "w")
    m : Result<&1, &1, U32 & String, Unit> <- H.FS.chmod(path, 384)
    Gf.write.opened(r, U.Utf8.encode(text))

def Gf.rm(path: String) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, Unit> <- H.FS.remove(path)
    return Unit{}

def Gf.env.k(r: Result<&1, &1, U32 & String, String>) -> String:
  match r:
    case Done{v}:
      v
    case Fail{_}:
      ""

def Gf.env(name: String, +d: String) -> IO(String):
  do IO<String>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env(name)
    return G.Str.or(String.trim(Gf.env.k(r)), d)

def Gf.bytes4(+x: U32, acc: List<&2, U32>) -> List<&2, U32>:
  U32.shrn(x, 24n) <> U32.and(U32.shrn(x, 16n), 255) <> U32.and(U32.shrn(x, 8n), 255) <> U32.and(x, 255) <> acc

# 4n random bytes
def Gf.rand(n: Nat, acc: List<&2, U32>) -> IO(List<&2, U32>):
  match n:
    case 0n:
      IO.pure(List<&2, U32>, acc)
    case 1n+m:
      IO.bind(U32, List<&2, U32>, IO.try(U32, IO.random_u32()), x => Gf.rand(m, Gf.bytes4(x, acc)))

# random text from 4n bytes, base64url (RFC 7636's unreserved characters)
def Gf.nonce(n: Nat) -> IO(String):
  IO.bind(List<&2, U32>, String, Gf.rand(n, Nil{}), bs => IO.pure(String, G.Gb64.encode_url(bs)))

# The secrets file
# ----------------

# client, tokens, and a sign-in in flight (its PKCE verifier, state and
# redirect); expiry in epoch seconds
type GSec is Data:
  GSec{id: String, secret: String, refresh: String, access: String, expiry: Nat, email: String, verifier: String, state: String, redirect: String}

def Gs.dir(+home: String) -> String:
  home ++ "/secrets"

def Gs.path(+home: String) -> String:
  Gs.dir(home) ++ "/google.json"

def Gs.of(+j: J.Json) -> GSec:
  GSec{J.Json.get_str(j, "client_id", ""), J.Json.get_str(j, "client_secret", ""), J.Json.get_str(j, "refresh_token", ""),
    J.Json.get_str(j, "access_token", ""), J.Json.get_nat(j, "expiry", 0n), J.Json.get_str(j, "email", ""),
    J.Json.get_str(j, "pending_verifier", ""), J.Json.get_str(j, "pending_state", ""), J.Json.get_str(j, "redirect", "")}

def Gs.show(s: GSec) -> String:
  match s:
    case GSec{id, secret, refresh, access, expiry, email, verifier, state, redirect}:
      J.Json.show(J.Json.obj([J.KV{"client_id", J.Str{id}}, J.KV{"client_secret", J.Str{secret}},
        J.KV{"refresh_token", J.Str{refresh}}, J.KV{"access_token", J.Str{access}}, J.KV{"expiry", J.Json.nat(expiry)},
        J.KV{"email", J.Str{email}}, J.KV{"pending_verifier", J.Str{verifier}}, J.KV{"pending_state", J.Str{state}},
        J.KV{"redirect", J.Str{redirect}}]))

def Gs.load(+home: String) -> IO(GSec):
  do IO<GSec>:
    t : String <- Gf.text(Gs.path(home))
    return Gs.of(Maybe.default(&2, J.Json, J.Json.parse(t), J.Null{}))

# written whole to a 0600 file beside it, then renamed over it
def Gs.save(+home: String, s: GSec) -> IO(Unit):
  do IO<Unit>:
    mk : Result<&1, &1, U32 & String, Unit> <- H.FS.mkdirs(Gs.dir(home))
    m : Result<&1, &1, U32 & String, Unit> <- H.FS.chmod(Gs.dir(home), 448)
    Gf.write(Gs.path(home) ++ ".new", Gs.show(s))
    r : Result<&1, &1, U32 & String, Unit> <- H.FS.rename(Gs.path(home) ++ ".new", Gs.path(home))
    return Unit{}

# what the UI may know: {configured, connected, email, pending}
def Gs.status(s: GSec) -> String:
  match s:
    case GSec{id, _, refresh, _, _, email, _, state, _}:
      J.Json.show(J.Json.obj([J.KV{"configured", J.Flag{Bool.not(String.is_empty(id))}},
        J.KV{"connected", J.Flag{Bool.not(String.is_empty(refresh))}}, J.KV{"email", J.Str{email}},
        J.KV{"pending", J.Flag{Bool.not(String.is_empty(state))}}]))

# HTTP through curl
# -----------------

# a value for a curl config file: quoted, \ and " escaped, controls dropped
def Gc.q.k(ctl: Bool, esc: Bool, +c: U32, rest: String) -> String:
  match ctl esc:
    case True{} _:
      rest
    case False{} True{}:
      SCon{Chr{92}, SCon{Chr{c}, rest}}
    case False{} False{}:
      SCon{Chr{c}, rest}

def Gc.q.go(s: String) -> String:
  match s:
    case SNil{}:
      "\""
    case SCon{Chr{+c}, t}:
      Gc.q.k(U32.is_lt(c, 32), Bool.or(U32.is_eq(c, 34), U32.is_eq(c, 92)), c, Gc.q.go(t))

def Gc.q(s: String) -> String:
  "\"" ++ Gc.q.go(s)

def Gc.headers(hs: List<&2, String>) -> String:
  match hs:
    case Nil{}:
      ""
    case h <> t:
      "header = " ++ Gc.q(h) ++ "\n" ++ Gc.headers(t)

def Gc.data(has: Bool, +file: String) -> String:
  match has:
    case True{}:
      "data-binary = " ++ Gc.q("@" ++ file) ++ "\n"
    case False{}:
      ""

# one request: its URL, headers, and a body file when there is a body
def Gc.config(+url: String, hs: List<&2, String>, has: Bool, +body: String, +out: String) -> String:
  "url = " ++ Gc.q(url) ++ "\n" ++ Gc.headers(hs) ++ Gc.data(has, body)
    ++ "output = " ++ Gc.q(out) ++ "\n" ++ "write-out = \"%{http_code}\"\n"

# the status curl printed last, and what it said before it (its errors)
type GResp is Data:
  GResp{code: String, body: String, err: String}

def Gc.code(+out: String) -> String:
  String.drop(String.trim(out), Nat.sub(String.length(String.trim(out)), 3n))

def Gc.said(+out: String) -> String:
  String.trim(String.take(String.trim(out), Nat.sub(String.length(String.trim(out)), 3n)))

def Gc.ran(r: P.Ran) -> String:
  match r:
    case P.Ran{_, out}:
      out

def Gc.body.put(has: Bool, +file: String, body: String) -> IO(Unit):
  match has:
    case True{}:
      Gf.write(file, body)
    case False{}:
      IO.pure(Unit, Unit{})

# a request; the body (form or JSON, as the headers say) when not ""
def Gc.req(+dir: String, +url: String, hs: List<&2, String>, +body: String) -> IO(GResp):
  do IO<GResp>:
    +name : String <- Gf.nonce(3n)
    +cfg : String = dir ++ "/g-" ++ name ++ ".curl"
    +inp : String = dir ++ "/g-" ++ name ++ ".in"
    +out : String = dir ++ "/g-" ++ name ++ ".out"
    +has : Bool = Bool.not(String.is_empty(body))
    Gc.body.put(has, inp, body)
    Gf.write(cfg, Gc.config(url, hs, has, inp, out))
    r : P.Ran <- P.Proc.run("curl", ["-sS", "--max-time", "30", "-K", cfg], dir)
    +said : String = Gc.ran(r)
    text : String <- Gf.text(out)
    Gf.rm(cfg)
    Gf.rm(inp)
    Gf.rm(out)
    return GResp{Gc.code(said), text, Gc.said(said)}

def Gc.ok(+code: String) -> Bool:
  String.starts_with(code, "2")

def Gc.why(+code: String) -> String:
  Bool.pick(String, String.eq(code, "401"), " (Google access expired or was revoked: connect Google again in Settings)", "")

# an unsuccessful answer as text for the agent
def Gc.fail(r: GResp) -> String:
  match r:
    case GResp{+code, +body, +err}:
      Bool.pick(String, Bool.or(String.eq(code, "000"), String.is_empty(body)),
        "error: could not reach Google: " ++ G.Str.or(err, "no answer"),
        "error: HTTP " ++ code ++ ": " ++ G.Google.api_error(body) ++ Gc.why(code))

def Gc.json(+s: String) -> J.Json:
  Maybe.default(&2, J.Json, J.Json.parse(s), J.Null{})

def Gc.answer.k(ok: Bool, r: GResp, f: J.Json -> String) -> String:
  match ok r:
    case True{} GResp{_, +body, _}:
      f(Gc.json(body))
    case False{} r2:
      Gc.fail(r2)

# a successful answer through f, else the error
def Gc.answer(+r: GResp, f: J.Json -> String) -> String:
  match r:
    case GResp{+code, _, _}:
      Gc.answer.k(Gc.ok(code), r, f)

# several GETs in one curl, one output file each

def Gc.outs(xs: List<&2, String>, +dir: String, +name: String, +i: Nat) -> List<&2, String>:
  match xs:
    case Nil{}:
      Nil{}
    case _ <> t:
      (dir ++ "/g-" ++ name ++ "-" ++ Nat.show(i) ++ ".out") <> Gc.outs(t, dir, name, 1n+i)

def Gc.pairs(urls: List<&2, String>, outs: List<&2, String>) -> String:
  match urls outs:
    case u <> t o <> t2:
      "url = " ++ Gc.q(u) ++ "\noutput = " ++ Gc.q(o) ++ "\n" ++ Gc.pairs(t, t2)
    case _ _:
      ""

def Gc.read_all(ps: List<&2, String>, acc: List<&2, String>) -> IO(List<&2, String>):
  match ps:
    case Nil{}:
      IO.pure(List<&2, String>, List.reverse(&2, String, acc))
    case +p <> t:
      IO.bind(String, List<&2, String>, Gf.text(p), s => IO.bind(Unit, List<&2, String>, Gf.rm(p), u => Gc.read_all(t, s <> acc)))

# the bodies of GETs to each URL, in order ("" for one that failed)
def Gc.many(+dir: String, +urls: List<&2, String>, hs: List<&2, String>) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    +name : String <- Gf.nonce(3n)
    +cfg : String = dir ++ "/g-" ++ name ++ ".curl"
    +outs : List<&2, String> = Gc.outs(urls, dir, name, 0n)
    Gf.write(cfg, Gc.headers(hs) ++ Gc.pairs(urls, outs))
    r : P.Ran <- P.Proc.run("curl", ["-sS", "--max-time", "60", "-K", cfg], dir)
    Gf.rm(cfg)
    Gc.read_all(outs, Nil{})

# Endpoints
# ---------

type GEnds is Data:
  GEnds{oauth: String, api: String}

def Ge.get() -> IO(GEnds):
  do IO<GEnds>:
    o : String <- Gf.env("BACKPLANE_GOOGLE_OAUTH", "https://oauth2.googleapis.com")
    a : String <- Gf.env("BACKPLANE_GOOGLE_API", "https://www.googleapis.com")
    return GEnds{o, a}

def Ge.token(e: GEnds) -> String:
  match e:
    case GEnds{o, _}:
      o ++ "/token"

def Ge.revoke(e: GEnds) -> String:
  match e:
    case GEnds{o, _}:
      o ++ "/revoke"

def Ge.api(e: GEnds, +path: String) -> String:
  match e:
    case GEnds{_, a}:
      a ++ path

def Gh.form() -> List<&2, String>:
  ["Content-Type: application/x-www-form-urlencoded"]

def Gh.auth(+token: String) -> List<&2, String>:
  ["Authorization: Bearer " ++ token]

def Gh.json(+token: String) -> List<&2, String>:
  ["Authorization: Bearer " ++ token, "Content-Type: application/json; charset=UTF-8"]

# Setup
# -----

def Google.status(+home: String) -> IO(String):
  IO.bind(GSec, String, Gs.load(home), s => IO.pure(String, Gs.status(s)))

def Gs.config.k(same: Bool, s: GSec, +id: String, +secret: String) -> GSec:
  match same s:
    case True{} GSec{_, _, refresh, access, expiry, email, verifier, state, redirect}:
      GSec{id, secret, refresh, access, expiry, email, verifier, state, redirect}
    case False{} _:
      GSec{id, secret, "", "", 0n, "", "", "", ""}

def Gs.configure.k(empty: Bool, +home: String, s: GSec, +id: String, +secret: String) -> IO(String):
  match empty s:
    case True{} _:
      IO.pure(String, "error: a Google OAuth client id and secret are both needed")
    case False{} GSec{+old, a, b, c, d, e, f, g, h}:
      do IO<String>:
        +s2 : GSec = Gs.config.k(String.eq(old, id), GSec{old, a, b, c, d, e, f, g, h}, id, secret)
        Gs.save(home, s2)
        return Gs.status(s2)

# the OAuth client (a Google Cloud "Desktop app" client); a different
# client forgets the tokens of the old one
def Google.configure(+home: String, client_id: String, client_secret: String) -> IO(String):
  do IO<String>:
    s : GSec <- Gs.load(home)
    +id : String = String.trim(client_id)
    +secret : String = String.trim(client_secret)
    Gs.configure.k(Bool.or(String.is_empty(id), String.is_empty(secret)), home, s, id, secret)

def Gs.challenge(+dir: String, +verifier: String) -> IO(String):
  do IO<String>:
    r : P.Ran <- P.Proc.run("sh", ["-c", "printf '%s' \"$1\" | openssl dgst -sha256 -binary | openssl base64 -A | tr '+/' '-_' | tr -d '='", "sh", verifier], dir)
    return String.trim(Gc.ran(r))

def Gs.begin.go(ok: Bool, +home: String, s: GSec, +verifier: String, +state: String, +challenge: String, +redirect: String) -> IO(String):
  match ok s:
    case False{} _:
      IO.pure(String, "error: could not make the PKCE challenge (is openssl installed?)")
    case True{} GSec{+id, secret, refresh, access, expiry, email, _, _, _}:
      do IO<String>:
        Gs.save(home, GSec{id, secret, refresh, access, expiry, email, verifier, state, redirect})
        return G.Google.auth_url(id, redirect, challenge, state, G.Google.scopes())

def Gs.begin.k(ok: Bool, +home: String, s: GSec, +redirect: String) -> IO(String):
  match ok:
    case False{}:
      IO.pure(String, "error: set the Google OAuth client id and secret first")
    case True{}:
      do IO<String>:
        mk : Result<&1, &1, U32 & String, Unit> <- H.FS.mkdirs(Gs.dir(home))
        m : Result<&1, &1, U32 & String, Unit> <- H.FS.chmod(Gs.dir(home), 448)
        +verifier : String <- Gf.nonce(12n)
        +state : String <- Gf.nonce(4n)
        +challenge : String <- Gs.challenge(Gs.dir(home), verifier)
        Gs.begin.go(Nat.is_eq(String.length(challenge), 43n), home, s, verifier, state, challenge, redirect)

def Gs.configured(s: GSec) -> Bool:
  match s:
    case GSec{id, secret, _, _, _, _, _, _, _}:
      Bool.not(Bool.or(String.is_empty(id), String.is_empty(secret)))

# starts a sign-in: keeps a fresh PKCE verifier and state, and answers the
# URL the user opens (or "error: ..."). redirect is where Google sends the
# browser back: http://127.0.0.1:<port>/oauth/google.
def Google.begin(+home: String, +redirect: String) -> IO(String):
  do IO<String>:
    +s : GSec <- Gs.load(home)
    Gs.begin.k(Gs.configured(s), home, s, redirect)

def Gs.email.k(ok: Bool, +body: String) -> String:
  match ok:
    case True{}:
      J.Json.get_str(Gc.json(body), "emailAddress", "")
    case False{}:
      ""

def Gs.email.of(r: GResp) -> String:
  match r:
    case GResp{+code, +body, _}:
      Gs.email.k(Gc.ok(code), body)

# the account's address: the id_token's, else Gmail's profile's ("" when neither)
def Gs.email(have: Bool, +dir: String, +e: GEnds, +email: String, +access: String) -> IO(String):
  match have:
    case True{}:
      IO.pure(String, email)
    case False{}:
      do IO<String>:
        r : GResp <- Gc.req(dir, Ge.api(e, G.Google.gmail_profile_path()), Gh.auth(access), "")
        return Gs.email.of(r)

def Gc.bodyof(r: GResp) -> String:
  match r:
    case GResp{_, body, _}:
      body

def Gs.finish.done(has: Bool, +home: String, s2: GSec) -> IO(String):
  match has:
    case True{}:
      do IO<String>:
        +s3 : GSec = s2
        Gs.save(home, s3)
        return Gs.status(s3)
    case False{}:
      IO.pure(String, "error: Google sent no refresh token; remove Backplane's access at https://myaccount.google.com/permissions and connect again")

def Gs.finish.keep(s: GSec, +access: String, +expiry: Nat, +refresh: String, +email: String) -> GSec:
  match s:
    case GSec{id, secret, oldr, _, _, olde, _, _, redirect}:
      GSec{id, secret, G.Str.or(refresh, oldr), access, expiry, G.Str.or(email, olde), "", "", redirect}

def Gs.linked(s: GSec) -> Bool:
  match s:
    case GSec{_, _, refresh, _, _, _, _, _, _}:
      Bool.not(String.is_empty(refresh))

def Gs.finish.tok(m: Maybe<&2, G.Tok>, +home: String, s: GSec, r: GResp, +e: GEnds) -> IO(String):
  match m:
    case None{}:
      IO.pure(String, Gc.fail(r))
    case Some{G.Tok{+access, expiry, refresh, +email}}:
      do IO<String>:
        em : String <- Gs.email(Bool.not(String.is_empty(email)), Gs.dir(home), e, email, access)
        +s2 : GSec = Gs.finish.keep(s, access, expiry, refresh, em)
        Gs.finish.done(Gs.linked(s2), home, s2)

def Gs.finish.x(ok: Bool, +home: String, s: GSec, +code: String, +verifier: String, +redirect: String) -> IO(String):
  match ok s:
    case False{} _:
      IO.pure(String, "error: this sign-in was not started here or has expired; start again")
    case True{} GSec{+id, +secret, a, b, c, d, f, g, h}:
      do IO<String>:
        +e : GEnds <- Ge.get()
        +r : GResp <- Gc.req(Gs.dir(home), Ge.token(e), Gh.form(), G.Google.code_body(id, secret, code, verifier, redirect))
        t : U32 <- H.Clock.epoch()
        Gs.finish.tok(G.Google.tokens(Gc.bodyof(r), U32.to_nat(t)), home, GSec{id, secret, a, b, c, d, f, g, h}, r, e)

def Gs.finish.k(m: Maybe<&2, G.CodeState>, +err: String, +home: String, s: GSec, +redirect: String) -> IO(String):
  match m s:
    case None{} _:
      IO.pure(String, Bool.pick(String, String.is_empty(err), "error: no authorization code in that text", "error: Google said " ++ err))
    case Some{G.CodeState{+code, +state, bare}} GSec{a, b, c, d, f, g, +verifier, +pstate, +predir}:
      Gs.finish.x(Bool.and(Bool.not(String.is_empty(verifier)), Bool.or(bare, String.eq(state, pstate))), home,
        GSec{a, b, c, d, f, g, verifier, pstate, predir}, code, verifier, G.Str.or(predir, redirect))

# ends a sign-in: text is the redirected URL (or its path and query, as
# the hub's /oauth/google route sees it, or the bare code pasted). Checks
# the state, trades the code for tokens, stores them, and answers the
# status JSON, or "error: ...".
def Google.finish(+home: String, +text: String, +redirect: String) -> IO(String):
  do IO<String>:
    s : GSec <- Gs.load(home)
    Gs.finish.k(G.Google.code_of(text), G.Google.error_of(text), home, s, redirect)

# Access tokens
# -------------

type GAccess is Data:
  GOk{token: String}
  GErr{msg: String}

def Gs.fresh(s: GSec, +now: Nat) -> Bool:
  match s:
    case GSec{_, _, _, access, expiry, _, _, _, _}:
      Bool.and(Bool.not(String.is_empty(access)), G.Google.fresh(now, expiry))

def Gs.access(s: GSec) -> String:
  match s:
    case GSec{_, _, _, access, _, _, _, _, _}:
      access

def Gs.refreshed(m: Maybe<&2, G.Tok>, +home: String, s: GSec, r: GResp) -> IO(GAccess):
  match m:
    case None{}:
      IO.pure(GAccess, GErr{Gc.fail(r) ++ " (could not refresh Google access; connect Google again in Settings if this persists)"})
    case Some{G.Tok{+access, expiry, refresh, email}}:
      do IO<GAccess>:
        Gs.save(home, Gs.finish.keep(s, access, expiry, refresh, email))
        return GOk{access}

def Gs.refresh(+home: String, s: GSec, +now: Nat) -> IO(GAccess):
  match s:
    case GSec{+id, +secret, +refresh, a, b, c, d, f, g}:
      do IO<GAccess>:
        e : GEnds <- Ge.get()
        +r : GResp <- Gc.req(Gs.dir(home), Ge.token(e), Gh.form(), G.Google.refresh_body(id, secret, refresh))
        Gs.refreshed(G.Google.tokens(Gc.bodyof(r), now), home, GSec{id, secret, refresh, a, b, c, d, f, g}, r)

def Gs.token.k(fresh: Bool, linked: Bool, +home: String, s: GSec, +now: Nat) -> IO(GAccess):
  match fresh linked:
    case True{} _:
      IO.pure(GAccess, GOk{Gs.access(s)})
    case False{} False{}:
      IO.pure(GAccess, GErr{"error: Google is not connected (connect it in Settings)"})
    case False{} True{}:
      Gs.refresh(home, s, now)

# an access token good for a minute more, refreshed (and stored) when the
# one kept is not
def Google.token(+home: String) -> IO(GAccess):
  do IO<GAccess>:
    +s : GSec <- Gs.load(home)
    t : U32 <- H.Clock.epoch()
    +now : Nat = U32.to_nat(t)
    Gs.token.k(Gs.fresh(s, now), Gs.linked(s), home, s, now)

def Gs.revoke(none: Bool, +home: String, +e: GEnds, +refresh: String) -> IO(Unit):
  match none:
    case True{}:
      IO.pure(Unit, Unit{})
    case False{}:
      do IO<Unit>:
        r : GResp <- Gc.req(Gs.dir(home), Ge.revoke(e), Gh.form(), G.Url.pair("token", refresh))
        return Unit{}

def Gs.disconnect.k(s: GSec, +home: String) -> IO(String):
  match s:
    case GSec{id, secret, +refresh, _, _, _, _, _, _}:
      do IO<String>:
        e : GEnds <- Ge.get()
        Gs.revoke(String.is_empty(refresh), home, e, refresh)
        +s2 : GSec = GSec{id, secret, "", "", 0n, "", "", "", ""}
        Gs.save(home, s2)
        return Gs.status(s2)

# revokes the refresh token (best effort) and forgets every token; the
# client id and secret stay
def Google.disconnect(+home: String) -> IO(String):
  IO.bind(GSec, String, Gs.load(home), s => Gs.disconnect.k(s, home))

# Tools
# -----

def Gt.clamp(+n: Nat, +hi: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_eq(n, 0n), 1n, Bool.pick(Nat, Nat.is_gt(n, hi), hi, n))

def Gt.urls(ids: List<&2, String>, +e: GEnds) -> List<&2, String>:
  match ids:
    case Nil{}:
      Nil{}
    case id <> t:
      Ge.api(e, G.Google.gmail_get_path(id, False{})) <> Gt.urls(t, e)

def Gt.parsed.put(m: Maybe<&2, J.Json>, +acc: List<&2, J.Json>) -> List<&2, J.Json>:
  match m:
    case Some{+j}:
      Bool.pick(List<&2, J.Json>, String.is_empty(J.Json.get_str(j, "id", "")), acc, j <> acc)
    case None{}:
      acc

def Gt.parsed(bs: List<&2, String>, acc: List<&2, J.Json>) -> List<&2, J.Json>:
  match bs:
    case Nil{}:
      List.reverse(&2, J.Json, acc)
    case b <> t:
      Gt.parsed(t, Gt.parsed.put(J.Json.parse(b), acc))

def Gt.metas(none: Bool, +ids: List<&2, String>, +tok: String, +dir: String, +e: GEnds) -> IO(String):
  match none:
    case True{}:
      IO.pure(String, "No messages.")
    case False{}:
      do IO<String>:
        bs : List<&2, String> <- Gc.many(dir, Gt.urls(ids, e), Gh.auth(tok))
        return G.Google.msg_list(Gt.parsed(bs, Nil{}))

def Gt.metas.ids(+ids: List<&2, String>, +tok: String, +dir: String, +e: GEnds) -> IO(String):
  Gt.metas(List.is_empty(&2, String, ids), ids, tok, dir, e)

def Gt.search.k(ok: Bool, r: GResp, +tok: String, +dir: String, +e: GEnds) -> IO(String):
  match ok r:
    case False{} r2:
      IO.pure(String, Gc.fail(r2))
    case True{} GResp{_, body, _}:
      Gt.metas.ids(G.Google.msg_ids(Gc.json(body)), tok, dir, e)

def Gc.okr(r: GResp) -> Bool:
  match r:
    case GResp{code, _, _}:
      Gc.ok(code)

# gmail_search {query, max}: the list, then each message's headers (one curl)
def Gt.search(+args: J.Json, +tok: String, +dir: String, +e: GEnds) -> IO(String):
  do IO<String>:
    +r : GResp <- Gc.req(dir, Ge.api(e, G.Google.gmail_search_path(J.Json.get_str(args, "query", ""), Gt.clamp(J.Json.get_nat(args, "max", 10n), 25n))), Gh.auth(tok), "")
    Gt.search.k(Gc.okr(r), r, tok, dir, e)

def Gt.need(missing: Bool, +what: String, act: IO(String)) -> IO(String):
  match missing:
    case True{}:
      IO.pure(String, "error: " ++ what ++ " is required")
    case False{}:
      act

# gmail_read {id}
def Gt.read(+args: J.Json, +tok: String, +dir: String, +e: GEnds) -> IO(String):
  +id = J.Json.get_str(args, "id", "")
  Gt.need(String.is_empty(String.trim(id)), "id",
    IO.bind(GResp, String, Gc.req(dir, Ge.api(e, G.Google.gmail_get_path(String.trim(id), True{})), Gh.auth(tok), ""),
      r => IO.pure(String, Gc.answer(r, j => G.Google.msg_full(j)))))

def Gt.sent(+j: J.Json) -> String:
  "Sent (message id " ++ J.Json.get_str(j, "id", "") ++ ", thread " ++ J.Json.get_str(j, "threadId", "") ++ ")."

# gmail_send {to, subject, body, cc?} (the hub has asked the user)
def Gt.send(+args: J.Json, +tok: String, +dir: String, +e: GEnds) -> IO(String):
  +to = String.trim(J.Json.get_str(args, "to", ""))
  Gt.need(String.is_empty(to), "to",
    IO.bind(GResp, String,
      Gc.req(dir, Ge.api(e, G.Google.gmail_send_path()), Gh.json(tok),
        G.Google.send_body(to, J.Json.get_str(args, "cc", ""), J.Json.get_str(args, "subject", ""), J.Json.get_str(args, "body", ""))),
      r => IO.pure(String, Gc.answer(r, j => Gt.sent(j)))))

# default window: from now (or the from given) for a week
def Gt.until(+from: String, +to: String, +now: Nat) -> String:
  Bool.pick(String, String.is_empty(to),
    Bool.pick(String, String.is_empty(from), G.Date.iso(Nat.add(now, 604800n)), G.Date.time(G.Date.plus_days(from, 7n))), to)

# calendar_events {from?, to?, max?, query?}
def Gt.events(+args: J.Json, +tok: String, +dir: String, +e: GEnds, +now: Nat) -> IO(String):
  +from = String.trim(J.Json.get_str(args, "from", ""))
  +to = String.trim(J.Json.get_str(args, "to", ""))
  IO.bind(GResp, String,
    Gc.req(dir, Ge.api(e, G.Google.cal_list_path(G.Str.or(from, G.Date.iso(now)), Gt.until(from, to, now),
      Gt.clamp(J.Json.get_nat(args, "max", 20n), 50n), J.Json.get_str(args, "query", ""))), Gh.auth(tok), ""),
    r => IO.pure(String, Gc.answer(r, j => G.Google.events(j))))

def Gt.strs(xs: List<&2, J.Json>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      List.reverse(&2, String, acc)
    case x <> t:
      Gt.strs(t, String.trim(J.Json.as_str(Some{x}, "")) <> acc)

def Gt.nonempty(xs: List<&2, String>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      List.reverse(&2, String, acc)
    case +x <> t:
      Gt.nonempty(t, Bool.pick(List<&2, String>, String.is_empty(String.trim(x)), acc, String.trim(x) <> acc))

# attendees as a JSON array of emails, or one comma-separated string
def Gt.people(m: Maybe<&2, J.Json>) -> List<&2, String>:
  match m:
    case Some{J.Arr{xs}}:
      Gt.nonempty(Gt.strs(J.Json.to_list(xs), Nil{}), Nil{})
    case Some{J.Str{s}}:
      Gt.nonempty(String.split(s, ','), Nil{})
    case _:
      Nil{}

# calendar_create {summary, start, end, description?, attendees?, all_day?, timeZone?}
def Gt.create(+args: J.Json, +tok: String, +dir: String, +e: GEnds) -> IO(String):
  +start = String.trim(J.Json.get_str(args, "start", ""))
  +end = String.trim(J.Json.get_str(args, "end", ""))
  +all = J.Json.get_bool(args, "all_day", False{})
  +who = Gt.people(J.Json.get(args, "attendees"))
  Gt.need(Bool.or(String.is_empty(start), Bool.and(String.is_empty(end), Bool.not(all))), "start and end",
    IO.bind(GResp, String,
      Gc.req(dir, Ge.api(e, G.Google.cal_insert_path(Bool.not(List.is_empty(&2, String, who)))), Gh.json(tok),
        G.Google.event_body(G.Str.or(J.Json.get_str(args, "summary", ""), "(no title)"), J.Json.get_str(args, "description", ""),
          start, end, who, all, String.trim(J.Json.get_str(args, "timeZone", "")))),
      r => IO.pure(String, Gc.answer(r, j => G.Google.created(j)))))

def Gt.id(+tool: String) -> Nat:
  Bool.pick(Nat, String.eq(tool, "gmail_search"), 1n,
    Bool.pick(Nat, String.eq(tool, "gmail_read"), 2n,
      Bool.pick(Nat, String.eq(tool, "gmail_send"), 3n,
        Bool.pick(Nat, String.eq(tool, "calendar_events"), 4n,
          Bool.pick(Nat, String.eq(tool, "calendar_create"), 5n, 0n)))))

def Gt.run(n: Nat, +tool: String, +args: J.Json, +tok: String, +dir: String, +e: GEnds, +now: Nat) -> IO(String):
  match n:
    case 1n:
      Gt.search(args, tok, dir, e)
    case 2n:
      Gt.read(args, tok, dir, e)
    case 3n:
      Gt.send(args, tok, dir, e)
    case 4n:
      Gt.events(args, tok, dir, e, now)
    case 5n:
      Gt.create(args, tok, dir, e)
    case _:
      IO.pure(String, "error: no Google tool named " ++ tool)

def Gs.call.k(a: GAccess, +home: String, +tool: String, +args: J.Json) -> IO(String):
  match a:
    case GErr{m}:
      IO.pure(String, m)
    case GOk{+tok}:
      do IO<String>:
        +e : GEnds <- Ge.get()
        t : U32 <- H.Clock.epoch()
        Gt.run(Gt.id(tool), tool, args, tok, Gs.dir(home), e, U32.to_nat(t))

# one MCP tool call (gmail_search, gmail_read, gmail_send, calendar_events,
# calendar_create): compact text for the agent, or "error: ...". The hub
# asks the user before gmail_send and calendar_create (G.Google.asks).
def Google.call(+home: String, +tool: String, +args: J.Json) -> IO(String):
  do IO<String>:
    a : GAccess <- Google.token(home)
    Gs.call.k(a, home, tool, args)

# the MCP tool definitions, a JSON array shaped as tools/list's
def Google.tools() -> J.Json:
  J.Json.arr(G.Google.tool_defs())
