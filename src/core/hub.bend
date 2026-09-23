import Base
import ./json.bend as J
import ./model.bend as M
import ./codec.bend as C
import ./attach.bend as AT
import ./agent.bend as AG

# The decider. Requests from clients and lines from agents come in; changes
# (persisted, folded into the read model) and effects (run by the server)
# come out. Nothing here does IO, so the server's behaviour is these defs.

# what the server must do after a step
type Out is Data:
  # to one client
  Send{client: U32, text: String}
  # to every client
  Broadcast{text: String}
  # ensure an agent process runs for a thread, then write a line to it
  AgentStart{thread: String, cwd: String, provider: String, model: String, session: String, runtime: M.RuntimeMode, interaction: M.InteractionMode}
  AgentSend{thread: String, line: String}
  AgentStop{thread: String}
  # watch a KiCad file for a client (the viewer)
  Watch{client: U32, path: String}
  # install the latest release and restart
  Upgrade{}
  KiCadInstall{}
  # run one Codex turn (a process per turn; `session` resumes)
  CodexTurn{thread: String, cwd: String, model: String, session: String, runtime: M.RuntimeMode, text: String}
  GrokTurn{thread: String, cwd: String, model: String, session: String, runtime: M.RuntimeMode, text: String}
  TurnEnded{thread: String, state: String}
  AskAnswered{id: String, answer: String}
  Git{client: U32, id: String, job: String, thread: String, cwd: String, a: String, b: String}
  TermOp{op: String, thread: String, cwd: String, data: List<&2, U32>, cols: U32, rows: U32}
  Fs{client: U32, id: String, op: String, path: String}

type Step is Data:
  Step{changes: List<&2, M.Change>, outs: List<&2, Out>}

def Step.none() -> Step:
  Step{Nil{}, Nil{}}

def Step.outs(os: List<&2, Out>) -> Step:
  Step{Nil{}, os}

# Replies
# -------

def Reply.ok(+client: U32, +id: String) -> Out:
  Send{client, J.Json.show(J.Json.obj([J.KV{"t", J.Str{"reply"}}, J.KV{"id", J.Num{id}}, J.KV{"ok", J.Flag{True{}}}]))}

def Reply.err(+client: U32, +id: String, msg: String) -> Out:
  Send{client, J.Json.show(J.Json.obj([J.KV{"t", J.Str{"reply"}}, J.KV{"id", J.Num{id}}, J.KV{"ok", J.Flag{False{}}}, J.KV{"error", J.Str{msg}}]))}

def Step.reply(+client: U32, +id: String, cs: List<&2, M.Change>) -> Step:
  Step{cs, [Reply.ok(client, id)]}

# Ids
# ---

# unique and replay-stable: the event sequence never repeats
def Hub.id(prefix: String, +now: Nat, +seq: Nat) -> String:
  prefix ++ Nat.show(now) ++ "-" ++ Nat.show(seq)

def Hub.seq(s: M.State) -> Nat:
  match s:
    case M.State{_, _, _, n, _, _, _, _, _}:
      n

def Hub.thread.k(r: Map<&2, M.Thread> & M.Thread) -> M.Thread:
  (_, t) = r
  t

# Lookups
# -------

def Hub.thread(s: M.State, +id: String) -> M.Thread:
  match s:
    case M.State{_, ts, _, _, _, _, _, _, _}:
      Hub.thread.k(Map.get(M.Thread, M.Thread.blank(id), ts, id))

def Hub.project.k(r: Map<&2, M.Project> & M.Project) -> M.Project:
  (_, p) = r
  p

def Hub.project(s: M.State, +id: String) -> M.Project:
  match s:
    case M.State{ps, _, _, _, _, _, _, _, _}:
      Hub.project.k(Map.get(M.Project, M.Project.blank(id), ps, id))

# the base name of a path, for a default project title
def Hub.base.k(parts: List<&2, String>) -> String:
  Maybe.default(&2, String, List.last(&2, String, List.filter(~String, ~(x => Bool.not(String.is_empty(x))), parts)), "project")

def Hub.base(p: String) -> String:
  Hub.base.k(String.split(p, '/'))

def Hub.project.root(p: M.Project) -> String:
  match p:
    case M.Project{_, _, root, _, _}:
      root

# the directory a thread's agent works in
def Hub.cwd(+s: M.State, t: M.Thread) -> String:
  match t:
    case M.Thread{_, +project, _, _, _, _, _, _, _, _, _, _, _, _, +worktree, _, _, _, _, _, _}:
      Bool.pick(String, String.is_empty(worktree), Hub.project.root(Hub.project(s, project)), worktree)

# Claude's stream-json input line for one user message
def Claude.user(text: String) -> String:
  J.Json.show(J.Json.obj([
    J.KV{"type", J.Str{"user"}},
    J.KV{"message", J.Json.obj([
      J.KV{"role", J.Str{"user"}},
      J.KV{"content", J.Json.arr([J.Json.obj([J.KV{"type", J.Str{"text"}}, J.KV{"text", J.Str{text}}])])}])}]))

def Claude.interrupt(+id: String) -> String:
  J.Json.show(J.Json.obj([
    J.KV{"type", J.Str{"control_request"}},
    J.KV{"request_id", J.Str{id}},
    J.KV{"request", J.Json.obj([J.KV{"subtype", J.Str{"interrupt"}}])}]))

# a user message for Claude: straight in, or, when it attaches images, by
# the server, which reads them into image content blocks first
def Claude.send(+thread: String, +cwd: String, +text: String) -> Out:
  Bool.pick(Out, List.is_empty(&2, String, AT.Att.images(text)), AgentSend{thread, Claude.user(text)},
    Git{0, "", "attach.claude", thread, cwd, text, ""})

def Hub.title.cut(long: Bool, +line: String) -> String:
  match long:
    case True{}:
      String.take(line, 57n) ++ "..."
    case False{}:
      line

def Hub.title.of(+text: String) -> String:
  +line = String.trim(Maybe.default(&2, String, List.head(&2, String, String.lines(text)), ""))
  Hub.title.cut(Nat.is_gt(String.length(line), 60n), line)

# Requests
# --------

# a thread still called "New thread" takes its first message as its title
def Hub.title.k(fresh: Bool, +thread: String, +text: String, +now: Nat, rest: List<&2, M.Change>) -> List<&2, M.Change>:
  match fresh:
    case True{}:
      M.ThreadRenamed{thread, Hub.title.of(text), now} <> rest
    case False{}:
      rest

