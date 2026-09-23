import Base
import ./json.bend as J
import ./model.bend as M

# Changes as JSON: the event log on disk and the change stream to clients
# share this codec, so the browser folds exactly what the server stored.
# An encoded Change is {"$": "<Constructor>", ...fields}. Decoding is total:
# unknown tags answer None (a newer server's log is skipped, not misread).

def Codec.nat(n: Nat) -> J.Json:
  J.Num{Nat.show(n)}

def Codec.str(s: String) -> J.Json:
  J.Str{s}

def Codec.bool(b: Bool) -> J.Json:
  J.Flag{b}

def Codec.index.hit(names: List<&2, String>, +s: String) -> Bool:
  match names:
    case n <> _:
      String.eq(n, s)
    case Nil{}:
      False{}

def Codec.index.go(names: List<&2, String>, hit: Bool, +i: Nat, +s: String) -> Nat:
  match names hit:
    case _ <> _ True{}:
      i
    case _ <> +t False{}:
      Codec.index.go(t, Codec.index.hit(t, s), 1n+i, s)
    case Nil{} _:
      i

def Codec.pos(+names: List<&2, String>, +s: String) -> Nat:
  Codec.index.go(names, Codec.index.hit(names, s), 0n, s)

# Enums
# -----

def Role.name(r: M.Role) -> String:
  match r:
    case M.User{}:
      "user"
    case M.Assistant{}:
      "assistant"
    case M.System{}:
      "system"

def Role.of.k(i: Nat) -> M.Role:
  match i:
    case 0n:
      M.User{}
    case 1n:
      M.Assistant{}
    case _:
      M.System{}

def Role.of(+s: String) -> M.Role:
  Role.of.k(Codec.pos(["user", "assistant", "system"], s))

def Turn.name(t: M.TurnState) -> String:
  match t:
    case M.Idle{}:
      "idle"
    case M.Running{}:
      "running"
    case M.Completed{}:
      "completed"
    case M.Interrupted{}:
      "interrupted"
    case M.Failed{}:
      "failed"

def Turn.of.k(i: Nat) -> M.TurnState:
  match i:
    case 1n:
      M.Running{}
    case 2n:
      M.Completed{}
    case 3n:
      M.Interrupted{}
    case 4n:
      M.Failed{}
    case _:
      M.Idle{}

def Turn.of(+s: String) -> M.TurnState:
  Turn.of.k(Codec.pos(["idle", "running", "completed", "interrupted", "failed"], s))

def Env.name(e: M.EnvMode) -> String:
  match e:
    case M.Local{}:
      "local"
    case M.Worktree{}:
      "worktree"

def Env.of(+s: String) -> M.EnvMode:
  Bool.pick(M.EnvMode, String.eq(s, "worktree"), M.Worktree{}, M.Local{})

def Runtime.name(r: M.RuntimeMode) -> String:
  match r:
    case M.Supervised{}:
      "approval-required"
    case M.AcceptEdits{}:
      "auto-accept-edits"
    case M.AutoMode{}:
      "auto"
    case M.FullAccess{}:
      "full-access"

def Runtime.of.k(i: Nat) -> M.RuntimeMode:
  match i:
    case 0n:
      M.Supervised{}
    case 1n:
      M.AcceptEdits{}
    case 2n:
      M.AutoMode{}
    case _:
      M.FullAccess{}

def Runtime.of(+s: String) -> M.RuntimeMode:
  Runtime.of.k(Codec.pos(["approval-required", "auto-accept-edits", "auto", "full-access"], s))

def Interaction.name(i: M.InteractionMode) -> String:
  match i:
    case M.DefaultMode{}:
      "default"
    case M.PlanMode{}:
      "plan"

def Interaction.of(+s: String) -> M.InteractionMode:
  Bool.pick(M.InteractionMode, String.eq(s, "plan"), M.PlanMode{}, M.DefaultMode{})

def TaskSt.name(t: M.TaskState) -> String:
  match t:
    case M.TaskQueued{}:
      "queued"
    case M.TaskRunning{}:
      "running"
    case M.TaskDone{}:
      "done"
    case M.TaskFailed{}:
      "failed"
    case M.TaskCancelled{}:
      "cancelled"