# the effects that run one turn of a thread's agent, by provider: Claude
# keeps one process per thread fed with stream-json; Codex and Grok run a
# process per turn, resuming their session (Grok over ACP, reported in
# Codex's event shapes)
def Hub.run.k(i: Nat, +thread: String, +cwd: String, +provider: String, +model: String, +session: String, runtime: M.RuntimeMode, interaction: M.InteractionMode, +text: String) -> List<&2, Out>:
  match i:
    case 1n:
      [CodexTurn{thread, cwd, model, session, runtime, text}]
    case 2n:
      [GrokTurn{thread, cwd, model, session, runtime, text}]
    case _:
      [AgentStart{thread, cwd, provider, model, session, runtime, interaction}, Claude.send(thread, cwd, text)]

def Hub.run(t: M.Thread, +cwd: String, +text: String) -> List<&2, Out>:
  match t:
    case M.Thread{+id, _, _, _, _, _, _, _, _, _, _, _, _, _, _, +provider, model, runtime, interaction, session, _}:
      Hub.run.k(C.Codec.pos(["claude", "codex", "grok"], provider), id, cwd, provider, model, session, runtime, interaction, text)

def Hub.post.go(wait: Bool, +t: M.Thread, +cwd: String, +queued: String, +now: Nat, +thread: String, +msg: String, role: M.Role, +text: String) -> Step:
  match wait:
    case True{}:
      Step{[M.MessagePosted{thread, msg, role, text, now}, M.TurnQueued{thread, msg, text, now}], Nil{}}
    case False{}:
      Step{List.concat(&2, M.Change, [[M.MessagePosted{thread, msg, role, text, now}],
          Bool.pick(List<&2, M.Change>, String.is_empty(queued), Nil{}, [M.QueueTaken{thread, now}]),
          [M.TurnChanged{thread, M.Running{}, now}]]),
        Git{0, "", "checkpoint0", thread, cwd, "", ""} <> Hub.run(t, cwd, M.Queue.join(queued, text))}

def Step.before(cs: List<&2, M.Change>, os: List<&2, Out>, st: Step) -> Step:
  match st:
    case Step{c2, o2}:
      Step{List.append(&2, M.Change, cs, c2), List.append(&2, Out, os, o2)}

def Hub.has_msg(es: List<&2, M.Entry>, +id: String) -> Bool:
  match es:
    case Nil{}:
      False{}
    case M.Msg{i, _, _, _, _} <> t:
      Bool.or(String.eq(i, id), Hub.has_msg(t, id))
    case M.Act{_, _, _, _, _, _} <> t:
      Hub.has_msg(t, id)

def Hub.entries(s: M.State) -> List<&2, M.Entry>:
  match s:
    case M.State{_, _, es, _, _, _, _, _, _}:
      es

def Hub.thread_create(+s: M.State, +now: Nat, +client: U32, +id: String, +p: J.Json) -> Step:
  +project = J.Json.get_str(p, "project", "")
  +title = J.Json.get_str(p, "title", "New thread")
  +env = J.Json.get_str(p, "env", M.Setting.get(s, "thread.env", "local"))
  +th = Hub.id("t", now, Hub.seq(s))
  Step{[M.ThreadCreated{th, project, title,
    C.Env.of(env), "", "", J.Json.get_str(p, "provider", M.Setting.get(s, "agent.provider", "claude")),
    J.Json.get_str(p, "model", M.Setting.get(s, "agent.model", "")), now}],
    Reply.ok(client, id) <> Bool.pick(List<&2, Out>, String.eq(env, "worktree"),
      [Git{0, "", "worktree", th, Hub.project.root(Hub.project(s, project)), Hub.base(Hub.project.root(Hub.project(s, project))), ""}], Nil{})}

def Hub.has_root(ps: List<&2, M.Project>, +root: String) -> Bool:
  match ps:
    case Nil{}:
      False{}
    case M.Project{_, _, r, _, rm} <> t:
      Bool.or(Bool.and(String.eq(r, root), Bool.not(rm)), Hub.has_root(t, root))

def Hub.projects(s: M.State) -> List<&2, M.Project>:
  match s:
    case M.State{ps, _, _, _, _, _, _, _, _}:
      Map.values(&2, M.Project, ps)

def Hub.project_add.k(dup: Bool, +s: M.State, +now: Nat, +client: U32, +id: String, +p: J.Json, +root: String) -> Step:
  match dup:
    case True{}:
      Step.outs([Reply.err(client, id, "already a project: " ++ root)])
    case False{}:
      Step.reply(client, id, [M.ProjectCreated{Hub.id("p", now, Hub.seq(s)), J.Json.get_str(p, "title", Hub.base(root)), root, now}])

# a folder becomes a project once (the same root twice is refused)
def Hub.project_add(+s: M.State, +now: Nat, +client: U32, +id: String, +p: J.Json) -> Step:
  Hub.project_add.k(Hub.has_root(Hub.projects(s), J.Json.get_str(p, "path", "")), s, now, client, id, p, J.Json.get_str(p, "path", ""))

# change a thread's modes; what the request leaves out stays as it is
def Hub.modes(+s: M.State, +now: Nat, +client: U32, +id: String, +p: J.Json, t: M.Thread) -> Step:
  match t:
    case M.Thread{+th, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, mo, rt, im, _, _}:
      Step.before([M.ModesSet{th, C.Runtime.of(J.Json.get_str(p, "runtime", C.Runtime.name(rt))),
        C.Interaction.of(J.Json.get_str(p, "interaction", C.Interaction.name(im))), J.Json.get_str(p, "model", mo), now}], [Reply.ok(client, id)], Step.none())

# Answering asks
# --------------

def Ask.find(as: List<&2, M.Ask>, +id: String) -> M.Ask:
  match as:
    case Nil{}:
      M.Ask.blank(id)
    case M.Ask{+i, th, k, t, d, o, op, an} <> rest:
      Bool.pick(M.Ask, String.eq(i, id), M.Ask{i, th, k, t, d, o, op, an}, Ask.find(rest, id))

def Hub.implement.k(t: M.Thread, +now: Nat) -> List<&2, M.Change>:
  match t:
    case M.Thread{+th, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, mo, rt, _, _, _}:
      [M.ModesSet{th, rt, M.DefaultMode{}, mo, now}]

# the state the implementing turn starts from: the plan is out of the way
def Hub.impl.state(+s: M.State, +th: String, +now: Nat) -> M.State:
  M.State.replay(Hub.implement.k(Hub.thread(s, th), now), s)

# Git: worktrees, checkpoints, diffs, stacked actions
# ---------------------------------------------------
# The hub decides; the server runs git (src/server/git.bend) and reports
# back: thread.worktree and thread.note come from the server itself.

# a commit made from a thread says what the thread was about
def Hub.thread_title(t: M.Thread) -> String:
  match t:
    case M.Thread{_, _, ti, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      ti

def Hub.methods.git() -> List<&2, String>:
  ["git.diff", "git.revert", "git.act", "git.status", "thread.worktree", "thread.note", "term.open", "term.input", "term.resize"]

def Hub.git(+s: M.State, +client: U32, +id: String, +job: String, +thread: String, +a: String, +b: String) -> Step:
  Step.outs([Git{client, id, job, thread, Hub.cwd(s, Hub.thread(s, thread)), a, b}])

def Term.bytes(xs: List<&2, J.Json>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Nil{}
    case +x <> t:
      U32.from_nat(Maybe.default(&2, Nat, Nat.read(J.Json.as_raw(Some{x}, "0")), 0n)) <> Term.bytes(t)

# a thread's terminal: open (in the thread's directory), keys in, resize
def Hub.term(+s: M.State, +client: U32, +id: String, +op: String, +p: J.Json) -> Step:
  Step.outs([Reply.ok(client, id), TermOp{op, J.Json.get_str(p, "thread", ""), Hub.cwd(s, Hub.thread(s, J.Json.get_str(p, "thread", ""))),
    Term.bytes(J.Json.elems(J.Json.get_obj(p, "b"))), J.Json.get_u32(p, "cols", 80), J.Json.get_u32(p, "rows", 24)}])

# Phones
# ------

# a push token or bundle id: letters, digits and . _ : - only (APNs tokens
# are hex, FCM tokens base64url with a colon), so neither can bend a URL
# or a header
def Device.char(+c: U32) -> Bool:
  Bool.or(Bool.or(Bool.and(U32.is_ge(c, 48), U32.is_le(c, 57)), Bool.and(U32.is_ge(c, 65), U32.is_le(c, 90))),
    Bool.or(Bool.and(U32.is_ge(c, 97), U32.is_le(c, 122)), Bool.or(Bool.or(U32.is_eq(c, 46), U32.is_eq(c, 95)), Bool.or(U32.is_eq(c, 58), U32.is_eq(c, 45)))))

def Device.chars(s: String) -> Bool:
  match s:
    case SNil{}:
      True{}
    case SCon{Chr{+c}, t}:
      Bool.and(Device.char(c), Device.chars(t))

def Device.safe(+s: String) -> Bool:
  Bool.and(Bool.not(String.is_empty(s)), Bool.and(Nat.is_le(String.length(s), 512n), Device.chars(s)))

def Device.one_of(+names: List<&2, String>, +s: String) -> Bool:
  Nat.is_lt(C.Codec.pos(names, s), List.length(&2, String, names))

def Device.ok(+p: J.Json) -> Bool:
  Bool.and(Bool.and(Device.safe(J.Json.get_str(p, "token", "")), Device.safe(J.Json.get_str(p, "bundle", ""))),
    Bool.and(Bool.and(Device.one_of(["ios", "android"], J.Json.get_str(p, "platform", "")), Device.one_of(["alert", "activity", "start"], J.Json.get_str(p, "kind", ""))),
      Device.one_of(["sandbox", "production"], J.Json.get_str(p, "env", "production"))))

def Device.register.k(ok: Bool, +now: Nat, +client: U32, +id: String, +p: J.Json) -> Step:
  match ok:
    case True{}:
      Step.reply(client, id, [M.DeviceRegistered{J.Json.get_str(p, "token", ""), J.Json.get_str(p, "platform", ""), J.Json.get_str(p, "kind", ""),
        J.Json.get_str(p, "thread", ""), J.Json.get_str(p, "env", "production"), J.Json.get_str(p, "bundle", ""), now}])
    case False{}:
      Step.outs([Reply.err(client, id, "bad device")])

# a phone registers a push token (never echoed: clients get the event
# without it)
def Device.register(+now: Nat, +client: U32, +id: String, +p: J.Json) -> Step:
  Device.register.k(Device.ok(p), now, client, id, p)

# Method groups (each appended to only by its own feature area)
# ------------------------------------------------------------

# folders for the project picker (listing, creating); the server answers
def Hub.methods.fs() -> List<&2, String>:
  ["fs.list", "fs.mkdir"]

# sidebar and navigation
def Hub.methods.nav() -> List<&2, String>:
  []

# agent features (skills, effort, naming)
def Hub.methods.agent() -> List<&2, String>:
  ["thread.branch", "skills.list", "thread.effort"]

def Hub.provider_of(t: M.Thread) -> String:
  match t:
    case M.Thread{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, p, _, _, _, _, _}:
      p

def Hub.worktree(t: M.Thread) -> String:
  match t:
    case M.Thread{_, _, _, _, _, _, _, _, _, _, _, _, _, _, wt, _, _, _, _, _, _}:
      wt

# a thread's reasoning effort: kept in the settings map (effort.<thread>),
# only as a level its provider offers ("" is the provider's default)
def Hub.effort(+s: M.State, +now: Nat, +client: U32, +id: String, +thread: String, +e: String) -> Step:
  Step.reply(client, id, [M.SettingSet{AG.Effort.key(thread), AG.Effort.of(Hub.provider_of(Hub.thread(s, thread)), e), now}])

# a worktree thread's first message names its branch: the server asks a
# small model for a name while the turn runs, renames the temporary
# backplane/<hex> branch and reports it (thread.branch)
def Name.out.k(go: Bool, +thread: String, +wt: String, +branch: String, +text: String) -> List<&2, Out>:
  match go:
    case True{}:
      [Git{0, "", "name", thread, wt, branch, text}]
    case False{}:
      Nil{}

def Name.out(t: M.Thread, +text: String) -> List<&2, Out>:
  match t:
    case M.Thread{+id, _, +title, _, _, _, _, _, _, _, _, _, _, +br, +wt, _, _, _, _, _, _}:
      Name.out.k(Bool.and(Bool.and(String.eq(title, "New thread"), AG.Name.temp(br)), Bool.not(String.is_empty(wt))), id, wt, br, text)

# Commit & push and Open PR without a message: the server writes one from
# the thread's diff (the thread's title when it cannot)
def Hub.act(+s: M.State, +client: U32, +id: String, +thread: String, +action: String, +p: J.Json) -> Step:
  Bool.pick(Step, Bool.and(String.contains(action, "commit"), String.eq(J.Json.show(Maybe.default(&2, J.Json, J.Json.get(p, "message"), J.Null{})), "null")),
    Hub.git(s, client, id, "act_gen", thread, action, Hub.thread_title(Hub.thread(s, thread))),
    Hub.git(s, client, id, "act", thread, action, J.Json.get_str(p, "message", Hub.thread_title(Hub.thread(s, thread)))))

# attachments, files and the web client's panes
def Hub.methods.media() -> List<&2, String>:
  ["attach.put", "attach.file", "update.check"]

# one piece of an upload: "<index>|<1 when last>|<stored name>"
def Attach.piece(+p: J.Json) -> String:
  Nat.show(J.Json.get_nat(p, "i", 0n)) ++ "|" ++ Bool.pick(String, J.Json.get_bool(p, "last", True{}), "1", "0") ++ "|" ++
    AT.Att.stored(J.Json.get_str(p, "key", "u"), J.Json.get_str(p, "name", "file"))

# uploads are stored per thread; a thread must be named
def Attach.go(ok: Bool, +client: U32, +id: String, o: Out) -> Step:
  match ok:
    case True{}:
      Step.outs([o])
    case False{}:
      Step.outs([Reply.err(client, id, "no thread to attach to")])

# attach.put: a piece of an uploaded file (base64); attach.file: a file on
# this machine, copied in; update.check: look for a release now
def Hub.media(i: Nat, +s: M.State, +now: Nat, +client: U32, +id: String, +p: J.Json, +m: String) -> Step:
  match i:
    case 0n:
      Attach.go(Bool.not(String.is_empty(J.Json.get_str(p, "thread", ""))), client, id,
        Git{client, id, "attach.put", J.Json.get_str(p, "thread", ""), "", Attach.piece(p), J.Json.get_str(p, "data", "")})
    case 1n:
      Attach.go(Bool.not(String.is_empty(J.Json.get_str(p, "thread", ""))), client, id,
        Git{client, id, "attach.file", J.Json.get_str(p, "thread", ""), "", AT.Att.from_uri(J.Json.get_str(p, "path", "")),
          AT.Att.stored(Hub.id("a", now, Hub.seq(s)), AT.Att.base(AT.Att.from_uri(J.Json.get_str(p, "path", ""))))})
    case 2n:
      Step.outs([Git{client, id, "update.check", "", "", M.Setting.get(s, "update.channel", "stable"), ""}])
    case _:
      Step.outs([Reply.err(client, id, "unknown method")])

def Hub.agentm(i: Nat, +s: M.State, +now: Nat, +client: U32, +id: String, +p: J.Json, +m: String) -> Step:
  match i:
    case 0n:
      Step.reply(client, id, [M.WorktreeSet{J.Json.get_str(p, "thread", ""), J.Json.get_str(p, "branch", ""), Hub.worktree(Hub.thread(s, J.Json.get_str(p, "thread", ""))), now}])
    case 1n:
      Hub.git(s, client, id, "skills", J.Json.get_str(p, "thread", ""), "", "")
    case 2n:
      Hub.effort(s, now, client, id, J.Json.get_str(p, "thread", ""), J.Json.get_str(p, "effort", ""))
    case _:
      Hub.media(C.Codec.pos(Hub.methods.media(), m), s, now, client, id, p, m)

def Hub.nav(i: Nat, +s: M.State, +now: Nat, +client: U32, +id: String, +p: J.Json, +m: String) -> Step:
  match i:
    case _:
      Hub.agentm(C.Codec.pos(Hub.methods.agent(), m), s, now, client, id, p, m)

def Hub.fs(i: Nat, +s: M.State, +now: Nat, +client: U32, +id: String, +p: J.Json, +m: String) -> Step:
  match i:
    case 0n:
      Step.outs([Fs{client, id, "list", J.Json.get_str(p, "path", "")}])
    case 1n:
      Step.outs([Fs{client, id, "mkdir", J.Json.get_str(p, "path", "")}])
    case _:
      Hub.nav(C.Codec.pos(Hub.methods.nav(), m), s, now, client, id, p, m)

def Hub.more(i: Nat, +s: M.State, +now: Nat, +client: U32, +id: String, +p: J.Json, +m: String) -> Step:
  match i:
    case 0n:
      Hub.git(s, client, id, "diff", J.Json.get_str(p, "thread", ""), J.Json.as_raw(J.Json.get(p, "from"), "0"), J.Json.as_raw(J.Json.get(p, "to"), "-1"))
    case 1n:
      Hub.git(s, client, id, "revert", J.Json.get_str(p, "thread", ""), J.Json.as_raw(J.Json.get(p, "turn"), "0"), "")
    case 2n:
      Hub.act(s, client, id, J.Json.get_str(p, "thread", ""), J.Json.get_str(p, "action", "commit"), p)
    case 3n:
      Hub.git(s, client, id, "status", J.Json.get_str(p, "thread", ""), "", "")
    case 4n:
      Step.reply(client, id, [M.WorktreeSet{J.Json.get_str(p, "thread", ""), J.Json.get_str(p, "branch", ""), J.Json.get_str(p, "path", ""), now}])
    case 5n:
      Step.reply(client, id, [M.ActivityLogged{J.Json.get_str(p, "thread", ""), Hub.id("g", now, Hub.seq(s)), J.Json.get_str(p, "tone", "info"),
        J.Json.get_str(p, "kind", "git"), J.Json.get_str(p, "summary", ""), now}])
    case 6n:
      Hub.term(s, client, id, "open", p)
    case 7n:
      Hub.term(s, client, id, "input", p)
    case 8n:
      Hub.term(s, client, id, "resize", p)
    case _:
      Hub.fs(C.Codec.pos(Hub.methods.fs(), m), s, now, client, id, p, m)

def Hub.methods() -> List<&2, String>:
  ["project.add", "project.remove", "thread.create", "turn.start", "turn.interrupt",
   "thread.settle", "thread.unsettle", "thread.archive", "thread.unarchive",
   "thread.pin", "thread.unpin", "thread.rename", "thread.delete", "kicad.watch", "thread.modes", "app.update", "setting.set", "kicad.install",
   "ask.answer", "device.register", "device.drop"]

# Agent output (Claude stream-json)
# ---------------------------------

def Delta.push(thread: String, text: String) -> Out:
  Broadcast{J.Json.show(J.Json.obj([J.KV{"t", J.Str{"delta"}}, J.KV{"thread", J.Str{thread}}, J.KV{"text", J.Str{text}}]))}

def Claude.stream.k(block: Bool, text: Bool, +thread: String, s: String) -> Step:
  match block text:
    case True{} True{}:
      Step.outs([Delta.push(thread, s)])
    case _ _:
      Step.none()

def Claude.stream(+thread: String, +ev: J.Json) -> Step:
  +d = J.Json.get_obj(ev, "delta")
  Claude.stream.k(String.eq(J.Json.get_str(ev, "type", ""), "content_block_delta"),
    String.eq(J.Json.get_str(d, "type", ""), "text_delta"), thread, J.Json.get_str(d, "text", ""))

# a short line describing a tool call, from its input
def Claude.tool_summary(+name: String, +input: J.Json) -> String:
  +cmd = J.Json.get_str(input, "command", "")
  +path = J.Json.get_str(input, "file_path", J.Json.get_str(input, "path", ""))
  +pat = J.Json.get_str(input, "pattern", "")
  Bool.pick(String, Bool.not(String.is_empty(cmd)), cmd,
    Bool.pick(String, Bool.not(String.is_empty(path)), path,
      Bool.pick(String, Bool.not(String.is_empty(pat)), pat, J.Json.get_str(input, "description", name))))

def Claude.block.k(i: Nat, +thread: String, +msg: String, +n: Nat, +now: Nat, +seq: Nat, +b: J.Json) -> List<&2, M.Change>:
  match i:
    case 0n:
      [M.MessagePosted{thread, msg ++ ":" ++ Nat.show(n), M.Assistant{}, J.Json.get_str(b, "text", ""), now}]
    case 1n:
      [M.ActivityLogged{thread, J.Json.get_str(b, "id", Hub.id("a", now, seq)), "tool", J.Json.get_str(b, "name", "tool"),
        Claude.tool_summary(J.Json.get_str(b, "name", "tool"), J.Json.get_obj(b, "input")), now}]
    case _:
      Nil{}

def Claude.blocks(bs: List<&2, J.Json>, +thread: String, +msg: String, +n: Nat, +now: Nat, +seq: Nat) -> List<&2, M.Change>:
  match bs:
    case Nil{}:
      Nil{}
    case +b <> t:
      List.append(&2, M.Change,
        Claude.block.k(C.Codec.pos(["text", "tool_use"], J.Json.get_str(b, "type", "")), thread, msg, n, now, seq, b),
        Claude.blocks(t, thread, msg, 1n+n, now, seq))

def Claude.assistant(+thread: String, +now: Nat, +seq: Nat, +m: J.Json) -> Step:
  Step{Claude.blocks(J.Json.elems(J.Json.get_obj(m, "content")), thread, J.Json.get_str(m, "id", "msg"), 0n, now, seq),
    [Broadcast{J.Json.show(J.Json.obj([J.KV{"t", J.Str{"delta_end"}}, J.KV{"thread", J.Str{thread}}]))}]}

def Claude.result.k(err: Bool, +thread: String, +now: Nat, text: String) -> Step:
  match err:
    case True{}:
      Step{[M.ActivityLogged{thread, Hub.id("e", now, 0n), "error", "result", text, now}, M.TurnChanged{thread, M.Failed{}, now}], Nil{}}
    case False{}:
      Step{[M.TurnChanged{thread, M.Completed{}, now}], Nil{}}

def Claude.result(+thread: String, +now: Nat, +o: J.Json) -> Step:
  Claude.result.k(J.Json.get_bool(o, "is_error", False{}), thread, now, J.Json.get_str(o, "result", ""))

def Claude.init.same(t: M.Thread, +sid: String) -> Bool:
  match t:
    case M.Thread{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, session, _}:
      String.eq(session, sid)

def Claude.init.k(same: Bool, thread: String, sid: String, +now: Nat) -> Step:
  match same:
    case True{}:
      Step.none()
    case False{}:
      Step{[M.SessionSet{thread, sid, now}], Nil{}}

# the session id arrives in the init line; record it once
def Claude.init(+s: M.State, +thread: String, +now: Nat, +o: J.Json) -> Step:
  +sid = J.Json.get_str(o, "session_id", "")
  Claude.init.k(Claude.init.same(Hub.thread(s, thread), sid), thread, sid, now)

def Claude.line.k(i: Nat, +s: M.State, +thread: String, +now: Nat, +o: J.Json) -> Step:
  match i:
    case 0n:
      Claude.init(s, thread, now, o)
    case 1n:
      Claude.stream(thread, J.Json.get_obj(o, "event"))
    case 2n:
      Claude.assistant(thread, now, Hub.seq(s), J.Json.get_obj(o, "message"))
    case 3n:
      Claude.result(thread, now, o)
    case _:
      Step.none()

def Claude.line.parsed(m: Maybe<&2, J.Json>, +s: M.State, +thread: String, +now: Nat) -> Step:
  match m:
    case Some{+o}:
      Claude.line.k(C.Codec.pos(["system", "stream_event", "assistant", "result"], J.Json.get_str(o, "type", "")), s, thread, now, o)
    case None{}:
      Step.none()

def Hub.provider(t: M.Thread) -> String:
  match t:
    case M.Thread{_, _, _, _, _, _, _, _, _, _, _, _, _, _, _, p, _, _, _, _, _}:
      p

def Hub.running(t: M.Thread) -> Bool:
  match t:
    case M.Thread{_, _, _, _, _, M.Running{}, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      True{}
    case _:
      False{}

# a message for a thread's agent: it starts a turn, or, while a Codex or
# Grok turn runs (one turn at a time), it is stored and waits in the
# thread's queue (Claude takes input mid-turn itself)
def Hub.post(+s: M.State, +now: Nat, +thread: String, +msg: String, role: M.Role, +text: String) -> Step:
  Hub.post.go(Bool.and(Hub.running(Hub.thread(s, thread)), Bool.not(String.eq(Hub.provider(Hub.thread(s, thread)), "claude"))),
    Hub.thread(s, thread), Hub.cwd(s, Hub.thread(s, thread)), M.Queue.of(s, thread), now, thread, msg, role, text)

# a message from another thread (thread_send, a delegated task's result):
# it lands in the target's inbox and waits while the target works, for
# every provider (it never interrupts a running turn, Claude's included);
# its id names the sender, which is what the link visuals read
def Hub.inbox(+s: M.State, +now: Nat, +from: String, +to: String, role: M.Role, +text: String) -> Step:
  Hub.post.go(Hub.running(Hub.thread(s, to)), Hub.thread(s, to), Hub.cwd(s, Hub.thread(s, to)), M.Queue.of(s, to), now, to,
    M.Link.id(from, Hub.id("m", now, Hub.seq(s))), role, text)

def Hub.answer.plan(impl: Bool, +s: M.State, +now: Nat, +client: U32, +id: String, +ask: String, +answer: String, +th: String) -> Step:
  match impl:
    case True{}:
      Step.before(M.AskClosed{ask, answer, now} <> Hub.implement.k(Hub.thread(s, th), now), [Reply.ok(client, id)],
        Hub.post(Hub.impl.state(s, th, now), now, th, Hub.id("m", now, Hub.seq(s)), M.User{}, "Implement the proposed plan."))
    case False{}:
      Step{[M.AskClosed{ask, answer, now}], [Reply.ok(client, id), AskAnswered{ask, answer}]}

# the user's answer: the ask closes (once; law ask_closes_once), a parked
# agent request gets its reply, and implementing a plan leaves plan mode
# and asks the agent to carry it out
def Hub.answer.k(a: M.Ask, +s: M.State, +now: Nat, +client: U32, +id: String, +ask: String, +answer: String) -> Step:
  match a:
    case M.Ask{_, +th, +k, _, _, _, True{}, _}:
      Hub.answer.plan(Bool.and(String.eq(k, "plan"), String.eq(answer, "implement")), s, now, client, id, ask, answer, th)
    case M.Ask{_, _, _, _, _, _, False{}, _}:
      Step.outs([Reply.ok(client, id)])

def Hub.answer(+s: M.State, +now: Nat, +client: U32, +id: String, +ask: String, +answer: String) -> Step:
  Hub.answer.k(Ask.find(M.Asks.all(s), ask), s, now, client, id, ask, answer)

def Hub.turn.go(+s: M.State, +t: M.Thread, +now: Nat, +client: U32, +id: String, +thread: String, +msg: String, +text: String) -> Step:
  match t:
    case M.Thread{_, _, +title, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      Step.before(Hub.title.k(String.eq(title, "New thread"), thread, text, now, Nil{}), Reply.ok(client, id) <> Name.out(Hub.thread(s, thread), text), Hub.post(s, now, thread, msg, M.User{}, text))

def Hub.turn.k(dup: Bool, +s: M.State, +now: Nat, +client: U32, +id: String, +thread: String, +msg: String, +text: String) -> Step:
  match dup:
    case True{}:
      Step.outs([Reply.ok(client, id)])
    case False{}:
      Hub.turn.go(s, Hub.thread(s, thread), now, client, id, thread, msg, text)

def Hub.turn.m(+s: M.State, +now: Nat, +client: U32, +id: String, +thread: String, +text: String, +msg: String, named: Bool) -> Step:
  Hub.turn.k(Bool.and(named, Hub.has_msg(Hub.entries(s), msg)), s, now, client, id, thread, msg, text)

# a user message. The client names it (msg), so a message resent after a
# dropped connection is stored once; the hub names it otherwise
def Hub.turn(+s: M.State, +now: Nat, +client: U32, +id: String, +thread: String, +text: String, +msg: String) -> Step:
  Hub.turn.m(s, now, client, id, thread, text, Bool.pick(String, String.is_empty(msg), Hub.id("m", now, Hub.seq(s)), msg), Bool.not(String.is_empty(msg)))

def Hub.request.k(i: Nat, +s: M.State, +now: Nat, +client: U32, +id: String, +p: J.Json, +m: String) -> Step:
  match i:
    case 0n:
      Hub.project_add(s, now, client, id, p)
    case 1n:
      Step.reply(client, id, [M.ProjectRemoved{J.Json.get_str(p, "project", ""), now}])
    case 2n:
      Hub.thread_create(s, now, client, id, p)
    case 3n:
      Hub.turn(s, now, client, id, J.Json.get_str(p, "thread", ""), J.Json.get_str(p, "text", ""), J.Json.get_str(p, "msg", ""))
    case 4n:
      Step{[M.TurnChanged{J.Json.get_str(p, "thread", ""), M.Interrupted{}, now}], [Reply.ok(client, id), AgentSend{J.Json.get_str(p, "thread", ""), Claude.interrupt(Hub.id("i", now, Hub.seq(s)))}]}
    case 5n:
      Step.reply(client, id, [M.ThreadSettled{J.Json.get_str(p, "thread", ""), True{}, now}])
    case 6n:
      Step.reply(client, id, [M.ThreadUnsettled{J.Json.get_str(p, "thread", ""), now}])
    case 7n:
      Step{[M.ThreadArchived{J.Json.get_str(p, "thread", ""), True{}, now}], [Reply.ok(client, id), AgentStop{J.Json.get_str(p, "thread", "")}]}
    case 8n:
      Step.reply(client, id, [M.ThreadArchived{J.Json.get_str(p, "thread", ""), False{}, now}])
    case 9n:
      Step.reply(client, id, [M.ThreadPinned{J.Json.get_str(p, "thread", ""), True{}, now}])
    case 10n:
      Step.reply(client, id, [M.ThreadPinned{J.Json.get_str(p, "thread", ""), False{}, now}])
    case 11n:
      Step.reply(client, id, [M.ThreadRenamed{J.Json.get_str(p, "thread", ""), J.Json.get_str(p, "title", ""), now}])
    case 12n:
      Step{[M.ThreadDeleted{J.Json.get_str(p, "thread", ""), now}], [Reply.ok(client, id), AgentStop{J.Json.get_str(p, "thread", "")}]}
    case 13n:
      Step.outs([Reply.ok(client, id), Watch{client, J.Json.get_str(p, "path", "")}])
    case 14n:
      Hub.modes(s, now, client, id, p, Hub.thread(s, J.Json.get_str(p, "thread", "")))
    case 15n:
      Step.outs([Reply.ok(client, id), Upgrade{}])
    case 16n:
      Step.reply(client, id, [M.SettingSet{J.Json.get_str(p, "key", ""), J.Json.get_str(p, "value", ""), now}])
    case 17n:
      Step.outs([Reply.ok(client, id), KiCadInstall{}])
    case 18n:
      Hub.answer(s, now, client, id, J.Json.get_str(p, "id", ""), J.Json.get_str(p, "answer", ""))
    case 19n:
      Device.register(now, client, id, p)
    case 20n:
      Step.reply(client, id, [M.DeviceDropped{J.Json.get_str(p, "token", ""), now}])
    case _:
      Hub.more(C.Codec.pos(Hub.methods.git(), m), s, now, client, id, p, m)

# one client request {"id": n, "m": method, "p": params}
def Hub.request(+s: M.State, +now: Nat, +client: U32, +o: J.Json) -> Step:
  Hub.request.k(C.Codec.pos(Hub.methods(), J.Json.get_str(o, "m", "")), s, now, client,
    J.Json.as_raw(J.Json.get(o, "id"), "0"), J.Json.get_obj(o, "p"), J.Json.get_str(o, "m", ""))

def Hub.request_text.k(m: Maybe<&2, J.Json>, +s: M.State, +now: Nat, +client: U32) -> Step:
  match m:
    case Some{o}:
      Hub.request(s, now, client, o)
    case None{}:
      Step.outs([Reply.err(client, "0", "malformed request")])

def Hub.request_text(+s: M.State, +now: Nat, +client: U32, text: String) -> Step:
  Hub.request_text.k(J.Json.parse(text), s, now, client)

def Hub.agent_gone.k(running: Bool, +thread: String, +now: Nat, +code: U32) -> Step:
  match running:
    case True{}:
      Step{[M.ActivityLogged{thread, Hub.id("x", now, 0n), "error", "exit", "agent exited with code " ++ U32.show(code), now},
        M.TurnChanged{thread, M.Failed{}, now}], Nil{}}
    case False{}:
      Step.none()

def Hub.settle.k(auto: Bool, sh: M.Shelf, t: M.Thread, +now: Nat, rest: List<&2, M.Change>) -> List<&2, M.Change>:
  match auto sh t:
    case True{} M.Active{} M.Thread{id, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _}:
      M.ThreadSettled{id, False{}, now} <> rest
    case _ _ _:
      rest

# Settle tick
# -----------

def Hub.settle.go(ts: List<&2, M.Thread>, +now: Nat, +w: Nat) -> List<&2, M.Change>:
  match ts:
    case Nil{}:
      Nil{}
    case +t <> rest:
      Hub.settle.k(M.Settle.auto(now, w, t), M.Shelf.of(t), t, now, Hub.settle.go(rest, now, w))

# the settle window in seconds: the "settle.days" setting (1..90), else 3 days
def Hub.settle.window(+s: M.State) -> Nat:
  Nat.mul(Nat.max(1n, Nat.min(90n, Maybe.default(&2, Nat, Nat.read(M.Setting.get(s, "settle.days", "3")), 3n))), 86400n)

# every thread that should settle now, settled
def Hub.tick(+s: M.State, +now: Nat) -> Step:
  match s:
    case M.State{_, ts, _, _, _, _, _, _, _}:
      Step{Hub.settle.go(Map.values(&2, M.Thread, ts), now, Hub.settle.window(s)), Nil{}}

# Codex (codex exec --json)
# -------------------------

def Codex.item.k(i: Nat, +thread: String, +now: Nat, +seq: Nat, +it: J.Json) -> Step:
  match i:
    case 0n:
      Step{[M.MessagePosted{thread, J.Json.get_str(it, "id", Hub.id("c", now, seq)) ++ "-" ++ Nat.show(seq), M.Assistant{}, J.Json.get_str(it, "text", ""), now}], Nil{}}
    case 1n:
      Step{[M.ActivityLogged{thread, J.Json.get_str(it, "id", Hub.id("x", now, seq)) ++ "-" ++ Nat.show(seq), "tool", "shell", J.Json.get_str(it, "command", ""), now}], Nil{}}
    case 2n:
      Step{[M.ActivityLogged{thread, Hub.id("f", now, seq), "tool", "edit", J.Json.show(J.Json.get_obj(it, "changes")), now}], Nil{}}
    case _:
      Step.none()

def Codex.line.k(i: Nat, +s: M.State, +thread: String, +now: Nat, +o: J.Json) -> Step:
  match i:
    case 0n:
      Claude.init.k(Claude.init.same(Hub.thread(s, thread), J.Json.get_str(o, "thread_id", "")), thread, J.Json.get_str(o, "thread_id", ""), now)
    case 1n:
      Codex.item.k(C.Codec.pos(["agent_message", "command_execution", "file_change"], J.Json.get_str(J.Json.get_obj(o, "item"), "type", "")), thread, now, Hub.seq(s), J.Json.get_obj(o, "item"))
    case 2n:
      Step{[M.TurnChanged{thread, M.Completed{}, now}], Nil{}}
    case 4n:
      Step.outs([Delta.push(thread, J.Json.get_str(o, "text", ""))])
    case 3n:
      Step{[M.ActivityLogged{thread, Hub.id("e", now, Hub.seq(s)), "error", Hub.provider(Hub.thread(s, thread)), J.Json.get_str(J.Json.get_obj(o, "error"), "message", J.Json.get_str(o, "message", "turn failed")), now}, M.TurnChanged{thread, M.Failed{}, now}], Nil{}}
    case _:
      Step.none()

def Codex.line.parsed(m: Maybe<&2, J.Json>, +s: M.State, +thread: String, +now: Nat) -> Step:
  match m:
    case Some{+o}:
      Codex.line.k(C.Codec.pos(["thread.started", "item.completed", "turn.completed", "turn.failed", "item.delta"], J.Json.get_str(o, "type", "")), s, thread, now, o)
    case None{}:
      Step.none()

def Hub.agent_line.k(codex: Bool, +s: M.State, +now: Nat, +thread: String, line: String) -> Step:
  match codex:
    case True{}:
      Codex.line.parsed(J.Json.parse(line), s, thread, now)
    case False{}:
      Claude.line.parsed(J.Json.parse(line), s, thread, now)

# Queued turns
# ------------

def Queue.ended.one(c: M.Change, +thread: String) -> Bool:
  match c:
    case M.TurnChanged{th, M.Completed{}, _}:
      String.eq(th, thread)
    case M.TurnChanged{th, M.Failed{}, _}:
      String.eq(th, thread)
    case _:
      False{}

# whether these changes end the thread's turn (an interrupt keeps the
# queue: it goes with the next message)
def Queue.ended(cs: List<&2, M.Change>, +thread: String) -> Bool:
  match cs:
    case Nil{}:
      False{}
    case c <> t:
      Bool.or(Queue.ended.one(c, thread), Queue.ended(t, thread))

def Queue.drain.k(go: Bool, st: Step, +t: M.Thread, cwd: String, +queued: String, +now: Nat, +thread: String) -> Step:
  match go st:
    case True{} Step{cs, os}:
      Step{List.append(&2, M.Change, cs, [M.QueueTaken{thread, now}, M.TurnChanged{thread, M.Running{}, now}]), List.append(&2, Out, os, Hub.run(t, cwd, queued))}
    case False{} _:
      st

def Queue.changes(st: Step) -> List<&2, M.Change>:
  match st:
    case Step{cs, _}:
      cs

# the turn ended with messages waiting: start the next turn with them
def Ended.state(cs: List<&2, M.Change>, +thread: String) -> String:
  match cs:
    case Nil{}:
      ""
    case M.TurnChanged{+th, M.Completed{}, _} <> t:
      Bool.pick(String, String.eq(th, thread), "completed", Ended.state(t, thread))
    case M.TurnChanged{+th, M.Failed{}, _} <> t:
      Bool.pick(String, String.eq(th, thread), "failed", Ended.state(t, thread))
    case _ <> t:
      Ended.state(t, thread)

def Ended.out.k(none: Bool, +state: String, +thread: String, +cwd: String, st: Step) -> Step:
  match none st:
    case True{} _:
      st
    case False{} Step{cs, os}:
      Step{cs, List.append(&2, Out, os, [TurnEnded{thread, state}, Git{0, "", "checkpoint", thread, cwd, "", ""}])}

def Ended.out.s(+state: String, +thread: String, +cwd: String, st: Step) -> Step:
  Ended.out.k(String.is_empty(state), state, thread, cwd, st)

# a turn that ends tells the server (phone notifications hang off this)
def Ended.out(+s: M.State, +thread: String, +st: Step) -> Step:
  Ended.out.s(Ended.state(Queue.changes(st), thread), thread, Hub.cwd(s, Hub.thread(s, thread)), st)

def Queue.drain(+s: M.State, +now: Nat, +thread: String, +st: Step) -> Step:
  Queue.drain.k(Bool.and(Queue.ended(Queue.changes(st), thread), Bool.not(String.is_empty(M.Queue.of(s, thread)))), st,
    Hub.thread(s, thread), Hub.cwd(s, Hub.thread(s, thread)), M.Queue.of(s, thread), now, thread)

# Delegated tasks finishing
# -------------------------

def Task.child.hit(ts: List<&2, M.Task>, +child: String) -> Bool:
  match ts:
    case M.Task{_, _, c, _, _, _, _, _, _} <> _:
      String.eq(c, child)
    case Nil{}:
      False{}

def Task.child.go(ts: List<&2, M.Task>, hit: Bool, +child: String) -> Maybe<&2, M.Task>:
  match ts hit:
    case t <> _ True{}:
      Some{t}
    case _ <> +rest False{}:
      Task.child.go(rest, Task.child.hit(rest, child), child)
    case Nil{} _:
      None{}

def Task.of_child.k(+ts: List<&2, M.Task>, +child: String) -> Maybe<&2, M.Task>:
  Task.child.go(ts, Task.child.hit(ts, child), child)

# the task a child thread is working on, if any
def Task.of_child(s: M.State, +child: String) -> Maybe<&2, M.Task>:
  match s:
    case M.State{_, _, _, _, tk, _, _, _, _}:
      Task.of_child.k(Map.values(&2, M.Task, tk), child)

def Task.depth.k(m: Maybe<&2, M.Task>) -> Nat:
  match m:
    case Some{M.Task{_, _, _, d, _, _, _, _, _}}:
      d
    case None{}:
      0n

# the depth of a thread: 0 at the top, its task's depth for a child
def Task.depth(+s: M.State, +thread: String) -> Nat:
  Task.depth.k(Task.of_child(s, thread))

# the newest assistant message of a thread (a child's result)
def Task.last.k(same: Bool, e: M.Entry, rest: String) -> String:
  match same e:
    case True{} M.Msg{_, _, M.Assistant{}, text, _}:
      text
    case _ _:
      rest

def Task.last.hit(es: List<&2, M.Entry>, +th: String) -> Bool:
  match es:
    case M.Msg{_, t, M.Assistant{}, _, _} <> _:
      String.eq(t, th)
    case _:
      False{}

def Task.last.go(es: List<&2, M.Entry>, hit: Bool, +th: String) -> String:
  match es hit:
    case M.Msg{_, _, _, text, _} <> _ True{}:
      text
    case _ <> +t False{}:
      Task.last.go(t, Task.last.hit(t, th), th)
    case _ _:
      ""

def Task.last(s: M.State, +th: String) -> String:
  match s:
    case M.State{_, _, +es, _, _, _, _, _, _}:
      Task.last.go(es, Task.last.hit(es, th), th)

# the turn outcome a step reports for a thread, if it ended one
type Ended is Data:
  NotEnded{}
  EndedOk{}
  EndedBad{}

def Task.ended(cs: List<&2, M.Change>) -> Ended:
  match cs:
    case Nil{}:
      NotEnded{}
    case M.TurnChanged{_, M.Completed{}, _} <> _:
      EndedOk{}
    case M.TurnChanged{_, M.Failed{}, _} <> _:
      EndedBad{}
    case M.TurnChanged{_, M.Interrupted{}, _} <> _:
      EndedBad{}
    case _ <> t:
      Task.ended(t)

def Task.state_of(e: Ended) -> M.TaskState:
  match e:
    case EndedOk{}:
      M.TaskDone{}
    case _:
      M.TaskFailed{}

def Task.word(e: Ended) -> String:
  match e:
    case EndedOk{}:
      "finished"
    case _:
      "failed"

def Task.note(+id: String, +provider: String, +model: String, +word: String, +summary: String) -> String:
  "[Backplane] Delegated task " ++ id ++ " (" ++ provider ++ Bool.pick(String, String.is_empty(model), "", "/" ++ model) ++ ") " ++ word ++ ":\n\n" ++ summary

def Task.finish.go(deliver: Bool, +s: M.State, +now: Nat, +id: String, +thread: String, +parent: String, +provider: String, +model: String, +word: String, st: M.TaskState, +summary: String, cs: List<&2, M.Change>, os: List<&2, Out>) -> Step:
  match deliver:
    case True{}:
      Step.before(List.append(&2, M.Change, cs, [M.TaskStateSet{id, st, summary, now}, M.TaskDelivered{id, now}]), os,
        Hub.inbox(s, now, thread, parent, M.System{}, Task.note(id, provider, model, word, summary)))
    case False{}:
      Step{List.append(&2, M.Change, cs, [M.TaskStateSet{id, st, summary, now}]), os}

def Task.finish.k(e: Ended, m: Maybe<&2, M.Task>, +s: M.State, +now: Nat, +thread: String, cs: List<&2, M.Change>, os: List<&2, Out>) -> Step:
  match e m:
    case NotEnded{} _:
      Step{cs, os}
    case _ None{}:
      Step{cs, os}
    case +ended Some{M.Task{+id, +parent, _, _, +cur, _, +dl, +provider, +model}}:
      Task.finish.go(M.Task.pending(M.Task{id, parent, thread, 0n, M.TaskState.next(cur, Task.state_of(ended)), "", dl, provider, model}),
        s, now, id, thread, parent, provider, model, Task.word(ended), Task.state_of(ended), Task.last(s, thread), cs, os)

# when a child thread's turn ends, its task ends and the result goes to the
# parent once (the pending check makes delivery exactly-once)
def Task.finish(+s: M.State, +now: Nat, +thread: String, st: Step) -> Step:
  match st:
    case Step{+cs, os}:
      Task.finish.k(Task.ended(cs), Task.of_child(s, thread), s, now, thread, cs, os)

# one line of an agent's stdout
def Hub.agent_line(+s: M.State, +now: Nat, +thread: String, line: String) -> Step:
  Task.finish(s, now, thread, Queue.drain(s, now, thread, Ended.out(s, thread, Hub.agent_line.k(Bool.not(String.eq(Hub.provider(Hub.thread(s, thread)), "claude")), s, now, thread, line))))

# an agent process ended; a turn still running ends with it
def Hub.agent_gone(+s: M.State, +now: Nat, +thread: String, +code: U32) -> Step:
  Task.finish(s, now, thread, Queue.drain(s, now, thread, Ended.out(s, thread, Hub.agent_gone.k(Hub.running(Hub.thread(s, thread)), thread, now, code))))

def Step.outs_of(st: Step) -> List<&2, Out>:
  match st:
    case Step{_, os}:
      os