def TaskSt.of.k(i: Nat) -> M.TaskState:
  match i:
    case 0n:
      M.TaskQueued{}
    case 1n:
      M.TaskRunning{}
    case 2n:
      M.TaskDone{}
    case 3n:
      M.TaskFailed{}
    case _:
      M.TaskCancelled{}

def TaskSt.of(+s: String) -> M.TaskState:
  TaskSt.of.k(Codec.pos(["queued", "running", "done", "failed", "cancelled"], s))

# Changes
# -------

def Change.obj(tag: String, kvs: List<&2, J.KV>) -> J.Json:
  J.Json.obj(J.KV{"$", J.Str{tag}} <> kvs)

def Change.encode(c: M.Change) -> J.Json:
  match c:
    case M.ProjectCreated{id, title, root, at}:
      Change.obj("ProjectCreated", [J.KV{"id", J.Str{id}}, J.KV{"title", J.Str{title}}, J.KV{"root", J.Str{root}}, J.KV{"at", Codec.nat(at)}])
    case M.ProjectRemoved{id, at}:
      Change.obj("ProjectRemoved", [J.KV{"id", J.Str{id}}, J.KV{"at", Codec.nat(at)}])
    case M.ThreadCreated{id, project, title, env, branch, worktree, provider, model, at}:
      Change.obj("ThreadCreated", [J.KV{"id", J.Str{id}}, J.KV{"project", J.Str{project}}, J.KV{"title", J.Str{title}}, J.KV{"env", J.Str{Env.name(env)}}, J.KV{"branch", J.Str{branch}}, J.KV{"worktree", J.Str{worktree}}, J.KV{"provider", J.Str{provider}}, J.KV{"model", J.Str{model}}, J.KV{"at", Codec.nat(at)}])
    case M.ThreadRenamed{id, title, at}:
      Change.obj("ThreadRenamed", [J.KV{"id", J.Str{id}}, J.KV{"title", J.Str{title}}, J.KV{"at", Codec.nat(at)}])
    case M.MessagePosted{thread, msg, role, text, at}:
      Change.obj("MessagePosted", [J.KV{"thread", J.Str{thread}}, J.KV{"msg", J.Str{msg}}, J.KV{"role", J.Str{Role.name(role)}}, J.KV{"text", J.Str{text}}, J.KV{"at", Codec.nat(at)}])
    case M.TurnChanged{thread, state, at}:
      Change.obj("TurnChanged", [J.KV{"thread", J.Str{thread}}, J.KV{"state", J.Str{Turn.name(state)}}, J.KV{"at", Codec.nat(at)}])
    case M.PendingChanged{thread, count, at}:
      Change.obj("PendingChanged", [J.KV{"thread", J.Str{thread}}, J.KV{"count", Codec.nat(count)}, J.KV{"at", Codec.nat(at)}])
    case M.ActivityLogged{thread, act, tone, kind, summary, at}:
      Change.obj("ActivityLogged", [J.KV{"thread", J.Str{thread}}, J.KV{"act", J.Str{act}}, J.KV{"tone", J.Str{tone}}, J.KV{"kind", J.Str{kind}}, J.KV{"summary", J.Str{summary}}, J.KV{"at", Codec.nat(at)}])
    case M.ThreadSettled{id, manual, at}:
      Change.obj("ThreadSettled", [J.KV{"id", J.Str{id}}, J.KV{"manual", J.Flag{manual}}, J.KV{"at", Codec.nat(at)}])
    case M.ThreadUnsettled{id, at}:
      Change.obj("ThreadUnsettled", [J.KV{"id", J.Str{id}}, J.KV{"at", Codec.nat(at)}])
    case M.ThreadArchived{id, archived, at}:
      Change.obj("ThreadArchived", [J.KV{"id", J.Str{id}}, J.KV{"archived", J.Flag{archived}}, J.KV{"at", Codec.nat(at)}])
    case M.ThreadPinned{id, pinned, at}:
      Change.obj("ThreadPinned", [J.KV{"id", J.Str{id}}, J.KV{"pinned", J.Flag{pinned}}, J.KV{"at", Codec.nat(at)}])
    case M.ThreadDeleted{id, at}:
      Change.obj("ThreadDeleted", [J.KV{"id", J.Str{id}}, J.KV{"at", Codec.nat(at)}])
    case M.WorktreeSet{id, branch, worktree, at}:
      Change.obj("WorktreeSet", [J.KV{"id", J.Str{id}}, J.KV{"branch", J.Str{branch}}, J.KV{"worktree", J.Str{worktree}}, J.KV{"at", Codec.nat(at)}])
    case M.SessionSet{id, session, at}:
      Change.obj("SessionSet", [J.KV{"id", J.Str{id}}, J.KV{"session", J.Str{session}}, J.KV{"at", Codec.nat(at)}])
    case M.ModesSet{id, runtime, interaction, model, at}:
      Change.obj("ModesSet", [J.KV{"id", J.Str{id}}, J.KV{"runtime", J.Str{Runtime.name(runtime)}}, J.KV{"interaction", J.Str{Interaction.name(interaction)}}, J.KV{"model", J.Str{model}}, J.KV{"at", Codec.nat(at)}])
    case M.TaskDelegated{task, parent, child, depth, provider, model, at}:
      Change.obj("TaskDelegated", [J.KV{"task", J.Str{task}}, J.KV{"parent", J.Str{parent}}, J.KV{"child", J.Str{child}}, J.KV{"depth", Codec.nat(depth)}, J.KV{"provider", J.Str{provider}}, J.KV{"model", J.Str{model}}, J.KV{"at", Codec.nat(at)}])
    case M.TaskStateSet{task, state, summary, at}:
      Change.obj("TaskStateSet", [J.KV{"task", J.Str{task}}, J.KV{"state", J.Str{TaskSt.name(state)}}, J.KV{"summary", J.Str{summary}}, J.KV{"at", Codec.nat(at)}])
    case M.TaskDelivered{task, at}:
      Change.obj("TaskDelivered", [J.KV{"task", J.Str{task}}, J.KV{"at", Codec.nat(at)}])
    case M.SettingSet{key, value, at}:
      Change.obj("SettingSet", [J.KV{"key", J.Str{key}}, J.KV{"value", J.Str{value}}, J.KV{"at", Codec.nat(at)}])
    case M.TurnQueued{thread, msg, text, at}:
      Change.obj("TurnQueued", [J.KV{"thread", J.Str{thread}}, J.KV{"msg", J.Str{msg}}, J.KV{"text", J.Str{text}}, J.KV{"at", Codec.nat(at)}])
    case M.QueueTaken{thread, at}:
      Change.obj("QueueTaken", [J.KV{"thread", J.Str{thread}}, J.KV{"at", Codec.nat(at)}])

def Change.tags() -> List<&2, String>:
  ["ProjectCreated", "ProjectRemoved", "ThreadCreated", "ThreadRenamed", "MessagePosted", "TurnChanged", "PendingChanged", "ActivityLogged", "ThreadSettled", "ThreadUnsettled", "ThreadArchived", "ThreadPinned", "ThreadDeleted", "WorktreeSet", "SessionSet", "ModesSet", "TaskDelegated", "TaskStateSet", "TaskDelivered", "SettingSet", "TurnQueued", "QueueTaken"]

def Change.decode.k(i: Nat, +o: J.Json) -> Maybe<&2, M.Change>:
  match i:
    case 0n:
      Some{M.ProjectCreated{J.Json.get_str(o, "id", ""), J.Json.get_str(o, "title", ""), J.Json.get_str(o, "root", ""), J.Json.get_nat(o, "at", 0n)}}
    case 1n:
      Some{M.ProjectRemoved{J.Json.get_str(o, "id", ""), J.Json.get_nat(o, "at", 0n)}}
    case 2n:
      Some{M.ThreadCreated{J.Json.get_str(o, "id", ""), J.Json.get_str(o, "project", ""), J.Json.get_str(o, "title", ""), Env.of(J.Json.get_str(o, "env", "")), J.Json.get_str(o, "branch", ""), J.Json.get_str(o, "worktree", ""), J.Json.get_str(o, "provider", ""), J.Json.get_str(o, "model", ""), J.Json.get_nat(o, "at", 0n)}}
    case 3n:
      Some{M.ThreadRenamed{J.Json.get_str(o, "id", ""), J.Json.get_str(o, "title", ""), J.Json.get_nat(o, "at", 0n)}}
    case 4n:
      Some{M.MessagePosted{J.Json.get_str(o, "thread", ""), J.Json.get_str(o, "msg", ""), Role.of(J.Json.get_str(o, "role", "")), J.Json.get_str(o, "text", ""), J.Json.get_nat(o, "at", 0n)}}
    case 5n:
      Some{M.TurnChanged{J.Json.get_str(o, "thread", ""), Turn.of(J.Json.get_str(o, "state", "")), J.Json.get_nat(o, "at", 0n)}}
    case 6n:
      Some{M.PendingChanged{J.Json.get_str(o, "thread", ""), J.Json.get_nat(o, "count", 0n), J.Json.get_nat(o, "at", 0n)}}
    case 7n:
      Some{M.ActivityLogged{J.Json.get_str(o, "thread", ""), J.Json.get_str(o, "act", ""), J.Json.get_str(o, "tone", ""), J.Json.get_str(o, "kind", ""), J.Json.get_str(o, "summary", ""), J.Json.get_nat(o, "at", 0n)}}
    case 8n:
      Some{M.ThreadSettled{J.Json.get_str(o, "id", ""), J.Json.get_bool(o, "manual", False{}), J.Json.get_nat(o, "at", 0n)}}
    case 9n:
      Some{M.ThreadUnsettled{J.Json.get_str(o, "id", ""), J.Json.get_nat(o, "at", 0n)}}
    case 10n:
      Some{M.ThreadArchived{J.Json.get_str(o, "id", ""), J.Json.get_bool(o, "archived", False{}), J.Json.get_nat(o, "at", 0n)}}
    case 11n:
      Some{M.ThreadPinned{J.Json.get_str(o, "id", ""), J.Json.get_bool(o, "pinned", False{}), J.Json.get_nat(o, "at", 0n)}}
    case 12n:
      Some{M.ThreadDeleted{J.Json.get_str(o, "id", ""), J.Json.get_nat(o, "at", 0n)}}
    case 13n:
      Some{M.WorktreeSet{J.Json.get_str(o, "id", ""), J.Json.get_str(o, "branch", ""), J.Json.get_str(o, "worktree", ""), J.Json.get_nat(o, "at", 0n)}}
    case 14n:
      Some{M.SessionSet{J.Json.get_str(o, "id", ""), J.Json.get_str(o, "session", ""), J.Json.get_nat(o, "at", 0n)}}
    case 15n:
      Some{M.ModesSet{J.Json.get_str(o, "id", ""), Runtime.of(J.Json.get_str(o, "runtime", "")), Interaction.of(J.Json.get_str(o, "interaction", "")), J.Json.get_str(o, "model", ""), J.Json.get_nat(o, "at", 0n)}}
    case 16n:
      Some{M.TaskDelegated{J.Json.get_str(o, "task", ""), J.Json.get_str(o, "parent", ""), J.Json.get_str(o, "child", ""), J.Json.get_nat(o, "depth", 0n), J.Json.get_str(o, "provider", ""), J.Json.get_str(o, "model", ""), J.Json.get_nat(o, "at", 0n)}}
    case 17n:
      Some{M.TaskStateSet{J.Json.get_str(o, "task", ""), TaskSt.of(J.Json.get_str(o, "state", "")), J.Json.get_str(o, "summary", ""), J.Json.get_nat(o, "at", 0n)}}
    case 18n:
      Some{M.TaskDelivered{J.Json.get_str(o, "task", ""), J.Json.get_nat(o, "at", 0n)}}
    case 19n:
      Some{M.SettingSet{J.Json.get_str(o, "key", ""), J.Json.get_str(o, "value", ""), J.Json.get_nat(o, "at", 0n)}}
    case 20n:
      Some{M.TurnQueued{J.Json.get_str(o, "thread", ""), J.Json.get_str(o, "msg", ""), J.Json.get_str(o, "text", ""), J.Json.get_nat(o, "at", 0n)}}
    case 21n:
      Some{M.QueueTaken{J.Json.get_str(o, "thread", ""), J.Json.get_nat(o, "at", 0n)}}
    case _:
      None{}

# a Change from its JSON, or None for an unknown tag
def Change.decode(+o: J.Json) -> Maybe<&2, M.Change>:
  Change.decode.k(Codec.pos(Change.tags(), J.Json.get_str(o, "$", "")), o)
